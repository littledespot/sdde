//! Native candidate failures. Context corruption and operational errors never
//! enter this result; these facts grant observation, not repair authority.
const r = @import("reference_reconciliation.zig");
const std = @import("std");
const Origin = @import("model_candidate_origin.zig").Origin;
pub const Field = enum { record, selections, content, relationship };
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
    omission_conflict_claims: []const r.ClaimId = &.{},
    pub fn at(self: Source, unit: Unit, field: Field) ?Origin {
        for (self.fields) |value| if (std.meta.eql(value.unit, unit) and value.field == field) return value.origin;
        for (self.fields) |value| if (std.meta.eql(value.unit, unit) and value.field == .record) return value.origin;
        const parent: ?Unit = switch (unit) {
            .statement => .summary,
            .disposition => .dispositions,
            .signal => .signals,
            .conflict => .conflicts,
            else => null,
        };
        if (parent) |collection| return self.at(collection, .record);
        return self.origin;
    }
};
pub const Unit = union(enum) { summary, statement: usize, dispositions, disposition: usize, signals, signal: usize, conflicts, conflict: usize };
pub const Rule = enum { membership, claim_selection, content, cardinality, duplicate_disposition, relationship, cycle, signal_coverage, duplicate_signal, role_assignment, conflict_coverage, duplicate_conflict, typed_text };
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
    supported_role_assignment,
    conflict_claim_covered,
    conflict_pair_covered,

    /// Presentation scope only; every merged candidate still runs all validators.
    pub const Assignment = enum { summary, dispositions, signals, roles, conflicts };
    pub const Scope = union(enum) { all, selection: enum { statement, signal, conflict }, content: ContentKind, disposition: enum { rules, choices }, summary, conflict_detail, assignment: Assignment };
    pub fn appliesTo(self: Constraint, purpose: @FieldType(r.Input, "purpose"), scope: Scope) bool {
        const in_purpose = switch (self) {
            .unique_nonzero, .nonempty_unique_allowed_claims, .matching_claim_content, .exact_selected_token => true,
            else => purpose == .global,
        };
        return in_purpose and switch (scope) {
            .all => true,
            .content => |kind| self == .matching_claim_content or (kind == .preserved_token and self == .exact_selected_token),
            .disposition => |mode| mode == .rules and switch (self) {
                .no_self_relation, .same_content_kind, .same_token_value, .nonconflicting_target, .reciprocal_conflict, .acyclic, .nonempty => true,
                else => false,
            },
            .selection => |unit| switch (unit) {
                .statement => self == .nonempty_unique_allowed_claims,
                .signal => self == .nonempty_unique_allowed_claims or self == .nonconflicting_claims or self == .unique_members,
                .conflict => false,
            },
            .summary, .conflict_detail => false,
            .assignment => |assignment| switch (assignment) {
                .summary => self != .exact_selected_token and self != .unique_nonzero and self.appliesTo(.summary, .all),
                .dispositions => self.appliesTo(purpose, .{ .disposition = .rules }),
                .signals => switch (self) {
                    .nonempty_unique_allowed_claims, .matching_claim_content, .nonconflicting_claims, .unique_members, .retained_claim_covered, .token_projected => true,
                    else => false,
                },
                .roles => self == .supported_role_assignment,
                .conflicts => switch (self) {
                    .unique_members, .conflict_claim_covered, .conflict_pair_covered => true,
                    else => false,
                },
            },
        };
    }
    /// Present the same native rule for the actual assignment, not the complete
    /// assembled result. Repair scopes retain their own authorized selections.
    pub fn descriptionFor(self: Constraint, scope: Scope) []const u8 {
        if (scope == .selection) return switch (self) {
            .nonempty_unique_allowed_claims => "Select a nonempty, unique subset of repair.rule.selection. Other claims are supporting evidence and cannot be selected.",
            .unique_members => "Do not duplicate another candidate signal's complete member set. Different sets may overlap.",
            else => self.description(),
        };
        if (scope == .assignment) switch (scope.assignment) {
            .summary, .signals => {
                if (scope.assignment == .summary and self == .nonempty_unique_allowed_claims) return "Each statement must select a nonempty, unique subset of assignment.claim_ids. Together, the statements must cover every assigned claim ID. Claims may be combined, split across statements or selected by overlapping statements. Other claims are supporting evidence; native code adds preserved-token statements.";
                if (self == .nonempty_unique_allowed_claims) return "Select a nonempty, unique subset of assignment.claim_ids. Other claims are supporting evidence and cannot be selected.";
                if (scope.assignment == .signals) return switch (self) {
                    .retained_claim_covered => "Cover every retained claim in assignment.claim_ids that is not already covered by accepted.signals.",
                    .unique_members => "Do not repeat a complete member set from accepted.signals or another returned signal. Different sets may overlap.",
                    .token_projected => "Preserved-token claims are evidence only; native code supplies their signals.",
                    else => self.description(),
                };
            },
            else => {},
        };
        return self.description();
    }
    pub fn description(self: Constraint) []const u8 {
        return switch (self) {
            .unique_nonzero => "IDs must be nonzero and unique within their collection.",
            .nonempty_unique_allowed_claims => "Select a nonempty, unique subset of the supplied claim IDs.",
            .matching_claim_content => "Authored content must match each selected claim's content.kind (representation) and, for model content, content.model.kind (semantic category).",
            .exact_selected_token => "Preserved-token identity and exact content must match the source; native code supplies them.",
            .no_self_relation => "A claim cannot relate to itself.",
            .same_content_kind => "Duplicate and superseded targets must match the original claim's content.kind (representation) and, for model content, content.model.kind (semantic category).",
            .same_token_value => "Duplicate tokens must have the same token kind and exact value.",
            .nonconflicting_target => "Duplicate and superseded targets cannot be conflicting.",
            .reciprocal_conflict => "Each selected conflict group represents mutually incompatible claims; native code expands reciprocal relationships.",
            .acyclic => "Duplicate and superseded chains must terminate without cycles.",
            .nonempty => "Superseding selections and conflict groups must be nonempty.",
            .at_least_two => "A conflict group must contain at least two claims.",
            .nonconflicting_claims => "Signals may select only nonconflicting claims.",
            .conflicting_related_claims => "Conflict membership must match the accepted incompatible claim groups.",
            .unique_members => "Do not repeat an identical member set for the same projection kind.",
            .retained_claim_covered => "Every retained claim must appear in a signal.",
            .token_projected => "Native code projects every nonconflicting preserved token, including after supersession.",
            .supported_role_assignment => "Assess every registered role exactly once. Return supported with nonempty unique signal_ids from accepted.signals, or unsupported without IDs. Every claim in a selected authoring group must be retained; groups and roles may support each other many-to-many.",
            .conflict_claim_covered => "Every conflicting claim must appear in a conflict.",
            .conflict_pair_covered => "Explain every accepted conflict group; native code attaches its membership.",
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
    if (rule == .role_assignment) return .relationship;
    if (rule == .relationship and (unit == .signal or unit == .conflict)) return .selections;
    return switch (rule) {
        .claim_selection => .selections,
        .content, .typed_text => .content,
        .relationship, .cycle => .relationship,
        else => .record,
    };
}
pub fn textFailure(issue: r.text.Issue, observed: Fact) Issue {
    return .{ .rule = .typed_text, .observed = observed, .expected = .{ .text_issue = issue } };
}
