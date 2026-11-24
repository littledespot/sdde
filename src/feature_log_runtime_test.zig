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
const retention_routine = @import("application/feature_log_retention_routine.zig");
const runtime_lifecycle = @import("application/feature_log_runtime_lifecycle.zig");
const cancelling = @import("test_fixtures/cancelling_io.zig");
const retention_store = @import("adapters/filesystem/feature_log_retention_store.zig");
const log_file = @import("adapters/filesystem/feature_log_file.zig");

fn portsFor(
    sink: anytype,
    clock: clock_port.Clock,
    console: console_port.Sink,
    emergency: emergency_port.Sink,
) runner_module.Ports {
    return .{
        .clock = clock,
        .acquirer = sink.lockAcquirer(),
        .recoverer = sink.streamRecoverer(),
        .creator = sink.segmentCreator(),
        .rotator = sink.segmentRotator(),
        .appender = sink.recordAppender(),
        .closer = sink.streamCloser(),
        .releaser = sink.lockReleaser(),
        .console = console,
        .emergency = emergency,
    };
}

/// The lifecycle's persist, prepare and finalize on one runner, which is what the old runner offered these tests.
fn processOn(runner: *runner_module.Runner, fact: telemetry.WorkflowTelemetryFact) log_stream.Outcome {
    return runtime_lifecycle.processEvent(runner, fact);
}

fn processPromptOn(runner: *runner_module.Runner, fragment: prompt_log.SanitizedPromptFragment) log_stream.Outcome {
    return runtime_lifecycle.processPrompt(runner, fragment);
}

fn prepareOn(runner: *runner_module.Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
    return runtime_lifecycle.prepare(runner, shortcode);
}

/// Finalizes a runner whose activation these tests skipped: only a prepared, live run is finalized, so such a runner
/// is marked prepared first, and the outcome is read as the old runner's close gave it.
fn closeOn(runner: *runner_module.Runner, shortcode: telemetry.WorkflowShortcode) log_stream.Outcome {
    if (!runner.runtime.retired) runner.runtime.prepared = true;
    return switch (runtime_lifecycle.finalize(runner, shortcode)) {
        .ok => .dropped,
        .blocked => |failure| .{ .blocked = failure },
        .cancelled => .cancelled,
        .invalid => .{ .blocked = .LOG_SINK_FAILURE },
    };
}

/// One prior run's prune through the retention routine, over a fake sink that offers the three pruning ports.
fn retainWith(
    policy: *const log_policy.CompiledLoggingPolicy,
    current: *const log_binding.ValidatedFeatureLogBinding,
    historical: *const log_binding.ValidatedFeatureLogBinding,
    target_stream: log_stream.Stream,
    clock: clock_port.Clock,
    sink: anytype,
) retention_routine.Outcome {
    var diagnostic: retention_routine.Diagnostic = .{};
    return retention_routine.run(
        .{ .clock = clock, .acquirer = sink.lockAcquirer(), .pruner = sink.segmentPruner(), .releaser = sink.lockReleaser() },
        .{ .allocator = std.testing.allocator, .policy = policy, .current = current, .historical = historical, .target_stream = target_stream },
        &diagnostic,
    );
}

/// A stream's cached state when it has one, the state the old runner kept per stream.
fn stateOf(runner: *const runner_module.Runner, comptime stream: log_stream.Stream) ?log_stream.StreamState {
    return switch (switch (stream) {
        .event => runner.runtime.event,
        .prompt => runner.runtime.prompt,
    }) {
        .open => |state| state,
        .unopened, .dropped => null,
    };
}

fn isDropped(runner: *const runner_module.Runner, comptime stream: log_stream.Stream) bool {
    return (switch (stream) {
        .event => runner.runtime.event,
        .prompt => runner.runtime.prompt,
    }) == .dropped;
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
        .ports = portsFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()),
    };
    const attributed: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"),
        .fact = .{ .task_started = .{ .task_id = telemetry.Identifier.validate("TASK-1").? } },
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{ .active = &runner };
    const first = lifecycle.barrier().process(attributed);
    try std.testing.expect(first == .persisted);
    try std.testing.expectEqual(@as(u64, 1), first.persisted.sequence);
    try std.testing.expect(first.persisted.bytes_written > 0);
    try std.testing.expectEqual(@as(u64, 2), stateOf(&runner, .event).?.next_sequence);
    const second = processOn(&runner, attributed);
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
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .run_started = .{} } };
    try std.testing.expect(processOn(&first_runner, fact) == .persisted);
    var file = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_write });
    const size = (try file.stat(io)).size;
    try file.writePositionalAll(io, "partial", size);
    file.close(io);
    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const outcome = processOn(&second_runner, fact);
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
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .run_started = .{} } };

    var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(processOn(&first_runner, fact) == .persisted);
    try std.testing.expect(closeOn(&first_runner, shortcode) == .dropped);

    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const outcome = processOn(&second_runner, fact);
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
    var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .run_started = .{} } };
    try std.testing.expect(processOn(&first_runner, fact) == .persisted);
    var file = try directory.dir.openFile(io, "0001.log", .{ .mode = .read_write });
    try file.setPermissions(io, std.Io.File.Permissions.fromMode(0o644));
    file.close(io);
    var second_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, processOn(&second_runner, fact).blocked);
}

