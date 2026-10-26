//! Exact byte witnesses from the caller's current native eligible occurrence
//! scope. This owner neither selects support nor decides semantic fulfillment.
const std = @import("std");
const identity = @import("reference_identity.zig");
const boundary = @import("exact_value_boundary.zig");

pub const Occurrence = struct { claim_id: identity.ClaimId, bytes: []const u8 };
/// `delimiters` counts the matching Markdown code delimiters (backticks) directly
/// around the value on each side. The engine formats exact values itself, so
/// callers drop the outer span, delimiters included (ADR 0036).
pub const Witness = struct {
    claim_id: identity.ClaimId,
    start_byte: usize,
    end_byte: usize,
    delimiters: usize = 0,

    pub fn outerStart(self: Witness) usize {
        return self.start_byte - self.delimiters;
    }
    pub fn outerEnd(self: Witness) usize {
        return self.end_byte + self.delimiters;
    }
};
pub const Conflict = struct { left: Witness, right: Witness };
pub const Diagnostic = union(enum) { competing_lineage: Conflict, overlapping_matches: Conflict };
pub const RejectionReason = enum { invalid_prose, invalid_occurrence_id, duplicate_occurrence_id, empty_occurrence, invalid_occurrence_bytes };
pub const Rejection = struct { reason: RejectionReason, occurrence_index: ?usize = null };
pub const Outcome = union(enum) {
    rejected: Rejection,
    no_match,
    /// Ambiguity rejects the complete field; no usable partial witnesses exist.
    ambiguous: []const Diagnostic,
    matched: []const Witness,

    pub fn deinit(self: Outcome, a: std.mem.Allocator) void {
        switch (self) {
            .rejected, .no_match => {},
            .ambiguous => |diagnostics| a.free(diagnostics),
            .matched => |witnesses| a.free(witnesses),
        }
    }
};

/// Match raw decoded UTF-8 bytes before NFC, case folding, rendering or escaping.
/// The caller supplies exactly the currently eligible native occurrence scope;
/// catalogues, selected support and same-source guesses are not inferred here.
/// Returned arrays are owned by `a`; input prose/occurrences remain borrowed and
/// unchanged. Field scalar/composition rules remain with their existing owner.
/// `edges` must describe this run's actual field/reference context; opaque
/// reference-adjacent edges cannot create a delimiter for a truncated word.
pub fn recognize(a: std.mem.Allocator, prose: []const u8, occurrences: []const Occurrence, edges: boundary.Edges) std.mem.Allocator.Error!Outcome {
    return switch (try match(a, prose, occurrences, edges)) {
        .outcome => |outcome| outcome,
        .witnesses => |found| .{ .matched = found },
    };
}

/// ADR 0036 Decision 6: a copy of `witnesses`, matched in `prose`, with their
/// code delimiters counted. `eligible` is every value any later check of this
/// text can match. Delimiters are removed only when matching `eligible` finds
/// the same values, shifted, without them as with them, so admission stays
/// idempotent; otherwise every delimiter in `prose` stays as written.
pub fn delimited(a: std.mem.Allocator, prose: []const u8, witnesses: []const Witness, eligible: []const Occurrence, edges: boundary.Edges) std.mem.Allocator.Error![]const Witness {
    const result = try a.dupe(Witness, witnesses);
    errdefer a.free(result);
    if (!countDelimiters(prose, result)) return result;
    var stripped: std.ArrayList(u8) = .empty;
    defer stripped.deinit(a);
    var cursor: usize = 0;
    for (result) |witness| {
        try stripped.appendSlice(a, prose[cursor..witness.outerStart()]);
        try stripped.appendSlice(a, prose[witness.start_byte..witness.end_byte]);
        cursor = witness.outerEnd();
    }
    try stripped.appendSlice(a, prose[cursor..]);
    const before = try match(a, prose, eligible, edges);
    defer before.deinit(a);
    const after = try match(a, stripped.items, eligible, edges);
    defer after.deinit(a);
    if (before != .witnesses or after != .witnesses or !sameMatches(result, before.witnesses, after.witnesses)) for (result) |*witness| {
        witness.delimiters = 0;
    };
    return result;
}

