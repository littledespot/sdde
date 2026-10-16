//! Independently authored diagnostic controls for the offline lexical prototype.
//! Fixture expectations do not derive from recognition output. No control or
//! lexical witness establishes source support, semantic fulfillment or coverage.
const std = @import("std");
const strict = @import("../../../src/domain/strict_json.zig");
const recognition = @import("recognition.zig");
const unicode = @import("exact_value_unicode");
pub const controls_bytes = @embedFile("../../calibration/exact-value-recognition/controls.json");
pub const ExpectedState = enum { matched, no_match, ambiguous, rejected };
pub const Ambiguity = enum { competing_lineage, overlapping_matches };
pub const Expected = struct {
    state: ExpectedState,
    rejection: ?recognition.RejectionReason,
    matches: []const recognition.Witness,
    unbound_matches: []const recognition.Witness,
    semantic_coverage_assessed: bool,
    ambiguity: ?Ambiguity,
};
pub const Case = struct {
    id: []const u8,
    domain: enum { hello_world, loan_renewal, technical, unicode, invalid_input },
    meaning: enum { affirmative, denial, formatting },
    rationale: []const u8,
    input: recognition.Input,
    expected: Expected,
};
pub const Fixture = struct {
    version: enum { @"exact-value-controls/v1" },
    diagnostic_only: bool,
    production_policy_changed: bool,
    boundary_policy: enum { pinned_lexical_without_connector_or_format },
    cases: []const Case,
};
pub const Failure = struct {
    case_id: []const u8,
    kind: enum { state, rejection, matches, unbound_matches, ambiguity },
};
pub const Summary = struct {
    case_count: usize,
    matched: usize = 0,
    no_match: usize = 0,
    ambiguous: usize = 0,
    rejected: usize = 0,
    denial_controls: usize = 0,
    semantic_coverage_assessed: bool = false,
    failures: []const Failure,
    passed: bool,
};

/// Caller arena owns the closed fixture and all its strings/slices.
pub fn decode(a: std.mem.Allocator, bytes: []const u8) !Fixture {
    const fixture = try strict.decode(Fixture, a, bytes, .{ .maximum_depth = 64 });
    if (!fixture.diagnostic_only or fixture.production_policy_changed or fixture.cases.len == 0) return error.InvalidControls;
    for (fixture.cases, 0..) |case, index| {
        if (case.id.len == 0 or case.rationale.len == 0 or case.expected.semantic_coverage_assessed) return error.InvalidControls;
        for (fixture.cases[0..index]) |prior| if (std.mem.eql(u8, prior.id, case.id)) return error.InvalidControls;
        switch (case.expected.state) {
            .rejected => if (case.expected.rejection == null or case.expected.matches.len != 0 or case.expected.unbound_matches.len != 0 or case.expected.ambiguity != null) return error.InvalidControls,
            .ambiguous => if (case.expected.rejection != null or case.expected.ambiguity == null) return error.InvalidControls,
            .matched, .no_match => if (case.expected.rejection != null or case.expected.ambiguity != null) return error.InvalidControls,
        }
        if (case.expected.state == .matched and case.expected.matches.len == 0) return error.InvalidControls;
        if (case.expected.state == .no_match and case.expected.matches.len != 0) return error.InvalidControls;
        for (case.expected.matches) |witness| try validateWitness(case.input, witness);
        for (case.expected.unbound_matches) |witness| try validateWitness(case.input, witness);
    }
    return fixture;
}
fn validateWitness(input: recognition.Input, witness: recognition.Witness) !void {
    if (witness.start_byte >= witness.end_byte or witness.end_byte > input.prose.len) return error.InvalidControls;
    const occurrence = for (input.occurrences) |value| {
        if (value.id.value == witness.occurrence.value) break value;
    } else return error.InvalidControls;
    if (!std.mem.eql(u8, input.prose[witness.start_byte..witness.end_byte], occurrence.bytes)) return error.InvalidControls;
}
fn sameWitnesses(left: []const recognition.Witness, right: []const recognition.Witness) bool {
    if (left.len != right.len) return false;
    for (left, right) |one, two| if (one.occurrence.value != two.occurrence.value or one.start_byte != two.start_byte or one.end_byte != two.end_byte) return false;
    return true;
}
fn observedState(outcome: recognition.Outcome) ExpectedState {
    return switch (outcome) {
        .rejected => .rejected,
        .evaluated => |report| switch (report.state) {
            .matched => .matched,
            .no_match => .no_match,
            .ambiguous => .ambiguous,
        },
    };
}
fn hasAmbiguity(report: recognition.Report, expected: Ambiguity) bool {
    for (report.diagnostics) |diagnostic| switch (diagnostic) {
        .competing_lineage => if (expected == .competing_lineage) return true,
        .overlapping_matches => if (expected == .overlapping_matches) return true,
        .boundary_rejected => {},
    };
    return false;
}
/// Returned summary is caller-arena owned. Recognition's temporary arrays are
/// released independently after each case, on both match and rejection paths.
pub fn verify(a: std.mem.Allocator, fixture: Fixture) !Summary {
    var failures: std.ArrayList(Failure) = .empty;
    errdefer failures.deinit(a);
    var summary: Summary = .{ .case_count = fixture.cases.len, .failures = &.{}, .passed = true };
    for (fixture.cases) |case| {
        const outcome = try recognition.recognize(a, case.input, .{ .boundary_fn = unicode.wholeWordBoundary });
        defer outcome.deinit(a);
        const observed = observedState(outcome);
        switch (observed) {
            .matched => summary.matched += 1,
            .no_match => summary.no_match += 1,
            .ambiguous => summary.ambiguous += 1,
            .rejected => summary.rejected += 1,
        }
        if (case.meaning == .denial) summary.denial_controls += 1;
        if (observed != case.expected.state) try failures.append(a, .{ .case_id = case.id, .kind = .state });
        switch (outcome) {
            .rejected => |rejection| if (case.expected.rejection != rejection.reason) {
                try failures.append(a, .{ .case_id = case.id, .kind = .rejection });
            },
            .evaluated => |report| {
                if (!sameWitnesses(case.expected.matches, report.matches)) try failures.append(a, .{ .case_id = case.id, .kind = .matches });
                if (!sameWitnesses(case.expected.unbound_matches, report.unbound_matches)) try failures.append(a, .{ .case_id = case.id, .kind = .unbound_matches });
                if (case.expected.ambiguity) |expected| if (!hasAmbiguity(report, expected)) {
                    try failures.append(a, .{ .case_id = case.id, .kind = .ambiguity });
                };
            },
        }
    }
    summary.failures = try failures.toOwnedSlice(a);
    summary.passed = summary.failures.len == 0;
    return summary;
}

