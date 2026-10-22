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
const provenance = @import("../domain/specification_provenance.zig");
const spec = @import("../domain/specification.zig");
const codec = @import("../domain/model_candidate_json.zig");
const packets = @import("../domain/model_input_packet.zig");
const cases_root = "test/calibration/source-loss-attribution/bound-preservation/obligation";
const root = "test/calibration/source-loss-attribution/bound-preservation/citation-completeness";
// Current contract preparation is separate from the retained historical panel.
// Old receipts are neither overwritten nor read through the new text contract.
const output = ".zig-cache/source-loss-citation-completeness-current-contract";
const Arm = enum { baseline, candidate };
pub const Case = struct {
    id: []const u8,
    cohort: enum { development, unused },
    sources: []const []const u8,
    claims: []const struct { source: u32, text: []const u8, first: u32, last: u32 },
    description: []const u8,
    missing: []const u8,
    missing_obligation: []const u8,
    mode: enum { candidate, signal },
    grouping: enum { combined, per_claim, per_source },
    /// Scripted authoring selection over this fixture's explicitly built groups.
    source_group_ids: []const u32,
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
    const retained = try codec.decode([]const Case, a, try read(a, cases_root ++ "/cases.associated.json"));
    const controls = try codec.decode([]const Case, a, try read(a, root ++ "/citation.controls.associated.json"));
    const cases = try a.alloc(Case, retained.len + controls.len);
    @memcpy(cases[0..retained.len], retained);
    @memcpy(cases[retained.len..], controls);
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try read(a, "design/workflows/spec/support.schema.json"));
    try runCitationCompleteness(a, schema, cases);
}

/// Current calibration fixtures cross the same closed association boundary as
/// production; historical unassociated payloads cannot acquire native lineage.
fn currentAssociationChecks(a: std.mem.Allocator, example: Case) !void {
    var legacy = try std.json.parseFromSliceLeaky(std.json.Value, a, try codec.encode(Case, a, example), .{});
    try std.testing.expect(legacy.object.orderedRemove("source_group_ids"));
    try std.testing.expectError(error.InvalidJsonDocument, codec.decode(Case, a, try std.json.Stringify.valueAlloc(a, legacy, .{})));
    const prepared = try prepareContext(a, example);
    defer prepared.passive.deinit();
    const field = prepared.brief.description;
    const p = @import("../domain/specification_provenance.zig");
    const records = @import("../domain/reference_support.zig").records(prepared.context.references);
    const current = try p.validateAssociation(.canonical, a, prepared.context.inputs, records, field.source_group_ids, field.provenance, .content);
    defer a.free(current);
    try std.testing.expectEqualDeep(field.source_group_ids, current);
    try std.testing.expectError(error.InvalidSpecification, p.validateAssociation(.canonical, a, prepared.context.inputs, records, &.{.{ .ordinal = 999 }}, field.provenance, .content));
    try std.testing.expectError(error.InvalidSpecification, p.validateAssociation(.canonical, a, prepared.context.inputs, records, &.{}, field.provenance, .content));
}

