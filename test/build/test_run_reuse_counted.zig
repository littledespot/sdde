//! Appends one line to `<file stem>.log` in the working directory each time it runs.
//! If `<file stem>.mutate` exists, it also edits the tracked `data.txt`, the way a
//! person editing during a build would. If `<file stem>.link` exists, it adds a
//! symbolic link, which makes confirming its inputs fail with an error. If
//! `<file stem>.hold` exists, it writes `<file stem>.held` and waits for
//! `<file stem>.release`, so a second build can start while it runs.
const std = @import("std");

test "count this run" {
    const io = std.testing.io;
    const stem = std.fs.path.stem(@src().file);
    var name: [64]u8 = undefined;
    const log = try std.Io.Dir.cwd().createFile(io, try std.fmt.bufPrint(&name, "{s}.log", .{stem}), .{ .truncate = false });
    defer log.close(io);
    try log.writePositionalAll(io, "run\n", (try log.stat(io)).size);
    if (try exists(io, try std.fmt.bufPrint(&name, "{s}.mutate", .{stem}))) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = "data.txt", .data = "edited during the build\n" });
    }
    if (try exists(io, try std.fmt.bufPrint(&name, "{s}.link", .{stem}))) {
        try std.Io.Dir.cwd().symLink(io, "data.txt", "mid-build-link.txt", .{});
    }
    if (try exists(io, try std.fmt.bufPrint(&name, "{s}.hold", .{stem}))) {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fmt.bufPrint(&name, "{s}.held", .{stem}), .data = "" });
        var waited: usize = 0;
        while (!try exists(io, try std.fmt.bufPrint(&name, "{s}.release", .{stem}))) : (waited += 1) {
            if (waited == 1200) return error.NeverReleased;
            try io.sleep(.fromMilliseconds(50), .awake);
        }
    }
}

fn exists(io: std.Io, path: []const u8) !bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}
