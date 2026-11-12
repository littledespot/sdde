const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const feature = @import("domain/feature_directory.zig");
const identity = @import("domain/feature_identity.zig");
const reference = @import("domain/reference_ingestion.zig");
const selector = @import("domain/reference_selector.zig");
const evidence = @import("domain/reference_evidence.zig");
const naming = @import("domain/naming_policy.zig");
const safety = @import("domain/toolchain_safety.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const corpus_port = @import("ports/reference_corpus_source.zig");
const markdown = @import("adapters/parsers/markdown_reference.zig");
const unicode = @import("unicode_normalization");
const evidence_stage = @import("actions/reference/prepare_reference_evidence.zig");
const token_stage = @import("actions/reference/prepare_reference_tokens.zig");
const evidence_runner = @import("application/reference_evidence_preparation_workflow.zig");
const token_runner = @import("application/reference_token_preparation_workflow.zig");
const values = @import("application/pipeline_values.zig");
const feature_values = @import("application/feature_directory_workflow.zig");
const reference_values = @import("application/reference_workflow_values.zig");
const evidence_values = @import("application/reference_evidence_workflow.zig");
const toolchain_values = @import("application/toolchain_workflow_values.zig");
const grammar_values = @import("application/path_token_workflow.zig");
const literal_values = @import("application/passive_literal_workflow.zig");
const token_values = @import("application/structured_token_workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const Envelope = @import("application/pipeline_envelope.zig").PipelineEnvelope;
const View = @import("domain/pipeline_data.zig").View;
const Schema = @import("domain/pipeline_data.zig").Schema;
const id_fixture = @import("reference_evidence_test.zig");
const fixture = @import("test_fixtures/reference_text.zig");

// ADR 0031: the absorbed steps are tested as functions in their owners' test files. This file tests
// the two stage edges of the reference preparation, with fake ports: the step named by each failure,
// the checkpoints between steps, allocation failure in the scratch space, and the bindings that
// publish the edge values. A step whose derivation can fail only on a forged value (the chunk
// validation, the literal and token steps) fails at the edge only by allocation.

const evidence_step_count = @typeInfo(evidence_stage.Step).@"enum".fields.len;
const token_step_count = @typeInfo(token_stage.Step).@"enum".fields.len;
const feature_id: identity.FeatureId = .{ .bytes = "Chosen/Café" };
const directory: selector.Directory = .{
    .selector = .{ .bytes = "hello" },
    .project_relative_path = "reference-input/hello",
    .root_identity = .{ .filesystem_id = 1, .file_id = 1 },
    .directory_identity = .{ .filesystem_id = 1, .file_id = 2 },
};
const source_text = "A requirement. Use src/main.zig and `Hello, World!`.\n";

var capability_storage: u8 = 0;
fn contentCapability() *const roots.ReferenceContentReadCapability {
    return @ptrCast(&capability_storage);
}

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

/// Fake ports. `fail` names the one port step that returns its port's error. The decoder is the
/// production Markdown reader behind a counting wrapper; the identity source is the evidence tests'.
const Fake = struct {
    fail: ?evidence_stage.Step = null,
    bytes: []const u8 = source_text,
    duplicate_identity: bool = false,
    adapter: markdown.Adapter = .{ .io = undefined },
    ids: id_fixture.IdSource = .{},
    ran: [evidence_step_count]usize = @splat(0),

    fn action(self: *Fake) evidence_stage.Action {
        self.adapter = .{ .io = std.testing.io };
        self.ids.fail = self.fail == .assign_identities;
        return .{
            .enumerator = .{ .context = self, .capability = contentCapability(), .enumerate_fn = enumerate },
            .normalizer = .{ .normalize_fn = unicode.nfc },
            .case_folder = .{ .fold_fn = unicode.caseFold },
            .capturer = .{ .context = self, .capability = contentCapability(), .capture_fn = capture },
            .decoder = .{ .context = self, .decode_fn = decode },
            .identities = self.ids.port(),
        };
    }

    fn mark(self: *Fake, step: evidence_stage.Step) bool {
        self.ran[@intFromEnum(step)] += 1;
        return self.fail == step;
    }

    fn descriptor(self: *const Fake, id: u128) reference.Descriptor {
        return .{ .raw_path = "source.md", .observation = .{ .file = .{
            .identity = .{ .filesystem_id = 1, .file_id = id },
            .size = self.bytes.len,
            .modified_ns = 1,
            .changed_ns = 1,
        } } };
    }

    fn enumerate(context: *anyopaque, _: *const roots.ReferenceContentReadCapability, allocator: std.mem.Allocator, selected: selector.Directory) corpus_port.Error!reference.RawInventory {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.mark(.inventory_sources)) return error.ReferenceUnavailable;
        const entries = try allocator.alloc(reference.Descriptor, if (self.duplicate_identity) 2 else 1);
        entries[0] = self.descriptor(3);
        if (self.duplicate_identity) {
            entries[1] = self.descriptor(3);
            entries[1].raw_path = "other.md";
        }
        return .{ .directory = selected, .entries = entries };
    }
    fn capture(context: *anyopaque, _: *const roots.ReferenceContentReadCapability, allocator: std.mem.Allocator, inventory: reference.Inventory) corpus_port.Error!reference.CapturedCorpus {
        const self: *Fake = @ptrCast(@alignCast(context));
        if (self.mark(.capture_sources)) return error.ReferenceUnavailable;
        const entries = try allocator.alloc(reference.CapturedEntry, 1);
        entries[0] = .{ .entry = inventory.entries[0], .source = .{ .bytes = self.bytes }, .debit = .{ .reserved = self.bytes.len, .outcome = .{ .committed = self.bytes.len } } };
        return .{ .inventory = inventory, .entries = entries, .source_bytes = self.bytes.len, .budget_revision = 1 };
    }
    fn decode(context: *anyopaque, allocator: std.mem.Allocator, path: reference.RelativePath, bytes: []const u8, maximum: usize) @import("ports/reference_decoder.zig").Error!reference.Decoded {
        const self: *Fake = @ptrCast(@alignCast(context));
        _ = self.mark(.decode_markdown);
        return self.adapter.decoderPort().decode(allocator, path, bytes, maximum);
    }
};

/// The port steps the fake counts; the identity source counts its own draws.
const evidence_ports = [_]evidence_stage.Step{ .inventory_sources, .capture_sources, .decode_markdown };

test "the evidence stage contract is one read-only operation from the directories to the citable inputs" {
    const contract = evidence_stage.Action.contract;
    try std.testing.expectEqualStrings("prepare-reference-evidence", contract.id);
    try std.testing.expectEqual(pipeline.SideEffect.filesystem_read, contract.side_effect);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{ .reference_directory, .feature_directory }, contract.requires);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.citable_reference_inputs}, contract.produces);
    try std.testing.expectEqual(@as(usize, 0), contract.optional.len + contract.replaces.len + contract.invalidates.len);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, contract.repair_role);
    try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, contract.runner_accounting);
}

