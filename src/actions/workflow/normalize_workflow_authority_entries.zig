const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const inventory = @import("../../domain/workflow_inventory.zig");

pub const Error = error{WorkflowAuthorityInventoryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "normalize-workflow-authority-entries@1",
        .kind = .action,
        .requires = &.{.raw_workflow_authority_entries},
        .produces = &.{.normalized_workflow_authority_entries},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        descriptors: []inventory.InventoryDescriptor,
    ) Error![]inventory.InventoryDescriptor {
        for (descriptors) |descriptor| {
            if (!inventory.validPath(descriptor.path) or inventory.reservedAlias(descriptor.path)) {
                return error.WorkflowAuthorityInventoryInvalid;
            }
        }
        std.mem.sort(inventory.InventoryDescriptor, descriptors, {}, lessThan);
        return descriptors;
    }
};

fn lessThan(_: void, left: inventory.InventoryDescriptor, right: inventory.InventoryDescriptor) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}
