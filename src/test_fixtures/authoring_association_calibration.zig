//! Current authoring qualification preparation, without dispatch or semantic proof.
//! Every packet, schema restriction, association and review projection uses its
//! production owner; scripted context seeds are explicitly offline fixtures.
const std = @import("std");
const shared = @import("source_loss_calibration.zig");
const text = @import("reference_text.zig");
const g = @import("../domain/specification_generation.zig");
const session = @import("../domain/specification_session.zig");
const spec = g.spec;
const packets = @import("../domain/model_input_packet.zig");
const codec = @import("../domain/model_candidate_json.zig");
const binding = @import("../domain/specification_source_binding.zig");
const schema_owner = @import("../domain/model_result_schema.zig");
const root = "test/calibration/authoring-associations";
const output = ".zig-cache/authoring-associations/v14-text";
const captured_run = "zig-out/e2e-spec/2026-10-11T07-50-47Z-7c05a7d38e4f86264d45ec27a08a4959";
const captured_feature = captured_run ++ "/project/specs/hello-world";
const parent_identity: shared.ReviewParent = .{ .run = "RUN-5603b655c6e6a7498c6980fc0d447584", .call = "request-1-inference-1" };

const Seed = struct {
    title: []const u8,
    description: []const u8,
    primary_goal: []const u8,
    story: []const u8,
    entity_disposition: spec.Applicability,
    entity_basis: []const u8,
    given: []const u8,
    when: []const u8,
    then: []const u8,
    functional_requirement: []const u8,
    entity_name: ?[]const u8,
};
const RecordSeed = struct {
    group_id: u32,
    given: ?[]const u8,
    when: ?[]const u8,
    then: ?[]const u8,
    functional_requirement: ?[]const u8,
    entity_name: ?[]const u8,
};
const Case = struct {
    id: []const u8,
    fixture: shared.Case,
    source_file: ?[]const u8,
    groups: []const u32,
    seed: Seed,
    record_seeds: []const RecordSeed,
    expectation: struct {
        obligations: []const []const u8,
        support_examples: []const u32,
        entity_decision: spec.Applicability,
        literal: ?[]const u8,
        gap: ?[]const u8,
        forbidden: []const []const u8,
    },
};
const File = struct { path: []const u8, sha256: []const u8, bytes: usize };
const ParentPreparation = union(enum) { unavailable: void, ready: File };
const Request = struct {
    unit: []const u8,
    group_id: ?u32,
    packet: File,
    edit: File,
    request: File,
};
const Trial = struct {
    id: []const u8,
    case_id: []const u8,
    repetition: u32,
    requests: []const Request,
};
const Run = struct {
    schema: enum { @"authoring-diagnostic-run/v1" },
    preparation_sha256: []const u8,
    parent: shared.ReviewParent,
};
const ReplayOrigin = struct { parent: shared.ReviewParent, run: []const u8, id: []const u8 };
const Receipt = struct {
    schema: enum { @"authoring-diagnostic-receipt/v1" },
    trial_id: []const u8,
    input: []const u8,
    request_sha256: []const u8,
    response_sha256: []const u8,
    result: struct { request: @import("../domain/request_debugger.zig").RequestRecord, response: @import("../domain/request_debugger.zig").ResponseRecord },
    replay_elapsed_ns: ?u64,
};
const Cost = struct {
    origin: ReplayOrigin,
    usage: ?@import("../domain/llm_provider_operation.zig").ProviderUsage = null,
    replay_elapsed_ns: ?u64,
    provider_stop: ?[]const u8 = null,
};
const CaseState = struct { context: @import("../domain/specification_provenance.zig").Context, seed: session.Session };
const ExcludedRecordSeed = struct { seed: RecordSeed, reason: enum { preserved_tokens_only } };
const RecordPopulation = struct {
    case_id: []const u8,
    historical_seed_count: usize,
    scheduled_seed_count: usize,
    excluded_seed_count: usize,
    scheduled: []const RecordSeed,
    excluded: []const ExcludedRecordSeed,
};

fn recordPopulation(a: std.mem.Allocator, example: Case, current: session.Session, context: @import("../domain/specification_provenance.zig").Context) !RecordPopulation {
    const records = @import("../domain/reference_support.zig").records(context.references);
    const available = try binding.catalogue(a, records, .question);
    defer a.free(available);
    const scheduled = try a.alloc(RecordSeed, current.record_group_count);
    for (scheduled, 0..) |*seed, index| {
        const assigned = (try binding.record(a, records, context.inputs, index)).records;
        defer a.free(assigned.selection.claim_ids);
        var found: ?RecordSeed = null;
        for (example.record_seeds) |historical| if (historical.group_id == assigned.signal.ordinal) {
            if (found != null) return error.InvalidCalibrationCase;
            found = historical;
        };
        seed.* = found orelse return error.InvalidCalibrationCase;
    }
    var excluded: std.ArrayList(ExcludedRecordSeed) = .empty;
    for (example.record_seeds, 0..) |seed, index| {
        for (example.record_seeds[0..index]) |prior| if (prior.group_id == seed.group_id) return error.InvalidCalibrationCase;
        const included = for (scheduled) |active| {
            if (seed.group_id == active.group_id) break true;
        } else false;
        if (included) continue;
        const active = for (available) |group| {
            if (group.signal_id.ordinal == seed.group_id) break true;
        } else false;
        if (!active) return error.InvalidCalibrationCase;
        if (!try binding.tokenOnly(records, .{ .ordinal = seed.group_id })) return error.InvalidCalibrationCase;
        try excluded.append(a, .{ .seed = seed, .reason = .preserved_tokens_only });
    }
    try std.testing.expectEqual(example.record_seeds.len, scheduled.len + excluded.items.len);
    return .{ .case_id = example.id, .historical_seed_count = example.record_seeds.len, .scheduled_seed_count = scheduled.len, .excluded_seed_count = excluded.items.len, .scheduled = scheduled, .excluded = excluded.items };
}

