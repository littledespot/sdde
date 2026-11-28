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

/// The engine runs a retained run's project holds that are not its own. A case's second leg starts from a copy of its
/// first leg's project, so it holds the first leg's engine run beside the one it added, and owns only the one it added.
/// `continued_from` names the first leg, a run directory beside the run whose path under `root` is `path`; with none,
/// the run inherited nothing. A name that is no run directory's, or is the run's own, is an `InvalidReport`, and a missing
/// first leg is an error: neither is ever read as an empty set.
pub fn inherited(io: std.Io, a: std.mem.Allocator, root: std.Io.Dir, path: []const u8, continued_from: ?[]const u8) ![]const []const u8 {
    const name = continued_from orelse return &.{};
    if (!isRunName(name) or std.mem.eql(u8, name, std.fs.path.basename(path))) return error.InvalidReport;
    const beside = if (std.fs.path.dirname(path)) |parent| try std.fs.path.join(a, &.{ parent, name }) else name;
    var first = try directories.open(io, root, beside);
    defer first.close(io);
    var segments: std.ArrayList([]const u8) = .empty;
    try eventLogs(io, a, first, "project", &segments);
    var owners: std.ArrayList([]const u8) = .empty;
    for (segments.items) |segment| {
        const owner = engineRun(segment);
        if (!isInherited(owners.items, owner)) try owners.append(a, owner);
    }
    return owners.toOwnedSlice(a);
}

/// The engine run a feature log segment belongs to: `.../<engine run>/<binding>/<segment>.log`.
pub fn engineRun(segment: []const u8) []const u8 {
    return std.fs.path.basename(std.fs.path.dirname(std.fs.path.dirname(segment).?).?);
}

/// Whether `run` is one of the engine runs `runs` names.
pub fn isInherited(runs: []const []const u8, run: []const u8) bool {
    for (runs) |held| if (std.mem.eql(u8, held, run)) return true;
    return false;
}

/// Whether `name` has the shape `directoryName` gives a run directory: a UTC time with `-` for `:`, then 32 hex digits.
pub fn isRunName(name: []const u8) bool {
    if (name.len != 53) return false;
    for (name, 0..) |char, at| {
        const valid = switch (at) {
            4, 7, 13, 16, 20 => char == '-',
            10 => char == 'T',
            19 => char == 'Z',
            0...3, 5...6, 8...9, 11...12, 14...15, 17...18 => std.ascii.isDigit(char),
            else => std.ascii.isDigit(char) or (char >= 'a' and char <= 'f'),
        };
        if (!valid) return false;
    }
    return true;
}

test "a run name has the shape of a run directory's and nothing else does" {
    const name = directoryName("2026-11-27T08-48-56Z".*, .{0xab} ** 16);
    try std.testing.expect(isRunName(&name));
    try std.testing.expect(isRunName("2026-11-27T08-48-56Z-74b1a2cfe51c25d38a161e475a494183"));
    for ([_][]const u8{
        "",
        "one",
        "../2026-11-27T08-48-56Z-74b1a2cfe51c25d38a161e475a494183",
        "2026-11-27T08:48:56Z-74b1a2cfe51c25d38a161e475a494183",
        "2026-11-27T08-48-56Z-74B1A2CFE51C25D38A161E475A494183",
        "2026-11-27T08-48-56Z-74b1a2cfe51c25d38a161e475a49418",
        "2026-11-27T08-48-56Z_74b1a2cfe51c25d38a161e475a494183",
    }) |rejected| try std.testing.expect(!isRunName(rejected));
}

/// Every feature event log segment under `path`, as `<path>/.../logs/events/<engine run>/<binding>/<segment>.log`.
pub fn eventLogs(io: std.Io, a: std.mem.Allocator, run: std.Io.Dir, path: []const u8, segments: *std.ArrayList([]const u8)) !void {
    var dir = directories.open(io, run, path) catch |err| switch (err) {
        error.DirectoryMissing => return,
        else => return err,
    };
    defer dir.close(io);
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        const child = try std.fmt.allocPrint(a, "{s}/{s}", .{ path, entry.name });
        switch (entry.kind) {
            .directory => try eventLogs(io, a, run, child, segments),
            .file => if (std.mem.indexOf(u8, child, "/logs/events/") != null and std.mem.endsWith(u8, child, ".log")) try segments.append(a, child),
            else => {},
        }
    }
}

pub fn directoryName(timestamp: [20]u8, random: [16]u8) [53]u8 {
    var name: [53]u8 = undefined;
    @memcpy(name[0..20], &timestamp);
    name[13] = '-';
    name[16] = '-';
    name[20] = '-';
    @memcpy(name[21..], &std.fmt.bytesToHex(random, .lower));
    return name;
}
