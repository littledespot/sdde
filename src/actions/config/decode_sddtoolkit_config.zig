const std = @import("std");
const config = @import("../../domain/config.zig");

pub const Error = error{EngineConfigParseError};

pub fn execute(allocator: std.mem.Allocator, bytes: []const u8) Error!config.Owned {
    var parsed = std.json.parseFromSlice(
        config.SDDToolKitConfig,
        allocator,
        bytes,
        .{
            .duplicate_field_behavior = .@"error",
            .ignore_unknown_fields = false,
            .allocate = .alloc_always,
        },
    ) catch return error.EngineConfigParseError;
    errdefer parsed.deinit();

    if (!std.mem.eql(u8, parsed.value.version, config.version)) {
        return error.EngineConfigParseError;
    }
    if (!promptCaptureIsUnique(parsed.value.logs.promptCapture)) {
        return error.EngineConfigParseError;
    }

    return .{ .parsed = parsed };
}

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
    \\  "version": "2.0",
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

test "decodes the closed v2 structure directly into the owned type" {
    var decoded = try execute(std.testing.allocator, valid_config);
    defer decoded.deinit();

    try std.testing.expectEqualStrings("2.0", decoded.value().version);
    try std.testing.expect(decoded.value().logs.console);
    try std.testing.expectEqual(@as(usize, 1), decoded.value().models.slots.map.count());
}

test "rejects malformed unsupported unknown missing duplicate and wrong-kind input" {
    const invalid = [_][]const u8{
        "{",
        \\{"version":"1.0","logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"version":"2.0","extra":true,"logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"version":"2.0","logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}}}
        ,
        \\{"version":"2.0","version":"2.0","logs":{"level":"debug","console":false,"promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"version":"2.0","logs":{"level":"debug","console":"no","promptCapture":[]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
        \\{"version":"2.0","logs":{"level":"debug","console":false,"promptCapture":["request","request"]},"models":{"slots":{}},"paths":{"specs":"s","references":"r","specsArchive":"s/a","workflows":"w","toolchainPreset":"t","principles":"p","templates":"x"}}
        ,
    };

    for (invalid) |bytes| {
        try std.testing.expectError(error.EngineConfigParseError, execute(std.testing.allocator, bytes));
    }
}

test "accepts JSON member reordering" {
    const reordered =
        \\{"paths":{"templates":"x","principles":"p","toolchainPreset":"t","workflows":"w","specsArchive":"s/a","references":"r","specs":"s"},"models":{"slots":{}},"logs":{"promptCapture":[],"console":false,"level":"INFO"},"version":"2.0"}
    ;
    var decoded = try execute(std.testing.allocator, reordered);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("INFO", decoded.value().logs.level);
}
