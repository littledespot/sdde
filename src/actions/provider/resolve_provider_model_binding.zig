const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const contracts = @import("../../domain/llm_provider_contracts.zig");
const identity = @import("../../domain/llm_provider_identity.zig");
const provider_registry = @import("../../domain/llm_provider_registry.zig");
const repository_allowlist = @import("../../domain/repository_model_allowlist.zig");
const workflow = @import("../../domain/workflow.zig");
const compilation = @import("../../domain/workflow_compilation.zig");

pub const Error = error{ProviderModelBindingInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "resolve-provider-model-binding@1",
        .kind = .action,
        .requires = &.{ .selected_compiled_workflow, .llm_provider_registry, .repository_model_allowlist },
        .produces = &.{.validated_provider_model_binding},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        graph: *const compilation.CompiledWorkflow,
        step_id: workflow.WorkflowStepId,
        registry: *const provider_registry.ValidatedLLMProviderRegistry,
        allowlist: *const repository_allowlist.ValidatedRepositoryModelAllowlist,
    ) Error!binding.ValidatedProviderModelBinding {
        const step = findStep(graph.authority.steps, step_id) orelse return invalid();
        if (!@import("../../domain/workflow_model.zig").validProjection(step.*)) return invalid();

        var selected_slot: ?identity.ModelSlotId = null;
        for (step.parameters) |parameter| {
            if (parameter.value != .model_slot) continue;
            if (selected_slot != null) return invalid();
            selected_slot = parameter.value.model_slot;
        }
        const slot_id = selected_slot orelse return invalid();
        const allowed = allowlist.resolveSlot(slot_id) orelse return invalid();
        const entry = registry.resolveId(allowed.registry_entry_id) orelse return invalid();
        const required = step.model orelse return invalid();
        const supported = entry.capabilities;
        if (!supported.supports(required.response_mode, required.controls)) return invalid();
        const capacity = @import("../../domain/model_limits.zig").Capacity.intersect(
            required.capacity,
            supported.capacity,
        ) orelse return invalid();
        if (!contracts.supportsReasoningEffort(
            entry.supported_reasoning_efforts,
            allowed.reasoning_effort,
        )) return invalid();

        return .{
            .operation_id = .{
                .workflow_id = graph.authority.workflow_id,
                .workflow_version = graph.authority.workflow_version,
                .workflow_step_id = step.id,
            },
            .slot_id = allowed.slot_id,
            .registry_entry = entry,
            .reasoning_effort = allowed.reasoning_effort,
            .capacity = capacity,
            .response_mode = required.response_mode,
            .controls = required.controls,
        };
    }
};

fn findStep(
    steps: []const compilation.CompiledStep,
    expected: workflow.WorkflowStepId,
) ?*const compilation.CompiledStep {
    var found: ?*const compilation.CompiledStep = null;
    for (steps) |*step| {
        if (!std.mem.eql(u8, step.id.bytes, expected.bytes)) continue;
        if (found != null) return null;
        found = step;
    }
    return found;
}

fn invalid() Error {
    return error.ProviderModelBindingInvalid;
}
