//! Native candidate failures. Context corruption and operational errors never
//! enter this result; these facts grant observation, not repair authority.
const r = @import("reference_reconciliation.zig");
const std = @import("std");
const Origin = @import("model_candidate_origin.zig").Origin;
pub const Field = enum { record, key, selections, content, relationship };
pub const FieldOrigin = struct { unit: Unit, field: Field, origin: ?Origin };
pub const Source = struct {
    revision: u64 = 1,
    last_repair: ?@import("atomic_repair.zig").Merge = null,
    origin: ?Origin = null,
    fields: []const FieldOrigin = &.{},
    statements: @import("repair_occurrences.zig").Set = .{},
    dispositions: @import("repair_occurrences.zig").Set = .{},
    signals: @import("repair_occurrences.zig").Set = .{},
    conflicts: @import("repair_occurrences.zig").Set = .{},
    pending_repair: ?@import("atomic_repair.zig").Pending(@import("reference_reconciliation_repair.zig").ObservationTarget) = null,
    omission_retry: ?@import("workflow_retry.zig").Permit = null,
    pub fn at(self: Source, unit: Unit, field: Field) ?Origin {
        for (self.fields) |value| if (std.meta.eql(value.unit, unit) and value.field == field) return value.origin;
        for (self.fields) |value| if (std.meta.eql(value.unit, unit) and value.field == .record) return value.origin;
        return self.origin;
    }
};
pub const Unit = union(enum) { summary, statement: usize, dispositions, disposition: usize, signals, signal: usize, conflicts, conflict: usize };
pub const Rule = enum { membership, local_key, claim_selection, content, cardinality, duplicate_disposition, relationship, cycle, signal_coverage, duplicate_signal, conflict_coverage, duplicate_conflict, typed_text };
pub const Constraint = enum {
    unique_nonzero,
    nonempty_unique_allowed_claims,
    matching_claim_content,
    exact_selected_token,
    no_self_relation,
    same_content_kind,
    same_token_value,
    nonconflicting_target,
    reciprocal_conflict,
    acyclic,
    nonempty,
    at_least_two,
    nonconflicting_claims,
    conflicting_related_claims,
    unique_members,
    retained_claim_covered,
    token_projected,
    conflict_claim_covered,
    conflict_pair_covered,

    /// Presentation scope only; every merged candidate still runs all validators.
    pub const Scope = union(enum) { all, key, selection, content: ContentKind, disposition: enum { rules, choices }, summary, conflict_detail };
    pub fn appliesTo(self: Constraint, purpose: @FieldType(r.Input, "purpose"), scope: Scope) bool {
        const in_purpose = switch (self) {
            .unique_nonzero, .nonempty_unique_allowed_claims, .matching_claim_content, .exact_selected_token => true,
            else => purpose == .global,
        };
        return in_purpose and switch (scope) {
            .all => true,
            .key => self == .unique_nonzero,
            .content => |kind| self == .matching_claim_content or (kind == .preserved_token and self == .exact_selected_token),
            .disposition => |mode| mode == .rules and switch (self) {
                .no_self_relation, .same_content_kind, .same_token_value, .nonconflicting_target, .reciprocal_conflict, .acyclic, .nonempty => true,
                else => false,
            },
            .selection => switch (self) {
                .unique_nonzero, .no_self_relation, .same_content_kind, .same_token_value, .nonconflicting_target, .reciprocal_conflict, .acyclic, .nonempty => false,
                else => true,
            },
            .summary, .conflict_detail => false,
        };
    }
    pub fn description(self: Constraint) []const u8 {
        return switch (self) {
            .unique_nonzero => "IDs and local keys must be nonzero and unique within their collection.",
            .nonempty_unique_allowed_claims => "Select a nonempty, unique subset of the supplied claim IDs.",
            .matching_claim_content => "Content must match the selected claims' content kind.",
            .exact_selected_token => "Preserved-token content must select one claim and its exact token ID.",
            .no_self_relation => "A claim cannot relate to itself.",
            .same_content_kind => "Duplicate and superseded targets must have the same content kind.",
            .same_token_value => "Duplicate tokens must have the same token kind and exact value.",
            .nonconflicting_target => "Duplicate and superseded targets cannot be conflicting.",
            .reciprocal_conflict => "Every conflicting relationship must be declared in both directions.",
            .acyclic => "Duplicate and superseded chains must terminate without cycles.",
            .nonempty => "Superseded and conflicting claims require at least one related claim.",
            .at_least_two => "A conflict must select at least two claims.",
            .nonconflicting_claims => "Signals may select only nonconflicting claims.",
            .conflicting_related_claims => "Conflict members must declare each other as conflicting.",
            .unique_members => "Do not repeat an identical member set for the same projection kind.",
            .retained_claim_covered => "Every retained claim must appear in a signal.",
            .token_projected => "Every nonconflicting preserved token needs an exact-token signal, including after supersession.",
            .conflict_claim_covered => "Every conflicting claim must appear in a conflict.",
            .conflict_pair_covered => "Every declared conflicting pair must appear together in a conflict.",
        };
    }
};

pub const Fact = union(enum) {
    count: usize,
    claims: []const r.ClaimId,
    disposition: r.ClaimDisposition,
    content: r.ContentProposal,
    text: r.text.ReferenceSemanticText,
    text_issue: r.text.Issue,
    constraint: Constraint,
};
pub const Issue = struct { rule: Rule, observed: Fact, expected: Fact };
pub const RecordIssue = struct { unit: Unit, issue: Issue };
pub const RepairBlock = enum { competing_entries, no_independent_target, no_required_member };
pub const ContentKind = union(enum) { model: std.meta.Tag(r.extraction.Content), preserved_token: r.TokenReference };
/// Necessary independent-edit facts from the owning validators. They describe
/// available choices, never select a repair operation or prove semantic support.
pub const Relations = struct {
    content: ?ContentKind = null,
    selection: []const r.ClaimId = &.{},
    conflicting_pairs: []const struct { left: r.ClaimId, right: r.ClaimId } = &.{},
    redundant: ?usize = null,
    competing: bool = false,
};
pub const Rejection = struct {
    blocked: ?RepairBlock = null,
    relations: Relations = .{},
    dependencies: ?@import("atomic_repair.zig").Snapshot = null,
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
    return .{ .invalid = .{ .state_id = input.progress.plan.layout.items.state_id, .partition_id = input.partition.id, .revision = source.revision, .origin = source.at(unit, fieldFor(unit, issue.rule)), .unit = unit, .issue = issue } };
}
pub fn fieldFor(unit: Unit, rule: Rule) Field {
    if (rule == .relationship and (unit == .signal or unit == .conflict)) return .selections;
    return switch (rule) {
        .local_key => .key,
        .claim_selection => .selections,
        .content, .typed_text => .content,
        .relationship, .cycle => .relationship,
        else => .record,
    };
}
pub fn textFailure(issue: r.text.Issue, observed: Fact) Issue {
    return .{ .rule = .typed_text, .observed = observed, .expected = .{ .text_issue = issue } };
}
