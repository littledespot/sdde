const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
const source_port = @import("../../ports/workflow_authority_source.zig");

pub const Error = error{ Cancelled, WorkflowAuthorityInventoryInvalid };

pub const Action = struct {
    source: source_port.Enumerator,

    pub const contract: pipeline.NodeContract = .{
        .id = "enumerate-workflow-authority-resources@1",
        .kind = .action,
        .requires = &.{.workflow_authority_layout},
        .produces = &.{.raw_workflow_authority_entries},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        layout: inventory.Layout,
        runtime: pipeline.NodeRuntime,
    ) Error![]inventory.InventoryDescriptor {
        const descriptors = self.source.enumerate(layout.capability, allocator, runtime) catch |failure| {
            return switch (failure) {
                error.Cancelled => error.Cancelled,
                else => error.WorkflowAuthorityInventoryInvalid,
            };
        };
        if (descriptors.len > inventory.max_inventory_entries) {
            return error.WorkflowAuthorityInventoryInvalid;
        }
        return descriptors;
    }
};
