const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const toolchain = @import("domain/toolchain.zig");
const safety = @import("domain/toolchain_safety.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const compilation = @import("domain/workflow_compilation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const schemas = @import("application/toolchain_workflow_values.zig");
const runners = @import("application/toolchain_workflow_runner.zig");
const bindings = @import("application/workflow_operation_binding.zig");
const stage = @import("actions/toolchain/prepare_toolchain.zig");
const steps = stage.steps;

// ADR 0031: the nine absorbed steps are tested as functions with fake ports, and the stage
// at its edge: its contract, every failing step, cancellation between steps and cleanup.

const no_policies: toolchain.PolicyRegistry = .{ .contracts = &.{} };

const key_schema: toolchain.RawNode = .{ .scalar = "schema" };
const key_presets: toolchain.RawNode = .{ .scalar = "presets" };
const key_policies: toolchain.RawNode = .{ .scalar = "policies" };
const key_package: toolchain.RawNode = .{ .scalar = "package" };
const key_layer: toolchain.RawNode = .{ .scalar = "layer" };
const key_extends: toolchain.RawNode = .{ .scalar = "extends" };
const project_schema_value: toolchain.RawNode = .{ .scalar = toolchain.project_schema };
const preset_schema_value: toolchain.RawNode = .{ .scalar = toolchain.preset_schema };
const base_ref: toolchain.RawNode = .{ .scalar = "base@1.0.0" };
const absent_ref: toolchain.RawNode = .{ .scalar = "absent@1.0.0" };
const missing_ref: toolchain.RawNode = .{ .scalar = "missing@1.0.0" };
const unknown_policy_ref: toolchain.RawNode = .{ .scalar = "unknown.policy@1" };
const layer_value: toolchain.RawNode = .{ .scalar = "language" };
const empty_sequence: toolchain.RawNode = .{ .sequence = &.{} };
const base_sequence: toolchain.RawNode = .{ .sequence = &.{&base_ref} };
const absent_sequence: toolchain.RawNode = .{ .sequence = &.{&absent_ref} };
const missing_sequence: toolchain.RawNode = .{ .sequence = &.{&missing_ref} };
const unknown_policy_sequence: toolchain.RawNode = .{ .sequence = &.{&unknown_policy_ref} };

fn projectRoot(presets: *const toolchain.RawNode, policies: *const toolchain.RawNode) toolchain.RawNode {
    return .{ .mapping = &.{
        .{ .key = &key_schema, .value = &project_schema_value },
        .{ .key = &key_presets, .value = presets },
        .{ .key = &key_policies, .value = policies },
    } };
}
fn presetRoot(extends: *const toolchain.RawNode) toolchain.RawNode {
    return .{ .mapping = &.{
        .{ .key = &key_schema, .value = &preset_schema_value },
        .{ .key = &key_package, .value = &base_ref },
        .{ .key = &key_layer, .value = &layer_value },
        .{ .key = &key_extends, .value = extends },
        .{ .key = &key_policies, .value = &empty_sequence },
    } };
}
const project_root = projectRoot(&base_sequence, &empty_sequence);
const missing_preset_project_root = projectRoot(&missing_sequence, &empty_sequence);
const unknown_policy_project_root = projectRoot(&base_sequence, &unknown_policy_sequence);
const preset_root = presetRoot(&empty_sequence);
const orphan_preset_root = presetRoot(&absent_sequence);
const project_document: toolchain.RawDocument = .{ .name = toolchain.project_filename, .root = &project_root };
const missing_preset_project_document: toolchain.RawDocument = .{ .name = toolchain.project_filename, .root = &missing_preset_project_root };
const unknown_policy_project_document: toolchain.RawDocument = .{ .name = toolchain.project_filename, .root = &unknown_policy_project_root };
const preset_document: toolchain.RawDocument = .{ .name = "base.toolchain-preset.yaml", .root = &preset_root };
const orphan_preset_document: toolchain.RawDocument = .{ .name = "base.toolchain-preset.yaml", .root = &orphan_preset_root };

var capability_storage: u8 = 0;
fn capability() *const roots.ConfiguredBaseRootCapability {
    return @ptrCast(&capability_storage);
}

const entry_a: toolchain.Entry = .{ .name = "a.toolchain-preset.yaml", .size = 8, .identity = .{ .filesystem_id = 1, .file_id = 1 } };
const entry_b: toolchain.Entry = .{ .name = "b.toolchain-preset.yaml", .size = 8, .identity = .{ .filesystem_id = 1, .file_id = 2 } };

/// Fake ports. `fail` names the one port step that returns its port's error.
const Fake = struct {
    documents: []const toolchain.RawDocument = &.{ project_document, preset_document },
    entries: []const toolchain.Entry = &.{entry_a},
    fail: ?stage.Step = null,
    project_reads: usize = 0,
    inventories: usize = 0,
    preset_reads: usize = 0,
    parses: usize = 0,
    parsed_captures: usize = 0,
    first_capture: []const u8 = "",

    fn action(self: *Fake, policies: toolchain.PolicyRegistry) stage.Action {
        return .{
            .project_source = .{ .context = self, .capability = capability(), .capture_project_fn = captureProject },
            .preset_source = .{ .context = self, .capability = capability(), .inventory_presets_fn = inventory },
            .preset_capture = .{ .context = self, .capability = capability(), .capture_preset_fn = capturePreset },
            .parser = .{ .context = self, .parse_fn = parse },
            .policies = policies,
        };
    }
    fn captureProject(context: *anyopaque, _: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) @import("ports/toolchain_authority_source.zig").Error!toolchain.Capture {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.project_reads += 1;
        if (self.fail == .capture_project) return error.InvalidToolchainSource;
        return .{ .name = toolchain.project_filename, .bytes = allocator.dupe(u8, "project") catch return error.InvalidToolchainSource };
    }
    fn inventory(context: *anyopaque, _: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator) @import("ports/toolchain_authority_source.zig").Error![]const toolchain.Entry {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.inventories += 1;
        if (self.fail == .inventory_presets) return error.InvalidToolchainSource;
        return allocator.dupe(toolchain.Entry, self.entries) catch error.InvalidToolchainSource;
    }
    fn capturePreset(context: *anyopaque, _: *const roots.ConfiguredBaseRootCapability, entry: toolchain.Entry, allocator: std.mem.Allocator) @import("ports/toolchain_authority_source.zig").Error!toolchain.Capture {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.preset_reads += 1;
        if (self.fail == .capture_presets) return error.InvalidToolchainSource;
        return .{ .name = entry.name, .bytes = allocator.dupe(u8, "preset") catch return error.InvalidToolchainSource };
    }
    fn parse(context: *anyopaque, _: std.mem.Allocator, captures: []const toolchain.Capture) @import("ports/toolchain_document_parser.zig").Error![]const toolchain.RawDocument {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.parses += 1;
        self.parsed_captures = captures.len;
        self.first_capture = captures[0].name;
        if (self.fail == .parse_documents) return error.InvalidToolchainDocument;
        return self.documents;
    }
};

/// Reports cancelled from its `cancel_at`-th status check on.
const Countdown = struct {
    checks: usize = 0,
    cancel_at: usize = std.math.maxInt(usize),
    fn runtime(self: *Countdown) pipeline.NodeRuntime {
        return .{ .context = self, .status_fn = status };
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Countdown = @ptrCast(@alignCast(context.?));
        self.checks += 1;
        return if (self.checks >= self.cancel_at) .cancelled else .active;
    }
};

test "the binding derives exactly the toolchain read and parser capabilities" {
    const derived = comptime bindings.inspect(runners.PrepareToolchain, &.{});
    try std.testing.expect(derived.valid and derived.toolchain_read and derived.toolchain_parser);
    try std.testing.expect(!derived.model_provider and !derived.feature_logging and !derived.principle_read and !derived.feature_output_write and !derived.feature_read);
}

test "the stage contract is one read-only operation that produces only the valid toolchain" {
    const contract = stage.Action.contract;
    try std.testing.expectEqualStrings("prepare-toolchain", contract.id);
    try std.testing.expectEqual(pipeline.SideEffect.filesystem_read, contract.side_effect);
    try std.testing.expectEqual(@as(usize, 0), contract.requires.len);
    try std.testing.expectEqual(@as(usize, 0), contract.optional.len + contract.replaces.len + contract.invalidates.len);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.valid_toolchain}, contract.produces);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, contract.repair_role);
    try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, contract.runner_accounting);
}

