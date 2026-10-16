//! Offline qualification preparation for actual Source-review values passed to
//! one complete native preservation assignment. No dispatch or semantic oracle.
const std = @import("std");
const temperature_policy = @import("calibration_temperature_policy.zig");
const shared = @import("source_loss_calibration.zig");
const authority = @import("../domain/required_authority.zig");
const support = @import("../domain/specification_support.zig").Source;
const evidence = @import("../domain/specification_support_evidence.zig");
const model = @import("../domain/specification_support_model.zig");
const codec = @import("../domain/model_candidate_json.zig");
const packets = @import("../domain/model_input_packet.zig");
const comparison = @import("../domain/source_omission_comparison.zig");
const envelope = @import("../domain/model_envelope.zig");
const root = "test/calibration/source-review-handoff";
const output = ".zig-cache/source-review-handoff";

const Case = struct {
    id: []const u8,
    cohort: enum { development, reserved_qualification },
    retained_case: ?[]const u8,
    fixture: ?shared.Case,
    target_slot: ?authority.Slot,
    expectation: struct {
        discovery: enum { candidate_omission, supported, unsupported, inconclusive },
        meaning: []const u8,
        attribution: []const u8,
        preserve: []const []const u8,
        forbidden: []const []const u8,
    },
};
const File = struct { path: []const u8, sha256: []const u8, bytes: usize };
const Trial = struct {
    id: []const u8,
    case_id: []const u8,
    cohort: @FieldType(Case, "cohort"),
    repetition: u32,
    review_packet: File,
    review_edit: File,
    review_request: File,
    loss_request: enum { derive_after_exact_receipt_admission },
};

/// The diagnostic receipt remains diagnostic. Pasted/replayed bytes do not mint
/// a provider-operation origin or a native repair/publication capability.
pub const Admitted = struct {
    receipt: shared.ReviewReceipt,
    collection: support.Collection,
    normalization: envelope.Normalization,
};
pub const Derived = struct {
    candidate: support.Candidate,
    assignment: comparison.Assignment,
    packet: *packets.Packet,
};

pub fn admit(a: std.mem.Allocator, id: []const u8, repetition: usize, prepared: shared.PreparedContext, prior: ?support.Collection, packet: *const packets.Packet, parent: shared.ReviewParent, request_hash: []const u8, bytes: []const u8) !Admitted {
    const receipt = try shared.admitReviewReceipt(a, id, repetition, packet, parent, request_hash, bytes);
    var document = try envelope.parseContent(a, receipt.response_bytes, null);
    defer document.deinit();
    return .{ .receipt = receipt, .collection = try support.collectFocused(a, prepared.inputs, prepared.context, prior, packet, document.content, null), .normalization = document.normalization };
}

/// Only the native admitted omission can produce a loss request. Expected panel
/// labels and obligations are deliberately absent from this interface.
pub fn derive(a: std.mem.Allocator, prepared: shared.PreparedContext, admitted: Admitted) !?Derived {
    const candidate = candidateOf(admitted.collection) orelse return null;
    if (admitted.collection == .rejected or candidate.pending_localization == null) return null;
    const assignment = try support.comparisonAssignment(a, prepared.inputs, prepared.context, candidate);
    const packet = try support.packetForLoss(a, prepared.inputs, prepared.context, candidate);
    return .{ .candidate = candidate, .assignment = assignment, .packet = packet };
}

