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

pub fn admit(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, id: a.Id, finding: a.Finding, selection: spec.Selection, source_ids: []const @import("reference_identity.zig").SourceId, detail: []const u8) Error!a.ReviewEvidence {
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    if (!records.items.state_id.eql(sources.corpus.state_id) or !a.contains(a.Authority, inputs.authorities, .{ .reference = records.items.state_id })) return error.InvalidRequiredAuthority;
    if (!validDetail(finding, detail)) return error.InvalidRequiredAuthority;
    try r.unique(@import("reference_identity.zig").SourceId, source_ids);
    for (source_ids) |selected| {
        for (sources.corpus.sources) |source| {
            if (std.meta.eql(selected, source.id)) break;
        } else return error.InvalidRequiredAuthority;
    }
    const resolved = try refs.select(allocator, records.items, sources, selection);
    for (selection.claim_ids) |claim| if (!eligible(records, id, claim)) return error.InvalidRequiredAuthority;
    if (finding == .supported or finding == .candidate_omission) {
        if (selection.claim_ids.len == 0 and (finding == .supported or source_ids.len == 0)) return error.InvalidRequiredAuthority;
        switch (id.unit) {
            .signal, .conflict, .token => try r.sameSet(r.ClaimId, try choices(allocator, records, id), selection.claim_ids),
            else => {},
        }
    }
    if (finding == .supported) {
        if (inputs.brief) |brief| if (id.unit == .feature) {
            const expected: ?spec.Provenance = switch (id.slot) {
                .description => brief.description.provenance,
                .primary_goal => brief.primary_goal.provenance,
                else => null,
            };
            if (expected) |value| try sameProvenance(value, resolved.provenance);
        };
        if (inputs.specification) |content| if (candidateProvenance(content, id)) |expected| try sameProvenance(expected, resolved.provenance);
    }
    return .{ .detail = detail, .provenance = resolved.provenance, .source_ids = source_ids };
}

pub fn validDetail(finding: a.Finding, detail: []const u8) bool {
    return (finding == .supported and detail.len == 0) or @import("clarification_inputs.zig").validText(detail, @import("clarification_inputs.zig").max_text_bytes);
}

pub fn validate(allocator: std.mem.Allocator, inputs: a.Inputs, sources: r.evidence.Inputs, evidence: a.Evidence) Error!void {
    const review = evidence.review orelse return error.InvalidRequiredAuthority;
    const expected = try admit(allocator, inputs, sources, evidence.requirement, evidence.finding, .{ .claim_ids = review.provenance.claim_ids, .clarification_response_ids = review.provenance.clarification_response_ids }, review.source_ids, review.detail);
    try sameProvenance(expected.provenance, review.provenance);
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