test "independent exact value controls cover matches boundaries lineage and rejected inputs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try decode(a, controls_bytes);
    const summary = try verify(a, fixture);
    if (!summary.passed) for (summary.failures) |failure| std.debug.print("Exact-value control {s}: {s}\n", .{ failure.case_id, @tagName(failure.kind) });
    try std.testing.expect(summary.passed);
    try std.testing.expectEqual(@as(usize, 53), summary.case_count);
    // These totals were frozen before the first matcher execution.
    try std.testing.expectEqual(@as(usize, 18), summary.matched);
    try std.testing.expectEqual(@as(usize, 22), summary.no_match);
    try std.testing.expectEqual(@as(usize, 4), summary.ambiguous);
    try std.testing.expectEqual(@as(usize, 9), summary.rejected);
    var domains: std.EnumSet(@FieldType(Case, "domain")) = .initEmpty();
    for (fixture.cases) |case| domains.insert(case.domain);
    try std.testing.expectEqual(std.EnumSet(@FieldType(Case, "domain")).initFull(), domains);
    try std.testing.expectEqual(@as(usize, 2), summary.denial_controls);
    try std.testing.expect(!summary.semantic_coverage_assessed);
}
test "exact value control fixture rejects unknown fields coercions and forged coverage assertions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try decode(a, controls_bytes);
    const bytes = try std.json.Stringify.valueAlloc(a, fixture, .{});
    for ([_][2][]const u8{
        .{ "\"diagnostic_only\":true", "\"diagnostic_only\":true,\"unknown\":false" },
        .{ "\"prose\":", "\"unknown\":{},\"prose\":" },
        .{ "\"value\":101", "\"value\":\"101\"" },
        .{ "\"meaning\":\"affirmative\"", "\"meaning\":0" },
        .{ "\"version\":\"exact-value-controls/v1\"", "\"version\":\"exact-value-controls/v99\"" },
    }) |change| {
        const rejected = try std.mem.replaceOwned(u8, a, bytes, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, bytes, rejected));
        try std.testing.expectError(error.InvalidJsonDocument, decode(a, rejected));
    }
    for ([_][2][]const u8{
        .{ "\"diagnostic_only\":true", "\"diagnostic_only\":false" },
        .{ "\"production_policy_changed\":false", "\"production_policy_changed\":true" },
        .{ "\"semantic_coverage_assessed\":false", "\"semantic_coverage_assessed\":true" },
    }) |change| {
        const rejected = try std.mem.replaceOwned(u8, a, bytes, change[0], change[1]);
        try std.testing.expectError(error.InvalidControls, decode(a, rejected));
    }
}
test "exact value lexical witness also occurs in denial and cannot prove coverage" {
    // The same bytes appear in both a requirement and a denial. Recognition
    // deliberately reports only lexical evidence; no fulfillment flag exists.
    try std.testing.expect(!@hasField(recognition.Report, "coverage"));
    try std.testing.expect(!@hasField(recognition.Report, "fulfilled"));
    for ([_][]const u8{ "Display ACTIVE.", "Do not display ACTIVE." }) |prose| {
        const outcome = try recognition.recognize(std.testing.allocator, .{ .prose = prose, .bound_requirements = &.{.{ .value = 1 }}, .occurrences = &.{.{ .id = .{ .value = 1 }, .requirements = &.{.{ .value = 1 }}, .bytes = "ACTIVE" }} }, .{ .boundary_fn = unicode.wholeWordBoundary });
        defer outcome.deinit(std.testing.allocator);
        try std.testing.expect(outcome == .evaluated);
        try std.testing.expectEqual(recognition.State.matched, outcome.evaluated.state);
        try std.testing.expectEqual(@as(usize, 1), outcome.evaluated.matches.len);
    }
}
test "exact value prototype rejects invalid UTF8 outside the JSON fixture transport" {
    const outcome = try recognition.recognize(std.testing.allocator, .{ .prose = "ACTIVE\xff", .bound_requirements = &.{.{ .value = 1 }}, .occurrences = &.{.{ .id = .{ .value = 1 }, .requirements = &.{.{ .value = 1 }}, .bytes = "ACTIVE" }} }, .{ .boundary_fn = unicode.wholeWordBoundary });
    defer outcome.deinit(std.testing.allocator);
    try std.testing.expect(outcome == .rejected);
    try std.testing.expectEqual(recognition.RejectionReason.invalid_prose, outcome.rejected.reason);
}

