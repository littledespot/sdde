//! Review-purpose evidence admission, shared by collection and state readback.
//! Business provenance retains its narrower retained-claim policy.
const std = @import("std");
const a = @import("required_authority.zig");
const r = @import("reference_reconciliation.zig");
const spec = @import("specification.zig");
const refs = @import("reference_support.zig");
const SourceId = @import("reference_identity.zig").SourceId;
pub const Error = a.Error || r.Error || spec.Error;

pub fn eligible(records: refs.Records, id: a.Id, claim: r.ClaimId) bool {
    const disposition = for (records.dispositions) |value| {
        if (std.meta.eql(value.claim_id, claim)) break value.disposition;
    } else return false;
    return switch (id.unit) {
        .signal => |selected| for (records.signals) |signal| {
            if (std.meta.eql(signal.id, selected)) break disposition != .conflicting and r.contains(r.ClaimId, signal.value.claim_ids, claim);
        } else false,
        .conflict => |selected| for (records.conflicts) |conflict| {
            if (std.meta.eql(conflict.id, selected)) break disposition == .conflicting and r.contains(r.ClaimId, conflict.value.claim_ids, claim);
        } else false,
        .token => |selected| token: {
            const item = r.item(records.items, claim) catch break :token false;
            break :token disposition != .conflicting and item.claim.content == .preserved_token and std.meta.eql(item.claim.content.preserved_token.value.id, selected);
        },
        .feature, .record => @import("specification_provenance.zig").eligibleClaim(disposition),
        .decision => false,
    };
}

pub fn choices(allocator: std.mem.Allocator, records: refs.Records, id: a.Id) std.mem.Allocator.Error![]const r.ClaimId {
    var ids: std.ArrayList(r.ClaimId) = .empty;
    for (records.items.entries) |item| if (eligible(records, id, item.claim.id)) try ids.append(allocator, item.claim.id);
    return ids.toOwnedSlice(allocator);
}

pub fn sourceChoices(allocator: std.mem.Allocator, sources: r.evidence.Inputs) std.mem.Allocator.Error![]const SourceId {
    const ids = try allocator.alloc(SourceId, sources.corpus.sources.len);
    for (sources.corpus.sources, ids) |source, *id| id.* = source.id;
    return ids;
}

