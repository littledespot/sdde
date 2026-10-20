const std = @import("std");
const layout = @import("adapters/filesystem/feature_log_layout.zig");
const active = @import("domain/active_feature_directory.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const root_contract = @import("domain/bootstrap_roots.zig");
const artifacts = @import("domain/workflow_artifact_registry.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const feature = @import("domain/feature_directory.zig");
const directories = @import("adapters/filesystem/directory_access.zig");

fn rootOwner(allocator: std.mem.Allocator, project: std.Io.Dir) !*roots.Owner {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const names = [_][]const u8{ "requirements/current", "references", "archive", "workflows", "presets", "principles", "templates" };
    var inspector = @import("adapters/filesystem/bootstrap_root_inspector.zig").Adapter.init(std.testing.io, project);
    var configured: [root_contract.PathKey.count]root_contract.ValidatedConfiguredRoot = undefined;
    for (&configured, names, 0..) |*entry, name, index| {
        const key: root_contract.PathKey = @enumFromInt(index);
        entry.* = .{
            .path_key = key,
            .root_role = key.role(),
            .canonical_project_root = "/project",
            .configured_relative_path = name,
            .canonical_path = try std.mem.concat(a, u8, &.{ "/project/", name }),
            .access_class = key.accessClass(),
            .existence_policy = key.existencePolicy(),
            .observation = try inspector.inspector().inspect(name),
        };
    }
    return roots.createValidated(allocator, .{
        .id = .{ .canonical_project_root = "/project", .contract_version = root_contract.bootstrap_root_contract_version },
        .config_location = .{ .canonical_project_root = "/project", .canonical_config_path = "/project/.sddtoolkit.json", .no_follow_file_identity = .{ .filesystem_id = 1, .file_id = 1 } },
        .configured_roots = configured,
        .llm_provider_config_path = .{ .relative_path = ".sddproviders.json", .canonical_project_root = "/project", .canonical_path = "/project/.sddproviders.json" },
    });
}

fn logOwner(allocator: std.mem.Allocator, selected: []const u8) !*log_binding.BindingOwner {
    return log_binding.createValidated(allocator, .{
        .log_policy_id = .{ .bytes = "LOGPOL-1" },
        .binding_id = .{ .bytes = "BINDING-1" },
        .run_id = .{ .bytes = "RUN-1" },
        .feature_id = .{ .bytes = selected },
    });
}

fn observe(allocator: std.mem.Allocator, project: std.Io.Dir, registry: *const roots.BootstrapRootRegistry) !feature.Directory {
    const selected: feature.Selector = .{ .feature_id = .{ .bytes = "Group/Café" }, .project_relative_path = "requirements/current/Group/Café" };
    var inspector: @import("adapters/filesystem/feature_directory_inspector.zig").Adapter = .{ .io = std.testing.io, .project_root = project };
    var port = inspector.inspector();
    port.capability = registry.featureDirectoryRead();
    return port.inspect(allocator, selected);
}

test "production finalization preserves capture cause through close failure and repeated cleanup" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    for ([_]bool{ false, true }) |fail_close| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        const root_owner = try rootOwner(a, project.dir);
        defer roots.deinitOwner(root_owner);
        const registry = roots.registry(root_owner);
        const prior = try observe(a, project.dir, registry);
        const policy = @import("domain/log_policy.zig");
        const policy_owner = try policy.createValidated(a, .{ .level = "debug", .console = false }, try policy.canonicalizeConfiguredLevel("debug"));
        var logs = @import("application/log_service.zig").LogService.init(policy_owner);
        defer logs.deinit();
        var inputs: @import("adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var outputs: @import("adapters/filesystem/workflow_output.zig").Adapter = .{ .io = io, .project_root = project.dir };
        var assembly: @import("composition/feature_logging_runtime.zig").Assembly = .{ .allocator = a, .io = io, .project = project.dir, .roots = registry, .logs = &logs, .inputs = &inputs, .outputs = &outputs };
        defer assembly.deinit();
        const shortcode = try @import("domain/telemetry.zig").WorkflowShortcode.parse("TEST");
        try std.testing.expectEqual(.ready, std.meta.activeTag(assembly.activator().activate(prior, shortcode)));
        const log_runner = @import("composition/active_feature_log_runtime.zig").runner(assembly.runtime_owner.?);
        const CloseFault = struct {
            original: @import("ports/feature_log_sink.zig").StreamCloser,
            fail: bool,
            calls: usize = 0,
            fn close(context: *anyopaque, selected: *const log_binding.ValidatedFeatureLogBinding, stream: @import("domain/feature_log_stream.zig").Stream, state: @import("domain/feature_log_stream.zig").StreamState, trailer: []const u8) @import("ports/feature_log_sink.zig").Error!void {
                const self: *@This() = @ptrCast(@alignCast(context));
                self.calls += 1;
                if (self.fail) return error.FlushFailure;
                return self.original.close(selected, stream, state, trailer);
            }
        };
        var close_fault: CloseFault = .{ .original = log_runner.actions.close_stream.sink, .fail = fail_close };
        log_runner.actions.close_stream.sink = .{ .context = &close_fault, .close_fn = CloseFault.close };
        var capture: @import("application/model_exchange_capture.zig").Capture = .{ .allocator = a, .logs = logs.barrier() };
        defer capture.deinit();
        capture.begin(.{
            .workflow = shortcode,
            .workflow_id = .{ .bytes = "unrelated-workflow" },
            .node = .{ .bytes = "repair-invoke" },
            .action = .{ .bytes = "invoke-model" },
            .operation = .{ .bytes = "repair-prepare" },
            .model_slot = .{ .bytes = "repair" },
            .origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } },
            .kind = .repair,
            .source = .none,
        });
        defer capture.end();
        try std.testing.expectEqual(.blocked, capture.port().capture(.request, .{ .provider_body = "must not be dispatched" }, &.{}));
        const original = capture.failure.?;
        try std.testing.expectEqual(.missing_source, original.cause.lineage);
        const reason: @import("domain/run_outcome.zig").Outcome = .{ .execution_rejected = .{ .model_capture = original } };
        const finalized = assembly.finalizer().finish(reason);
        var expected = original;
        if (fail_close) expected.subsequent_logging_failure = .LOG_FLUSH_FAILURE;
        try std.testing.expectEqualDeep(expected, finalized.execution_rejected.model_capture);
        try std.testing.expectEqual(.blocked, finalized.executionStatus().?);
        try std.testing.expect(assembly.finalized and logs.lifecycle.active == null);
        const calls_before = close_fault.calls;
        try std.testing.expectEqualDeep(finalized, assembly.finalizer().finish(finalized));
        try std.testing.expectEqual(calls_before, close_fault.calls);
    }
}

