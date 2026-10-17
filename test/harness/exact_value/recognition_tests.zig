const std = @import("std");
const recognition = @import("recognition.zig");
const classifier: recognition.LexicalClassifier = .{ .boundary_fn = @import("exact_value_unicode").wholeWordBoundary };
const requirement: recognition.RequirementId = .{ .value = 1 };
const other: recognition.RequirementId = .{ .value = 2 };

const allocation_occurrences: []const recognition.Occurrence = &.{
    .{ .id = .{ .value = 1 }, .requirements = &.{requirement}, .bytes = "ACTIVE" },
    .{ .id = .{ .value = 2 }, .requirements = &.{requirement}, .bytes = "ACTIVE-RENEWAL" },
    .{ .id = .{ .value = 3 }, .requirements = &.{other}, .bytes = "READY" },
    .{ .id = .{ .value = 4 }, .requirements = &.{requirement}, .bytes = "Done!" },
};
const allocation_input: recognition.Input = .{
    .prose = "ACTIVE-RENEWAL READY NotACTIVE Done! ACTIVE",
    .bound_requirements = &.{requirement},
    .occurrences = allocation_occurrences,
};

test "prototype owns every result array and cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(a: std.mem.Allocator) !void {
    const outcome = try recognition.recognize(a, allocation_input, classifier);
    defer outcome.deinit(a);
    const report = outcome.evaluated;
    try std.testing.expectEqual(.ambiguous, report.state);
    try std.testing.expectEqual(@as(usize, 2), report.matches.len);
    try std.testing.expectEqual(@as(usize, 1), report.unbound_matches.len);
    try std.testing.expectEqual(@as(usize, 2), report.diagnostics.len);
    try std.testing.expectEqual(@as(u32, 4), report.matches[0].occurrence.value);
    try std.testing.expectEqual(@as(u32, 1), report.matches[1].occurrence.value);
    try std.testing.expectEqual(.boundary_rejected, std.meta.activeTag(report.diagnostics[0]));
    try std.testing.expectEqual(.overlapping_matches, std.meta.activeTag(report.diagnostics[1]));
    try std.testing.expectEqualStrings("ACTIVE-RENEWAL READY NotACTIVE Done! ACTIVE", allocation_input.prose);
}

test "catalogue order cannot choose a lineage or change witness ordering" {
    const original = try recognition.recognize(std.testing.allocator, allocation_input, classifier);
    defer original.deinit(std.testing.allocator);
    var reversed: [allocation_occurrences.len]recognition.Occurrence = undefined;
    for (allocation_occurrences, 0..) |occurrence, index| reversed[reversed.len - index - 1] = occurrence;
    var reordered = allocation_input;
    reordered.occurrences = &reversed;
    const other_order = try recognition.recognize(std.testing.allocator, reordered, classifier);
    defer other_order.deinit(std.testing.allocator);
    try std.testing.expectEqualDeep(original.evaluated, other_order.evaluated);
}

test "overlapping repeated occurrences of one identity remain ambiguous" {
    const outcome = try recognition.recognize(std.testing.allocator, .{
        .prose = "......",
        .bound_requirements = &.{requirement},
        .occurrences = &.{.{ .id = .{ .value = 1 }, .requirements = &.{requirement}, .bytes = "..." }},
    }, classifier);
    defer outcome.deinit(std.testing.allocator);
    try std.testing.expectEqual(.ambiguous, outcome.evaluated.state);
    try std.testing.expectEqual(@as(usize, 0), outcome.evaluated.matches.len);
    try std.testing.expectEqual(@as(usize, 5), outcome.evaluated.diagnostics.len);
    for (outcome.evaluated.diagnostics) |diagnostic| {
        try std.testing.expectEqual(.overlapping_matches, std.meta.activeTag(diagnostic));
        try std.testing.expectEqual(diagnostic.overlapping_matches.left.occurrence.value, diagnostic.overlapping_matches.right.occurrence.value);
    }
}

test "shared scalar policy permits exact tabs and newlines without normalization" {
    const bytes = "A\tB\r\nC";
    const prose = "Display [A\tB\r\nC] exactly.";
    const outcome = try recognition.recognize(std.testing.allocator, .{
        .prose = prose,
        .bound_requirements = &.{requirement},
        .occurrences = &.{.{ .id = .{ .value = 1 }, .requirements = &.{requirement}, .bytes = bytes }},
    }, classifier);
    defer outcome.deinit(std.testing.allocator);
    try std.testing.expectEqual(.matched, outcome.evaluated.state);
    const witness = outcome.evaluated.matches[0];
    try std.testing.expectEqual(@as(usize, 9), witness.start_byte);
    try std.testing.expectEqualStrings(bytes, prose[witness.start_byte..witness.end_byte]);
    try std.testing.expectEqualStrings("A\tB\r\nC", bytes);
}

test "invalid input rejects before allocating or reporting lexical matches" {
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    const outcome = try recognition.recognize(failing.allocator(), .{
        .prose = "ACTIVE",
        .bound_requirements = &.{requirement},
        .occurrences = &.{
            .{ .id = .{ .value = 7 }, .requirements = &.{requirement}, .bytes = "ACTIVE" },
            .{ .id = .{ .value = 7 }, .requirements = &.{other}, .bytes = "ACTIVE" },
        },
    }, classifier);
    defer outcome.deinit(failing.allocator());
    try std.testing.expectEqual(.duplicate_occurrence_id, outcome.rejected.reason);
    try std.testing.expectEqual(@as(?usize, 1), outcome.rejected.occurrence_index);
}