test "restart recovery leaves regular files the engine never names alone and rejects other entries" {
    const io = std.testing.io;
    const Case = enum { strays_only, symlinked_entry, nested_directory };
    for (std.enums.values(Case)) |case| {
        var root = std.testing.tmpDir(.{ .iterate = true });
        defer root.cleanup();
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
        const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .run_started = .{} } };

        var first_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, binding_directory, candidate);
        defer first_sink.deinit();
        var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
        try std.testing.expect(processOn(&first_runner, fact) == .persisted);
        try std.testing.expect(closeOn(&first_runner, shortcode) == .dropped);

        // Stray files in the run directory and this binding.
        for ([_][]const u8{ ".DS_Store", "LOGBIND-1/Thumbs.db" }) |path| {
            try root.dir.writeFile(io, .{ .sub_path = path, .data = "stray" });
        }
        switch (case) {
            .strays_only => {},
            .symlinked_entry => try root.dir.symLink(io, "0001.log", "LOGBIND-1/desktop.ini", .{}),
            .nested_directory => try root.dir.createDir(io, "LOGBIND-1/nested", .default_dir),
        }

        var second_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, binding_directory, candidate);
        defer second_sink.deinit();
        var second_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&second_sink, clock.port(), outputs.console(), outputs.emergency()) };
        const outcome = processOn(&second_runner, fact);
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
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()) };
    const outcome = processOn(&runner, .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .run_started = .{} } });
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
        .ports = portsFor(&rejecting_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const result = processOn(&runner, .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .run_started = .{} },
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
        .ports = portsFor(&sink_adapter, clock.port(), outputs.console(), outputs.emergency()),
    };
    const outcome = processPromptOn(&runner, .{
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
    var runner: runner_module.Runner = .{ .allocator = a, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    const exchange = @import("application/model_exchange_capture.zig");
    // Production constructs the barrier before workflow feature activation.
    var capture: exchange.Capture = .{ .allocator = a, .logs = lifecycle.barrier() };
    defer capture.deinit();
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    try std.testing.expectEqual(.ok, lifecycle.activate(&runner, shortcode));
    capture.begin(.{ .workflow = shortcode, .workflow_id = .{ .bytes = "example" }, .action = .{ .bytes = "invoke-model" }, .node = .{ .bytes = "invoke" }, .operation = .{ .bytes = "generate" }, .model_slot = .{ .bytes = "generation" }, .origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 2 } } });
    defer capture.end();
    const padding = try a.alloc(u8, 11000);
    defer a.free(padding);
    @memset(padding, 'x');
    const request = try std.mem.concat(a, u8, &.{ "first prompt credential-value ", padding, " final prompt text" });
    defer a.free(request);
    try std.testing.expectEqual(.recorded, capture.port().capture(.request, .{ .provider_body = request }, &.{"credential-value"}));
    try std.testing.expectEqual(.recorded, capture.port().capture(.response, .{ .provider_body = "malformed response credential-value {" }, &.{"credential-value"}));
    try std.testing.expect(closeOn(&runner, shortcode) != .blocked);
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
        .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    try std.testing.expect(processPromptOn(&runner, .{
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
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .run_completed = .{ .outcome = .completed } } };

    inline for (.{ Fault.lock, Fault.recovery, Fault.flush, Fault.console, Fault.rotation }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{ .console_failure = fault == .console };
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (fault == .rotation) runner.runtime.event = .{ .open = .{
            .segment_ordinal = 1,
            .next_sequence = 1,
            .segment_bytes = log_limits.max_segment_bytes - 1,
            .segment_count = 1,
            .total_segment_count = 1,
            .records_since_flush = 0,
            .last_flush_monotonic_ms = 0,
        } };
        const outcome = processOn(&runner, fact);
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
    const retention = retainWith(&policy, log_binding.binding(owner), log_binding.binding(historical_owner), .event, retention_clock.port(), &retention_sink);
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, retention.stopped.blocked);
}

const full_segment: log_stream.StreamState = .{
    .segment_ordinal = 1,
    .next_sequence = 3,
    .segment_bytes = log_limits.max_segment_bytes - 1,
    .segment_count = 1,
    .total_segment_count = 1,
    .records_since_flush = 0,
    .last_flush_monotonic_ms = 0,
};

fn seedStream(runner: *runner_module.Runner, comptime stream: log_stream.Stream, state: log_stream.StreamState) void {
    switch (stream) {
        .event => runner.runtime.event = .{ .open = state },
        .prompt => runner.runtime.prompt = .{ .open = state },
    }
}

fn persistOneRow(runner: *runner_module.Runner, comptime stream: log_stream.Stream) !log_stream.Outcome {
    return switch (stream) {
        .event => processOn(runner, .{
            .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
            .fact = .{ .run_completed = .{ .outcome = .completed } },
        }),
        .prompt => processPromptOn(runner, .{
            .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
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
        }),
    };
}

test "a full segment rotates before its row, a spent segment budget writes nothing and a failed rotation keeps the old state, in either stream" {
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };

    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        {
            var sink: FaultSink = .{ .fault = .none };
            var clock: FakeClock = .{};
            var outputs: FakeOutputs = .{};
            var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
            seedStream(&runner, stream, full_segment);
            const outcome = try persistOneRow(&runner, stream);
            try std.testing.expect(outcome == .persisted);
            // The row opens the next segment, and the cached state follows it.
            try std.testing.expectEqual(@as(u16, 2), outcome.persisted.segment_ordinal);
            // The row itself names the segment it opens, not the full one it replaced.
            try std.testing.expectEqual(@as(u16, 2), sink.row_segment_ordinal);
            try std.testing.expectEqual(@as(usize, 1), sink.rotated);
            try std.testing.expectEqual(@as(usize, 1), sink.appended);
            const state = stateOf(&runner, stream).?;
            try std.testing.expectEqual(@as(u16, 2), state.segment_ordinal);
            try std.testing.expectEqual(@as(u8, 2), state.segment_count);
            try std.testing.expectEqual(@as(u64, 4), state.next_sequence);
            try std.testing.expectEqual(@as(usize, 0), outputs.emergency_count);
        }
        {
            var spent = full_segment;
            spent.total_segment_count = log_limits.max_segments;
            var sink: FaultSink = .{ .fault = .none };
            var clock: FakeClock = .{};
            var outputs: FakeOutputs = .{};
            var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
            seedStream(&runner, stream, spent);
            const outcome = try persistOneRow(&runner, stream);
            try std.testing.expect(outcome == .blocked);
            try std.testing.expectEqual(log_stream.FailureCode.LOG_SEGMENT_LIMIT_EXHAUSTED, outcome.blocked);
            try std.testing.expectEqual(@as(usize, 0), sink.rotated);
            try std.testing.expectEqual(@as(usize, 0), sink.appended);
            try std.testing.expectEqual(spent, stateOf(&runner, stream).?);
            try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
        }
        {
            var sink: FaultSink = .{ .fault = .rotation };
            var clock: FakeClock = .{};
            var outputs: FakeOutputs = .{};
            var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
            seedStream(&runner, stream, full_segment);
            const outcome = try persistOneRow(&runner, stream);
            try std.testing.expect(outcome == .blocked);
            try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
            try std.testing.expectEqual(@as(usize, 0), sink.appended);
            try std.testing.expectEqual(full_segment, stateOf(&runner, stream).?);
            try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
        }
    }
}

