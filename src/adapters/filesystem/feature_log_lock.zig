const std = @import("std");
const log_limits = @import("../../domain/feature_log_limits.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const feature_log_file = @import("feature_log_file.zig");

const Io = std.Io;

pub fn acquire(io: Io, run_directory: Io.Dir, held: *?Io.File, deadline_ms: u16) sink_port.Error!void {
    if (held.* != null or deadline_ms != log_limits.stream_lock_deadline_ms) return error.InvalidBinding;
    var file = run_directory.openFile(io, feature_log_file.lock_name, .{
        .mode = .read_write,
        .allow_directory = false,
        .follow_symlinks = false,
        .resolve_beneath = true,
    }) catch |open_error| switch (open_error) {
        error.FileNotFound => run_directory.createFile(io, feature_log_file.lock_name, .{
            .read = true,
            .exclusive = true,
            .permissions = feature_log_file.ownerOnlyPermissions(),
            .resolve_beneath = true,
        }) catch return error.SinkFailure,
        else => return error.SinkFailure,
    };
    errdefer file.close(io);
    const stat = file.stat(io) catch return error.SinkFailure;
    if (stat.kind != .file or !feature_log_file.hasOwnerFilePermissions(stat.permissions)) return error.SinkFailure;
    if (!(file.tryLock(io, .exclusive) catch return error.SinkFailure)) return error.LockUnavailable;
    held.* = file;
}

pub fn release(io: Io, held: *?Io.File) sink_port.Error!void {
    const file = held.* orelse return error.ReleaseFailure;
    file.unlock(io);
    file.close(io);
    held.* = null;
}

pub fn deinit(io: Io, held: *?Io.File) void {
    if (held.*) |file| {
        file.unlock(io);
        file.close(io);
        held.* = null;
    }
}