fn recordPopulationChecks(a: std.mem.Allocator, example: Case, current: session.Session, context: @import("../domain/specification_provenance.zig").Context, population: RecordPopulation) !void {
    try std.testing.expectEqual(@as(usize, 1), population.excluded.len);
    var malformed = example;
    const seeds = try a.dupe(RecordSeed, example.record_seeds);
    malformed.record_seeds = seeds;
    seeds[seeds.len - 1].group_id = 999999;
    try std.testing.expectError(error.InvalidCalibrationCase, recordPopulation(a, malformed, current, context));
    seeds[seeds.len - 1] = seeds[0];
    try std.testing.expectError(error.InvalidCalibrationCase, recordPopulation(a, malformed, current, context));
    malformed.record_seeds = &.{};
    try std.testing.expectError(error.InvalidCalibrationCase, recordPopulation(a, malformed, current, context));
    var inactive = context;
    const r = @import("../domain/reference_reconciliation.zig");
    const dispositions = try a.dupe(r.ClaimDisposition, @import("../domain/reference_support.zig").records(context.references).dispositions);
    const excluded = population.excluded[0].seed.group_id;
    const claims = for (context.references.records.signals) |group| {
        if (group.id.ordinal == excluded) break group.value.claim_ids;
    } else return error.InvalidCalibrationCase;
    for (dispositions) |*entry| if (r.contains(r.ClaimId, claims, entry.claim_id)) {
        entry.disposition = .superseded;
    };
    inactive.references.records.assignments.checked.prior.prior.dispositions = dispositions;
    try std.testing.expectError(error.InvalidCalibrationCase, recordPopulation(a, example, current, inactive));
}
const Observation = struct {
    trial_id: []const u8,
    status: enum { not_run, incomplete, rejected, admitted_content, admitted_clarification },
    received: usize = 0,
    costs_complete: bool = false,
    rejection: ?[]const u8 = null,
    issue: ?@import("../domain/specification_candidate.zig").Issue = null,
    projection_error: ?[]const u8 = null,
    origins: []const ReplayOrigin = &.{},
    costs: []const Cost = &.{},
    responses: []const g.CanonicalResponse = &.{},
    review_packets: []const []const u8 = &.{},
};

