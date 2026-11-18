//! Response-level syntax, schema and mechanical text-composition correction.
//! No semantic reconsideration, new allowance or request identity.
const std = @import("std");
const projection = @import("model_schema_projection.zig");
const preparation = @import("model_request_preparation.zig");
const provider = @import("llm_provider_operation.zig");
pub const Diagnostic = union(enum) {
    decoder: @import("strict_json.zig").Diagnostic,
    composition: @import("model_text_composition.zig").Diagnostic,
    schema: @import("model_payload_schema.zig").Diagnostic,
    missing_final_text,

    pub fn copy(self: Diagnostic, allocator: std.mem.Allocator) std.mem.Allocator.Error!Diagnostic {
        return switch (self) {
            inline .decoder, .schema, .composition => |value, tag| @unionInit(Diagnostic, @tagName(tag), try value.copy(allocator)),
            .missing_final_text => .missing_final_text,
        };
    }

    pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        switch (self) {
            .decoder => |value| value.deinit(allocator),
            .schema => |value| value.deinit(allocator),
            .composition => |value| value.deinit(allocator),
            .missing_final_text => {},
        }
    }

    pub fn eql(self: Diagnostic, other: Diagnostic) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            inline .decoder, .schema, .composition => |value, tag| value.eql(@field(other, @tagName(tag))),
            .missing_final_text => true,
        };
    }
};

/// A handoff-proven comparison, never an attempt count or response identity claim.
pub const Repetition = enum { unconfirmed, confirmed };

pub fn build(allocator: std.mem.Allocator, source: preparation.Source, base_content: []const provider.ModelVisibleContent, rejected: *const @import("provider_invocation_validation.zig").Evidence, diagnostic: Diagnostic, repetition: Repetition, prompt: []const u8) preparation.Error!preparation.Owned {
    const original = rejected.request();
    if (original.model_request_id != source.request_binding.modelRequestId() or original.response_schema != try source.resultSchema()) return error.ModelRequestAssociationInvalid;
    const content: ?[]const u8 = switch (diagnostic) {
        .missing_final_text => if (rejected.missingFinalText()) null else return error.ModelRequestAssociationInvalid,
        .decoder, .schema, .composition => switch (rejected.result()) {
            .complete => |candidate| candidate.content(),
            .failed, .stopped => return error.ModelRequestAssociationInvalid,
        },
    };
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const guidance = switch (diagnostic) {
        .missing_final_text => try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .provider_content = provider.ProviderContentDiagnostic.missing_final_text }, .explanation = "Final-answer admission failed: no final answer was received." }, .{}),
        .decoder => |reason| try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .decoder = reason }, .explanation = reason.explanation() }, .{}),
        .composition => |reason| try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .composition = try reason.describe(scratch) }, .explanation = "Model-text composition failed. Correct every listed field within this same response and retain the original assignment." }, .{}),
        .schema => |reason| value: {
            // ADR 0038 Decision 5: exactly a partly taken item's correction names the
            // exclusive and owning kinds.
            if ((reason.coverage != null) != (reason.reason == .shared_member)) return error.ModelRequestAssociationInvalid;
            // Exactly a missing member's correction names the member no item names.
            if ((reason.member != null) != (reason.reason == .missing_member)) return error.ModelRequestAssociationInvalid;
            // ADR 0038 Decision 3: exactly an equal-items correction names the rule that compares them.
            if ((reason.members != null) != (reason.reason == .equal_items)) return error.ModelRequestAssociationInvalid;
            // ADR 0036 Decision 7: exactly a disagreeing-items correction names the rule that compares them.
            if ((reason.agreement != null) != (reason.reason == .disagreeing_items)) return error.ModelRequestAssociationInvalid;
            // Exactly an integer enumeration's mismatch names the value the candidate gave and
            // the set it missed (22-repair.md §22.6): the value from admission, the set from the
            // compiled node the request itself carries.
            const allowed = projection.allowedIntegers(reason.expected);
            if ((reason.rejected != null) != (reason.reason == .enum_mismatch and allowed != null)) return error.ModelRequestAssociationInvalid;
            const Exclusive = struct { kind_property: []const u8, kinds: []const []const u8, owning: []const []const u8 };
            // A correction that lists namings reads the rejected response again; the admission owner finds
            // the namings from the rule that rejected it.
            var document = if (reason.reason == .shared_member or reason.reason == .equal_items or reason.reason == .disagreeing_items)
                @import("model_envelope.zig").parseContent(scratch, content orelse return error.ModelRequestAssociationInvalid, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ModelRequestAssociationInvalid
            else
                null;
            defer if (document) |*parsed| parsed.deinit();
            const rejected_root: ?@import("model_envelope.zig").Value = if (document) |*parsed| @import("model_envelope.zig").value(&parsed.parsed.value) else null;
            // ADR 0038 Decision 5: a partly taken item's correction lists every taken value's naming in such items.
            const shared: ?[]const []const u8 = if (reason.reason == .shared_member) try sharedPaths(scratch, rejected_root.?, reason) else null;
            // ADR 0038 Decision 3: an equal-items correction lists the key of every item of each equal set.
            const Equal = struct { key: []const u8, compared: []const []const u8, sets: []const []const i64 };
            const equal: ?Equal = if (reason.reason == .equal_items) .{ .key = reason.members.?.property, .compared = reason.members.?.distinct, .sets = try equalSets(scratch, rejected_root.?, reason) } else null;
            // ADR 0036 Decision 7: a disagreeing-items correction lists each group of values its items disagree on, with the location of every item that lists them.
            const Agreed = struct { property: []const u8, agree: []const u8, sets: []const Disagreement };
            const agreement: ?Agreed = if (reason.reason == .disagreeing_items) .{ .property = reason.agreement.?.property, .agree = reason.agreement.?.agree, .sets = try disagreeingSets(scratch, rejected_root.?, reason) } else null;
            break :value try std.json.Stringify.valueAlloc(scratch, .{
                .diagnostic = .{ .schema = try reason.describe(scratch) },
                .explanation = reason.explanation(),
                .expected = .{
                    .path = (try reason.describeExpected(scratch)).path,
                    .scope = reason.expected_location,
                    .schema_pointer = (try projection.locate(scratch, original.response_schema, reason.expected)) orelse return error.ModelRequestAssociationInvalid,
                    .shape = try projection.outline(scratch, reason.expected),
                },
                .exclusive = @as(?Exclusive, if (reason.reason == .shared_member) .{ .kind_property = reason.coverage.?.rule.kind_property, .kinds = reason.coverage.?.rule.exclusive, .owning = reason.coverage.?.rule.owning } else null),
                .shared = shared,
                .equal = equal,
                .agreement = agreement,
                .member = reason.member,
                .rejected = reason.rejected,
                .allowed = if (reason.rejected != null) allowed else null,
            }, .{ .emit_null_optional_fields = false });
        },
    };
    const parts = try scratch.alloc(provider.ModelVisibleContent, base_content.len + 2 + @as(usize, @intFromBool(content != null)));
    @memcpy(parts[0..base_content.len], base_content);
    parts[base_content.len] = .{ .guidance = if (repetition == .confirmed)
        try std.fmt.allocPrint(scratch, "{s}\nThe previous correction still failed this validation.", .{prompt})
    else
        prompt };
    parts[base_content.len + 1] = .{ .guidance = guidance };
    if (content) |bytes| parts[base_content.len + 2] = .{ .evidence = try std.json.Stringify.valueAlloc(scratch, .{ .rejected_response = bytes }, .{}) };
    return preparation.build(allocator, source, parts);
}

