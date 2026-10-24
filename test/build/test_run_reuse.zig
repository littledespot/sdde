//! An isolated build fixture for test-run freshness; each test counts its own runs.
const std = @import("std");
const test_run_reuse = @import("build/test_run_reuse.zig");

pub fn build(b: *std.Build) void {
    const reuse_test_runs = b.option(bool, test_run_reuse.option_name, test_run_reuse.option_description) orelse false;
    const key_tool = b.option([]const u8, "test-run-key", "Prebuilt test-run key tool");
    const counted = rootedRun(b, "counted_test.zig");
    b.step("test", "Run the counted test").dependOn(&counted.step);
    const verify = b.step("verify", "Run the counted test as verification evidence");
    verify.dependOn(&counted.step);
    b.step("mutating", "Run a test that edits a tracked file mid-run when asked").dependOn(&rootedRun(b, "mutating_test.zig").step);
    // Inherits the invocation's working directory, which reuse must key.
    b.step("inherited-cwd", "Run a test that writes where it was invoked").dependOn(&countedRun(b, "inherited_cwd_test.zig").step);
    test_run_reuse.apply(b, .{
        .reuse = reuse_test_runs,
        .key_tool = if (reuse_test_runs) .{ .cwd_relative = key_tool orelse std.debug.panic("-Dtest-run-key is required", .{}) } else null,
        .ignored = &.{"evidence/run"},
        .fresh = &.{verify},
    }) catch |err| std.debug.panic("test-run freshness wiring failed: {s}", .{@errorName(err)});
    // Added after `apply`, so it is never keyed and must never be reused.
    b.step("late", "Run a test added after the freshness wiring").dependOn(&rootedRun(b, "late_test.zig").step);
}

fn countedRun(b: *std.Build, source: []const u8) *std.Build.Step.Run {
    return b.addRunArtifact(b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path(source),
        .target = b.graph.host,
    }) }));
}

fn rootedRun(b: *std.Build, source: []const u8) *std.Build.Step.Run {
    const run = countedRun(b, source);
    run.setCwd(b.path("."));
    return run;
}
