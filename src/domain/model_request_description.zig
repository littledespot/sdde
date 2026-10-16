//! Closed diagnostic projection of a prepared request. Never workflow authority.
const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const binding = @import("llm_provider_binding.zig");
pub const Description = struct {
    version: enum { @"model-request-debug/v5" } = .@"model-request-debug/v5",
    provider: []const u8,
    model: []const u8,
    provider_config: @import("llm_provider_contracts.zig").ValidatedProviderConfig,
    model_slot: []const u8,
    workflow_id: []const u8,
    workflow_version: u32,
    request_step: []const u8,
    content: []const provider.ModelVisibleContent,
    protocol_prompt: []const u8,
    schema: []const u8,
    response_mode: @import("model_controls.zig").ResponseGuidanceMode,
    controls: @import("model_controls.zig").InferenceControls,
    reasoning_effort: ?[]const u8,
    operation_kind: provider.ProviderOperationKind,
    original_sources: []const @import("model_text_wire.zig").SourceText = &.{},
    prose_fields: []const @import("model_text_wire.zig").ProseField = &.{},
    field_policies: []const @import("model_text_field.zig").Binding = &.{},

    pub fn from(request: *const provider.IdentifiedProviderNeutralModelRequest, selected: *const binding.ValidatedProviderModelBinding, kind: provider.ProviderOperationKind) Description {
        return .{
            .provider = selected.registry_entry.provider.bytes,
            .model = selected.registry_entry.model.bytes,
            .provider_config = selected.registry_entry.config,
            .model_slot = selected.slot_id.bytes,
            .workflow_id = selected.operation_id.workflow_id.bytes,
            .workflow_version = selected.operation_id.workflow_version,
            .request_step = selected.operation_id.workflow_step_id.bytes,
            .content = request.content,
            .protocol_prompt = @import("model_controls.zig").response_format_guidance,
            .schema = request.response_schema.modelBytes(),
            .response_mode = request.response_guidance_mode,
            .controls = request.controls,
            .reasoning_effort = selected.reasoning_effort,
            .operation_kind = kind,
            .original_sources = request.original_sources,
            .prose_fields = request.prose_fields,
            .field_policies = request.field_policies,
        };
    }

    pub fn decode(a: std.mem.Allocator, bytes: []const u8) @import("strict_json.zig").Error!Description {
        const value = try @import("strict_json.zig").decode(Description, a, bytes, .{ .maximum_depth = 64 });
        if (!@import("model_text_wire.zig").validSources(value.original_sources) or !@import("model_text_wire.zig").validProseFields(value.prose_fields)) return error.InvalidJsonDocument;
        if (!@import("model_text_field.zig").valid(value.field_policies)) return error.InvalidJsonDocument;
        var scratch: std.heap.ArenaAllocator = .init(a);
        defer scratch.deinit();
        // Schema keyword bounds use the compiler's native numeric contract,
        // just as the canonical schema syntax adapter does.
        const parsed_schema = try @import("strict_json.zig").parse(scratch.allocator(), value.schema, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }, true, null);
        const selected_schema = @import("model_result_schema.zig").compileSelected(scratch.allocator(), parsed_schema.value, value.schema) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidJsonDocument;
        if (!@import("model_text_field.zig").validSchema(selected_schema.root(), value.field_policies)) return error.InvalidJsonDocument;
        const ids = @import("llm_provider_identity.zig");
        const workflow = @import("workflow.zig");
        if (ids.ProviderId.parse(value.provider) == null or ids.ModelId.parse(value.model) == null or ids.ModelSlotId.parse(value.model_slot) == null or
            workflow.WorkflowId.parse(value.workflow_id) == null or workflow.WorkflowStepId.parse(value.request_step) == null or value.workflow_version == 0 or value.content.len == 0 or !value.controls.isValid()) return error.InvalidJsonDocument;
        return value;
    }
};
