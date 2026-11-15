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

const file_identity = @import("filesystem_identity.zig");

fn testFile(path: []const u8, file_id: u64) inventory.InventoryDescriptor {
    return .{ .path = path, .kind = .file, .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = file_id }, .size = 3 };
}

test "entries are portable relative paths, sorted by path" {
    var entries = [_]inventory.InventoryDescriptor{ testFile("prompts/b.md", 2), testFile("a.workflow.yaml", 1) };
    const sorted = try normalizeEntries(&entries);
    try std.testing.expectEqualStrings("a.workflow.yaml", sorted[0].path);
    try std.testing.expectEqualStrings("prompts/b.md", sorted[1].path);
    for ([_][]const u8{ "../escape.md", "/absolute.md", "a//b.md", "a\\b.md", "" }) |path| {
        var rejected = [_]inventory.InventoryDescriptor{testFile(path, 3)};
        try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, normalizeEntries(&rejected));
    }
}

test "accounts classify definitions and resources, and reject an unclassifiable entry or too many definitions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const entries = [_]inventory.InventoryDescriptor{ testFile("a.workflow.yaml", 1), testFile("prompts/b.md", 2) };
    const accounts = try buildAccounts(arena.allocator(), &entries);
    try std.testing.expectEqualSlices(u16, &.{1}, accounts.definition_ordinals);
    try std.testing.expectEqualSlices(u16, &.{2}, accounts.resource_ordinals);

    const unidentified = [_]inventory.InventoryDescriptor{.{ .path = "a.md", .kind = .file, .identity = null, .size = 3 }};
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, buildAccounts(arena.allocator(), &unidentified));

    const many = try arena.allocator().alloc(inventory.InventoryDescriptor, definition.max_definitions + 1);
    for (many, 0..) |*entry, index| {
        const name = try std.fmt.allocPrint(arena.allocator(), "w{d}.workflow.yaml", .{index});
        entry.* = testFile(name, index + 1);
    }
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, buildAccounts(arena.allocator(), many));
}

test "a validated inventory is a distinct wrapper that only validation produces, and it rejects inconsistent accounts" {
    try std.testing.expect(ValidatedInventory != inventory.Inventory);
    const entries = [_]inventory.InventoryDescriptor{testFile("a.workflow.yaml", 1)};
    const accounts = [_]inventory.InventoryAccount{.{ .ordinal = 1, .path = "a.workflow.yaml", .disposition = .definition }};
    const candidate: inventory.Inventory = .{
        .capability = undefined,
        .descriptors = &entries,
        .accounts = &accounts,
        .definition_ordinals = &.{1},
        .resource_ordinals = &.{},
    };
    const validated = try validate(candidate);
    try std.testing.expectEqualStrings("a.workflow.yaml", validated.value.descriptors[0].path);

    var mismatched = candidate;
    mismatched.accounts = &.{};
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, validate(mismatched));
}
