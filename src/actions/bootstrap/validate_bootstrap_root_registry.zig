const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const bootstrap_root_registry = @import("../../domain/bootstrap_root_registry.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootRegistryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-bootstrap-root-registry@1",
        .kind = .action,
        .requires = &.{.bootstrap_root_registry},
        .produces = &.{.bootstrap_root_registry_evidence},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        candidate: bootstrap_roots.BootstrapRootRegistryCandidate,
    ) Error!*bootstrap_root_registry.Owner {
        return bootstrap_root_registry.createValidated(allocator, candidate) catch {
            return error.BootstrapRootRegistryInvalid;
        };
    }
};

fn validCandidate() bootstrap_roots.BootstrapRootRegistryCandidate {
    const paths = [_][]const u8{
        "specs",
        "references",
        "specs/archive",
        ".sdd/workflows",
        ".sdd/presets",
        ".sdd/principles",
        ".sdd/templates",
    };
    var roots: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot = undefined;
    for (&roots, 0..) |*root, index| {
        const key: bootstrap_roots.PathKey = @enumFromInt(index);
        root.* = .{
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
                .{ .directory = .{ .filesystem_id = 1, .file_id = 4 } }
            else
                .absent,
        };
    }
    return .{
        .id = .{
            .canonical_project_root = "/project",
            .contract_version = bootstrap_roots.bootstrap_root_contract_version,
        },
        .config_location = .{
            .canonical_project_root = "/project",
            .canonical_config_path = "/project/.sddtoolkit.json",
            .no_follow_file_identity = .{ .filesystem_id = 1, .file_id = 1 },
        },
        .configured_roots = roots,
    };
}

test "accepts the exact seven mappings and sole archive nesting exception" {
    const owner = try (Action{}).execute(std.testing.allocator, validCandidate());
    defer bootstrap_root_registry.deinitOwner(owner);
    const registry = bootstrap_root_registry.registry(owner);
    const workflow_authority = registry.workflowAuthority();
    try std.testing.expect(workflow_authority.isPresent());
    try std.testing.expectEqual(bootstrap_roots.PathKey.workflows, workflow_authority.pathKey());
    try std.testing.expectEqual(
        bootstrap_roots.ConfiguredRootRole.workflow_authority,
        workflow_authority.role(),
    );
}

test "publishes each configured root through one concrete typed accessor" {
    const owner = try (Action{}).execute(std.testing.allocator, validCandidate());
    defer bootstrap_root_registry.deinitOwner(owner);
    const registry = bootstrap_root_registry.registry(owner);
    const capabilities = [_]*const bootstrap_root_registry.ConfiguredBaseRootCapability{
        registry.specsArtifacts(),
        registry.referenceSources(),
        registry.archivedSpecs(),
        registry.workflowAuthority(),
        registry.toolchainPresetRegistry(),
        registry.projectPrinciples(),
        registry.initializationTemplates(),
    };

    for (capabilities, 0..) |capability, index| {
        const expected: bootstrap_roots.PathKey = @enumFromInt(index);
        try std.testing.expectEqual(expected, capability.pathKey());
        try std.testing.expectEqual(expected.role(), capability.role());
        for (capabilities[0..index]) |previous| {
            try std.testing.expect(capability != previous);
        }
    }
}

test "rejects duplicate missing relabelled and case-fold-equivalent capabilities" {
    var duplicate = validCandidate();
    duplicate.configured_roots[1].path_key = .specs;
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, duplicate),
    );

    var relabelled = validCandidate();
    relabelled.configured_roots[1].root_role = .workflow_authority;
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, relabelled),
    );

    var collision = validCandidate();
    collision.configured_roots[1].configured_relative_path = "SPECS";
    collision.configured_roots[1].canonical_path = "/project/SPECS";
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, collision),
    );
}

test "rejects every undeclared nesting direction and physical alias" {
    var nested = validCandidate();
    nested.configured_roots[1].configured_relative_path = "specs/reference";
    nested.configured_roots[1].canonical_path = "/project/specs/reference";
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, nested),
    );

    var reverse_archive = validCandidate();
    reverse_archive.configured_roots[0].configured_relative_path = "specs/archive/active";
    reverse_archive.configured_roots[0].canonical_path = "/project/specs/archive/active";
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, reverse_archive),
    );

    var alias = validCandidate();
    alias.configured_roots[0].observation = .{
        .directory = .{ .filesystem_id = 9, .file_id = 77 },
    };
    alias.configured_roots[1].observation = .{
        .directory = .{ .filesystem_id = 9, .file_id = 77 },
    };
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, alias),
    );
}

test "does not confuse equal file ids from different filesystems" {
    var candidate = validCandidate();
    candidate.configured_roots[0].observation = .{
        .directory = .{ .filesystem_id = 1, .file_id = 77 },
    };
    candidate.configured_roots[1].observation = .{
        .directory = .{ .filesystem_id = 2, .file_id = 77 },
    };

    const owner = try (Action{}).execute(std.testing.allocator, candidate);
    defer bootstrap_root_registry.deinitOwner(owner);
}

test "rejects a canonical path that does not match its normalized relative path" {
    var mismatched = validCandidate();
    mismatched.configured_roots[1].canonical_path = "/project/other";
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, mismatched),
    );
}
