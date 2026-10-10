//! Offline preparation/admission for a frozen diagnostic comparison.
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
const cases_root = "test/calibration/source-loss-attribution/bound-preservation/obligation";
const root = "test/calibration/source-loss-attribution/bound-preservation/citation-completeness";
const output = ".zig-cache/source-loss-citation-completeness";
const prior_root = "test/calibration/source-loss-attribution/bound-preservation/native-scope";
const Arm = enum { baseline, candidate };
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
    const retained = try codec.decode([]const Case, a, try read(a, cases_root ++ "/cases.json"));
    const controls = try codec.decode([]const Case, a, try read(a, root ++ "/citation.controls.json"));
    const cases = try a.alloc(Case, retained.len + controls.len);
    @memcpy(cases[0..retained.len], retained);
    @memcpy(cases[retained.len..], controls);
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try read(a, "design/workflows/spec/support.schema.json"));
    try runCitationCompleteness(a, schema, cases, retained.len);
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
    return exportBodyAt(a, output, schema, id, arm, packet, body, prompt);
}
fn exportBodyAt(a: std.mem.Allocator, directory: []const u8, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, arm: []const u8, packet: *const packets.Packet, body: []const u8, prompt: []const u8) !void {
    const restricted = try @import("../domain/model_result_schema.zig").restrict(a, schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    const bytes = try std.json.Stringify.valueAlloc(a, .{ .content = .{ .{ .guidance = prompt }, .{ .user = body } }, .schema = restricted.selected().modelBytes() }, .{});
    try writeAt(a, directory, id, try std.fmt.allocPrint(a, "{s}.edit.json", .{arm}), bytes);
    try writeAt(a, directory, id, try std.fmt.allocPrint(a, "{s}.request.json", .{arm}), try encodeEdit(a, try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{})));
}
fn reviewHandoff(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, repetition: usize, prepared: Prepared, packet: *const packets.Packet, bytes: []const u8, origin: ?ReviewOrigin) !void {
    const ordinal = prepared.pending.pending_localization.?;
    var prior = prepared.pending;
    prior.pending_localization = null;
    prior.review.entries = prior.review.entries[0 .. ordinal - 1];
    prior.origins = prior.origins[0 .. ordinal - 1];
    const envelope = @import("../domain/model_envelope.zig");
    var syntax_diagnostic: ?envelope.Diagnostic = null;
    defer if (syntax_diagnostic) |diagnostic| diagnostic.deinit(a);
    var document: ?envelope.Document = envelope.parseContent(a, bytes, &syntax_diagnostic) catch |err| if (err == error.OutOfMemory) return err else null;
    defer if (document) |*value| value.deinit();
    const result = try support.collectFocused(a, prepared.inputs, prepared.context, if (ordinal == 1) null else .{ .pending = prior }, packet, if (document) |value| value.content else bytes, null);
    const tag = @tagName(result);
    const suffix = try std.fmt.allocPrint(a, "review.native-{d}.json", .{repetition});
    const admitted: ?support.Candidate = switch (result) {
        .pending => |candidate| candidate,
        .accepted => |accepted| accepted.candidate,
        .rejected => null,
    };
    const rejection = switch (result) {
        .rejected => |rejected| rejected.rejection,
        else => null,
    };
    if (admitted == null or admitted.?.pending_localization == null) {
        const finding = if (admitted) |candidate| if (candidate.review.entries.len >= ordinal) candidate.review.entries[ordinal - 1].value else null else null;
        try write(a, id, suffix, try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = false, .result = tag, .finding = finding, .rejection = rejection, .syntax_diagnostic = syntax_diagnostic, .normalization = if (document) |value| value.normalization else .none, .source_review_origin = origin, .native_origin_available = false }, .{}));
        return;
    }
    const pending = admitted.?;
    const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, pending);
    const finding = pending.review.entries[ordinal - 1].value;
    try std.testing.expectEqualStrings(finding.missing_obligation.?, assigned.finding.missing_obligation);
    try std.testing.expectEqualDeep(finding.source_ids, assigned.finding.source_ids);
    const loss_packet = try support.packetForLoss(a, prepared.inputs, prepared.context, pending);
    defer packets.release(loss_packet);
    const loss_input = try std.json.parseFromSliceLeaky(std.json.Value, a, loss_packet.body(), .{});
    try std.testing.expectEqualStrings(finding.missing_obligation.?, loss_input.object.get("fixed_finding").?.object.get("missing_obligation").?.string);
    const offered_sources = loss_input.object.get("sources").?.array.items;
    for (offered_sources) |source| {
        const id_value = source.object.get("source_id").?.integer;
        const authorized = for (finding.source_ids) |source_id| {
            if (source_id.ordinal == id_value) break true;
        } else false;
        try std.testing.expect(authorized);
    }
    for (finding.source_ids) |source_id| {
        const present = for (offered_sources) |source| {
            if (source.object.get("source_id").?.integer == source_id.ordinal) break true;
        } else false;
        try std.testing.expect(present);
    }
    const arm = try std.fmt.allocPrint(a, "handoff-{d}", .{repetition});
    try exportPacket(a, schema, id, arm, loss_packet, try read(a, "design/workflows/spec/support-loss.prompt.md"));
    try write(a, id, suffix, try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = true, .finding = finding, .assignment = assigned, .normalization = document.?.normalization, .source_review_origin = origin, .native_origin_available = false }, .{}));
}
const ReviewOrigin = struct {
    trial_id: []const u8,
    parent_run: []const u8,
    parent_call: []const u8,
    replay_run: []const u8,
    replay_id: []const u8,
    request_sha256: []const u8,
    response_sha256: []const u8,
};
const ReviewReceipt = struct { input: []const u8, origin: ReviewOrigin, response_bytes: []const u8 };
const ReviewParent = struct { run: []const u8, call: []const u8 };
const ReviewReceiptError = @import("../domain/strict_json.zig").Error || error{ InvalidCalibrationAssignment, InvalidCalibrationOrigin };
fn admitReviewReceipt(a: std.mem.Allocator, id: []const u8, repetition: usize, packet: *const packets.Packet, parent: ReviewParent, expected_request_sha256: []const u8, bytes: []const u8) ReviewReceiptError!ReviewReceipt {
    const receipt = try @import("../domain/strict_json.zig").decode(ReviewReceipt, a, bytes, .{ .maximum_depth = 128 });
    if (!std.mem.eql(u8, packet.body(), receipt.input)) return error.InvalidCalibrationAssignment;
    if (!std.mem.eql(u8, try std.fmt.allocPrint(a, "{s}-review-{d}", .{ id, repetition }), receipt.origin.trial_id) or !std.mem.eql(u8, expected_request_sha256, receipt.origin.request_sha256)) return error.InvalidCalibrationOrigin;
    if (!std.mem.eql(u8, parent.run, receipt.origin.parent_run) or !std.mem.eql(u8, parent.call, receipt.origin.parent_call)) return error.InvalidCalibrationOrigin;
    inline for (.{ "parent_run", "parent_call", "replay_run", "replay_id" }) |field| {
        if (std.mem.trim(u8, @field(receipt.origin, field), " \r\n\t").len == 0) return error.InvalidCalibrationOrigin;
    }
    if (!std.mem.eql(u8, receipt.origin.response_sha256, try sha256(a, receipt.response_bytes))) return error.InvalidCalibrationOrigin;
    return receipt;
}
fn consumeReviewReceipt(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, repetition: usize, prepared: Prepared, packet: *const packets.Packet) !void {
    const bytes = (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.review.receipt-{d}.json", .{ output, id, repetition }))) orelse return;
    const request_bytes = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.request.json", .{ output, id }));
    const parent = try @import("../domain/strict_json.zig").decode(ReviewParent, a, try read(a, root ++ "/handoff.parent.json"), .{ .maximum_depth = 8 });
    const receipt = admitReviewReceipt(a, id, repetition, packet, parent, try sha256(a, request_bytes), bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        try write(a, id, try std.fmt.allocPrint(a, "review.native-{d}.json", .{repetition}), try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = false, .result = "rejected_receipt", .rejection = @errorName(err), .native_origin_available = false }, .{}));
        return;
    };
    try reviewHandoff(a, schema, id, repetition, prepared, packet, receipt.response_bytes, receipt.origin);
}
fn sha256(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
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
fn write(a: std.mem.Allocator, id: []const u8, suffix: []const u8, bytes: []const u8) !void {
    return writeAt(a, output, id, suffix, bytes);
}
fn writeAt(a: std.mem.Allocator, directory: []const u8, id: []const u8, suffix: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ directory, id, suffix }), .data = bytes });
}

