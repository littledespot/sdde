const std = @import("std");
const contracts = @import("../../domain/llm_provider_contracts.zig");

/// Provider families that authenticate with one API key (ADR 0028).
pub const Family = enum {
    aws_bedrock,
    anthropic,

    /// The family whose key a validated catalogue configuration needs, if any.
    pub fn of(config: contracts.ValidatedProviderConfig) ?Family {
        return switch (config) {
            .aws_bedrock => .aws_bedrock,
            .anthropic => .anthropic,
            .deadline_only => null,
        };
    }

    pub fn configSchema(self: Family) contracts.ProviderConfigSchema {
        return switch (self) {
            .aws_bedrock => .aws_bedrock,
            .anthropic => .anthropic,
        };
    }
};

/// Keys a harness supplies directly, one optional snapshot per family.
pub const Supplied = std.EnumArray(Family, ?Snapshot);

/// One owned, validated copy of a key, zeroed on release.
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn capture(allocator: std.mem.Allocator, raw: ?[]const u8) std.mem.Allocator.Error!?Snapshot {
        const value = raw orelse return null;
        if (value.len == 0) return null;
        for (value) |byte| if (byte <= 32 or byte >= 127) return null;
        return .{ .allocator = allocator, .bytes = try allocator.dupe(u8, value) };
    }

    pub fn deinit(self: *Snapshot) void {
        std.crypto.secureZero(u8, self.bytes);
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const Material = union(enum) {
    unavailable,
    allocation_failed,
    ready: Snapshot,

    pub fn deinit(self: *Material) void {
        if (self.* == .ready) self.ready.deinit();
        self.* = .unavailable;
    }
};

/// One material slot per family; an unread family stays unavailable.
pub const Materials = struct {
    values: std.EnumArray(Family, Material) = .initFill(.unavailable),

    pub fn set(self: *Materials, family: Family, material: Material) void {
        self.values.getPtr(family).deinit();
        self.values.set(family, material);
    }

    pub fn get(self: *Materials, family: Family) *Material {
        return self.values.getPtr(family);
    }

    pub fn deinit(self: *Materials) void {
        for (std.enums.values(Family)) |family| self.values.getPtr(family).deinit();
    }
};
