const std = @import("std");
const compilation = @import("workflow_compilation.zig");
const execution = @import("workflow_execution.zig");
const requirement = @import("model_provider_requirement.zig");
const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");

/// Whether the selected compiled workflow needs provider bootstrap: any step with a model binding
/// or the exact provider-call capability. Workflow names never matter.
pub fn derive(selected: *const execution.SelectedWorkflow) requirement.Requirement {
    for (selected.graph.authority.steps) |step| {
        if (step.model != null) return .required;
        for (step.capabilities) |capability| {
            if (std.mem.eql(u8, capability, requirement.capability_id)) {
                return .required;
            }
        }
    }
    return .not_required;
}

test "provider-call requirement uses the exact capability and ignores workflow names" {
    try std.testing.expectEqual(
        requirement.Requirement.required,
        deriveFor("arbitrary-flow", &.{requirement.capability_id}),
    );
    try std.testing.expectEqual(
        requirement.Requirement.not_required,
        deriveFor("arbitrary-flow", &.{}),
    );
    try std.testing.expectEqual(
        requirement.Requirement.not_required,
        deriveFor("arbitrary-flow", &.{"model-provider-extra"}),
    );
    try std.testing.expectEqual(
        requirement.Requirement.not_required,
        deriveFor("model-provider", &.{"project-read"}),
    );
}

fn deriveFor(workflow_id: []const u8, capabilities: []const []const u8) requirement.Requirement {
    const step: compilation.CompiledStep = .{
        .id = workflow.WorkflowStepId.parse("run").?,
        .operation_id = workflow.OperationId.parse("test.operation").?,
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
        .gates = &.{},
        .capabilities = capabilities,
        .retry_authority = null,
    };
    const transition: workflow.Transition = .{
        .from = step.id,
        .outcome = .ok,
        .target = .{ .terminal = .ok },
    };
    const graph: compilation.CompiledWorkflow = .{
        .source_ordinal = 1,
        .shortcode = telemetry.WorkflowShortcode.parse("TEST") catch unreachable,
        .authority = .{
            .workflow_id = workflow.WorkflowId.parse(workflow_id).?,
            .workflow_version = 1,
            .invocation_operation_id = workflow.OperationId.parse("test.empty").?,
            .policy_profile_id = workflow.RegisteredRef.parse("test.safe@1").?,
            .start_step_id = step.id,
            .invocation_outputs = &.{},
            .resources = &.{},
            .steps = &.{step},
            .transitions = &.{transition},
            .maximum_step_executions = 1,
        },
    };
    const selected: execution.SelectedWorkflow = .{
        .invocation = .{
            .workflow_id = graph.authority.workflow_id,
            .arguments = &.{},
        },
        .graph = &graph,
    };
    return derive(&selected);
}
