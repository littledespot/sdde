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
        .aws_bedrock => blk: {
            // The model's documented maximum output is required: no default,
            // lookup or clamp stands in for it.
            if (raw != .object or raw.object.count() != 2) break :blk null;
            const region = raw.object.get("region") orelse break :blk null;
            const maximum = raw.object.get("maxOutputTokens") orelse break :blk null;
            if (region != .string or maximum != .integer) break :blk null;
            break :blk .{ .aws_bedrock = .{
                .region = std.meta.stringToEnum(contracts.BedrockRegion, region.string) orelse break :blk null,
                .max_output_tokens = contracts.ModelMaximumOutput.parse(maximum.integer) orelse break :blk null,
            } };
        },
    };
}

pub fn matches(
    schema: contracts.ProviderConfigSchema,
    value: contracts.ValidatedProviderConfig,
) bool {
    return switch (schema) {
        .empty_object => value == .empty_object,
        .aws_bedrock => value == .aws_bedrock,
    };
}
