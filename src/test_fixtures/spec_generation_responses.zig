//! Shared scripted provider candidate data. No workflow execution or test loop.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const values = @import("../application/pipeline_values.zig");
const r = @import("../domain/reference_reconciliation.zig");
const g = @import("../domain/specification_generation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const a = @import("../domain/required_authority.zig");
pub const ReconciliationFault = enum { summary_membership, duplicate_disposition, self_relation, cycle, signal_coverage, mixed_selection, conflict_coverage, summary_text, signal_text, conflict_text, occupied_summary, occupied_signals, occupied_conflict, permuted_disposition, permuted_conflict_disposition, misbound_summary, misbound_signals, missing_entity_role, unassigned_roles };
pub const SupportFault = enum { inconclusive, missing_detail, foreign_source_single, foreign_sources, question_recover, question_exhaust, question_native_exhaust, question_mixed_exhaust, question_evidence_recover, question_evidence_exhaust, question_evidence_alternating };
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

pub const SourceLoss = enum { empty, partial, classification, signal, unchanged, false_conflict, unchanged_conflict, false_conflict_questions };
fn falseConflict(mode: ?SourceLoss) bool {
    return mode == .false_conflict or mode == .unchanged_conflict or mode == .false_conflict_questions;
}

pub const PrincipleFault = enum { recover, repeated, alternating };
pub const Options = struct {
    global_sequence: ?@import("global_protocol_sequence.zig").Mode = null,
    summary_sequence: ?@import("summary_protocol_sequence.zig").Mode = null,
    disposition_sequence: ?enum { recover, exhaust } = null,
    attempt: u32 = 1,
    source_loss: ?SourceLoss = null,
    support_fault: ?SupportFault = null,
    support_merges: usize = 0,
    applicability: ?Applicability = null,
    principle_conflict: bool = false,
    principle_fault: ?PrincipleFault = null,
    principle_repair_calls: usize = 0,
    source_gaps: bool = false,
    evidence_fault: ?enum { recover, empty_correction } = null,
    candidate_omissions: ?enum { functional, acceptance_and_functional } = null,
    extraction_omission: bool = false,
    text_fault: bool = false,
    failed_text_repair: bool = false,
    reconciliation_repair_fault: ?enum { unchanged, alternating, unchanged_text } = null,
    reconciliation_fault: ?ReconciliationFault = null,
    script: ?@import("specification_script.zig").Script = null,
    uncertain: bool = false,
    brief_uncertain: bool = false,
    brief_text: ?[3][]const u8 = null,
    repair: bool = false,
    repeated_provenance_fault: bool = false,
    repair_across_units: bool = false,
    failed_repair: bool = false,
    omit_exact: bool = false,
    normalize_exact: bool = false,
    citation_fault: ?enum { unknown, missing } = null,
    failed_citation_repair: bool = false,
    missing_classifications: bool = false,
    failed_classification_repair: bool = false,
    entities_required: bool = false,
    contradict_entities: bool = false,
    generation_gap: bool = false,
};

pub fn build(allocator: std.mem.Allocator, view: data.View, options: Options) ![]const u8 {
    const request = try requests.readCurrent(&view, requests.prepared_schema);
    const body = try partResponse(allocator, request, try completeResponse(allocator, view, options), options.reconciliation_fault);
    return modelWire(allocator, body, request.packet() orelse return body);
}

/// Project canonical fixture data to the currently bound response wire shape.
/// This test helper does not admit or normalize actual provider responses.
pub fn modelWire(allocator: std.mem.Allocator, body: []const u8, packet: *const @import("../domain/model_input_packet.zig").Packet) ![]const u8 {
    for (packet.integerChoices()) |choice| {
        if (choice.constructedValue() != null) break;
    } else return body;
    var parsed = try @import("../domain/strict_json.zig").parse(allocator, body, .{ .maximum_depth = 64 }, false, null);
    try omitScriptedNativeFields(&parsed.value, packet.integerChoices());
    return std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
}

// Scripted canonical values are fixture data; model-wire responses omit only
// their matching determined handles. Independent boundary tests cover admission.
fn omitScriptedNativeFields(value: *std.json.Value, choices: []const @import("../domain/model_result_schema.zig").IntegerChoice) !void {
    switch (value.*) {
        .object => |*object| {
            for (object.values()) |*child| try omitScriptedNativeFields(child, choices);
            const kind = object.get("kind") orelse return;
            if (kind != .string) return;
            for (choices) |choice| if (choice.constructedValue()) |fixed| {
                const target = choice.target.tagged;
                if (!std.mem.eql(u8, target.kind, kind.string)) continue;
                const selected = object.get(target.field) orelse continue;
                if (selected != .number_string) return error.InvalidFixture;
                const id = try @import("../domain/model_payload_schema.zig").exactInteger(selected.number_string);
                if (id == fixed) _ = object.swapRemove(target.field);
            };
        },
        .array => |*array| for (array.items) |*child| try omitScriptedNativeFields(child, choices),
        else => {},
    }
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
                const packet = try values.read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet);
                if (view.contains(.source_omission_repair)) {
                    const state = try @import("../application/source_omission_repair_workflow.zig").read(&view);
                    if (state.authorization.extraction.target == .classification) {
                        const id = state.authorization.extraction.operation.replace.classification.id();
                        return @import("../domain/model_candidate_json.zig").encode(r.extraction.tokens.Classification, allocator, .{ .preserve = .{ .token_candidate_id = id, .kind = if (id.extractor_id == .markdown_fenced_code_v1) .code_sample else .business_exact_string } });
                    }
                    return @import("../domain/model_candidate_json.zig").encode(r.extraction.Proposal, allocator, .{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Preserve the source-required deadline." } }} } }, .citations = &.{@import("../reference_extraction_test.zig").wholeChunk(chunk)} });
                }
                if (std.mem.eql(u8, packet.resultDefinition().?.bytes, "business_text_replacement")) {
                    const replacement: @import("../domain/reference_extraction_text_repair.zig").Replacement = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = if (options.failed_text_repair) "Invalid\x01text" else try extractedClaim(allocator, chunk.id) } }} } };
                    return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/reference_extraction_text_repair.zig").Replacement, allocator, replacement);
                }
                if (options.citation_fault) |fault| {
                    const choice = if (options.failed_citation_repair) @import("../domain/source_selections.zig").Selection{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } } else @import("../reference_extraction_test.zig").wholeChunk(chunk);
                    const replacement: @import("../domain/reference_extraction_repair.zig").Replacement = switch (fault) {
                        .unknown => .{ .citation = choice },
                        .missing => .{ .citations = .{ .citations = &.{choice} } },
                    };
                    return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/reference_extraction_repair.zig").Replacement, allocator, replacement);
                }
                const choices = if (options.failed_classification_repair) &.{} else try @import("reference_tokens.zig").classifications(allocator, candidates, chunk);
                return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/reference_extraction_repair.zig").Replacement, allocator, .{ .classifications = .{ .token_classifications = choices } });
            }
            if (options.extraction_omission or options.source_loss == .empty) {
                const choices = try @import("reference_tokens.zig").classifications(allocator, candidates, chunk);
                const discarded = try allocator.alloc(@import("../domain/structured_tokens.zig").Classification, choices.len);
                for (choices, discarded) |choice, *decision| decision.* = .{ .irrelevant = choice.id() };
                // R21: a protocol-valid correction abandons the source task.
                const reply = try @import("../domain/model_candidate_json.zig").encode(@import("../domain/reference_extraction_parser.zig").Response, allocator, .{ .no_feature_claim = .{ .reason = .{ .nodes = &.{.{ .literal = .{ .value = "The rejected response JSON has a syntax error in its claims array." } }} }, .token_classifications = &.{} } });
                return @import("reference_tokens.zig").wire(allocator, reply, discarded);
            }
            const claim = if (options.script) |script| (try @import("specification_script.zig").extraction(script, selected_chunk.bytes)).claim else if (options.brief_text) |texts| texts[1] else try extractedClaim(allocator, chunk.id);
            const citation: @import("../domain/source_selections.zig").Selection = if (options.citation_fault == .unknown) .{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } } else @import("../reference_extraction_test.zig").wholeChunk(chunk);
            const mixed_kinds = options.summary_sequence != null or options.global_sequence != null or options.reconciliation_fault == .mixed_selection;
            // Empty citations now fail the complete response schema. A protocol
            // correction must provide the full claim again before native repair.
            const body = try @import("../domain/model_candidate_json.zig").encode(@import("../domain/reference_extraction_parser.zig").Response, allocator, .{ .claims = .{ .claims = &.{.{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = if (options.text_fault) "Invalid\x01text" else claim } }} } }, .citations = if (options.citation_fault == .missing and options.attempt == 1) &.{} else &.{citation} }}, .token_classifications = &.{} } });
            // Native correlation faults need two eligible semantic kinds;
            // selecting an exact-token ID is now rejected by the wire schema.
            if (falseConflict(options.source_loss) or (mixed_kinds and chunk.id.eql(inputs.chunks.entries[0].id))) {
                const response_type = @import("../domain/reference_extraction_parser.zig").Response;
                var response = try @import("../domain/model_candidate_json.zig").decode(response_type, allocator, body);
                const claims = try allocator.alloc(r.extraction.Proposal, 2);
                claims[0] = response.claims.claims[0];
                claims[1] = .{ .content = .{ .technical = .{ .nodes = &.{.{ .literal = .{ .value = "Present the source-required confirmation at startup." } }} } }, .citations = claims[0].citations };
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
                if (options.disposition_sequence == .exhaust) {
                    const replacement: repair.Replacement = if (authorization.operation == .insert)
                        .{ .disposition = .{ .duplicate = .{ .target_claim_id = .{ .ordinal = 1 } } } }
                    else
                        .{ .disposition = .{ .superseded = .{ .related_claim_ids = &.{.{ .ordinal = 1 }} } } };
                    return @import("reference_reconciliation.zig").repairResponse(allocator, replacement);
                }
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
                    .disposition, .insert_disposition => .{ .disposition = .{ .retained = .{} } },
                    .insert_conflict => .{ .conflict_detail = .{ .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The supplied claims state conflicting outcomes." } }} } } },
                    else => return error.UnexpectedScriptedRepair,
                };
                return @import("reference_reconciliation.zig").repairResponse(allocator, replacement);
            }
            if (input.purpose == .summary) {
                if (options.global_sequence != null) return @import("summary_protocol_sequence.zig").response(allocator, input, if (input.progress.summary_count == 0 or options.attempt > 1) 3 else 1, .recover);
                if (options.summary_sequence) |mode| return @import("summary_protocol_sequence.zig").response(allocator, input, options.attempt, mode);
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
            const accepted = if (view.contains(.validated_reference_dispositions)) (try native.read(&view, reconciliation.dispositions_schema, .reconciliation_dispositions)).payload().reconciliation_dispositions else null;
            // Later phase responses follow accepted repairs, rather than
            // reintroducing the initial scripted relationship defect.
            if (falseConflict(options.source_loss) and (accepted == null or accepted.?.proposal.conflict_groups.len != 0)) {
                const claims = try allocator.alloc(r.ClaimId, 2);
                var count: usize = 0;
                for (input.progress.plan.layout.items.entries) |item| if (item.claim.content == .model and count < 2) {
                    claims[count] = item.claim.id;
                    count += 1;
                };
                if (count != 2) return error.InvalidConflictFixture;
                const dispositions = try allocator.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
                for (dispositions) |*value| {
                    if (std.meta.eql(value.claim_id, claims[0])) value.disposition = .{ .conflicting = .{ .related_claim_ids = claims[1..2] } };
                    if (std.meta.eql(value.claim_id, claims[1])) value.disposition = .{ .conflicting = .{ .related_claim_ids = claims[0..1] } };
                }
                proposal.claim_dispositions = dispositions;
                var signals: std.ArrayList(r.SignalProposal) = .empty;
                for (proposal.signals) |signal| if (!r.contains(r.ClaimId, claims, signal.claim_ids[0])) {
                    try signals.append(allocator, signal);
                };
                proposal.signals = try signals.toOwnedSlice(allocator);
                proposal.conflicts = &.{.{ .claim_ids = claims, .kind = .mutually_exclusive, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The source behavior and its presentation." } }} } }};
            }
            if (options.global_sequence != null) proposal = try @import("global_protocol_sequence.zig").mixed(allocator, input, proposal);
            if (options.disposition_sequence != null) {
                const signals = try allocator.dupe(r.SignalProposal, proposal.signals[0..1]);
                signals[0].claim_ids = try allocator.dupe(r.ClaimId, if (options.attempt == 1) &.{ input.items[0].claim.id, input.items[1].claim.id } else &.{input.items[0].claim.id});
                proposal.signals = signals;
                if (options.attempt > 1) proposal.claim_dispositions = proposal.claim_dispositions[0..1];
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
                    .summary_membership, .summary_text, .occupied_summary, .misbound_summary, .missing_entity_role, .unassigned_roles => {},
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
                        proposal.claim_dispositions = duplicate;
                    },
                    .mixed_selection => proposal = try @import("global_protocol_sequence.zig").mixed(allocator, input, proposal),
                    .signal_text => {
                        const signals = try allocator.dupe(r.SignalProposal, proposal.signals);
                        signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } };
                        proposal.signals = signals;
                    },
                    .duplicate_disposition => dispositions[1] = dispositions[0],
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
                        proposal.conflicts = if (fault == .conflict_coverage) &.{} else &.{.{ .claim_ids = &.{ dispositions[0].claim_id, dispositions[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } }};
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
            const current = try @import("../application/specification_workflow.zig").readSession(&view);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const dispositions = context.references.records.assignments.checked.prior.prior.dispositions;
            const first = for (dispositions) |disposition| {
                if (@import("../domain/reference_support.zig").eligibleClaim(disposition.disposition) and (try businessValue(allocator, (try r.item(all, disposition.claim_id)).claim)) != null) break disposition.claim_id;
            } else return error.InvalidFixture;
            const value = try attributed(allocator, all, &.{first});
            if (request.id().purpose == .atomic_repair) {
                const omission_schema = @import("../application/specification_omission_repair_workflow.zig").schema;
                if (view.contains(omission_schema.key)) {
                    const state = try @import("../application/specification_values.zig").storage.read(&view, omission_schema, .omission_repair);
                    const kind = try @import("../domain/specification_coverage_repair.zig").omissionRecordKind(state.authorization.rule.omission.requirement);
                    const replacement: g.spec.Wire.RecordProposal = .{ .content = switch (kind) {
                        .functional_requirement => .{ .functional_requirement = .{ .text = value.value } },
                        .acceptance_criterion => .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } },
                        else => return error.UnexpectedScriptedRepair,
                    } };
                    return @import("../domain/model_candidate_json.zig").encode(g.spec.Wire.RecordProposal, allocator, replacement);
                }
                if (view.contains(.specification_repair_authorization)) {
                    const state = try @import("../application/specification_values.zig").storage.read(&view, @import("../application/specification_repair_workflow.zig").authorization_schema, .repair_authorization);
                    const auth = state.authorization;
                    if (auth.operation == .replace and auth.operation.replace == .value) {
                        const wire = try @import("../domain/model_candidate_json.zig").encode(struct { value: g.spec.BusinessValue }, allocator, .{ .value = value.value });
                        return if (options.repeated_provenance_fault) try withForbiddenProvenance(allocator, wire) else wire;
                    }
                    if (auth.rule.group != null and auth.rule.group.? == .membership) {
                        const membership = auth.rule.group.?.membership;
                        const decision = membership.disposition;
                        var content_value = value.value;
                        if (options.failed_repair) content_value = .{ .segments = &.{.{ .literal = .{ .value = " " } }} };
                        const record: g.spec.Model.RecordProposal = .{ .content = if (decision == .required)
                            .{ .entity = .{ .name = content_value, .business_meaning = value.value, .relationships = &.{} } }
                        else
                            .{ .business_rule = .{ .text = content_value } }, .provenance = membership.fixed_provenance orelse value.provenance };
                        return @import("../domain/model_candidate_json.zig").encode(g.spec.Wire.RecordProposal, allocator, .{ .content = record.content });
                    }
                }
                return if (options.failed_repair) "{\"provenance\":{\"claim_ids\":[999999]}}" else error.UnexpectedScriptedRepair;
            }
            const unit = try @import("../domain/specification_session.zig").unit(current.completed);
            const assigned = try @import("../domain/specification_session.zig").currentBinding(allocator, current, context);
            if (options.script) |script| return @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, try g.ModelResponse.from(allocator, try scriptedContent(allocator, all, unit, script)));
            if (options.generation_gap and unit == .primary_user_story) return @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, .{ .clarification = .{ .reason = .missing, .question = .{ .value = value.value } } });
            var proposed: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
                .primary_user_story => .{ .primary_user_story = value },
                .entities => .{ .entities = .{ .disposition = if (options.entities_required) .required else .not_applicable, .basis = value } },
                .records => result: {
                    var records: std.ArrayList(g.spec.Model.RecordProposal) = .empty;
                    for (std.enums.values(g.spec.Kind)) |kind| {
                        const include_entity = if (!options.entities_required and options.contradict_entities)
                            (options.failed_repair or options.attempt == 1)
                        else
                            (options.entities_required != options.contradict_entities);
                        if (kind == .entity and include_entity and current.record_cursor == 0) {
                            const record: g.spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = value.value, .business_meaning = value.value, .relationships = &.{} } }, .provenance = value.provenance };
                            try records.append(allocator, record);
                            continue;
                        }
                        if (omittedKind(options, kind)) continue;
                        if ((kind != .functional_requirement and kind != .user_visible_outcome and kind != .acceptance_criterion) or (options.omit_exact and kind == .user_visible_outcome)) continue;
                        for (all.entries) |item| {
                            const retained = eligibleRecordClaim(dispositions, item.claim.id);
                            if (!retained or (try businessValue(allocator, item.claim)) == null or !r.contains(r.ClaimId, assigned.records.selection.claim_ids, item.claim.id)) continue;
                            const selected = try attributed(allocator, all, &.{item.claim.id});
                            if (kind == .acceptance_criterion and item.claim.content == .model) try records.append(allocator, .{ .content = .{ .acceptance_criterion = .{ .given = selected.value, .when = selected.value, .then = selected.value } }, .provenance = selected.provenance });
                            if (kind == .functional_requirement and item.claim.content == .model) try records.append(allocator, .{ .content = .{ .functional_requirement = .{ .text = selected.value } }, .provenance = selected.provenance });
                            if (kind == .user_visible_outcome and item.claim.content == .model and std.meta.eql(item.claim.id, try outcomeClaim(allocator, all, dispositions, item.claim.chunk_id))) for (all.entries) |exact_item| {
                                if (exact_item.claim.content != .preserved_token or !std.mem.eql(u8, exact_item.claim.chunk_id.bytes, item.claim.chunk_id.bytes)) continue;
                                const token = exact_item.claim.content.preserved_token;
                                const exact: g.spec.BusinessValue = if (options.normalize_exact)
                                    .{ .segments = try allocator.dupe(@import("../domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = token.value.raw_value.bytes } }}) }
                                else
                                    .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .exact_copy = .{ .claim_id = exact_item.claim.id } }}) };
                                try records.append(allocator, .{ .content = .{ .user_visible_outcome = .{ .text = exact } }, .provenance = selected.provenance });
                            };
                        }
                    }
                    break :result .{ .records = records.items };
                },
            } };
            if (unit == .brief) if (options.brief_text) |texts| {
                inline for (.{ "title", "description", "primary_goal" }, 0..) |field, index| {
                    @field(proposed.content.brief, field).value = try scriptedValue(allocator, all, .{ .bytes = texts[index] });
                }
            };
            if (options.repair and options.attempt == 1) {
                const invalid: g.spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = " " } }} };
                switch (unit) {
                    .brief => proposed.content.brief.title.value = invalid,
                    .primary_user_story => if (options.repair_across_units) {
                        proposed.content.primary_user_story.value = invalid;
                    },
                    .entities => if (options.repair_across_units) {
                        proposed.content.entities.basis.value = invalid;
                    },
                    .records => {},
                }
            }
            const wire = try @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, try g.ModelResponse.from(allocator, proposed));
            return wire;
        },
        .semantic_review => {
            const workflow = @import("../application/specification_support_workflow.zig");
            const progress = try workflow.progress(&view);
            if (workflow.purpose(progress) == .principles) {
                const policy_inputs = try workflow.inputs(&view, progress);
                const policy = @import("../domain/specification_support.zig").Contract(.principles);
                const selected_index = if (request.id().purpose == .atomic_repair) 0 else try reviewIndex(allocator, policy_inputs, try policy.nextSubject(allocator, policy_inputs, try workflow.prior(.principles, progress)));
                const findings = try allocator.alloc(policy.Finding, policy_inputs.seeds.len);
                const id = policy_inputs.principle_context.?.selection.chunks[0];
                for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = if (options.principle_conflict and index == 0) .conflicting else .compatible, .citations = if (options.principle_conflict and index == 0) &.{.{ .chunk = .{ .ordinal = 999 }, .first_line = 1, .last_line = 1 }} else &.{}, .detail = if (options.principle_conflict and index == 0) (if (options.applicability != null) "The output-only policy conflicts with the additional source-required output; Plan must resolve it." else "The business retention requirement conflicts with policy; Plan must resolve it.") else "" } };
                if (options.principle_fault) |fault| {
                    // Reproduce assignment/chunk confusion without changing native authority.
                    for (findings) |*finding| finding.value.citations = try allocator.dupe(@import("../domain/principle_registry.zig").Citation, &.{.{ .chunk = .{ .ordinal = finding.requirement_ordinal }, .first_line = 1, .last_line = 1 }});
                    if (request.id().purpose == .atomic_repair) {
                        const repair = @import("../domain/specification_support_repair.zig").Contract(.principles);
                        const state = try @import("../application/required_authority_values.zig").read(&view, @import("../application/specification_support_repair_workflow.zig").schema, .principle_support_repair);
                        const good = &[_]@import("../domain/principle_registry.zig").Citation{.{ .chunk = id, .first_line = 1, .last_line = 1 }};
                        if (state.authorization.operation == .insert) {
                            var value = findings[state.authorization.target.ordinal - 1].value;
                            value.citations = good;
                            return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, .{ .finding = value });
                        }
                        const citations: []const @import("../domain/principle_registry.zig").Citation = switch (fault) {
                            .recover => good,
                            .repeated => state.authorization.operation.replace.selection.citations,
                            .alternating => if (options.principle_repair_calls % 2 == 0) &.{.{ .chunk = id, .first_line = 1, .last_line = 2 }} else &.{.{ .chunk = .{ .ordinal = state.authorization.target.ordinal }, .first_line = 1, .last_line = 1 }},
                        };
                        return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, .{ .selection = .{ .citations = citations } });
                    }
                    return @import("../domain/model_candidate_json.zig").encode(policy.Value, allocator, findings[selected_index].value);
                }
                if (request.id().purpose == .atomic_repair) {
                    if (options.attempt == 1) return "{}";
                    return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/specification_support_repair.zig").Contract(.principles).Replacement, allocator, .{ .selection = .{ .citations = &.{.{ .chunk = id, .first_line = 1, .last_line = 1 }} } });
                }
                return @import("../domain/model_candidate_json.zig").encode(policy.Value, allocator, findings[selected_index].value);
            }
            const inputs = try @import("../application/required_authority_values.zig").read(&view, @import("../application/required_authority_workflow.zig").inputs_schema, .inputs);
            const ledger = try a.build(allocator, inputs);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const packet = try values.read(&view, requests.packet_schema, @import("../domain/model_input_packet.zig").Packet);
            if (options.evidence_fault == .empty_correction and options.attempt > 1) return "{}";
            if (packet.resultDefinition()) |definition| if (std.mem.eql(u8, definition.bytes, "preservation_comparisons")) {
                const prior = try workflow.prior(.source, progress);
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
                else if (options.candidate_omissions != null)
                    .{ .candidate = .{} }
                else
                    .{ .unlocalized = .{} };
                return @import("source_omission_evidence.zig").encode(allocator, try @import("../domain/specification_support.zig").Source.comparisonAssignment(allocator, inputs, context, candidate), location);
            };
            const selected_index = if (request.id().purpose == .atomic_repair) 0 else try reviewIndex(allocator, inputs, try @import("../domain/specification_support.zig").Source.nextSubject(allocator, inputs, try workflow.prior(.source, progress)));
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const findings = try allocator.alloc(@import("../domain/specification_support.zig").Source.Finding, ledger.requirements.len);
            for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
                const eligible = try @import("../domain/specification_support_evidence.zig").choices(allocator, inputs.references.?, requirement.seed.id);
                var selected: g.spec.Selection = .{ .claim_ids = if (eligible.len == 0) &.{} else eligible[0..1], .clarification_response_ids = &.{} };
                if (inputs.brief) |brief| if (requirement.seed.id.unit == .feature) {
                    selected = switch (requirement.seed.id.slot) {
                        .description => selection(brief.description.provenance),
                        .primary_goal => selection(brief.primary_goal.provenance),
                        else => selected,
                    };
                };
                switch (requirement.seed.id.unit) {
                    .token => |token| for (all.entries) |item| {
                        if (item.claim.content == .preserved_token and item.claim.content.preserved_token.value.id.ordinal == token.ordinal) selected = (try attributed(allocator, all, &.{item.claim.id})).provenance;
                    },
                    .signal => |id| for (context.references.records.signals) |signal| {
                        if (signal.id.ordinal == id.ordinal) selected = selection(.{ .claim_ids = signal.value.claim_ids, .citation_ids = signal.value.citation_ids, .clarification_response_ids = &.{} });
                    },
                    .conflict => |id| for (context.references.records.conflicts) |conflict| {
                        if (conflict.id.ordinal == id.ordinal) selected = selection(.{ .claim_ids = conflict.value.claim_ids, .citation_ids = conflict.value.citation_ids, .clarification_response_ids = &.{} });
                    },
                    .record => |id| if (inputs.specification) |content| {
                        for (content.records) |record| if (std.meta.eql(record.id, id)) {
                            selected = selection(record.proposal.provenance);
                        };
                    },
                    .feature => if (inputs.specification) |content| {
                        selected = switch (requirement.seed.id.slot) {
                            .display_name => selection(content.display_name.provenance),
                            .primary_user_story => selection(content.primary_user_story.provenance),
                            .entities => selection(content.entities.basis.provenance),
                            else => selected,
                        };
                    },
                    else => {},
                }
                const uncertain = options.uncertain or (options.brief_uncertain and inputs.brief != null and requirement.seed.id.slot == .description);
                const bound = try @import("../domain/specification_support_evidence.zig").expectedProvenance(allocator, inputs, context.inputs, requirement.seed.id);
                const unbound = eligible.len != 0 and bound == null and (requirement.seed.id.unit == .feature or requirement.seed.id.unit == .record);
                const conflict = requirement.seed.id.unit == .conflict or ((eligible.len == 0 or unbound) and context.references.records.conflicts.len != 0);
                const omission_kind: ?g.spec.Kind = switch (requirement.seed.id.slot) {
                    .functional_requirements => .functional_requirement,
                    .acceptance_criteria => .acceptance_criterion,
                    else => null,
                };
                const omission = if (omission_kind) |kind| omittedKind(options, kind) and inputs.specification != null and !g.spec.hasRecords(inputs.specification.?, kind) else false;
                finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .question = if (conflict) "Should the loan be renewed or rejected? Choose the required outcome." else if (uncertain and !omission) "Which renewal deadline applies? Supply the duration and starting event." else null, .kind = if (conflict) .conflicting else if (omission) .candidate_omission else if (uncertain) .ambiguous else if (unbound) .inconclusive else .supported, .provenance = selected, .source_ids = &.{}, .detail = if (conflict) "Should the loan be renewed or rejected? The sources disagree." else if (omission) "The specification omits the source-supported requirement." else if (uncertain) "Which renewal deadline applies? The sources do not settle it." else if (unbound) "No validated source group binds this requirement." else "" } };
                if (omission) finding.value.source_ids = &.{context.inputs.corpus.sources[0].id};
                if (falseConflict(options.source_loss) and options.source_loss != .false_conflict_questions and requirement.seed.id.unit == .conflict) {
                    finding.value.kind = .candidate_omission;
                    finding.value.question = null;
                    finding.value.detail = "The source meanings are compatible; the false conflict discarded their supported behavior.";
                    finding.value.loss = .{ .reconciliation_conflict = requirement.seed.id.unit.conflict };
                    finding.value.source_ids = &.{context.inputs.corpus.sources[0].id};
                }
                if (options.source_gaps and requirement.seed.id.kind == .feature_intent and requirement.seed.id.unit == .feature) finding.value = .{ .kind = .unsupported, .question = switch (requirement.seed.id.slot) {
                    .display_name => "What should users call this feature? Supply its display name.",
                    .description => "What behavior should this feature provide? Describe the expected result.",
                    .primary_goal => "Which user outcome takes priority? Name the primary goal.",
                    .primary_user_story => "Who uses this feature and why? Name the user and intended benefit.",
                    .acceptance_criteria => "Which observable outcome counts as success? State the pass/fail condition.",
                    .functional_requirements => "What should happen when renewal is requested? State the required behavior.",
                    .scenario_coverage => "What should happen when renewal is refused? Describe that scenario outcome.",
                    else => return error.UnexpectedSourceGap,
                }, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "The source leaves this decision unspecified." };
                if (options.extraction_omission) finding.value = .{ .kind = .candidate_omission, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{context.inputs.corpus.sources[0].id}, .detail = "Extraction discarded the source-required behavior and exact message." };
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
                    findings[target_index].value = .{ .kind = .candidate_omission, .loss = location, .detail = "Preserve the source-required deadline.", .source_ids = try allocator.dupe(r.extraction.identity.SourceId, &.{context.inputs.corpus.sources[0].id}), .provenance = .{ .claim_ids = if (location == .reconciliation_signal) context.references.records.signals[location.reconciliation_signal.ordinal - 1].value.claim_ids else &.{}, .clarification_response_ids = &.{} } };
                }
            }
            if (request.id().purpose == .atomic_repair) {
                const repair = @import("../domain/specification_support_repair.zig").Source;
                const state = try @import("../application/required_authority_values.zig").read(&view, @import("../application/specification_support_repair_workflow.zig").schema, .support_repair);
                const authorized = state.authorization;
                if (options.applicability == .missing_text) return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, .{ .detail = .{ .detail = applicability_detail, .question = applicability_question } });
                if (options.source_loss == .false_conflict_questions) return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, .{ .detail = .{ .detail = findings[authorized.target.ordinal - 1].value.detail, .question = "Which behavior is intended? State the action and date to display." } });
                if (options.support_fault) |fault| switch (fault) {
                    .question_evidence_recover, .question_evidence_exhaust, .question_evidence_alternating => {
                        var replacement = authorized.operation.replace;
                        if (replacement != .detail) return error.InvalidFixture;
                        replacement.detail.question = "What duration applies? State the duration and starting event.";
                        return sourceRepairWire(allocator, inputs, context, authorized, replacement);
                    },
                    .question_recover, .question_exhaust, .question_native_exhaust, .question_mixed_exhaust => {
                        var replacement: repair.Replacement = .{ .detail = .{
                            .detail = "The source establishes the action; its duration is unspecified.",
                            .question = "What duration applies? State the duration and starting event.",
                        } };
                        switch (fault) {
                            .question_recover => if (options.attempt == 1) {
                                replacement.detail.question = null;
                            },
                            .question_exhaust => replacement.detail.question = null,
                            .question_native_exhaust => if (options.support_merges == 0) {
                                replacement.detail.detail = " ";
                            } else {
                                replacement.detail.question = " ";
                            },
                            .question_mixed_exhaust => replacement.detail.question = if (options.attempt == 1) null else " ",
                            else => unreachable,
                        }
                        return sourceRepairWire(allocator, inputs, context, authorized, replacement);
                    },
                    else => {},
                };
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
                    if (inputs.specification == null) finding.value.kind = .not_applicable;
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
            if (options.support_fault) |fault| {
                switch (fault) {
                    .inconclusive => {
                        findings[0].value.kind = .inconclusive;
                        findings[0].value.detail = "No missing user decision was established; interpretation remains inconclusive.";
                        findings[0].value.question = null;
                    },
                    .question_evidence_recover, .question_evidence_exhaust, .question_evidence_alternating => {
                        for (findings[0..4]) |*finding| {
                            finding.value.kind = .unsupported;
                            finding.value.detail = "The source establishes the action; its duration is unspecified.";
                            finding.value.question = " ";
                        }
                        for (ledger.requirements, findings) |requirement, *finding| if (requirement.seed.id.kind == .entity_applicability) {
                            if (inputs.specification == null) finding.value.kind = .not_applicable;
                            finding.value.source_ids = if (options.attempt == 1 or fault == .question_evidence_exhaust or fault == .question_evidence_alternating) &.{.{ .ordinal = if (fault == .question_evidence_alternating) 999999 + options.attempt else 999999 }} else &.{context.inputs.corpus.sources[0].id};
                        };
                    },
                    .question_recover, .question_exhaust, .question_native_exhaust, .question_mixed_exhaust => {
                        for (findings[0..2]) |*finding| {
                            finding.value.kind = .unsupported;
                            finding.value.detail = "The source establishes the action; its duration is unspecified.";
                            finding.value.question = " ";
                        }
                    },
                    .missing_detail => {
                        findings[0].value.kind = .ambiguous;
                        findings[0].value.question = "Which renewal deadline applies? Supply a duration and starting event.";
                        findings[0].value.detail = if (options.attempt == 1) "" else "The source leaves the renewal deadline unspecified.";
                    },
                    .foreign_source_single => if (options.attempt == 1) {
                        findings[0].value.source_ids = &.{.{ .ordinal = 999999 }};
                    },
                    .foreign_sources => {
                        // Foreign source IDs now fail protocol admission. The
                        // immutable correction supplies eligible source evidence.
                        if (options.attempt == 1) for ([_]usize{ 1, 4, 5, 6, 7, 8, 10 }) |index| {
                            findings[index].value.source_ids = &.{.{ .ordinal = 2 }};
                        };
                    },
                }
            }
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
                        finding.value.kind = if (inputs.specification == null) .not_applicable else .supported;
                        finding.value.detail = "The source requires calculated output, with no business records needed for that behavior.";
                    },
                    .entities => {},
                    .missing_decision, .missing_text => {
                        finding.value.kind = .ambiguous;
                        finding.value.detail = applicability_detail;
                        finding.value.question = if (mode == .missing_text) " " else applicability_question;
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
fn businessValue(allocator: std.mem.Allocator, claim: r.extraction.Claim) !?g.spec.BusinessValue {
    return switch (claim.content) {
        .model => |model| switch (model) {
            .business, .scope_guard => |value| .{ .segments = value.value.segments },
            else => null,
        },
        .preserved_token => .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .exact_copy = .{ .claim_id = claim.id } }}) },
    };
}

