const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const feature = @import("domain/feature_directory.zig");
const identity = @import("domain/feature_identity.zig");
const reference = @import("domain/reference_selector.zig");
const artifacts = @import("domain/workflow_artifact_registry.zig");
const clarification = @import("domain/clarification_inputs.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const invocation_types = @import("domain/specify_invocation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const feature_port = @import("ports/feature_directory_inspector.zig");
const reference_port = @import("ports/reference_directory_inspector.zig");
const state_port = @import("ports/workflow_state_source.zig");
const parser_port = @import("ports/clarification_input_parser.zig");
const fixtures = @import("test_fixtures/clarification_inputs.zig");
const stage = @import("actions/specify/prepare_inputs.zig");
const steps = stage.steps;
const runners = @import("application/input_preparation_workflow.zig");
const invocation_runner = @import("application/specify_invocation_runner.zig");
const invocation_values = @import("application/specify_invocation_values.zig");
const feature_values = @import("application/feature_directory_workflow.zig");
const reference_values = @import("application/reference_workflow_values.zig");
const clarification_values = @import("application/clarification_input_workflow.zig");
const principle_values = @import("application/principle_workflow.zig");
const publication = @import("application/specification_publication_workflow.zig");
const Envelope = @import("application/pipeline_envelope.zig").PipelineEnvelope;
const View = @import("domain/pipeline_data.zig").View;
const Schema = @import("domain/pipeline_data.zig").Schema;
const compilation = @import("domain/workflow_compilation.zig");

// ADR 0031: the thirteen absorbed steps are tested as functions in their owners' test files; this file
// tests the stage edge, which fakes every port and checks the step named by each failure, the
// checkpoints between steps, allocation failure in each allocator, and the binding that publishes
// the edge values.

const step_count = @typeInfo(stage.Step).@"enum".fields.len;
const default_invocation: invocation_types.Invocation = .{ .raw_feature = "Chosen/Café", .raw_reference = "hello" };
const port_steps = [_]stage.Step{ .inspect_feature, .inspect_reference, .capture_state, .capture_clarifications, .parse_clarification_state };

var capability_storage: u8 = 0;
fn featureCapability() *const roots.FeatureDirectoryReadCapability {
    return @ptrCast(&capability_storage);
}
fn baseCapability() *const roots.ConfiguredBaseRootCapability {
    return @ptrCast(&capability_storage);
}
fn inputCapability() *const roots.FeatureInputReadCapability {
    return @ptrCast(&capability_storage);
}

/// The fake in effect for the running test: the clarification parsers carry no context.
var active: ?*Fake = null;

/// Fake ports. `fail` names the one port step that returns its port's error. The clarification
/// state bytes choose what the state parser does: "malformed" fails and "other" names another feature.
const Fake = struct {
    fail: ?stage.Step = null,
    state_bytes: ?[]const u8 = null,
    clarification_state: ?[]const u8 = "ok",
    forms: []const clarification.FormCapture = &.{},
    ran: [step_count]usize = @splat(0),

    fn action(self: *Fake) stage.Action {
        active = self;
        return .{
            .normalizer = .{ .normalize_fn = @import("unicode_normalization").nfc },
            .feature_roots = .{ .specs = "requirements/current", .archive = "requirements/current/archive" },
            .artifact_roots = .{ .specs = "requirements/current", .archive = "requirements/current/archive", .workflows = "engine/flows" },
            .feature_inspector = .{ .context = self, .capability = featureCapability(), .inspect_fn = inspectFeature },
            .reference_inspector = .{ .context = self, .capability = baseCapability(), .inspect_fn = inspectReference },
            .state_source = .{ .context = self, .capability = inputCapability(), .capture_fn = captureState },
            .input_source = .{ .context = self, .capability = inputCapability(), .capture_fn = captureClarifications },
            .state_parser = .{ .parse_state_fn = parseState },
            .form_parser = .{ .parse_form_fn = parseForm },
        };
    }

    fn mark(self: *Fake, step: stage.Step) bool {
        self.ran[@intFromEnum(step)] += 1;
        return self.fail == step;
    }

    fn inspectFeature(context: *anyopaque, _: *const roots.FeatureDirectoryReadCapability, _: std.mem.Allocator, selector: feature.Selector) feature_port.Error!feature.Directory {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.mark(.inspect_feature)) return error.FeatureDirectoryUnavailable;
        return .{ .selector = selector, .root_observation = .absent, .observation = .absent };
    }
    fn inspectReference(context: *anyopaque, _: *const roots.ConfiguredBaseRootCapability, allocator: std.mem.Allocator, selector: reference.RelativeSelector) reference_port.Error!reference.Directory {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.mark(.inspect_reference)) return error.ReferenceDirectoryUnavailable;
        return .{
            .selector = selector,
            .project_relative_path = try allocator.dupe(u8, selector.bytes),
            .root_identity = .{ .filesystem_id = 1, .file_id = 1 },
            .directory_identity = .{ .filesystem_id = 1, .file_id = 2 },
        };
    }
    fn captureState(context: *anyopaque, _: *const roots.FeatureInputReadCapability, allocator: std.mem.Allocator, _: feature.Directory, _: artifacts.FeaturePaths) state_port.Error!?[]const u8 {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.mark(.capture_state)) return error.FeatureInputUnavailable;
        return try allocator.dupe(u8, self.state_bytes orelse return null);
    }
    fn captureClarifications(context: *anyopaque, _: *const roots.FeatureInputReadCapability, allocator: std.mem.Allocator, _: feature.Directory, _: artifacts.FeaturePaths) @import("ports/feature_input_source.zig").Error!clarification.Captures {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.mark(.capture_clarifications)) return error.FeatureInputUnavailable;
        return .{ .state = if (self.clarification_state) |bytes| try allocator.dupe(u8, bytes) else null, .forms = self.forms };
    }
    fn parseState(_: std.mem.Allocator, bytes: []const u8) clarification.Error!clarification.State {
        const self = active.?;
        _ = self.mark(.parse_clarification_state);
        if (std.mem.eql(u8, bytes, "malformed")) return error.InvalidClarificationInput;
        var value = fixtures.state(&.{});
        if (std.mem.eql(u8, bytes, "other")) value.feature_id = "Other/Feature";
        return value;
    }
    fn parseForm(_: std.mem.Allocator, _: []const u8, _: clarification.Record, _: @import("domain/clarification_form.zig").Binding) clarification.Error!parser_port.Form {
        _ = active.?.mark(.validate_clarification_forms);
        return error.InvalidClarificationInput;
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

test "the stage contract is one read-only operation that requires the invocation and produces only the input values" {
    const contract = stage.Action.contract;
    try std.testing.expectEqualStrings("prepare-inputs", contract.id);
    try std.testing.expectEqual(pipeline.SideEffect.filesystem_read, contract.side_effect);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.specify_invocation}, contract.requires);
    try std.testing.expectEqual(@as(usize, 0), contract.optional.len + contract.replaces.len + contract.invalidates.len);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{ .feature_directory, .relative_feature_directory, .reference_directory, .feature_artifact_paths, .prior_specification_state, .prior_principle_registry, .raw_clarification_inputs, .clarification_inputs }, contract.produces);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, contract.repair_role);
    try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, contract.runner_accounting);
}

