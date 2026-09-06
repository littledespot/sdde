const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const binding = @import("llm_provider_binding.zig");
const identity = @import("model_request_identity.zig");
const compilation = @import("workflow_compilation.zig");
const workflow = @import("workflow.zig");

pub const ValidationError = provider.RequestError || error{
    InvalidModelRequestSource,
    ModelRequestAssociationInvalid,
    ModelRequestBindingInvalid,
};
pub const Error = ValidationError || std.mem.Allocator.Error;

pub fn build(allocator: std.mem.Allocator, source: Source, content: []const provider.ModelVisibleContent) Error!Owned {
    const selected = source.provider_binding;
    // Reuse the request's closed validator before any content allocation.
    // Construction does not grant provider-call authority.
    var request: provider.IdentifiedProviderNeutralModelRequest = .{
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
    };
    try validateRequest(source, &request);
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

/// Runner-selected references, not a second identity/schema/binding authority.
/// The request ledger, provider registry and compiled graph outlive preparation
/// and every consumer of the prepared request. Input identity is supplied by
/// the runner; this boundary neither allocates it nor imports it from a model.
pub const Source = struct {
    request_binding: *const identity.ModelRequestBindingEvidence,
    provider_binding: *const binding.ValidatedProviderModelBinding,
    request_schema_id: provider.RequestSchemaId,
    model_visible_input_id: provider.ModelVisibleInputId,
    result_resource: *const compilation.CompiledResource,

    pub fn resultSchema(self: Source) ValidationError!*const @import("model_result_schema.zig").Schema {
        if (workflow.WorkflowResourceId.parse(self.result_resource.id.bytes) == null or
            self.result_resource.content != .result_schema) return error.InvalidModelRequestSource;
        return self.result_resource.content.result_schema;
    }
};

/// Owns content and transient identity bytes. Canonical request identity,
/// model-binding identity and compiled result schema are borrowed immutable
/// execution authorities, deliberately not cloned into competing identities.
pub const Owned = struct {
    arena: std.heap.ArenaAllocator,
    request: *const provider.IdentifiedProviderNeutralModelRequest,

    pub fn deinit(self: *Owned) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

/// Validate the prepared request against its exact runner-selected authorities.
/// This grants no send authority and produces no separate preflight evidence.
pub fn validateRequest(source: Source, request: *const provider.IdentifiedProviderNeutralModelRequest) ValidationError!void {
    try request.validate();
    const schema = try source.resultSchema();
    if (request.model_request_id != source.request_binding.modelRequestId() or
        !std.mem.eql(u8, request.request_schema_id.bytes, source.request_schema_id.bytes) or
        !std.mem.eql(u8, request.result_schema_id.bytes, source.result_resource.id.bytes) or
        request.response_schema != schema or
        !request.model_visible_input_id.eql(source.model_visible_input_id)) return error.ModelRequestAssociationInvalid;
    if (!request.matchesBinding(source.provider_binding.*)) return error.ModelRequestBindingInvalid;
}
