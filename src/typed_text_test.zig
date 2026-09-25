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

test "prose punctuation never manufactures a reference and exact selections retain scope" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(a, &ids, try ingest(a, "source.md", "A supported statement.\n"));
    const prepared = try fixture.prepare(a, inputs);
    defer prepared.deinit();
    const ctx = context(prepared, inputs, 0);
    var scoped: text.ScopeSetContext = .{ .registry = ctx.registry, .current = ctx.current, .inputs = inputs, .scopes = &.{ctx.scope} };
    for ([_][]const u8{ "Display the UTC date/time.", "Support input/output.", "Read src/ledger.zig.", "See https://example.test" }) |value| {
        const checked = (try fixture.validator.checkBusinessIn(a, scoped, .{ .segments = &.{.{ .literal = .{ .value = value } }} })).valid;
        try std.testing.expectEqual(@as(usize, 1), checked.value.segments.len);
        try std.testing.expectEqualStrings(value, checked.value.segments[0].literal.value);
    }
    const selected: text.ExactCopy = .{ .token_id = .{ .ordinal = 7 }, .citation_id = .{ .ordinal = 9 } };
    const content: text.BusinessText = .{ .segments = &.{ .{ .literal = .{ .value = "Display " } }, .{ .exact_copy = selected }, .{ .literal = .{ .value = " at date/time." } } } };
    const rejected = (try fixture.validator.checkBusinessIn(a, scoped, content)).invalid;
    try std.testing.expectEqual(.unknown_exact, rejected.reason);
    try std.testing.expectEqualDeep(selected, rejected.rejected_exact.?);
    try std.testing.expectEqual(@as(usize, 1), rejected.first_node);
    scoped.exact_copies = &.{selected};
    try std.testing.expectEqualDeep(content, (try fixture.validator.checkBusinessIn(a, scoped, content)).valid.value);
    scoped.scopes = &.{};
    try std.testing.expectError(error.InvalidTypedText, fixture.validator.checkBusinessIn(a, scoped, content));
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
    try std.testing.expectEqual(@as(usize, 2), prepared.registry.records.len);
    try std.testing.expectEqual(@as(usize, 3), prepared.registry.occurrences.len);
    try std.testing.expectEqualStrings("src/Café.zig", prepared.registry.records[0].value);
    try std.testing.expectEqual(.display_path, prepared.registry.records[0].kind);
    try std.testing.expectEqual(.external_uri, prepared.registry.records[1].kind);
    try std.testing.expectEqualDeep(prepared.registry.occurrences[0].id, prepared.registry.occurrences[1].id);
    const origin = prepared.registry.occurrences[0].origin;
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
            0 => entries[0].value = "src/forged.zig",
            1 => entries[0].origin.start_byte += 1,
            2 => candidate.candidates.entries = entries[0..1],
            3 => ordinals[1].ordinal = 0,
            4 => ordinals[1].ordinal = 3,
            5 => entries[0].kind = .external_uri,
            6 => entries[0].origin.block_id.ordinal += 1,
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
    const local: text.BusinessText = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 1 } } }} };
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

test "one shared text validator normalizes inert prose without promoting inline or split path lexemes" {
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
        _ = try fixture.validator.business(allocator, unit, .{ .segments = &.{.{ .literal = .{ .value = value } }} });
        _ = try fixture.validator.reference(allocator, unit, .{ .nodes = &.{.{ .literal = .{ .value = value } }} });
    }
    _ = try fixture.validator.business(allocator, unit, .{ .segments = &.{ .{ .literal = .{ .value = "sto" } }, .{ .literal = .{ .value = "ries.md" } } } });
    for ([_][]const u8{ "", " \t\r\n", "bad\x00text", "\xff", "bad\u{85}text" }) |value| try std.testing.expectError(error.InvalidTypedText, fixture.validator.reference(allocator, unit, .{ .nodes = &.{.{ .literal = .{ .value = value } }} }));
    try std.testing.expectError(error.InvalidTypedText, fixture.validator.business(allocator, unit, .{ .segments = &.{} }));
}

