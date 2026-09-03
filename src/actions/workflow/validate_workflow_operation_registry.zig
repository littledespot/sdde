const pipeline = @import("../../domain/pipeline.zig");
const operations = @import("../../ports/workflow_operation_registry.zig");

pub const Error = error{WorkflowOperationRegistryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-workflow-operation-registry@1",
        .kind = .action,
        .requires = &.{.workflow_operation_registry},
        .produces = &.{.workflow_operation_registry_evidence},
        .side_effect = .none,
    };

    pub fn execute(_: Action, registry: *const operations.Registry) Error!void {
        if (!registry.validate()) return error.WorkflowOperationRegistryInvalid;
    }
};

test "rejects a duplicate operation identity" {
    const execution = @import("../../domain/workflow_execution.zig");
    const std = @import("std");
    const entry: operations.Entry = .{
        .contract = .{ .id = "test.noop@1", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none },
        .invoke_fn = struct {
            fn invoke(_: ?*anyopaque, _: operations.Input) operations.Error!execution.Candidate {
                return error.OperationExecutionFailed;
            }
        }.invoke,
    };
    const registry: operations.Registry = .{
        .operations = &.{ entry, entry },
        .policies = &.{},
        .gates = &.{},
        .capabilities = &.{},
    };
    try std.testing.expectError(error.WorkflowOperationRegistryInvalid, (Action{}).execute(&registry));
}
