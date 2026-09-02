const std = @import("std");

const Io = std.Io;

pub const Error = error{ ArtifactStorageUnavailable, InsecurePermissions };

pub fn openOwner(io: Io, root: Io.Dir, path: []const u8) !Io.Dir {
    return root.openDir(io, path, .{
        .iterate = true,
        .follow_symlinks = false,
    });
}

pub fn validateOwner(io: Io, directory: Io.Dir) Error!void {
    const stat = directory.stat(io) catch return error.ArtifactStorageUnavailable;
    if (stat.kind != .directory) return error.ArtifactStorageUnavailable;
    if (@hasDecl(Io.File.Permissions, "toMode") and stat.permissions.toMode() & 0o077 != 0) {
        return error.InsecurePermissions;
    }
}
