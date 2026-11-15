//! The two owner routes the scripted integration matrix cannot reach (E4 review finding 1): the
//! `reference-text` and `specification-support` owners of the generic repair operations. Response
//! admission inside `request-model` rejects the defects their native validators would repair, and the
//! fixtures cannot encode a rejected support finding, so no scenario drives them. These tests drive
//! each of the owner's generic operations over real native facts instead: the authorization, the
//! input, a real model request answered through the stage seam, the parse and the merge, and assert
//! each operation's outcome, the exact keys its delta writes, replaces and invalidates (which the
//! fixed contract table cannot catch, being written from the same contracts), and the value it
//! produces against the domain function it runs.
//!
//! What this proves is the generic path's behaviour against the domain rules. It is not an
//! equivalence to the deleted per-owner operations: that code is gone and no frozen trace ran these
//! routes.
const std = @import("std");
const data = @import("domain/pipeline_data.zig");
const pipeline = @import("domain/pipeline.zig");
const compilation = @import("domain/workflow_compilation.zig");
const execution = @import("domain/workflow_execution.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const generic = @import("application/repair_workflow.zig");
const repair_owner = @import("domain/repair_owner.zig");
const values = @import("application/pipeline_values.zig");
const requests = @import("application/model_request_workflow.zig");
const candidate_handoff = @import("application/model_candidate_handoff.zig");
const packets = @import("domain/model_input_packet.zig");
const json = @import("domain/model_candidate_json.zig");
const typed_text = @import("domain/typed_text.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const model_tests = @import("model_request_workflow_test.zig");
const Key = pipeline.DataKey;
const Operation = repair_owner.Operation;
const RepairOwner = repair_owner.RepairOwner;

// ---------------------------------------------------------------- shared

/// Run one generic operation as the runner would: a compiled step that selects `owner`, over `view`.
fn call(comptime G: type, comptime op: Operation, comptime owner: RepairOwner, context: *G, view: data.View) !execution.Candidate {
    var storage = [1]compilation.CompiledParameter{.{ .id = .{ .bytes = generic.selector }, .value = .{ .enumeration = owner.id() } }};
    const effects = generic.OwnerBinding(op, owner).effects;
    const step: compilation.CompiledStep = .{ .id = .{ .bytes = "repair" }, .operation_id = .{ .bytes = op.id() }, .parameters = &storage, .requires = effects.requires, .optional = effects.optional, .produces = effects.produces, .replaces = effects.replaces, .invalidates = effects.invalidates, .outcomes = &.{ .ok, .more, .invalid, .blocked, .failed }, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
    return G.invoke(context, .{ .step = .{ .data = view, .step = &step, .resources = &.{}, .model_binding = null, .log = .init(try @import("domain/telemetry.zig").WorkflowShortcode.parse("SGEN")) } });
}

fn contains(list: []const Key, key: Key) bool {
    return std.mem.indexOfScalar(Key, list, key) != null;
}

/// A delta writes, replaces and invalidates exactly these keys: nothing else, and each of them.
fn expectDelta(delta: pipeline.NodeDelta, writes: []const Key, replaces: []const Key, invalidates: []const Key) !void {
    for (std.enums.values(Key)) |key| {
        const index = @intFromEnum(key);
        try std.testing.expectEqual(contains(writes, key), delta.data_writes[index] != null);
        try std.testing.expectEqual(contains(replaces, key), delta.data_replacements[index] != null);
        try std.testing.expectEqual(contains(invalidates, key), delta.data_invalidations.contains(key));
    }
}

fn discard(delta: pipeline.NodeDelta) void {
    for (delta.data_writes) |slot| if (slot) |value| values.destroy(value);
    for (delta.data_replacements) |slot| if (slot) |value| values.destroy(value);
}

/// One real model request answered through the stage seam, left accepted and current: its ledger,
/// prepared request, accounting, payload proof and the packet the request carried.
const Request = struct {
    runner: runner_module.Runner,
    fake: fake_provider.FakeLLMProvider,

    /// `authorized` is the authorize step's own transition: the runner commits it before the request,
    /// and a repair request is admitted only under the permit it committed.
    fn start(self: *Request, fixture: *model_tests.Fixture, schema_file: []const u8, packet_value: *data.Value, authorized: @import("domain/workflow_retry.zig").Transition, response: []const u8) !void {
        const a = fixture.arena.allocator();
        const base = try model_tests.protocolRetryYaml(fixture);
        const source = try std.mem.replaceOwned(u8, a, base, ", input: input.txt", "");
        const definition = try std.mem.replaceOwned(u8, a, source, ", input: input }", ", result-selection: input }");
        const schema_source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, schema_file, a, .unlimited);
        const graph = try fixture.compileWithAssets(definition, schema_source, false);
        self.runner = fixture.runner(graph, std.testing.allocator);
        self.runner.envelope.slots[@intFromEnum(requests.packet_schema.key)] = packet_value;
        try self.runner.repair_retry.commit(try self.runner.repair_retry.prepare(authorized));
        self.fake = model_tests.invocationProvider(&self.runner, std.testing.allocator);
        fixture.native.invoke_model.action = .{ .provider = self.fake.interface() };
        self.fake.invocation_plan.complete.content = response;
        try model_tests.prepareProtocolAttempt(&self.runner, false);
        for ([_][]const u8{ "call", "validate-response", "complete-operation", "validate-payload", "close-request" }) |step|
            try std.testing.expectEqual(.ok, self.runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    }

    fn deinit(self: *Request) void {
        self.runner.deinit();
    }

    /// The runner's current keys, as the next operation's input view.
    fn view(self: *const Request) data.View {
        return .{ .slots = self.runner.envelope.slots };
    }
};

// ------------------------------------------------------- reference text

const evidence = @import("domain/reference_evidence.zig");
const extraction = @import("domain/reference_extraction.zig");
const native = @import("application/reference_extraction_workflow.zig");
const reference_value = @import("domain/reference_candidate_value.zig");
const text_binding = @import("application/reference_text_repair_workflow.zig");
const text_domain = @import("domain/reference_extraction_text_repair.zig");
const contexts = @import("domain/reference_extraction_context.zig");
const evidence_test = @import("reference_evidence_test.zig");
const ingest = @import("reference_ingestion_test.zig").read;
const text_fixture = @import("test_fixtures/reference_text.zig");
const token_fixture = @import("test_fixtures/reference_tokens.zig");

/// A real text rejection (or, for the present-but-wrong cases, a real valid text) in the keys the
/// text route reads, adopted as the engine would hold them.
const TextWorld = struct {
    inputs: evidence.Inputs,
    prepared: text_fixture.Prepared,
    candidate: extraction.Parsed,
    rejection: ?extraction.TextRejection,
    tokens: @import("domain/structured_tokens.zig").Candidates,
    view: data.View = .{},
    held: [6]?*data.Value = [_]?*data.Value{null} ** 6,

    fn init(a: std.mem.Allocator, rejected: bool) !TextWorld {
        var ids: evidence_test.IdSource = .{};
        const inputs = try evidence_test.prepare(a, &ids, try ingest(a, "guidance.md", "Background context only."));
        const prepared = try text_fixture.prepare(a, inputs);
        const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id };
        const reason: extraction.text.ReferenceSemanticText = if (rejected) .{ .nodes = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } else .{ .nodes = &.{.{ .literal = .{ .value = "This source supplies background context." } }} };
        // The entries outlive this frame (the world holds them), so they cannot be a stack literal.
        const entries = try a.alloc(extraction.ParsedResult, 1);
        entries[0] = .{ .scope = scope, .token_classifications = &.{}, .outcome = .{ .no_feature_claim = reason } };
        const candidate: extraction.Parsed = .{ .entries = entries };
        const checked = try text_fixture.validate_text.execute(a, prepared.registry, text_fixture.safety.value(prepared.owner), inputs, candidate);
        var world: TextWorld = .{ .inputs = inputs, .prepared = prepared, .candidate = candidate, .rejection = if (rejected) checked.invalid else null, .tokens = try token_fixture.candidates(a, inputs) };
        errdefer world.deinit();
        const toolchain = @import("application/toolchain_workflow_values.zig").valid;
        world.hold(0, try values.adopt(std.testing.allocator, toolchain, text_fixture.safety.ValidToolchain, text_fixture.safety.Owner, prepared.owner, text_fixture.safety.value, text_fixture.safety.deinitOwner, text_fixture.safety.retainedBytes(prepared.owner)), toolchain.key);
        const source_schema = @import("application/reference_evidence_workflow.zig").inputs_schema;
        world.hold(1, try values.create(std.testing.allocator, source_schema, evidence.Inputs, inputs), source_schema.key);
        const registry_schema = @import("application/passive_literal_workflow.zig").registry_schema;
        world.hold(2, try values.create(std.testing.allocator, registry_schema, @import("domain/passive_literals.zig").Registry, prepared.registry), registry_schema.key);
        const tokens_schema = @import("application/structured_token_workflow.zig").candidates_schema;
        world.hold(3, try values.create(std.testing.allocator, tokens_schema, @import("domain/structured_tokens.zig").Candidates, world.tokens), tokens_schema.key);
        world.hold(4, try publishPayload(native.parsed_schema, .{ .parsed = candidate }), native.parsed_schema.key);
        world.hold(5, try publishPayload(native.text_schema, if (rejected) .{ .text_rejected = checked.invalid } else .{ .text_validated = checked.valid }), native.text_schema.key);
        return world;
    }

    fn hold(self: *TextWorld, slot: usize, value: *data.Value, key: Key) void {
        self.held[slot] = value;
        self.view.slots[@intFromEnum(key)] = value;
    }

    fn deinit(self: *TextWorld) void {
        for (self.held) |slot| if (slot) |value| values.destroy(value);
    }

    fn facts(self: *const TextWorld) !text_domain.Facts {
        return contexts.textFacts(self.inputs, self.prepared.registry, text_fixture.safety.value(self.prepared.owner), self.candidate);
    }
};

fn publishPayload(schema: data.Schema, payload: @FieldType(reference_value.Owner, "payload")) !*data.Value {
    const owner = try reference_value.create(std.testing.allocator, null);
    errdefer reference_value.destroy(owner);
    owner.payload = payload;
    return (try native.publish(std.testing.allocator, schema, owner, .ok)).delta.data_writes[@intFromEnum(schema.key)].?;
}

const text_replacement: text_domain.Replacement = .{ .reference = .{ .nodes = &.{.{ .literal = .{ .value = "This source supplies background context." } }} } };

test "the reference-text route runs authorize, input, parse and merge through the generic operations over a real text rejection" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var world = try TextWorld.init(a, true);
    defer world.deinit();
    var view = world.view;
    const facts = try world.facts();
    const expected_authorization = try text_domain.authorize(a, facts, world.rejection.?);

    // Authorize: a model replacement is authorized, with its permit, and writes only the authorization.
    var authorize_context: generic.AuthorizeRepair = undefined;
    authorize_context.reference_text = .{ .allocator = std.testing.allocator };
    const authorized = try call(generic.AuthorizeRepair, .authorize, .reference_text, &authorize_context, view);
    try std.testing.expectEqual(.ok, authorized.outcome);
    try expectDelta(authorized.delta, &.{.reference_text_repair_authorization}, &.{}, &.{});
    try std.testing.expect(authorized.delta.repair_transition != null and authorized.delta.repair_transition.? == .authorized);
    const authorization_value = authorized.delta.data_writes[@intFromEnum(text_binding.authorization_schema.key)].?;
    defer values.destroy(authorization_value);
    view.slots[@intFromEnum(text_binding.authorization_schema.key)] = authorization_value;

    // Input: the packet the domain function builds for the same authorization, and nothing else.
    var input_context: generic.BuildRepairInput = undefined;
    input_context.reference_text = .{ .allocator = std.testing.allocator };
    const built = try call(generic.BuildRepairInput, .build_input, .reference_text, &input_context, view);
    try std.testing.expectEqual(.ok, built.outcome);
    try expectDelta(built.delta, &.{.model_input_packet}, &.{}, &.{});
    const packet_value = built.delta.data_writes[@intFromEnum(requests.packet_schema.key)].?;
    const built_packet = try values.read(&.{ .slots = built.delta.data_writes }, requests.packet_schema, packets.Packet);
    const expected_packet = try text_domain.packet(std.testing.allocator, facts, world.prepared.registry, text_fixture.safety.value(world.prepared.owner), world.tokens, expected_authorization);
    defer packets.release(expected_packet);
    try std.testing.expectEqualStrings(expected_packet.body(), built_packet.body());

    // A real request answers that packet; the runner's keys are the parse's model evidence.
    var model: model_tests.Fixture = undefined;
    try model.init(std.testing.allocator);
    defer model.deinit();
    var request: Request = undefined;
    try request.start(&model, "design/workflows/spec/extraction.schema.json", packet_value, authorized.delta.repair_transition.?, try json.encodeSelected(text_domain.Replacement, a, text_replacement));
    defer request.deinit();
    var next = request.view();
    for (world.view.slots, 0..) |slot, index| if (slot) |value| {
        next.slots[index] = value;
    };
    next.slots[@intFromEnum(text_binding.authorization_schema.key)] = authorization_value;

    // Parse: the replacement is retained beside the authorization, and nothing is replaced.
    var parse_context: generic.ParseRepair = undefined;
    parse_context.reference_text = .{ .allocator = std.testing.allocator };
    const parsed = try call(generic.ParseRepair, .parse, .reference_text, &parse_context, next);
    try std.testing.expectEqual(.ok, parsed.outcome);
    try expectDelta(parsed.delta, &.{.reference_text_repair_result}, &.{}, &.{});
    const result_value = parsed.delta.data_writes[@intFromEnum(text_binding.result_schema.key)].?;
    defer values.destroy(result_value);
    next.slots[@intFromEnum(text_binding.result_schema.key)] = result_value;

    // Merge: the parsed extraction is replaced by what the domain merge produces, the three keys the
    // repair spent are invalidated, and the repair is recorded as a native merge.
    var merge_context: generic.MergeRepair = undefined;
    merge_context.reference_text = .{ .allocator = std.testing.allocator, .normalizer = text_fixture.normalizer };
    const merged = try call(generic.MergeRepair, .merge, .reference_text, &merge_context, next);
    defer discard(merged.delta);
    try std.testing.expectEqual(.ok, merged.outcome);
    try expectDelta(merged.delta, &.{}, &.{.parsed_reference_extraction}, &.{ .text_validated_reference_extraction, .reference_text_repair_authorization, .reference_text_repair_result });
    try std.testing.expect(merged.delta.repair_transition != null);
    const accepted = try candidate_handoff.read(&next);
    const direct = try text_domain.parse(a, expected_authorization, built_packet, accepted.body);
    var canonical = try typed_text.CanonicalText.fromInputs(a, text_fixture.normalizer, facts.text.inputs);
    defer canonical.deinit(a);
    const expected = try text_domain.merge(a, canonical, facts, expected_authorization, direct, accepted.origin);
    const merged_parsed = (try native.read(&.{ .slots = merged.delta.data_replacements }, native.parsed_schema, .parsed)).payload().parsed;
    try std.testing.expectEqualDeep(expected, merged_parsed);
    // And the repair did its work: the repaired candidate passes the text validator that rejected it.
    const valid = (try text_fixture.validate_text.execute(a, world.prepared.registry, text_fixture.safety.value(world.prepared.owner), world.inputs, merged_parsed)).valid;
    try std.testing.expect(valid.entries[0].outcome == .no_feature_claim);
}

test "each reference-text operation fails closed over data that is not its native facts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var rejected = try TextWorld.init(a, true);
    defer rejected.deinit();
    var accepted = try TextWorld.init(a, false);
    defer accepted.deinit();

    var authorize_context: generic.AuthorizeRepair = undefined;
    authorize_context.reference_text = .{ .allocator = std.testing.allocator };
    // The text key is present and holds a valid text, not a rejection: the owner finds no native fact.
    try std.testing.expectError(error.RepairOwnerMismatch, call(generic.AuthorizeRepair, .authorize, .reference_text, &authorize_context, accepted.view));
    // The text key is absent.
    var without_text = rejected.view;
    without_text.slots[@intFromEnum(native.text_schema.key)] = null;
    try std.testing.expectError(error.MissingRequiredData, call(generic.AuthorizeRepair, .authorize, .reference_text, &authorize_context, without_text));

    // Input, parse and merge each read the authorization the authorize step wrote.
    var input_context: generic.BuildRepairInput = undefined;
    input_context.reference_text = .{ .allocator = std.testing.allocator };
    try std.testing.expectError(error.MissingRequiredData, call(generic.BuildRepairInput, .build_input, .reference_text, &input_context, rejected.view));
    var parse_context: generic.ParseRepair = undefined;
    parse_context.reference_text = .{ .allocator = std.testing.allocator };
    try std.testing.expectError(error.MissingRequiredData, call(generic.ParseRepair, .parse, .reference_text, &parse_context, rejected.view));
    var merge_context: generic.MergeRepair = undefined;
    merge_context.reference_text = .{ .allocator = std.testing.allocator, .normalizer = text_fixture.normalizer };
    try std.testing.expectError(error.MissingRequiredData, call(generic.MergeRepair, .merge, .reference_text, &merge_context, rejected.view));
}

