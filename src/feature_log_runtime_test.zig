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
        .prompt_capture = &.{},
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
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
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
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
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
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
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

test "stream lock acquisition rejects a symbolic link" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    try directory.dir.writeFile(io, .{ .sub_path = "lock-target", .data = "unchanged" });
    try directory.dir.symLink(io, "lock-target", ".stream.lock", .{});
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()) };
    const outcome = runner.process(.{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_started } });
    try std.testing.expectEqual(log_stream.FailureCode.LOG_LOCK_TIMEOUT, outcome.blocked);
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
        .prompt_capture = &.{},
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

test "enabled sanitized prompt fragments persist in their separate stream" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const captures = [_]@import("domain/config.zig").PromptCapture{.request};
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &captures,
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
        .attempt = 1,
        .request_id = telemetry.Identifier.validate("REQ-1").?,
        .route_id = telemetry.Identifier.validate("ROUTE-1").?,
        .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
        .fragment_id = telemetry.Identifier.validate("FRAG-1").?,
        .direction = .request,
        .body_class = .ordinary,
        .content = "sanitized",
        .retained_bytes = 9,
        .truncated = false,
        .redacted = true,
    });
    try std.testing.expect(outcome == .persisted);
    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.startsWith(u8, bytes, @import("domain/feature_log_format.zig").prompt_heading));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|PLAN|") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|sanitized|9|false|true\n") != null);
}

test "prompt batches persist in canonical fragment id order and consume transient ownership" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const captures = [_]@import("domain/config.zig").PromptCapture{.request};
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &captures };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .actions = childrenFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()) };
    const base: prompt_log.SanitizedPromptFragment = .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("PLAN"),
        .attempt = 1,
        .request_id = telemetry.Identifier.validate("REQ-1").?,
        .route_id = telemetry.Identifier.validate("ROUTE-1").?,
        .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
        .fragment_id = telemetry.Identifier.validate("FRAG-2").?,
        .direction = .request,
        .body_class = .ordinary,
        .content = "second",
        .retained_bytes = 6,
        .truncated = false,
        .redacted = true,
    };
    var first = base;
    first.fragment_id = telemetry.Identifier.validate("FRAG-1").?;
    first.content = "first";
    first.retained_bytes = 5;
    const batch = try prompt_log.createBatch(std.testing.allocator, &.{ base, first });
    try std.testing.expect(runner.processPromptBatch(batch) == .persisted);
    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|FRAG-1|").? < std.mem.indexOf(u8, bytes, "|FRAG-2|").?);
}

test "fault barriers distinguish lock recovery flush console rotation and retention failures" {
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true, .prompt_capture = &.{} };
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
    const authorization = try (build_retention.Action{ .clock = retention_clock.port() }).execute(
        std.testing.allocator,
        &policy,
        log_binding.binding(owner),
        log_binding.binding(historical_owner),
        .event,
    );
    defer log_retention.deinit(authorization);
    var retention_sink: FaultSink = .{ .fault = .retention };
    var retention_execution: retention_runner.Runner = .{
        .current = log_binding.binding(owner),
        .historical = log_binding.binding(historical_owner),
        .authorization = authorization,
        .acquire_action = .{ .sink = retention_sink.lockAcquirer() },
        .prune_action = prune_segments.Action{ .sink = retention_sink.segmentPruner() },
        .release_action = .{ .sink = retention_sink.lockReleaser() },
    };
    const retention = retention_coordinator.run(retention_execution.childBindings());
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, retention.blocked);
}

