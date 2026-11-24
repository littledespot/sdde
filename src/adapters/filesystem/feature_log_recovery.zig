const std = @import("std");
const format = @import("../../domain/feature_log_format.zig");
const log_limits = @import("../../domain/feature_log_limits.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const feature_log_file = @import("feature_log_file.zig");

const Io = std.Io;

pub const Source = struct {
    io: Io,
    directory: Io.Dir,
};

pub fn recover(
    source: Source,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    stream: log_stream.Stream,
    heading: []const u8,
    allocator: std.mem.Allocator,
) sink_port.Error!log_stream.Recovery {
    var ordinals: std.ArrayList(u16) = .empty;
    defer ordinals.deinit(allocator);
    var iterator = source.directory.iterate();
    while (iterator.next(source.io) catch |err| return feature_log_file.sinkFault(err)) |entry| switch (feature_log_file.classifyBindingEntry(entry)) {
        .segment => |ordinal| ordinals.append(allocator, ordinal) catch return error.SinkFailure,
        .ignored => {},
        .invalid => return error.CorruptStream,
    };
    if (ordinals.items.len > log_limits.max_segments) return error.CorruptStream;
    const total_segments: u8 = @intCast(ordinals.items.len);
    if (ordinals.items.len == 0) return .{ .empty = .{
        .next_segment_ordinal = 1,
        .next_sequence = 1,
        .total_segment_count = total_segments,
    } };
    std.mem.sort(u16, ordinals.items, {}, std.sort.asc(u16));
    for (ordinals.items, 0..) |ordinal, index| {
        if (ordinal != index + 1) return error.CorruptStream;
    }
    var active: ?log_stream.StreamState = null;
    var prior_sequence: u64 = 0;
    for (ordinals.items, 0..) |ordinal, index| {
        const inspection = inspectSegment(
            source.io,
            source.directory,
            allocator,
            binding,
            stream,
            ordinal,
            heading,
            if (index + 1 == ordinals.items.len) .truncate else .reject,
            std.math.add(u64, prior_sequence, 1) catch return error.CorruptStream,
        ) catch |err| return switch (err) {
            error.Cancelled => error.Cancelled,
            error.InvalidSegment, error.SegmentUnavailable, error.OutOfMemory => error.CorruptStream,
        };
        prior_sequence = inspection.last_sequence;
        if (!inspection.closed) {
            if (index + 1 != ordinals.items.len or active != null) return error.CorruptStream;
            active = .{
                .segment_ordinal = ordinal,
                .next_sequence = std.math.add(u64, inspection.last_sequence, 1) catch return error.CorruptStream,
                .segment_bytes = inspection.bytes,
                .segment_count = @intCast(ordinals.items.len),
                .total_segment_count = total_segments,
                .records_since_flush = 0,
                .last_flush_monotonic_ms = 0,
            };
        }
    }
    return if (active) |state| .{ .active = state } else .{ .empty = .{
        .next_segment_ordinal = ordinals.items[ordinals.items.len - 1] + 1,
        .next_sequence = std.math.add(u64, prior_sequence, 1) catch return error.CorruptStream,
        .total_segment_count = total_segments,
    } };
}

pub const Inspection = struct {
    closed: bool,
    last_sequence: u64,
    bytes: u64,
    /// Bytes after the last complete row were ignored, not truncated.
    partial_tail: bool = false,
};

/// How a segment's bytes after its last complete row are handled: recovery
/// truncates an active tail, read-only inspection ignores them, and any other
/// segment must end on a complete row.
pub const Tail = enum { truncate, ignore, reject };

pub const InspectError = error{ InvalidSegment, SegmentUnavailable, Cancelled, OutOfMemory };

/// The segment validator shared by recovery and read-only retention
/// inspection. A null `first_sequence` adopts the first record's sequence. The
/// segment's bytes stay allocated, so pass an arena.
pub fn inspectReadOnly(
    io: Io,
    directory: Io.Dir,
    allocator: std.mem.Allocator,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    stream: log_stream.Stream,
    ordinal: u16,
    tail: enum { ignore, reject },
    first_sequence: ?u64,
) InspectError!Inspection {
    const heading = format.segmentHeading(stream);
    return inspectSegment(io, directory, allocator, binding, stream, ordinal, heading, if (tail == .ignore) .ignore else .reject, first_sequence);
}

pub const GroupState = enum { empty, closed, active };

/// Read-only validation of one binding directory: every segment is valid for
/// the binding with continuous sequences, and only the last may be an active
/// tail. Ordinals are consecutive but may start after 1 once retention removed
/// the oldest segments. Nothing is written.
pub fn inspectGroup(
    io: Io,
    directory: Io.Dir,
    allocator: std.mem.Allocator,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    stream: log_stream.Stream,
) InspectError!GroupState {
    var ordinals: [log_limits.max_segments]u16 = undefined;
    const count = try segmentOrdinals(io, directory, &ordinals);
    if (count == 0) return .empty;
    var next: ?u64 = null;
    for (ordinals[0..count], 0..) |ordinal, index| {
        const last = index + 1 == count;
        // Each segment's bytes are released before the next is read.
        var segment: std.heap.ArenaAllocator = .init(allocator);
        defer segment.deinit();
        const inspection = try inspectReadOnly(io, directory, segment.allocator(), binding, stream, ordinal, if (last) .ignore else .reject, next);
        // Nothing is written after a trailer, so bytes there are corruption.
        if (inspection.closed and inspection.partial_tail) return error.InvalidSegment;
        if (!inspection.closed) return if (last) .active else error.InvalidSegment;
        next = std.math.add(u64, inspection.last_sequence, 1) catch return error.InvalidSegment;
    }
    return .closed;
}

/// The policy ID named by a segment's header row, or null when the segment is
/// torn: empty, or ended before its header row was complete. Only a binding's
/// last segment may be torn, as a crash during creation leaves it.
pub fn segmentPolicy(io: Io, directory: Io.Dir, allocator: std.mem.Allocator, ordinal: u16, stream: log_stream.Stream) InspectError!?[]const u8 {
    var name_buffer: [32]u8 = undefined;
    const file_name = feature_log_file.segmentName(ordinal, &name_buffer) catch return error.InvalidSegment;
    const segment = feature_log_file.openSegment(io, directory, file_name, .read_only) catch |err| return openError(err);
    defer segment.close(io);
    // The segment's bytes stay in a local arena; only the policy is returned.
    var local: std.heap.ArenaAllocator = .init(allocator);
    defer local.deinit();
    const bytes = feature_log_file.readSegment(io, local.allocator(), segment) catch |err| return readError(err);
    const heading = format.segmentHeading(stream);
    const header = (try headerRow(bytes, heading, stream)) orelse return null;
    return try allocator.dupe(u8, format.logPolicyCell(header) orelse return error.InvalidSegment);
}

/// The complete header row after the heading, or null when the bytes stop
/// before it is complete. Torn bytes must still be a prefix of the heading and
/// of this stream's `segment_header` row within the row size limit; anything
/// else is invalid.
fn headerRow(bytes: []const u8, heading: []const u8, stream: log_stream.Stream) InspectError!?[]const u8 {
    if (bytes.len < heading.len) return if (std.mem.startsWith(u8, heading, bytes)) null else error.InvalidSegment;
    if (!std.mem.startsWith(u8, bytes, heading)) return error.InvalidSegment;
    const rest = bytes[heading.len..];
    if (std.mem.indexOfScalar(u8, rest, '\n')) |end| return rest[0..end];
    if (rest.len >= log_limits.max_record_bytes) return error.InvalidSegment;
    // The row kind, schema version, stream and column schema precede the
    // binding's identity cells.
    const prefix = switch (stream) {
        inline else => |selected| "segment_header|" ++ log_limits.schema_version ++ "|" ++ @tagName(selected) ++ "|" ++
            (if (selected == .event) log_limits.event_column_schema_id else log_limits.prompt_column_schema_id) ++ "|",
    };
    return if (std.mem.startsWith(u8, prefix, rest) or std.mem.startsWith(u8, rest, prefix)) null else error.InvalidSegment;
}

/// A binding directory holds consecutive segment files, at most the stream's
/// segment limit, returned in ascending order. Other regular files are left
/// alone; any other entry is invalid.
pub fn segmentOrdinals(io: Io, directory: Io.Dir, ordinals: *[log_limits.max_segments]u16) InspectError!usize {
    var count: usize = 0;
    var iterator = directory.iterate();
    while (iterator.next(io) catch |err| return fileError(err)) |entry| {
        const ordinal = switch (feature_log_file.classifyBindingEntry(entry)) {
            .segment => |ordinal| ordinal,
            .ignored => continue,
            .invalid => return error.InvalidSegment,
        };
        if (count == ordinals.len) return error.InvalidSegment;
        ordinals[count] = ordinal;
        count += 1;
    }
    std.mem.sort(u16, ordinals[0..count], {}, std.sort.asc(u16));
    for (ordinals[0..count], 0..) |ordinal, index| if (ordinal != ordinals[0] + index) return error.InvalidSegment;
    return count;
}

/// A segment the open rejected is invalid; any other failed open call is a file error.
fn openError(err: anyerror) InspectError {
    return if (err == error.SegmentRejected) error.InvalidSegment else fileError(err);
}

fn readError(err: feature_log_file.ReadError) InspectError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.Canceled => error.Cancelled,
        error.ReadFailed => error.SegmentUnavailable,
        error.SizeDrift => error.InvalidSegment,
    };
}

