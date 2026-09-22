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
pub const selection_instruction: []const u8 = "Select evidence supporting the finding; not_applicable still needs claims. Localized candidate_omission uses the named producer's exact claims, including conflicting claims; source-only loss uses its captured source. These diagnostic claims do not support positive content. Eligibility alone is not support.";
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

    pub fn rule(self: Requirements, finding: a.Finding, loss: @import("source_omission.zig").Location) Rule {
        const diagnostic = if (finding == .candidate_omission and loss != .unlocalized) @import("source_omission.zig").diagnosticClaims(self.records, loss) else null;
        return .{
            .minimum = if (diagnostic != null and diagnostic.?.len != 0 and loss != .reconciliation_disposition) .claim_required else minimum(finding),
            .claims = if (diagnostic) |claims| (if (loss == .reconciliation_disposition) .{ .eligible = claims } else .{ .exact = claims }) else if (minimum(finding) != .optional and self.positive_claims == .exact_set) .{ .exact = self.eligible_claim_ids } else .{ .eligible = self.eligible_claim_ids },
            .eligible_source_ids = self.eligible_source_ids,
            .provenance = if (finding == .supported) self.supported_provenance else null,
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
        .supported_provenance = expectedProvenance(inputs, id),
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
    for (proposed.claim_ids) |claim| if (!r.contains(r.ClaimId, switch (rule.claims) {
        .eligible => |ids| ids,
        .exact => |ids| ids,
    }, claim)) return reject(.ineligible_claim, rule);
    const resolved = refs.select(allocator, records.items, sources, proposed) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else reject(.invalid_selection, rule);
    switch (rule.minimum) {
        .claim_required => if (proposed.claim_ids.len == 0) return reject(.missing_claims, rule),
        .claim_or_source_required => if (proposed.claim_ids.len == 0 and source_ids.len == 0) return reject(.missing_evidence, rule),
        .optional => {},
    }
    if (rule.claims == .exact) r.sameSet(r.ClaimId, rule.claims.exact, proposed.claim_ids) catch return reject(.wrong_claim_set, rule);
    if (rule.provenance) |expected| sameProvenance(expected, resolved.provenance) catch return reject(.wrong_candidate_provenance, rule);
    const review: a.ReviewEvidence = .{ .loss = loss, .detail = detail, .provenance = resolved.provenance, .source_ids = source_ids };
    @import("source_omission.zig").validate(inputs, sources, finding, review, loss) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else reject(.invalid_loss, rule);
    return .{ .accepted = review };
}
fn reject(issue: Issue, rule: Rule) Admission {
    return .{ .rejected = .{ .issue = issue, .rule = rule } };
}
fn selection(value: spec.Provenance) spec.Selection {
    return .{ .claim_ids = value.claim_ids, .clarification_response_ids = value.clarification_response_ids };
}
fn expectedProvenance(inputs: a.Inputs, id: a.Id) ?spec.Provenance {
    if (inputs.brief) |brief| if (id.unit == .feature) switch (id.slot) {
        .description => return brief.description.provenance,
        .primary_goal => return brief.primary_goal.provenance,
        else => {},
    };
    return if (inputs.specification) |content| candidateProvenance(content, id) else null;
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

fn candidateProvenance(content: spec.IdentifiedContent, id: a.Id) ?spec.Provenance {
    switch (id.unit) {
        .feature => return switch (id.slot) {
            .display_name => content.display_name.provenance,
            .primary_user_story => content.primary_user_story.provenance,
            .entities => content.entities.basis.provenance,
            else => null,
        },
        .record => |selected| for (content.records) |record| {
            if (std.meta.eql(record.id, selected)) return record.proposal.provenance;
        },
        else => {},
    }
    return null;
}