test "feature log layout activates absent and present directories without changing bootstrap observations" {
    const io = std.testing.io;
    for ([_]bool{ false, true }) |present| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        if (present) try project.dir.createDirPath(io, "requirements/current/Group/Café");
        const root_owner = try rootOwner(std.testing.allocator, project.dir);
        defer roots.deinitOwner(root_owner);
        const registry = roots.registry(root_owner);
        const prior = try observe(std.testing.allocator, project.dir, registry);
        const log_owner = try logOwner(std.testing.allocator, prior.selector.feature_id.bytes);
        defer log_binding.deinitOwner(log_owner);
        const binding = log_binding.binding(log_owner);
        var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
        const activated = try adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, binding);
        defer active.deinitOwner(activated);
        const capability = active.capability(activated);
        const current = active.directory(capability);
        try std.testing.expect(current.root_observation == .directory and current.observation == .directory);
        if (present) {
            try std.testing.expect(prior.root_observation.directory.eql(current.root_observation.directory));
            try std.testing.expect(prior.observation.directory.eql(current.observation.directory));
        } else {
            try std.testing.expect(roots.bindSpecsArtifactRegistry(registry.specsArtifacts()) == null);
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const paths = try artifacts.resolveFeaturePaths(arena.allocator(), registry.featureArtifactRoots(), prior.selector);
            var reader: @import("adapters/filesystem/feature_input_source.zig").Adapter = .{ .io = io, .project_root = project.dir, .active_feature = capability };
            var capture = reader.capturer();
            capture.capability = registry.featureInputRead();
            try std.testing.expectError(error.FeatureInputUnavailable, capture.capture(arena.allocator(), prior, paths));
        }
        const artifact_owner = try artifacts.createForActive(std.testing.allocator, registry.featureOutputWrite(), binding, capability);
        defer artifacts.deinitOwner(artifact_owner);
        var sink = try @import("adapters/filesystem/feature_log_sink.zig").Adapter.init(io, project.dir, artifacts.registry(artifact_owner), binding);
        defer sink.deinit();
        for ([_][]const u8{ "events", "prompts" }) |stream| {
            var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
            defer arena.deinit();
            const path = try std.fmt.allocPrint(arena.allocator(), "requirements/current/Group/Café/logs/{s}/RUN-1/BINDING-1", .{stream});
            const directory = try directories.open(io, project.dir, path);
            defer directory.close(io);
            try std.testing.expectEqual(@as(u32, 0), (try directory.stat(io)).permissions.toMode() & 0o077);
        }
        try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/Group/Café/spec.md", .{}));
        const foreign = try logOwner(std.testing.allocator, "other");
        defer log_binding.deinitOwner(foreign);
        try std.testing.expectError(error.InvalidWorkflowArtifactRegistry, artifacts.createForActive(std.testing.allocator, registry.featureOutputWrite(), log_binding.binding(foreign), capability));
        if (present) try std.testing.expectError(error.FeatureLogLayoutUnavailable, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), current, binding));
    }
}

test "feature log activation rejects changed directories and symlink ancestry" {
    const io = std.testing.io;
    for (0..3) |scenario| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        if (scenario != 0) try project.dir.createDirPath(io, "requirements/current/Group/Café");
        const root_owner = try rootOwner(std.testing.allocator, project.dir);
        defer roots.deinitOwner(root_owner);
        const registry = roots.registry(root_owner);
        const prior = try observe(std.testing.allocator, project.dir, registry);
        const log_owner = try logOwner(std.testing.allocator, prior.selector.feature_id.bytes);
        defer log_binding.deinitOwner(log_owner);
        switch (scenario) {
            0 => {
                try project.dir.createDirPath(io, "outside/current");
                try project.dir.symLink(io, "outside", "requirements", .{ .is_directory = true });
            },
            1 => {
                try project.dir.rename("requirements/current/Group/Café", project.dir, "old-feature", io);
                try project.dir.createDirPath(io, "requirements/current/Group/Café");
            },
            2 => {
                try project.dir.rename("requirements/current/Group", project.dir, "old-group", io);
                try project.dir.symLink(io, "../../old-group", "requirements/current/Group", .{ .is_directory = true });
            },
            else => unreachable,
        }
        var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
        try std.testing.expectError(error.FeatureLogLayoutUnavailable, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, log_binding.binding(log_owner)));
    }
}

