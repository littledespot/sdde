//! Filesystem adapter for locating and reading the exact engine configuration.
//!
//! It opens the exact file once and returns a narrow no-follow regular-file
//! capability. Actions own the public failure mapping and pipeline contracts.

const std = @import("std");
const config = @import("../../domain/config.zig");
const engine_config_source = @import("../../ports/engine_config_source.zig");
const file_identity = @import("file_identity.zig");

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

    pub fn locator(self: *Adapter) engine_config_source.Locator {
        return .{
            .context = self,
            .locate_fn = locate,
        };
    }

    fn locate(
        context: *anyopaque,
        allocator: Allocator,
    ) engine_config_source.Error!engine_config_source.ExactEngineConfigFile {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const project_root = self.invocation_working_directory;

        const canonical_project_root = canonicalProjectRoot(
            project_root,
            self.io,
            allocator,
        ) catch return error.EngineConfigReadFailure;
        errdefer allocator.free(canonical_project_root);

        const canonical_config_path = std.fs.path.joinZ(
            allocator,
            &.{ canonical_project_root, config.engine_config_basename },
        ) catch return error.EngineConfigReadFailure;
        errdefer allocator.free(canonical_config_path);

        var file = project_root.openFile(self.io, config.engine_config_basename, .{
            .mode = .read_only,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.EngineConfigReadFailure;
        errdefer file.close(self.io);

        const file_stat = file.stat(self.io) catch return error.EngineConfigReadFailure;
        if (file_stat.kind != .file) return error.EngineConfigReadFailure;
        const observed_identity = file_identity.inspect(file.handle) catch {
            return error.EngineConfigReadFailure;
        };

        const open_engine_config_file = allocator.create(OpenEngineConfigFile) catch {
            return error.EngineConfigReadFailure;
        };
        open_engine_config_file.* = .{
            .io = self.io,
            .file = file,
        };

        return engine_config_source.ExactEngineConfigFile.init(
            canonical_project_root,
            canonical_config_path,
            observed_identity,
            open_engine_config_file,
            &exact_config_file_vtable,
        );
    }
};

fn canonicalProjectRoot(
    project_root: Io.Dir,
    io: Io,
    allocator: Allocator,
) engine_config_source.Error![:0]u8 {
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

const OpenEngineConfigFile = struct {
    io: Io,
    file: Io.File,
};

const exact_config_file_vtable: engine_config_source.ExactEngineConfigFile.VTable = .{
    .read = read,
    .deinit = deinitExactConfigFile,
};

fn read(
    context: *anyopaque,
    allocator: Allocator,
    max_bytes: usize,
) engine_config_source.Error!engine_config_source.RawEngineConfig {
    const open_engine_config_file: *OpenEngineConfigFile = @ptrCast(@alignCast(context));
    const file_stat = open_engine_config_file.file.stat(open_engine_config_file.io) catch {
        return error.EngineConfigReadFailure;
    };

    var file_reader = open_engine_config_file.file.reader(open_engine_config_file.io, &.{});
    return captureExactObservedBytes(
        allocator,
        &file_reader.interface,
        file_stat.size,
        max_bytes,
    );
}

fn captureExactObservedBytes(
    allocator: Allocator,
    reader: *Io.Reader,
    observed_size: u64,
    max_bytes: usize,
) engine_config_source.Error!engine_config_source.RawEngineConfig {
    if (max_bytes == 0 or max_bytes == std.math.maxInt(usize) or
        observed_size > max_bytes)
    {
        return error.EngineConfigReadFailure;
    }

    const bytes = reader.allocRemaining(
        allocator,
        .limited(max_bytes + 1),
    ) catch return error.EngineConfigReadFailure;

    const expected_size: usize = @intCast(observed_size);
    if (bytes.len != expected_size) {
        allocator.free(bytes);
        return error.EngineConfigReadFailure;
    }

    return .{ .bytes = bytes };
}

fn deinitExactConfigFile(context: *anyopaque, allocator: Allocator) void {
    const open_engine_config_file: *OpenEngineConfigFile = @ptrCast(@alignCast(context));
    open_engine_config_file.file.close(open_engine_config_file.io);
    allocator.destroy(open_engine_config_file);
}

test "locates and reads only the exact config from the supplied working directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const expected = "{}";

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();
    try project_root.dir.writeFile(io, .{
        .sub_path = config.engine_config_basename,
        .data = expected,
    });

    var adapter = Adapter.init(io, project_root.dir);
    var located = try adapter.locator().locate(allocator);
    defer located.deinit(allocator);
    try std.testing.expect(std.fs.path.isAbsolute(located.canonical_project_root));
    try std.testing.expectEqualStrings(
        config.engine_config_basename,
        std.fs.path.basename(located.canonical_config_path),
    );

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
        .sub_path = config.engine_config_basename,
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
        .sub_path = config.engine_config_basename,
        .data = "{}",
    });
    try parent.dir.deleteFile(io, config.engine_config_basename);
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
    try project_root.dir.symLink(io, "config-target.json", config.engine_config_basename, .{});

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
    try project_root.dir.createDir(io, config.engine_config_basename, .default_dir);

    var adapter = Adapter.init(io, project_root.dir);
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        adapter.locator().locate(allocator),
    );
}

test "read accepts exactly the compiler byte limit and rejects one byte more" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();

    const exact_bytes = try allocator.alloc(u8, config.max_engine_config_bytes);
    defer allocator.free(exact_bytes);
    @memset(exact_bytes, ' ');
    try project_root.dir.writeFile(io, .{
        .sub_path = config.engine_config_basename,
        .data = exact_bytes,
    });

    var adapter = Adapter.init(io, project_root.dir);
    var located = try adapter.locator().locate(allocator);
    var raw = try located.read(allocator, config.max_engine_config_bytes);
    try std.testing.expectEqual(config.max_engine_config_bytes, raw.bytes.len);
    raw.deinit(allocator);
    located.deinit(allocator);

    const oversized_bytes = try allocator.alloc(u8, config.max_engine_config_bytes + 1);
    defer allocator.free(oversized_bytes);
    @memset(oversized_bytes, ' ');
    try project_root.dir.writeFile(io, .{
        .sub_path = config.engine_config_basename,
        .data = oversized_bytes,
    });

    var oversized = try adapter.locator().locate(allocator);
    defer oversized.deinit(allocator);
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        oversized.read(allocator, config.max_engine_config_bytes),
    );
}

test "read rejects shrink and growth after the observed size" {
    const allocator = std.testing.allocator;

    var shrunk_reader: Io.Reader = .fixed("ab");
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        captureExactObservedBytes(allocator, &shrunk_reader, 3, 4),
    );

    var grown_reader: Io.Reader = .fixed("abc");
    try std.testing.expectError(
        error.EngineConfigReadFailure,
        captureExactObservedBytes(allocator, &grown_reader, 2, 4),
    );
}
