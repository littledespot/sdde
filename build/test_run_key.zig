//! Keys opt-in reuse of test runs (`test_run_reuse.zig`).
//!
//! `capture <key-out> <build-out> <state> <ignored-location>...` writes:
//! - to `<key-out>`, the reuse key, over the Git-listed content, the named ignored
//!   locations (`test_run_inputs.zig`) and the `<state>` directory;
//! - to `<build-out>`, which test runs don't take as an input, a nonce for this
//!   build and a confirmation digest of the Git-listed files that also covers each
//!   file's change time and inode, so an edit that was reverted is still a change.
//!
//! `begin <build-file> <state> <run>` marks one keyed run of this build pending
//! before it starts. `confirm <build-file> <state> <run>` clears that mark only if
//! the Git-listed files still match the confirmation digest; otherwise it records
//! the change and fails. A run that fails, is interrupted or can't be confirmed
//! leaves its mark. Marks are named by build, so no other build or result clears
//! them, and they change every later key, so such a result is never reused.
//!
//! The Git-listed content covers every path Git lists through the repository's
//! `.gitignore` files, tracked or untracked, by kind and executable bit with its
//! full bytes, plus deleted tracked files, the HEAD revision and the `git` version.
//! Files are read only through the repository's no-follow capture. Paths that are
//! credential-like, or hidden only by a user's own Git excludes, are keyed by size
//! and modification time and never opened; confirmation skips them. Symbolic links
//! and multiply linked files are refused, because their content can live outside
//! what the key reads. Any error fails the build, so there is no key and no reuse.
const std = @import("std");
const credential_paths = @import("credential_paths.zig");
const directory_access = @import("../src/adapters/filesystem/directory_access.zig");
const file_access = @import("../src/adapters/filesystem/file_access.zig");

const Hash = std.crypto.hash.sha2.Sha256;
const Digest = [64]u8;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const a = init.arena.allocator();
    const args = try init.minimal.args.toSlice(a);
    if (args.len >= 5 and std.mem.eql(u8, args[1], "capture")) {
        const key = try capture(init.gpa, io, .cwd(), args[4], args[5..]);
        try writeLines(io, args[2], &.{&key.reuse});
        var nonce: [16]u8 = undefined;
        io.random(&nonce);
        try writeLines(io, args[3], &.{ &std.fmt.bytesToHex(nonce, .lower), &key.confirmation });
        return;
    }
    if (args.len == 5 and (std.mem.eql(u8, args[1], "begin") or std.mem.eql(u8, args[1], "confirm"))) {
        var lines = std.mem.tokenizeScalar(u8, try std.Io.Dir.cwd().readFileAlloc(io, args[2], a, .limited(256)), '\n');
        const nonce = lines.next() orelse return error.InvalidTestRunBuild;
        const confirmation = lines.next() orelse return error.InvalidTestRunBuild;
        if (std.mem.eql(u8, args[1], "begin")) return begin(a, io, args[3], nonce, args[4]);
        confirm(init.gpa, io, .cwd(), confirmation, args[3], nonce, args[4]) catch |err| {
            if (err == error.TestRunInputsChangedDuringBuild) {
                try std.Io.File.stderr().writeStreamingAll(io, "Repository files changed while opt-in test runs were executing; the next opt-in build reruns them.\n");
            }
            return err;
        };
        return;
    }
    return error.InvalidArguments;
}

fn writeLines(io: std.Io, path: []const u8, lines: []const []const u8) !void {
    const output = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer output.close(io);
    for (lines) |line| {
        try output.writeStreamingAll(io, line);
        try output.writeStreamingAll(io, "\n");
    }
}

pub const Key = struct { reuse: Digest, confirmation: Digest };