test "feature log activation refuses existing run paths and foreign feature bindings" {
    const io = std.testing.io;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    try project.dir.createDirPath(io, "requirements/current/Group/Café/logs/events/RUN-1");
    const root_owner = try rootOwner(std.testing.allocator, project.dir);
    defer roots.deinitOwner(root_owner);
    const registry = roots.registry(root_owner);
    const prior = try observe(std.testing.allocator, project.dir, registry);
    const log_owner = try logOwner(std.testing.allocator, prior.selector.feature_id.bytes);
    defer log_binding.deinitOwner(log_owner);
    var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
    try std.testing.expectError(error.FeatureLogLayoutUnavailable, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, log_binding.binding(log_owner)));
    const foreign = try logOwner(std.testing.allocator, "other");
    defer log_binding.deinitOwner(foreign);
    try std.testing.expectError(error.InvalidFeatureLogLayout, adapter.port().activate(std.testing.allocator, registry.featureOutputWrite(), prior, log_binding.binding(foreign)));
    try std.testing.expectError(error.FileNotFound, project.dir.access(io, "requirements/current/other", .{}));
}

const telemetry = @import("domain/telemetry.zig");
const LogService = @import("application/log_service.zig").LogService;
const LoggingAssembly = @import("composition/feature_logging_runtime.zig").Assembly;

/// One process lifetime: fresh bootstrap roots, log service and logging assembly,
/// as every engine invocation has.
const Run = struct {
    root_owner: *roots.Owner,
    logs: LogService,
    inputs: @import("adapters/filesystem/feature_input_source.zig").Adapter,
    outputs: @import("adapters/filesystem/workflow_output.zig").Adapter,
    assembly: LoggingAssembly = undefined,

    fn start(self: *Run, a: std.mem.Allocator, io: std.Io, project: std.Io.Dir) !@import("ports/feature_log_activation.zig").Outcome {
        self.root_owner = try rootOwner(a, project);
        const policy = @import("domain/log_policy.zig");
        self.logs = LogService.init(try policy.createValidated(a, .{ .level = "debug", .console = false }, try policy.canonicalizeConfiguredLevel("debug")));
        self.inputs = .{ .io = io, .project_root = project };
        self.outputs = .{ .io = io, .project_root = project };
        const registry = roots.registry(self.root_owner);
        self.assembly = .{ .allocator = a, .io = io, .project = project, .roots = registry, .logs = &self.logs, .inputs = &self.inputs, .outputs = &self.outputs };
        return self.assembly.activator().activate(try observe(a, project, registry), try telemetry.WorkflowShortcode.parse("TEST"));
    }

    fn finish(self: *Run) void {
        _ = self.assembly.finalizer().finish(.{ .execution = .ok });
        self.assembly.deinit();
        self.logs.deinit();
        roots.deinitOwner(self.root_owner);
    }
};

const logs_root = "requirements/current/Group/Café/logs";

/// The first segment of each stream of one completed run.
const Segments = struct {
    event: []const u8,
    prompt: []const u8,

    fn deinit(self: Segments, a: std.mem.Allocator) void {
        a.free(self.event);
        a.free(self.prompt);
    }
    fn get(self: Segments, stream: @import("domain/feature_log_stream.zig").Stream) []const u8 {
        return if (stream == .event) self.event else self.prompt;
    }
};

/// Run one complete feature-log lifetime and return its first segment paths.
fn completedRun(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir) !Segments {
    var run: Run = undefined;
    try std.testing.expectEqual(.ready, std.meta.activeTag(try run.start(a, io, project)));
    defer run.finish();
    const selected = log_binding.binding(run.assembly.binding_owner.?);
    const event = try std.fmt.allocPrint(a, logs_root ++ "/events/{s}/{s}/0001.log", .{ selected.runId().bytes, selected.bindingId().bytes });
    errdefer a.free(event);
    return .{ .event = event, .prompt = try std.fmt.allocPrint(a, logs_root ++ "/prompts/{s}/{s}/0001.log", .{ selected.runId().bytes, selected.bindingId().bytes }) };
}

/// Start the next run and return its activation outcome, finishing it.
fn nextRun(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir) !@import("ports/feature_log_activation.zig").Outcome {
    var run: Run = undefined;
    const outcome = try run.start(a, io, project);
    run.finish();
    return outcome;
}

/// Rewrite the trailer's close time in place, keeping length and permissions.
fn ageTrailer(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir, path: []const u8) !void {
    const utc = "2026-01-01T00:00:00Z";
    const bytes = try project.readFileAlloc(io, path, a, .limited(1 << 24));
    defer a.free(bytes);
    const trailer = (std.mem.lastIndexOfScalar(u8, bytes[0 .. bytes.len - 1], '\n') orelse return error.MissingTrailer) + 1;
    var offset = trailer;
    for (0..10) |_| offset = std.mem.indexOfScalarPos(u8, bytes, offset, '|').? + 1;
    try std.testing.expectEqual(utc.len, std.mem.indexOfScalarPos(u8, bytes, offset, '|').? - offset);
    var file = try project.openFile(io, path, .{ .mode = .read_write });
    defer file.close(io);
    try file.writePositionalAll(io, utc, offset);
}

fn ageRun(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir, run: Segments) !void {
    try ageTrailer(a, io, project, run.event);
    try ageTrailer(a, io, project, run.prompt);
}