/// Matched witnesses stay mutable here so delimiters can be counted.
const Found = union(enum) {
    outcome: Outcome,
    witnesses: []Witness,

    fn deinit(self: Found, a: std.mem.Allocator) void {
        switch (self) {
            .outcome => |outcome| outcome.deinit(a),
            .witnesses => |found| a.free(found),
        }
    }
};
fn match(a: std.mem.Allocator, prose: []const u8, occurrences: []const Occurrence, edges: boundary.Edges) std.mem.Allocator.Error!Found {
    const parsed = boundary.Utf8Prose.parse(prose) orelse return .{ .outcome = .{ .rejected = .{ .reason = .invalid_prose } } };
    if (validate(occurrences)) |rejection| return .{ .outcome = .{ .rejected = rejection } };
    var witnesses: std.ArrayList(Witness) = .empty;
    defer witnesses.deinit(a);
    for (occurrences) |occurrence| {
        var offset: usize = 0;
        while (std.mem.indexOfPos(u8, prose, offset, occurrence.bytes)) |start| {
            const end = start + occurrence.bytes.len;
            switch (parsed.evaluate(start, end, edges)) {
                .accepted => try witnesses.append(a, .{ .claim_id = occurrence.claim_id, .start_byte = start, .end_byte = end }),
                .rejected => {},
            }
            // Keep overlapping byte candidates; never choose by longest value,
            // catalogue order or the first occurrence encountered.
            offset = start + 1;
        }
    }
    std.mem.sort(Witness, witnesses.items, {}, lessWitness);
    var diagnostics: std.ArrayList(Diagnostic) = .empty;
    defer diagnostics.deinit(a);
    for (witnesses.items, 0..) |left, index| {
        for (witnesses.items[index + 1 ..]) |right| {
            if (right.start_byte >= left.end_byte) break;
            const conflict: Conflict = .{ .left = left, .right = right };
            try diagnostics.append(a, if (left.start_byte == right.start_byte and left.end_byte == right.end_byte)
                .{ .competing_lineage = conflict }
            else
                .{ .overlapping_matches = conflict });
        }
    }
    if (diagnostics.items.len != 0) return .{ .outcome = .{ .ambiguous = try diagnostics.toOwnedSlice(a) } };
    if (witnesses.items.len == 0) return .{ .outcome = .no_match };
    return .{ .witnesses = try witnesses.toOwnedSlice(a) };
}

/// Sets each witness's delimiters to an equal backtick run on both sides. A run
/// that is all that separates two witnesses belongs to neither. Returns whether
/// any witness has delimiters.
fn countDelimiters(prose: []const u8, witnesses: []Witness) bool {
    var any = false;
    for (witnesses, 0..) |*witness, index| {
        const floor = if (index == 0) 0 else witnesses[index - 1].end_byte;
        const ceiling = if (index + 1 == witnesses.len) prose.len else witnesses[index + 1].start_byte;
        var before: usize = 0;
        while (witness.start_byte - before > floor and prose[witness.start_byte - before - 1] == '`') before += 1;
        var after: usize = 0;
        while (witness.end_byte + after < ceiling and prose[witness.end_byte + after] == '`') after += 1;
        const shared = (before != 0 and witness.start_byte - before == floor and index != 0) or
            (after != 0 and witness.end_byte + after == ceiling and index + 1 != witnesses.len);
        witness.delimiters = if (before == after and !shared) before else 0;
        any = any or witness.delimiters != 0;
    }
    return any;
}

/// Every eligible value matched with delimiters is matched without them, at the
/// same place once the removed delimiters are discounted, and none spans one.
fn sameMatches(cuts: []const Witness, before: []const Witness, after: []const Witness) bool {
    if (before.len != after.len) return false;
    for (before, after) |original, stripped| {
        if (original.claim_id.ordinal != stripped.claim_id.ordinal) return false;
        var removed: usize = 0;
        for (cuts) |cut| {
            if (cut.delimiters == 0) continue;
            for ([_][2]usize{ .{ cut.outerStart(), cut.start_byte }, .{ cut.end_byte, cut.outerEnd() } }) |range| {
                if (original.start_byte < range[1] and range[0] < original.end_byte) return false;
                if (range[1] <= original.start_byte) removed += range[1] - range[0];
            }
        }
        if (stripped.start_byte + removed != original.start_byte) return false;
    }
    return true;
}

