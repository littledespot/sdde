//! Frozen, offline-only source-review presentation comparison. All subjects,
//! schemas and provider bytes come from existing native owners. No dispatch,
//! semantic judge, receipt authority or production fallback lives here.
const std = @import("std");
const temperature_policy = @import("calibration_temperature_policy.zig");
const shared = @import("source_loss_calibration.zig");
const authority = @import("../domain/required_authority.zig");
const spec = @import("../domain/specification.zig");
const provenance = @import("../domain/specification_provenance.zig");
const support = @import("../domain/specification_support.zig").Source;
const evidence = @import("../domain/specification_support_evidence.zig");
const model = @import("../domain/specification_support_model.zig");
const codec = @import("../domain/model_candidate_json.zig");
const packets = @import("../domain/model_input_packet.zig");
const reference = @import("../domain/reference_reconciliation.zig");
const root = "test/calibration/source-review-scope";
const output = ".zig-cache/source-review-scope";
const Arm = enum { baseline, candidate };
const Record = struct {
    kind: enum { acceptance_criterion, functional_requirement, edge_case, user_visible_outcome },
    text: ?[]const u8 = null,
    given: ?[]const u8 = null,
    when: ?[]const u8 = null,
    then: ?[]const u8 = null,
    condition: ?[]const u8 = null,
    expected_outcome: ?[]const u8 = null,
    source_ids: ?[]const u32 = null,
};
const Target = struct {
    unit: enum { feature, record, source },
    slot: authority.Slot,
    record_kind: ?spec.Kind = null,
    ordinal: u32 = 1,
};
const Case = struct {
    id: []const u8,
    card: []const u8,
    cohort: enum { development, reserved_qualification },
    retained_case: ?[]const u8 = null,
    sources: []const []const u8 = &.{},
    claims: @FieldType(shared.Case, "claims") = &.{},
    description: ?[]const u8 = null,
    description_sources: ?[]const u32 = null,
    title: ?[]const u8 = null,
    goal: ?[]const u8 = null,
    story: ?[]const u8 = null,
    records: ?[]const Record = null,
    target: Target,
    expected: struct {
        finding: enum { supported, candidate_omission },
        meaning: []const u8,
        missing_obligation: ?[]const u8 = null,
        preserve: []const []const u8,
        forbidden: []const []const u8,
    },
};
const File = struct { path: []const u8, sha256: []const u8, bytes: usize };
const Trial = struct {
    id: []const u8,
    case_id: []const u8,
    card: []const u8,
    cohort: @FieldType(Case, "cohort"),
    arm: Arm,
    repetition: u32,
    packet: File,
    edit: File,
    request: File,
};