test "the stage runs the thirteen steps in order once each and returns the edge values and an absent prior state" {
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    var fake: Fake = .{};
    var diagnostic: stage.Diagnostic = .{};
    const outputs = try fake.action().execute(scratch.allocator(), std.testing.allocator, .{}, &diagnostic, default_invocation);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(?stage.Step, null), diagnostic.step);
    try std.testing.expectEqualStrings("Chosen/Café", outputs.feature.selector.feature_id.bytes);
    try std.testing.expectEqualStrings("requirements/current/Chosen/Café", outputs.selector.project_relative_path);
    try std.testing.expectEqualStrings("hello", outputs.reference.selector.bytes);
    try std.testing.expectEqualStrings("Chosen/Café", outputs.paths.feature.feature_id.bytes);
    try std.testing.expect(outputs.captures.state != null);
    try std.testing.expect(outputs.inputs.state.value != null);
    try std.testing.expectEqual(@as(usize, 0), outputs.inputs.submissions.len);
    try std.testing.expectEqual(@as(?[]const u8, null), outputs.prior.captured);
    try std.testing.expectEqual(@as(?@TypeOf(outputs.prior.specified().?), null), outputs.prior.specified());
    for (port_steps) |step| try std.testing.expectEqual(@as(usize, 1), fake.ran[@intFromEnum(step)]);
    // No record, so no form was parsed.
    try std.testing.expectEqual(@as(usize, 0), fake.ran[@intFromEnum(stage.Step.validate_clarification_forms)]);
}