pub fn run() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = try @import("../domain/strict_json.zig").decode([]const Case, a, try shared.read(a, root ++ "/cases.associated.json"), .{ .maximum_depth = 128 });
    const retained = try codec.decode([]const shared.Case, a, try shared.read(a, "test/calibration/source-loss-attribution/bound-preservation/obligation/cases.associated.json"));
    const parent = try @import("../domain/strict_json.zig").decode(shared.ReviewParent, a, try shared.read(a, root ++ "/handoff.parent.json"), .{ .maximum_depth = 8 });
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try shared.read(a, "design/workflows/spec/support.schema.json"));
    const review_prompt = try shared.read(a, "design/workflows/spec/support.prompt.md");
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    var trials: std.ArrayList(Trial) = .empty;
    var development: usize = 0;
    var qualification: usize = 0;
    var prepared_development: usize = 0;
    var prepared_qualification: usize = 0;
    var admission_rejections: std.ArrayList(shared.AdmissionRejection) = .empty;
    for (cases, 0..) |example, index| {
        for (cases[0..index]) |previous| try std.testing.expect(!std.mem.eql(u8, example.id, previous.id));
        if (example.cohort == .development) development += 1 else qualification += 1;
        const base = try sourceCase(example, retained);
        const prepared = prepare(a, example, base) catch |err| {
            const rejection: shared.AdmissionRejection = .{ .case_id = example.id, .reason = shared.admissionReason(err) orelse return err };
            try admission_rejections.append(a, rejection);
            try shared.writeAdmissionRejection(a, output, rejection);
            continue;
        };
        defer prepared.passive.deinit();
        if (example.cohort == .development) prepared_development += 1 else prepared_qualification += 1;
        const target = try selectedTarget(a, prepared, base, example.target_slot);
        const prior = try prefix(a, prepared, target);
        const packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = target });
        defer packets.release(packet);
        try shared.writeAt(a, output, example.id, "review.packet.json", packet.body());
        try shared.exportBodyAt(a, output, schema, example.id, "review", packet, packet.body(), review_prompt);
        const packet_file = try pin(a, example.id, "review.packet.json");
        const edit_file = try pin(a, example.id, "review.edit.json");
        const request_file = try pin(a, example.id, "review.request.json");
        for (1..3) |repetition| try trials.append(a, .{ .id = try std.fmt.allocPrint(a, "{s}-review-{d}", .{ example.id, repetition }), .case_id = example.id, .cohort = example.cohort, .repetition = @intCast(repetition), .review_packet = packet_file, .review_edit = edit_file, .review_request = request_file, .loss_request = .derive_after_exact_receipt_admission });
        try mechanicalProbe(a, example.id, prepared, prior, target, packet, parent, request_file.sha256, trials.items.len == 2);
    }
    try std.testing.expectEqual(@as(usize, 11), development);
    try std.testing.expectEqual(@as(usize, 1), qualification);
    try std.testing.expectEqualDeep(@as([]const shared.AdmissionRejection, &.{
        .{ .case_id = "captured-description", .reason = .embedded_insertion_syntax },
        .{ .case_id = "dual-ready", .reason = .ambiguous_exact },
    }), admission_rejections.items);
    try std.testing.expectEqual(@as(usize, 9), prepared_development);
    try std.testing.expectEqual(@as(usize, 1), prepared_qualification);
    try std.testing.expectEqual(@as(usize, 20), trials.items.len);
    const dependency_paths = [_][]const u8{
        "src/test_fixtures/source_review_handoff_calibration.zig",
        "src/test_fixtures/source_loss_calibration.zig",
        "src/test_fixtures/calibration_temperature_policy.zig",
        "src/test_fixtures/source_omission_evidence.zig",
        "src/domain/specification_support.zig",
        "src/domain/specification_support_model.zig",
        "src/domain/specification_support_evidence.zig",
        "src/domain/source_omission_binding.zig",
        "src/domain/source_omission_comparison.zig",
        "src/domain/source_omission_context.zig",
        "src/domain/specification_review_subject.zig",
        "src/domain/specification_identity.zig",
        "src/domain/specification_provenance.zig",
        "src/domain/specification_authority.zig",
        "src/domain/specification.zig",
        "src/domain/typed_text.zig",
        "src/domain/required_authority_description.zig",
        "src/domain/model_envelope.zig",
        "src/domain/model_candidate_json.zig",
        "src/domain/model_controls.zig",
        "src/domain/model_result_schema.zig",
        "src/domain/model_schema_projection.zig",
        "src/adapters/provider/bedrock_request.zig",
        "design/workflows/spec/support.schema.json",
        "design/workflows/spec/support.prompt.md",
        "design/workflows/spec/support-loss.prompt.md",
        root ++ "/cases.associated.json",
        root ++ "/scorecard.template.json",
        root ++ "/handoff.parent.json",
        "test/calibration/source-loss-attribution/bound-preservation/obligation/cases.associated.json",
    };
    var dependencies: std.ArrayList(File) = .empty;
    for (dependency_paths) |path| try dependencies.append(a, try filePin(a, path));
    for (cases) |example| if ((try sourceCase(example, retained)).candidate_file) |path| try dependencies.append(a, try filePin(a, path));
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = output ++ "/preparation.json", .data = try std.json.Stringify.valueAlloc(a, .{
        .status = "offline_prepared_no_live_dispatch_authority",
        .measurement = "Actual admitted reviewer values to one complete native preservation assignment; semantic discovery, attribution, repair eligibility, denial and harm remain separate judgments.",
        .settings = .{ .provider = "aws-bedrock", .model = "openai.gpt-oss-20b-1:0", .region = "ap-southeast-2", .reasoning_effort = "low", .temperature = temperature_policy.temperature, .response_mode = "native_schema", .max_output_tokens = 16384, .seed = "absent", .top_p = "absent" },
        .limits = .{ .repetitions = 2, .development_assignments = development, .reserved_qualification_assignments = qualification, .review_sends = trials.items.len, .conditional_loss_sends = trials.items.len, .maximum_physical_sends = trials.items.len * 2, .stop_at_actual_input_plus_output_tokens = 250000, .retries_corrections_repairs_model_judges_e2e = 0 },
        .native_admission = .{ .input_cases = cases.len, .prepared_development = prepared_development, .prepared_qualification = prepared_qualification, .pre_review_rejections = admission_rejections.items },
        .native_origin_available_from_replayed_receipt = false,
        .prior_findings = "MOCK bound support or inconclusive unauthored prefix; never evidence of complete production workflow validation.",
        .downstream = "Not frozen or fabricated from expectations. Derive current complete packet and request only from an exact admitted receipt; unchanged reviewer obligation, source IDs and diagnostic origin.",
        .dependencies = dependencies.items,
        .trials = trials.items,
    }, .{}) });
    // Optional future receipts are local evidence only. This never dispatches.
    for (cases) |example| {
        const base = try sourceCase(example, retained);
        const prepared = prepare(a, example, base) catch |err| {
            if (shared.admissionReason(err) != null) continue;
            return err;
        };
        defer prepared.passive.deinit();
        const target = try selectedTarget(a, prepared, base, example.target_slot);
        const prior = try prefix(a, prepared, target);
        const packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = target });
        defer packets.release(packet);
        for (1..3) |repetition| try consumeReceipt(a, schema, example.id, repetition, prepared, prior, packet, parent);
    }
}

