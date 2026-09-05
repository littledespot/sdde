const std = @import("std");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const directory = @import("../../domain/feature_directory.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const source = @import("../../ports/feature_input_source.zig");
const directories = @import("directory_access.zig");

pub const Adapter = struct {
    io: std.Io,
    project_root: std.Io.Dir,

    pub fn capturer(self: *Adapter) source.Capturer {
        return .{ .context = self, .capture_fn = capture };
    }
    fn capture(context: *anyopaque, capability: *const roots.FeatureInputReadCapability, allocator: std.mem.Allocator, observed: directory.Directory, paths: artifacts.FeaturePaths) source.Error!clarification.Captures {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const binding = roots.bindFeatureInputAdapter(capability);
        if (!std.mem.eql(u8, observed.selector.feature_id.bytes, paths.feature.feature_id.bytes) or
            !std.mem.eql(u8, observed.selector.project_relative_path, paths.feature.project_relative_path) or
            !std.meta.eql(observed.root_observation, binding.specs_observation)) return error.FeatureInputUnavailable;
        const checked = artifacts.resolveFeaturePaths(allocator, binding.paths, paths.feature) catch return error.FeatureInputUnavailable;
        defer for (checked.entries) |entry| {
            allocator.free(entry.root_relative);
            allocator.free(entry.project_relative);
        };
        for (checked.entries, paths.entries) |expected, supplied| {
            if (expected.root != supplied.root or !std.mem.eql(u8, expected.root_relative, supplied.root_relative) or
                !std.mem.eql(u8, expected.project_relative, supplied.project_relative)) return error.FeatureInputUnavailable;
        }
        var forms: std.ArrayList(clarification.FormCapture) = .empty;
        errdefer {
            for (forms.items) |form| allocator.free(form.bytes);
            forms.deinit(allocator);
        }
        const specs = directories.openObserved(self.io, self.project_root, binding.paths.specs, binding.specs_observation) catch return error.FeatureInputUnavailable;
        if (specs) |root| {
            defer root.close(self.io);
            const selected = directories.openObserved(self.io, root, observed.selector.feature_id.bytes, observed.observation) catch return error.FeatureInputUnavailable;
            if (selected) |target| {
                defer target.close(self.io);
                const collection = directories.open(self.io, target, std.fs.path.basename(paths.get(.clarification_forms).root_relative)) catch |err| switch (err) {
                    error.DirectoryMissing => null,
                    else => return error.FeatureInputUnavailable,
                };
                if (collection) |folder| {
                    defer folder.close(self.io);
                    var iterator = folder.iterate();
                    while (iterator.next(self.io) catch return error.FeatureInputUnavailable) |entry| {
                        if (entry.kind != .file or forms.items.len == clarification.max_forms or entry.name.len != 6 or
                            !std.mem.endsWith(u8, entry.name, ".md")) return error.FeatureInputUnavailable;
                        const id = clarification.Id.parse(entry.name[0..3]) orelse return error.FeatureInputUnavailable;
                        const bytes = try readFile(self.io, allocator, folder, entry.name, clarification.max_form_bytes) orelse return error.FeatureInputUnavailable;
                        errdefer allocator.free(bytes);
                        try forms.append(allocator, .{ .id = id, .bytes = bytes });
                    }
                }
            }
        } else if (observed.observation != .absent) return error.FeatureInputUnavailable;
        std.mem.sort(clarification.FormCapture, forms.items, {}, lessForm);
        for (forms.items, 0..) |form, index| if (index > 0 and form.id.index() == forms.items[index - 1].id.index()) return error.FeatureInputUnavailable;

        const workflow_root = (directories.openObserved(self.io, self.project_root, binding.paths.workflows, .{ .directory = binding.workflows_identity }) catch return error.FeatureInputUnavailable) orelse return error.FeatureInputUnavailable;
        defer workflow_root.close(self.io);
        const state_path = paths.get(.clarification_state);
        const parent = directories.open(self.io, workflow_root, std.fs.path.dirname(state_path.root_relative).?) catch |err| switch (err) {
            error.DirectoryMissing => null,
            else => return error.FeatureInputUnavailable,
        };
        const state = if (parent) |folder| blk: {
            defer folder.close(self.io);
            break :blk try readFile(self.io, allocator, folder, std.fs.path.basename(state_path.root_relative), clarification.max_state_bytes);
        } else null;
        errdefer if (state) |bytes| allocator.free(bytes);
        return .{ .state = state, .forms = try forms.toOwnedSlice(allocator) };
    }
};

fn lessForm(_: void, left: clarification.FormCapture, right: clarification.FormCapture) bool {
    return left.id.index() < right.id.index();
}

fn readFile(io: std.Io, allocator: std.mem.Allocator, parent: std.Io.Dir, name: []const u8, maximum: usize) source.Error!?[]const u8 {
    return @import("file_access.zig").capture(io, allocator, parent, name, null, maximum) catch return error.FeatureInputUnavailable;
}
