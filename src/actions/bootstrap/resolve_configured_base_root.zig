const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootResolutionError};

pub const Action = struct {
    policy: bootstrap_roots.WorkspacePathPolicy,

    pub const contract: pipeline.NodeContract = .{
        .id = "resolve-configured-base-root@1",
        .kind = .action,
        .requires = &.{ .exact_engine_config_file, .configured_root_path_policy_set },
        .produces = &.{.configured_root_candidate_set},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        canonical_project_root: []const u8,
        normalized_path: bootstrap_roots.NormalizedConfiguredPath,
    ) Error!bootstrap_roots.ConfiguredRootCandidate {
        if (!std.fs.path.isAbsolute(canonical_project_root)) {
            return error.BootstrapRootResolutionError;
        }
        const canonical_path = std.fs.path.join(
            allocator,
            &.{ canonical_project_root, normalized_path.relative_path },
        ) catch return error.BootstrapRootResolutionError;
        errdefer allocator.free(canonical_path);

        if (canonical_path.len > self.policy.max_absolute_path_bytes or
            !isContained(canonical_project_root, canonical_path))
        {
            return error.BootstrapRootResolutionError;
        }

        return .{
            .path = normalized_path,
            .canonical_project_root = canonical_project_root,
            .canonical_path = canonical_path,
        };
    }
};

fn isContained(root: []const u8, candidate: []const u8) bool {
    if (std.mem.eql(u8, root, candidate)) return false;
    if (!std.mem.startsWith(u8, candidate, root)) return false;
    if (root.len == 1 and std.fs.path.isSep(root[0])) return true;
    return candidate.len > root.len and std.fs.path.isSep(candidate[root.len]);
}

test "joins one normalized path beneath the exact canonical project root" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = 1024,
    } };
    const normalized: bootstrap_roots.NormalizedConfiguredPath = .{
        .path_key = .workflows,
        .root_role = .workflow_authority,
        .relative_path = ".sddtoolkit/workflows",
    };
    const result = try action.execute(allocator, "/project", normalized);
    defer allocator.free(result.canonical_path);
    try std.testing.expectEqualStrings("/project/.sddtoolkit/workflows", result.canonical_path);
}

test "rejects a noncanonical project root and an absolute path ceiling breach" {
    const normalized: bootstrap_roots.NormalizedConfiguredPath = .{
        .path_key = .specs,
        .root_role = .specs_artifacts,
        .relative_path = "specs",
    };
    const action: Action = .{ .policy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = 12,
    } };
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        action.execute(std.testing.allocator, "relative", normalized),
    );
    try std.testing.expectError(
        error.BootstrapRootResolutionError,
        action.execute(std.testing.allocator, "/project", normalized),
    );
}

test "accepts the exact absolute path ceiling" {
    const normalized: bootstrap_roots.NormalizedConfiguredPath = .{
        .path_key = .specs,
        .root_role = .specs_artifacts,
        .relative_path = "specs",
    };
    const action: Action = .{ .policy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = "/project/specs".len,
    } };
    const resolved = try action.execute(std.testing.allocator, "/project", normalized);
    defer std.testing.allocator.free(resolved.canonical_path);
    try std.testing.expectEqualStrings("/project/specs", resolved.canonical_path);
}