test "the evidence stage runs the eight steps in order and returns citable inputs for the feature" {
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    var fake: Fake = .{};
    var diagnostic: evidence_stage.Diagnostic = .{};
    const inputs = try fake.action().execute(scratch.allocator(), .{}, &diagnostic, directory, feature_id);
    try std.testing.expectEqual(@as(?evidence_stage.Step, null), diagnostic.step);
    try std.testing.expectEqualStrings("Chosen/Café", inputs.corpus.feature_id.bytes);
    try std.testing.expectEqual(@as(usize, 1), inputs.corpus.sources.len);
    try std.testing.expectEqualStrings("source.md", inputs.corpus.sources[0].path.bytes);
    try std.testing.expectEqualStrings(source_text, inputs.corpus.sources[0].bytes);
    try std.testing.expect(inputs.chunks.entries.len >= 1);
    // Each port step ran once, and the identity source was drawn on exactly once.
    for (evidence_ports) |step| try std.testing.expectEqual(@as(usize, 1), fake.ran[@intFromEnum(step)]);
    try std.testing.expectEqual(@as(u8, 1), fake.ids.calls);
}

fn expectEvidenceStops(fake: *Fake, step: evidence_stage.Step, expected: evidence_stage.Error) !void {
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    var diagnostic: evidence_stage.Diagnostic = .{};
    try std.testing.expectError(expected, fake.action().execute(scratch.allocator(), .{}, &diagnostic, directory, feature_id));
    try std.testing.expectEqual(@as(?evidence_stage.Step, step), diagnostic.step);
}