/// Simulate a crash by removing the closing trailer row.
fn dropTrailer(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir, path: []const u8) !void {
    const bytes = try project.readFileAlloc(io, path, a, .limited(1 << 24));
    defer a.free(bytes);
    const trailer = (std.mem.lastIndexOfScalar(u8, bytes[0 .. bytes.len - 1], '\n') orelse return error.MissingTrailer) + 1;
    var file = try project.openFile(io, path, .{ .mode = .read_write });
    defer file.close(io);
    try file.setLength(io, trailer);
}

/// Rewrite every row of a segment to name another feature, keeping it closed.
fn renameFeature(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir, path: []const u8) !void {
    const bytes = try project.readFileAlloc(io, path, a, .limited(1 << 24));
    defer a.free(bytes);
    const replaced = try std.mem.replaceOwned(u8, a, bytes, "|Group/Café|", "|Group/Cafe|");
    defer a.free(replaced);
    try std.testing.expect(!std.mem.eql(u8, bytes, replaced));
    var file = try project.openFile(io, path, .{ .mode = .read_write });
    defer file.close(io);
    try file.setLength(io, 0);
    try file.writePositionalAll(io, replaced, 0);
}

/// One pipe-delimited row with cell `index` replaced; these rows hold no
/// escaped delimiters.
fn setCell(a: std.mem.Allocator, row: []const u8, index: usize, value: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    var cells = std.mem.splitScalar(u8, row, '|');
    var position: usize = 0;
    while (cells.next()) |cell| : (position += 1) {
        if (position != 0) try out.append(a, '|');
        try out.appendSlice(a, if (position == index) value else cell);
    }
    return out.toOwnedSlice(a);
}

const Rows = struct { heading: []const u8, header: []const u8, trailer: []const u8 };

fn rowsOf(bytes: []const u8) Rows {
    const heading_end = std.mem.indexOfScalar(u8, bytes, '\n').? + 1;
    const header_end = std.mem.indexOfScalarPos(u8, bytes, heading_end, '\n').?;
    const trailer_start = std.mem.lastIndexOfScalar(u8, bytes[0 .. bytes.len - 1], '\n').? + 1;
    return .{ .heading = bytes[0..heading_end], .header = bytes[heading_end..header_end], .trailer = bytes[trailer_start .. bytes.len - 1] };
}

/// Write an owner-only segment that holds no record: the heading, a header and
/// a trailer naming `ordinal` and stating `sequence` as its final sequence.
fn writeEmptySegment(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir, model: []const u8, path: []const u8, ordinal: []const u8, sequence: ?[]const u8) !void {
    const bytes = try project.readFileAlloc(io, model, a, .limited(1 << 24));
    defer a.free(bytes);
    const rows = rowsOf(bytes);
    const header = try setCell(a, rows.header, 6, ordinal);
    defer a.free(header);
    const ordered = try setCell(a, rows.trailer, 6, ordinal);
    defer a.free(ordered);
    const trailer = if (sequence) |value| try setCell(a, ordered, 9, value) else try a.dupe(u8, ordered);
    defer a.free(trailer);
    const content = try std.mem.concat(a, u8, &.{ rows.heading, header, "\n", trailer, "\n" });
    defer a.free(content);
    try writeOwned(io, project, path, content);
}

fn writeOwned(io: std.Io, project: std.Io.Dir, path: []const u8, content: []const u8) !void {
    var file = try project.createFile(io, path, .{ .permissions = std.Io.File.Permissions.fromMode(0o600) });
    defer file.close(io);
    try file.setLength(io, 0);
    try file.writePositionalAll(io, content, 0);
}

fn siblingSegment(a: std.mem.Allocator, path: []const u8, name: []const u8) ![]u8 {
    return std.fmt.allocPrint(a, "{s}/{s}", .{ std.fs.path.dirname(path).?, name });
}

fn setMode(io: std.Io, project: std.Io.Dir, path: []const u8, mode: std.posix.mode_t) !void {
    var directory = try project.openDir(io, path, .{});
    defer directory.close(io);
    try directory.setPermissions(io, std.Io.File.Permissions.fromMode(mode));
}

fn expectKept(io: std.Io, project: std.Io.Dir, run: Segments) !void {
    try project.access(io, run.event, .{});
    try project.access(io, run.prompt, .{});
}

fn expectPruned(io: std.Io, project: std.Io.Dir, run: Segments) !void {
    try std.testing.expectError(error.FileNotFound, project.access(io, run.event, .{}));
    try std.testing.expectError(error.FileNotFound, project.access(io, run.prompt, .{}));
}

test "fresh activation prunes expired closed prior runs in both streams and keeps recent, crashed and current runs" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    const expired = try completedRun(a, io, project.dir);
    defer expired.deinit(a);
    const recent = try completedRun(a, io, project.dir);
    defer recent.deinit(a);
    // A crash after the event stream closed leaves only the prompt tail active;
    // the run is kept whole, including its closed, expired event segment.
    const crashed = try completedRun(a, io, project.dir);
    defer crashed.deinit(a);
    try ageRun(a, io, project.dir, expired);
    try ageRun(a, io, project.dir, crashed);
    try dropTrailer(a, io, project.dir, crashed.prompt);
    // The next run's activation applies retention before it starts.
    const current = try completedRun(a, io, project.dir);
    defer current.deinit(a);
    try expectPruned(io, project.dir, expired);
    for ([_]Segments{ recent, crashed, current }) |kept| try expectKept(io, project.dir, kept);
    // Empty directories stay, and a later run validates them as empty groups.
    try project.dir.access(io, std.fs.path.dirname(expired.event).?, .{});
    try std.testing.expectEqual(.ready, std.meta.activeTag(try nextRun(a, io, project.dir)));
}

