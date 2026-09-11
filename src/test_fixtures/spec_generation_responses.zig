//! Shared scripted provider candidate data. No workflow execution or test loop.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const values = @import("../application/pipeline_values.zig");
const r = @import("../domain/reference_reconciliation.zig");
const g = @import("../domain/specification_generation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const a = @import("../domain/required_authority.zig");
pub const Options = struct {
    script: ?@import("specification_script.zig").Script = null,
    uncertain: bool = false,
    brief_uncertain: bool = false,
    repair: bool = false,
    failed_repair: bool = false,
    omit_exact: bool = false,
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
            const claim = if (options.script) |script| (try @import("specification_script.zig").extraction(script, selected_chunk.bytes)).claim else try std.fmt.allocPrint(allocator, "The outcome from reference unit {s} is observable.", .{chunk.id.bytes});
            const body = try @import("../domain/model_candidate_json.zig").encode(@import("../domain/reference_extraction_parser.zig").Response, allocator, .{ .claims = .{ .claims = &.{.{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = claim } }} } }, .citations = &.{.{ .source_id = chunk.source_id, .block_id = chunk.block_id, .location = chunk.span, .verbatim = selected_chunk.bytes }} }}, .token_classifications = &.{} } });
            return @import("reference_tokens.zig").wire(allocator, body, try @import("reference_tokens.zig").classifications(allocator, candidates, chunk));
        },
        .reference_global => {
            const input = (try native.read(&view, @import("../application/reference_reconciliation_workflow.zig").input_schema, .reconciliation_input)).payload().reconciliation_input;
            return @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), allocator, if (input.purpose == .summary) .{ .summary = try @import("reference_reconciliation.zig").summary(allocator, input) } else .{ .global = try @import("reference_reconciliation.zig").global(allocator, input) });
        },
        .specification_unit => {
            const current = try @import("../application/specification_workflow.zig").readSession(&view);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const value = try attributed(allocator, all, &.{all.entries[0].claim.id});
            if (request.id().purpose == .atomic_repair) {
                var replacement = value;
                if (options.failed_repair) replacement.provenance.claim_ids = &.{.{ .ordinal = 999999 }};
                return @import("../domain/model_candidate_json.zig").encodeSelected(@import("../domain/specification_repair.zig").Replacement, allocator, .{ .attributed = replacement });
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
                        const record: g.spec.RecordProposal = .{ .content = .{ .entity = .{ .name = value.value, .business_meaning = value.value, .relationships = &.{} } }, .provenance = value.provenance };
                        break :result .{ .records = try allocator.dupe(g.spec.RecordProposal, &.{record}) };
                    }
                    if ((kind != .functional_requirement and kind != .user_visible_outcome and kind != .acceptance_criterion) or (options.omit_exact and kind == .user_visible_outcome)) break :result .{ .records = &.{} };
                    var records: std.ArrayList(g.spec.RecordProposal) = .empty;
                    for (all.entries) |item| {
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
            const inputs = try @import("../application/required_authority_values.zig").read(&view, @import("../application/required_authority_workflow.zig").inputs_schema, .inputs);
            const ledger = try a.build(allocator, inputs);
            const context = try @import("../application/specification_workflow.zig").readContext(&view);
            const all = try @import("../domain/specification_provenance.zig").items(context);
            const findings = try allocator.alloc(@import("../domain/specification_support.zig").Finding, ledger.requirements.len);
            for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
                var selected = (try attributed(allocator, all, &.{all.entries[0].claim.id})).provenance;
                if (inputs.brief) |brief| if (requirement.seed.id.unit == .feature) {
                    selected = switch (requirement.seed.id.slot) {
                        .description => brief.description.provenance,
                        .primary_goal => brief.primary_goal.provenance,
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
                    .record => |id| if (inputs.specification) |content| {
                        for (content.records) |record| if (std.meta.eql(record.id, id)) {
                            selected = record.proposal.provenance;
                        };
                    },
                    .feature => if (inputs.specification) |content| {
                        selected = switch (requirement.seed.id.slot) {
                            .display_name => content.display_name.provenance,
                            .primary_user_story => content.primary_user_story.provenance,
                            .entities => content.entities.basis.provenance,
                            else => selected,
                        };
                    },
                    else => {},
                }
                const uncertain = options.uncertain or (options.brief_uncertain and inputs.brief != null and requirement.seed.id.slot == .description);
                finding.* = .{ .requirement_ordinal = @intCast(index + 1), .finding = if (uncertain) .ambiguous else .supported, .disposition = if (requirement.seed.id.kind == .entity_applicability and inputs.specification != null and inputs.specification.?.entities.disposition == .not_applicable) .not_applicable else .supported, .provenance = selected };
            }
            return std.json.Stringify.valueAlloc(allocator, @import("../domain/specification_support.zig").Review{ .entries = findings }, .{});
        },
        else => return error.InvalidFixture,
    }
}
fn attributed(allocator: std.mem.Allocator, all: r.Items, ids: []const r.ClaimId) !g.spec.AttributedValue {
    var citations: std.ArrayList(r.CitationId) = .empty;
    for (ids) |id| for ((try r.item(all, id)).claim.citation_ids) |citation| {
        if (!r.contains(r.CitationId, citations.items, citation)) try citations.append(allocator, citation);
    };
    const claim = (try r.item(all, ids[0])).claim;
    const value: g.spec.BusinessValue = switch (claim.content) {
        .model => |model| switch (model) {
            .business => |business| .{ .normalized = business.value },
            else => return error.InvalidFixture,
        },
        .preserved_token => |token| .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } },
    };
    return .{ .value = value, .provenance = .{ .claim_ids = try allocator.dupe(r.ClaimId, ids), .citation_ids = citations.items, .clarification_response_ids = &.{} } };
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
            var result: std.ArrayList(g.spec.RecordProposal) = .empty;
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