test "closed extraction text shapes reject legacy strings wrong nodes and extra authority fields" {
    const parser = @import("actions/reference/parse_reference_extraction_results.zig").Action{};
    for ([_]struct { kind: []const u8, value: []const u8 }{
        .{ .kind = "business", .value = "\"legacy string\"" },
        .{ .kind = "business", .value = "{\"segments\":[{\"source\":{\"source_id\":1}}]}" },
        .{ .kind = "technical", .value = "{\"nodes\":[{\"file\":{\"file_id\":1}}]}" },
        .{ .kind = "business", .value = "{\"segments\":[{\"passive\":{\"passive_literal_id\":1,\"display_value\":\"invented\"}}]}" },
        .{ .kind = "business", .value = "{\"segments\":[{\"literal\":{\"value\":\"ordinary\",\"approved\":true}}]}" },
        .{ .kind = "technical", .value = "{\"segments\":[]}" },
        .{ .kind = "business", .value = "{\"segments\":[{\"literal\":{\"value\":\"ordinary\"},\"passive\":{\"passive_literal_id\":1}}]}" },
        .{ .kind = "business", .value = "null" },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const bytes = try std.fmt.allocPrint(arena.allocator(), "{{\"kind\":\"claims\",\"claims\":[{{\"content\":{{\"kind\":\"{s}\",\"text\":{s}}},\"citations\":[]}}],\"token_classifications\":[]}}", .{ case.kind, case.value });
        try std.testing.expectError(error.InvalidReferenceExtraction, parser.execute(arena.allocator(), .{ .entries = &.{.{ .scope = .{ .state_id = .{ .bytes = "s" }, .chunk_id = .{ .bytes = "c" } }, .result = .{ .response = bytes } }} }));
    }
}

test "known filename selections remain distinct from prose with matching bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(allocator, &ids, try ingest(allocator, "House Rules.md", "Read (House Rules.md).\n"));
    const prepared = try fixture.prepare(allocator, inputs);
    defer prepared.deinit();
    try std.testing.expectEqual(@as(usize, 1), prepared.registry.records.len);
    try std.testing.expectEqual(@as(usize, 1), prepared.registry.occurrences.len);
    _ = try fixture.validator.business(allocator, context(prepared, inputs, 0), .{ .segments = &.{.{ .literal = .{ .value = "Read House Rules.md." } }} });
    _ = try fixture.validator.business(allocator, context(prepared, inputs, 0), .{ .segments = &.{.{ .literal = .{ .value = "Read src/" } }} });
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
        const bytes = try std.fmt.allocPrint(allocator, "{{\"kind\":\"claims\",\"claims\":[{{\"content\":{{\"kind\":\"{s}\",\"{s}\":[\"A statement\"]}},\"citations\":[]}}],\"token_classifications\":[]}}", .{ kind, field });
        const parsed = try parser.execute(allocator, .{ .entries = &.{.{ .scope = scope, .result = .{ .response = bytes } }} });
        const checked = (try fixture.validate_text.execute(allocator, prepared.registry, fixture.safety.value(prepared.owner), inputs, parsed)).valid;
        try std.testing.expectEqualStrings(kind, @tagName(checked.entries[0].outcome.claims[0].content));
    }
    const reason = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":[\"Read source.md\"]},\"token_classifications\":[]}";
    const parsed = try parser.execute(allocator, .{ .entries = &.{.{ .scope = scope, .result = .{ .response = reason } }} });
    try std.testing.expect((try fixture.validate_text.execute(allocator, prepared.registry, fixture.safety.value(prepared.owner), inputs, parsed)) == .valid);
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
    _ = try fixture.validator.business(arena.allocator(), context(prepared, inputs, 0), .{ .segments = &.{ .{ .literal = .{ .value = "Display " } }, .{ .passive = .{ .passive_literal_id = .{ .ordinal = 1 } } } } });
}

test "source names remain citation metadata and only body occurrences become content choices" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { name: []const u8, source: []const u8, filename: []const u8, reference: bool = true }{
        .{ .name = "stories.md", .source = "The application displays a greeting.", .filename = "report.csv", .reference = false },
        .{ .name = "requirements.md", .source = "The user exports an account statement.", .filename = "requirements.md" },
    }) |case| {
        var ids: reference.IdSource = .{};
        const input = try reference.prepare(a, &ids, try ingest(a, case.name, case.source));
        const prepared = try fixture.prepare(a, input);
        defer prepared.deinit();
        try std.testing.expectEqualStrings(case.name, input.corpus.sources[0].path.bytes);
        try std.testing.expectEqual(@as(usize, 0), prepared.registry.records.len);
        const scope = context(prepared, input, 0).scope;
        const choices = try @import("domain/reference_model_input.zig").passiveChoices(a, prepared.registry, input, &.{scope});
        try std.testing.expectEqual(@as(usize, 0), choices.len);
        const invented: text.BusinessText = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 1 } } }} };
        try std.testing.expectError(error.InvalidPassiveLiteral, fixture.validator.business(a, context(prepared, input, 0), invented));
        try std.testing.expectError(error.InvalidPassiveLiteral, literals.resolveCaptured(.{ .records = prepared.registry.records, .occurrences = prepared.registry.occurrences }, input, &.{scope}, .{ .ordinal = 1 }));

        const body = try std.fmt.allocPrint(a, "{s} Export {s}.\n", .{ case.source, case.filename });
        const mentioned = try reference.prepare(a, &ids, try ingest(a, case.name, body));
        const available = try fixture.prepare(a, mentioned);
        defer available.deinit();
        const ctx = context(available, mentioned, 0);
        const permitted = try @import("domain/reference_model_input.zig").passiveChoices(a, available.registry, mentioned, &.{ctx.scope});
        if (!case.reference) {
            // A filename outside the configured detector remains ordinary prose;
            // this change adds neither extensions nor a second lexical policy.
            try std.testing.expectEqual(@as(usize, 0), permitted.len);
            _ = try fixture.validator.business(a, ctx, .{ .segments = &.{.{ .literal = .{ .value = body } }} });
            continue;
        }
        try std.testing.expectEqual(@as(usize, 1), permitted.len);
        try std.testing.expectEqualStrings(case.filename, permitted[0].value);
        const prose: text.BusinessText = .{ .segments = &.{ .{ .literal = .{ .value = "Export " } }, .{ .passive = .{ .passive_literal_id = permitted[0].id } } } };
        _ = try fixture.validator.business(a, ctx, prose);
        try std.testing.expectEqualDeep(permitted[0], try literals.resolveCaptured(.{ .records = available.registry.records, .occurrences = available.registry.occurrences }, mentioned, &.{ctx.scope}, permitted[0].id));
    }
}