/// The same facts constrain admission and describe evidence selection to a model.
pub const selection_instruction: []const u8 = "Judge source meaning and select a loss location or source when needed. The bound subject and diagnostic location fix claim evidence; source-only omissions have no claim selection. Eligibility alone is not support.";
pub const Minimum = enum { optional, claim_required, claim_or_source_required };
pub fn minimum(finding: a.Finding) Minimum {
    return switch (finding) {
        .supported => .claim_required,
        .candidate_omission => .claim_or_source_required,
        .ambiguous, .conflicting, .unsupported, .inconclusive => .optional,
    };
}
pub const ClaimSet = union(enum) { eligible: []const r.ClaimId, exact: []const r.ClaimId };
pub const Rule = struct {
    minimum: Minimum,
    claims: ClaimSet,
    eligible_source_ids: []const SourceId,
    provenance: ?spec.Provenance,

    /// Evidence already determined by the bound requirement and finding.
    pub fn fixedClaims(self: Rule) ?[]const r.ClaimId {
        if (self.provenance) |value| return value.claim_ids;
        return switch (self.claims) {
            .exact => |claims| claims,
            .eligible => null,
        };
    }

    pub const Guidance = struct { instruction: []const u8 = selection_instruction, minimum: Minimum, claims: ClaimSet, eligible_source_ids: []const SourceId, provenance: ?spec.Selection };
    pub fn guidance(self: Rule) Guidance {
        return .{ .minimum = self.minimum, .claims = self.claims, .eligible_source_ids = self.eligible_source_ids, .provenance = if (self.provenance) |value| selection(value) else null };
    }
};
pub const Requirements = struct {
    records: refs.Records,
    eligible_claim_ids: []const r.ClaimId,
    eligible_source_ids: []const SourceId,
    positive_claims: enum { eligible_subset, exact_set },
    supported_provenance: ?spec.Provenance,
    candidate_bound: bool,

    pub fn rule(self: Requirements, finding: a.Finding, loss: @import("source_omission.zig").Location) Rule {
        const diagnostic = if (finding == .candidate_omission and loss != .unlocalized) @import("source_omission.zig").diagnosticClaims(self.records, loss) else null;
        return .{
            .minimum = if (diagnostic != null and diagnostic.?.len != 0 and loss != .reconciliation_disposition) .claim_required else minimum(finding),
            .claims = if (diagnostic) |claims| (if (loss == .reconciliation_disposition) .{ .eligible = claims } else .{ .exact = claims }) else if (self.positive_claims == .exact_set) .{ .exact = self.eligible_claim_ids } else .{ .eligible = self.eligible_claim_ids },
            .eligible_source_ids = self.eligible_source_ids,
            .provenance = if (finding == .candidate_omission and diagnostic != null and loss != .reconciliation_disposition) null else if (finding != .supported and self.positive_claims == .eligible_subset and !self.candidate_bound) .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} } else if (self.supported_provenance) |value| value else if (finding == .candidate_omission and self.positive_claims == .exact_set) null else null,
        };
    }
    pub const Guidance = struct { eligible_claim_ids: []const r.ClaimId, positive_claims: @FieldType(Requirements, "positive_claims"), supported_provenance: ?spec.Selection };
    pub fn guidance(self: Requirements) Guidance {
        return .{ .eligible_claim_ids = self.eligible_claim_ids, .positive_claims = self.positive_claims, .supported_provenance = if (self.supported_provenance) |value| selection(value) else null };
    }
};
pub fn requirements(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, id: a.Id) Error!Requirements {
    const eligible_claim_ids = try choices(allocator, inputs.references orelse return error.InvalidRequiredAuthority, id);
    errdefer allocator.free(eligible_claim_ids);
    return .{
        .records = inputs.references.?,
        .eligible_claim_ids = eligible_claim_ids,
        .eligible_source_ids = try sourceChoices(allocator, sources),
        .positive_claims = switch (id.unit) {
            .signal, .conflict, .token => .exact_set,
            else => .eligible_subset,
        },
        .supported_provenance = try expectedProvenance(allocator, inputs, sources, id),
        .candidate_bound = inputs.specification != null or (inputs.brief != null and id.unit == .feature and (id.slot == .description or id.slot == .primary_goal)),
    };
}
pub const Issue = enum { invalid_loss, stale_authority, invalid_sources, ineligible_claim, invalid_selection, missing_claims, missing_evidence, wrong_claim_set, wrong_candidate_provenance };
pub const Rejection = struct { issue: Issue, rule: Rule };
pub const Admission = union(enum) { accepted: a.ReviewEvidence, rejected: Rejection };