fn expectStops(action: stage.Action, invocation: invocation_types.Invocation, step: stage.Step, expected: stage.Error) !void {
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    var retained: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer retained.deinit();
    var diagnostic: stage.Diagnostic = .{};
    try std.testing.expectError(expected, action.execute(scratch.allocator(), retained.allocator(), .{}, &diagnostic, invocation));
    try std.testing.expectEqual(@as(?stage.Step, step), diagnostic.step);
}

const bad_utf8 = "\xed\xa0\x80";
const orphan_form: []const clarification.FormCapture = &.{.{ .id = .{ .stage = .spec, .ordinal = 1 }, .bytes = "form" }};

test "a failure in each internal step names that step and propagates the step's own error" {
    var fake: Fake = .{};
    try expectStops(fake.action(), .{ .raw_feature = bad_utf8, .raw_reference = "hello" }, .normalize_feature, error.InvalidUtf8);
    var unrooted = fake.action();
    unrooted.feature_roots = null;
    try expectStops(unrooted, default_invocation, .validate_feature, error.InvalidFeatureDirectory);
    try expectStops(fake.action(), .{ .raw_feature = "../outside", .raw_reference = "hello" }, .validate_feature, error.InvalidFeatureDirectory);
    var inspect_feature: Fake = .{ .fail = .inspect_feature };
    try expectStops(inspect_feature.action(), default_invocation, .inspect_feature, error.FeatureDirectoryUnavailable);
    try expectStops(fake.action(), .{ .raw_feature = "Chosen/Café", .raw_reference = bad_utf8 }, .normalize_reference, error.InvalidUtf8);
    try expectStops(fake.action(), .{ .raw_feature = "Chosen/Café", .raw_reference = "../hello" }, .validate_reference, error.InvalidReferenceSelector);
    var inspect_reference: Fake = .{ .fail = .inspect_reference };
    try expectStops(inspect_reference.action(), default_invocation, .inspect_reference, error.ReferenceDirectoryUnavailable);
    var without_artifact_roots = fake.action();
    without_artifact_roots.artifact_roots = null;
    try expectStops(without_artifact_roots, default_invocation, .resolve_paths, error.InvalidFeatureArtifactPath);
    var capture_state: Fake = .{ .fail = .capture_state };
    try expectStops(capture_state.action(), default_invocation, .capture_state, error.FeatureInputUnavailable);
    var without_state_source = fake.action();
    without_state_source.state_source = null;
    try expectStops(without_state_source, default_invocation, .capture_state, error.FeatureInputUnavailable);
    var parse_state: Fake = .{ .state_bytes = "not a specification state" };
    try expectStops(parse_state.action(), default_invocation, .parse_state, error.InvalidSpecificationState);
    var capture_clarifications: Fake = .{ .fail = .capture_clarifications };
    try expectStops(capture_clarifications.action(), default_invocation, .capture_clarifications, error.FeatureInputUnavailable);
    var malformed: Fake = .{ .clarification_state = "malformed" };
    try expectStops(malformed.action(), default_invocation, .parse_clarification_state, error.InvalidClarificationInput);
    var other_feature: Fake = .{ .clarification_state = "other" };
    try expectStops(other_feature.action(), default_invocation, .validate_clarification_state, error.InvalidClarificationInput);
    // A form with no recorded clarification, with and without a state, fails the forms step.
    var orphan: Fake = .{ .forms = orphan_form };
    try expectStops(orphan.action(), default_invocation, .validate_clarification_forms, error.InvalidClarificationInput);
    var orphan_without_state: Fake = .{ .clarification_state = null, .forms = orphan_form };
    try expectStops(orphan_without_state.action(), default_invocation, .validate_clarification_forms, error.InvalidClarificationInput);
}

test "the state steps read bytes without parsing and parse them without reading" {
    const selected = identity.FeatureId.parse("Chosen/Café").?;
    // Absent bytes are an absent prior state; unparsable bytes are an invalid one.
    const prior = try steps.parseState(std.testing.allocator, null, selected, null);
    try std.testing.expectEqual(@as(?[]const u8, null), prior.captured);
    try std.testing.expectError(error.InvalidSpecificationState, steps.parseState(std.testing.allocator, null, selected, "not a specification state"));
    // Reading the state hands back the bytes unparsed, even when they are not a state.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var fake: Fake = .{ .state_bytes = "not a specification state" };
    const directory: feature.Directory = .{ .selector = .{ .feature_id = selected, .project_relative_path = "requirements/current/Chosen/Café" }, .root_observation = .absent, .observation = .absent };
    const paths = try artifacts.resolveFeaturePaths(arena.allocator(), fake.action().artifact_roots.?, directory.selector);
    const bytes = try steps.captureState(fake.action().state_source, arena.allocator(), directory, paths);
    try std.testing.expectEqualStrings("not a specification state", bytes.?);
}