fn validate(occurrences: []const Occurrence) ?Rejection {
    for (occurrences, 0..) |occurrence, index| {
        if (occurrence.claim_id.ordinal == 0) return .{ .reason = .invalid_occurrence_id, .occurrence_index = index };
        for (occurrences[0..index]) |prior| if (prior.claim_id.ordinal == occurrence.claim_id.ordinal)
            return .{ .reason = .duplicate_occurrence_id, .occurrence_index = index };
        if (occurrence.bytes.len == 0) return .{ .reason = .empty_occurrence, .occurrence_index = index };
        if (!std.unicode.utf8ValidateSlice(occurrence.bytes)) return .{ .reason = .invalid_occurrence_bytes, .occurrence_index = index };
    }
    return null;
}
fn lessWitness(_: void, left: Witness, right: Witness) bool {
    if (left.start_byte != right.start_byte) return left.start_byte < right.start_byte;
    if (left.end_byte != right.end_byte) return left.end_byte < right.end_byte;
    return left.claim_id.ordinal < right.claim_id.ordinal;
}

const full_field_edges: boundary.Edges = .{ .left = .field_edge, .right = .field_edge };
const test_occurrences = [_]Occurrence{
    .{ .claim_id = .{ .ordinal = 2 }, .bytes = "ACTIVE" },
    .{ .claim_id = .{ .ordinal = 1 }, .bytes = "Hello, World!" },
};

fn delimitersFor(prose: []const u8, occurrences: []const Occurrence, eligible: []const Occurrence) ![]const usize {
    const a = std.testing.allocator;
    const result = try recognize(a, prose, occurrences, full_field_edges);
    defer result.deinit(a);
    const cuts = try delimited(a, prose, result.matched, eligible, full_field_edges);
    defer a.free(cuts);
    const counts = try a.alloc(usize, cuts.len);
    for (cuts, counts) |cut, *count| count.* = cut.delimiters;
    return counts;
}

test "exact recognition counts only matching code delimiters around a value" {
    const a = std.testing.allocator;
    const spaced = [_]Occurrence{ .{ .claim_id = .{ .ordinal = 1 }, .bytes = "x " }, .{ .claim_id = .{ .ordinal = 2 }, .bytes = " y" } };
    const nested = [_]Occurrence{ .{ .claim_id = .{ .ordinal = 1 }, .bytes = "Hello, World!" }, .{ .claim_id = .{ .ordinal = 2 }, .bytes = "Hello" } };
    const active = [_]Occurrence{ .{ .claim_id = .{ .ordinal = 3 }, .bytes = "ACTIVE" }, .{ .claim_id = .{ .ordinal = 4 }, .bytes = "ACTIVE VALUE" } };
    for ([_]struct { prose: []const u8, occurrences: []const Occurrence, eligible: []const Occurrence, delimiters: []const usize }{
        .{ .prose = "Show `Hello, World!` and `ACTIVE`.", .occurrences = &test_occurrences, .eligible = &test_occurrences, .delimiters = &.{ 1, 1 } },
        .{ .prose = "Show ``Hello, World!`` and ACTIVE.", .occurrences = &test_occurrences, .eligible = &test_occurrences, .delimiters = &.{ 2, 0 } },
        .{ .prose = "Show \"Hello, World!\" and ACTIVE.", .occurrences = &test_occurrences, .eligible = &test_occurrences, .delimiters = &.{ 0, 0 } },
        // A backtick that is all that separates two values belongs to neither.
        .{ .prose = "`x ` y`", .occurrences = &spaced, .eligible = &spaced, .delimiters = &.{ 0, 0 } },
        // Removing delimiters that would join a longer value keeps them all.
        .{ .prose = "Display `Hello`, World! now.", .occurrences = &nested, .eligible = &nested, .delimiters = &.{0} },
        .{ .prose = "Show `Hello, World!` and `Hello`, World! now.", .occurrences = &nested, .eligible = &nested, .delimiters = &.{ 0, 0 } },
        // The guard uses every eligible value, not only the caller's matches.
        .{ .prose = "Display `ACTIVE` VALUE.", .occurrences = active[0..1], .eligible = &active, .delimiters = &.{0} },
        .{ .prose = "Display `ACTIVE` VALUE.", .occurrences = active[0..1], .eligible = active[0..1], .delimiters = &.{1} },
    }) |case| {
        const counts = try delimitersFor(case.prose, case.occurrences, case.eligible);
        defer a.free(counts);
        try std.testing.expectEqualSlices(usize, case.delimiters, counts);
    }
    // Unequal runs give the value no boundary, so nothing is matched or removed.
    const uneven = try recognize(a, "Show ``Hello, World!` now.", &test_occurrences, full_field_edges);
    defer uneven.deinit(a);
    try std.testing.expect(uneven == .no_match);
}

