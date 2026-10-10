//! Offline preparation/admission for the explicitly approved diagnostic cohort.
//! No model dispatch, semantic judge or production fallback.
const std = @import("std");
const refs = @import("reference_reconciliation.zig");
const r = refs.r;
const text = @import("reference_text.zig");
const tokens = @import("reference_tokens.zig");
const extraction = @import("../reference_extraction_test.zig");
const authority = @import("../domain/required_authority.zig");
const support = @import("../domain/specification_support.zig").Source;
const comparison = @import("../domain/source_omission_comparison.zig");
const codec = @import("../domain/model_candidate_json.zig");
const packets = @import("../domain/model_input_packet.zig");
const root = "test/calibration/source-loss-attribution/bound-preservation/obligation";
const output = ".zig-cache/source-loss-obligation";
const Case = struct {
    id: []const u8,
    cohort: enum { development, unused },
    sources: []const []const u8,
    claims: []const struct { source: u32, text: []const u8, first: u32, last: u32 },
    description: []const u8,
    missing: []const u8,
    missing_obligation: []const u8,
    mode: enum { candidate, signal, second_role },
    verdicts: []const comparison.Verdict,
    expected: []const u8,
    target: ?enum { description, primary_user_story } = null,
    candidate_file: ?[]const u8 = null,
    source_path: ?[]const u8 = null,
    signal_text: ?[]const u8 = null,
};

