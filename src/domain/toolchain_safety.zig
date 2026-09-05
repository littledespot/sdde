const std = @import("std");
const toolchain = @import("toolchain.zig");

pub const ValidToolchain = opaque {
    pub fn packages(self: *const ValidToolchain) []const []const u8 {
        return validStorage(self).packages;
    }

    pub fn policies(self: *const ValidToolchain) []const toolchain.PolicyContract {
        return validStorage(self).policies;
    }
};

const ValidToolchainStorage = struct {
    packages: []const []const u8,
    policies: []const toolchain.PolicyContract,
};

pub const Owner = opaque {};
const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    value: ValidToolchainStorage,
};

pub fn validate(
    backing_allocator: std.mem.Allocator,
    composed: toolchain.Composed,
    registry: toolchain.PolicyRegistry,
) toolchain.Error!*Owner {
    for (registry.contracts, 0..) |contract, index| for (registry.contracts[0..index]) |prior| {
        if (std.mem.eql(u8, contract.id, prior.id)) return error.InvalidToolchain;
    };
    const owner = backing_allocator.create(OwnerStorage) catch return error.InvalidToolchain;
    errdefer backing_allocator.destroy(owner);
    owner.* = .{ .backing_allocator = backing_allocator, .arena = .init(backing_allocator), .value = undefined };
    errdefer owner.arena.deinit();
    const allocator = owner.arena.allocator();
    const packages = allocator.alloc([]const u8, composed.packages.len) catch return error.InvalidToolchain;
    for (composed.packages, packages) |package, *copy| copy.* = allocator.dupe(u8, package) catch return error.InvalidToolchain;
    var selected: std.ArrayList(*const toolchain.PolicyContract) = .empty;
    for (registry.contracts) |*contract| if (contract.locked_required) try appendPolicy(allocator, &selected, contract);
    for (composed.policies) |id| {
        const contract = findPolicy(registry, id) orelse return error.InvalidToolchain;
        if (!contract.project_selectable) return error.InvalidToolchain;
        try appendPolicy(allocator, &selected, contract);
    }
    const policies = allocator.alloc(toolchain.PolicyContract, selected.items.len) catch return error.InvalidToolchain;
    for (selected.items, policies) |contract, *copy| copy.* = .{
        .id = allocator.dupe(u8, contract.id) catch return error.InvalidToolchain,
        .project_selectable = contract.project_selectable,
        .locked_required = contract.locked_required,
    };
    owner.value = .{ .packages = packages, .policies = policies };
    return @ptrCast(owner);
}

pub fn value(owner: *const Owner) *const ValidToolchain {
    return @ptrCast(&ownerStorageConst(owner).value);
}

pub fn retainedBytes(owner: *const Owner) usize {
    const storage = ownerStorageConst(owner);
    return @sizeOf(OwnerStorage) + storage.arena.queryCapacity();
}

pub fn deinitOwner(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

fn findPolicy(registry: toolchain.PolicyRegistry, id: []const u8) ?*const toolchain.PolicyContract {
    for (registry.contracts) |*contract| if (std.mem.eql(u8, contract.id, id)) return contract;
    return null;
}

fn appendPolicy(
    allocator: std.mem.Allocator,
    list: *std.ArrayList(*const toolchain.PolicyContract),
    contract: *const toolchain.PolicyContract,
) toolchain.Error!void {
    for (list.items) |present| if (std.mem.eql(u8, present.id, contract.id)) return;
    list.append(allocator, contract) catch return error.InvalidToolchain;
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn validStorage(valid: *const ValidToolchain) *const ValidToolchainStorage {
    return @ptrCast(@alignCast(valid));
}

test "safety injects locked policy and owns immutable result" {
    const registry: toolchain.PolicyRegistry = .{ .contracts = &.{
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
        .{ .id = "project.zig@1", .project_selectable = true, .locked_required = false },
    } };
    const owner = try validate(std.testing.allocator, .{ .packages = &.{"zig@0.16.0"}, .policies = &.{"project.zig@1"} }, registry);
    defer deinitOwner(owner);
    try std.testing.expectEqualStrings("zig@0.16.0", value(owner).packages()[0]);
    try std.testing.expectEqualStrings("core.safety@1", value(owner).policies()[0].id);
}

test "safety rejects unknown nonselectable and duplicate policy authority" {
    const registry: toolchain.PolicyRegistry = .{ .contracts = &.{
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
    } };
    try std.testing.expectError(error.InvalidToolchain, validate(std.testing.allocator, .{ .packages = &.{}, .policies = &.{"unknown@1"} }, registry));
    try std.testing.expectError(error.InvalidToolchain, validate(std.testing.allocator, .{ .packages = &.{}, .policies = &.{"core.safety@1"} }, registry));

    const duplicate: toolchain.PolicyRegistry = .{ .contracts = &.{
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
        .{ .id = "core.safety@1", .project_selectable = false, .locked_required = true },
    } };
    try std.testing.expectError(error.InvalidToolchain, validate(std.testing.allocator, .{ .packages = &.{}, .policies = &.{} }, duplicate));
}
