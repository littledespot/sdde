//! Read-only no-follow source for the configured LLM-provider document.

const std = @import("std");
const bootstrap_root_registry = @import("../../domain/bootstrap_root_registry.zig");
const llm_provider_config = @import("../../domain/llm_provider_config.zig");
const pipeline = @import("../../domain/pipeline.zig");
const source_port = @import("../../ports/llm_provider_config_source.zig");
const bounded_file_capture = @import("bounded_file_capture.zig");
const file_identity = @import("file_identity.zig");

const Io = std.Io;

pub const Adapter = struct {
    io: Io,
    project_root: Io.Dir,

    pub fn init(io: Io, project_root: Io.Dir) Adapter {
        return .{ .io = io, .project_root = project_root };
    }

    pub fn locator(self: *Adapter) source_port.Locator {
        return .{ .context = self, .locate_fn = locate };
    }

    fn locate(
        context: *anyopaque,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) source_port.Error!source_port.ExactFile {
        const self: *Adapter = @ptrCast(@alignCast(context));
        try checkRuntime(runtime);
        const binding = bootstrap_root_registry.bindLLMProviderConfigSource(capability) orelse {
            return error.LLMProviderConfigReadFailure;
        };

        var file = try openFileNoFollow(
            self.io,
            self.project_root,
            binding.project_relative_path,
        );
        errdefer file.close(self.io);

        const stat = file.stat(self.io) catch return error.LLMProviderConfigReadFailure;
        if (stat.kind != .file or stat.size > llm_provider_config.max_bytes) {
            return error.LLMProviderConfigReadFailure;
        }
        const identity = file_identity.inspect(file.handle) catch {
            return error.LLMProviderConfigReadFailure;
        };
        if (identity.eql(binding.engine_config_identity)) {
            return error.LLMProviderConfigReadFailure;
        }
        try checkRuntime(runtime);

        const owned_relative_path = allocator.dupe(
            u8,
            binding.project_relative_path,
        ) catch return error.LLMProviderConfigReadFailure;
        errdefer allocator.free(owned_relative_path);
        const open_file = allocator.create(OpenFile) catch {
            return error.LLMProviderConfigReadFailure;
        };
        open_file.* = .{
            .io = self.io,
            .project_root = self.project_root,
            .relative_path = owned_relative_path,
            .file = file,
            .observed_size = stat.size,
            .observed_identity = identity,
        };
        return .{
            .identity = identity,
            .context = open_file,
            .vtable = &exact_file_vtable,
        };
    }
};

