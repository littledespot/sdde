//! Shared descriptor-relative, component-by-component no-follow directory access.
const std = @import("std");
const identity = @import("../../domain/filesystem_identity.zig");
const file_identity = @import("file_identity.zig");

pub const Error = error{ DirectoryMissing, DirectoryUnavailable, Cancelled };

pub fn open(io: std.Io, base: std.Io.Dir, relative: []const u8) Error!std.Io.Dir {
    if (relative.len == 0) return error.DirectoryUnavailable;
    var current = base;
    var owned = false;
    errdefer if (owned) current.close(io);
    var segments = std.mem.splitScalar(u8, relative, '/');
    while (segments.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..") or
            std.mem.indexOfScalar(u8, segment, '\\') != null or std.mem.indexOfScalar(u8, segment, 0) != null) return error.DirectoryUnavailable;
        const next = current.openDir(io, segment, .{ .iterate = segments.peek() == null, .follow_symlinks = false }) catch |err| return switch (err) {
            error.FileNotFound => error.DirectoryMissing,
            error.Canceled => error.Cancelled,
            else => error.DirectoryUnavailable,
        };
        if (owned) current.close(io);
        current = next;
        owned = true;
    }
    return current;
}

pub fn inspectReadable(io: std.Io, directory: std.Io.Dir) Error!identity.FileIdentity {
    const stat = directory.stat(io) catch |err| return switch (err) {
        error.Canceled => error.Cancelled,
        else => error.DirectoryUnavailable,
    };
    if (stat.kind != .directory) return error.DirectoryUnavailable;
    directory.access(io, ".", .{ .follow_symlinks = false, .read = true, .execute = true }) catch |err| return switch (err) {
        error.Canceled => error.Cancelled,
        else => error.DirectoryUnavailable,
    };
    return file_identity.inspect(directory.handle) catch error.DirectoryUnavailable;
}
