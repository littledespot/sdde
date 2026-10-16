//! Native field identity for a model-text schema leaf. Paths follow the shared
//! wire codec; a variant selects the compiler's closed `kind` discriminator.
const std = @import("std");
const schema = @import("model_result_schema.zig");
const policy = @import("text_field_policy.zig");
pub const Step = union(enum) { property: []const u8, items, variant: []const u8 };
pub const Binding = struct { field: policy.Field, path: []const Step };
pub const Error = schema.Error;
pub fn samePath(left: []const Step, right: []const Step) bool {
    if (left.len != right.len) return false;
    for (left, right) |l, r| {
        if (std.meta.activeTag(l) != std.meta.activeTag(r)) return false;
        switch (l) {
            .property => |name| if (!std.mem.eql(u8, name, r.property)) return false,
            .variant => |name| if (!std.mem.eql(u8, name, r.variant)) return false,
            .items => {},
        }
    }
    return true;
}
pub fn valid(bindings: []const Binding) bool {
    if (bindings.len > schema.max_nodes) return false;
    for (bindings, 0..) |binding, index| {
        if (binding.path.len > schema.max_depth * 2) return false;
        for (binding.path) |step| switch (step) {
            .property, .variant => |name| if (name.len == 0 or !std.unicode.utf8ValidateSlice(name)) return false,
            .items => {},
        };
        for (bindings[0..index]) |prior| if (samePath(prior.path, binding.path)) return false;
    }
    return true;
}
pub fn clone(a: std.mem.Allocator, bindings: []const Binding) std.mem.Allocator.Error![]const Binding {
    var result: std.ArrayList(Binding) = .empty;
    errdefer {
        for (result.items) |binding| {
            for (binding.path) |step| switch (step) {
                .property, .variant => |name| a.free(name),
                .items => {},
            };
            a.free(binding.path);
        }
        result.deinit(a);
    }
    for (bindings) |binding| {
        const path = try a.alloc(Step, binding.path.len);
        var count: usize = 0;
        errdefer {
            for (path[0..count]) |step| switch (step) {
                .property, .variant => |name| a.free(name),
                .items => {},
            };
            a.free(path);
        }
        for (binding.path, path) |step, *copy| {
            copy.* = switch (step) {
                .property => |name| .{ .property = try a.dupe(u8, name) },
                .variant => |name| .{ .variant = try a.dupe(u8, name) },
                .items => .items,
            };
            count += 1;
        }
        try result.append(a, .{ .field = binding.field, .path = path });
    }
    return result.toOwnedSlice(a);
}
pub fn same(left: []const Binding, right: []const Binding) bool {
    if (left.len != right.len) return false;
    for (left, right) |l, r| if (l.field != r.field or !samePath(l.path, r.path)) return false;
    return true;
}
/// The effective schema must already exclude every prohibited alternative.
/// This allocation-free check guards prepared/provider requests and replay.
pub fn validSchema(root: *const schema.Node, bindings: []const Binding) bool {
    if (!valid(bindings)) return false;
    var path: [schema.max_depth * 2 + 2]Step = undefined;
    return checkSchema(root, bindings, &path, 0);
}
fn checkSchema(node: *const schema.Node, bindings: []const Binding, path: []Step, depth: usize) bool {
    var length = depth;
    if (schema.discriminator(node)) |tag| {
        if (length == path.len) return false;
        path[length] = .{ .variant = tag };
        length += 1;
    }
    const binding = for (bindings) |entry| {
        if (samePath(entry.path, path[0..length])) break entry;
    } else null;
    if (@import("model_text_wire.zig").textContract(node)) return if (binding) |entry| allowed(node, entry.field) else false;
    switch (node.*) {
        .object => |properties| for (properties) |property| {
            if (length == path.len) return false;
            path[length] = .{ .property = property.name };
            if (!checkSchema(property.schema, bindings, path, length + 1)) return false;
        },
        .array => |array| {
            if (length == path.len) return false;
            path[length] = .items;
            return checkSchema(array.items, bindings, path, length + 1);
        },
        .one_of => |variants| for (variants) |variant| if (!checkSchema(variant, bindings, path, length)) return false,
        else => {},
    }
    return true;
}
fn allowed(node: *const schema.Node, field: policy.Field) bool {
    if (schema.discriminator(node)) |tag| return policy.permits(field, std.meta.stringToEnum(policy.Insertion, tag) orelse return false);
    return switch (node.*) {
        .one_of => |variants| result: {
            for (variants) |variant| if (!allowed(variant, field)) break :result false;
            break :result true;
        },
        .object => |properties| result: {
            for (properties) |property| if (!allowed(property.schema, field)) break :result false;
            break :result true;
        },
        .array => |array| allowed(array.items, field),
        else => true,
    };
}
/// A native binding resolved against its actual selected wire-text leaf.
/// Paths borrow the supplied bindings; insertion choices come from that leaf.
pub const ActiveBinding = struct { field: policy.Field, path: []const Step, insertions: policy.Insertions };
pub const Projection = struct { root: *const schema.Node, active: []const ActiveBinding };
pub fn project(a: std.mem.Allocator, root: *const schema.Node, bindings: []const Binding, require_complete: bool) Error!Projection {
    if (!valid(bindings)) return error.InvalidModelResultSchema;
    var path: std.ArrayList(Step) = .empty;
    defer path.deinit(a);
    var active: std.ArrayList(ActiveBinding) = .empty;
    errdefer active.deinit(a);
    const selected = try walk(a, root, bindings, require_complete, &path, &active);
    return .{ .root = selected, .active = try active.toOwnedSlice(a) };
}
pub fn activeBindings(a: std.mem.Allocator, root: *const schema.Node, bindings: []const Binding) Error![]const ActiveBinding {
    return (try project(a, root, bindings, false)).active;
}
fn walk(a: std.mem.Allocator, node: *const schema.Node, bindings: []const Binding, complete: bool, path: *std.ArrayList(Step), active: *std.ArrayList(ActiveBinding)) Error!*const schema.Node {
    const before = path.items.len;
    defer path.shrinkRetainingCapacity(before);
    if (schema.discriminator(node)) |tag| try path.append(a, .{ .variant = tag });
    const binding = for (bindings) |entry| {
        if (samePath(entry.path, path.items)) break entry;
    } else null;
    if (@import("model_text_wire.zig").textContract(node) or (binding != null and node.* == .string)) {
        const field = binding orelse {
            if (complete) return error.InvalidModelResultSchema;
            return node;
        };
        const selected = try filter(a, node, field.field);
        var insertions: policy.Insertions = .initEmpty();
        collectInsertions(selected, field.field, &insertions);
        for (active.items) |*prior| {
            if (samePath(prior.path, field.path)) {
                inline for (std.meta.tags(policy.Insertion)) |kind| if (insertions.contains(kind)) prior.insertions.insert(kind);
                return selected;
            }
        }
        try active.append(a, .{ .field = field.field, .path = field.path, .insertions = insertions });
        return selected;
    }
    const copy = try a.create(schema.Node);
    copy.* = node.*;
    switch (node.*) {
        .object => |properties| {
            const values = try a.dupe(schema.Property, properties);
            for (values) |*property| {
                try path.append(a, .{ .property = property.name });
                property.schema = try walk(a, property.schema, bindings, complete, path, active);
                _ = path.pop();
            }
            copy.* = .{ .object = values };
        },
        .array => |array| {
            try path.append(a, .items);
            copy.array.items = try walk(a, array.items, bindings, complete, path, active);
        },
        .one_of => |variants| {
            const values = try a.alloc(*const schema.Node, variants.len);
            for (variants, values) |variant, *value| value.* = try walk(a, variant, bindings, complete, path, active);
            copy.* = .{ .one_of = values };
        },
        else => {},
    }
    return copy;
}
fn collectInsertions(node: *const schema.Node, field: policy.Field, result: *policy.Insertions) void {
    if (schema.discriminator(node)) |tag| {
        if (std.meta.stringToEnum(policy.Insertion, tag)) |kind| if (policy.permits(field, kind)) result.insert(kind);
        return;
    }
    switch (node.*) {
        .object => |properties| for (properties) |property| collectInsertions(property.schema, field, result),
        .array => |array| collectInsertions(array.items, field, result),
        .one_of => |variants| for (variants) |variant| collectInsertions(variant, field, result),
        else => {},
    }
}
fn filter(a: std.mem.Allocator, node: *const schema.Node, field: policy.Field) Error!*const schema.Node {
    if (schema.discriminator(node)) |tag| if (!policy.permits(field, std.meta.stringToEnum(policy.Insertion, tag) orelse return error.InvalidModelResultSchema)) return error.InvalidModelResultSchema;
    const copy = try a.create(schema.Node);
    copy.* = node.*;
    switch (node.*) {
        .one_of => |variants| {
            var retained: std.ArrayList(*const schema.Node) = .empty;
            for (variants) |variant| {
                if (schema.discriminator(variant)) |tag| if (std.meta.stringToEnum(policy.Insertion, tag)) |kind| if (!policy.permits(field, kind)) continue;
                try retained.append(a, try filter(a, variant, field));
            }
            if (retained.items.len == 0) return error.InvalidModelResultSchema;
            copy.* = if (retained.items.len == 1) retained.items[0].* else .{ .one_of = try retained.toOwnedSlice(a) };
        },
        .object => |properties| {
            const values = try a.dupe(schema.Property, properties);
            for (values) |*property| property.schema = try filter(a, property.schema, field);
            copy.* = .{ .object = values };
        },
        .array => |array| copy.array.items = try filter(a, array.items, field),
        else => {},
    }
    return copy;
}