// Isolation is a diagnostic projection, not a second production loss-review
// implementation. The complete native assignment and admission stay unchanged.
const IsolationOrigin = struct { trial_id: []const u8, response_id: []const u8, request_sha256: []const u8 };
const IsolationRequest = struct { comparison_id: u32, request_sha256: []const u8 };
const IsolationScope = struct { case_id: []const u8, arm: Arm, repetition: usize, requests: []const IsolationRequest };
const IsolationPiece = struct { comparison_id: u32, origin: IsolationOrigin, response: std.json.Value };
const IsolationReceipt = struct { assignment: comparison.Assignment, pieces: []const IsolationPiece };
const IsolationResult = union(enum) { incomplete: []const u32, admitted: comparison.Attribution };
const IsolationError = support.ComparisonError || error{ InvalidCalibrationAssignment, InvalidCalibrationPiece, InvalidCalibrationOrigin };

fn aggregateIsolation(a: std.mem.Allocator, prepared: Prepared, scope: IsolationScope, receipt: IsolationReceipt) IsolationError!IsolationResult {
    const current = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
    const snapshot = @import("../domain/atomic_repair.zig").snapshot;
    if (!std.meta.eql(try snapshot(comparison.Assignment, a, receipt.assignment), try snapshot(comparison.Assignment, a, current))) return error.InvalidCalibrationAssignment;
    var assessments: std.ArrayList(comparison.Assessment) = .empty;
    for (receipt.pieces, 0..) |piece, index| {
        const assigned = for (current.comparisons) |view| {
            if (view.id.ordinal == piece.comparison_id) break true;
        } else false;
        if (!assigned) return error.InvalidCalibrationPiece;
        if (std.mem.trim(u8, piece.origin.trial_id, " \r\n\t").len == 0 or std.mem.trim(u8, piece.origin.response_id, " \r\n\t").len == 0) return error.InvalidCalibrationOrigin;
        if (!std.mem.eql(u8, piece.origin.trial_id, try isolationTrial(a, scope, piece.comparison_id))) return error.InvalidCalibrationOrigin;
        const request = for (scope.requests) |value| {
            if (value.comparison_id == piece.comparison_id) break value;
        } else return error.InvalidCalibrationAssignment;
        if (!std.mem.eql(u8, request.request_sha256, piece.origin.request_sha256)) return error.InvalidCalibrationOrigin;
        for (receipt.pieces[0..index]) |prior| {
            if (prior.comparison_id == piece.comparison_id) return error.InvalidCalibrationPiece;
            if (std.mem.eql(u8, prior.origin.trial_id, piece.origin.trial_id) or std.mem.eql(u8, prior.origin.response_id, piece.origin.response_id)) return error.InvalidCalibrationOrigin;
        }
        const response = try codec.decode(comparison.Response, a, try std.json.Stringify.valueAlloc(a, piece.response, .{}));
        if (response.assessments.len != 1 or response.assessments[0].comparison_id.ordinal != piece.comparison_id) return error.InvalidCalibrationPiece;
        try assessments.append(a, response.assessments[0]);
    }
    var missing: std.ArrayList(u32) = .empty;
    for (current.comparisons) |view| {
        const present = for (receipt.pieces) |piece| {
            if (piece.comparison_id == view.id.ordinal) break true;
        } else false;
        if (!present) try missing.append(a, view.id.ordinal);
    }
    if (missing.items.len != 0) return .{ .incomplete = missing.items };
    // Only a complete set reaches the existing full-assignment native owner.
    const bytes = try codec.encode(comparison.Response, a, .{ .assessments = assessments.items });
    return .{ .admitted = try support.admitComparisons(a, prepared.inputs, prepared.context, prepared.pending, receipt.assignment, bytes) };
}

