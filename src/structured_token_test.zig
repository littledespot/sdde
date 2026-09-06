const std = @import("std");
const tokens = @import("domain/structured_tokens.zig");
const extraction = @import("domain/reference_extraction.zig");
const evidence = @import("domain/reference_evidence.zig");
const source_fixture = @import("reference_evidence_test.zig");
const ingest = @import("reference_ingestion_test.zig").read;
const fixture = @import("test_fixtures/reference_tokens.zig");
const text = @import("test_fixtures/reference_text.zig");
const parse = @import("actions/reference/parse_reference_extraction_results.zig").Action{};
const validate = @import("actions/reference/validate_reference_claims.zig").Action{};
const assign = @import("actions/reference/assign_reference_claim_identities.zig").Action{};
const build = @import("actions/reference/build_reference_extraction_ledger.zig").Action{};
const account = @import("actions/reference/validate_reference_extraction_accounting.zig").Action{};

fn inputsFor(allocator: std.mem.Allocator, bytes: []const u8) !evidence.Inputs {
    var ids: source_fixture.IdSource = .{};
    return source_fixture.prepare(allocator, &ids, try ingest(allocator, "arbitrary.md", bytes));
}
fn result(inputs: evidence.Inputs, chunk: evidence.Chunk, bytes: []const u8) extraction.RawResult {
    return .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = bytes } };
}
const Run = struct { assigned: extraction.TokenAssignments, ledger: extraction.Ledger };
fn run(allocator: std.mem.Allocator, inputs: evidence.Inputs, available: tokens.Candidates, entries: []const extraction.RawResult) !Run {
    const parsed = try parse.execute(allocator, .{ .entries = entries });
    const assigned = try fixture.assign.execute(allocator, try fixture.classify.execute(allocator, inputs, available, try text.check(allocator, inputs, parsed)));
    const valid = try validate.execute(allocator, inputs, try fixture.build.execute(allocator, assigned));
    const ledger = try build.execute(allocator, try assign.execute(allocator, valid));
    _ = try account.execute(inputs, assigned, ledger);
    return .{ .assigned = assigned, .ledger = ledger };
}
const token_only = "{\"kind\":\"claims\",\"claims\":[],\"token_classifications\":[]}";

