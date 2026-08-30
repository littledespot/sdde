const std = @import("std");
const feature_log_sink = @import("../adapters/filesystem/feature_log_sink.zig");
const log_output = @import("../adapters/system/log_output.zig");
const trusted_log_clock = @import("../adapters/system/trusted_log_clock.zig");
const feature_log_runner = @import("../application/feature_log_runner.zig");
const runtime = @import("../domain/feature_log_runtime.zig");
const logging = @import("../domain/logging.zig");
const artifacts = @import("../domain/workflow_artifact_registry.zig");
const stabilizer_port = @import("../ports/transaction_stabilizer.zig");

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
    policy: *const logging.CompiledLoggingPolicy,
    registry: *const artifacts.WorkflowArtifactRegistry,
    binding: *const runtime.ValidatedFeatureLogBinding,
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
        .sink = owner.sink.sink(),
        .clock = owner.clock.clock(),
        .console = owner.output.console(),
        .emergency_sink = owner.output.emergency(),
        .stabilizer = stabilizer,
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