pub fn read(a: std.mem.Allocator, path: []const u8) ![]const u8 {
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
pub fn exportBodyAt(a: std.mem.Allocator, directory: []const u8, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, arm: []const u8, packet: *const packets.Packet, body: []const u8, prompt: []const u8) !void {
    const rendered = try renderBody(a, schema, packet, body, prompt);
    try writeAt(a, directory, id, try std.fmt.allocPrint(a, "{s}.edit.json", .{arm}), rendered.edit);
    try writeAt(a, directory, id, try std.fmt.allocPrint(a, "{s}.request.json", .{arm}), rendered.request);
}

/// Shared diagnostic projection through the production restriction and provider
/// encoder. Neither a packet builder nor a dispatch/admission authority.
pub const RenderedRequest = struct { edit: []const u8, request: []const u8 };
pub fn renderBody(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, packet: *const packets.Packet, body: []const u8, prompt: []const u8) !RenderedRequest {
    return renderContent(a, schema, packet, &.{ .{ .guidance = prompt }, .{ .user = body } });
}

/// Preserve every production-visible guidance block for diagnostic exports.
/// The caller supplies current native packet metadata; no send is authorized.
pub fn renderContent(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, packet: *const packets.Packet, content: []const @import("../domain/llm_provider_operation.zig").ModelVisibleContent) !RenderedRequest {
    const restricted = try @import("../domain/model_result_schema.zig").restrict(a, schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    const bytes = try std.json.Stringify.valueAlloc(a, .{ .content = content, .schema = restricted.selected().modelBytes() }, .{});
    return .{ .edit = bytes, .request = try encodeEdit(a, try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{})) };
}

/// Historical presentation only. Removing this one field cannot make a prior
/// replay receipt current, nor does it change the production packet or schema.
pub fn baselineReviewBody(a: std.mem.Allocator, packet: *const packets.Packet) ![]const u8 {
    var body = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
    var removed = body.object.orderedRemove("assessment_scope");
    for (body.object.getPtr("requirements").?.array.items) |*member| {
        removed = member.object.orderedRemove("assessment_scope") or removed;
    }
    try std.testing.expect(removed);
    return std.json.Stringify.valueAlloc(a, body, .{});
}

fn exportHistoricalReview(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, packet: *const packets.Packet) !void {
    try exportBody(a, schema, id, "review", packet, try baselineReviewBody(a, packet), try read(a, "test/calibration/source-review-scope/baseline.prompt.md"));
}
fn reviewHandoff(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, id: []const u8, repetition: usize, prepared: Prepared, packet: *const packets.Packet, bytes: []const u8, origin: ?ReviewOrigin) !void {
    const ordinal = prepared.pending.pending_localization.?;
    var prior = prepared.pending;
    prior.pending_localization = null;
    prior.review.entries = prior.review.entries[0 .. ordinal - 1];
    prior.origins = prior.origins[0 .. ordinal - 1];
    const envelope = @import("../domain/model_envelope.zig");
    var syntax_diagnostic: ?envelope.SyntaxDiagnostic = null;
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
pub const ReviewOrigin = struct {
    trial_id: []const u8,
    parent_run: []const u8,
    parent_call: []const u8,
    replay_run: []const u8,
    replay_id: []const u8,
    request_sha256: []const u8,
    response_sha256: []const u8,
};
pub const ReviewReceipt = struct { input: []const u8, origin: ReviewOrigin, response_bytes: []const u8 };
pub const ReviewParent = struct { run: []const u8, call: []const u8 };
const ReviewReceiptError = @import("../domain/strict_json.zig").Error || error{ InvalidCalibrationAssignment, InvalidCalibrationOrigin };
pub fn admitReviewReceipt(a: std.mem.Allocator, id: []const u8, repetition: usize, packet: *const packets.Packet, parent: ReviewParent, expected_request_sha256: []const u8, bytes: []const u8) ReviewReceiptError!ReviewReceipt {
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
    const current = try renderBody(a, schema, packet, packet.body(), try read(a, "design/workflows/spec/support.prompt.md"));
    if (!std.mem.eql(u8, current.request, request_bytes)) {
        // Old receipts stay recorded historical evidence. Do not supply their
        // missing scope or classify them as current production admission.
        const historical_path = try std.fmt.allocPrint(a, "{s}/{s}.review.native-{d}.json", .{ output, id, repetition });
        const historical = try optional(a, historical_path);
        const receipt_hash = try sha256(a, bytes);
        try write(a, id, try std.fmt.allocPrint(a, "review.current-scope-rejection-{d}.json", .{repetition}), try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = false, .result = "rejected_receipt", .rejection = "ObsoleteCalibrationScope", .native_origin_available = false }, .{}));
        if (historical) |retained| try std.testing.expectEqualStrings(retained, try read(a, historical_path));
        try std.testing.expectEqualStrings(receipt_hash, try sha256(a, try read(a, try std.fmt.allocPrint(a, "{s}/{s}.review.receipt-{d}.json", .{ output, id, repetition }))));
        return;
    }
    const parent = try @import("../domain/strict_json.zig").decode(ReviewParent, a, try read(a, root ++ "/handoff.parent.json"), .{ .maximum_depth = 8 });
    const receipt = admitReviewReceipt(a, id, repetition, packet, parent, try sha256(a, request_bytes), bytes) catch |err| {
        if (err == error.OutOfMemory) return err;
        try write(a, id, try std.fmt.allocPrint(a, "review.native-{d}.json", .{repetition}), try std.json.Stringify.valueAlloc(a, .{ .admitted_omission = false, .result = "rejected_receipt", .rejection = @errorName(err), .native_origin_available = false }, .{}));
        return;
    };
    try reviewHandoff(a, schema, id, repetition, prepared, packet, receipt.response_bytes, receipt.origin);
}
pub fn sha256(a: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}
pub const PreparedContext = struct {
    inputs: authority.Inputs,
    context: @import("../domain/specification_provenance.zig").Context,
    /// Independently admitted diagnostic data. Its presence does not invent a
    /// complete generated candidate or change a source-readiness projection.
    brief: spec.Brief,
    passive: text.Prepared,
};

