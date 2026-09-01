const std = @import("std");
const contracts = @import("llm_provider_contracts.zig");

pub fn decode(
    schema: contracts.ProviderConfigSchema,
    raw: std.json.Value,
) ?contracts.ValidatedProviderConfig {
    return switch (schema) {
        .empty_object => switch (raw) {
            .object => |object| if (object.count() == 0) .empty_object else null,
            else => null,
        },
    };
}

pub fn matches(
    schema: contracts.ProviderConfigSchema,
    value: contracts.ValidatedProviderConfig,
) bool {
    return switch (schema) {
        .empty_object => value == .empty_object,
    };
}
