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
