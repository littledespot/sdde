//! Offline comparison of candidate binding rules. Supplied native eligibility
//! and occurrence/requirement edges are assumptions, never reconstructed from
//! source IDs, token spelling, catalogue availability or a retained response.
//! No result establishes source support, coverage, repair or workflow authority.
const std = @import("std");
const recognition = @import("recognition.zig");
const fields = @import("../../../src/domain/text_field_policy.zig");

pub const Policy = enum {
    selected_requirement_membership,
    request_eligible_occurrences,
    explicit_requirement_relation,
};
pub const SnapshotId = struct { value: u64 };
pub const RequestId = struct { value: u64 };
pub const UnitId = struct { value: u32 };
pub const Context = struct {
    snapshot: SnapshotId,
    request: RequestId,
    unit: UnitId,
    field: fields.Field,
};
pub const Occurrence = struct {
    id: recognition.OccurrenceId,
    bytes: []const u8,
    /// A caller-supplied native fact for this exact context, not proof inferred
    /// by this prototype. Historical absence must remain unavailable.
    eligibility: enum { eligible, ineligible, unavailable },
};
pub const Catalogue = struct { context: Context, occurrences: []const Occurrence };
pub const Edge = struct { occurrence: recognition.OccurrenceId, requirement: recognition.RequirementId };
pub const Relations = struct { context: Context, edges: []const Edge };
pub const FixedScope = struct {
    context: Context,
    selected_requirements: []const recognition.RequirementId,
    eligible_occurrences: []const recognition.OccurrenceId,
    relation_edges: ?[]const Edge = null,
};
pub const Input = struct {
    context: Context,
    prose: []const u8,
    selected_requirements: []const recognition.RequirementId,
    catalogue: ?Catalogue,
    relations: ?Relations = null,
    /// Already authorized repair evidence. A broader later catalogue cannot
    /// replace this exact selected set or expand its eligible occurrence set.
    fixed_scope: ?FixedScope = null,
};
pub const Rejection = enum {
    invalid_context,
    foreign_catalogue,
    invalid_requirement,
    duplicate_requirement,
    invalid_occurrence,
    duplicate_occurrence,
    foreign_relations,
    invalid_relation,
    duplicate_relation,
    foreign_fixed_scope,
    changed_selected_scope,
    changed_occurrence_scope,
    changed_relation_scope,
};
pub const Unavailable = enum { native_eligibility, requirement_relations };
pub const Diagnostic = union(enum) { binding: Rejection, lexical: recognition.Rejection };
pub const Candidate = struct {
    policy: Policy,
    field_role: fields.Role,
    /// Original S, copied byte-for-byte in its supplied order. Recognition
    /// never appends E here, even under the hypothetical request-wide policy.
    selected_requirements: []const recognition.RequirementId,
    lexical: recognition.Report,

    pub fn deinit(self: Candidate, a: std.mem.Allocator) void {
        a.free(self.selected_requirements);
        self.lexical.deinit(a);
    }
};
pub const Outcome = union(enum) {
    rejected: Diagnostic,
    unavailable: Unavailable,
    evaluated: Candidate,

    pub fn deinit(self: Outcome, a: std.mem.Allocator) void {
        switch (self) {
            .rejected, .unavailable => {},
            .evaluated => |candidate| candidate.deinit(a),
        }
    }
};

