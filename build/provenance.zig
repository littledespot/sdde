//! Development harness build identity. Never linked into the production engine.
const std = @import("std");

pub const Identity = struct { revision: []const u8, source_sha256: []const u8, modified: bool };
pub const Input = struct {
    path: []const u8,
    tracked: bool = false,
    permissions: ?u32 = null,
    state: enum { captured, deleted, excluded, unavailable },
    bytes: ?[]const u8 = null,
    reason: ?[]const u8 = null,
};
pub const Bundle = struct {
    schema: []const u8 = "build-inputs/v1",
    identity: Identity,
    inputs: []const Input,
    complete: bool,
    compiler: []const u8 = @import("builtin").zig_version_string,
};
const roots = [_][]const u8{ "build_provenance.zig", ".zigversion", "build.zig", "build.zig.zon", "integration.zig", "role_calibration.zig", "build", "src", "test", "design", "scripts", "e2e.zig", "harness.zig", "tests.zig" };

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len != 2) return error.InvalidArguments;
    const value = try capture(a, init.io, .cwd());
    const output = try std.Io.Dir.cwd().createFile(init.io, args[1], .{});
    defer output.close(init.io);
    try output.writeStreamingAll(init.io, try std.json.Stringify.valueAlloc(a, value, .{}));
}

fn capture(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !Bundle {
    const revision = std.mem.trim(u8, try git(a, io, root, &.{ "rev-parse", "HEAD" }), "\r\n");
    const names = try git(a, io, root, &(.{ "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--" } ++ roots));
    const status = try git(a, io, root, &(.{ "status", "--porcelain", "--untracked-files=all", "--" } ++ roots));
    const tracked_names = try git(a, io, root, &(.{ "ls-files", "--cached", "-z", "--" } ++ roots));
    const deleted_names = try git(a, io, root, &(.{ "ls-files", "--deleted", "-z", "--" } ++ roots));
    var files: std.ArrayList([]const u8) = .empty;
    var paths = std.mem.tokenizeScalar(u8, names, 0);
    while (paths.next()) |path| try files.append(a, path);
    std.mem.sort([]const u8, files.items, {}, less);
    var inputs: std.ArrayList(Input) = .empty;
    var complete = true;
    var hash: std.crypto.hash.sha2.Sha256 = .init(.{});
    var previous: ?[]const u8 = null;
    for (files.items) |path| {
        if (previous) |prior| if (std.mem.eql(u8, prior, path)) continue;
        previous = path;
        const tracked = containsName(tracked_names, path);
        if (excluded(path)) {
            complete = false;
            try inputs.append(a, .{ .path = path, .tracked = tracked, .state = .excluded, .reason = "credential_path" });
            continue;
        }
        if (containsName(deleted_names, path)) {
            try inputs.append(a, .{ .path = path, .tracked = tracked, .state = .deleted });
            continue;
        }
        const parent_name = std.fs.path.dirname(path);
        const parent = if (parent_name) |name| @import("../src/adapters/filesystem/directory_access.zig").open(io, root, name) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            complete = false;
            try inputs.append(a, .{ .path = path, .tracked = tracked, .state = .unavailable, .reason = @errorName(err) });
            continue;
        } else root;
        defer if (parent_name != null) parent.close(io);
        const bytes = @import("../src/adapters/filesystem/file_access.zig").capture(io, a, parent, std.fs.path.basename(path), null, std.math.maxInt(usize) - 1) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            complete = false;
            try inputs.append(a, .{ .path = path, .tracked = tracked, .state = .unavailable, .reason = @errorName(err) });
            continue;
        };
        const state: @FieldType(Input, "state") = if (bytes) |value| if (std.unicode.utf8ValidateSlice(value)) .captured else .unavailable else .deleted;
        if (state == .unavailable) complete = false;
        const stat = if (state == .captured) try parent.statFile(io, std.fs.path.basename(path), .{ .follow_symlinks = false }) else null;
        try inputs.append(a, .{ .path = path, .tracked = tracked, .permissions = if (stat) |value| @intCast(value.permissions.toMode() & 0o777) else null, .state = state, .bytes = if (state == .captured) bytes else null, .reason = if (state == .unavailable) "non_utf8_build_input" else null });
    }
    for (inputs.items) |input| {
        hash.update(@tagName(input.state));
        hash.update(&.{ 0, @intFromBool(input.tracked) });
        var permissions: [4]u8 = undefined;
        std.mem.writeInt(u32, &permissions, input.permissions orelse 0, .little);
        hash.update(&permissions);
        add(&hash, input.path, input.bytes);
    }
    const digest = std.fmt.bytesToHex(hash.finalResult(), .lower);
    return .{ .identity = .{ .revision = revision, .source_sha256 = try a.dupe(u8, &digest), .modified = status.len != 0 }, .inputs = try inputs.toOwnedSlice(a), .complete = complete };
}

