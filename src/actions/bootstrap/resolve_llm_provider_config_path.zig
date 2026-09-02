const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const configured_path_resolution = @import("../../domain/configured_path_resolution.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootResolutionError};

pub const Action = struct {
    policy: bootstrap_roots.WorkspacePathPolicy,

    pub const contract: pipeline.NodeContract = .{
        .id = "resolve-llm-provider-config-path@1",
        .kind = .action,
        .requires = &.{ .exact_engine_config_file, .llm_provider_config_path_policy },
        .produces = &.{.llm_provider_config_path_candidate},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        canonical_project_root: []const u8,
        normalized_path: bootstrap_roots.NormalizedLLMProviderConfigPath,
    ) Error!bootstrap_roots.LLMProviderConfigPathCandidate {
        return .{
            .relative_path = normalized_path.relative_path,
            .canonical_project_root = canonical_project_root,
            .canonical_path = configured_path_resolution.join(
                self.policy,
                allocator,
                canonical_project_root,
                normalized_path.relative_path,
            ) catch return error.BootstrapRootResolutionError,
        };
    }
};

test "resolves the provider document beneath the canonical project root" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = .{
        .max_component_bytes = 255,
        .max_relative_path_bytes = 1024,
        .max_absolute_path_bytes = 1024,
    } };
    const resolved = try action.execute(
        allocator,
        "/project",
        .{ .relative_path = "configuration/.sddproviders.json" },
    );
    defer allocator.free(resolved.canonical_path);
    try std.testing.expect(resolved.isStructurallyValid());
}