test "a prior run missing one stream still has its other stream pruned" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    const expired = try completedRun(a, io, project.dir);
    defer expired.deinit(a);
    try ageRun(a, io, project.dir, expired);
    try project.dir.deleteTree(io, std.fs.path.dirname(std.fs.path.dirname(expired.prompt).?).?);
    try std.testing.expectEqual(.ready, std.meta.activeTag(try nextRun(a, io, project.dir)));
    try std.testing.expectError(error.FileNotFound, project.dir.access(io, expired.event, .{}));
}

/// Discovery for a fresh current run over the project's existing prior runs.
fn discoverHistory(a: std.mem.Allocator, io: std.Io, project: std.Io.Dir) !@import("ports/feature_log_history.zig").Discovery {
    const root_owner = try rootOwner(a, project);
    defer roots.deinitOwner(root_owner);
    const registry = roots.registry(root_owner);
    const prior = try observe(a, project, registry);
    const log_owner = try logOwner(a, prior.selector.feature_id.bytes);
    defer log_binding.deinitOwner(log_owner);
    var adapter: layout.Adapter = .{ .io = io, .project_root = project };
    const activated = try adapter.port().activate(a, registry.featureOutputWrite(), prior, log_binding.binding(log_owner));
    defer active.deinitOwner(activated);
    const artifact_owner = try artifacts.createForActive(a, registry.featureOutputWrite(), log_binding.binding(log_owner), active.capability(activated));
    defer artifacts.deinitOwner(artifact_owner);
    var history: @import("adapters/filesystem/feature_log_history.zig").Adapter = .{ .io = io, .project_root = project };
    return history.discoverer().discover(a, artifacts.registry(artifact_owner));
}

test "discovery orders closed groups, keeps a run with any active tail whole and frees what it returns" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    var runs: [3]Segments = undefined;
    for (&runs) |*run| run.* = try completedRun(a, io, project.dir);
    defer for (runs) |run| run.deinit(a);
    try dropTrailer(a, io, project.dir, runs[1].event);
    const found = try discoverHistory(a, io, project.dir);
    defer found.deinit(a);
    // The crashed run is kept whole; the two closed runs give one group per stream.
    try std.testing.expectEqual(@as(usize, 1), found.retained_runs);
    try std.testing.expectEqual(@as(usize, 4), found.groups.len);
    for (found.groups[1..], found.groups[0 .. found.groups.len - 1]) |later, earlier| {
        const order = std.mem.order(u8, earlier.binding.run_id.bytes, later.binding.run_id.bytes);
        try std.testing.expect(order == .lt or (order == .eq and earlier.stream == .event and later.stream == .prompt));
    }
    const crashed = std.fs.path.basename(std.fs.path.dirname(std.fs.path.dirname(runs[1].event).?).?);
    for (found.groups) |group| {
        try std.testing.expect(!std.mem.eql(u8, crashed, group.binding.run_id.bytes));
        const run = for (runs) |candidate| {
            if (std.mem.indexOf(u8, candidate.event, group.binding.run_id.bytes) != null) break candidate;
        } else return error.UnknownRun;
        try std.testing.expect(std.mem.indexOf(u8, run.get(group.stream), group.binding.binding_id.bytes) != null);
    }
}

