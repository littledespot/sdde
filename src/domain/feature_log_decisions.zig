const limits = @import("feature_log_limits.zig");
const event_registry = @import("log_event_registry.zig");
const policy = @import("log_policy.zig");
const stream = @import("feature_log_stream.zig");
const telemetry = @import("telemetry.zig");

// The pure decisions of the feature-log routines: what a policy emits and captures, when a segment rotates, when a row
// forces a flush, how a stream's cached state advances, and when a run may be finalized. None reads a port.

pub const Emission = enum { emit, drop };
pub const Capture = enum { capture, drop };
pub const Flush = enum { flush, buffer };
pub const Rotation = union(enum) { append, rotate: u16, exhausted };

/// An ADR-required event is emitted at every threshold (§26.5); every other event follows the configured threshold.
pub fn emission(active: policy.CompiledLoggingPolicy, definition: event_registry.EventDefinition) Emission {
    return switch (definition.emission) {
        .always => .emit,
        .threshold => if (policy.isEmitted(active, definition.level)) .emit else .drop,
    };
}

pub fn capture(active: policy.CompiledLoggingPolicy) Capture {
    return if (policy.promptCaptureEnabled(active)) .capture else .drop;
}

pub fn rotation(state: stream.StreamState, row_bytes: usize, trailer_bytes: usize, next_header_bytes: usize) Rotation {
    if (state.segment_bytes + row_bytes + trailer_bytes <= limits.max_segment_bytes) return .append;
    if (state.total_segment_count == limits.max_segments) return .exhausted;
    if (next_header_bytes + row_bytes > limits.max_segment_bytes) return .exhausted;
    return .{ .rotate = state.segment_ordinal + 1 };
}

pub fn flush(
    active: policy.CompiledLoggingPolicy,
    level: telemetry.CanonicalLogLevel,
    event_type: telemetry.EventType,
    state: stream.StreamState,
    monotonic_ms: u64,
) Flush {
    const required = level.rank() >= active.flush_at_or_above.rank() or
        terminalEvent(event_type) or
        state.records_since_flush + 1 >= active.lower_level_flush_records or
        monotonic_ms -| state.last_flush_monotonic_ms >= active.lower_level_flush_interval_ms;
    return if (required) .flush else .buffer;
}

fn terminalEvent(event_type: telemetry.EventType) bool {
    return switch (event_type) {
        .stage_completed,
        .stage_blocked,
        .stage_failed,
        .task_completed,
        .task_blocked,
        .task_failed,
        => true,
        else => false,
    };
}

/// The stream's state after one row reached its file.
pub fn advance(current: stream.StreamState, row_bytes: usize, flushed: bool, monotonic_ms: u64) stream.StreamState {
    var next = current;
    next.segment_bytes += row_bytes;
    next.next_sequence += 1;
    if (flushed) {
        next.records_since_flush = 0;
        next.last_flush_monotonic_ms = monotonic_ms;
    } else {
        next.records_since_flush += 1;
    }
    return next;
}

/// Only a prepared, live run is finalized.
pub fn mayFinalize(status: stream.RuntimeStatus) bool {
    return status == .prepared;
}

test "a threshold above an event drops it before any identity or sink work" {
    const active: policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .warning, .alias_evidence = .none },
        .console = false,
    };
    try @import("std").testing.expectEqual(Emission.drop, emission(active, event_registry.eventDefinition(.run_started)));
}

test "ADR-required events are emitted at every threshold; other warnings follow it" {
    const testing = @import("std").testing;
    for (@import("std").enums.values(telemetry.CanonicalLogLevel)) |configured| {
        const active: policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = configured, .alias_evidence = .none }, .console = false };
        for ([_]telemetry.EventType{ .model_response_normalized, .model_provider_stopped, .model_runaway_resent }) |required|
            try testing.expectEqual(Emission.emit, emission(active, event_registry.eventDefinition(required)));
        const ordinary = event_registry.eventDefinition(.validation_failed);
        try testing.expectEqual(event_registry.Emission.threshold, ordinary.emission);
        try testing.expectEqual(if (policy.isEmitted(active, ordinary.level)) Emission.emit else Emission.drop, emission(active, ordinary));
    }
}