// -------------------------------------------------- specification support

const authority = @import("domain/required_authority.zig");
const support_domain = @import("domain/specification_support.zig").Source;
const support_repair = @import("domain/specification_support_repair.zig").Source;
const support_binding = @import("application/specification_support_repair_workflow.zig");
const support_workflow = @import("application/specification_support_workflow.zig");
const authority_workflow = @import("application/required_authority_workflow.zig");
const authority_owned = @import("application/required_authority_values.zig");
const guidance_workflow = @import("application/packet_guidance_workflow.zig");
const spec_tests = @import("specification_generation_test.zig");
const packet_guidance = @import("test_fixtures/packet_guidance.zig");
const OutcomeTag = @import("domain/workflow.zig").OutcomeTag;
const Rejected = @FieldType(support_domain.Collection, "rejected");

/// How the real rejected review is made: a whole review one finding of which names a source that does
/// not exist, or the first focused subject answered with such a source (a working candidate, so a
/// repaired review is still incomplete).
const SupportShape = enum { whole_review, focused };

const SupportWorld = struct {
    fixture: spec_tests.Fixture,
    inputs: authority.Inputs,
    rejected: Rejected,
    view: data.View = .{},
    held: [7]?*data.Value = [_]?*data.Value{null} ** 7,

    fn init(a: std.mem.Allocator, shape: SupportShape) !SupportWorld {
        const fixture = switch (shape) {
            .whole_review => try spec_tests.Fixture.init(a, "On startup display `MOCK Hello, World!`."),
            .focused => try spec_tests.Fixture.initContent(a, "A borrower may renew an eligible loan and see the new deadline.", null, false, 1),
        };
        const inputs = try spec_tests.readinessSupportInputs(&fixture);
        const guidance = &packet_guidance.marked;
        const rejected: Rejected = switch (shape) {
            .whole_review => whole: {
                const good = try spec_tests.reviewFor(a, inputs, fixture.context.inputs);
                const findings = try a.dupe(support_domain.Finding, good.entries);
                findings[1].value.source_ids = &.{.{ .ordinal = 2 }};
                break :whole (try spec_tests.collectReview(support_domain, a, inputs, fixture.context, try json.encode(support_domain.Review, a, .{ .entries = findings }), null)).rejected;
            },
            .focused => focused: {
                const ledger = try authority.build(a, inputs);
                const packet = try support_domain.packetFor(std.testing.allocator, inputs, fixture.context, guidance, .{ .finding = ledger.requirements[0].seed.id });
                defer packets.release(packet);
                const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 701 }, .attempt = .{ .value = 1 } };
                break :focused (try support_domain.collectFocused(a, inputs, fixture.context, guidance, null, packet, "{\"kind\":\"supported\",\"source_ids\":[999],\"detail\":\"\"}", origin)).rejected;
            },
        };
        var world: SupportWorld = .{ .fixture = fixture, .inputs = inputs, .rejected = rejected };
        // The toolchain takes the fixture's owner, so it is released with the world.
        world.hold(0, try values.adopt(std.testing.allocator, @import("application/toolchain_workflow_values.zig").valid, text_fixture.safety.ValidToolchain, text_fixture.safety.Owner, fixture.passive.owner, text_fixture.safety.value, text_fixture.safety.deinitOwner, text_fixture.safety.retainedBytes(fixture.passive.owner)), @import("application/toolchain_workflow_values.zig").valid.key);
        errdefer world.deinit();
        const sources = @import("application/reference_evidence_workflow.zig").inputs_schema;
        world.hold(1, try values.create(std.testing.allocator, sources, evidence.Inputs, fixture.context.inputs), sources.key);
        const registry = @import("application/passive_literal_workflow.zig").registry_schema;
        world.hold(2, try values.create(std.testing.allocator, registry, @import("domain/passive_literals.zig").Registry, fixture.context.registry), registry.key);
        const accounted = @import("application/reference_reconciliation_workflow.zig").accounted_schema;
        world.hold(3, try publishPayload(accounted, .{ .reconciliation_accounted = fixture.context.references }), accounted.key);
        world.hold(4, try values.create(std.testing.allocator, guidance_workflow.schema, @import("domain/packet_guidance.zig").Guidance, guidance.*), guidance_workflow.schema.key);
        world.hold(5, try world.authorityValue(authority_workflow.inputs_schema, .{ .inputs = inputs }), authority_workflow.inputs_schema.key);
        world.hold(6, try world.authorityValue(support_workflow.schema, .{ .support = .{ .rejected = rejected } }), support_workflow.schema.key);
        return world;
    }

    fn hold(self: *SupportWorld, slot: usize, value: *data.Value, key: Key) void {
        self.held[slot] = value;
        self.view.slots[@intFromEnum(key)] = value;
    }

    fn deinit(self: *SupportWorld) void {
        for (self.held) |slot| if (slot) |value| values.destroy(value);
    }

    /// A required-authority value created from what the world holds so far, as the engine retains it.
    fn authorityValue(self: *const SupportWorld, schema: data.Schema, payload: authority_owned.Payload) !*data.Value {
        return authorityValueOver(self.view, schema, payload);
    }
};

