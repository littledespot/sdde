const std = @import("std");
const registry = @import("../../domain/principle_registry.zig");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const port = @import("../../ports/principle_source.zig");
const directories = @import("directory_access.zig");
const files = @import("file_access.zig");
const scan = @import("directory_inventory.zig").scan;
pub const Adapter = struct {
    io: std.Io,
    project_root: std.Io.Dir,
    pub fn reader(self: *Adapter) port.Reader {
        return .{ .context = self, .read_fn = read };
    }
    pub fn enumerator(self: *Adapter) port.Enumerator {
        return .{ .context = self, .enumerate_fn = enumerate };
    }
    pub fn capturer(self: *Adapter) port.Capturer {
        return .{ .context = self, .capture_fn = capture };
    }
    fn read(context: *anyopaque, capability: *const roots.ConfiguredBaseRootCapability, a: std.mem.Allocator) port.Error!registry.Captured {
        const raw = try enumerate(context, capability, a);
        const inventory = try registry.classify(a, raw, .{ .normalize_fn = @import("unicode_normalization").nfc }, .{ .fold_fn = @import("unicode_normalization").caseFold });
        return capture(context, capability, a, inventory);
    }
    fn enumerate(context: *anyopaque, capability: *const roots.ConfiguredBaseRootCapability, a: std.mem.Allocator) port.Error!registry.Raw {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const binding = roots.bindPrincipleSourcesAdapter(capability) orelse return error.PrincipleSourceUnavailable;
        const root = (directories.openObserved(self.io, self.project_root, binding.project_relative_path, .{ .directory = binding.physical_identity }) catch return error.PrincipleSourceUnavailable) orelse return error.PrincipleSourceUnavailable;
        defer root.close(self.io);
        return .{ .root = .{ .path = try a.dupe(u8, binding.project_relative_path), .identity = binding.physical_identity }, .entries = scan(self.io, a, root, registry.limits) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.PrincipleSourceUnavailable };
    }
    fn capture(context: *anyopaque, capability: *const roots.ConfiguredBaseRootCapability, a: std.mem.Allocator, inventory: registry.Inventory) port.Error!registry.Captured {
        const self: *Adapter = @ptrCast(@alignCast(context));
        try registry.validateInventory(inventory);
        const binding = roots.bindPrincipleSourcesAdapter(capability) orelse return error.PrincipleSourceUnavailable;
        if (!std.mem.eql(u8, binding.project_relative_path, inventory.root.path) or !binding.physical_identity.eql(inventory.root.identity)) return error.PrincipleSourceUnavailable;
        const root = (directories.openObserved(self.io, self.project_root, binding.project_relative_path, .{ .directory = binding.physical_identity }) catch return error.PrincipleSourceUnavailable) orelse return error.PrincipleSourceUnavailable;
        defer root.close(self.io);
        const started: std.Io.Clock.Timestamp = .now(self.io, .boot);
        var sources: std.ArrayList(registry.Capture) = .empty;
        for (inventory.entries, 0..) |entry, index| {
            if (entry.kind != .semantic_markdown) continue;
            if (started.durationTo(.now(self.io, .boot)).raw.toMilliseconds() > registry.limits.duration_ms) return error.PrincipleSourceUnavailable;
            const path = entry.descriptor.raw_path;
            var parent = root;
            var owned = false;
            defer if (owned) parent.close(self.io);
            var offset: usize = 0;
            while (std.mem.indexOfScalarPos(u8, path, offset, '/')) |slash| {
                const expected = for (inventory.entries) |candidate| {
                    if (candidate.kind == .directory and std.mem.eql(u8, candidate.descriptor.raw_path, path[0..slash])) break candidate.descriptor.observation.directory;
                } else return error.PrincipleSourceUnavailable;
                const next = (directories.openObserved(self.io, parent, path[offset..slash], .{ .directory = expected }) catch return error.PrincipleSourceUnavailable) orelse return error.PrincipleSourceUnavailable;
                if (owned) parent.close(self.io);
                parent = next;
                owned = true;
                offset = slash + 1;
            }
            const bytes = (files.capture(self.io, a, parent, std.fs.path.basename(path), entry.descriptor.observation.file, registry.max_source_bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.PrincipleSourceUnavailable) orelse return error.PrincipleSourceUnavailable;
            try sources.append(a, .{ .entry = @intCast(index + 1), .bytes = bytes });
        }
        const current = try enumerate(context, capability, a);
        if (current.entries.len != inventory.entries.len) return error.PrincipleSourceUnavailable;
        for (inventory.entries) |expected| {
            for (current.entries) |actual| {
                if (std.mem.eql(u8, actual.raw_path, expected.descriptor.raw_path) and std.meta.eql(actual.observation, expected.descriptor.observation)) break;
            } else return error.PrincipleSourceUnavailable;
        }
        return .{ .inventory = inventory, .sources = try sources.toOwnedSlice(a) };
    }
};
