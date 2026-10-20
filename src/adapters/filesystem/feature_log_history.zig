//! Filesystem discovery of the current feature's prior-run log groups for
//! retention. It only reads. Every prior binding is validated by recovery's
//! segment inspector against the identity in its first segment header; any
//! failure is returned, never skipped. A prior run whose event or prompt stream
//! ends in an active tail is kept whole, so a crashed run is never pruned.
const std = @import("std");
const artifacts = @import("../../domain/workflow_artifact_registry.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_limits = @import("../../domain/feature_log_limits.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const port = @import("../../ports/feature_log_history.zig");
const directory_boundary = @import("feature_log_directory.zig");
const feature_log_file = @import("feature_log_file.zig");
const file_identity = @import("file_identity.zig");
const recovery = @import("feature_log_recovery.zig");

const Io = std.Io;

pub const Adapter = struct {
    io: Io,
    project_root: Io.Dir,

    pub fn discoverer(self: *Adapter) port.Discoverer {
        return .{ .context = self, .discover_fn = discover };
    }

    fn discover(context: *anyopaque, allocator: std.mem.Allocator, registry: *const artifacts.WorkflowArtifactRegistry) port.Error!port.Discovery {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const history = artifacts.featureLogHistory(registry);
        var specs_root = self.project_root.openDir(self.io, history.specs_root_path, .{ .access_sub_paths = true, .follow_symlinks = false }) catch |err| return if (err == error.Canceled) error.Cancelled else error.HistoryUnavailable;
        defer specs_root.close(self.io);
        if (!(file_identity.inspect(specs_root.handle) catch return error.HistoryUnavailable).eql(history.specs_root_identity)) return error.HistoryUnavailable;
        // Closed groups not yet handed to the result are freed here.
        var closed: std.ArrayList(port.Group) = .empty;
        defer {
            for (closed.items) |group| port.freeCandidate(allocator, group.binding);
            closed.deinit(allocator);
        }
        var active_runs: std.ArrayList([]const u8) = .empty;
        defer {
            for (active_runs.items) |run_id| allocator.free(run_id);
            active_runs.deinit(allocator);
        }
        for ([_]log_stream.Stream{ .event, .prompt }) |stream| {
            var logs = try openValidated(self.io, specs_root, if (stream == .event) history.event_logs_path else history.prompt_logs_path);
            defer logs.close(self.io);
            var runs = logs.iterate();
            while (runs.next(self.io) catch |err| return iterationError(err)) |run_entry| {
                if (std.mem.eql(u8, run_entry.name, history.current.run_id.bytes)) continue;
                if (run_entry.kind != .directory) return error.InvalidHistory;
                var run = try openValidated(self.io, logs, run_entry.name);
                defer run.close(self.io);
                var bindings = run.iterate();
                while (bindings.next(self.io) catch |err| return iterationError(err)) |binding_entry| {
                    if (binding_entry.kind == .file and std.mem.eql(u8, binding_entry.name, feature_log_file.lock_name)) continue;
                    if (binding_entry.kind != .directory) return error.InvalidHistory;
                    var directory = try openValidated(self.io, run, binding_entry.name);
                    defer directory.close(self.io);
                    const candidate = switch (try groupCandidate(self.io, allocator, directory, run_entry.name, binding_entry.name, history.current.feature_id, stream)) {
                        .empty => continue,
                        // A crash while the only segment was created left no identity to read.
                        .torn => {
                            try markActive(allocator, &active_runs, run_entry.name);
                            continue;
                        },
                        .identified => |value| value,
                    };
                    var retained = false;
                    defer if (!retained) port.freeCandidate(allocator, candidate);
                    const owner = log_binding.createValidated(allocator, candidate) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidHistory;
                    defer log_binding.deinitOwner(owner);
                    var scratch: std.heap.ArenaAllocator = .init(allocator);
                    defer scratch.deinit();
                    switch (recovery.inspectGroup(self.io, directory, scratch.allocator(), log_binding.binding(owner), stream) catch |err| return inspectionError(err)) {
                        .empty => {},
                        .active => try markActive(allocator, &active_runs, run_entry.name),
                        .closed => {
                            try closed.append(allocator, .{ .stream = stream, .binding = candidate });
                            retained = true;
                        },
                    }
                }
            }
        }
        std.mem.sort(port.Group, closed.items, {}, lessGroup);
        // A run with an active tail in either stream keeps all of its groups.
        var groups: std.ArrayList(port.Group) = try .initCapacity(allocator, closed.items.len);
        errdefer {
            for (groups.items) |group| port.freeCandidate(allocator, group.binding);
            groups.deinit(allocator);
        }
        var kept: usize = 0;
        for (closed.items) |group| {
            if (contains(active_runs.items, group.binding.run_id.bytes)) {
                closed.items[kept] = group;
                kept += 1;
            } else groups.appendAssumeCapacity(group);
        }
        closed.shrinkRetainingCapacity(kept);
        return .{ .groups = try groups.toOwnedSlice(allocator), .retained_runs = active_runs.items.len };
    }
};

fn lessGroup(_: void, left: port.Group, right: port.Group) bool {
    const run = std.mem.order(u8, left.binding.run_id.bytes, right.binding.run_id.bytes);
    if (run != .eq) return run == .lt;
    const binding = std.mem.order(u8, left.binding.binding_id.bytes, right.binding.binding_id.bytes);
    if (binding != .eq) return binding == .lt;
    return @intFromEnum(left.stream) < @intFromEnum(right.stream);
}

fn markActive(allocator: std.mem.Allocator, runs: *std.ArrayList([]const u8), run_id: []const u8) port.Error!void {
    if (contains(runs.items, run_id)) return;
    const owned = try allocator.dupe(u8, run_id);
    errdefer allocator.free(owned);
    try runs.append(allocator, owned);
}

fn contains(values: []const []const u8, value: []const u8) bool {
    for (values) |entry| if (std.mem.eql(u8, entry, value)) return true;
    return false;
}

/// Directories are opened without following any component and must be
/// owner-only. An insecure directory blocks; it is never skipped.
fn openValidated(io: Io, parent: Io.Dir, path: []const u8) port.Error!Io.Dir {
    var directory = directory_boundary.openOwner(io, parent, path) catch |err| return switch (err) {
        error.Cancelled => error.Cancelled,
        error.DirectoryMissing, error.DirectoryUnavailable => error.HistoryUnavailable,
    };
    errdefer directory.close(io);
    directory_boundary.validateOwner(io, directory) catch |err| return switch (err) {
        error.InsecurePermissions => error.InvalidHistory,
        error.ArtifactStorageUnavailable => error.HistoryUnavailable,
    };
    return directory;
}

fn iterationError(err: anyerror) port.Error {
    return if (err == error.Canceled) error.Cancelled else error.HistoryUnavailable;
}

fn inspectionError(err: recovery.InspectError) port.Error {
    return switch (err) {
        error.InvalidSegment => error.InvalidHistory,
        error.SegmentUnavailable => error.HistoryUnavailable,
        error.Cancelled => error.Cancelled,
        error.OutOfMemory => error.OutOfMemory,
    };
}

const Candidate = union(enum) { empty, torn, identified: log_binding.BindingCandidate };

/// The group's identity: its directory names, the current feature and the
/// policy named by its first segment header. Validation of every segment
/// against that identity follows. A lone first segment torn during creation has
/// no identity and marks its run as crashed once its directory names are valid
/// identifiers; any other torn segment is invalid.
fn groupCandidate(
    io: Io,
    allocator: std.mem.Allocator,
    directory: Io.Dir,
    run_id: []const u8,
    binding_id: []const u8,
    feature_id: @import("../../domain/feature_identity.zig").FeatureId,
    stream: log_stream.Stream,
) port.Error!Candidate {
    var ordinals: [log_limits.max_segments]u16 = undefined;
    const count = recovery.segmentOrdinals(io, directory, &ordinals) catch |err| return inspectionError(err);
    if (count == 0) return .empty;
    const policy = (recovery.segmentPolicy(io, directory, allocator, ordinals[0], stream) catch |err| return inspectionError(err)) orelse {
        const identifiers = log_binding.validPathName(run_id) and log_binding.validPathName(binding_id);
        return if (count == 1 and ordinals[0] == 1 and identifiers) .torn else error.InvalidHistory;
    };
    errdefer allocator.free(policy);
    const binding = try allocator.dupe(u8, binding_id);
    errdefer allocator.free(binding);
    const run = try allocator.dupe(u8, run_id);
    errdefer allocator.free(run);
    return .{ .identified = .{
        .log_policy_id = .{ .bytes = policy },
        .binding_id = .{ .bytes = binding },
        .run_id = .{ .bytes = run },
        .feature_id = .{ .bytes = try allocator.dupe(u8, feature_id.bytes) },
    } };
}
