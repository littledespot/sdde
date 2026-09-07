//! Shared bounded, descriptor-relative regular-file capture.
const std = @import("std");
const identity = @import("file_identity.zig");
const Observation = @import("../../domain/filesystem_identity.zig").FileObservation;
pub const Error = std.mem.Allocator.Error || error{ FileUnavailable, Cancelled };
pub const Expected = union(enum) { any, absent, exact: []const u8 };

/// Ordinary full replacement with no-follow, single-link and exact-input
/// preconditions checked before truncation. A failed write may leave bytes.
pub fn replace(io: std.Io, allocator: std.mem.Allocator, parent: std.Io.Dir, name: []const u8, expected: Expected, bytes: []const u8) Error!void {
    try validateLeaf(name);
    const named = parent.statFile(io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => null,
        error.Canceled => return error.Cancelled,
        else => return error.FileUnavailable,
    };
    if (named) |stat| if (stat.kind != .file) return error.FileUnavailable;
    switch (expected) {
        .any => {},
        .absent => if (named != null) return error.FileUnavailable,
        .exact => |value| if (named == null or named.?.size != value.len) return error.FileUnavailable,
    }
    const before = if (named != null) try observe(io, parent, name) else null;
    const handle = std.posix.openat(parent.handle, name, .{ .ACCMODE = .RDWR, .CLOEXEC = true, .NOFOLLOW = true, .NOCTTY = true, .NONBLOCK = true, .CREAT = named == null, .EXCL = named == null }, 0o600) catch return error.FileUnavailable;
    var file: std.Io.File = .{ .handle = handle, .flags = .{ .nonblocking = true } };
    defer file.close(io);
    var stat: std.c.Stat = undefined;
    if (std.c.fstat(handle, &stat) != 0 or stat.nlink != 1) return error.FileUnavailable;
    const opened = try inspect(io, file);
    if (before) |observed| {
        if (!same(observed, opened)) return error.FileUnavailable;
    }
    try requireExactName(io, parent, name);
    if (expected == .exact) {
        const current = (try capture(io, allocator, parent, name, opened, expected.exact.len)) orelse return error.FileUnavailable;
        defer allocator.free(current);
        if (!std.mem.eql(u8, expected.exact, current)) return error.FileUnavailable;
    }
    if (!same(opened, try observe(io, parent, name))) return error.FileUnavailable;
    file.setLength(io, 0) catch return error.FileUnavailable;
    file.writePositionalAll(io, bytes, 0) catch return error.FileUnavailable;
    file.sync(io) catch return error.FileUnavailable;
    const after = try inspect(io, file);
    const verified = (try capture(io, allocator, parent, name, after, bytes.len)) orelse return error.FileUnavailable;
    defer allocator.free(verified);
    if (!std.mem.eql(u8, bytes, verified)) return error.FileUnavailable;
}

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
    try requireExactName(io, parent, name);
    return bytes;
}

fn requireExactName(io: std.Io, parent: std.Io.Dir, name: []const u8) Error!void {
    var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const length = parent.realPathFile(io, name, &path_buffer) catch return error.FileUnavailable;
    var scratch: [std.Io.Dir.max_name_bytes * 34 + 16]u8 = undefined;
    var fixed: std.heap.FixedBufferAllocator = .init(&scratch);
    const actual = @import("unicode_normalization").nfc(fixed.allocator(), std.fs.path.basename(path_buffer[0..length]), std.Io.Dir.max_name_bytes) catch return error.FileUnavailable;
    const wanted = @import("unicode_normalization").nfc(fixed.allocator(), name, std.Io.Dir.max_name_bytes) catch return error.FileUnavailable;
    if (!std.mem.eql(u8, actual, wanted)) return error.FileUnavailable;
}

/// NONBLOCK prevents a raced-in FIFO/device from hanging before fstat rejects
/// its kind. A single validated leaf and NOFOLLOW keep lookup under this parent.
fn openLeaf(parent: std.Io.Dir, name: []const u8) Error!std.Io.File {
    try validateLeaf(name);
    const handle = std.posix.openat(parent.handle, name, .{
        .ACCMODE = .RDONLY,
        .CLOEXEC = true,
        .NOFOLLOW = true,
        .NOCTTY = true,
        .NONBLOCK = true,
    }, 0) catch return error.FileUnavailable;
    return .{ .handle = handle, .flags = .{ .nonblocking = true } };
}

fn validateLeaf(name: []const u8) Error!void {
    @import("../../domain/relative_directory_path.zig").validate(name) catch return error.FileUnavailable;
    if (std.mem.indexOfScalar(u8, name, '/') != null) return error.FileUnavailable;
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

test "registered-file replacement truncates and refuses stale preconditions aliases and special files" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try replace(io, a, project.dir, "view.md", .absent, "long original output\n");
    try std.testing.expectError(error.FileUnavailable, replace(io, a, project.dir, "view.md", .absent, "bad"));
    try std.testing.expectError(error.FileUnavailable, replace(io, a, project.dir, "view.md", .{ .exact = "stale" }, "bad"));
    try replace(io, a, project.dir, "view.md", .{ .exact = "long original output\n" }, "x\n");
    const bytes = (try capture(io, a, project.dir, "view.md", null, 2)).?;
    defer a.free(bytes);
    try std.testing.expectEqualStrings("x\n", bytes);
    try project.dir.symLink(io, "view.md", "alias.md", .{});
    try std.testing.expectError(error.FileUnavailable, replace(io, a, project.dir, "alias.md", .any, "bad"));
    try project.dir.createDirPath(io, "directory");
    try std.testing.expectError(error.FileUnavailable, replace(io, a, project.dir, "directory", .any, "bad"));
    try std.testing.expectError(error.FileUnavailable, replace(io, a, project.dir, "../view.md", .any, "bad"));
    try replace(io, a, project.dir, "view.md", .any, "ok\n");
}
