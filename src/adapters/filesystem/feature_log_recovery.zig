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
    run_directory: Io.Dir,
    expected_binding: log_binding.BindingCandidate,
    scans_run_history: bool,
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
    while (iterator.next(source.io) catch return error.SinkFailure) |entry| {
        if (entry.kind != .file) return error.CorruptStream;
        if (feature_log_file.parseSegmentName(entry.name)) |ordinal| {
            ordinals.append(allocator, ordinal) catch return error.SinkFailure;
            continue;
        }
        if (std.mem.eql(u8, entry.name, feature_log_file.lock_name)) continue;
        return error.CorruptStream;
    }
    const total_segments = countRunSegments(source) catch return error.CorruptStream;
    const history_next_sequence = historicalNextSequence(source, stream, heading, allocator) catch return error.CorruptStream;
    if (total_segments > log_limits.max_segments) return error.CorruptStream;
    if (ordinals.items.len == 0) return .{ .empty = .{
        .next_segment_ordinal = 1,
        .next_sequence = history_next_sequence,
        .total_segment_count = total_segments,
    } };
    std.mem.sort(u16, ordinals.items, {}, std.sort.asc(u16));
    for (ordinals.items, 0..) |ordinal, index| {
        if (ordinal != index + 1) return error.CorruptStream;
    }
    var active: ?log_stream.StreamState = null;
    var prior_sequence: u64 = history_next_sequence - 1;
    for (ordinals.items, 0..) |ordinal, index| {
        const inspection = inspectSegment(
            source,
            allocator,
            binding,
            stream,
            ordinal,
            heading,
            index + 1 == ordinals.items.len,
            prior_sequence + 1,
        ) catch return error.CorruptStream;
        prior_sequence = inspection.last_sequence;
        if (!inspection.closed) {
            if (index + 1 != ordinals.items.len or active != null) return error.CorruptStream;
            active = .{
                .segment_ordinal = ordinal,
                .next_sequence = inspection.last_sequence + 1,
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
        .next_sequence = prior_sequence + 1,
        .total_segment_count = total_segments,
    } };
}

const Inspection = struct { closed: bool, last_sequence: u64, bytes: u64 };

fn inspectSegment(
    source: Source,
    allocator: std.mem.Allocator,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    stream: log_stream.Stream,
    ordinal: u16,
    heading: []const u8,
    allow_truncate: bool,
    first_sequence: u64,
) !Inspection {
    var name_buffer: [32]u8 = undefined;
    const file_name = try feature_log_file.segmentName(ordinal, &name_buffer);
    var file = try source.directory.openFile(source.io, file_name, .{
        .mode = if (allow_truncate) .read_write else .read_only,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    });
    defer file.close(source.io);
    var stat = try file.stat(source.io);
    if (stat.kind != .file or !feature_log_file.hasOwnerFilePermissions(stat.permissions) or stat.size > log_limits.max_segment_bytes) {
        return error.InvalidSegment;
    }
    var reader = file.reader(source.io, &.{});
    var bytes = try reader.interface.allocRemaining(allocator, .limited64(stat.size + 1));
    if (bytes.len != stat.size or bytes.len == 0) return error.InvalidSegment;
    if (bytes[bytes.len - 1] != '\n') {
        if (!allow_truncate) return error.InvalidSegment;
        const end = std.mem.lastIndexOfScalar(u8, bytes, '\n') orelse return error.InvalidSegment;
        try file.setLength(source.io, end + 1);
        try file.sync(source.io);
        bytes = bytes[0 .. end + 1];
        stat.size = end + 1;
    }
    if (!std.mem.startsWith(u8, bytes, heading)) return error.InvalidSegment;
    var lines = std.mem.splitScalar(u8, bytes[heading.len..], '\n');
    const header = lines.next() orelse return error.InvalidSegment;
    if (header.len == 0 or !std.mem.eql(u8, format.cellAt(header, 0) orelse return error.InvalidSegment, "segment_header")) {
        return error.InvalidSegment;
    }
    const header_with_lf = try std.fmt.allocPrint(allocator, "{s}\n", .{header});
    try format.validateEncodedRow(allocator, header_with_lf, if (stream == .event) 38 else 30);
    try format.validatePersistedIdentityRow(header, binding, ordinal, stream);
    try format.validatePersistedControlRow(header, .segment_header, stream, null);
    var last_sequence: u64 = first_sequence - 1;
    var closed = false;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        const with_lf = try std.fmt.allocPrint(allocator, "{s}\n", .{line});
        try format.validateEncodedRow(allocator, with_lf, if (stream == .event) 38 else 30);
        const kind = format.cellAt(line, 0) orelse return error.InvalidSegment;
        if (std.mem.eql(u8, kind, @tagName(stream))) {
            if (closed) return error.InvalidSegment;
            try format.validatePersistedIdentityRow(line, binding, ordinal, stream);
            const sequence = try std.fmt.parseInt(u64, format.cellAt(line, 9) orelse return error.InvalidSegment, 10);
            if (sequence != last_sequence + 1) return error.InvalidSegment;
            last_sequence = sequence;
        } else if (std.mem.eql(u8, kind, "segment_trailer")) {
            if (closed) return error.InvalidSegment;
            try format.validatePersistedIdentityRow(line, binding, ordinal, stream);
            try format.validatePersistedControlRow(line, .segment_trailer, stream, last_sequence);
            closed = true;
        } else return error.InvalidSegment;
    }
    return .{ .closed = closed, .last_sequence = last_sequence, .bytes = stat.size };
}

