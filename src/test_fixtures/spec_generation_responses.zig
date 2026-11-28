//! Shared scripted provider candidate data. No workflow execution or test loop.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const values = @import("../application/pipeline_values.zig");
const definitions = @import("../domain/specification_result_definitions.zig");
const r = @import("../domain/reference_reconciliation.zig");
const g = @import("../domain/specification_generation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const a = @import("../domain/required_authority.zig");
pub const ReconciliationFault = enum { summary_membership, duplicate_disposition, self_relation, cycle, signal_coverage, mixed_selection, conflict_coverage, summary_text, signal_text, conflict_text, occupied_summary, occupied_signals, occupied_conflict, permuted_disposition, permuted_conflict_disposition, misbound_summary, misbound_signals };
pub const SupportFault = enum { foreign_source_single };
// Semantic outcomes remain scripted candidates, not native semantic proof.
pub const Applicability = enum {
    unjustified,
    no_entities,
    entities,
    missing_decision,
    missing_text,
    inconclusive,

    pub fn source(self: Applicability, other: bool) []const u8 {
        return switch (self) {
            .entities => if (other) "Track customer invoices and display the outstanding balance." else "Track library loans and display their return deadlines.",
            .missing_decision, .missing_text => if (other) "Display a sensor reading; whether it is calculated on request or read from managed records is undecided." else "Display a status value; whether it is calculated on request or read from managed records is undecided.",
            else => if (other) "Calculate a checksum and display the digest and elapsed time." else "On startup display the greeting and the current UTC date and time.",
        };
    }
};
pub const applicability_detail = "The source requires a displayed value. Its origin is undecided; the choice determines whether business records and their fields are required.";
pub const applicability_question = "Should the displayed value be calculated on request or read from managed records? Answer calculate, or records with their required fields.";

/// `two_false_conflicts` holds two conflicts that share no claim, each between a chunk's two claims and each judged
/// false, so the source review's repair of one is followed by a repair of the other. `overlapping_false_conflict` holds a
/// genuine conflict between the first two model claims and a false one between the second and the third: they share the
/// second claim, so the review judges the first record `conflicting` and the second `candidate_omission`, and the repair of
/// the second decides the third claim alone.
pub const SourceLoss = enum { empty, partial, classification, signal, unchanged, false_conflict, unchanged_conflict, false_conflict_questions, two_false_conflicts, overlapping_false_conflict };
/// Scripted edge cases (ADR 0038 Decision 7). `native` writes one for each model claim, beside the
/// one criterion the engine writes for the claim's requirement. `chosen` groups two claims in each
/// signal and writes one edge case per group naming both, beside the two criteria the engine
/// writes for them, so the model decides. `unlinked` names the claim of every group after the first
/// only in an edge case: no requirement names it, so no criterion can serve the edge case.
pub const EdgeCases = enum { native, chosen, unlinked };
fn falseConflict(mode: ?SourceLoss) bool {
    return mode == .false_conflict or mode == .unchanged_conflict or mode == .false_conflict_questions or mode == .two_false_conflicts or mode == .overlapping_false_conflict;
}

/// The conflicts a scripted reconciliation holds, as positions in model-claim order: the first two claims, for two
/// conflicts that share none the next two as well, and for an overlapping pair the second and the third.
fn conflictPairs(options: Options) []const [2]usize {
    if (options.overlapping_conflicts) return &.{ .{ 0, 1 }, .{ 1, 2 } };
    return switch (options.source_loss orelse .empty) {
        .two_false_conflicts => &.{ .{ 0, 1 }, .{ 2, 3 } },
        .overlapping_false_conflict => &.{ .{ 0, 1 }, .{ 1, 2 } },
        else => &.{.{ 0, 1 }},
    };
}

/// Whether one accepted conflict group holds both claims of a scripted conflict.
fn groupHolds(groups: []const @import("../domain/reference_conflict_groups.zig").Group, pair: []const r.ClaimId) bool {
    for (groups) |group| if (r.contains(r.ClaimId, group.claim_ids, pair[0]) and r.contains(r.ClaimId, group.claim_ids, pair[1])) return true;
    return false;
}

/// The kinds of restating record the scripted runs offer. The story comparison (ADR 0038 Decision 5) deletes any single-statement
/// kind but a functional requirement, which is never deleted as a restatement; these are two of them.
pub const RestatingKind = enum { business_rule, non_goal };

pub const Options = struct {
    /// The reconciliation holds one conflict between the first two business claims, and its source review raises it.
    /// A rerun with the claims retained reconciles them again: the engine applies any answer.
    conflict: bool = false,
    /// With `conflict`, the reconciliation holds a second conflict between the second and third model claims, so the two
    /// share the second, and the source review judges each `conflicting`: both raise a form, as a model that declares an
    /// overlapping pair and judges both genuine does.
    overlapping_conflicts: bool = false,
    /// The extraction files every claim as an open question rather than a business claim, as a model may file two lines that
    /// contradict each other.
    open_question_claims: bool = false,
    global_sequence: ?@import("global_protocol_sequence.zig").Mode = null,
    summary_sequence: ?@import("summary_protocol_sequence.zig").Mode = null,
    disposition_sequence: ?enum { recover, exhaust } = null,
    attempt: u32 = 1,
    /// The attempts the compiled workflow allows the request being answered (its step's retry limit plus
    /// the first attempt). The summary and global sequences answer wrongly until their last allowed attempt.
    allowance: ?u32 = null,
    source_loss: ?SourceLoss = null,
    support_fault: ?SupportFault = null,
    applicability: ?Applicability = null,
    source_gaps: bool = false,
    evidence_fault: ?enum { recover, empty_correction } = null,
    /// The records response omits every functional requirement.
    candidate_omissions: bool = false,
    /// The records response states each claim as an outcome and writes no functional requirement,
    /// so its groups have scenario slots while the mandatory requirement family is missing.
    behaviour_without_requirement: bool = false,
    /// The first group's records name the first claim the story quotes in no functional requirement.
    /// A record of this kind states the story's own text for it, ahead of an outcome naming the same
    /// claim, so the story comparison decides which of the two the batch keeps: ADR 0038 Decision 5
    /// would keep the first and delete the outcome. The group needs a second claim, which keeps its requirement.
    story_restatement: ?RestatingKind = null,
    /// The first chunk's extraction answer states no feature claim, giving a reason the text validation
    /// rejects (a control character, which response admission accepts), so the reference-text repair route
    /// runs and its answer fixes the reason. Every other chunk answers as usual.
    defective_reason: bool = false,
    extraction_omission: bool = false,
    reconciliation_repair_fault: ?enum { unchanged, alternating, unchanged_text } = null,
    reconciliation_fault: ?ReconciliationFault = null,
    uncertain: bool = false,
    /// The brief's description and primary goal.
    brief_text: ?[2][]const u8 = null,
    repair: bool = false,
    repeated_provenance_fault: bool = false,
    repair_across_units: bool = false,
    failed_repair: bool = false,
    omit_exact: bool = false,
    missing_classifications: bool = false,
    failed_classification_repair: bool = false,
    entities_required: bool = false,
    contradict_entities: bool = false,
    generation_gap: bool = false,
    edge_cases: ?EdgeCases = null,
    /// The first scenario of each group's first scenarios answer has a text defect, which the
    /// field-level repair fixes (ADR 0038 Decision 3).
    scenario_defect: bool = false,
    /// Every scenario of a scenarios answer omits its Given, as one may where the sources state no starting
    /// situation for the requirement (ADR 0038 Decision 3). The edge cases a records answer writes keep theirs.
    scenarios_without_given: bool = false,
};

pub fn build(allocator: std.mem.Allocator, view: data.View, options: Options) ![]const u8 {
    const request = try requests.readCurrent(&view, requests.prepared_schema);
    return partResponse(allocator, request, try completeResponse(allocator, view, options));
}

fn completeResponse(allocator: std.mem.Allocator, view: data.View, options: Options) ![]const u8 {
    const request = try requests.readCurrent(&view, requests.prepared_schema);
    switch (request.id().immutable_unit_owner_id) {
        .reference_chunk => |scope| {
            const inputs = (try values.read(&view, @import("../application/reference_evidence_workflow.zig").inputs_schema, r.evidence.Inputs)).*;
            const selected_chunk = try r.evidence.resolve(inputs, .{ .state_id = .{ .bytes = scope.reference_state_id.bytes }, .chunk_id = .{ .bytes = scope.chunk_id.bytes } });
            const chunk = selected_chunk.chunk;
            const candidates = (try values.read(&view, @import("../application/structured_token_workflow.zig").candidates_schema, r.extraction.tokens.Candidates)).*;
            if (request.id().purpose == .atomic_repair) {
                if (view.contains(.reference_text_repair_authorization)) return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/reference_extraction_text_repair.zig").Replacement, allocator, .{ .reference = .{ .nodes = &.{.{ .literal = .{ .value = "The text only tells the reader to read a file." } }} } });
                if (view.contains(.source_omission_repair)) {
                    const state = try @import("../application/source_omission_repair_workflow.zig").read(&view);
                    if (state.authorization.extraction.target == .classification) {
                        const id = state.authorization.extraction.operation.replace.classification.id();
                        return @import("../domain/model_candidate_json.zig").encode(r.extraction.tokens.Classification, allocator, .{ .preserve = .{ .token_candidate_id = id, .kind = if (id.extractor_id == .markdown_fenced_code_v1) .code_sample else .business_exact_string } });
                    }
                    // Cite only the last line, a quote distinct from the whole-chunk claim.
                    const lines = try @import("../reference_extraction_test.zig").citableLines(allocator, inputs, chunk);
                    return @import("../domain/model_candidate_json.zig").encode(r.extraction.Proposal, allocator, .{ .category = .business, .citations = lines[lines.len - 1 ..] });
                }
                const choices = if (options.failed_classification_repair) &.{} else try @import("reference_tokens.zig").classifications(allocator, candidates, chunk);
                return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/reference_extraction_repair.zig").Replacement, allocator, .{ .classifications = .{ .token_classifications = choices } });
            }
            if (options.defective_reason and chunk.id.eql(inputs.chunks.entries[0].id)) {
                const choices = try @import("reference_tokens.zig").classifications(allocator, candidates, chunk);
                const discarded = try allocator.alloc(@import("../domain/structured_tokens.zig").Classification, choices.len);
                for (choices, discarded) |choice, *decision| decision.* = .{ .irrelevant = choice.id() };
                // A control character passes response admission and fails the text validation (invalid scalar).
                const reply = try @import("../domain/model_candidate_json.zig").encode(@import("../domain/reference_extraction_parser.zig").Response, allocator, .{ .no_feature_claim = .{ .reason = .{ .nodes = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} }, .token_classifications = &.{} } });
                return @import("reference_tokens.zig").wire(allocator, reply, discarded);
            }
            if (options.extraction_omission or options.source_loss == .empty) {
                const choices = try @import("reference_tokens.zig").classifications(allocator, candidates, chunk);
                const discarded = try allocator.alloc(@import("../domain/structured_tokens.zig").Classification, choices.len);
                for (choices, discarded) |choice, *decision| decision.* = .{ .irrelevant = choice.id() };
                // A protocol-valid correction abandons the source task.
                const reply = try @import("../domain/model_candidate_json.zig").encode(@import("../domain/reference_extraction_parser.zig").Response, allocator, .{ .no_feature_claim = .{ .reason = .{ .nodes = &.{.{ .literal = .{ .value = "The rejected response JSON has a syntax error in its claims array." } }} }, .token_classifications = &.{} } });
                return @import("reference_tokens.zig").wire(allocator, reply, discarded);
            }
            const mixed_kinds = options.summary_sequence != null or options.global_sequence != null or options.disposition_sequence != null or options.reconciliation_fault == .mixed_selection;
            // The claim quotes every citable line of its chunk (ADR 0036). A
            // classification loss leaves the token's final line unquoted.
            const lines = try @import("../reference_extraction_test.zig").citableLines(allocator, inputs, chunk);
            const cited = if (options.source_loss == .classification) lines[0 .. lines.len - 1] else lines;
            const body = try @import("../domain/model_candidate_json.zig").encode(@import("../domain/reference_extraction_parser.zig").Response, allocator, .{ .claims = .{ .claims = &.{.{ .category = if (options.open_question_claims) .open_question else .business, .citations = cited }}, .token_classifications = &.{} } });
            // Native correlation faults need two eligible semantic kinds;
            // selecting an exact-token ID is now rejected by the wire schema.
            if (falseConflict(options.source_loss) or (mixed_kinds and chunk.id.eql(inputs.chunks.entries[0].id))) {
                const response_type = @import("../domain/reference_extraction_parser.zig").Response;
                var response = try @import("../domain/model_candidate_json.zig").decode(response_type, allocator, body);
                const claims = try allocator.alloc(r.extraction.Proposal, 2);
                claims[0] = response.claims.claims[0];
                // A line cited under two categories is corrected at admission (ADR 0036 Decision 7), so the
                // second kind cites the first line alone and the first claim keeps the rest.
                if (claims[0].citations.len < 2) return error.InvalidFixture;
                claims[1] = .{ .category = .technical, .citations = claims[0].citations[0..1] };
                claims[0].citations = claims[0].citations[1..];
                response.claims.claims = claims;
                response.claims.token_classifications = try @import("reference_tokens.zig").classifications(allocator, candidates, chunk);
                return @import("../domain/model_candidate_json.zig").encode(response_type, allocator, response);
            }
            const choices = try allocator.dupe(r.extraction.tokens.Classification, try @import("reference_tokens.zig").classifications(allocator, candidates, chunk));
            if (options.source_loss == .classification) for (choices) |*choice| {
                choice.* = .{ .irrelevant = choice.id() };
            };
            return @import("reference_tokens.zig").wire(allocator, body, if (options.missing_classifications) &.{} else choices);
        },
        .reference_global => {
            const reconciliation = @import("../application/reference_reconciliation_workflow.zig");
            const input = (try native.read(&view, reconciliation.input_schema, .reconciliation_input)).payload().reconciliation_input;
            if (request.id().purpose == .atomic_repair) {
                const repair = @import("../domain/reference_reconciliation_repair.zig");
                if (view.contains(.source_omission_repair)) {
                    const auth = (try @import("../application/source_omission_repair_workflow.zig").read(&view)).authorization.reconciliation;
                    if (options.source_loss == .unchanged or options.source_loss == .unchanged_conflict) return @import("reference_reconciliation.zig").repairResponse(allocator, auth.operation.replace);
                    if (auth.target == .conflict_group) {
                        const dispositions = try allocator.dupe(r.ClaimDispositionProposal, auth.operation.replace.conflict_group.claim_dispositions);
                        for (dispositions) |*value| value.disposition = .{ .retained = .{} };
                        return @import("reference_reconciliation.zig").repairResponse(allocator, .{ .conflict_group = .{ .claim_dispositions = dispositions, .conflicts = &.{} } });
                    }
                    const claim = (try r.item(input.progress.plan.layout.items, auth.dependencies.reconciliation.proposal.global.signals[auth.target.unit.signal_content].claim_ids[0])).claim;
                    return @import("reference_reconciliation.zig").repairResponse(allocator, .{ .content = @import("reference_reconciliation.zig").content(claim) });
                }
                const authorization = try @import("../application/reference_reconciliation_repair_workflow.zig").readAuthorization(&view);
                if (options.reconciliation_repair_fault) |fault| {
                    if (fault == .unchanged_text) return @import("reference_reconciliation.zig").repairResponse(allocator, authorization.operation.replace);
                    const target = authorization.target.disposition;
                    const replacement: repair.Replacement = if (fault == .alternating and options.attempt % 2 == 0)
                        .{ .disposition = .{ .duplicate = .{ .target_claim_id = .{ .ordinal = 999999 } } } }
                    else
                        .{ .disposition = .{ .superseded = .{ .related_claim_ids = &.{target.claim} } } };
                    return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, replacement);
                }
                // Selection answers consume the actual request's native choices.
                // They do not infer missing guidance from hidden fixture state.
                if (authorization.target == .signal_selection or authorization.target == .statement_selection) {
                    const packet = try values.read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet);
                    const input_json = try std.json.parseFromSlice(std.json.Value, allocator, packet.body(), .{});
                    const choices = input_json.value.object.get("repair").?.object.get("rule").?.object.get("selection").?;
                    var selected: std.array_list.Managed(std.json.Value) = .init(allocator);
                    for (choices.array.items) |choice| if (r.contains(r.ClaimId, authorization.operation.replace.selection.claim_ids, .{ .ordinal = @intCast(choice.integer) })) try selected.append(choice);
                    if (selected.items.len == 0 and choices.array.items.len != 0) try selected.append(choices.array.items[0]);
                    return std.json.Stringify.valueAlloc(allocator, .{ .claim_ids = std.json.Value{ .array = selected } }, .{});
                }
                const replacement: repair.Replacement = switch (authorization.target) {
                    .statement_content => |index| .{ .content = @import("reference_reconciliation.zig").content((try r.item(input.progress.plan.layout.items, authorization.dependencies.proposal.summary.statements[index].claim_ids[0])).claim) },
                    .signal_content => |index| .{ .content = @import("reference_reconciliation.zig").content((try r.item(input.progress.plan.layout.items, authorization.dependencies.proposal.global.signals[index].claim_ids[0])).claim) },
                    .conflict_summary => .{ .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The supplied assertions disagree." } }} } },
                    .insert_statement => |target| .{ .content = @import("reference_reconciliation.zig").content((try r.item(input.progress.plan.layout.items, target.claim)).claim) },
                    .insert_signal => |target| .{ .content = @import("reference_reconciliation.zig").content((try r.item(input.progress.plan.layout.items, target.claim)).claim) },
                    .disposition => .{ .disposition = .{ .retained = .{} } },
                    .insert_conflict => .{ .conflict_detail = .{ .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The supplied claims state conflicting outcomes." } }} } } },
                    else => return error.UnexpectedScriptedRepair,
                };
                return @import("reference_reconciliation.zig").repairResponse(allocator, replacement);
            }
            if (input.purpose == .summary) {
                if (options.global_sequence != null) return @import("summary_protocol_sequence.zig").response(allocator, input, if (input.progress.summary_count == 0 or options.attempt > 1) options.allowance.? else 1, options.allowance.?, .recover);
                if (options.summary_sequence) |mode| return @import("summary_protocol_sequence.zig").response(allocator, input, options.attempt, options.allowance.?, mode);
                var proposal = try @import("reference_reconciliation.zig").summary(allocator, input);
                if (options.reconciliation_fault == .misbound_summary and input.progress.summary_count == 0 and options.attempt == 1) {
                    const statements = try allocator.alloc(r.StatementProposal, proposal.statements.len + 1);
                    @memcpy(statements[0..proposal.statements.len], proposal.statements);
                    const extra = try misboundProjection(r.StatementProposal, proposal.statements);
                    statements[proposal.statements.len] = .{ .claim_ids = extra.claim_ids, .content = extra.content };
                    proposal.statements = statements;
                }
                if (options.reconciliation_fault == .occupied_summary and options.attempt == 1) {
                    const statements = try allocator.alloc(r.StatementProposal, proposal.statements.len + 1);
                    @memcpy(statements[0..proposal.statements.len], proposal.statements);
                    statements[proposal.statements.len] = .{ .claim_ids = &.{}, .content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different proposed meaning." } }} } } } };
                    proposal.statements = statements;
                }
                if (options.reconciliation_fault == .summary_membership) proposal.statements = proposal.statements[1..];
                if (options.reconciliation_fault == .summary_text and input.progress.summary_count == 0) {
                    const statements = try allocator.dupe(r.StatementProposal, proposal.statements);
                    statements[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } };
                    proposal.statements = statements;
                }
                return @import("reference_reconciliation.zig").modelWire(allocator, .{ .summary = proposal });
            }
            var proposal = try @import("reference_reconciliation.zig").global(allocator, input);
            if (options.edge_cases == .chosen) proposal.signals = try pairedSignals(allocator, proposal.signals);
            const disposition_claims = try dispositionClaims(allocator, request, input);
            var semantic_dispositions: std.ArrayList(r.ClaimDispositionProposal) = .empty;
            for (proposal.claim_dispositions) |entry| if (r.contains(r.ClaimId, disposition_claims, entry.claim_id)) try semantic_dispositions.append(allocator, entry);
            proposal.claim_dispositions = semantic_dispositions.items;
            const accepted = if (view.contains(.validated_reference_dispositions)) (try native.read(&view, reconciliation.dispositions_schema, .reconciliation_dispositions)).payload().reconciliation_dispositions else null;
            // Later phase responses follow accepted repairs, rather than
            // reintroducing the initial scripted relationship defect.
            if ((falseConflict(options.source_loss) or options.conflict) and (accepted == null or accepted.?.proposal.conflict_groups.len != 0)) {
                // Each conflict is a pair of model claims, in claim order: the first two and, for two conflicts, the next
                // two. A later phase holds the pairs the accepted groups still hold, so it follows an accepted repair of
                // one pair and keeps the other.
                const pairs = conflictPairs(options);
                var needed: usize = 0;
                for (pairs) |pair| needed = @max(needed, @max(pair[0], pair[1]) + 1);
                const claims = try allocator.alloc(r.ClaimId, needed);
                var count: usize = 0;
                for (input.progress.plan.layout.items.entries) |item| if (item.claim.content == .model and count < claims.len) {
                    claims[count] = item.claim.id;
                    count += 1;
                };
                if (count != claims.len) return error.InvalidConflictFixture;
                const dispositions = try allocator.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
                var held: std.ArrayList(r.ClaimId) = .empty;
                var conflicts: std.ArrayList(r.ConflictProposal) = .empty;
                for (pairs) |positions| {
                    const pair = try allocator.dupe(r.ClaimId, &.{ claims[positions[0]], claims[positions[1]] });
                    if (accepted) |checked| if (!groupHolds(checked.proposal.conflict_groups, pair)) continue;
                    // A claim two conflicts share is related to the other claim of each.
                    for (dispositions) |*value| for (pair, 0..) |claim, side| if (std.meta.eql(value.claim_id, claim)) {
                        var related: std.ArrayList(r.ClaimId) = .empty;
                        if (value.disposition == .conflicting) try related.appendSlice(allocator, value.disposition.conflicting.related_claim_ids);
                        try related.append(allocator, pair[1 - side]);
                        value.disposition = .{ .conflicting = .{ .related_claim_ids = try related.toOwnedSlice(allocator) } };
                    };
                    for (pair) |claim| if (!r.contains(r.ClaimId, held.items, claim)) try held.append(allocator, claim);
                    try conflicts.append(allocator, .{ .claim_ids = pair, .kind = .mutually_exclusive, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The source behavior and its presentation." } }} } });
                }
                proposal.claim_dispositions = dispositions;
                var signals: std.ArrayList(r.SignalProposal) = .empty;
                for (proposal.signals) |signal| if (!r.contains(r.ClaimId, held.items, signal.claim_ids[0])) {
                    try signals.append(allocator, signal);
                };
                proposal.signals = try signals.toOwnedSlice(allocator);
                proposal.conflicts = try conflicts.toOwnedSlice(allocator);
            }
            if (options.global_sequence != null) proposal = try @import("global_protocol_sequence.zig").mixed(allocator, input, proposal);
            if (options.disposition_sequence != null) {
                if (disposition_claims.len < 2) return error.InvalidReconciliationFixture;
                if (options.attempt == 1) {
                    const token = for (input.progress.plan.layout.items.entries) |item| {
                        if (item.claim.content == .preserved_token) break item.claim.id;
                    } else return error.InvalidReconciliationFixture;
                    const signals = try allocator.dupe(r.SignalProposal, proposal.signals);
                    const selected = for (signals) |*signal| {
                        if (signal.content == .model) break signal;
                    } else return error.InvalidReconciliationFixture;
                    // Token membership is native, so this initial selector is
                    // a protocol fault. The correction restores every original
                    // semantic signal rather than inventing mixed-kind content.
                    selected.claim_ids = try std.mem.concat(allocator, r.ClaimId, &.{ selected.claim_ids, &.{token} });
                    proposal.signals = signals;
                }
                // The first correction still omits claims: admission
                // corrects the whole assignment again, which recovers or exhausts.
                if (options.attempt == 2 or (options.attempt > 2 and options.disposition_sequence == .exhaust)) proposal.claim_dispositions = proposal.claim_dispositions[0..1];
                return @import("reference_reconciliation.zig").modelWire(allocator, .{ .global = proposal });
            }
            if (options.source_loss == .signal or options.source_loss == .unchanged) {
                const signals = try allocator.dupe(r.SignalProposal, proposal.signals);
                signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Incomplete signal." } }} } } };
                proposal.signals = signals;
            }
            if (options.reconciliation_fault) |fault| {
                const dispositions = try allocator.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
                proposal.claim_dispositions = dispositions;
                switch (fault) {
                    .summary_membership, .summary_text, .occupied_summary, .misbound_summary => {},
                    .misbound_signals => if (options.attempt == 1) {
                        const signals = try allocator.alloc(r.SignalProposal, proposal.signals.len + 1);
                        @memcpy(signals[0..proposal.signals.len], proposal.signals);
                        signals[proposal.signals.len] = try misboundProjection(r.SignalProposal, proposal.signals);
                        proposal.signals = signals;
                    },
                    .occupied_signals => if (options.attempt == 1) {
                        const signals = try allocator.alloc(r.SignalProposal, proposal.signals.len + 1);
                        @memcpy(signals[0..proposal.signals.len], proposal.signals);
                        signals[proposal.signals.len] = .{ .claim_ids = &.{}, .content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different proposed meaning." } }} } } } };
                        proposal.signals = signals;
                    },
                    .permuted_disposition, .permuted_conflict_disposition => {
                        const duplicate = try allocator.alloc(r.ClaimDispositionProposal, dispositions.len + 1);
                        @memcpy(duplicate[0..dispositions.len], dispositions);
                        const related = try allocator.dupe(r.ClaimId, &.{ dispositions[1].claim_id, dispositions[2].claim_id });
                        duplicate[0].disposition = .{ .superseded = .{ .related_claim_ids = related } };
                        if (fault == .permuted_conflict_disposition) {
                            duplicate[0].disposition = .{ .conflicting = .{ .related_claim_ids = related } };
                            duplicate[1].disposition = .{ .conflicting = .{ .related_claim_ids = try allocator.dupe(r.ClaimId, &.{dispositions[0].claim_id}) } };
                            duplicate[2].disposition = duplicate[1].disposition;
                            proposal.signals = proposal.signals[3..];
                            const conflicts = try allocator.alloc(r.ConflictProposal, 2);
                            for (related, conflicts) |id, *conflict| conflict.* = .{ .claim_ids = try allocator.dupe(r.ClaimId, &.{ dispositions[0].claim_id, id }), .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The supplied outcomes differ." } }} } };
                            proposal.conflicts = conflicts;
                        }
                        duplicate[dispositions.len] = duplicate[0];
                        const reversed = try allocator.dupe(r.ClaimId, &.{ related[1], related[0] });
                        if (fault == .permuted_conflict_disposition) duplicate[dispositions.len].disposition.conflicting.related_claim_ids = reversed else duplicate[dispositions.len].disposition.superseded.related_claim_ids = reversed;
                        // A repeated record is an admission defect: the
                        // correction returns the same meaning without the repeat.
                        proposal.claim_dispositions = if (options.attempt == 1) duplicate else duplicate[0..dispositions.len];
                    },
                    .mixed_selection => proposal = try @import("global_protocol_sequence.zig").mixed(allocator, input, proposal),
                    .signal_text => {
                        const signals = try allocator.dupe(r.SignalProposal, proposal.signals);
                        signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } };
                        proposal.signals = signals;
                    },
                    .duplicate_disposition => if (options.attempt == 1) {
                        dispositions[1] = dispositions[0];
                    },
                    .self_relation => {
                        dispositions[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
                    },
                    .cycle => {
                        dispositions[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[1].claim_id} } };
                        dispositions[1].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
                    },
                    .signal_coverage => proposal.signals = proposal.signals[1..],
                    .conflict_coverage, .conflict_text, .occupied_conflict => {
                        dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[1].claim_id} } };
                        dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
                        proposal.signals = proposal.signals[2..];
                        // An omitted group is an admission defect (ADR 0022, amended 25 November 2026): the correction
                        // returns the group's explanation.
                        proposal.conflicts = if (fault == .conflict_coverage and options.attempt == 1) &.{} else &.{.{ .claim_ids = &.{ dispositions[0].claim_id, dispositions[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = if (fault == .conflict_coverage) "The outcomes differ." else "Invalid\x01text" } }} } }};
                        if (fault == .occupied_conflict) {
                            const conflicts = try allocator.dupe(r.ConflictProposal, &.{ proposal.conflicts[0], proposal.conflicts[0] });
                            conflicts[0].summary = .{ .nodes = &.{.{ .literal = .{ .value = "The outcomes differ." } }} };
                            conflicts[1].summary = .{ .nodes = &.{.{ .literal = .{ .value = "The conditions differ." } }} };
                            conflicts[1].claim_ids = &.{};
                            proposal.conflicts = conflicts;
                        }
                    },
                }
            }
            return @import("reference_reconciliation.zig").modelWire(allocator, .{ .global = proposal });
        },
        .specification_unit => {
            // An edge case's outcome link: the model names the last criterion it is offered for the
            // first pending edge case, the first for the next, and so on, so a run proves the engine
            // used each answer for its own edge case, not a default candidate.
            if (request.packet()) |packet| if (packet.resultDefinition()) |definition| if (definitions.Links.parse(definition) == .scenario_link) {
                const offered = packet.integerChoices()[0].allowed;
                const earlier = (try @import("../application/scenario_link_workflow.zig").chosen(&view)).len;
                return std.fmt.allocPrint(allocator, "{{\"criterion\":{d}}}", .{if (earlier % 2 == 0) offered[offered.len - 1] else offered[0]});
            };
            const current = try @import("../application/specification_workflow.zig").readSession(&view);
            // The one batch whose records restate the story and keep their own claims.
            const restating_batch = options.story_restatement != null and current.record_cursor == 0;
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const provenance = @import("../domain/specification_provenance.zig");
            const references = @import("../domain/reference_support.zig").records(context.references);
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const dispositions = @import("../domain/reference_support.zig").records(context.references).dispositions;
            const first = for (dispositions) |disposition| {
                if (@import("../domain/reference_support.zig").eligibleClaim(disposition.disposition) and (try r.item(all, disposition.claim_id)).claim.content == .model and (try businessValue(allocator, (try r.item(all, disposition.claim_id)).claim, options)) != null) break disposition.claim_id;
            } else return error.InvalidFixture;
            const value = try withoutExact(allocator, options, try attributed(allocator, options, all, &.{first}));
            if (request.id().purpose == .atomic_repair) {
                if (view.contains(.specification_repair_authorization)) {
                    const state = try @import("../application/specification_values.zig").storage.read(&view, @import("../application/specification_repair_workflow.zig").authorization_schema, .repair_authorization);
                    const auth = state.authorization;
                    if (auth.operation == .replace and auth.operation.replace == .value) {
                        const wire = try @import("../domain/model_candidate_json.zig").encode(struct { value: g.spec.BusinessValue }, allocator, .{ .value = try provenance.modelValue(allocator, references, value.value) });
                        return if (options.repeated_provenance_fault) try withForbiddenProvenance(allocator, wire) else wire;
                    }
                    if (auth.rule.group != null and auth.rule.group.? == .membership) {
                        const membership = auth.rule.group.?.membership;
                        var content_value = value.value;
                        if (options.failed_repair) content_value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
                        const record: g.spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = content_value } }, .provenance = membership.fixed_provenance };
                        return @import("../domain/model_candidate_json.zig").encode(g.spec.Wire.RecordProposal, allocator, .{ .content = try provenance.modelRecord(allocator, references, record.content) });
                    }
                }
                return if (options.failed_repair) "{\"provenance\":{\"claim_ids\":[999999]}}" else error.UnexpectedScriptedRepair;
            }
            if (request.packet()) |packet| if (packet.resultDefinition()) |definition| if (definitions.Generation.parse(definition) == .scenarios) return scenarios(allocator, current, context, options);
            const unit = try @import("../domain/specification_session.zig").unit(current.completed);
            const assigned = try @import("../domain/specification_session.zig").currentBinding(allocator, current, context);
            if (options.generation_gap and unit == .entities) {
                const selected = try fixtureGroups(allocator, context, value.provenance.claim_ids, .question);
                return @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, .{ .clarification = .{ .reason = .missing, .question = .{ .value = value.value, .signal_ids = selected.source_group_ids } } });
            }
            var proposed: g.Response = .{
                .content = switch (unit) {
                    .brief => .{ .brief = .{ .description = value, .primary_goal = value } },
                    // ADR 0047: the engine composes the story; no request asks for it.
                    .primary_user_story => return error.UnexpectedStoryRequest,
                    .entities => entity: {
                        const include = options.entities_required != options.contradict_entities;
                        const records = try allocator.alloc(g.spec.Model.RecordProposal, @intFromBool(include));
                        if (include) records[0] = .{ .content = .{ .entity = .{ .name = value.value } }, .provenance = value.provenance };
                        break :entity .{ .entities = .{ .disposition = if (options.entities_required) .required else .not_applicable, .basis = value, .records = records } };
                    },
                    .records => result: {
                        var records: std.ArrayList(g.spec.Model.RecordProposal) = .empty;
                        // One statement record per claim (ADR 0038): each claim's functional
                        // requirement carries its chunk's exact value, which no second record
                        // restates. No acceptance criterion: the scenarios request writes them.
                        // `unlinked` states the claim of every group after the first only as an
                        // edge case, which no requirement's criterion serves.
                        const unlinked = options.edge_cases == .unlinked and current.record_cursor != 0;
                        const statement: g.spec.Kind = if (options.behaviour_without_requirement) .user_visible_outcome else .functional_requirement;
                        const restating = if (restating_batch) try storyRestatement(allocator, options, current, all, dispositions, assigned.records.selection.claim_ids) else null;
                        for (std.enums.values(g.spec.Kind)) |kind| {
                            if (omittedKind(options, kind) or (unlinked and kind == .functional_requirement)) continue;
                            if (kind != statement and !(kind == .edge_case and options.edge_cases != null)) continue;
                            for (all.entries) |item| {
                                const retained = eligibleRecordClaim(dispositions, item.claim.id);
                                if (!retained or (try businessValue(allocator, item.claim, options)) == null or !r.contains(r.ClaimId, assigned.records.selection.claim_ids, item.claim.id)) continue;
                                if (kind == .functional_requirement and restating != null and std.meta.eql(item.claim.id, restating.?.claim)) continue;
                                const selected = try withoutExact(allocator, options, try attributed(allocator, options, all, &.{item.claim.id}));
                                if (kind == .edge_case) {
                                    // `chosen` writes one edge case for the group, which names every claim it holds.
                                    const written = options.edge_cases != .chosen or item.claim.id.ordinal == assigned.records.selection.claim_ids[0].ordinal;
                                    if (written and item.claim.content == .model) try records.append(allocator, .{ .content = .{ .edge_case = .{ .given = selected.value } }, .provenance = selected.provenance });
                                    continue;
                                }
                                if (item.claim.content != .model) continue;
                                var text: std.ArrayList(r.text.BusinessSegment) = .empty;
                                try text.appendSlice(allocator, selected.value.segments);
                                if (!options.omit_exact and std.meta.eql(item.claim.id, try outcomeClaim(allocator, options, all, dispositions, item.claim.chunk_id))) for (all.entries) |exact_item| {
                                    if (exact_item.claim.content != .preserved_token or !std.mem.eql(u8, exact_item.claim.chunk_id.bytes, item.claim.chunk_id.bytes)) continue;
                                    try text.append(allocator, .{ .literal = .{ .value = " " } });
                                    try text.append(allocator, .{ .exact_copy = .{ .claim_id = exact_item.claim.id } });
                                };
                                const wording: g.spec.BusinessValue = .{ .segments = try text.toOwnedSlice(allocator) };
                                try records.append(allocator, .{ .content = if (kind == .user_visible_outcome) .{ .user_visible_outcome = .{ .text = wording } } else .{ .functional_requirement = .{ .text = wording } }, .provenance = selected.provenance });
                            }
                        }
                        if (restating) |subject| {
                            // The restating record comes first: ADR 0038 Decision 5 deletes the later of two
                            // records that name one claim, so only the story comparison removes this one.
                            const selected = try withoutExact(allocator, options, try attributed(allocator, options, all, &.{subject.claim}));
                            try records.append(allocator, .{ .content = switch (options.story_restatement.?) {
                                .business_rule => .{ .business_rule = .{ .text = subject.story } },
                                .non_goal => .{ .non_goal = .{ .text = subject.story } },
                            }, .provenance = selected.provenance });
                            try records.append(allocator, .{ .content = .{ .user_visible_outcome = .{ .text = selected.value } }, .provenance = selected.provenance });
                        }
                        break :result .{ .records = records.items };
                    },
                },
            };
            if (unit == .brief) if (options.brief_text) |texts| {
                inline for (.{ "description", "primary_goal" }, 0..) |field, index| {
                    @field(proposed.content.brief, field).value = .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = texts[index] } }}) };
                }
            };
            if (options.repair and options.attempt == 1) {
                // Generic native unit-repair scenarios use a scalar defect;
                // missing prose belongs to response protocol correction.
                const invalid: g.spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
                switch (unit) {
                    .brief => proposed.content.brief.description.value = invalid,
                    .primary_user_story => return error.UnexpectedStoryRequest,
                    .entities => if (options.repair_across_units) {
                        proposed.content.entities.basis.value = invalid;
                    },
                    // The story is composed natively (ADR 0047), so the third model
                    // unit repaired across units is the first record batch.
                    .records => if (options.repair_across_units and proposed.content.records.len != 0) {
                        const records = try allocator.dupe(g.spec.Model.RecordProposal, proposed.content.records);
                        switch (records[0].content) {
                            .functional_requirement => |*requirement| requirement.text = invalid,
                            else => return error.InvalidFixture,
                        }
                        proposed.content.records = records;
                    },
                }
            }
            try associateFixtureResponse(allocator, context, assigned, restating_batch, &proposed);
            const wire = try @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, try g.ModelResponse.from(allocator, context, proposed));
            return wire;
        },
        .semantic_review => {
            const workflow = @import("../application/specification_support_workflow.zig");
            const packet = try values.read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet);
            const progress = try workflow.progress(&view);
            const inputs = try @import("../application/required_authority_values.zig").read(&view, @import("../application/required_authority_workflow.zig").inputs_schema, .inputs);
            const ledger = try a.build(allocator, inputs);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            if (options.evidence_fault == .empty_correction and options.attempt > 1) return "{}";
            if (packet.resultDefinition()) |definition| if (definitions.Support.parse(definition) == .preservation_comparisons) {
                const prior = workflow.prior(progress);
                const candidate = switch (prior.?) {
                    .pending => |value| value,
                    .accepted => |value| value.candidate,
                    .rejected => return error.InvalidFixture,
                };
                const ordinal = candidate.pending_localization orelse return error.InvalidFixture;
                const id = ledger.requirements[ordinal - 1].seed.id;
                const location: @import("../domain/source_omission.zig").Location = if (falseConflict(options.source_loss) and id.unit == .conflict)
                    .{ .reconciliation_conflict = id.unit.conflict }
                else if (options.source_loss) |mode|
                    try fixtureLoss(&view, inputs, context, mode)
                else
                    .{ .unlocalized = .{} };
                return @import("source_omission_evidence.zig").encode(allocator, try @import("../domain/specification_support.zig").Source.comparisonAssignment(allocator, inputs, context, candidate), location);
            };
            const selected_index = if (request.id().purpose == .atomic_repair) 0 else try reviewIndex(allocator, inputs, try @import("../domain/specification_support.zig").Source.nextSubject(allocator, inputs, workflow.prior(progress)));
            const all = try @import("../domain/specification_provenance.zig").items(context);
            // Of two overlapping conflicts only the second is false: the record that holds the third model claim.
            const dismissed: ?r.ClaimId = if (options.source_loss == .overlapping_false_conflict) third: {
                var seen: usize = 0;
                for (all.entries) |item| if (item.claim.content == .model) {
                    seen += 1;
                    if (seen == 3) break :third item.claim.id;
                };
                break :third null;
            } else null;
            const findings = try allocator.alloc(@import("../domain/specification_support.zig").Source.Finding, ledger.requirements.len);
            for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
                const required = try @import("../domain/specification_support_evidence.zig").requirements(allocator, inputs, context.inputs, requirement.seed.id);
                const eligible = required.eligible_claim_ids;
                var selected: g.spec.Selection = .{ .claim_ids = if (eligible.len == 0) &.{} else eligible[0..1], .clarification_response_ids = &.{} };
                switch (requirement.seed.id.unit) {
                    .token => |token| for (all.entries) |item| {
                        if (item.claim.content == .preserved_token and item.claim.content.preserved_token.value.id.ordinal == token.ordinal) selected = (try attributed(allocator, options, all, &.{item.claim.id})).provenance;
                    },
                    .signal => |id| for (context.references.records.signals) |signal| {
                        if (signal.id.ordinal == id.ordinal) selected = selection(.{ .claim_ids = signal.value.claim_ids, .citation_ids = signal.value.citation_ids, .clarification_response_ids = &.{} });
                    },
                    .conflict => |id| for (context.references.records.conflicts) |conflict| {
                        if (conflict.id.ordinal == id.ordinal) selected = selection(.{ .claim_ids = conflict.value.claim_ids, .citation_ids = conflict.value.citation_ids, .clarification_response_ids = &.{} });
                    },
                    else => {},
                }
                const uncertain = options.uncertain;
                const source_only = required.positive_evidence == .original_sources;
                const source_positive = source_only and required.eligible_source_ids.len != 0;
                if (source_only) selected = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} };
                const unbound = (source_only and !source_positive) or (!source_only and eligible.len != 0 and (requirement.seed.id.unit == .feature or requirement.seed.id.unit == .record));
                const conflict = requirement.seed.id.unit == .conflict;
                finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .question = if (conflict) "Should the loan be renewed or rejected? Choose the required outcome." else if (uncertain) "Which renewal deadline applies? Supply the duration and starting event." else null, .kind = if (conflict) .conflicting else if (uncertain) .ambiguous else if (unbound) .inconclusive else .supported, .provenance = selected, .source_ids = &.{}, .detail = if (conflict) "Should the loan be renewed or rejected? The sources disagree." else if (uncertain) "Which renewal deadline applies? The sources do not settle it." else if (unbound) "No validated source group binds this requirement." else "" } };
                if (source_positive and finding.value.kind == .supported) {
                    finding.value.source_ids = required.eligible_source_ids[0..1];
                    finding.value.detail = "The original source establishes the required readiness fact.";
                }
                if (falseConflict(options.source_loss) and options.source_loss != .false_conflict_questions and requirement.seed.id.unit == .conflict and
                    (options.source_loss != .overlapping_false_conflict or (dismissed != null and r.contains(r.ClaimId, selected.claim_ids, dismissed.?))))
                {
                    finding.value.kind = .candidate_omission;
                    finding.value.missing_obligation = context.inputs.corpus.sources[0].bytes;
                    finding.value.question = null;
                    finding.value.detail = "The source meanings are compatible; the false conflict discarded their supported behavior.";
                    finding.value.loss = .{ .reconciliation_conflict = requirement.seed.id.unit.conflict };
                    finding.value.source_ids = &.{context.inputs.corpus.sources[0].id};
                }
                if (options.source_gaps and requirement.seed.id.kind == .feature_intent and requirement.seed.id.unit == .feature) finding.value = .{ .kind = .unsupported, .question = switch (requirement.seed.id.slot) {
                    .description => "What behavior should this feature provide? Describe the expected result.",
                    .primary_goal => "Which user outcome takes priority? Name the primary goal.",
                    .acceptance_criteria => "Which observable outcome counts as success? State the pass/fail condition.",
                    .functional_requirements => "What should happen when renewal is requested? State the required behavior.",
                    .scenario_coverage => "What should happen when renewal is refused? Describe that scenario outcome.",
                    else => return error.UnexpectedSourceGap,
                }, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "The source leaves this decision unspecified." };
                if (options.extraction_omission) finding.value = .{ .kind = .candidate_omission, .missing_obligation = context.inputs.corpus.sources[0].bytes, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{context.inputs.corpus.sources[0].id}, .detail = "Extraction discarded the source-required behavior and exact message." };
            }
            if (options.source_loss == .false_conflict_questions) for (ledger.requirements, findings) |required, *finding| {
                if (required.seed.id.unit == .signal or required.seed.id.unit == .token) continue;
                finding.value.kind = .unsupported;
                finding.value.question = null;
                finding.value.detail = "The source gives the action and date, but the derived conflict left the interpretation unsupported.";
            };
            if (options.source_loss) |mode| {
                const location = try fixtureLoss(&view, inputs, context, mode);
                if (@import("../domain/source_omission.zig").isUpstream(location)) {
                    if (all.entries.len == 0) for (findings) |*finding| {
                        finding.value.kind = .candidate_omission;
                        finding.value.missing_obligation = context.inputs.corpus.sources[0].bytes;
                        finding.value.detail = "Extraction lost source-required behavior.";
                        finding.value.source_ids = try allocator.dupe(r.extraction.identity.SourceId, &.{context.inputs.corpus.sources[0].id});
                    };
                    const target_index = if (location == .reconciliation_signal) target: {
                        for (ledger.requirements, 0..) |required, at| if (required.seed.id.unit == .signal and std.meta.eql(required.seed.id.unit.signal, location.reconciliation_signal)) break :target at;
                        return error.InvalidFixture;
                    } else if (location == .token_classification) target: {
                        // Review the deficient reference collection, not an
                        // authored field with independent local repair rights.
                        for (ledger.requirements, 0..) |required, at| if (required.seed.id.unit == .signal) break :target at;
                        return error.InvalidFixture;
                    } else 0;
                    findings[target_index].value = .{ .kind = .candidate_omission, .missing_obligation = context.inputs.corpus.sources[0].bytes, .loss = location, .detail = "Preserve the source-required deadline.", .source_ids = try allocator.dupe(r.extraction.identity.SourceId, &.{context.inputs.corpus.sources[0].id}), .provenance = .{ .claim_ids = if (location == .reconciliation_signal) context.references.records.signals[location.reconciliation_signal.ordinal - 1].value.claim_ids else &.{}, .clarification_response_ids = &.{} } };
                }
            }
            if (request.id().purpose == .atomic_repair) {
                const repair = @import("../domain/specification_support_repair.zig").Source;
                const state = try @import("../application/required_authority_values.zig").read(&view, @import("../application/specification_support_repair_workflow.zig").schema, .support_repair);
                const authorized = state.authorization;
                if (options.applicability == .missing_text) return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, .{ .detail = .{ .detail = applicability_detail, .question = applicability_question } });
                if (options.source_loss == .false_conflict_questions) return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, .{ .detail = .{ .detail = findings[authorized.target.ordinal - 1].value.detail, .question = "Which behavior is intended? State the action and date to display." } });
                const value = findings[authorized.target.ordinal - 1].value;
                const kind = switch (authorized.operation) {
                    .replace => |replacement| std.meta.activeTag(replacement),
                    .insert => |kind| kind,
                    .delete => return error.InvalidFixture,
                };
                const replacement: repair.Replacement = switch (kind) {
                    .detail => .{ .detail = .{ .detail = "The sources do not settle the renewal deadline.", .question = "Which renewal deadline applies? Supply the duration and starting event." } },
                    .selection => .{ .selection = .{ .provenance = value.provenance, .source_ids = value.source_ids } },
                    .finding => .{ .finding = value },
                };
                return sourceRepairWire(allocator, inputs, context, authorized, replacement);
            }
            if (options.evidence_fault != null) for (ledger.requirements, findings) |requirement, *finding| {
                if (requirement.seed.id.kind == .entity_applicability) {
                    finding.value.kind = .not_applicable;
                    finding.value.source_ids = if (options.attempt == 1) &.{.{ .ordinal = 999999 }} else &.{context.inputs.corpus.sources[0].id};
                } else if (requirement.seed.id.unit == .token) {
                    finding.value.source_ids = if (options.attempt == 1) &.{.{ .ordinal = 999999 }} else &.{context.inputs.corpus.sources[0].id};
                } else {
                    finding.value.kind = .unsupported;
                    finding.value.question = "Which renewal rule should apply? Specify the duration and starting event.";
                    finding.value.provenance.claim_ids = &.{};
                    finding.value.detail = "The source does not settle this requirement.";
                }
                if (requirement.seed.id.kind != .entity_applicability and requirement.seed.id.unit != .token) finding.value.source_ids = &.{context.inputs.corpus.sources[0].id};
            };
            if (options.support_fault) |fault| switch (fault) {
                .foreign_source_single => if (options.attempt == 1) {
                    findings[0].value.source_ids = &.{.{ .ordinal = 999999 }};
                },
            };
            if (options.applicability) |mode| for (ledger.requirements, findings) |requirement, *finding| {
                if (requirement.seed.id.kind != .entity_applicability) continue;
                finding.value.source_ids = &.{context.inputs.corpus.sources[0].id};
                switch (mode) {
                    .unjustified => {
                        finding.value.kind = .unsupported;
                        finding.value.provenance.claim_ids = &.{};
                        finding.value.detail = "No claim indicates the presence or absence of business entities or data; insufficient evidence to determine.";
                        finding.value.question = if (options.attempt == 1) null else "Does the application involve any business entities or data? Please answer Yes or No.";
                    },
                    .no_entities => {
                        finding.value.kind = .not_applicable;
                        finding.value.detail = "The source requires calculated output, with no business records needed for that behavior.";
                    },
                    .entities => {},
                    .missing_decision, .missing_text => {
                        finding.value.kind = .ambiguous;
                        finding.value.detail = applicability_detail;
                        finding.value.question = if (mode == .missing_text) "Invalid scalar\x01" else applicability_question;
                    },
                    .inconclusive => {
                        finding.value.kind = .inconclusive;
                        finding.value.detail = "The review could not establish applicability from the source; no missing user decision was identified.";
                        finding.value.question = null;
                    },
                }
            };
            const model = @import("../domain/specification_support_model.zig");
            const admission = @import("../domain/specification_support_evidence.zig");
            return model.encode(allocator, findings[selected_index].value, try admission.requirements(allocator, inputs, context.inputs, ledger.requirements[selected_index].seed.id));
        },
        else => return error.InvalidFixture,
    }
}
fn sourceRepairWire(allocator: std.mem.Allocator, inputs: a.Inputs, context: @import("../domain/specification_provenance.zig").Context, authorized: @import("../domain/specification_support_repair.zig").Source.Authorization, replacement: @import("../domain/specification_support_repair.zig").Source.Replacement) ![]const u8 {
    const repair = @import("../domain/specification_support_repair.zig").Source;
    const codec = @import("../domain/model_candidate_json.zig");
    const model = @import("../domain/specification_support_model.zig");
    return switch (replacement) {
        .detail => codec.encodeSelected(repair.Replacement, allocator, replacement),
        .finding => |value| model.encode(allocator, value, try @import("../domain/specification_support_evidence.zig").requirements(allocator, inputs, context.inputs, authorized.target.requirement)),
        .selection => |value| codec.encode(model.Selection, allocator, .{ .source_ids = value.source_ids }),
    };
}
fn fixtureLoss(view: *const data.View, _: a.Inputs, context: @import("../domain/specification_provenance.zig").Context, mode: SourceLoss) !@import("../domain/source_omission.zig").Location {
    const candidate = (try native.read(view, native.text_schema, .text_validated)).payload().text_validated;
    const first = candidate.entries[0];
    if ((mode == .empty and first.outcome == .no_feature_claim) or (mode == .partial and first.outcome == .claims and first.outcome.claims.len == 1)) return .{ .extraction_claim = first.scope.chunk_id };
    if (mode == .empty or mode == .classification) {
        for (first.token_classifications) |classification| if (classification == .irrelevant) return .{ .token_classification = classification.id() };
    } else {
        for (context.references.records.signals) |signal| if (signal.value.content == .model and signal.value.content.model == .business and signal.value.content.model.business.value.segments.len == 1 and signal.value.content.model.business.value.segments[0] == .literal and std.mem.eql(u8, signal.value.content.model.business.value.segments[0].literal.value, "Incomplete signal.")) return .{ .reconciliation_signal = signal.id };
    }
    return .{ .unlocalized = .{} };
}

