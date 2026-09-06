const std = @import("std");
const text = @import("domain/typed_text.zig");
const literals = @import("domain/passive_literals.zig");
const fixture = @import("test_fixtures/reference_text.zig");
const reference = @import("reference_evidence_test.zig");
const ingest = @import("reference_ingestion_test.zig").read;
const evidence = @import("domain/reference_evidence.zig");

fn context(prepared: fixture.Prepared, inputs: evidence.Inputs, index: usize) text.Context {
    return .{ .registry = prepared.registry, .current = fixture.safety.value(prepared.owner), .inputs = inputs, .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[index].id } };
}

test "passive literals deduplicate normalized source scalars and retain exact origins" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: reference.IdSource = .{};
    const bytes = "Use src/Cafe\u{301}.zig and src/Café.zig; https://example.test.\r\n";
    const inputs = try reference.prepare(allocator, &ids, try ingest(allocator, "stories.md", bytes));
    const prepared = try fixture.prepare(allocator, inputs);
    defer prepared.deinit();
    try std.testing.expectEqual(@as(usize, 3), prepared.registry.records.len);
    try std.testing.expectEqual(@as(usize, 4), prepared.registry.occurrences.len);
    try std.testing.expectEqualStrings("src/Café.zig", prepared.registry.records[1].value);
    try std.testing.expectEqual(.display_path, prepared.registry.records[1].kind);
    try std.testing.expectEqual(.external_uri, prepared.registry.records[2].kind);
    try std.testing.expectEqualDeep(prepared.registry.occurrences[1].id, prepared.registry.occurrences[2].id);
    const origin = prepared.registry.occurrences[1].origin.reference_span;
    try std.testing.expectEqualStrings("src/Cafe\u{301}.zig", bytes[origin.start_byte..origin.end_byte]);
    try std.testing.expectEqualDeep(prepared.assigned, try fixture.assign.execute(allocator, prepared.candidates));
}

test "literal publication rejects forged scalars origins IDs and incomplete source coverage" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(allocator, &ids, try ingest(allocator, "source.md", "src/one.zig src/one.zig\n"));
    const prepared = try fixture.prepare(allocator, inputs);
    defer prepared.deinit();
    for (0..7) |case| {
        var candidate = prepared.assigned;
        const entries = try allocator.dupe(literals.Candidate, prepared.candidates.entries);
        const ordinals = try allocator.dupe(literals.Id, prepared.assigned.ids);
        candidate.candidates.entries = entries;
        candidate.ids = ordinals;
        switch (case) {
            0 => entries[1].value = "src/forged.zig",
            1 => entries[1].origin.reference_span.start_byte += 1,
            2 => candidate.candidates.entries = entries[0..1],
            3 => ordinals[1].ordinal = 0,
            4 => ordinals[2].ordinal = 3,
            5 => entries[1].kind = .external_uri,
            6 => entries[1].origin.reference_span.block_id.ordinal += 1,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidPassiveLiteral, fixture.validate.execute(allocator, candidate, fixture.safety.value(prepared.owner), inputs));
    }
    var foreign = inputs;
    foreign.corpus.state_id.bytes = "different-state";
    try std.testing.expectError(error.InvalidPathTokenGrammar, fixture.validate.execute(allocator, prepared.assigned, fixture.safety.value(prepared.owner), foreign));
}