fn eligibleRecordClaim(dispositions: []const r.ClaimDisposition, id: r.ClaimId) bool {
    for (dispositions) |disposition| if (std.meta.eql(disposition.claim_id, id)) return @import("../domain/reference_support.zig").eligibleClaim(disposition.disposition);
    return false;
}

/// This fake chooses one business claim per chunk to author its exact outcomes.
/// Other groups still receive their own requirements and acceptance criteria.
fn outcomeClaim(allocator: std.mem.Allocator, all: r.Items, dispositions: []const r.ClaimDisposition, chunk: r.extraction.identity.ChunkId) !r.ClaimId {
    for (all.entries) |item| {
        if (item.claim.content != .model or !item.claim.chunk_id.eql(chunk) or !eligibleRecordClaim(dispositions, item.claim.id)) continue;
        if ((try businessValue(allocator, item.claim)) != null) return item.claim.id;
    }
    return error.InvalidFixture;
}
fn attributed(allocator: std.mem.Allocator, all: r.Items, ids: []const r.ClaimId) !g.spec.Model.AttributedValue {
    const value = (try businessValue(allocator, (try r.item(all, ids[0])).claim)) orelse return error.InvalidFixture;
    return .{ .value = value, .provenance = .{ .claim_ids = try allocator.dupe(r.ClaimId, ids), .clarification_response_ids = &.{} } };
}

