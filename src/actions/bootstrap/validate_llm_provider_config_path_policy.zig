const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const configured_path_policy = @import("../../domain/configured_path_policy.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootResolutionError};

pub const Action = struct {
    policy: bootstrap_roots.WorkspacePathPolicy,

    pub const contract: pipeline.NodeContract = .{
        .id = "validate-llm-provider-config-path-policy@1",
        .kind = .action,
        .requires = &.{.engine_config},
        .produces = &.{.llm_provider_config_path_policy},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        raw_path: []const u8,
    ) Error!bootstrap_roots.NormalizedLLMProviderConfigPath {
        const normalized = configured_path_policy.normalize(self.policy, allocator, raw_path, false) catch {
            return error.BootstrapRootResolutionError;
        };
        errdefer allocator.free(normalized);
        if (!std.mem.eql(u8, std.fs.path.basename(normalized), bootstrap_roots.llm_provider_config_basename)) {
            return error.BootstrapRootResolutionError;
        }
        return .{ .relative_path = normalized };
    }
};

test "requires the exact provider basename without a directory suffix" {
    const allocator = std.testing.allocator;
    const action: Action = .{ .policy = .{
        .max_component_bytes = 32,
        .max_relative_path_bytes = 128,
        .max_absolute_path_bytes = 256,
    } };
    const exact = try action.execute(allocator, "configuration/.sddproviders.json");
    defer allocator.free(exact.relative_path);
    try std.testing.expectEqualStrings("configuration/.sddproviders.json", exact.relative_path);
    for ([_][]const u8{
        "configuration/providers.json",
        "configuration/.sddproviders.json/",
        "configuration/.SDDPROVIDERS.JSON",
    }) |path| try std.testing.expectError(
        error.BootstrapRootResolutionError,
        action.execute(allocator, path),
    );
}
