//! No-follow directory inspection for validated configured-root candidates.

const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const root_inspector = @import("../../ports/bootstrap_root_inspector.zig");
const file_identity = @import("file_identity.zig");

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
        if (normalized_relative_path.len == 0) {
            return error.BootstrapRootInspectionFailure;
        }

        var current = self.invocation_working_directory;
        var current_is_owned = false;
        defer if (current_is_owned) current.close(self.io);

        var component_start: usize = 0;
        while (component_start < normalized_relative_path.len) {
            const component_end = std.mem.indexOfScalarPos(
                u8,
                normalized_relative_path,
                component_start,
                '/',
            ) orelse normalized_relative_path.len;
            const is_leaf = component_end == normalized_relative_path.len;
            const component = normalized_relative_path[component_start..component_end];

            const next = current.openDir(self.io, component, .{
                .access_sub_paths = true,
                .iterate = is_leaf,
                .follow_symlinks = false,
            }) catch |open_error| switch (open_error) {
                error.FileNotFound => return .absent,
                error.Canceled => return error.Cancelled,
                else => return error.BootstrapRootInspectionFailure,
            };

            if (current_is_owned) current.close(self.io);
            current = next;
            current_is_owned = true;
            component_start = component_end + 1;
        }

        const stat = current.stat(self.io) catch |stat_error| {
            return switch (stat_error) {
                error.Canceled => error.Cancelled,
                else => error.BootstrapRootInspectionFailure,
            };
        };
        if (stat.kind != .directory) {
            return error.BootstrapRootInspectionFailure;
        }
        const identity = file_identity.inspect(current.handle) catch {
            return error.BootstrapRootInspectionFailure;
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
    try project_root.dir.deleteDir(io, "replaceable");
    try project_root.dir.createDir(io, "replaceable", .default_dir);
    const after = (try adapter.inspector().inspect("replaceable")).directory;

    try std.testing.expect(!before.eql(after));
}