fn isolationReport(a: std.mem.Allocator, prepared: Prepared, scope: IsolationScope, bytes: []const u8) ![]const u8 {
    const Origin = struct { comparison_id: u32, origin: IsolationOrigin };
    const Report = struct {
        status: enum { incomplete, admitted, rejected },
        origins: []const Origin,
        missing_comparison_ids: []const u32 = &.{},
        attribution: ?comparison.Attribution = null,
        rejection: ?[]const u8 = null,
    };
    // Assignment uses canonical wrappers from packet.json. Each nested response
    // uses the model wire codec separately; no mixed-format or legacy reader.
    const receipt = decodeIsolationReceipt(a, bytes) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return std.json.Stringify.valueAlloc(a, Report{ .status = .rejected, .origins = &.{}, .rejection = @errorName(err) }, .{});
    };
    const origins = try a.alloc(Origin, receipt.pieces.len);
    for (receipt.pieces, origins) |piece, *origin| origin.* = .{ .comparison_id = piece.comparison_id, .origin = piece.origin };
    const result = aggregateIsolation(a, prepared, scope, receipt) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return std.json.Stringify.valueAlloc(a, Report{ .status = .rejected, .origins = origins, .rejection = @errorName(err) }, .{});
    };
    return std.json.Stringify.valueAlloc(a, switch (result) {
        .incomplete => |missing| Report{ .status = .incomplete, .origins = origins, .missing_comparison_ids = missing },
        .admitted => |attribution| Report{ .status = .admitted, .origins = origins, .attribution = attribution },
    }, .{});
}

fn decodeIsolationReceipt(a: std.mem.Allocator, bytes: []const u8) @import("../domain/strict_json.zig").Error!IsolationReceipt {
    const strict = @import("../domain/strict_json.zig");
    const raw = try strict.decode(std.json.Value, a, bytes, .{ .maximum_depth = 128 });
    if (raw != .object or raw.object.count() != 2) return error.InvalidJsonDocument;
    const assigned = raw.object.get("assignment") orelse return error.InvalidJsonDocument;
    const received = raw.object.get("pieces") orelse return error.InvalidJsonDocument;
    if (received != .array) return error.InvalidJsonDocument;
    const assignment = try strict.decode(comparison.Assignment, a, try std.json.Stringify.valueAlloc(a, assigned, .{}), .{ .maximum_depth = 128 });
    const pieces = try a.alloc(IsolationPiece, received.array.items.len);
    for (received.array.items, pieces) |entry, *piece| {
        if (entry != .object or entry.object.count() != 3) return error.InvalidJsonDocument;
        const id = entry.object.get("comparison_id") orelse return error.InvalidJsonDocument;
        if (id != .integer) return error.InvalidJsonDocument;
        const origin = entry.object.get("origin") orelse return error.InvalidJsonDocument;
        piece.* = .{
            .comparison_id = std.math.cast(u32, id.integer) orelse return error.InvalidJsonDocument,
            .origin = try strict.decode(IsolationOrigin, a, try std.json.Stringify.valueAlloc(a, origin, .{}), .{ .maximum_depth = 8 }),
            .response = entry.object.get("response") orelse return error.InvalidJsonDocument,
        };
    }
    return .{ .assignment = assignment, .pieces = pieces };
}

