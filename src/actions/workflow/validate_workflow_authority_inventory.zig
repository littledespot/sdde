const pipeline = @import("../../domain/pipeline.zig");
const inventory = @import("../../domain/workflow_inventory.zig");

pub const Error = error{WorkflowAuthorityInventoryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-workflow-authority-inventory@1",
        .kind = .action,
        .requires = &.{.workflow_authority_inventory_candidate},
        .produces = &.{.workflow_authority_inventory},
        .side_effect = .none,
    };

    pub fn execute(_: Action, candidate: inventory.Inventory) Error!inventory.Inventory {
        inventory.validate(candidate) catch return error.WorkflowAuthorityInventoryInvalid;
        return candidate;
    }
};
