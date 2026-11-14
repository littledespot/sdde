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
            // Exactly an integer enumeration's mismatch names the value the candidate gave and
            // the set it missed (22-repair.md §22.6): the value from admission, the set from the
            // compiled node the request itself carries.
            const allowed = projection.allowedIntegers(reason.expected);
            if ((reason.rejected != null) != (reason.reason == .enum_mismatch and allowed != null)) return error.ModelRequestAssociationInvalid;
            const Exclusive = struct { kind_property: []const u8, kinds: []const []const u8, owning: []const []const u8 };
            // ADR 0038 Decision 5: a partly taken item's correction lists every taken
            // value's naming in such items, found by the admission owner from the same rule.
            const shared: ?[]const []const u8 = if (reason.reason == .shared_member) listed: {
                var document = @import("model_envelope.zig").parseContent(scratch, content orelse return error.ModelRequestAssociationInvalid, null) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ModelRequestAssociationInvalid;
                defer document.deinit();
                break :listed try sharedPaths(scratch, @import("model_envelope.zig").value(&document.parsed.value), reason);
            } else null;
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

/// Every taken value's naming in the rejected response's partly taken items, as JSON
/// Pointer paths. The rejection's path ends in the first such item; the rest names the
/// array.
fn sharedPaths(allocator: std.mem.Allocator, root: @import("model_envelope.zig").Value, first: @import("model_payload_schema.zig").Diagnostic) preparation.Error![]const []const u8 {
    const payload = @import("model_payload_schema.zig");
    const pointer = @import("json_pointer.zig");
    if (first.length < 1) return error.ModelRequestAssociationInvalid;
    const array_path = first.segments[0 .. first.length - 1];
    const rejected_item = switch (first.segments[first.length - 1]) {
        .index => |index| index,
        .property => return error.ModelRequestAssociationInvalid,
    };
    const coverage = first.coverage orelse return error.ModelRequestAssociationInvalid;
    var cursor = root;
    for (array_path) |segment| cursor = switch (segment) {
        .property => |name| if (cursor == .object) cursor.object.get(name) orelse return error.ModelRequestAssociationInvalid else return error.ModelRequestAssociationInvalid,
        .index => |index| if (cursor == .array) cursor.array.at(index) orelse return error.ModelRequestAssociationInvalid else return error.ModelRequestAssociationInvalid,
    };
    if (cursor != .array) return error.ModelRequestAssociationInvalid;
    var paths: std.ArrayList([]const u8) = .empty;
    var segments = first.segments;
    var from: payload.SharedNaming = .{ .item = 0, .position = 0 };
    // Admission located the first such item; any other means the response isn't the
    // one it rejected.
    if ((payload.nextSharedNaming(cursor.array, coverage, from) orelse return error.ModelRequestAssociationInvalid).item != rejected_item) return error.ModelRequestAssociationInvalid;
    while (payload.nextSharedNaming(cursor.array, coverage, from)) |found| {
        segments[array_path.len] = .{ .index = found.item };
        segments[array_path.len + 1] = .{ .property = coverage.property };
        segments[array_path.len + 2] = .{ .index = found.position };
        try paths.append(allocator, try pointer.render(allocator, segments[0 .. array_path.len + 3]));
        from = .{ .item = found.item, .position = found.position + 1 };
    }
    return paths.toOwnedSlice(allocator);
}
