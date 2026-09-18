//! Review-purpose evidence admission, shared by collection and state readback.
//! Business provenance retains its narrower retained-claim policy.
const std = @import("std");
const a = @import("required_authority.zig");
const r = @import("reference_reconciliation.zig");
const spec = @import("specification.zig");
const refs = @import("reference_support.zig");
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

/// The same facts constrain admission and describe evidence selection to a model.
pub const Minimum = enum { optional, claim_required, claim_or_source_required };
pub fn minimum(finding: a.Finding) Minimum {
    return switch (finding) {
        .supported => .claim_required,
        .candidate_omission => .claim_or_source_required,
        .ambiguous, .conflicting, .unsupported => .optional,
    };
}
pub const ClaimSet = union(enum) { eligible: []const r.ClaimId, exact: []const r.ClaimId };
pub const Rule = struct {
    minimum: Minimum,
    claims: ClaimSet,
    provenance: ?spec.Provenance,

    pub const Guidance = struct { minimum: Minimum, claims: ClaimSet, provenance: ?spec.Selection };
    pub fn guidance(self: Rule) Guidance {
        return .{ .minimum = self.minimum, .claims = self.claims, .provenance = if (self.provenance) |value| selection(value) else null };
    }
};
pub const Requirements = struct {
    eligible_claim_ids: []const r.ClaimId,
    positive_claims: enum { eligible_subset, exact_set },
    supported_provenance: ?spec.Provenance,

    pub fn rule(self: Requirements, finding: a.Finding) Rule {
        return .{
            .minimum = minimum(finding),
            .claims = if (minimum(finding) != .optional and self.positive_claims == .exact_set) .{ .exact = self.eligible_claim_ids } else .{ .eligible = self.eligible_claim_ids },
            .provenance = if (finding == .supported) self.supported_provenance else null,
        };
    }
    pub const Guidance = struct { eligible_claim_ids: []const r.ClaimId, positive_claims: @FieldType(Requirements, "positive_claims"), supported_provenance: ?spec.Selection };
    pub fn guidance(self: Requirements) Guidance {
        return .{ .eligible_claim_ids = self.eligible_claim_ids, .positive_claims = self.positive_claims, .supported_provenance = if (self.supported_provenance) |value| selection(value) else null };
    }
};
pub fn requirements(allocator: std.mem.Allocator, inputs: a.Inputs, id: a.Id) Error!Requirements {
    return .{
        .eligible_claim_ids = try choices(allocator, inputs.references orelse return error.InvalidRequiredAuthority, id),
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
pub fn admit(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, id: a.Id, finding: a.Finding, proposed: spec.Selection, source_ids: []const @import("reference_identity.zig").SourceId, detail: []const u8) Error!Admission {
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    const required = try requirements(allocator, inputs, id);
    const rule = required.rule(finding);
    if (!records.items.state_id.eql(sources.corpus.state_id) or !a.contains(a.Authority, inputs.authorities, .{ .reference = records.items.state_id })) return reject(.stale_authority, rule);
    r.unique(@import("reference_identity.zig").SourceId, source_ids) catch return reject(.invalid_sources, rule);
    for (source_ids) |selected| {
        for (sources.corpus.sources) |source| {
            if (std.meta.eql(selected, source.id)) break;
        } else return reject(.invalid_sources, rule);
    }
    for (proposed.claim_ids) |claim| if (!r.contains(r.ClaimId, required.eligible_claim_ids, claim)) return reject(.ineligible_claim, rule);
    const resolved = refs.select(allocator, records.items, sources, proposed) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else reject(.invalid_selection, rule);
    switch (rule.minimum) {
        .claim_required => if (proposed.claim_ids.len == 0) return reject(.missing_claims, rule),
        .claim_or_source_required => if (proposed.claim_ids.len == 0 and source_ids.len == 0) return reject(.missing_evidence, rule),
        .optional => {},
    }
    if (rule.claims == .exact) r.sameSet(r.ClaimId, rule.claims.exact, proposed.claim_ids) catch return reject(.wrong_claim_set, rule);
    if (rule.provenance) |expected| sameProvenance(expected, resolved.provenance) catch return reject(.wrong_candidate_provenance, rule);
    return .{ .accepted = .{ .detail = detail, .provenance = resolved.provenance, .source_ids = source_ids } };
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

pub fn validDetail(finding: a.Finding, detail: []const u8) bool {
    return (finding == .supported and detail.len == 0) or @import("clarification_inputs.zig").validText(detail, @import("clarification_inputs.zig").max_text_bytes);
}

pub fn validate(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, evidence: a.Evidence) Error!void {
    const review = evidence.review orelse return error.InvalidRequiredAuthority;
    if (review.principle_citations.len != 0 or review.principle_registry != null) return error.InvalidRequiredAuthority;
    if (!validDetail(evidence.finding, review.detail)) return error.InvalidRequiredAuthority;
    const result = try admit(allocator, inputs, sources, evidence.requirement, evidence.finding, .{ .claim_ids = review.provenance.claim_ids, .clarification_response_ids = review.provenance.clarification_response_ids }, review.source_ids, review.detail);
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
