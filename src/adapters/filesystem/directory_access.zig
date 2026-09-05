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
        requireExactName(io, next, segment) catch |err| {
            next.close(io);
            return err;
        };
        if (owned) current.close(io);
        current = next;
        owned = true;
    }
    return current;
}

/// Compare the opened descriptor's actual name, not a directory inventory.
/// NFC-equivalent spellings are the same normalized input; case/other aliases
/// cannot silently select a differently named directory on the active filesystem.
fn requireExactName(io: std.Io, directory: std.Io.Dir, expected: []const u8) Error!void {
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = directory.realPathFile(io, ".", &path_buffer) catch return error.DirectoryUnavailable;
    // Two bounded NFC calls: each needs at most 4 scalars/byte of i32
    // workspace plus its owned UTF-8 output; reserve alignment/terminators too.
    var scratch: [std.Io.Dir.max_name_bytes * 34 + 16]u8 = undefined;
    var fixed: std.heap.FixedBufferAllocator = .init(&scratch);
    const actual = @import("unicode_normalization").nfc(fixed.allocator(), std.fs.path.basename(path_buffer[0..length]), std.Io.Dir.max_name_bytes) catch return error.DirectoryUnavailable;
    const canonical_expected = @import("unicode_normalization").nfc(fixed.allocator(), expected, std.Io.Dir.max_name_bytes) catch return error.DirectoryUnavailable;
    if (!std.mem.eql(u8, actual, canonical_expected)) return error.DirectoryUnavailable;
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

/// Recheck an earlier root/target observation without materializing an absent path.
pub fn openObserved(io: std.Io, base: std.Io.Dir, relative: []const u8, expected: @import("../../domain/bootstrap_roots.zig").RootObservation) Error!?std.Io.Dir {
    const directory = open(io, base, relative) catch |err| return switch (err) {
        error.DirectoryMissing => if (expected == .absent) null else error.DirectoryUnavailable,
        else => err,
    };
    errdefer directory.close(io);
    const current = try inspectReadable(io, directory);
    if (expected != .directory or !expected.directory.eql(current)) return error.DirectoryUnavailable;
    return directory;
}