pub fn run() !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = try codec.decode([]const Case, a, try read(a, root ++ "/cases.json"));
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try read(a, "design/workflows/spec/support.schema.json"));
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    for (cases) |example| {
        const prepared = try prepare(a, example);
        defer prepared.passive.deinit();
        const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
        const loss_packet = try support.packetForLoss(a, prepared.inputs, prepared.context, prepared.pending);
        defer packets.release(loss_packet);
        try std.testing.expectEqualStrings(example.missing_obligation, assigned.finding.missing_obligation);
        try std.testing.expectEqual(example.verdicts.len, assigned.comparisons.len);
        const model_input = try std.json.parseFromSliceLeaky(std.json.Value, a, loss_packet.body(), .{});
        try std.testing.expectEqualStrings(example.missing_obligation, model_input.object.get("fixed_finding").?.object.get("missing_obligation").?.string);
        try std.testing.expectEqual(@as(usize, 1), model_input.object.get("fixed_finding").?.object.count());
        try std.testing.expect(!model_input.object.contains("expected") and !model_input.object.contains("verdicts"));
        try write(a, example.id, "packet.json", try std.json.Stringify.valueAlloc(a, .{ .assignment = assigned, .input = model_input }, .{}));
        try exportPacket(a, schema, example.id, "candidate", loss_packet, try read(a, "design/workflows/spec/support-loss.prompt.md"));
        // Only an experiment builds the retired presentation. Production has no
        // old-reader/fallback path; prior experiments and their results stay inert.
        var baseline = try std.json.parseFromSliceLeaky(std.json.Value, a, loss_packet.body(), .{});
        const supporting = &baseline.object.getPtr("supporting_evidence").?.object;
        var fixed: std.json.ObjectMap = .empty;
        try fixed.put(a, "detail", supporting.get("diagnostic_detail").?);
        try fixed.put(a, "target_purpose", supporting.get("target_purpose").?);
        _ = supporting.orderedRemove("diagnostic_detail");
        _ = supporting.orderedRemove("target_purpose");
        baseline.object.getPtr("fixed_finding").?.* = .{ .object = fixed };
        try exportBody(a, schema, example.id, "baseline", loss_packet, try std.json.Stringify.valueAlloc(a, baseline, .{}), try read(a, root ++ "/baseline.prompt.md"));
        const review_packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = assigned.finding.subject });
        defer packets.release(review_packet);
        try exportPacket(a, schema, example.id, "review", review_packet, try read(a, "design/workflows/spec/support.prompt.md"));
        const probe_id = try std.fmt.allocPrint(a, "{s}.probe", .{example.id});
        const selected_value = prepared.pending.review.entries[prepared.pending.pending_localization.? - 1].value;
        const requirements = try @import("../domain/specification_support_evidence.zig").requirements(a, prepared.inputs, prepared.context.inputs, assigned.finding.subject);
        const review_response = try @import("../domain/specification_support_model.zig").encode(a, selected_value, requirements);
        try reviewHandoff(a, schema, probe_id, 1, prepared, review_packet, review_response);
        const probe = try std.json.parseFromSliceLeaky(std.json.Value, a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.native-1.json", .{ output, probe_id })), .{});
        try std.testing.expect(probe.object.get("admitted_omission").?.bool);
        try std.testing.expectEqualStrings(example.missing_obligation, probe.object.get("finding").?.object.get("missing_obligation").?.string);
        var response = try @import("source_omission_evidence.zig").response(a, assigned, .{ .unlocalized = .{} });
        const assessments = try a.dupe(comparison.Assessment, response.assessments);
        for (assessments, example.verdicts) |*entry, verdict| entry.result = verdict;
        response.assessments = assessments;
        const mock = try codec.encode(comparison.Response, a, response);
        const accepted = try support.admitComparisons(a, prepared.inputs, prepared.context, prepared.pending, assigned, mock);
        try std.testing.expectEqualStrings(example.expected, @tagName(comparison.location(accepted)));
        try std.testing.expectError(error.InvalidPreservationComparison, support.admitComparisons(a, prepared.inputs, prepared.context, prepared.pending, assigned, "{\"assessments\":[]}"));
        for (1..3) |repetition| {
            for ([_][]const u8{ "baseline", "candidate" }) |arm| {
                const id = try std.fmt.allocPrint(a, "{s}.{s}", .{ example.id, arm });
                try write(a, id, try std.fmt.allocPrint(a, "probe-native-{d}.json", .{repetition}), try admissionReport(a, prepared, assigned, mock));
                if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.response-{d}.json", .{ output, id, repetition }))) |bytes|
                    try write(a, id, try std.fmt.allocPrint(a, "native-{d}.json", .{repetition}), try admissionReport(a, prepared, assigned, bytes));
            }
            // Exercise the actual review -> native admission -> loss handoff.
            // Live review text is never replaced with the cohort's expected obligation.
            if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.review.response-{d}.json", .{ output, example.id, repetition }))) |bytes|
                try reviewHandoff(a, schema, example.id, repetition, prepared, review_packet, bytes);
        }
    }
    // Requests are immutable experiment projections; never edit their generated
    // copies to fix a mismatch. Regenerate from the canonical owners and re-freeze.
    for (cases) |example| {
        for ([_][]const u8{ "packet.json", "baseline.edit.json", "baseline.request.json", "candidate.edit.json", "candidate.request.json", "review.edit.json", "review.request.json" }) |suffix| {
            const exported = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, example.id, suffix }));
            const frozen = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ root, example.id, suffix }));
            try std.testing.expectEqualStrings(frozen, exported);
        }
    }
}
fn read(a: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited);
}
fn optional(a: std.mem.Allocator, path: []const u8) !?[]const u8 {
    return read(a, path) catch |err| switch (err) {
        error.FileNotFound => null,
        else => err,
    };
}
fn exportPacket(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, arm: []const u8, packet: *const packets.Packet, prompt: []const u8) !void {
    return exportBody(a, schema, id, arm, packet, packet.body(), prompt);
}
fn exportBody(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, arm: []const u8, packet: *const packets.Packet, body: []const u8, prompt: []const u8) !void {
    const restricted = try @import("../domain/model_result_schema.zig").restrict(a, schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    const bytes = try std.json.Stringify.valueAlloc(a, .{ .content = .{ .{ .guidance = prompt }, .{ .user = body } }, .schema = restricted.selected().modelBytes() }, .{});
    try write(a, id, try std.fmt.allocPrint(a, "{s}.edit.json", .{arm}), bytes);
    try write(a, id, try std.fmt.allocPrint(a, "{s}.request.json", .{arm}), try encodeEdit(a, try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{})));
}
fn reviewHandoff(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, repetition: usize, prepared: Prepared, packet: *const packets.Packet, bytes: []const u8) !void {
    const ordinal = prepared.pending.pending_localization.?;
    var prior = prepared.pending;
    prior.pending_localization = null;
    prior.review.entries = prior.review.entries[0 .. ordinal - 1];
    prior.origins = prior.origins[0 .. ordinal - 1];
    const result = try support.collectFocused(a, prepared.inputs, prepared.context, if (ordinal == 1) null else .{ .pending = prior }, packet, bytes, null);
    const tag = @tagName(result);
    const suffix = try std.fmt.allocPrint(a, "review.native-{d}.json", .{repetition});
    const admitted: ?support.Candidate = switch (result) {
        .pending => |candidate| candidate,
        .accepted => |accepted| accepted.candidate,
        .rejected => null,
    };
    if (admitted == null or admitted.?.pending_localization == null) {
        try write(a, id, suffix, try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = false, .result = tag }, .{}));
        return;
    }
    const pending = admitted.?;
    try write(a, id, suffix, try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = true, .finding = pending.review.entries[ordinal - 1].value }, .{}));
    const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, pending);
    const loss_packet = try support.packetForLoss(a, prepared.inputs, prepared.context, pending);
    defer packets.release(loss_packet);
    const arm = try std.fmt.allocPrint(a, "handoff-{d}", .{repetition});
    try exportPacket(a, schema, id, arm, loss_packet, try read(a, "design/workflows/spec/support-loss.prompt.md"));
    const live_prepared: Prepared = .{ .inputs = prepared.inputs, .context = prepared.context, .pending = pending, .passive = prepared.passive };
    if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.response.json", .{ output, id, arm }))) |response|
        try write(a, id, try std.fmt.allocPrint(a, "{s}.native.json", .{arm}), try admissionReport(a, live_prepared, assigned, response));
}
const Prepared = struct {
    inputs: authority.Inputs,
    context: @import("../domain/specification_provenance.zig").Context,
    pending: support.Candidate,
    passive: text.Prepared,
};
fn prepare(a: std.mem.Allocator, example: Case) !Prepared {
    var ids: @import("../reference_evidence_test.zig").IdSource = .{};
    const sources = try @import("../reference_evidence_test.zig").prepare(a, &ids, if (example.source_path) |path| try @import("../reference_ingestion_test.zig").read(a, path, example.sources[0]) else try @import("../reference_ingestion_test.zig").readSources(std.testing.io, a, example.sources));
    const passive = try text.prepare(a, sources);
    errdefer passive.deinit();
    const available = try tokens.candidates(a, sources);
    const raw = try a.alloc(r.extraction.RawResult, sources.chunks.entries.len);
    for (sources.chunks.entries, raw) |chunk, *result| {
        const resolved = try r.evidence.resolve(sources, .{ .state_id = sources.corpus.state_id, .chunk_id = chunk.id });
        var claims: std.ArrayList(r.extraction.Proposal) = .empty;
        for (example.claims) |claim| if (claim.source == resolved.source.id.ordinal) {
            try claims.append(a, .{ .content = .{ .business = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = claim.text } }}) } }, .citations = try a.dupe(@import("../domain/source_selections.zig").Selection, &.{.{ .first = .{ .ordinal = claim.first }, .last = .{ .ordinal = claim.last } }}) });
        };
        result.* = .{ .scope = .{ .state_id = sources.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = try codec.encode(@import("../domain/reference_extraction_parser.zig").Response, a, .{ .claims = .{ .claims = claims.items, .token_classifications = try tokens.classifications(a, available, chunk) } }) } };
    }
    const extracted = try extraction.finish(a, sources, raw);
    const context: refs.Context = .{ .inputs = sources, .registry = passive.registry, .current = text.safety.value(passive.owner) };
    const global = try refs.summaries(a, try refs.initialize(a, sources, extracted, 2), context);
    var proposed = try refs.global(a, global);
    var groups: std.ArrayList(r.SignalProposal) = .empty;
    var business: std.ArrayList(r.ClaimId) = .empty;
    var combined: std.ArrayList(u8) = .empty;
    for (global.items) |item| if (item.claim.content == .model) {
        try business.append(a, item.claim.id);
        for (item.claim.content.model.business.value.segments) |segment| try combined.appendSlice(a, segment.literal.value);
        try combined.append(a, ' ');
    };
    if (example.mode == .second_role) {
        for (proposed.signals) |signal| try groups.append(a, signal);
    } else {
        try groups.append(a, .{ .claim_ids = business.items, .content = .{ .model = .{ .business = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = example.signal_text orelse (if (example.mode == .signal) example.description else combined.items) } }}) } } } });
        for (proposed.signals) |signal| if (signal.content == .preserved_token) try groups.append(a, signal);
    }
    proposed.signals = groups.items;
    var roles: std.ArrayList(r.RoleAssignment) = .empty;
    for (proposed.signals, 1..) |signal, ordinal| if (signal.content == .model) {
        try roles.append(a, .{ .signal_id = .{ .ordinal = @intCast(ordinal) }, .generation_roles = if (example.mode == .second_role and ordinal == 1) &.{.records} else std.enums.values(r.GenerationRole) });
    };
    proposed.role_decisions = try refs.roleDecisions(a, roles.items);
    const finished = (try refs.finish(a, global, proposed, context)).valid;
    const provenance_context: @import("../domain/specification_provenance.zig").Context = .{ .inputs = sources, .references = finished, .registry = context.registry, .current = context.current };
    const records = @import("../domain/reference_support.zig").records(finished);
    const assigned = try @import("../domain/specification_source_binding.zig").roleClaimIds(a, records, if (example.target == .primary_user_story) .primary_user_story else .description);
    const attribution = try @import("../domain/specification_provenance.zig").select(a, provenance_context, .{ .claim_ids = assigned, .clarification_response_ids = &.{} });
    const spec = @import("../domain/specification.zig");
    const value: spec.AttributedValue = .{ .value = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = example.description } }}) }, .provenance = attribution };
    var brief: spec.Brief = .{ .title = value, .description = value, .primary_goal = value };
    var candidate: ?spec.IdentifiedContent = null;
    if (example.candidate_file) |path| {
        const captured = try @import("../domain/strict_json.zig").decode(struct { brief: spec.Brief, candidate: spec.IdentifiedContent }, a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited), .{ .maximum_depth = 128 });
        brief = captured.brief;
        candidate = captured.candidate;
        try @import("../domain/specification_provenance.zig").validateStored(a, sources, .{ .records = passive.registry.records, .occurrences = passive.registry.occurrences }, records, brief, candidate.?);
    }
    const inputs = try @import("../domain/specification_authority.zig").project(a, sources.corpus.feature_id, finished, candidate, if (example.mode == .signal) null else brief);
    const ledger = try authority.build(a, inputs);
    const index = for (ledger.requirements, 0..) |required, at| {
        if (if (example.mode == .signal) required.seed.id.unit == .signal else required.seed.id.unit == .feature and required.seed.id.slot == (if (example.target == .primary_user_story) authority.Slot.primary_user_story else .description)) break at;
    } else return error.MissingCalibrationTarget;
    // A fixed admitted omission is the experimental premise, not a model judge.
    const findings = try a.alloc(support.Finding, index + 1);
    for (findings, 1..) |*entry, ordinal| entry.* = .{ .requirement_ordinal = @intCast(ordinal), .value = .{ .kind = .supported, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "", .question = null } };
    const source_ids = try a.alloc(r.extraction.identity.SourceId, sources.corpus.sources.len);
    for (sources.corpus.sources, source_ids) |source, *id| id.* = source.id;
    for (findings[0..index], ledger.requirements[0..index]) |*entry, required| {
        const rules = try @import("../domain/specification_support_evidence.zig").requirements(a, inputs, sources, required.seed.id);
        // Wire ordinals use model_candidate_json, not canonical wrapper objects.
        const selected = try codec.encode(@import("../domain/specification_support_model.zig").Value, a, .{ .supported = .{ .source_ids = rules.eligible_source_ids, .detail = "MOCK Prior source review accepted for isolated handoff preparation." } });
        entry.value = try @import("../domain/specification_support_model.zig").decode(a, selected, rules);
    }
    findings[index].value.kind = .candidate_omission;
    findings[index].value.detail = example.missing;
    findings[index].value.missing_obligation = example.missing_obligation;
    findings[index].value.source_ids = source_ids;
    const rules = try @import("../domain/specification_support_evidence.zig").requirements(a, inputs, sources, ledger.requirements[index].seed.id);
    findings[index].value.provenance.claim_ids = rules.rule(.candidate_omission, .{ .unlocalized = .{} }).fixedClaims() orelse &.{};
    const origins = try a.alloc(?@import("../domain/model_candidate_origin.zig").Origin, findings.len);
    @memset(origins, null);
    const pending: support.Candidate = .{ .review = .{ .entries = findings }, .pending_localization = @intCast(index + 1), .working = true, .origin = null, .origins = origins };
    return .{ .inputs = inputs, .context = provenance_context, .pending = pending, .passive = passive };
}