test "exact recognition owns stable raw spans for all repeated eligible occurrences" {
    const prose = "Display \"Hello, World!\" and ACTIVE. ACTIVE";
    const result = try recognize(std.testing.allocator, prose, &test_occurrences, full_field_edges);
    defer result.deinit(std.testing.allocator);
    const expected = [_]Witness{
        .{ .claim_id = .{ .ordinal = 1 }, .start_byte = 9, .end_byte = 22 },
        .{ .claim_id = .{ .ordinal = 2 }, .start_byte = 28, .end_byte = 34 },
        .{ .claim_id = .{ .ordinal = 2 }, .start_byte = 36, .end_byte = 42 },
    };
    try std.testing.expectEqualDeep(@as([]const Witness, &expected), result.matched);
    const reversed = [_]Occurrence{ test_occurrences[1], test_occurrences[0] };
    const reordered = try recognize(std.testing.allocator, prose, &reversed, full_field_edges);
    defer reordered.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(result, reordered);
    for (result.matched) |witness| for (test_occurrences) |occurrence| if (occurrence.claim_id.ordinal == witness.claim_id.ordinal)
        try std.testing.expectEqualStrings(occurrence.bytes, prose[witness.start_byte..witness.end_byte]);
    try std.testing.expectEqualStrings("Display \"Hello, World!\" and ACTIVE. ACTIVE", prose);
}

test "exact recognition uses contextual delimiters across unrelated technical and prose values" {
    const cases = [_]struct { prose: []const u8, exact: []const u8, matched: bool }{
        .{ .prose = "Use 1.2.3.", .exact = "1.2", .matched = false },
        .{ .prose = "Use 1.2.", .exact = "1.2", .matched = true },
        .{ .prose = "Call /v1/renewals/archive.", .exact = "/v1/renewals", .matched = false },
        .{ .prose = "Call (/v1/renewals).", .exact = "/v1/renewals", .matched = true },
        .{ .prose = "Read report.txt.", .exact = "report", .matched = false },
        .{ .prose = "Read [report].", .exact = "report", .matched = true },
        .{ .prose = "ACTIVE-PENDING", .exact = "ACTIVE", .matched = false },
        .{ .prose = "ACTIVE.", .exact = "ACTIVE", .matched = true },
    };
    for (cases) |case| {
        const result = try recognize(std.testing.allocator, case.prose, &.{.{ .claim_id = .{ .ordinal = 1 }, .bytes = case.exact }}, full_field_edges);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.matched, result == .matched);
        if (!case.matched) try std.testing.expect(result == .no_match);
    }
}

