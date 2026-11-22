const stream = @import("feature_log_stream.zig");
const sink = @import("operation_error.zig").FeatureLogSink;

// Why a logging step stopped, from what its port reported (F0002, ADR 0026). A cancellation is no logging failure: it
// carries no code, and no emergency line reports it. Each function is the one mapping for the ports that share it.

/// A lock acquisition: only a lock held elsewhere is a timeout. A binding the sink rejects, or a lock file it cannot
/// use, is a sink failure.
pub fn ofLock(failure: sink) stream.Stop {
    return switch (failure) {
        error.LockUnavailable => .{ .blocked = .LOG_LOCK_TIMEOUT },
        error.Cancelled => .cancelled,
        error.InvalidBinding, error.CorruptStream, error.SegmentLimitExhausted, error.SinkFailure, error.FlushFailure, error.ReleaseFailure => .{ .blocked = .LOG_SINK_FAILURE },
    };
}

/// A recover, create, rotate or prune: every failure but a cancellation is a sink failure.
pub fn ofSink(failure: sink) stream.Stop {
    return switch (failure) {
        error.Cancelled => .cancelled,
        error.LockUnavailable, error.InvalidBinding, error.CorruptStream, error.SegmentLimitExhausted, error.SinkFailure, error.FlushFailure, error.ReleaseFailure => .{ .blocked = .LOG_SINK_FAILURE },
    };
}

/// An append or a close: a failed flush is its own logging failure.
pub fn ofFlushing(failure: sink) stream.Stop {
    return switch (failure) {
        error.FlushFailure => .{ .blocked = .LOG_FLUSH_FAILURE },
        error.Cancelled => .cancelled,
        error.LockUnavailable, error.InvalidBinding, error.CorruptStream, error.SegmentLimitExhausted, error.SinkFailure, error.ReleaseFailure => .{ .blocked = .LOG_SINK_FAILURE },
    };
}

pub const serialization: stream.Stop = .{ .blocked = .LOG_SERIALIZATION_FAILURE };
pub const sink_failure: stream.Stop = .{ .blocked = .LOG_SINK_FAILURE };
pub const release_failure: stream.Stop = .{ .blocked = .LOG_RELEASE_FAILURE };

/// The stop after a lock is released, where a release that failed is a logging failure of its own and outranks the stop
/// that preceded it. A cancelled step still releases, and its cancellation is kept when the release succeeds.
pub fn releaseOutranks(earlier: ?stream.Stop, released: bool) ?stream.Stop {
    return if (released) earlier else release_failure;
}

/// The stop after a lock is released, where the stop that preceded the release is the cause and is kept: retention
/// reports why it could not prune, and a release failure only when nothing else stopped it.
pub fn earlierOutranks(earlier: ?stream.Stop, released: bool) ?stream.Stop {
    return earlier orelse if (released) null else release_failure;
}

test "each port failure maps to the stop its kind has, and a cancellation is never a logging failure" {
    const testing = @import("std").testing;
    const lock_timeout: stream.Stop = .{ .blocked = .LOG_LOCK_TIMEOUT };
    const flush_failure: stream.Stop = .{ .blocked = .LOG_FLUSH_FAILURE };
    const failures = [_]sink{ error.LockUnavailable, error.Cancelled, error.InvalidBinding, error.CorruptStream, error.SegmentLimitExhausted, error.SinkFailure, error.FlushFailure, error.ReleaseFailure };
    for (failures) |failure| {
        const cancelled = failure == error.Cancelled;
        // Only a lock mapping times out, and only an append or a close names a failed flush.
        try testing.expectEqual(if (cancelled) stream.Stop.cancelled else if (failure == error.LockUnavailable) lock_timeout else sink_failure, ofLock(failure));
        try testing.expectEqual(if (cancelled) stream.Stop.cancelled else sink_failure, ofSink(failure));
        try testing.expectEqual(if (cancelled) stream.Stop.cancelled else if (failure == error.FlushFailure) flush_failure else sink_failure, ofFlushing(failure));
    }
}

test "after a release a failed release outranks the stop before it, except where the stop that caused it is kept" {
    const testing = @import("std").testing;
    const stops = [_]?stream.Stop{ null, .cancelled, sink_failure, serialization };
    for (stops) |earlier| {
        // A release that worked leaves the earlier stop, whichever mapping decides.
        try testing.expectEqual(earlier, releaseOutranks(earlier, true));
        try testing.expectEqual(earlier, earlierOutranks(earlier, true));
        // A release that failed is a stop of its own, which outranks the earlier one except where the earlier one is kept.
        try testing.expectEqual(@as(?stream.Stop, release_failure), releaseOutranks(earlier, false));
        try testing.expectEqual(@as(?stream.Stop, earlier orelse release_failure), earlierOutranks(earlier, false));
    }
}