fn authorityValueOver(view: data.View, schema: data.Schema, payload: authority_owned.Payload) !*data.Value {
    const owner = try authority_owned.create(std.testing.allocator, view);
    errdefer authority_owned.destroy(owner);
    owner.payload = payload;
    return values.adopt(std.testing.allocator, schema, authority_owned.Value, authority_owned.Owner, owner, authority_owned.view, authority_owned.destroy, null);
}

test "the specification-support route runs authorize, input, parse and merge through the generic operations over a real rejected review" {
    var saw: [2]OutcomeTag = undefined;
    for ([_]SupportShape{ .whole_review, .focused }, 0..) |shape, index| saw[index] = try supportRoute(shape);
    // A repaired whole review is complete; a repaired focused subject leaves the rest to collect.
    try std.testing.expectEqualSlices(OutcomeTag, &.{ .ok, .more }, &saw);
}

/// Returns the merge outcome so the caller can state which results the shapes reach.
fn supportRoute(shape: SupportShape) !OutcomeTag {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var world = try SupportWorld.init(a, shape);
    defer world.deinit();
    var view = world.view;
    const context = world.fixture.context;
    const guidance = &packet_guidance.marked;
    const candidate = world.rejected.candidate.?;
    const expected_authorization = try support_repair.authorize(a, world.inputs, context, guidance, world.rejected);
    try std.testing.expect(expected_authorization.operation == .replace);

    // Authorize: the review's selection is replaced under a permit, and only the repair state is written.
    var authorize_context: generic.AuthorizeRepair = undefined;
    authorize_context.specification_support = .{ .allocator = std.testing.allocator };
    const authorized = try call(generic.AuthorizeRepair, .authorize, .specification_support, &authorize_context, view);
    try std.testing.expectEqual(.ok, authorized.outcome);
    try expectDelta(authorized.delta, &.{.specification_support_repair}, &.{}, &.{});
    try std.testing.expect(authorized.delta.repair_transition != null and authorized.delta.repair_transition.? == .authorized);
    const state_value = authorized.delta.data_writes[@intFromEnum(support_binding.schema.key)].?;
    defer values.destroy(state_value);
    view.slots[@intFromEnum(support_binding.schema.key)] = state_value;
    const state = try authority_owned.read(&view, support_binding.schema, .support_repair);
    try std.testing.expectEqualDeep(expected_authorization, state.authorization);
    try std.testing.expect(state.response == null);
    try std.testing.expect(!(try support_binding.authorizationBlocked(&view)));

    // Input: the packet the domain function builds for the same authorization.
    var input_context: generic.BuildRepairInput = undefined;
    input_context.specification_support = .{ .allocator = std.testing.allocator };
    const built = try call(generic.BuildRepairInput, .build_input, .specification_support, &input_context, view);
    try std.testing.expectEqual(.ok, built.outcome);
    try expectDelta(built.delta, &.{.model_input_packet}, &.{}, &.{});
    const packet_value = built.delta.data_writes[@intFromEnum(requests.packet_schema.key)].?;
    const built_packet = try values.read(&.{ .slots = built.delta.data_writes }, requests.packet_schema, packets.Packet);
    const expected_packet = try support_repair.packet(std.testing.allocator, world.inputs, context, guidance, candidate, expected_authorization);
    defer packets.release(expected_packet);
    try std.testing.expectEqualStrings(expected_packet.body(), built_packet.body());

    // A real request answers that packet: the one existing source.
    const admission = @import("domain/specification_support_evidence.zig");
    try std.testing.expectEqualDeep(&[_]@import("domain/reference_identity.zig").SourceId{.{ .ordinal = 1 }}, try admission.sourceChoices(a, context.inputs));
    var model: model_tests.Fixture = undefined;
    try model.init(std.testing.allocator);
    defer model.deinit();
    var request: Request = undefined;
    try request.start(&model, "design/workflows/spec/support.schema.json", packet_value, authorized.delta.repair_transition.?, "{\"source_ids\":[1]}");
    defer request.deinit();
    var next = request.view();
    for (world.view.slots, 0..) |slot, index| if (slot) |value| {
        next.slots[index] = value;
    };
    next.slots[@intFromEnum(support_binding.schema.key)] = state_value;

    // Parse: the response is retained in the repair state, replacing the authorization-only state.
    var parse_context: generic.ParseRepair = undefined;
    parse_context.specification_support = .{ .allocator = std.testing.allocator };
    const parsed = try call(generic.ParseRepair, .parse, .specification_support, &parse_context, next);
    try std.testing.expectEqual(.ok, parsed.outcome);
    try expectDelta(parsed.delta, &.{}, &.{.specification_support_repair}, &.{});
    const parsed_value = parsed.delta.data_replacements[@intFromEnum(support_binding.schema.key)].?;
    defer values.destroy(parsed_value);
    const parsed_state = try authority_owned.read(&.{ .slots = parsed.delta.data_replacements }, support_binding.schema, .support_repair);
    const handoff = try candidate_handoff.read(&next);
    const expected_response = try support_repair.parse(a, expected_authorization, built_packet, handoff.body);
    try std.testing.expectEqualDeep(expected_authorization, parsed_state.authorization);
    try std.testing.expectEqualDeep(expected_response, parsed_state.response.?.value);
    try std.testing.expectEqualDeep(handoff.origin, parsed_state.response.?.origin);
    next.slots[@intFromEnum(support_binding.schema.key)] = parsed_value;

    // Merge: the review is replaced by what the domain merge produces, the repair state is spent, and the
    // outcome is the one the merged collection maps to.
    var merge_context: generic.MergeRepair = undefined;
    merge_context.specification_support = .{ .allocator = std.testing.allocator, .normalizer = text_fixture.normalizer };
    const merged = try call(generic.MergeRepair, .merge, .specification_support, &merge_context, next);
    defer discard(merged.delta);
    var canonical = try typed_text.CanonicalText.fromInputs(a, text_fixture.normalizer, context.inputs);
    defer canonical.deinit(a);
    const expected_result = try support_repair.merge(a, canonical, world.inputs, context, guidance, candidate, expected_authorization, expected_response, handoff.origin);
    const expected_outcome: OutcomeTag = switch (expected_result) {
        .accepted => .ok,
        .pending => .more,
        .rejected => .invalid,
    };
    try std.testing.expectEqual(expected_outcome, merged.outcome);
    try expectDelta(merged.delta, &.{}, &.{.specification_support_review}, &.{.specification_support_repair});
    try std.testing.expect(merged.delta.repair_transition != null);
    const merged_progress = try support_workflow.progress(&.{ .slots = merged.delta.data_replacements });
    try std.testing.expectEqualDeep(expected_result, merged_progress.source);

    // A response that changes nothing leaves the same defect: the review stays rejected and the outcome is
    // invalid, with the repair state still spent.
    const unchanged_value = try authorityValueOver(world.view, support_binding.schema, .{ .support_repair = .{ .authorization = expected_authorization, .response = .{ .value = expected_authorization.operation.replace, .origin = null } } });
    defer values.destroy(unchanged_value);
    var unchanged_view = world.view;
    unchanged_view.slots[@intFromEnum(support_binding.schema.key)] = unchanged_value;
    const unchanged = try call(generic.MergeRepair, .merge, .specification_support, &merge_context, unchanged_view);
    defer discard(unchanged.delta);
    try std.testing.expectEqual(.invalid, unchanged.outcome);
    try expectDelta(unchanged.delta, &.{}, &.{.specification_support_review}, &.{.specification_support_repair});
    try std.testing.expect(unchanged.delta.repair_transition != null);
    const still_rejected = (try support_workflow.progress(&.{ .slots = unchanged.delta.data_replacements })).source.rejected;
    try std.testing.expectEqualDeep(candidate.review, still_rejected.candidate.?.review);
    return merged.outcome;
}