pub fn capture(gpa: std.mem.Allocator, io: std.Io, root: std.Io.Dir, state: []const u8, ignored: []const []const u8) !Key {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const listed = try listing(a, io, root);
    var hash: Hash = .init(.{});
    field(&hash, "schema", "sdde-test-run-key/v4");
    field(&hash, "listed", &try listedDigest(gpa, io, root, listed, .reuse));
    for (ignored) |location| {
        field(&hash, "ignored", location);
        try addIgnored(gpa, a, io, root, &hash, location);
    }
    try addState(a, io, state, &hash);
    return .{ .reuse = std.fmt.bytesToHex(hash.finalResult(), .lower), .confirmation = try listedDigest(gpa, io, root, listed, .confirmation) };
}

pub fn begin(a: std.mem.Allocator, io: std.Io, state: []const u8, nonce: []const u8, run: []const u8) !void {
    var pending = try openPending(a, io, state);
    defer pending.close(io);
    try pending.writeFile(io, .{ .sub_path = try markName(a, nonce, run), .data = "pending\n" });
}

fn markName(a: std.mem.Allocator, nonce: []const u8, run: []const u8) ![]const u8 {
    return std.fmt.allocPrint(a, "{s}-{s}", .{ nonce, run });
}

/// Clears this build's mark for `run` when the listed files still match
/// `recorded`. Otherwise the mark stays, the change is recorded, and it fails.
pub fn confirm(gpa: std.mem.Allocator, io: std.Io, root: std.Io.Dir, recorded: []const u8, state: []const u8, nonce: []const u8, run: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    const current = try listedDigest(gpa, io, root, try listing(a, io, root), .confirmation);
    if (!std.mem.eql(u8, &current, recorded)) {
        var directory = try std.Io.Dir.cwd().openDir(io, state, .{});
        defer directory.close(io);
        const log = try directory.createFile(io, "changed", .{ .truncate = false });
        defer log.close(io);
        try log.writePositionalAll(io, try std.fmt.allocPrint(a, "{s}: {s} -> {s}\n", .{ run, recorded, &current }), (try log.stat(io)).size);
        return error.TestRunInputsChangedDuringBuild;
    }
    var pending = try openPending(a, io, state);
    defer pending.close(io);
    try pending.deleteFile(io, try markName(a, nonce, run));
}

fn openPending(a: std.mem.Allocator, io: std.Io, state: []const u8) !std.Io.Dir {
    const path = try std.fs.path.join(a, &.{ state, "pending" });
    try std.Io.Dir.cwd().createDirPath(io, path);
    return std.Io.Dir.cwd().openDir(io, path, .{});
}

/// Hashes every file under `state` by relative path and bytes. Only files count,
/// so a missing directory and an empty one give the same key.
fn addState(a: std.mem.Allocator, io: std.Io, state: []const u8, hash: *Hash) !void {
    var directory = std.Io.Dir.cwd().openDir(io, state, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer directory.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var walker = try directory.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .directory) try names.append(a, try a.dupe(u8, entry.path));
    }
    std.mem.sort([]const u8, names.items, {}, less);
    for (names.items) |name| {
        field(hash, "state", name);
        field(hash, "bytes", try directory.readFileAlloc(io, name, a, .limited(16 * 1024 * 1024)));
    }
}

const Entry = struct { path: []const u8, user_excluded: bool };
const Listing = struct { revision: []const u8, git_version: []const u8, entries: []const Entry };