test "the active binding activates once, persists, retains history and finalizes" {
    const io = std.testing.io;
    var root = std.testing.tmpDir(.{ .iterate = true });
    defer root.cleanup();
    var prompt_root = std.testing.tmpDir(.{ .iterate = true });
    defer prompt_root.cleanup();
    try root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
    try prompt_root.dir.createDir(io, "LOGBIND-1", std.Io.File.Permissions.fromMode(0o700));
    var old_directory = try root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
    defer old_directory.close(io);
    var old_prompt_directory = try prompt_root.dir.openDir(io, "LOGBIND-1", .{ .iterate = true });
    defer old_prompt_directory.close(io);
    const old_candidate = bindingCandidate();
    const old_owner = try log_binding.createValidated(std.testing.allocator, old_candidate);
    defer log_binding.deinitOwner(old_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var old_sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, old_directory, old_candidate);
    old_sink.prompt_run_directory = prompt_root.dir;
    old_sink.prompt_directory = old_prompt_directory;
    defer old_sink.deinit();
    var old_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .ports = portsFor(&old_sink, clock.port(), outputs.console(), outputs.emergency()) };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .run_started = .{} } };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.barrier().process(fact) == .blocked);
    try std.testing.expect(lifecycle.activate(&old_runner, fact.workflow_shortcode) == .ok);
    try std.testing.expect(stateOf(&old_runner, .prompt) != null);
    try std.testing.expect(lifecycle.activate(&old_runner, fact.workflow_shortcode) == .invalid);
    try std.testing.expect(lifecycle.barrier().process(fact) == .persisted);
    try std.testing.expectEqual(@as(u64, 2), stateOf(&old_runner, .event).?.next_sequence);

    const historical_candidate: log_binding.BindingCandidate = .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = old_candidate.feature_id,
    };
    const historical_owner = try log_binding.createValidated(std.testing.allocator, historical_candidate);
    defer log_binding.deinitOwner(historical_owner);
    var retention_clock: FakeClock = .{};
    var retention_sink: FaultSink = .{ .fault = .retention };
    const retention = lifecycle.retainHistorical(
        .{ .clock = retention_clock.port(), .acquirer = retention_sink.lockAcquirer(), .pruner = retention_sink.segmentPruner(), .releaser = retention_sink.lockReleaser() },
        .{ .allocator = std.testing.allocator, .policy = &policy, .current = log_binding.binding(old_owner), .historical = log_binding.binding(historical_owner), .target_stream = .event },
        fact.workflow_shortcode,
    );
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, retention.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    try std.testing.expect(lifecycle.finalizeActive(&old_runner, fact.workflow_shortcode) == .ok);
    try std.testing.expect(old_runner.runtime.retired);
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
    const authorization = try retention_routine.steps.authorize(
        clock.port(),
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
        retention_routine.steps.authorize(
            clock.port(),
            std.testing.allocator,
            &invalid_policy,
            log_binding.binding(current_owner),
            log_binding.binding(historical_owner),
            .event,
        ),
    );
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
        .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    const fact: telemetry.WorkflowTelemetryFact = .{
        .workflow_shortcode = shortcode,
        .fact = .{ .run_started = .{} },
    };
    var lifecycle: runtime_lifecycle.Lifecycle = .{};
    try std.testing.expect(lifecycle.activate(&runner, shortcode) == .ok);
    const outcome = lifecycle.finalizeActive(&runner, shortcode);
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
        .ports = portsFor(&rejecting_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const outcome = processOn(&runner, .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .run_started = .{} },
    });
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), rejecting_sink.calls);
    try std.testing.expect(stateOf(&runner, .event) == null);
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
        .ports = portsFor(&rejecting_sink, clock.port(), outputs.console(), outputs.emergency()),
    };
    const outcome = processOn(&runner, .{
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"),
        .fact = .{ .run_started = .{} },
    });
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, outcome.blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_calls);
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_count);
    try std.testing.expectEqual(@as(usize, 1), rejecting_sink.calls);
    try std.testing.expect(stateOf(&runner, .event) == null);
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
    /// Rotations and appends the sink completed, so a test can show that a blocked persist wrote nothing.
    rotated: usize = 0,
    appended: usize = 0,
    /// The segment ordinal the last appended row names in its own cell, so a test can show a row was rendered
    /// against the segment it was appended to.
    row_segment_ordinal: u16 = 0,
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
    self.rotated += 1;
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
    self.appended += 1;
    const format = @import("domain/feature_log_format.zig");
    self.row_segment_ordinal = std.fmt.parseInt(u16, format.cellAt(row, format.sharedColumn("segment_ordinal")).?, 10) catch 0;
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
                const code = telemetry.fieldOf(fact.fact, .diagnostic_code) orelse return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
                if (!std.mem.eql(u8, code.bytes, "MODEL_CAPTURE_LINEAGE_FAILURE_MISSING_SOURCE")) return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
                if (telemetry.eventOf(fact.fact) == .run_blocked) {
                    const common = telemetry.commonOf(fact.fact);
                    const correlation = common.correlation_id orelse return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
                    if (!std.mem.eql(u8, correlation.bytes, "request-7-inference-1") or common.attempt != 1) return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
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
        try std.testing.expectEqual(expected, events.emit(.{ .run_started = .{} }));
        try std.testing.expectEqual(expected, events.action(node, null, null, null));
        for (std.enums.values(@import("domain/workflow.zig").OutcomeTag)) |status| {
            try std.testing.expectEqual(expected, events.action(node, .{ .outcome = status }, null, null));
            if (status != .more) try std.testing.expectEqual(expected, events.terminal(.{ .execution = status }));
        }
        try std.testing.expectEqual(expected, events.action(node, .{ .rejected = .{ .authority = .kernel_stage } }, null, null));
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SERIALIZATION_FAILURE }, events.terminal(.{ .execution = .more }).?);
        try std.testing.expectEqual(expected, events.validation(node, .ok, null, null));
        try std.testing.expectEqual(expected, events.validation(node, .invalid, "WRONG_SHAPE", null));
        try std.testing.expectEqual(expected, events.repair(node, .requested));
        try std.testing.expectEqual(expected, events.repair(node, .{ .applied = .ok }));
        try std.testing.expectEqual(expected, events.repair(node, .{ .rejected = .{ .status = .invalid, .reason = "REPAIR_RECURRING" } }));
        try std.testing.expectEqual(expected, events.retryAttempt(node, 2, false));
        try std.testing.expectEqual(expected, events.retryAttempt(node, 3, true));
        try std.testing.expectEqual(expected, events.emit(.{ .publication_prepared = .{ .outcome = .needs_user } }));
        spy.expect_capture = true;
        const rejected: @import("domain/workflow_execution.zig").Rejection = .{ .model_capture = .{ .code = .LOG_SERIALIZATION_FAILURE, .stage = .lineage, .cause = .{ .lineage = .missing_source }, .origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } }, .direction = .request } };
        try std.testing.expectEqual(expected, events.action(node, .{ .rejected = rejected }, null, null));
        try std.testing.expectEqual(expected, events.terminal(.{ .execution_rejected = rejected }));
        spy.expect_capture = false;
    }
    try std.testing.expect(spy.count > 0);
}

