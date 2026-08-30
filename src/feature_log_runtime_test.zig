const std = @import("std");
const filesystem_sink = @import("adapters/filesystem/feature_log_sink.zig");
const runner_module = @import("application/feature_log_runner.zig");
const runtime = @import("domain/feature_log_runtime.zig");
const logging = @import("domain/logging.zig");
const telemetry = @import("domain/telemetry.zig");
const console_port = @import("ports/console_log_sink.zig");
const emergency_port = @import("ports/emergency_log_sink.zig");
const stabilizer_port = @import("ports/transaction_stabilizer.zig");
const clock_port = @import("ports/trusted_log_clock.zig");
const build_retention = @import("actions/log/build_feature_log_retention_authorization.zig");
const retention_coordinator = @import("application/feature_log_retention_coordinator.zig");
const runtime_lifecycle = @import("application/feature_log_runtime_lifecycle.zig");

test "runner barrier persists recovers and sequences feature events" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const binding_owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(binding_owner);
    const binding = runtime.binding(binding_owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = binding,
        .sink = sink_adapter.sink(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
    };
    const attributed: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"),
        .fact = .{
            .event_type = .task_started,
            .fields = .{ .task_id = telemetry.Identifier.validate("TASK-1").? },
        },
    };
    const first = runner.barrier().process(attributed);
    if (first == .blocked) try std.testing.expectEqual(runtime.FailureCode.LOG_SINK_FAILURE, first.blocked);
    try std.testing.expectEqual(@as(std.meta.Tag(runtime.BarrierOutcome), .persisted), std.meta.activeTag(first));
    try std.testing.expectEqual(@as(u64, 1), first.persisted.sequence);
    const second = runner.process(attributed);
    try std.testing.expect(second == .persisted);
    try std.testing.expectEqual(@as(u64, 2), second.persisted.sequence);

    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(logging.max_segment_bytes));
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
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = first_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .event_type = .run_started } };
    try std.testing.expect(first_runner.process(fact) == .persisted);
    var file = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_write });
    const size = (try file.stat(io)).size;
    try file.writePositionalAll(io, "partial", size);
    file.close(io);
    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = second_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    const outcome = second_runner.process(fact);
    try std.testing.expect(outcome == .persisted);
    try std.testing.expectEqual(@as(u64, 2), outcome.persisted.sequence);
    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(logging.max_segment_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "partial") == null);
}

test "restart recovery resumes after a durably closed tail" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .event_type = .run_started } };

    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = first_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    try std.testing.expect(first_runner.process(fact) == .persisted);
    try std.testing.expect(first_runner.close(shortcode) == .dropped);

    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = second_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
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
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = first_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .event_type = .run_started } };
    try std.testing.expect(first_runner.process(fact) == .persisted);
    var file = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_write });
    try file.setPermissions(io, std.Io.File.Permissions.fromMode(0o644));
    file.close(io);
    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = second_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    try std.testing.expectEqual(runtime.FailureCode.LOG_SINK_FAILURE, second_runner.process(fact).blocked);
}

test "stream lock acquisition rejects a symbolic link" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    try directory.dir.writeFile(io, .{ .sub_path = "lock-target", .data = "unchanged" });
    try directory.dir.symLink(io, "lock-target", ".stream.lock", .{});
    const candidate = bindingCandidate();
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = sink_adapter.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    const outcome = runner.process(.{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_started } });
    try std.testing.expectEqual(runtime.FailureCode.LOG_LOCK_TIMEOUT, outcome.blocked);
    const target = try directory.dir.readFileAlloc(io, "lock-target", std.testing.allocator, .limited(32));
    defer std.testing.allocator.free(target);
    try std.testing.expectEqualStrings("unchanged", target);
}

