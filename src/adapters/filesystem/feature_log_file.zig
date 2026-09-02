const std = @import("std");

const Io = std.Io;

pub const lock_name = ".stream.lock";

pub fn segmentName(ordinal: u16, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{d:0>4}.log", .{ordinal});
}

pub fn parseSegmentName(value: []const u8) ?u16 {
    if (value.len != 8 or !std.mem.endsWith(u8, value, ".log")) return null;
    const ordinal = std.fmt.parseInt(u16, value[0..4], 10) catch return null;
    return if (ordinal == 0) null else ordinal;
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
    try std.testing.expect(parseSegmentName("0000.log") == null);
    try std.testing.expect(parseSegmentName("7.log") == null);
}
