const std = @import("std");

const Io = std.Io;

pub const lock_name = ".stream.lock";

pub fn segmentName(ordinal: u16, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{d:0>4}.log", .{ordinal});
}

/// Exactly four ASCII digits, not all zero, then `.log`.
fn parseSegmentName(value: []const u8) ?u16 {
    if (value.len != 8 or !std.mem.endsWith(u8, value, ".log")) return null;
    for (value[0..4]) |byte| if (!std.ascii.isDigit(byte)) return null;
    const ordinal = std.fmt.parseInt(u16, value[0..4], 10) catch return null;
    return if (ordinal == 0) null else ordinal;
}

// Entries of the `logs/events` and `logs/prompts` folders are judged from the
// type the directory listing reports; nothing is opened. The engine writes only
// directories, segment files and the stream lock, which no listing reads. A
// regular file whose name is not a segment name, such as a file browser's
// `.DS_Store`, is not log history: every listing leaves it alone, so it is never
// read, deleted, counted or permission-checked. Any other entry the folder's
// level does not hold, including a symbolic link, is invalid (ADR 0026,
// log-folder entries amendment).

/// A stream collection or run directory holds directories only.
pub const ContainerEntry = enum { directory, ignored, invalid };

pub fn classifyContainerEntry(entry: Io.Dir.Entry) ContainerEntry {
    return switch (entry.kind) {
        .directory => .directory,
        .file => if (parseSegmentName(entry.name) == null) .ignored else .invalid,
        else => .invalid,
    };
}

/// A binding directory holds segment files only.
pub const BindingEntry = union(enum) { segment: u16, ignored, invalid };

pub fn classifyBindingEntry(entry: Io.Dir.Entry) BindingEntry {
    return switch (entry.kind) {
        .file => if (parseSegmentName(entry.name)) |ordinal| .{ .segment = ordinal } else .ignored,
        else => .invalid,
    };
}

pub fn ownerOnlyPermissions() Io.File.Permissions {
    return if (@hasDecl(Io.File.Permissions, "fromMode"))
        Io.File.Permissions.fromMode(0o600)
    else
        .default_file;
}

pub fn hasOwnerFilePermissions(permissions: Io.File.Permissions) bool {
    if (@hasDecl(Io.File.Permissions, "toMode")) {
        const mode = permissions.toMode();
        return mode & 0o077 == 0 and mode & 0o600 == 0o600;
    }
    return true;
}

test "segment filenames are exact and nonzero" {
    var buffer: [16]u8 = undefined;
    try std.testing.expectEqualStrings("0007.log", try segmentName(7, &buffer));
    try std.testing.expectEqual(@as(?u16, 7), parseSegmentName("0007.log"));
    for ([_][]const u8{ "0000.log", "7.log", "00007.log", "0007.LOG", "+007.log", "0_07.log", " 007.log" }) |name| {
        try std.testing.expect(parseSegmentName(name) == null);
    }
}

fn testEntry(name: []const u8, kind: Io.File.Kind) Io.Dir.Entry {
    return .{ .name = name, .kind = kind, .inode = 0 };
}

test "log folder levels leave only regular files without a segment name alone" {
    const strays = [_][]const u8{ ".DS_Store", "._0001.log", "Thumbs.db", "desktop.ini", "0001.log.bak", "0000.log", "+001.log", "0_01.log", "RUN-1", lock_name };
    const specials = [_]Io.File.Kind{ .sym_link, .named_pipe, .unix_domain_socket, .character_device, .block_device, .unknown };
    // A container holds directories; a segment there is misplaced.
    try std.testing.expectEqual(ContainerEntry.directory, classifyContainerEntry(testEntry("RUN-1", .directory)));
    try std.testing.expectEqual(ContainerEntry.invalid, classifyContainerEntry(testEntry("0001.log", .file)));
    // A binding holds segments; a directory there is misplaced.
    try std.testing.expectEqual(BindingEntry{ .segment = 7 }, classifyBindingEntry(testEntry("0007.log", .file)));
    try std.testing.expectEqual(BindingEntry.invalid, classifyBindingEntry(testEntry("nested", .directory)));
    for (strays) |name| {
        try std.testing.expectEqual(ContainerEntry.ignored, classifyContainerEntry(testEntry(name, .file)));
        try std.testing.expectEqual(BindingEntry.ignored, classifyBindingEntry(testEntry(name, .file)));
    }
    for (specials) |kind| {
        for ([_][]const u8{ ".DS_Store", "0001.log", "RUN-1" }) |name| {
            try std.testing.expectEqual(ContainerEntry.invalid, classifyContainerEntry(testEntry(name, kind)));
            try std.testing.expectEqual(BindingEntry.invalid, classifyBindingEntry(testEntry(name, kind)));
        }
    }
}
