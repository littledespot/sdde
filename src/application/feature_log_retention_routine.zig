const std = @import("std");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_limits = @import("../domain/feature_log_limits.zig");
const log_policy = @import("../domain/log_policy.zig");
const log_retention = @import("../domain/feature_log_retention.zig");
const log_stop = @import("../domain/feature_log_stop.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const clock_port = @import("../ports/trusted_log_clock.zig");
const sink_port = @import("../ports/feature_log_sink.zig");

// ADR 0032, ADR 0026: pruning one prior run's closed segments of one stream as one engine routine. It authorizes
// the prune from the trusted clock, resolves the stream that authorization names, takes the prior run's own stream
// lock, prunes, and releases the lock on every path. It is no pipeline node, writes no log row and reports nothing:
// a stop is its caller's to report. Cancellation reaches it only as the sink's `Cancelled`, so the lock is released
// after a cancelled prune. A prune stop is the cause and is kept; a release failure is reported only when nothing
// stopped the routine before it.

/// The closed set of steps, in execution order. A stop records the step it belongs to in the caller's `Diagnostic`.
pub const Step = enum { authorize, resolve_stream, acquire, prune, release };

/// What a stopped run leaves beside its stop: the step. No report reads it.
pub const Diagnostic = struct {
    step: ?Step = null,
};

/// The ports the routine's steps reach. No step receives this set; each takes the one port it uses.
pub const Ports = struct {
    clock: clock_port.Clock,
    acquirer: sink_port.LockAcquirer,
    pruner: sink_port.SegmentPruner,
    releaser: sink_port.LockReleaser,
};

/// The closed values the routine reads: the prior run's binding and the current run's, the stream to prune and the
/// policy that sets the retention period.
pub const Inputs = struct {
    allocator: std.mem.Allocator,
    policy: *const log_policy.CompiledLoggingPolicy,
    current: *const log_binding.ValidatedFeatureLogBinding,
    historical: *const log_binding.ValidatedFeatureLogBinding,
    target_stream: log_stream.Stream,
};

pub const Outcome = union(enum) { ok, stopped: log_stream.Stop };

/// The entry function only sequences the steps and passes each port on.
pub fn run(ports: Ports, inputs: Inputs, diagnostic: *Diagnostic) Outcome {
    const authorization = steps.authorize(ports.clock, inputs.allocator, inputs.policy, inputs.current, inputs.historical, inputs.target_stream) catch return stopped(diagnostic, .authorize, log_stop.sink_failure);
    defer log_retention.deinit(authorization);
    const selected = steps.resolveStream(authorization, inputs.current, inputs.historical) catch return stopped(diagnostic, .resolve_stream, log_stop.sink_failure);
    if (steps.acquire(ports.acquirer, inputs.historical, selected)) |stop| return stopped(diagnostic, .acquire, stop);
    // The lock is released after any prune outcome, a cancelled prune included.
    const pruned = steps.prune(ports.pruner, inputs.historical, authorization);
    const released = steps.release(ports.releaser);
    if (log_stop.earlierOutranks(pruned, released)) |stop| return stopped(diagnostic, if (pruned != null) .prune else .release, stop);
    return .ok;
}

fn stopped(diagnostic: *Diagnostic, step: Step, stop: log_stream.Stop) Outcome {
    diagnostic.step = step;
    return .{ .stopped = stop };
}

/// The five steps. Each is one typed function; a step that reaches a port takes exactly that port, and none takes the
/// port set. The pure steps call their domain owners.
pub const steps = struct {
    /// Reads the trusted clock once and builds the single-use authorization from it and the policy.
    pub fn authorize(
        clock: clock_port.Clock,
        allocator: std.mem.Allocator,
        policy: *const log_policy.CompiledLoggingPolicy,
        current: *const log_binding.ValidatedFeatureLogBinding,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        target_stream: log_stream.Stream,
    ) error{FeatureLogRetentionAuthorizationInvalid}!*log_retention.AuthorizationOwner {
        const reading = clock.now() catch return error.FeatureLogRetentionAuthorizationInvalid;
        return log_retention.create(allocator, policy, current, historical, target_stream, reading.unix_ms) catch error.FeatureLogRetentionAuthorizationInvalid;
    }

    pub fn resolveStream(
        authorization: *const log_retention.AuthorizationOwner,
        current: *const log_binding.ValidatedFeatureLogBinding,
        historical: *const log_binding.ValidatedFeatureLogBinding,
    ) error{FeatureLogRetentionAuthorizationInvalid}!log_stream.Stream {
        return log_retention.authorizedStream(authorization, current, historical) orelse error.FeatureLogRetentionAuthorizationInvalid;
    }

    pub fn acquire(
        acquirer: sink_port.LockAcquirer,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        selected: log_stream.Stream,
    ) ?log_stream.Stop {
        acquirer.acquire(historical, selected, log_limits.stream_lock_deadline_ms) catch |failure| return log_stop.ofLock(failure);
        return null;
    }

    /// Consumes the authorization, which a second prune cannot, and prunes the closed segments it names.
    pub fn prune(
        pruner: sink_port.SegmentPruner,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        authorization: *log_retention.AuthorizationOwner,
    ) ?log_stream.Stop {
        const authorized = log_retention.consume(authorization, historical) orelse return log_stop.sink_failure;
        pruner.prune(historical, authorized.stream, authorized.cutoff_unix_ms) catch |failure| return log_stop.ofSink(failure);
        return null;
    }

    /// Whether the lock was released. A release is no cancellation point: a sink that reports `Cancelled` here has
    /// failed to release.
    pub fn release(releaser: sink_port.LockReleaser) bool {
        releaser.release() catch return false;
        return true;
    }
};
