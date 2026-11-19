const std = @import("std");

const Io = std.Io;

pub const Error = error{ ArtifactStorageUnavailable, InsecurePermissions, Cancelled };

pub fn openOwner(io: Io, root: Io.Dir, path: []const u8) !Io.Dir {
    return @import("directory_access.zig").open(io, root, path);
}

/// What a failed directory call is to the sink's activation: a cancellation request, or an unavailable
/// store.
pub fn storageFault(err: anyerror) Error {
    return if (err == error.Canceled or err == error.Cancelled) error.Cancelled else error.ArtifactStorageUnavailable;
}

pub fn validateOwner(io: Io, directory: Io.Dir) Error!void {
    const stat = directory.stat(io) catch |err| return storageFault(err);
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
