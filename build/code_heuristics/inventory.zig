//! Capture the current Git source inventory for advisory development reports.
//! Missing/deleted inputs are distinguished from unreadable or aliased inputs.
const std = @import("std");
const model = @import("model.zig");
const analyze = @import("analyze.zig");
const directories = @import("../../src/adapters/filesystem/directory_access.zig");
const files = @import("../../src/adapters/filesystem/file_access.zig");

/// All returned measurements and their source storage belong to `a`.
/// Callers normally provide a short-lived arena for the complete report.
pub fn capture(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) ![]const model.File {
    const prefix = try git(a, io, root, &.{ "rev-parse", "--show-prefix" });
    defer a.free(prefix);
    if (std.mem.trim(u8, prefix, "\r\n").len != 0) return error.GitInventoryUnavailable;
    const names = try git(a, io, root, &.{ "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.zig" });
    defer a.free(names);
    const deleted = try git(a, io, root, &.{ "ls-files", "--deleted", "-z", "--", "*.zig" });
    defer a.free(deleted);
    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(a);
    var items = std.mem.tokenizeScalar(u8, names, 0);
    while (items.next()) |path| if (model.scope(path) != null) try paths.append(a, path);
    std.mem.sort([]const u8, paths.items, {}, less);

    var measurements: std.ArrayList(model.File) = .empty;
    errdefer measurements.deinit(a);
    var previous: ?[]const u8 = null;
    for (paths.items) |path| {
        if (previous) |prior| if (std.mem.eql(u8, prior, path)) continue;
        previous = path;
        const is_deleted = contains(deleted, path);
        const parent_name = std.fs.path.dirname(path);
        const parent = if (parent_name) |name| directories.open(io, root, name) catch |err| {
            if (err == error.DirectoryMissing and is_deleted) continue;
            return err;
        } else root;
        defer if (parent_name != null) parent.close(io);
        const source = (try files.capture(io, a, parent, std.fs.path.basename(path), null, std.math.maxInt(usize) - 1)) orelse {
            if (is_deleted) continue;
            return error.InventoryInputDisappeared;
        };
        // The analyzer's result and the path must outlive the Git listing.
        // Source is retained because token spellings may borrow from it.
        const owned_path = try a.dupe(u8, path);
        try measurements.append(a, try analyze.analyze(a, owned_path, source));
    }
    return measurements.toOwnedSlice(a);
}

fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn contains(names: []const u8, path: []const u8) bool {
    var items = std.mem.tokenizeScalar(u8, names, 0);
    while (items.next()) |name| if (std.mem.eql(u8, path, name)) return true;
    return false;
}

fn git(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, args: []const []const u8) ![]u8 {
    const argv = try a.alloc([]const u8, args.len + 1);
    defer a.free(argv);
    argv[0] = "git";
    @memcpy(argv[1..], args);
    const result = try std.process.run(a, io, .{ .argv = argv, .cwd = .{ .dir = root } });
    defer a.free(result.stderr);
    errdefer a.free(result.stdout);
    if (result.term != .exited or result.term.exited != 0) return error.GitInventoryUnavailable;
    return result.stdout;
}

test "inventory captures tracked and unignored source in stable path order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDirPath(io, "src/nested");
    try repository.dir.createDirPath(io, "test");
    try repository.dir.createDirPath(io, "zig-out");
    try repository.dir.writeFile(io, .{ .sub_path = "src/zeta.zig", .data = "pub fn zeta() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/deleted.zig", .data = "pub fn gone() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/nested/deleted.zig", .data = "pub fn gone() void {}\n" });
    _ = try git(a, io, repository.dir, &.{ "add", "src" });
    try repository.dir.deleteFile(io, "src/deleted.zig");
    try repository.dir.deleteTree(io, "src/nested");
    try repository.dir.writeFile(io, .{ .sub_path = ".gitignore", .data = "src/ignored.zig\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/ignored.zig", .data = "not Zig\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "zig-out/generated.zig", .data = "not Zig\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "src/alpha space.zig", .data = "pub fn alpha() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "test/example.zig", .data = "test \"example\" {}\n" });
    const first = try capture(a, io, repository.dir);
    const expected = [_][]const u8{ "src/alpha space.zig", "src/zeta.zig", "test/example.zig" };
    try std.testing.expectEqual(expected.len, first.len);
    for (first, expected) |entry, path| try std.testing.expectEqualStrings(path, entry.path);
    try std.testing.expectEqual(.production, first[0].scope);
    try std.testing.expectEqual(.tests, first[2].scope);
    try std.testing.expectEqualDeep(first, try capture(a, io, repository.dir));
}

test "inventory fails on unreadable source kinds and file symlinks" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDirPath(io, "src");
    try repository.dir.writeFile(io, .{ .sub_path = "src/real.zig", .data = "pub fn real() void {}\n" });
    try repository.dir.symLink(io, "real.zig", "src/link.zig", .{});
    try std.testing.expectError(error.FileUnavailable, capture(a, io, repository.dir));
    try repository.dir.deleteFile(io, "src/link.zig");
    _ = try git(a, io, repository.dir, &.{ "add", "src/real.zig" });
    try repository.dir.deleteFile(io, "src/real.zig");
    try repository.dir.createDirPath(io, "src/real.zig");
    try std.testing.expectError(error.FileUnavailable, capture(a, io, repository.dir));
}

test "inventory refuses replaced parent symlinks and nonrepository roots" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    try std.testing.expectError(error.GitInventoryUnavailable, capture(a, io, repository.dir));
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDirPath(io, "src/nested");
    try repository.dir.createDirPath(io, "other");
    try repository.dir.writeFile(io, .{ .sub_path = "src/nested/real.zig", .data = "pub fn real() void {}\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "other/real.zig", .data = "pub fn other() void {}\n" });
    _ = try git(a, io, repository.dir, &.{ "add", "src" });
    try repository.dir.deleteTree(io, "src/nested");
    try repository.dir.symLink(io, "../other", "src/nested", .{ .is_directory = true });
    try std.testing.expectError(error.DirectoryUnavailable, capture(a, io, repository.dir));
}