pub fn run() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = try @import("../domain/strict_json.zig").decode([]const Case, a, try shared.read(a, root ++ "/cases.json"), .{ .maximum_depth = 128 });
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try shared.read(a, "design/workflows/spec/generation.schema.json"));
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    var trials: std.ArrayList(Trial) = .empty;
    var starts: std.ArrayList(session.Session) = .empty;
    var owners: std.ArrayList(shared.PreparedContext) = .empty;
    defer for (owners.items) |owner| owner.passive.deinit();
    const states = try a.alloc(CaseState, cases.len);
    var record_populations: std.ArrayList(RecordPopulation) = .empty;
    var physical_sends: usize = 0;
    for (cases, 0..) |example, index| {
        for (cases[0..index]) |prior| try std.testing.expect(!std.mem.eql(u8, prior.id, example.id));
        try std.testing.expect(@import("../domain/workflow.zig").WorkflowId.parse(example.id) != null);
        if (example.source_file) |source| try std.testing.expectEqualStrings(example.fixture.sources[0], try shared.read(a, source));
        const prepared = try shared.prepareContext(a, example.fixture);
        try owners.append(a, prepared);
        var current = switch (try session.initialize(a, prepared.context.inputs.corpus.feature_id, prepared.context)) {
            .ready => |ready| ready,
            .blocked => return error.InvalidCalibrationCase,
        };
        const population = try recordPopulation(a, example, current, prepared.context);
        if (index == 0) try recordPopulationChecks(a, example, current, prepared.context, population);
        try record_populations.append(a, population);
        const ids = try a.alloc(@import("../domain/reference_reconciliation.zig").SignalId, example.groups.len);
        for (example.groups, ids) |id, *group| group.* = .{ .ordinal = id };
        const selected = try binding.resolveGroups(a, @import("../domain/reference_support.zig").records(prepared.context.references), prepared.context.inputs, ids, .content);
        const seeds = try narrativeSeeds(a, example, selected);
        for (seeds) |seed| {
            if (index == 0 and current.completed == 1) try singletonConstructionChecks(a, schema, current, prepared.context);
            const request = try exportRequest(a, schema, example.id, current, prepared.context);
            if (index == 0 and current.completed == 0) try receiptChecks(a, request, try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, prepared.context, seed)));
            try addTrials(a, &trials, example.id, request);
            for (0..2) |_| try starts.append(a, current);
            physical_sends += 2;
            current = try admittedSeed(a, schema, current, prepared.context, seed);
        }
        var record_requests: std.ArrayList(Request) = .empty;
        const records_start = current;
        for (population.scheduled) |seed| {
            const assigned = try session.currentBinding(a, current, prepared.context);
            try std.testing.expectEqual(seed.group_id, assigned.records.signal.ordinal);
            try record_requests.append(a, try exportRequest(a, schema, example.id, current, prepared.context));
            const records = try recordSeed(a, seed, assigned.records);
            current = try admittedSeed(a, schema, current, prepared.context, .{ .content = .{ .records = records } });
            physical_sends += 2;
        }
        for (1..3) |repeat| try trials.append(a, .{ .id = try std.fmt.allocPrint(a, "{s}-records-{d}", .{ example.id, repeat }), .case_id = example.id, .repetition = @intCast(repeat), .requests = record_requests.items });
        for (0..2) |_| try starts.append(a, records_start);
        states[index] = .{ .context = prepared.context, .seed = current };
        const candidate = try session.assemble(a, text.validator, prepared.context, current);
        const projected = try @import("../domain/specification_authority.zig").project(a, current.feature, prepared.context.references, candidate.content, current.units[0].?.response.content.brief);
        const review = @import("../domain/specification_support.zig").Source;
        const id: @import("../domain/required_authority.zig").Id = .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .description };
        const review_packet = try review.packetFor(a, projected, prepared.context, .{ .finding = id });
        defer packets.release(review_packet);
        try shared.writeAt(a, output, example.id, "seed-review.packet.json", review_packet.body());
        try shared.writeAt(a, output, example.id, "seed.json", try std.json.Stringify.valueAlloc(a, .{ .session = current, .brief = current.units[0].?.response.content.brief, .candidate = candidate.content }, .{}));
        // Expectation labels and authored context seeds never become initial
        // brief/story inputs. Later business context uses resolved prior units.
        const brief_body = try shared.read(a, try std.fmt.allocPrint(a, "{s}/{s}.brief.packet.json", .{ output, example.id }));
        try std.testing.expect(std.mem.indexOf(u8, brief_body, "expectation") == null);
        try std.testing.expect(std.mem.indexOf(u8, brief_body, example.seed.description) == null);
    }
    try std.testing.expectEqual(@as(usize, 3), cases.len);
    try std.testing.expectEqual(@as(usize, 24), trials.items.len);
    const parent = try wirePreflight(a, output, trials.items);
    const paths = [_][]const u8{
        root ++ "/cases.json",                                     root ++ "/README.md",                            root ++ "/scorecard.template.json",
        "src/test_fixtures/authoring_association_calibration.zig", "src/test_fixtures/source_loss_calibration.zig", "src/domain/specification_generation.zig",
        "src/domain/specification_session.zig",                    "src/domain/specification_source_binding.zig",   "src/domain/specification_provenance.zig",
        "src/domain/specification.zig",                            "src/domain/specification_coverage.zig",         "src/domain/specification_authority.zig",
        "src/domain/specification_support_evidence.zig",           "src/domain/model_result_schema.zig",            "src/domain/model_schema_projection.zig",
        "src/adapters/provider/bedrock_request.zig",               "design/workflows/spec/generation.schema.json",  "design/workflows/spec/generation.context.json",
        "design/workflows/spec/generation.prompt.md",              "design/workflows/spec/story.prompt.md",         "design/workflows/spec/entities.prompt.md",
        "design/workflows/spec/records.prompt.md",                 "design/workflows/spec.workflow.yaml",
    };
    var dependencies: std.ArrayList(File) = .empty;
    for (paths) |path| try dependencies.append(a, try pin(a, path));
    if (parent == .ready) for ([_][]const u8{ captured_run ++ "/evidence/generation/call-000001/context.json", captured_run ++ "/evidence/generation/call-000001/request.json", captured_feature ++ "/logs/prompts/" ++ parent_identity.run ++ "/LOGBIND-1/0001.log", captured_feature ++ "/logs/events/" ++ parent_identity.run ++ "/LOGBIND-1/0001.log" }) |path| try dependencies.append(a, try pin(a, path));
    for (cases) |example| if (example.source_file) |path| {
        var present = false;
        for (dependencies.items) |file| if (std.mem.eql(u8, file.path, path)) {
            present = true;
            break;
        };
        if (!present) try dependencies.append(a, try pin(a, path));
    };
    const preparation = try std.json.Stringify.valueAlloc(a, .{
        .status = "offline_prepared_no_live_dispatch_authority",
        .factor = "Initial production authoring with current group selection; controlled current prior units for dependent tasks. No like-for-like role-classifier baseline and no seed is a semantic result.",
        .settings = .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0", .region = "ap-southeast-2", .reasoning_effort = "low", .temperature = @import("calibration_temperature_policy.zig").temperature, .response_mode = "native_schema", .seed = "absent", .top_p = "absent" },
        .limits = .{ .cases = cases.len, .logical_trials = trials.items.len, .repetitions = 2, .physical_sends = physical_sends, .stop_at_actual_input_plus_output_tokens = 200000, .retries_corrections_repairs_model_judges_review_calls_e2e = 0 },
        .admission = "Actual response must pass its frozen schema, current native generation parse/validate/admit and record consistency. A diagnostic receipt is never native workflow origin or publication authority.",
        .downstream = "Native admitted authored associations determine the review subject and evidence. No review model calls or expected-value loss findings are prepared.",
        .parent = .{ .feature = captured_feature, .identity = parent_identity, .description = parent, .wire_preflight = "Current Converse modified bodies rebuilt through existing replay provider prepare; zero sends. A retained request with different wire bytes is ineligible as an exact current parent. Current compiled graph authorization is a separate required preflight." },
        .dependencies = dependencies.items,
        .record_authoring_population = record_populations.items,
        .trials = trials.items,
    }, .{});
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = output ++ "/preparation.json", .data = preparation });
    try collect(a, output, schema, cases, states, trials.items, starts.items, preparation, parent);
}

const PreparationAccess = struct {
    expected: @import("../domain/request_debugger.zig").Description,
    fn authorize(context: *@import("../ports/request_replay.zig").Context, supplied: @import("../domain/request_debugger.zig").Description) @import("../ports/request_replay.zig").Error!@import("../domain/llm_provider_contracts.zig").ProviderFacts {
        const self: *PreparationAccess = @ptrCast(@alignCast(context));
        if (!std.meta.eql(self.expected, supplied)) return error.ReplayUnauthorized;
        const model = @import("../composition/provider_model_contracts.zig").registry.resolve(
            @import("../domain/llm_provider_identity.zig").ProviderId.parse(supplied.provider) orelse return error.ReplayUnauthorized,
            @import("../domain/llm_provider_identity.zig").ModelId.parse(supplied.model) orelse return error.ReplayUnauthorized,
            supplied.provider_config,
        ) orelse return error.ReplayUnauthorized;
        if (!model.capabilities.supports(supplied.response_mode, supplied.controls) or
            !@import("../domain/llm_provider_contracts.zig").supportsReasoningEffort(model.supported_reasoning_efforts, supplied.reasoning_effort)) return error.ReplayUnauthorized;
        return model.facts;
    }
};

