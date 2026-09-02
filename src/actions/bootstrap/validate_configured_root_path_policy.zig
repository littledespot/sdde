const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const configured_path_policy = @import("../../domain/configured_path_policy.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootResolutionError};

pub const Action = struct {
    policy: bootstrap_roots.WorkspacePathPolicy,

    pub const contract: pipeline.NodeContract = .{
        .id = "validate-configured-root-path-policy@1",
        .kind = .action,
        .requires = &.{.engine_config},
        .produces = &.{.configured_root_path_policy_set},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        path_key: bootstrap_roots.PathKey,
        raw_path: []const u8,
    ) Error!bootstrap_roots.NormalizedConfiguredPath {
        return .{
            .path_key = path_key,
            .root_role = path_key.role(),
            .relative_path = configured_path_policy.normalize(self.policy, allocator, raw_path, true) catch {
                return error.BootstrapRootResolutionError;
            },
        };
    }
};

fn testPolicy() bootstrap_roots.WorkspacePathPolicy {
    return .{ .max_component_bytes = 16, .max_relative_path_bytes = 64, .max_absolute_path_bytes = 128 };
}

test "normalizes configured roots and rejects unsafe portable paths" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = testPolicy() };
    const result = try action.execute(allocator, .workflows, ".sddtoolkit/workflows/");
    defer allocator.free(result.relative_path);
    try std.testing.expectEqualStrings(".sddtoolkit/workflows", result.relative_path);

    const invalid = [_][]const u8{ "", "/absolute", "C:/drive", "a//b", "a/../b", "a\\b", "a/%2f/b", "a/con", "non-ascii-\xc3\xa9" };
    for (invalid) |path| try std.testing.expectError(
        error.BootstrapRootResolutionError,
        action.execute(allocator, .specs, path),
    );
}

test "accepts exact component and relative limits" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = testPolicy() };
    const component = try action.execute(allocator, .specs, "abcdefghijklmnop");
    defer allocator.free(component.relative_path);
    const relative = try action.execute(allocator, .references, "aaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbb/cccccccccccccccc/ddddddddddddd");
    defer allocator.free(relative.relative_path);
    try std.testing.expectEqual(@as(usize, 64), relative.relative_path.len);
}