test "the stage runs the nine steps in order and returns one safety-valid toolchain that outlives its scratch space" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    var fake: Fake = .{};
    var diagnostic: stage.Diagnostic = .{};
    const owner = try fake.action(no_policies).execute(arena.allocator(), std.testing.allocator, .{}, &diagnostic);
    // Every intermediate lived in the scratch space; the owner must not point into it.
    arena.deinit();
    defer safety.deinitOwner(owner);
    const packages = safety.value(owner).packages();
    try std.testing.expectEqual(@as(usize, 1), packages.len);
    try std.testing.expectEqualStrings("base@1.0.0", packages[0]);
    try std.testing.expectEqual(@as(?stage.Step, null), diagnostic.step);
    try std.testing.expectEqual(@as(usize, 1), fake.project_reads);
    try std.testing.expectEqual(@as(usize, 1), fake.inventories);
    try std.testing.expectEqual(@as(usize, 1), fake.preset_reads);
    try std.testing.expectEqual(@as(usize, 1), fake.parses);
    // The project capture precedes the presets, so the parser's first document is the project's.
    try std.testing.expectEqual(@as(usize, 2), fake.parsed_captures);
    try std.testing.expectEqualStrings(toolchain.project_filename, fake.first_capture);
}

fn expectStops(fake: *Fake, policies: toolchain.PolicyRegistry, step: stage.Step, expected: stage.Error) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var diagnostic: stage.Diagnostic = .{};
    try std.testing.expectError(expected, fake.action(policies).execute(arena.allocator(), std.testing.allocator, .{}, &diagnostic));
    try std.testing.expectEqual(@as(?stage.Step, step), diagnostic.step);
}

