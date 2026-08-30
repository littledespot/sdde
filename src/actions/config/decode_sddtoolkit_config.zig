const std = @import("std");
const config = @import("../../domain/config.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{EngineConfigParseError};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "decode-sddtoolkit-config@1",
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

        owned.config = std.json.parseFromSliceLeaky(
            config.SDDToolKitConfig,
            owned.allocator(),
            bytes,
            .{
                .duplicate_field_behavior = .@"error",
                .ignore_unknown_fields = false,
                .allocate = .alloc_always,
            },
        ) catch return error.EngineConfigParseError;

        if (!promptCaptureIsUnique(owned.config.logs.promptCapture)) {
            return error.EngineConfigParseError;
        }

        return owned;
    }
};

fn promptCaptureIsUnique(values: []const config.PromptCapture) bool {
    var seen: std.EnumSet(config.PromptCapture) = .initEmpty();
    for (values) |value| {
        if (seen.contains(value)) return false;
        seen.insert(value);
    }
    return true;
}

const valid_config =
    \\{
    \\  "logs": { "level": "debug", "console": true, "promptCapture": [] },
    \\  "models": { "slots": { "implementation": { "provider": "openai", "model": "gpt-5.4-mini" } } },
    \\  "paths": {
    \\    "specs": "specs/", "references": "references/",
    \\    "specsArchive": "specs/_archive/", "workflows": ".sddtoolkit/workflows",
    \\    "toolchainPreset": ".sddtoolkit/toolchainPreset",
    \\    "principles": ".sddtoolkit/principles", "templates": ".sddtoolkit/templates"
    \\  }
    \\}
;

test "decodes the closed structure directly into the owned type" {
    var decoded = try (Action{}).execute(std.testing.allocator, valid_config);
    defer decoded.deinit();

    try std.testing.expect(decoded.value().logs.console);
    try std.testing.expectEqual(@as(usize, 1), decoded.value().models.slots.map.count());
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
        \\{"version":"legacy","logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"extra":true,"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"logs":{"level":"info","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":"no","promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[],"extra":true},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{},"extra":true},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":[]},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{"implementation":{"provider":"openai"}}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x","extra":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":1,"references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":["unknown"]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"logs":{"level":"debug","console":false,"promptCapture":["request","request"]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
    };

    for (invalid) |bytes| {
        try std.testing.expectError(
            error.EngineConfigParseError,
            (Action{}).execute(std.testing.allocator, bytes),
        );
    }
}

test "accepts JSON member reordering" {
    const reordered =
        \\{"paths":{"templates":"x","principles":"p","toolchainPreset":"t","workflows":"w","specsArchive":"s/a","references":"r","specs":"s"},"models":{"slots":{}},"logs":{"promptCapture":[],"console":false,"level":"INFO"}}
    ;
    var decoded = try (Action{}).execute(std.testing.allocator, reordered);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("INFO", decoded.value().logs.level);
}
