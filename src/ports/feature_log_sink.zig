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

pub const Sink = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        acquire: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, u16) Error!void,
        recover: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, []const u8, std.mem.Allocator) Error!runtime.Recovery,
        create: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, u16, runtime.StreamSeed, []const u8, []const u8) Error!runtime.StreamState,
        rotate: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, runtime.StreamState, []const u8, []const u8, []const u8) Error!runtime.StreamState,
        close: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, runtime.StreamState, []const u8) Error!void,
        append: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, runtime.StreamState, []const u8, bool) Error!runtime.PersistedEvidence,
        prune: *const fn (*anyopaque, *const runtime.ValidatedFeatureLogBinding, runtime.Stream, u64) Error!void,
        release: *const fn (*anyopaque) Error!void,
    };

    pub fn acquire(self: Sink, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, deadline_ms: u16) Error!void {
        return self.vtable.acquire(self.context, value, stream, deadline_ms);
    }
    pub fn recover(self: Sink, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, heading: []const u8, allocator: std.mem.Allocator) Error!runtime.Recovery {
        return self.vtable.recover(self.context, value, stream, heading, allocator);
    }
    pub fn create(self: Sink, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, ordinal: u16, seed: runtime.StreamSeed, heading: []const u8, header: []const u8) Error!runtime.StreamState {
        return self.vtable.create(self.context, value, stream, ordinal, seed, heading, header);
    }
    pub fn rotate(self: Sink, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8, heading: []const u8, header: []const u8) Error!runtime.StreamState {
        return self.vtable.rotate(self.context, value, stream, state, trailer, heading, header);
    }
    pub fn close(self: Sink, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8) Error!void {
        return self.vtable.close(self.context, value, stream, state, trailer);
    }
    pub fn append(self: Sink, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, row: []const u8, flush: bool) Error!runtime.PersistedEvidence {
        return self.vtable.append(self.context, value, stream, state, row, flush);
    }
    pub fn prune(self: Sink, value: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, cutoff_unix_ms: u64) Error!void {
        return self.vtable.prune(self.context, value, stream, cutoff_unix_ms);
    }
    pub fn release(self: Sink) Error!void {
        return self.vtable.release(self.context);
    }
};