test "a failure in each internal step names that step and propagates the step's own error" {
    var capture_project: Fake = .{ .fail = .capture_project };
    try expectStops(&capture_project, no_policies, .capture_project, error.InvalidToolchain);
    var inventory_presets: Fake = .{ .fail = .inventory_presets };
    try expectStops(&inventory_presets, no_policies, .inventory_presets, error.InvalidToolchain);
    var capture_presets: Fake = .{ .fail = .capture_presets };
    try expectStops(&capture_presets, no_policies, .capture_presets, error.InvalidToolchain);
    var parse_documents: Fake = .{ .fail = .parse_documents };
    try expectStops(&parse_documents, no_policies, .parse_documents, error.InvalidToolchain);
    // A preset document is not a project document.
    var validate_project: Fake = .{ .documents = &.{ preset_document, preset_document } };
    try expectStops(&validate_project, no_policies, .validate_project, error.InvalidToolchain);
    // A preset whose parent is absent fails the complete-registry check.
    var validate_registry: Fake = .{ .documents = &.{ project_document, orphan_preset_document } };
    try expectStops(&validate_registry, no_policies, .validate_registry, error.InvalidToolchain);
    // The project selects a preset the registry does not hold.
    var resolve_inheritance: Fake = .{ .documents = &.{ missing_preset_project_document, preset_document } };
    try expectStops(&resolve_inheritance, no_policies, .resolve_inheritance, error.InvalidToolchain);
    // The project selects a policy the safety registry does not hold.
    var validate_safety: Fake = .{ .documents = &.{ unknown_policy_project_document, preset_document } };
    try expectStops(&validate_safety, no_policies, .validate_safety, error.InvalidToolchain);
}

