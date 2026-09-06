//! Execution-local semantic candidates. Structural validation is not proof that
//! a model found every conflict; no record here is a persisted snapshot.
const std = @import("std");
pub const extraction = @import("reference_extraction.zig");
pub const evidence = @import("reference_evidence.zig");
pub const text = extraction.text;
pub const Error = extraction.Error || error{InvalidReferenceReconciliation};
pub const ClaimId = extraction.ClaimId;
pub const CitationId = extraction.CitationId;
pub const PartitionId = struct { ordinal: u32 };
pub const SummaryId = struct { ordinal: u32 };
pub const StatementId = struct { ordinal: u32 };
pub const SignalId = struct { ordinal: u32 };
pub const ConflictId = struct { ordinal: u32 };
pub const Item = struct {
    claim: extraction.Claim,
    source_id: evidence.identity.SourceId,
    block_id: evidence.identity.BlockId,
    citations: []const extraction.Citation,
};
pub const Items = struct { state_id: evidence.identity.StateId, entries: []const Item };
pub const Level = enum { within_source, cross_source, global };
/// Local grouping coordinates are not canonical identities or model input.
pub const GroupIndex = struct { value: usize };
pub const Group = struct { level: Level, round: u32, claim_ids: []const ClaimId, children: []const GroupIndex };
pub const Layout = struct { items: Items, group_size: u32, groups: []const Group };
pub const Partition = struct { id: PartitionId, group: Group };
pub const Plan = struct { layout: Layout, partitions: []const Partition };
pub const TokenReference = struct { token_id: extraction.tokens.Id };
pub const ContentProposal = union(enum) {
    model: extraction.ProposalContent,
    preserved_token: TokenReference,
};
pub const Content = union(enum) {
    model: extraction.Content,
    preserved_token: TokenReference,
};
pub const StatementProposal = struct { local_key: u32, claim_ids: []const ClaimId, content: ContentProposal };
pub const ValidatedStatement = struct { local_key: u32, claim_ids: []const ClaimId, content: Content };
pub const Statement = struct { id: StatementId, claim_ids: []const ClaimId, content: Content };
pub const SummaryProposal = struct { member_claim_ids: []const ClaimId, member_summary_ids: []const SummaryId, statements: []const StatementProposal };
pub const Summary = struct { id: SummaryId, partition_id: PartitionId, member_claim_ids: []const ClaimId, member_summary_ids: []const SummaryId, statements: []const Statement };
/// Immutable append-only execution history; appending a summary does not copy
/// every previous summary or mutate an older workflow value.
pub const SummaryHistory = struct { value: Summary, previous: ?*const SummaryHistory };
pub const Progress = struct { plan: Plan, latest: ?*const SummaryHistory, summary_count: usize, next_statement_ordinal: u32 };
pub const Input = struct { progress: Progress, partition: Partition, items: []const Item, summaries: []const Summary, member_summary_ids: []const SummaryId, purpose: enum { summary, global } };
pub const Disposition = enum { retained, superseded, duplicate, conflicting };
pub const ClaimDisposition = struct { claim_id: ClaimId, disposition: Disposition, related_claim_ids: []const ClaimId };
pub const SignalProposal = struct { claim_ids: []const ClaimId, citation_ids: []const CitationId, content: ContentProposal };
pub const ValidatedSignal = struct { claim_ids: []const ClaimId, citation_ids: []const CitationId, content: Content };
pub const ConflictKind = enum { mutually_exclusive, precedence_missing, value_mismatch, scope_mismatch };
pub const ConflictProposal = struct {
    claim_ids: []const ClaimId,
    citation_ids: []const CitationId,
    kind: ConflictKind,
    summary: text.ReferenceSemanticText,
    // No registered precedence authority is available in this increment.
    resolution: enum { unresolved },
};
pub const ValidatedConflict = struct { claim_ids: []const ClaimId, citation_ids: []const CitationId, kind: ConflictKind, summary: text.ValidatedReferenceSemanticText, resolution: enum { unresolved } };
pub const Proposal = struct { claim_dispositions: []const ClaimDisposition, signals: []const SignalProposal, conflicts: []const ConflictProposal };
pub const Raw = struct { input: Input, bytes: []const u8 };
pub const Parsed = struct { input: Input, proposal: union(enum) { summary: SummaryProposal, global: Proposal } };
pub const CheckedSummary = struct { input: Input, statements: []const ValidatedStatement };
pub const SummaryAssignment = struct { checked: CheckedSummary, id: SummaryId, statement_ids: []const StatementId, next_statement_ordinal: u32 };
pub const CheckedDispositions = struct { input: Input, proposal: Proposal, dispositions: []const ClaimDisposition };
pub const CheckedSignals = struct { prior: CheckedDispositions, signals: []const ValidatedSignal };
pub const CheckedConflicts = struct { prior: CheckedSignals, conflicts: []const ValidatedConflict };
pub const RecordAssignments = struct { checked: CheckedConflicts, signal_ids: []const SignalId, conflict_ids: []const ConflictId };
pub const Signal = struct { id: SignalId, value: ValidatedSignal };
pub const Conflict = struct { id: ConflictId, value: ValidatedConflict };
pub const Records = struct { assignments: RecordAssignments, signals: []const Signal, conflicts: []const Conflict };
pub const Accounted = struct { records: Records, outcome: enum { complete, blocked } };

pub fn item(items: Items, id: ClaimId) Error!Item {
    if (id.ordinal == 0 or id.ordinal > items.entries.len) return error.InvalidReferenceReconciliation;
    const result = items.entries[id.ordinal - 1];
    if (result.claim.id.ordinal != id.ordinal) return error.InvalidReferenceReconciliation;
    return result;
}
pub fn contains(comptime Id: type, ids: []const Id, id: Id) bool {
    for (ids) |value| if (value.ordinal == id.ordinal) return true;
    return false;
}
pub fn unique(comptime Id: type, ids: []const Id) Error!void {
    for (ids, 0..) |id, index| if (id.ordinal == 0 or contains(Id, ids[0..index], id)) return error.InvalidReferenceReconciliation;
}
pub fn sameSet(comptime Id: type, a: []const Id, b: []const Id) Error!void {
    try unique(Id, a);
    try unique(Id, b);
    if (a.len != b.len) return error.InvalidReferenceReconciliation;
    for (a) |id| if (!contains(Id, b, id)) return error.InvalidReferenceReconciliation;
}
pub fn next(current: u32) Error!u32 {
    return std.math.add(u32, current, 1) catch error.InvalidReferenceReconciliation;
}
pub fn ordinal(index: usize) Error!u32 {
    return std.math.cast(u32, index + 1) orelse error.InvalidReferenceReconciliation;
}
