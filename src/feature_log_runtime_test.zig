const std = @import("std");
const filesystem_sink = @import("adapters/filesystem/feature_log_sink.zig");
const runner_module = @import("application/feature_log_runner.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const prompt_log = @import("domain/sanitized_prompt_log.zig");
const log_retention = @import("domain/feature_log_retention.zig");
const log_policy = @import("domain/log_policy.zig");
const log_event_registry = @import("domain/log_event_registry.zig");
const log_limits = @import("domain/feature_log_limits.zig");
const telemetry = @import("domain/telemetry.zig");
const console_port = @import("ports/console_log_sink.zig");
const emergency_port = @import("ports/emergency_log_sink.zig");
const clock_port = @import("ports/trusted_log_clock.zig");
const sink_port = @import("ports/feature_log_sink.zig");
const build_retention = @import("actions/log/build_feature_log_retention_authorization.zig");
const retention_coordinator = @import("application/feature_log_retention_coordinator.zig");
const retention_runner = @import("application/feature_log_retention_runner.zig");
const transition_runner = @import("application/feature_log_policy_transition_runner.zig");
const finalization_runner = @import("application/feature_log_finalization_runner.zig");
const runtime_lifecycle = @import("application/feature_log_runtime_lifecycle.zig");
const action_set = @import("application/feature_log_actions.zig");
const acquire_lock = @import("actions/log/acquire_feature_log_stream_lock.zig");
const prune_segments = @import("actions/log/prune_feature_log_segments.zig");
const release_lock = @import("actions/log/release_feature_log_stream_lock.zig");
const recover_stream = @import("actions/log/recover_feature_log_stream.zig");
const create_segment = @import("actions/log/create_feature_log_segment.zig");
const rotate_segment = @import("actions/log/rotate_feature_log_segment.zig");
const append_record = @import("actions/log/append_feature_log_record.zig");
const close_stream = @import("actions/log/close_feature_log_stream.zig");
const cancelling = @import("test_fixtures/cancelling_io.zig");
const retention_store = @import("adapters/filesystem/feature_log_retention_store.zig");
const log_file = @import("adapters/filesystem/feature_log_file.zig");

fn childrenFor(
    sink: anytype,
    clock: clock_port.Clock,
    console: console_port.Sink,
    emergency: emergency_port.Sink,
) action_set.Set {
    return .{
        .acquire_lock = acquire_lock.Action{ .sink = sink.lockAcquirer() },
        .release_lock = release_lock.Action{ .sink = sink.lockReleaser() },
        .recover_stream = recover_stream.Action{ .sink = sink.streamRecoverer() },
        .create_segment = create_segment.Action{ .sink = sink.segmentCreator() },
        .rotate_segment = rotate_segment.Action{ .sink = sink.segmentRotator() },
        .append_record = append_record.Action{ .sink = sink.recordAppender() },
        .close_stream = close_stream.Action{ .sink = sink.streamCloser() },
        .read_clock = .{ .clock = clock },
        .write_console = .{ .sink = console },
        .emit_emergency = .{ .sink = emergency },
    };
}

test "runner barrier persists recovers and sequences feature events" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const binding_owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(binding_owner);
    const binding = log_binding.binding(binding_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = binding,
        .actions = childrenFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()),
    };
    const attributed: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"),
        .fact = .{
            .event_type = .task_started,
            .fields = .{ .task_id = telemetry.Identifier.validate("TASK-1").? },
        },
    };
    const first = runner.barrier().process(attributed);
    try std.testing.expect(first == .persisted);
    try std.testing.expectEqual(@as(u64, 1), first.persisted.sequence);
    try std.testing.expect(first.persisted.bytes_written > 0);
    try std.testing.expectEqual(@as(u64, 2), runner.event_state.?.next_sequence);
    const second = runner.process(attributed);
    try std.testing.expect(second == .persisted);
    try std.testing.expectEqual(@as(u64, 2), second.persisted.sequence);

    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, @import("domain/feature_log_format.zig").event_heading));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|EVENT-1|1|2026-08-30T10:15:30Z|") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|EVENT-2|2|2026-08-30T10:15:30Z|") != null);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, bytes, "|task.started|"));
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_count);
}

test "restart recovery truncates only an incomplete final row" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .event_type = .run_started } };
    try std.testing.expect(first_runner.process(fact) == .persisted);
    var file = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_write });
    const size = (try file.stat(io)).size;
    try file.writePositionalAll(io, "partial", size);
    file.close(io);
    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const outcome = second_runner.process(fact);
    try std.testing.expect(outcome == .persisted);
    try std.testing.expectEqual(@as(u64, 2), outcome.persisted.sequence);
    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "partial") == null);
}

test "restart recovery resumes after a durably closed tail" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .event_type = .run_started } };

    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(first_runner.process(fact) == .persisted);
    try std.testing.expect(first_runner.close(shortcode) == .dropped);

    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const outcome = second_runner.process(fact);
    try std.testing.expect(outcome == .persisted);
    try std.testing.expectEqual(@as(u64, 2), outcome.persisted.sequence);
    try std.testing.expectEqual(@as(u16, 2), outcome.persisted.segment_ordinal);

    var successor = try directory.dir.openFile(io, "0002.log", .{ .mode = .read_only });
    successor.close(io);
}

test "restart rejects an insecure segment permission instead of trusting its bytes" {
    if (!@hasDecl(std.Io.File.Permissions, "fromMode")) return;
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .event_type = .run_started } };
    try std.testing.expect(first_runner.process(fact) == .persisted);
    var file = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_write });
    try file.setPermissions(io, std.Io.File.Permissions.fromMode(0o644));
    file.close(io);
    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, second_runner.process(fact).blocked);
}

test "restart recovery leaves regular files the engine never names alone and rejects other entries" {
    const io = std.testing.io;
    const Case = enum { strays_only, symlinked_entry, nested_directory, misplaced_segment, symlinked_run_entry, symlinked_sibling_entry, nested_sibling_directory };
    for (std.enums.values(Case)) |case| {
        var root = std.testing.tmpDir(.{ .iterate = true });
        defer root.cleanup();
        try root.dir.createDir(io, "LOGBIND-0", std.Io.File.Permissions.fromMode(0o700));
        try root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
        var binding_directory = try root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
        defer binding_directory.close(io);
        const candidate = bindingCandidate();
        const owner = try log_binding.createValidated(std.testing.allocator, candidate);
        defer log_binding.deinitOwner(owner);
        const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
        const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .event_type = .run_started } };

        var first_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, binding_directory, candidate);
        defer first_sink.deinit();
        var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
        try std.testing.expect(first_runner.process(fact) == .persisted);
        try std.testing.expect(first_runner.close(shortcode) == .dropped);

        // Stray files in the run directory, this binding and a sibling binding.
        for ([_][]const u8{ ".DS_Store", "LOGBIND-1/Thumbs.db", "LOGBIND-0/._0001.log" }) |path| {
            try root.dir.writeFile(io, .{ .sub_path = path, .data = "stray" });
        }
        switch (case) {
            .strays_only => {},
            .symlinked_entry => try root.dir.symLink(io, "0001.log", "LOGBIND-1/desktop.ini", .{}),
            .nested_directory => try root.dir.createDir(io, "LOGBIND-1/nested", .default_dir),
            .misplaced_segment => try root.dir.copyFile("LOGBIND-1/0001.log", root.dir, "0001.log", io, .{}),
            .symlinked_run_entry => try root.dir.symLink(io, "LOGBIND-1/0001.log", "desktop.ini", .{}),
            .symlinked_sibling_entry => try root.dir.symLink(io, "../LOGBIND-1/0001.log", "LOGBIND-0/desktop.ini", .{}),
            .nested_sibling_directory => try root.dir.createDir(io, "LOGBIND-0/nested", .default_dir),
        }

        var second_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, binding_directory, candidate);
        defer second_sink.deinit();
        var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
        const outcome = second_runner.process(fact);
        if (case != .strays_only) {
            try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
            continue;
        }
        try std.testing.expect(outcome == .persisted);
        try std.testing.expectEqual(@as(u64, 2), outcome.persisted.sequence);
        try std.testing.expectEqual(@as(u16, 2), outcome.persisted.segment_ordinal);
        const stray = try root.dir.readFileAlloc(io, "LOGBIND-1/Thumbs.db", std.testing.allocator, .limited(16));
        defer std.testing.allocator.free(stray);
        try std.testing.expectEqualStrings("stray", stray);
    }
}