test "a parser result that is not one document per capture fails the parse step" {
    // One capture for the project and one for the preset: none, too few and too many all reject.
    var none: Fake = .{ .documents = &.{} };
    try expectStops(&none, no_policies, .parse_documents, error.InvalidToolchain);
    var short: Fake = .{ .documents = &.{project_document} };
    try expectStops(&short, no_policies, .parse_documents, error.InvalidToolchain);
    var long: Fake = .{ .documents = &.{ project_document, preset_document, preset_document } };
    try expectStops(&long, no_policies, .parse_documents, error.InvalidToolchain);
}

test "cancellation is checked between every pair of internal steps and stops before the next" {
    var checkpoint: usize = 1;
    while (checkpoint <= 8) : (checkpoint += 1) {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var fake: Fake = .{};
        var countdown: Countdown = .{ .cancel_at = checkpoint };
        var diagnostic: stage.Diagnostic = .{};
        try std.testing.expectError(error.Cancelled, fake.action(no_policies).execute(arena.allocator(), std.testing.allocator, countdown.runtime(), &diagnostic));
        try std.testing.expectEqual(@as(?stage.Step, @enumFromInt(checkpoint)), diagnostic.step);
        try std.testing.expectEqual(checkpoint, countdown.checks);
        // Each port step before the checkpoint ran once and none after it ran.
        try std.testing.expectEqual(@as(usize, 1), fake.project_reads);
        try std.testing.expectEqual(@as(usize, if (checkpoint >= 2) 1 else 0), fake.inventories);
        try std.testing.expectEqual(@as(usize, if (checkpoint >= 3) 1 else 0), fake.preset_reads);
        try std.testing.expectEqual(@as(usize, if (checkpoint >= 4) 1 else 0), fake.parses);
    }
}

test "an allocation failure in an internal step reports that step and propagates the same error" {
    var seen = [_]bool{false} ** @typeInfo(stage.Step).@"enum".fields.len;
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var failing: std.testing.FailingAllocator = .init(arena.allocator(), .{ .fail_index = fail_index });
        var fake: Fake = .{};
        var diagnostic: stage.Diagnostic = .{};
        if (fake.action(no_policies).execute(failing.allocator(), std.testing.allocator, .{}, &diagnostic)) |owner| {
            safety.deinitOwner(owner);
            break;
        } else |err| {
            try std.testing.expectEqual(error.InvalidToolchain, err);
            seen[@intFromEnum(diagnostic.step.?)] = true;
        }
    }
    // Every step that allocates from the stage's scratch space was the failing one at some index.
    for (seen[0..@intFromEnum(stage.Step.validate_safety)]) |hit| try std.testing.expect(hit);
}

test "an allocation failure while building the safety owner reports validate_safety and leaks nothing" {
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = fail_index });
        var fake: Fake = .{};
        var diagnostic: stage.Diagnostic = .{};
        if (fake.action(no_policies).execute(arena.allocator(), failing.allocator(), .{}, &diagnostic)) |owner| {
            safety.deinitOwner(owner);
            break;
        } else |err| {
            try std.testing.expectEqual(error.InvalidToolchain, err);
            try std.testing.expectEqual(@as(?stage.Step, .validate_safety), diagnostic.step);
        }
    }
}

test "a source port without its root capability rejects as an invalid toolchain" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var fake: Fake = .{};
    var action = fake.action(no_policies);
    action.project_source.capability = null;
    action.preset_source.capability = null;
    action.preset_capture.capability = null;
    try std.testing.expectError(error.InvalidToolchain, steps.captureProject(action.project_source, arena.allocator()));
    try std.testing.expectError(error.InvalidToolchain, steps.inventoryPresets(action.preset_source, arena.allocator()));
    try std.testing.expectError(error.InvalidToolchain, steps.capturePresets(action.preset_capture, arena.allocator(), .{ .name = toolchain.project_filename, .bytes = "" }, &.{entry_a}));
    try std.testing.expectEqual(@as(usize, 0), fake.project_reads + fake.inventories + fake.preset_reads);
}

