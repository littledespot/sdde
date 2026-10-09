const std = @import("std");
const config = @import("../../domain/config.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{EngineConfigParseError};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "decode-sddtoolkit-config",
        .kind = .action,
        .requires = &.{.raw_engine_config},
        .produces = &.{.engine_config},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        bytes: []const u8,
    ) Error!config.Owned {
        var owned = config.Owned.init(allocator);
        errdefer owned.deinit();

        const raw = std.json.parseFromSliceLeaky(
            std.json.Value,
            owned.allocator(),
            bytes,
            .{
                .duplicate_field_behavior = .@"error",
                .ignore_unknown_fields = false,
                .allocate = .alloc_always,
                .parse_numbers = false,
            },
        ) catch return error.EngineConfigParseError;
        try validateOutputAllowances(raw);
        owned.config = std.json.parseFromValueLeaky(config.SDDToolKitConfig, owned.allocator(), raw, .{
            .ignore_unknown_fields = false,
            .allocate = .alloc_always,
        }) catch return error.EngineConfigParseError;

        return owned;
    }
};

// Optional means absent, not null. Inspect the JSON number before native decoding
// so quoted numbers and fractional values cannot be coerced into an allowance.
fn validateOutputAllowances(raw: std.json.Value) Error!void {
    if (raw != .object) return error.EngineConfigParseError;
    const models = raw.object.get("models") orelse return error.EngineConfigParseError;
    if (models != .object) return error.EngineConfigParseError;
    const slots = models.object.get("slots") orelse return error.EngineConfigParseError;
    if (slots != .object) return error.EngineConfigParseError;
    for (slots.object.values()) |slot| {
        if (slot != .object) return error.EngineConfigParseError;
        const value = slot.object.get("maxOutputTokens") orelse continue;
        if (value != .number_string) return error.EngineConfigParseError;
        const integer = @import("../../domain/model_payload_schema.zig").exactInteger(value.number_string) catch return error.EngineConfigParseError;
        const positive = std.math.cast(u32, integer) orelse return error.EngineConfigParseError;
        _ = @import("../../domain/model_controls.zig").OutputTokenAllowance.init(positive) orelse return error.EngineConfigParseError;
    }
}

const valid_config =
    \\{
    \\  "logs": { "level": "debug", "console": true },
    \\  "models": { "slots": { "implementation": { "provider": "openai", "model": "gpt-5.4-mini" } } },
    \\  "paths": {
    \\    "specs": "specs/", "references": "references/",
    \\    "specsArchive": "specs/_archive/", "workflows": ".sddtoolkit/workflows",
    \\    "toolchainPreset": ".sddtoolkit/toolchainPreset",
    \\    "principles": ".sddtoolkit/principles", "templates": ".sddtoolkit/templates",
    \\    "providers": ".sddproviders.json"
    \\  }
    \\}
;

test "decodes the closed structure directly into the owned type" {
    var decoded = try (Action{}).execute(std.testing.allocator, valid_config);
    defer decoded.deinit();

    try std.testing.expect(decoded.value().logs.console);
    try std.testing.expectEqual(@as(usize, 1), decoded.value().models.slots.map.count());
    try std.testing.expect(!decoded.value().validation.sourcePreservationCheck);
    try std.testing.expect(decoded.value().models.slots.map.get("implementation").?.maxOutputTokens == null);
}

test "output allowance is an optional positive integer without coercion or provider ceiling" {
    const a = std.testing.allocator;
    const cases = [_]struct { raw: []const u8, expected: ?u32 }{
        .{ .raw = "1", .expected = 1 },
        .{ .raw = "32768", .expected = 32768 },
        .{ .raw = "4294967295", .expected = std.math.maxInt(u32) },
        .{ .raw = "1.0", .expected = 1 },
        .{ .raw = "1e3", .expected = 1000 },
        .{ .raw = "0", .expected = null },
        .{ .raw = "-1", .expected = null },
        .{ .raw = "1.5", .expected = null },
        .{ .raw = "\"32768\"", .expected = null },
        .{ .raw = "4294967296", .expected = null },
        .{ .raw = "null", .expected = null },
        .{ .raw = "true", .expected = null },
        .{ .raw = "32768,\"maxOutputTokens\":65536", .expected = null },
    };
    for (cases) |case| {
        const replacement = try std.fmt.allocPrint(a, "\"model\": \"gpt-5.4-mini\", \"maxOutputTokens\": {s}", .{case.raw});
        defer a.free(replacement);
        const bytes = try std.mem.replaceOwned(u8, a, valid_config, "\"model\": \"gpt-5.4-mini\"", replacement);
        defer a.free(bytes);
        if (case.expected) |expected| {
            var decoded = try (Action{}).execute(a, bytes);
            defer decoded.deinit();
            try std.testing.expectEqual(expected, decoded.value().models.slots.map.get("implementation").?.maxOutputTokens.?);
        } else try std.testing.expectError(error.EngineConfigParseError, (Action{}).execute(a, bytes));
    }
}

