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
            if (raw != .object or raw.object.count() != 3) break :blk null;
            break :blk .{ .aws_bedrock = .{
                .region = closedName(contracts.BedrockRegion, raw, "region") orelse break :blk null,
                .family = closedName(contracts.BedrockFamily, raw, "family") orelse break :blk null,
                .max_output_tokens = maximumOutput(raw) orelse break :blk null,
            } };
        },
        .anthropic => blk: {
            if (raw != .object or raw.object.count() != 1) break :blk null;
            break :blk .{ .anthropic = .{ .max_output_tokens = maximumOutput(raw) orelse break :blk null } };
        },
    };
}

/// One required string field naming a compiled closed value exactly.
fn closedName(comptime T: type, raw: std.json.Value, field: []const u8) ?T {
    const value = raw.object.get(field) orelse return null;
    if (value != .string) return null;
    return std.meta.stringToEnum(T, value.string);
}

/// Every family records its model's documented maximum output: required, with
/// no default, lookup or clamp standing in for it (ADR 0011, ADR 0028).
fn maximumOutput(raw: std.json.Value) ?contracts.ModelMaximumOutput {
    const maximum = raw.object.get("maxOutputTokens") orelse return null;
    if (maximum != .integer) return null;
    return contracts.ModelMaximumOutput.parse(maximum.integer);
}

pub fn matches(
    schema: contracts.ProviderConfigSchema,
    value: contracts.ValidatedProviderConfig,
) bool {
    return schema == std.meta.activeTag(value);
}
