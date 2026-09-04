const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const operations = @import("../ports/workflow_operation_registry.zig");

const empty_invocation_id = "core.empty-invocation@1";
const noop_id = "core.noop@1";
const capability_free_policy_id = "core.capability-free@1";

const entries = [_]operations.Entry{
    .{
        .contract = .{
            .id = empty_invocation_id,
            .kind = .invocation,
            .produces = &.{},
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .invoke_fn = emptyInvocation,
    },
    .{
        .contract = .{
            .id = noop_id,
            .kind = .step,
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .invoke_fn = noop,
    },
};

pub const registry: operations.Registry = .{
    .operations = &entries,
    .policies = &.{.{
        .id = capability_free_policy_id,
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{ .ok, .needs_user, .invalid, .blocked, .failed, .cancelled },
        .total_model_token_budget = .{ .value = 100_000 },
    }},
    .gates = &.{},
    .capabilities = &.{},
};

fn emptyInvocation(_: ?*anyopaque, input: operations.Input) operations.Error!execution.Candidate {
    const invocation = switch (input) {
        .invocation => |value| value,
        .step => return error.OperationExecutionFailed,
    };
    if (invocation.arguments.len != 0) return error.OperationExecutionFailed;
    const contract: pipeline.NodeContract = .{
        .id = empty_invocation_id,
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
    };
    return .{ .outcome = .ok, .delta = pipeline.NodeDelta.successful(contract) };
}

fn noop(_: ?*anyopaque, input: operations.Input) operations.Error!execution.Candidate {
    const step_input = switch (input) {
        .step => |value| value,
        .invocation => return error.OperationExecutionFailed,
    };
    const step = step_input.step;
    const contract: pipeline.NodeContract = .{
        .id = step.operation_id.bytes,
        .kind = .action,
        .requires = step.requires,
        .produces = step.produces,
        .replaces = step.replaces,
        .invalidates = step.invalidates,
        .side_effect = step.side_effect,
    };
    return .{ .outcome = .ok, .delta = pipeline.NodeDelta.successful(contract) };
}
