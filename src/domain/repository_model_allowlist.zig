const std = @import("std");
const config = @import("config.zig");
const contracts = @import("llm_provider_contracts.zig");
const identity = @import("llm_provider_identity.zig");
const registry_contract = @import("llm_provider_registry.zig");

pub const Entry = struct {
    slot_id: identity.ModelSlotId,
    registry_entry_id: registry_contract.RegistryEntryId,
    reasoning_effort: ?[]const u8,
};

pub const ValidatedRepositoryModelAllowlist = opaque {
    pub fn count(self: *const ValidatedRepositoryModelAllowlist) usize {
        return storage(self).entries.len;
    }

    pub fn resolveSlot(
        self: *const ValidatedRepositoryModelAllowlist,
        slot_id: identity.ModelSlotId,
    ) ?*const Entry {
        for (storage(self).entries) |*entry| {
            if (entry.slot_id.eql(slot_id)) return entry;
        }
        return null;
    }
};

pub const Owner = opaque {};

const AllowlistStorage = struct {
    entries: []const Entry,
};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    allowlist: AllowlistStorage,
};

pub const Error = error{InvalidRepositoryModelAllowlist};

pub fn createValidated(
    allocator: std.mem.Allocator,
    models: *const config.ModelsConfig,
    registry: *const registry_contract.ValidatedLLMProviderRegistry,
) Error!*Owner {
    const owner = allocator.create(OwnerStorage) catch {
        return error.InvalidRepositoryModelAllowlist;
    };
    errdefer allocator.destroy(owner);
    owner.* = .{
        .backing_allocator = allocator,
        .arena = .init(allocator),
        .allowlist = undefined,
    };
    errdefer owner.arena.deinit();

    const keys = models.slots.map.keys();
    const values = models.slots.map.values();
    const entries = owner.arena.allocator().alloc(Entry, keys.len) catch {
        return error.InvalidRepositoryModelAllowlist;
    };
    for (entries, keys, values) |*destination, slot_name, selected| {
        const slot_id = identity.ModelSlotId.parse(slot_name) orelse {
            return error.InvalidRepositoryModelAllowlist;
        };
        const provider = identity.ProviderId.parse(selected.provider) orelse {
            return error.InvalidRepositoryModelAllowlist;
        };
        const model = identity.ModelId.parse(selected.model) orelse {
            return error.InvalidRepositoryModelAllowlist;
        };
        const catalogue_entry = registry.resolve(provider, model) orelse {
            return error.InvalidRepositoryModelAllowlist;
        };
        if (!contracts.supportsReasoningEffort(
            catalogue_entry.supported_reasoning_efforts,
            selected.reasoningEffort,
        )) return error.InvalidRepositoryModelAllowlist;

        destination.* = .{
            .slot_id = .{ .bytes = owner.arena.allocator().dupe(u8, slot_id.bytes) catch {
                return error.InvalidRepositoryModelAllowlist;
            } },
            .registry_entry_id = catalogue_entry.id,
            .reasoning_effort = if (selected.reasoningEffort) |effort|
                owner.arena.allocator().dupe(u8, effort) catch {
                    return error.InvalidRepositoryModelAllowlist;
                }
            else
                null,
        };
    }
    std.mem.sort(Entry, entries, {}, lessThan);
    owner.allowlist = .{ .entries = entries };
    return @ptrCast(owner);
}

pub fn allowlist(owner: *const Owner) *const ValidatedRepositoryModelAllowlist {
    return @ptrCast(&ownerStorageConst(owner).allowlist);
}

pub fn deinitOwner(owner: *Owner) void {
    const value = ownerStorage(owner);
    const allocator = value.backing_allocator;
    value.arena.deinit();
    allocator.destroy(value);
}

fn lessThan(_: void, left: Entry, right: Entry) bool {
    return std.mem.order(u8, left.slot_id.bytes, right.slot_id.bytes) == .lt;
}

fn storage(value: *const ValidatedRepositoryModelAllowlist) *const AllowlistStorage {
    return @ptrCast(@alignCast(value));
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