/// Pure experimental adapter around the existing lexical recognizer. All three
/// candidates share explicit native eligibility and canonical field-role gates.
/// This is stronger evidence than historical selected-ID-only corpus metadata.
/// The request-wide query set is scratch data, never a replacement for S.
pub fn evaluate(a: std.mem.Allocator, policy: Policy, input: Input, classifier: recognition.LexicalClassifier) std.mem.Allocator.Error!Outcome {
    if (validate(policy, input)) |rejection| return .{ .rejected = .{ .binding = rejection } };
    const catalogue = input.catalogue orelse return .{ .unavailable = .native_eligibility };
    for (catalogue.occurrences) |occurrence| if (occurrence.eligibility == .unavailable) return .{ .unavailable = .native_eligibility };
    if (policy == .explicit_requirement_relation and input.relations == null) return .{ .unavailable = .requirement_relations };
    if (policy == .explicit_requirement_relation) if (input.fixed_scope) |fixed| {
        if (fixed.relation_edges == null) return .{ .unavailable = .requirement_relations };
    };

    var scratch: std.heap.ArenaAllocator = .init(a);
    defer scratch.deinit();
    const temporary = scratch.allocator();
    const occurrences = try temporary.alloc(recognition.Occurrence, catalogue.occurrences.len);
    var query: std.ArrayList(recognition.RequirementId) = .empty;
    if (policy != .request_eligible_occurrences) try query.appendSlice(temporary, input.selected_requirements);
    const role = fields.get(input.context.field).exact_copy;
    for (catalogue.occurrences, occurrences) |occurrence, *projected| {
        var requirements: std.ArrayList(recognition.RequirementId) = .empty;
        if (occurrence.eligibility == .eligible and role != .prohibited) switch (policy) {
            .selected_requirement_membership => try requirements.append(temporary, .{ .value = occurrence.id.value }),
            .request_eligible_occurrences => {
                const id: recognition.RequirementId = .{ .value = occurrence.id.value };
                try query.append(temporary, id);
                try requirements.append(temporary, id);
            },
            .explicit_requirement_relation => for (input.relations.?.edges) |edge| {
                if (edge.occurrence.value == occurrence.id.value) try requirements.append(temporary, edge.requirement);
            },
        };
        projected.* = .{ .id = occurrence.id, .bytes = occurrence.bytes, .requirements = try requirements.toOwnedSlice(temporary) };
    }
    const selected = try a.dupe(recognition.RequirementId, input.selected_requirements);
    errdefer a.free(selected);
    const result = try recognition.recognize(a, .{ .prose = input.prose, .bound_requirements = query.items, .occurrences = occurrences }, classifier);
    return switch (result) {
        .rejected => |rejection| rejected: {
            a.free(selected);
            break :rejected .{ .rejected = .{ .lexical = rejection } };
        },
        .evaluated => |report| .{ .evaluated = .{ .policy = policy, .field_role = role, .selected_requirements = selected, .lexical = report } },
    };
}

fn validate(policy: Policy, input: Input) ?Rejection {
    if (input.context.snapshot.value == 0 or input.context.request.value == 0 or input.context.unit.value == 0) return .invalid_context;
    if (requirementsIssue(input.selected_requirements)) |issue| return issue;
    const catalogue = input.catalogue orelse return null;
    if (!std.meta.eql(input.context, catalogue.context)) return .foreign_catalogue;
    for (catalogue.occurrences, 0..) |occurrence, index| {
        if (occurrence.id.value == 0) return .invalid_occurrence;
        for (catalogue.occurrences[0..index]) |prior| if (prior.id.value == occurrence.id.value) return .duplicate_occurrence;
    }
    if (policy == .explicit_requirement_relation) if (input.relations) |relations| {
        if (!std.meta.eql(input.context, relations.context)) return .foreign_relations;
        for (relations.edges, 0..) |edge, index| {
            if (edge.requirement.value == 0 or !hasOccurrence(catalogue.occurrences, edge.occurrence)) return .invalid_relation;
            for (relations.edges[0..index]) |prior| if (std.meta.eql(prior, edge)) return .duplicate_relation;
        }
    };
    if (input.fixed_scope) |fixed| {
        if (!std.meta.eql(input.context, fixed.context)) return .foreign_fixed_scope;
        if (requirementsIssue(fixed.selected_requirements) != null or !sameRequirements(input.selected_requirements, fixed.selected_requirements)) return .changed_selected_scope;
        for (fixed.eligible_occurrences, 0..) |id, index| {
            if (id.value == 0) return .changed_occurrence_scope;
            for (fixed.eligible_occurrences[0..index]) |prior| if (id.value == prior.value) return .changed_occurrence_scope;
            var found = false;
            for (catalogue.occurrences) |occurrence| if (occurrence.id.value == id.value and occurrence.eligibility == .eligible) {
                found = true;
                break;
            };
            if (!found) return .changed_occurrence_scope;
        }
        for (catalogue.occurrences) |occurrence| if (occurrence.eligibility == .eligible) {
            for (fixed.eligible_occurrences) |id| {
                if (id.value == occurrence.id.value) break;
            } else return .changed_occurrence_scope;
        };
        if (policy == .explicit_requirement_relation and fixed.relation_edges != null and input.relations != null) {
            const expected = fixed.relation_edges.?;
            const actual = input.relations.?.edges;
            if (expected.len != actual.len) return .changed_relation_scope;
            for (expected, actual) |left, right| if (!std.meta.eql(left, right)) return .changed_relation_scope;
        }
    }
    return null;
}
fn requirementsIssue(requirements: []const recognition.RequirementId) ?Rejection {
    for (requirements, 0..) |id, index| {
        if (id.value == 0) return .invalid_requirement;
        for (requirements[0..index]) |prior| if (id.value == prior.value) return .duplicate_requirement;
    }
    return null;
}
fn hasOccurrence(occurrences: []const Occurrence, id: recognition.OccurrenceId) bool {
    for (occurrences) |occurrence| if (occurrence.id.value == id.value) return true;
    return false;
}
fn sameRequirements(left: []const recognition.RequirementId, right: []const recognition.RequirementId) bool {
    if (left.len != right.len) return false;
    for (left, right) |left_id, right_id| if (left_id.value != right_id.value) return false;
    return true;
}

