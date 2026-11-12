const std = @import("std");
const bootstrap_roots = @import("bootstrap_roots.zig");
const configured_path_policy = @import("configured_path_policy.zig");
const configured_path_resolution = @import("configured_path_resolution.zig");

pub const ResolutionError = error{BootstrapRootResolutionError};
pub const RegistryError = error{BootstrapRootRegistryInvalid};

pub fn normalizeRootPath(
    policy: bootstrap_roots.WorkspacePathPolicy,
    allocator: std.mem.Allocator,
    path_key: bootstrap_roots.PathKey,
    raw_path: []const u8,
) ResolutionError!bootstrap_roots.NormalizedConfiguredPath {
    return .{
        .path_key = path_key,
        .root_role = path_key.role(),
        .relative_path = configured_path_policy.normalize(policy, allocator, raw_path, true) catch {
            return error.BootstrapRootResolutionError;
        },
    };
}

pub fn normalizeProviderPath(
    policy: bootstrap_roots.WorkspacePathPolicy,
    allocator: std.mem.Allocator,
    raw_path: []const u8,
) ResolutionError!bootstrap_roots.NormalizedLLMProviderConfigPath {
    const normalized = configured_path_policy.normalize(policy, allocator, raw_path, false) catch {
        return error.BootstrapRootResolutionError;
    };
    errdefer allocator.free(normalized);
    if (!std.mem.eql(u8, std.fs.path.basename(normalized), bootstrap_roots.llm_provider_config_basename)) {
        return error.BootstrapRootResolutionError;
    }
    return .{ .relative_path = normalized };
}

pub fn resolveRoot(
    policy: bootstrap_roots.WorkspacePathPolicy,
    allocator: std.mem.Allocator,
    canonical_project_root: []const u8,
    normalized_path: bootstrap_roots.NormalizedConfiguredPath,
) ResolutionError!bootstrap_roots.ConfiguredRootCandidate {
    return .{
        .path = normalized_path,
        .canonical_project_root = canonical_project_root,
        .canonical_path = configured_path_resolution.join(
            policy,
            allocator,
            canonical_project_root,
            normalized_path.relative_path,
        ) catch return error.BootstrapRootResolutionError,
    };
}

pub fn resolveProviderPath(
    policy: bootstrap_roots.WorkspacePathPolicy,
    allocator: std.mem.Allocator,
    canonical_project_root: []const u8,
    normalized_path: bootstrap_roots.NormalizedLLMProviderConfigPath,
) ResolutionError!bootstrap_roots.LLMProviderConfigPathCandidate {
    return .{
        .relative_path = normalized_path.relative_path,
        .canonical_project_root = canonical_project_root,
        .canonical_path = configured_path_resolution.join(
            policy,
            allocator,
            canonical_project_root,
            normalized_path.relative_path,
        ) catch return error.BootstrapRootResolutionError,
    };
}

pub fn buildRegistryId(
    allocator: std.mem.Allocator,
    canonical_project_root: []const u8,
) RegistryError!bootstrap_roots.BootstrapRootRegistryId {
    const candidate: bootstrap_roots.BootstrapRootRegistryId = .{
        .canonical_project_root = canonical_project_root,
        .contract_version = bootstrap_roots.bootstrap_root_contract_version,
    };
    if (!candidate.isValid()) {
        return error.BootstrapRootRegistryInvalid;
    }
    return .{
        .canonical_project_root = allocator.dupe(u8, canonical_project_root) catch {
            return error.BootstrapRootRegistryInvalid;
        },
        .contract_version = bootstrap_roots.bootstrap_root_contract_version,
    };
}