/// Rebuild authentic diagnostic descriptions through the existing replay adapter.
/// The empty environment and fake transport cannot send to an external provider.
fn wirePreflight(a: std.mem.Allocator, directory: []const u8, trials: []const Trial) !ParentPreparation {
    // A clean checkout still exercises every native packet/admission probe.
    // External archive availability only qualifies the separate live launcher.
    if (try optional(a, captured_run ++ "/evidence/generation/call-000001/context.json") == null) return .unavailable;
    const feature = try std.Io.Dir.cwd().openDir(std.testing.io, captured_feature, .{});
    defer feature.close(std.testing.io);
    var store: @import("../adapters/filesystem/request_debugger_store.zig").Store = .{ .io = std.testing.io, .feature = feature };
    const calls = store.load(a) catch |err| switch (err) {
        // Unsupported historical evidence cannot be a current replay parent.
        // All native packet/admission probes still execute independently.
        error.UnsupportedDebugDescriptionVersion => return .unavailable,
        else => return err,
    };
    var parent: ?@import("../domain/request_debugger.zig").Call = null;
    for (calls) |call| if (std.mem.eql(u8, call.run, parent_identity.run) and std.mem.eql(u8, call.id, parent_identity.call)) {
        if (parent != null) return error.AmbiguousCalibrationParent;
        parent = call;
    };
    const actual = parent orelse return error.MissingCalibrationParent;
    if (!actual.request_complete or actual.redacted or actual.description == null or actual.request == null or actual.replay != null) return error.InvalidCalibrationParent;
    const description = actual.description.?;
    try validateSettings(description);
    try std.testing.expectEqualStrings("g7-extract-content", description.request_step);
    try std.testing.expectEqualStrings("spec-generation", description.workflow_id);
    try std.testing.expectEqualStrings("spec_generation", description.model_slot);
    var access: PreparationAccess = .{ .expected = description };
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    var wire: @import("../model_transport_test_fixture.zig").Wire = .{};
    var clock: @import("../provider_authorization_test_fixture.zig").TestClock = .{};
    var compiler: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    var adapter: @import("../adapters/provider/request_replay.zig").Adapter = .{ .authorization = .{ .context = @ptrCast(&access), .authorize_fn = PreparationAccess.authorize }, .environment = &environment, .transport = wire.port(), .clock = clock.port(), .compiler = compiler.compiler() };
    const current_parent = std.mem.eql(u8, actual.request.?, try adapter.provider().prepare(a, description));
    for (trials) |trial| for (trial.requests) |request| {
        const edit = try @import("../domain/strict_json.zig").decode(@import("../domain/request_debugger.zig").Edit, a, try shared.read(a, request.edit.path), .{ .maximum_depth = 64 });
        var modified = description;
        modified.content = edit.content;
        modified.schema = edit.schema;
        access.expected = modified;
        try std.testing.expectEqualStrings(try shared.read(a, request.request.path), try adapter.provider().prepare(a, modified));
    };
    try std.testing.expectEqual(@as(usize, 0), wire.calls);
    // Exact replay admission is byte-exact. An old provider protocol never
    // becomes a current parent merely because its model/settings still match.
    if (!current_parent) return .unavailable;
    try shared.writeAt(a, directory, "parent", "description.json", try std.json.Stringify.valueAlloc(a, description, .{}));
    return .{ .ready = try pin(a, try std.fmt.allocPrint(a, "{s}/parent.description.json", .{directory})) };
}