/// Diagnostic current native scope only. Original occurrences and semantic
/// evidence remain separate from the one eligible equal-byte representative.
pub fn writeExactScope(a: std.mem.Allocator, directory: []const u8, id: []const u8, prepared: PreparedContext) !void {
    const records = @import("../domain/reference_support.zig").records(prepared.context.references);
    const Original = struct { claim: r.extraction.Claim, disposition: r.ClaimDisposition };
    var originals: std.ArrayList(Original) = .empty;
    for (records.items.entries, records.dispositions) |item, disposition| if (item.claim.content == .preserved_token) try originals.append(a, .{ .claim = item.claim, .disposition = disposition });
    try writeAt(a, directory, id, "native-exact-scope.json", try std.json.Stringify.valueAlloc(a, .{
        .reference_state = records.items.state_id,
        .original_token_occurrences = originals.items,
        .eligible_exact_occurrences = try provenance.exactOccurrences(a, records, null),
        .admitted_brief = prepared.brief,
        .semantic_evidence = false,
        .model_calls = @as(usize, 0),
    }, .{}));
}
/// Current diagnostic candidates are admitted through the production owner;
/// frozen captured text supplies no pre-existing canonical exact authority.
pub fn admitAttributed(a: std.mem.Allocator, context: provenance.Context, value: spec.AttributedValue, field: @import("../domain/text_field_policy.zig").Field) !spec.AttributedValue {
    var inspection: provenance.Inspection = .{};
    return provenance.inspectAttributed(.model, a, text.validator, context, .{
        .value = try provenance.modelValue(a, @import("../domain/reference_support.zig").records(context.references), value.value),
        .source_group_ids = value.source_group_ids,
        .provenance = .{ .claim_ids = value.provenance.claim_ids, .clarification_response_ids = value.provenance.clarification_response_ids },
    }, field, &inspection) catch |err| {
        if (inspection.text_issue) |issue| switch (issue.reason) {
            .ambiguous_exact => return error.AmbiguousCalibrationExactValue,
            .embedded_insertion_syntax => return error.EmbeddedCalibrationInsertionSyntax,
            else => {},
        };
        return err;
    };
}

pub fn admitBrief(a: std.mem.Allocator, context: provenance.Context, brief: spec.Brief) !spec.Brief {
    return .{
        .title = try admitAttributed(a, context, brief.title, .spec_title),
        .description = try admitAttributed(a, context, brief.description, .spec_description),
        .primary_goal = try admitAttributed(a, context, brief.primary_goal, .spec_goal),
    };
}

