//! Converts an already-open filesystem handle into stable physical identity.

const std = @import("std");
const filesystem_identity = @import("../../domain/filesystem_identity.zig");

pub const Error = error{FileIdentityUnavailable};

pub fn inspect(handle: std.posix.fd_t) Error!filesystem_identity.FileIdentity {
    var stat: std.c.Stat = undefined;
    if (std.c.fstat(handle, &stat) != 0) return error.FileIdentityUnavailable;

    return .{
        .filesystem_id = @intCast(stat.dev),
        .file_id = @intCast(stat.ino),
        .generation_id = if (@hasField(std.c.Stat, "gen")) stat.gen else 0,
    };
}