fn reviewIndex(allocator: std.mem.Allocator, inputs: a.Inputs, selected: a.Id) !usize {
    const ledger = try a.build(allocator, inputs);
    for (ledger.requirements, 0..) |requirement, index| if (std.meta.eql(requirement.seed.id, selected)) return index;
    return error.InvalidFixture;
}
fn businessValue(allocator: std.mem.Allocator, claim: r.extraction.Claim, options: Options) !?g.spec.BusinessValue {
    return switch (claim.content) {
        .model => |model| switch (model) {
            .business, .scope_guard => |value| .{ .segments = value.value.segments },
            // A run that files its claims as open questions authors from the one an answer kept: the engine admits no other.
            .open_question => |value| if (options.open_question_claims) try questionSegments(allocator, value.value.nodes) else null,
            else => null,
        },
        .preserved_token => .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .exact_copy = .{ .claim_id = claim.id } }}) },
    };
}

/// The claim's wording as business segments, when it is source quotation alone.
fn questionSegments(allocator: std.mem.Allocator, nodes: []const r.text.ReferenceNode) !?g.spec.BusinessValue {
    const segments = try allocator.alloc(r.text.BusinessSegment, nodes.len);
    for (nodes, segments) |node, *segment| segment.* = switch (node) {
        .literal => |literal| .{ .literal = literal },
        .passive, .source => return null,
    };
    return .{ .segments = segments };
}