test "a failure in each reachable evidence step names that step and propagates the step's own error" {
    var inventory: Fake = .{ .fail = .inventory_sources };
    try expectEvidenceStops(&inventory, .inventory_sources, error.ReferenceUnavailable);
    // Two entries with one file identity fail the inventory's validation.
    var duplicate: Fake = .{ .duplicate_identity = true };
    try expectEvidenceStops(&duplicate, .validate_inventory, error.InvalidReferenceInventory);
    var capture: Fake = .{ .fail = .capture_sources };
    try expectEvidenceStops(&capture, .capture_sources, error.ReferenceUnavailable);
    // The reader blocks malformed text, which accounting does not accept as a document.
    var malformed: Fake = .{ .bytes = "\xff" };
    try expectEvidenceStops(&malformed, .validate_accounting, error.InvalidReferenceAccounting);
    var identities: Fake = .{ .fail = .assign_identities };
    try expectEvidenceStops(&identities, .assign_identities, error.IdentityUnavailable);
}

test "evidence cancellation is checked between every pair of steps and stops before the next" {
    var checkpoint: usize = 1;
    while (checkpoint < evidence_step_count) : (checkpoint += 1) {
        var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer scratch.deinit();
        var fake: Fake = .{};
        var countdown: Countdown = .{ .cancel_at = checkpoint };
        var diagnostic: evidence_stage.Diagnostic = .{};
        try std.testing.expectError(error.Cancelled, fake.action().execute(scratch.allocator(), countdown.runtime(), &diagnostic, directory, feature_id));
        try std.testing.expectEqual(@as(?evidence_stage.Step, @enumFromInt(checkpoint)), diagnostic.step);
        try std.testing.expectEqual(checkpoint, countdown.checks);
        // Each port step before the checkpoint ran once and none after it ran.
        for (evidence_ports) |step| try std.testing.expectEqual(@as(usize, if (@intFromEnum(step) < checkpoint) 1 else 0), fake.ran[@intFromEnum(step)]);
        try std.testing.expectEqual(@as(u8, if (@intFromEnum(evidence_stage.Step.assign_identities) < checkpoint) 1 else 0), fake.ids.calls);
    }
}

test "an allocation failure in the evidence scratch space names the failing step and propagates out-of-memory" {
    var seen = [_]bool{false} ** evidence_step_count;
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer scratch.deinit();
        var failing: std.testing.FailingAllocator = .init(scratch.allocator(), .{ .fail_index = fail_index });
        var fake: Fake = .{};
        var diagnostic: evidence_stage.Diagnostic = .{};
        if (fake.action().execute(failing.allocator(), .{}, &diagnostic, directory, feature_id)) |_| {
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            seen[@intFromEnum(diagnostic.step.?)] = true;
        }
    }
    // Every step that allocates from the scratch space was the failing one at some index.
    for ([_]evidence_stage.Step{ .inventory_sources, .validate_inventory, .capture_sources, .decode_markdown, .validate_accounting, .assign_identities, .build_chunks }) |step| try std.testing.expect(seen[@intFromEnum(step)]);
}

// The token stage. Its inputs are the production evidence steps' result for the same text, and its
// toolchain is the one the passive-literal tests use.

