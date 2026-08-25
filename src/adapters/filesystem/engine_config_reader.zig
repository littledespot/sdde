//! Filesystem adapter for the raw engine-configuration read boundary.
//!
//! The caller supplies a validated project-root directory capability. Root
//! discovery, JSON parsing, schema validation, and policy compilation are
//! separate responsibilities.

const std = @import("std");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const config_basename = ".sddtoolkit.json";

pub const ReadLimit = struct {
    max_bytes: usize,

    pub const InitError = error{InvalidReadLimit};

    pub fn init(max_bytes: usize) InitError!ReadLimit {
        if (max_bytes == 0 or max_bytes == std.math.maxInt(usize)) {
            return error.InvalidReadLimit;
        }
        return .{ .max_bytes = max_bytes };
    }
};

pub const Rejection = enum {
    exact_config_missing,
    symlink_forbidden,
    not_regular_file,
    read_limit_exceeded,
};

pub const RawEngineConfig = struct {
    bytes: []u8,

    pub fn deinit(self: *RawEngineConfig, allocator: Allocator) void {
        allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const Outcome = union(enum) {
    loaded: RawEngineConfig,
    rejected: Rejection,

    pub fn deinit(self: *Outcome, allocator: Allocator) void {
        switch (self.*) {
            .loaded => |*config| config.deinit(allocator),
            .rejected => {},
        }
        self.* = undefined;
    }
};

pub const ReadError = Io.File.OpenError || Io.File.StatError ||
    Io.File.Reader.Error || Allocator.Error;

pub fn read(
    validated_project_root: Io.Dir,
    io: Io,
    allocator: Allocator,
    limit: ReadLimit,
) ReadError!Outcome {
    var file = validated_project_root.openFile(io, config_basename, .{
        .mode = .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |err| switch (err) {
        error.FileNotFound => return .{ .rejected = .exact_config_missing },
        error.SymLinkLoop => return .{ .rejected = .symlink_forbidden },
        error.IsDir => return .{ .rejected = .not_regular_file },
        else => |unexpected| return unexpected,
    };
    defer file.close(io);

    const file_stat = try file.stat(io);
    if (file_stat.kind != .file) {
        return .{ .rejected = .not_regular_file };
    }
    if (file_stat.size > limit.max_bytes) {
        return .{ .rejected = .read_limit_exceeded };
    }

    var file_reader = file.reader(io, &.{});
    const bytes = file_reader.interface.allocRemaining(
        allocator,
        .limited(limit.max_bytes + 1),
    ) catch |err| switch (err) {
        error.StreamTooLong => return .{ .rejected = .read_limit_exceeded },
        error.ReadFailed => return file_reader.err.?,
        error.OutOfMemory => return error.OutOfMemory,
    };
    errdefer allocator.free(bytes);

    if (bytes.len > limit.max_bytes) {
        allocator.free(bytes);
        return .{ .rejected = .read_limit_exceeded };
    }

    return .{ .loaded = .{ .bytes = bytes } };
}

test "reads only the exact config basename from the supplied project root" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const expected = "{\"schemaVersion\":\"1.0\"}\n";
    const limit = try ReadLimit.init(1024);

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();

    try project_root.dir.writeFile(io, .{
        .sub_path = config_basename,
        .data = expected,
    });

    var outcome = try read(project_root.dir, io, allocator, limit);
    defer outcome.deinit(allocator);

    switch (outcome) {
        .loaded => |config| try std.testing.expectEqualStrings(expected, config.bytes),
        .rejected => return error.UnexpectedConfigRejection,
    }
}

test "does not use the example filename as a fallback" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const limit = try ReadLimit.init(1024);

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();

    try project_root.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json.example",
        .data = "{}",
    });

    var outcome = try read(project_root.dir, io, allocator, limit);
    defer outcome.deinit(allocator);

    try std.testing.expectEqual(Rejection.exact_config_missing, outcome.rejected);
}

test "rejects a config symlink" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const limit = try ReadLimit.init(1024);

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();

    try project_root.dir.writeFile(io, .{
        .sub_path = "config-target.json",
        .data = "{}",
    });
    try project_root.dir.symLink(io, "config-target.json", config_basename, .{});

    var outcome = try read(project_root.dir, io, allocator, limit);
    defer outcome.deinit(allocator);

    try std.testing.expectEqual(Rejection.symlink_forbidden, outcome.rejected);
}

test "rejects a non-regular config resource" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const limit = try ReadLimit.init(1024);

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();

    try project_root.dir.createDir(io, config_basename, .default_dir);

    var outcome = try read(project_root.dir, io, allocator, limit);
    defer outcome.deinit(allocator);

    try std.testing.expectEqual(Rejection.not_regular_file, outcome.rejected);
}

test "accepts the byte limit and rejects a larger config" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const limit = try ReadLimit.init(2);

    var project_root = std.testing.tmpDir(.{});
    defer project_root.cleanup();

    try project_root.dir.writeFile(io, .{
        .sub_path = config_basename,
        .data = "{}",
    });

    var accepted = try read(project_root.dir, io, allocator, limit);
    defer accepted.deinit(allocator);
    switch (accepted) {
        .loaded => |config| try std.testing.expectEqualStrings("{}", config.bytes),
        .rejected => return error.UnexpectedConfigRejection,
    }

    try project_root.dir.writeFile(io, .{
        .sub_path = config_basename,
        .data = "{ }",
    });

    var rejected = try read(project_root.dir, io, allocator, limit);
    defer rejected.deinit(allocator);
    try std.testing.expectEqual(Rejection.read_limit_exceeded, rejected.rejected);
}

test "rejects unusable read limits" {
    try std.testing.expectError(error.InvalidReadLimit, ReadLimit.init(0));
    try std.testing.expectError(
        error.InvalidReadLimit,
        ReadLimit.init(std.math.maxInt(usize)),
    );
}
