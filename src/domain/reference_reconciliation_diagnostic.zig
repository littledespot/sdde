//! Native candidate failures. Context corruption and operational errors never
//! enter this result; these facts grant observation, not repair authority.
const r = @import("reference_reconciliation.zig");
pub const Source = struct { revision: u64 = 1, origin: ?@import("model_candidate_origin.zig").Origin = null };
pub const Unit = union(enum) { summary, statement: usize, dispositions, disposition: usize, signals, signal: usize, conflicts, conflict: usize };
pub const Rule = enum { membership, local_key, claim_selection, content, citations, cardinality, duplicate_disposition, relationship, cycle, signal_coverage, duplicate_signal, conflict_coverage, duplicate_conflict, typed_text };
pub const Constraint = enum { unique_nonzero, nonempty_unique_allowed_claims, matching_claim_content, exact_selected_token, no_self_relation, same_content_kind, same_token_value, nonconflicting_target, reciprocal_conflict, acyclic, nonempty, at_least_two, nonconflicting_claims, conflicting_related_claims, unique_members, retained_claim_covered, token_projected, conflict_claim_covered, conflict_pair_covered, valid_typed_text };
pub const Fact = union(enum) {
    count: usize,
    claims: []const r.ClaimId,
    summaries: []const r.SummaryId,
    citations: []const r.CitationId,
    disposition: r.ClaimDisposition,
    content: r.ContentProposal,
    text: r.text.ReferenceSemanticText,
    constraint: Constraint,
};
pub const Issue = struct { rule: Rule, observed: Fact, expected: Fact, native_error: ?enum { InvalidTypedText, UnboundPathReference, InvalidPassiveLiteral } = null };
pub const Rejection = struct {
    state_id: r.evidence.identity.StateId,
    partition_id: r.PartitionId,
    revision: u64,
    origin: ?@import("model_candidate_origin.zig").Origin,
    unit: Unit,
    issue: Issue,
};
pub fn Result(comptime T: type) type {
    return union(enum) { valid: T, invalid: Rejection };
}
pub fn Check(comptime T: type) type {
    return union(enum) { valid: T, invalid: Issue };
}
pub fn reject(comptime T: type, input: r.Input, source: Source, unit: Unit, issue: Issue) Result(T) {
    return .{ .invalid = .{ .state_id = input.progress.plan.layout.items.state_id, .partition_id = input.partition.id, .revision = source.revision, .origin = source.origin, .unit = unit, .issue = issue } };
}
pub fn textFailure(err: r.Error, observed: Fact) r.Error!Issue {
    return .{ .rule = .typed_text, .observed = observed, .native_error = switch (err) {
        error.InvalidTypedText => .InvalidTypedText,
        error.UnboundPathReference => .UnboundPathReference,
        error.InvalidPassiveLiteral => .InvalidPassiveLiteral,
        else => return err,
    }, .expected = .{ .constraint = .valid_typed_text } };
}