fn addTrials(a: std.mem.Allocator, trials: *std.ArrayList(Trial), id: []const u8, request: Request) !void {
    for (1..3) |repeat| try trials.append(a, .{ .id = try std.fmt.allocPrint(a, "{s}-{s}-{d}", .{ id, request.unit, repeat }), .case_id = id, .repetition = @intCast(repeat), .requests = try a.dupe(Request, &.{request}) });
}
fn business(a: std.mem.Allocator, value: []const u8) !spec.BusinessValue {
    return .{ .segments = try a.dupe(@import("../domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = value } }}) };
}
fn attributed(a: std.mem.Allocator, value: []const u8, selected: binding.Association) !spec.Values(.model).AttributedValue {
    return .{ .value = try business(a, value), .source_group_ids = selected.source_group_ids, .provenance = selected.selection };
}
fn narrativeSeeds(a: std.mem.Allocator, example: Case, selected: binding.Association) ![3]g.Response {
    return .{
        .{ .content = .{ .brief = .{ .title = try attributed(a, example.seed.title, selected), .description = try attributed(a, example.seed.description, selected), .primary_goal = try attributed(a, example.seed.primary_goal, selected) } } },
        .{ .content = .{ .primary_user_story = try attributed(a, example.seed.story, selected) } },
        .{ .content = .{ .entities = .{ .disposition = example.seed.entity_disposition, .basis = try attributed(a, example.seed.entity_basis, selected), .records = if (example.seed.entity_name) |name| try a.dupe(spec.Model.RecordProposal, &.{.{ .content = .{ .entity = .{ .name = try business(a, name), .business_meaning = try business(a, "MOCK Controlled business entity seed."), .relationships = &.{} } }, .source_group_ids = selected.source_group_ids, .provenance = selected.selection }}) else &.{} } } },
    };
}
fn recordSeed(a: std.mem.Allocator, seed: RecordSeed, assigned: binding.RecordBound) ![]const spec.Values(.model).RecordProposal {
    var records: std.ArrayList(spec.Values(.model).RecordProposal) = .empty;
    const groups = try a.dupe(@import("../domain/reference_reconciliation.zig").SignalId, &.{assigned.signal});
    if (seed.functional_requirement) |requirement| try records.append(a, .{ .content = .{ .functional_requirement = .{ .text = try business(a, requirement) } }, .source_group_ids = groups, .provenance = assigned.selection });
    if (seed.given) |given| try records.append(a, .{ .content = .{ .acceptance_criterion = .{ .given = try business(a, given), .when = try business(a, seed.when orelse return error.InvalidCalibrationCase), .then = try business(a, seed.then orelse return error.InvalidCalibrationCase) } }, .source_group_ids = groups, .provenance = assigned.selection });
    return records.items;
}
fn admittedSeed(a: std.mem.Allocator, schema: *const schema_owner.Schema, current: session.Session, context: @import("../domain/specification_provenance.zig").Context, proposed: g.Response) !session.Session {
    const bytes = try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, context, proposed));
    const checked = switch (try admitResponse(a, schema, current, context, bytes)) {
        .valid => |checked| checked,
        .invalid => return error.InvalidCalibrationSeed,
    };
    return session.appendBound(a, current, checked);
}

/// One exact current request's native candidate checks, without minting a
/// provider origin, execution delta, repair permission or successful workflow.
pub fn admitResponse(a: std.mem.Allocator, schema: *const schema_owner.Schema, current: session.Session, context: @import("../domain/specification_provenance.zig").Context, bytes: []const u8) !g.Validation {
    const packet = try session.packet(a, current, context);
    defer packets.release(packet);
    const restricted = try schema_owner.restrict(a, schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    var document = try @import("../domain/model_envelope.zig").parseContent(a, bytes, null);
    defer document.deinit();
    if (@import("../domain/model_payload_schema.zig").validateValue(@import("../domain/model_envelope.zig").value(&document.parsed.value), restricted.selected().root()) != null) return error.InvalidCalibrationPayload;
    // Production collection restores only engine-determined singleton fields
    // after selected-wire admission; provider bytes remain original evidence.
    const constructed = try codec.constructBound(a, document.content, packet.integerChoices());
    defer a.free(constructed);
    const parsed = try g.parse(a, constructed, try session.currentBinding(a, current, context));
    const checked = switch (try g.validate(a, text.validator, context, try session.unit(current.completed), parsed)) {
        .valid => |checked| try session.admit(a, current, context, checked),
        .invalid => |issue| return .{ .invalid = issue },
    };
    if (try session.checkConsistency(a, current, context, checked)) |issue| return .{ .invalid = issue };
    return .{ .valid = checked };
}

fn singletonConstructionChecks(a: std.mem.Allocator, schema: *const schema_owner.Schema, current: session.Session, context: @import("../domain/specification_provenance.zig").Context) !void {
    const occurrences = try @import("../domain/specification_provenance.zig").exactOccurrences(a, @import("../domain/reference_support.zig").records(context.references), null);
    if (occurrences.len != 1) return error.InvalidCalibrationSingleton;
    const prose = try std.fmt.allocPrint(a, "{s} MOCK The application starts successfully and displays its greeting and UTC date and time.", .{occurrences[0].bytes});
    const wire = try codec.encode(g.ModelResponse, a, .{ .primary_user_story = .{ .value = try business(a, prose), .signal_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } } } });
    const checked = switch (try admitResponse(a, schema, current, context, wire)) {
        .valid => |checked| checked,
        .invalid => return error.InvalidCalibrationSingleton,
    };
    try std.testing.expectEqual(@as(u32, 4), checked.response.content.primary_user_story.value.segments[0].exact_copy.claim_id.ordinal);
    const echoed = "{\"kind\":\"primary_user_story\",\"value\":{\"fragments\":[{\"kind\":\"exact_copy\",\"claim_id\":4}]},\"signal_ids\":[1,2]}";
    try std.testing.expectError(error.InvalidCalibrationPayload, admitResponse(a, schema, current, context, echoed));
}

fn optional(a: std.mem.Allocator, path: []const u8) !?[]const u8 {
    return shared.read(a, path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}

fn collect(a: std.mem.Allocator, directory: []const u8, schema: *const schema_owner.Schema, cases: []const Case, states: []const CaseState, trials: []const Trial, starts: []const session.Session, preparation: []const u8, parent: ParentPreparation) !void {
    const run_bytes = try optional(a, try std.fmt.allocPrint(a, "{s}/live-run.json", .{directory}));
    const run_manifest = if (run_bytes) |bytes| try @import("../domain/strict_json.zig").decode(Run, a, bytes, .{ .maximum_depth = 8 }) else null;
    if (run_manifest) |value| {
        if (!std.mem.eql(u8, value.preparation_sha256, try shared.sha256(a, preparation)) or !std.mem.eql(u8, value.parent.run, parent_identity.run) or !std.mem.eql(u8, value.parent.call, parent_identity.call)) return error.StaleCalibrationRun;
        if (parent != .ready) return error.MissingCalibrationParent;
    }
    var seen: std.ArrayList(ReplayOrigin) = .empty;
    const observations = try a.alloc(Observation, trials.len);
    for (trials, starts, observations) |trial, start, *observation| {
        const state = for (cases, states) |example, prepared| {
            if (std.mem.eql(u8, example.id, trial.case_id)) break prepared;
        } else return error.InvalidCalibrationCase;
        observation.* = consumeTrial(a, directory, schema, state, trial, start, run_manifest, &seen) catch |err| rejected: {
            if (err == error.OutOfMemory) return err;
            break :rejected .{ .trial_id = trial.id, .status = .rejected, .received = try receivedCount(a, directory, trial), .rejection = @errorName(err) };
        };
    }
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}/admission.json", .{directory}), .data = try std.json.Stringify.valueAlloc(a, .{ .status = if (run_manifest == null) "not_run" else "diagnostic_native_checks_only", .native_workflow_origin_available = false, .semantic_quality = "unscored", .run = run_manifest, .observations = observations }, .{}) });
}