test "display literal IDs and source nodes are limited to their exact extraction chunk" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(allocator, &ids, try ingest(allocator, "two.md", "src/first.zig\n" ++ "ordinary\n" ** 63 ++ "https://second.test\n"));
    try std.testing.expectEqual(@as(usize, 2), inputs.chunks.entries.len);
    const prepared = try fixture.prepare(allocator, inputs);
    defer prepared.deinit();
    const local: text.BusinessText = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 2 } } }} };
    _ = try fixture.validator.business(allocator, context(prepared, inputs, 0), local);
    try std.testing.expectError(error.InvalidPassiveLiteral, fixture.validator.business(allocator, context(prepared, inputs, 1), local));
    for ([_]u32{ 0, 999 }) |ordinal| {
        try std.testing.expectError(error.InvalidPassiveLiteral, fixture.validator.business(allocator, context(prepared, inputs, 0), .{ .segments = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = ordinal } } }} }));
    }
    const source: text.ReferenceSemanticText = .{ .nodes = &.{.{ .source = .{ .source_id = inputs.chunks.entries[0].source_id } }} };
    _ = try fixture.validator.reference(allocator, context(prepared, inputs, 0), source);
    try std.testing.expectError(error.InvalidTypedText, fixture.validator.reference(allocator, context(prepared, inputs, 0), .{ .nodes = &.{.{ .source = .{ .source_id = .{ .ordinal = 99 } } }} }));
    const successor = try fixture.prepare(allocator, inputs);
    defer successor.deinit();
    var stale = context(prepared, inputs, 0);
    stale.current = fixture.safety.value(successor.owner);
    try std.testing.expectError(error.StaleNamingPolicy, fixture.validator.business(allocator, stale, local));
}

test "one shared text validator normalizes prose and rejects inline or split path lexemes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(allocator, &ids, try ingest(allocator, "stories.md", "ordinary source\n"));
    const prepared = try fixture.prepare(allocator, inputs);
    defer prepared.deinit();
    const unit = context(prepared, inputs, 0);
    const normalized = try fixture.validator.business(allocator, unit, .{ .segments = &.{ .{ .literal = .{ .value = "Cafe" } }, .{ .literal = .{ .value = "\u{301} choices" } } } });
    try std.testing.expectEqual(@as(usize, 1), normalized.value.segments.len);
    try std.testing.expectEqualStrings("Café choices", normalized.value.segments[0].literal.value);
    for ([_][]const u8{ "stories.md", "src/code.unknown", "https://example.test", "file%252Fname", "C:\\data\\file" }) |value| {
        try std.testing.expectError(error.UnboundPathReference, fixture.validator.business(allocator, unit, .{ .segments = &.{.{ .literal = .{ .value = value } }} }));
        try std.testing.expectError(error.UnboundPathReference, fixture.validator.reference(allocator, unit, .{ .nodes = &.{.{ .literal = .{ .value = value } }} }));
    }
    try std.testing.expectError(error.UnboundPathReference, fixture.validator.business(allocator, unit, .{ .segments = &.{ .{ .literal = .{ .value = "sto" } }, .{ .literal = .{ .value = "ries.md" } } } }));
    for ([_][]const u8{ "", " \t\r\n", "bad\x00text", "\xff", "bad\u{85}text" }) |value| try std.testing.expectError(error.InvalidTypedText, fixture.validator.reference(allocator, unit, .{ .nodes = &.{.{ .literal = .{ .value = value } }} }));
    try std.testing.expectError(error.InvalidTypedText, fixture.validator.business(allocator, unit, .{ .segments = &.{} }));
}

