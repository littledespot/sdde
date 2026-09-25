//! An isolated build fixture; none of these steps execute a model or command.
const std = @import("std");
const isolation = @import("live_step_isolation.zig");

pub fn build(b: *std.Build) void {
    verify(b) catch |err| std.debug.panic("live-step isolation regression: {s}", .{@errorName(err)});
}

fn verify(b: *std.Build) !void {
    const tests = b.step("test", "Safe automated root");
    const compile_harness = b.step("compile-harness", "Building a harness does not execute it");
    const shared = b.step("shared", "Shared safe dependency");
    tests.dependOn(shared);
    tests.dependOn(compile_harness);
    compile_harness.dependOn(shared);
    const generation = b.step("manual-generation", "Manual generation");
    const evaluation = b.step("manual-evaluation", "Manual evaluation");
    generation.dependOn(compile_harness);
    evaluation.dependOn(compile_harness);
    const live = [_]*std.Build.Step{ generation, evaluation };
    try isolation.check(b.allocator, tests, &live);
    for (live, 0..) |selected, index| {
        try std.testing.expectError(error.LiveModelDependency, isolation.check(b.allocator, selected, &live));
        const direct = b.step(b.fmt("direct-{d}", .{index}), "Forbidden direct dependency");
        direct.dependOn(selected);
        try std.testing.expectError(error.LiveModelDependency, isolation.check(b.allocator, direct, &live));
        const indirect = b.step(b.fmt("indirect-{d}", .{index}), "Forbidden transitive dependency");
        indirect.dependOn(shared);
        indirect.dependOn(direct);
        try std.testing.expectError(error.LiveModelDependency, isolation.check(b.allocator, indirect, &live));
    }
}