/// The array a rejection's location ends in, read from the rejected response, and the item the location
/// names. `path_length` is the length of the location without that item.
const RejectedArray = struct { array: *const @import("model_envelope.zig").Array, item: usize, path_length: usize };

fn rejectedArray(root: @import("model_envelope.zig").Value, first: @import("model_payload_schema.zig").Diagnostic) preparation.Error!RejectedArray {
    if (first.length < 1) return error.ModelRequestAssociationInvalid;
    const array_path = first.segments[0 .. first.length - 1];
    const rejected_item = switch (first.segments[first.length - 1]) {
        .index => |index| index,
        .property => return error.ModelRequestAssociationInvalid,
    };
    var cursor = root;
    for (array_path) |segment| cursor = switch (segment) {
        .property => |name| if (cursor == .object) cursor.object.get(name) orelse return error.ModelRequestAssociationInvalid else return error.ModelRequestAssociationInvalid,
        .index => |index| if (cursor == .array) cursor.array.at(index) orelse return error.ModelRequestAssociationInvalid else return error.ModelRequestAssociationInvalid,
    };
    if (cursor != .array) return error.ModelRequestAssociationInvalid;
    return .{ .array = cursor.array, .item = rejected_item, .path_length = array_path.len };
}

/// Every taken value's naming in the rejected response's partly taken items, as JSON
/// Pointer paths. The rejection's path ends in the first such item; the rest names the
/// array.
fn sharedPaths(allocator: std.mem.Allocator, root: @import("model_envelope.zig").Value, first: @import("model_payload_schema.zig").Diagnostic) preparation.Error![]const []const u8 {
    const payload = @import("model_payload_schema.zig");
    const pointer = @import("json_pointer.zig");
    const located = try rejectedArray(root, first);
    const coverage = first.coverage orelse return error.ModelRequestAssociationInvalid;
    var paths: std.ArrayList([]const u8) = .empty;
    var segments = first.segments;
    var from: payload.SharedNaming = .{ .item = 0, .position = 0 };
    // Admission located the first such item; any other means the response isn't the
    // one it rejected.
    if ((payload.nextSharedNaming(located.array, coverage, from) orelse return error.ModelRequestAssociationInvalid).item != located.item) return error.ModelRequestAssociationInvalid;
    while (payload.nextSharedNaming(located.array, coverage, from)) |found| {
        segments[located.path_length] = .{ .index = found.item };
        segments[located.path_length + 1] = .{ .property = coverage.property };
        segments[located.path_length + 2] = .{ .index = found.position };
        try paths.append(allocator, try pointer.render(allocator, segments[0 .. located.path_length + 3]));
        from = .{ .item = found.item, .position = found.position + 1 };
    }
    return paths.toOwnedSlice(allocator);
}

