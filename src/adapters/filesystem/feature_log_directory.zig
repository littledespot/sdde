const std = @import("std");

const Io = std.Io;

pub const Error = error{ ArtifactStorageUnavailable, InsecurePermissions };

pub fn openOwner(io: Io, root: Io.Dir, path: []const u8) !Io.Dir {
    return @import("directory_access.zig").open(io, root, path);
}

pub fn validateOwner(io: Io, directory: Io.Dir) Error!void {
    const stat = directory.stat(io) catch return error.ArtifactStorageUnavailable;
    if (stat.kind != .directory) return error.ArtifactStorageUnavailable;
    if (@hasDecl(Io.File.Permissions, "toMode") and stat.permissions.toMode() & 0o077 != 0) {
        return error.InsecurePermissions;
    }
}

test "log directory access supports nested feature keys without following any ancestor symlink" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDirPath(io, "Group/Café/logs/events/run/binding");
    var accepted = try openOwner(io, project.dir, "Group/Café/logs/events/run/binding");
    accepted.close(io);
    try project.dir.symLink(io, "Group", "Alias", .{ .is_directory = true });
    try std.testing.expectError(error.DirectoryUnavailable, openOwner(io, project.dir, "Alias/Café/logs/events/run/binding"));
}
