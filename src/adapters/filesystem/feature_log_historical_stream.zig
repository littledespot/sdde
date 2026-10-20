//! One stream of one prior run, opened only to prune its closed segments under
//! that run's own stream lock. It offers no create, append, rotate or close, and
//! it opens nothing of the other stream.
const std = @import("std");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const directory_boundary = @import("feature_log_directory.zig");
const file_identity = @import("file_identity.zig");
const lock = @import("feature_log_lock.zig");
const recovery = @import("feature_log_recovery.zig");
const retention_store = @import("feature_log_retention_store.zig");

const Io = std.Io;

pub const Adapter = struct {
    /// Owns transient segment bytes read during a prune.
    allocator: std.mem.Allocator,
    io: Io,
    run_directory: Io.Dir,
    binding_directory: Io.Dir,
    stream: log_stream.Stream,
    expected_binding: log_binding.BindingCandidate,
    lock_file: ?Io.File = null,

    pub const InitError = error{ InvalidArtifactRegistry, ArtifactStorageUnavailable, InsecurePermissions, Cancelled } || std.mem.Allocator.Error;

    pub fn init(
        allocator: std.mem.Allocator,
        io: Io,
        project_root: Io.Dir,
        registry: *const artifacts.WorkflowArtifactRegistry,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
    ) InitError!Adapter {
        const authority = try artifacts.bindHistoricalFeatureLogStream(allocator, registry, binding, stream) orelse return error.InvalidArtifactRegistry;
        defer allocator.free(authority.run_path);
        var specs_root = project_root.openDir(io, authority.specs_root_path, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        }) catch |err| return if (err == error.Canceled) error.Cancelled else error.ArtifactStorageUnavailable;
        defer specs_root.close(io);
        if (!(file_identity.inspect(specs_root.handle) catch return error.ArtifactStorageUnavailable).eql(authority.specs_root_identity)) {
            return error.InvalidArtifactRegistry;
        }
        var run = directory_boundary.openOwner(io, specs_root, authority.run_path) catch |err| return if (err == error.Cancelled) error.Cancelled else error.ArtifactStorageUnavailable;
        errdefer run.close(io);
        // The pruned directory is opened beneath the run directory whose lock
        // guards it, never by a second walk from the specs root.
        var binding_directory = directory_boundary.openOwner(io, run, authority.expected_binding.binding_id.bytes) catch |err| return if (err == error.Cancelled) error.Cancelled else error.ArtifactStorageUnavailable;
        errdefer binding_directory.close(io);
        try directory_boundary.validateOwner(io, run);
        try directory_boundary.validateOwner(io, binding_directory);
        return .{
            .allocator = allocator,
            .io = io,
            .run_directory = run,
            .binding_directory = binding_directory,
            .stream = stream,
            .expected_binding = authority.expected_binding,
        };
    }

    pub fn deinit(self: *Adapter) void {
        lock.deinit(self.io, &self.lock_file);
        self.binding_directory.close(self.io);
        self.run_directory.close(self.io);
        self.* = undefined;
    }

    pub fn lockAcquirer(self: *Adapter) sink_port.LockAcquirer {
        return .{ .context = self, .acquire_fn = acquire };
    }

    pub fn segmentPruner(self: *Adapter) sink_port.SegmentPruner {
        return .{ .context = self, .prune_fn = prune };
    }

    pub fn lockReleaser(self: *Adapter) sink_port.LockReleaser {
        return .{ .context = self, .release_fn = release };
    }

    fn acquire(context: *anyopaque, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, deadline_ms: u16) sink_port.Error!void {
        const self = cast(context);
        if (stream != self.stream or !log_binding.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
        return lock.acquire(self.io, self.run_directory, &self.lock_file, deadline_ms);
    }

    /// Closure and identity are proved again under the lock before anything is
    /// deleted, so a group that changed since discovery is never pruned.
    fn prune(context: *anyopaque, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, cutoff_unix_ms: u64) sink_port.Error!void {
        const self = cast(context);
        if (self.lock_file == null or stream != self.stream or !log_binding.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
        const state = recovery.inspectGroup(self.io, self.binding_directory, self.allocator, binding, stream) catch |err| return switch (err) {
            error.InvalidSegment => error.CorruptStream,
            error.SegmentUnavailable, error.Cancelled, error.OutOfMemory => error.SinkFailure,
        };
        switch (state) {
            .empty => return,
            .active => return error.CorruptStream,
            .closed => return retention_store.prune(self.io, self.allocator, self.binding_directory, cutoff_unix_ms),
        }
    }

    fn release(context: *anyopaque) sink_port.Error!void {
        const self = cast(context);
        return lock.release(self.io, &self.lock_file);
    }
};

fn cast(context: *anyopaque) *Adapter {
    return @ptrCast(@alignCast(context));
}