// The order of the retention steps, the release after any prune outcome, the prune stop kept over a release failure and
// the cancelled acquire and prune are the retention routine's, and its tests (feature_log_retention_routine_test.zig)
// run them against fake ports. What its entry function cannot reach is the stream resolution, which it feeds the same
// bindings it authorized with, so that step is held here.
test "retention resolves no stream for an authorization made for other bindings" {
    const current_owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(current_owner);
    const historical_owner = try log_binding.createValidated(std.testing.allocator, .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-HIST").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-HIST").?,
        .run_id = telemetry.Identifier.validate("RUN-HIST").?,
        .feature_id = bindingCandidate().feature_id,
    });
    defer log_binding.deinitOwner(historical_owner);
    const other_owner = try log_binding.createValidated(std.testing.allocator, .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-OTHER").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-OTHER").?,
        .run_id = telemetry.Identifier.validate("RUN-OTHER").?,
        .feature_id = bindingCandidate().feature_id,
    });
    defer log_binding.deinitOwner(other_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    var clock: FakeClock = .{};
    const authorization = try retention_routine.steps.authorize(clock.port(), std.testing.allocator, &policy, log_binding.binding(current_owner), log_binding.binding(historical_owner), .prompt);
    defer log_retention.deinit(authorization);
    try std.testing.expectEqual(log_stream.Stream.prompt, try retention_routine.steps.resolveStream(authorization, log_binding.binding(current_owner), log_binding.binding(historical_owner)));
    try std.testing.expectError(error.FeatureLogRetentionAuthorizationInvalid, retention_routine.steps.resolveStream(authorization, log_binding.binding(other_owner), log_binding.binding(historical_owner)));
    try std.testing.expectError(error.FeatureLogRetentionAuthorizationInvalid, retention_routine.steps.resolveStream(authorization, log_binding.binding(current_owner), log_binding.binding(other_owner)));
}