/// The claim a story-restating record names and the story's own text, read from the admitted story:
/// the first claim of the batch the story quotes, while another claim of the batch keeps its
/// requirement. A group without both is a mis-specified fixture, so it fails instead of restating nothing.
fn storyRestatement(allocator: std.mem.Allocator, options: Options, current: @import("../domain/specification_session.zig").Session, all: r.Items, dispositions: []const r.ClaimDisposition, batch_claims: []const r.ClaimId) !struct { claim: r.ClaimId, story: g.spec.BusinessValue } {
    const admitted = current.units[@import("../domain/specification_session.zig").story_index] orelse return error.StoryRestatementNeedsStory;
    if (admitted.response != .content or admitted.response.content != .primary_user_story) return error.StoryRestatementNeedsStory;
    const story = admitted.response.content.primary_user_story;
    var subject: ?r.ClaimId = null;
    var others: usize = 0;
    for (all.entries) |item| {
        if (!eligibleRecordClaim(dispositions, item.claim.id) or item.claim.content != .model or (try businessValue(allocator, item.claim, options)) == null or !r.contains(r.ClaimId, batch_claims, item.claim.id)) continue;
        if (subject == null and r.contains(r.ClaimId, story.provenance.claim_ids, item.claim.id)) subject = item.claim.id else others += 1;
    }
    if (others == 0) return error.StoryRestatementNeedsAnotherClaim;
    return .{ .claim = subject orelse return error.StoryRestatementNeedsQuotedClaim, .story = story.value };
}