fn openFileNoFollow(
    io: Io,
    project_root: Io.Dir,
    relative_path: []const u8,
) source_port.Error!Io.File {
    var parent = try openParent(io, project_root, relative_path);
    defer if (parent.owned) parent.directory.close(io);
    return parent.directory.openFile(io, std.fs.path.basename(relative_path), .{
        .mode = .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |open_error| return switch (open_error) {
        error.Canceled => error.Cancelled,
        else => error.LLMProviderConfigReadFailure,
    };
}

fn openParent(
    io: Io,
    project_root: Io.Dir,
    relative_path: []const u8,
) source_port.Error!OpenedParent {
    const parent_path = std.fs.path.dirname(relative_path) orelse {
        return .{ .directory = project_root, .owned = false };
    };
    var current = project_root;
    var current_is_owned = false;
    errdefer if (current_is_owned) current.close(io);

    var components = std.mem.splitScalar(u8, parent_path, '/');
    while (components.next()) |component| {
        const next = current.openDir(io, component, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        }) catch |open_error| return switch (open_error) {
            error.Canceled => error.Cancelled,
            else => error.LLMProviderConfigReadFailure,
        };
        if (current_is_owned) current.close(io);
        current = next;
        current_is_owned = true;
    }
    return .{ .directory = current, .owned = current_is_owned };
}

const OpenedParent = struct {
    directory: Io.Dir,
    owned: bool,
};

const OpenFile = struct {
    io: Io,
    project_root: Io.Dir,
    relative_path: []u8,
    file: Io.File,
    observed_size: u64,
    observed_identity: @import("../../domain/filesystem_identity.zig").FileIdentity,
};

const exact_file_vtable: source_port.ExactFile.VTable = .{
    .read = read,
    .deinit = deinitExactFile,
};

fn read(
    context: *anyopaque,
    allocator: std.mem.Allocator,
    max_bytes: usize,
    runtime: pipeline.NodeRuntime,
) source_port.Error!llm_provider_config.Raw {
    const open_file: *OpenFile = @ptrCast(@alignCast(context));
    try checkRuntime(runtime);
    try validatePathBinding(open_file);
    const before = open_file.file.stat(open_file.io) catch {
        return error.LLMProviderConfigReadFailure;
    };
    const before_identity = file_identity.inspect(open_file.file.handle) catch {
        return error.LLMProviderConfigReadFailure;
    };
    if (before.kind != .file or before.size != open_file.observed_size or
        !before_identity.eql(open_file.observed_identity))
    {
        return error.LLMProviderConfigReadFailure;
    }

    var reader = open_file.file.reader(open_file.io, &.{});
    const bytes = bounded_file_capture.capture(
        allocator,
        &reader.interface,
        before.size,
        max_bytes,
    ) catch return error.LLMProviderConfigReadFailure;
    errdefer allocator.free(bytes);

    const after = open_file.file.stat(open_file.io) catch {
        return error.LLMProviderConfigReadFailure;
    };
    const after_identity = file_identity.inspect(open_file.file.handle) catch {
        return error.LLMProviderConfigReadFailure;
    };
    if (after.kind != .file or after.size != before.size or
        !after_identity.eql(before_identity))
    {
        return error.LLMProviderConfigReadFailure;
    }
    try validatePathBinding(open_file);
    try checkRuntime(runtime);
    return .{ .bytes = bytes };
}

fn validatePathBinding(open_file: *const OpenFile) source_port.Error!void {
    var current = try openFileNoFollow(
        open_file.io,
        open_file.project_root,
        open_file.relative_path,
    );
    defer current.close(open_file.io);
    const stat = current.stat(open_file.io) catch {
        return error.LLMProviderConfigReadFailure;
    };
    const identity = file_identity.inspect(current.handle) catch {
        return error.LLMProviderConfigReadFailure;
    };
    if (stat.kind != .file or stat.size != open_file.observed_size or
        !identity.eql(open_file.observed_identity))
    {
        return error.LLMProviderConfigReadFailure;
    }
}

fn deinitExactFile(context: *anyopaque, allocator: std.mem.Allocator) void {
    const open_file: *OpenFile = @ptrCast(@alignCast(context));
    open_file.file.close(open_file.io);
    allocator.free(open_file.relative_path);
    allocator.destroy(open_file);
}

fn checkRuntime(runtime: pipeline.NodeRuntime) source_port.Error!void {
    return switch (runtime.status()) {
        .active => {},
        .cancelled => error.Cancelled,
        .deadline_exhausted => error.DeadlineExhausted,
    };
}

test "reads only the configured provider document path" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "configuration", .default_dir);
    try project.dir.writeFile(io, .{
        .sub_path = "configuration/.sddproviders.json",
        .data = "{\"providers\":[]}",
    });
    try project.dir.writeFile(io, .{
        .sub_path = ".sddproviders.json",
        .data = "wrong",
    });

    const owner = try testRegistry(allocator, "configuration/.sddproviders.json");
    defer bootstrap_root_registry.deinitOwner(owner);
    var adapter = Adapter.init(io, project.dir);
    var exact = try adapter.locator().locate(
        bootstrap_root_registry.registry(owner).llmProviderConfig(),
        allocator,
        .{},
    );
    defer exact.deinit(allocator);
    var raw = try exact.read(allocator, llm_provider_config.max_bytes, .{});
    defer raw.deinit(allocator);
    try std.testing.expectEqualStrings("{\"providers\":[]}", raw.bytes);
}