test "a rejected review with no candidate is blocked at authorization, with the repair state carrying why" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var world = try SupportWorld.init(a, .whole_review);
    defer world.deinit();
    // The real rejection, but no candidate the repair could target: the domain refuses it as unsafe.
    const without_candidate: Rejected = .{ .candidate = null, .rejection = world.rejected.rejection };
    const review_value = try authorityValueOver(world.view, support_workflow.schema, .{ .support = .{ .rejected = without_candidate } });
    defer values.destroy(review_value);
    var view = world.view;
    view.slots[@intFromEnum(support_workflow.schema.key)] = review_value;
    const domain_error = error.UnsafeSupportRepair;
    try std.testing.expectError(domain_error, support_repair.authorize(a, world.inputs, world.fixture.context, &packet_guidance.marked, without_candidate));

    var authorize_context: generic.AuthorizeRepair = undefined;
    authorize_context.specification_support = .{ .allocator = std.testing.allocator };
    const blocked = try call(generic.AuthorizeRepair, .authorize, .specification_support, &authorize_context, view);
    defer discard(blocked.delta);
    try std.testing.expectEqual(.blocked, blocked.outcome);
    try std.testing.expectEqual(domain_error, blocked.diagnostic.?);
    try expectDelta(blocked.delta, &.{.specification_support_repair}, &.{}, &.{});
    try std.testing.expect(blocked.delta.repair_transition == null);
    var after = view;
    after.slots[@intFromEnum(support_binding.schema.key)] = blocked.delta.data_writes[@intFromEnum(support_binding.schema.key)];
    try std.testing.expect(try support_binding.authorizationBlocked(&after));
}

