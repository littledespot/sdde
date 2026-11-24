const std = @import("std");
const contracts = @import("../../domain/llm_provider_contracts.zig");
const operation = @import("../../domain/llm_provider_operation.zig");

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

/// The one rule for a key's bytes: why they cannot be used, or null when they can. Unset and empty
/// are `missing`; a space, control or non-ASCII byte (such as a CR from CRLF line endings) is
/// `malformed`. Only the class is reported, never a byte or a length.
pub fn defect(raw: ?[]const u8) ?operation.ProviderCredentialDiagnostic {
    const value = raw orelse return .missing;
    if (value.len == 0) return .missing;
    for (value) |byte| if (byte <= 32 or byte >= 127) return .malformed;
    return null;
}

/// One owned, validated copy of a key, zeroed on release.
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn capture(allocator: std.mem.Allocator, raw: ?[]const u8) std.mem.Allocator.Error!?Snapshot {
        if (defect(raw) != null) return null;
        return .{ .allocator = allocator, .bytes = try allocator.dupe(u8, raw.?) };
    }

    pub fn deinit(self: *Snapshot) void {
        std.crypto.secureZero(u8, self.bytes);
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const Material = union(enum) {
    /// No key was supplied: unset or empty.
    unavailable,
    /// A key was supplied but its bytes are unusable.
    malformed,
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