pub fn admitContent(a: std.mem.Allocator, context: provenance.Context, content: spec.IdentifiedContent) !spec.IdentifiedContent {
    var result = content;
    result.display_name = try admitAttributed(a, context, content.display_name, .spec_title);
    result.primary_user_story = try admitAttributed(a, context, content.primary_user_story, .spec_story);
    result.entities.basis = try admitAttributed(a, context, content.entities.basis, .spec_entity_basis);
    const records = try a.dupe(spec.IdentifiedRecord, content.records);
    for (records) |*record| {
        const value = record.proposal;
        var inspection: provenance.Inspection = .{};
        record.proposal = provenance.inspectRecord(.model, a, text.validator, context, .{
            .content = try provenance.modelRecord(a, @import("../domain/reference_support.zig").records(context.references), value.content),
            .source_group_ids = value.source_group_ids,
            .provenance = .{ .claim_ids = value.provenance.claim_ids, .clarification_response_ids = value.provenance.clarification_response_ids },
        }, &inspection) catch |err| {
            if (inspection.text_issue) |issue| switch (issue.reason) {
                .ambiguous_exact => return error.AmbiguousCalibrationExactValue,
                .embedded_insertion_syntax => return error.EmbeddedCalibrationInsertionSyntax,
                else => {},
            };
            return err;
        };
    }
    result.records = records;
    return result;
}

/// A current native admission rejection is a measured negative case, never an
/// omitted panel row or a fabricated review request. Frozen inputs stay intact.
pub const AdmissionReason = enum { ambiguous_exact, embedded_insertion_syntax };
pub const AdmissionRejection = struct { case_id: []const u8, reason: AdmissionReason };
pub fn admissionReason(err: anyerror) ?AdmissionReason {
    return switch (err) {
        error.AmbiguousCalibrationExactValue => .ambiguous_exact,
        error.EmbeddedCalibrationInsertionSyntax => .embedded_insertion_syntax,
        else => null,
    };
}
pub fn writeAdmissionRejection(a: std.mem.Allocator, directory: []const u8, rejection: AdmissionRejection) !void {
    try writeAt(a, directory, rejection.case_id, "native-admission.json", try std.json.Stringify.valueAlloc(a, .{
        .case_id = rejection.case_id,
        .stage = @as(enum { pre_review }, .pre_review),
        .native_issue = rejection.reason,
        .review_request = @as(?[]const u8, null),
        .model_calls = @as(usize, 0),
    }, .{}));
}
pub const Unavailable = struct { case_id: []const u8, reason: enum { incomplete_candidate } = .incomplete_candidate };
pub fn writeUnavailable(a: std.mem.Allocator, directory: []const u8, value: Unavailable) !void {
    try writeAt(a, directory, value.case_id, "unavailable.json", try std.json.Stringify.valueAlloc(a, .{ .case_id = value.case_id, .reason = value.reason, .current_admission = false, .model_calls = @as(usize, 0) }, .{}));
}

pub const Focus = struct { prior: ?support.Collection, packet: *packets.Packet };
pub const SelectedReview = struct { target: authority.Id, value: @import("../domain/specification_support_model.zig").Value };

/// Reach the actual complete native assignment containing the target. Mock
/// siblings supply no semantic proof or provider-operation origin.
pub fn focus(a: std.mem.Allocator, prepared: PreparedContext, target: authority.Id) !Focus {
    var prior: ?support.Collection = null;
    while (true) {
        const first = try support.nextSubject(a, prepared.inputs, prior);
        const packet = try support.packetFor(a, prepared.inputs, prepared.context, support.assignmentScope(prepared.inputs, first));
        errdefer packets.release(packet);
        const assigned = try support.assignmentSubjects(a, prepared.inputs, first);
        const contains = for (assigned) |id| {
            if (std.meta.eql(id, target)) break true;
        } else false;
        if (contains) return .{ .prior = prior, .packet = packet };
        const next = try support.collectFocused(a, prepared.inputs, prepared.context, prior, packet, try reviewResponse(a, prepared, packet, null), null);
        if (next != .pending) return error.InvalidCalibrationPrefix;
        packets.release(packet);
        prior = next;
    }
}

