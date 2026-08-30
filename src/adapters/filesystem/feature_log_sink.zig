const std = @import("std");
const builtin = @import("builtin");
const format = @import("../../domain/feature_log_format.zig");
const logging = @import("../../domain/logging.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const sink_port = @import("../../ports/feature_log_sink.zig");
const file_identity = @import("file_identity.zig");

const Io = std.Io;

pub const Adapter = struct {
    io: Io,
    event_run_directory: Io.Dir,
    event_directory: Io.Dir,
    prompt_run_directory: Io.Dir,
    prompt_directory: Io.Dir,
    expected_binding: runtime.BindingCandidate,
    lock_file: ?Io.File = null,
    owns_directories: bool,
    scans_run_history: bool,

    pub const InitError = error{ InvalidArtifactRegistry, ArtifactStorageUnavailable, InsecurePermissions };

    pub fn init(
        io: Io,
        project_root: Io.Dir,
        registry: *const artifacts.WorkflowArtifactRegistry,
        binding: *const runtime.ValidatedFeatureLogBinding,
    ) InitError!Adapter {
        const authority = artifacts.bindFeatureLogSinkAdapter(registry, binding) orelse return error.InvalidArtifactRegistry;
        var specs_root = project_root.openDir(io, authority.specs_root_path, .{
            .access_sub_paths = true,
            .follow_symlinks = false,
        }) catch return error.ArtifactStorageUnavailable;
        defer specs_root.close(io);
        if (!(file_identity.inspect(specs_root.handle) catch return error.ArtifactStorageUnavailable).eql(authority.specs_root_identity)) {
            return error.InvalidArtifactRegistry;
        }
        var event_run = openOwnerDirectory(io, specs_root, authority.event_run_path) catch return error.ArtifactStorageUnavailable;
        errdefer event_run.close(io);
        var event_binding = openOwnerDirectory(io, specs_root, authority.event_binding_path) catch return error.ArtifactStorageUnavailable;
        errdefer event_binding.close(io);
        var prompt_run = openOwnerDirectory(io, specs_root, authority.prompt_run_path) catch return error.ArtifactStorageUnavailable;
        errdefer prompt_run.close(io);
        var prompt_binding = openOwnerDirectory(io, specs_root, authority.prompt_binding_path) catch return error.ArtifactStorageUnavailable;
        errdefer prompt_binding.close(io);
        try requireOwnerDirectory(io, event_run);
        try requireOwnerDirectory(io, event_binding);
        try requireOwnerDirectory(io, prompt_run);
        try requireOwnerDirectory(io, prompt_binding);
        return .{
            .io = io,
            .event_run_directory = event_run,
            .event_directory = event_binding,
            .prompt_run_directory = prompt_run,
            .prompt_directory = prompt_binding,
            .expected_binding = authority.expected_binding,
            .owns_directories = true,
            .scans_run_history = true,
        };
    }

    pub fn initForTest(io: Io, test_directory: Io.Dir, expected_binding: runtime.BindingCandidate) Adapter {
        if (!builtin.is_test) @compileError("test-only feature log sink constructor");
        return .{
            .io = io,
            .event_run_directory = test_directory,
            .event_directory = test_directory,
            .prompt_run_directory = test_directory,
            .prompt_directory = test_directory,
            .expected_binding = expected_binding,
            .owns_directories = false,
            .scans_run_history = false,
        };
    }

    pub fn initForTestLayout(io: Io, run_directory: Io.Dir, binding_directory: Io.Dir, expected_binding: runtime.BindingCandidate) Adapter {
        if (!builtin.is_test) @compileError("test-only feature log sink constructor");
        return .{
            .io = io,
            .event_run_directory = run_directory,
            .event_directory = binding_directory,
            .prompt_run_directory = run_directory,
            .prompt_directory = binding_directory,
            .expected_binding = expected_binding,
            .owns_directories = false,
            .scans_run_history = true,
        };
    }

    pub fn deinit(self: *Adapter) void {
        if (self.lock_file) |file| {
            file.unlock(self.io);
            file.close(self.io);
        }
        if (self.owns_directories) {
            self.prompt_directory.close(self.io);
            self.prompt_run_directory.close(self.io);
            self.event_directory.close(self.io);
            self.event_run_directory.close(self.io);
        }
        self.* = undefined;
    }

    pub fn sink(self: *Adapter) sink_port.Sink {
        return .{ .context = self, .vtable = &vtable };
    }

    fn acquire(context: *anyopaque, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, deadline_ms: u16) sink_port.Error!void {
        const self = cast(context);
        if (self.lock_file != null or deadline_ms != logging.stream_lock_deadline_ms or
            !runtime.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
        var file = self.runDirectory(stream).openFile(self.io, lockName(), .{
            .mode = .read_write,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch |open_error| switch (open_error) {
            error.FileNotFound => self.runDirectory(stream).createFile(self.io, lockName(), .{
                .read = true,
                .exclusive = true,
                .permissions = ownerOnlyPermissions(),
                .resolve_beneath = true,
            }) catch return error.SinkFailure,
            else => return error.SinkFailure,
        };
        errdefer file.close(self.io);
        const lock_stat = file.stat(self.io) catch return error.SinkFailure;
        if (lock_stat.kind != .file or !ownerFilePermissions(lock_stat.permissions)) return error.SinkFailure;
        if (!(file.tryLock(self.io, .exclusive) catch return error.SinkFailure)) {
            return error.LockUnavailable;
        }
        self.lock_file = file;
    }

    fn recover(context: *anyopaque, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, heading: []const u8, allocator: std.mem.Allocator) sink_port.Error!runtime.Recovery {
        const self = cast(context);
        try self.requireHeld(binding);
        var ordinals: std.ArrayList(u16) = .empty;
        const stream_directory = self.directory(stream);
        var iterator = stream_directory.iterate();
        while (iterator.next(self.io) catch return error.SinkFailure) |entry| {
            if (entry.kind != .file) return error.CorruptStream;
            if (parseSegmentName(entry.name, stream)) |ordinal| {
                ordinals.append(allocator, ordinal) catch return error.SinkFailure;
                continue;
            }
            if (std.mem.eql(u8, entry.name, lockName())) continue;
            return error.CorruptStream;
        }
        const total_segments = self.countRunSegments(stream) catch return error.CorruptStream;
        const history_next_sequence = self.historicalNextSequence(stream, heading, allocator) catch return error.CorruptStream;
        if (total_segments > logging.max_segments) return error.CorruptStream;
        if (ordinals.items.len == 0) return .{ .empty = .{
            .next_segment_ordinal = 1,
            .next_sequence = history_next_sequence,
            .total_segment_count = total_segments,
        } };
        std.mem.sort(u16, ordinals.items, {}, std.sort.asc(u16));
        for (ordinals.items, 0..) |ordinal, index| {
            if (ordinal != index + 1) return error.CorruptStream;
        }
        var active: ?runtime.StreamState = null;
        var prior_sequence: u64 = history_next_sequence - 1;
        for (ordinals.items, 0..) |ordinal, index| {
            const inspection = self.inspectSegment(
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

    fn create(context: *anyopaque, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, ordinal: u16, seed: runtime.StreamSeed, heading: []const u8, header: []const u8) sink_port.Error!runtime.StreamState {
        const self = cast(context);
        try self.requireHeld(binding);
        if (ordinal == 0 or ordinal != seed.next_segment_ordinal or seed.next_sequence == 0 or
            seed.total_segment_count >= logging.max_segments or
            heading.len + header.len > logging.max_segment_bytes) return error.SinkFailure;
        var name_buffer: [32]u8 = undefined;
        const name = segmentName(stream, ordinal, &name_buffer) catch return error.SinkFailure;
        var file = self.directory(stream).createFile(self.io, name, .{
            .read = true,
            .exclusive = true,
            .permissions = ownerOnlyPermissions(),
            .resolve_beneath = true,
        }) catch return error.SinkFailure;
        defer file.close(self.io);
        file.writeStreamingAll(self.io, heading) catch return error.SinkFailure;
        file.writeStreamingAll(self.io, header) catch return error.SinkFailure;
        file.sync(self.io) catch return error.FlushFailure;
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

    fn rotate(context: *anyopaque, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8, heading: []const u8, header: []const u8) sink_port.Error!runtime.StreamState {
        const self = cast(context);
        try self.requireHeld(binding);
        if (state.total_segment_count == logging.max_segments) return error.SegmentLimitExhausted;
        var old_name_buffer: [32]u8 = undefined;
        const old_name = segmentName(stream, state.segment_ordinal, &old_name_buffer) catch return error.SinkFailure;
        var old = self.directory(stream).openFile(self.io, old_name, .{
            .mode = .read_write,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.SinkFailure;
        defer old.close(self.io);
        const stat = old.stat(self.io) catch return error.SinkFailure;
        if (stat.kind != .file or !ownerFilePermissions(stat.permissions) or stat.size != state.segment_bytes or stat.size + trailer.len > logging.max_segment_bytes) {
            return error.SinkFailure;
        }
        old.writePositionalAll(self.io, trailer, stat.size) catch return error.SinkFailure;
        old.sync(self.io) catch return error.FlushFailure;
        const next = try create(context, binding, stream, state.segment_ordinal + 1, .{
            .next_segment_ordinal = state.segment_ordinal + 1,
            .next_sequence = state.next_sequence,
            .total_segment_count = state.total_segment_count,
        }, heading, header);
        return next;
    }

    fn append(context: *anyopaque, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, row: []const u8, flush: bool) sink_port.Error!runtime.PersistedEvidence {
        const self = cast(context);
        try self.requireHeld(binding);
        if (row.len == 0 or row[row.len - 1] != '\n' or state.segment_bytes + row.len > logging.max_segment_bytes) {
            return error.SinkFailure;
        }
        var name_buffer: [32]u8 = undefined;
        const name = segmentName(stream, state.segment_ordinal, &name_buffer) catch return error.SinkFailure;
        var file = self.directory(stream).openFile(self.io, name, .{
            .mode = .read_write,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.SinkFailure;
        defer file.close(self.io);
        const stat = file.stat(self.io) catch return error.SinkFailure;
        if (stat.kind != .file or !ownerFilePermissions(stat.permissions) or stat.size != state.segment_bytes) return error.SinkFailure;
        file.writePositionalAll(self.io, row, stat.size) catch return error.SinkFailure;
        if (flush) file.sync(self.io) catch return error.FlushFailure;
        return .{
            .segment_ordinal = state.segment_ordinal,
            .sequence = state.next_sequence,
            .bytes_written = row.len,
            .flushed = flush,
        };
    }

    fn close(context: *anyopaque, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, state: runtime.StreamState, trailer: []const u8) sink_port.Error!void {
        const self = cast(context);
        try self.requireHeld(binding);
        var name_buffer: [32]u8 = undefined;
        const name = segmentName(stream, state.segment_ordinal, &name_buffer) catch return error.SinkFailure;
        var file = self.directory(stream).openFile(self.io, name, .{
            .mode = .read_write,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        }) catch return error.SinkFailure;
        defer file.close(self.io);
        const stat = file.stat(self.io) catch return error.SinkFailure;
        if (stat.kind != .file or !ownerFilePermissions(stat.permissions) or stat.size != state.segment_bytes or stat.size + trailer.len > logging.max_segment_bytes) return error.SinkFailure;
        file.writePositionalAll(self.io, trailer, stat.size) catch return error.SinkFailure;
        file.sync(self.io) catch return error.FlushFailure;
    }

    fn prune(context: *anyopaque, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, cutoff_unix_ms: u64) sink_port.Error!void {
        const self = cast(context);
        try self.requireHeld(binding);
        const stream_directory = self.directory(stream);
        var selected: [logging.max_segments]RetentionEntry = undefined;
        var selected_count: usize = 0;
        var iterator = stream_directory.iterate();
        while (iterator.next(self.io) catch return error.SinkFailure) |entry| {
            const ordinal = parseSegmentName(entry.name, stream) orelse continue;
            var file = stream_directory.openFile(self.io, entry.name, .{
                .mode = .read_only,
                .allow_directory = false,
                .follow_symlinks = false,
                .resolve_beneath = true,
            }) catch return error.SinkFailure;
            defer file.close(self.io);
            const stat = file.stat(self.io) catch return error.SinkFailure;
            if (stat.kind != .file or !ownerFilePermissions(stat.permissions) or stat.size > logging.max_segment_bytes) return error.CorruptStream;
            var reader = file.reader(self.io, &.{});
            const bytes = reader.interface.allocRemaining(
                std.heap.page_allocator,
                .limited(@intCast(stat.size + 1)),
            ) catch return error.SinkFailure;
            defer std.heap.page_allocator.free(bytes);
            if (bytes.len != stat.size) return error.CorruptStream;
            const closed_at = trailerUnixMs(bytes) orelse return error.CorruptStream;
            if (closed_at <= cutoff_unix_ms) {
                if (selected_count == selected.len) return error.CorruptStream;
                selected[selected_count] = .{ .ordinal = ordinal, .closed_at_unix_ms = closed_at };
                selected_count += 1;
            }
        }
        std.mem.sort(RetentionEntry, selected[0..selected_count], {}, retentionLessThan);
        for (selected[0..selected_count]) |entry| {
            var name_buffer: [32]u8 = undefined;
            const name = segmentName(stream, entry.ordinal, &name_buffer) catch return error.SinkFailure;
            stream_directory.deleteFile(self.io, name) catch return error.SinkFailure;
        }
    }

    fn release(context: *anyopaque) sink_port.Error!void {
        const self = cast(context);
        const file = self.lock_file orelse return error.ReleaseFailure;
        file.unlock(self.io);
        file.close(self.io);
        self.lock_file = null;
    }

    const Inspection = struct { closed: bool, last_sequence: u64, bytes: u64 };
    fn inspectSegment(self: *Adapter, allocator: std.mem.Allocator, binding: *const runtime.ValidatedFeatureLogBinding, stream: runtime.Stream, ordinal: u16, heading: []const u8, allow_truncate: bool, first_sequence: u64) !Inspection {
        var name_buffer: [32]u8 = undefined;
        const name = try segmentName(stream, ordinal, &name_buffer);
        var file = try self.directory(stream).openFile(self.io, name, .{
            .mode = if (allow_truncate) .read_write else .read_only,
            .allow_directory = false,
            .follow_symlinks = false,
            .resolve_beneath = true,
        });
        defer file.close(self.io);
        var stat = try file.stat(self.io);
        if (stat.kind != .file or !ownerFilePermissions(stat.permissions) or stat.size > logging.max_segment_bytes) return error.InvalidSegment;
        var reader = file.reader(self.io, &.{});
        var bytes = try reader.interface.allocRemaining(allocator, .limited64(stat.size + 1));
        if (bytes.len != stat.size) return error.InvalidSegment;
        if (bytes.len == 0) return error.InvalidSegment;
        if (bytes[bytes.len - 1] != '\n') {
            if (!allow_truncate) return error.InvalidSegment;
            const end = std.mem.lastIndexOfScalar(u8, bytes, '\n') orelse return error.InvalidSegment;
            try file.setLength(self.io, end + 1);
            try file.sync(self.io);
            bytes = bytes[0 .. end + 1];
            stat.size = end + 1;
        }
        if (!std.mem.startsWith(u8, bytes, heading)) return error.InvalidSegment;
        var lines = std.mem.splitScalar(u8, bytes[heading.len..], '\n');
        const header = lines.next() orelse return error.InvalidSegment;
        if (header.len == 0 or !std.mem.eql(u8, cellAt(header, 0) orelse return error.InvalidSegment, "segment_header")) {
            return error.InvalidSegment;
        }
        const header_with_lf = try std.fmt.allocPrint(allocator, "{s}\n", .{header});
        try format.validateEncodedRow(allocator, header_with_lf, if (stream == .event) 38 else 30);
        try validateIdentityCells(header, binding, ordinal, stream);
        try validateControlCells(header, .segment_header, stream, null);
        var last_sequence: u64 = first_sequence - 1;
        var closed = false;
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            const with_lf = try std.fmt.allocPrint(allocator, "{s}\n", .{line});
            try format.validateEncodedRow(allocator, with_lf, if (stream == .event) 38 else 30);
            const kind = cellAt(line, 0) orelse return error.InvalidSegment;
            if (std.mem.eql(u8, kind, @tagName(stream))) {
                if (closed) return error.InvalidSegment;
                try validateIdentityCells(line, binding, ordinal, stream);
                const sequence = try std.fmt.parseInt(u64, cellAt(line, 9) orelse return error.InvalidSegment, 10);
                if (sequence != last_sequence + 1) return error.InvalidSegment;
                last_sequence = sequence;
            } else if (std.mem.eql(u8, kind, "segment_trailer")) {
                if (closed) return error.InvalidSegment;
                try validateIdentityCells(line, binding, ordinal, stream);
                try validateControlCells(line, .segment_trailer, stream, last_sequence);
                closed = true;
            } else return error.InvalidSegment;
        }
        return .{ .closed = closed, .last_sequence = last_sequence, .bytes = stat.size };
    }

    fn requireHeld(self: *Adapter, binding: *const runtime.ValidatedFeatureLogBinding) sink_port.Error!void {
        if (self.lock_file == null or !runtime.sameBinding(binding, self.expected_binding)) return error.InvalidBinding;
    }

    fn directory(self: *Adapter, stream: runtime.Stream) Io.Dir {
        return if (stream == .event) self.event_directory else self.prompt_directory;
    }

    fn runDirectory(self: *Adapter, stream: runtime.Stream) Io.Dir {
        return if (stream == .event) self.event_run_directory else self.prompt_run_directory;
    }

    fn countRunSegments(self: *Adapter, stream: runtime.Stream) !u8 {
        var count: usize = 0;
        var iterator = self.runDirectory(stream).iterate();
        while (try iterator.next(self.io)) |entry| switch (entry.kind) {
            .file => {
                if (parseSegmentName(entry.name, stream) != null) count += 1 else if (!std.mem.eql(u8, entry.name, lockName())) return error.CorruptStream;
            },
            .directory => {
                var binding_directory = try self.runDirectory(stream).openDir(self.io, entry.name, .{ .iterate = true, .follow_symlinks = false });
                defer binding_directory.close(self.io);
                var segments = binding_directory.iterate();
                while (try segments.next(self.io)) |segment| {
                    if (segment.kind != .file or parseSegmentName(segment.name, stream) == null) return error.CorruptStream;
                    count += 1;
                }
            },
            else => return error.CorruptStream,
        };
        if (count > logging.max_segments) return error.CorruptStream;
        return @intCast(count);
    }

    fn historicalNextSequence(self: *Adapter, stream: runtime.Stream, heading: []const u8, allocator: std.mem.Allocator) !u64 {
        if (!self.scans_run_history) return 1;
        var maximum: u64 = 0;
        var iterator = self.runDirectory(stream).iterate();
        while (try iterator.next(self.io)) |entry| {
            if (entry.kind == .file and std.mem.eql(u8, entry.name, lockName())) continue;
            if (entry.kind != .directory) return error.CorruptStream;
            if (std.mem.eql(u8, entry.name, self.expected_binding.binding_id.bytes)) continue;
            var historical = try self.runDirectory(stream).openDir(self.io, entry.name, .{
                .iterate = true,
                .follow_symlinks = false,
            });
            defer historical.close(self.io);
            var segments = historical.iterate();
            while (try segments.next(self.io)) |segment| {
                const ordinal = parseSegmentName(segment.name, stream) orelse return error.CorruptStream;
                if (segment.kind != .file) return error.CorruptStream;
                var file = try historical.openFile(self.io, segment.name, .{
                    .mode = .read_only,
                    .allow_directory = false,
                    .follow_symlinks = false,
                    .resolve_beneath = true,
                });
                defer file.close(self.io);
                const stat = try file.stat(self.io);
                if (stat.kind != .file or !ownerFilePermissions(stat.permissions) or stat.size > logging.max_segment_bytes) return error.CorruptStream;
                var reader = file.reader(self.io, &.{});
                const bytes = try reader.interface.allocRemaining(allocator, .limited64(stat.size + 1));
                if (bytes.len != stat.size or !std.mem.startsWith(u8, bytes, heading) or bytes.len == 0 or bytes[bytes.len - 1] != '\n') {
                    return error.CorruptStream;
                }
                const without_lf = bytes[0 .. bytes.len - 1];
                const trailer_start = (std.mem.lastIndexOfScalar(u8, without_lf, '\n') orelse return error.CorruptStream) + 1;
                const trailer = without_lf[trailer_start..];
                if (!std.mem.eql(u8, cellAt(trailer, 0) orelse return error.CorruptStream, "segment_trailer") or
                    !std.mem.eql(u8, cellAt(trailer, 2) orelse return error.CorruptStream, @tagName(stream)) or
                    !std.mem.eql(u8, cellAt(trailer, 5) orelse return error.CorruptStream, entry.name) or
                    try std.fmt.parseInt(u16, cellAt(trailer, 6) orelse return error.CorruptStream, 10) != ordinal or
                    !std.mem.eql(u8, cellAt(trailer, 15) orelse return error.CorruptStream, self.expected_binding.run_id.bytes) or
                    !std.mem.eql(u8, cellAt(trailer, 16) orelse return error.CorruptStream, self.expected_binding.feature_id.bytes))
                {
                    return error.CorruptStream;
                }
                const sequence = try std.fmt.parseInt(u64, cellAt(trailer, 9) orelse return error.CorruptStream, 10);
                maximum = @max(maximum, sequence);
            }
        }
        return maximum + 1;
    }
};

const RetentionEntry = struct { ordinal: u16, closed_at_unix_ms: u64 };
fn retentionLessThan(_: void, left: RetentionEntry, right: RetentionEntry) bool {
    return left.closed_at_unix_ms < right.closed_at_unix_ms or
        (left.closed_at_unix_ms == right.closed_at_unix_ms and left.ordinal < right.ordinal);
}

const vtable: sink_port.Sink.VTable = .{
    .acquire = Adapter.acquire,
    .recover = Adapter.recover,
    .create = Adapter.create,
    .rotate = Adapter.rotate,
    .close = Adapter.close,
    .append = Adapter.append,
    .prune = Adapter.prune,
    .release = Adapter.release,
};

fn cast(context: *anyopaque) *Adapter {
    return @ptrCast(@alignCast(context));
}
fn lockName() []const u8 {
    return ".stream.lock";
}
fn segmentName(stream: runtime.Stream, ordinal: u16, buffer: []u8) ![]const u8 {
    _ = stream;
    return std.fmt.bufPrint(buffer, "{d:0>4}.log", .{ordinal});
}
fn parseSegmentName(name: []const u8, stream: runtime.Stream) ?u16 {
    _ = stream;
    if (name.len != 8 or !std.mem.endsWith(u8, name, ".log")) return null;
    const digits = name[0..4];
    const value = std.fmt.parseInt(u16, digits, 10) catch return null;
    return if (value == 0) null else value;
}
fn ownerOnlyPermissions() Io.File.Permissions {
    return if (@hasDecl(Io.File.Permissions, "fromMode"))
        Io.File.Permissions.fromMode(0o600)
    else
        .default_file;
}

fn ownerFilePermissions(permissions: Io.File.Permissions) bool {
    if (@hasDecl(Io.File.Permissions, "toMode")) {
        const mode = permissions.toMode();
        return mode & 0o077 == 0 and mode & 0o600 == 0o600;
    }
    return true;
}

fn openOwnerDirectory(io: Io, root: Io.Dir, path: []const u8) !Io.Dir {
    return root.openDir(io, path, .{
        .iterate = true,
        .follow_symlinks = false,
    });
}

fn requireOwnerDirectory(io: Io, directory: Io.Dir) Adapter.InitError!void {
    const stat = directory.stat(io) catch return error.ArtifactStorageUnavailable;
    if (stat.kind != .directory) return error.ArtifactStorageUnavailable;
    if (@hasDecl(Io.File.Permissions, "toMode") and stat.permissions.toMode() & 0o077 != 0) {
        return error.InsecurePermissions;
    }
}

fn validateIdentityCells(line: []const u8, binding: *const runtime.ValidatedFeatureLogBinding, ordinal: u16, stream: runtime.Stream) !void {
    if (!std.mem.eql(u8, cellAt(line, 1) orelse return error.InvalidSegment, logging.schema_version) or
        !std.mem.eql(u8, cellAt(line, 2) orelse return error.InvalidSegment, @tagName(stream)) or
        !std.mem.eql(u8, cellAt(line, 3) orelse return error.InvalidSegment, if (stream == .event) logging.event_column_schema_id else logging.prompt_column_schema_id) or
        !std.mem.eql(u8, cellAt(line, 4) orelse return error.InvalidSegment, binding.logPolicyId().bytes) or
        !std.mem.eql(u8, cellAt(line, 5) orelse return error.InvalidSegment, binding.bindingId().bytes) or
        try std.fmt.parseInt(u16, cellAt(line, 6) orelse return error.InvalidSegment, 10) != ordinal or
        !std.mem.eql(u8, cellAt(line, 15) orelse return error.InvalidSegment, binding.runId().bytes) or
        !std.mem.eql(u8, cellAt(line, 16) orelse return error.InvalidSegment, binding.featureId().bytes))
    {
        return error.InvalidSegment;
    }
}

fn validateControlCells(line: []const u8, kind: format.ControlKind, stream: runtime.Stream, final_sequence: ?u64) !void {
    if (!std.mem.eql(u8, cellAt(line, 0) orelse return error.InvalidSegment, @tagName(kind)) or
        parseUtcMs(cellAt(line, 10) orelse return error.InvalidSegment) == null) return error.InvalidSegment;
    const event_nulls = [_]usize{ 7, 8, 11, 12, 13, 14, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37 };
    const prompt_nulls = [_]usize{ 7, 8, 11, 12, 13, 14, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29 };
    const null_columns: []const usize = if (stream == .event) &event_nulls else &prompt_nulls;
    for (null_columns) |column| if (!std.mem.eql(u8, cellAt(line, column) orelse return error.InvalidSegment, "\\N")) return error.InvalidSegment;
    const sequence = cellAt(line, 9) orelse return error.InvalidSegment;
    if (final_sequence) |expected| {
        if (try std.fmt.parseInt(u64, sequence, 10) != expected) return error.InvalidSegment;
    } else if (!std.mem.eql(u8, sequence, "\\N")) return error.InvalidSegment;
}

fn cellAt(line: []const u8, expected: usize) ?[]const u8 {
    var cell: usize = 0;
    var start: usize = 0;
    var escaped = false;
    for (line, 0..) |byte, index| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (byte == '\\') {
            escaped = true;
        } else if (byte == '|') {
            if (cell == expected) return line[start..index];
            cell += 1;
            start = index + 1;
        }
    }
    return if (cell == expected) line[start..] else null;
}

fn trailerUnixMs(bytes: []const u8) ?u64 {
    if (bytes.len == 0 or bytes[bytes.len - 1] != '\n') return null;
    const without_lf = bytes[0 .. bytes.len - 1];
    const start = (std.mem.lastIndexOfScalar(u8, without_lf, '\n') orelse return null) + 1;
    const line = without_lf[start..];
    if (!std.mem.eql(u8, cellAt(line, 0) orelse return null, "segment_trailer")) return null;
    return parseUtcMs(cellAt(line, 10) orelse return null);
}

fn parseUtcMs(value: []const u8) ?u64 {
    if (value.len != 20 or value[4] != '-' or value[7] != '-' or value[10] != 'T' or
        value[13] != ':' or value[16] != ':' or value[19] != 'Z') return null;
    const year = std.fmt.parseInt(u16, value[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, value[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, value[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, value[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u8, value[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u8, value[17..19], 10) catch return null;
    if (year < 1970 or month == 0 or month > 12 or day == 0 or hour > 23 or minute > 59 or second > 59) return null;
    var days: u64 = 0;
    var current_year: u16 = 1970;
    while (current_year < year) : (current_year += 1) days += if (leap(current_year)) 366 else 365;
    const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var current_month: u8 = 1;
    while (current_month < month) : (current_month += 1) {
        days += month_days[current_month - 1] + @as(u8, if (current_month == 2 and leap(year)) 1 else 0);
    }
    const max_day = month_days[month - 1] + @as(u8, if (month == 2 and leap(year)) 1 else 0);
    if (day > max_day) return null;
    days += day - 1;
    return (((days * 24 + hour) * 60 + minute) * 60 + second) * 1000;
}
fn leap(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
}