const Prepared = struct {
    owner: *safety.Owner,
    policy: naming.Compiled,
    inputs: evidence.Inputs,
    fn deinit(self: Prepared) void {
        safety.deinitOwner(self.owner);
    }
};

fn prepareTokens(allocator: std.mem.Allocator) !Prepared {
    var ids: id_fixture.IdSource = .{};
    const inputs = try id_fixture.prepare(allocator, &ids, try @import("reference_ingestion_test.zig").read(allocator, "source.md", source_text));
    const owner = safety.validate(allocator, .{ .packages = &.{}, .policies = &.{"project.zig@1"} }, @import("composition/toolchain_policy_registry.zig").registry) catch return error.OutOfMemory;
    errdefer safety.deinitOwner(owner);
    const policy = try (@import("actions/toolchain/compile_naming_policy.zig").Action{ .normalizer = fixture.normalizer, .folder = fixture.folder }).execute(allocator, safety.value(owner));
    return .{ .owner = owner, .policy = policy, .inputs = inputs };
}

fn tokenAction() token_stage.Action {
    return .{ .normalizer = fixture.normalizer, .case_folder = fixture.folder, .classifier = fixture.classifier };
}

test "the token stage contract is one capability-free operation from the naming policy and inputs to three products" {
    const contract = token_stage.Action.contract;
    try std.testing.expectEqualStrings("prepare-reference-tokens", contract.id);
    try std.testing.expectEqual(pipeline.SideEffect.none, contract.side_effect);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{ .compiled_naming_policy, .valid_toolchain, .citable_reference_inputs }, contract.requires);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{ .path_token_grammar, .reference_passive_literals, .structured_token_candidates }, contract.produces);
    try std.testing.expectEqual(@as(usize, 0), contract.optional.len + contract.replaces.len + contract.invalidates.len);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, contract.repair_role);
    try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, contract.runner_accounting);
}

test "the token stage returns the grammar, the literal registry and the token candidates for the inputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const prepared = try prepareTokens(arena.allocator());
    defer prepared.deinit();
    var diagnostic: token_stage.Diagnostic = .{};
    const outputs = try tokenAction().execute(arena.allocator(), .{}, &diagnostic, prepared.policy, safety.value(prepared.owner), prepared.inputs);
    try std.testing.expectEqual(@as(?token_stage.Step, null), diagnostic.step);
    try std.testing.expect(outputs.grammar.reference_names.len >= 1);
    try std.testing.expectEqualStrings("source.md", outputs.grammar.reference_names[0].basename);
    try std.testing.expect(outputs.registry.records.len >= 1);
    try std.testing.expect(outputs.candidates.entries.len >= 1);
}

test "a naming policy compiled for another toolchain fails the grammar step" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const prepared = try prepareTokens(arena.allocator());
    defer prepared.deinit();
    const successor = safety.validate(arena.allocator(), .{ .packages = &.{}, .policies = &.{"project.zig@1"} }, @import("composition/toolchain_policy_registry.zig").registry) catch return error.OutOfMemory;
    defer safety.deinitOwner(successor);
    var diagnostic: token_stage.Diagnostic = .{};
    try std.testing.expectError(error.StaleNamingPolicy, tokenAction().execute(arena.allocator(), .{}, &diagnostic, prepared.policy, safety.value(successor), prepared.inputs));
    try std.testing.expectEqual(@as(?token_stage.Step, .build_grammar), diagnostic.step);
}

test "token cancellation is checked between every pair of steps and stops before the next" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const prepared = try prepareTokens(arena.allocator());
    defer prepared.deinit();
    var checkpoint: usize = 1;
    while (checkpoint < token_step_count) : (checkpoint += 1) {
        var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer scratch.deinit();
        var countdown: Countdown = .{ .cancel_at = checkpoint };
        var diagnostic: token_stage.Diagnostic = .{};
        try std.testing.expectError(error.Cancelled, tokenAction().execute(scratch.allocator(), countdown.runtime(), &diagnostic, prepared.policy, safety.value(prepared.owner), prepared.inputs));
        try std.testing.expectEqual(@as(?token_stage.Step, @enumFromInt(checkpoint)), diagnostic.step);
        try std.testing.expectEqual(checkpoint, countdown.checks);
    }
}