test "threshold drop performs no clock sink or identity work" {
    const candidate = bindingCandidate();
    const binding_owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(binding_owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .fatal, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var rejecting_sink: RejectingSink = .{};
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(binding_owner),
        .sink = rejecting_sink.port(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
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
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const captures = [_]@import("domain/config.zig").PromptCapture{.request};
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &captures,
    };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(owner),
        .sink = sink_adapter.sink(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
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
    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(logging.max_segment_bytes));
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
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const captures = [_]@import("domain/config.zig").PromptCapture{.request};
    const policy: logging.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &captures };
    var sink_adapter = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = sink_adapter.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    const base: runtime.SanitizedPromptFragment = .{
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
    const batch = try runtime.createPromptBatch(std.testing.allocator, &.{ base, first });
    try std.testing.expect(runner.processPromptBatch(batch) == .persisted);
    const bytes = try directory.dir.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(logging.max_segment_bytes));
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "|FRAG-1|").? < std.mem.indexOf(u8, bytes, "|FRAG-2|").?);
}

test "fault barriers distinguish lock recovery flush console rotation and retention failures" {
    const candidate = bindingCandidate();
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true, .prompt_capture = &.{} };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_completed, .fields = .{ .outcome = .completed } } };

    inline for (.{ Fault.lock, Fault.recovery, Fault.flush, Fault.console, Fault.rotation }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{ .console_failure = fault == .console };
        var stabilizer: FakeStabilizer = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(owner), .sink = sink.port(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
        if (fault == .rotation) runner.event_state = .{
            .segment_ordinal = 1,
            .next_sequence = 1,
            .segment_bytes = logging.max_segment_bytes - 1,
            .segment_count = 1,
            .total_segment_count = 1,
            .records_since_flush = 0,
            .last_flush_monotonic_ms = 0,
        };
        const outcome = runner.process(fact);
        try std.testing.expect(outcome == .blocked);
        try std.testing.expectEqual(switch (fault) {
            .lock => runtime.FailureCode.LOG_LOCK_TIMEOUT,
            .flush => runtime.FailureCode.LOG_FLUSH_FAILURE,
            else => runtime.FailureCode.LOG_SINK_FAILURE,
        }, outcome.blocked);
        try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    }

    const historical_candidate: runtime.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = candidate.feature_id,
    };
    const historical_owner = try runtime.createValidatedBinding(std.testing.allocator, historical_candidate);
    defer runtime.deinitBindingOwner(historical_owner);
    var retention_clock: FakeClock = .{};
    const authorization = try (build_retention.Action{ .clock = retention_clock.port() }).execute(
        std.testing.allocator,
        &policy,
        runtime.binding(owner),
        runtime.binding(historical_owner),
        .event,
    );
    defer runtime.deinitRetentionAuthorization(authorization);
    var retention_sink: FaultSink = .{ .fault = .retention };
    const retention = retention_coordinator.run(
        retention_sink.port(),
        runtime.binding(owner),
        runtime.binding(historical_owner),
        authorization,
    );
    try std.testing.expectEqual(runtime.FailureCode.LOG_SINK_FAILURE, retention.blocked);
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
    const next_candidate: runtime.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-2").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-2").?,
        .run_id = old_candidate.run_id,
        .feature_id = old_candidate.feature_id,
    };
    const old_owner = try runtime.createValidatedBinding(std.testing.allocator, old_candidate);
    defer runtime.deinitBindingOwner(old_owner);
    const next_owner = try runtime.createValidatedBinding(std.testing.allocator, next_candidate);
    defer runtime.deinitBindingOwner(next_owner);
    const policy: logging.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false, .prompt_capture = &.{} };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var old_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, old_directory, old_candidate);
    defer old_sink.deinit();
    var old_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(old_owner), .sink = old_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    var next_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, next_directory, next_candidate);
    defer next_sink.deinit();
    var next_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = runtime.binding(next_owner), .sink = next_sink.sink(), .clock = clock.port(), .console = outputs.console(), .emergency_sink = outputs.emergency(), .stabilizer = stabilizer.port() };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .event_type = .run_started } };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expect(lifecycle.activate(&old_runner, fact.workflow_shortcode) == .ok);
    try std.testing.expect(lifecycle.activate(&next_runner, fact.workflow_shortcode) == .invalid);
    try std.testing.expectEqual(@as(u64, 1), lifecycle.barrier().process(fact).persisted.sequence);
    try std.testing.expect(lifecycle.transition(&next_runner, fact.workflow_shortcode) == .ok);
    const outcome = lifecycle.barrier().process(fact);
    try std.testing.expectEqual(@as(u64, 2), outcome.persisted.sequence);
    try std.testing.expectEqual(@as(u8, 2), next_runner.event_state.?.total_segment_count);

    const historical_candidate: runtime.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = next_candidate.feature_id,
    };
    const historical_owner = try runtime.createValidatedBinding(std.testing.allocator, historical_candidate);
    defer runtime.deinitBindingOwner(historical_owner);
    var retention_clock: FakeClock = .{};
    const authorization = try (build_retention.Action{ .clock = retention_clock.port() }).execute(
        std.testing.allocator,
        &policy,
        runtime.binding(next_owner),
        runtime.binding(historical_owner),
        .event,
    );
    defer runtime.deinitRetentionAuthorization(authorization);
    var retention_sink: FaultSink = .{ .fault = .retention };
    const retention = lifecycle.retainHistorical(
        retention_sink.port(),
        runtime.binding(historical_owner),
        authorization,
        fact.workflow_shortcode,
    );
    try std.testing.expectEqual(runtime.FailureCode.LOG_SINK_FAILURE, retention.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), stabilizer.calls);
    try std.testing.expect(lifecycle.finalizeActive(fact.workflow_shortcode) == .ok);
    try std.testing.expect(next_runner.retired);
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
}

