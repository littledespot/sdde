//! Borrowed canonical reference evidence; no execution history or continuation.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const spec = @import("specification.zig");
pub const Records = struct {
    items: r.Items,
    dispositions: []const r.ClaimDisposition,
    signals: []const r.Signal,
    conflicts: []const r.Conflict,
};
pub fn records(value: r.Accounted) Records {
    const global = value.records.assignments.checked.prior.prior;
    return .{ .items = global.input.progress.plan.layout.items, .dispositions = global.dispositions, .signals = value.records.signals, .conflicts = value.records.conflicts };
}
pub fn snapshot(a: std.mem.Allocator, value: @import("reference_snapshot.zig").Snapshot) r.Error!Records {
    return .{ .items = try @import("reference_claim_items.zig").build(a, value.inputs, value.extraction), .dispositions = value.dispositions, .signals = value.signals, .conflicts = value.conflicts };
}
pub const Resolved = struct { provenance: spec.Provenance, scopes: []const r.evidence.Scope };
/// Meaningful selections resolve once. Each consumer owns its eligibility policy.
pub fn select(a: std.mem.Allocator, items: r.Items, inputs: r.evidence.Inputs, selection: spec.Selection) (r.Error || spec.Error)!Resolved {
    if (!items.state_id.eql(inputs.corpus.state_id) or selection.clarification_response_ids.len != 0) return error.InvalidSpecification;
    try r.unique(r.ClaimId, selection.claim_ids);
    const scopes = try a.alloc(r.evidence.Scope, selection.claim_ids.len);
    for (selection.claim_ids, scopes) |id, *scope| {
        const claim = (try r.item(items, id)).claim;
        scope.* = .{ .state_id = items.state_id, .chunk_id = claim.chunk_id };
        _ = try r.evidence.resolve(inputs, scope.*);
    }
    return .{ .provenance = .{ .claim_ids = selection.claim_ids, .citation_ids = try r.citationUnion(a, items, selection.claim_ids), .clarification_response_ids = selection.clarification_response_ids }, .scopes = scopes };
}
