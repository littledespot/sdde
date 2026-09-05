const std = @import("std");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const feature = @import("../../domain/feature_directory.zig");
const source = @import("../../ports/feature_directory_inspector.zig");
const directories = @import("directory_access.zig");
const observations = @import("../../domain/bootstrap_roots.zig");

pub const Adapter = struct {
    io: std.Io,
    project_root: std.Io.Dir,

    pub fn inspector(self: *Adapter) source.Inspector {
        return .{ .context = self, .inspect_fn = inspect };
    }

    fn inspect(context: *anyopaque, capability: *const roots.FeatureDirectoryReadCapability, allocator: std.mem.Allocator, selector: feature.Selector) source.Error!feature.Directory {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const binding = roots.bindFeatureDirectoryAdapter(capability);
        const checked = feature.validate(allocator, .{ .bytes = selector.feature_id.bytes }, binding.paths) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidFeatureDirectory => error.FeatureDirectoryUnavailable,
        };
        defer allocator.free(checked.project_relative_path);
        if (!std.mem.eql(u8, checked.project_relative_path, selector.project_relative_path)) return error.FeatureDirectoryUnavailable;
        var root = directories.open(self.io, self.project_root, binding.paths.specs) catch |err| return switch (err) {
            error.DirectoryMissing => if (binding.observation == .absent)
                .{ .selector = selector, .root_observation = .absent, .observation = .absent }
            else
                error.FeatureDirectoryUnavailable,
            else => error.FeatureDirectoryUnavailable,
        };
        defer root.close(self.io);
        const root_identity = directories.inspectReadable(self.io, root) catch return error.FeatureDirectoryUnavailable;
        switch (binding.observation) {
            .absent => return error.FeatureDirectoryUnavailable,
            .directory => |expected| if (!root_identity.eql(expected)) return error.FeatureDirectoryUnavailable,
        }
        const root_observation: observations.RootObservation = .{ .directory = root_identity };
        var directory = directories.open(self.io, root, selector.feature_id.bytes) catch |err| return switch (err) {
            error.DirectoryMissing => .{ .selector = selector, .root_observation = root_observation, .observation = .absent },
            else => error.FeatureDirectoryUnavailable,
        };
        defer directory.close(self.io);
        const identity = directories.inspectReadable(self.io, directory) catch return error.FeatureDirectoryUnavailable;
        return .{ .selector = selector, .root_observation = root_observation, .observation = .{ .directory = identity } };
    }
};