test "closed extraction text shapes reject legacy strings wrong nodes and extra authority fields" {
    const parser = @import("actions/reference/parse_reference_extraction_results.zig").Action{};
    for ([_]struct { kind: []const u8, value: []const u8 }{
        .{ .kind = "business", .value = "\"legacy string\"" },
        .{ .kind = "business", .value = "{\"segments\":[{\"source\":{\"source_id\":{\"ordinal\":1}}}]}" },
        .{ .kind = "technical", .value = "{\"nodes\":[{\"file\":{\"file_id\":1}}]}" },
        .{ .kind = "business", .value = "{\"segments\":[{\"passive\":{\"passive_literal_id\":{\"ordinal\":1},\"display_value\":\"invented\"}}]}" },
        .{ .kind = "business", .value = "{\"segments\":[{\"literal\":{\"value\":\"ordinary\",\"approved\":true}}]}" },
        .{ .kind = "technical", .value = "{\"segments\":[]}" },
        .{ .kind = "business", .value = "{\"segments\":[{\"literal\":{\"value\":\"ordinary\"},\"passive\":{\"passive_literal_id\":{\"ordinal\":1}}}]}" },
        .{ .kind = "business", .value = "null" },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const bytes = try std.fmt.allocPrint(arena.allocator(), "{{\"kind\":\"claims\",\"claims\":[{{\"content\":{{\"kind\":\"{s}\",\"text\":{s}}},\"citations\":[]}}],\"token_classifications\":[]}}", .{ case.kind, case.value });
        try std.testing.expectError(error.InvalidReferenceExtraction, parser.execute(arena.allocator(), .{ .entries = &.{.{ .scope = .{ .state_id = .{ .bytes = "s" }, .chunk_id = .{ .bytes = "c" } }, .result = .{ .response = bytes } }} }));
    }
}

test "known filenames with spaces remain source-backed and cannot be copied inline" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(allocator, &ids, try ingest(allocator, "House Rules.md", "Read (House Rules.md).\n"));
    const prepared = try fixture.prepare(allocator, inputs);
    defer prepared.deinit();
    try std.testing.expectEqual(@as(usize, 1), prepared.registry.records.len);
    try std.testing.expectEqual(@as(usize, 2), prepared.registry.occurrences.len);
    try std.testing.expectError(error.UnboundPathReference, fixture.validator.business(allocator, context(prepared, inputs, 0), .{ .segments = &.{.{ .literal = .{ .value = "Read House Rules.md." } }} }));
    try std.testing.expectError(error.UnboundPathReference, fixture.validator.business(allocator, context(prepared, inputs, 0), .{ .segments = &.{.{ .literal = .{ .value = "Read src/" } }} }));
}

test "all extraction content kinds and no-claim reasons pass through the shared text gate" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(allocator, &ids, try ingest(allocator, "source.md", "A supported statement.\n"));
    const prepared = try fixture.prepare(allocator, inputs);
    defer prepared.deinit();
    const parser = @import("actions/reference/parse_reference_extraction_results.zig").Action{};
    const scope = context(prepared, inputs, 0).scope;
    for ([_][]const u8{ "business", "scope_guard", "design", "technical", "validation", "implementation_assumption", "open_question" }) |kind| {
        const field = if (std.mem.eql(u8, kind, "business") or std.mem.eql(u8, kind, "scope_guard")) "segments" else "nodes";
        const bytes = try std.fmt.allocPrint(allocator, "{{\"kind\":\"claims\",\"claims\":[{{\"content\":{{\"kind\":\"{s}\",\"{s}\":[{{\"kind\":\"literal\",\"value\":\"A statement\"}}]}},\"citations\":[]}}],\"token_classifications\":[]}}", .{ kind, field });
        const parsed = try parser.execute(allocator, .{ .entries = &.{.{ .scope = scope, .result = .{ .response = bytes } }} });
        const checked = try fixture.validate_text.execute(allocator, prepared.registry, fixture.safety.value(prepared.owner), inputs, parsed);
        try std.testing.expectEqualStrings(kind, @tagName(checked.entries[0].outcome.claims[0].content));
    }
    const reason = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":[{\"kind\":\"literal\",\"value\":\"Read source.md\"}]},\"token_classifications\":[]}";
    const parsed = try parser.execute(allocator, .{ .entries = &.{.{ .scope = scope, .result = .{ .response = reason } }} });
    try std.testing.expectError(error.UnboundPathReference, fixture.validate_text.execute(allocator, prepared.registry, fixture.safety.value(prepared.owner), inputs, parsed));
}

test "source-backed literal and typed-text allocations clean up on every failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(arena.allocator(), &ids, try ingest(arena.allocator(), "source.md", "src/main.zig\n"));
    const prepared = try fixture.prepare(arena.allocator(), inputs);
    defer prepared.deinit();
    _ = try fixture.validator.business(arena.allocator(), context(prepared, inputs, 0), .{ .segments = &.{ .{ .literal = .{ .value = "Display " } }, .{ .passive = .{ .passive_literal_id = .{ .ordinal = 2 } } } } });
}
