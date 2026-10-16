//! Model-visible field rules and insertion catalogues projected from the exact
//! selected schema and native field metadata. This grants no evidence authority.
const std = @import("std");
const schema = @import("model_result_schema.zig");
const fields = @import("model_text_field.zig");
const policy = @import("text_field_policy.zig");
const strict = @import("strict_json.zig");
pub const Error = fields.Error || strict.Error || error{InvalidModelFieldPresentation};
pub const BodyStep = union(enum) { property: []const u8, index: u32 };
/// A native producer identifies catalogue data useful to a field's declared
/// reference role. Exact catalogues support native recognition; they never add
/// model insertion alternatives. Paths address input data, never capabilities.
pub const Omission = struct { requires: policy.Insertion, path: []const BodyStep };

pub fn valid(omissions: []const Omission) bool {
    if (omissions.len > schema.max_nodes) return false;
    for (omissions, 0..) |omission, index| {
        if (omission.path.len == 0 or omission.path.len > schema.max_depth * 2) return false;
        for (omission.path) |step| if (step == .property and (step.property.len == 0 or !std.unicode.utf8ValidateSlice(step.property))) return false;
        for (omissions[0..index]) |prior| if (samePath(prior.path, omission.path)) return false;
    }
    return true;
}

fn samePath(left: []const BodyStep, right: []const BodyStep) bool {
    if (left.len != right.len) return false;
    for (left, right) |l, r| {
        if (std.meta.activeTag(l) != std.meta.activeTag(r)) return false;
        switch (l) {
            .property => |name| if (!std.mem.eql(u8, name, r.property)) return false,
            .index => |index| if (index != r.index) return false,
        }
    }
    return true;
}

pub fn clone(a: std.mem.Allocator, omissions: []const Omission) std.mem.Allocator.Error![]const Omission {
    return prefixed(a, omissions, &.{});
}

/// The caller's arena owns these descriptors and their property names.
pub fn prefixed(a: std.mem.Allocator, omissions: []const Omission, prefix: []const BodyStep) std.mem.Allocator.Error![]const Omission {
    const result = try a.alloc(Omission, omissions.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |entry| {
            for (entry.path) |step| if (step == .property) a.free(step.property);
            a.free(entry.path);
        }
        a.free(result);
    }
    for (omissions, result) |entry, *destination| {
        const path = try a.alloc(BodyStep, prefix.len + entry.path.len);
        var copied: usize = 0;
        errdefer {
            for (path[0..copied]) |step| if (step == .property) a.free(step.property);
            a.free(path);
        }
        for (path, 0..) |*step, index| {
            const source = if (index < prefix.len) prefix[index] else entry.path[index - prefix.len];
            step.* = switch (source) {
                .property => |name| .{ .property = try a.dupe(u8, name) },
                .index => |ordinal| .{ .index = ordinal },
            };
            copied += 1;
        }
        destination.* = .{ .requires = entry.requires, .path = path };
        initialized += 1;
    }
    return result;
}

const Rule = struct { field: []const u8, instruction: []const u8 };
const InsertionFields = struct { passive: []const []const u8, source: []const []const u8 };

