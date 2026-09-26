//! Development harness build identity. Never linked into the production engine.
const std = @import("std");

pub const Identity = struct { revision: []const u8, source_sha256: []const u8, modified: bool };
const roots = [_][]const u8{ "build.zig", "build.zig.zon", "build", "src", "test", "design", "scripts", "e2e.zig", "harness.zig", "tests.zig" };

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) return error.InvalidArguments;
    const value = try capture(a, init.io, .cwd());
    const output = try std.Io.Dir.cwd().createFile(init.io, args[1], .{});
    defer output.close(init.io);
    try output.writeStreamingAll(init.io, try std.json.Stringify.valueAlloc(a, value, .{}));
}

fn capture(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !Identity {
    const revision = std.mem.trim(u8, try git(a, io, root, &.{ "rev-parse", "HEAD" }), "\r\n");
    const names = try git(a, io, root, &(.{ "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--" } ++ roots));
    const status = try git(a, io, root, &(.{ "status", "--porcelain", "--untracked-files=all", "--" } ++ roots));
    var files: std.ArrayList([]const u8) = .empty;
    var paths = std.mem.tokenizeScalar(u8, names, 0);
    while (paths.next()) |path| try files.append(a, path);
    std.mem.sort([]const u8, files.items, {}, less);
    var hash: std.crypto.hash.sha2.Sha256 = .init(.{});
    var previous: ?[]const u8 = null;
    for (files.items) |path| {
        if (previous) |prior| if (std.mem.eql(u8, prior, path)) continue;
        previous = path;
        const bytes = root.readFileAlloc(io, path, a, .unlimited) catch |err| switch (err) {
            error.FileNotFound => {
                add(&hash, path, null);
                continue;
            },
            else => return err,
        };
        add(&hash, path, bytes);
    }
    const digest = std.fmt.bytesToHex(hash.finalResult(), .lower);
    return .{ .revision = revision, .source_sha256 = try a.dupe(u8, &digest), .modified = status.len != 0 };
}

fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn git(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, args: []const []const u8) ![]const u8 {
    const argv = try a.alloc([]const u8, args.len + 1);
    argv[0] = "git";
    @memcpy(argv[1..], args);
    const result = try std.process.run(a, io, .{ .argv = argv, .cwd = .{ .dir = root } });
    if (result.term != .exited or result.term.exited != 0) return error.BuildProvenanceUnavailable;
    return result.stdout;
}

fn add(hash: *std.crypto.hash.sha2.Sha256, path: []const u8, bytes: ?[]const u8) void {
    hash.update(path);
    hash.update(&.{0});
    if (bytes) |value| {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, value.len, .little);
        hash.update(&length);
        hash.update(value);
    } else hash.update("deleted");
}

test "source identity distinguishes modified deleted and renamed build inputs" {
    var original: std.crypto.hash.sha2.Sha256 = .init(.{});
    add(&original, "src/sample.zig", "source");
    const expected = original.finalResult();
    for (0..3) |change| {
        var changed: std.crypto.hash.sha2.Sha256 = .init(.{});
        add(&changed, if (change == 2) "src/renamed.zig" else "src/sample.zig", if (change == 0) "modified" else if (change == 1) null else "source");
        try std.testing.expect(!std.mem.eql(u8, &expected, &changed.finalResult()));
    }
}

test "captured provenance distinguishes clean and locally modified source without reading credentials" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDir(io, "src", .default_dir);
    try repository.dir.writeFile(io, .{ .sub_path = "src/sample.zig", .data = "original" });
    _ = try git(a, io, repository.dir, &.{ "add", "src" });
    _ = try git(a, io, repository.dir, &.{ "-c", "user.name=SDDE test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "baseline" });
    const clean = try capture(a, io, repository.dir);
    try std.testing.expect(!clean.modified);
    try repository.dir.writeFile(io, .{ .sub_path = ".env.e2e", .data = "secret must not be read" });
    try std.testing.expectEqualDeep(clean, try capture(a, io, repository.dir));
    try repository.dir.writeFile(io, .{ .sub_path = "src/sample.zig", .data = "modified" });
    const modified = try capture(a, io, repository.dir);
    try std.testing.expect(modified.modified);
    try std.testing.expectEqualStrings(clean.revision, modified.revision);
    try std.testing.expect(!std.mem.eql(u8, clean.source_sha256, modified.source_sha256));
    try repository.dir.writeFile(io, .{ .sub_path = "src/new.zig", .data = "untracked build input" });
    try std.testing.expect(!std.mem.eql(u8, modified.source_sha256, (try capture(a, io, repository.dir)).source_sha256));
}
