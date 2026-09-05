const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const provider = @import("../../domain/llm_provider_operation.zig");
const preparation = @import("../../domain/model_request_preparation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-model-request@1",
        .kind = .action,
        .requires = &.{ .model_request_identity_ledger, .validated_provider_model_binding },
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, source: preparation.Source, content: []const provider.ModelVisibleContent) preparation.Error!preparation.Owned {
        const selected = source.provider_binding;
        // Reuse the request's closed validator before any content allocation.
        // Construction does not grant static-preflight or provider-call authority.
        var request = try provider.IdentifiedProviderNeutralModelRequest.init(.{
            .model_request_id = source.request_binding.modelRequestId(),
            .model_operation_id = selected.operation_id,
            .binding_id = selected.bindingId(),
            .request_schema_id = source.request_schema_id,
            .result_schema_id = .{ .bytes = source.result_resource.id.bytes },
            .model_visible_input_id = source.model_visible_input_id,
            .content = content,
            .response_schema = try source.resultSchema(),
            .response_guidance_mode = selected.response_mode,
            .controls = selected.controls,
            .limits = selected.capacity.canonical,
        });
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const owned = arena.allocator();
        const parts = try owned.alloc(provider.ModelVisibleContent, content.len);
        for (content, parts) |part, *copy| {
            copy.* = switch (part) {
                inline else => |bytes, kind| @unionInit(provider.ModelVisibleContent, @tagName(kind), try owned.dupe(u8, bytes)),
            };
        }
        request.content = parts;
        request.request_schema_id.bytes = try owned.dupe(u8, request.request_schema_id.bytes);
        request.model_visible_input_id.bytes = try owned.dupe(u8, request.model_visible_input_id.bytes);
        const result = try owned.create(provider.IdentifiedProviderNeutralModelRequest);
        result.* = request;
        return .{ .arena = arena, .request = result };
    }
};
