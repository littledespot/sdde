const std = @import("std");

pub const ProjectRoot = struct {
    canonical_path: [:0]u8,
    dir: std.Io.Dir,

    pub fn deinit(self: *ProjectRoot, allocator: std.mem.Allocator) void {
        allocator.free(self.canonical_path);
        self.* = undefined;
    }
};

pub const Error = error{EngineConfigReadError};

pub fn execute(io: std.Io, allocator: std.mem.Allocator) Error!ProjectRoot {
    const path = std.process.currentPathAlloc(io, allocator) catch {
        return error.EngineConfigReadError;
    };
    errdefer allocator.free(path);
    if (!std.fs.path.isAbsolute(path)) return error.EngineConfigReadError;

    return .{
        .canonical_path = path,
        .dir = .cwd(),
    };
}

test "binds the invocation working directory once" {
    var root = try execute(std.testing.io, std.testing.allocator);
    defer root.deinit(std.testing.allocator);
    try std.testing.expect(std.fs.path.isAbsolute(root.canonical_path));
}