test "retention authorization derives its single-use cutoff from trusted policy and time" {
    const current_candidate = bindingCandidate();
    const historical_candidate: runtime.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = current_candidate.feature_id,
    };
    const current_owner = try runtime.createValidatedBinding(std.testing.allocator, current_candidate);
    defer runtime.deinitBindingOwner(current_owner);
    const historical_owner = try runtime.createValidatedBinding(std.testing.allocator, historical_candidate);
    defer runtime.deinitBindingOwner(historical_owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var clock: FakeClock = .{};
    const authorization = try (build_retention.Action{ .clock = clock.port() }).execute(
        std.testing.allocator,
        &policy,
        runtime.binding(current_owner),
        runtime.binding(historical_owner),
        .event,
    );
    defer runtime.deinitRetentionAuthorization(authorization);
    const authorized = runtime.consumeRetentionAuthorization(
        authorization,
        runtime.binding(historical_owner),
    ).?;
    try std.testing.expectEqual(
        @as(u64, 1_788_087_330_000) - logging.retention_period_ms,
        authorized.cutoff_unix_ms,
    );
    try std.testing.expect(runtime.consumeRetentionAuthorization(
        authorization,
        runtime.binding(historical_owner),
    ) == null);

    var invalid_policy = policy;
    invalid_policy.retention_days -= 1;
    try std.testing.expectError(
        error.FeatureLogRetentionAuthorizationInvalid,
        (build_retention.Action{ .clock = clock.port() }).execute(
            std.testing.allocator,
            &invalid_policy,
            runtime.binding(current_owner),
            runtime.binding(historical_owner),
            .event,
        ),
    );
}

test "historical finalization recovers and durably closes one active tail" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(owner),
        .sink = first_sink.sink(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
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
        .binding = runtime.binding(owner),
        .sink = recovered_sink.sink(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.finalizeHistorical(&recovered_runner, shortcode) == .ok);
    try std.testing.expect(recovered_runner.retired);
    const bytes = try directory.dir.readFileAlloc(
        io,
        "0001.log",
        std.testing.allocator,
        .limited(logging.max_segment_bytes),
    );
    defer std.testing.allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "segment_trailer|") != null);
}