test "stream lock acquisition rejects a symbolic link" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    try directory.dir.writeFile(io, .{ .sub_path = "lock-target", .data = "unchanged" });
    try directory.dir.symLink(io, "lock-target", ".stream.lock", .{});
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()) };
    const outcome = runner.process(.{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_started } });
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
    const target = try directory.dir.readFileAlloc(io, "lock-target", std.testing.allocator, .limited(32));
    defer std.testing.allocator.free(target);
    try std.testing.expectEqualStrings("unchanged", target);
}

test "threshold drop performs no clock sink or identity work" {
    const candidate = bindingCandidate();
    const binding_owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(binding_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .fatal, .alias_evidence = .none },
        .console = false,
    };
    var rejecting_sink: RejectingSink = .{};
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(binding_owner),
        .actions = childrenFor(&rejecting_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const result = runner.process(.{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .event_type = .run_started },
    });
    try std.testing.expect(result == .dropped);
    try std.testing.expectEqual(@as(usize, 0), clock.calls);
    try std.testing.expectEqual(@as(usize, 0), rejecting_sink.calls);
}

test "debug captures response code content without explicit prompt selectors" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(owner),
        .actions = childrenFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()),
    };
    const outcome = runner.processPrompt(.{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("PLAN"),
        .attempt = 70_000,
        .request_id = telemetry.Identifier.validate("REQ-1").?,
        .route_id = telemetry.Identifier.validate("ROUTE-1").?,
        .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
        .fragment_id = telemetry.Identifier.validate("FRAG-1").?,
        .direction = .response,
        .body_class = .code_body,
        .content = "sanitized",
        .retained_bytes = 9,
        .truncated = false,
        .redacted = true,
    });
    try std.testing.expect(outcome == .persisted);
    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, @import("domain/feature_log_format.zig").prompt_heading));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|2026-08-30T10:15:30Z|") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|PLAN|") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|70000|") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|sanitized|9|false|true|") != null);
}

test "production capture resolves the active lifecycle and persists complete debug exchanges" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var events = std.testing.tmpDir(.{ .iterate = true });
    defer events.cleanup();
    var prompts = std.testing.tmpDir(.{ .iterate = true });
    defer prompts.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(a, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var sink = filesystem_sink.Adapter.initForTest(io, events.dir, candidate);
    sink.prompt_directory = prompts.dir;
    sink.prompt_run_directory = prompts.dir;
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{ .allocator = a, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    const exchange = @import("application/model_exchange_capture.zig");
    // Production constructs the barrier before workflow feature activation.
    var capture: exchange.Capture = .{ .allocator = a, .logs = lifecycle.barrier() };
    defer capture.deinit();
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    try std.testing.expectEqual(.ok, lifecycle.activate(runner.childBindings(), shortcode));
    capture.begin(.{ .workflow = shortcode, .workflow_id = .{ .bytes = "example" }, .action = .{ .bytes = "invoke-model" }, .node = .{ .bytes = "invoke" }, .operation = .{ .bytes = "generate" }, .model_slot = .{ .bytes = "generation" }, .origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 2 } } });
    defer capture.end();
    const padding = try a.alloc(u8, 11000);
    defer a.free(padding);
    @memset(padding, 'x');
    const request = try std.mem.concat(a, u8, &.{ "first prompt credential-value ", padding, " final prompt text" });
    defer a.free(request);
    try std.testing.expectEqual(.recorded, capture.port().capture(.request, .{ .provider_body = request }, &.{"credential-value"}));
    try std.testing.expectEqual(.recorded, capture.port().capture(.response, .{ .provider_body = "malformed response credential-value {" }, &.{"credential-value"}));
    try std.testing.expect(runner.close(shortcode) != .blocked);
    const logged = try prompts.dir.readFileAlloc(io, "0001.log", a, .limited(log_limits.max_segment_bytes));
    defer a.free(logged);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, logged, "|model.prompt_fragment|"));
    try std.testing.expect(std.mem.indexOf(u8, logged, "first prompt [REDACTED_CREDENTIAL]") != null);
    try std.testing.expect(std.mem.indexOf(u8, logged, "final prompt text") != null);
    try std.testing.expect(std.mem.indexOf(u8, logged, "malformed response [REDACTED_CREDENTIAL] {") != null);
    try std.testing.expect(std.mem.indexOf(u8, logged, "credential-value") == null);
    try std.testing.expect(std.mem.indexOf(u8, logged, "|request-3|generate|generation|") != null);
    try std.testing.expect(std.mem.indexOf(u8, logged, "|request|complete_body|") != null);
    try std.testing.expect(std.mem.indexOf(u8, logged, "|response|complete_body|") != null);
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_count);
    // A retired active logger cannot silently discard future bodies.
    try std.testing.expectEqual(.blocked, capture.port().capture(.request, .{ .provider_body = "next" }, &.{}));
}

test "info logging filters complete prompt bodies before effects" {
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .info, .alias_evidence = .none },
        .console = false,
    };
    var sink: RejectingSink = .{};
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(owner),
        .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    try std.testing.expect(runner.processPrompt(.{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("PLAN"),
        .attempt = 1,
        .request_id = telemetry.Identifier.validate("REQ-1").?,
        .route_id = telemetry.Identifier.validate("ROUTE-1").?,
        .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
        .fragment_id = telemetry.Identifier.validate("FRAG-1").?,
        .direction = .request,
        .body_class = .complete_body,
        .content = "sanitized",
        .retained_bytes = 9,
        .truncated = false,
        .redacted = true,
    }) == .dropped);
    try std.testing.expectEqual(@as(usize, 0), clock.calls);
    try std.testing.expectEqual(@as(usize, 0), sink.calls);
}

test "fault barriers distinguish lock recovery flush console rotation and retention failures" {
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_completed, .fields = .{ .outcome = .completed } } };

    inline for (.{ Fault.lock, Fault.recovery, Fault.flush, Fault.console, Fault.rotation }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{ .console_failure = fault == .console };
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (fault == .rotation) runner.event_state = .{
            .segment_ordinal = 1,
            .next_sequence = 1,
            .segment_bytes = log_limits.max_segment_bytes - 1,
            .segment_count = 1,
            .total_segment_count = 1,
            .records_since_flush = 0,
            .last_flush_monotonic_ms = 0,
        };
        const outcome = runner.process(fact);
        try std.testing.expect(outcome == .blocked);
        try std.testing.expectEqual(switch (fault) {
            .lock => log_stream.FailureCode.LOG_LOCK_TIMEOUT,
            .flush => log_stream.FailureCode.LOG_FLUSH_FAILURE,
            else => log_stream.FailureCode.LOG_SINK_FAILURE,
        }, outcome.blocked);
        try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    }

    const historical_candidate: log_binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = candidate.feature_id,
    };
    const historical_owner = try log_binding.createValidated(std.testing.allocator, historical_candidate);
    defer log_binding.deinitOwner(historical_owner);
    var retention_clock: FakeClock = .{};
    var retention_sink: FaultSink = .{ .fault = .retention };
    var retention_execution: retention_runner.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .current = log_binding.binding(owner),
        .historical = log_binding.binding(historical_owner),
        .target_stream = .event,
        .authorize_action = .{ .clock = retention_clock.port() },
        .acquire_action = .{ .sink = retention_sink.lockAcquirer() },
        .prune_action = prune_segments.Action{ .sink = retention_sink.segmentPruner() },
        .release_action = .{ .sink = retention_sink.lockReleaser() },
    };
    defer retention_execution.deinit();
    const retention = retention_coordinator.run(retention_execution.childBindings());
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, retention.blocked);
}