test "an invalid prior group blocks discovery and activation and is never skipped" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    const Case = enum { forged_identity, symlinked_run, insecure_run, unexpected_entry, oversized_segment, foreign_feature, torn_before_another, torn_between, torn_not_first, torn_foreign_row, torn_wrong_stream, torn_reserved_name, torn_invalid_name, open_before_another, ordinal_gap, bytes_after_trailer, sequence_overflow };
    for (std.enums.values(Case)) |case| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        const expired = try completedRun(a, io, project.dir);
        defer expired.deinit(a);
        try ageRun(a, io, project.dir, expired);
        const binding_dir = std.fs.path.dirname(expired.event).?;
        const run_dir = std.fs.path.dirname(binding_dir).?;
        switch (case) {
            // A copied segment whose header names another run and binding.
            .forged_identity => {
                const forged = logs_root ++ "/events/RUN-FORGED/BINDING-FORGED";
                try project.dir.createDirPath(io, forged);
                try setMode(io, project.dir, logs_root ++ "/events/RUN-FORGED", 0o700);
                try setMode(io, project.dir, forged, 0o700);
                try project.dir.copyFile(expired.event, project.dir, forged ++ "/0001.log", io, .{});
            },
            .symlinked_run => try project.dir.symLink(io, std.fs.path.basename(run_dir), logs_root ++ "/events/RUN-ALIAS", .{ .is_directory = true }),
            .insecure_run => try setMode(io, project.dir, run_dir, 0o755),
            .unexpected_entry => {
                const path = try std.fmt.allocPrint(a, "{s}/notes.txt", .{binding_dir});
                defer a.free(path);
                try project.dir.writeFile(io, .{ .sub_path = path, .data = "x" });
            },
            // A segment torn or left open is a crash shape only when it is last.
            .torn_before_another, .open_before_another => {
                const second = try siblingSegment(a, expired.event, "0002.log");
                defer a.free(second);
                try writeEmptySegment(a, io, project.dir, expired.event, second, "2", null);
                if (case == .open_before_another) try dropTrailer(a, io, project.dir, expired.event) else try writeOwned(io, project.dir, expired.event, "");
            },
            .torn_between => {
                const bytes = try project.dir.readFileAlloc(io, expired.event, a, .limited(1 << 24));
                defer a.free(bytes);
                const second = try siblingSegment(a, expired.event, "0002.log");
                defer a.free(second);
                try writeOwned(io, project.dir, second, rowsOf(bytes).heading);
                const third = try siblingSegment(a, expired.event, "0003.log");
                defer a.free(third);
                try writeEmptySegment(a, io, project.dir, expired.event, third, "3", null);
            },
            // A creation crash tears only a first segment, and only into a
            // prefix of the heading and its `segment_header` row.
            .torn_not_first, .torn_foreign_row, .torn_wrong_stream => {
                const bytes = try project.dir.readFileAlloc(io, expired.event, a, .limited(1 << 24));
                defer a.free(bytes);
                const heading = rowsOf(bytes).heading;
                if (case == .torn_not_first) {
                    try project.dir.deleteFile(io, expired.event);
                    const fifth = try siblingSegment(a, expired.event, "0005.log");
                    defer a.free(fifth);
                    try writeOwned(io, project.dir, fifth, heading);
                } else {
                    const content = try std.mem.concat(a, u8, &.{ heading, if (case == .torn_foreign_row) "event|1" else "segment_header|feature-log/v2|prompt|" });
                    defer a.free(content);
                    try writeOwned(io, project.dir, expired.event, content);
                }
            },
            // A torn segment's directory names must still be valid binding names.
            .torn_reserved_name, .torn_invalid_name => {
                const binding = if (case == .torn_reserved_name) "aux" else "BINDING.";
                const directory = try std.fmt.allocPrint(a, logs_root ++ "/events/RUN-TORN/{s}", .{binding});
                defer a.free(directory);
                try project.dir.createDirPath(io, directory);
                try setMode(io, project.dir, logs_root ++ "/events/RUN-TORN", 0o700);
                try setMode(io, project.dir, directory, 0o700);
                const segment = try std.fmt.allocPrint(a, "{s}/0001.log", .{directory});
                defer a.free(segment);
                try writeOwned(io, project.dir, segment, "");
            },
            .ordinal_gap => {
                const third = try siblingSegment(a, expired.event, "0003.log");
                defer a.free(third);
                try writeEmptySegment(a, io, project.dir, expired.event, third, "3", null);
            },
            // Nothing is written after a trailer.
            .bytes_after_trailer => {
                var file = try project.dir.openFile(io, expired.event, .{ .mode = .read_write });
                defer file.close(io);
                try file.writePositionalAll(io, "event|x", (try file.stat(io)).size);
            },
            // A persisted final sequence at the integer limit has no successor.
            .sequence_overflow => {
                const max = std.fmt.comptimePrint("{d}", .{std.math.maxInt(u64)});
                const second = try siblingSegment(a, expired.event, "0002.log");
                defer a.free(second);
                try writeEmptySegment(a, io, project.dir, expired.event, second, "2", max);
                try writeEmptySegment(a, io, project.dir, second, expired.event, "1", max);
            },
            .oversized_segment => {
                var file = try project.dir.openFile(io, expired.event, .{ .mode = .read_write });
                defer file.close(io);
                try file.setLength(io, @import("domain/feature_log_limits.zig").max_segment_bytes + 1);
            },
            // A header and rows that name another feature.
            .foreign_feature => try renameFeature(a, io, project.dir, expired.event),
        }
        try std.testing.expectError(error.InvalidHistory, discoverHistory(a, io, project.dir));
        const outcome = try nextRun(a, io, project.dir);
        try std.testing.expectEqual(@import("domain/feature_log_stream.zig").FailureCode.LOG_SINK_FAILURE, outcome.blocked);
        try project.dir.access(io, expired.prompt, .{});
    }
}

test "a last segment torn or left open by a crash keeps its whole run" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    const Shape = enum { empty, heading_only, partial_header, partial_row };
    // A crash while creating the first segment, or while rotating to a new one
    // behind closed segments, leaves the last segment torn.
    for ([_]bool{ false, true }) |rotated| for (std.enums.values(Shape)) |shape| {
        if (rotated and shape == .partial_row) continue;
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        const crashed = try completedRun(a, io, project.dir);
        defer crashed.deinit(a);
        try ageRun(a, io, project.dir, crashed);
        const bytes = try project.dir.readFileAlloc(io, crashed.event, a, .limited(1 << 24));
        defer a.free(bytes);
        const rows = rowsOf(bytes);
        const torn = if (rotated) try siblingSegment(a, crashed.event, "0002.log") else try a.dupe(u8, crashed.event);
        defer a.free(torn);
        switch (shape) {
            .empty => try writeOwned(io, project.dir, torn, ""),
            .heading_only => try writeOwned(io, project.dir, torn, rows.heading),
            .partial_header => try writeOwned(io, project.dir, torn, bytes[0 .. rows.heading.len + rows.header.len / 2]),
            .partial_row => {
                try dropTrailer(a, io, project.dir, torn);
                var file = try project.dir.openFile(io, torn, .{ .mode = .read_write });
                defer file.close(io);
                try file.writePositionalAll(io, "event|torn", (try file.stat(io)).size);
            },
        }
        const found = try discoverHistory(a, io, project.dir);
        defer found.deinit(a);
        try std.testing.expectEqual(@as(usize, 1), found.retained_runs);
        try std.testing.expectEqual(@as(usize, 0), found.groups.len);
        try std.testing.expectEqual(.ready, std.meta.activeTag(try nextRun(a, io, project.dir)));
        // The closed, expired segments of the crashed run are kept too.
        try expectKept(io, project.dir, crashed);
        try project.dir.access(io, torn, .{});
    };
}