test "cancellation under the feature log lock is a cancellation: no emergency line, lock released, runner reusable" {
    const owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("SPEC"), .fact = .{ .run_started = .{} } };
    // The lock, recovery, rotation and append are four sink operations; none of them reports a logging failure.
    inline for (.{ Fault.cancel_lock, Fault.cancel_recovery, Fault.cancel_rotation, Fault.cancel_append }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (fault == .cancel_rotation or fault == .cancel_append) runner.runtime.event = .{ .open = .{
            .segment_ordinal = 1,
            .next_sequence = 1,
            .segment_bytes = if (fault == .cancel_rotation) log_limits.max_segment_bytes - 1 else 0,
            .segment_count = 1,
            .total_segment_count = 1,
            .records_since_flush = 0,
            .last_flush_monotonic_ms = 0,
        } };
        try std.testing.expect(processOn(&runner, fact) == .cancelled);
        try std.testing.expect(!sink.held);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
        // Nothing was retired or advanced: once the sink stops cancelling, the same fact persists.
        sink.fault = .none;
        try std.testing.expect(processOn(&runner, fact) == .persisted);
    }
}

test "a lock that cannot be released after a cancelled step is a logging failure of its own" {
    const owner = try log_binding.createValidated(std.testing.allocator, bindingCandidate());
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .run_started = .{} } };
    inline for (.{ Fault.cancel_append_release_fails, Fault.cancel_close_release_fails }) |fault| {
        var sink: FaultSink = .{ .fault = fault };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        const outcome = if (fault == .cancel_append_release_fails) processOn(&runner, fact) else close: {
            runner.runtime.event = .{ .open = .{ .segment_ordinal = 1, .next_sequence = 1, .segment_bytes = 0, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 } };
            break :close closeOn(&runner, shortcode);
        };
        // The release failure outranks the cancellation before it, and is reported once like any logging failure.
        try std.testing.expectEqual(log_stream.FailureCode.LOG_RELEASE_FAILURE, outcome.blocked);
        try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
        // The cancelled close may have written its trailer, so the stream's state is dropped whatever the release did.
        if (fault == .cancel_close_release_fails) try std.testing.expect(stateOf(&runner, .event) == null and isDropped(&runner, .event));
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
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (fault == .cancel_recovery) {
            try std.testing.expect(prepareOn(&runner, shortcode) == .cancelled);
            try std.testing.expect(!runner.runtime.prepared);
        } else {
            runner.runtime.event = .{ .open = .{ .segment_ordinal = 1, .next_sequence = 1, .segment_bytes = 0, .segment_count = 1, .total_segment_count = 1, .records_since_flush = 0, .last_flush_monotonic_ms = 0 } };
            try std.testing.expect(closeOn(&runner, shortcode) == .cancelled);
            try std.testing.expect(!runner.runtime.retired);
            // The trailer may already be written, so the cached state is dropped and a later close recovers it.
            try std.testing.expect(stateOf(&runner, .event) == null and isDropped(&runner, .event));
        }
        try std.testing.expect(!sink.held);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    }
}

test "cancelled activation and finalization end as cancellation and release the lock" {
    const old_candidate = bindingCandidate();
    const old_owner = try log_binding.createValidated(std.testing.allocator, old_candidate);
    defer log_binding.deinitOwner(old_owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");

    // Activation prepares the stream, which recovers it under the lock.
    {
        var sink: FaultSink = .{ .fault = .cancel_recovery };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        var lifecycle: runtime_lifecycle.Lifecycle = .{};
        try std.testing.expect(lifecycle.activate(&runner, shortcode) == .cancelled);
        try std.testing.expect(lifecycle.active == null);
        try std.testing.expect(!sink.held);
        try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    }
    // Finalization closes the stream under the lock.
    {
        var sink: FaultSink = .{ .fault = .cancel_close };
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(old_owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        var lifecycle: runtime_lifecycle.Lifecycle = .{};
        try std.testing.expect(lifecycle.activate(&runner, shortcode) == .ok);
        try std.testing.expect(lifecycle.finalizeActive(&runner, shortcode) == .cancelled);
        try std.testing.expect(lifecycle.active == null);
        try std.testing.expect(!sink.held);
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
    try std.testing.expectEqual(log_stream.Stop.cancelled, retainWith(&policy, log_binding.binding(owner), log_binding.binding(historical_owner), .event, clock.port(), &sink).stopped);
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
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .run_started = .{} } };
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
            var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
            try std.testing.expect(processOn(&first_runner, fact) == .persisted);
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
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        try std.testing.expect(processOn(&runner, fact) == .cancelled);
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
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(processOn(&runner, fact) == .persisted);
}

test "a cancelled console mirror write under the lock is a cancellation, and the row it followed is recovered" {
    const io = std.testing.io;
    var directory = std.testing.tmpDir(.{ .iterate = true });
    defer directory.cleanup();
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true };
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"), .fact = .{ .run_started = .{} } };
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(processOn(&runner, fact) == .persisted);
    outputs.console_cancel = true;
    try std.testing.expect(processOn(&runner, fact) == .cancelled);
    try std.testing.expect(sink.lock_file == null);
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    // The second row was appended and the state advanced before its console write; a cancellation still drops that
    // state (ADR 0032) and the next persist recovers it from the bytes, so the next event continues the sequence.
    outputs.console_cancel = false;
    const next = processOn(&runner, fact);
    try std.testing.expect(next == .persisted);
    try std.testing.expectEqual(@as(u64, 3), next.persisted.sequence);
    // The recovered state is the cache again, so the mark is cleared.
    try std.testing.expect(!isDropped(&runner, .event) and !isDropped(&runner, .prompt) and stateOf(&runner, .event) != null);
    // A console failure that is no cancellation stays a logging failure.
    outputs.console_failure = true;
    try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, processOn(&runner, fact).blocked);
    try std.testing.expectEqual(@as(usize, 1), outputs.emergency_count);
}