fn countRunSegments(source: Source) !u8 {
    var count: usize = 0;
    var iterator = source.run_directory.iterate();
    while (try iterator.next(source.io)) |entry| switch (entry.kind) {
        .file => {
            if (feature_log_file.parseSegmentName(entry.name) != null) {
                count += 1;
            } else if (!std.mem.eql(u8, entry.name, feature_log_file.lock_name)) return error.CorruptStream;
        },
        .directory => {
            var binding_directory = try source.run_directory.openDir(source.io, entry.name, .{
                .iterate = true,
                .follow_symlinks = false,
            });
            defer binding_directory.close(source.io);
            var segments = binding_directory.iterate();
            while (try segments.next(source.io)) |entry_segment| {
                if (entry_segment.kind != .file or feature_log_file.parseSegmentName(entry_segment.name) == null) return error.CorruptStream;
                count += 1;
            }
        },
        else => return error.CorruptStream,
    };
    if (count > log_limits.max_segments) return error.CorruptStream;
    return @intCast(count);
}

fn historicalNextSequence(
    source: Source,
    stream: log_stream.Stream,
    heading: []const u8,
    allocator: std.mem.Allocator,
) !u64 {
    if (!source.scans_run_history) return 1;
    var maximum: u64 = 0;
    var iterator = source.run_directory.iterate();
    while (try iterator.next(source.io)) |entry| {
        if (entry.kind == .file and std.mem.eql(u8, entry.name, feature_log_file.lock_name)) continue;
        if (entry.kind != .directory) return error.CorruptStream;
        if (std.mem.eql(u8, entry.name, source.expected_binding.binding_id.bytes)) continue;
        var historical = try source.run_directory.openDir(source.io, entry.name, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        defer historical.close(source.io);
        var segments = historical.iterate();
        while (try segments.next(source.io)) |historical_entry| {
            const ordinal = feature_log_file.parseSegmentName(historical_entry.name) orelse return error.CorruptStream;
            if (historical_entry.kind != .file) return error.CorruptStream;
            var file = try historical.openFile(source.io, historical_entry.name, .{
                .mode = .read_only,
                .allow_directory = false,
                .follow_symlinks = false,
                .resolve_beneath = true,
            });
            defer file.close(source.io);
            const stat = try file.stat(source.io);
            if (stat.kind != .file or !feature_log_file.hasOwnerFilePermissions(stat.permissions) or stat.size > log_limits.max_segment_bytes) {
                return error.CorruptStream;
            }
            var reader = file.reader(source.io, &.{});
            const bytes = try reader.interface.allocRemaining(allocator, .limited64(stat.size + 1));
            if (bytes.len != stat.size or !std.mem.startsWith(u8, bytes, heading) or bytes.len == 0 or bytes[bytes.len - 1] != '\n') {
                return error.CorruptStream;
            }
            const without_lf = bytes[0 .. bytes.len - 1];
            const trailer_start = (std.mem.lastIndexOfScalar(u8, without_lf, '\n') orelse return error.CorruptStream) + 1;
            const trailer = without_lf[trailer_start..];
            if (!std.mem.eql(u8, format.cellAt(trailer, 0) orelse return error.CorruptStream, "segment_trailer") or
                !std.mem.eql(u8, format.cellAt(trailer, 2) orelse return error.CorruptStream, @tagName(stream)) or
                !std.mem.eql(u8, format.cellAt(trailer, 5) orelse return error.CorruptStream, entry.name) or
                try std.fmt.parseInt(u16, format.cellAt(trailer, 6) orelse return error.CorruptStream, 10) != ordinal or
                !std.mem.eql(u8, format.cellAt(trailer, 15) orelse return error.CorruptStream, source.expected_binding.run_id.bytes) or
                !std.mem.eql(u8, format.cellAt(trailer, 16) orelse return error.CorruptStream, source.expected_binding.feature_id.bytes))
            {
                return error.CorruptStream;
            }
            const sequence = try std.fmt.parseInt(u64, format.cellAt(trailer, 9) orelse return error.CorruptStream, 10);
            maximum = @max(maximum, sequence);
        }
    }
    return maximum + 1;
}
