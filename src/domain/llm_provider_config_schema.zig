const std = @import("std");
const contracts = @import("llm_provider_contracts.zig");

pub fn decode(
    schema: contracts.ProviderConfigSchema,
    raw: std.json.Value,
) ?contracts.ValidatedProviderConfig {
    return switch (schema) {
        .deadline_only => blk: {
            if (raw != .object or raw.object.count() != 1) break :blk null;
            break :blk .{ .deadline_only = .{ .request_timeout = requestTimeout(raw) orelse break :blk null } };
        },
        .aws_bedrock => blk: {
            if (raw != .object or raw.object.count() != 4) break :blk null;
            break :blk .{ .aws_bedrock = .{
                .region = closedName(contracts.BedrockRegion, raw, "region") orelse break :blk null,
                .family = closedName(contracts.BedrockFamily, raw, "family") orelse break :blk null,
                .max_output_tokens = maximumOutput(raw) orelse break :blk null,
                .request_timeout = requestTimeout(raw) orelse break :blk null,
            } };
        },
        .anthropic => blk: {
            if (raw != .object or raw.object.count() != 2) break :blk null;
            break :blk .{ .anthropic = .{
                .max_output_tokens = maximumOutput(raw) orelse break :blk null,
                .request_timeout = requestTimeout(raw) orelse break :blk null,
            } };
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
    return integerLimit(contracts.ModelMaximumOutput, raw, "maxOutputTokens");
}

/// Every family records its model's provider-operation deadline: required, with
/// no default or workflow value standing in for it (ADR 0030).
fn requestTimeout(raw: std.json.Value) ?contracts.RequestTimeout {
    return integerLimit(contracts.RequestTimeout, raw, "requestTimeoutMs");
}

/// One required integer field admitted only through its wrapper's `parse` rule.
fn integerLimit(comptime T: type, raw: std.json.Value, field: []const u8) ?T {
    const value = raw.object.get(field) orelse return null;
    if (value != .integer) return null;
    return T.parse(value.integer);
}

pub fn matches(
    schema: contracts.ProviderConfigSchema,
    value: contracts.ValidatedProviderConfig,
) bool {
    return schema == std.meta.activeTag(value);
}

test "every provider family requires one positive u32 requestTimeoutMs beside its other fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Case = struct { schema: contracts.ProviderConfigSchema, fields: []const u8 };
    // The other fields of a valid entry of each family, each followed by the
    // `requestTimeoutMs` member under test.
    const families = [_]Case{
        .{ .schema = .deadline_only, .fields = "" },
        .{ .schema = .aws_bedrock, .fields = "\"region\":\"ap-southeast-2\",\"family\":\"gpt-oss\",\"maxOutputTokens\":16384," },
        .{ .schema = .anthropic, .fields = "\"maxOutputTokens\":128000," },
    };
    for (families) |family| {
        for ([_]u32{ 1, 1000, 180000, std.math.maxInt(u32) }) |milliseconds| {
            const bytes = try std.fmt.allocPrint(a, "{{{s}\"requestTimeoutMs\":{d}}}", .{ family.fields, milliseconds });
            const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{});
            const decoded = decode(family.schema, parsed) orelse return error.TestExpectedAccepted;
            try std.testing.expectEqual(family.schema, std.meta.activeTag(decoded));
            try std.testing.expectEqual(milliseconds, decoded.requestTimeout().milliseconds);
        }
        // Missing, zero, negative, fractional (including float-written integers),
        // quoted, null, boolean, nested and out-of-u32-range values are rejected,
        // as is an unknown field beside a valid deadline.
        for ([_][]const u8{
            "\"requestTimeoutMs\":0",
            "\"requestTimeoutMs\":-1",
            "\"requestTimeoutMs\":1000.5",
            "\"requestTimeoutMs\":180000.0",
            "\"requestTimeoutMs\":1.8e5",
            "\"requestTimeoutMs\":\"180000\"",
            "\"requestTimeoutMs\":null",
            "\"requestTimeoutMs\":true",
            "\"requestTimeoutMs\":{\"milliseconds\":180000}",
            "\"requestTimeoutMs\":4294967296",
            "\"requestTimeoutMs\":9223372036854775808",
            "\"timeoutMs\":180000",
            "\"requestTimeoutMs\":180000,\"timeout-ms\":180000",
        }) |member| {
            const bytes = try std.mem.concat(a, u8, &.{ "{", family.fields, member, "}" });
            try std.testing.expect(decode(family.schema, try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{})) == null);
        }
        const without_deadline = try std.mem.concat(a, u8, &.{ "{", std.mem.trimEnd(u8, family.fields, ","), "}" });
        try std.testing.expect(decode(family.schema, try std.json.parseFromSliceLeaky(std.json.Value, a, without_deadline, .{})) == null);
    }
    // A deadline cannot make another family's configuration valid.
    const bedrock = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"region\":\"ap-southeast-2\",\"family\":\"gpt-oss\",\"maxOutputTokens\":16384,\"requestTimeoutMs\":180000}", .{});
    try std.testing.expect(decode(.anthropic, bedrock) == null);
    try std.testing.expect(decode(.deadline_only, bedrock) == null);
}

test "a request timeout is one positive u32 admitted only through its parse rule" {
    for ([_]i64{ 1, 60000, 180000, std.math.maxInt(u32) }) |milliseconds| try std.testing.expectEqual(@as(u32, @intCast(milliseconds)), contracts.RequestTimeout.parse(milliseconds).?.milliseconds);
    for ([_]i64{ 0, -1, std.math.maxInt(u32) + 1, std.math.maxInt(i64), std.math.minInt(i64) }) |milliseconds| try std.testing.expect(contracts.RequestTimeout.parse(milliseconds) == null);
    // Every decoder sees the same integer-written wire form.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Holder = struct { deadline: contracts.RequestTimeout };
    const closed = @import("strict_json.zig");
    const accepted = try closed.decode(Holder, a, "{\"deadline\":180000}", .{ .maximum_depth = 4 });
    try std.testing.expectEqual(@as(u32, 180000), accepted.deadline.milliseconds);
    try std.testing.expectEqualStrings("{\"deadline\":180000}", try std.json.Stringify.valueAlloc(a, accepted, .{}));
    for ([_][]const u8{
        "{\"deadline\":0}",
        "{\"deadline\":-1}",
        "{\"deadline\":4294967296}",
        "{\"deadline\":\"180000\"}",
        "{\"deadline\":180000.5}",
        "{\"deadline\":180000.0}",
        "{\"deadline\":1.8e5}",
        "{\"deadline\":null}",
        "{\"deadline\":true}",
        "{\"deadline\":{\"milliseconds\":180000}}",
        "{}",
    }) |bytes| try std.testing.expectError(error.InvalidJsonDocument, closed.decode(Holder, a, bytes, .{ .maximum_depth = 4 }));
    for ([_][]const u8{ "{\"deadline\":\"180000\"}", "{\"deadline\":180000.0}", "{\"deadline\":1.8e5}" }) |bytes|
        try std.testing.expect(std.meta.isError(std.json.parseFromSliceLeaky(Holder, a, bytes, .{})));
}