/// Populate exactly the request's native ordinals. An optional selected value
/// stays unchanged; all other values are explicitly scripted diagnostic data.
pub fn reviewResponse(a: std.mem.Allocator, prepared: PreparedContext, packet: *const packets.Packet, selected: ?SelectedReview) ![]const u8 {
    const ledger = try authority.build(a, prepared.inputs);
    const input = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
    const assigned = input.object.get("requirements").?.array.items;
    var findings: std.ArrayList(std.json.Value) = .empty;
    var single: ?[]const u8 = null;
    for (assigned) |requirement| {
        const ordinal = std.math.cast(u32, requirement.object.get("ordinal").?.integer) orelse return error.InvalidCalibrationTarget;
        if (ordinal == 0 or ordinal > ledger.requirements.len) return error.InvalidCalibrationTarget;
        const id = ledger.requirements[ordinal - 1].seed.id;
        const rules = try @import("../domain/specification_support_evidence.zig").requirements(a, prepared.inputs, prepared.context.inputs, id);
        const bytes = if (selected != null and std.meta.eql(selected.?.target, id)) try codec.encode(@import("../domain/specification_support_model.zig").Value, a, selected.?.value) else try mockPrefix(a, rules);
        single = bytes;
        var finding: std.json.ObjectMap = .{};
        try finding.put(a, "requirement_ordinal", .{ .integer = ordinal });
        try finding.put(a, "value", try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{}));
        try findings.append(a, .{ .object = finding });
    }
    if (!std.mem.eql(u8, packet.resultDefinition().?.bytes, "assignment_findings")) return single orelse error.InvalidCalibrationTarget;
    var result: std.json.ObjectMap = .{};
    try result.put(a, "findings", .{ .array = std.array_list.Managed(std.json.Value).fromOwnedSlice(a, try findings.toOwnedSlice(a)) });
    return std.json.Stringify.valueAlloc(a, std.json.Value{ .object = result }, .{});
}

const Prepared = struct {
    inputs: authority.Inputs,
    context: @import("../domain/specification_provenance.zig").Context,
    pending: support.Candidate,
    passive: text.Prepared,
};
pub fn prepareContext(a: std.mem.Allocator, example: Case) !PreparedContext {
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
    if (example.grouping == .per_claim) {
        for (proposed.signals) |signal| if (signal.content == .model) try groups.append(a, signal);
    } else if (example.grouping == .per_source) {
        // This mock topology has one explicit group per supplied source. It
        // never becomes a production claims-to-group selection algorithm.
        for (sources.corpus.sources) |source| {
            var members: std.ArrayList(r.ClaimId) = .empty;
            var meaning: std.ArrayList(u8) = .empty;
            for (global.items) |item| if (std.meta.eql(item.source_id, source.id) and item.claim.content == .model) {
                try members.append(a, item.claim.id);
                for (item.claim.content.model.business.value.segments) |segment| try meaning.appendSlice(a, segment.literal.value);
                try meaning.append(a, ' ');
            };
            if (members.items.len == 0) return error.MissingCalibrationSource;
            try groups.append(a, .{ .claim_ids = members.items, .content = .{ .model = .{ .business = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = meaning.items } }}) } } } });
        }
    } else {
        try groups.append(a, .{ .claim_ids = business.items, .content = .{ .model = .{ .business = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = example.signal_text orelse (if (example.mode == .signal) example.description else combined.items) } }}) } } } });
    }
    for (proposed.signals) |signal| if (signal.content == .preserved_token) try groups.append(a, signal);
    proposed.signals = groups.items;
    const finished = (try refs.finish(a, global, proposed, context)).valid;
    const provenance_context: @import("../domain/specification_provenance.zig").Context = .{ .inputs = sources, .references = finished, .registry = context.registry, .current = context.current };
    const records = @import("../domain/reference_support.zig").records(finished);
    const ids_selected = try a.alloc(r.SignalId, example.source_group_ids.len);
    for (example.source_group_ids, ids_selected) |id, *selected| selected.* = .{ .ordinal = id };
    const assigned = try @import("../domain/specification_source_binding.zig").resolveGroups(a, records, sources, ids_selected, .content);
    const attribution = try @import("../domain/specification_provenance.zig").select(a, provenance_context, assigned.selection);
    const value: spec.AttributedValue = .{ .value = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = example.description } }}) }, .source_group_ids = assigned.source_group_ids, .provenance = attribution };
    var brief: spec.Brief = .{ .title = value, .description = value, .primary_goal = value };
    var candidate: ?spec.IdentifiedContent = null;
    if (example.candidate_file) |path| {
        const captured = try @import("../domain/strict_json.zig").decode(struct { brief: spec.Brief, candidate: spec.IdentifiedContent }, a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .unlimited), .{ .maximum_depth = 128 });
        brief = captured.brief;
        candidate = try admitContent(a, provenance_context, captured.candidate);
        brief = try admitBrief(a, provenance_context, brief);
        try @import("../domain/specification_provenance.zig").validateStored(a, sources, .{ .records = passive.registry.records, .occurrences = passive.registry.occurrences }, records, brief, candidate.?);
    } else brief = try admitBrief(a, provenance_context, brief);
    const inputs = try @import("../domain/specification_authority.zig").project(a, sources.corpus.feature_id, finished, candidate, if (candidate != null) brief else null);
    return .{ .inputs = inputs, .context = provenance_context, .brief = brief, .passive = passive };
}

