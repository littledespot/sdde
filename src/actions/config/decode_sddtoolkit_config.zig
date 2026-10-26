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

        owned.config = std.json.parseFromSliceLeaky(config.SDDToolKitConfig, owned.allocator(), bytes, .{
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = false,
            .allocate = .alloc_always,
        }) catch return error.EngineConfigParseError;

        return owned;
    }
};

const valid_config =
    \\{
    \\  "logs": { "level": "debug", "console": true },
    \\  "workflowTokenBudget": 100000,
    \\  "temperature": 0.1,
    \\  "temperatureRunawayRetry": 1,
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
}

test "slots configure no output-token allowance or request deadline" {
    // ADR 0011 and ADR 0030: a slot cannot narrow the catalogue's recorded model
    // maximum or replace its deadline; the closed contract rejects both fields.
    const a = std.testing.allocator;
    for ([_][]const u8{ "maxOutputTokens", "requestTimeoutMs", "timeout-ms" }) |field| for ([_][]const u8{ "1", "2048", "16384", "null" }) |raw| {
        const replacement = try std.fmt.allocPrint(a, "\"model\": \"gpt-5.4-mini\", \"{s}\": {s}", .{ field, raw });
        defer a.free(replacement);
        const bytes = try std.mem.replaceOwned(u8, a, valid_config, "\"model\": \"gpt-5.4-mini\"", replacement);
        defer a.free(bytes);
        try std.testing.expectError(error.EngineConfigParseError, (Action{}).execute(a, bytes));
    };
}

test "the workflow token budget is a required positive integer within the u32 range" {
    // ADR 0037: the project configuration is the budget's one source; no default exists.
    const a = std.testing.allocator;
    const configured = "\"workflowTokenBudget\": 100000,\n";
    for ([_]struct { raw: []const u8, value: u64 }{ .{ .raw = "1", .value = 1 }, .{ .raw = "125000", .value = 125_000 }, .{ .raw = "4294967295", .value = 4_294_967_295 } }) |case| {
        const replacement = try std.fmt.allocPrint(a, "\"workflowTokenBudget\": {s},\n", .{case.raw});
        defer a.free(replacement);
        const bytes = try std.mem.replaceOwned(u8, a, valid_config, configured, replacement);
        defer a.free(bytes);
        var decoded = try (Action{}).execute(a, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(case.value, decoded.value().workflowTokenBudget.budget.value);
    }
    for ([_][]const u8{ "", "\"workflowTokenBudget\": 0,\n", "\"workflowTokenBudget\": -1,\n", "\"workflowTokenBudget\": 1.5,\n", "\"workflowTokenBudget\": 1e3,\n", "\"workflowTokenBudget\": \"125000\",\n", "\"workflowTokenBudget\": null,\n", "\"workflowTokenBudget\": 4294967296,\n", "\"workflowTokenBudget\": [],\n", "\"workflowTokenBudget\": 1,\n  \"workflowTokenBudget\": 2,\n" }) |replacement| {
        const bytes = try std.mem.replaceOwned(u8, a, valid_config, configured, replacement);
        defer a.free(bytes);
        try std.testing.expectError(error.EngineConfigParseError, (Action{}).execute(a, bytes));
    }
}

test "both temperatures are required numbers, zero or greater" {
    // ADR 0039: the project configuration is each temperature's one source.
    const a = std.testing.allocator;
    const configured = "\"temperature\": 0.1,\n  \"temperatureRunawayRetry\": 1,\n";
    for ([_]struct { raw: []const u8, temperature: f64, retry: f64 }{
        .{ .raw = "\"temperature\": 0,\n  \"temperatureRunawayRetry\": 0,\n", .temperature = 0, .retry = 0 },
        .{ .raw = configured, .temperature = 0.1, .retry = 1 },
        .{ .raw = "\"temperature\": 1,\n  \"temperatureRunawayRetry\": 1.5,\n", .temperature = 1, .retry = 1.5 },
    }) |case| {
        const bytes = try std.mem.replaceOwned(u8, a, valid_config, configured, case.raw);
        defer a.free(bytes);
        var decoded = try (Action{}).execute(a, bytes);
        defer decoded.deinit();
        try std.testing.expectEqual(case.temperature, decoded.value().temperatures().configured.value);
        try std.testing.expectEqual(case.retry, decoded.value().temperatures().runaway_retry.value);
    }
    for ([_][]const u8{
        "\"temperatureRunawayRetry\": 1,\n",
        "\"temperature\": 0.1,\n",
        "\"temperature\": -0.1,\n  \"temperatureRunawayRetry\": 1,\n",
        "\"temperature\": 0.1,\n  \"temperatureRunawayRetry\": -1,\n",
        "\"temperature\": \"0.1\",\n  \"temperatureRunawayRetry\": 1,\n",
        "\"temperature\": 0.1,\n  \"temperatureRunawayRetry\": \"1\",\n",
        "\"temperature\": null,\n  \"temperatureRunawayRetry\": 1,\n",
        "\"temperature\": 0.1,\n  \"temperatureRunawayRetry\": null,\n",
        "\"temperature\": [],\n  \"temperatureRunawayRetry\": 1,\n",
        "\"temperature\": 0.1,\n  \"temperatureRunawayRetry\": true,\n",
        "\"temperature\": 0.1,\n  \"temperature\": 0.2,\n  \"temperatureRunawayRetry\": 1,\n",
        "\"temperature\": 0.1,\n  \"temperatureRunawayRetry\": 1,\n  \"temperatureRunawayRetry\": 2,\n",
    }) |replacement| {
        const bytes = try std.mem.replaceOwned(u8, a, valid_config, configured, replacement);
        defer a.free(bytes);
        try std.testing.expectError(error.EngineConfigParseError, (Action{}).execute(a, bytes));
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
        \\{"version":"legacy","logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"extra":true,"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}}}
        ,
        \\{"logs":{"level":"debug","console":false},"logs":{"level":"info","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":"no"},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false,"extra":true},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug"},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{},"extra":true},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":[]},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{"implementation":{"provider":"openai"}}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json","extra":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":1,"references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","providers":".sddproviders.json"}}
        ,
        \\{"logs":{"level":"debug","console":false},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
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
        \\{"paths":{"providers":".sddproviders.json","templates":"x","principles":"p","toolchainPreset":"t","workflows":"w","specsArchive":"s/a","references":"r","specs":"s"},"workflowTokenBudget":100000,"temperature":0.1,"temperatureRunawayRetry":1,"models":{"slots":{}},"logs":{"console":false,"level":"INFO"}}
    ;
    var decoded = try (Action{}).execute(std.testing.allocator, reordered);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("INFO", decoded.value().logs.level);
}
