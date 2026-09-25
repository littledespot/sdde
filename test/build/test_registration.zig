//! Validate discovery without executing the synthetic test processes.
const std = @import("std");
const registration = @import("test_registration.zig");

pub fn build(b: *std.Build) void {
    verify(b) catch |err| std.debug.panic("test registration regression: {s}", .{@errorName(err)});
    _ = b.step("test", "Validate test registration");
}

fn verify(b: *std.Build) !void {
    const root = b.step("synthetic-suite", "Synthetic suite");
    const shared = std.Build.Step.Run.create(b, "shared repository tests");
    shared.stdio = .zig_test;
    const dependency = std.Build.Step.Run.create(b, "dependency-module tests");
    dependency.stdio = .zig_test;
    root.dependOn(&shared.step);
    root.dependOn(&dependency.step);
    const diamond = b.step("diamond", "Repeated references execute the same step once");
    diamond.dependOn(&shared.step);
    root.dependOn(diamond);
    const registered = [_]*std.Build.Step.Run{ shared, dependency };
    try registration.check(b.allocator, root, &registered);
    try std.testing.expectError(error.UnregisteredTestExecution, registration.check(b.allocator, root, &.{shared}));
    const missing = std.Build.Step.Run.create(b, "missing required group");
    missing.stdio = .zig_test;
    try std.testing.expectError(error.MissingTestExecution, registration.check(b.allocator, root, &.{ shared, dependency, missing }));
    const duplicate = std.Build.Step.Run.create(b, "separate run of overlapping tests");
    duplicate.stdio = .zig_test;
    diamond.dependOn(&duplicate.step);
    try std.testing.expectError(error.UnregisteredTestExecution, registration.check(b.allocator, root, &registered));
}