/// A sink whose append reaches the file and then, when the append asks for a flush, reports a flush failure on
/// request, as the real sink does when its sync fails: the row is on disk, and the runner's cached state does not
/// include it.
const FlushFailsAfterWrite = struct {
    real: *filesystem_sink.Adapter,
    fail: bool = false,
    fn lockAcquirer(self: *FlushFailsAfterWrite) sink_port.LockAcquirer {
        return self.real.lockAcquirer();
    }
    fn lockReleaser(self: *FlushFailsAfterWrite) sink_port.LockReleaser {
        return self.real.lockReleaser();
    }
    fn streamRecoverer(self: *FlushFailsAfterWrite) sink_port.StreamRecoverer {
        return self.real.streamRecoverer();
    }
    fn segmentCreator(self: *FlushFailsAfterWrite) sink_port.SegmentCreator {
        return self.real.segmentCreator();
    }
    fn segmentRotator(self: *FlushFailsAfterWrite) sink_port.SegmentRotator {
        return self.real.segmentRotator();
    }
    fn streamCloser(self: *FlushFailsAfterWrite) sink_port.StreamCloser {
        return self.real.streamCloser();
    }
    fn recordAppender(self: *FlushFailsAfterWrite) sink_port.RecordAppender {
        return .{ .context = self, .append_fn = appendThenFail };
    }
    fn appendThenFail(context: *anyopaque, binding: *const log_binding.ValidatedFeatureLogBinding, stream: log_stream.Stream, state: log_stream.StreamState, row: []const u8, flush: bool) sink_port.Error!log_stream.PersistedEvidence {
        const self: *FlushFailsAfterWrite = @ptrCast(@alignCast(context));
        const evidence = try self.real.recordAppender().append(binding, stream, state, row, flush);
        if (self.fail and flush) return error.FlushFailure;
        return evidence;
    }
};