test "an allocation failure in the token scratch space names the failing step and propagates out-of-memory" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const prepared = try prepareTokens(arena.allocator());
    defer prepared.deinit();
    var seen = [_]bool{false} ** token_step_count;
    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer scratch.deinit();
        var failing: std.testing.FailingAllocator = .init(scratch.allocator(), .{ .fail_index = fail_index });
        var diagnostic: token_stage.Diagnostic = .{};
        if (tokenAction().execute(failing.allocator(), .{}, &diagnostic, prepared.policy, safety.value(prepared.owner), prepared.inputs)) |_| {
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            seen[@intFromEnum(diagnostic.step.?)] = true;
        }
    }
    for ([_]token_stage.Step{ .build_grammar, .scan_literals, .assign_literals, .validate_literals, .extract_facts, .assign_candidates }) |step| try std.testing.expect(seen[@intFromEnum(step)]);
}

// The bindings. Their inputs are seeded into a real envelope, so the stages read them through the
// same view a run gives them.

const all_schemas = feature_values.schemas ++ reference_values.schemas ++ evidence_values.schemas ++ toolchain_values.schemas ++ grammar_values.schemas ++ literal_values.schemas ++ token_values.schemas;

fn bindingStep(comptime contract: pipeline.NodeContract) compilation.CompiledStep {
    return .{
        .id = .{ .bytes = "stage" },
        .operation_id = .{ .bytes = contract.id },
        .parameters = &.{},
        .requires = contract.requires,
        .produces = contract.produces,
        .replaces = &.{},
        .invalidates = &.{},
        .outcomes = &.{ .ok, .failed },
        .side_effect = contract.side_effect,
        .gates = &.{},
        .capabilities = &.{},
        .retry_authority = null,
    };
}

fn invokeBinding(comptime Runner: type, comptime contract: pipeline.NodeContract, runner: *Runner, data: View, runtime: pipeline.NodeRuntime, slot: ?*pipeline.StageStepSlot) operations.Error!@import("domain/workflow_execution.zig").Candidate {
    const step = bindingStep(contract);
    return Runner.invoke(runner, .{ .step = .{
        .data = data,
        .step = &step,
        .resources = &.{},
        .model_binding = null,
        .log = pipeline.WorkflowLog.init(.{ .bytes = "TEST".* }),
        .runtime = runtime,
        .stage_step = slot,
    } });
}

fn expectProducedOnly(delta: pipeline.NodeDelta, produces: []const pipeline.DataKey) !void {
    for (delta.data_writes, 0..) |slot, index| {
        const key: pipeline.DataKey = @enumFromInt(index);
        try std.testing.expectEqual(std.mem.indexOfScalar(pipeline.DataKey, produces, key) != null, slot != null);
    }
}

fn seedDirectories(envelope: *Envelope) !void {
    var delta: pipeline.NodeDelta = .{};
    const selected: feature.Directory = .{ .selector = .{ .feature_id = feature_id, .project_relative_path = "requirements/current/Chosen/Café" }, .root_observation = .absent, .observation = .absent };
    delta.data_writes[@intFromEnum(reference_values.directory.key)] = try values.create(std.testing.allocator, reference_values.directory, selector.Directory, directory);
    delta.data_writes[@intFromEnum(feature_values.directory.key)] = try values.create(std.testing.allocator, feature_values.directory, feature.Directory, selected);
    defer envelope.discard(&delta);
    const contract: pipeline.NodeContract = .{ .id = "seed", .kind = .action, .requires = &.{}, .produces = &.{ .reference_directory, .feature_directory }, .side_effect = .none };
    try envelope.apply(contract, &delta, .ok);
}

