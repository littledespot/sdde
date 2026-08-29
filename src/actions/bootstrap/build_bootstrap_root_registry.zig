const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootRegistryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-bootstrap-root-registry@1",
        .kind = .action,
        .requires = &.{ .bootstrap_root_registry_id, .configured_root_capability_set },
        .produces = &.{.bootstrap_root_registry},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        id: bootstrap_roots.BootstrapRootRegistryId,
        canonical_config_path: []const u8,
        config_file_identity: bootstrap_roots.NoFollowFileIdentity,
        configured_roots: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot,
    ) Error!bootstrap_roots.BootstrapRootRegistryCandidate {
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

        return .{
            .id = id,
            .config_location = .{
                .canonical_project_root = id.canonical_project_root,
                .canonical_config_path = owned_config_path,
                .no_follow_file_identity = config_file_identity,
            },
            .configured_roots = owned_roots,
        };
    }
};

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
    const candidate = try (Action{}).execute(
        allocator,
        .{
            .canonical_project_root = "/project",
            .contract_version = bootstrap_roots.bootstrap_root_contract_version,
        },
        "/project/.sddtoolkit.json",
        .{ .filesystem_id = 1, .file_id = 1 },
        roots,
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
}
