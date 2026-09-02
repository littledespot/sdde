const std = @import("std");
const bootstrap_root_registry = @import("../../domain/bootstrap_root_registry.zig");
const pipeline = @import("../../domain/pipeline.zig");
const definition = @import("../../domain/workflow_definition.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
const source_port = @import("../../ports/workflow_authority_source.zig");
const file_identity = @import("file_identity.zig");

const Io = std.Io;
pub const Adapter = struct {
    io: Io,
    project_root: Io.Dir,
    started_at: ?Io.Clock.Timestamp = null,

    pub fn init(io: Io, project_root: Io.Dir) Adapter {
        return .{ .io = io, .project_root = project_root };
    }
    pub fn enumerator(self: *Adapter) source_port.Enumerator {
        return .{ .context = self, .enumerate_fn = enumerate };
    }
    pub fn capturer(self: *Adapter) source_port.Capturer {
        return .{ .context = self, .capture_fn = capture };
    }

    fn enumerate(
        context: *anyopaque,
        capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) source_port.Error![]inventory.InventoryDescriptor {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const binding = bootstrap_root_registry.bindWorkflowAuthorityAdapter(capability) orelse {
            return error.InventoryInvalid;
        };
        try checkRuntime(runtime);
        self.started_at = .now(self.io, .boot);
        var root = self.project_root.openDir(self.io, binding.project_relative_path, .{
            .access_sub_paths = true,
            .iterate = true,
            .follow_symlinks = false,
        }) catch return error.InventoryInvalid;
        defer root.close(self.io);
        if (!(file_identity.inspect(root.handle) catch return error.InventoryInvalid).eql(binding.physical_identity)) {
            return error.InventoryInvalid;
        }
        var descriptors: std.ArrayList(inventory.InventoryDescriptor) = .empty;
        var walker = root.walkSelectively(allocator) catch return error.InventoryInvalid;
        defer walker.deinit();
        while (walker.next(self.io) catch return error.InventoryInvalid) |entry| {
            try self.checkBounds(runtime);
            if (descriptors.items.len == inventory.max_inventory_entries or
                entry.depth() > inventory.max_inventory_depth) return error.InventoryInvalid;
            const path = allocator.dupe(u8, entry.path) catch return error.InventoryInvalid;
            var descriptor: inventory.InventoryDescriptor = .{ .path = path, .kind = classify(entry.kind) };
            switch (descriptor.kind) {
                .file => {
                    var file = entry.dir.openFile(self.io, entry.basename, .{
                        .mode = .read_only,
                        .allow_directory = false,
                        .path_only = true,
                        .follow_symlinks = false,
                        .resolve_beneath = true,
                    }) catch return error.InventoryInvalid;
                    defer file.close(self.io);
                    const stat = file.stat(self.io) catch return error.InventoryInvalid;
                    if (stat.kind != .file) return error.InventoryInvalid;
                    descriptor.identity = file_identity.inspect(file.handle) catch return error.InventoryInvalid;
                    descriptor.size = stat.size;
                },
                .directory => {
                    var directory = entry.dir.openDir(self.io, entry.basename, .{
                        .iterate = true,
                        .follow_symlinks = false,
                    }) catch return error.InventoryInvalid;
                    defer directory.close(self.io);
                    descriptor.identity = file_identity.inspect(directory.handle) catch return error.InventoryInvalid;
                },
                .symlink, .special => {},
            }
            descriptors.append(allocator, descriptor) catch return error.InventoryInvalid;
            if (entry.kind == .directory and !reserved(entry.path, entry.depth())) {
                walker.enter(self.io, entry) catch return error.InventoryInvalid;
            }
        }
        return descriptors.toOwnedSlice(allocator) catch return error.InventoryInvalid;
    }

    fn capture(
        context: *anyopaque,
        capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability,
        descriptor: inventory.InventoryDescriptor,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) source_port.Error![]const u8 {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const binding = bootstrap_root_registry.bindWorkflowAuthorityAdapter(capability) orelse {
            return error.DefinitionReadError;
        };
        if (descriptor.kind != .file or descriptor.identity == null or descriptor.size == null or
            descriptor.size.? > definition.max_definition_bytes) return error.DefinitionReadError;
        try self.checkBounds(runtime);
        var root = self.project_root.openDir(self.io, binding.project_relative_path, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        }) catch return error.DefinitionReadError;
        defer root.close(self.io);
        if (!(file_identity.inspect(root.handle) catch return error.DefinitionReadError).eql(binding.physical_identity)) {
            return error.DefinitionReadError;
        }
        var file = root.openFile(self.io, descriptor.path, .{
            .mode = .read_only,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.DefinitionReadError;
        defer file.close(self.io);
        const before = file.stat(self.io) catch return error.DefinitionReadError;
        const identity = file_identity.inspect(file.handle) catch return error.DefinitionReadError;
        if (before.kind != .file or before.size != descriptor.size.? or
            !identity.eql(descriptor.identity.?)) return error.DefinitionReadError;
        var reader = file.reader(self.io, &.{});
        const bytes = reader.interface.allocRemaining(
            allocator,
            .limited(definition.max_definition_bytes + 1),
        ) catch return error.DefinitionReadError;
        if (bytes.len != before.size) return error.DefinitionReadError;
        const after = file.stat(self.io) catch return error.DefinitionReadError;
        if (after.kind != .file or after.size != before.size or
            !(file_identity.inspect(file.handle) catch return error.DefinitionReadError).eql(identity))
        {
            return error.DefinitionReadError;
        }
        try self.checkBounds(runtime);
        return bytes;
    }

    fn checkBounds(self: *Adapter, runtime: pipeline.NodeRuntime) source_port.Error!void {
        try checkRuntime(runtime);
        const started = self.started_at orelse return error.InventoryInvalid;
        if (started.durationTo(.now(self.io, .boot)).raw.toMilliseconds() >
            inventory.max_inventory_duration_ms) return error.DeadlineExhausted;
    }
};

fn checkRuntime(runtime: pipeline.NodeRuntime) source_port.Error!void {
    return switch (runtime.status()) {
        .active => {},
        .cancelled => error.Cancelled,
        .deadline_exhausted => error.DeadlineExhausted,
    };
}
fn classify(kind: Io.File.Kind) inventory.EntryKind {
    return switch (kind) {
        .directory => .directory,
        .file => .file,
        .sym_link => .symlink,
        else => .special,
    };
}
fn reserved(path: []const u8, depth: usize) bool {
    return depth == 1 and (std.mem.eql(u8, path, "features") or std.mem.eql(u8, path, "transactions"));
}
