const std = @import("std");
const log_binding = @import("../domain/feature_log_binding.zig");
const log_stream = @import("../domain/feature_log_stream.zig");

pub const Error = error{
    LockUnavailable,
    InvalidBinding,
    CorruptStream,
    SegmentLimitExhausted,
    SinkFailure,
    FlushFailure,
    ReleaseFailure,
};

pub const LockAcquirer = struct {
    context: *anyopaque,
    acquire_fn: *const fn (*anyopaque, *const log_binding.ValidatedFeatureLogBinding, log_stream.Stream, u16) Error!void,
    pub fn acquire(self: LockAcquirer, value: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, deadline_ms: u16) Error!void {
        return self.acquire_fn(self.context, value, stream, deadline_ms);
    }
};

pub const StreamRecoverer = struct {
    context: *anyopaque,
    recover_fn: *const fn (*anyopaque, *const log_binding.ValidatedFeatureLogBinding, log_stream.Stream, []const u8, std.mem.Allocator) Error!log_stream.Recovery,
    pub fn recover(self: StreamRecoverer, value: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, heading: []const u8, allocator: std.mem.Allocator) Error!log_stream.Recovery {
        return self.recover_fn(self.context, value, stream, heading, allocator);
    }
};

pub const SegmentCreator = struct {
    context: *anyopaque,
    create_fn: *const fn (*anyopaque, *const log_binding.ValidatedFeatureLogBinding, log_stream.Stream, u16, log_stream.StreamSeed, []const u8, []const u8) Error!log_stream.StreamState,
    pub fn create(self: SegmentCreator, value: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, ordinal: u16, seed: log_stream.StreamSeed, heading: []const u8, header: []const u8) Error!log_stream.StreamState {
        return self.create_fn(self.context, value, stream, ordinal, seed, heading, header);
    }
};

pub const SegmentRotator = struct {
    context: *anyopaque,
    rotate_fn: *const fn (*anyopaque, *const log_binding.ValidatedFeatureLogBinding, log_stream.Stream, log_stream.StreamState, []const u8, []const u8, []const u8) Error!log_stream.StreamState,
    pub fn rotate(self: SegmentRotator, value: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, trailer: []const u8, heading: []const u8, header: []const u8) Error!log_stream.StreamState {
        return self.rotate_fn(self.context, value, stream, state, trailer, heading, header);
    }
};

pub const StreamCloser = struct {
    context: *anyopaque,
    close_fn: *const fn (*anyopaque, *const log_binding.ValidatedFeatureLogBinding, log_stream.Stream, log_stream.StreamState, []const u8) Error!void,
    pub fn close(self: StreamCloser, value: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, trailer: []const u8) Error!void {
        return self.close_fn(self.context, value, stream, state, trailer);
    }
};

pub const RecordAppender = struct {
    context: *anyopaque,
    append_fn: *const fn (*anyopaque, *const log_binding.ValidatedFeatureLogBinding, log_stream.Stream, log_stream.StreamState, []const u8, bool) Error!log_stream.PersistedEvidence,
    pub fn append(self: RecordAppender, value: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, row: []const u8, flush: bool) Error!log_stream.PersistedEvidence {
        return self.append_fn(self.context, value, stream, state, row, flush);
    }
};

pub const SegmentPruner = struct {
    context: *anyopaque,
    prune_fn: *const fn (*anyopaque, *const log_binding.ValidatedFeatureLogBinding, log_stream.Stream, u64) Error!void,
    pub fn prune(self: SegmentPruner, value: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, cutoff_unix_ms: u64) Error!void {
        return self.prune_fn(self.context, value, stream, cutoff_unix_ms);
    }
};

pub const LockReleaser = struct {
    context: *anyopaque,
    release_fn: *const fn (*anyopaque) Error!void,
    pub fn release(self: LockReleaser) Error!void {
        return self.release_fn(self.context);
    }
};