fn eligibleRecordClaim(dispositions: []const r.ClaimDisposition, id: r.ClaimId) bool {
    for (dispositions) |disposition| if (std.meta.eql(disposition.claim_id, id)) return @import("../domain/reference_support.zig").eligibleClaim(disposition.disposition);
    return false;
}

/// This fake chooses one business claim per chunk to author its exact outcomes.
/// Other groups still receive their own requirements and acceptance criteria.
fn outcomeClaim(allocator: std.mem.Allocator, options: Options, all: r.Items, dispositions: []const r.ClaimDisposition, chunk: r.extraction.identity.ChunkId) !r.ClaimId {
    for (all.entries) |item| {
        if (item.claim.content != .model or !item.claim.chunk_id.eql(chunk) or !eligibleRecordClaim(dispositions, item.claim.id)) continue;
        if ((try businessValue(allocator, item.claim, options)) != null) return item.claim.id;
    }
    return error.InvalidFixture;
}
/// Claims quote the source (ADR 0036), so copying one copies its exact values.
/// An omitted-exact script authors its own text instead.
fn withoutExact(allocator: std.mem.Allocator, options: Options, value: g.spec.Model.AttributedValue) !g.spec.Model.AttributedValue {
    if (!options.omit_exact) return value;
    var result = value;
    const text = try std.fmt.allocPrint(allocator, "MOCK Required behavior {d} is described.", .{value.provenance.claim_ids[0].ordinal});
    result.value = .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = text } }}) };
    return result;
}
fn attributed(allocator: std.mem.Allocator, options: Options, all: r.Items, ids: []const r.ClaimId) !g.spec.Model.AttributedValue {
    const value = (try businessValue(allocator, (try r.item(all, ids[0])).claim, options)) orelse return error.InvalidFixture;
    return .{ .value = value, .provenance = .{ .claim_ids = try allocator.dupe(r.ClaimId, ids), .clarification_response_ids = &.{} } };
}