test "rejects missing linked parents linked leaves wrong kinds and oversized files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    inline for (.{ "missing", "linked-parent", "linked-leaf", "directory", "oversized" }) |scenario| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "configuration", .default_dir);
        if (std.mem.eql(u8, scenario, "missing")) {
            // Keep the exact configured leaf absent.
        } else if (std.mem.eql(u8, scenario, "linked-parent")) {
            try project.dir.writeFile(io, .{
                .sub_path = "configuration/.sddproviders.json",
                .data = "{}",
            });
            try project.dir.symLink(io, "configuration", "linked", .{ .is_directory = true });
        } else if (std.mem.eql(u8, scenario, "linked-leaf")) {
            try project.dir.writeFile(io, .{
                .sub_path = "configuration/target.json",
                .data = "{}",
            });
            var configuration = try project.dir.openDir(io, "configuration", .{});
            defer configuration.close(io);
            try configuration.symLink(io, "target.json", ".sddproviders.json", .{});
        } else if (std.mem.eql(u8, scenario, "directory")) {
            try project.dir.createDirPath(io, "configuration/.sddproviders.json");
        } else {
            const bytes = try allocator.alloc(u8, llm_provider_config.max_bytes + 1);
            defer allocator.free(bytes);
            @memset(bytes, ' ');
            try project.dir.writeFile(io, .{
                .sub_path = "configuration/.sddproviders.json",
                .data = bytes,
            });
        }

        const configured_path = if (std.mem.eql(u8, scenario, "linked-parent"))
            "linked/.sddproviders.json"
        else
            "configuration/.sddproviders.json";
        const owner = try testRegistry(allocator, configured_path);
        defer bootstrap_root_registry.deinitOwner(owner);
        var adapter = Adapter.init(io, project.dir);
        try std.testing.expectError(
            error.LLMProviderConfigReadFailure,
            adapter.locator().locate(
                bootstrap_root_registry.registry(owner).llmProviderConfig(),
                allocator,
                .{},
            ),
        );
    }
}

test "accepts the exact byte limit and preserves cancellation" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    const bytes = try allocator.alloc(u8, llm_provider_config.max_bytes);
    defer allocator.free(bytes);
    @memset(bytes, ' ');
    try project.dir.writeFile(io, .{
        .sub_path = ".sddproviders.json",
        .data = bytes,
    });

    const owner = try testRegistry(allocator, ".sddproviders.json");
    defer bootstrap_root_registry.deinitOwner(owner);
    var adapter = Adapter.init(io, project.dir);
    try std.testing.expectError(
        error.Cancelled,
        adapter.locator().locate(
            bootstrap_root_registry.registry(owner).llmProviderConfig(),
            allocator,
            .{ .status_fn = cancelled },
        ),
    );

    var exact = try adapter.locator().locate(
        bootstrap_root_registry.registry(owner).llmProviderConfig(),
        allocator,
        .{},
    );
    defer exact.deinit(allocator);
    var raw = try exact.read(allocator, llm_provider_config.max_bytes, .{});
    defer raw.deinit(allocator);
    try std.testing.expectEqual(llm_provider_config.max_bytes, raw.bytes.len);
}

test "rejects a provider document hard-linked to the engine config" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.writeFile(io, .{
        .sub_path = ".sddtoolkit.json",
        .data = "{}",
    });
    try project.dir.hardLink(
        ".sddtoolkit.json",
        project.dir,
        ".sddproviders.json",
        io,
        .{},
    );
    var engine_config_file = try project.dir.openFile(io, ".sddtoolkit.json", .{
        .mode = .read_only,
        .follow_symlinks = false,
    });
    defer engine_config_file.close(io);
    const engine_config_identity = try file_identity.inspect(engine_config_file.handle);

    const owner = try testRegistryWithConfigIdentity(
        allocator,
        ".sddproviders.json",
        engine_config_identity,
    );
    defer bootstrap_root_registry.deinitOwner(owner);
    var adapter = Adapter.init(io, project.dir);
    try std.testing.expectError(
        error.LLMProviderConfigReadFailure,
        adapter.locator().locate(
            bootstrap_root_registry.registry(owner).llmProviderConfig(),
            allocator,
            .{},
        ),
    );
}