/// A diagnostic prefix cannot invent an authored association. Absent canonical
/// fields remain explicitly inconclusive; these mock siblings are not live proof.
pub fn mockPrefix(a: std.mem.Allocator, rules: @import("../domain/specification_support_evidence.zig").Requirements) ![]const u8 {
    const model = @import("../domain/specification_support_model.zig");
    const positive = rules.rule(.supported, .{ .unlocalized = .{} });
    const bound = if (positive.fixedClaims()) |claims| claims.len != 0 or (rules.source_preservation and positive.eligible_source_ids.len != 0) else false;
    return codec.encode(model.Value, a, if (bound)
        .{ .supported = .{ .source_ids = rules.eligible_source_ids, .detail = "MOCK Bound prior source review for isolated diagnostic preparation; no semantic evidence." } }
    else
        .{ .inconclusive = .{ .source_ids = rules.eligible_source_ids, .detail = "MOCK Unauthored prior subject; no source association or semantic proof is invented." } });
}

fn prepare(a: std.mem.Allocator, example: Case) !Prepared {
    const prepared = try prepareContext(a, example);
    errdefer prepared.passive.deinit();
    const inputs = prepared.inputs;
    if (example.mode != .signal or authority.assessmentPolicy(inputs.projection) != .required) return error.InvalidCalibrationAssignment;
    const provenance_context = prepared.context;
    const sources = provenance_context.inputs;
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
        const selected = try mockPrefix(a, rules);
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
    return .{ .inputs = inputs, .context = provenance_context, .pending = pending, .passive = prepared.passive };
}