test "the evidence binding publishes exactly the citable inputs and hands the slot the failing step" {
    var envelope: Envelope = .init(std.testing.allocator, &all_schemas);
    defer envelope.deinit();
    try seedDirectories(&envelope);
    const read: pipeline.NodeContract = .{ .id = "read", .kind = .action, .requires = &.{ .reference_directory, .feature_directory }, .produces = &.{}, .side_effect = .none };
    const view = try envelope.view(read);
    var fake: Fake = .{};
    var runner: evidence_runner.PrepareReferenceEvidence = .{ .allocator = std.testing.allocator, .action = fake.action() };
    var candidate = try invokeBinding(evidence_runner.PrepareReferenceEvidence, evidence_stage.Action.contract, &runner, view, .{}, null);
    defer envelope.discard(&candidate.delta);
    try std.testing.expectEqual(@import("domain/workflow.zig").OutcomeTag.ok, candidate.outcome);
    try expectProducedOnly(candidate.delta, evidence_stage.Action.contract.produces);
    // A failing step is named in the runner's slot and the error is unchanged.
    var failing: Fake = .{ .fail = .capture_sources };
    var failing_runner: evidence_runner.PrepareReferenceEvidence = .{ .allocator = std.testing.allocator, .action = failing.action() };
    var slot: pipeline.StageStepSlot = .{};
    try std.testing.expectError(error.ReferenceUnavailable, invokeBinding(evidence_runner.PrepareReferenceEvidence, evidence_stage.Action.contract, &failing_runner, view, .{}, &slot));
    try std.testing.expectEqualStrings("capture_sources", slot.name.?);
    // A cancelled stage names the step it did not start.
    var countdown: Countdown = .{ .cancel_at = 1 };
    var cancelled_fake: Fake = .{};
    var cancelled: evidence_runner.PrepareReferenceEvidence = .{ .allocator = std.testing.allocator, .action = cancelled_fake.action() };
    var cancelled_slot: pipeline.StageStepSlot = .{};
    try std.testing.expectError(error.Cancelled, invokeBinding(evidence_runner.PrepareReferenceEvidence, evidence_stage.Action.contract, &cancelled, view, countdown.runtime(), &cancelled_slot));
    try std.testing.expectEqualStrings("validate_inventory", cancelled_slot.name.?);
}

test "the evidence binding cleans up on every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(evidenceBindingCase, .{});
}

fn evidenceBindingCase(allocator: std.mem.Allocator) !void {
    var envelope: Envelope = .init(std.testing.allocator, &all_schemas);
    defer envelope.deinit();
    try seedDirectories(&envelope);
    const read: pipeline.NodeContract = .{ .id = "read", .kind = .action, .requires = &.{ .reference_directory, .feature_directory }, .produces = &.{}, .side_effect = .none };
    var fake: Fake = .{};
    var runner: evidence_runner.PrepareReferenceEvidence = .{ .allocator = allocator, .action = fake.action() };
    var candidate = invokeBinding(evidence_runner.PrepareReferenceEvidence, evidence_stage.Action.contract, &runner, try envelope.view(read), .{}, null) catch return error.OutOfMemory;
    defer envelope.discard(&candidate.delta);
    try expectProducedOnly(candidate.delta, evidence_stage.Action.contract.produces);
}

fn seedTokens(envelope: *Envelope, prepared: Prepared) !void {
    var delta: pipeline.NodeDelta = .{};
    delta.data_writes[@intFromEnum(toolchain_values.valid.key)] = try values.adopt(std.testing.allocator, toolchain_values.valid, safety.ValidToolchain, safety.Owner, prepared.owner, safety.value, safety.deinitOwner, safety.retainedBytes(prepared.owner));
    delta.data_writes[@intFromEnum(grammar_values.policy_schema.key)] = try values.create(std.testing.allocator, grammar_values.policy_schema, naming.Compiled, prepared.policy);
    delta.data_writes[@intFromEnum(evidence_values.inputs_schema.key)] = try values.create(std.testing.allocator, evidence_values.inputs_schema, evidence.Inputs, prepared.inputs);
    defer envelope.discard(&delta);
    const contract: pipeline.NodeContract = .{ .id = "seed", .kind = .action, .requires = &.{}, .produces = &.{ .valid_toolchain, .compiled_naming_policy, .citable_reference_inputs }, .side_effect = .none };
    try envelope.apply(contract, &delta, .ok);
}