fn admitReceipt(a: std.mem.Allocator, run_manifest: Run, trial_id: []const u8, request: Request, bytes: []const u8, seen: *std.ArrayList(ReplayOrigin)) !Receipt {
    const admitted = try @import("../domain/strict_json.zig").decode(Receipt, a, bytes, .{ .maximum_depth = 64 });
    const actual = admitted.result.request;
    const response = admitted.result.response;
    const origin = replayOrigin(admitted);
    if (!std.mem.eql(u8, admitted.trial_id, trial_id) or !std.mem.eql(u8, admitted.input, try shared.read(a, request.packet.path)) or !std.mem.eql(u8, admitted.request_sha256, request.request.sha256) or !std.mem.eql(u8, admitted.request_sha256, try shared.sha256(a, actual.body)) or !std.mem.eql(u8, admitted.response_sha256, try shared.sha256(a, response.body orelse "")) or !std.mem.eql(u8, response.id, actual.id) or !std.mem.eql(u8, actual.parent_run, run_manifest.parent.run) or !std.mem.eql(u8, actual.parent_call, run_manifest.parent.call)) return error.InvalidCalibrationOrigin;
    if (std.mem.trim(u8, origin.run, " \r\n\t").len == 0 or std.mem.trim(u8, origin.id, " \r\n\t").len == 0 or actual.mode != .modified or actual.sequence == 0) return error.InvalidCalibrationOrigin;
    try validateSettings(actual.description);
    for (seen.items) |prior| if (std.mem.eql(u8, prior.run, origin.run) and std.mem.eql(u8, prior.id, origin.id)) return error.DuplicateCalibrationOrigin;
    try seen.append(a, origin);
    return admitted;
}

fn validateSettings(description: @import("../domain/request_debugger.zig").Description) error{InvalidCalibrationSettings}!void {
    if (!std.mem.eql(u8, description.provider, "aws-bedrock") or !std.mem.eql(u8, description.model, "openai.gpt-oss-20b-1:0") or description.provider_config != .aws_bedrock or description.provider_config.aws_bedrock.region != .@"ap-southeast-2" or !@import("../domain/request_debugger.zig").sameOptional(description.reasoning_effort, "low") or description.response_mode != .native_schema or description.operation_kind != .inference or description.controls.temperature != .fixed) return error.InvalidCalibrationSettings;
}

fn consumeTrial(a: std.mem.Allocator, directory: []const u8, schema: *const schema_owner.Schema, state: CaseState, trial: Trial, start: session.Session, run_manifest: ?Run, seen: *std.ArrayList(ReplayOrigin)) !Observation {
    var result: Observation = .{ .trial_id = trial.id, .status = if (run_manifest == null) .not_run else .incomplete };
    const receipts = try a.alloc(Receipt, trial.requests.len);
    var facts: std.ArrayList(ResponseFacts) = .empty;
    var costs: std.ArrayList(Cost) = .empty;
    var origins: std.ArrayList(ReplayOrigin) = .empty;
    var missing = false;
    for (trial.requests, receipts) |request, *receipt| {
        const member = if (request.group_id) |group| try std.fmt.allocPrint(a, "records-{d}", .{group}) else request.unit;
        // All input paths come from the closed prepared schedule, never a model.
        const bytes = (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.receipt.json", .{ directory, trial.id, member }))) orelse {
            missing = true;
            continue;
        };
        if (run_manifest == null) return error.MissingCalibrationRun;
        receipt.* = try admitReceipt(a, run_manifest.?, trial.id, request, bytes, seen);
        const origin = replayOrigin(receipt.*);
        try origins.append(a, origin);
        const fact = try responseFacts(a, receipt.*);
        try facts.append(a, fact);
        try costs.append(a, fact.cost);
        result.received += 1;
    }
    result.origins = origins.items;
    result.costs = costs.items;
    result.costs_complete = !missing and costs.items.len == trial.requests.len;
    for (costs.items) |cost| if (cost.usage == null) {
        result.costs_complete = false;
    };
    if (missing) return result;
    var current = start;
    var native: std.ArrayList(g.CanonicalResponse) = .empty;
    for (trial.requests, receipts, facts.items) |request, receipt, fact| {
        const packet = try session.packet(a, current, state.context);
        defer packets.release(packet);
        if (!std.mem.eql(u8, packet.body(), receipt.input)) return .{ .trial_id = trial.id, .status = .rejected, .received = result.received, .costs_complete = result.costs_complete, .rejection = "StaleCalibrationAssignment", .origins = origins.items, .costs = costs.items, .responses = native.items };
        if (fact.rejection) |rejection| return .{ .trial_id = trial.id, .status = .rejected, .received = result.received, .costs_complete = result.costs_complete, .rejection = rejection, .origins = origins.items, .costs = costs.items, .responses = native.items };
        const admitted = admitResponse(a, schema, current, state.context, fact.answer.?) catch |err| {
            if (err == error.OutOfMemory) return err;
            return .{ .trial_id = trial.id, .status = .rejected, .received = result.received, .costs_complete = result.costs_complete, .rejection = @errorName(err), .origins = origins.items, .costs = costs.items, .responses = native.items };
        };
        const checked = switch (admitted) {
            .valid => |checked| checked,
            .invalid => |issue| return .{ .trial_id = trial.id, .status = .rejected, .received = result.received, .costs_complete = result.costs_complete, .issue = issue, .origins = origins.items, .costs = costs.items, .responses = native.items },
        };
        try native.append(a, checked.response);
        if (checked.response == .clarification) {
            if (trial.requests.len != 1) return .{ .trial_id = trial.id, .status = .admitted_clarification, .received = result.received, .costs_complete = result.costs_complete, .origins = origins.items, .costs = costs.items, .responses = native.items };
            result.status = .admitted_clarification;
            break;
        }
        if (request.group_id != null) current = try session.appendBound(a, current, checked) else {
            var projected = state.seed;
            projected.units[start.completed] = checked;
            current = projected;
        }
        result.status = .admitted_content;
    }
    result.origins = origins.items;
    result.costs = costs.items;
    result.responses = native.items;
    if (result.status == .admitted_content) result.review_packets = reviewPackets(a, state.context, current, trial.requests[0].unit) catch |err| {
        if (err == error.OutOfMemory) return err;
        result.projection_error = @errorName(err);
        return result;
    };
    return result;
}

