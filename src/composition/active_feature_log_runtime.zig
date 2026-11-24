const std = @import("std");
const feature_log_sink = @import("../adapters/filesystem/feature_log_sink.zig");
const log_output = @import("../adapters/system/log_output.zig");
const trusted_log_clock = @import("../adapters/system/trusted_log_clock.zig");
const feature_log_runner = @import("../application/feature_log_runner.zig");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_policy = @import("../domain/log_policy.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");

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
        .ports = .{
            .clock = owner.clock.clock(),
            .acquirer = owner.sink.lockAcquirer(),
            .recoverer = owner.sink.streamRecoverer(),
            .creator = owner.sink.segmentCreator(),
            .rotator = owner.sink.segmentRotator(),
            .appender = owner.sink.recordAppender(),
            .closer = owner.sink.streamCloser(),
            .releaser = owner.sink.lockReleaser(),
            .console = owner.output.console(),
            .emergency = owner.output.emergency(),
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
