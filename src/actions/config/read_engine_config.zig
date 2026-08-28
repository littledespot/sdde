const std = @import("std");
const config = @import("../../domain/config.zig");
const reader = @import("../../adapters/filesystem/engine_config_reader.zig");

pub const Error = error{EngineConfigReadError};

pub fn execute(
    project_root: std.Io.Dir,
    io: std.Io,
    allocator: std.mem.Allocator,
) Error!reader.RawEngineConfig {
    const limit = reader.ReadLimit.init(config.max_engine_config_bytes) catch unreachable;
    var outcome = reader.read(project_root, io, allocator, limit) catch {
        return error.EngineConfigReadError;
    };
    return switch (outcome) {
        .loaded => |raw| raw,
        .rejected => error.EngineConfigReadError,
    };
}