test "same-run policy transition closes the old binding and continues sequence and total budget" {
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{ .iterate = true });
    defer root.cleanup();
    var prompt_root = std.testing.tmpDir(.{ .iterate = true });
    defer prompt_root.cleanup();
    try root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
    try root.dir.createDir(io, "LOGBIND-2", std.Io.File.Permissions.fromMode(0o700));
    try prompt_root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
    try prompt_root.dir.createDir(io, "LOGBIND-2", std.Io.File.Permissions.fromMode(0o700));
    var old_directory = try root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
    defer old_directory.close(io);
    var next_directory = try root.dir.openDir(io, "LOGBIND-2", .{ .iterate = true });
    defer next_directory.close(io);
    var old_prompt_directory = try prompt_root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
    defer old_prompt_directory.close(io);
    var next_prompt_directory = try prompt_root.dir.openDir(io, "LOGBIND-2", .{ .iterate = true });
    defer next_prompt_directory.close(io);
    const old_candidate = bindingCandidate();
    const next_candidate: log_binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-2").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-2").?,
        .run_id = old_candidate.run_id,
        .feature_id = old_candidate.feature_id,
    };
    const old_owner = try log_binding.createValidated(std.testing.allocator, old_candidate);
    defer log_binding.deinitOwner(old_owner);
    const next_owner = try log_binding.createValidated(std.testing.allocator, next_candidate);
    defer log_binding.deinitOwner(next_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var old_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, old_directory, old_candidate);
    old_sink.prompt_run_directory = prompt_root.dir;
    old_sink.prompt_directory = old_prompt_directory;
    defer old_sink.deinit();
    var old_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .actions = childrenFor(&old_sink, clock.port(), outputs.console(), outputs.emergency()) };
    var next_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, next_directory, next_candidate);
    next_sink.prompt_run_directory = prompt_root.dir;
    next_sink.prompt_directory = next_prompt_directory;
    defer next_sink.deinit();
    var next_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(next_owner), .actions = childrenFor(&next_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_started } };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expect(lifecycle.activate(old_runner.childBindings(), fact.workflow_shortcode) == .ok);
    try std.testing.expect(old_runner.prompt_state != null);
    try std.testing.expect(lifecycle.activate(next_runner.childBindings(), fact.workflow_shortcode) == .invalid);
    try std.testing.expect(lifecycle.barrier().process(fact) == .persisted);
    try std.testing.expectEqual(@as(u64, 2), old_runner.event_state.?.next_sequence);
    var transition_execution: transition_runner.Runner = .{
        .current = &old_runner,
        .next = &next_runner,
        .shortcode = fact.workflow_shortcode,
    };
    try std.testing.expect(lifecycle.transition(transition_execution.childBindings()) == .ok);
    try std.testing.expect(next_runner.prompt_state != null);
    const outcome = lifecycle.barrier().process(fact);
    try std.testing.expect(outcome == .persisted);
    try std.testing.expectEqual(@as(u64, 3), next_runner.event_state.?.next_sequence);
    try std.testing.expectEqual(@as(u8, 2), next_runner.event_state.?.total_segment_count);

    const historical_candidate: log_binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = next_candidate.feature_id,
    };
    const historical_owner = try log_binding.createValidated(std.testing.allocator, historical_candidate);
    defer log_binding.deinitOwner(historical_owner);
    var retention_clock: FakeClock = .{};
    var retention_sink: FaultSink = .{ .fault = .retention };
    var retention_execution: retention_runner.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .current = log_binding.binding(next_owner),
        .historical = log_binding.binding(historical_owner),
        .target_stream = .event,
        .authorize_action = .{ .clock = retention_clock.port() },
        .acquire_action = .{ .sink = retention_sink.lockAcquirer() },
        .prune_action = prune_segments.Action{ .sink = retention_sink.segmentPruner() },
        .release_action = .{ .sink = retention_sink.lockReleaser() },
    };
    defer retention_execution.deinit();
    const retention = lifecycle.retainHistorical(retention_execution.childBindings(), fact.workflow_shortcode);
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, retention.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    var finalization_execution: finalization_runner.Runner = .{
        .target = &next_runner,
        .mode = .active,
        .shortcode = fact.workflow_shortcode,
    };
    try std.testing.expect(lifecycle.finalizeActive(finalization_execution.childBindings()) == .ok);
    try std.testing.expect(next_runner.retired);
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
}

test "retention authorization derives its single-use cutoff from trusted policy and time" {
    const current_candidate = bindingCandidate();
    const historical_candidate: log_binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = current_candidate.feature_id,
    };
    const current_owner = try log_binding.createValidated(std.testing.allocator, current_candidate);
    defer log_binding.deinitOwner(current_owner);
    const historical_owner = try log_binding.createValidated(std.testing.allocator, historical_candidate);
    defer log_binding.deinitOwner(historical_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var clock: FakeClock = .{};
    const authorization = try (build_retention.Action{ .clock = clock.port() }).execute(
        std.testing.allocator,
        &policy,
        log_binding.binding(current_owner),
        log_binding.binding(historical_owner),
        .event,
    );
    defer log_retention.deinit(authorization);
    const authorized = log_retention.consume(
        authorization,
        log_binding.binding(historical_owner),
    ).?;
    try std.testing.expectEqual(
        @as(u64, 1_788_087_330_000) - log_limits.retention_period_ms,
        authorized.cutoff_unix_ms,
    );
    try std.testing.expect(log_retention.consume(
        authorization,
        log_binding.binding(historical_owner),
    ) == null);

    var invalid_policy = policy;
    invalid_policy.retention_days -= 1;
    try std.testing.expectError(
        error.FeatureLogRetentionAuthorizationInvalid,
        (build_retention.Action{ .clock = clock.port() }).execute(
            std.testing.allocator,
            &invalid_policy,
            log_binding.binding(current_owner),
            log_binding.binding(historical_owner),
            .event,
        ),
    );
}

test "historical finalization recovers and durably closes one active tail" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    var prompt_directory = std.testing.tmpDir(.{ .iterate = true });
    defer prompt_directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    first_sink.prompt_run_directory = prompt_directory.dir;
    first_sink.prompt_directory = prompt_directory.dir;
    var first_runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(owner),
        .actions = childrenFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    try std.testing.expect(first_runner.process(.{
        .workflow_shortcode = shortcode,
        .fact = .{ .event_type = .run_started },
    }) == .persisted);

    var recovered_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    recovered_sink.prompt_run_directory = prompt_directory.dir;
    recovered_sink.prompt_directory = prompt_directory.dir;
    var recovered_runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(owner),
        .actions = childrenFor(&recovered_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    var finalization_execution: finalization_runner.Runner = .{
        .target = &recovered_runner,
        .mode = .historical,
        .shortcode = shortcode,
    };
    try std.testing.expect(lifecycle.finalizeHistorical(finalization_execution.childBindings()) == .ok);
    try std.testing.expect(recovered_runner.retired);
    const bytes = try directory.dir.readFileAlloc(
        io,
        "0001.log",
        std.testing.allocator,
        .limited(log_limits.max_segment_bytes),
    );
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "segment_trailer|") != null);
}

test "failed successor preparation removes the active observer" {
    const old_candidate = bindingCandidate();
    const next_candidate: log_binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-2").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-2").?,
        .run_id = old_candidate.run_id,
        .feature_id = old_candidate.feature_id,
    };
    const old_owner = try log_binding.createValidated(std.testing.allocator, old_candidate);
    defer log_binding.deinitOwner(old_owner);
    const next_owner = try log_binding.createValidated(std.testing.allocator, next_candidate);
    defer log_binding.deinitOwner(next_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var old_sink: FaultSink = .{ .fault = .none };
    var next_sink: FaultSink = .{ .fault = .recovery };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var old_runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(old_owner),
        .actions = childrenFor(&old_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    var next_runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(next_owner),
        .actions = childrenFor(&next_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    const fact: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = shortcode,
        .fact = .{ .event_type = .run_started },
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.activate(old_runner.childBindings(), shortcode) == .ok);
    var transition_execution: transition_runner.Runner = .{
        .current = &old_runner,
        .next = &next_runner,
        .shortcode = shortcode,
    };
    try std.testing.expect(lifecycle.transition(transition_execution.childBindings()) == .blocked);
    try std.testing.expect(old_runner.retired);
    try std.testing.expect(!next_sink.held);
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
}

test "failed active finalization releases the lock and removes the observer" {
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var sink: FaultSink = .{ .fault = .flush };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(owner),
        .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    const fact: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = shortcode,
        .fact = .{ .event_type = .run_started },
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.activate(runner.childBindings(), shortcode) == .ok);
    var finalization_execution: finalization_runner.Runner = .{
        .target = &runner,
        .mode = .active,
        .shortcode = shortcode,
    };
    const outcome = lifecycle.finalizeActive(finalization_execution.childBindings());
    try std.testing.expectEqual(log_stream.FailureCode.LOG_FLUSH_FAILURE, outcome.blocked);
    try std.testing.expect(!sink.held);
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
}