/// The Then of the last scenario of each group under `chosen` edge cases, which tells the group's
/// two criteria apart in the published specification.
pub const refusal = "The request is refused.";

/// The answer to a group's scenarios request (ADR 0038 Decision 3): one scenario for each slot,
/// written from the slot's claim. It names no claim, kind or group; the engine binds them.
fn scenarios(allocator: std.mem.Allocator, current: @import("../domain/specification_session.zig").Session, context: @import("../domain/specification_provenance.zig").Context, options: Options) ![]const u8 {
    const request = @import("../domain/scenario_request.zig");
    const provenance = @import("../domain/specification_provenance.zig");
    // The scripted defect is a text defect in the first scenario's Given, which an omitted Given cannot carry.
    if (options.scenario_defect and options.scenarios_without_given) return error.InvalidFixture;
    const group_plan = try @import("../domain/specification_session.zig").scenarioPlan(allocator, current);
    const all = try provenance.items(context);
    const references = @import("../domain/reference_support.zig").records(context.references);
    const written = try allocator.alloc(request.Scenario, group_plan.count());
    for (written, 0..) |*scenario, index| {
        const slot = group_plan.slot(index);
        const claim = try withoutExact(allocator, options, try attributed(allocator, options, all, &.{slot.claim}));
        const value = try provenance.modelValue(allocator, references, claim.value);
        const refuses = options.edge_cases == .chosen and index + 1 == written.len;
        scenario.* = .{ .number = slot.number, .given = if (options.scenarios_without_given) null else value, .when = value, .then = if (refuses) .{ .segments = &.{.{ .literal = .{ .value = refusal } }} } else value };
    }
    if (options.scenario_defect and options.attempt == 1) written[0].given = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    return @import("../domain/model_candidate_json.zig").encode(request.Response, allocator, .{ .scenarios = written });
}

