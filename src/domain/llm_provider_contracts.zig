const std = @import("std");
const identity = @import("llm_provider_identity.zig");

pub const max_contracts: usize = 256;
pub const max_reasoning_efforts: usize = 16;

pub const RegisteredProviderImplementationId = struct {
    ordinal: u16,

    pub fn init(ordinal: u16) ?RegisteredProviderImplementationId {
        if (ordinal == 0) return null;
        return .{ .ordinal = ordinal };
    }

    pub fn eql(
        left: RegisteredProviderImplementationId,
        right: RegisteredProviderImplementationId,
    ) bool {
        return left.ordinal == right.ordinal;
    }
};

pub const ProviderConfigSchema = enum {
    empty_object,
};

pub const ValidatedProviderConfig = union(enum) {
    empty_object,
};

pub const ProviderModelContract = struct {
    provider: identity.ProviderId,
    model: identity.ModelId,
    implementation_id: RegisteredProviderImplementationId,
    config_schema: ProviderConfigSchema,
    supported_reasoning_efforts: []const []const u8 = &.{},
};

pub const Registry = struct {
    entries: []const ProviderModelContract,

    pub const empty: Registry = .{ .entries = &.{} };

    pub fn validate(self: Registry) Error!void {
        if (self.entries.len > max_contracts) return error.InvalidProviderModelContracts;
        for (self.entries, 0..) |entry, index| {
            if (identity.ProviderId.parse(entry.provider.bytes) == null or
                identity.ModelId.parse(entry.model.bytes) == null or
                RegisteredProviderImplementationId.init(entry.implementation_id.ordinal) == null or
                entry.supported_reasoning_efforts.len > max_reasoning_efforts)
            {
                return error.InvalidProviderModelContracts;
            }
            for (entry.supported_reasoning_efforts, 0..) |effort, effort_index| {
                if (effort.len == 0) return error.InvalidProviderModelContracts;
                for (entry.supported_reasoning_efforts[0..effort_index]) |previous| {
                    if (std.mem.eql(u8, effort, previous)) return error.InvalidProviderModelContracts;
                }
            }
            for (self.entries[0..index]) |previous| {
                if (entry.provider.eql(previous.provider) and entry.model.eql(previous.model)) {
                    return error.InvalidProviderModelContracts;
                }
                if (entry.provider.eql(previous.provider) and
                    !entry.implementation_id.eql(previous.implementation_id))
                {
                    return error.InvalidProviderModelContracts;
                }
            }
        }
    }

    pub fn containsProvider(self: Registry, provider: identity.ProviderId) bool {
        for (self.entries) |entry| {
            if (entry.provider.eql(provider)) return true;
        }
        return false;
    }

    pub fn resolve(
        self: Registry,
        provider: identity.ProviderId,
        model: identity.ModelId,
    ) ?*const ProviderModelContract {
        for (self.entries) |*entry| {
            if (entry.provider.eql(provider) and entry.model.eql(model)) return entry;
        }
        return null;
    }
};

pub const Error = error{InvalidProviderModelContracts};

pub fn supportsReasoningEffort(
    supported_values: []const []const u8,
    selected: ?[]const u8,
) bool {
    const value = selected orelse return true;
    for (supported_values) |supported| {
        if (std.mem.eql(u8, value, supported)) return true;
    }
    return false;
}

test "contract registry is exact unique and provider consistent" {
    const provider = identity.ProviderId.parse("compiled-provider").?;
    const first = ProviderModelContract{
        .provider = provider,
        .model = identity.ModelId.parse("model-a").?,
        .implementation_id = RegisteredProviderImplementationId.init(1).?,
        .config_schema = .empty_object,
        .supported_reasoning_efforts = &.{ "low", "high" },
    };
    const second = ProviderModelContract{
        .provider = provider,
        .model = identity.ModelId.parse("model-b").?,
        .implementation_id = RegisteredProviderImplementationId.init(1).?,
        .config_schema = .empty_object,
    };
    const registry: Registry = .{ .entries = &.{ first, second } };
    try registry.validate();
    try std.testing.expect(registry.resolve(provider, first.model) != null);
    try std.testing.expect(supportsReasoningEffort(first.supported_reasoning_efforts, "low"));
    try std.testing.expect(!supportsReasoningEffort(first.supported_reasoning_efforts, "medium"));

    const duplicate: Registry = .{ .entries = &.{ first, first } };
    try std.testing.expectError(error.InvalidProviderModelContracts, duplicate.validate());
    var conflicting = second;
    conflicting.implementation_id = RegisteredProviderImplementationId.init(2).?;
    const inconsistent: Registry = .{ .entries = &.{ first, conflicting } };
    try std.testing.expectError(error.InvalidProviderModelContracts, inconsistent.validate());
}
