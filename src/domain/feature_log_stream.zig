pub const Stream = enum { event, prompt };
pub const RuntimeStatus = enum { unprepared, prepared, retired };

pub const FailureCode = enum {
    LOG_LOCK_TIMEOUT,
    LOG_SERIALIZATION_FAILURE,
    LOG_SINK_FAILURE,
    LOG_FLUSH_FAILURE,
    LOG_RELEASE_FAILURE,
    LOG_SEGMENT_LIMIT_EXHAUSTED,
};

pub const ClockReading = struct {
    occurred_at_utc: [20]u8,
    unix_ms: u64,
    monotonic_ms: u64,

    pub fn utc(self: *const ClockReading) []const u8 {
        return &self.occurred_at_utc;
    }
};

pub const StreamState = struct {
    segment_ordinal: u16,
    next_sequence: u64,
    segment_bytes: u64,
    segment_count: u8,
    total_segment_count: u8,
    records_since_flush: u8,
    last_flush_monotonic_ms: u64,
};

pub const StreamSeed = struct {
    next_segment_ordinal: u16,
    next_sequence: u64,
    total_segment_count: u8,
};

pub const Recovery = union(enum) {
    empty: StreamSeed,
    active: StreamState,
};

/// What one binding's segments are, read without writing: no segment, every segment closed, or an active tail (the
/// last segment holds no trailer).
pub const TailState = enum { empty, closed, active };

pub const PersistedEvidence = struct {
    segment_ordinal: u16,
    sequence: u64,
    bytes_written: usize,
    flushed: bool,
};

/// Why a logging step stopped: a logging failure with its closed code, or a cancellation. A cancellation
/// is no logging failure; it carries no code, and no emergency line reports it.
pub const Stop = union(enum) {
    blocked: FailureCode,
    cancelled,
};

/// One stream's cached state. A cancelled step drops it, because a cancellation can land after bytes were written, so
/// the file may be ahead of the cache: a dropped stream is recovered from its bytes, as after a crash, before it is
/// written again or closed.
pub const Slot = union(enum) { unopened, open: StreamState, dropped };

/// What the logging routines act on: both streams' cached states and the activation flags.
pub const Runtime = struct {
    event: Slot = .unopened,
    prompt: Slot = .unopened,
    prepared: bool = false,
    retired: bool = false,

    pub fn slot(self: *Runtime, stream: Stream) *Slot {
        return switch (stream) {
            .event => &self.event,
            .prompt => &self.prompt,
        };
    }

    pub fn status(self: Runtime) RuntimeStatus {
        return if (self.retired) .retired else if (self.prepared) .prepared else .unprepared;
    }
};

/// How a logging routine ends: the fact was dropped or persisted, or the routine stopped. A stop is reported (an
/// emergency line for a failure, none for a cancellation) by the routine's caller, never by the routine.
pub const Result = union(enum) {
    dropped,
    persisted: PersistedEvidence,
    stopped: Stop,
};

pub const Outcome = union(enum) {
    dropped,
    persisted: PersistedEvidence,
    blocked: FailureCode,
    cancelled,

    /// The stop this outcome reports, or null when the fact was dropped or persisted.
    pub fn stop(self: Outcome) ?Stop {
        return switch (self) {
            .dropped, .persisted => null,
            .blocked => |code| .{ .blocked = code },
            .cancelled => .cancelled,
        };
    }
};
