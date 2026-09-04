const std = @import("std");
const compilation = @import("../../domain/workflow_compilation.zig");
const execution = @import("../../domain/workflow_execution.zig");
const pipeline = @import("../../domain/pipeline.zig");
const requirement = @import("../../domain/model_provider_requirement.zig");
const telemetry = @import("../../domain/telemetry.zig");
const workflow = @import("../../domain/workflow.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "derive-provider-requirement@1",
        .kind = .action,
        .requires = &.{.selected_compiled_workflow},
        .produces = &.{.model_provider_requirement},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        selected: *const execution.SelectedWorkflow,
    ) requirement.Requirement {
        for (selected.graph.authority.steps) |step| {
            for (step.capabilities) |capability| {
                if (std.mem.eql(u8, capability, requirement.capability_id)) {
                    return .required;
                }
            }
        }
        return .not_required;
    }
};

test "derives only the exact compiler-owned model-provider capability" {
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
        .operation_id = workflow.RegisteredRef.parse("test.operation@1").?,
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
            .invocation_operation_id = workflow.RegisteredRef.parse("test.empty@1").?,
            .policy_profile_id = workflow.RegisteredRef.parse("test.safe@1").?,
            .total_model_token_budget = .{ .value = 1000 },
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
    return (Action{}).execute(&selected);
}
