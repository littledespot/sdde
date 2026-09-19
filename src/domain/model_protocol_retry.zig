//! Response-level syntax/schema correction. No semantic reconsideration or ID change.
const std = @import("std");
const projection = @import("model_schema_projection.zig");
const preparation = @import("model_request_preparation.zig");
const provider = @import("llm_provider_operation.zig");
pub const Diagnostic = union(enum) { decoder: @import("strict_json.zig").Diagnostic, schema: @import("model_payload_schema.zig").Diagnostic };
pub fn build(allocator: std.mem.Allocator, source: preparation.Source, base_content: []const provider.ModelVisibleContent, rejected: *const @import("provider_invocation_validation.zig").CompleteCandidate, diagnostic: Diagnostic, prompt: []const u8) preparation.Error!preparation.Owned {
    const original = rejected.association().request();
    if (original.model_request_id != source.request_binding.modelRequestId() or original.response_schema != try source.resultSchema()) return error.ModelRequestAssociationInvalid;
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const guidance = switch (diagnostic) {
        .decoder => |reason| if (reason.explanation()) |explanation|
            try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .decoder = reason }, .explanation = explanation }, .{})
        else
            try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .decoder = reason } }, .{}),
        .schema => |reason| try std.json.Stringify.valueAlloc(scratch, .{
            .diagnostic = .{ .schema = try reason.describe(scratch) },
            .expected = .{
                .path = (try reason.describeExpected(scratch)).path,
                .scope = reason.expected_location,
                .schema_pointer = (try projection.locate(scratch, original.response_schema, reason.expected)) orelse return error.ModelRequestAssociationInvalid,
                .shape = try projection.outline(scratch, reason.expected),
            },
        }, .{}),
    };
    const response = try std.json.Stringify.valueAlloc(scratch, .{ .rejected_response = rejected.content() }, .{});
    const parts = try scratch.alloc(provider.ModelVisibleContent, base_content.len + 3);
    @memcpy(parts[0..base_content.len], base_content);
    parts[base_content.len] = .{ .guidance = prompt };
    parts[base_content.len + 1] = .{ .guidance = guidance };
    parts[base_content.len + 2] = .{ .evidence = response };
    return preparation.build(allocator, source, parts);
}