fn encodeEdit(a: std.mem.Allocator, edit: std.json.Value) ![]const u8 {
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = try parser.compiler().compile(a, edit.object.get("schema").?.string);
    const content = edit.object.get("content").?.array.items;
    return @import("../adapters/provider/bedrock_request.zig").encodeText(a, .{
        .content = &.{ .{ .guidance = content[0].object.get("guidance").?.string }, .{ .user = content[1].object.get("user").?.string } },
        .schema = .{ .native = .{ .guidance = compiled.modelBytes(), .structure = try @import("../domain/model_schema_projection.zig").render(a, compiled, .bedrock) } },
        .schema_name = "sdde_model_envelope_v1",
        .temperature = .zero,
        .max_output_tokens = .{ .value = 16384 },
        .reasoning_effort = .low,
    }, .inference);
}
fn admissionReport(a: std.mem.Allocator, prepared: Prepared, assigned: comparison.Assignment, bytes: []const u8) ![]const u8 {
    return if (support.admitComparisons(a, prepared.inputs, prepared.context, prepared.pending, assigned, bytes)) |accepted|
        std.json.Stringify.valueAlloc(a, .{ .admitted = true, .attribution = accepted }, .{})
    else |err|
        std.json.Stringify.valueAlloc(a, .{ .admitted = false, .rejection = @errorName(err) }, .{});
}

fn write(a: std.mem.Allocator, id: []const u8, suffix: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, id, suffix }), .data = bytes });
}