pub const State = enum { matched, no_match, ambiguous, rejected, unavailable };
const Expected = struct {
    state: State,
    matches: []const recognition.Witness = &.{},
    unbound: []const recognition.Witness = &.{},
    rejection: ?Rejection = null,
    unavailable: ?Unavailable = null,
};
pub const ControlResult = struct {
    id: []const u8,
    policy: Policy,
    expected: Expected,
    state: State,
    field_role: ?fields.Role,
    selected_requirements: []const recognition.RequirementId,
    matches: []const recognition.Witness,
    unbound: []const recognition.Witness,
    diagnostics: []const recognition.Diagnostic,
    rejection: ?Diagnostic,
    unavailable: ?Unavailable,
    passed: bool,
};
pub const Counts = struct {
    policy: Policy,
    matched: usize = 0,
    no_match: usize = 0,
    ambiguous: usize = 0,
    rejected: usize = 0,
    unavailable: usize = 0,
    failures: usize = 0,
};
pub const Summary = struct {
    schema: []const u8 = "exact-value-binding-experiment/v1",
    evidence: enum { independently_fixed_synthetic_controls } = .independently_fixed_synthetic_controls,
    policy_adopted: bool = false,
    semantic_support_assessed: bool = false,
    workflow_authority: bool = false,
    counts: [3]Counts,
    controls: []const ControlResult,
    passed: bool,
};

const context: Context = .{ .snapshot = .{ .value = 10 }, .request = .{ .value = 20 }, .unit = .{ .value = 30 }, .field = .ac_then };
const one: recognition.RequirementId = .{ .value = 1 };
const two: recognition.RequirementId = .{ .value = 2 };
const three: recognition.RequirementId = .{ .value = 3 };
const token: Occurrence = .{ .id = .{ .value = 2 }, .bytes = "ACTIVE", .eligibility = .eligible };
const witness: recognition.Witness = .{ .occurrence = .{ .value = 2 }, .start_byte = 8, .end_byte = 14 };
const linked: Relations = .{ .context = context, .edges = &.{.{ .occurrence = token.id, .requirement = one }} };
const base: Input = .{ .context = context, .prose = "Display ACTIVE.", .selected_requirements = &.{one}, .catalogue = .{ .context = context, .occurrences = &.{token} }, .relations = linked };
const matched: Expected = .{ .state = .matched, .matches = &.{witness} };
const unbound: Expected = .{ .state = .no_match, .unbound = &.{witness} };
const Control = struct { id: []const u8, input: Input, expected: [3]Expected };