/// Two claims to a signal, in the order the model's reconciliation lists them: a group holding two
/// claims, so an edge case naming both meets two criteria. A signal of a preserved token, and a
/// last signal with no partner, stay as they are.
fn pairedSignals(allocator: std.mem.Allocator, signals: []const r.SignalProposal) ![]const r.SignalProposal {
    var paired: std.ArrayList(r.SignalProposal) = .empty;
    var held: ?r.SignalProposal = null;
    for (signals) |signal| {
        if (signal.content != .model) {
            try paired.append(allocator, signal);
        } else if (held) |first| {
            try paired.append(allocator, .{ .claim_ids = try std.mem.concat(allocator, r.ClaimId, &.{ first.claim_ids, signal.claim_ids }), .content = first.content });
            held = null;
        } else held = signal;
    }
    if (held) |single| try paired.append(allocator, single);
    return paired.items;
}

// Explicit scripted source choices, resolved by the production occurrence owner.
// This fake knows its authored claim set; it does not infer support for an LLM.
fn fixtureGroups(allocator: std.mem.Allocator, context: @import("../domain/specification_provenance.zig").Context, claims: []const r.ClaimId, mode: @import("../domain/specification_source_binding.zig").Mode) !@import("../domain/specification_source_binding.zig").Association {
    const binding = @import("../domain/specification_source_binding.zig");
    const records = @import("../domain/reference_support.zig").records(context.references);
    var groups: std.ArrayList(r.SignalId) = .empty;
    for (try binding.catalogue(allocator, records, mode)) |group| {
        const chosen = for (group.claim_ids) |id| {
            if (r.contains(r.ClaimId, claims, id)) break true;
        } else false;
        if (chosen) try groups.append(allocator, group.signal_id);
    }
    if (groups.items.len == 0) return error.InvalidFixture;
    const selected = try binding.resolveGroups(allocator, records, context.inputs, groups.items, mode);
    for (claims) |id| if (!r.contains(r.ClaimId, selected.selection.claim_ids, id)) return error.InvalidFixture;
    return selected;
}

