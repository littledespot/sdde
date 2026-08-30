const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const definition = @import("../../domain/workflow_definition.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
const source_port = @import("../../ports/workflow_authority_source.zig");

pub const Error = error{ Cancelled, WorkflowAuthorityInventoryInvalid };

pub const Action = struct {
    source: source_port.Source,

    pub const contract: pipeline.NodeContract = .{
        .id = "inventory-workflow-authority@1",
        .kind = .action,
        .requires = &.{.workflow_authority_layout},
        .produces = &.{.workflow_authority_inventory},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        layout: inventory.Layout,
        runtime: pipeline.NodeRuntime,
    ) Error!inventory.Inventory {
        const descriptors = self.source.enumerate(layout.capability, allocator, runtime) catch |failure| {
            return switch (failure) {
                error.Cancelled => error.Cancelled,
                else => error.WorkflowAuthorityInventoryInvalid,
            };
        };
        if (descriptors.len > inventory.max_inventory_entries) {
            return error.WorkflowAuthorityInventoryInvalid;
        }
        std.mem.sort(inventory.InventoryDescriptor, descriptors, {}, lessThan);
        const accounts = allocator.alloc(inventory.InventoryAccount, descriptors.len) catch {
            return error.WorkflowAuthorityInventoryInvalid;
        };
        var definition_ordinals: std.ArrayList(u16) = .empty;
        for (descriptors, 0..) |descriptor, index| {
            const disposition = inventory.classifyInventoryDescriptor(descriptor) orelse {
                return error.WorkflowAuthorityInventoryInvalid;
            };
            const ordinal: u16 = @intCast(index + 1);
            accounts[index] = .{ .ordinal = ordinal, .path = descriptor.path, .disposition = disposition };
            if (disposition == .definition) {
                if (definition_ordinals.items.len == definition.max_definitions) {
                    return error.WorkflowAuthorityInventoryInvalid;
                }
                definition_ordinals.append(allocator, ordinal) catch {
                    return error.WorkflowAuthorityInventoryInvalid;
                };
            }
        }
        const result: inventory.Inventory = .{
            .capability = layout.capability,
            .descriptors = descriptors,
            .accounts = accounts,
            .definition_ordinals = definition_ordinals.toOwnedSlice(allocator) catch {
                return error.WorkflowAuthorityInventoryInvalid;
            },
        };
        inventory.validate(result) catch return error.WorkflowAuthorityInventoryInvalid;
        return result;
    }
};

fn lessThan(_: void, left: inventory.InventoryDescriptor, right: inventory.InventoryDescriptor) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}

test "inventory classification is generic and excludes only reserved authority children" {
    const identity: @import("../../domain/filesystem_identity.zig").FileIdentity = .{ .filesystem_id = 1, .file_id = 2 };
    try std.testing.expectEqual(inventory.Disposition.reserved_child, inventory.classifyInventoryDescriptor(.{ .path = "features", .kind = .directory, .identity = identity }).?);
    try std.testing.expectEqual(inventory.Disposition.reserved_child, inventory.classifyInventoryDescriptor(.{ .path = "transactions", .kind = .directory, .identity = identity }).?);
    try std.testing.expectEqual(inventory.Disposition.definition, inventory.classifyInventoryDescriptor(.{ .path = "future/audit.workflow.yaml", .kind = .file, .identity = identity, .size = 1 }).?);
    try std.testing.expect(inventory.classifyInventoryDescriptor(.{ .path = "notes.txt", .kind = .file, .identity = identity, .size = 1 }) == null);
    try std.testing.expect(inventory.classifyInventoryDescriptor(.{ .path = "linked.workflow.yaml", .kind = .symlink }) == null);
}
