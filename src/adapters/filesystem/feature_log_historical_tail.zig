//! One stream of one prior run, opened only to close the active tail a crash left (ADR 0026). Under that run's own
//! stream lock it reads the group without writing, recovers the tail by truncating to its last complete row, appends
//! one trailer and closes the segment. It offers no create, rotate, append or prune, and it opens nothing of the other
//! stream. Retention's historical stream remains the only prior-run adapter that deletes.
const std = @import("std");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const directory_boundary = @import("feature_log_directory.zig");
const file_identity = @import("file_identity.zig");
const lock = @import("feature_log_lock.zig");
const recovery = @import("feature_log_recovery.zig");
const segment_store = @import("feature_log_segment_store.zig");

const Io = std.Io;

pub const Adapter = struct {
    /// Owns transient segment bytes read while the group is inspected.
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
        }) catch |err| return directory_boundary.storageFault(err);
        defer specs_root.close(io);
        if (!(file_identity.inspect(specs_root.handle) catch return error.ArtifactStorageUnavailable).eql(authority.specs_root_identity)) {
            return error.InvalidArtifactRegistry;
        }
        var run = directory_boundary.openOwner(io, specs_root, authority.run_path) catch |err| return directory_boundary.storageFault(err);
        errdefer run.close(io);
        // The closed directory is opened beneath the run directory whose lock guards it, never by a second walk from
        // the specs root.
        var binding_directory = directory_boundary.openOwner(io, run, authority.expected_binding.binding_id.bytes) catch |err| return directory_boundary.storageFault(err);
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

    pub fn tailInspector(self: *Adapter) sink_port.TailInspector {
        return .{ .context = self, .inspect_fn = inspect };
    }

    pub fn streamRecoverer(self: *Adapter) sink_port.StreamRecoverer {
        return .{ .context = self, .recover_fn = recover };
    }

    pub fn streamCloser(self: *Adapter) sink_port.StreamCloser {
        return .{ .context = self, .close_fn = close };
    }

    pub fn lockReleaser(self: *Adapter) sink_port.LockReleaser {
        return .{ .context = self, .release_fn = release };
    }

    fn acquire(context: *anyopaque, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, deadline_ms: u16) sink_port.Error!void {
        const self = cast(context);
        if (stream != self.stream or !log_binding.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
        return lock.acquire(self.io, self.run_directory, &self.lock_file, deadline_ms);
    }

    /// Read-only, and only under the lock: what the group is now, which the routine compares with what discovery saw.
    fn inspect(context: *anyopaque, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream) sink_port.Error!log_stream.TailState {
        const self = cast(context);
        try self.requireHeld(binding, stream);
        const state = recovery.inspectGroup(self.io, self.binding_directory, self.allocator, binding, stream) catch |err| return switch (err) {
            error.InvalidSegment => error.CorruptStream,
            error.Cancelled => error.Cancelled,
            error.SegmentUnavailable, error.OutOfMemory => error.SinkFailure,
        };
        return switch (state) {
            .empty => .empty,
            .closed => .closed,
            .active => .active,
        };
    }

    /// Truncates the active tail to its last complete row, the one write besides the trailer a crash recovery makes.
    fn recover(
        context: *anyopaque,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
        heading: []const u8,
        allocator: std.mem.Allocator,
    ) sink_port.Error!log_stream.Recovery {
        const self = cast(context);
        try self.requireHeld(binding, stream);
        return recovery.recover(.{ .io = self.io, .directory = self.binding_directory }, binding, stream, heading, allocator);
    }

    fn close(
        context: *anyopaque,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
        state: log_stream.StreamState,
        trailer: []const u8,
    ) sink_port.Error!void {
        const self = cast(context);
        try self.requireHeld(binding, stream);
        return segment_store.close(self.io, self.binding_directory, state, trailer);
    }

    fn release(context: *anyopaque) sink_port.Error!void {
        const self = cast(context);
        return lock.release(self.io, &self.lock_file);
    }

    fn requireHeld(self: *Adapter, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream) sink_port.Error!void {
        if (self.lock_file == null or stream != self.stream or !log_binding.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
    }
};

fn cast(context: *anyopaque) *Adapter {
    return @ptrCast(@alignCast(context));
}
