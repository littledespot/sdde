//! Shared bounded, descriptor-relative regular-file capture.
const std = @import("std");
const identity = @import("file_identity.zig");
const Observation = @import("../../domain/filesystem_identity.zig").FileObservation;
pub const Error = std.mem.Allocator.Error || error{ FileUnavailable, Cancelled };

pub fn observe(io: std.Io, parent: std.Io.Dir, name: []const u8) Error!Observation {
    var file = try openLeaf(parent, name);
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
    var file = try openLeaf(parent, name);
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

/// NONBLOCK prevents a raced-in FIFO/device from hanging before fstat rejects
/// its kind. A single validated leaf and NOFOLLOW keep lookup under this parent.
fn openLeaf(parent: std.Io.Dir, name: []const u8) Error!std.Io.File {
    @import("../../domain/relative_directory_path.zig").validate(name) catch return error.FileUnavailable;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return error.FileUnavailable;
    const handle = std.posix.openat(parent.handle, name, .{
        .ACCMODE = .RDONLY,
        .CLOEXEC = true,
        .NOFOLLOW = true,
        .NOCTTY = true,
        .NONBLOCK = true,
    }, 0) catch return error.FileUnavailable;
    return .{ .handle = handle, .flags = .{ .nonblocking = true } };
}

test "regular-file capture rejects missing aliases special nodes and stale observations" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.writeFile(io, .{ .sub_path = "source.md", .data = "first" });
    const observed = try observe(io, project.dir, "source.md");
    const bytes = (try capture(io, std.testing.allocator, project.dir, "source.md", observed, 5)).?;
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("first", bytes);
    try std.testing.expect((try capture(io, std.testing.allocator, project.dir, "missing.md", null, 5)) == null);
    try std.testing.expectError(error.FileUnavailable, capture(io, std.testing.allocator, project.dir, "missing.md", observed, 5));
    try project.dir.symLink(io, "source.md", "alias.md", .{});
    try std.testing.expectError(error.FileUnavailable, capture(io, std.testing.allocator, project.dir, "alias.md", null, 5));
    try project.dir.writeFile(io, .{ .sub_path = "source.md", .data = "other" });
    try std.testing.expectError(error.FileUnavailable, capture(io, std.testing.allocator, project.dir, "source.md", observed, 5));
    try std.testing.expectError(error.FileUnavailable, capture(io, std.testing.allocator, project.dir, "source.md", null, 4));
    try std.testing.expectError(error.FileUnavailable, observe(io, project.dir, "../source.md"));
}
