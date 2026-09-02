const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const definition = @import("../../domain/workflow_definition.zig");
const inventory = @import("../../domain/workflow_inventory.zig");

pub const Error = error{WorkflowAuthorityInventoryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-workflow-authority-entry-accounts@1",
        .kind = .action,
        .requires = &.{.normalized_workflow_authority_entries},
        .produces = &.{.workflow_authority_entry_accounts},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        descriptors: []const inventory.InventoryDescriptor,
    ) Error!inventory.AccountSet {
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
        return .{
            .accounts = accounts,
            .definition_ordinals = definition_ordinals.toOwnedSlice(allocator) catch {
                return error.WorkflowAuthorityInventoryInvalid;
            },
        };
    }
};
