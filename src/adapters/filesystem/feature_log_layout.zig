//! Materializes only the selected observed feature and engine-owned log paths.
const std = @import("std");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const feature = @import("../../domain/feature_directory.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const active = @import("../../domain/active_feature_directory.zig");
const port_module = @import("../../ports/feature_log_layout.zig");
const directories = @import("directory_access.zig");
const log_directories = @import("feature_log_directory.zig");

const private_directory = std.Io.File.Permissions.fromMode(0o700);

pub const Adapter = struct {
    io: std.Io,
    project_root: std.Io.Dir,

    pub fn port(self: *Adapter) port_module.Port {
        return .{ .context = @ptrCast(self), .activate_fn = activate };
    }

    fn activate(context: *port_module.Context, allocator: std.mem.Allocator, capability: *const roots.FeatureOutputWriteCapability, prior: feature.Directory, binding: *const log_binding.ValidatedFeatureLogBinding) port_module.Error!*active.Owner {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const authority = roots.bindFeatureOutputAdapter(capability);
        active.validatePrior(allocator, authority, prior) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidActiveFeatureDirectory => error.InvalidFeatureLogLayout,
        };
        if (!std.mem.eql(u8, prior.selector.feature_id.bytes, binding.featureId().bytes)) return error.InvalidFeatureLogLayout;
        const specs = try self.activateObserved(self.project_root, authority.paths.specs, prior.root_observation);
        defer specs.close(self.io);
        const selected = try self.activateObserved(specs, prior.selector.feature_id.bytes, prior.observation);
        defer selected.close(self.io);
        const current: feature.Directory = .{
            .selector = prior.selector,
            .root_observation = .{ .directory = directories.inspectReadable(self.io, specs) catch |err| return mapDirectoryError(err) },
            .observation = .{ .directory = directories.inspectReadable(self.io, selected) catch |err| return mapDirectoryError(err) },
        };
        const owner = active.createValidated(allocator, authority, prior, current) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidActiveFeatureDirectory => error.InvalidFeatureLogLayout,
        };
        errdefer active.deinitOwner(owner);
        const artifact_owner = artifacts.createForActive(allocator, capability, binding, active.capability(owner)) catch return error.InvalidFeatureLogLayout;
        defer artifacts.deinitOwner(artifact_owner);
        const layout = artifacts.bindFeatureLogSinkAdapter(artifacts.registry(artifact_owner), binding) orelse return error.InvalidFeatureLogLayout;
        for ([_][]const u8{ layout.event_binding_path, layout.prompt_binding_path }) |relative| {
            // Every invocation owns a fresh run identity. Existing run paths are
            // collisions, never a request to append a previous execution's log.
            const run = try self.activateObserved(specs, std.fs.path.dirname(relative).?, .absent);
            defer run.close(self.io);
            const target = try self.activateObserved(run, std.fs.path.basename(relative), .absent);
            defer target.close(self.io);
            log_directories.validateOwner(self.io, target) catch |err| return mapLogDirectoryError(err);
            log_directories.validateOwner(self.io, run) catch |err| return mapLogDirectoryError(err);
        }
        // Creation via held descriptors cannot authorize a concurrently replaced
        // path. Reopen from the project root and compare both activated identities.
        const rechecked_specs = (directories.openObserved(self.io, self.project_root, authority.paths.specs, current.root_observation) catch |err| return mapDirectoryError(err)) orelse return error.FeatureLogLayoutUnavailable;
        defer rechecked_specs.close(self.io);
        const rechecked_feature = (directories.openObserved(self.io, rechecked_specs, current.selector.feature_id.bytes, current.observation) catch |err| return mapDirectoryError(err)) orelse return error.FeatureLogLayoutUnavailable;
        rechecked_feature.close(self.io);
        return owner;
    }

    fn activateObserved(self: *Adapter, base: std.Io.Dir, relative: []const u8, observed: @import("../../domain/bootstrap_roots.zig").RootObservation) port_module.Error!std.Io.Dir {
        if ((directories.openObserved(self.io, base, relative, observed) catch |err| return mapDirectoryError(err))) |existing| return existing;
        // The final component must still be absent when created. Intermediate
        // normalized directories may already exist; none may be followed links.
        const parent_path = std.fs.path.dirname(relative);
        const parent = if (parent_path) |path| directories.ensureWithPermissions(self.io, base, path, private_directory) catch |err| return mapDirectoryError(err) else base;
        defer if (parent_path != null) parent.close(self.io);
        const basename = std.fs.path.basename(relative);
        parent.createDir(self.io, basename, private_directory) catch |err| return switch (err) {
            error.Canceled => error.Cancelled,
            else => error.FeatureLogLayoutUnavailable,
        };
        return directories.open(self.io, parent, basename) catch |err| return mapDirectoryError(err);
    }
};

fn mapDirectoryError(err: directories.Error) port_module.Error {
    return switch (err) {
        error.Cancelled => error.Cancelled,
        error.DirectoryMissing, error.DirectoryUnavailable => error.FeatureLogLayoutUnavailable,
    };
}

fn mapLogDirectoryError(err: log_directories.Error) port_module.Error {
    return switch (err) {
        error.InsecurePermissions => error.InsecurePermissions,
        error.ArtifactStorageUnavailable => error.FeatureLogLayoutUnavailable,
    };
}