/// Evidence checks are independent of detail/applicability checks in collection.
pub fn admit(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, id: a.Id, finding: a.Finding, proposed: spec.Selection, source_ids: []const SourceId, detail: []const u8, loss: @import("source_omission.zig").Location) Error!Admission {
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    const required = try requirements(allocator, inputs, sources, id);
    const rule = required.rule(finding, loss);
    if (!records.items.state_id.eql(sources.corpus.state_id) or !a.contains(a.Authority, inputs.authorities, .{ .reference = records.items.state_id })) return reject(.stale_authority, rule);
    r.unique(SourceId, source_ids) catch return reject(.invalid_sources, rule);
    for (source_ids) |selected| if (!r.contains(SourceId, rule.eligible_source_ids, selected)) return reject(.invalid_sources, rule);
    if (finding == .supported and required.positive_claims == .eligible_subset and required.supported_provenance == null and required.eligible_claim_ids.len != 0) return reject(.invalid_selection, rule);
    for (proposed.claim_ids) |claim| if (!r.contains(r.ClaimId, switch (rule.claims) {
        .eligible => |ids| ids,
        .exact => |ids| ids,
    }, claim)) return reject(.ineligible_claim, rule);
    if (proposed.clarification_response_ids.len != 0) return reject(.invalid_selection, rule);
    const resolved = refs.select(allocator, records.items, sources, proposed.claim_ids) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else reject(.invalid_selection, rule);
    const provenance: spec.Provenance = .{ .claim_ids = resolved.claim_ids, .citation_ids = resolved.citation_ids, .clarification_response_ids = proposed.clarification_response_ids };
    switch (rule.minimum) {
        .claim_required => if (proposed.claim_ids.len == 0) return reject(.missing_claims, rule),
        .claim_or_source_required => if (proposed.claim_ids.len == 0 and source_ids.len == 0) return reject(.missing_evidence, rule),
        .optional => {},
    }
    if (rule.claims == .exact) r.sameSet(r.ClaimId, rule.claims.exact, proposed.claim_ids) catch return reject(.wrong_claim_set, rule);
    if (rule.provenance) |expected| sameProvenance(expected, provenance) catch return reject(.wrong_candidate_provenance, rule);
    const review: a.ReviewEvidence = .{ .loss = loss, .detail = detail, .provenance = provenance, .source_ids = source_ids };
    @import("source_omission.zig").validate(inputs, sources, finding, review, loss) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else reject(.invalid_loss, rule);
    return .{ .accepted = review };
}
fn reject(issue: Issue, rule: Rule) Admission {
    return .{ .rejected = .{ .issue = issue, .rule = rule } };
}
fn selection(value: spec.Provenance) spec.Selection {
    return .{ .claim_ids = value.claim_ids, .clarification_response_ids = value.clarification_response_ids };
}
pub fn expectedProvenance(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, id: a.Id) Error!?spec.Provenance {
    if (inputs.brief) |brief| if (id.unit == .feature) switch (id.slot) {
        .description => return try effectiveAttributed(allocator, brief.description),
        .primary_goal => return try effectiveAttributed(allocator, brief.primary_goal),
        else => {},
    };
    if (inputs.specification) |content| if (try candidateProvenance(allocator, content, id)) |candidate| return candidate;
    // Pre-generation source review uses the roles chosen and validated during
    // reconciliation. The eligible catalogue alone cannot establish support.
    if (id.unit == .feature) {
        const role: ?r.GenerationRole = switch (id.slot) {
            .display_name => .title,
            .description => .description,
            .primary_goal => .primary_goal,
            .primary_user_story => .primary_user_story,
            .entities => .entity_basis,
            .acceptance_criteria, .functional_requirements, .scenario_coverage => .records,
            else => null,
        };
        if (role) |selected| {
            const records = inputs.references orelse return error.InvalidRequiredAuthority;
            if (records.signals.len == 0) return null;
            const chosen = @import("specification_source_binding.zig").roleClaims(allocator, records, sources, selected) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                error.InvalidSpecificationBinding => return null,
                else => error.InvalidRequiredAuthority,
            };
            const resolved = refs.select(allocator, records.items, sources, chosen.claim_ids) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority;
            return .{ .claim_ids = resolved.claim_ids, .citation_ids = resolved.citation_ids, .clarification_response_ids = &.{} };
        }
    }
    return null;
}

fn withEffective(value: spec.Provenance, claims: []const r.ClaimId) spec.Provenance {
    return .{ .claim_ids = claims, .citation_ids = value.citation_ids, .clarification_response_ids = value.clarification_response_ids };
}
fn effectiveAttributed(allocator: std.mem.Allocator, value: spec.AttributedValue) Error!spec.Provenance {
    return withEffective(value.provenance, try @import("specification_provenance.zig").effectiveClaims(allocator, value.provenance.claim_ids, &.{value.value}));
}

pub const DetailRule = struct {
    allow_empty: bool,

    pub const Guidance = struct { instruction: []const u8, allow_empty: bool, maximum_utf8_bytes: usize };
    pub fn guidance(self: DetailRule) Guidance {
        return .{
            .instruction = "Preserve the retained finding. Put known facts/preconditions and the reason in detail. Nonempty text must be nonblank UTF-8; only tab/newline controls are allowed.",
            .allow_empty = self.allow_empty,
            .maximum_utf8_bytes = @import("clarification_inputs.zig").max_text_bytes,
        };
    }
    pub fn accepts(self: DetailRule, detail: []const u8) bool {
        return (self.allow_empty and detail.len == 0) or @import("clarification_inputs.zig").validText(detail, @import("clarification_inputs.zig").max_text_bytes);
    }
};
pub fn detailRule(finding: a.Finding) DetailRule {
    return .{ .allow_empty = finding == .supported };
}
pub fn validDetail(finding: a.Finding, detail: []const u8) bool {
    return detailRule(finding).accepts(detail);
}
pub fn questionRequired(finding: a.Finding) bool {
    return switch (finding) {
        .supported, .candidate_omission, .inconclusive => false,
        .ambiguous, .conflicting, .unsupported => true,
    };
}
pub fn questionGuidance(finding: a.Finding) []const u8 {
    return if (questionRequired(finding)) "In detail, explain how the missing choice affects required behavior. Ask only for that choice, with an answer format that resolves it, including needed details beyond yes/no. The user answers; do not ask for a review verdict." else "Omit question; preserve the finding and meaning.";
}
pub const QuestionIssue = enum { missing_question, invalid_question, forbidden_question };
pub fn questionIssue(finding: a.Finding, question: ?[]const u8) ?QuestionIssue {
    if (!questionRequired(finding)) return if (question == null) null else .forbidden_question;
    const value = question orelse return .missing_question;
    return if (@import("clarification_inputs.zig").validText(value, @import("clarification_inputs.zig").max_text_bytes)) null else .invalid_question;
}