fn fileError(err: anyerror) InspectError {
    return switch (err) {
        error.Canceled => error.Cancelled,
        error.OutOfMemory => error.OutOfMemory,
        error.AccessDenied, error.PermissionDenied, error.SymLinkLoop, error.IsDir, error.NotDir, error.FileNotFound => error.InvalidSegment,
        else => error.SegmentUnavailable,
    };
}

fn inspectSegment(
    io: Io,
    directory: Io.Dir,
    allocator: std.mem.Allocator,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    stream: log_stream.Stream,
    ordinal: u16,
    heading: []const u8,
    tail: Tail,
    first_sequence: ?u64,
) InspectError!Inspection {
    var name_buffer: [32]u8 = undefined;
    const file_name = feature_log_file.segmentName(ordinal, &name_buffer) catch return error.InvalidSegment;
    const segment = feature_log_file.openSegment(io, directory, file_name, if (tail == .truncate) .read_write else .read_only) catch |err| return openError(err);
    defer segment.close(io);
    var size = segment.size;
    var bytes = feature_log_file.readSegment(io, allocator, segment) catch |err| return readError(err);
    // A crash while a segment was created can leave it torn before its header
    // row is complete. Read-only inspection reports that as an active tail;
    // recovery refuses it before any write, because truncating a segment with
    // no identified header would extend what recovery may do to a log file.
    if (try headerRow(bytes, heading, stream) == null) switch (tail) {
        .ignore => return .{ .closed = false, .last_sequence = if (first_sequence) |first| first -| 1 else 0, .bytes = size, .partial_tail = true },
        .truncate => return error.InvalidSegment,
        .reject => {},
    };
    if (bytes.len == 0) return error.InvalidSegment;
    var partial_tail = false;
    if (bytes[bytes.len - 1] != '\n') {
        const end = std.mem.lastIndexOfScalar(u8, bytes, '\n') orelse return error.InvalidSegment;
        switch (tail) {
            .reject => return error.InvalidSegment,
            .ignore => partial_tail = true,
            .truncate => {
                segment.file.setLength(io, end + 1) catch |err| return fileError(err);
                segment.file.sync(io) catch |err| return fileError(err);
                size = end + 1;
            },
        }
        bytes = bytes[0 .. end + 1];
    }
    if (!std.mem.startsWith(u8, bytes, heading)) return error.InvalidSegment;
    const columns = if (stream == .event) format.event_column_count else format.prompt_column_count;
    var lines = std.mem.splitScalar(u8, bytes[heading.len..], '\n');
    const header = lines.next() orelse return error.InvalidSegment;
    if (header.len == 0 or !std.mem.eql(u8, format.cellAt(header, format.sharedColumn("record_kind")) orelse return error.InvalidSegment, "segment_header")) {
        return error.InvalidSegment;
    }
    try validRow(allocator, header, columns);
    format.validatePersistedIdentityRow(header, binding, ordinal, stream) catch return error.InvalidSegment;
    format.validatePersistedControlRow(header, .segment_header, stream, null) catch return error.InvalidSegment;
    var last_sequence: ?u64 = if (first_sequence) |first| std.math.sub(u64, first, 1) catch return error.InvalidSegment else null;
    var closed = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        try validRow(allocator, line, columns);
        const kind = format.cellAt(line, format.sharedColumn("record_kind")) orelse return error.InvalidSegment;
        if (std.mem.eql(u8, kind, @tagName(stream))) {
            if (closed) return error.InvalidSegment;
            format.validatePersistedIdentityRow(line, binding, ordinal, stream) catch return error.InvalidSegment;
            const sequence = std.fmt.parseInt(u64, format.cellAt(line, format.sharedColumn("sequence")) orelse return error.InvalidSegment, 10) catch return error.InvalidSegment;
            if (last_sequence) |prior| if (sequence != (std.math.add(u64, prior, 1) catch return error.InvalidSegment)) return error.InvalidSegment;
            last_sequence = sequence;
        } else if (std.mem.eql(u8, kind, "segment_trailer")) {
            if (closed) return error.InvalidSegment;
            format.validatePersistedIdentityRow(line, binding, ordinal, stream) catch return error.InvalidSegment;
            // A segment with no record states its own final sequence.
            const final = last_sequence orelse std.fmt.parseInt(u64, format.cellAt(line, format.sharedColumn("sequence")) orelse return error.InvalidSegment, 10) catch return error.InvalidSegment;
            format.validatePersistedControlRow(line, .segment_trailer, stream, final) catch return error.InvalidSegment;
            last_sequence = final;
            closed = true;
        } else return error.InvalidSegment;
    }
    return .{ .closed = closed, .last_sequence = last_sequence orelse 0, .bytes = size, .partial_tail = partial_tail };
}

fn validRow(allocator: std.mem.Allocator, line: []const u8, columns: usize) InspectError!void {
    const with_lf = try std.fmt.allocPrint(allocator, "{s}\n", .{line});
    defer allocator.free(with_lf);
    format.validateEncodedRow(allocator, with_lf, columns) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidSegment,
    };
}
