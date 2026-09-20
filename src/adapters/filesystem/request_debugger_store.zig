//! Reads observed feature logs and appends exclusive diagnostic replay records.
const std = @import("std");
const debug = @import("../../domain/request_debugger.zig");
const archive = @import("../../domain/request_debugger_archive.zig");
const replay_port = @import("../../ports/request_replay.zig");
const directories = @import("directory_access.zig");
pub const Store = struct {
    io: std.Io,
    feature: std.Io.Dir,

    pub fn port(self: *Store) replay_port.Store {
        return .{ .context = @ptrCast(self), .request_fn = writeRequest, .response_fn = writeResponse };
    }
    fn writeRequest(context: *replay_port.Context, a: std.mem.Allocator, value: debug.RequestRecord) replay_port.Error!void {
        const self: *Store = @ptrCast(@alignCast(context));
        if (value.sequence == 0 or @import("../../domain/telemetry.zig").Identifier.validate(value.run) == null) return error.InvalidReplay;
        const bytes = std.json.Stringify.valueAlloc(a, value, .{}) catch return error.OutOfMemory;
        defer a.free(bytes);
        try self.write(a, value.id, ".request.json", bytes);
    }
    fn writeResponse(context: *replay_port.Context, a: std.mem.Allocator, value: debug.ResponseRecord) replay_port.Error!void {
        const self: *Store = @ptrCast(@alignCast(context));
        const bytes = std.json.Stringify.valueAlloc(a, value, .{}) catch return error.OutOfMemory;
        defer a.free(bytes);
        try self.write(a, value.id, ".response.json", bytes);
    }
    fn write(self: *Store, a: std.mem.Allocator, id: []const u8, suffix: []const u8, bytes: []const u8) replay_port.Error!void {
        if (!validId(id)) return error.InvalidReplay;
        const dir = directories.ensureWithPermissions(self.io, self.feature, "logs/debugger", .fromMode(0o700)) catch return error.ReplayStorageFailure;
        defer dir.close(self.io);
        @import("feature_log_directory.zig").validateOwner(self.io, dir) catch return error.ReplayStorageFailure;
        const name = try std.mem.concat(a, u8, &.{ id, suffix });
        defer a.free(name);
        var file = dir.createFile(self.io, name, .{ .exclusive = true, .permissions = .fromMode(0o600) }) catch return error.ReplayStorageFailure;
        defer file.close(self.io);
        file.writeStreamingAll(self.io, bytes) catch return error.ReplayStorageFailure;
        file.sync(self.io) catch return error.ReplayStorageFailure;
    }

    pub fn load(self: *Store, a: std.mem.Allocator) ![]debug.Call {
        var accumulated: archive.Archive = .{ .allocator = a };
        try self.loadStream(a, "logs/prompts", &accumulated, false);
        try self.loadStream(a, "logs/events", &accumulated, true);
        var calls: std.ArrayList(debug.Call) = .empty;
        try calls.appendSlice(a, try accumulated.calls());
        const dir = directories.open(self.io, self.feature, "logs/debugger") catch |err| {
            if (err == error.DirectoryMissing) return calls.toOwnedSlice(a);
            return err;
        };
        defer dir.close(self.io);
        var iterator = dir.iterate();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".request.json")) continue;
            const id = entry.name[0 .. entry.name.len - ".request.json".len];
            if (!validId(id)) return error.InvalidDebugArchive;
            const request_bytes = try read(self.io, a, dir, entry.name, .unlimited);
            const request = try @import("../../domain/strict_json.zig").decode(debug.RequestRecord, a, request_bytes, .{ .maximum_depth = 64 });
            if (!std.mem.eql(u8, request.id, id)) return error.InvalidDebugArchive;
            if (request.sequence == 0 or @import("../../domain/telemetry.zig").Identifier.validate(request.run) == null) return error.InvalidDebugArchive;
            const description_bytes = try std.json.Stringify.valueAlloc(a, request.description, .{});
            _ = try debug.Description.decode(a, description_bytes);
            if (request.source_snapshot) |snapshot| {
                try snapshot.validate();
                if (!snapshot.matches(request.description.workflow_id, request.node, request.description.request_step)) return error.InvalidDebugArchive;
            }
            if (request.mode == .modified and !request.source_overrides) return error.InvalidDebugArchive;
            var call: debug.Call = .{
                .run = request.run,
                .sequence = request.sequence,
                .id = request.id,
                .workflow = request.description.workflow_id,
                .action = "replay-model-request",
                .node = request.node,
                .request_step = request.description.request_step,
                .slot = request.description.model_slot,
                .kind = "replay",
                .original = request.original_call,
                .original_run = request.original_run,
                .parent = request.parent_call,
                .parent_run = request.parent_run,
                .description = request.description,
                .source_snapshot = request.source_snapshot,
                .source_overrides = request.source_overrides,
                .request = request.body,
                .request_complete = true,
                .replay = request.mode,
            };
            const response_name = try std.mem.concat(a, u8, &.{ id, ".response.json" });
            const response_bytes = read(self.io, a, dir, response_name, .unlimited) catch |err| switch (err) {
                error.FileNotFound => null,
                else => return err,
            };
            if (response_bytes) |bytes| {
                const response = try @import("../../domain/strict_json.zig").decode(debug.ResponseRecord, a, bytes, .{ .maximum_depth = 64 });
                if (!std.mem.eql(u8, response.id, id)) return error.InvalidDebugArchive;
                call.response = response.body;
                call.response_provenance = if (response.outcome == .received and response.status == 200) "provider_body" else @tagName(response.outcome);
                call.response_encoding = @tagName(response.encoding);
                call.response_status = response.status;
                call.response_diagnostic = response.diagnostic;
            }
            try calls.append(a, call);
        }
        try debug.orderCalls(calls.items);
        return calls.toOwnedSlice(a);
    }

    fn loadStream(self: *Store, a: std.mem.Allocator, path: []const u8, accumulated: *archive.Archive, events: bool) !void {
        const base = directories.open(self.io, self.feature, path) catch |err| {
            if (err == error.DirectoryMissing) return;
            return err;
        };
        defer base.close(self.io);
        var paths: std.ArrayList([]const u8) = .empty;
        try enumerate(self.io, a, base, "", 0, &paths);
        var segments: std.ArrayList(Segment) = .empty;
        for (paths.items) |relative| {
            const parent = try directories.open(self.io, base, std.fs.path.dirname(relative) orelse return error.InvalidDebugArchive);
            defer parent.close(self.io);
            const bytes = try read(self.io, a, parent, std.fs.path.basename(relative), .limited(@import("../../domain/feature_log_limits.zig").max_segment_bytes));
            try segments.append(a, .{ .bytes = bytes, .order = try archive.segmentOrder(a, bytes, events) });
        }
        std.mem.sort(Segment, segments.items, {}, Segment.lessThan);
        var previous: ?archive.SegmentOrder = null;
        for (segments.items) |segment| {
            if (segment.order) |order| {
                if (previous) |last| {
                    if (std.mem.eql(u8, last.run, order.run) and order.first <= last.last) return error.InvalidDebugArchive;
                }
                previous = order;
            }
            if (events) try accumulated.ingestEvents(segment.bytes) else try accumulated.ingest(segment.bytes);
        }
    }
};

