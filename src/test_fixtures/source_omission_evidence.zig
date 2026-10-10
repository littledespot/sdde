//! Offline supplied semantic assessments. Native bindings and admission remain
//! production-owned; these mock verdicts are not evidence of semantic accuracy.
const std = @import("std");
const loss = @import("../domain/source_omission.zig");
const c = loss.comparisons;
const authority = @import("../domain/required_authority.zig");
const r = @import("../domain/reference_reconciliation.zig");
const support = @import("../domain/specification_support.zig").Source;

pub fn response(a: std.mem.Allocator, assigned: c.Assignment, location: loss.Location) !c.Response {
    const values = try a.alloc(c.Assessment, assigned.comparisons.len);
    var lost_from: ?u32 = null;
    var bound = location == .candidate or location == .unlocalized;
    if (location != .unlocalized and location != .candidate) {
        for (assigned.boundaries) |boundary| if (boundary.owner) |owner| {
            if (c.location(.{ .established = owner }).eql(location)) {
                bound = true;
                if (boundary.output == .comparison) lost_from = boundary.output.comparison.ordinal;
                break;
            }
        };
    }
    // A fixture cannot turn a former culprit label into native authority. When
    // no unique producer was bound, supply uncertainty rather than inventing it.
    for (assigned.comparisons, values) |view, *value| {
        const members = try a.alloc(c.MemberId, view.members.len);
        for (view.members, members) |member, *id| id.* = member.id;
        value.* = .{ .comparison_id = view.id, .result = if (!bound or location == .unlocalized) .uncertain else if (lost_from != null and view.id.ordinal >= lost_from.?) .lost else .preserved, .sources = try a.dupe(c.Span, &.{.{ .chunk_id = assigned.sources[0].chunk_id, .lines = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } } }}), .members = members, .explanation = "MOCK Supplied preservation assessment." };
    }
    return .{ .assessments = values };
}

pub fn proof(a: std.mem.Allocator, inputs: authority.Inputs, sources: r.evidence.Inputs, finding: support.Finding) !c.Evidence {
    const ledger = try authority.build(a, inputs);
    const fixed = finding.value;
    const assigned = try @import("../domain/source_omission_binding.zig").build(a, inputs, sources, ledger.requirements[finding.requirement_ordinal - 1].seed.id, finding.requirement_ordinal, 1, .{ .detail = fixed.detail, .source_ids = fixed.source_ids, .provenance = .{ .claim_ids = fixed.provenance.claim_ids, .citation_ids = &.{}, .clarification_response_ids = &.{} } });
    return .{ .assignment = assigned, .response = try response(a, assigned, fixed.loss) };
}

pub fn encode(a: std.mem.Allocator, assigned: c.Assignment, location: loss.Location) ![]const u8 {
    return @import("../domain/model_candidate_json.zig").encode(c.Response, a, try response(a, assigned, location));
}