/// Every record of a batch names the group's whole claim selection, except when `own_claims`: then a
/// statement record keeps the claims its script gave it, so a requirement need not name every claim of the batch.
fn associateFixtureResponse(allocator: std.mem.Allocator, context: @import("../domain/specification_provenance.zig").Context, bound: @import("../domain/specification_source_binding.zig").Bound, own_claims: bool, response: *g.Response) !void {
    switch (response.*) {
        .content => |*content| switch (content.*) {
            .brief => |*brief| inline for (.{ "description", "primary_goal" }) |field| try associateFixtureValue(allocator, context, &@field(brief, field)),
            .primary_user_story => return error.UnexpectedStoryRequest,
            .entities => |*entities| {
                try associateFixtureValue(allocator, context, &entities.basis);
                const selected = try allocator.dupe(g.spec.Model.RecordProposal, entities.records);
                for (selected) |*record| {
                    const association = try fixtureGroups(allocator, context, record.provenance.claim_ids, .content);
                    record.source_group_ids = association.source_group_ids;
                    record.provenance = association.selection;
                }
                entities.records = selected;
            },
            .records => |records| {
                if (bound != .records) return error.InvalidFixture;
                const selected = try allocator.dupe(g.spec.Model.RecordProposal, records);
                for (selected) |*record| {
                    record.source_group_ids = try allocator.dupe(r.SignalId, &.{bound.records.signal});
                    if (!own_claims or record.content == .edge_case) record.provenance = bound.records.selection;
                }
                content.* = .{ .records = selected };
            },
        },
        .clarification, .inconclusive => {},
    }
}
fn associateFixtureValue(allocator: std.mem.Allocator, context: @import("../domain/specification_provenance.zig").Context, value: *g.spec.Model.AttributedValue) !void {
    const selected = try fixtureGroups(allocator, context, value.provenance.claim_ids, .content);
    value.source_group_ids = selected.source_group_ids;
    value.provenance = selected.selection;
}