test "same-run policy transition closes the old binding and continues sequence and total budget" {
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{ .iterate = true });
    defer root.cleanup();
    try root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
    try root.dir.createDir(io, "LOGBIND-2", std.Io.File.Permissions.fromMode(0o700));
    var old_directory = try root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
    defer old_directory.close(io);
    var next_directory = try root.dir.openDir(io, "LOGBIND-2", .{ .iterate = true });
    defer next_directory.close(io);
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
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var old_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, old_directory, old_candidate);
    defer old_sink.deinit();
    var old_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .actions = childrenFor(&old_sink, clock.port(), outputs.console(), outputs.emergency()) };
    var next_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, next_directory, next_candidate);
    defer next_sink.deinit();
    var next_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(next_owner), .actions = childrenFor(&next_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_started } };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expect(lifecycle.activate(old_runner.childBindings(), fact.workflow_shortcode) == .ok);
    try std.testing.expect(lifecycle.activate(next_runner.childBindings(), fact.workflow_shortcode) == .invalid);
    try std.testing.expect(lifecycle.barrier().process(fact) == .persisted);
    try std.testing.expectEqual(@as(u64, 2), old_runner.event_state.?.next_sequence);
    var transition_execution: transition_runner.Runner = .{
        .current = &old_runner,
        .next = &next_runner,
        .shortcode = fact.workflow_shortcode,
    };
    try std.testing.expect(lifecycle.transition(transition_execution.childBindings()) == .ok);
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
    const authorization = try (build_retention.Action{ .clock = retention_clock.port() }).execute(
        std.testing.allocator,
        &policy,
        log_binding.binding(next_owner),
        log_binding.binding(historical_owner),
        .event,
    );
    defer log_retention.deinit(authorization);
    var retention_sink: FaultSink = .{ .fault = .retention };
    var retention_execution: retention_runner.Runner = .{
        .current = log_binding.binding(next_owner),
        .historical = log_binding.binding(historical_owner),
        .authorization = authorization,
        .acquire_action = .{ .sink = retention_sink.lockAcquirer() },
        .prune_action = prune_segments.Action{ .sink = retention_sink.segmentPruner() },
        .release_action = .{ .sink = retention_sink.lockReleaser() },
    };
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
        .prompt_capture = &.{},
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
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
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
        .prompt_capture = &.{},
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
        .prompt_capture = &.{},
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
        .prompt_capture = &.{},
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
    try std.testing.expectEqual(log_stream.FailureCode.LOG_LOCK_TIMEOUT, outcome.blocked);
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
        .prompt_capture = &.{},
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
    try std.testing.expectEqual(log_stream.FailureCode.LOG_LOCK_TIMEOUT, outcome.blocked);
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
    fn console(self: *FakeOutputs) console_port.Sink {
        return .{ .context = self, .write_fn = writeConsole };
    }
    fn emergency(self: *FakeOutputs) emergency_port.Sink {
        return .{ .context = self, .write_fn = writeEmergency };
    }
    fn writeConsole(context: *anyopaque, _: []const u8) console_port.Error!void {
        const self: *FakeOutputs = @ptrCast(@alignCast(context));
        if (self.console_failure) return error.ConsoleWriteFailure;
    }
    fn writeEmergency(context: *anyopaque, _: []const u8) emergency_port.Error!void {
        const self: *FakeOutputs = @ptrCast(@alignCast(context));
        self.emergency_calls += 1;
        if (self.emergency_failure) return error.EmergencyWriteFailure;
        self.emergency_count += 1;
    }
};

const Fault = enum { none, lock, recovery, flush, console, rotation, retention };
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
    self.held = true;
}
fn faultRecover(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: []const u8, _: std.mem.Allocator) @import("ports/feature_log_sink.zig").Error!log_stream.Recovery {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .recovery) return error.CorruptStream;
    return .{ .empty = .{ .next_segment_ordinal = 1, .next_sequence = 1, .total_segment_count = 0 } };
}
fn faultCreate(_: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, ordinal: u16, seed: log_stream.StreamSeed, heading: []const u8, header: []const u8) @import("ports/feature_log_sink.zig").Error!log_stream.StreamState {
    return .{ .segment_ordinal = ordinal, .next_sequence = seed.next_sequence, .segment_bytes = heading.len + header.len, .segment_count = 1, .total_segment_count = seed.total_segment_count + 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
}
fn faultRotate(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, state: log_stream.StreamState, _: []const u8, _: []const u8, _: []const u8) @import("ports/feature_log_sink.zig").Error!log_stream.StreamState {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .rotation) return error.SinkFailure;
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
}
fn faultAppend(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, state: log_stream.StreamState, row: []const u8, flush: bool) @import("ports/feature_log_sink.zig").Error!log_stream.PersistedEvidence {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .flush and flush) return error.FlushFailure;
    return .{ .segment_ordinal = state.segment_ordinal, .sequence = state.next_sequence, .bytes_written = row.len, .flushed = flush };
}
fn faultPrune(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u64) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .retention) return error.SinkFailure;
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
