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
const root = "test/calibration/source-loss-attribution/bound-preservation/native-scope";
const output = ".zig-cache/source-loss-native-scope";
const isolation_root = "test/calibration/source-loss-attribution/bound-preservation/isolation";
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
    const cases = try codec.decode([]const Case, a, try read(a, cases_root ++ "/cases.json"));
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try read(a, "design/workflows/spec/support.schema.json"));
    try runNativeScope(a, schema, cases);
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
        const finding = if (admitted) |candidate| if (candidate.review.entries.len >= ordinal) candidate.review.entries[ordinal - 1].value else null else null;
        try write(a, id, suffix, try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = false, .result = tag, .finding = finding }, .{}));
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
    return writeAt(a, output, id, suffix, bytes);
}
fn writeAt(a: std.mem.Allocator, directory: []const u8, id: []const u8, suffix: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ directory, id, suffix }), .data = bytes });
}

// Isolation is a diagnostic projection, not a second production loss-review
// implementation. The complete native assignment and admission stay unchanged.
const IsolationOrigin = struct { trial_id: []const u8, response_id: []const u8, request_sha256: []const u8 };
const IsolationRequest = struct { comparison_id: u32, request_sha256: []const u8 };
const IsolationScope = struct { case_id: []const u8, repetition: usize, requests: []const IsolationRequest };
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

