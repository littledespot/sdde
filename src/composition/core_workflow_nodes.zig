const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const workflow = @import("../domain/workflow.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const implementation = @import("../ports/workflow_node_implementation.zig");

const empty_invocation_id = "core.empty-invocation@1";
const noop_id = "core.noop@1";
const capability_free_policy_id = "core.capability-free@1";

pub const compiler_registry: compilation.CompilerRegistry = .{
    .invocations = &.{.{
        .id = empty_invocation_id,
        .capability_free = true,
        .produces = &.{},
    }},
    .nodes = &.{.{
        .id = noop_id,
        .parameters = &.{},
        .requires = &.{},
        .produces = &.{},
        .outcomes = &.{.ok},
        .side_effect = .none,
    }},
    .policies = &.{.{
        .id = capability_free_policy_id,
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{ .ok, .needs_user, .invalid, .blocked, .failed, .cancelled },
    }},
    .gates = &.{},
    .capabilities = &.{},
};

pub const registry: implementation.Registry = .{
    .invocations = &.{.{
        .contract_id = empty_invocation_id,
        .invoke_fn = emptyInvocation,
    }},
    .nodes = &.{.{
        .contract_id = noop_id,
        .invoke_fn = noop,
    }},
};

fn emptyInvocation(_: ?*anyopaque, input: implementation.InvocationInput) implementation.Error!execution.Candidate {
    if (input.arguments.len != 0) return error.NodeExecutionFailed;
    const contract: pipeline.NodeContract = .{
        .id = empty_invocation_id,
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
    };
    return .{ .outcome = .ok, .delta = pipeline.NodeDelta.successful(contract) };
}

fn noop(_: ?*anyopaque, input: implementation.NodeInput) implementation.Error!execution.Candidate {
    const contract: pipeline.NodeContract = .{
        .id = input.node.contract_id.bytes,
        .kind = .action,
        .requires = input.node.requires,
        .produces = input.node.produces,
        .replaces = input.node.replaces,
        .invalidates = input.node.invalidates,
        .side_effect = input.node.side_effect,
    };
    return .{ .outcome = .ok, .delta = pipeline.NodeDelta.successful(contract) };
}