fn selection(value: g.spec.Provenance) g.spec.Selection {
    return .{ .claim_ids = value.claim_ids, .clarification_response_ids = value.clarification_response_ids };
}

// Canonical fixture proposals include native token facts. The scripted model
// chooses only current semantic subjects, before any negative fault is injected.
fn dispositionClaims(allocator: std.mem.Allocator, request: *const @import("../domain/model_request_handoff.zig").Request, input: r.Input) ![]const r.ClaimId {
    const packet = request.packet() orelse return error.InvalidReconciliationFixture;
    const definition = packet.resultDefinition() orelse return error.InvalidReconciliationFixture;
    if (definitions.Reconciliation.parse(definition) != .dispositions_assignment) return @import("../domain/reference_reconciliation_projection.zig").semanticClaimIds(allocator, input.items);
    const body = try std.json.parseFromSlice(std.json.Value, allocator, packet.body(), .{});
    const supplied = body.value.object.get("assignment").?.object.get("claim_ids").?.array.items;
    const result = try allocator.alloc(r.ClaimId, supplied.len);
    for (supplied, result) |id, *claim| claim.* = .{ .ordinal = std.math.cast(u32, id.integer) orelse return error.InvalidReconciliationFixture };
    return result;
}

/// The scripted complete source remains one fixture; each provider call gets
/// only its configured fields. Protocol faults are injected afterward
/// by Driver, so this projection cannot repair or conceal a malformed response.
fn partResponse(allocator: std.mem.Allocator, request: *const @import("../domain/model_request_handoff.zig").Request, body: []const u8) ![]const u8 {
    const part = request.part() orelse {
        const bound = request.packet() orelse return body;
        const definition = bound.resultDefinition() orelse return body;
        const field: ?[]const u8 = if (definitions.Reconciliation.parse(definition)) |selected| switch (selected) {
            .dispositions_assignment => "claim_dispositions",
            .signals_assignment => "signals",
            .conflicts_assignment => "conflicts",
            else => null,
        } else null;
        if (field) |name| {
            const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
            defer parsed.deinit();
            var result: std.json.ObjectMap = .{};
            try result.put(allocator, name, parsed.value.object.get(name) orelse return error.InvalidReconciliationFixture);
            if (std.mem.eql(u8, name, "claim_dispositions")) {
                var groups: std.array_list.Managed(std.json.Value) = .init(allocator);
                const dispositions = result.getPtr(name).?;
                for (dispositions.array.items) |*entry| {
                    const choice = entry.object.getPtr("disposition").?;
                    if (!std.mem.eql(u8, choice.object.get("kind").?.string, "conflicting")) continue;
                    const left = entry.object.get("claim_id").?.integer;
                    for (choice.object.get("related_claim_ids").?.array.items) |right| if (left < right.integer) {
                        const duplicate = for (groups.items) |group| {
                            const pair = group.object.get("claim_ids").?.array.items;
                            if (pair[0].integer == left and pair[1].integer == right.integer) break true;
                        } else false;
                        if (duplicate) continue;
                        var pair: std.array_list.Managed(std.json.Value) = .init(allocator);
                        try pair.append(.{ .integer = left });
                        try pair.append(right);
                        var group: std.json.ObjectMap = .{};
                        try group.put(allocator, "claim_ids", .{ .array = pair });
                        try groups.append(.{ .object = group });
                    };
                    _ = choice.object.swapRemove("related_claim_ids");
                }
                try result.put(allocator, "conflict_groups", .{ .array = groups });
            } else if (std.mem.eql(u8, name, "signals")) {
                const packet = try std.json.parseFromSlice(std.json.Value, allocator, (request.packet() orelse return error.InvalidSpecificationScript).body(), .{});
                const accepted_signals = packet.value.object.get("accepted").?.object.get("signals").?.array.items;
                var pending: std.array_list.Managed(std.json.Value) = .init(allocator);
                for (result.get(name).?.array.items) |candidate| {
                    const ids = candidate.object.get("claim_ids").?.array.items;
                    var present = false;
                    for (accepted_signals) |existing| {
                        const members = existing.object.get("claim_ids").?.array.items;
                        if (ids.len != members.len) continue;
                        var equal = true;
                        for (ids, members) |id, member| if (id.integer != member.integer) {
                            equal = false;
                        };
                        if (equal) present = true;
                    }
                    if (!present) try pending.append(candidate);
                }
                try result.put(allocator, name, .{ .array = pending });
            } else if (std.mem.eql(u8, name, "conflicts")) {
                const packet = try std.json.parseFromSlice(std.json.Value, allocator, (request.packet() orelse return error.InvalidSpecificationScript).body(), .{});
                try result.put(allocator, name, try @import("reference_reconciliation.zig").explanationWire(allocator, packet.value.object.get("accepted").?.object.get("conflict_groups").?.array.items, result.get(name).?.array.items));
            }
            return std.json.Stringify.valueAlloc(allocator, std.json.Value{ .object = result }, .{});
        }
        return body;
    };
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    var result: std.json.ObjectMap = .{};
    for (part.plan.parts()[part.part].paths) |path| {
        const value = @import("../domain/json_pointer.zig").lookup(parsed.value, path) orelse continue;
        var parent = &result;
        for (path.segments[0 .. path.segments.len - 1]) |name| {
            const child = try parent.getOrPutValue(allocator, name, .{ .object = .{} });
            parent = &child.value_ptr.object;
        }
        try parent.put(allocator, path.segments[path.segments.len - 1], value);
    }
    return std.json.Stringify.valueAlloc(allocator, std.json.Value{ .object = result }, .{});
}

fn misboundProjection(comptime T: type, projections: []const T) !r.SignalProposal {
    if (T != r.StatementProposal and T != r.SignalProposal) @compileError("expected a reconciliation projection");
    var business: ?r.ContentProposal = null;
    var token_claims: ?[]const r.ClaimId = null;
    for (projections) |value| {
        if (value.content == .model and value.content.model == .business) business = value.content;
        if (value.content == .preserved_token) token_claims = value.claim_ids;
    }
    return .{ .claim_ids = token_claims orelse return error.InvalidReconciliationFixture, .content = business orelse return error.InvalidReconciliationFixture };
}

// Scripted semantic judgments stay in fake-provider fixtures. The native engine
// still validates ordinary candidate data; review has no content-repair authority.
fn omittedKind(options: Options, kind: g.spec.Kind) bool {
    return options.candidate_omissions and kind == .functional_requirement;
}

pub fn withForbiddenProvenance(allocator: std.mem.Allocator, wire: []const u8) ![]const u8 {
    var decoded = try std.json.parseFromSlice(std.json.Value, allocator, wire, .{});
    defer decoded.deinit();
    try decoded.value.object.put(allocator, "provenance", .{ .object = .{} });
    return std.json.Stringify.valueAlloc(allocator, decoded.value, .{});
}
