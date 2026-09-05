const std = @import("std");
const reference = @import("../../domain/reference_ingestion.zig");
const selection = @import("../../domain/reference_selector.zig");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const source = @import("../../ports/reference_corpus_source.zig");
const paths = @import("../../domain/relative_directory_path.zig");
const directories = @import("directory_access.zig");
const files = @import("file_access.zig");

pub const Adapter = struct {
    io: std.Io,
    project_root: std.Io.Dir,
    pub fn enumerator(self: *Adapter) source.Enumerator {
        return .{ .context = self, .enumerate_fn = enumerate };
    }
    pub fn capturer(self: *Adapter) source.Capturer {
        return .{ .context = self, .capture_fn = capture };
    }
    fn openSelected(self: *Adapter, capability: *const roots.ReferenceContentReadCapability, allocator: std.mem.Allocator, observed: selection.Directory) source.Error!std.Io.Dir {
        const binding = roots.bindReferenceContentAdapter(capability) orelse return error.ReferenceUnavailable;
        _ = selection.validate(.{ .bytes = observed.selector.bytes }) catch return error.ReferenceUnavailable;
        const project_path = try std.mem.concat(allocator, u8, &.{ binding.project_relative_path, "/", observed.selector.bytes });
        defer allocator.free(project_path);
        if (!std.mem.eql(u8, project_path, observed.project_relative_path) or !binding.physical_identity.eql(observed.root_identity)) return error.ReferenceUnavailable;
        const root = (directories.openObserved(self.io, self.project_root, binding.project_relative_path, .{ .directory = binding.physical_identity }) catch return error.ReferenceUnavailable) orelse return error.ReferenceUnavailable;
        defer root.close(self.io);
        return (directories.openObserved(self.io, root, observed.selector.bytes, .{ .directory = observed.directory_identity }) catch return error.ReferenceUnavailable) orelse return error.ReferenceUnavailable;
    }
    fn enumerate(context: *anyopaque, capability: *const roots.ReferenceContentReadCapability, allocator: std.mem.Allocator, observed: selection.Directory) source.Error!reference.RawInventory {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const root = try self.openSelected(capability, allocator, observed);
        defer root.close(self.io);
        return .{ .directory = observed, .entries = try self.scan(allocator, root) };
    }
    /// The caller owns an arena, including any partial inventory on failure.
    fn scan(self: *Adapter, allocator: std.mem.Allocator, root: std.Io.Dir) source.Error![]const reference.Descriptor {
        var entries: std.ArrayList(reference.Descriptor) = .empty;
        try self.walk(allocator, root, "", 1, .now(self.io, .boot), &entries);
        return entries.toOwnedSlice(allocator);
    }
    fn walk(self: *Adapter, allocator: std.mem.Allocator, parent: std.Io.Dir, prefix: []const u8, depth: usize, started: std.Io.Clock.Timestamp, entries: *std.ArrayList(reference.Descriptor)) source.Error!void {
        var iterator = parent.iterate();
        while (iterator.next(self.io) catch return error.ReferenceUnavailable) |entry| {
            try self.checkTime(started);
            if (entries.items.len >= reference.limits.entries or depth > reference.limits.depth) return error.ReferenceLimitExceeded;
            const path = try std.mem.concat(allocator, u8, &.{ prefix, entry.name });
            paths.validate(path) catch return error.ReferenceUnavailable;
            const index = entries.items.len;
            try entries.append(allocator, .{ .raw_path = path, .observation = .{ .unreadable = {} } });
            switch (entry.kind) {
                .directory => {
                    const child = directories.open(self.io, parent, entry.name) catch continue;
                    defer child.close(self.io);
                    const id = directories.inspectReadable(self.io, child) catch continue;
                    entries.items[index].observation = .{ .directory = id };
                    const next = try std.mem.concat(allocator, u8, &.{ path, "/" });
                    try self.walk(allocator, child, next, depth + 1, started, entries);
                },
                .file => {
                    const observation = files.observe(self.io, parent, entry.name) catch continue;
                    entries.items[index].observation = .{ .file = observation };
                },
                .sym_link => entries.items[index].observation = .{ .symlink = {} },
                else => entries.items[index].observation = .{ .special = {} },
            }
        }
    }
    fn capture(context: *anyopaque, capability: *const roots.ReferenceContentReadCapability, allocator: std.mem.Allocator, inventory: reference.Inventory) source.Error!reference.CapturedCorpus {
        const self: *Adapter = @ptrCast(@alignCast(context));
        if (inventory.entries.len > reference.limits.entries) return error.ReferenceLimitExceeded;
        const root = try self.openSelected(capability, allocator, inventory.directory);
        defer root.close(self.io);
        const started: std.Io.Clock.Timestamp = .now(self.io, .boot);
        const entries = try allocator.alloc(reference.CapturedEntry, inventory.entries.len);
        var total: usize = 0;
        var revision: u32 = 0;
        for (inventory.entries, 0..) |entry, index| {
            try self.checkTime(started);
            paths.validate(entry.raw_path) catch return error.ReferenceUnavailable;
            if (entry.id.ordinal != index + 1) return error.ReferenceUnavailable;
            var item: reference.CapturedEntry = .{ .entry = entry, .source = .{ .blocked = .unreadable }, .debit = null };
            switch (entry.observation) {
                .directory => item.source = .{ .directory = {} },
                .symlink => item.source = .{ .blocked = .symlink },
                .special => item.source = .{ .blocked = .special },
                .unreadable => {},
                .file => |expected| file: {
                    if (expected.size > reference.limits.source_file_bytes) {
                        item.source = .{ .blocked = .source_size };
                        break :file;
                    }
                    if (expected.size > reference.limits.source_corpus_bytes - total) {
                        item.source = .{ .blocked = .source_budget };
                        break :file;
                    }
                    const reserved: usize = @intCast(expected.size);
                    revision += 1;
                    item.debit = .{ .reserved = reserved, .outcome = .{ .released = {} } };
                    item.source = .{ .blocked = .source_capture };
                    const parent = self.openParent(root, inventory, entry.raw_path) catch break :file;
                    defer if (parent.owned) parent.directory.close(self.io);
                    const bytes = files.capture(self.io, allocator, parent.directory, std.fs.path.basename(entry.raw_path), expected, reserved) catch break :file;
                    item.source = .{ .bytes = bytes orelse break :file };
                    item.debit = .{ .reserved = reserved, .outcome = .{ .committed = reserved } };
                    total += reserved;
                },
            }
            entries[index] = item;
        }
        try self.checkTime(started);
        // Detect additions/removals/replacements without reopening source bodies.
        const current_root = try self.openSelected(capability, allocator, inventory.directory);
        defer current_root.close(self.io);
        const current = try self.scan(allocator, current_root);
        if (current.len != inventory.entries.len) return error.ReferenceInventoryChanged;
        for (inventory.entries) |expected| {
            const actual = for (current) |entry| {
                if (std.mem.eql(u8, entry.raw_path, expected.raw_path)) break entry;
            } else return error.ReferenceInventoryChanged;
            if (!std.meta.eql(actual.observation, expected.observation)) return error.ReferenceInventoryChanged;
        }
        return .{ .inventory = inventory, .entries = entries, .source_bytes = total, .budget_revision = revision };
    }
    fn openParent(self: *Adapter, root: std.Io.Dir, inventory: reference.Inventory, path: []const u8) source.Error!struct { directory: std.Io.Dir, owned: bool } {
        var current = root;
        var owned = false;
        errdefer if (owned) current.close(self.io);
        var offset: usize = 0;
        while (std.mem.indexOfScalarPos(u8, path, offset, '/')) |slash| {
            const prior = for (inventory.entries) |entry| {
                if (std.mem.eql(u8, entry.raw_path, path[0..slash])) break entry;
            } else return error.ReferenceUnavailable;
            if (prior.observation != .directory) return error.ReferenceUnavailable;
            const next = (directories.openObserved(self.io, current, path[offset..slash], .{ .directory = prior.observation.directory }) catch return error.ReferenceUnavailable) orelse return error.ReferenceUnavailable;
            if (owned) current.close(self.io);
            current = next;
            owned = true;
            offset = slash + 1;
        }
        return .{ .directory = current, .owned = owned };
    }
    fn checkTime(self: *Adapter, started: std.Io.Clock.Timestamp) source.Error!void {
        if (started.durationTo(.now(self.io, .boot)).raw.toMilliseconds() > reference.limits.duration_ms) return error.ReferenceLimitExceeded;
    }
};