fn enumerate(io: std.Io, a: std.mem.Allocator, dir: std.Io.Dir, prefix: []const u8, depth: usize, paths: *std.ArrayList([]const u8)) !void {
    if (depth > 2) return error.InvalidDebugArchive;
    var iterator = dir.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind == .directory) {
            const child = try directories.open(io, dir, entry.name);
            defer child.close(io);
            const next = if (prefix.len == 0) try a.dupe(u8, entry.name) else try std.fmt.allocPrint(a, "{s}/{s}", .{ prefix, entry.name });
            try enumerate(io, a, child, next, depth + 1, paths);
        } else if (entry.kind == .file and @import("feature_log_file.zig").parseSegmentName(entry.name) != null) {
            try paths.append(a, try std.fmt.allocPrint(a, "{s}/{s}", .{ prefix, entry.name }));
        } else if (entry.kind == .sym_link) return error.InvalidDebugArchive;
    }
}
fn read(io: std.Io, a: std.mem.Allocator, dir: std.Io.Dir, name: []const u8, limit: std.Io.Limit) ![]const u8 {
    var file = try dir.openFile(io, name, .{ .mode = .read_only, .follow_symlinks = false, .allow_directory = false, .resolve_beneath = true });
    defer file.close(io);
    if ((try file.stat(io)).kind != .file) return error.InvalidDebugArchive;
    var buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &buffer);
    return reader.interface.allocRemaining(a, limit);
}
const Segment = struct {
    bytes: []const u8,
    order: ?archive.SegmentOrder,

    fn lessThan(_: void, a: Segment, b: Segment) bool {
        const first = a.order orelse return false;
        const second = b.order orelse return true;
        const run_order = std.mem.order(u8, first.run, second.run);
        return if (run_order == .eq) first.first < second.first else run_order == .lt;
    }
};
pub fn validId(id: []const u8) bool {
    if (id.len != 32) return false;
    for (id) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}