fn configurationWithValidation(allocator: std.mem.Allocator, section: []const u8) ![]u8 {
    const replacement = try std.fmt.allocPrint(allocator, "{{\"validation\":{s},\n  \"logs\"", .{section});
    defer allocator.free(replacement);
    return std.mem.replaceOwned(u8, allocator, valid_config, "{\n  \"logs\"", replacement);
}

test "source preservation is an optional closed boolean policy" {
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "{}", "{\"sourcePreservationCheck\":false}", "{\"sourcePreservationCheck\":true}" }, 0..) |section, index| {
        const bytes = try configurationWithValidation(allocator, section);
        defer allocator.free(bytes);
        var decoded = try (Action{}).execute(allocator, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(index == 2, decoded.value().validation.sourcePreservationCheck);
    }
    for ([_][]const u8{ "null", "true", "[]", "{\"sourcePreservationCheck\":\"true\"}", "{\"sourcePreservationCheck\":null}", "{\"sourcePreservationCheck\":true,\"extra\":false}", "{\"sourcePreservationCheck\":true,\"sourcePreservationCheck\":false}" }) |section| {
        const bytes = try configurationWithValidation(allocator, section);
        defer allocator.free(bytes);
        try std.testing.expectError(error.EngineConfigParseError, (Action{}).execute(allocator, bytes));
    }
}

test "decodes a valid document at the exact compiler byte limit" {
    const allocator = std.testing.allocator;
    const bytes = try allocator.alloc(u8, config.max_engine_config_bytes);
    defer allocator.free(bytes);
    @memset(bytes, ' ');
    @memcpy(bytes[0..valid_config.len], valid_config);

    var decoded = try (Action{}).execute(allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("debug", decoded.value().logs.level);
}

test "rejects malformed unknown missing duplicate and wrong-kind input" {
    const invalid = [_][]const u8{
        "{",
        valid_config ++ "\ntrue",
        \\{"version":"legacy","logs":{"level":"debug","console":false},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"extra":true,"logs":{"level":"debug","console":false},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{}}}
        ,
        \\{"logs":{"level":"debug","console":false},"logs":{"level":"info","console":false},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":"no"},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false,"extra":true},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug"},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{},"extra":true},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":[]},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{"implementation":{"provider":"openai"}}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json","extra":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{}},"paths":{"specs":1,"references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
    };

    for (invalid) |bytes| {
        try std.testing.expectError(
            error.EngineConfigParseError,
            (Action{}).execute(std.testing.allocator, bytes),
        );
    }
}

test "rejects the removed promptCapture configuration field" {
    const legacy = try std.mem.replaceOwned(u8, std.testing.allocator, valid_config, "\"console\": true", "\"console\": true, \"promptCapture\": []");
    defer std.testing.allocator.free(legacy);
    try std.testing.expectError(error.EngineConfigParseError, (Action{}).execute(std.testing.allocator, legacy));
}

test "accepts JSON member reordering" {
    const reordered =
        \\{"paths":{"providers":".sddproviders.json","templates":"x","principles":"p","toolchainPreset":"t","workflows":"w","specsArchive":"s/a","references":"r","specs":"s"},"models":{"slots":{}},"logs":{"console":false,"level":"INFO"}}
    ;
    var decoded = try (Action{}).execute(std.testing.allocator, reordered);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("INFO", decoded.value().logs.level);
}