test "failed successor preparation removes the active observer" {
    const old_candidate = bindingCandidate();
    const next_candidate: runtime.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-2").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-2").?,
        .run_id = old_candidate.run_id,
        .feature_id = old_candidate.feature_id,
    };
    const old_owner = try runtime.createValidatedBinding(std.testing.allocator, old_candidate);
    defer runtime.deinitBindingOwner(old_owner);
    const next_owner = try runtime.createValidatedBinding(std.testing.allocator, next_candidate);
    defer runtime.deinitBindingOwner(next_owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var old_sink: FaultSink = .{ .fault = .none };
    var next_sink: FaultSink = .{ .fault = .recovery };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var old_runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(old_owner),
        .sink = old_sink.port(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
    };
    var next_runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(next_owner),
        .sink = next_sink.port(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
    };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    const fact: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = shortcode,
        .fact = .{ .event_type = .run_started },
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.activate(&old_runner, shortcode) == .ok);
    try std.testing.expect(lifecycle.transition(&next_runner, shortcode) == .blocked);
    try std.testing.expect(old_runner.retired);
    try std.testing.expect(!next_sink.held);
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), stabilizer.calls);
}

test "failed active finalization releases the lock and removes the observer" {
    const candidate = bindingCandidate();
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var sink: FaultSink = .{ .fault = .flush };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(owner),
        .sink = sink.port(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
    };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    const fact: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = shortcode,
        .fact = .{ .event_type = .run_started },
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.activate(&runner, shortcode) == .ok);
    const outcome = lifecycle.finalizeActive(shortcode);
    try std.testing.expectEqual(runtime.FailureCode.LOG_FLUSH_FAILURE, outcome.blocked);
    try std.testing.expect(!sink.held);
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), stabilizer.calls);
}

test "sink acquisition failure stabilizes once reports once and blocks" {
    const candidate = bindingCandidate();
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var rejecting_sink: RejectingSink = .{};
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var stabilizer: FakeStabilizer = .{};
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(owner),
        .sink = rejecting_sink.port(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
    };
    const outcome = runner.process(.{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .event_type = .run_started },
    });
    try std.testing.expectEqual(runtime.FailureCode.LOG_LOCK_TIMEOUT, outcome.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), stabilizer.calls);
}

test "stabilization and emergency failures remain fail closed without retry" {
    const candidate = bindingCandidate();
    const owner = try runtime.createValidatedBinding(std.testing.allocator, candidate);
    defer runtime.deinitBindingOwner(owner);
    const policy: logging.CompiledLoggingPolicy = .{
        .level = .{ .threshold = .debug, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var rejecting_sink: RejectingSink = .{};
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{ .emergency_failure = true };
    var stabilizer: FakeStabilizer = .{ .fail = true };
    var runner: runner_module.Runner = .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .binding = runtime.binding(owner),
        .sink = rejecting_sink.port(),
        .clock = clock.port(),
        .console = outputs.console(),
        .emergency_sink = outputs.emergency(),
        .stabilizer = stabilizer.port(),
    };
    const outcome = runner.process(.{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .event_type = .run_started },
    });
    try std.testing.expectEqual(runtime.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
    try std.testing.expectEqual(@as(usize, 1), stabilizer.calls);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_calls);
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_count);
}

fn bindingCandidate() runtime.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = telemetry.Identifier.validate("F0002").?,
    };
}

