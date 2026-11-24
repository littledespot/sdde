const std = @import("std");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_policy = @import("../domain/log_policy.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const clock_port = @import("../ports/trusted_log_clock.zig");
const console_port = @import("../ports/console_log_sink.zig");
const emergency_port = @import("../ports/emergency_log_sink.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

/// Every port one run's logging routines reach (ADR 0032). Composition builds it from the run's adapters and the
/// runtime logging lifecycle hands each routine the ports that routine names; no step ever receives the whole set.
pub const Ports = struct {
    clock: clock_port.Clock,
    acquirer: sink_port.LockAcquirer,
    recoverer: sink_port.StreamRecoverer,
    creator: sink_port.SegmentCreator,
    rotator: sink_port.SegmentRotator,
    appender: sink_port.RecordAppender,
    closer: sink_port.StreamCloser,
    releaser: sink_port.LockReleaser,
    console: console_port.Sink,
    emergency: emergency_port.Sink,
};

/// One run's feature-log state: its compiled policy and binding, its ports, and both streams' cached state with the
/// activation flags. It holds state and calls nothing: the runtime logging lifecycle runs the logging routines on it,
/// and a routine acts on its `runtime` through the pointer it is given.
pub const Runner = struct {
    allocator: std.mem.Allocator,
    policy: *const log_policy.CompiledLoggingPolicy,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    ports: Ports,
    runtime: log_stream.Runtime = .{},
};
