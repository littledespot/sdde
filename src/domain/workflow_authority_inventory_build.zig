const std = @import("std");
const bootstrap_root_registry = @import("bootstrap_root_registry.zig");
const definition = @import("workflow_definition.zig");
const inventory = @import("workflow_inventory.zig");

pub const Error = error{WorkflowAuthorityInventoryInvalid};

/// An inventory that `validate` accepted. Later startup steps require this wrapper, so a candidate
/// inventory cannot reach them: the candidate and the validated inventory are otherwise one type.
pub const ValidatedInventory = struct { value: inventory.Inventory };

pub fn buildLayout(registry: *const bootstrap_root_registry.BootstrapRootRegistry) inventory.Layout {
    return .{ .capability = registry.workflowAuthority() };
}

pub fn normalizeEntries(descriptors: []inventory.InventoryDescriptor) Error![]inventory.InventoryDescriptor {
    for (descriptors) |descriptor| {
        if (!inventory.validPath(descriptor.path) or inventory.reservedAlias(descriptor.path)) {
            return error.WorkflowAuthorityInventoryInvalid;
        }
    }
    std.mem.sort(inventory.InventoryDescriptor, descriptors, {}, lessThan);
    return descriptors;
}

pub fn buildAccounts(
    allocator: std.mem.Allocator,
    descriptors: []const inventory.InventoryDescriptor,
) Error!inventory.AccountSet {
    const accounts = allocator.alloc(inventory.InventoryAccount, descriptors.len) catch {
        return error.WorkflowAuthorityInventoryInvalid;
    };
    var definition_ordinals: std.ArrayList(u16) = .empty;
    var resource_ordinals: std.ArrayList(u16) = .empty;
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
        } else if (disposition == .resource) {
            resource_ordinals.append(allocator, ordinal) catch {
                return error.WorkflowAuthorityInventoryInvalid;
            };
        }
    }
    return .{
        .accounts = accounts,
        .definition_ordinals = definition_ordinals.toOwnedSlice(allocator) catch {
            return error.WorkflowAuthorityInventoryInvalid;
        },
        .resource_ordinals = resource_ordinals.toOwnedSlice(allocator) catch {
            return error.WorkflowAuthorityInventoryInvalid;
        },
    };
}

pub fn buildInventory(
    layout: inventory.Layout,
    descriptors: []const inventory.InventoryDescriptor,
    accounts: inventory.AccountSet,
) inventory.Inventory {
    return .{
        .capability = layout.capability,
        .descriptors = descriptors,
        .accounts = accounts.accounts,
        .definition_ordinals = accounts.definition_ordinals,
        .resource_ordinals = accounts.resource_ordinals,
    };
}

pub fn validate(candidate: inventory.Inventory) Error!ValidatedInventory {
    inventory.validate(candidate) catch return error.WorkflowAuthorityInventoryInvalid;
    return .{ .value = candidate };
}

fn lessThan(_: void, left: inventory.InventoryDescriptor, right: inventory.InventoryDescriptor) bool {
    return std.mem.order(u8, left.path, right.path) == .lt;
}