fn scriptedContent(allocator: std.mem.Allocator, all: r.Items, unit: g.Unit, script: @import("specification_script.zig").Script) !g.Response {
    const ids = try allocator.alloc(r.ClaimId, all.entries.len);
    for (all.entries, ids) |item, *id| id.* = item.claim.id;
    const provenance = (try attributed(allocator, all, ids)).provenance;
    const document = script.document;
    return .{ .content = switch (unit) {
        .brief => .{ .brief = .{
            .title = .{ .value = try scriptedValue(allocator, all, document.display_name), .provenance = provenance },
            .description = .{ .value = try scriptedValue(allocator, all, .{ .bytes = script.description }), .provenance = provenance },
            .primary_goal = .{ .value = try scriptedValue(allocator, all, .{ .bytes = script.primary_goal }), .provenance = provenance },
        } },
        .primary_user_story => .{ .primary_user_story = .{ .value = try scriptedValue(allocator, all, document.primary_user_story), .provenance = provenance } },
        .entities => .{ .entities = .{ .disposition = if (document.entity_section == .present) .required else .not_applicable, .basis = .{ .value = try scriptedValue(allocator, all, .{ .bytes = script.entity_basis }), .provenance = provenance } } },
        .records => records: {
            var result: std.ArrayList(g.spec.Model.RecordProposal) = .empty;
            for (document.records) |record| {
                switch (record.content) {
                    inline else => |fields, tag| {
                        var content: @FieldType(g.spec.Content(g.spec.BusinessValue), @tagName(tag)) = undefined;
                        inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                            const raw = @field(fields, field.name);
                            if (comptime field.type == g.spec.Scalar) {
                                @field(content, field.name) = try scriptedValue(allocator, all, raw);
                            } else {
                                const relationships = try allocator.alloc(g.spec.BusinessValue, raw.len);
                                for (raw, relationships) |value, *converted| converted.* = try scriptedValue(allocator, all, value);
                                @field(content, field.name) = relationships;
                            }
                        }
                        try result.append(allocator, .{ .content = @unionInit(g.spec.Content(g.spec.BusinessValue), @tagName(tag), content), .provenance = provenance });
                    },
                }
            }
            break :records .{ .records = result.items };
        },
    } };
}