fn isolatedBody(a: std.mem.Allocator, packet: *const packets.Packet, id: comparison.Id) ![]const u8 {
    var body = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
    const collection = body.object.getPtr("comparisons").?;
    const selected = for (collection.array.items) |view| {
        if (view.object.get("id").?.integer == id.ordinal) break view;
    } else return error.InvalidCalibrationPiece;
    collection.* = .{ .array = std.json.Array.init(a) };
    try collection.array.append(selected);
    return std.json.Stringify.valueAlloc(a, body, .{});
}

fn isolatedPacket(a: std.mem.Allocator, packet: *const packets.Packet, id: comparison.Id) !*packets.Packet {
    const Choice = @import("../domain/model_result_schema.zig").IntegerChoice;
    const choices = try a.dupe(Choice, packet.integerChoices());
    var found = false;
    for (choices) |*choice| {
        if (choice.definition == null or !std.mem.eql(u8, choice.definition.?.bytes, "preservation_comparisons") or choice.target != .path) continue;
        const path = choice.target.path;
        if (path.len != 3 or path[0] != .property or !std.mem.eql(u8, path[0].property, "assessments") or path[1] != .items or path[2] != .property or !std.mem.eql(u8, path[2].property, "comparison_id")) continue;
        if (found) return error.InvalidCalibrationAssignment;
        found = true;
        choice.allowed = try a.dupe(i64, &.{id.ordinal});
    }
    if (!found) return error.InvalidCalibrationAssignment;
    return packets.withRestrictions(a, packet, packet.excludedVariants(), choices);
}