// A cancelled persist recovers its stream's state from the bytes (ADR 0032). The console is only a mirror (ADR 0018), so
// a console failure after an appended row leaves the stream's state level with the file: the next append and the close
// continue it. A flush failure after the write may or may not have made the bytes durable and recovers nothing: the
// state stays behind the file, so the next append and the close fail, and the segment keeps the failed row without a
// trailer, the crash shape ADR 0026 keeps whole.
test "after a console failure the next append and the close continue the file, and after a flush failure they leave it as it was" {
    const io = std.testing.io;
    const Kind = enum { console, flush };
    for ([_]log_stream.Stream{ .event, .prompt }) |stream| for ([_]Kind{ .console, .flush }) |kind| {
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
        // Every append flushes, so the flush the sink reports as failed is one the real sink would perform.
        const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = true, .lower_level_flush_records = 1 };
        const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
        const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .run_started = .{} } };
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
        var real = filesystem_sink.Adapter.initForTestLayout(io, root.dir, event_directory, candidate);
        real.prompt_run_directory = prompt_root.dir;
        real.prompt_directory = prompt_directory;
        defer real.deinit();
        var sink: FlushFailsAfterWrite = .{ .real = &real };
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        try std.testing.expect(prepareOn(&runner, shortcode) == .dropped);
        try std.testing.expect(processOn(&runner, fact) == .persisted);
        try std.testing.expect(processPromptOn(&runner, fragment) == .persisted);
        switch (kind) {
            .console => outputs.console_failure = true,
            .flush => sink.fail = true,
        }
        // The row reaches the file before the failure.
        const failed = switch (stream) {
            .event => processOn(&runner, fact),
            .prompt => processPromptOn(&runner, fragment),
        };
        try std.testing.expectEqual(if (kind == .console) log_stream.FailureCode.LOG_SINK_FAILURE else log_stream.FailureCode.LOG_FLUSH_FAILURE, failed.blocked);
        const directory = if (stream == .event) event_directory else prompt_directory;
        const before = try directory.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
        defer std.testing.allocator.free(before);
        outputs.console_failure = false;
        sink.fail = false;
        const next = switch (stream) {
            .event => processOn(&runner, fact),
            .prompt => processPromptOn(&runner, fragment),
        };
        const closed = closeOn(&runner, shortcode);
        const after = try directory.readFileAlloc(io, "0001.log", std.testing.allocator, .limited(log_limits.max_segment_bytes));
        defer std.testing.allocator.free(after);
        switch (kind) {
            .console => {
                // The failed row stays, the next row follows it at the right offset, and the stream closes with its
                // trailer.
                try std.testing.expect(next == .persisted);
                try std.testing.expect(closed != .blocked);
                try std.testing.expect(after.len > before.len and std.mem.startsWith(u8, after, before));
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, after, "segment_trailer|"));
            },
            .flush => {
                // The runner's state is one row behind the file: no later row is written at a wrong offset and no
                // trailer is written over the row.
                try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, next.blocked);
                try std.testing.expectEqual(log_stream.FailureCode.LOG_SINK_FAILURE, closed.blocked);
                try std.testing.expectEqualStrings(before, after);
                // The segment keeps the failed row and no trailer: the crash shape ADR 0026 keeps whole.
                try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, after, "segment_trailer|"));
                try std.testing.expect(std.mem.endsWith(u8, after, "\n"));
            },
        }
    };
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
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .run_started = .{} } };
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
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
    try std.testing.expect(prepareOn(&runner, shortcode) == .dropped);
    try std.testing.expect(processOn(&runner, fact) == .persisted);
    try std.testing.expect(processPromptOn(&runner, fragment) == .persisted);
    // Each stream's second row is appended and then its console mirror write is cancelled: the file is ahead of the cache.
    outputs.console_cancel = true;
    try std.testing.expect(processOn(&runner, fact) == .cancelled);
    try std.testing.expect(processPromptOn(&runner, fragment) == .cancelled);
    outputs.console_cancel = false;
    try std.testing.expect(stateOf(&runner, .event) == null and isDropped(&runner, .event));
    try std.testing.expect(stateOf(&runner, .prompt) == null and isDropped(&runner, .prompt));
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_calls);
    // Finalization is not skipped for a dropped stream: each is recovered under its lock and closed with its trailer.
    try std.testing.expect(closeOn(&runner, shortcode) == .dropped);
    try std.testing.expect(!isDropped(&runner, .event) and !isDropped(&runner, .prompt) and runner.runtime.retired);
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
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .run_started = .{} } };
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
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        if (processOn(&runner, fact) != .persisted) continue;
        if (closeOn(&runner, shortcode) != .cancelled) continue;
        reached[index] += 1;
        // A cancel inside the close drops the state; one at the lock came before any write and keeps it. Never both.
        try std.testing.expectEqual(stateOf(&runner, .event) == null, isDropped(&runner, .event));
        try std.testing.expect(!runner.runtime.retired);
        try std.testing.expect(closeOn(&runner, shortcode) == .dropped);
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
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        const prepared = prepareOn(&runner, shortcode);
        if (case.close_phase) {
            // Cancelled flushes follow their trailer's bytes, so a stream that was attempted has its trailer.
            if (prepared != .dropped or closeOn(&runner, shortcode) != .cancelled) continue;
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
        var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), outputs.console(), outputs.emergency()) };
        runner.runtime.event = .dropped;
        const outcome = closeOn(&runner, shortcode);
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
        try std.testing.expect(isDropped(&runner, .event) and !runner.runtime.retired);
    }
}

test "a filesystem cancellation while retention prunes closed segments is a cancellation and deletes nothing more" {
    const io = std.testing.io;
    const candidate = bindingCandidate();
    const owner = try log_binding.createValidated(std.testing.allocator, candidate);
    defer log_binding.deinitOwner(owner);
    const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };
    const shortcode = try telemetry.WorkflowShortcode.parse("IMPL");
    const fact: telemetry.WorkflowTelemetryFact = .{ .workflow_shortcode = shortcode, .fact = .{ .run_started = .{} } };
    for ([_]cancelling.Op{ .dir_read, .open_file, .stat, .read_positional, .delete_file }) |op| {
        var directory = std.testing.tmpDir(.{ .iterate = true });
        defer directory.cleanup();
        var clock: FakeClock = .{};
        var outputs: FakeOutputs = .{};
        var first_sink = filesystem_sink.Adapter.initForTest(io, directory.dir, candidate);
        var first_runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&first_sink, clock.port(), outputs.console(), outputs.emergency()) };
        try std.testing.expect(processOn(&first_runner, fact) == .persisted);
        try std.testing.expect(closeOn(&first_runner, shortcode) == .dropped);
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
    try std.testing.expectEqual(cancelled, events.emit(.{ .run_started = .{} }));
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

/// Captures the console mirror's bytes, so the golden run proves them too.
const ConsoleCapture = struct {
    bytes: std.ArrayList(u8) = .empty,

    fn sink(self: *ConsoleCapture) console_port.Sink {
        return .{ .context = self, .write_fn = write };
    }
    fn write(context: *anyopaque, bytes: []const u8) console_port.Error!void {
        const self: *ConsoleCapture = @ptrCast(@alignCast(context));
        self.bytes.appendSlice(std.testing.allocator, bytes) catch return error.ConsoleWriteFailure;
    }
};

fn digestHex(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}

/// Pads the open segment with filler up to `remaining` bytes below the segment limit, and records that size in the
/// cached state, as a segment that real rows filled would be. The filler is the test's, never a log row.
fn fillSegment(io: std.Io, directory: std.Io.Dir, state: *log_stream.StreamState, remaining: usize) !void {
    var file = try directory.openFile(io, "0001.log", .{ .mode = .read_write });
    defer file.close(io);
    const size = (try file.stat(io)).size;
    const filler = [_]u8{'x'} ** 4096;
    var written: u64 = size;
    const target: u64 = log_limits.max_segment_bytes - remaining;
    while (written < target) {
        const chunk: usize = @intCast(@min(filler.len, target - written));
        try file.writePositionalAll(io, filler[0..chunk], written);
        written += chunk;
    }
    state.segment_bytes = written;
}

