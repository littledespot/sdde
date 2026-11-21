//! The files a workflow definition's `resources:` block names, read from the definition itself so that no test
//! or packaging step keeps its own list of a workflow's assets.
const std = @import("std");

/// Each resource's path under the definition's directory, in declaration order.
pub fn paths(comptime definition: []const u8) []const []const u8 {
    comptime {
        @setEvalBranchQuota(200_000);
        var count: usize = 0;
        var lines = std.mem.splitScalar(u8, definition, '\n');
        var inside = false;
        while (lines.next()) |line| {
            if (!inside) {
                inside = std.mem.eql(u8, line, "resources:");
                continue;
            }
            if (!std.mem.startsWith(u8, line, "  ")) break;
            count += 1;
        }
        if (count == 0) @compileError("the definition names no resources");
        var result: [count][]const u8 = undefined;
        var index: usize = 0;
        lines = std.mem.splitScalar(u8, definition, '\n');
        inside = false;
        while (lines.next()) |line| {
            if (!inside) {
                inside = std.mem.eql(u8, line, "resources:");
                continue;
            }
            if (!std.mem.startsWith(u8, line, "  ")) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse @compileError("a resource line names no path");
            result[index] = std.mem.trim(u8, line[colon + 1 ..], " ");
            index += 1;
        }
        const final = result;
        return &final;
    }
}
