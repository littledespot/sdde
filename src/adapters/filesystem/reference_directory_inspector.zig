const std = @import("std");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const reference = @import("../../domain/reference_selector.zig");
const source = @import("../../ports/reference_directory_inspector.zig");
const directories = @import("directory_access.zig");

pub const Adapter = struct {
    io: std.Io,
    project_root: std.Io.Dir,

    pub fn inspector(self: *Adapter) source.Inspector {
        return .{ .context = self, .inspect_fn = inspect };
    }

    fn inspect(context: *anyopaque, capability: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator, selector: reference.RelativeSelector) source.Error!reference.Directory {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const binding = roots.bindReferenceSourcesAdapter(capability) orelse return error.ReferenceDirectoryUnavailable;
        // Recheck at the I/O boundary; a native caller cannot use a forged wrapper.
        _ = reference.validate(.{ .bytes = selector.bytes }) catch return error.ReferenceDirectoryUnavailable;
        const root = (directories.openObserved(self.io, self.project_root, binding.project_relative_path, .{ .directory = binding.physical_identity }) catch return error.ReferenceDirectoryUnavailable) orelse return error.ReferenceDirectoryUnavailable;
        defer root.close(self.io);
        var directory = directories.open(self.io, root, selector.bytes) catch return error.ReferenceDirectoryUnavailable;
        defer directory.close(self.io);
        const directory_identity = directories.inspectReadable(self.io, directory) catch return error.ReferenceDirectoryUnavailable;
        const relative = try std.mem.concat(allocator, u8, &.{ binding.project_relative_path, "/", selector.bytes });
        return .{ .selector = selector, .project_relative_path = relative, .root_identity = binding.physical_identity, .directory_identity = directory_identity };
    }
};