test "a row forces a flush when its level, its type, the record budget or the interval says so, and not otherwise" {
    const testing = @import("std").testing;
    const active: policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .trace, .alias_evidence = .none }, .console = false };
    const base: stream.StreamState = .{ .segment_ordinal = 1, .next_sequence = 3, .segment_bytes = 500, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 100 };
    const spent = limits.lower_level_flush_records;
    const interval: u64 = limits.lower_level_flush_interval_ms;
    // No trigger: a row below the flush level, not terminal, one record short of the budget, inside the interval.
    var quiet = base;
    quiet.records_since_flush = spent - 2;
    try testing.expectEqual(Flush.buffer, flush(active, .info, .run_started, quiet, 100 + interval - 1));
    // The level alone: at and above the configured flush level, never below it.
    try testing.expectEqual(Flush.flush, flush(active, .error_level, .run_started, quiet, 100));
    try testing.expectEqual(Flush.flush, flush(active, .fatal, .run_started, quiet, 100));
    try testing.expectEqual(Flush.buffer, flush(active, .warning, .run_started, quiet, 100));
    // The type alone: each terminal event type, and no other, at a level that does not force it.
    for ([_]telemetry.EventType{ .stage_completed, .stage_blocked, .stage_failed, .task_completed, .task_blocked, .task_failed }) |terminal|
        try testing.expectEqual(Flush.flush, flush(active, .info, terminal, quiet, 100));
    try testing.expectEqual(Flush.buffer, flush(active, .info, .validation_failed, quiet, 100));
    // The record budget alone: the row that reaches it flushes, the one before it does not.
    var counted = base;
    counted.records_since_flush = spent - 1;
    try testing.expectEqual(Flush.flush, flush(active, .info, .run_started, counted, 100));
    counted.records_since_flush = spent - 2;
    try testing.expectEqual(Flush.buffer, flush(active, .info, .run_started, counted, 100));
    // The interval alone: reached flushes, one millisecond short does not, and a clock behind the last flush is no wait.
    try testing.expectEqual(Flush.flush, flush(active, .info, .run_started, base, 100 + interval));
    try testing.expectEqual(Flush.buffer, flush(active, .info, .run_started, base, 100 + interval - 1));
    try testing.expectEqual(Flush.buffer, flush(active, .info, .run_started, base, 50));
    // A policy that flushes from a lower level makes that level a trigger.
    var lowered = active;
    lowered.flush_at_or_above = .info;
    try testing.expectEqual(Flush.flush, flush(lowered, .info, .run_started, base, 100));
    try testing.expectEqual(Flush.buffer, flush(lowered, .debug, .run_started, base, 100));
}

test "advancing a state counts the row, and a flush resets the budget and the interval" {
    const testing = @import("std").testing;
    const base: stream.StreamState = .{ .segment_ordinal = 1, .next_sequence = 3, .segment_bytes = 500, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 4, .last_flush_monotonic_ms = 100 };
    const buffered = advance(base, 40, false, 900);
    try testing.expectEqual(@as(u64, 4), buffered.next_sequence);
    try testing.expectEqual(@as(u64, 540), buffered.segment_bytes);
    try testing.expectEqual(@as(u8, 5), buffered.records_since_flush);
    try testing.expectEqual(@as(u64, 100), buffered.last_flush_monotonic_ms);
    const flushed = advance(base, 40, true, 900);
    try testing.expectEqual(@as(u8, 0), flushed.records_since_flush);
    try testing.expectEqual(@as(u64, 900), flushed.last_flush_monotonic_ms);
    try testing.expectEqual(@as(u64, 4), flushed.next_sequence);
}

test "only a prepared, live run is finalized" {
    const testing = @import("std").testing;
    try testing.expect(mayFinalize(.prepared));
    try testing.expect(!mayFinalize(.unprepared));
    try testing.expect(!mayFinalize(.retired));
}
