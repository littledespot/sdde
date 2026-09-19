const std = @import("std");
const layout = @import("adapters/filesystem/feature_log_layout.zig");
const active = @import("domain/active_feature_directory.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const root_contract = @import("domain/bootstrap_roots.zig");
const artifacts = @import("domain/workflow_artifact_registry.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const feature = @import("domain/feature_directory.zig");
const directories = @import("adapters/filesystem/directory_access.zig");

fn rootOwner(allocator: std.mem.Allocator, project: std.Io.Dir) !*roots.Owner {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const names = [_][]const u8{ "requirements/current", "references", "archive", "workflows", "presets", "principles", "templates" };
    var inspector = @import("adapters/filesystem/bootstrap_root_inspector.zig").Adapter.init(std.testing.io, project);
    var configured: [root_contract.PathKey.count]root_contract.ValidatedConfiguredRoot = undefined;
    for (&configured, names, 0..) |*entry, name, index| {
        const key: root_contract.PathKey = @enumFromInt(index);
        entry.* = .{
            .path_key = key,
            .root_role = key.role(),
            .canonical_project_root = "/project",
            .configured_relative_path = name,
            .canonical_path = try std.mem.concat(a, u8, &.{ "/project/", name }),
            .access_class = key.accessClass(),
            .existence_policy = key.existencePolicy(),
            .observation = try inspector.inspector().inspect(name),
        };
    }
    return roots.createValidated(allocator, .{
        .id = .{ .canonical_project_root = "/project", .contract_version = root_contract.bootstrap_root_contract_version },
        .config_location = .{ .canonical_project_root = "/project", .canonical_config_path = "/project/.sddtoolkit.json", .no_follow_file_identity = .{ .filesystem_id = 1, .file_id = 1 } },
        .configured_roots = configured,
        .llm_provider_config_path = .{ .relative_path = ".sddproviders.json", .canonical_project_root = "/project", .canonical_path = "/project/.sddproviders.json" },
    });
}

fn logOwner(allocator: std.mem.Allocator, selected: []const u8) !*log_binding.BindingOwner {
    return log_binding.createValidated(allocator, .{
        .log_policy_id = .{ .bytes = "LOGPOL-1" },
        .binding_id = .{ .bytes = "BINDING-1" },
        .run_id = .{ .bytes = "RUN-1" },
        .feature_id = .{ .bytes = selected },
    });
}

fn observe(allocator: std.mem.Allocator, project: std.Io.Dir, registry: *const roots.BootstrapRootRegistry) !feature.Directory {
    const selected: feature.Selector = .{ .feature_id = .{ .bytes = "Group/Café" }, .project_relative_path = "requirements/current/Group/Café" };
    var inspector: @import("adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = std.testing.io, .project_root = project };
    var port = inspector.inspector();
    port.capability = registry.featureDirectoryRead();
    return port.inspect(allocator, selected);
}

test "feature log layout activates absent and present directories without changing bootstrap observations" {
    const io = std.testing.io;
    for ([_]bool{ false, true }) |present| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        if (present) try project.dir.createDirPath(io, "requirements/current/Group/Café");
        const root_owner = try rootOwner(std.testing.allocator, project.dir);
        defer roots.deinitOwner(root_owner);
        const registry = roots.registry(root_owner);
        const prior = try observe(std.testing.allocator, project.dir, registry);
        const log_owner = try logOwner(std.testing.allocator, prior.selector.feature_id.bytes);
        defer log_binding.deinitOwner(log_owner);
        const binding = log_binding.binding(log_owner);
        var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
        const activated = try adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, binding);
        defer active.deinitOwner(activated);
        const capability = active.capability(activated);
        const current = active.directory(capability);
        try std.testing.expect(current.root_observation == .directory and current.observation == .directory);
        if (present) {
            try std.testing.expect(prior.root_observation.directory.eql(current.root_observation.directory));
            try std.testing.expect(prior.observation.directory.eql(current.observation.directory));
        } else {
            try std.testing.expect(roots.bindSpecsArtifactRegistry(registry.specsArtifacts()) == null);
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const paths = try artifacts.resolveFeaturePaths(arena.allocator(), registry.featureArtifactRoots(), prior.selector);
            var reader: @import("adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir, .active_feature = capability };
            var capture = reader.capturer();
            capture.capability = registry.featureInputRead();
            try std.testing.expectError(error.FeatureInputUnavailable, capture.capture(arena.allocator(), prior, paths));
        }
        const artifact_owner = try artifacts.createForActive(std.testing.allocator, registry.featureOutputWrite(), binding, capability);
        defer artifacts.deinitOwner(artifact_owner);
        var sink = try @import("adapters/filesystem/feature_log_sink.zig").Adapter.init(io, project.dir, artifacts.registry(artifact_owner), binding);
        defer sink.deinit();
        for ([_][]const u8{ "events", "prompts" }) |stream| {
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const path = try std.fmt.allocPrint(arena.allocator(), "requirements/current/Group/Café/logs/{s}/RUN-1/BINDING-1", .{stream});
            const directory = try directories.open(io, project.dir, path);
            defer directory.close(io);
            try std.testing.expectEqual(@as(u32, 0), (try directory.stat(io)).permissions.toMode() & 0o077);
        }
        try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/Group/Café/spec.md", .{}));
        const foreign = try logOwner(std.testing.allocator, "other");
        defer log_binding.deinitOwner(foreign);
        try std.testing.expectError(error.InvalidWorkflowArtifactRegistry, artifacts.createForActive(std.testing.allocator, registry.featureOutputWrite(), log_binding.binding(foreign), capability));
        if (present) try std.testing.expectError(error.FeatureLogLayoutUnavailable, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), current, binding));
    }
}

