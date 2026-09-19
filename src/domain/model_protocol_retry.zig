//! Response-level content/syntax/schema correction. No semantic reconsideration or ID change.
const std = @import("std");
const projection = @import("model_schema_projection.zig");
const preparation = @import("model_request_preparation.zig");
const provider = @import("llm_provider_operation.zig");
pub const Diagnostic = union(enum) { decoder: @import("strict_json.zig").Diagnostic, schema: @import("model_payload_schema.zig").Diagnostic, missing_final_text };
pub fn build(allocator: std.mem.Allocator, source: preparation.Source, base_content: []const provider.ModelVisibleContent, rejected: *const @import("provider_invocation_validation.zig").Evidence, diagnostic: Diagnostic, prompt: []const u8) preparation.Error!preparation.Owned {
    const original = rejected.request();
    if (original.model_request_id != source.request_binding.modelRequestId() or original.response_schema != try source.resultSchema()) return error.ModelRequestAssociationInvalid;
    const content: ?[]const u8 = switch (diagnostic) {
        .missing_final_text => if (rejected.missingFinalText()) null else return error.ModelRequestAssociationInvalid,
        .decoder, .schema => switch (rejected.result()) {
            .complete => |candidate| candidate.content(),
            .failed, .stopped => return error.ModelRequestAssociationInvalid,
        },
    };
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const guidance = switch (diagnostic) {
        .missing_final_text => try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .provider_content = provider.ProviderContentDiagnostic.missing_final_text }, .instruction = "No final answer was received. Return the complete assigned response." }, .{}),
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
    const parts = try scratch.alloc(provider.ModelVisibleContent, base_content.len + 2 + @as(usize, @intFromBool(content != null)));
    @memcpy(parts[0..base_content.len], base_content);
    parts[base_content.len] = .{ .guidance = prompt };
    parts[base_content.len + 1] = .{ .guidance = guidance };
    if (content) |bytes| parts[base_content.len + 2] = .{ .evidence = try std.json.Stringify.valueAlloc(scratch, .{ .rejected_response = bytes }, .{}) };
    return preparation.build(allocator, source, parts);
}