/// Independently fixed synthetic controls, not repaired or enriched captures.
/// Caller arena owns the complete serializable summary. All expectations are
/// literal policy outcomes; no matcher output supplies an expected value.
pub fn runControls(a: std.mem.Allocator, classifier: recognition.LexicalClassifier) std.mem.Allocator.Error!Summary {
    const token_selected = altered(.token_selected);
    const no_relations = altered(.missing_relations);
    const no_edge = altered(.empty_relations);
    const ineligible = altered(.ineligible);
    const prohibited = altered(.prohibited_field);
    const incidental = altered(.incidental_field);
    const unavailable = altered(.unavailable_eligibility);
    const stale = altered(.stale_catalogue);
    const widened = altered(.widened_repair);
    const controls = [_]Control{
        .{ .id = "business-selection-with-explicit-occurrence-edge", .input = base, .expected = .{ unbound, matched, matched } },
        .{ .id = "token-selection-with-explicit-occurrence-edge", .input = token_selected, .expected = .{ matched, matched, matched } },
        .{ .id = "business-selection-missing-relation-metadata", .input = no_relations, .expected = .{ unbound, matched, .{ .state = .unavailable, .unavailable = .requirement_relations } } },
        .{ .id = "catalogue-and-source-proximity-supply-no-edge", .input = no_edge, .expected = .{ unbound, matched, unbound } },
        .{ .id = "known-ineligible-occurrence", .input = ineligible, .expected = .{ unbound, unbound, unbound } },
        .{ .id = "canonical-prohibited-field-role", .input = prohibited, .expected = .{ unbound, unbound, unbound } },
        .{ .id = "canonical-incidental-identity-role", .input = incidental, .expected = .{ matched, matched, matched } },
        .{ .id = "missing-native-eligibility-is-unavailable", .input = unavailable, .expected = @splat(.{ .state = .unavailable, .unavailable = .native_eligibility }) },
        .{ .id = "stale-catalogue-is-rejected", .input = stale, .expected = @splat(.{ .state = .rejected, .rejection = .foreign_catalogue }) },
        .{ .id = "repair-cannot-widen-eligible-occurrences", .input = widened, .expected = @splat(.{ .state = .rejected, .rejection = .changed_occurrence_scope }) },
        .{ .id = "competing-lineages-never-select-by-catalogue-order", .input = competingInput(false), .expected = @splat(.{ .state = .ambiguous }) },
        .{ .id = "explicit-relation-excludes-unrelated-equal-bytes", .input = competingInput(true), .expected = .{ .{ .state = .ambiguous }, .{ .state = .ambiguous }, .{ .state = .matched, .matches = &.{witness}, .unbound = &.{.{ .occurrence = .{ .value = 3 }, .start_byte = 8, .end_byte = 14 }} } } },
    };
    var rows: std.ArrayList(ControlResult) = .empty;
    var counts = [3]Counts{ .{ .policy = .selected_requirement_membership }, .{ .policy = .request_eligible_occurrences }, .{ .policy = .explicit_requirement_relation } };
    var passed = true;
    for (controls) |control| inline for (std.enums.values(Policy), 0..) |policy, index| {
        const outcome = try evaluate(a, policy, control.input, classifier);
        const actual: State = switch (outcome) {
            .rejected => .rejected,
            .unavailable => .unavailable,
            .evaluated => |candidate| switch (candidate.lexical.state) {
                .matched => .matched,
                .no_match => .no_match,
                .ambiguous => .ambiguous,
            },
        };
        var row: ControlResult = .{ .id = control.id, .policy = policy, .expected = control.expected[index], .state = actual, .field_role = null, .selected_requirements = &.{}, .matches = &.{}, .unbound = &.{}, .diagnostics = &.{}, .rejection = null, .unavailable = null, .passed = actual == control.expected[index].state };
        switch (outcome) {
            .rejected => |rejection| {
                row.rejection = rejection;
                row.passed = row.passed and rejection == .binding and control.expected[index].rejection == rejection.binding;
            },
            .unavailable => |reason| {
                row.unavailable = reason;
                row.passed = row.passed and control.expected[index].unavailable == reason;
            },
            .evaluated => |candidate| {
                row.field_role = candidate.field_role;
                row.selected_requirements = candidate.selected_requirements;
                row.matches = candidate.lexical.matches;
                row.unbound = candidate.lexical.unbound_matches;
                row.diagnostics = candidate.lexical.diagnostics;
                row.passed = row.passed and sameRequirements(candidate.selected_requirements, control.input.selected_requirements) and sameWitnesses(row.matches, row.expected.matches) and sameWitnesses(row.unbound, row.expected.unbound);
            },
        }
        switch (actual) {
            .matched => counts[index].matched += 1,
            .no_match => counts[index].no_match += 1,
            .ambiguous => counts[index].ambiguous += 1,
            .rejected => counts[index].rejected += 1,
            .unavailable => counts[index].unavailable += 1,
        }
        if (!row.passed) {
            passed = false;
            counts[index].failures += 1;
        }
        try rows.append(a, row);
    };
    return .{ .counts = counts, .controls = try rows.toOwnedSlice(a), .passed = passed };
}