test "sink acquisition failure reports once and blocks" {
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var rejecting_sink: RejectingSink = .{};
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(owner),
        .actions = childrenFor(&rejecting_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const outcome = runner.process(.{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .event_type = .run_started },
    });
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), rejecting_sink.calls);
    try std.testing.expect(runner.event_state == null);
}

test "emergency failure preserves the original logging failure without retry" {
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
    };
    var rejecting_sink: RejectingSink = .{};
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{ .emergency_failure = true };
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = log_binding.binding(owner),
        .actions = childrenFor(&rejecting_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const outcome = runner.process(.{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .event_type = .run_started },
    });
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_calls);
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), rejecting_sink.calls);
    try std.testing.expect(runner.event_state == null);
}

fn bindingCandidate() log_binding.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = @import("domain/feature_identity.zig").FeatureId.parse("F0002").?,
    };
}

const FakeClock = struct {
    calls: usize = 0,
    fn port(self: *FakeClock) clock_port.Clock {
        return .{ .context = self, .now_fn = now };
    }
    fn now(context: *anyopaque) clock_port.Error!log_stream.ClockReading {
        const self: *FakeClock = @ptrCast(@alignCast(context));
        self.calls += 1;
        return .{
            .occurred_at_utc = "2026-08-30T10:15:30Z".*,
            .unix_ms = 1_788_087_330_000,
            .monotonic_ms = 1000 + self.calls,
        };
    }
};
const FakeOutputs = struct {
    emergency_count: usize = 0,
    emergency_calls: usize = 0,
    emergency_failure: bool = false,
    console_failure: bool = false,
    /// The console write observes a cancellation, which is no console failure.
    console_cancel: bool = false,
    fn console(self: *FakeOutputs) console_port.Sink {
        return .{ .context = self, .write_fn = writeConsole };
    }
    fn emergency(self: *FakeOutputs) emergency_port.Sink {
        return .{ .context = self, .write_fn = writeEmergency };
    }
    fn writeConsole(context: *anyopaque, _: []const u8) console_port.Error!void {
        const self: *FakeOutputs = @ptrCast(@alignCast(context));
        if (self.console_cancel) return error.Cancelled;
        if (self.console_failure) return error.ConsoleWriteFailure;
    }
    fn writeEmergency(context: *anyopaque, _: []const u8) emergency_port.Error!void {
        const self: *FakeOutputs = @ptrCast(@alignCast(context));
        self.emergency_calls += 1;
        if (self.emergency_failure) return error.EmergencyWriteFailure;
        self.emergency_count += 1;
    }
};

/// A `cancel_*` fault is the sink observing a cancellation at that operation, which is no sink fault.
/// The `_release_fails` faults also leave the lock unheld, so releasing it fails after the cancelled step.
const Fault = enum { none, lock, recovery, flush, console, rotation, retention, cancel_lock, cancel_recovery, cancel_rotation, cancel_append, cancel_close, cancel_retention, cancel_append_release_fails, cancel_close_release_fails };
const FaultSink = struct {
    fault: Fault,
    held: bool = false,
    fn lockAcquirer(self: *FaultSink) sink_port.LockAcquirer {
        return .{ .context = self, .acquire_fn = faultAcquire };
    }
    fn streamRecoverer(self: *FaultSink) sink_port.StreamRecoverer {
        return .{ .context = self, .recover_fn = faultRecover };
    }
    fn segmentCreator(self: *FaultSink) sink_port.SegmentCreator {
        return .{ .context = self, .create_fn = faultCreate };
    }
    fn segmentRotator(self: *FaultSink) sink_port.SegmentRotator {
        return .{ .context = self, .rotate_fn = faultRotate };
    }
    fn streamCloser(self: *FaultSink) sink_port.StreamCloser {
        return .{ .context = self, .close_fn = faultClose };
    }
    fn recordAppender(self: *FaultSink) sink_port.RecordAppender {
        return .{ .context = self, .append_fn = faultAppend };
    }
    fn segmentPruner(self: *FaultSink) sink_port.SegmentPruner {
        return .{ .context = self, .prune_fn = faultPrune };
    }
    fn lockReleaser(self: *FaultSink) sink_port.LockReleaser {
        return .{ .context = self, .release_fn = faultRelease };
    }
};
fn faultAcquire(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u16) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .lock) return error.LockUnavailable;
    if (self.fault == .cancel_lock) return error.Cancelled;
    self.held = true;
}
fn faultRecover(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: []const u8, _: std.mem.Allocator) @import("ports/feature_log_sink.zig").Error!log_stream.Recovery {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .recovery) return error.CorruptStream;
    if (self.fault == .cancel_recovery) return error.Cancelled;
    return .{ .empty = .{ .next_segment_ordinal = 1, .next_sequence = 1, .total_segment_count = 0 } };
}
fn faultCreate(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, ordinal: u16, seed: log_stream.StreamSeed, heading: []const u8, header: []const u8) @import("ports/feature_log_sink.zig").Error!log_stream.StreamState {
    return .{ .segment_ordinal = ordinal, .next_sequence = seed.next_sequence, .segment_bytes = heading.len + header.len, .segment_count = 1, .total_segment_count = seed.total_segment_count + 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
}
fn faultRotate(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, state: log_stream.StreamState, _: []const u8, _: []const u8, _: []const u8) @import("ports/feature_log_sink.zig").Error!log_stream.StreamState {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .rotation) return error.SinkFailure;
    if (self.fault == .cancel_rotation) return error.Cancelled;
    var next = state;
    next.segment_ordinal += 1;
    next.segment_count += 1;
    next.total_segment_count += 1;
    next.segment_bytes = 0;
    return next;
}
fn faultClose(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: log_stream.StreamState, _: []const u8) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .flush) return error.FlushFailure;
    if (self.fault == .cancel_close) return error.Cancelled;
    if (self.fault == .cancel_close_release_fails) {
        self.held = false;
        return error.Cancelled;
    }
}
fn faultAppend(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, state: log_stream.StreamState, row: []const u8, flush: bool) @import("ports/feature_log_sink.zig").Error!log_stream.PersistedEvidence {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .flush and flush) return error.FlushFailure;
    if (self.fault == .cancel_append) return error.Cancelled;
    if (self.fault == .cancel_append_release_fails) {
        self.held = false;
        return error.Cancelled;
    }
    return .{ .segment_ordinal = state.segment_ordinal, .sequence = state.next_sequence, .bytes_written = row.len, .flushed = flush };
}
fn faultPrune(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u64) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .retention) return error.SinkFailure;
    if (self.fault == .cancel_retention) return error.Cancelled;
}
fn faultRelease(context: *anyopaque) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (!self.held) return error.ReleaseFailure;
    self.held = false;
}
const RejectingSink = struct {
    calls: usize = 0,
    fn lockAcquirer(self: *RejectingSink) sink_port.LockAcquirer {
        return .{ .context = self, .acquire_fn = rejectAcquire };
    }
    fn streamRecoverer(self: *RejectingSink) sink_port.StreamRecoverer {
        return .{ .context = self, .recover_fn = rejectRecover };
    }
    fn segmentCreator(self: *RejectingSink) sink_port.SegmentCreator {
        return .{ .context = self, .create_fn = rejectCreate };
    }
    fn segmentRotator(self: *RejectingSink) sink_port.SegmentRotator {
        return .{ .context = self, .rotate_fn = rejectRotate };
    }
    fn streamCloser(self: *RejectingSink) sink_port.StreamCloser {
        return .{ .context = self, .close_fn = rejectClose };
    }
    fn recordAppender(self: *RejectingSink) sink_port.RecordAppender {
        return .{ .context = self, .append_fn = rejectAppend };
    }
    fn segmentPruner(self: *RejectingSink) sink_port.SegmentPruner {
        return .{ .context = self, .prune_fn = rejectPrune };
    }
    fn lockReleaser(self: *RejectingSink) sink_port.LockReleaser {
        return .{ .context = self, .release_fn = rejectRelease };
    }
};
fn rejectAcquire(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u16) @import("ports/feature_log_sink.zig").Error!void {
    const self: *RejectingSink = @ptrCast(@alignCast(context));
    self.calls += 1;
    return error.SinkFailure;
}
fn rejectRecover(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: []const u8, _: std.mem.Allocator) @import("ports/feature_log_sink.zig").Error!log_stream.Recovery {
    return error.SinkFailure;
}
fn rejectCreate(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u16, _: log_stream.StreamSeed, _: []const u8, _: []const u8) @import("ports/feature_log_sink.zig").Error!log_stream.StreamState {
    return error.SinkFailure;
}
fn rejectRotate(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: log_stream.StreamState, _: []const u8, _: []const u8, _: []const u8) @import("ports/feature_log_sink.zig").Error!log_stream.StreamState {
    return error.SinkFailure;
}
fn rejectClose(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: log_stream.StreamState, _: []const u8) @import("ports/feature_log_sink.zig").Error!void {
    return error.SinkFailure;
}
fn rejectAppend(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: log_stream.StreamState, _: []const u8, _: bool) @import("ports/feature_log_sink.zig").Error!log_stream.PersistedEvidence {
    return error.SinkFailure;
}
fn rejectPrune(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u64) @import("ports/feature_log_sink.zig").Error!void {
    return error.SinkFailure;
}
fn rejectRelease(_: *anyopaque) @import("ports/feature_log_sink.zig").Error!void {
    return error.ReleaseFailure;
}