fn listing(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !Listing {
    // The repository's own ignore files decide what is keyed. A path that only a
    // user's global or local exclude hides is still keyed, but by metadata alone,
    // because the user may have hidden it for a reason.
    var standard: std.StringHashMapUnmanaged(void) = .empty;
    var standard_names = std.mem.tokenizeScalar(u8, try git(a, io, root, &.{ "ls-files", "--cached", "--others", "--exclude-standard", "-z" }), 0);
    while (standard_names.next()) |path| try standard.put(a, path, {});
    var paths: std.ArrayList([]const u8) = .empty;
    var names = std.mem.tokenizeScalar(u8, try git(a, io, root, &.{ "ls-files", "--cached", "--others", "--exclude-per-directory=.gitignore", "-z" }), 0);
    while (names.next()) |path| try paths.append(a, path);
    std.mem.sort([]const u8, paths.items, {}, less);
    var entries: std.ArrayList(Entry) = .empty;
    for (paths.items, 0..) |path, index| {
        if (index > 0 and std.mem.eql(u8, paths.items[index - 1], path)) continue;
        try entries.append(a, .{ .path = path, .user_excluded = !standard.contains(path) });
    }
    return .{
        .revision = try git(a, io, root, &.{ "rev-parse", "HEAD" }),
        .git_version = try git(a, io, root, &.{"--version"}),
        .entries = try entries.toOwnedSlice(a),
    };
}

const Purpose = enum { reuse, confirmation };

fn listedDigest(gpa: std.mem.Allocator, io: std.Io, root: std.Io.Dir, listed: Listing, purpose: Purpose) !Digest {
    var hash: Hash = .init(.{});
    field(&hash, "schema", @tagName(purpose));
    field(&hash, "revision", listed.revision);
    field(&hash, "git", listed.git_version);
    for (listed.entries) |entry| {
        if (purpose == .confirmation and (entry.user_excluded or credential_paths.excluded(entry.path))) continue;
        field(&hash, "path", entry.path);
        try addListed(gpa, io, root, &hash, entry, purpose);
    }
    return std.fmt.bytesToHex(hash.finalResult(), .lower);
}

fn addListed(gpa: std.mem.Allocator, io: std.Io, root: std.Io.Dir, hash: *Hash, entry: Entry, purpose: Purpose) !void {
    const parent_name = std.fs.path.dirname(entry.path);
    const parent = if (parent_name) |name| directory_access.open(io, root, name) catch |err| switch (err) {
        // A tracked file whose directory was deleted from the working tree.
        error.DirectoryMissing => return field(hash, "state", "deleted"),
        else => return err,
    } else root;
    defer if (parent_name != null) parent.close(io);
    try addEntry(gpa, io, parent, std.fs.path.basename(entry.path), entry.path, entry.user_excluded, purpose, hash);
}

fn addEntry(gpa: std.mem.Allocator, io: std.Io, parent: std.Io.Dir, name: []const u8, path: []const u8, user_excluded: bool, purpose: Purpose, hash: *Hash) !void {
    const stat = parent.statFile(io, name, .{ .follow_symlinks = false }) catch |err| switch (err) {
        error.FileNotFound => return field(hash, "state", "deleted"),
        else => return err,
    };
    if (credential_paths.excluded(path) or user_excluded) {
        field(hash, "state", "metadata");
        number(hash, stat.size);
        number(hash, @bitCast(@as(i128, stat.mtime.nanoseconds)));
        return;
    }
    switch (stat.kind) {
        .file => {
            if (stat.nlink > 1) return error.MultiplyLinkedTestRunInput;
            field(hash, "state", if (stat.permissions.toMode() & 0o111 != 0) "executable" else "file");
            const bytes = (try file_access.capture(io, gpa, parent, name, null, std.math.maxInt(usize) - 1)) orelse return error.TestRunInputChanged;
            defer gpa.free(bytes);
            field(hash, "bytes", bytes);
            if (purpose == .confirmation) {
                number(hash, @bitCast(@as(i128, stat.ctime.nanoseconds)));
                number(hash, stat.inode);
            }
        },
        .sym_link => return error.SymbolicLinkTestRunInput,
        else => |kind| field(hash, "state", @tagName(kind)),
    }
}

fn addIgnored(gpa: std.mem.Allocator, a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, hash: *Hash, location: []const u8) !void {
    const parent_name = std.fs.path.dirname(location) orelse return error.InvalidIgnoredLocation;
    var parent = directory_access.open(io, root, parent_name) catch |err| switch (err) {
        error.DirectoryMissing => return field(hash, "state", "missing"),
        else => return err,
    };
    defer parent.close(io);
    try addTree(gpa, a, io, parent, parent_name, std.fs.path.basename(location), hash);
}

/// Hashes, in name order, every entry of `directory` whose name starts with
/// `prefix`, descending into directories through the same no-follow access.
fn addTree(gpa: std.mem.Allocator, a: std.mem.Allocator, io: std.Io, directory: std.Io.Dir, directory_path: []const u8, prefix: []const u8, hash: *Hash) !void {
    var names: std.ArrayList([]const u8) = .empty;
    var entries = directory.iterate();
    while (try entries.next(io)) |entry| {
        if (std.mem.startsWith(u8, entry.name, prefix)) try names.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, less);
    for (names.items) |name| {
        const path = try std.fmt.allocPrint(a, "{s}/{s}", .{ directory_path, name });
        field(hash, "entry", path);
        const stat = try directory.statFile(io, name, .{ .follow_symlinks = false });
        if (stat.kind == .directory and !credential_paths.excluded(path)) {
            var child = try directory_access.open(io, directory, name);
            defer child.close(io);
            try addTree(gpa, a, io, child, path, "", hash);
        } else try addEntry(gpa, io, directory, name, path, false, .reuse, hash);
    }
}

fn field(hash: *Hash, name: []const u8, value: []const u8) void {
    hash.update(name);
    hash.update(&.{0});
    number(hash, value.len);
    hash.update(value);
}

fn number(hash: *Hash, value: u128) void {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(u128, &bytes, value, .little);
    hash.update(&bytes);
}

fn less(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn git(a: std.mem.Allocator, io: std.Io, root: std.Io.Dir, args: []const []const u8) ![]const u8 {
    const argv = try a.alloc([]const u8, args.len + 1);
    argv[0] = "git";
    @memcpy(argv[1..], args);
    const result = try std.process.run(a, io, .{ .argv = argv, .cwd = .{ .dir = root } });
    if (result.term != .exited or result.term.exited != 0) return error.TestRunKeyUnavailable;
    return result.stdout;
}

const Repository = struct {
    directory: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,

    fn init() !Repository {
        var repository: Repository = .{ .directory = std.testing.tmpDir(.{}), .arena = .init(std.testing.allocator) };
        errdefer repository.deinit();
        try repository.runGit(&.{ "-c", "init.templateDir=", "init", "-q" });
        try repository.write(".gitignore", "evidence/\nstate/\n");
        try repository.write("data.txt", "original");
        try repository.runGit(&.{ "add", "-A" });
        try repository.runGit(&.{ "-c", "user.name=SDDE test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "-qm", "baseline" });
        return repository;
    }

    fn deinit(self: *Repository) void {
        self.arena.deinit();
        self.directory.cleanup();
    }

    fn runGit(self: *Repository, args: []const []const u8) !void {
        _ = try git(self.arena.allocator(), std.testing.io, self.directory.dir, args);
    }

    fn write(self: *Repository, path: []const u8, data: []const u8) !void {
        try self.directory.dir.writeFile(std.testing.io, .{ .sub_path = path, .data = data });
    }

    /// The state directory as an absolute path, as `apply` passes it.
    fn state(self: *Repository) ![]const u8 {
        const root = try self.directory.dir.realPathFileAlloc(std.testing.io, ".", self.arena.allocator());
        return std.fs.path.join(self.arena.allocator(), &.{ root, "state" });
    }

    fn captureKey(self: *Repository) !Key {
        return capture(std.testing.allocator, std.testing.io, self.directory.dir, try self.state(), &.{"evidence/run"});
    }

    fn key(self: *Repository) !Digest {
        return (try self.captureKey()).reuse;
    }

    fn setTime(self: *Repository, path: []const u8, time: std.Io.Timestamp) !void {
        const file = try self.directory.dir.openFile(std.testing.io, path, .{ .mode = .read_write });
        defer file.close(std.testing.io);
        try file.setTimestamps(std.testing.io, .{ .modify_timestamp = .{ .new = time } });
    }
};

fn expectChanged(before: Digest, after: Digest) !void {
    try std.testing.expect(!std.mem.eql(u8, &before, &after));
}

const fixed_time: std.Io.Timestamp = .{ .nanoseconds = 1_700_000_000 * std.time.ns_per_s };

test "test-run key is stable and changes with tracked bytes, binary bytes, deletion and the executable bit" {
    const io = std.testing.io;
    var repository: Repository = try .init();
    defer repository.deinit();
    const clean = try repository.key();
    const repeated = try repository.key();
    try std.testing.expectEqualStrings(&clean, &repeated);

    try repository.write("data.txt", "modified");
    const modified = try repository.key();
    try expectChanged(clean, modified);

    try repository.write("binary.dat", &.{ 0xff, 0x00 });
    const binary = try repository.key();
    try repository.write("binary.dat", &.{ 0xfe, 0x00 });
    try expectChanged(binary, try repository.key());
    try repository.directory.dir.deleteFile(io, "binary.dat");

    const data = try repository.directory.dir.openFile(io, "data.txt", .{});
    try data.setPermissions(io, .fromMode(0o755));
    data.close(io);
    const executable = try repository.key();
    try expectChanged(modified, executable);

    try repository.directory.dir.deleteFile(io, "data.txt");
    try expectChanged(executable, try repository.key());
}

test "test-run key refuses symbolic links, symlinked directories and hard links" {
    const io = std.testing.io;
    var repository: Repository = try .init();
    defer repository.deinit();
    try repository.directory.dir.symLink(io, "data.txt", "link.txt", .{});
    try std.testing.expectError(error.SymbolicLinkTestRunInput, repository.key());
    try repository.directory.dir.deleteFile(io, "link.txt");

    try repository.directory.dir.createDirPath(io, "evidence/run-1");
    try repository.directory.dir.symLink(io, "../../data.txt", "evidence/run-1/linked.json", .{});
    try std.testing.expectError(error.SymbolicLinkTestRunInput, repository.key());
    try repository.directory.dir.deleteFile(io, "evidence/run-1/linked.json");

    try repository.write("other.txt", "other");
    try repository.directory.dir.hardLink("other.txt", repository.directory.dir, "alias.txt", io, .{});
    try std.testing.expectError(error.MultiplyLinkedTestRunInput, repository.key());
    try repository.directory.dir.deleteFile(io, "alias.txt");

    try repository.directory.dir.createDir(io, "real", .default_dir);
    try repository.directory.dir.createDir(io, "nested", .default_dir);
    try repository.write("nested/file.txt", "tracked under a directory");
    try repository.runGit(&.{ "add", "nested/file.txt" });
    try repository.directory.dir.deleteFile(io, "nested/file.txt");
    try repository.directory.dir.deleteDir(io, "nested");
    try repository.directory.dir.symLink(io, "real", "nested", .{ .is_directory = true });
    // Ignoring the link itself leaves only the tracked file beneath it to refuse.
    try repository.write(".gitignore", "evidence/\nstate/\nnested\n");
    try std.testing.expectError(error.DirectoryUnavailable, repository.key());
}

test "test-run key covers named ignored locations and only them" {
    const io = std.testing.io;
    var repository: Repository = try .init();
    defer repository.deinit();
    const missing = try repository.key();
    try repository.directory.dir.createDirPath(io, "evidence/run-1/nested");
    try repository.write("evidence/run-1/nested/result.json", "first");
    const present = try repository.key();
    try expectChanged(missing, present);
    try repository.write("evidence/run-1/nested/result.json", "second");
    const rewritten = try repository.key();
    try expectChanged(present, rewritten);
    try repository.write("evidence/unrelated.json", "not a listed location");
    const unrelated = try repository.key();
    try std.testing.expectEqualStrings(&rewritten, &unrelated);
}

test "test-run key keys credentials and user-excluded files by size and modification time, never by content" {
    const io = std.testing.io;
    var repository: Repository = try .init();
    defer repository.deinit();
    try repository.directory.dir.createDirPath(io, ".git/info");
    try repository.write(".git/info/exclude", "secret.token\n");
    for ([_][]const u8{ ".env.local", "secret.token" }) |path| {
        const before = try repository.key();
        try repository.write(path, "MOCK_SECRET_ONE");
        try repository.setTime(path, fixed_time);
        const first = try repository.key();
        try expectChanged(before, first);

        // Same size and time with different bytes: the content never reaches the key.
        try repository.write(path, "MOCK_SECRET_TWO");
        try repository.setTime(path, fixed_time);
        const same_metadata = try repository.key();
        try std.testing.expectEqualStrings(&first, &same_metadata);

        try repository.setTime(path, .{ .nanoseconds = fixed_time.nanoseconds + std.time.ns_per_s });
        try expectChanged(first, try repository.key());
        try repository.write(path, "MOCK_SECRET_LONGER");
        try repository.setTime(path, fixed_time);
        try expectChanged(first, try repository.key());

        // An unreadable file still keys; under root the file stays readable.
        const file = try repository.directory.dir.openFile(io, path, .{});
        try file.setPermissions(io, .fromMode(0));
        file.close(io);
        _ = try repository.key();
    }
}

test "test-run confirmation clears a run's pending mark only when nothing changed" {
    const io = std.testing.io;
    var repository: Repository = try .init();
    defer repository.deinit();
    const a = repository.arena.allocator();
    const state = try repository.state();
    const clean = try repository.captureKey();

    // A confirmed run returns the state to where it was, so its result is reused.
    try begin(a, io, state, "build-a", "run-0");
    try expectChanged(clean.reuse, try repository.key());
    try confirm(std.testing.allocator, io, repository.directory.dir, &clean.confirmation, state, "build-a", "run-0");
    const confirmed = try repository.key();
    try std.testing.expectEqualStrings(&clean.reuse, &confirmed);

    // A run that never confirms, because it failed or was interrupted, keeps its mark.
    try begin(a, io, state, "build-b", "run-0");
    const unconfirmed = try repository.key();
    try expectChanged(clean.reuse, unconfirmed);
    const repeated = try repository.key();
    try std.testing.expectEqualStrings(&unconfirmed, &repeated);

    // A later build confirming the same run, for another binary or environment,
    // clears only its own mark, so the earlier result stays unusable.
    try begin(a, io, state, "build-c", "run-0");
    try confirm(std.testing.allocator, io, repository.directory.dir, &clean.confirmation, state, "build-c", "run-0");
    const after_later_build = try repository.key();
    try std.testing.expectEqualStrings(&unconfirmed, &after_later_build);
}

test "test-run confirmation fails closed on an edit, a reverted edit or an unreadable listing" {
    const io = std.testing.io;
    var repository: Repository = try .init();
    defer repository.deinit();
    const a = repository.arena.allocator();
    const state = try repository.state();
    const clean = try repository.captureKey();

    try begin(a, io, state, "build", "edited");
    try repository.write("data.txt", "edited during the build");
    try std.testing.expectError(error.TestRunInputsChangedDuringBuild, confirm(std.testing.allocator, io, repository.directory.dir, &clean.confirmation, state, "build", "edited"));

    // Restoring the bytes changes the change time, so the revert is still a change.
    try repository.write("data.txt", "original");
    try begin(a, io, state, "build", "reverted");
    try std.testing.expectError(error.TestRunInputsChangedDuringBuild, confirm(std.testing.allocator, io, repository.directory.dir, &clean.confirmation, state, "build", "reverted"));

    // An error while confirming leaves the mark set.
    try begin(a, io, state, "build", "unreadable");
    try repository.directory.dir.symLink(io, "data.txt", "link.txt", .{});
    try std.testing.expectError(error.SymbolicLinkTestRunInput, confirm(std.testing.allocator, io, repository.directory.dir, &clean.confirmation, state, "build", "unreadable"));
    try repository.directory.dir.deleteFile(io, "link.txt");

    try expectChanged(clean.reuse, try repository.key());
    var pending = try repository.directory.dir.openDir(io, "state/pending", .{});
    defer pending.close(io);
    for ([_][]const u8{ "build-edited", "build-reverted", "build-unreadable" }) |mark| _ = try pending.statFile(io, mark, .{});
}
