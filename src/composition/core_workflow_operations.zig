const execution = @import("../domain/workflow_execution.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const bindings = @import("../application/workflow_operation_binding.zig");

const empty_invocation_id = "core.empty-invocation@1";
const noop_id = "core.noop@1";
const capability_free_policy_id = "core.capability-free@1";

pub const entries = [_]operations.Entry{
    .{
        .contract = .{
            .id = empty_invocation_id,
            .kind = .invocation,
            .produces = &.{},
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .binding = bindings.bind(void, null, emptyInvocation),
    },
    .{
        .contract = .{
            .id = noop_id,
            .kind = .step,
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .binding = bindings.bind(void, null, noop),
    },
};

pub const profiles = [_]@import("../domain/workflow_operation.zig").PolicyProfile{.{
    .id = capability_free_policy_id,
    .allowed_capabilities = &.{},
    .allowed_terminal_outcomes = &.{ .ok, .needs_user, .invalid, .blocked, .failed, .cancelled },
    .total_model_token_budget = .{ .value = 100_000 },
}};

pub const registry: operations.Registry = .{
    .operations = &entries,
    .policies = &profiles,
    .gates = &.{},
};

fn emptyInvocation(_: ?*void, input: operations.Input) operations.Error!execution.Candidate {
    const invocation = switch (input) {
        .invocation => |value| value,
        .step => return error.OperationExecutionFailed,
    };
    if (invocation.arguments.len != 0) return error.OperationExecutionFailed;
    return .{ .outcome = .ok, .delta = .{} };
}

fn noop(_: ?*void, input: operations.Input) operations.Error!execution.Candidate {
    switch (input) {
        .step => {},
        .invocation => return error.OperationExecutionFailed,
    }
    return .{ .outcome = .ok, .delta = .{} };
}
