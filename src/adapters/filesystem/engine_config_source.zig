//! Filesystem adapter for locating and reading the exact engine configuration.
//!
//! It opens the exact file once and returns a narrow no-follow regular-file
//! capability. Actions own the public failure mapping and pipeline contracts.

const std = @import("std");
const config = @import("../../domain/config.zig");
const source = @import("../../ports/engine_config_source.zig");

const Allocator = std.mem.Allocator;
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

    pub fn locator(self: *Adapter) source.Locator {
        return .{
            .context = self,
            .locate_fn = locate,
        };
    }

    fn locate(context: *anyopaque, allocator: Allocator) source.Error!source.ExactEngineConfig {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const project_root = self.invocation_working_directory;

        const canonical_project_root = canonicalProjectRoot(
            project_root,
            self.io,
            allocator,
        ) catch return error.EngineConfigReadFailure;
        errdefer allocator.free(canonical_project_root);

        var file = project_root.openFile(self.io, config.basename, .{
            .mode = .read_only,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.EngineConfigReadFailure;
        errdefer file.close(self.io);

        const file_stat = file.stat(self.io) catch return error.EngineConfigReadFailure;
        if (file_stat.kind != .file) return error.EngineConfigReadFailure;

        const open_config = allocator.create(OpenConfig) catch {
            return error.EngineConfigReadFailure;
        };
        open_config.* = .{
            .io = self.io,
            .file = file,
        };

        return source.ExactEngineConfig.init(
            canonical_project_root,
            open_config,
            &exact_config_vtable,
        );
    }
};

fn canonicalProjectRoot(
    project_root: Io.Dir,
    io: Io,
    allocator: Allocator,
) source.Error![:0]u8 {
    const canonical_path = if (project_root.handle == Io.Dir.cwd().handle)
        std.process.currentPathAlloc(io, allocator) catch {
            return error.EngineConfigReadFailure;
        }
    else
        project_root.realPathFileAlloc(io, ".", allocator) catch {
            return error.EngineConfigReadFailure;
        };
    errdefer allocator.free(canonical_path);

    if (!std.fs.path.isAbsolute(canonical_path)) {
        return error.EngineConfigReadFailure;
    }
    return canonical_path;
}

const OpenConfig = struct {
    io: Io,
    file: Io.File,
};

const exact_config_vtable: source.ExactEngineConfig.VTable = .{
    .read = read,
    .deinit = deinitExactConfig,
};

fn read(
    context: *anyopaque,
    allocator: Allocator,
    max_bytes: usize,
) source.Error!source.RawEngineConfig {
    const open_config: *OpenConfig = @ptrCast(@alignCast(context));
    if (max_bytes == 0 or max_bytes == std.math.maxInt(usize)) {
        return error.EngineConfigReadFailure;
    }

    const file_stat = open_config.file.stat(open_config.io) catch {
        return error.EngineConfigReadFailure;
    };
    if (file_stat.size > max_bytes) {
        return error.EngineConfigReadFailure;
    }

    var file_reader = open_config.file.reader(open_config.io, &.{});
    const bytes = file_reader.interface.allocRemaining(
        allocator,
        .limited(max_bytes + 1),
    ) catch return error.EngineConfigReadFailure;
    errdefer allocator.free(bytes);

    if (bytes.len > max_bytes) {
        allocator.free(bytes);
        return error.EngineConfigReadFailure;
    }

    return .{ .bytes = bytes };
}

fn deinitExactConfig(context: *anyopaque, allocator: Allocator) void {
    const open_config: *OpenConfig = @ptrCast(@alignCast(context));
    open_config.file.close(open_config.io);
    allocator.destroy(open_config);
}

test "locates and reads only the exact config from the supplied working directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const expected = "{}";

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = config.basename,
        .data = expected,
    });

    var adapter = Adapter.init(io, project_root.dir);
    var located = try adapter.locator().locate(allocator);
    defer located.deinit(allocator);
    try std.testing.expect(std.fs.path.isAbsolute(located.canonical_project_root));

    var raw = try located.read(allocator, expected.len);
    defer raw.deinit(allocator);
    try std.testing.expectEqualStrings(expected, raw.bytes);
}

test "does not use the example filename as a fallback" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json.example",
        .data = "{}",
    });

    var adapter = Adapter.init(io, project_root.dir);

    try std.testing.expectError(
        error.EngineConfigReadFailure,
        adapter.locator().locate(allocator),
    );
}

test "does not inspect parent or child directories" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var parent = std.testing.tmpDir(.{});
    defer parent.cleanup();
    try parent.dir.writeFile(io, .{
        .sub_path = config.basename,
        .data = "{}",
    });
    try parent.dir.createDir(io, "child", .default_dir);
    var child = try parent.dir.openDir(io, "child", .{});
    defer child.close(io);

    var child_adapter = Adapter.init(io, child);
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        child_adapter.locator().locate(allocator),
    );

    try child.writeFile(io, .{
        .sub_path = config.basename,
        .data = "{}",
    });
    try parent.dir.deleteFile(io, config.basename);
    var parent_adapter = Adapter.init(io, parent.dir);
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        parent_adapter.locator().locate(allocator),
    );
}

test "rejects a symlink during locate" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = "config-target.json",
        .data = "{}",
    });
    try project_root.dir.symLink(io, "config-target.json", config.basename, .{});

    var adapter = Adapter.init(io, project_root.dir);
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        adapter.locator().locate(allocator),
    );
}

test "rejects a non-regular resource during locate" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.createDir(io, config.basename, .default_dir);

    var adapter = Adapter.init(io, project_root.dir);
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        adapter.locator().locate(allocator),
    );
}

test "read accepts the byte limit and rejects a larger file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = config.basename,
        .data = "{ }",
    });

    var adapter = Adapter.init(io, project_root.dir);
    var located = try adapter.locator().locate(allocator);
    defer located.deinit(allocator);

    try std.testing.expectError(
        error.EngineConfigReadFailure,
        located.read(allocator, 2),
    );
}