fn runNativeScope(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, cases: []const Case) !void {
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    const prompt = try read(a, "design/workflows/spec/support-loss.prompt.md");
    for (cases) |example| {
        const prepared = try prepare(a, example);
        defer prepared.passive.deinit();
        const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
        const packet = try support.packetForLoss(a, prepared.inputs, prepared.context, prepared.pending);
        defer packets.release(packet);
        const full = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
        try std.testing.expectEqualStrings(example.missing_obligation, assigned.finding.missing_obligation);
        try std.testing.expectEqual(example.verdicts.len, assigned.comparisons.len);
        try write(a, example.id, "packet.json", try std.json.Stringify.valueAlloc(a, .{ .assignment = assigned, .input = full }, .{}));
        const requests = try a.alloc(IsolationRequest, assigned.comparisons.len);
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
            const arm = try std.fmt.allocPrint(a, "candidate-{d}", .{view.id.ordinal});
            try exportBodyAt(a, output, schema, example.id, arm, isolated, body, prompt);
            // Frozen old requests are historical experiment inputs, never a
            // second reader or a production compatibility contract.
            for ([_][]const u8{ "edit.json", "request.json" }) |kind| {
                const baseline = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.candidate-{d}.{s}", .{ isolation_root, example.id, view.id.ordinal, kind }));
                try write(a, example.id, try std.fmt.allocPrint(a, "baseline-{d}.{s}", .{ view.id.ordinal, kind }), baseline);
                if (std.mem.eql(u8, kind, "edit.json")) {
                    const edit = try std.json.parseFromSliceLeaky(std.json.Value, a, baseline, .{});
                    const content = edit.object.get("content").?.array.items;
                    try std.testing.expectEqualStrings(body, content[1].object.get("user").?.string);
                }
            }
            const request_bytes = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}.request.json", .{ output, example.id, arm }));
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(request_bytes, &digest, .{});
            request.* = .{ .comparison_id = view.id.ordinal, .request_sha256 = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower)) };
        }
        try isolationChecks(a, prepared, assigned, example, requests);
        const review_packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = assigned.finding.subject });
        defer packets.release(review_packet);
        try exportPacket(a, schema, example.id, "review", review_packet, try read(a, "design/workflows/spec/support.prompt.md"));
        const probe_id = try std.fmt.allocPrint(a, "{s}.probe", .{example.id});
        const selected = prepared.pending.review.entries[prepared.pending.pending_localization.? - 1].value;
        const requirements = try @import("../domain/specification_support_evidence.zig").requirements(a, prepared.inputs, prepared.context.inputs, assigned.finding.subject);
        const review_response = try @import("../domain/specification_support_model.zig").encode(a, selected, requirements);
        try reviewHandoff(a, schema, probe_id, 1, prepared, review_packet, review_response);
        const probe = try std.json.parseFromSliceLeaky(std.json.Value, a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.native-1.json", .{ output, probe_id })), .{});
        try std.testing.expect(probe.object.get("admitted_omission").?.bool);
        try std.testing.expectEqualStrings(example.missing_obligation, probe.object.get("finding").?.object.get("missing_obligation").?.string);
        for (1..3) |repetition| {
            if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.candidate.receipt-{d}.json", .{ output, example.id, repetition }))) |bytes|
                try write(a, example.id, try std.fmt.allocPrint(a, "candidate.native-{d}.json", .{repetition}), try isolationReport(a, prepared, .{ .case_id = example.id, .repetition = repetition, .requests = requests }, bytes));
            // Actual review responses are admitted before loss input creation;
            // the oracle missing_obligation is never substituted for live text.
            if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.review.response-{d}.json", .{ output, example.id, repetition }))) |bytes|
                try reviewHandoff(a, schema, example.id, repetition, prepared, review_packet, bytes);
        }
    }
    try prepareHandoffControls(a, schema);
    for (cases) |example| {
        const prepared = try prepare(a, example);
        defer prepared.passive.deinit();
        const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
        try frozenNativeScope(a, example.id, "packet.json");
        for ([_][]const u8{ "review.edit.json", "review.request.json" }) |suffix| try frozenNativeScope(a, example.id, suffix);
        for (assigned.comparisons) |view| for ([_][]const u8{ "baseline", "candidate" }) |arm| for ([_][]const u8{ "edit.json", "request.json" }) |kind| {
            try frozenNativeScope(a, example.id, try std.fmt.allocPrint(a, "{s}-{d}.{s}", .{ arm, view.id.ordinal, kind }));
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
    const controls = try codec.decode([]const Control, a, try read(a, root ++ "/handoff.controls.json"));
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
        try reviewHandoff(a, schema, probe_id, 1, prepared, packet, response);
        const probe = try std.json.parseFromSliceLeaky(std.json.Value, a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.native-1.json", .{ output, probe_id })), .{});
        try std.testing.expect(!probe.object.get("admitted_omission").?.bool);
        try std.testing.expectEqualStrings(@tagName(control.expected), probe.object.get("finding").?.object.get("kind").?.string);
        for (1..3) |repetition| {
            if (try optional(a, try std.fmt.allocPrint(a, "{s}/{s}.review.response-{d}.json", .{ output, control.fixture.id, repetition }))) |bytes|
                try reviewHandoff(a, schema, control.fixture.id, repetition, prepared, packet, bytes);
        }
        for ([_][]const u8{ "review.edit.json", "review.request.json" }) |suffix| try frozenNativeScope(a, control.fixture.id, suffix);
    }
}

fn frozenNativeScope(a: std.mem.Allocator, id: []const u8, suffix: []const u8) !void {
    const exported = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ output, id, suffix }));
    const frozen = try read(a, try std.fmt.allocPrint(a, "{s}/{s}.{s}", .{ root, id, suffix }));
    try std.testing.expectEqualStrings(frozen, exported);
}

fn isolationTrial(a: std.mem.Allocator, scope: IsolationScope, id: u32) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}-candidate-{d}-{d}", .{ scope.case_id, id, scope.repetition });
}

fn isolationChecks(a: std.mem.Allocator, prepared: Prepared, assigned: comparison.Assignment, example: Case, requests: []const IsolationRequest) !void {
    var mock = try @import("source_omission_evidence.zig").response(a, assigned, .{ .unlocalized = .{} });
    const assessments = try a.dupe(comparison.Assessment, mock.assessments);
    for (assessments, example.verdicts) |*assessment, verdict| assessment.result = verdict;
    mock.assessments = assessments;
    const scope: IsolationScope = .{ .case_id = example.id, .repetition = 1, .requests = requests };
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
    try write(a, example.id, "candidate.probe-native.json", report);
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
    bad[0].origin.trial_id = try isolationTrial(a, .{ .case_id = "MOCK-other-case", .repetition = 1, .requests = requests }, bad[0].comparison_id);
    try std.testing.expectError(error.InvalidCalibrationOrigin, aggregateIsolation(a, prepared, scope, changed));
    bad[0].origin.trial_id = try isolationTrial(a, .{ .case_id = example.id, .repetition = 2, .requests = requests }, bad[0].comparison_id);
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
