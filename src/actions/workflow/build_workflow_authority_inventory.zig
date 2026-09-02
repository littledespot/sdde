const pipeline = @import("../../domain/pipeline.zig");
const inventory = @import("../../domain/workflow_inventory.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-workflow-authority-inventory@1",
        .kind = .action,
        .requires = &.{ .workflow_authority_layout, .normalized_workflow_authority_entries, .workflow_authority_entry_accounts },
        .produces = &.{.workflow_authority_inventory_candidate},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        layout: inventory.Layout,
        descriptors: []const inventory.InventoryDescriptor,
        accounts: inventory.AccountSet,
    ) inventory.Inventory {
        return .{
            .capability = layout.capability,
            .descriptors = descriptors,
            .accounts = accounts.accounts,
            .definition_ordinals = accounts.definition_ordinals,
        };
    }
};