test "rejects replacement of the configured path after locate" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.writeFile(io, .{
        .sub_path = ".sddproviders.json",
        .data = "original",
    });
    try project.dir.writeFile(io, .{
        .sub_path = "replacement",
        .data = "replaced",
    });

    const owner = try testRegistry(allocator, ".sddproviders.json");
    defer bootstrap_root_registry.deinitOwner(owner);
    var adapter = Adapter.init(io, project.dir);
    var exact = try adapter.locator().locate(
        bootstrap_root_registry.registry(owner).llmProviderConfig(),
        allocator,
        .{},
    );
    defer exact.deinit(allocator);
    try project.dir.rename(
        "replacement",
        project.dir,
        ".sddproviders.json",
        io,
    );

    try std.testing.expectError(
        error.LLMProviderConfigReadFailure,
        exact.read(allocator, llm_provider_config.max_bytes, .{}),
    );
}

fn cancelled(_: ?*anyopaque) pipeline.RuntimeStatus {
    return .cancelled;
}

fn testRegistry(
    allocator: std.mem.Allocator,
    provider_path: []const u8,
) !*bootstrap_root_registry.Owner {
    return testRegistryWithConfigIdentity(
        allocator,
        provider_path,
        .{ .filesystem_id = 1, .file_id = 1 },
    );
}

fn testRegistryWithConfigIdentity(
    allocator: std.mem.Allocator,
    provider_path: []const u8,
    engine_config_identity: @import("../../domain/filesystem_identity.zig").FileIdentity,
) !*bootstrap_root_registry.Owner {
    const roots = @import("../../domain/bootstrap_roots.zig");
    var configured: [roots.PathKey.count]roots.ValidatedConfiguredRoot = undefined;
    const paths = [_][]const u8{
        "specs",
        "references",
        "specs/archive",
        ".sdd/workflows",
        ".sdd/presets",
        ".sdd/principles",
        ".sdd/templates",
    };
    for (&configured, 0..) |*value, index| {
        const key: roots.PathKey = @enumFromInt(index);
        value.* = .{
            .path_key = key,
            .root_role = key.role(),
            .canonical_project_root = "/project",
            .configured_relative_path = paths[index],
            .canonical_path = switch (key) {
                .specs => "/project/specs",
                .references => "/project/references",
                .specs_archive => "/project/specs/archive",
                .workflows => "/project/.sdd/workflows",
                .toolchain_preset => "/project/.sdd/presets",
                .principles => "/project/.sdd/principles",
                .templates => "/project/.sdd/templates",
            },
            .access_class = key.accessClass(),
            .existence_policy = key.existencePolicy(),
            .observation = if (key == .workflows)
                .{ .directory = .{ .filesystem_id = 1, .file_id = 3 } }
            else
                .absent,
        };
    }
    const canonical_path = try std.fs.path.join(allocator, &.{ "/project", provider_path });
    defer allocator.free(canonical_path);
    return bootstrap_root_registry.createValidated(allocator, .{
        .id = .{
            .canonical_project_root = "/project",
            .contract_version = roots.bootstrap_root_contract_version,
        },
        .config_location = .{
            .canonical_project_root = "/project",
            .canonical_config_path = "/project/.sddtoolkit.json",
            .no_follow_file_identity = engine_config_identity,
        },
        .configured_roots = configured,
        .llm_provider_config_path = .{
            .relative_path = provider_path,
            .canonical_project_root = "/project",
            .canonical_path = canonical_path,
        },
    });
}