const FakeClock = struct {
    calls: usize = 0,
    fn port(self: *FakeClock) clock_port.Clock {
        return .{ .context = self, .now_fn = now };
    }
    fn now(context: *anyopaque) clock_port.Error!runtime.ClockReading {
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
    fn port(self: *FaultSink) @import("ports/feature_log_sink.zig").Sink {
        return .{ .context = self, .vtable = &fault_vtable };
    }
};
const fault_vtable: @import("ports/feature_log_sink.zig").Sink.VTable = .{
    .acquire = faultAcquire,
    .recover = faultRecover,
    .create = faultCreate,
    .rotate = faultRotate,
    .close = faultClose,
    .append = faultAppend,
    .prune = faultPrune,
    .release = faultRelease,
};
fn faultAcquire(context: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: u16) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .lock) return error.LockUnavailable;
    self.held = true;
}
fn faultRecover(context: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: []const u8, _: std.mem.Allocator) @import("ports/feature_log_sink.zig").Error!runtime.Recovery {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .recovery) return error.CorruptStream;
    return .{ .empty = .{ .next_segment_ordinal = 1, .next_sequence = 1, .total_segment_count = 0 } };
}
fn faultCreate(_: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, ordinal: u16, seed: runtime.StreamSeed, heading: []const u8, header: []const u8) @import("ports/feature_log_sink.zig").Error!runtime.StreamState {
    return .{ .segment_ordinal = ordinal, .next_sequence = seed.next_sequence, .segment_bytes = heading.len + header.len, .segment_count = 1, .total_segment_count = seed.total_segment_count + 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 };
}
fn faultRotate(context: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, state: runtime.StreamState, _: []const u8, _: []const u8, _: []const u8) @import("ports/feature_log_sink.zig").Error!runtime.StreamState {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .rotation) return error.SinkFailure;
    var next = state;
    next.segment_ordinal += 1;
    next.segment_count += 1;
    next.total_segment_count += 1;
    next.segment_bytes = 0;
    return next;
}
fn faultClose(context: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: runtime.StreamState, _: []const u8) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .flush) return error.FlushFailure;
}
fn faultAppend(context: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, state: runtime.StreamState, row: []const u8, flush: bool) @import("ports/feature_log_sink.zig").Error!runtime.PersistedEvidence {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .flush and flush) return error.FlushFailure;
    return .{ .segment_ordinal = state.segment_ordinal, .sequence = state.next_sequence, .bytes_written = row.len, .flushed = flush };
}
fn faultPrune(context: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: u64) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (self.fault == .retention) return error.SinkFailure;
}
fn faultRelease(context: *anyopaque) @import("ports/feature_log_sink.zig").Error!void {
    const self: *FaultSink = @ptrCast(@alignCast(context));
    if (!self.held) return error.ReleaseFailure;
    self.held = false;
}
const FakeStabilizer = struct {
    calls: usize = 0,
    fail: bool = false,
    fn port(self: *FakeStabilizer) stabilizer_port.Stabilizer {
        return .{ .context = self, .stabilize_fn = stabilize };
    }
    fn stabilize(context: *anyopaque) stabilizer_port.Error!void {
        const self: *FakeStabilizer = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.fail) return error.StabilizationFailure;
    }
};
const RejectingSink = struct {
    calls: usize = 0,
    fn port(self: *RejectingSink) @import("ports/feature_log_sink.zig").Sink {
        return .{ .context = self, .vtable = &rejecting_vtable };
    }
};
const rejecting_vtable: @import("ports/feature_log_sink.zig").Sink.VTable = .{
    .acquire = rejectAcquire,
    .recover = rejectRecover,
    .create = rejectCreate,
    .rotate = rejectRotate,
    .close = rejectClose,
    .append = rejectAppend,
    .prune = rejectPrune,
    .release = rejectRelease,
};
fn rejectAcquire(context: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: u16) @import("ports/feature_log_sink.zig").Error!void {
    const self: *RejectingSink = @ptrCast(@alignCast(context));
    self.calls += 1;
    return error.SinkFailure;
}
fn rejectRecover(_: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: []const u8, _: std.mem.Allocator) @import("ports/feature_log_sink.zig").Error!runtime.Recovery {
    return error.SinkFailure;
}
fn rejectCreate(_: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: u16, _: runtime.StreamSeed, _: []const u8, _: []const u8) @import("ports/feature_log_sink.zig").Error!runtime.StreamState {
    return error.SinkFailure;
}
fn rejectRotate(_: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: runtime.StreamState, _: []const u8, _: []const u8, _: []const u8) @import("ports/feature_log_sink.zig").Error!runtime.StreamState {
    return error.SinkFailure;
}
fn rejectClose(_: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: runtime.StreamState, _: []const u8) @import("ports/feature_log_sink.zig").Error!void {
    return error.SinkFailure;
}
fn rejectAppend(_: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: runtime.StreamState, _: []const u8, _: bool) @import("ports/feature_log_sink.zig").Error!runtime.PersistedEvidence {
    return error.SinkFailure;
}
fn rejectPrune(_: *anyopaque, _: *const runtime.ValidatedFeatureLogBinding, _: runtime.Stream, _: u64) @import("ports/feature_log_sink.zig").Error!void {
    return error.SinkFailure;
}
fn rejectRelease(_: *anyopaque) @import("ports/feature_log_sink.zig").Error!void {
    return error.ReleaseFailure;
}
