//! Shared bounded, descriptor-relative regular-file capture.
const std = @import("std");
const identity = @import("file_identity.zig");
const Observation = @import("../../domain/filesystem_identity.zig").FileObservation;
pub const Error = std.mem.Allocator.Error || error{ FileUnavailable, Cancelled };

pub fn observe(io: std.Io, parent: std.Io.Dir, name: []const u8) Error!Observation {
    var file = parent.openFile(io, name, .{ .mode = .read_only, .path_only = true, .allow_directory = false, .follow_symlinks = false, .resolve_beneath = true }) catch return error.FileUnavailable;
    defer file.close(io);
    return inspect(io, file);
}
fn inspect(io: std.Io, file: std.Io.File) Error!Observation {
    const stat = file.stat(io) catch return error.FileUnavailable;
    if (stat.kind != .file) return error.FileUnavailable;
    return .{ .identity = identity.inspect(file.handle) catch return error.FileUnavailable, .size = stat.size, .modified_ns = stat.mtime.nanoseconds, .changed_ns = stat.ctime.nanoseconds };
}
pub fn same(a: Observation, b: Observation) bool {
    return a.identity.eql(b.identity) and a.size == b.size and a.modified_ns == b.modified_ns and a.changed_ns == b.changed_ns;
}

/// Missing is returned only when no prior observation is required.
pub fn capture(io: std.Io, allocator: std.mem.Allocator, parent: std.Io.Dir, name: []const u8, expected: ?Observation, maximum: usize) Error!?[]const u8 {
    const named = parent.statFile(io, name, .{ .follow_symlinks = false }) catch |err| return switch (err) {
        error.FileNotFound => if (expected == null) null else error.FileUnavailable,
        error.Canceled => error.Cancelled,
        else => error.FileUnavailable,
    };
    if (named.kind != .file or named.size > maximum) return error.FileUnavailable;
    var file = parent.openFile(io, name, .{ .mode = .read_only, .allow_directory = false, .follow_symlinks = false, .resolve_beneath = true }) catch return error.FileUnavailable;
    defer file.close(io);
    const before = try inspect(io, file);
    if (expected) |prior| if (!same(prior, before)) return error.FileUnavailable;
    if (named.inode != before.identity.file_id or named.size != before.size or
        named.mtime.nanoseconds != before.modified_ns or named.ctime.nanoseconds != before.changed_ns) return error.FileUnavailable;
    var reader = file.reader(io, &.{});
    const bytes = @import("bounded_file_capture.zig").capture(allocator, &reader.interface, before.size, maximum) catch return error.FileUnavailable;
    errdefer allocator.free(bytes);
    if (!same(before, try inspect(io, file))) return error.FileUnavailable;
    const after = parent.statFile(io, name, .{ .follow_symlinks = false }) catch return error.FileUnavailable;
    if (after.kind != .file or after.inode != before.identity.file_id or after.size != before.size or
        after.mtime.nanoseconds != before.modified_ns or after.ctime.nanoseconds != before.changed_ns) return error.FileUnavailable;
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = parent.realPathFile(io, name, &path_buffer) catch return error.FileUnavailable;
    var scratch: [std.Io.Dir.max_name_bytes * 34 + 16]u8 = undefined;
    var fixed: std.heap.FixedBufferAllocator = .init(&scratch);
    const actual = @import("unicode_normalization").nfc(fixed.allocator(), std.fs.path.basename(path_buffer[0..length]), std.Io.Dir.max_name_bytes) catch return error.FileUnavailable;
    const wanted = @import("unicode_normalization").nfc(fixed.allocator(), name, std.Io.Dir.max_name_bytes) catch return error.FileUnavailable;
    if (!std.mem.eql(u8, actual, wanted)) return error.FileUnavailable;
    return bytes;
}