fn runCitationCompleteness(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, cases: []const Case, retained_count: usize) !void {
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    const prompt = try read(a, "design/workflows/spec/support-loss.prompt.md");
    for (cases, 0..) |example, case_index| {
        const prepared = try prepare(a, example);
        defer prepared.passive.deinit();
        const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
        const packet = try support.packetForLoss(a, prepared.inputs, prepared.context, prepared.pending);
        defer packets.release(packet);
        const full = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
        try std.testing.expectEqualStrings(example.missing_obligation, assigned.finding.missing_obligation);
        try std.testing.expectEqual(example.verdicts.len, assigned.comparisons.len);
        try write(a, example.id, "packet.json", try std.json.Stringify.valueAlloc(a, .{ .assignment = assigned, .input = full }, .{}));
        const requests = try a.alloc([2]IsolationRequest, assigned.comparisons.len);
        for (assigned.comparisons, requests) |view, *request| {
            const isolated = try isolatedPacket(a, packet, view.id);
            defer packets.release(isolated);
            const body = try isolatedBody(a, packet, view.id);
            var restored = try std.json.parseFromSliceLeaky(std.json.Value, a, body, .{});
            const members = restored.object.get("comparisons").?.array.items;
            try std.testing.expectEqual(@as(usize, 1), members.len);
            const original = for (full.object.get("comparisons").?.array.items) |value| {
                if (value.object.get("id").?.integer == view.id.ordinal) break value;
            } else return error.InvalidCalibrationAssignment;
            try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, original, .{}), try std.json.Stringify.valueAlloc(a, members[0], .{}));
            // All original business evidence survives isolation byte-for-byte.
            restored.object.getPtr("comparisons").?.* = full.object.get("comparisons").?;
            try std.testing.expectEqualStrings(packet.body(), try std.json.Stringify.valueAlloc(a, restored, .{}));
            for (std.enums.values(Arm), 0..) |arm, arm_index| {
                const name = try std.fmt.allocPrint(a, "{s}-{d}", .{ @tagName(arm), view.id.ordinal });
                try exportBodyAt(a, output, schema, example.id, name, isolated, body, if (arm == .baseline) try read(a, root ++ "/baseline.prompt.md") else prompt);
                if (arm == .baseline and case_index < retained_count) {
                    // Prior panels remain immutable; both arms now use the same
                    // native-owned response contract and differ only in guidance.
                    for ([_][]const u8{ "edit.json", "request.json" }) |kind| {
                        const prior = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.candidate-{d}.{s}", .{ prior_root, example.id, view.id.ordinal, kind }));
                        const current = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.{s}", .{ output, example.id, name, kind }));
                        try std.testing.expectEqualStrings(prior, current);
                    }
                }
                const request_bytes = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.request.json", .{ output, example.id, name }));
                request[arm_index] = .{ .comparison_id = view.id.ordinal, .request_sha256 = try sha256(a, request_bytes) };
            }
        }
        const arms_requests = try a.alloc([]IsolationRequest, 2);
        for (std.enums.values(Arm), 0..) |arm, arm_index| {
            const selected = try a.alloc(IsolationRequest, requests.len);
            for (requests, selected) |pair, *request| request.* = pair[arm_index];
            arms_requests[arm_index] = selected;
            try isolationChecks(a, prepared, assigned, example, selected, arm);
        }
        const review_packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = assigned.finding.subject });
        defer packets.release(review_packet);
        try exportPacket(a, schema, example.id, "review", review_packet, try read(a, "design/workflows/spec/support.prompt.md"));
        const probe_id = try std.fmt.allocPrint(a, "{s}.probe", .{example.id});
        const selected = prepared.pending.review.entries[prepared.pending.pending_localization.? - 1].value;
        const requirements = try @import("../domain/specification_support_evidence.zig").requirements(a, prepared.inputs, prepared.context.inputs, assigned.finding.subject);
        const review_response = try @import("../domain/specification_support_model.zig").encode(a, selected, requirements);
        try reviewHandoff(a, schema, probe_id, 1, prepared, review_packet, review_response, null);
        const probe = try std.json.parseFromSliceLeaky(std.json.Value, a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.native-1.json", .{ output, probe_id })), .{});
        try std.testing.expect(probe.object.get("admitted_omission").?.bool);
        try std.testing.expectEqualStrings(example.missing_obligation, probe.object.get("finding").?.object.get("missing_obligation").?.string);
        try reviewReceiptChecks(a, example.id, prepared, review_packet, review_response);
        for (1..3) |repetition| {
            for (std.enums.values(Arm), 0..) |arm, arm_index| {
                if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.receipt-{d}.json", .{ output, example.id, @tagName(arm), repetition }))) |bytes|
                    try write(a, example.id, try std.fmt.allocPrint(a, "{s}.native-{d}.json", .{ @tagName(arm), repetition }), try isolationReport(a, prepared, .{ .case_id = example.id, .arm = arm, .repetition = repetition, .requests = arms_requests[arm_index] }, bytes));
            }
            // Receipt lineage is diagnostic observation, not engine ledger authority.
            try consumeReviewReceipt(a, schema, example.id, repetition, prepared, review_packet);
        }
    }
    try prepareHandoffControls(a, schema);
    for (cases) |example| {
        const prepared = try prepare(a, example);
        defer prepared.passive.deinit();
        const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
        try frozenCitationCompleteness(a, example.id, "packet.json");
        for ([_][]const u8{ "review.edit.json", "review.request.json" }) |suffix| try frozenCitationCompleteness(a, example.id, suffix);
        for (assigned.comparisons) |view| for ([_][]const u8{ "baseline", "candidate" }) |arm| for ([_][]const u8{ "edit.json", "request.json" }) |kind| {
            try frozenCitationCompleteness(a, example.id, try std.fmt.allocPrint(a, "{s}-{d}.{s}", .{ arm, view.id.ordinal, kind }));
        };
    }
}

fn prepareHandoffControls(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema) !void {
    const Control = struct {
        expected: enum { supported, unsupported },
        detail: []const u8,
        question: ?[]const u8,
        fixture: Case,
    };
    const controls = try codec.decode([]const Control, a, try read(a, prior_root ++ "/handoff.controls.json"));
    for (controls) |control| {
        const prepared = try prepare(a, control.fixture);
        defer prepared.passive.deinit();
        const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
        const packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = assigned.finding.subject });
        defer packets.release(packet);
        try exportPacket(a, schema, control.fixture.id, "review", packet, try read(a, "design/workflows/spec/support.prompt.md"));
        const model = @import("../domain/specification_support_model.zig");
        const requirements = try @import("../domain/specification_support_evidence.zig").requirements(a, prepared.inputs, prepared.context.inputs, assigned.finding.subject);
        const finding = try model.decode(a, try codec.encode(model.Value, a, switch (control.expected) {
            .supported => .{ .supported = .{ .source_ids = assigned.finding.source_ids, .detail = control.detail } },
            .unsupported => .{ .unsupported = .{ .source_ids = assigned.finding.source_ids, .detail = control.detail, .question = control.question.? } },
        }), requirements);
        const response = try model.encode(a, finding, requirements);
        const probe_id = try std.fmt.allocPrint(a, "{s}.probe", .{control.fixture.id});
        try reviewHandoff(a, schema, probe_id, 1, prepared, packet, response, null);
        const probe = try std.json.parseFromSliceLeaky(std.json.Value, a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.native-1.json", .{ output, probe_id })), .{});
        try std.testing.expect(!probe.object.get("admitted_omission").?.bool);
        try std.testing.expectEqualStrings(@tagName(control.expected), probe.object.get("finding").?.object.get("kind").?.string);
        for (1..3) |repetition| {
            try consumeReviewReceipt(a, schema, control.fixture.id, repetition, prepared, packet);
        }
        for ([_][]const u8{ "review.edit.json", "review.request.json" }) |suffix| try frozenCitationCompleteness(a, control.fixture.id, suffix);
    }
}

