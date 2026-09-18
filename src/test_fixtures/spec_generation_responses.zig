//! Shared scripted provider candidate data. No workflow execution or test loop.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const values = @import("../application/pipeline_values.zig");
const r = @import("../domain/reference_reconciliation.zig");
const g = @import("../domain/specification_generation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const a = @import("../domain/required_authority.zig");
pub const ReconciliationFault = enum { summary_membership, duplicate_disposition, self_relation, cycle, signal_coverage, mixed_selection, conflict_coverage, summary_text, signal_text, conflict_text, occupied_summary, occupied_signals, occupied_conflict, permuted_disposition, permuted_conflict_disposition };
pub const SupportFault = enum { missing_detail, foreign_provenance, missing_finding, duplicate_finding, partial_findings, two_missing_findings, foreign_sources };
pub const SourceLoss = enum { empty, partial, classification, signal, post_generation, unchanged };
pub const Options = struct {
    disposition_sequence: ?enum { recover, exhaust } = null,
    attempt: u32 = 1,
    source_loss: ?SourceLoss = null,
    support_fault: ?SupportFault = null,
    support_merges: usize = 0,
    support_post: bool = false,
    principle_conflict: bool = false,
    source_gaps: bool = false,
    evidence_fault: ?enum { recover, unchanged } = null,
    candidate_omissions: ?enum { functional, acceptance_and_functional } = null,
    extraction_omission: bool = false,
    text_fault: bool = false,
    failed_text_repair: bool = false,
    reconciliation_repair_fault: ?enum { unchanged, alternating, unchanged_text } = null,
    reconciliation_fault: ?ReconciliationFault = null,
    script: ?@import("specification_script.zig").Script = null,
    uncertain: bool = false,
    brief_uncertain: bool = false,
    repair: bool = false,
    failed_repair: bool = false,
    omit_exact: bool = false,
    citation_fault: ?enum { unknown, missing } = null,
    failed_citation_repair: bool = false,
    missing_classifications: bool = false,
    failed_classification_repair: bool = false,
    entities_required: bool = false,
    generation_gap: bool = false,
};

pub fn build(allocator: std.mem.Allocator, view: data.View, options: Options) ![]const u8 {
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
                        return @import("../domain/model_candidate_json.zig").encode(r.extraction.tokens.Classification, allocator, .{ .preserve = .{ .token_candidate_id = id, .kind = .business_exact_string } });
                    }
                    return @import("../domain/model_candidate_json.zig").encode(r.extraction.Proposal, allocator, .{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Preserve the source-required deadline." } }} } }, .citations = &.{@import("../reference_extraction_test.zig").wholeChunk(chunk)} });
                }
                if (std.mem.eql(u8, packet.resultDefinition().?.bytes, "business_text_replacement")) {
                    const replacement: @import("../domain/reference_extraction_text_repair.zig").Replacement = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = if (options.failed_text_repair) "unbound/reference.md" else try extractedClaim(allocator, chunk.id) } }} } };
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
            const claim = if (options.script) |script| (try @import("specification_script.zig").extraction(script, selected_chunk.bytes)).claim else try extractedClaim(allocator, chunk.id);
            const citation: @import("../domain/source_selections.zig").Selection = if (options.citation_fault == .unknown) .{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } } else @import("../reference_extraction_test.zig").wholeChunk(chunk);
            const body = try @import("../domain/model_candidate_json.zig").encode(@import("../domain/reference_extraction_parser.zig").Response, allocator, .{ .claims = .{ .claims = &.{.{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = if (options.text_fault) "unbound/reference.md" else claim } }} } }, .citations = if (options.citation_fault == .missing) &.{} else &.{citation} }}, .token_classifications = &.{} } });
            const choices = try allocator.dupe(r.extraction.tokens.Classification, try @import("reference_tokens.zig").classifications(allocator, candidates, chunk));
            if (options.source_loss == .classification) for (choices) |*choice| {
                choice.* = .{ .irrelevant = choice.id() };
            };
            return @import("reference_tokens.zig").wire(allocator, body, if (options.missing_classifications) &.{} else choices);
        },
        .reference_global => {
            const input = (try native.read(&view, @import("../application/reference_reconciliation_workflow.zig").input_schema, .reconciliation_input)).payload().reconciliation_input;
            if (request.id().purpose == .atomic_repair) {
                const repair = @import("../domain/reference_reconciliation_repair.zig");
                if (view.contains(.source_omission_repair)) {
                    const auth = (try @import("../application/source_omission_repair_workflow.zig").read(&view)).authorization.reconciliation;
                    if (options.source_loss == .unchanged) return @import("reference_reconciliation.zig").repairResponse(allocator, auth.operation.replace);
                    const claim = (try r.item(input.progress.plan.layout.items, auth.dependencies.reconciliation.proposal.global.signals[auth.target.signal_content].claim_ids[0])).claim;
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
                    const replacement: repair.Replacement = if (fault == .alternating and authorization.revision % 2 == 0)
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
                    return std.json.Stringify.valueAlloc(allocator, .{ .claim_ids = choices }, .{});
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
                var proposal = try @import("reference_reconciliation.zig").summary(allocator, input);
                if (options.reconciliation_fault == .occupied_summary) {
                    const statements = try allocator.alloc(r.StatementProposal, proposal.statements.len + 1);
                    @memcpy(statements[0..proposal.statements.len], proposal.statements);
                    statements[proposal.statements.len] = .{ .local_key = @intCast(statements.len), .claim_ids = &.{}, .content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different proposed meaning." } }} } } } };
                    proposal.statements = statements;
                }
                if (options.reconciliation_fault == .summary_membership) proposal.statements = proposal.statements[1..];
                if (options.reconciliation_fault == .summary_text and input.progress.summary_count == 0) {
                    const statements = try allocator.dupe(r.StatementProposal, proposal.statements);
                    statements[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Display \\\"a result\\\"." } }} } } };
                    proposal.statements = statements;
                }
                return @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), allocator, .{ .summary = proposal });
            }
            var proposal = try @import("reference_reconciliation.zig").global(allocator, input);
            if (options.disposition_sequence != null) {
                const signals = try allocator.dupe(r.SignalProposal, proposal.signals[0..1]);
                signals[0].claim_ids = try allocator.dupe(r.ClaimId, &.{ input.items[0].claim.id, input.items[1].claim.id });
                proposal.signals = signals;
                if (options.attempt > 1) proposal.claim_dispositions = proposal.claim_dispositions[0..1];
                const json = @import("../domain/model_candidate_json.zig");
                const body = try json.encodeSelected(@FieldType(r.Parsed, "proposal"), allocator, .{ .global = proposal });
                if (options.attempt > 1) return body;
                var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
                _ = parsed.value.object.getPtr("signals").?.array.items[0].object.getPtr("content").?.object.swapRemove("kind");
                return std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
            }
            if (options.source_loss == .signal or options.source_loss == .post_generation or options.source_loss == .unchanged) {
                const signals = try allocator.dupe(r.SignalProposal, proposal.signals);
                signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Incomplete signal." } }} } } };
                proposal.signals = signals;
            }
            if (options.reconciliation_fault) |fault| {
                const dispositions = try allocator.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
                proposal.claim_dispositions = dispositions;
                switch (fault) {
                    .summary_membership, .summary_text, .occupied_summary => {},
                    .occupied_signals => {
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
                            for (related, conflicts) |id, *conflict| conflict.* = .{ .claim_ids = try allocator.dupe(r.ClaimId, &.{ dispositions[0].claim_id, id }), .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The supplied outcomes differ." } }} }, .resolution = .unresolved };
                            proposal.conflicts = conflicts;
                        }
                        duplicate[dispositions.len] = duplicate[0];
                        const reversed = try allocator.dupe(r.ClaimId, &.{ related[1], related[0] });
                        if (fault == .permuted_conflict_disposition) duplicate[dispositions.len].disposition.conflicting.related_claim_ids = reversed else duplicate[dispositions.len].disposition.superseded.related_claim_ids = reversed;
                        proposal.claim_dispositions = duplicate;
                    },
                    .mixed_selection => {
                        const signals = try allocator.dupe(r.SignalProposal, proposal.signals);
                        const token = for (input.items) |item| {
                            if (item.claim.content == .preserved_token) break item.claim.id;
                        } else return error.UnexpectedScriptedRepair;
                        signals[0].claim_ids = try allocator.dupe(r.ClaimId, &.{ signals[0].claim_ids[0], token });
                        proposal.signals = signals;
                    },
                    .signal_text => {
                        const signals = try allocator.dupe(r.SignalProposal, proposal.signals);
                        signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Display \\\"a result\\\"." } }} } } };
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
                        proposal.conflicts = if (fault == .conflict_coverage) &.{} else &.{.{ .claim_ids = &.{ dispositions[0].claim_id, dispositions[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "Display \\\"a result\\\"." } }} }, .resolution = .unresolved }};
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
            return @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), allocator, .{ .global = proposal });
        },
        .specification_unit => {
            const current = try @import("../application/specification_workflow.zig").readSession(&view);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const dispositions = context.references.records.assignments.checked.prior.prior.dispositions;
            const first = for (dispositions) |disposition| {
                if (@import("../domain/specification_provenance.zig").eligibleClaim(disposition.disposition)) break disposition.claim_id;
            } else return error.InvalidFixture;
            const value = try attributed(allocator, all, &.{first});
            if (request.id().purpose == .atomic_repair) {
                const omission_schema = @import("../application/specification_omission_repair_workflow.zig").schema;
                if (view.contains(omission_schema.key)) {
                    const state = try @import("../application/specification_values.zig").storage.read(&view, omission_schema, .omission_repair);
                    const kind = (try @import("../domain/specification_session.zig").unit(state.authorization.target.unit)).records;
                    const replacement: @import("../domain/specification_coverage_repair.zig").Replacement = .{ .record = .{ .content = switch (kind) {
                        .functional_requirement => .{ .functional_requirement = .{ .text = value.value } },
                        .acceptance_criterion => .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } },
                        else => return error.UnexpectedScriptedRepair,
                    }, .provenance = value.provenance } };
                    return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/specification_coverage_repair.zig").Replacement, allocator, replacement);
                }
                var replacement = value;
                if (options.failed_repair) replacement.provenance.claim_ids = &.{.{ .ordinal = 999999 }};
                return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/specification_repair.zig").Replacement, allocator, .{ .provenance = replacement.provenance });
            }
            const unit = try @import("../domain/specification_session.zig").unit(current.completed);
            if (options.script) |script| return @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, g.ModelResponse.from(try scriptedContent(allocator, all, unit, script)));
            if (options.generation_gap and unit == .primary_user_story) return @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, .{ .clarification = .{ .reason = .missing, .question = value } });
            var proposed: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
                .primary_user_story => .{ .primary_user_story = value },
                .entities => .{ .entities = .{ .disposition = if (options.entities_required) .required else .not_applicable, .basis = value } },
                .records => |kind| result: {
                    if (kind == .entity and options.entities_required) {
                        const record: g.spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = value.value, .business_meaning = value.value, .relationships = &.{} } }, .provenance = value.provenance };
                        break :result .{ .records = try allocator.dupe(g.spec.Model.RecordProposal, &.{record}) };
                    }
                    if (omittedKind(options, kind)) break :result .{ .records = &.{} };
                    if ((kind != .functional_requirement and kind != .user_visible_outcome and kind != .acceptance_criterion) or (options.omit_exact and kind == .user_visible_outcome)) break :result .{ .records = &.{} };
                    var records: std.ArrayList(g.spec.Model.RecordProposal) = .empty;
                    for (all.entries) |item| {
                        const retained = for (dispositions) |disposition| {
                            if (std.meta.eql(disposition.claim_id, item.claim.id)) break @import("../domain/specification_provenance.zig").eligibleClaim(disposition.disposition);
                        } else false;
                        if (!retained) continue;
                        const selected = try attributed(allocator, all, &.{item.claim.id});
                        if (kind == .acceptance_criterion and item.claim.content == .model) try records.append(allocator, .{ .content = .{ .acceptance_criterion = .{ .given = selected.value, .when = selected.value, .then = selected.value } }, .provenance = selected.provenance });
                        if (kind == .functional_requirement and item.claim.content == .model) try records.append(allocator, .{ .content = .{ .functional_requirement = .{ .text = selected.value } }, .provenance = selected.provenance });
                        if (kind == .user_visible_outcome and item.claim.content == .preserved_token) try records.append(allocator, .{ .content = .{ .user_visible_outcome = .{ .text = .{ .exact_copy = .{ .token_id = item.claim.content.preserved_token.value.id, .citation_id = item.claim.content.preserved_token.citation_id } } } }, .provenance = selected.provenance });
                    }
                    break :result .{ .records = records.items };
                },
            } };
            if (options.repair and unit == .brief) proposed.content.brief.description.provenance.claim_ids = &.{.{ .ordinal = 999999 }};
            return @import("../domain/model_candidate_json.zig").encode(g.ModelResponse, allocator, g.ModelResponse.from(proposed));
        },
        .semantic_review => {
            const workflow = @import("../application/specification_support_workflow.zig");
            const progress = try workflow.progress(&view);
            if (workflow.purpose(progress) == .principles) {
                const policy_inputs = try workflow.inputs(&view, progress);
                const policy = @import("../domain/specification_support.zig").Contract(.principles);
                const findings = try allocator.alloc(policy.Finding, policy_inputs.seeds.len);
                const id = policy_inputs.principle_context.?.selection.chunks[0];
                for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = if (options.principle_conflict and index == 0) .conflicting else .compatible, .citations = if (options.principle_conflict and index == 0) &.{.{ .chunk = .{ .ordinal = 999 }, .first_line = 1, .last_line = 1 }} else &.{}, .detail = if (options.principle_conflict and index == 0) "The business retention requirement conflicts with policy; Plan must resolve it." else "" } };
                if (request.id().purpose == .atomic_repair) {
                    if (options.attempt == 1) return "{}";
                    return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/specification_support_repair.zig").Contract(.principles).Replacement, allocator, .{ .selection = .{ .citations = &.{.{ .chunk = id, .first_line = 1, .last_line = 1 }} } });
                }
                return @import("../domain/model_candidate_json.zig").encode(policy.Review, allocator, .{ .entries = findings });
            }
            const inputs = try @import("../application/required_authority_values.zig").read(&view, @import("../application/required_authority_workflow.zig").inputs_schema, .inputs);
            const ledger = try a.build(allocator, inputs);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
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
                        if (signal.id.ordinal == id.ordinal) selected = (try attributed(allocator, all, signal.value.claim_ids)).provenance;
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
                const conflict = requirement.seed.id.unit == .conflict or (eligible.len == 0 and context.references.records.conflicts.len != 0);
                const omission_kind: ?g.spec.Kind = switch (requirement.seed.id.slot) {
                    .functional_requirements => .functional_requirement,
                    .acceptance_criteria => .acceptance_criterion,
                    else => null,
                };
                const omission = if (omission_kind) |kind| omittedKind(options, kind) and inputs.specification != null and !g.spec.hasRecords(inputs.specification.?, kind) else false;
                finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = if (conflict) .conflicting else if (omission) .candidate_omission else if (uncertain) .ambiguous else .supported, .provenance = selected, .source_ids = &.{}, .detail = if (conflict) "Should the loan be renewed or rejected? The sources disagree." else if (omission) "The specification omits the source-supported requirement." else if (uncertain) "Which renewal deadline applies? The sources do not settle it." else "" } };
                if (options.source_gaps and requirement.seed.id.kind == .feature_intent and requirement.seed.id.unit == .feature) finding.value = .{ .decision = .unsupported, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "The source leaves this decision unspecified." };
                if (options.extraction_omission) finding.value = .{ .decision = .candidate_omission, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{context.inputs.corpus.sources[0].id}, .detail = "Extraction discarded the source-required behavior and exact message." };
            }
            if (options.source_loss) |mode| {
                const candidate = (try native.read(&view, native.text_schema, .text_validated)).payload().text_validated;
                const first = candidate.entries[0];
                var location: @import("../domain/source_omission.zig").Location = .{ .unlocalized = .{} };
                if ((mode == .empty and first.outcome == .no_feature_claim) or (mode == .partial and first.outcome == .claims and first.outcome.claims.len == 1)) {
                    location = .{ .extraction_claim = first.scope.chunk_id };
                } else if (mode == .empty or mode == .classification) {
                    for (first.token_classifications) |classification| if (classification == .irrelevant) {
                        location = .{ .token_classification = classification.id() };
                        break;
                    };
                } else if (mode != .post_generation or inputs.specification != null) {
                    for (context.references.records.signals) |signal| if (signal.value.content == .model and signal.value.content.model == .business and signal.value.content.model.business.value.segments.len == 1 and signal.value.content.model.business.value.segments[0] == .literal and std.mem.eql(u8, signal.value.content.model.business.value.segments[0].literal.value, "Incomplete signal.")) {
                        location = .{ .reconciliation_signal = signal.id };
                        break;
                    };
                }
                if (location != .unlocalized) {
                    if (all.entries.len == 0) for (findings) |*finding| {
                        finding.value.decision = .candidate_omission;
                        finding.value.detail = "Extraction lost source-required behavior.";
                        finding.value.source_ids = try allocator.dupe(r.extraction.identity.SourceId, &.{context.inputs.corpus.sources[0].id});
                    };
                    findings[0].value = .{ .decision = .candidate_omission, .loss = location, .detail = "Preserve the source-required deadline.", .source_ids = try allocator.dupe(r.extraction.identity.SourceId, &.{context.inputs.corpus.sources[0].id}), .provenance = .{ .claim_ids = if (location == .reconciliation_signal) context.references.records.signals[location.reconciliation_signal.ordinal - 1].value.claim_ids else &.{}, .clarification_response_ids = &.{} } };
                }
            }
            if (request.id().purpose == .atomic_repair) {
                const repair = @import("../domain/specification_support_repair.zig").Source;
                const state = try @import("../application/required_authority_values.zig").read(&view, @import("../application/specification_support_repair_workflow.zig").schema, .support_repair);
                const authorized = state.authorization;
                if (options.evidence_fault == .unchanged) return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, authorized.operation.replace);
                if (options.support_fault == .foreign_sources and options.support_merges == 0) return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, authorized.operation.replace);
                var value = findings[authorized.target.ordinal - 1].value;
                if (options.support_fault == .foreign_sources) value.source_ids = &.{context.inputs.corpus.sources[0].id};
                if (options.support_fault == .partial_findings) {
                    if (authorized.operation == .replace) return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, authorized.operation.replace);
                    value.provenance.claim_ids = &.{.{ .ordinal = @intCast(all.entries.len + 1) }};
                }
                const kind = switch (authorized.operation) {
                    .replace => |replacement| std.meta.activeTag(replacement),
                    .insert => |kind| kind,
                    .delete => return error.InvalidFixture,
                };
                const replacement: repair.Replacement = switch (kind) {
                    .detail => .{ .detail = .{ .detail = "Which renewal deadline applies? The sources do not settle it." } },
                    .selection => .{ .selection = .{ .provenance = value.provenance, .source_ids = value.source_ids } },
                    .finding => .{ .finding = value },
                };
                return @import("../domain/model_candidate_json.zig").encodeSelected(repair.Replacement, allocator, replacement);
            }
            var entries: []const @import("../domain/specification_support.zig").Source.Finding = findings;
            if (options.evidence_fault != null) for (ledger.requirements, findings) |requirement, *finding| {
                if (requirement.seed.id.kind == .entity_applicability) {
                    finding.value.decision = .not_applicable;
                    finding.value.provenance.claim_ids = &.{};
                } else if (requirement.seed.id.unit == .token) {
                    finding.value.provenance.claim_ids = &.{all.entries[0].claim.id};
                } else {
                    finding.value.decision = .unsupported;
                    finding.value.provenance.claim_ids = &.{};
                    finding.value.detail = "The source does not settle this requirement.";
                }
                finding.value.source_ids = &.{context.inputs.corpus.sources[0].id};
            };
            if (options.support_fault) |fault| if ((inputs.specification != null) == options.support_post) {
                switch (fault) {
                    .missing_detail => {
                        findings[0].value.decision = .ambiguous;
                        findings[0].value.detail = "";
                    },
                    .foreign_provenance => findings[0].value.provenance.claim_ids = &.{.{ .ordinal = 999999 }},
                    .missing_finding => entries = findings[1..],
                    .partial_findings => entries = findings[0..2],
                    .two_missing_findings => entries = findings[2..],
                    .foreign_sources => {
                        // R29's seven findings confuse the source namespace with
                        // claim ordinals. The first repair repeats that mistake.
                        for ([_]usize{ 1, 4, 5, 6, 7, 8, 10 }) |index| findings[index].value.source_ids = &.{.{ .ordinal = 2 }};
                    },
                    .duplicate_finding => entries = try std.mem.concat(allocator, @import("../domain/specification_support.zig").Source.Finding, &.{ findings, findings[0..1] }),
                }
            };
            return @import("../domain/model_candidate_json.zig").encode(@import("../domain/specification_support.zig").Source.Review, allocator, .{ .entries = entries });
        },
        else => return error.InvalidFixture,
    }
}
fn attributed(allocator: std.mem.Allocator, all: r.Items, ids: []const r.ClaimId) !g.spec.Model.AttributedValue {
    const claim = (try r.item(all, ids[0])).claim;
    const value: g.spec.BusinessValue = switch (claim.content) {
        .model => |model| switch (model) {
            .business => |business| .{ .normalized = business.value },
            else => return error.InvalidFixture,
        },
        .preserved_token => |token| .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } },
    };
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
        .records => |kind| records: {
            var result: std.ArrayList(g.spec.Model.RecordProposal) = .empty;
            for (document.records) |record| {
                if (record.content != kind) continue;
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
                if (std.mem.eql(u8, token.value.raw_value.bytes, scalar.bytes)) return .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } };
            }
        }
        return error.InvalidSpecificationScript;
    }
    // Script strings are retained by the invocation's arena.
    return .{ .normalized = .{ .segments = try allocator.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = scalar.bytes } }}) } };
}

fn selection(value: g.spec.Provenance) g.spec.Selection {
    return .{ .claim_ids = value.claim_ids, .clarification_response_ids = value.clarification_response_ids };
}

fn extractedClaim(allocator: std.mem.Allocator, chunk: r.evidence.identity.ChunkId) ![]const u8 {
    return std.fmt.allocPrint(allocator, "The outcome from reference unit {s} is observable.", .{chunk.bytes});
}

fn omittedKind(options: Options, kind: g.spec.Kind) bool {
    const selected = options.candidate_omissions orelse return false;
    return kind == .functional_requirement or (selected == .acceptance_and_functional and kind == .acceptance_criterion);
}
