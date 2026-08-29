//! Resolves the conservative portability policy for the active workspace.

const std = @import("std");
const builtin = @import("builtin");
const bootstrap_roots = @import("../../domain/bootstrap_roots.zig");
const file_identity = @import("file_identity.zig");

const Io = std.Io;

pub const Error = error{WorkspacePathPolicyUnavailable};

pub const Resolver = struct {
    io: Io,
    invocation_working_directory: Io.Dir,

    pub fn init(io: Io, invocation_working_directory: Io.Dir) Resolver {
        return .{
            .io = io,
            .invocation_working_directory = invocation_working_directory,
        };
    }

    pub fn resolve(
        self: *const Resolver,
        allocator: std.mem.Allocator,
    ) Error!bootstrap_roots.WorkspacePathPolicy {
        const canonical_root = if (self.invocation_working_directory.handle == Io.Dir.cwd().handle)
            std.process.currentPathAlloc(self.io, allocator) catch {
                return error.WorkspacePathPolicyUnavailable;
            }
        else
            self.invocation_working_directory.realPathFileAlloc(
                self.io,
                ".",
                allocator,
            ) catch return error.WorkspacePathPolicyUnavailable;
        defer allocator.free(canonical_root);

        if (!std.fs.path.isAbsolute(canonical_root) or
            canonical_root.len >= Io.Dir.max_path_bytes)
        {
            return error.WorkspacePathPolicyUnavailable;
        }

        var active_root = self.invocation_working_directory.openDir(self.io, ".", .{
            .follow_symlinks = false,
        }) catch return error.WorkspacePathPolicyUnavailable;
        defer active_root.close(self.io);
        _ = file_identity.inspect(active_root.handle) catch {
            return error.WorkspacePathPolicyUnavailable;
        };
        const active_limits = resolveActiveLimits(active_root.handle) catch {
            return error.WorkspacePathPolicyUnavailable;
        };

        return .{
            .max_component_bytes = @min(Io.Dir.max_name_bytes, active_limits.component),
            .max_relative_path_bytes = @min(Io.Dir.max_path_bytes - 1, active_limits.path),
            .max_absolute_path_bytes = @min(Io.Dir.max_path_bytes - 1, active_limits.path),
        };
    }
};

const ActiveLimits = struct {
    component: usize,
    path: usize,
};

fn resolveActiveLimits(handle: std.posix.fd_t) Error!ActiveLimits {
    const names = switch (builtin.os.tag) {
        .linux => .{ .component = 3, .path = 4 },
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        .freebsd,
        .openbsd,
        .netbsd,
        .dragonfly,
        => .{ .component = 4, .path = 5 },
        else => return error.WorkspacePathPolicyUnavailable,
    };
    const component = fpathconf(handle, names.component);
    const path = fpathconf(handle, names.path);
    if (component <= 0 or path <= 0) return error.WorkspacePathPolicyUnavailable;
    return .{
        .component = @intCast(component),
        .path = @intCast(path),
    };
}

extern "c" fn fpathconf(fd: std.posix.fd_t, name: c_int) c_long;

test "resolves policy only after inspecting the active workspace" {
    const io = std.testing.io;
    var workspace = std.testing.tmpDir(.{});
    defer workspace.cleanup();

    const resolver = Resolver.init(io, workspace.dir);
    const policy = try resolver.resolve(std.testing.allocator);
    try std.testing.expect(policy.policy_id == .portable_ascii_workspace_v1);
    try std.testing.expect(policy.max_component_bytes > 0);
    try std.testing.expect(policy.max_absolute_path_bytes > 0);
}