fn frozenCitationCompleteness(a: std.mem.Allocator, id: []const u8, suffix: []const u8) !void {
    const exported = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, id, suffix }));
    const frozen = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ root, id, suffix }));
    try std.testing.expectEqualStrings(frozen, exported);
}

fn reviewReceiptChecks(a: std.mem.Allocator, id: []const u8, prepared: Prepared, packet: *const packets.Packet, response: []const u8) !void {
    const request_bytes = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.request.json", .{ output, id }));
    const request_hash = try sha256(a, request_bytes);
    const parent = try @import("../domain/strict_json.zig").decode(ReviewParent, a, try read(a, root ++ "/handoff.parent.json"), .{ .maximum_depth = 8 });
    const receipt: ReviewReceipt = .{
        .input = packet.body(),
        .origin = .{
            .trial_id = try std.fmt.allocPrint(a, "{s}-review-1", .{id}),
            .parent_run = parent.run,
            .parent_call = parent.call,
            .replay_run = "MOCK replay run",
            .replay_id = "MOCK replay response",
            .request_sha256 = request_hash,
            .response_sha256 = try sha256(a, response),
        },
        .response_bytes = response,
    };
    const accepted = try admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, receipt, .{}));
    try std.testing.expectEqualStrings(response, accepted.response_bytes);
    try std.testing.expectEqualDeep(receipt.origin, accepted.origin);
    var prefixed = receipt;
    prefixed.response_bytes = try std.fmt.allocPrint(a, "{{\"{s}", .{response});
    prefixed.origin.response_sha256 = try sha256(a, prefixed.response_bytes);
    const accepted_prefix = try admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, prefixed, .{}));
    var changed = receipt;
    changed.input = "MOCK changed canonical subject or source evidence";
    try std.testing.expectError(error.InvalidCalibrationAssignment, admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    changed = receipt;
    changed.origin.request_sha256 = "MOCK changed request";
    try std.testing.expectError(error.InvalidCalibrationOrigin, admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    changed = receipt;
    changed.origin.replay_id = " ";
    try std.testing.expectError(error.InvalidCalibrationOrigin, admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    changed = receipt;
    changed.origin.parent_call = "MOCK unrelated source review call";
    try std.testing.expectError(error.InvalidCalibrationOrigin, admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    changed = receipt;
    changed.origin.response_sha256 = "MOCK changed response";
    try std.testing.expectError(error.InvalidCalibrationOrigin, admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, changed, .{})));
    try std.testing.expectError(error.InvalidCalibrationOrigin, admitReviewReceipt(a, id, 2, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, receipt, .{})));
    try std.testing.expectError(error.InvalidCalibrationOrigin, admitReviewReceipt(a, "MOCK other case", 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, receipt, .{})));
    var raw = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.json.Stringify.valueAlloc(a, receipt, .{}), .{});
    try raw.object.put(a, "unknown", .{ .bool = true });
    try std.testing.expectError(error.InvalidJsonDocument, admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, raw, .{})));
    _ = raw.object.orderedRemove("unknown");
    try raw.object.getPtr("origin").?.object.put(a, "unknown", .{ .bool = true });
    try std.testing.expectError(error.InvalidJsonDocument, admitReviewReceipt(a, id, 1, packet, parent, request_hash, try std.json.Stringify.valueAlloc(a, raw, .{})));
    // A real receipt's rejected model bytes remain an explicit admission result.
    const probe_id = try std.fmt.allocPrint(a, "{s}.malformed-probe", .{id});
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try read(a, "design/workflows/spec/support.schema.json"));
    const prefix_probe_id = try std.fmt.allocPrint(a, "{s}.prefix-probe", .{id});
    try reviewHandoff(a, schema, prefix_probe_id, 1, prepared, packet, accepted_prefix.response_bytes, accepted_prefix.origin);
    const prefix_report = try std.json.parseFromSliceLeaky(std.json.Value, a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.native-1.json", .{ output, prefix_probe_id })), .{});
    try std.testing.expect(prefix_report.object.get("admitted_omission").?.bool);
    try std.testing.expectEqualStrings("removed_leading_brace_quote", prefix_report.object.get("normalization").?.string);
    try std.testing.expectEqualStrings(prepared.pending.review.entries[prepared.pending.pending_localization.? - 1].value.missing_obligation.?, prefix_report.object.get("finding").?.object.get("missing_obligation").?.string);
    try reviewHandoff(a, schema, probe_id, 1, prepared, packet, "MOCK not JSON", receipt.origin);
    const report = try std.json.parseFromSliceLeaky(std.json.Value, a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.native-1.json", .{ output, probe_id })), .{});
    try std.testing.expectEqualStrings("rejected", report.object.get("result").?.string);
    try std.testing.expect(!report.object.get("admitted_omission").?.bool);
    try std.testing.expect(report.object.get("rejection").?.object.get("diagnostics").?.array.items.len != 0);
    try std.testing.expectEqualStrings(receipt.origin.replay_id, report.object.get("source_review_origin").?.object.get("replay_id").?.string);
}

fn isolationTrial(a: std.mem.Allocator, scope: IsolationScope, id: u32) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}-{s}-{d}-{d}", .{ scope.case_id, @tagName(scope.arm), id, scope.repetition });
}