test "production event projection uses closed facts and propagates every barrier failure" {
    const capture = @import("application/workflow_event_capture.zig");
    const Spy = struct {
        count: usize = 0,
        blocked: bool = false,
        expect_capture: bool = false,
        fn process(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
            const self: *@This() = @ptrCast(@alignCast(context));
            _ = log_event_registry.validateFact(fact.fact) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
            if (self.expect_capture) {
                const code = fact.fact.fields.diagnostic_code orelse return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
                if (!std.mem.eql(u8, code.bytes, "MODEL_CAPTURE_LINEAGE_FAILURE_MISSING_SOURCE")) return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
                if (fact.fact.event_type == .run_blocked) {
                    const correlation = fact.fact.correlation_id orelse return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
                    if (!std.mem.eql(u8, correlation.bytes, "request-7-inference-1") or fact.fact.attempt != 1) return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
                }
            }
            self.count += 1;
            return if (self.blocked) .{ .blocked = .LOG_FLUSH_FAILURE } else .dropped;
        }
    };
    var spy: Spy = .{};
    const events: capture.Capture = .{ .barrier = .{ .context = &spy, .process_fn = Spy.process }, .shortcode = try telemetry.WorkflowShortcode.parse("OTHR") };
    const node: @import("domain/workflow.zig").WorkflowStepId = .{ .bytes = "check" };
    for ([_]bool{ false, true }) |blocked| {
        spy.blocked = blocked;
        const expected: ?log_stream.Stop = if (blocked) .{ .blocked = .LOG_FLUSH_FAILURE } else null;
        try std.testing.expectEqual(expected, events.emit(.{ .event_type = .run_started }));
        try std.testing.expectEqual(expected, events.action(node, null, null, null));
        for (std.enums.values(@import("domain/workflow.zig").OutcomeTag)) |status| {
            try std.testing.expectEqual(expected, events.action(node, .{ .outcome = status }, null, null));
            if (status != .more) try std.testing.expectEqual(expected, events.terminal(.{ .execution = status }));
        }
        try std.testing.expectEqual(expected, events.action(node, .{ .rejected = .{ .authority = .kernel_stage } }, null, null));
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SERIALIZATION_FAILURE }, events.terminal(.{ .execution = .more }).?);
        try std.testing.expectEqual(expected, events.validation(node, .ok, null, null));
        try std.testing.expectEqual(expected, events.validation(node, .invalid, "WRONG_SHAPE", null));
        try std.testing.expectEqual(expected, events.repair(node, .repair_requested, .ok, null));
        try std.testing.expectEqual(expected, events.repair(node, .repair_applied, .ok, null));
        try std.testing.expectEqual(expected, events.repair(node, .repair_rejected, .invalid, "REPAIR_RECURRING"));
        try std.testing.expectEqual(expected, events.retryAttempt(node, 2, false));
        try std.testing.expectEqual(expected, events.retryAttempt(node, 3, true));
        try std.testing.expectEqual(expected, events.emit(.{ .event_type = .publication_prepared, .fields = .{ .outcome = .needs_user } }));
        spy.expect_capture = true;
        const rejected: @import("domain/workflow_execution.zig").Rejection = .{ .model_capture = .{ .code = .LOG_SERIALIZATION_FAILURE, .stage = .lineage, .cause = .{ .lineage = .missing_source }, .origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } }, .direction = .request } };
        try std.testing.expectEqual(expected, events.action(node, .{ .rejected = rejected }, null, null));
        try std.testing.expectEqual(expected, events.terminal(.{ .execution_rejected = rejected }));
        spy.expect_capture = false;
    }
    try std.testing.expect(spy.count > 0);
}

const RetentionSpy = struct {
    const Step = enum { authorize, resolve, acquire, prune, release };
    const bindings = @import("application/feature_log_retention_child_bindings.zig");
    failing: ?Step = null,
    also_failing: ?Step = null,
    /// The step that observes a cancellation; only a step that touches the sink can.
    cancelled: ?Step = null,
    calls: [5]Step = undefined,
    count: usize = 0,

    fn record(self: *RetentionSpy, which: Step) ?log_stream.FailureCode {
        self.calls[self.count] = which;
        self.count += 1;
        if (self.failing == which or (self.also_failing == which)) return if (which == .release) .LOG_RELEASE_FAILURE else .LOG_SINK_FAILURE;
        return null;
    }
    fn step(context: *anyopaque, which: Step) bindings.StepOutcome {
        const self: *RetentionSpy = @ptrCast(@alignCast(context));
        return if (self.record(which)) |code| .{ .failed = code } else .ok;
    }
    fn sinkStep(context: *anyopaque, which: Step) bindings.SinkOutcome {
        const self: *RetentionSpy = @ptrCast(@alignCast(context));
        const failure = self.record(which);
        if (self.cancelled == which) return .cancelled;
        return if (failure) |code| .{ .failed = code } else .ok;
    }
    fn authorize(context: *anyopaque) bindings.StepOutcome {
        return step(context, .authorize);
    }
    fn resolve(context: *anyopaque) bindings.StepOutcome {
        return step(context, .resolve);
    }
    fn acquire(context: *anyopaque) bindings.SinkOutcome {
        return sinkStep(context, .acquire);
    }
    fn prune(context: *anyopaque) bindings.SinkOutcome {
        return sinkStep(context, .prune);
    }
    fn release(context: *anyopaque) bindings.StepOutcome {
        return step(context, .release);
    }
    const vtable: @import("application/feature_log_retention_child_bindings.zig").ChildBindings.VTable = .{
        .authorize = authorize,
        .resolve_stream = resolve,
        .acquire = acquire,
        .prune = prune,
        .release = release,
    };
};