/// Every set of items of the rejected response that return equal values for the compared properties, as
/// the key of each item. The rejection's path ends in the first item of the first set.
fn equalSets(allocator: std.mem.Allocator, root: @import("model_envelope.zig").Value, first: @import("model_payload_schema.zig").Diagnostic) preparation.Error![]const []const i64 {
    const payload = @import("model_payload_schema.zig");
    const located = try rejectedArray(root, first);
    const members = first.members orelse return error.ModelRequestAssociationInvalid;
    // Admission located the first such item; any other means the response isn't the one it rejected.
    if ((payload.firstEqualItem(located.array, members) orelse return error.ModelRequestAssociationInvalid) != located.item) return error.ModelRequestAssociationInvalid;
    const count = located.array.count();
    const placed = try allocator.alloc(bool, count);
    @memset(placed, false);
    var sets: std.ArrayList([]const i64) = .empty;
    // Each set opens at its first item in response order and takes every later item equal to it; equality
    // is one relation, so a set is complete and no item is in two. An item with no readable key is never named.
    for (0..count) |left| {
        if (placed[left]) continue;
        var keys: std.ArrayList(i64) = .empty;
        try keys.append(allocator, payload.memberKey(located.array.at(left).?, members.property) orelse continue);
        for (left + 1..count) |right| {
            if (placed[right] or !payload.equalItems(located.array, members, left, right)) continue;
            try keys.append(allocator, payload.memberKey(located.array.at(right).?, members.property) orelse continue);
            placed[right] = true;
        }
        if (keys.items.len > 1) try sets.append(allocator, keys.items);
    }
    if (sets.items.len == 0) return error.ModelRequestAssociationInvalid;
    return sets.items;
}

/// One group of values that items of the rejected response list in common yet disagree on: the values,
/// and the JSON Pointer of every item that lists them (ADR 0036 Decision 7).
const Disagreement = struct { values: []const i64, items: []const []const u8 };

/// Every value that items of the rejected response list in common yet disagree on, grouped: values that
/// the same items list form one group, in the order their first value arrives, and each group names every
/// one of those items in response order. The rejection's path ends in the first item that a later one
/// disagrees with.
fn disagreeingSets(allocator: std.mem.Allocator, root: @import("model_envelope.zig").Value, first: @import("model_payload_schema.zig").Diagnostic) preparation.Error![]const Disagreement {
    const payload = @import("model_payload_schema.zig");
    const pointer = @import("json_pointer.zig");
    const located = try rejectedArray(root, first);
    const agreement = first.agreement orelse return error.ModelRequestAssociationInvalid;
    // Admission located the first such item; any other means the response isn't the one it rejected.
    if ((payload.firstDisagreeingItem(located.array, agreement) orelse return error.ModelRequestAssociationInvalid) != located.item) return error.ModelRequestAssociationInvalid;
    const count = located.array.count();
    const Group = struct { members: []const usize, values: std.ArrayList(i64) };
    var groups: std.ArrayList(Group) = .empty;
    var seen: std.ArrayList(i64) = .empty;
    for (0..count) |index| {
        const list = payload.itemList(located.array, agreement, index) orelse continue;
        for (0..list.count()) |position| {
            const value = payload.valueAt(list, position) orelse continue;
            if (std.mem.indexOfScalar(i64, seen.items, value) != null) continue;
            try seen.append(allocator, value);
            // The items that list this value, which disagree when some one differs from the first of them.
            var members: std.ArrayList(usize) = .empty;
            var differs = false;
            for (0..count) |other| {
                const other_list = payload.itemList(located.array, agreement, other) orelse continue;
                if (!payload.lists(other_list, value)) continue;
                if (members.items.len != 0 and payload.disagree(located.array, agreement, members.items[0], other)) differs = true;
                try members.append(allocator, other);
            }
            if (!differs) continue;
            const joined = for (groups.items) |*group| {
                if (std.mem.eql(usize, group.members, members.items)) break group;
            } else null;
            if (joined) |group| try group.values.append(allocator, value) else {
                var values: std.ArrayList(i64) = .empty;
                try values.append(allocator, value);
                try groups.append(allocator, .{ .members = members.items, .values = values });
            }
        }
    }
    if (groups.items.len == 0) return error.ModelRequestAssociationInvalid;
    var segments = first.segments;
    const sets = try allocator.alloc(Disagreement, groups.items.len);
    for (groups.items, sets) |group, *set| {
        const locations = try allocator.alloc([]const u8, group.members.len);
        for (group.members, locations) |item, *location| {
            segments[located.path_length] = .{ .index = item };
            location.* = try pointer.render(allocator, segments[0 .. located.path_length + 1]);
        }
        set.* = .{ .values = group.values.items, .items = locations };
    }
    return sets;
}
