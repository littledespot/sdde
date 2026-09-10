const std = @import("std");
const directories = @import("../../../src/adapters/filesystem/directory_access.zig");

pub const Run = struct {
    dir: std.Io.Dir,
    project: std.Io.Dir,
    name: [53]u8,
    started_at_utc: [20]u8,

    pub fn create(io: std.Io, parent: std.Io.Dir) !Run {
        var random: [16]u8 = undefined;
        try io.randomSecure(&random);
        var clock: @import("../../../src/adapters/system/trusted_log_clock.zig").Adapter = .{ .io = io };
        const reading = try clock.clock().now();
        const name = directoryName(reading.occurred_at_utc, random);
        try parent.createDir(io, &name, .default_dir);
        const dir = try directories.open(io, parent, &name);
        errdefer dir.close(io);
        try dir.createDir(io, "project", .default_dir);
        const project = try directories.open(io, dir, "project");
        return .{ .dir = dir, .project = project, .name = name, .started_at_utc = reading.occurred_at_utc };
    }

    /// Retain the isolated project and report, but release every descriptor.
    pub fn close(self: Run, io: std.Io) void {
        self.project.close(io);
        self.dir.close(io);
    }
};

pub fn directoryName(timestamp: [20]u8, random: [16]u8) [53]u8 {
    var name: [53]u8 = undefined;
    @memcpy(name[0..20], &timestamp);
    name[13] = '-';
    name[16] = '-';
    name[20] = '-';
    @memcpy(name[21..], &std.fmt.bytesToHex(random, .lower));
    return name;
}