fn scriptedValue(allocator: std.mem.Allocator, all: r.Items, scalar: g.spec.Scalar) !g.spec.BusinessValue {
    if (scalar.code_spans.len != 0) {
        if (scalar.code_spans.len != 1 or scalar.code_spans[0].start != 0 or scalar.code_spans[0].end != scalar.bytes.len) return error.InvalidSpecificationScript;
        for (all.entries) |item| {
            if (item.claim.content == .preserved_token) {
                const token = item.claim.content.preserved_token;
                if (std.mem.eql(u8, token.value.raw_value.bytes, scalar.bytes)) return .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .exact_copy = .{ .claim_id = item.claim.id } }}) };
            }
        }
        return error.InvalidSpecificationScript;
    }
    // Script strings are retained by the invocation's arena.
    return .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = scalar.bytes } }}) };
}

fn selection(value: g.spec.Provenance) g.spec.Selection {
    return .{ .claim_ids = value.claim_ids, .clarification_response_ids = value.clarification_response_ids };
}

fn extractedClaim(allocator: std.mem.Allocator, chunk: r.evidence.identity.ChunkId) ![]const u8 {
    return std.fmt.allocPrint(allocator, "The outcome from reference unit {s} is observable.", .{chunk.bytes});
}

/// The scripted complete source remains one fixture; each provider call gets
/// only its configured fields. Protocol faults are injected afterward
/// by Driver, so this projection cannot repair or conceal a malformed response.
fn partResponse(allocator: std.mem.Allocator, request: *const @import("../domain/model_request_handoff.zig").Request, body: []const u8, fault: ?ReconciliationFault) ![]const u8 {
    const part = request.part() orelse {
        const bound = request.packet() orelse return body;
        const definition = bound.resultDefinition() orelse return body;
        const field: ?[]const u8 = if (std.mem.eql(u8, definition.bytes, "dispositions_assignment")) "claim_dispositions" else if (std.mem.eql(u8, definition.bytes, "signals_assignment")) "signals" else if (std.mem.eql(u8, definition.bytes, "roles_assignment")) "role_decisions" else if (std.mem.eql(u8, definition.bytes, "conflicts_assignment")) "conflicts" else null;
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
            } else if (std.mem.eql(u8, name, "role_decisions")) {
                const packet = try std.json.parseFromSlice(std.json.Value, allocator, (request.packet() orelse return error.InvalidSpecificationScript).body(), .{});
                const groups = packet.value.object.get("accepted").?.object.get("signals").?.array.items;
                var assignments: std.ArrayList(r.RoleAssignment) = .empty;
                for (groups) |group| {
                    if (fault == .unassigned_roles) continue;
                    const content = group.object.get("value").?.object.get("content").?.object;
                    if (!std.mem.eql(u8, content.get("kind").?.string, "model") or !std.mem.eql(u8, content.get("model").?.object.get("kind").?.string, "business")) continue;
                    var roles: std.ArrayList(r.GenerationRole) = .empty;
                    if (assignments.items.len == 0) {
                        for (std.enums.values(r.GenerationRole)) |role| {
                            if (fault == .missing_entity_role and role == .entity_basis) continue;
                            try roles.append(allocator, role);
                        }
                    } else try roles.append(allocator, .records);
                    try assignments.append(allocator, .{ .signal_id = .{ .ordinal = @intCast(group.object.get("signal_id").?.integer) }, .generation_roles = try roles.toOwnedSlice(allocator) });
                }
                const decisions = try @import("reference_reconciliation.zig").roleDecisions(allocator, assignments.items);
                const wire = try @import("../domain/model_candidate_json.zig").encode(r.RoleDecisions, allocator, decisions);
                try result.put(allocator, name, (try std.json.parseFromSlice(std.json.Value, allocator, wire, .{})).value);
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

fn omittedKind(options: Options, kind: g.spec.Kind) bool {
    const selected = options.candidate_omissions orelse return false;
    return kind == .functional_requirement or (selected == .acceptance_and_functional and kind == .acceptance_criterion);
}

pub fn withForbiddenProvenance(allocator: std.mem.Allocator, wire: []const u8) ![]const u8 {
    var decoded = try std.json.parseFromSlice(std.json.Value, allocator, wire, .{});
    defer decoded.deinit();
    try decoded.value.object.put(allocator, "provenance", .{ .object = .{} });
    return std.json.Stringify.valueAlloc(allocator, decoded.value, .{});
}