test "the capture budget rejects before any preset is read and accepted presets are read once each in order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var fake: Fake = .{};
    const port = fake.action(no_policies).preset_capture;
    const project: toolchain.Capture = .{ .name = toolchain.project_filename, .bytes = "project" };
    const oversize: toolchain.Entry = .{ .name = "big", .size = toolchain.max_document_bytes + 1, .identity = .{ .filesystem_id = 1, .file_id = 3 } };
    try std.testing.expectError(error.InvalidToolchain, steps.capturePresets(port, arena.allocator(), project, &.{ entry_a, oversize }));
    try std.testing.expectEqual(@as(usize, 0), fake.preset_reads);
    const captures = try steps.capturePresets(port, arena.allocator(), project, &.{ entry_a, entry_b });
    try std.testing.expectEqual(@as(usize, 2), fake.preset_reads);
    try std.testing.expectEqualStrings(entry_a.name, captures[0].name);
    try std.testing.expectEqualStrings(entry_b.name, captures[1].name);
}

test "parsing sends the project capture first and rejects a parser failure as an invalid toolchain" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var fake: Fake = .{};
    const project: toolchain.Capture = .{ .name = toolchain.project_filename, .bytes = "project" };
    const documents = try steps.parseDocuments(fake.action(no_policies).parser, arena.allocator(), project, &.{.{ .name = "preset", .bytes = "" }});
    try std.testing.expectEqual(@as(usize, 2), documents.len);
    try std.testing.expectEqual(@as(usize, 2), fake.parsed_captures);
    try std.testing.expectEqualStrings(toolchain.project_filename, fake.first_capture);
    fake.fail = .parse_documents;
    try std.testing.expectError(error.InvalidToolchain, steps.parseDocuments(fake.action(no_policies).parser, arena.allocator(), project, &.{}));
}

test "the project step reads the first document and the registry step the rest" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const documents = [_]toolchain.RawDocument{ project_document, preset_document };
    const project = try steps.validateProject(arena.allocator(), &documents);
    try std.testing.expectEqual(@as(usize, 1), project.presets.len);
    const registry = try steps.validateRegistry(arena.allocator(), &documents);
    try std.testing.expectEqual(@as(usize, 1), registry.presets.len);
    try std.testing.expectError(error.InvalidToolchain, steps.validateProject(arena.allocator(), &.{}));
    try std.testing.expectError(error.InvalidToolchain, steps.validateRegistry(arena.allocator(), &.{}));
    try std.testing.expectError(error.InvalidToolchain, steps.validateProject(arena.allocator(), &.{preset_document}));
    try std.testing.expectError(error.InvalidToolchain, steps.validateRegistry(arena.allocator(), &.{ project_document, orphan_preset_document }));
}

test "resolution, composition and safety validation chain, and only safety constructs the valid toolchain" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const documents = [_]toolchain.RawDocument{ project_document, preset_document };
    const project = try steps.validateProject(allocator, &documents);
    const registry = try steps.validateRegistry(allocator, &documents);
    const resolved = try steps.resolveInheritance(allocator, project, registry);
    try std.testing.expectEqual(@as(usize, 1), resolved.packages.len);
    const composed = try steps.compose(allocator, project, resolved);
    const owner = try steps.validateSafety(std.testing.allocator, composed, no_policies);
    defer safety.deinitOwner(owner);
    try std.testing.expectEqualStrings("base@1.0.0", safety.value(owner).packages()[0]);
    const unknown: toolchain.Composed = .{ .packages = composed.packages, .policies = &.{"unknown.policy@1"} };
    try std.testing.expectError(error.InvalidToolchain, steps.validateSafety(std.testing.allocator, unknown, no_policies));
}