const ResponseFacts = struct { cost: Cost, answer: ?[]const u8 = null, rejection: ?[]const u8 = null };
fn responseFacts(a: std.mem.Allocator, receipt: Receipt) !ResponseFacts {
    var result: ResponseFacts = .{ .cost = .{ .origin = replayOrigin(receipt), .replay_elapsed_ns = receipt.replay_elapsed_ns } };
    const response = receipt.result.response;
    if (response.outcome != .received or response.status != 200 or response.body == null or response.encoding != .utf8 or response.redacted) {
        result.rejection = "ProviderResponseUnavailable";
        return result;
    }
    var raw = @import("../domain/strict_json.zig").parse(a, response.body.?, .{ .maximum_depth = std.math.maxInt(usize) }, false, null) catch |err| {
        if (err == error.OutOfMemory) return err;
        result.rejection = "InvalidProviderResponse";
        return result;
    };
    defer raw.deinit();
    var decoded = @import("../adapters/provider/bedrock_response.zig").decodeConverse(a, raw.value, null) catch |err| {
        if (err == error.OutOfMemory) return err;
        result.rejection = "InvalidProviderResponse";
        return result;
    };
    defer decoded.deinit(a);
    result.cost.usage = decoded.usage;
    if (decoded.output != .text) {
        result.cost.provider_stop = switch (decoded.output) {
            .text => unreachable,
            inline else => |reason| @tagName(reason),
        };
        result.rejection = "ProviderNonCandidateResponse";
    } else result.answer = try a.dupe(u8, decoded.output.text);
    return result;
}

fn replayOrigin(receipt: Receipt) ReplayOrigin {
    const actual = receipt.result.request;
    return .{ .parent = .{ .run = actual.parent_run, .call = actual.parent_call }, .run = actual.run, .id = actual.id };
}
fn receivedCount(a: std.mem.Allocator, directory: []const u8, trial: Trial) !usize {
    var count: usize = 0;
    for (trial.requests) |request| {
        const member = if (request.group_id) |group| try std.fmt.allocPrint(a, "records-{d}", .{group}) else request.unit;
        if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.receipt.json", .{ directory, trial.id, member })) != null) count += 1;
    }
    return count;
}

