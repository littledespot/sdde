const std = @import("std");
const format = @import("../../domain/feature_log_format.zig");
const log_limits = @import("../../domain/feature_log_limits.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const feature_log_file = @import("feature_log_file.zig");

const Io = std.Io;

const Entry = struct { ordinal: u16, closed_at_unix_ms: u64 };

/// Delete the longest prefix, in ordinal order, of closed segments whose close
/// time is at or before the cutoff. Sequence order is the ordering authority and
/// timestamps are informational, so a later segment is never removed before an
/// earlier one and the remaining ordinals stay consecutive. Every segment must
/// be closed. Segment bytes are read into `allocator` one at a time.
pub fn prune(io: Io, allocator: std.mem.Allocator, directory: Io.Dir, cutoff_unix_ms: u64) sink_port.Error!void {
    var entries: [log_limits.max_segments]Entry = undefined;
    var count: usize = 0;
    var iterator = directory.iterate();
    while (iterator.next(io) catch return error.SinkFailure) |directory_entry| {
        const ordinal = switch (feature_log_file.classifyBindingEntry(directory_entry)) {
            .segment => |ordinal| ordinal,
            .ignored => continue,
            .invalid => return error.CorruptStream,
        };
        var file = directory.openFile(io, directory_entry.name, .{
            .mode = .read_only,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.SinkFailure;
        defer file.close(io);
        const stat = file.stat(io) catch return error.SinkFailure;
        if (stat.kind != .file or !feature_log_file.hasOwnerFilePermissions(stat.permissions) or stat.size > log_limits.max_segment_bytes) {
            return error.CorruptStream;
        }
        var reader = file.reader(io, &.{});
        const bytes = reader.interface.allocRemaining(allocator, .limited(@intCast(stat.size + 1))) catch return error.SinkFailure;
        defer allocator.free(bytes);
        if (bytes.len != stat.size) return error.CorruptStream;
        if (count == entries.len) return error.CorruptStream;
        entries[count] = .{ .ordinal = ordinal, .closed_at_unix_ms = format.trailerUnixMs(bytes) orelse return error.CorruptStream };
        count += 1;
    }
    std.mem.sort(Entry, entries[0..count], {}, lessOrdinal);
    for (entries[0..count]) |entry| {
        if (entry.closed_at_unix_ms > cutoff_unix_ms) break;
        var name_buffer: [32]u8 = undefined;
        const file_name = feature_log_file.segmentName(entry.ordinal, &name_buffer) catch return error.SinkFailure;
        directory.deleteFile(io, file_name) catch return error.SinkFailure;
    }
}

fn lessOrdinal(_: void, left: Entry, right: Entry) bool {
    return left.ordinal < right.ordinal;
}