fn bindingStep() compilation.CompiledStep {
    return .{
        .id = .{ .bytes = "toolchain" },
        .operation_id = .{ .bytes = stage.Action.contract.id },
        .parameters = &.{},
        .requires = stage.Action.contract.requires,
        .produces = stage.Action.contract.produces,
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{ .ok, .failed },
        .side_effect = .filesystem_read,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = null,
    };
}

fn invokeBinding(runner: *runners.PrepareToolchain, runtime: pipeline.NodeRuntime, slot: ?*pipeline.StageStepSlot) operations.Error!@import("domain/workflow_execution.zig").Candidate {
    const step = bindingStep();
    return runners.PrepareToolchain.invoke(runner, .{ .step = .{
        .data = .{},
        .step = &step,
        .resources = &.{},
        .model_binding = null,
        .log = pipeline.WorkflowLog.init(.{ .bytes = "TEST".* }),
        .runtime = runtime,
        .stage_step = slot,
    } });
}

test "the binding publishes the valid toolchain once and cleans up on every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(bindingAllocationCase, .{});
}

fn bindingAllocationCase(allocator: std.mem.Allocator) !void {
    var fake: Fake = .{};
    var runner: runners.PrepareToolchain = .{ .allocator = allocator, .action = fake.action(no_policies) };
    var candidate = invokeBinding(&runner, .{}, null) catch return error.OutOfMemory;
    const store = @import("application/pipeline_envelope.zig").PipelineEnvelope.init(std.testing.allocator, &.{schemas.valid});
    defer store.discard(&candidate.delta);
    try std.testing.expectEqual(@import("domain/workflow.zig").OutcomeTag.ok, candidate.outcome);
    try std.testing.expect(candidate.delta.data_writes[@intFromEnum(schemas.valid.key)] != null);
}

const Recorder = struct {
    last: ?@import("domain/telemetry.zig").WorkflowTelemetryFact = null,
    fn port(self: *Recorder) @import("ports/telemetry_barrier.zig").Barrier {
        return .{ .context = self, .process_fn = process };
    }
    fn process(context: *anyopaque, fact: @import("domain/telemetry.zig").WorkflowTelemetryFact) @import("domain/feature_log_stream.zig").Outcome {
        const self: *Recorder = @ptrCast(@alignCast(context));
        self.last = fact;
        return .{ .persisted = .{ .segment_ordinal = 1, .sequence = 1, .bytes_written = 1, .flushed = true } };
    }
};

test "a failed action's event records the stage step, and no other action event does" {
    const telemetry = @import("domain/telemetry.zig");
    const execution = @import("domain/workflow_execution.zig");
    const registry = @import("domain/log_event_registry.zig");
    var recorder: Recorder = .{};
    const capture: @import("application/workflow_event_capture.zig").Capture = .{ .barrier = recorder.port(), .shortcode = try telemetry.WorkflowShortcode.parse("TEST") };
    const node: @import("domain/workflow.zig").WorkflowStepId = .{ .bytes = "toolchain" };
    const rejected: execution.Applied = .{ .rejected = .{ .operation_failed = error.InvalidToolchain } };
    try std.testing.expectEqual(@as(?@import("domain/feature_log_stream.zig").FailureCode, null), capture.action(node, rejected, null, "validate_registry"));
    const failed = recorder.last.?.fact;
    try std.testing.expectEqual(telemetry.EventType.action_failed, failed.event_type);
    try std.testing.expectEqualStrings("validate_registry", failed.fields.step_id.?.bytes);
    _ = try registry.validateFact(failed);
    // A failure with no stage step, and a completed action given one, record none.
    try std.testing.expectEqual(@as(?@import("domain/feature_log_stream.zig").FailureCode, null), capture.action(node, rejected, null, null));
    try std.testing.expectEqual(@as(?telemetry.Identifier, null), recorder.last.?.fact.fields.step_id);
    try std.testing.expectEqual(@as(?@import("domain/feature_log_stream.zig").FailureCode, null), capture.action(node, .{ .outcome = .ok }, null, "validate_registry"));
    try std.testing.expectEqual(telemetry.EventType.action_completed, recorder.last.?.fact.event_type);
    try std.testing.expectEqual(@as(?telemetry.Identifier, null), recorder.last.?.fact.fields.step_id);
    // The field is for action events only: no other event type admits it.
    var misplaced: telemetry.TelemetryFact = .{ .event_type = .run_completed, .fields = .{ .outcome = .completed, .step_id = failed.fields.step_id } };
    try std.testing.expectError(error.InvalidLogEventFact, registry.validateFact(misplaced));
    misplaced.event_type = .stage_completed;
    try std.testing.expectError(error.InvalidLogEventFact, registry.validateFact(misplaced));
}