fn reviewPackets(a: std.mem.Allocator, context: @import("../domain/specification_provenance.zig").Context, current: session.Session, unit_name: []const u8) ![]const []const u8 {
    const candidate = try session.assemble(a, text.validator, context, current);
    const inputs = try @import("../domain/specification_authority.zig").project(a, current.feature, context.references, candidate.content, current.units[0].?.response.content.brief);
    var projections: std.ArrayList([]const u8) = .empty;
    for (inputs.seeds) |seed| {
        const selected = if (std.mem.eql(u8, unit_name, "brief")) seed.id.kind == .feature_intent and seed.id.unit == .feature and (seed.id.slot == .display_name or seed.id.slot == .description or seed.id.slot == .primary_goal) else if (std.mem.eql(u8, unit_name, "primary_user_story")) seed.id.kind == .feature_intent and seed.id.unit == .feature and seed.id.slot == .primary_user_story else if (std.mem.eql(u8, unit_name, "entities")) seed.id.kind == .entity_applicability or (seed.id.unit == .record and seed.id.unit.record.kind == .entity) else (seed.id.unit == .record and seed.id.unit.record.kind != .entity) or (seed.id.kind == .feature_intent and seed.id.unit == .feature and @import("../domain/specification_authority.zig").collectionFamily(seed.id.slot) != null);
        if (!selected) continue;
        const packet = try @import("../domain/specification_support.zig").Source.packetFor(a, inputs, context, .{ .finding = seed.id });
        defer packets.release(packet);
        try projections.append(a, try a.dupe(u8, packet.body()));
    }
    return projections.items;
}
fn exportRequest(a: std.mem.Allocator, schema: *const schema_owner.Schema, id: []const u8, current: session.Session, context: @import("../domain/specification_provenance.zig").Context) !Request {
    return exportRequestAt(a, output, schema, id, current, context, try shared.read(a, "design/workflows/spec/generation.context.json"));
}
fn exportRequestAt(a: std.mem.Allocator, directory: []const u8, schema: *const schema_owner.Schema, id: []const u8, current: session.Session, context: @import("../domain/specification_provenance.zig").Context, guidance: []const u8) !Request {
    const packet = try session.packet(a, current, context);
    defer packets.release(packet);
    const selected = try session.unit(current.completed);
    const group: ?u32 = if (selected == .records) (try session.currentBinding(a, current, context)).records.signal.ordinal else null;
    const name = if (group) |ordinal| try std.fmt.allocPrint(a, "records-{d}", .{ordinal}) else @tagName(selected);
    const prompt = try shared.read(a, switch (selected) {
        .brief => "design/workflows/spec/generation.prompt.md",
        .primary_user_story => "design/workflows/spec/story.prompt.md",
        .entities => "design/workflows/spec/entities.prompt.md",
        .records => "design/workflows/spec/records.prompt.md",
    });
    const body = packet.body();
    const rendered = try shared.renderContent(a, schema, packet, &.{ .{ .guidance = guidance }, .{ .guidance = prompt }, .{ .user = body } });
    try shared.writeAt(a, directory, id, try std.fmt.allocPrint(a, "{s}.packet.json", .{name}), body);
    try shared.writeAt(a, directory, id, try std.fmt.allocPrint(a, "{s}.edit.json", .{name}), rendered.edit);
    try shared.writeAt(a, directory, id, try std.fmt.allocPrint(a, "{s}.request.json", .{name}), rendered.request);
    return .{ .unit = @tagName(selected), .group_id = group, .packet = try pin(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.packet.json", .{ directory, id, name })), .edit = try pin(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.edit.json", .{ directory, id, name })), .request = try pin(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.request.json", .{ directory, id, name })) };
}

fn receiptChecks(a: std.mem.Allocator, request: Request, answer: []const u8) !void {
    const edit = try @import("../domain/strict_json.zig").decode(@import("../domain/request_debugger.zig").Edit, a, try shared.read(a, request.edit.path), .{ .maximum_depth = 64 });
    const run_manifest: Run = .{ .schema = .@"authoring-diagnostic-run/v1", .preparation_sha256 = "MOCK preparation hash", .parent = .{ .run = "MOCK-parent", .call = "MOCK-call" } };
    const raw = try std.json.Stringify.valueAlloc(a, .{ .output = .{ .message = .{ .role = "assistant", .content = &.{.{ .text = answer }} } }, .stopReason = "end_turn", .usage = .{ .inputTokens = 11, .outputTokens = 7, .totalTokens = 18 } }, .{});
    const good: Receipt = .{
        .schema = .@"authoring-diagnostic-receipt/v1",
        .trial_id = "MOCK-trial",
        .input = try shared.read(a, request.packet.path),
        .request_sha256 = request.request.sha256,
        .response_sha256 = try shared.sha256(a, raw),
        .replay_elapsed_ns = null,
        .result = .{ .request = .{ .id = "MOCK-replay", .run = "MOCK-run", .sequence = 1, .parent_run = run_manifest.parent.run, .parent_call = run_manifest.parent.call, .original_run = run_manifest.parent.run, .original_call = run_manifest.parent.call, .node = "MOCK-node", .mode = .modified, .body = try shared.read(a, request.request.path), .description = .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0", .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16000 }, .request_timeout = .{ .milliseconds = 180000 } } }, .model_slot = "MOCK-slot", .workflow_id = "MOCK-workflow", .workflow_version = 1, .request_step = "MOCK-step", .content = edit.content, .protocol_prompt = @import("../domain/model_controls.zig").response_format_guidance, .schema = edit.schema, .response_mode = .native_schema, .controls = .{ .temperature = .fixed }, .reasoning_effort = "low", .operation_kind = .inference } }, .response = .{ .id = "MOCK-replay", .outcome = .received, .status = 200, .body = raw } },
    };
    var seen: std.ArrayList(ReplayOrigin) = .empty;
    const accepted = try admitReceipt(a, run_manifest, good.trial_id, request, try std.json.Stringify.valueAlloc(a, good, .{}), &seen);
    const facts = try responseFacts(a, accepted);
    try std.testing.expectEqualStrings(answer, facts.answer.?);
    try std.testing.expectEqual(@as(u64, 18), facts.cost.usage.?.total_tokens);
    try std.testing.expectError(error.DuplicateCalibrationOrigin, admitReceipt(a, run_manifest, good.trial_id, request, try std.json.Stringify.valueAlloc(a, good, .{}), &seen));
    for (0..5) |fault| {
        var rejected = good;
        switch (fault) {
            0 => rejected.input = "MOCK foreign packet",
            1 => rejected.request_sha256 = "MOCK wrong request hash",
            2 => rejected.response_sha256 = "MOCK wrong response hash",
            3 => rejected.result.request.parent_call = "MOCK foreign parent",
            4 => rejected.trial_id = "MOCK foreign trial",
            else => unreachable,
        }
        var fresh: std.ArrayList(ReplayOrigin) = .empty;
        try std.testing.expectError(error.InvalidCalibrationOrigin, admitReceipt(a, run_manifest, good.trial_id, request, try std.json.Stringify.valueAlloc(a, rejected, .{}), &fresh));
    }
    var changed_settings = good;
    changed_settings.result.request.description.reasoning_effort = "high";
    var fresh: std.ArrayList(ReplayOrigin) = .empty;
    try std.testing.expectError(error.InvalidCalibrationSettings, admitReceipt(a, run_manifest, good.trial_id, request, try std.json.Stringify.valueAlloc(a, changed_settings, .{}), &fresh));
    var unknown = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.json.Stringify.valueAlloc(a, good, .{}), .{});
    try unknown.object.put(a, "approved", .{ .bool = true });
    try std.testing.expectError(error.InvalidJsonDocument, admitReceipt(a, run_manifest, good.trial_id, request, try std.json.Stringify.valueAlloc(a, unknown, .{}), &fresh));
}

fn pin(a: std.mem.Allocator, path: []const u8) !File {
    const bytes = try shared.read(a, path);
    return .{ .path = path, .sha256 = try shared.sha256(a, bytes), .bytes = bytes.len };
}
