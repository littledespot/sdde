const std = @import("std");
const log_limits = @import("../../domain/feature_log_limits.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const feature_log_file = @import("feature_log_file.zig");

const Io = std.Io;

pub fn create(
    io: Io,
    directory: Io.Dir,
    ordinal: u16,
    seed: log_stream.StreamSeed,
    heading: []const u8,
    header: []const u8,
) sink_port.Error!log_stream.StreamState {
    if (ordinal == 0 or ordinal != seed.next_segment_ordinal or seed.next_sequence == 0 or
        seed.total_segment_count >= log_limits.max_segments or
        heading.len + header.len > log_limits.max_segment_bytes) return error.SinkFailure;
    var name_buffer: [32]u8 = undefined;
    const file_name = feature_log_file.segmentName(ordinal, &name_buffer) catch return error.SinkFailure;
    var file = directory.createFile(io, file_name, .{
        .read = true,
        .exclusive = true,
        .permissions = feature_log_file.ownerOnlyPermissions(),
        .resolve_beneath = true,
    }) catch |err| return feature_log_file.sinkFault(err);
    defer file.close(io);
    file.writeStreamingAll(io, heading) catch |err| return feature_log_file.sinkFault(err);
    file.writeStreamingAll(io, header) catch |err| return feature_log_file.sinkFault(err);
    file.sync(io) catch |err| return feature_log_file.flushFault(err);
    return .{
        .segment_ordinal = ordinal,
        .next_sequence = seed.next_sequence,
        .segment_bytes = heading.len + header.len,
        .segment_count = @intCast(ordinal),
        .total_segment_count = seed.total_segment_count + 1,
        .records_since_flush = 0,
        .last_flush_monotonic_ms = 0,
    };
}

pub fn rotate(
    io: Io,
    directory: Io.Dir,
    state: log_stream.StreamState,
    trailer: []const u8,
    heading: []const u8,
    header: []const u8,
) sink_port.Error!log_stream.StreamState {
    if (state.total_segment_count == log_limits.max_segments) return error.SegmentLimitExhausted;
    var old_name_buffer: [32]u8 = undefined;
    const old_name = feature_log_file.segmentName(state.segment_ordinal, &old_name_buffer) catch return error.SinkFailure;
    const old = feature_log_file.openSegment(io, directory, old_name, .read_write) catch |err| return feature_log_file.segmentSinkFault(err);
    defer old.close(io);
    if (old.size != state.segment_bytes or old.size + trailer.len > log_limits.max_segment_bytes) return error.SinkFailure;
    old.file.writePositionalAll(io, trailer, old.size) catch |err| return feature_log_file.sinkFault(err);
    old.file.sync(io) catch |err| return feature_log_file.flushFault(err);
    return create(io, directory, state.segment_ordinal + 1, .{
        .next_segment_ordinal = state.segment_ordinal + 1,
        .next_sequence = state.next_sequence,
        .total_segment_count = state.total_segment_count,
    }, heading, header);
}

pub fn append(
    io: Io,
    directory: Io.Dir,
    state: log_stream.StreamState,
    row: []const u8,
    flush: bool,
) sink_port.Error!log_stream.PersistedEvidence {
    if (row.len == 0 or row[row.len - 1] != '\n' or state.segment_bytes + row.len > log_limits.max_segment_bytes) {
        return error.SinkFailure;
    }
    var name_buffer: [32]u8 = undefined;
    const file_name = feature_log_file.segmentName(state.segment_ordinal, &name_buffer) catch return error.SinkFailure;
    const segment = feature_log_file.openSegment(io, directory, file_name, .read_write) catch |err| return feature_log_file.segmentSinkFault(err);
    defer segment.close(io);
    if (segment.size != state.segment_bytes) return error.SinkFailure;
    segment.file.writePositionalAll(io, row, segment.size) catch |err| return feature_log_file.sinkFault(err);
    if (flush) segment.file.sync(io) catch |err| return feature_log_file.flushFault(err);
    return .{
        .segment_ordinal = state.segment_ordinal,
        .sequence = state.next_sequence,
        .bytes_written = row.len,
        .flushed = flush,
    };
}

pub fn close(
    io: Io,
    directory: Io.Dir,
    state: log_stream.StreamState,
    trailer: []const u8,
) sink_port.Error!void {
    var name_buffer: [32]u8 = undefined;
    const file_name = feature_log_file.segmentName(state.segment_ordinal, &name_buffer) catch return error.SinkFailure;
    const segment = feature_log_file.openSegment(io, directory, file_name, .read_write) catch |err| return feature_log_file.segmentSinkFault(err);
    defer segment.close(io);
    if (segment.size != state.segment_bytes or segment.size + trailer.len > log_limits.max_segment_bytes) return error.SinkFailure;
    segment.file.writePositionalAll(io, trailer, segment.size) catch |err| return feature_log_file.sinkFault(err);
    segment.file.sync(io) catch |err| return feature_log_file.flushFault(err);
}