test "Markdown eligibility excludes prose quotes fences and unmatched delimiters" {
    const Case = struct { source: []const u8, exact: []const []const u8 };
    for ([_]Case{
        .{ .source = "Display `Hello, World!`.", .exact = &.{"Hello, World!"} },
        .{ .source = "A grey button says \"Saved\".", .exact = &.{} },
        .{ .source = "Use ``a ` b`` and `other`.", .exact = &.{ "a ` b", "other" } },
        .{ .source = "` Cafe\u{301} \r\n日本語 `", .exact = &.{" Cafe\u{301} \r\n日本語 "} },
        .{ .source = "A `first\n    continuation`.", .exact = &.{"first\n    continuation"} },
        .{ .source = "# `heading`\n    `indented code`", .exact = &.{"heading"} },
        .{ .source = "A `broken\n# Heading\n`not a continuation", .exact = &.{} },
        .{ .source = "A `broken\n---\n`not a continuation", .exact = &.{} },
        .{ .source = "```zig\n`hidden`\n```\n`shown`\n", .exact = &.{"shown"} },
        .{ .source = "~~~~\n`hidden`\n~~~\n`still hidden`\n~~~~\n`shown`", .exact = &.{"shown"} },
        .{ .source = "~~~\n`unclosed fence`", .exact = &.{} },
        .{ .source = "> ```\n> `hidden`\n> ```\n> `shown`", .exact = &.{"shown"} },
        .{ .source = "- ```\n  `hidden`\n  ```\n- `shown`", .exact = &.{"shown"} },
        .{ .source = "    `indented code`\n\t`more code`\n\n`shown`", .exact = &.{"shown"} },
        .{ .source = "\\`escaped\\` and `shown`", .exact = &.{"shown"} },
        .{ .source = "`unmatched\n\n`another unmatched", .exact = &.{} },
        .{ .source = "`backslash\\`", .exact = &.{"backslash\\"} },
        .{ .source = "`outer \\``suffix`", .exact = &.{"outer \\``suffix"} },
        .{ .source = "`one``two`", .exact = &.{"one``two"} },
        .{ .source = "``unmatched `shown`", .exact = &.{"shown"} },
        .{ .source = "<!-- `not Markdown` --> `shown`", .exact = &.{"shown"} },
        .{ .source = "`<!-- exact -->` `<span title=\"exact\">`", .exact = &.{ "<!-- exact -->", "<span title=\"exact\">" } },
        .{ .source = "<span title=\"`not code`\">`shown`</span>", .exact = &.{"shown"} },
        .{ .source = "<!-- `hidden`\n\n`also hidden` --> `shown`", .exact = &.{"shown"} },
        .{ .source = "<div>\n`not Markdown`\n</div>\n\n`shown`", .exact = &.{"shown"} },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const inputs = try inputsFor(arena.allocator(), case.source);
        const available = try fixture.candidates(arena.allocator(), inputs);
        try std.testing.expectEqual(case.exact.len, available.entries.len);
        for (case.exact, available.entries, 1..) |expected, candidate, ordinal| {
            try std.testing.expectEqualStrings(expected, candidate.fact.citation.verbatim.?);
            try std.testing.expectEqual(ordinal, candidate.id.ordinal);
            try std.testing.expectEqual(.markdown_inline_code_v1, candidate.id.extractor_id);
        }
    }
}

test "reader keeps multiline values together and fails over-limit values explicitly" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try inputsFor(allocator, "Before\n`" ++ "line\n" ** 70 ++ "end`\nAfter");
    const available = try fixture.candidates(allocator, inputs);
    try std.testing.expectEqual(@as(usize, 1), available.entries.len);
    const resolved = try evidence.resolve(inputs, available.entries[0].fact.scope);
    try std.testing.expect(available.entries[0].fact.citation.location.end.byte <= resolved.chunk.span.end.byte);
    const near_limit = try inputsFor(allocator, "a" ** 16000 ++ " `" ++ "b" ** 1000 ++ "`");
    try std.testing.expectEqual(@as(usize, 1), (try fixture.candidates(allocator, near_limit)).entries.len);
    try std.testing.expectError(error.InvalidReferenceAccounting, ingest(allocator, "long.md", "`" ++ "x" ** (@import("domain/reference_ingestion.zig").limits.block_bytes + 1) ++ "`"));
}

test "exact values of every token kind enter ordinary claim and citation accounting" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try inputsFor(allocator, "`Hello, World!` ` Cafe\u{301} \r\n日本語 ` `#a0a0a0` `src/main.zig`");
    const available = try fixture.candidates(allocator, inputs);
    inline for (std.meta.tags(tokens.Kind)) |kind| {
        const choices = try allocator.alloc(tokens.Classification, available.entries.len);
        for (available.entries, choices) |candidate, *choice| choice.* = .{ .preserve = .{ .token_candidate_id = candidate.id, .kind = kind } };
        const response = try fixture.wire(allocator, token_only, choices);
        const completed = try run(allocator, inputs, available, &.{result(inputs, inputs.chunks.entries[0], response)});
        try std.testing.expectEqual(available.entries.len, completed.ledger.claims.len);
        for (completed.ledger.claims, available.entries, 1..) |claim, candidate, ordinal| {
            const token = claim.content.preserved_token;
            try std.testing.expectEqual(ordinal, token.value.id.ordinal);
            try std.testing.expectEqual(kind, token.value.kind);
            try std.testing.expectEqualStrings(candidate.fact.citation.verbatim.?, token.value.raw_value.bytes);
            try std.testing.expectEqual(token.citation_id.ordinal, claim.citation_ids[0].ordinal);
            try std.testing.expectEqualDeep(token.value.id, token.value.downstream_obligation_id.token_id);
        }
        const again = try run(allocator, inputs, available, &.{result(inputs, inputs.chunks.entries[0], response)});
        try std.testing.expectEqualDeep(completed, again);
    }
}

