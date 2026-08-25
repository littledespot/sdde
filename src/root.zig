const std = @import("std");

pub const engine_config_reader = @import("adapters/filesystem/engine_config_reader.zig");

pub const greeting = "Hello, world!\n";

test "greeting is stable" {
    try std.testing.expectEqualStrings("Hello, world!\n", greeting);
}