test "each specification-support operation fails closed over data that is not its native facts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var world = try SupportWorld.init(a, .whole_review);
    defer world.deinit();
    const review_key = @intFromEnum(support_workflow.schema.key);
    const repair_key = @intFromEnum(support_binding.schema.key);

    var authorize_context: generic.AuthorizeRepair = undefined;
    authorize_context.specification_support = .{ .allocator = std.testing.allocator };
    // The review key is absent.
    var without_review = world.view;
    without_review.slots[review_key] = null;
    try std.testing.expectError(error.MissingRequiredData, call(generic.AuthorizeRepair, .authorize, .specification_support, &authorize_context, without_review));
    // The review key is present but holds no rejected review: a pending one, then one not yet begun.
    const pending = try world.authorityValue(support_workflow.schema, .{ .support = .{ .pending = world.rejected.candidate.? } });
    defer values.destroy(pending);
    var holding_pending = world.view;
    holding_pending.slots[review_key] = pending;
    try std.testing.expectError(error.RepairOwnerMismatch, call(generic.AuthorizeRepair, .authorize, .specification_support, &authorize_context, holding_pending));
    const initial = try world.authorityValue(support_workflow.schema, .support_initial);
    defer values.destroy(initial);
    var holding_initial = world.view;
    holding_initial.slots[review_key] = initial;
    try std.testing.expectError(error.RepairOwnerMismatch, call(generic.AuthorizeRepair, .authorize, .specification_support, &authorize_context, holding_initial));

    // Input, parse and merge each read the repair state authorize wrote: absent, then of another kind.
    const wrong_state = try world.authorityValue(support_binding.schema, .support_initial);
    defer values.destroy(wrong_state);
    var holding_wrong = world.view;
    holding_wrong.slots[repair_key] = wrong_state;
    var input_context: generic.BuildRepairInput = undefined;
    input_context.specification_support = .{ .allocator = std.testing.allocator };
    var parse_context: generic.ParseRepair = undefined;
    parse_context.specification_support = .{ .allocator = std.testing.allocator };
    var merge_context: generic.MergeRepair = undefined;
    merge_context.specification_support = .{ .allocator = std.testing.allocator, .normalizer = text_fixture.normalizer };
    try std.testing.expectError(error.MissingRequiredData, call(generic.BuildRepairInput, .build_input, .specification_support, &input_context, world.view));
    try std.testing.expectError(error.MissingRequiredData, call(generic.ParseRepair, .parse, .specification_support, &parse_context, world.view));
    try std.testing.expectError(error.MissingRequiredData, call(generic.MergeRepair, .merge, .specification_support, &merge_context, world.view));
    try std.testing.expectError(error.RepairOwnerMismatch, call(generic.BuildRepairInput, .build_input, .specification_support, &input_context, holding_wrong));
    try std.testing.expectError(error.RepairOwnerMismatch, call(generic.ParseRepair, .parse, .specification_support, &parse_context, holding_wrong));
    try std.testing.expectError(error.RepairOwnerMismatch, call(generic.MergeRepair, .merge, .specification_support, &merge_context, holding_wrong));
}