test "retention authorizes before resolving and locking, and releases after any prune outcome" {
    const Step = RetentionSpy.Step;
    for ([_]struct { ?Step, []const Step }{
        .{ null, &.{ .authorize, .resolve, .acquire, .prune, .release } },
        .{ .authorize, &.{.authorize} },
        .{ .resolve, &.{ .authorize, .resolve } },
        .{ .acquire, &.{ .authorize, .resolve, .acquire } },
        .{ .prune, &.{ .authorize, .resolve, .acquire, .prune, .release } },
        .{ .release, &.{ .authorize, .resolve, .acquire, .prune, .release } },
    }) |case| {
        var spy: RetentionSpy = .{ .failing = case[0] };
        const outcome = retention_coordinator.run(.{ .context = &spy, .vtable = &RetentionSpy.vtable });
        try std.testing.expectEqualSlices(Step, case[1], spy.calls[0..spy.count]);
        if (case[0] == null) try std.testing.expect(outcome == .ok) else try std.testing.expectEqual(if (case[0] == .release) log_stream.FailureCode.LOG_RELEASE_FAILURE else .LOG_SINK_FAILURE, outcome.blocked);
    }
    // Release is still attempted after a failed prune, and the prune failure is
    // the reported cause.
    var both: RetentionSpy = .{ .failing = .prune, .also_failing = .release };
    const outcome = retention_coordinator.run(.{ .context = &both, .vtable = &RetentionSpy.vtable });
    try std.testing.expectEqualSlices(Step, &.{ .authorize, .resolve, .acquire, .prune, .release }, both.calls[0..both.count]);
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
}

test "cancellation under the retention lock is a cancellation and still releases the lock" {
    const Step = RetentionSpy.Step;
    // A cancelled acquisition ends the run of steps there; a cancelled prune still releases. Neither is a logging failure.
    for ([_]struct { Step, []const Step }{
        .{ .acquire, &.{ .authorize, .resolve, .acquire } },
        .{ .prune, &.{ .authorize, .resolve, .acquire, .prune, .release } },
    }) |case| {
        var spy: RetentionSpy = .{ .cancelled = case[0] };
        try std.testing.expect(retention_coordinator.run(.{ .context = &spy, .vtable = &RetentionSpy.vtable }) == .cancelled);
        try std.testing.expectEqualSlices(Step, case[1], spy.calls[0..spy.count]);
    }
    // The cancelled prune is the cause, and a release that fails after it does not replace it.
    var both: RetentionSpy = .{ .cancelled = .prune, .failing = .release };
    try std.testing.expect(retention_coordinator.run(.{ .context = &both, .vtable = &RetentionSpy.vtable }) == .cancelled);
    // The same steps failing as sink faults stay logging failures.
    var failing: RetentionSpy = .{ .failing = .acquire };
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, retention_coordinator.run(.{ .context = &failing, .vtable = &RetentionSpy.vtable }).blocked);
}

test "cancellation under the feature log lock is a cancellation: no emergency line, lock released, runner reusable" {
    const owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_started } };
    // The lock, recovery, rotation and append are four sink operations; none of them reports a logging failure.
    inline for (.{ Fault.cancel_lock, Fault.cancel_recovery, Fault.cancel_rotation, Fault.cancel_append }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (fault == .cancel_rotation or fault == .cancel_append) runner.event_state = .{
            .segment_ordinal = 1,
            .next_sequence = 1,
            .segment_bytes = if (fault == .cancel_rotation) log_limits.max_segment_bytes - 1 else 0,
            .segment_count = 1,
            .total_segment_count = 1,
            .records_since_flush = 0,
            .last_flush_monotonic_ms = 0,
        };
        try std.testing.expect(runner.process(fact) == .cancelled);
        try std.testing.expect(!sink.held);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
        // Nothing was retired or advanced: once the sink stops cancelling, the same fact persists.
        sink.fault = .none;
        try std.testing.expect(runner.process(fact) == .persisted);
    }
}

test "a lock that cannot be released after a cancelled step is a logging failure of its own" {
    const owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .event_type = .run_started } };
    inline for (.{ Fault.cancel_append_release_fails, Fault.cancel_close_release_fails }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        const outcome = if (fault == .cancel_append_release_fails) runner.process(fact) else close: {
            runner.event_state = .{ .segment_ordinal = 1, .next_sequence = 1, .segment_bytes = 0, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
            break :close runner.close(shortcode);
        };
        // The release failure outranks the cancellation before it, and is reported once like any logging failure.
        try std.testing.expectEqual(log_stream.FailureCode.LOG_RELEASE_FAILURE, outcome.blocked);
        try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
        // The cancelled close may have written its trailer, so the stream's state is dropped whatever the release did.
        if (fault == .cancel_close_release_fails) try std.testing.expect(runner.event_state == null and runner.dropped.contains(.event));
    }
}

test "cancellation while a stream is prepared or closed is a cancellation, never a logging failure" {
    const owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    inline for (.{ Fault.cancel_recovery, Fault.cancel_close }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (fault == .cancel_recovery) {
            try std.testing.expect(runner.prepare(shortcode) == .cancelled);
            try std.testing.expect(!runner.prepared);
        } else {
            runner.event_state = .{ .segment_ordinal = 1, .next_sequence = 1, .segment_bytes = 0, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
            try std.testing.expect(runner.close(shortcode) == .cancelled);
            try std.testing.expect(!runner.retired);
            // The trailer may already be written, so the cached state is dropped and a later close recovers it.
            try std.testing.expect(runner.event_state == null and runner.dropped.contains(.event));
        }
        try std.testing.expect(!sink.held);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    }
}

test "cancelled activation, finalization and transition end as cancellation and release the lock" {
    const old_candidate = bindingCandidate();
    const next_candidate: log_binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-2").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-2").?,
        .run_id = old_candidate.run_id,
        .feature_id = old_candidate.feature_id,
    };
    const old_owner = try log_binding.createValidated(std.testing.allocator, old_candidate);
    defer log_binding.deinitOwner(old_owner);
    const next_owner = try log_binding.createValidated(std.testing.allocator, next_candidate);
    defer log_binding.deinitOwner(next_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");

    // Activation prepares the stream, which recovers it under the lock.
    {
        var sink: FaultSink = .{ .fault = .cancel_recovery };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        var lifecycle: runtime_lifecycle.Lifecycle = .{};
        try std.testing.expect(lifecycle.activate(runner.childBindings(), shortcode) == .cancelled);
        try std.testing.expect(lifecycle.active == null);
        try std.testing.expect(!sink.held);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    }
    // Finalization closes the stream under the lock.
    {
        var sink: FaultSink = .{ .fault = .cancel_close };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        var lifecycle: runtime_lifecycle.Lifecycle = .{};
        try std.testing.expect(lifecycle.activate(runner.childBindings(), shortcode) == .ok);
        var finalization_execution: finalization_runner.Runner = .{ .target = &runner, .mode = .active, .shortcode = shortcode };
        try std.testing.expect(lifecycle.finalizeActive(finalization_execution.childBindings()) == .cancelled);
        try std.testing.expect(lifecycle.active == null);
        try std.testing.expect(!sink.held);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    }
    // A policy transition closes the current stream before it prepares the next.
    {
        var old_sink: FaultSink = .{ .fault = .cancel_close };
        var next_sink: FaultSink = .{ .fault = .none };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var old_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .actions = childrenFor(&old_sink, clock.port(), outputs.console(), outputs.emergency()) };
        var next_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(next_owner), .actions = childrenFor(&next_sink, clock.port(), outputs.console(), outputs.emergency()) };
        var lifecycle: runtime_lifecycle.Lifecycle = .{};
        try std.testing.expect(lifecycle.activate(old_runner.childBindings(), shortcode) == .ok);
        var transition_execution: transition_runner.Runner = .{ .current = &old_runner, .next = &next_runner, .shortcode = shortcode };
        try std.testing.expect(lifecycle.transition(transition_execution.childBindings()) == .cancelled);
        try std.testing.expect(!old_sink.held);
        try std.testing.expect(!next_runner.prepared);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    }
}