pub fn buildRegistryCandidate(
    allocator: std.mem.Allocator,
    id: bootstrap_roots.BootstrapRootRegistryId,
    canonical_config_path: []const u8,
    config_file_identity: bootstrap_roots.NoFollowFileIdentity,
    configured_roots: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot,
    llm_provider_config_path: bootstrap_roots.LLMProviderConfigPathCandidate,
) RegistryError!bootstrap_roots.BootstrapRootRegistryCandidate {
    const owned_config_path = allocator.dupe(u8, canonical_config_path) catch {
        return error.BootstrapRootRegistryInvalid;
    };
    errdefer allocator.free(owned_config_path);

    var owned_roots = configured_roots;
    for (&owned_roots) |*capability| {
        if (!std.mem.eql(u8, capability.canonical_project_root, id.canonical_project_root)) {
            return error.BootstrapRootRegistryInvalid;
        }
        capability.canonical_project_root = id.canonical_project_root;
    }
    if (!std.mem.eql(
        u8,
        llm_provider_config_path.canonical_project_root,
        id.canonical_project_root,
    )) {
        return error.BootstrapRootRegistryInvalid;
    }

    return .{
        .id = id,
        .config_location = .{
            .canonical_project_root = id.canonical_project_root,
            .canonical_config_path = owned_config_path,
            .no_follow_file_identity = config_file_identity,
        },
        .configured_roots = owned_roots,
        .llm_provider_config_path = .{
            .relative_path = llm_provider_config_path.relative_path,
            .canonical_project_root = id.canonical_project_root,
            .canonical_path = llm_provider_config_path.canonical_path,
        },
    };
}

test "normalizes configured roots and rejects unsafe portable paths" {
    const allocator = std.testing.allocator;
    const policy: bootstrap_roots.WorkspacePathPolicy = .{ .max_component_bytes = 16, .max_relative_path_bytes = 64, .max_absolute_path_bytes = 128 };
    const result = try normalizeRootPath(policy, allocator, .workflows, ".sddtoolkit/workflows/");
    defer allocator.free(result.relative_path);
    try std.testing.expectEqualStrings(".sddtoolkit/workflows", result.relative_path);

    const invalid = [_][]const u8{ "", "/absolute", "C:/drive", "a//b", "a/../b", "a\\b", "a/%2f/b", "a/con", "non-ascii-\xc3\xa9" };
    for (invalid) |path| try std.testing.expectError(
        error.BootstrapRootResolutionError,
        normalizeRootPath(policy, allocator, .specs, path),
    );
}

test "accepts exact component and relative limits" {
    const allocator = std.testing.allocator;
    const policy: bootstrap_roots.WorkspacePathPolicy = .{ .max_component_bytes = 16, .max_relative_path_bytes = 64, .max_absolute_path_bytes = 128 };
    const component = try normalizeRootPath(policy, allocator, .specs, "abcdefghijklmnop");
    defer allocator.free(component.relative_path);
    const relative = try normalizeRootPath(policy, allocator, .references, "aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb/cccccccccccccccc/ddddddddddddd");
    defer allocator.free(relative.relative_path);
    try std.testing.expectEqual(@as(usize, 64), relative.relative_path.len);
}

test "requires the exact provider basename without a directory suffix" {
    const allocator = std.testing.allocator;
    const policy: bootstrap_roots.WorkspacePathPolicy = .{
        .max_component_bytes = 32,
        .max_relative_path_bytes = 128,
        .max_absolute_path_bytes = 256,
    };
    const exact = try normalizeProviderPath(policy, allocator, "configuration/.sddproviders.json");
    defer allocator.free(exact.relative_path);
    try std.testing.expectEqualStrings("configuration/.sddproviders.json", exact.relative_path);
    for ([_][]const u8{
        "configuration/providers.json",
        "configuration/.sddproviders.json/",
        "configuration/.SDDPROVIDERS.JSON",
    }) |path| try std.testing.expectError(
        error.BootstrapRootResolutionError,
        normalizeProviderPath(policy, allocator, path),
    );
}

test "joins one normalized path beneath the exact canonical project root" {
    const allocator = std.testing.allocator;
    const policy: bootstrap_roots.WorkspacePathPolicy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = 1024,
    };
    const normalized: bootstrap_roots.NormalizedConfiguredPath = .{
        .path_key = .workflows,
        .root_role = .workflow_authority,
        .relative_path = ".sddtoolkit/workflows",
    };
    const result = try resolveRoot(policy, allocator, "/project", normalized);
    defer allocator.free(result.canonical_path);
    try std.testing.expectEqualStrings("/project/.sddtoolkit/workflows", result.canonical_path);
}