fn sourceCase(example: Case, retained: []const shared.Case) !shared.Case {
    if ((example.retained_case != null) == (example.fixture != null)) return error.InvalidCalibrationCase;
    if (example.fixture) |fixture| return fixture;
    for (retained) |value| if (std.mem.eql(u8, value.id, example.retained_case.?)) return value;
    return error.MissingCalibrationSource;
}
fn prepare(a: std.mem.Allocator, example: Case, base: shared.Case) !shared.PreparedContext {
    var prepared = try shared.prepareContext(a, base);
    errdefer prepared.passive.deinit();
    if (example.target_slot) |slot| {
        if (slot != .functional_requirements or base.mode == .signal) return error.InvalidCalibrationTarget;
        const spec = @import("../domain/specification.zig");
        const brief = prepared.inputs.brief orelse return error.MissingCalibrationSource;
        const value = brief.description;
        // The collection duty owns the whole feature. One retained description
        // becomes its incomplete FR; companion AC data is mock scaffolding,
        // not another independently approved requirement or semantic finding.
        const records = [_]spec.RecordProposal{
            .{ .content = .{ .acceptance_criterion = .{ .given = try business(a, "MOCK The feature is in operation."), .when = try business(a, "MOCK The represented behavior is requested."), .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance },
            .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance },
        };
        const assigned = try @import("../domain/specification_identity.zig").assign(a, .{ .display_name = brief.title, .primary_user_story = value, .records = &records, .entities = .{ .disposition = .not_applicable, .basis = value } }, .{});
        const context = prepared.context;
        const content = try shared.admitContent(a, context, assigned.content);
        try @import("../domain/specification_provenance.zig").validateStored(a, context.inputs, .{ .records = context.registry.records, .occurrences = context.registry.occurrences }, @import("../domain/reference_support.zig").records(context.references), brief, content);
        prepared.inputs = try @import("../domain/specification_authority.zig").project(a, prepared.inputs.feature, context.references, content, brief);
    }
    return prepared;
}
fn business(a: std.mem.Allocator, text: []const u8) !@import("../domain/specification.zig").BusinessValue {
    return .{ .segments = try a.dupe(@import("../domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = text } }}) };
}
fn selectedTarget(a: std.mem.Allocator, prepared: shared.PreparedContext, base: shared.Case, target_slot: ?authority.Slot) !authority.Id {
    const ledger = try authority.build(a, prepared.inputs);
    for (ledger.requirements) |required| {
        const id = required.seed.id;
        if (if (base.mode == .signal) id.unit == .signal else id.unit == .feature and id.slot == (target_slot orelse if (base.target == .primary_user_story) authority.Slot.primary_user_story else .description)) return id;
    }
    return error.MissingCalibrationTarget;
}
fn prefix(a: std.mem.Allocator, prepared: shared.PreparedContext, target: authority.Id) !?support.Collection {
    const ledger = try authority.build(a, prepared.inputs);
    var prior: ?support.Collection = null;
    for (ledger.requirements) |required| {
        if (std.meta.eql(required.seed.id, target)) return prior;
        const packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = required.seed.id });
        defer packets.release(packet);
        const rules = try evidence.requirements(a, prepared.inputs, prepared.context.inputs, required.seed.id);
        const bytes = try shared.mockPrefix(a, rules);
        prior = try support.collectFocused(a, prepared.inputs, prepared.context, prior, packet, bytes, null);
        try std.testing.expect(prior.? == .pending);
    }
    return error.MissingCalibrationTarget;
}
fn candidateOf(value: support.Collection) ?support.Candidate {
    return switch (value) {
        .pending => |candidate| candidate,
        .accepted => |accepted| accepted.candidate,
        .rejected => |rejected| rejected.candidate,
    };
}
fn mockReceipt(a: std.mem.Allocator, id: []const u8, packet: *const packets.Packet, parent: shared.ReviewParent, request_hash: []const u8, response: []const u8) !shared.ReviewReceipt {
    return .{ .input = packet.body(), .origin = .{ .trial_id = try std.fmt.allocPrint(a, "{s}-review-1", .{id}), .parent_run = parent.run, .parent_call = parent.call, .replay_run = "MOCK-offline-no-provider-send", .replay_id = "MOCK-response-1", .request_sha256 = request_hash, .response_sha256 = try shared.sha256(a, response) }, .response_bytes = response };
}
fn mechanicalProbe(a: std.mem.Allocator, id: []const u8, prepared: shared.PreparedContext, prior: ?support.Collection, target: authority.Id, packet: *const packets.Packet, parent: shared.ReviewParent, request_hash: []const u8, receipt_probes: bool) !void {
    const rules = try evidence.requirements(a, prepared.inputs, prepared.context.inputs, target);
    const source_ids = rules.eligible_source_ids;
    if (target.slot == .functional_requirements) {
        const projected = try @import("../domain/specification_review_subject.zig").project(a, prepared.inputs, prepared.context, target);
        try std.testing.expect(projected == .collection);
        try std.testing.expectEqual(authority.Slot.functional_requirements, projected.collection.slot);
        try std.testing.expectEqual(@as(usize, 1), projected.collection.records.len);
    }
    // Deliberately unrelated to panel expectations. Native admission cannot
    // turn this supplied semantic assertion into proof of correct discovery.
    const obligation = "MOCK deliberately incorrect reviewer obligation, retained byte for byte.";
    const response = try codec.encode(model.Value, a, .{ .candidate_omission = .{ .source_ids = source_ids, .detail = "MOCK actual reviewer detail; do not replace from an oracle.", .missing_obligation = obligation } });
    const receipt = try mockReceipt(a, id, packet, parent, request_hash, response);
    const receipt_bytes = try std.json.Stringify.valueAlloc(a, receipt, .{});
    const admitted = try admit(a, id, 1, prepared, prior, packet, parent, request_hash, receipt_bytes);
    try std.testing.expect(admitted.collection != .rejected);
    try std.testing.expectEqualDeep(receipt.origin, admitted.receipt.origin);
    try std.testing.expectEqualStrings(response, admitted.receipt.response_bytes);
    const derived = (try derive(a, prepared, admitted)) orelse return error.MissingCalibrationHandoff;
    defer packets.release(derived.packet);
    const ordinal = derived.candidate.pending_localization.?;
    const finding = derived.candidate.review.entries[ordinal - 1].value;
    try std.testing.expectEqualStrings(obligation, finding.missing_obligation.?);
    try std.testing.expectEqualStrings(obligation, derived.assignment.finding.missing_obligation);
    try std.testing.expectEqualDeep(source_ids, derived.assignment.finding.source_ids);
    try std.testing.expectEqualStrings(finding.detail, derived.assignment.finding.detail);
    try std.testing.expectEqualDeep(target, derived.assignment.finding.subject);
    const body = try std.json.parseFromSliceLeaky(std.json.Value, a, derived.packet.body(), .{});
    try std.testing.expectEqualStrings(obligation, body.object.get("fixed_finding").?.object.get("missing_obligation").?.string);
    try std.testing.expectEqual(derived.assignment.comparisons.len, body.object.get("comparisons").?.array.items.len);
    for (derived.assignment.comparisons, body.object.get("comparisons").?.array.items) |view, projected| {
        try std.testing.expectEqual(@as(i64, @intCast(view.id.ordinal)), projected.object.get("id").?.integer);
        try std.testing.expectEqual(view.members.len, projected.object.get("members").?.array.items.len);
    }
    try std.testing.expectEqual(source_ids.len, body.object.get("sources").?.array.items.len);
    for (body.object.get("sources").?.array.items) |source| {
        const number = source.object.get("source_id").?.integer;
        const present = for (source_ids) |source_id| {
            if (source_id.ordinal == number) break true;
        } else false;
        try std.testing.expect(present);
    }
    try std.testing.expect(derived.candidate.origin == null);
    for (derived.candidate.origins) |origin| try std.testing.expect(origin == null);
    const uncertain = try @import("source_omission_evidence.zig").response(a, derived.assignment, .{ .unlocalized = .{} });
    try std.testing.expect(try comparison.admit(a, derived.assignment, derived.assignment, prepared.context.inputs, uncertain) == .unresolved);
    const localized = try support.collectLoss(a, prepared.inputs, prepared.context, admitted.collection, derived.packet, try codec.encode(comparison.Response, a, uncertain), null);
    try std.testing.expect(localized != .rejected);
    const after = candidateOf(localized).?;
    try std.testing.expect(after.pending_localization == null);
    const retained = after.review.entries[ordinal - 1].value;
    try std.testing.expectEqualStrings(obligation, retained.missing_obligation.?);
    try std.testing.expectEqualStrings(finding.detail, retained.detail);
    try std.testing.expectEqualDeep(source_ids, retained.source_ids);
    try std.testing.expect(retained.loss == .unlocalized);
    try std.testing.expect(retained.preservation.?.origin == null);
    try completeAssignmentNegatives(a, prepared, derived.assignment, uncertain);
    // A subsequent review value is admitted independently; a gap/uncertainty
    // or ordinary support never manufactures a preservation request.
    const controls = [_]model.Value{
        .{ .supported = .{ .source_ids = source_ids, .detail = "MOCK grounded control." } },
        .{ .unsupported = .{ .source_ids = source_ids, .detail = "MOCK actual missing user choice.", .question = "MOCK Which event permits release?" } },
        .{ .inconclusive = .{ .source_ids = source_ids, .detail = "MOCK entailment unresolved without an identifiable missing user choice." } },
    };
    for (controls) |value| {
        const bytes = try codec.encode(model.Value, a, value);
        const control = try mockReceipt(a, id, packet, parent, request_hash, bytes);
        const result = try admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, control, .{}));
        try std.testing.expect(result.collection != .rejected);
        try std.testing.expect((try derive(a, prepared, result)) == null);
        const entry = candidateOf(result.collection).?.review.entries[ordinal - 1].value;
        try std.testing.expect(entry.missing_obligation == null);
        if (value == .unsupported) try std.testing.expectEqualStrings(value.unsupported.question, entry.question.?);
    }
    var foreign = receipt;
    foreign.response_bytes = try codec.encode(model.Value, a, .{ .candidate_omission = .{ .source_ids = &.{.{ .ordinal = 999 }}, .detail = "MOCK foreign source.", .missing_obligation = obligation } });
    foreign.origin.response_sha256 = try shared.sha256(a, foreign.response_bytes);
    const rejected = try admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, foreign, .{}));
    try std.testing.expect(rejected.collection == .rejected);
    try std.testing.expect((try derive(a, prepared, rejected)) == null);
    if (receipt_probes) {
        try receiptNegatives(a, id, prepared, prior, packet, parent, request_hash, receipt);
        var normalized_receipt = receipt;
        normalized_receipt.response_bytes = try std.fmt.allocPrint(a, "{{\"{s}", .{response});
        normalized_receipt.origin.response_sha256 = try shared.sha256(a, normalized_receipt.response_bytes);
        const normalized = try admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, normalized_receipt, .{}));
        try std.testing.expectEqual(envelope.Normalization.removed_leading_brace_quote, normalized.normalization);
        try std.testing.expectEqualStrings(normalized_receipt.response_bytes, normalized.receipt.response_bytes);
        const normalized_loss = (try derive(a, prepared, normalized)).?;
        defer packets.release(normalized_loss.packet);
        try std.testing.expectEqualStrings(derived.packet.body(), normalized_loss.packet.body());
    }
    var stale = prepared;
    stale.inputs.feature = .{ .bytes = "MOCK-foreign-feature" };
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, stale.inputs, stale.context, prior, packet, response, null));
    try shared.writeAt(a, output, id, "mock.mechanics.json", try std.json.Stringify.valueAlloc(a, .{ .mock = true, .semantic_evidence = false, .unchanged_actual_values = true, .complete_comparison_admission = true, .gap_uncertainty_no_loss = true, .foreign_stale_rejected = true, .native_origin_available = false, .repair_eligibility = "not_assessed_by_diagnostic_attribution", .denial = "requires_connected_native_authorizer", .harm = "not_measured_offline" }, .{}));
}
fn completeAssignmentNegatives(a: std.mem.Allocator, prepared: shared.PreparedContext, assigned: comparison.Assignment, response: comparison.Response) !void {
    try std.testing.expect(assigned.comparisons.len > 0);
    try std.testing.expectError(error.InvalidPreservationComparison, comparison.admit(a, assigned, assigned, prepared.context.inputs, .{ .assessments = response.assessments[0 .. response.assessments.len - 1] }));
    var bad = try a.dupe(comparison.Assessment, response.assessments);
    bad[0].comparison_id.ordinal = 999;
    try std.testing.expectError(error.InvalidPreservationComparison, comparison.admit(a, assigned, assigned, prepared.context.inputs, .{ .assessments = bad }));
    @memcpy(bad, response.assessments);
    if (bad.len > 1) {
        bad[1] = bad[0];
    } else {
        bad = try a.dupe(comparison.Assessment, &.{ bad[0], bad[0] });
    }
    try std.testing.expectError(error.InvalidPreservationComparison, comparison.admit(a, assigned, assigned, prepared.context.inputs, .{ .assessments = bad }));
    bad = try a.dupe(comparison.Assessment, response.assessments);
    const spans = try a.dupe(comparison.Span, bad[0].sources);
    spans[0].chunk_id = .{ .bytes = "MOCK foreign chunk" };
    bad[0].sources = spans;
    try std.testing.expectError(error.InvalidPreservationComparison, comparison.admit(a, assigned, assigned, prepared.context.inputs, .{ .assessments = bad }));
    var stale = assigned;
    stale.finding.revision += 1;
    try std.testing.expectError(error.InvalidPreservationComparison, comparison.admit(a, stale, assigned, prepared.context.inputs, response));
    var changed = assigned;
    changed.finding.missing_obligation = "MOCK different reviewer obligation";
    try std.testing.expectError(error.InvalidPreservationComparison, comparison.admit(a, assigned, changed, prepared.context.inputs, response));
}
fn receiptNegatives(a: std.mem.Allocator, id: []const u8, prepared: shared.PreparedContext, prior: ?support.Collection, packet: *const packets.Packet, parent: shared.ReviewParent, request_hash: []const u8, receipt: shared.ReviewReceipt) !void {
    var changed = receipt;
    changed.input = "{}";
    try std.testing.expectError(error.InvalidCalibrationAssignment, admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    inline for (.{ "trial_id", "parent_run", "parent_call", "request_sha256", "response_sha256" }) |field| {
        changed = receipt;
        @field(changed.origin, field) = "MOCK foreign or stale binding";
        try std.testing.expectError(error.InvalidCalibrationOrigin, admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    }
    changed = receipt;
    changed.origin.replay_id = " ";
    try std.testing.expectError(error.InvalidCalibrationOrigin, admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    try std.testing.expectError(error.InvalidCalibrationOrigin, admit(a, id, 2, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, receipt, .{})));
    var unknown = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.json.Stringify.valueAlloc(a, receipt, .{}), .{});
    try unknown.object.put(a, "native_origin", .null);
    try std.testing.expectError(error.InvalidJsonDocument, admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, unknown, .{})));
    _ = unknown.object.orderedRemove("native_origin");
    _ = unknown.object.orderedRemove("response_bytes");
    try std.testing.expectError(error.InvalidJsonDocument, admit(a, id, 1, prepared, prior, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, unknown, .{})));
}
fn consumeReceipt(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, repetition: usize, prepared: shared.PreparedContext, prior: ?support.Collection, packet: *const packets.Packet, parent: shared.ReviewParent) !void {
    const path = try std.fmt.allocPrint(a, "{s}/{s}.review.receipt-{d}.json", .{ output, id, repetition });
    const bytes = shared.read(a, path) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    const request = try shared.read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.request.json", .{ output, id }));
    const admitted = admit(a, id, repetition, prepared, prior, packet, parent, try shared.sha256(a, request), bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        try shared.writeAt(a, output, id, try std.fmt.allocPrint(a, "review.native-{d}.json", .{repetition}), try std.json.Stringify.valueAlloc(a, .{ .result = "rejected_receipt_or_envelope", .rejection = @errorName(err), .receipt_sha256 = try shared.sha256(a, bytes), .native_origin_available = false, .loss_request = @as(?[]const u8, null) }, .{}));
        return;
    };
    const derived = try derive(a, prepared, admitted);
    defer if (derived) |value| packets.release(value.packet);
    const arm = try std.fmt.allocPrint(a, "handoff-{d}-{s}", .{ repetition, admitted.receipt.origin.response_sha256 });
    const previous_count = if (prior) |value| candidateOf(value).?.review.entries.len else 0;
    const actual_finding = if (candidateOf(admitted.collection)) |candidate| if (candidate.review.entries.len > previous_count) candidate.review.entries[previous_count].value else null else null;
    if (derived) |value| {
        try shared.writeAt(a, output, id, try std.fmt.allocPrint(a, "{s}.packet.json", .{arm}), value.packet.body());
        try shared.exportBodyAt(a, output, schema, id, arm, value.packet, value.packet.body(), try shared.read(a, "design/workflows/spec/support-loss.prompt.md"));
    }
    try shared.writeAt(a, output, id, try std.fmt.allocPrint(a, "review.native-{d}.json", .{repetition}), try std.json.Stringify.valueAlloc(a, .{
        .result = @tagName(admitted.collection),
        .receipt_sha256 = try shared.sha256(a, bytes),
        .source_review_origin = admitted.receipt.origin,
        .normalization = admitted.normalization,
        .native_origin_available = false,
        .finding = actual_finding,
        .rejection = switch (admitted.collection) {
            .rejected => |value| value.rejection,
            else => null,
        },
        .loss_assignment = if (derived) |value| value.assignment else null,
        .loss_request = if (derived != null) try std.fmt.allocPrint(a, "{s}/{s}.{s}.request.json", .{ output, id, arm }) else null,
        .repair_eligibility = "requires_connected_native_authorizer; attribution is not permission",
    }, .{}));
}
fn pin(a: std.mem.Allocator, id: []const u8, suffix: []const u8) !File {
    const path = try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, id, suffix });
    const bytes = try shared.read(a, path);
    return .{ .path = path, .sha256 = try shared.sha256(a, bytes), .bytes = bytes.len };
}
fn filePin(a: std.mem.Allocator, path: []const u8) !File {
    const bytes = try shared.read(a, path);
    return .{ .path = path, .sha256 = try shared.sha256(a, bytes), .bytes = bytes.len };
}