test "cancelled retention at the sink is a cancellation and releases the lock" {
    const owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(owner);
    const historical_owner = try log_binding.createValidated(std.testing.allocator, .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = bindingCandidate().feature_id,
    });
    defer log_binding.deinitOwner(historical_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true };
    var clock: FakeClock = .{};
    var sink: FaultSink = .{ .fault = .cancel_retention };
    var execution: retention_runner.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .current = log_binding.binding(owner),
        .historical = log_binding.binding(historical_owner),
        .target_stream = .event,
        .authorize_action = .{ .clock = clock.port() },
        .acquire_action = .{ .sink = sink.lockAcquirer() },
        .prune_action = prune_segments.Action{ .sink = sink.segmentPruner() },
        .release_action = .{ .sink = sink.lockReleaser() },
    };
    defer execution.deinit();
    try std.testing.expect(retention_coordinator.run(execution.childBindings()) == .cancelled);
    try std.testing.expect(!sink.held);
}

test "a filesystem cancellation at any sink operation is a cancellation, with the lock released and no emergency line" {
    const io = std.testing.io;
    const Prepared = enum { fresh, active_segment, partial_tail };
    const Case = struct { op: cancelling.Op, pass: usize = 0, prepared: Prepared = .fresh };
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .event_type = .run_started } };
    // Each case names the nth call of one filesystem operation, in the order a persist makes them: the lock file
    // is opened, created, inspected and locked; recovery lists the directory and reads or truncates a segment; a
    // new segment is created, its heading and header written and synced; the row is appended.
    const cases = [_]Case{
        .{ .op = .open_file },
        .{ .op = .create_file },
        .{ .op = .stat },
        .{ .op = .try_lock },
        .{ .op = .dir_read },
        .{ .op = .create_file, .pass = 1 },
        .{ .op = .write_streaming },
        .{ .op = .write_streaming, .pass = 1 },
        .{ .op = .sync },
        .{ .op = .open_file, .pass = 1 },
        .{ .op = .stat, .pass = 1 },
        .{ .op = .write_positional },
        .{ .op = .read_positional, .prepared = .active_segment },
        .{ .op = .set_length, .prepared = .partial_tail },
    };
    for (cases) |case| {
        var directory = std.testing.tmpDir(.{ .iterate = true });
        defer directory.cleanup();
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        if (case.prepared != .fresh) {
            var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
            var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
            try std.testing.expect(first_runner.process(fact) == .persisted);
            if (case.prepared == .partial_tail) {
                var file = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_write });
                try file.writePositionalAll(io, "partial", (try file.stat(io)).size);
                file.close(io);
            }
        }
        var cancel: cancelling.CancellingIo = undefined;
        cancel.init(case.op, case.pass);
        defer cancel.deinit();
        var sink = filesystem_sink.Adapter.initForTest(cancel.io(), directory.dir, candidate);
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        try std.testing.expect(runner.process(fact) == .cancelled);
        try std.testing.expect(cancel.fired);
        try std.testing.expect(sink.lock_file == null);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    }
    // The wrapper is transparent: with nothing to cancel, the same persist succeeds.
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var passthrough: cancelling.CancellingIo = undefined;
    passthrough.init(.none, 0);
    defer passthrough.deinit();
    var sink = filesystem_sink.Adapter.initForTest(passthrough.io(), directory.dir, candidate);
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(runner.process(fact) == .persisted);
}

test "a cancellation while recovery scans the run's other bindings is a cancellation, never a corrupt stream" {
    const io = std.testing.io;
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .event_type = .run_started } };
    // The run directory holds this binding and a sibling; recovery lists both, and the nth directory read is cancelled.
    var cancelled_reads: usize = 0;
    for (0..6) |pass| {
        var root = std.testing.tmpDir(.{ .iterate = true });
        defer root.cleanup();
        try root.dir.createDir(io, "LOGBIND-0", std.Io.File.Permissions.fromMode(0o700));
        try root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
        var binding_directory = try root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
        defer binding_directory.close(io);
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var cancel: cancelling.CancellingIo = undefined;
        cancel.init(.dir_read, pass);
        defer cancel.deinit();
        var sink = filesystem_sink.Adapter.initForTestLayout(cancel.io(), root.dir, binding_directory, candidate);
        defer sink.deinit();
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        const outcome = runner.process(fact);
        // A read the persist never reaches leaves the run unaffected; every read it does reach reports a cancellation.
        if (cancel.fired) {
            cancelled_reads += 1;
            try std.testing.expect(outcome == .cancelled);
            try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
        } else try std.testing.expect(outcome == .persisted);
    }
    // More than the binding's own listing was reached: the scan of the run's other bindings reads too.
    try std.testing.expect(cancelled_reads >= 2);
}

test "a cancelled console mirror write under the lock is a cancellation, and the row it followed is recovered" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .event_type = .run_started } };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(runner.process(fact) == .persisted);
    outputs.console_cancel = true;
    try std.testing.expect(runner.process(fact) == .cancelled);
    try std.testing.expect(sink.lock_file == null);
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    // The second row was appended before its console write, so the runner's cached state is behind the file. It
    // drops that state and recovers it: the next event continues the sequence instead of failing on the size
    // it expected.
    outputs.console_cancel = false;
    const next = runner.process(fact);
    try std.testing.expect(next == .persisted);
    try std.testing.expectEqual(@as(u64, 3), next.persisted.sequence);
    // The recovered state is the cache again, so the mark is cleared.
    try std.testing.expect(runner.dropped.count() == 0 and runner.event_state != null);
    // A console failure that is no cancellation stays a logging failure.
    outputs.console_failure = true;
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, runner.process(fact).blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
}

test "finalization recovers and closes a stream whose state a cancelled persist dropped, in either stream" {
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{ .iterate = true });
    defer root.cleanup();
    var prompt_root = std.testing.tmpDir(.{ .iterate = true });
    defer prompt_root.cleanup();
    try root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
    try prompt_root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
    var event_directory = try root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
    defer event_directory.close(io);
    var prompt_directory = try prompt_root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
    defer prompt_directory.close(io);
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true };
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .event_type = .run_started } };
    const fragment: prompt_log.SanitizedPromptFragment = .{
        .workflow_shortcode = shortcode,
        .attempt = 1,
        .request_id = telemetry.Identifier.validate("REQ-1").?,
        .route_id = telemetry.Identifier.validate("ROUTE-1").?,
        .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
        .fragment_id = telemetry.Identifier.validate("FRAG-1").?,
        .direction = .response,
        .body_class = .code_body,
        .content = "sanitized",
        .retained_bytes = 9,
        .truncated = false,
        .redacted = true,
    };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, event_directory, candidate);
    sink.prompt_run_directory = prompt_root.dir;
    sink.prompt_directory = prompt_directory;
    defer sink.deinit();
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(runner.prepare(shortcode) == .dropped);
    try std.testing.expect(runner.process(fact) == .persisted);
    try std.testing.expect(runner.processPrompt(fragment) == .persisted);
    // Each stream's second row is appended and then its console mirror write is cancelled: the file is ahead of the cache.
    outputs.console_cancel = true;
    try std.testing.expect(runner.process(fact) == .cancelled);
    try std.testing.expect(runner.processPrompt(fragment) == .cancelled);
    outputs.console_cancel = false;
    try std.testing.expect(runner.event_state == null and runner.dropped.contains(.event));
    try std.testing.expect(runner.prompt_state == null and runner.dropped.contains(.prompt));
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    // Finalization is not skipped for a dropped stream: each is recovered under its lock and closed with its trailer.
    try std.testing.expect(runner.close(shortcode) == .dropped);
    try std.testing.expect(runner.dropped.count() == 0 and runner.retired);
    for ([_]std.Io.Dir{ event_directory, prompt_directory }) |directory| {
        const bytes = try directory.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
        defer std.testing.allocator.free(bytes);
        // The cancelled row was kept, and the trailer is the last row, written exactly once.
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "segment_trailer|"));
        const rows = std.mem.trimEnd(u8, bytes, "\n");
        try std.testing.expect(std.mem.startsWith(u8, rows[std.mem.lastIndexOfScalar(u8, rows, '\n').? + 1 ..], "segment_trailer|"));
    }
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
}