fn encodeEdit(a: std.mem.Allocator, edit: std.json.Value) ![]const u8 {
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = try parser.compiler().compile(a, edit.object.get("schema").?.string);
    const content = try @import("../domain/strict_json.zig").decode([]const @import("../domain/llm_provider_operation.zig").ModelVisibleContent, a, try std.json.Stringify.valueAlloc(a, edit.object.get("content").?, .{}), .{ .maximum_depth = 64 });
    return @import("../adapters/provider/bedrock_request.zig").encodeText(a, .{
        .content = content,
        .schema = .{ .native = .{ .guidance = compiled.modelBytes(), .structure = try @import("../domain/model_schema_projection.zig").render(a, compiled, .native) } },
        .schema_name = "sdde_model_envelope_v1",
        .temperature = .fixed,
        .reasoning_effort = .low,
        .family = .@"gpt-oss",
        .max_output_tokens = try catalogueMaximum(a),
    }, .inference);
}
/// The shipped test catalogue owns the GPT-OSS maximum output (ADR 0011). The
/// production decode, registry build and validation read it, so this projection
/// cannot drift from it or accept an entry the engine would refuse.
fn catalogueMaximum(a: std.mem.Allocator) !@import("../domain/llm_provider_contracts.zig").ModelMaximumOutput {
    const registered = &@import("../composition/provider_model_contracts.zig").registry;
    var catalogue = try (@import("../actions/provider/decode_llm_provider_config.zig").Action{}).execute(a, try read(a, "test/e2e/config/.sddproviders.json"));
    defer catalogue.deinit();
    var candidate = try (@import("../actions/provider/build_llm_provider_registry.zig").Action{ .contracts = registered }).execute(a, catalogue.value());
    defer candidate.deinit();
    const registry = @import("../domain/llm_provider_registry.zig");
    const owner = try (@import("../actions/provider/validate_llm_provider_registry.zig").Action{ .contracts = registered }).execute(a, candidate);
    defer registry.deinitOwner(owner);
    const entry = registry.registry(owner).resolve(.{ .bytes = "aws-bedrock" }, .{ .bytes = "openai.gpt-oss-20b-1:0" }) orelse return error.InvalidCalibrationCatalogue;
    return switch (entry.config) {
        .aws_bedrock => |config| config.max_output_tokens,
        .empty_object, .anthropic => error.InvalidCalibrationCatalogue,
    };
}
fn write(a: std.mem.Allocator, id: []const u8, suffix: []const u8, bytes: []const u8) !void {
    return writeAt(a, output, id, suffix, bytes);
}
pub fn writeAt(a: std.mem.Allocator, directory: []const u8, id: []const u8, suffix: []const u8, bytes: []const u8) !void {
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

fn runCitationCompleteness(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema, cases: []const Case) !void {
    try std.Io.Dir.cwd().createDirPath(std.testing.io, output);
    const prompt = try read(a, "design/workflows/spec/support-loss.prompt.md");
    var admission_rejections: std.ArrayList(AdmissionRejection) = .empty;
    var unavailable: std.ArrayList(Unavailable) = .empty;
    var prepared_cases: usize = 0;
    var advisory_cases: usize = 0;
    var pre_generation_cases: usize = 0;
    for (cases) |example| {
        const current = prepareContext(a, example) catch |err| {
            const rejection: AdmissionRejection = .{ .case_id = example.id, .reason = admissionReason(err) orelse return err };
            try admission_rejections.append(a, rejection);
            try writeAdmissionRejection(a, output, rejection);
            continue;
        };
        defer current.passive.deinit();
        if (example.mode == .candidate and current.inputs.specification == null) {
            const missing: Unavailable = .{ .case_id = example.id };
            try unavailable.append(a, missing);
            try writeUnavailable(a, output, missing);
            continue;
        }
        prepared_cases += 1;
        try writeExactScope(a, output, example.id, current);
        if (prepared_cases == 1) try currentAssociationChecks(a, example);
        if (authority.assessmentPolicy(current.inputs.projection) == .advisory) {
            advisory_cases += 1;
            const target: authority.Id = .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = if (example.target == .primary_user_story) .primary_user_story else .description };
            try advisoryProbe(a, example.id, current, target, .{ .candidate_omission = .{ .source_ids = try sourceIds(a, current), .detail = example.missing, .missing_obligation = example.missing_obligation } });
            continue;
        }
        pre_generation_cases += 1;
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
        try exportHistoricalReview(a, schema, example.id, review_packet);
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
    // The encoded insertion remains rejected. Equal-byte token identity now
    // admits dual-ready's brief, but no complete frozen candidate exists, so it
    // remains explicitly unavailable rather than acquiring fabricated content.
    try std.testing.expectEqualDeep(@as([]const AdmissionRejection, &.{
        .{ .case_id = "captured-description", .reason = .embedded_insertion_syntax },
    }), admission_rejections.items);
    try std.testing.expectEqual(@as(usize, 1), advisory_cases);
    try std.testing.expectEqual(@as(usize, 1), pre_generation_cases);
    try std.testing.expectEqual(@as(usize, 10), unavailable.items.len);
    try std.testing.expectEqual(cases.len, prepared_cases + admission_rejections.items.len + unavailable.items.len);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = output ++ "/native-admission.json", .data = try std.json.Stringify.valueAlloc(a, .{
        .input_cases = cases.len,
        .prepared_cases = prepared_cases,
        .current_advisory_cases = advisory_cases,
        .current_pre_generation_comparisons = pre_generation_cases,
        .pre_review_rejections = admission_rejections.items,
        .unavailable_cases = unavailable.items,
        .historical_panel = "Unchanged. Candidate labels lacking a complete native candidate are not reinterpreted as pre-generation judgments.",
        .model_calls = @as(usize, 0),
    }, .{}) });
    try prepareHandoffControls(a, schema);
}