test "cancellation is checked between every pair of internal steps and stops before the next" {
    var checkpoint: usize = 1;
    while (checkpoint < step_count) : (checkpoint += 1) {
        var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer scratch.deinit();
        var retained: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer retained.deinit();
        var fake: Fake = .{};
        var countdown: Countdown = .{ .cancel_at = checkpoint };
        var diagnostic: stage.Diagnostic = .{};
        try std.testing.expectError(error.Cancelled, fake.action().execute(scratch.allocator(), retained.allocator(), countdown.runtime(), &diagnostic, default_invocation));
        try std.testing.expectEqual(@as(?stage.Step, @enumFromInt(checkpoint)), diagnostic.step);
        try std.testing.expectEqual(checkpoint, countdown.checks);
        // Each port step before the checkpoint ran once and none after it ran.
        for (port_steps) |step| try std.testing.expectEqual(@as(usize, if (@intFromEnum(step) < checkpoint) 1 else 0), fake.ran[@intFromEnum(step)]);
    }
}

test "an allocation failure in the scratch space names the failing step and propagates out-of-memory" {
    var seen = [_]bool{false} ** step_count;
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer scratch.deinit();
        var retained: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer retained.deinit();
        var failing: std.testing.FailingAllocator = .init(scratch.allocator(), .{ .fail_index = fail_index });
        var fake: Fake = .{};
        var diagnostic: stage.Diagnostic = .{};
        if (fake.action().execute(failing.allocator(), retained.allocator(), .{}, &diagnostic, default_invocation)) |_| {
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            seen[@intFromEnum(diagnostic.step.?)] = true;
        }
    }
    // Every step that allocates from the scratch space was the failing one at some index.
    for ([_]stage.Step{ .normalize_feature, .validate_feature, .normalize_reference, .inspect_reference, .resolve_paths, .capture_clarifications }) |step| try std.testing.expect(seen[@intFromEnum(step)]);
}

test "an allocation failure in the retained space names the capture step and a parse failure the parse step" {
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    // The state bytes are read into the retained space.
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    var fake: Fake = .{ .state_bytes = "not a specification state" };
    var diagnostic: stage.Diagnostic = .{};
    try std.testing.expectError(error.OutOfMemory, fake.action().execute(scratch.allocator(), failing.allocator(), .{}, &diagnostic, default_invocation));
    try std.testing.expectEqual(@as(?stage.Step, .capture_state), diagnostic.step);
    // Valid JSON of an unknown stage makes the parse allocate before it rejects, so an allocation
    // failure inside the parse reports the parse step and stays out-of-memory; the sweep ends when
    // the parse reaches its own rejection.
    var fail_index: usize = 1;
    var saw_out_of_memory = false;
    while (true) : (fail_index += 1) {
        var retained: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer retained.deinit();
        var parsing: std.testing.FailingAllocator = .init(retained.allocator(), .{ .fail_index = fail_index });
        var parse_fake: Fake = .{ .state_bytes = "{\"stage\":\"unknown\"}" };
        var parse_diagnostic: stage.Diagnostic = .{};
        const result = parse_fake.action().execute(scratch.allocator(), parsing.allocator(), .{}, &parse_diagnostic, default_invocation);
        try std.testing.expectEqual(@as(?stage.Step, .parse_state), parse_diagnostic.step);
        if (result) |_| return error.TestUnexpectedResult else |err| {
            if (err == error.OutOfMemory) {
                saw_out_of_memory = true;
                continue;
            }
            try std.testing.expectEqual(error.InvalidSpecificationState, err);
            break;
        }
    }
    try std.testing.expect(saw_out_of_memory);
}

// The binding. The invocation is published by the real invocation binding, so the stage reads it
// through the same envelope view a run gives it.

const all_schemas = invocation_values.schemas ++ feature_values.schemas ++ reference_values.schemas ++ clarification_values.schemas ++ [_]Schema{ principle_values.prior_schema, publication.prior_schema };

