const std = @import("std");
const runtime = @import("../domain/feature_log_runtime.zig");

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
    acquire_fn: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, u16) Error!void,
    pub fn acquire(self: LockAcquirer, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, deadline_ms: u16) Error!void {
        return self.acquire_fn(self.context, value, stream, deadline_ms);
    }
};

pub const StreamRecoverer = struct {
    context: *anyopaque,
    recover_fn: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, []const u8, std.mem.Allocator) Error!runtime.Recovery,
    pub fn recover(self: StreamRecoverer, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, heading: []const u8, allocator: std.mem.Allocator) Error!runtime.Recovery {
        return self.recover_fn(self.context, value, stream, heading, allocator);
    }
};

pub const SegmentCreator = struct {
    context: *anyopaque,
    create_fn: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, u16, runtime.StreamSeed, []const u8, []const u8) Error!runtime.StreamState,
    pub fn create(self: SegmentCreator, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, ordinal: u16, seed: runtime.StreamSeed, heading: []const u8, header: []const u8) Error!runtime.StreamState {
        return self.create_fn(self.context, value, stream, ordinal, seed, heading, header);
    }
};

pub const SegmentRotator = struct {
    context: *anyopaque,
    rotate_fn: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, runtime.StreamState, []const u8, []const u8, []const u8) Error!runtime.StreamState,
    pub fn rotate(self: SegmentRotator, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8, heading: []const u8, header: []const u8) Error!runtime.StreamState {
        return self.rotate_fn(self.context, value, stream, state, trailer, heading, header);
    }
};

pub const StreamCloser = struct {
    context: *anyopaque,
    close_fn: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, runtime.StreamState, []const u8) Error!void,
    pub fn close(self: StreamCloser, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8) Error!void {
        return self.close_fn(self.context, value, stream, state, trailer);
    }
};

pub const RecordAppender = struct {
    context: *anyopaque,
    append_fn: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, runtime.StreamState, []const u8, bool) Error!runtime.PersistedEvidence,
    pub fn append(self: RecordAppender, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, row: []const u8, flush: bool) Error!runtime.PersistedEvidence {
        return self.append_fn(self.context, value, stream, state, row, flush);
    }
};

pub const SegmentPruner = struct {
    context: *anyopaque,
    prune_fn: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, u64) Error!void,
    pub fn prune(self: SegmentPruner, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, cutoff_unix_ms: u64) Error!void {
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