test "multi-segment groups prune only their longest expired ordinal prefix" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    for ([_]bool{ false, true }) |inverted| {
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try project.dir.createDir(io, "workflows", .default_dir);
        const run = try completedRun(a, io, project.dir);
        defer run.deinit(a);
        // Segment 2 continues segment 1's sequence and holds no record.
        const second = try siblingSegment(a, run.event, "0002.log");
        defer a.free(second);
        try writeEmptySegment(a, io, project.dir, run.event, second, "2", null);
        // A clock step back can make the later segment look older; timestamps
        // never reorder deletion.
        try ageTrailer(a, io, project.dir, if (inverted) second else run.event);
        try std.testing.expectEqual(.ready, std.meta.activeTag(try nextRun(a, io, project.dir)));
        try project.dir.access(io, second, .{});
        if (inverted) {
            try project.dir.access(io, run.event, .{});
            continue;
        }
        try std.testing.expectError(error.FileNotFound, project.dir.access(io, run.event, .{}));
        // The remaining group starts at ordinal 2 and still validates.
        const found = try discoverHistory(a, io, project.dir);
        defer found.deinit(a);
        try std.testing.expectEqual(@as(usize, 0), found.retained_runs);
        try std.testing.expect(found.groups.len >= 2);
        try std.testing.expectEqual(.ready, std.meta.activeTag(try nextRun(a, io, project.dir)));
    }
}

test "a historical stream proves closure again under its lock and serves only its own stream" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    const Stream = @import("adapters/filesystem/feature_log_historical_stream.zig").Adapter;
    const deadline = @import("domain/feature_log_limits.zig").stream_lock_deadline_ms;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    const expired = try completedRun(a, io, project.dir);
    defer expired.deinit(a);
    try ageRun(a, io, project.dir, expired);
    const root_owner = try rootOwner(a, project.dir);
    defer roots.deinitOwner(root_owner);
    const registry = roots.registry(root_owner);
    const prior = try observe(a, project.dir, registry);
    const log_owner = try logOwner(a, prior.selector.feature_id.bytes);
    defer log_binding.deinitOwner(log_owner);
    var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
    const activated = try adapter.port().activate(a, registry.featureOutputWrite(), prior, log_binding.binding(log_owner));
    defer active.deinitOwner(activated);
    const artifact_owner = try artifacts.createForActive(a, registry.featureOutputWrite(), log_binding.binding(log_owner), active.capability(activated));
    defer artifacts.deinitOwner(artifact_owner);
    const current = artifacts.registry(artifact_owner);
    var history: @import("adapters/filesystem/feature_log_history.zig").Adapter = .{ .io = io, .project_root = project.dir };
    const found = try history.discoverer().discover(a, current);
    defer found.deinit(a);
    try std.testing.expectEqual(@as(usize, 2), found.groups.len);
    const owner = try log_binding.createValidated(a, found.groups[0].binding);
    defer log_binding.deinitOwner(owner);
    const historical = log_binding.binding(owner);
    // After discovery the event segment is replaced by one naming another
    // feature, still closed and expired: the prune under the lock refuses it.
    try std.testing.expectEqual(.event, found.groups[0].stream);
    try renameFeature(a, io, project.dir, expired.event);
    var events = try Stream.init(a, io, project.dir, current, historical, .event);
    defer events.deinit();
    try std.testing.expectError(error.InvalidBinding, events.lockAcquirer().acquire(historical, .prompt, deadline));
    try std.testing.expectError(error.InvalidBinding, events.segmentPruner().prune(historical, .event, std.math.maxInt(u64)));
    try events.lockAcquirer().acquire(historical, .event, deadline);
    try std.testing.expectError(error.CorruptStream, events.segmentPruner().prune(historical, .event, std.math.maxInt(u64)));
    try events.lockReleaser().release();
    try project.dir.access(io, expired.event, .{});
    // Control: the still-closed prompt stream prunes under its own lock.
    var prompts = try Stream.init(a, io, project.dir, current, historical, .prompt);
    defer prompts.deinit();
    try prompts.lockAcquirer().acquire(historical, .prompt, deadline);
    try prompts.segmentPruner().prune(historical, .prompt, std.math.maxInt(u64));
    try prompts.lockReleaser().release();
    try std.testing.expectError(error.FileNotFound, project.dir.access(io, expired.prompt, .{}));
    // The current run is never a historical stream.
    try std.testing.expectError(error.InvalidArtifactRegistry, Stream.init(a, io, project.dir, current, log_binding.binding(log_owner), .event));
}

test "a stream torn after discovery is refused under its lock" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    const Stream = @import("adapters/filesystem/feature_log_historical_stream.zig").Adapter;
    const deadline = @import("domain/feature_log_limits.zig").stream_lock_deadline_ms;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    const expired = try completedRun(a, io, project.dir);
    defer expired.deinit(a);
    try ageRun(a, io, project.dir, expired);
    const root_owner = try rootOwner(a, project.dir);
    defer roots.deinitOwner(root_owner);
    const registry = roots.registry(root_owner);
    const prior = try observe(a, project.dir, registry);
    const log_owner = try logOwner(a, prior.selector.feature_id.bytes);
    defer log_binding.deinitOwner(log_owner);
    var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
    const activated = try adapter.port().activate(a, registry.featureOutputWrite(), prior, log_binding.binding(log_owner));
    defer active.deinitOwner(activated);
    const artifact_owner = try artifacts.createForActive(a, registry.featureOutputWrite(), log_binding.binding(log_owner), active.capability(activated));
    defer artifacts.deinitOwner(artifact_owner);
    const current = artifacts.registry(artifact_owner);
    var history: @import("adapters/filesystem/feature_log_history.zig").Adapter = .{ .io = io, .project_root = project.dir };
    const found = try history.discoverer().discover(a, current);
    defer found.deinit(a);
    try std.testing.expectEqual(.event, found.groups[0].stream);
    const owner = try log_binding.createValidated(a, found.groups[0].binding);
    defer log_binding.deinitOwner(owner);
    const bytes = try project.dir.readFileAlloc(io, expired.event, a, .limited(1 << 24));
    defer a.free(bytes);
    try writeOwned(io, project.dir, expired.event, rowsOf(bytes).heading);
    var events = try Stream.init(a, io, project.dir, current, log_binding.binding(owner), .event);
    defer events.deinit();
    try events.lockAcquirer().acquire(log_binding.binding(owner), .event, deadline);
    try std.testing.expectError(error.CorruptStream, events.segmentPruner().prune(log_binding.binding(owner), .event, std.math.maxInt(u64)));
    try events.lockReleaser().release();
    try project.dir.access(io, expired.event, .{});
}