test "classification is total and scoped; irrelevant is explicit and blocked stays blocked" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try inputsFor(allocator, "`one` `two`\n");
    const available = try fixture.candidates(allocator, inputs);
    const first: tokens.Classification = .{ .preserve = .{ .token_candidate_id = available.entries[0].id, .kind = .business_exact_string } };
    const second: tokens.Classification = .{ .irrelevant = available.entries[1].id };
    const chunk = inputs.chunks.entries[0];
    const accepted = try run(allocator, inputs, available, &.{result(inputs, chunk, try fixture.wire(allocator, token_only, &.{ first, second }))});
    try std.testing.expectEqual(@as(usize, 1), accepted.ledger.claims.len);
    const reversed = try run(allocator, inputs, available, &.{result(inputs, chunk, try fixture.wire(allocator, token_only, &.{ second, first }))});
    try std.testing.expectEqualDeep(accepted.ledger, reversed.ledger);
    for ([_][]const tokens.Classification{ &.{}, &.{first}, &.{ first, first }, &.{ first, second, second } }) |choices| {
        try std.testing.expectError(error.InvalidStructuredTokens, run(allocator, inputs, available, &.{result(inputs, chunk, try fixture.wire(allocator, token_only, choices))}));
    }
    var foreign = first;
    foreign.preserve.token_candidate_id.source_id.ordinal += 1;
    try std.testing.expectError(error.InvalidStructuredTokens, run(allocator, inputs, available, &.{result(inputs, chunk, try fixture.wire(allocator, token_only, &.{ foreign, second }))}));
    const empty = @import("reference_extraction_test.zig").no_claim;
    try std.testing.expectError(error.InvalidStructuredTokens, run(allocator, inputs, available, &.{result(inputs, chunk, try fixture.wire(allocator, empty, &.{ first, second }))}));
    const all_irrelevant = try run(allocator, inputs, available, &.{result(inputs, chunk, try fixture.wire(allocator, empty, &.{ .{ .irrelevant = available.entries[0].id }, second }))});
    try std.testing.expectEqual(@as(usize, 0), all_irrelevant.ledger.claims.len);
    const blocked = try run(allocator, inputs, available, &.{.{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .blocked = .extraction_failed } }});
    try std.testing.expectEqual(.blocked, (try account.execute(inputs, blocked.assigned, blocked.ledger)).outcome);
}

test "closed classifications never accept model bytes canonical IDs or mismatched kind fields" {
    const id = "\"token_candidate_id\":{\"source_id\":{\"ordinal\":1},\"extractor_id\":\"markdown_inline_code_v1\",\"ordinal\":1}";
    for ([_][]const u8{
        "{" ++ id ++ ",\"decision\":\"preserve\"}",
        "{" ++ id ++ ",\"decision\":\"preserve\",\"kind\":\"invented\"}",
        "{" ++ id ++ ",\"decision\":\"irrelevant\",\"kind\":null}",
        "{" ++ id ++ ",\"decision\":\"irrelevant\",\"kind\":\"exact_identifier\"}",
        "{" ++ id ++ ",\"decision\":\"irrelevant\",\"bytes\":\"rewritten\"}",
        "{" ++ id ++ ",\"decision\":\"irrelevant\",\"citation_id\":1}",
        "{" ++ id ++ ",\"decision\":\"irrelevant\",\"token_id\":1}",
        "{" ++ id ++ ",\"decision\":\"irrelevant\",\"decision\":\"preserve\"}",
    }) |choice| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const response = try std.fmt.allocPrint(arena.allocator(), "{{\"kind\":\"claims\",\"claims\":[],\"token_classifications\":[{s}]}}", .{choice});
        try std.testing.expectError(error.InvalidReferenceExtraction, parse.execute(arena.allocator(), .{ .entries = &.{.{ .scope = .{ .state_id = .{ .bytes = "s" }, .chunk_id = .{ .bytes = "c" } }, .result = .{ .response = response } }} }));
    }
}