test "rejects a noncanonical project root and an absolute path ceiling breach" {
    const normalized: bootstrap_roots.NormalizedConfiguredPath = .{
        .path_key = .specs,
        .root_role = .specs_artifacts,
        .relative_path = "specs",
    };
    const policy: bootstrap_roots.WorkspacePathPolicy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = 12,
    };
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        resolveRoot(policy, std.testing.allocator, "relative", normalized),
    );
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        resolveRoot(policy, std.testing.allocator, "/project", normalized),
    );
}

test "accepts the exact absolute path ceiling" {
    const normalized: bootstrap_roots.NormalizedConfiguredPath = .{
        .path_key = .specs,
        .root_role = .specs_artifacts,
        .relative_path = "specs",
    };
    const policy: bootstrap_roots.WorkspacePathPolicy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = "/project/specs".len,
    };
    const resolved = try resolveRoot(policy, std.testing.allocator, "/project", normalized);
    defer std.testing.allocator.free(resolved.canonical_path);
    try std.testing.expectEqualStrings("/project/specs", resolved.canonical_path);
}

test "resolves the provider document beneath the canonical project root" {
    const allocator = std.testing.allocator;
    const policy: bootstrap_roots.WorkspacePathPolicy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = 1024,
    };
    const resolved = try resolveProviderPath(
        policy,
        allocator,
        "/project",
        .{ .relative_path = "configuration/.sddproviders.json" },
    );
    defer allocator.free(resolved.canonical_path);
    try std.testing.expect(resolved.isStructurallyValid());
}

test "builds the self-validating project-root tuple without content identity" {
    const allocator = std.testing.allocator;
    const id = try buildRegistryId(allocator, "/project");
    defer allocator.free(id.canonical_project_root);

    try std.testing.expectEqualStrings("/project", id.canonical_project_root);
    try std.testing.expectEqualStrings(bootstrap_roots.bootstrap_root_contract_version, id.contract_version);
}

test "rejects a noncanonical project root" {
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        buildRegistryId(std.testing.allocator, "project"),
    );
}

test "assembles one candidate without relabelling configured roots" {
    const allocator = std.testing.allocator;
    var roots: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot = undefined;
    for (&roots, 0..) |*capability, index| {
        const key: bootstrap_roots.PathKey = @enumFromInt(index);
        capability.* = .{
            .path_key = key,
            .root_role = key.role(),
            .canonical_project_root = "/project",
            .configured_relative_path = "root",
            .canonical_path = "/project/root",
            .access_class = key.accessClass(),
            .existence_policy = key.existencePolicy(),
            .observation = .absent,
        };
    }
    const candidate = try buildRegistryCandidate(
        allocator,
        .{
            .canonical_project_root = "/project",
            .contract_version = bootstrap_roots.bootstrap_root_contract_version,
        },
        "/project/.sddtoolkit.json",
        .{ .filesystem_id = 1, .file_id = 1 },
        roots,
        .{
            .relative_path = ".sddproviders.json",
            .canonical_project_root = "/project",
            .canonical_path = "/project/.sddproviders.json",
        },
    );
    defer allocator.free(candidate.config_location.canonical_config_path);

    try std.testing.expectEqualStrings(
        "/project/.sddtoolkit.json",
        candidate.config_location.canonical_config_path,
    );
    for (candidate.configured_roots, 0..) |capability, index| {
        try std.testing.expectEqual(@as(bootstrap_roots.PathKey, @enumFromInt(index)), capability.path_key);
        try std.testing.expectEqualStrings("/project", capability.canonical_project_root);
    }
    try std.testing.expectEqualStrings(
        ".sddproviders.json",
        candidate.llm_provider_config_path.relative_path,
    );
}
