//! The bootstrap roots of a project directory as the engine observes them, for tests that run a
//! filesystem adapter against a real directory.
const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const root_contract = @import("../domain/bootstrap_roots.zig");

/// The configured root of each path key, in key order. Each is observed in `project`, so a directory
/// that exists is bound by its identity and one that does not is absent.
pub const root_names = [_][]const u8{ "requirements/current", "references", "archive", "workflows", "presets", "principles", "templates" };

pub fn owner(allocator: std.mem.Allocator, project: std.Io.Dir) !*roots.Owner {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var inspector = @import("../adapters/filesystem/bootstrap_root_inspector.zig").Adapter.init(std.testing.io, project);
    var configured: [root_contract.PathKey.count]root_contract.ValidatedConfiguredRoot = undefined;
    for (&configured, root_names, 0..) |*entry, name, index| {
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
