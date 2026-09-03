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
    }) catch return error.SinkFailure;
    defer file.close(io);
    file.writeStreamingAll(io, heading) catch return error.SinkFailure;
    file.writeStreamingAll(io, header) catch return error.SinkFailure;
    file.sync(io) catch return error.FlushFailure;
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
    var old = directory.openFile(io, old_name, .{
        .mode = .read_write,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch return error.SinkFailure;
    defer old.close(io);
    const stat = old.stat(io) catch return error.SinkFailure;
    if (stat.kind != .file or !feature_log_file.hasOwnerFilePermissions(stat.permissions) or
        stat.size != state.segment_bytes or stat.size + trailer.len > log_limits.max_segment_bytes)
    {
        return error.SinkFailure;
    }
    old.writePositionalAll(io, trailer, stat.size) catch return error.SinkFailure;
    old.sync(io) catch return error.FlushFailure;
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
    var file = directory.openFile(io, file_name, .{
        .mode = .read_write,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch return error.SinkFailure;
    defer file.close(io);
    const stat = file.stat(io) catch return error.SinkFailure;
    if (stat.kind != .file or !feature_log_file.hasOwnerFilePermissions(stat.permissions) or stat.size != state.segment_bytes) {
        return error.SinkFailure;
    }
    file.writePositionalAll(io, row, stat.size) catch return error.SinkFailure;
    if (flush) file.sync(io) catch return error.FlushFailure;
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
    var file = directory.openFile(io, file_name, .{
        .mode = .read_write,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch return error.SinkFailure;
    defer file.close(io);
    const stat = file.stat(io) catch return error.SinkFailure;
    if (stat.kind != .file or !feature_log_file.hasOwnerFilePermissions(stat.permissions) or
        stat.size != state.segment_bytes or stat.size + trailer.len > log_limits.max_segment_bytes)
    {
        return error.SinkFailure;
    }
    file.writePositionalAll(io, trailer, stat.size) catch return error.SinkFailure;
    file.sync(io) catch return error.FlushFailure;
}