test "exact recognition never normalizes case Unicode or whitespace into a match" {
    for ([_]struct { prose: []const u8, exact: []const u8 }{
        .{ .prose = "active", .exact = "ACTIVE" },
        .{ .prose = "Cafe\u{301}", .exact = "Café" },
        .{ .prose = "A B", .exact = "A\tB" },
        .{ .prose = "Hello, World?", .exact = "Hello, World!" },
    }) |case| {
        const result = try recognize(std.testing.allocator, case.prose, &.{.{ .claim_id = .{ .ordinal = 1 }, .bytes = case.exact }}, full_field_edges);
        defer result.deinit(std.testing.allocator);
        try std.testing.expect(result == .no_match);
    }
    const exact = try recognize(std.testing.allocator, "Say [Cafe\u{301}] now.", &.{.{ .claim_id = .{ .ordinal = 1 }, .bytes = "Cafe\u{301}" }}, full_field_edges);
    defer exact.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Cafe\u{301}", "Say [Cafe\u{301}] now."[exact.matched[0].start_byte..exact.matched[0].end_byte]);
}

test "competing exact lineages reject the entire field including otherwise disjoint witnesses" {
    const occurrences = [_]Occurrence{
        .{ .claim_id = .{ .ordinal = 1 }, .bytes = "ACTIVE" },
        .{ .claim_id = .{ .ordinal = 2 }, .bytes = "ACTIVE" },
        .{ .claim_id = .{ .ordinal = 3 }, .bytes = "READY" },
    };
    const result = try recognize(std.testing.allocator, "ACTIVE READY", &occurrences, full_field_edges);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), result.ambiguous.len);
    try std.testing.expectEqualDeep(Diagnostic{ .competing_lineage = .{
        .left = .{ .claim_id = .{ .ordinal = 1 }, .start_byte = 0, .end_byte = 6 },
        .right = .{ .claim_id = .{ .ordinal = 2 }, .start_byte = 0, .end_byte = 6 },
    } }, result.ambiguous[0]);
    const reversed = [_]Occurrence{ occurrences[2], occurrences[1], occurrences[0] };
    const other = try recognize(std.testing.allocator, "ACTIVE READY", &reversed, full_field_edges);
    defer other.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(result, other);
}

test "overlapping values and overlapping repetitions cannot select a longest or first match" {
    const different = try recognize(std.testing.allocator, "A A", &.{
        .{ .claim_id = .{ .ordinal = 1 }, .bytes = "A" },
        .{ .claim_id = .{ .ordinal = 2 }, .bytes = "A A" },
    }, full_field_edges);
    defer different.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), different.ambiguous.len);
    for (different.ambiguous) |diagnostic| try std.testing.expect(diagnostic == .overlapping_matches);
    const repeated = try recognize(std.testing.allocator, "A A A", &.{.{ .claim_id = .{ .ordinal = 1 }, .bytes = "A A" }}, full_field_edges);
    defer repeated.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), repeated.ambiguous.len);
    try std.testing.expect(repeated.ambiguous[0] == .overlapping_matches);
}

test "invalid raw recognition inputs reject before allocation and expose the owning occurrence" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    const cases = [_]struct { prose: []const u8 = "ACTIVE", occurrences: []const Occurrence, expected: Rejection }{
        .{ .prose = "ACTIVE\xff", .occurrences = &.{}, .expected = .{ .reason = .invalid_prose } },
        .{ .occurrences = &.{.{ .claim_id = .{ .ordinal = 0 }, .bytes = "ACTIVE" }}, .expected = .{ .reason = .invalid_occurrence_id, .occurrence_index = 0 } },
        .{ .occurrences = &.{.{ .claim_id = .{ .ordinal = 1 }, .bytes = "" }}, .expected = .{ .reason = .empty_occurrence, .occurrence_index = 0 } },
        .{ .occurrences = &.{.{ .claim_id = .{ .ordinal = 1 }, .bytes = "\xff" }}, .expected = .{ .reason = .invalid_occurrence_bytes, .occurrence_index = 0 } },
        .{ .occurrences = &.{
            .{ .claim_id = .{ .ordinal = 1 }, .bytes = "ACTIVE" },
            .{ .claim_id = .{ .ordinal = 1 }, .bytes = "READY" },
        }, .expected = .{ .reason = .duplicate_occurrence_id, .occurrence_index = 1 } },
    };
    for (cases) |case| {
        const result = try recognize(failing.allocator(), case.prose, case.occurrences, full_field_edges);
        defer result.deinit(failing.allocator());
        try std.testing.expectEqualDeep(case.expected, result.rejected);
    }
}

