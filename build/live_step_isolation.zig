//! Live harness execution cannot be a dependency of automated verification.
const std = @import("std");

pub fn check(allocator: std.mem.Allocator, root: *std.Build.Step, manual: []const *std.Build.Step) !void {
    var pending: std.ArrayList(*std.Build.Step) = .empty;
    defer pending.deinit(allocator);
    var visited: std.AutoHashMap(*std.Build.Step, void) = .init(allocator);
    defer visited.deinit();
    try pending.append(allocator, root);
    while (pending.pop()) |step| {
        for (manual) |live| if (step == live) return error.LiveModelDependency;
        if ((try visited.getOrPut(step)).found_existing) continue;
        try pending.appendSlice(allocator, step.dependencies.items);
    }
}