test "every event of a request stage names the stage, and a stage action's other events do not" {
    const telemetry = @import("domain/telemetry.zig");
    const execution = @import("domain/workflow_execution.zig");
    const registry = @import("domain/log_event_registry.zig");
    var recorder: Recorder = .{};
    const capture: @import("application/workflow_event_capture.zig").Capture = .{ .barrier = recorder.port(), .shortcode = try telemetry.WorkflowShortcode.parse("TEST") };
    const node: @import("domain/workflow.zig").WorkflowStepId = .{ .bytes = "request" };
    const failure: ?@import("domain/feature_log_stream.zig").FailureCode = null;
    // A stage's start and each kind of end name the stage, and the registry admits each fact.
    const ends = [_]struct { result: ?execution.Applied, event: telemetry.EventType }{
        .{ .result = null, .event = .action_started },
        .{ .result = .{ .outcome = .ok }, .event = .action_completed },
        .{ .result = .{ .outcome = .invalid }, .event = .action_invalid },
        .{ .result = .{ .outcome = .failed }, .event = .action_failed },
        .{ .result = .{ .outcome = .cancelled }, .event = .action_failed },
        .{ .result = .{ .rejected = .{ .authority = .kernel_stage } }, .event = .action_failed },
    };
    for (std.enums.values(@import("domain/model_request_stage.zig").Stage)) |request_stage| for (ends) |end| {
        try std.testing.expectEqual(failure, capture.requestStage(node, request_stage.name(), end.result, null));
        const fact = recorder.last.?.fact;
        try std.testing.expectEqual(end.event, fact.event_type);
        try std.testing.expectEqualStrings(request_stage.name(), fact.fields.step_id.?.bytes);
        _ = try registry.validateFact(fact);
    };
    // The same events of a step that is no stage name nothing unless a stage action failed (ADR 0031).
    for (ends) |end| {
        try std.testing.expectEqual(failure, capture.action(node, end.result, null, null));
        try std.testing.expectEqual(@as(?telemetry.Identifier, null), recorder.last.?.fact.fields.step_id);
        _ = try registry.validateFact(recorder.last.?.fact);
    }
}

/// Keeps the event type and diagnostic code of the last fact it is handed, copied while the fact's
/// own buffers are live, and refuses a fact the event registry does not admit.
const CodeRecorder = struct {
    event: ?@import("domain/telemetry.zig").EventType = null,
    code: [96]u8 = undefined,
    code_len: usize = 0,

    fn port(self: *CodeRecorder) @import("ports/telemetry_barrier.zig").Barrier {
        return .{ .context = self, .process_fn = process };
    }
    fn process(context: *anyopaque, fact: @import("domain/telemetry.zig").WorkflowTelemetryFact) @import("domain/feature_log_stream.zig").Outcome {
        const self: *CodeRecorder = @ptrCast(@alignCast(context));
        _ = @import("domain/log_event_registry.zig").validateFact(fact.fact) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        const bytes = (fact.fact.fields.diagnostic_code orelse return .{ .blocked = .LOG_SERIALIZATION_FAILURE }).bytes;
        self.event = fact.fact.event_type;
        @memcpy(self.code[0..bytes.len], bytes);
        self.code_len = bytes.len;
        return .{ .persisted = .{ .segment_ordinal = 1, .sequence = 1, .bytes_written = 1, .flushed = true } };
    }
    fn written(self: *const CodeRecorder) []const u8 {
        return self.code[0..self.code_len];
    }
};

