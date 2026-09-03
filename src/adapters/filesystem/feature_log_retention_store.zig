const std = @import("std");
const format = @import("../../domain/feature_log_format.zig");
const log_limits = @import("../../domain/feature_log_limits.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const feature_log_file = @import("feature_log_file.zig");

const Io = std.Io;

const Entry = struct { ordinal: u16, closed_at_unix_ms: u64 };

pub fn prune(io: Io, directory: Io.Dir, cutoff_unix_ms: u64) sink_port.Error!void {
    var selected: [log_limits.max_segments]Entry = undefined;
    var selected_count: usize = 0;
    var iterator = directory.iterate();
    while (iterator.next(io) catch return error.SinkFailure) |directory_entry| {
        const ordinal = feature_log_file.parseSegmentName(directory_entry.name) orelse continue;
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
        const bytes = reader.interface.allocRemaining(
            std.heap.page_allocator,
            .limited(@intCast(stat.size + 1)),
        ) catch return error.SinkFailure;
        defer std.heap.page_allocator.free(bytes);
        if (bytes.len != stat.size) return error.CorruptStream;
        const closed_at = format.trailerUnixMs(bytes) orelse return error.CorruptStream;
        if (closed_at <= cutoff_unix_ms) {
            if (selected_count == selected.len) return error.CorruptStream;
            selected[selected_count] = .{ .ordinal = ordinal, .closed_at_unix_ms = closed_at };
            selected_count += 1;
        }
    }
    std.mem.sort(Entry, selected[0..selected_count], {}, lessThan);
    for (selected[0..selected_count]) |entry| {
        var name_buffer: [32]u8 = undefined;
        const file_name = feature_log_file.segmentName(entry.ordinal, &name_buffer) catch return error.SinkFailure;
        directory.deleteFile(io, file_name) catch return error.SinkFailure;
    }
}

fn lessThan(_: void, left: Entry, right: Entry) bool {
    return left.closed_at_unix_ms < right.closed_at_unix_ms or
        (left.closed_at_unix_ms == right.closed_at_unix_ms and left.ordinal < right.ordinal);
}