/// Project once from the immutable native packet for this assignment. Array
/// omission paths refer to original indices; corrections reuse the projection.
pub fn project(a: std.mem.Allocator, body: []const u8, selected: *const schema.Node, bindings: []const fields.Binding, omissions: []const Omission) Error![]const u8 {
    if (!valid(omissions)) return error.InvalidModelFieldPresentation;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const active = try fields.activeBindings(scratch, selected, bindings);
    var allowed: std.EnumSet(policy.Insertion) = .initEmpty();
    var rules: std.ArrayList(Rule) = .empty;
    var passive: std.ArrayList([]const u8) = .empty;
    var source: std.ArrayList([]const u8) = .empty;
    for (active) |binding| {
        const path = try fieldPath(scratch, binding.path);
        try rules.append(scratch, .{ .field = path, .instruction = policy.selectedGuidance(binding.field, binding.insertions).instruction });
        if (policy.permits(binding.field, .exact_copy)) allowed.insert(.exact_copy);
        inline for (std.meta.tags(policy.Insertion)) |kind| if (binding.insertions.contains(kind)) {
            allowed.insert(kind);
            try switch (kind) {
                .exact_copy => return error.InvalidModelFieldPresentation,
                .passive => passive.append(scratch, path),
                .source => source.append(scratch, path),
            };
        };
    }
    var parsed = try strict.parse(scratch, body, .{ .maximum_depth = schema.max_json_depth }, false, null);
    if (parsed.value != .object) return error.InvalidModelFieldPresentation;
    var path: std.ArrayList(BodyStep) = .empty;
    try omit(scratch, &parsed.value, &path, omissions, allowed);
    if (rules.items.len != 0) {
        const guidance = try std.json.Stringify.valueAlloc(scratch, rules.items, .{});
        const insertion_fields: InsertionFields = .{ .passive = passive.items, .source = source.items };
        const choices = try std.json.Stringify.valueAlloc(scratch, insertion_fields, .{});
        try parsed.value.object.put(scratch, "field_rules", (try strict.parse(scratch, guidance, .{ .maximum_depth = schema.max_json_depth }, false, null)).value);
        try parsed.value.object.put(scratch, "insertion_fields", (try strict.parse(scratch, choices, .{ .maximum_depth = schema.max_json_depth }, false, null)).value);
    } else {
        _ = parsed.value.object.swapRemove("field_rules");
        _ = parsed.value.object.swapRemove("insertion_fields");
    }
    return std.json.Stringify.valueAlloc(a, parsed.value, .{});
}

fn omit(a: std.mem.Allocator, value: *std.json.Value, path: *std.ArrayList(BodyStep), omissions: []const Omission, allowed: std.EnumSet(policy.Insertion)) Error!void {
    switch (value.*) {
        .object => |*object| {
            var index: usize = 0;
            while (index < object.count()) {
                try path.append(a, .{ .property = object.keys()[index] });
                defer _ = path.pop();
                if (removed(path.items, omissions, allowed)) {
                    object.orderedRemoveAt(index);
                } else {
                    try omit(a, &object.values()[index], path, omissions, allowed);
                    index += 1;
                }
            }
        },
        .array => |*array| {
            var kept: usize = 0;
            for (array.items, 0..) |*item, index| {
                try path.append(a, .{ .index = std.math.cast(u32, index) orelse return error.InvalidModelFieldPresentation });
                defer _ = path.pop();
                if (removed(path.items, omissions, allowed)) continue;
                try omit(a, item, path, omissions, allowed);
                array.items[kept] = item.*;
                kept += 1;
            }
            array.shrinkRetainingCapacity(kept);
        },
        else => {},
    }
}

fn removed(path: []const BodyStep, omissions: []const Omission, allowed: std.EnumSet(policy.Insertion)) bool {
    for (omissions) |entry| if (!allowed.contains(entry.requires) and samePath(path, entry.path)) return true;
    return false;
}

fn fieldPath(a: std.mem.Allocator, path: []const fields.Step) std.mem.Allocator.Error![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(a);
    for (path) |step| switch (step) {
        .property, .variant => |name| {
            if (bytes.items.len != 0) try bytes.append(a, '.');
            try bytes.appendSlice(a, name);
        },
        .items => try bytes.appendSlice(a, "[]"),
    };
    if (bytes.items.len == 0) try bytes.appendSlice(a, "value");
    return bytes.toOwnedSlice(a);
}

