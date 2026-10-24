//! Fresh test runs by default, and opt-in reuse of unchanged ones
//! (`zig build <step> -Dreuse-test-runs`).
//!
//! By default every test run is marked as having side effects, so it reruns on every
//! `zig build`, even with an explicit `--seed`. With the option, each test run gets a
//! pinned seed and is keyed on a digest of the repository (`test_run_key.zig`), on
//! the ignored locations that tests read (`test_run_inputs.zig`), on an explicit
//! environment and on its working directory. A passing run is then reused only when
//! none of those, its binary or its arguments changed since that step last ran. Zig
//! keeps only the latest result per run and never caches a failing run.
//!
//! Each keyed run is marked pending in the cache root before it starts, under a name
//! unique to the build, and only its own confirmation clears the mark, after checking
//! that the Git-listed files didn't change while it ran. Remaining marks join every
//! later key, so a run that failed, was interrupted, couldn't be confirmed or saw
//! edited files is never reused, whatever builds follow. Only one opt-in build at a
//! time may use a cache, because concurrent builds would share its build file.
//! Steps that produce verification evidence refuse the option and run nothing.
const std = @import("std");
const Step = std.Build.Step;

pub const option_name = "reuse-test-runs";
pub const option_description = "Reuse a passing test run only when nothing it depends on changed; refused by verify";

/// The only variables an opt-in test run receives; their values join its key.
pub const passed_environment = [_][]const u8{ "PATH", "HOME" };

pub const Options = struct {
    reuse: bool,
    /// The key tool executable; required when `reuse` is set.
    key_tool: ?std.Build.LazyPath,
    /// Ignored locations that tests read.
    ignored: []const []const u8,
    /// Steps that produce verification evidence and must run every test fresh.
    fresh: []const *Step,
};

/// `build` calls this last, on the complete, checked graph. A test run added after
/// it is neither marked fresh nor keyed.
pub fn apply(b: *std.Build, options: Options) !void {
    const runs = try closure(b, &.{});
    if (!options.reuse) {
        for (runs) |run| run.has_side_effects = true;
        return;
    }
    const tool = options.key_tool orelse return error.MissingTestRunKey;
    // Pending marks live beside the results they guard, not in the checkout.
    const cache_root = try b.cache_root.handle.realPathFileAlloc(b.graph.io, ".", b.allocator);
    const state = b.pathJoin(&.{ cache_root, "test-run-reuse" });
    try holdStateLock(b, state);
    const capture = keyToolRun(b, tool, "capture test-run key");
    capture.addArg("capture");
    const key = capture.addOutputFileArg("test-run-key.txt");
    // The build's nonce and confirmation digest; test runs don't take it as input.
    const build_file = capture.addOutputFileArg("test-run-build.txt");
    capture.addArg(state);
    capture.addArgs(options.ignored);
    var confirmations: std.AutoHashMap(*Step.Run, *Step.Run) = .init(b.allocator);
    for (runs, 0..) |run, index| {
        // Replacing an environment a run already chose would change what it tests.
        if (run.environ_map != null) return error.TestRunEnvironmentAlreadySet;
        try pinSeed(b, run);
        run.clearEnvironment();
        for (passed_environment) |name| {
            if (b.graph.environ_map.get(name)) |value| run.setEnvironmentVariable(name, value);
        }
        // An inherited working directory isn't hashed; an explicit one is.
        if (run.cwd == null) run.setCwd(.{ .cwd_relative = b.graph.cache.cwd });
        run.addFileInput(key);

        const id = b.fmt("run-{d}", .{index});
        // Reading the build file orders the mark after the key is captured, so it
        // changes only later keys.
        const begin = keyToolRun(b, tool, b.fmt("mark test run {d} pending", .{index}));
        begin.addArg("begin");
        begin.addFileArg(build_file);
        begin.addArgs(&.{ state, id });
        run.step.dependOn(&begin.step);
        const confirmation = keyToolRun(b, tool, b.fmt("confirm test run {d} inputs", .{index}));
        confirmation.addArg("confirm");
        confirmation.addFileArg(build_file);
        confirmation.addArgs(&.{ state, id });
        confirmation.step.dependOn(&run.step);
        try confirmations.put(run, confirmation);
    }
    for (options.fresh) |step| {
        // The build runner derives scheduling from `dependencies` after `build`
        // returns, so the refusal replaces them and nothing else starts.
        step.dependencies.clearRetainingCapacity();
        step.dependOn(&b.addFail(b.fmt("'{s}' always runs every test fresh; run it without -D{s}.", .{ step.name, option_name })).step);
    }
    // A requested step finishes only after every run it holds is confirmed.
    for (b.top_level_steps.values()) |entry| {
        for (try closure(b, &.{&entry.step})) |run| entry.step.dependOn(&confirmations.get(run).?.step);
    }
}

/// Takes the cache's opt-in lock for the life of this build runner. The operating
/// system releases it when the process exits, including after a crash.
fn holdStateLock(b: *std.Build, state: []const u8) !void {
    const io = b.graph.io;
    try std.Io.Dir.cwd().createDirPath(io, state);
    const lock = try std.Io.Dir.cwd().createFile(io, b.pathJoin(&.{ state, "lock" }), .{ .truncate = false });
    if (!try lock.tryLock(io, .exclusive)) {
        lock.close(io);
        return error.AnotherOptInTestRunBuildIsRunning;
    }
    // Deliberately left open, so the lock lasts until the build runner exits.
}

fn keyToolRun(b: *std.Build, tool: std.Build.LazyPath, name: []const u8) *Step.Run {
    const run = Step.Run.create(b, name);
    run.addFileArg(tool);
    run.setCwd(b.path("."));
    // Each runs on every invocation; only the captured digest decides reuse.
    run.has_side_effects = true;
    return run;
}

/// Every test run reachable from `roots`, or from every top-level step if empty.
fn closure(b: *std.Build, roots: []const *Step) ![]const *Step.Run {
    var runs: std.ArrayList(*Step.Run) = .empty;
    var pending: std.ArrayList(*Step) = .empty;
    defer pending.deinit(b.allocator);
    var visited: std.AutoHashMap(*Step, void) = .init(b.allocator);
    defer visited.deinit();
    if (roots.len == 0) {
        for (b.top_level_steps.values()) |entry| try pending.append(b.allocator, &entry.step);
    } else try pending.appendSlice(b.allocator, roots);
    while (pending.pop()) |step| {
        if ((try visited.getOrPut(step)).found_existing) continue;
        try pending.appendSlice(b.allocator, step.dependencies.items);
        const run = step.cast(Step.Run) orelse continue;
        if (run.stdio == .zig_test) try runs.append(b.allocator, run);
    }
    return runs.toOwnedSlice(b.allocator);
}

/// Gives an unchanged binary identical arguments by replacing its random seed.
fn pinSeed(b: *std.Build, run: *Step.Run) !void {
    var pinned: usize = 0;
    for (run.argv.items) |*argument| switch (argument.*) {
        .bytes => |bytes| if (std.mem.startsWith(u8, bytes, "--seed=")) {
            argument.* = .{ .bytes = b.dupe("--seed=0x0") };
            pinned += 1;
        },
        else => {},
    };
    if (pinned != 1) return error.TestRunSeedNotFound;
}