test "cross-chunk and stale candidate classifications fail while arrival order cannot change token IDs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try inputsFor(allocator, "First `one`\n" ++ "line\n" ** 65 ++ "Second `two`\n");
    const available = try fixture.candidates(allocator, inputs);
    try std.testing.expectEqual(@as(usize, 2), inputs.chunks.entries.len);
    const first = inputs.chunks.entries[0];
    const second = inputs.chunks.entries[1];
    const first_choices = try fixture.classifications(allocator, available, first);
    const second_choices = try fixture.classifications(allocator, available, second);
    const first_result = result(inputs, first, try fixture.wire(allocator, token_only, first_choices));
    const second_result = result(inputs, second, try fixture.wire(allocator, token_only, second_choices));
    const ordered = try run(allocator, inputs, available, &.{ first_result, second_result });
    const reversed = try run(allocator, inputs, available, &.{ second_result, first_result });
    try std.testing.expectEqualDeep(ordered.ledger, reversed.ledger);
    try std.testing.expectError(error.InvalidStructuredTokens, run(allocator, inputs, available, &.{ result(inputs, first, try fixture.wire(allocator, token_only, second_choices)), second_result }));
    var stale = available;
    stale.state_id.bytes = "another-state";
    try std.testing.expectError(error.InvalidStructuredTokens, run(allocator, inputs, stale, &.{ first_result, second_result }));
    var forged_candidate = available.entries[0];
    forged_candidate.id.ordinal = 999;
    var forged = available;
    forged.entries = &.{ forged_candidate, available.entries[1] };
    try std.testing.expectError(error.InvalidStructuredTokens, run(allocator, inputs, forged, &.{ first_result, second_result }));
}

test "candidate assignment rejects forged omitted stale and changed source facts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try inputsFor(allocator, "`exact` ordinary");
    const facts = try fixture.extract.execute(allocator, inputs);
    for (0..5) |case| {
        var tampered = facts;
        var fact = facts.entries[0];
        switch (case) {
            0 => tampered.entries = &.{},
            1 => {
                fact.citation.verbatim = "changed";
                tampered.entries = &.{fact};
            },
            2 => {
                fact.citation.location.start.byte += 1;
                tampered.entries = &.{fact};
            },
            3 => tampered.state_id.bytes = "stale",
            4 => tampered.entries = &.{ fact, fact },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidStructuredTokens, fixture.identify.execute(allocator, inputs, tampered));
    }
}

test "final accounting rejects changed bytes kind obligation and missing or duplicated preserved claims" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try inputsFor(allocator, "`Cafe\u{301}`");
    const available = try fixture.candidates(allocator, inputs);
    const chunk = inputs.chunks.entries[0];
    const completed = try run(allocator, inputs, available, &.{result(inputs, chunk, try fixture.wire(allocator, token_only, try fixture.classifications(allocator, available, chunk)))});
    for (0..6) |case| {
        var ledger = completed.ledger;
        var claim = ledger.claims[0];
        switch (case) {
            0 => claim.content.preserved_token.value.raw_value.bytes = "Café",
            1 => claim.content.preserved_token.value.kind = .visual_color,
            2 => claim.content.preserved_token.value.downstream_obligation_id.token_id.ordinal += 1,
            3 => claim.content.preserved_token.citation_id.ordinal += 1,
            4 => claim.content.preserved_token.value.candidate_id.ordinal += 1,
            5 => claim.content = .{ .model = .{ .business = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Replaced exact copy" } }} } } } },
            else => unreachable,
        }
        ledger.claims = &.{claim};
        try std.testing.expectError(error.InvalidStructuredTokens, account.execute(inputs, completed.assigned, ledger));
    }
    var duplicated = completed.ledger;
    var second_claim = duplicated.claims[0];
    second_claim.id.ordinal = 2;
    second_claim.citation_ids = &.{.{ .ordinal = 2 }};
    second_claim.content.preserved_token.citation_id.ordinal = 2;
    var second_citation = duplicated.citations[0];
    second_citation.id.ordinal = 2;
    var chunk_result = duplicated.chunks[0];
    chunk_result.outcome = .{ .claims = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } } };
    duplicated.claims = &.{ duplicated.claims[0], second_claim };
    duplicated.citations = &.{ duplicated.citations[0], second_citation };
    duplicated.chunks = &.{chunk_result};
    duplicated.next_claim_ordinal = 3;
    duplicated.next_citation_ordinal = 3;
    try std.testing.expectError(error.InvalidStructuredTokens, account.execute(inputs, completed.assigned, duplicated));
}

test "allocation failures release the whole exact-value candidate pipeline" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const inputs = try inputsFor(scratch, "`exact value`");
    const available = try fixture.candidates(scratch, inputs);
    const chunk = inputs.chunks.entries[0];
    _ = try run(scratch, inputs, available, &.{result(inputs, chunk, try fixture.wire(scratch, token_only, try fixture.classifications(scratch, available, chunk)))});
}