test "an authority rejection's events carry its reason as their diagnostic code" {
    const telemetry = @import("domain/telemetry.zig");
    const execution = @import("domain/workflow_execution.zig");
    var recorder: CodeRecorder = .{};
    const capture: @import("application/workflow_event_capture.zig").Capture = .{ .barrier = recorder.port(), .shortcode = try telemetry.WorkflowShortcode.parse("TEST") };
    const node: @import("domain/workflow.zig").WorkflowStepId = .{ .bytes = "request" };
    const accepted: ?@import("domain/feature_log_stream.zig").FailureCode = null;
    for (std.enums.values(execution.AuthorityReason)) |reason| {
        // The existing token rule upper-cases the reason: no new code family, and each reason is its own code.
        var upper: [64]u8 = undefined;
        const expected = std.ascii.upperString(&upper, @tagName(reason));
        try std.testing.expectEqual(accepted, capture.action(node, .{ .rejected = .{ .authority = reason } }, null, null));
        try std.testing.expectEqual(@as(?telemetry.EventType, .action_failed), recorder.event);
        try std.testing.expectEqualStrings(expected, recorder.written());
        try std.testing.expectEqual(accepted, capture.terminal(.{ .execution_rejected = .{ .authority = reason } }));
        try std.testing.expectEqual(@as(?telemetry.EventType, .run_failed), recorder.event);
        try std.testing.expectEqualStrings(expected, recorder.written());
    }
    // Every other tag keeps the code it had, so the reason sits beside the tag and changes none of them.
    try std.testing.expectEqual(accepted, capture.terminal(.{ .execution_rejected = .deadline_exhausted }));
    try std.testing.expectEqualStrings("FAILED", recorder.written());
    try std.testing.expectEqual(accepted, capture.terminal(.{ .execution_rejected = .{ .operation_failed = error.InvalidToolchain } }));
    try std.testing.expectEqualStrings("INVALIDTOOLCHAIN", recorder.written());
}

test "the binding hands the runner's slot the failing step and propagates the unchanged error" {
    var fake: Fake = .{ .fail = .capture_presets };
    var runner: runners.PrepareToolchain = .{ .allocator = std.testing.allocator, .action = fake.action(no_policies) };
    var slot: pipeline.StageStepSlot = .{};
    try std.testing.expectError(error.InvalidToolchain, invokeBinding(&runner, .{}, &slot));
    try std.testing.expectEqualStrings("capture_presets", slot.name.?);
    // A successful invocation leaves a fresh slot empty.
    fake.fail = null;
    var fresh: pipeline.StageStepSlot = .{};
    var recovered = try invokeBinding(&runner, .{}, &fresh);
    const store = @import("application/pipeline_envelope.zig").PipelineEnvelope.init(std.testing.allocator, &.{schemas.valid});
    defer store.discard(&recovered.delta);
    try std.testing.expectEqual(@as(?[]const u8, null), fresh.name);
    // A cancelled stage names the step it did not start.
    var countdown: Countdown = .{ .cancel_at = 1 };
    var cancelled_fake: Fake = .{};
    var cancelled: runners.PrepareToolchain = .{ .allocator = std.testing.allocator, .action = cancelled_fake.action(no_policies) };
    var cancelled_slot: pipeline.StageStepSlot = .{};
    try std.testing.expectError(error.Cancelled, invokeBinding(&cancelled, countdown.runtime(), &cancelled_slot));
    try std.testing.expectEqualStrings("inventory_presets", cancelled_slot.name.?);
}