test "a prune that cannot delete blocks activation and keeps the segments" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    const expired = try completedRun(a, io, project.dir);
    defer expired.deinit(a);
    try ageRun(a, io, project.dir, expired);
    const binding_dir = std.fs.path.dirname(expired.event).?;
    // Still owner-only, but the owner cannot remove entries.
    try setMode(io, project.dir, binding_dir, 0o500);
    defer setMode(io, project.dir, binding_dir, 0o700) catch {};
    const outcome = try nextRun(a, io, project.dir);
    try std.testing.expectEqual(@import("domain/feature_log_stream.zig").FailureCode.LOG_SINK_FAILURE, outcome.blocked);
    try project.dir.access(io, expired.event, .{});
}

test "retention that cannot take a prior run's lock blocks activation and deletes nothing" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    const expired = try completedRun(a, io, project.dir);
    defer expired.deinit(a);
    try ageRun(a, io, project.dir, expired);
    // Another holder keeps the prior run's event stream lock.
    const lock_path = try std.fmt.allocPrint(a, "{s}/.stream.lock", .{std.fs.path.dirname(std.fs.path.dirname(expired.event).?).?});
    defer a.free(lock_path);
    var held = try project.dir.openFile(io, lock_path, .{ .mode = .read_write });
    defer held.close(io);
    try std.testing.expect(try held.tryLock(io, .exclusive));
    defer held.unlock(io);
    const outcome = try nextRun(a, io, project.dir);
    try std.testing.expectEqual(@import("domain/feature_log_stream.zig").FailureCode.LOG_LOCK_TIMEOUT, outcome.blocked);
    try expectKept(io, project.dir, expired);
}

test "historical stream paths require the current feature and a different run" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try project.dir.createDir(io, "workflows", .default_dir);
    const root_owner = try rootOwner(a, project.dir);
    defer roots.deinitOwner(root_owner);
    const registry = roots.registry(root_owner);
    const prior = try observe(a, project.dir, registry);
    const log_owner = try logOwner(a, prior.selector.feature_id.bytes);
    defer log_binding.deinitOwner(log_owner);
    var adapter: layout.Adapter = .{ .io = io, .project_root = project.dir };
    const activated = try adapter.port().activate(a, registry.featureOutputWrite(), prior, log_binding.binding(log_owner));
    defer active.deinitOwner(activated);
    const artifact_owner = try artifacts.createForActive(a, registry.featureOutputWrite(), log_binding.binding(log_owner), active.capability(activated));
    defer artifacts.deinitOwner(artifact_owner);
    const current = artifacts.registry(artifact_owner);
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const history = artifacts.featureLogHistory(current);
    try std.testing.expectEqualStrings("RUN-1", history.current.run_id.bytes);
    const prior_run = try log_binding.createValidated(a, .{ .log_policy_id = .{ .bytes = "LOGPOL-OLD" }, .binding_id = .{ .bytes = "BINDING-OLD" }, .run_id = .{ .bytes = "RUN-OLD" }, .feature_id = prior.selector.feature_id });
    defer log_binding.deinitOwner(prior_run);
    for ([_]@import("domain/feature_log_stream.zig").Stream{ .event, .prompt }) |stream| {
        const paths = (try artifacts.bindHistoricalFeatureLogStream(arena.allocator(), current, log_binding.binding(prior_run), stream)).?;
        const logs = if (stream == .event) history.event_logs_path else history.prompt_logs_path;
        try std.testing.expectEqual(stream, paths.stream);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(arena.allocator(), "{s}/RUN-OLD", .{logs}), paths.run_path);
        try std.testing.expectEqualStrings("BINDING-OLD", paths.expected_binding.binding_id.bytes);
        try std.testing.expectEqualStrings("LOGPOL-OLD", paths.expected_binding.log_policy_id.bytes);
        // The current run is not history, and another feature's run is never reachable.
        try std.testing.expect(try artifacts.bindHistoricalFeatureLogStream(arena.allocator(), current, log_binding.binding(log_owner), stream) == null);
    }
    const foreign = try log_binding.createValidated(a, .{ .log_policy_id = .{ .bytes = "LOGPOL-OLD" }, .binding_id = .{ .bytes = "BINDING-OLD" }, .run_id = .{ .bytes = "RUN-OLD" }, .feature_id = .{ .bytes = "other" } });
    defer log_binding.deinitOwner(foreign);
    try std.testing.expect(try artifacts.bindHistoricalFeatureLogStream(arena.allocator(), current, log_binding.binding(foreign), .event) == null);
}