fn isolationChecks(a: std.mem.Allocator, prepared: Prepared, assigned: comparison.Assignment, example: Case, requests: []const IsolationRequest, arm: Arm) !void {
    var mock = try @import("source_omission_evidence.zig").response(a, assigned, .{ .unlocalized = .{} });
    const assessments = try a.dupe(comparison.Assessment, mock.assessments);
    for (assessments, example.verdicts) |*assessment, verdict| assessment.result = verdict;
    mock.assessments = assessments;
    const scope: IsolationScope = .{ .case_id = example.id, .arm = arm, .repetition = 1, .requests = requests };
    const pieces = try a.alloc(IsolationPiece, assessments.len);
    for (pieces, assessments, requests) |*piece, assessment, request| piece.* = .{
        .comparison_id = assessment.comparison_id.ordinal,
        .origin = .{ .trial_id = try isolationTrial(a, scope, assessment.comparison_id.ordinal), .response_id = try std.fmt.allocPrint(a, "MOCK-response-{d}", .{assessment.comparison_id.ordinal}), .request_sha256 = request.request_sha256 },
        .response = try std.json.parseFromSliceLeaky(std.json.Value, a, try codec.encode(comparison.Response, a, .{ .assessments = &.{assessment} }), .{}),
    };
    const receipt: IsolationReceipt = .{ .assignment = assigned, .pieces = pieces };
    const accepted = try aggregateIsolation(a, prepared, scope, receipt);
    try std.testing.expectEqualStrings(example.expected, @tagName(comparison.location(accepted.admitted)));
    const encoded = try std.json.Stringify.valueAlloc(a, receipt, .{});
    const report = try isolationReport(a, prepared, scope, encoded);
    try write(a, example.id, try std.fmt.allocPrint(a, "{s}.probe-native.json", .{@tagName(arm)}), report);
    const decoded = try std.json.parseFromSliceLeaky(std.json.Value, a, report, .{});
    try std.testing.expectEqualStrings("admitted", decoded.object.get("status").?.string);
    try std.testing.expectEqual(pieces.len, decoded.object.get("origins").?.array.items.len);
    var wire = try std.json.parseFromSliceLeaky(std.json.Value, a, encoded, .{});
    try wire.object.put(a, "unknown", .{ .bool = true });
    try std.testing.expectError(error.InvalidJsonDocument, decodeIsolationReceipt(a, try std.json.Stringify.valueAlloc(a, wire, .{})));
    _ = wire.object.orderedRemove("unknown");
    const received = wire.object.get("pieces").?;
    _ = wire.object.orderedRemove("pieces");
    try std.testing.expectError(error.InvalidJsonDocument, decodeIsolationReceipt(a, try std.json.Stringify.valueAlloc(a, wire, .{})));
    try wire.object.put(a, "pieces", received);
    const raw_piece = &wire.object.getPtr("pieces").?.array.items[0].object;
    try raw_piece.put(a, "unknown", .{ .bool = true });
    try std.testing.expectError(error.InvalidJsonDocument, decodeIsolationReceipt(a, try std.json.Stringify.valueAlloc(a, wire, .{})));
    _ = raw_piece.orderedRemove("unknown");
    const raw_origin = &raw_piece.getPtr("origin").?.object;
    try raw_origin.put(a, "unknown", .{ .bool = true });
    try std.testing.expectError(error.InvalidJsonDocument, decodeIsolationReceipt(a, try std.json.Stringify.valueAlloc(a, wire, .{})));
    _ = raw_origin.orderedRemove("unknown");
    try raw_piece.getPtr("response").?.object.put(a, "unknown", .{ .bool = true });
    const malformed = try decodeIsolationReceipt(a, try std.json.Stringify.valueAlloc(a, wire, .{}));
    try std.testing.expectError(error.InvalidJsonDocument, aggregateIsolation(a, prepared, scope, malformed));
    var changed = receipt;
    changed.pieces = pieces[0 .. pieces.len - 1];
    const incomplete = try aggregateIsolation(a, prepared, scope, changed);
    try std.testing.expectEqual(@as(usize, 1), incomplete.incomplete.len);
    try std.testing.expectEqual(pieces[pieces.len - 1].comparison_id, incomplete.incomplete[0]);
    changed.assignment.finding.missing_obligation = "MOCK A different source obligation.";
    try std.testing.expectError(error.InvalidCalibrationAssignment, aggregateIsolation(a, prepared, scope, changed));
    changed = receipt;
    changed.assignment.finding.revision += 1;
    try std.testing.expectError(error.InvalidCalibrationAssignment, aggregateIsolation(a, prepared, scope, changed));
    changed = receipt;
    changed.assignment.facts.revision += 1;
    try std.testing.expectError(error.InvalidCalibrationAssignment, aggregateIsolation(a, prepared, scope, changed));
    changed = receipt;
    changed.assignment.finding.source_ids = &.{.{ .ordinal = 999 }};
    try std.testing.expectError(error.InvalidCalibrationAssignment, aggregateIsolation(a, prepared, scope, changed));
    changed = receipt;
    changed.assignment.facts.sources.corpus.state_id = .{ .bytes = "MOCK stale source state" };
    try std.testing.expectError(error.InvalidCalibrationAssignment, aggregateIsolation(a, prepared, scope, changed));
    const bad = try a.dupe(IsolationPiece, pieces);
    changed = .{ .assignment = assigned, .pieces = bad };
    bad[0].comparison_id = 999;
    try std.testing.expectError(error.InvalidCalibrationPiece, aggregateIsolation(a, prepared, scope, changed));
    bad[0] = pieces[0];
    bad[0].origin.response_id = " ";
    try std.testing.expectError(error.InvalidCalibrationOrigin, aggregateIsolation(a, prepared, scope, changed));
    bad[0] = pieces[0];
    bad[0].origin.request_sha256 = "MOCK changed request";
    try std.testing.expectError(error.InvalidCalibrationOrigin, aggregateIsolation(a, prepared, scope, changed));
    bad[0] = pieces[0];
    bad[0].origin.trial_id = try isolationTrial(a, .{ .case_id = "MOCK-other-case", .arm = arm, .repetition = 1, .requests = requests }, bad[0].comparison_id);
    try std.testing.expectError(error.InvalidCalibrationOrigin, aggregateIsolation(a, prepared, scope, changed));
    bad[0].origin.trial_id = try isolationTrial(a, .{ .case_id = example.id, .arm = arm, .repetition = 2, .requests = requests }, bad[0].comparison_id);
    try std.testing.expectError(error.InvalidCalibrationOrigin, aggregateIsolation(a, prepared, scope, changed));
    bad[0] = pieces[0];
    bad[0].response = try std.json.parseFromSliceLeaky(std.json.Value, a, "{\"assessments\":[]}", .{});
    try std.testing.expectError(error.InvalidCalibrationPiece, aggregateIsolation(a, prepared, scope, changed));
    bad[0].response = try std.json.parseFromSliceLeaky(std.json.Value, a, try codec.encode(comparison.Response, a, .{ .assessments = &.{ assessments[0], assessments[0] } }), .{});
    try std.testing.expectError(error.InvalidCalibrationPiece, aggregateIsolation(a, prepared, scope, changed));
    var foreign = assessments[0];
    foreign.comparison_id.ordinal = 999;
    bad[0].response = try std.json.parseFromSliceLeaky(std.json.Value, a, try codec.encode(comparison.Response, a, .{ .assessments = &.{foreign} }), .{});
    try std.testing.expectError(error.InvalidCalibrationPiece, aggregateIsolation(a, prepared, scope, changed));
    // Old response members are unknown fields, even if empty or otherwise valid.
    bad[0].response = try std.json.parseFromSliceLeaky(std.json.Value, a, try codec.encode(comparison.Response, a, .{ .assessments = &.{assessments[0]} }), .{});
    try bad[0].response.object.getPtr("assessments").?.array.items[0].object.put(a, "members", .{ .array = std.json.Array.init(a) });
    try std.testing.expectError(error.InvalidJsonDocument, aggregateIsolation(a, prepared, scope, changed));
    foreign = assessments[0];
    const spans = try a.dupe(comparison.Span, foreign.sources);
    spans[0].chunk_id = .{ .bytes = "MOCK foreign source chunk" };
    foreign.sources = spans;
    bad[0].response = try std.json.parseFromSliceLeaky(std.json.Value, a, try codec.encode(comparison.Response, a, .{ .assessments = &.{foreign} }), .{});
    try std.testing.expectError(error.InvalidPreservationComparison, aggregateIsolation(a, prepared, scope, changed));
    changed.pieces = &.{ pieces[0], pieces[0] };
    try std.testing.expectError(error.InvalidCalibrationPiece, aggregateIsolation(a, prepared, scope, changed));
    if (pieces.len > 1) {
        @memcpy(bad, pieces);
        changed.pieces = bad;
        std.mem.reverse(IsolationPiece, bad);
        const reordered = try aggregateIsolation(a, prepared, scope, changed);
        try std.testing.expectEqualStrings(example.expected, @tagName(comparison.location(reordered.admitted)));
        @memcpy(bad, pieces);
        bad[1].origin.response_id = bad[0].origin.response_id;
        try std.testing.expectError(error.InvalidCalibrationOrigin, aggregateIsolation(a, prepared, scope, changed));
        bad[1] = pieces[1];
        bad[1].origin.trial_id = bad[0].origin.trial_id;
        try std.testing.expectError(error.InvalidCalibrationOrigin, aggregateIsolation(a, prepared, scope, changed));
    }
}