pub fn run() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = try @import("../domain/strict_json.zig").decode([]const Case, a, try shared.read(a, root ++ "/cases.json"), .{ .maximum_depth = 128 });
    const retained = try codec.decode([]const shared.Case, a, try shared.read(a, "test/calibration/source-loss-attribution/bound-preservation/obligation/cases.associated.json"));
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try shared.read(a, "design/workflows/spec/support.schema.json"));
    const prompts = [2][]const u8{ try shared.read(a, root ++ "/baseline.prompt.md"), try shared.read(a, "design/workflows/spec/support.prompt.md") };
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    var trials: std.ArrayList(Trial) = .empty;
    var development: usize = 0;
    var qualification: usize = 0;
    var prepared_development: usize = 0;
    var prepared_qualification: usize = 0;
    var admission_rejections: std.ArrayList(shared.AdmissionRejection) = .empty;
    var unavailable: std.ArrayList(shared.Unavailable) = .empty;
    for (cases, 0..) |example, index| {
        for (cases[0..index]) |prior| try std.testing.expect(!std.mem.eql(u8, prior.id, example.id));
        if (example.cohort == .development) development += 1 else qualification += 1;
        const prepared = prepare(a, example, retained) catch |err| {
            if (err == error.MissingCalibrationCandidate) {
                const missing: shared.Unavailable = .{ .case_id = example.id };
                try unavailable.append(a, missing);
                try shared.writeUnavailable(a, output, missing);
                continue;
            }
            const rejection: shared.AdmissionRejection = .{ .case_id = example.id, .reason = shared.admissionReason(err) orelse return err };
            try admission_rejections.append(a, rejection);
            try shared.writeAdmissionRejection(a, output, rejection);
            continue;
        };
        defer prepared.passive.deinit();
        try shared.writeExactScope(a, output, example.id, prepared);
        if (example.cohort == .development) prepared_development += 1 else prepared_qualification += 1;
        const target = try targetId(example.target);
        const ledger = try authority.build(a, prepared.inputs);
        const ordinal = for (ledger.requirements, 1..) |required, number| {
            if (std.meta.eql(required.seed.id, target)) break number;
        } else return error.MissingCalibrationTarget;
        const unit = try @import("../domain/specification_review_subject.zig").assignmentUnit(a, prepared.inputs, target);
        const first = for (ledger.requirements) |required| {
            if (std.meta.eql(unit, try @import("../domain/specification_review_subject.zig").assignmentUnit(a, prepared.inputs, required.seed.id))) break required.seed.id;
        } else return error.MissingCalibrationTarget;
        const packet = try support.packetFor(a, prepared.inputs, prepared.context, support.assignmentScope(prepared.inputs, first));
        defer packets.release(packet);
        const baseline = try shared.baselineReviewBody(a, packet);
        // Remove the selected presentation field and prove that no subject,
        // task, derived evidence, source occurrence or native restriction moved.
        const current = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
        var without_scope = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
        var removed = without_scope.object.orderedRemove("assessment_scope");
        for (without_scope.object.getPtr("requirements").?.array.items) |*member| {
            removed = member.object.orderedRemove("assessment_scope") or removed;
        }
        try std.testing.expect(removed);
        try std.testing.expectEqualStrings(baseline, try std.json.Stringify.valueAlloc(a, without_scope, .{}));
        const assignment = current.object.get("requirements").?.array.items;
        const members = if (authority.assessmentPolicy(prepared.inputs.projection) == .advisory)
            try support.assignmentSubjects(a, prepared.inputs, first)
        else
            try a.dupe(authority.Id, &.{target});
        try std.testing.expectEqual(members.len, assignment.len);
        var target_found = false;
        for (members, assignment) |id, member| {
            const number = for (ledger.requirements, 1..) |required, index_of| {
                if (std.meta.eql(required.seed.id, id)) break index_of;
            } else return error.MissingCalibrationTarget;
            try std.testing.expectEqual(@as(i64, @intCast(number)), member.object.get("ordinal").?.integer);
            try std.testing.expectEqualStrings(try @import("../domain/required_authority_description.zig").task(a, id), member.object.get("task").?.string);
            if (number == ordinal) target_found = true;
        }
        try std.testing.expect(target_found);
        try shared.writeAt(a, output, example.id, "packet.json", try std.json.Stringify.valueAlloc(a, .{ .target = target, .input = current }, .{}));
        const packet_file = try pin(a, example.id, "packet.json");
        for (std.enums.values(Arm), 0..) |arm, arm_index| {
            try shared.exportBodyAt(a, output, schema, example.id, @tagName(arm), packet, if (arm == .baseline) baseline else packet.body(), prompts[arm_index]);
            const edit = try pin(a, example.id, try std.fmt.allocPrint(a, "{s}.edit.json", .{@tagName(arm)}));
            const request = try pin(a, example.id, try std.fmt.allocPrint(a, "{s}.request.json", .{@tagName(arm)}));
            for (1..3) |repetition| try trials.append(a, .{ .id = try std.fmt.allocPrint(a, "{s}-{s}-review-{d}", .{ example.id, @tagName(arm), repetition }), .case_id = example.id, .card = example.card, .cohort = example.cohort, .arm = arm, .repetition = @intCast(repetition), .packet = packet_file, .edit = edit, .request = request });
        }
        try mechanicalProbe(a, example, prepared, target);
    }
    try std.testing.expectEqual(@as(usize, 15), development);
    try std.testing.expectEqual(@as(usize, 9), qualification);
    try std.testing.expectEqual(@as(usize, 0), admission_rejections.items.len);
    try std.testing.expectEqualDeep(@as([]const shared.Unavailable, &.{
        .{ .case_id = "d4-inherited-recording-field" },
        .{ .case_id = "d6-derived-title" },
        .{ .case_id = "d6-derived-goal" },
    }), unavailable.items);
    try std.testing.expectEqual(@as(usize, 12), prepared_development);
    try std.testing.expectEqual(@as(usize, 9), prepared_qualification);
    try std.testing.expectEqual(@as(usize, 84), trials.items.len);
    try taxonomyProbes(a);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = output ++ "/preparation.json", .data = try std.json.Stringify.valueAlloc(a, .{
        .status = "offline_prepared_no_live_dispatch_authority",
        .factor = "Source-review scope presentation: current production per-member assessment_scope and its referring prompt; baseline omits only those fields and uses the pinned prior prompt. Partial historical candidates without complete native context remain unavailable.",
        .settings = .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0", .region = "ap-southeast-2", .reasoning_effort = "low", .temperature = temperature_policy.temperature, .response_mode = "native_schema", .max_output_tokens = 16384, .seed = "absent", .top_p = "absent" },
        .limits = .{ .repetitions_per_arm = 2, .development_assignments = development, .reserved_qualification_assignments = qualification, .maximum_physical_sends = trials.items.len, .stop_at_actual_input_plus_output_tokens = 600000, .retries_corrections_repairs_loss_calls_model_judges_e2e = 0 },
        .native_admission = .{ .input_cases = cases.len, .prepared_development = prepared_development, .prepared_qualification = prepared_qualification, .pre_review_rejections = admission_rejections.items, .unavailable_cases = unavailable.items },
        .cases = try filePin(a, root ++ "/cases.json"),
        .baseline_prompt = try filePin(a, root ++ "/baseline.prompt.md"),
        .candidate_prompt = try filePin(a, "design/workflows/spec/support.prompt.md"),
        .schema = try filePin(a, "design/workflows/spec/support.schema.json"),
        .scoring = try filePin(a, root ++ "/scorecard.template.json"),
        .taxonomy = try filePin(a, root ++ "/taxonomy.probes.json"),
        .parent = try filePin(a, "test/calibration/source-loss-attribution/bound-preservation/citation-completeness/handoff.parent.json"),
        .trials = trials.items,
    }, .{}) });
}