const token_read: pipeline.NodeContract = .{ .id = "read", .kind = .action, .requires = &.{ .valid_toolchain, .compiled_naming_policy, .citable_reference_inputs }, .produces = &.{}, .side_effect = .none };

/// Seeds the envelope with the token stage's three inputs; the envelope takes the toolchain owner.
fn seedTokenInputs(arena: std.mem.Allocator, envelope: *Envelope) !void {
    const owner = safety.validate(std.testing.allocator, .{ .packages = &.{}, .policies = &.{"project.zig@1"} }, @import("composition/toolchain_policy_registry.zig").registry) catch return error.OutOfMemory;
    var ids: id_fixture.IdSource = .{};
    const inputs = try id_fixture.prepare(arena, &ids, try @import("reference_ingestion_test.zig").read(arena, "source.md", source_text));
    const policy = try (@import("actions/toolchain/compile_naming_policy.zig").Action{ .normalizer = fixture.normalizer, .folder = fixture.folder }).execute(arena, safety.value(owner));
    try seedTokens(envelope, .{ .owner = owner, .policy = policy, .inputs = inputs });
}

test "the token binding cleans up every written value on every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(tokenBindingCase, .{});
}

fn tokenBindingCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var envelope: Envelope = .init(std.testing.allocator, &all_schemas);
    defer envelope.deinit();
    try seedTokenInputs(arena.allocator(), &envelope);
    var runner: token_runner.PrepareReferenceTokens = .{ .allocator = allocator, .action = tokenAction() };
    // The three outputs are created in turn, so a failure of the second or third leaves a partial
    // delta that the binding must destroy.
    var candidate = invokeBinding(token_runner.PrepareReferenceTokens, token_stage.Action.contract, &runner, try envelope.view(token_read), .{}, null) catch return error.OutOfMemory;
    defer envelope.discard(&candidate.delta);
    try expectProducedOnly(candidate.delta, token_stage.Action.contract.produces);
}

test "the token binding publishes exactly the grammar, registry and candidates and hands the slot the failing step" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var envelope: Envelope = .init(std.testing.allocator, &all_schemas);
    defer envelope.deinit();
    try seedTokenInputs(arena.allocator(), &envelope);
    const view = try envelope.view(token_read);
    var runner: token_runner.PrepareReferenceTokens = .{ .allocator = std.testing.allocator, .action = tokenAction() };
    var candidate = try invokeBinding(token_runner.PrepareReferenceTokens, token_stage.Action.contract, &runner, view, .{}, null);
    defer envelope.discard(&candidate.delta);
    try std.testing.expectEqual(@import("domain/workflow.zig").OutcomeTag.ok, candidate.outcome);
    try expectProducedOnly(candidate.delta, token_stage.Action.contract.produces);
    // A cancelled stage names the step it did not start, and a successful one leaves a fresh slot empty.
    var countdown: Countdown = .{ .cancel_at = 1 };
    var slot: pipeline.StageStepSlot = .{};
    try std.testing.expectError(error.Cancelled, invokeBinding(token_runner.PrepareReferenceTokens, token_stage.Action.contract, &runner, view, countdown.runtime(), &slot));
    try std.testing.expectEqualStrings("scan_literals", slot.name.?);
    var fresh: pipeline.StageStepSlot = .{};
    var recovered = try invokeBinding(token_runner.PrepareReferenceTokens, token_stage.Action.contract, &runner, view, .{}, &fresh);
    defer envelope.discard(&recovered.delta);
    try std.testing.expectEqual(@as(?[]const u8, null), fresh.name);
}