test "empty scope and unmatched eligible values produce no occurrence witnesses" {
    const empty = try recognize(std.testing.allocator, "ACTIVE", &.{}, full_field_edges);
    defer empty.deinit(std.testing.allocator);
    try std.testing.expect(empty == .no_match);
    const absent = try recognize(std.testing.allocator, "UNAVAILABLE", &test_occurrences, full_field_edges);
    defer absent.deinit(std.testing.allocator);
    try std.testing.expect(absent == .no_match);
}

test "literal runs cannot borrow field edges from adjacent passive or source references" {
    const occurrence = [_]Occurrence{.{ .claim_id = .{ .ordinal = 1 }, .bytes = "ACTIVE" }};
    const cases = [_]struct { prose: []const u8, edges: boundary.Edges, matched: bool }{
        // The adjacent reference might render a word continuation; no sentinel
        // spelling or claimed display value can turn that absence into proof.
        .{ .prose = "ACTIVE", .edges = .{ .left = .field_edge, .right = .reference_boundary }, .matched = false },
        .{ .prose = "ACTIVE", .edges = .{ .left = .reference_boundary, .right = .field_edge }, .matched = false },
        .{ .prose = "ACTIVE", .edges = .{ .left = .reference_boundary, .right = .reference_boundary }, .matched = false },
        .{ .prose = "[ACTIVE]", .edges = .{ .left = .reference_boundary, .right = .reference_boundary }, .matched = false },
        .{ .prose = "ACTIVE.", .edges = .{ .left = .field_edge, .right = .reference_boundary }, .matched = false },
        .{ .prose = " ACTIVE ", .edges = .{ .left = .reference_boundary, .right = .reference_boundary }, .matched = true },
        .{ .prose = " [ACTIVE] ", .edges = .{ .left = .reference_boundary, .right = .reference_boundary }, .matched = true },
        .{ .prose = "ACTIVE. ", .edges = .{ .left = .field_edge, .right = .reference_boundary }, .matched = true },
        .{ .prose = " ACTIVE", .edges = .{ .left = .reference_boundary, .right = .field_edge }, .matched = true },
    };
    for (cases) |case| {
        const result = try recognize(std.testing.allocator, case.prose, &occurrence, case.edges);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(case.matched, result == .matched);
        if (!case.matched) try std.testing.expect(result == .no_match);
    }
}

fn allocationCase(a: std.mem.Allocator) !void {
    const matched = try recognize(a, "Hello, World! ACTIVE", &test_occurrences, full_field_edges);
    defer matched.deinit(a);
    try std.testing.expect(matched == .matched);
    // Delimiters removed, and delimiters kept because removal would join a value.
    const nested = [_]Occurrence{ .{ .claim_id = .{ .ordinal = 1 }, .bytes = "Hello, World!" }, .{ .claim_id = .{ .ordinal = 2 }, .bytes = "Hello" } };
    for ([_][]const u8{ "Show `Hello, World!` and `Hello` now.", "Display `Hello`, World! and `Hello` now." }) |prose| {
        const found = try recognize(a, prose, &nested, full_field_edges);
        defer found.deinit(a);
        a.free(try delimited(a, prose, found.matched, &nested, full_field_edges));
    }
    const ambiguous = try recognize(a, "A A READY", &.{
        .{ .claim_id = .{ .ordinal = 1 }, .bytes = "A" },
        .{ .claim_id = .{ .ordinal = 2 }, .bytes = "A A" },
        .{ .claim_id = .{ .ordinal = 3 }, .bytes = "READY" },
    }, full_field_edges);
    defer ambiguous.deinit(a);
    try std.testing.expect(ambiguous == .ambiguous);
}
test "exact recognition cleans every allocation path for witnesses and ambiguity diagnostics" {
    try @import("../test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{});
}