test "selected field rules remove only native-declared unusable catalogues and original array members" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prose: schema.Node = .{ .string = .{ .minimum = 1, .maximum = 1024 } };
    const exact_kind: schema.Node = .{ .constant = .{ .string = "exact_copy" } };
    const insertion: schema.Node = .{ .object = &.{.{ .name = "kind", .required = true, .schema = &exact_kind }} };
    const fragment: schema.Node = .{ .one_of = &.{ &prose, &insertion } };
    const array: schema.Node = .{ .array = .{ .minimum = 1, .maximum = 16, .items = &fragment } };
    const composed: schema.Node = .{ .object = &.{.{ .name = "fragments", .required = true, .schema = &array }} };
    const text: schema.Node = .{ .one_of = &.{ &prose, &composed } };
    const selected: schema.Node = .{ .object = &.{.{ .name = "amount", .required = true, .schema = &text }} };
    const bindings = [_]fields.Binding{
        .{ .field = .spec_goal, .path = &.{.{ .property = "amount" }} },
        .{ .field = .spec_story, .path = &.{.{ .property = "absent_story" }} },
    };
    const omissions = [_]Omission{
        .{ .requires = .exact_copy, .path = &.{.{ .property = "inventory" }} },
        .{ .requires = .exact_copy, .path = &.{ .{ .property = "groups" }, .{ .index = 1 } } },
        .{ .requires = .exact_copy, .path = &.{ .{ .property = "groups" }, .{ .index = 3 } } },
    };
    const body = "{\"inventory\":[4],\"groups\":[1,2,3,4],\"unrelated\":{\"literal\":\"source evidence\"},\"number\":1e+04}";
    const encoded = try project(a, body, &selected, &bindings, &omissions);
    const observed = (try strict.parse(a, encoded, .{ .maximum_depth = schema.max_json_depth }, false, null)).value;
    try std.testing.expect(!observed.object.contains("inventory"));
    try std.testing.expectEqualStrings("1", observed.object.get("groups").?.array.items[0].number_string);
    try std.testing.expectEqualStrings("3", observed.object.get("groups").?.array.items[1].number_string);
    try std.testing.expectEqual(@as(usize, 2), observed.object.get("groups").?.array.items.len);
    try std.testing.expectEqualStrings("source evidence", observed.object.get("unrelated").?.object.get("literal").?.string);
    try std.testing.expectEqualStrings("1e+04", observed.object.get("number").?.number_string);
    const rules = observed.object.get("field_rules").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), rules.len);
    try std.testing.expectEqualStrings("amount", rules[0].object.get("field").?.string);
    try std.testing.expectEqualStrings(policy.selectedGuidance(.spec_goal, .initEmpty()).instruction, rules[0].object.get("instruction").?.string);
    try std.testing.expect(!observed.object.get("insertion_fields").?.object.contains("exact_copy"));
    const permitted = [_]fields.Binding{.{ .field = .business_rule, .path = &.{.{ .property = "amount" }} }};
    const admitted = (try strict.parse(a, try project(a, body, &selected, &permitted, &omissions), .{ .maximum_depth = schema.max_json_depth }, false, null)).value;
    try std.testing.expect(admitted.object.contains("inventory"));
    try std.testing.expectEqual(@as(usize, 4), admitted.object.get("groups").?.array.items.len);
    try std.testing.expect(!admitted.object.get("insertion_fields").?.object.contains("exact_copy"));
}

test "presentation descriptors clone nested input paths and reject ambiguous selectors" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var name = [_]u8{ 'l', 'i', 's', 't' };
    const original = [_]Omission{.{ .requires = .exact_copy, .path = &.{ .{ .property = &name }, .{ .index = 2 } } }};
    const copy = try prefixed(a, &original, &.{.{ .property = "input" }});
    name[0] = 'X';
    try std.testing.expect(valid(copy));
    try std.testing.expectEqualStrings("list", copy[0].path[1].property);
    try std.testing.expect(!valid(&.{.{ .requires = .source, .path = &.{} }}));
    try std.testing.expect(!valid(&.{ copy[0], copy[0] }));
    const selected: schema.Node = .{ .object = &.{} };
    try std.testing.expectError(error.InvalidModelFieldPresentation, project(a, "[]", &selected, &.{}, &.{}));
    const empty = try project(a, "{\"field_rules\":[],\"insertion_fields\":{},\"assignment\":true}", &selected, &.{}, &.{});
    const value = (try strict.parse(a, empty, .{ .maximum_depth = schema.max_json_depth }, false, null)).value;
    try std.testing.expect(!value.object.contains("field_rules") and !value.object.contains("insertion_fields"));
    try std.testing.expect(value.object.get("assignment").?.bool);
}