pub fn validate(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, evidence: a.Evidence) Error!void {
    const review = evidence.review orelse return error.InvalidRequiredAuthority;
    if (review.principle_citations.len != 0 or review.principle_registry != null) return error.InvalidRequiredAuthority;
    if (!validDetail(evidence.finding, review.detail)) return error.InvalidRequiredAuthority;
    if (questionIssue(evidence.finding, review.question) != null) return error.InvalidRequiredAuthority;
    const result = try admit(allocator, inputs, sources, evidence.requirement, evidence.finding, .{ .claim_ids = review.provenance.claim_ids, .clarification_response_ids = review.provenance.clarification_response_ids }, review.source_ids, review.detail, review.loss orelse return error.InvalidRequiredAuthority);
    if (result != .accepted) return error.InvalidRequiredAuthority;
    try sameProvenance(result.accepted.provenance, review.provenance);
    if (evidence.method != .model_assisted) return error.InvalidRequiredAuthority;
    if (inputs.authorities.len != evidence.authorities.len) return error.InvalidRequiredAuthority;
    for (inputs.authorities) |value| if (!a.contains(a.Authority, evidence.authorities, value)) return error.InvalidRequiredAuthority;
}

fn sameProvenance(expected: spec.Provenance, actual: spec.Provenance) Error!void {
    try r.sameSet(r.ClaimId, expected.claim_ids, actual.claim_ids);
    try r.sameSet(r.CitationId, expected.citation_ids, actual.citation_ids);
    try r.sameSet(spec.ResponseId, expected.clarification_response_ids, actual.clarification_response_ids);
}

fn candidateProvenance(allocator: std.mem.Allocator, content: spec.IdentifiedContent, id: a.Id) Error!?spec.Provenance {
    switch (id.unit) {
        .feature => return switch (id.slot) {
            .display_name => try effectiveAttributed(allocator, content.display_name),
            .primary_user_story => try effectiveAttributed(allocator, content.primary_user_story),
            .entities => try effectiveAttributed(allocator, content.entities.basis),
            .acceptance_criteria, .functional_requirements, .scenario_coverage => try aggregateRecords(allocator, content.records, id.slot),
            else => null,
        },
        .record => |selected| for (content.records) |record| {
            if (std.meta.eql(record.id, selected)) {
                const values = try @import("specification_provenance.zig").recordValues(allocator, record.proposal.content);
                return withEffective(record.proposal.provenance, try @import("specification_provenance.zig").effectiveClaims(allocator, record.proposal.provenance.claim_ids, values));
            }
        },
        else => {},
    }
    return null;
}

/// A feature-level review of a record family is bound to the candidate's
/// existing per-record associations. This does not change any record's support.
fn aggregateRecords(allocator: std.mem.Allocator, records: []const spec.IdentifiedRecord, slot: a.Slot) Error!?spec.Provenance {
    var claims: std.ArrayList(r.ClaimId) = .empty;
    var citations: std.ArrayList(r.CitationId) = .empty;
    for (records) |record| {
        const relevant = switch (slot) {
            .acceptance_criteria => record.proposal.content == .acceptance_criterion,
            .functional_requirements => record.proposal.content == .functional_requirement,
            .scenario_coverage => record.proposal.content == .acceptance_criterion or record.proposal.content == .edge_case or record.proposal.content == .user_visible_outcome,
            else => false,
        };
        if (!relevant) continue;
        const values = try @import("specification_provenance.zig").recordValues(allocator, record.proposal.content);
        const effective = try @import("specification_provenance.zig").effectiveClaims(allocator, record.proposal.provenance.claim_ids, values);
        for (effective) |claim| if (!r.contains(r.ClaimId, claims.items, claim)) try claims.append(allocator, claim);
        for (record.proposal.provenance.citation_ids) |citation| if (!r.contains(r.CitationId, citations.items, citation)) try citations.append(allocator, citation);
    }
    if (claims.items.len == 0) return null;
    return .{ .claim_ids = try claims.toOwnedSlice(allocator), .citation_ids = try citations.toOwnedSlice(allocator), .clarification_response_ids = &.{} };
}
