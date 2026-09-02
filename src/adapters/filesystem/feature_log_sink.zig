const std = @import("std");
const builtin = @import("builtin");
const runtime = @import("../../domain/feature_log_runtime.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const directory_boundary = @import("feature_log_directory.zig");
const file_identity = @import("file_identity.zig");
const lock = @import("feature_log_lock.zig");
const recovery = @import("feature_log_recovery.zig");
const retention_store = @import("feature_log_retention_store.zig");
const segment_store = @import("feature_log_segment_store.zig");

const Io = std.Io;

pub const Adapter = struct {
    io: Io,
    event_run_directory: Io.Dir,
    event_directory: Io.Dir,
    prompt_run_directory: Io.Dir,
    prompt_directory: Io.Dir,
    expected_binding: runtime.BindingCandidate,
    lock_file: ?Io.File = null,
    owns_directories: bool,
    scans_run_history: bool,

    pub const InitError = error{ InvalidArtifactRegistry, ArtifactStorageUnavailable, InsecurePermissions };

    pub fn init(
        io: Io,
        project_root: Io.Dir,
        registry: *const artifacts.WorkflowArtifactRegistry,
        binding: *const runtime.ValidatedFeatureLogBinding,
    ) InitError!Adapter {
        const authority = artifacts.bindFeatureLogSinkAdapter(registry, binding) orelse return error.InvalidArtifactRegistry;
        var specs_root = project_root.openDir(io, authority.specs_root_path, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        }) catch return error.ArtifactStorageUnavailable;
        defer specs_root.close(io);
        if (!(file_identity.inspect(specs_root.handle) catch return error.ArtifactStorageUnavailable).eql(authority.specs_root_identity)) {
            return error.InvalidArtifactRegistry;
        }
        var event_run = directory_boundary.openOwner(io, specs_root, authority.event_run_path) catch return error.ArtifactStorageUnavailable;
        errdefer event_run.close(io);
        var event_binding = directory_boundary.openOwner(io, specs_root, authority.event_binding_path) catch return error.ArtifactStorageUnavailable;
        errdefer event_binding.close(io);
        var prompt_run = directory_boundary.openOwner(io, specs_root, authority.prompt_run_path) catch return error.ArtifactStorageUnavailable;
        errdefer prompt_run.close(io);
        var prompt_binding = directory_boundary.openOwner(io, specs_root, authority.prompt_binding_path) catch return error.ArtifactStorageUnavailable;
        errdefer prompt_binding.close(io);
        try directory_boundary.validateOwner(io, event_run);
        try directory_boundary.validateOwner(io, event_binding);
        try directory_boundary.validateOwner(io, prompt_run);
        try directory_boundary.validateOwner(io, prompt_binding);
        return .{
            .io = io,
            .event_run_directory = event_run,
            .event_directory = event_binding,
            .prompt_run_directory = prompt_run,
            .prompt_directory = prompt_binding,
            .expected_binding = authority.expected_binding,
            .owns_directories = true,
            .scans_run_history = true,
        };
    }

    pub fn initForTest(io: Io, test_directory: Io.Dir, expected_binding: runtime.BindingCandidate) Adapter {
        if (!builtin.is_test) @compileError("test-only feature log sink constructor");
        return .{
            .io = io,
            .event_run_directory = test_directory,
            .event_directory = test_directory,
            .prompt_run_directory = test_directory,
            .prompt_directory = test_directory,
            .expected_binding = expected_binding,
            .owns_directories = false,
            .scans_run_history = false,
        };
    }

    pub fn initForTestLayout(
        io: Io,
        run_directory: Io.Dir,
        binding_directory: Io.Dir,
        expected_binding: runtime.BindingCandidate,
    ) Adapter {
        if (!builtin.is_test) @compileError("test-only feature log sink constructor");
        return .{
            .io = io,
            .event_run_directory = run_directory,
            .event_directory = binding_directory,
            .prompt_run_directory = run_directory,
            .prompt_directory = binding_directory,
            .expected_binding = expected_binding,
            .owns_directories = false,
            .scans_run_history = true,
        };
    }

    pub fn deinit(self: *Adapter) void {
        lock.deinit(self.io, &self.lock_file);
        if (self.owns_directories) {
            self.prompt_directory.close(self.io);
            self.prompt_run_directory.close(self.io);
            self.event_directory.close(self.io);
            self.event_run_directory.close(self.io);
        }
        self.* = undefined;
    }

    pub fn lockAcquirer(self: *Adapter) sink_port.LockAcquirer {
        return .{ .context = self, .acquire_fn = acquire };
    }

    pub fn streamRecoverer(self: *Adapter) sink_port.StreamRecoverer {
        return .{ .context = self, .recover_fn = recover };
    }

    pub fn segmentCreator(self: *Adapter) sink_port.SegmentCreator {
        return .{ .context = self, .create_fn = create };
    }

    pub fn segmentRotator(self: *Adapter) sink_port.SegmentRotator {
        return .{ .context = self, .rotate_fn = rotate };
    }

    pub fn streamCloser(self: *Adapter) sink_port.StreamCloser {
        return .{ .context = self, .close_fn = close };
    }

    pub fn recordAppender(self: *Adapter) sink_port.RecordAppender {
        return .{ .context = self, .append_fn = append };
    }

    pub fn segmentPruner(self: *Adapter) sink_port.SegmentPruner {
        return .{ .context = self, .prune_fn = prune };
    }

    pub fn lockReleaser(self: *Adapter) sink_port.LockReleaser {
        return .{ .context = self, .release_fn = release };
    }

    fn acquire(
        context: *anyopaque,
        binding: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
        deadline_ms: u16,
    ) sink_port.Error!void {
        const self = cast(context);
        if (!runtime.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
        return lock.acquire(self.io, self.runDirectory(stream), &self.lock_file, deadline_ms);
    }

    fn recover(
        context: *anyopaque,
        binding: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
        heading: []const u8,
        allocator: std.mem.Allocator,
    ) sink_port.Error!runtime.Recovery {
        const self = cast(context);
        try self.requireHeld(binding);
        return recovery.recover(self.recoverySource(stream), binding, stream, heading, allocator);
    }

    fn create(
        context: *anyopaque,
        binding: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
        ordinal: u16,
        seed: runtime.StreamSeed,
        heading: []const u8,
        header: []const u8,
    ) sink_port.Error!runtime.StreamState {
        const self = cast(context);
        try self.requireHeld(binding);
        return segment_store.create(self.io, self.directory(stream), ordinal, seed, heading, header);
    }

    fn rotate(
        context: *anyopaque,
        binding: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
        state: runtime.StreamState,
        trailer: []const u8,
        heading: []const u8,
        header: []const u8,
    ) sink_port.Error!runtime.StreamState {
        const self = cast(context);
        try self.requireHeld(binding);
        return segment_store.rotate(self.io, self.directory(stream), state, trailer, heading, header);
    }

    fn append(
        context: *anyopaque,
        binding: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
        state: runtime.StreamState,
        row: []const u8,
        flush: bool,
    ) sink_port.Error!runtime.PersistedEvidence {
        const self = cast(context);
        try self.requireHeld(binding);
        return segment_store.append(self.io, self.directory(stream), state, row, flush);
    }

    fn close(
        context: *anyopaque,
        binding: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
        state: runtime.StreamState,
        trailer: []const u8,
    ) sink_port.Error!void {
        const self = cast(context);
        try self.requireHeld(binding);
        return segment_store.close(self.io, self.directory(stream), state, trailer);
    }

    fn prune(
        context: *anyopaque,
        binding: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
        cutoff_unix_ms: u64,
    ) sink_port.Error!void {
        const self = cast(context);
        try self.requireHeld(binding);
        return retention_store.prune(self.io, self.directory(stream), cutoff_unix_ms);
    }

    fn release(context: *anyopaque) sink_port.Error!void {
        const self = cast(context);
        return lock.release(self.io, &self.lock_file);
    }

    fn requireHeld(self: *Adapter, binding: *const runtime.ValidatedFeatureLogBinding) sink_port.Error!void {
        if (self.lock_file == null or !runtime.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
    }

    fn directory(self: *Adapter, stream: runtime.Stream) Io.Dir {
        return if (stream == .event) self.event_directory else self.prompt_directory;
    }

    fn runDirectory(self: *Adapter, stream: runtime.Stream) Io.Dir {
        return if (stream == .event) self.event_run_directory else self.prompt_run_directory;
    }

    fn recoverySource(self: *Adapter, stream: runtime.Stream) recovery.Source {
        return .{
            .io = self.io,
            .directory = self.directory(stream),
            .run_directory = self.runDirectory(stream),
            .expected_binding = self.expected_binding,
            .scans_run_history = self.scans_run_history,
        };
    }
};

fn cast(context: *anyopaque) *Adapter {
    return @ptrCast(@alignCast(context));
}
