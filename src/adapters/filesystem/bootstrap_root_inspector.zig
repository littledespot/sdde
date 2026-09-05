//! No-follow directory inspection for validated configured-root candidates.

const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const root_inspector = @import("../../ports/bootstrap_root_inspector.zig");
const directories = @import("directory_access.zig");

const Io = std.Io;

pub const Adapter = struct {
    io: Io,
    invocation_working_directory: Io.Dir,

    pub fn init(io: Io, invocation_working_directory: Io.Dir) Adapter {
        return .{
            .io = io,
            .invocation_working_directory = invocation_working_directory,
        };
    }

    pub fn inspector(self: *Adapter) root_inspector.Inspector {
        return .{ .context = self, .inspect_fn = inspect };
    }

    fn inspect(
        context: *anyopaque,
        normalized_relative_path: []const u8,
    ) root_inspector.Error!bootstrap_roots.RootObservation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        var current = directories.open(self.io, self.invocation_working_directory, normalized_relative_path) catch |err| return switch (err) {
            error.DirectoryMissing => .absent,
            error.Cancelled => error.Cancelled,
            error.DirectoryUnavailable => error.BootstrapRootInspectionFailure,
        };
        defer current.close(self.io);
        const identity = directories.inspectReadable(self.io, current) catch |err| return switch (err) {
            error.Cancelled => error.Cancelled,
            else => error.BootstrapRootInspectionFailure,
        };
        return .{ .directory = identity };
    }
};

test "inspects an existing readable directory and reports an absent path" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.createDirPath(io, ".sdd/workflows");

    var adapter = Adapter.init(io, project_root.dir);
    const present = try adapter.inspector().inspect(".sdd/workflows");
    try std.testing.expect(present == .directory);
    const absent = try adapter.inspector().inspect("missing/descendant");
    try std.testing.expect(absent == .absent);
}

test "rejects regular files and symlinked path components" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{ .sub_path = "file", .data = "" });
    try project_root.dir.createDir(io, "real", .default_dir);
    try project_root.dir.symLink(io, "real", "linked", .{ .is_directory = true });

    var adapter = Adapter.init(io, project_root.dir);
    try std.testing.expectError(
        error.BootstrapRootInspectionFailure,
        adapter.inspector().inspect("file"),
    );
    try std.testing.expectError(
        error.BootstrapRootInspectionFailure,
        adapter.inspector().inspect("linked"),
    );
    try std.testing.expectError(
        error.BootstrapRootInspectionFailure,
        adapter.inspector().inspect("linked/child"),
    );
}

test "a replaced directory receives a different physical identity" {
    const io = std.testing.io;
    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.createDir(io, "replaceable", .default_dir);

    var adapter = Adapter.init(io, project_root.dir);
    const before = (try adapter.inspector().inspect("replaceable")).directory;
    try project_root.dir.rename("replaceable", project_root.dir, "replaced", io);
    try project_root.dir.createDir(io, "replaceable", .default_dir);
    const after = (try adapter.inspector().inspect("replaceable")).directory;

    try std.testing.expect(!before.eql(after));
}