fn prepare(a: std.mem.Allocator, example: Case, retained: []const shared.Case) !shared.PreparedContext {
    var base: shared.Case = if (example.retained_case) |id| found: {
        for (retained) |value| if (std.mem.eql(u8, value.id, id)) break :found value;
        return error.MissingCalibrationSource;
    } else .{ .id = example.id, .cohort = .development, .sources = example.sources, .claims = example.claims, .description = example.description orelse return error.MissingCalibrationSource, .missing = "MOCK unused loss premise", .missing_obligation = "MOCK unused loss premise", .mode = .candidate, .grouping = .combined, .source_group_ids = &.{1}, .verdicts = &.{}, .expected = "unlocalized" };
    if (example.description) |value| base.description = value;
    const source_scoped = example.description_sources != null or if (example.records) |records| for (records) |record| {
        if (record.source_ids != null) break true;
    } else false else false;
    // Test data declares this topology: either one complete composite group or
    // one group per supplied source. Explicit source choices identify those
    // occurrences; production never infers group support from source membership.
    base.grouping = if (source_scoped) .per_source else .combined;
    base.source_group_ids = if (source_scoped) groups: {
        const ids = try a.alloc(u32, base.sources.len);
        for (ids, 1..) |*id, ordinal| id.* = @intCast(ordinal);
        break :groups ids;
    } else &.{1};
    var prepared = try shared.prepareContext(a, base);
    errdefer prepared.passive.deinit();
    if (example.target.unit == .source) {
        prepared.inputs = try @import("../domain/source_preservation.zig").project(a, prepared.context.inputs.corpus.feature_id, @import("../domain/reference_support.zig").records(prepared.context.references), prepared.context.inputs);
        return prepared;
    }
    var brief = prepared.brief;
    if (example.title) |value| brief.title = try attributed(a, prepared.context, value, base.source_group_ids);
    if (example.goal) |value| brief.primary_goal = try attributed(a, prepared.context, value, base.source_group_ids);
    if (example.description_sources) |sources| brief.description = try attributed(a, prepared.context, base.description, sources);
    var candidate: ?spec.IdentifiedContent = prepared.inputs.specification;
    if (example.records) |records| {
        const identified = try a.alloc(spec.IdentifiedRecord, records.len);
        var counters: std.EnumArray(spec.Kind, u32) = .initFill(0);
        for (records, identified) |record, *identified_record| {
            const kind: spec.Kind = switch (record.kind) {
                inline else => |tag| @field(spec.Kind, @tagName(tag)),
            };
            const number = counters.get(kind) + 1;
            counters.set(kind, number);
            const association = try attributed(a, prepared.context, "MOCK provenance selection", record.source_ids orelse base.source_group_ids);
            if (association.source_group_ids.len != 1) return error.InvalidCalibrationRecord;
            identified_record.* = .{ .id = .{ .kind = kind, .ordinal = number }, .proposal = .{ .content = switch (record.kind) {
                .acceptance_criterion => .{ .acceptance_criterion = .{ .given = try business(a, record.given orelse return error.InvalidCalibrationRecord), .when = try business(a, record.when orelse return error.InvalidCalibrationRecord), .then = try business(a, record.then orelse return error.InvalidCalibrationRecord) } },
                .functional_requirement => .{ .functional_requirement = .{ .text = try business(a, record.text orelse return error.InvalidCalibrationRecord) } },
                .edge_case => .{ .edge_case = .{ .condition = try business(a, record.condition orelse return error.InvalidCalibrationRecord), .expected_outcome = try business(a, record.expected_outcome orelse return error.InvalidCalibrationRecord) } },
                .user_visible_outcome => .{ .user_visible_outcome = .{ .text = try business(a, record.text orelse return error.InvalidCalibrationRecord) } },
            }, .source_group_ids = association.source_group_ids, .provenance = association.provenance } };
        }
        candidate = .{ .display_name = brief.title, .primary_user_story = try attributed(a, prepared.context, example.story orelse base.description, base.source_group_ids), .records = identified, .entities = .{ .disposition = .not_applicable, .basis = try attributed(a, prepared.context, "No separate business entity records are supplied in this diagnostic candidate.", base.source_group_ids) } };
    }
    brief = try shared.admitBrief(a, prepared.context, brief);
    if (candidate) |value| {
        candidate = try shared.admitContent(a, prepared.context, value);
        try provenance.validateStored(a, prepared.context.inputs, .{ .records = prepared.context.registry.records, .occurrences = prepared.context.registry.occurrences }, @import("../domain/reference_support.zig").records(prepared.context.references), brief, candidate.?);
    }
    if (candidate == null) return error.MissingCalibrationCandidate;
    prepared.inputs = try @import("../domain/specification_authority.zig").project(a, prepared.context.inputs.corpus.feature_id, prepared.context.references, candidate, brief);
    return prepared;
}

