const std = @import("std");
const contracts = @import("llm_provider_contracts.zig");
const config_schema = @import("llm_provider_config_schema.zig");
const document = @import("llm_provider_document.zig");
const identity = @import("llm_provider_identity.zig");

pub const RegistryEntryId = struct {
    ordinal: u16,

    pub fn eql(left: RegistryEntryId, right: RegistryEntryId) bool {
        return left.ordinal == right.ordinal;
    }
};

pub const CandidateEntry = struct {
    provider: identity.ProviderId,
    model: identity.ModelId,
    implementation_id: contracts.RegisteredProviderImplementationId,
    config: contracts.ValidatedProviderConfig,
    capabilities: @import("model_capabilities.zig").Capabilities,
    supported_reasoning_efforts: []const []const u8,
};

pub const Candidate = struct {
    allocator: std.mem.Allocator,
    entries: []CandidateEntry,

    pub fn init(allocator: std.mem.Allocator, count: usize) Error!Candidate {
        return .{
            .allocator = allocator,
            .entries = allocator.alloc(CandidateEntry, count) catch {
                return error.InvalidLLMProviderRegistry;
            },
        };
    }

    pub fn deinit(self: *Candidate) void {
        self.allocator.free(self.entries);
        self.* = undefined;
    }
};

pub const Entry = struct {
    id: RegistryEntryId,
    provider: identity.ProviderId,
    model: identity.ModelId,
    implementation_id: contracts.RegisteredProviderImplementationId,
    config: contracts.ValidatedProviderConfig,
    capabilities: @import("model_capabilities.zig").Capabilities,
    supported_reasoning_efforts: []const []const u8,
};

pub const ValidatedLLMProviderRegistry = opaque {
    pub fn count(self: *const ValidatedLLMProviderRegistry) usize {
        return storage(self).entries.len;
    }

    pub fn resolve(
        self: *const ValidatedLLMProviderRegistry,
        provider: identity.ProviderId,
        model: identity.ModelId,
    ) ?*const Entry {
        for (storage(self).entries) |*entry| {
            if (entry.provider.eql(provider) and entry.model.eql(model)) return entry;
        }
        return null;
    }

    pub fn resolveId(
        self: *const ValidatedLLMProviderRegistry,
        id: RegistryEntryId,
    ) ?*const Entry {
        if (id.ordinal == 0 or id.ordinal > storage(self).entries.len) return null;
        return &storage(self).entries[id.ordinal - 1];
    }
};

pub const Owner = opaque {};

const RegistryStorage = struct {
    entries: []const Entry,
};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    registry: RegistryStorage,
};

pub const Error = error{InvalidLLMProviderRegistry};

pub fn createValidated(
    allocator: std.mem.Allocator,
    candidate: Candidate,
    registered_contracts: contracts.Registry,
) Error!*Owner {
    try validateCandidate(candidate.entries, registered_contracts);

    const owner = allocator.create(OwnerStorage) catch return error.InvalidLLMProviderRegistry;
    errdefer allocator.destroy(owner);
    owner.* = .{
        .backing_allocator = allocator,
        .arena = .init(allocator),
        .registry = undefined,
    };
    errdefer owner.arena.deinit();

    const entries = owner.arena.allocator().alloc(Entry, candidate.entries.len) catch {
        return error.InvalidLLMProviderRegistry;
    };
    for (entries, candidate.entries, 0..) |*destination, source, index| {
        destination.* = .{
            .id = .{ .ordinal = @intCast(index + 1) },
            .provider = .{ .bytes = owner.arena.allocator().dupe(u8, source.provider.bytes) catch {
                return error.InvalidLLMProviderRegistry;
            } },
            .model = .{ .bytes = owner.arena.allocator().dupe(u8, source.model.bytes) catch {
                return error.InvalidLLMProviderRegistry;
            } },
            .implementation_id = source.implementation_id,
            .config = source.config,
            .capabilities = source.capabilities,
            .supported_reasoning_efforts = cloneStrings(
                owner.arena.allocator(),
                source.supported_reasoning_efforts,
            ) catch return error.InvalidLLMProviderRegistry,
        };
    }
    owner.registry = .{ .entries = entries };
    return @ptrCast(owner);
}

pub fn registry(owner: *const Owner) *const ValidatedLLMProviderRegistry {
    return @ptrCast(&ownerStorageConst(owner).registry);
}

pub fn deinitOwner(owner: *Owner) void {
    const value = ownerStorage(owner);
    const allocator = value.backing_allocator;
    value.arena.deinit();
    allocator.destroy(value);
}

pub fn lessThan(_: void, left: CandidateEntry, right: CandidateEntry) bool {
    const provider_order = std.mem.order(u8, left.provider.bytes, right.provider.bytes);
    if (provider_order != .eq) return provider_order == .lt;
    return std.mem.order(u8, left.model.bytes, right.model.bytes) == .lt;
}

fn validateCandidate(
    entries: []const CandidateEntry,
    registered_contracts: contracts.Registry,
) Error!void {
    registered_contracts.validate() catch return error.InvalidLLMProviderRegistry;
    if (entries.len > document.max_models_total) return error.InvalidLLMProviderRegistry;
    for (entries, 0..) |entry, index| {
        if (identity.ProviderId.parse(entry.provider.bytes) == null or
            identity.ModelId.parse(entry.model.bytes) == null or
            contracts.RegisteredProviderImplementationId.init(entry.implementation_id.ordinal) == null or
            entry.supported_reasoning_efforts.len > contracts.max_reasoning_efforts)
        {
            return error.InvalidLLMProviderRegistry;
        }
        const registered = registered_contracts.resolve(entry.provider, entry.model) orelse {
            return error.InvalidLLMProviderRegistry;
        };
        if (!entry.implementation_id.eql(registered.implementation_id) or
            !std.meta.eql(entry.capabilities, registered.capabilities) or
            !config_schema.matches(registered.config_schema, entry.config) or
            !sameStrings(entry.supported_reasoning_efforts, registered.supported_reasoning_efforts))
        {
            return error.InvalidLLMProviderRegistry;
        }
        for (entry.supported_reasoning_efforts, 0..) |effort, effort_index| {
            if (effort.len == 0) return error.InvalidLLMProviderRegistry;
            for (entry.supported_reasoning_efforts[0..effort_index]) |previous| {
                if (std.mem.eql(u8, effort, previous)) return error.InvalidLLMProviderRegistry;
            }
        }
        if (index > 0 and !lessThan({}, entries[index - 1], entry)) {
            return error.InvalidLLMProviderRegistry;
        }
    }
}

fn sameStrings(left: []const []const u8, right: []const []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_value, right_value| {
        if (!std.mem.eql(u8, left_value, right_value)) return false;
    }
    return true;
}

fn cloneStrings(
    allocator: std.mem.Allocator,
    source: []const []const u8,
) ![]const []const u8 {
    const values = try allocator.alloc([]const u8, source.len);
    for (values, source) |*destination, value| {
        destination.* = try allocator.dupe(u8, value);
    }
    return values;
}

fn storage(value: *const ValidatedLLMProviderRegistry) *const RegistryStorage {
    return @ptrCast(@alignCast(value));
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
