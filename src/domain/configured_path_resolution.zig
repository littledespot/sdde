const std = @import("std");
const roots = @import("bootstrap_roots.zig");

pub const Error = error{InvalidConfiguredPathResolution};

pub fn join(
    policy: roots.WorkspacePathPolicy,
    allocator: std.mem.Allocator,
    canonical_project_root: []const u8,
    relative_path: []const u8,
) Error![]u8 {
    if (!std.fs.path.isAbsolute(canonical_project_root)) return error.InvalidConfiguredPathResolution;
    const canonical_path = std.fs.path.join(allocator, &.{ canonical_project_root, relative_path }) catch {
        return error.InvalidConfiguredPathResolution;
    };
    errdefer allocator.free(canonical_path);
    if (canonical_path.len > policy.max_absolute_path_bytes or
        !isContained(canonical_project_root, canonical_path)) return error.InvalidConfiguredPathResolution;
    return canonical_path;
}

fn isContained(root: []const u8, candidate: []const u8) bool {
    if (std.mem.eql(u8, root, candidate) or !std.mem.startsWith(u8, candidate, root)) return false;
    if (root.len == 1 and std.fs.path.isSep(root[0])) return true;
    return candidate.len > root.len and std.fs.path.isSep(candidate[root.len]);
}