fn business(a: std.mem.Allocator, value: []const u8) !spec.BusinessValue {
    return .{ .segments = try a.dupe(@import("../domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = value } }}) };
}
fn attributed(a: std.mem.Allocator, context: provenance.Context, value: []const u8, selected_groups: []const u32) !spec.AttributedValue {
    const ids = try a.alloc(reference.SignalId, selected_groups.len);
    for (selected_groups, ids) |id, *group| group.* = .{ .ordinal = id };
    const association = try @import("../domain/specification_source_binding.zig").resolveGroups(a, @import("../domain/reference_support.zig").records(context.references), context.inputs, ids, .content);
    return .{ .value = try business(a, value), .source_group_ids = association.source_group_ids, .provenance = try provenance.select(a, context, association.selection) };
}
fn targetId(target: Target) !authority.Id {
    if (target.ordinal == 0) return error.MissingCalibrationTarget;
    return .{ .kind = if (target.unit == .source) .reference_meaning else .feature_intent, .unit = switch (target.unit) {
        .feature => .{ .feature = .singleton },
        .record => .{ .record = .{ .kind = target.record_kind orelse return error.MissingCalibrationTarget, .ordinal = target.ordinal } },
        .source => .{ .source = .{ .ordinal = target.ordinal } },
    }, .slot = target.slot };
}
fn mechanicalProbe(a: std.mem.Allocator, example: Case, prepared: shared.PreparedContext, target: authority.Id) !void {
    const required = try evidence.requirements(a, prepared.inputs, prepared.context.inputs, target);
    const sources = required.eligible_source_ids;
    const bytes = try codec.encode(model.Value, a, switch (example.expected.finding) {
        .supported => .{ .supported = .{ .source_ids = sources, .detail = "MOCK mechanically admissible source-review finding; no semantic proof." } },
        .candidate_omission => .{ .candidate_omission = .{ .source_ids = sources, .detail = "MOCK mechanically admissible omission; expectation remains scoring data.", .missing_obligation = example.expected.missing_obligation orelse return error.MissingCalibrationExpectation } },
    });
    const value = try model.decode(a, bytes, required);
    const admitted = try evidence.admit(a, prepared.inputs, prepared.context.inputs, target, value.kind.finding(), value.provenance, value.source_ids, value.detail, value.missing_obligation, value.loss, value.preservation, value.authority_gap);
    try std.testing.expect(admitted == .accepted);
    try shared.writeAt(a, output, example.id, "mechanical-probe.json", try std.json.Stringify.valueAlloc(a, .{ .mock = true, .semantic_evidence = false, .admitted = true, .finding = value.kind }, .{}));
}
fn taxonomyProbes(a: std.mem.Allocator) !void {
    const strict = @import("../domain/strict_json.zig");
    _ = try strict.decode(std.json.Value, a, try shared.read(a, root ++ "/taxonomy.probes.json"), .{ .maximum_depth = 32 });
    try std.testing.expectError(error.InvalidJsonDocument, codec.decode(model.Value, a, "{\"kind\":\"candidate_addition\",\"source_ids\":[],\"detail\":\"MOCK unsupported addition\"}"));
    try std.testing.expectError(error.InvalidJsonDocument, codec.decode(model.Value, a, "{\"kind\":\"candidate_contradiction\",\"source_ids\":[],\"detail\":\"MOCK candidate contradicts a retained restriction\"}"));
    try std.testing.expectError(error.InvalidJsonDocument, codec.decode(model.Value, a, "{\"kind\":\"unsupported\",\"source_ids\":[],\"detail\":\"MOCK addition is not a source gap\"}"));
    try std.testing.expectError(error.InvalidJsonDocument, codec.decode(model.Value, a, "{\"kind\":\"inconclusive\",\"source_ids\":[],\"detail\":\"MOCK unresolved entailment\",\"question\":\"MOCK invented choice\"}"));
    try std.testing.expect(!evidence.validObligation(.candidate_omission, null));
    try std.testing.expect(!evidence.validObligation(.candidate_omission, " "));
    try std.testing.expect(evidence.validObligation(.unsupported, null));
    try std.testing.expect(evidence.validObligation(.inconclusive, null));
    _ = try codec.decode(model.Value, a, "{\"kind\":\"conflicting\",\"source_ids\":[1,2],\"detail\":\"MOCK genuinely incompatible original instructions\",\"question\":\"MOCK Which original instruction governs?\"}");
    _ = try codec.decode(model.Value, a, "{\"kind\":\"unsupported\",\"source_ids\":[1],\"detail\":\"MOCK release policy absent from original sources\",\"question\":\"MOCK What event permits release?\"}");
    _ = try codec.decode(model.Value, a, "{\"kind\":\"inconclusive\",\"source_ids\":[1],\"detail\":\"MOCK interpretation unresolved without an identifiable missing user choice\"}");
}
fn filePin(a: std.mem.Allocator, path: []const u8) !File {
    const bytes = try shared.read(a, path);
    return .{ .path = path, .sha256 = try shared.sha256(a, bytes), .bytes = bytes.len };
}
fn pin(a: std.mem.Allocator, id: []const u8, suffix: []const u8) !File {
    const path = try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, id, suffix });
    return filePin(a, path);
}
