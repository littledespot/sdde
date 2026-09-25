//! Full verification owns one repository test run plus dependency-module roots.
const std = @import("std");

pub fn check(allocator: std.mem.Allocator, root: *std.Build.Step, registered: []const *std.Build.Step.Run) !void {
    var pending: std.ArrayList(*std.Build.Step) = .empty;
    defer pending.deinit(allocator);
    var visited: std.AutoHashMap(*std.Build.Step, void) = .init(allocator);
    defer visited.deinit();
    try pending.append(allocator, root);
    while (pending.pop()) |step| {
        if ((try visited.getOrPut(step)).found_existing) continue;
        if (step.cast(std.Build.Step.Run)) |run| {
            if (run.stdio == .zig_test) {
                for (registered) |allowed| {
                    if (run == allowed) break;
                } else return error.UnregisteredTestExecution;
            }
        }
        try pending.appendSlice(allocator, step.dependencies.items);
    }
    for (registered) |required| {
        if (!visited.contains(&required.step)) return error.MissingTestExecution;
    }
}
