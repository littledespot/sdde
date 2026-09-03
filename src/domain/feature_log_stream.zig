pub const Stream = enum { event, prompt };
pub const FinalizationMode = enum { active, historical };
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

pub const PersistedEvidence = struct {
    segment_ordinal: u16,
    sequence: u64,
    bytes_written: usize,
    flushed: bool,
};