test "exact value lexical boundaries can match prefixes of changed version and path values" {
    // These are counterexamples to semantic preservation, not matcher defects:
    // the declared word policy treats '.' and '/' as separating punctuation.
    // A lexical witness alone cannot establish which complete value is used.
    for ([_]struct { value: []const u8, extended: []const u8, prose: []const u8, start: usize, end: usize }{
        .{ .value = "1.2", .extended = "1.2.3", .prose = "Use version 1.2.3.", .start = 12, .end = 15 },
        .{ .value = "/v1/renewals", .extended = "/v1/renewals/archive", .prose = "Call /v1/renewals/archive.", .start = 5, .end = 17 },
    }) |case| {
        try std.testing.expect(!std.mem.eql(u8, case.value, case.extended));
        try std.testing.expect(std.mem.indexOf(u8, case.prose, case.extended) != null);
        const outcome = try recognition.recognize(std.testing.allocator, .{
            .prose = case.prose,
            .bound_requirements = &.{.{ .value = 1 }},
            .occurrences = &.{.{ .id = .{ .value = 1 }, .requirements = &.{.{ .value = 1 }}, .bytes = case.value }},
        }, .{ .boundary_fn = unicode.wholeWordBoundary });
        defer outcome.deinit(std.testing.allocator);
        try std.testing.expect(outcome == .evaluated);
        try std.testing.expectEqual(recognition.State.matched, outcome.evaluated.state);
        try std.testing.expectEqual(@as(usize, 1), outcome.evaluated.matches.len);
        const witness = outcome.evaluated.matches[0];
        try std.testing.expectEqual(case.start, witness.start_byte);
        try std.testing.expectEqual(case.end, witness.end_byte);
        try std.testing.expectEqualStrings(case.value, case.prose[witness.start_byte..witness.end_byte]);
    }
}