const Alteration = enum { token_selected, missing_relations, empty_relations, ineligible, prohibited_field, incidental_field, unavailable_eligibility, stale_catalogue, widened_repair };
fn altered(comptime change: Alteration) Input {
    var result = base;
    switch (change) {
        .token_selected => {
            result.selected_requirements = &.{two};
            result.relations = .{ .context = context, .edges = &.{.{ .occurrence = token.id, .requirement = two }} };
        },
        .missing_relations => result.relations = null,
        .empty_relations => result.relations = .{ .context = context, .edges = &.{} },
        .ineligible => result.catalogue = .{ .context = context, .occurrences = &.{.{ .id = token.id, .bytes = token.bytes, .eligibility = .ineligible }} },
        .prohibited_field, .incidental_field => {
            result.context.field = if (change == .prohibited_field) .entity_meaning else .entity_name;
            result.catalogue.?.context = result.context;
            result.relations.?.context = result.context;
            if (change == .incidental_field) {
                result.selected_requirements = &.{two};
                result.relations.?.edges = &.{.{ .occurrence = token.id, .requirement = two }};
            }
        },
        .unavailable_eligibility => result.catalogue = .{ .context = context, .occurrences = &.{.{ .id = token.id, .bytes = token.bytes, .eligibility = .unavailable }} },
        .stale_catalogue => result.catalogue.?.context.snapshot.value += 1,
        .widened_repair => {
            result.catalogue = .{ .context = context, .occurrences = &.{ token, .{ .id = .{ .value = 3 }, .bytes = "READY", .eligibility = .eligible } } };
            result.fixed_scope = .{ .context = context, .selected_requirements = &.{one}, .eligible_occurrences = &.{token.id} };
        },
    }
    return result;
}
fn competingInput(comptime only_one_edge: bool) Input {
    var result = base;
    result.selected_requirements = &.{ two, three };
    result.catalogue = .{ .context = context, .occurrences = &.{ token, .{ .id = .{ .value = 3 }, .bytes = token.bytes, .eligibility = .eligible } } };
    result.relations = .{ .context = context, .edges = if (only_one_edge) &.{.{ .occurrence = token.id, .requirement = two }} else &.{ .{ .occurrence = token.id, .requirement = two }, .{ .occurrence = .{ .value = 3 }, .requirement = three } } };
    return result;
}
fn sameWitnesses(left: []const recognition.Witness, right: []const recognition.Witness) bool {
    if (left.len != right.len) return false;
    for (left, right) |one_witness, other| if (!std.meta.eql(one_witness, other)) return false;
    return true;
}

