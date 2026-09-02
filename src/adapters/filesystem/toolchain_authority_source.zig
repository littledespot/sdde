const std = @import("std");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const toolchain = @import("../../domain/toolchain.zig");
const source_port = @import("../../ports/toolchain_authority_source.zig");
const file_identity = @import("file_identity.zig");

pub const Adapter = struct {
    io: std.Io,
    project_root: std.Io.Dir,
    pub fn init(io: std.Io, project_root: std.Io.Dir) Adapter {
        return .{ .io = io, .project_root = project_root };
    }
    pub fn projectCapturer(self: *Adapter) source_port.ProjectCapturer {
        return .{ .context = self, .capture_project_fn = captureProject };
    }
    pub fn presetEnumerator(self: *Adapter) source_port.PresetEnumerator {
        return .{ .context = self, .inventory_presets_fn = inventoryPresets };
    }
    pub fn presetCapturer(self: *Adapter) source_port.PresetCapturer {
        return .{ .context = self, .capture_preset_fn = capturePreset };
    }
    fn captureProject(context: *anyopaque, capability: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) source_port.Error!toolchain.Capture {
        const self = cast(context);
        const binding = roots.bindToolchainAuthorityAdapter(capability) orelse return error.InvalidToolchainSource;
        if (binding.kind != .principles) return error.InvalidToolchainSource;
        var directory = try self.openBound(binding);
        defer directory.close(self.io);
        return .{ .name = toolchain.project_filename, .bytes = try self.readExact(directory, toolchain.project_filename, null, null, allocator) };
    }
    fn inventoryPresets(context: *anyopaque, capability: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) source_port.Error![]const toolchain.Entry {
        const self = cast(context);
        const binding = roots.bindToolchainAuthorityAdapter(capability) orelse return error.InvalidToolchainSource;
        if (binding.kind != .preset_registry) return error.InvalidToolchainSource;
        var directory = try self.openBound(binding);
        defer directory.close(self.io);
        var entries: std.ArrayList(toolchain.Entry) = .empty;
        var iterator = directory.iterate();
        while (iterator.next(self.io) catch return error.InvalidToolchainSource) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, toolchain.preset_suffix) or entries.items.len == toolchain.max_presets) return error.InvalidToolchainSource;
            var file = directory.openFile(self.io, entry.name, .{ .mode = .read_only, .allow_directory = false, .follow_symlinks = false, .resolve_beneath = true }) catch return error.InvalidToolchainSource;
            defer file.close(self.io);
            const stat = file.stat(self.io) catch return error.InvalidToolchainSource;
            if (stat.kind != .file or stat.size > toolchain.max_document_bytes) return error.InvalidToolchainSource;
            entries.append(allocator, .{
                .name = allocator.dupe(u8, entry.name) catch return error.InvalidToolchainSource,
                .size = stat.size,
                .identity = file_identity.inspect(file.handle) catch return error.InvalidToolchainSource,
            }) catch return error.InvalidToolchainSource;
        }
        std.mem.sort(toolchain.Entry, entries.items, {}, lessEntry);
        return entries.toOwnedSlice(allocator) catch return error.InvalidToolchainSource;
    }
    fn capturePreset(context: *anyopaque, capability: *const roots.ConfiguredBaseRootCapability, entry: toolchain.Entry, allocator: std.mem.Allocator) source_port.Error!toolchain.Capture {
        const self = cast(context);
        const binding = roots.bindToolchainAuthorityAdapter(capability) orelse return error.InvalidToolchainSource;
        if (binding.kind != .preset_registry or !std.mem.endsWith(u8, entry.name, toolchain.preset_suffix)) return error.InvalidToolchainSource;
        var directory = try self.openBound(binding);
        defer directory.close(self.io);
        return .{ .name = entry.name, .bytes = try self.readExact(directory, entry.name, entry.size, entry.identity, allocator) };
    }
    fn openBound(self: *Adapter, binding: roots.ToolchainAuthorityAdapterBinding) source_port.Error!std.Io.Dir {
        var directory = self.project_root.openDir(self.io, binding.project_relative_path, .{ .iterate = true, .follow_symlinks = false }) catch return error.InvalidToolchainSource;
        errdefer directory.close(self.io);
        if (!(file_identity.inspect(directory.handle) catch return error.InvalidToolchainSource).eql(binding.physical_identity)) return error.InvalidToolchainSource;
        return directory;
    }
    fn readExact(self: *Adapter, directory: std.Io.Dir, name: []const u8, expected_size: ?u64, expected_identity: ?@import("../../domain/filesystem_identity.zig").FileIdentity, allocator: std.mem.Allocator) source_port.Error![]const u8 {
        var file = directory.openFile(self.io, name, .{ .mode = .read_only, .allow_directory = false, .follow_symlinks = false, .resolve_beneath = true }) catch return error.InvalidToolchainSource;
        defer file.close(self.io);
        const before = file.stat(self.io) catch return error.InvalidToolchainSource;
        const identity = file_identity.inspect(file.handle) catch return error.InvalidToolchainSource;
        if (before.kind != .file or before.size > toolchain.max_document_bytes or
            (expected_size != null and expected_size.? != before.size) or
            (expected_identity != null and !identity.eql(expected_identity.?))) return error.InvalidToolchainSource;
        var reader = file.reader(self.io, &.{});
        const bytes = reader.interface.allocRemaining(allocator, .limited(toolchain.max_document_bytes + 1)) catch return error.InvalidToolchainSource;
        const after = file.stat(self.io) catch return error.InvalidToolchainSource;
        if (bytes.len != before.size or after.size != before.size or !(file_identity.inspect(file.handle) catch return error.InvalidToolchainSource).eql(identity)) return error.InvalidToolchainSource;
        return bytes;
    }
};
fn cast(context: *anyopaque) *Adapter {
    return @ptrCast(@alignCast(context));
}
fn lessEntry(_: void, left: toolchain.Entry, right: toolchain.Entry) bool {
    return std.mem.order(u8, left.name, right.name) == .lt;
}