fn sourceIds(a: std.mem.Allocator, prepared: PreparedContext) ![]const r.extraction.identity.SourceId {
    const result = try a.alloc(r.extraction.identity.SourceId, prepared.context.inputs.corpus.sources.len);
    for (prepared.context.inputs.corpus.sources, result) |source, *id| id.* = source.id;
    return result;
}

fn advisoryProbe(a: std.mem.Allocator, id: []const u8, prepared: PreparedContext, target: authority.Id, value: @import("../domain/specification_support_model.zig").Value) !void {
    const focused = try focus(a, prepared, target);
    defer packets.release(focused.packet);
    const bytes = try reviewResponse(a, prepared, focused.packet, .{ .target = target, .value = value });
    const result = try support.collectFocused(a, prepared.inputs, prepared.context, focused.prior, focused.packet, bytes, null);
    const candidate = switch (result) {
        .pending => |candidate| candidate,
        .accepted => |accepted| accepted.candidate,
        .rejected => return error.InvalidCalibrationAdvice,
    };
    try std.testing.expect(candidate.pending_localization == null);
    try std.testing.expectError(error.InvalidRequiredAuthority, support.packetForLoss(a, prepared.inputs, prepared.context, candidate));
    const ledger = try authority.build(a, prepared.inputs);
    const selected = for (ledger.requirements, 0..) |required, index| {
        if (std.meta.eql(required.seed.id, target)) break candidate.review.entries[index].value;
    } else return error.InvalidCalibrationTarget;
    try std.testing.expect(selected.preservation == null and selected.loss == .unlocalized);
    if (value == .candidate_omission) {
        try std.testing.expectEqualStrings(value.candidate_omission.missing_obligation, selected.missing_obligation.?);
        try std.testing.expectEqualStrings(value.candidate_omission.detail, selected.detail);
        try std.testing.expectEqualDeep(value.candidate_omission.source_ids, selected.source_ids);
    }
    try write(a, id, "current-advisory.json", try std.json.Stringify.valueAlloc(a, .{ .mock = true, .semantic_evidence = false, .current_assignment = focused.packet.body(), .response = bytes, .finding = selected, .pending_localization = false, .loss_request = @as(?[]const u8, null), .publication_authority = false, .model_calls = @as(usize, 0) }, .{}));
}

fn prepareHandoffControls(a: std.mem.Allocator, schema: *const @import("../domain/model_result_schema.zig").Schema) !void {
    const Control = struct {
        expected: enum { supported, unsupported },
        detail: []const u8,
        question: ?[]const u8,
        fixture: Case,
    };
    const controls = try codec.decode([]const Control, a, try read(a, root ++ "/handoff.controls.associated.json"));
    for (controls) |control| {
        if (control.fixture.mode == .candidate and control.fixture.candidate_file == null) {
            try writeUnavailable(a, output, .{ .case_id = control.fixture.id });
            continue;
        }
        const prepared = try prepare(a, control.fixture);
        defer prepared.passive.deinit();
        const assigned = try support.comparisonAssignment(a, prepared.inputs, prepared.context, prepared.pending);
        const packet = try support.packetFor(a, prepared.inputs, prepared.context, .{ .finding = assigned.finding.subject });
        defer packets.release(packet);
        try exportHistoricalReview(a, schema, control.fixture.id, packet);
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
    }
}

fn reviewReceiptChecks(a: std.mem.Allocator, id: []const u8, prepared: Prepared, packet: *const packets.Packet, response: []const u8) !void {
    var parser: @import("../adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try read(a, "design/workflows/spec/support.schema.json"));
    const current = try renderBody(a, schema, packet, packet.body(), try read(a, "design/workflows/spec/support.prompt.md"));
    const request_bytes = current.request;
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