const test_classifier: recognition.LexicalClassifier = .{ .boundary_fn = @import("exact_value_unicode").wholeWordBoundary };
test "binding experiment independently fixes every policy result without adopting a policy" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const summary = try runControls(arena.allocator(), test_classifier);
    for (summary.controls) |control| if (!control.passed) std.debug.print("Binding experiment {s}/{s}: expected {s}, observed {s}\n", .{ control.id, @tagName(control.policy), @tagName(control.expected.state), @tagName(control.state) });
    try std.testing.expect(summary.passed);
    try std.testing.expectEqual(@as(usize, 36), summary.controls.len);
    try std.testing.expect(!summary.policy_adopted and !summary.semantic_support_assessed and !summary.workflow_authority);
    try std.testing.expect((try std.json.Stringify.valueAlloc(arena.allocator(), summary, .{})).len != 0);
}
test "binding experiment rejects foreign context in every metadata owner" {
    const Foreign = enum { snapshot, request, unit, field };
    inline for (std.enums.values(Foreign)) |foreign| {
        var wrong = context;
        switch (foreign) {
            .snapshot => wrong.snapshot.value += 1,
            .request => wrong.request.value += 1,
            .unit => wrong.unit.value += 1,
            .field => wrong.field = .functional_requirement,
        }
        var input = base;
        input.catalogue.?.context = wrong;
        inline for (std.enums.values(Policy)) |policy| try expectBindingRejection(policy, input, .foreign_catalogue);
        input = base;
        input.relations.?.context = wrong;
        try expectBindingRejection(.explicit_requirement_relation, input, .foreign_relations);
        input = base;
        input.fixed_scope = .{ .context = wrong, .selected_requirements = &.{one}, .eligible_occurrences = &.{token.id} };
        inline for (std.enums.values(Policy)) |policy| try expectBindingRejection(policy, input, .foreign_fixed_scope);
    }
}
test "binding experiment keeps repair selections and occurrence identity fixed" {
    var input = base;
    input.fixed_scope = .{ .context = context, .selected_requirements = &.{one}, .eligible_occurrences = &.{token.id}, .relation_edges = linked.edges };
    inline for (std.enums.values(Policy)) |policy| {
        const original = try evaluate(std.testing.allocator, policy, input, test_classifier);
        defer original.deinit(std.testing.allocator);
        try std.testing.expect(original == .evaluated);
        try std.testing.expectEqualDeep(input.selected_requirements, original.evaluated.selected_requirements);
        var changed = input;
        changed.selected_requirements = &.{two};
        try expectBindingRejection(policy, changed, .changed_selected_scope);
        changed = input;
        changed.fixed_scope.?.eligible_occurrences = &.{.{ .value = 3 }};
        try expectBindingRejection(policy, changed, .changed_occurrence_scope);
        changed = input;
        changed.fixed_scope.?.eligible_occurrences = &.{ token.id, token.id };
        try expectBindingRejection(policy, changed, .changed_occurrence_scope);
    }
    var changed = input;
    changed.relations.?.edges = &.{.{ .occurrence = token.id, .requirement = two }};
    try expectBindingRejection(.explicit_requirement_relation, changed, .changed_relation_scope);
    changed = input;
    changed.fixed_scope.?.relation_edges = null;
    const absent = try evaluate(std.testing.allocator, .explicit_requirement_relation, changed, test_classifier);
    defer absent.deinit(std.testing.allocator);
    try std.testing.expect(absent == .unavailable and absent.unavailable == .requirement_relations);
}
test "binding experiment rejects malformed IDs and relation edges without guessing" {
    var input = base;
    input.selected_requirements = &.{ one, one };
    try expectBindingRejection(.selected_requirement_membership, input, .duplicate_requirement);
    input = base;
    input.selected_requirements = &.{.{ .value = 0 }};
    try expectBindingRejection(.request_eligible_occurrences, input, .invalid_requirement);
    input = base;
    input.catalogue = .{ .context = context, .occurrences = &.{ token, token } };
    try expectBindingRejection(.request_eligible_occurrences, input, .duplicate_occurrence);
    input = base;
    input.relations.?.edges = &.{.{ .occurrence = .{ .value = 999 }, .requirement = one }};
    try expectBindingRejection(.explicit_requirement_relation, input, .invalid_relation);
    input = base;
    input.relations.?.edges = &.{ linked.edges[0], linked.edges[0] };
    try expectBindingRejection(.explicit_requirement_relation, input, .duplicate_relation);
}
test "binding experiment preserves lexical rejection and cleans up allocation failures" {
    var input = base;
    input.prose = "ACTIVE\xff";
    const outcome = try evaluate(std.testing.allocator, .request_eligible_occurrences, input, test_classifier);
    defer outcome.deinit(std.testing.allocator);
    try std.testing.expect(outcome == .rejected and outcome.rejected == .lexical);
    try std.testing.expectEqual(.invalid_prose, outcome.rejected.lexical.reason);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn expectBindingRejection(policy: Policy, input: Input, expected: Rejection) !void {
    const outcome = try evaluate(std.testing.allocator, policy, input, test_classifier);
    defer outcome.deinit(std.testing.allocator);
    try std.testing.expect(outcome == .rejected and outcome.rejected == .binding);
    try std.testing.expectEqual(expected, outcome.rejected.binding);
}
fn allocationCase(a: std.mem.Allocator) !void {
    inline for (std.enums.values(Policy)) |policy| {
        const result = try evaluate(a, policy, base, test_classifier);
        defer result.deinit(a);
        try std.testing.expect(result == .evaluated);
        try std.testing.expectEqualDeep(base.selected_requirements, result.evaluated.selected_requirements);
    }
}
