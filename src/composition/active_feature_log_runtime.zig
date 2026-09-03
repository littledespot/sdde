const std = @import("std");
const feature_log_sink = @import("../adapters/filesystem/feature_log_sink.zig");
const log_output = @import("../adapters/system/log_output.zig");
const trusted_log_clock = @import("../adapters/system/trusted_log_clock.zig");
const feature_log_runner = @import("../application/feature_log_runner.zig");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_policy = @import("../domain/log_policy.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const stabilizer_port = @import("../ports/transaction_stabilizer.zig");
const acquire_lock = @import("../actions/log/acquire_feature_log_stream_lock.zig");
const release_lock = @import("../actions/log/release_feature_log_stream_lock.zig");
const recover_stream = @import("../actions/log/recover_feature_log_stream.zig");
const create_segment = @import("../actions/log/create_feature_log_segment.zig");
const rotate_segment = @import("../actions/log/rotate_feature_log_segment.zig");
const append_record = @import("../actions/log/append_feature_log_record.zig");
const close_stream = @import("../actions/log/close_feature_log_stream.zig");
const read_clock = @import("../actions/log/read_trusted_log_clock.zig");
const write_console = @import("../actions/log/write_console_log_record.zig");
const emit_emergency = @import("../actions/log/emit_emergency_log_failure_record.zig");
const stabilize_failure = @import("../actions/log/stabilize_log_failure.zig");

pub const Error = feature_log_sink.Adapter.InitError || error{OutOfMemory};
pub const Owner = opaque {};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    sink: feature_log_sink.Adapter,
    clock: trusted_log_clock.Adapter,
    output: log_output.Adapter,
    runner: feature_log_runner.Runner,
};

/// Composition-only assembly for an authority-bearing active feature log.
/// Feature activation owns every supplied authority and keeps it alive until
/// this runtime is released.
pub fn create(
    allocator: std.mem.Allocator,
    io: std.Io,
    project_root: std.Io.Dir,
    policy: *const log_policy.CompiledLoggingPolicy,
    registry: *const artifacts.WorkflowArtifactRegistry,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    stabilizer: stabilizer_port.Stabilizer,
) Error!*Owner {
    const owner = allocator.create(OwnerStorage) catch return error.OutOfMemory;
    errdefer allocator.destroy(owner);
    owner.backing_allocator = allocator;
    owner.sink = try feature_log_sink.Adapter.init(io, project_root, registry, binding);
    errdefer owner.sink.deinit();
    owner.clock = .{ .io = io };
    owner.output = .{ .io = io };
    owner.runner = .{
        .allocator = allocator,
        .policy = policy,
        .binding = binding,
        .actions = .{
            .acquire_lock = acquire_lock.Action{ .sink = owner.sink.lockAcquirer() },
            .release_lock = release_lock.Action{ .sink = owner.sink.lockReleaser() },
            .recover_stream = recover_stream.Action{ .sink = owner.sink.streamRecoverer() },
            .create_segment = create_segment.Action{ .sink = owner.sink.segmentCreator() },
            .rotate_segment = rotate_segment.Action{ .sink = owner.sink.segmentRotator() },
            .append_record = append_record.Action{ .sink = owner.sink.recordAppender() },
            .close_stream = close_stream.Action{ .sink = owner.sink.streamCloser() },
            .read_clock = read_clock.Action{ .clock = owner.clock.clock() },
            .write_console = write_console.Action{ .sink = owner.output.console() },
            .emit_emergency = emit_emergency.Action{ .sink = owner.output.emergency() },
            .stabilize_failure = stabilize_failure.Action{ .stabilizer = stabilizer },
        },
    };
    return @ptrCast(owner);
}

pub fn runner(owner: *Owner) *feature_log_runner.Runner {
    return &ownerStorage(owner).runner;
}

pub fn deinit(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.sink.deinit();
    allocator.destroy(storage);
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