const Seed = struct {
    envelope: Envelope,

    fn start(self: *Seed) !void {
        self.envelope = .init(std.testing.allocator, &all_schemas);
        var binding: invocation_runner.Invocation = .{ .allocator = std.testing.allocator };
        var candidate = try invocation_runner.Invocation.invoke(&binding, .{ .invocation = .{ .arguments = &.{ "--reference", "hello", "--feature", "Chosen/Café" } } });
        defer self.envelope.discard(&candidate.delta);
        const contract: pipeline.NodeContract = .{ .id = invocation_runner.Invocation.contract.id, .kind = .orchestrator, .requires = &.{}, .produces = invocation_runner.Invocation.contract.produces, .side_effect = .none };
        try self.envelope.apply(contract, &candidate.delta, .ok);
    }
    fn view(self: *const Seed) !View {
        const read: pipeline.NodeContract = .{ .id = "read", .kind = .action, .requires = &.{.specify_invocation}, .produces = &.{}, .side_effect = .none };
        return self.envelope.view(read);
    }
    fn deinit(self: *Seed) void {
        self.envelope.deinit();
    }
};

fn bindingStep() compilation.CompiledStep {
    return .{
        .id = .{ .bytes = "inputs" },
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

fn invokeBinding(runner: *runners.PrepareInputs, data: View, runtime: pipeline.NodeRuntime, slot: ?*pipeline.StageStepSlot) operations.Error!@import("domain/workflow_execution.zig").Candidate {
    const step = bindingStep();
    return runners.PrepareInputs.invoke(runner, .{ .step = .{
        .data = data,
        .step = &step,
        .resources = &.{},
        .model_binding = null,
        .log = pipeline.WorkflowLog.init(.{ .bytes = "TEST".* }),
        .runtime = runtime,
        .stage_step = slot,
    } });
}

test "the binding publishes exactly the produced keys once and cleans up on every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(bindingAllocationCase, .{});
}

fn bindingAllocationCase(allocator: std.mem.Allocator) !void {
    var seed: Seed = undefined;
    try seed.start();
    defer seed.deinit();
    var fake: Fake = .{};
    var runner: runners.PrepareInputs = .{ .allocator = allocator, .action = fake.action() };
    var candidate = invokeBinding(&runner, try seed.view(), .{}, null) catch return error.OutOfMemory;
    defer seed.envelope.discard(&candidate.delta);
    try std.testing.expectEqual(@import("domain/workflow.zig").OutcomeTag.ok, candidate.outcome);
    for (candidate.delta.data_writes, 0..) |slot, index| {
        const key: pipeline.DataKey = @enumFromInt(index);
        const produced = std.mem.indexOfScalar(pipeline.DataKey, stage.Action.contract.produces, key) != null;
        try std.testing.expectEqual(produced, slot != null);
    }
}

test "the binding hands the runner's slot the failing step and propagates the unchanged error" {
    var seed: Seed = undefined;
    try seed.start();
    defer seed.deinit();
    var fake: Fake = .{ .fail = .inspect_reference };
    var runner: runners.PrepareInputs = .{ .allocator = std.testing.allocator, .action = fake.action() };
    var slot: pipeline.StageStepSlot = .{};
    try std.testing.expectError(error.ReferenceDirectoryUnavailable, invokeBinding(&runner, try seed.view(), .{}, &slot));
    try std.testing.expectEqualStrings("inspect_reference", slot.name.?);
    // A successful invocation leaves a fresh slot empty.
    fake.fail = null;
    var fresh: pipeline.StageStepSlot = .{};
    var recovered = try invokeBinding(&runner, try seed.view(), .{}, &fresh);
    defer seed.envelope.discard(&recovered.delta);
    try std.testing.expectEqual(@as(?[]const u8, null), fresh.name);
    // A cancelled stage names the step it did not start.
    var countdown: Countdown = .{ .cancel_at = 1 };
    var cancelled_fake: Fake = .{};
    var cancelled: runners.PrepareInputs = .{ .allocator = std.testing.allocator, .action = cancelled_fake.action() };
    var cancelled_slot: pipeline.StageStepSlot = .{};
    try std.testing.expectError(error.Cancelled, invokeBinding(&cancelled, try seed.view(), countdown.runtime(), &cancelled_slot));
    try std.testing.expectEqualStrings("validate_feature", cancelled_slot.name.?);
}