test "feature log activation rejects changed directories and symlink ancestry" {
    const io = std.testing.io;
    for (0..3) |scenario| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        if (scenario != 0) try project.dir.createDirPath(io, "requirements/current/Group/Café");
        const root_owner = try rootOwner(std.testing.allocator, project.dir);
        defer roots.deinitOwner(root_owner);
        const registry = roots.registry(root_owner);
        const prior = try observe(std.testing.allocator, project.dir, registry);
        const log_owner = try logOwner(std.testing.allocator, prior.selector.feature_id.bytes);
        defer log_binding.deinitOwner(log_owner);
        switch (scenario) {
            0 => {
                try project.dir.createDirPath(io, "outside/current");
                try project.dir.symLink(io, "outside", "requirements", .{ .is_directory = true });
            },
            1 => {
                try project.dir.rename("requirements/current/Group/Café", project.dir, "old-feature", io);
                try project.dir.createDirPath(io, "requirements/current/Group/Café");
            },
            2 => {
                try project.dir.rename("requirements/current/Group", project.dir, "old-group", io);
                try project.dir.symLink(io, "../../old-group", "requirements/current/Group", .{ .is_directory = true });
            },
            else => unreachable,
        }
        var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
        try std.testing.expectError(error.FeatureLogLayoutUnavailable, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, log_binding.binding(log_owner)));
    }
}

test "feature log activation refuses existing run paths and foreign feature bindings" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    try project.dir.createDirPath(io, "requirements/current/Group/Café/logs/events/RUN-1");
    const root_owner = try rootOwner(std.testing.allocator, project.dir);
    defer roots.deinitOwner(root_owner);
    const registry = roots.registry(root_owner);
    const prior = try observe(std.testing.allocator, project.dir, registry);
    const log_owner = try logOwner(std.testing.allocator, prior.selector.feature_id.bytes);
    defer log_binding.deinitOwner(log_owner);
    var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
    try std.testing.expectError(error.FeatureLogLayoutUnavailable, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, log_binding.binding(log_owner)));
    const foreign = try logOwner(std.testing.allocator, "other");
    defer log_binding.deinitOwner(foreign);
    try std.testing.expectError(error.InvalidFeatureLogLayout, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, log_binding.binding(foreign)));
    try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/other", .{}));
}
