//! Explicit in-memory test bindings. These values grant no workflow authority.
const std = @import("std");
const debug = @import("../../src/domain/request_debugger.zig");
const ports = @import("../../src/ports/request_replay.zig");
const registered = @import("../../src/composition/provider_model_contracts.zig");
const identities = @import("../../src/domain/llm_provider_identity.zig");

pub const Error = std.mem.Allocator.Error || error{InvalidEvaluationContract};

pub const Authorization = struct {
    binding: debug.Description,

    pub fn authorize(context: *ports.Context, value: debug.Description) ports.Error!void {
        const self: *Authorization = @ptrCast(@alignCast(context));
        const expected = self.binding;
        if (!std.mem.eql(u8, value.provider, expected.provider) or !std.mem.eql(u8, value.model, expected.model) or !std.meta.eql(value.provider_config, expected.provider_config) or
            !std.meta.eql(value.controls, expected.controls) or !debug.sameOptional(value.reasoning_effort, expected.reasoning_effort) or value.response_mode != expected.response_mode or value.operation_kind != .inference) return error.ReplayUnauthorized;
    }
};

pub fn validateBinding(binding: debug.Description) error{InvalidEvaluationContract}!void {
    if (binding.provider_config != .aws_bedrock or binding.operation_kind != .inference) return error.InvalidEvaluationContract;
    const provider = identities.ProviderId.parse(binding.provider) orelse return error.InvalidEvaluationContract;
    const model = identities.ModelId.parse(binding.model) orelse return error.InvalidEvaluationContract;
    const supported = registered.registry.resolve(provider, model) orelse return error.InvalidEvaluationContract;
    if (!supported.acceptsConfig(binding.provider_config) or !supported.capabilities.supports(binding.response_mode, binding.controls) or
        !@import("../../src/domain/llm_provider_contracts.zig").supportsReasoningEffort(supported.supported_reasoning_efforts, binding.reasoning_effort)) return error.InvalidEvaluationContract;
}

/// Retains captured content, schema, controls and response mode. The caller's
/// explicit selection forms a temporary diagnostic slot, validated through the
/// ordinary catalogue and repository allowlist owners. No project is modified.
/// The result borrows captured fields and the requested model/effort slices;
/// none of its slices refer to the temporary registry or allowlist.
pub fn rebind(
    allocator: std.mem.Allocator,
    captured: debug.Description,
    catalogue_bytes: []const u8,
    requested_model: []const u8,
    requested_effort: ?[]const u8,
) Error!debug.Description {
    try validateBinding(captured);
    const slot = identities.ModelSlotId.parse(captured.model_slot) orelse return error.InvalidEvaluationContract;
    var document = (@import("../../src/actions/provider/decode_llm_provider_config.zig").Action{}).execute(allocator, catalogue_bytes) catch return error.InvalidEvaluationContract;
    defer document.deinit();
    var candidate = (@import("../../src/actions/provider/build_llm_provider_registry.zig").Action{ .contracts = &registered.registry }).execute(allocator, document.value()) catch return error.InvalidEvaluationContract;
    defer candidate.deinit();
    const registry_contract = @import("../../src/domain/llm_provider_registry.zig");
    const registry_owner = (@import("../../src/actions/provider/validate_llm_provider_registry.zig").Action{ .contracts = &registered.registry }).execute(allocator, candidate) catch return error.InvalidEvaluationContract;
    defer registry_contract.deinitOwner(registry_owner);
    const registry = registry_contract.registry(registry_owner);

    var models: @import("../../src/domain/config.zig").ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(allocator);
    try models.slots.map.put(allocator, slot.bytes, .{
        .provider = captured.provider,
        .model = requested_model,
        .reasoningEffort = requested_effort,
        .maxOutputTokens = if (captured.controls.max_output_tokens) |allowance| allowance.value else null,
    });
    const allowlist_contract = @import("../../src/domain/repository_model_allowlist.zig");
    const allowlist_owner = allowlist_contract.createValidated(allocator, &models, registry) catch return error.InvalidEvaluationContract;
    defer allowlist_contract.deinitOwner(allowlist_owner);
    const allowed = allowlist_contract.allowlist(allowlist_owner).resolveSlot(slot) orelse return error.InvalidEvaluationContract;
    const entry = registry.resolveId(allowed.registry_entry_id) orelse return error.InvalidEvaluationContract;
    if (entry.responseMode() != captured.response_mode or !std.meta.eql(allowed.controls, captured.controls) or
        !entry.capabilities.supports(captured.response_mode, captured.controls)) return error.InvalidEvaluationContract;

    var selected = captured;
    selected.model = requested_model;
    selected.reasoning_effort = requested_effort;
    selected.provider_config = entry.config;
    try validateBinding(selected);
    return selected;
}
