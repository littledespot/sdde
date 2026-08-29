const std = @import("std");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{BootstrapRootRegistryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-bootstrap-root-registry-id@1",
        .kind = .action,
        .requires = &.{ .exact_engine_config_file, .configured_root_capability_set },
        .produces = &.{.bootstrap_root_registry_id},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        canonical_project_root: []const u8,
    ) Error!bootstrap_roots.BootstrapRootRegistryId {
        if (!std.fs.path.isAbsolute(canonical_project_root)) {
            return error.BootstrapRootRegistryInvalid;
        }
        return .{
            .canonical_project_root = allocator.dupe(u8, canonical_project_root) catch {
                return error.BootstrapRootRegistryInvalid;
            },
            .contract_version = bootstrap_roots.bootstrap_root_contract_version,
        };
    }
};

test "builds the self-validating project-root tuple without content identity" {
    const allocator = std.testing.allocator;
    const id = try (Action{}).execute(allocator, "/project");
    defer allocator.free(id.canonical_project_root);

    try std.testing.expectEqualStrings("/project", id.canonical_project_root);
    try std.testing.expectEqualStrings(bootstrap_roots.bootstrap_root_contract_version, id.contract_version);
}

test "rejects a noncanonical project root" {
    try std.testing.expectError(
        error.BootstrapRootRegistryInvalid,
        (Action{}).execute(std.testing.allocator, "project"),
    );
}