// The byte-identity proof for log output (SPEC01 E3): a small run written through the real filesystem sink with a
// fake clock covers both streams' rows, a rotation in each stream, the console mirror and the close, and every
// segment's bytes and the console's bytes are pinned. The structural parts (headings and headers) are derived from
// the production serializers; each segment's SHA-256 pins the rest. The logging conversion must leave every one of
// these unchanged.
test "golden log segment bytes: rows, rotation, console mirror and close are byte-identical across the logging conversion" {
    const io = std.testing.io;
    const format = @import("domain/feature_log_format.zig");
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
    var sink = filesystem_sink.Adapter.initForTestLayout(io, root.dir, event_directory, candidate);
    sink.prompt_run_directory = prompt_root.dir;
    sink.prompt_directory = prompt_directory;
    defer sink.deinit();
    var clock: FakeClock = .{};
    var outputs: FakeOutputs = .{};
    var console: ConsoleCapture = .{};
    defer console.bytes.deinit(std.testing.allocator);
    var runner: runner_module.Runner = .{ .allocator = std.testing.allocator, .policy = &policy, .binding = log_binding.binding(owner), .ports = portsFor(&sink, clock.port(), console.sink(), outputs.emergency()) };
    const shortcode = try telemetry.WorkflowShortcode.parse("SPEC");

    try std.testing.expect(prepareOn(&runner, shortcode) == .dropped);
    const facts = [_]telemetry.TelemetryFact{
        .{ .run_started = .{} },
        .{ .task_started = .{ .task_id = telemetry.Identifier.validate("TASK-1").? } },
        .{ .run_completed = .{ .outcome = .completed } },
    };
    for (facts[0..2]) |fact| try std.testing.expect(processOn(&runner, .{ .workflow_shortcode = shortcode, .fact = fact }) == .persisted);
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
    try std.testing.expect(processPromptOn(&runner, fragment) == .persisted);

    // A segment that real rows filled rotates before the next row, in either stream.
    try fillSegment(io, event_directory, &runner.runtime.event.open, 400);
    try fillSegment(io, prompt_directory, &runner.runtime.prompt.open, 400);
    const rotated_event = processOn(&runner, .{ .workflow_shortcode = shortcode, .fact = facts[2] });
    try std.testing.expect(rotated_event == .persisted);
    try std.testing.expectEqual(@as(u16, 2), rotated_event.persisted.segment_ordinal);
    const rotated_prompt = processPromptOn(&runner, fragment);
    try std.testing.expect(rotated_prompt == .persisted);
    try std.testing.expectEqual(@as(u16, 2), rotated_prompt.persisted.segment_ordinal);
    try std.testing.expect(closeOn(&runner, shortcode) == .dropped);
    try std.testing.expectEqual(@as(usize, 0), outputs.emergency_count);

    const names = [_][]const u8{ "0001.log", "0002.log" };
    var digests: [5][64]u8 = undefined;
    var index: usize = 0;
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        const directory = if (stream == .event) event_directory else prompt_directory;
        for (names, 1..) |name, ordinal| {
            const bytes = try directory.readFileAlloc(io, name, std.testing.allocator, .limited(log_limits.max_segment_bytes));
            defer std.testing.allocator.free(bytes);
            const header = try format.serializeControl(std.testing.allocator, stream, .{
                .kind = .segment_header,
                .log_policy_id = log_binding.binding(owner).logPolicyId(),
                .binding_id = log_binding.binding(owner).bindingId(),
                .segment_ordinal = @intCast(ordinal),
                .final_sequence = null,
                .occurred_at_utc = "2026-08-30T10:15:30Z",
                .run_id = log_binding.binding(owner).runId(),
                .feature_id = log_binding.binding(owner).featureId(),
            });
            defer std.testing.allocator.free(header);
            try std.testing.expect(std.mem.startsWith(u8, bytes, format.segmentHeading(stream)));
            try std.testing.expect(std.mem.startsWith(u8, bytes[format.segmentHeading(stream).len..], header));
            // Every segment but the open one ends in its trailer, and the closed run ends in one too.
            try std.testing.expect(std.mem.endsWith(u8, bytes, "\n"));
            digests[index] = digestHex(bytes);
            index += 1;
        }
    }
    digests[index] = digestHex(console.bytes.items);
    const expected = [_][]const u8{
        "f61a270f8898a770c7f417ace117bae005185060c906485391e04824af0b7fe8",
        "11404373b8ab2b28bdd4725846d1b9b5a7eeda39883dfab1398afd5488118995",
        "9b3fd344ca12c74ec8445958e26caa61cc6ff2e6f30ecd4b9c63f6d5f76a6450",
        "23af14e24ca28ae541625f02ac00e808f6e2cc6c09296a49e6537c8f877832f5",
        "5feee973e9f5d9ceefa9b80686cb6639497e97bd6b22094553886e87a5c48443",
    };
    var mismatch = false;
    for (digests, expected) |actual, golden| {
        if (!std.mem.eql(u8, &actual, golden)) {
            mismatch = true;
            std.debug.print("golden log digest {s} (expected {s})\n", .{ actual, golden });
        }
    }
    try std.testing.expect(!mismatch);
}
