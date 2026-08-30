const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow_registry.zig");

pub const Error = error{WorkflowRegistryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-workflow-definition-registry@1",
        .kind = .action,
        .requires = &.{.workflow_definition_registry_candidate},
        .produces = &.{.workflow_definition_registry},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        candidate: workflow.RegistryCandidate,
    ) Error!*workflow.Owner {
        return workflow.createValidated(allocator, candidate) catch error.WorkflowRegistryInvalid;
    }
};