test "a cancelled close is closed again from the bytes, writing exactly one trailer whether or not the first wrote it" {
    const io = std.testing.io;
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .event_type = .run_started } };
    // The nth call of one operation is cancelled. A cancelled flush follows the trailer's bytes; a cancelled
    // stat or write precedes them, so the first close writes none and only the second can.
    var reached = [_]usize{0} ** 3;
    const ops = [_]cancelling.Op{ .sync, .stat, .write_positional };
    for (ops, 0..) |op, index| for (0..8) |pass| {
        var directory = std.testing.tmpDir(.{ .iterate = true });
        defer directory.cleanup();
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var cancel: cancelling.CancellingIo = undefined;
        cancel.init(op, pass);
        defer cancel.deinit();
        var sink = filesystem_sink.Adapter.initForTest(cancel.io(), directory.dir, candidate);
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (runner.process(fact) != .persisted) continue;
        if (runner.close(shortcode) != .cancelled) continue;
        reached[index] += 1;
        // A cancel inside the close drops the state; one at the lock came before any write and keeps it. Never both.
        try std.testing.expectEqual(runner.event_state == null, runner.dropped.contains(.event));
        try std.testing.expect(!runner.retired);
        try std.testing.expect(runner.close(shortcode) == .dropped);
        const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
        defer std.testing.allocator.free(bytes);
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, bytes, "segment_trailer|"));
        try std.testing.expect(sink.lock_file == null);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    };
    for (reached) |count| try std.testing.expect(count >= 1);
}

test "a stopped prompt prepare closes the event stream it already opened, and a stopped close still closes the other stream" {
    const io = std.testing.io;
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    // Event and prompt streams live in separate directories, as in a run. The nth call of one operation is cancelled.
    const Case = struct { op: cancelling.Op, close_phase: bool };
    var prepare_reached: usize = 0;
    var close_reached: usize = 0;
    for ([_]Case{ .{ .op = .create_file, .close_phase = false }, .{ .op = .sync, .close_phase = true } }) |case| for (0..8) |pass| {
        var root = std.testing.tmpDir(.{ .iterate = true });
        defer root.cleanup();
        var prompt_root = std.testing.tmpDir(.{ .iterate = true });
        defer prompt_root.cleanup();
        try root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
        try prompt_root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
        var event_directory = try root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
        defer event_directory.close(io);
        var prompt_directory = try prompt_root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
        defer prompt_directory.close(io);
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var cancel: cancelling.CancellingIo = undefined;
        cancel.init(case.op, pass);
        defer cancel.deinit();
        var sink = filesystem_sink.Adapter.initForTestLayout(cancel.io(), root.dir, event_directory, candidate);
        sink.prompt_run_directory = prompt_root.dir;
        sink.prompt_directory = prompt_directory;
        defer sink.deinit();
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        const prepared = runner.prepare(shortcode);
        if (case.close_phase) {
            // Cancelled flushes follow their trailer's bytes, so a stream that was attempted has its trailer.
            if (prepared != .dropped or runner.close(shortcode) != .cancelled) continue;
            close_reached += 1;
        } else {
            if (prepared != .cancelled) continue;
            prepare_reached += 1;
        }
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
        try std.testing.expect(sink.lock_file == null);
        const event_bytes = directory_bytes: {
            break :directory_bytes event_directory.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes)) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
        };
        defer std.testing.allocator.free(event_bytes);
        // A segment whose header was never completed is a torn creation, not a stream the runner could close.
        if (std.mem.indexOf(u8, event_bytes, "segment_header|") == null) continue;
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, event_bytes, "segment_trailer|"));
        if (case.close_phase) {
            const prompt_bytes = try prompt_directory.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
            defer std.testing.allocator.free(prompt_bytes);
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, prompt_bytes, "segment_trailer|"));
        }
    };
    try std.testing.expect(prepare_reached >= 1 and close_reached >= 2);
}

test "finalization's recovery of a dropped stream releases its lock on every exit and keeps the mark" {
    const owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    inline for (.{ Fault.cancel_recovery, Fault.recovery, Fault.lock }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        runner.dropped.insert(.event);
        const outcome = runner.close(shortcode);
        switch (fault) {
            // A cancellation is no logging failure: no code, no emergency line.
            .cancel_recovery => {
                try std.testing.expect(outcome == .cancelled);
                try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
            },
            .recovery => {
                try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
                try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
            },
            .lock => {
                try std.testing.expectEqual(log_stream.FailureCode.LOG_LOCK_TIMEOUT, outcome.blocked);
                try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
            },
            else => unreachable,
        }
        try std.testing.expect(!sink.held);
        try std.testing.expect(runner.dropped.contains(.event) and !runner.retired);
    }
}

test "a filesystem cancellation while retention prunes closed segments is a cancellation and deletes nothing more" {
    const io = std.testing.io;
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .event_type = .run_started } };
    for ([_]cancelling.Op{ .dir_read, .open_file, .stat, .read_positional, .delete_file }) |op| {
        var directory = std.testing.tmpDir(.{ .iterate = true });
        defer directory.cleanup();
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
        var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
        try std.testing.expect(first_runner.process(fact) == .persisted);
        try std.testing.expect(first_runner.close(shortcode) == .dropped);
        var cancel: cancelling.CancellingIo = undefined;
        cancel.init(op, 0);
        defer cancel.deinit();
        try std.testing.expectError(error.Cancelled, retention_store.prune(cancel.io(), std.testing.allocator, directory.dir, std.math.maxInt(u64)));
        try std.testing.expect(cancel.fired);
        // The cancelled prune removed nothing: the closed segment is still there, and a later prune removes it.
        var segment = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_only });
        segment.close(io);
        try retention_store.prune(io, std.testing.allocator, directory.dir, std.math.maxInt(u64));
        try std.testing.expectError(error.FileNotFound, directory.dir.openFile(io, "0001.log", .{ .mode = .read_only }));
    }
}

test "the sink's mapping owner makes a cancellation its own outcome and leaves every other fault as it was" {
    try std.testing.expectEqual(error.Cancelled, log_file.sinkFault(error.Canceled));
    try std.testing.expectEqual(error.SinkFailure, log_file.sinkFault(error.AccessDenied));
    try std.testing.expectEqual(error.Cancelled, log_file.flushFault(error.Canceled));
    try std.testing.expectEqual(error.FlushFailure, log_file.flushFault(error.AccessDenied));
}

test "production event projection reports a log cancellation as a cancellation" {
    const capture = @import("application/workflow_event_capture.zig");
    const Spy = struct {
        fn process(_: *anyopaque, _: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
            return .cancelled;
        }
    };
    var context: u8 = 0;
    const events: capture.Capture = .{ .barrier = .{ .context = &context, .process_fn = Spy.process }, .shortcode = try telemetry.WorkflowShortcode.parse("OTHR") };
    const node: @import("domain/workflow.zig").WorkflowStepId = .{ .bytes = "check" };
    const cancelled: ?log_stream.Stop = .cancelled;
    try std.testing.expectEqual(cancelled, events.emit(.{ .event_type = .run_started }));
    try std.testing.expectEqual(cancelled, events.action(node, null, null, null));
    try std.testing.expectEqual(cancelled, events.terminal(.{ .execution = .cancelled }));
    try std.testing.expectEqual(cancelled, events.retryAttempt(node, 2, false));
}

test "a logging stop rejects as a logging failure and a cancellation as the run's cancellation" {
    const Rejection = @import("domain/workflow_execution.zig").Rejection;
    const failure = Rejection.logStop(.{ .blocked = .LOG_SINK_FAILURE });
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, failure.logging);
    try std.testing.expectEqual(@import("domain/workflow.zig").OutcomeTag.blocked, failure.status());
    const cancelled = Rejection.logStop(.cancelled);
    try std.testing.expect(cancelled == .cancelled);
    try std.testing.expectEqual(@import("domain/workflow.zig").OutcomeTag.cancelled, cancelled.status());
    // An outcome is a stop only when it blocked or was cancelled; a dropped or persisted fact stops nothing.
    try std.testing.expect((log_stream.Outcome{ .dropped = {} }).stop() == null);
    try std.testing.expectEqual(@as(?log_stream.Stop, .cancelled), (log_stream.Outcome{ .cancelled = {} }).stop());
    try std.testing.expectEqual(@as(?log_stream.Stop, .{ .blocked = .LOG_FLUSH_FAILURE }), (log_stream.Outcome{ .blocked = .LOG_FLUSH_FAILURE }).stop());
}