fn containsName(names: []const u8, expected: []const u8) bool {
    var items = std.mem.tokenizeScalar(u8, names, 0);
    while (items.next()) |name| if (std.mem.eql(u8, name, expected)) return true;
    return false;
}

fn excluded(path: []const u8) bool {
    var parts = std.mem.tokenizeScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (std.mem.startsWith(u8, part, ".env") or std.mem.eql(u8, part, ".aws") or std.mem.eql(u8, part, "credentials") or std.mem.eql(u8, part, ".git") or std.mem.endsWith(u8, part, ".pem") or std.mem.endsWith(u8, part, ".key")) return true;
    }
    return false;
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
    try std.testing.expect(!clean.identity.modified);
    try repository.dir.writeFile(io, .{ .sub_path = ".env.e2e", .data = "secret must not be read" });
    try std.testing.expectEqualDeep(clean, try capture(a, io, repository.dir));
    try repository.dir.writeFile(io, .{ .sub_path = "src/sample.zig", .data = "modified" });
    const modified = try capture(a, io, repository.dir);
    try std.testing.expect(modified.identity.modified);
    try std.testing.expectEqualStrings(clean.identity.revision, modified.identity.revision);
    try std.testing.expect(!std.mem.eql(u8, clean.identity.source_sha256, modified.identity.source_sha256));
    try repository.dir.writeFile(io, .{ .sub_path = "src/new.zig", .data = "untracked build input" });
    try std.testing.expect(!std.mem.eql(u8, modified.identity.source_sha256, (try capture(a, io, repository.dir)).identity.source_sha256));
}

test "source bundle retains untracked and deleted bytes and rejects credential paths and symlinks" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    _ = try git(a, io, repository.dir, &.{ "-c", "init.templateDir=", "init", "-q" });
    try repository.dir.createDir(io, "src", .default_dir);
    try repository.dir.writeFile(io, .{ .sub_path = "src/deleted.zig", .data = "old" });
    _ = try git(a, io, repository.dir, &.{ "add", "src" });
    _ = try git(a, io, repository.dir, &.{ "-c", "user.name=SDDE test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "baseline" });
    try repository.dir.deleteFile(io, "src/deleted.zig");
    try repository.dir.writeFile(io, .{ .sub_path = "src/new.zig", .data = "untracked bytes" });
    const captured = try capture(a, io, repository.dir);
    try std.testing.expect(captured.complete);
    try std.testing.expectEqual(.deleted, captured.inputs[0].state);
    try std.testing.expect(captured.inputs[0].tracked and !captured.inputs[1].tracked);
    try std.testing.expect(captured.inputs[1].permissions != null);
    try std.testing.expectEqualStrings("untracked bytes", captured.inputs[1].bytes.?);
    try repository.dir.writeFile(io, .{ .sub_path = "src/.env", .data = "MOCK_CREDENTIAL" });
    try repository.dir.symLink(io, ".env", "src/link.zig", .{});
    try repository.dir.writeFile(io, .{ .sub_path = "src/binary.dat", .data = &.{0xff} });
    const unavailable = try capture(a, io, repository.dir);
    try std.testing.expect(!unavailable.complete);
    const bytes = try std.json.Stringify.valueAlloc(a, unavailable, .{});
    try std.testing.expect(std.mem.indexOf(u8, bytes, "MOCK_CREDENTIAL") == null);
    var excluded_count: usize = 0;
    var unavailable_count: usize = 0;
    for (unavailable.inputs) |input| {
        if (input.state == .excluded) excluded_count += 1;
        if (input.state == .unavailable) unavailable_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), excluded_count);
    try std.testing.expectEqual(@as(usize, 2), unavailable_count);
}
