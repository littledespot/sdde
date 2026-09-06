const std = @import("std");
const extraction = @import("domain/reference_extraction.zig");
const evidence = @import("domain/reference_evidence.zig");
const fixture = @import("reference_evidence_test.zig");
const ingest = @import("reference_ingestion_test.zig").read;
const parse = @import("actions/reference/parse_reference_extraction_results.zig").Action{};
const validate = @import("actions/reference/validate_reference_claims.zig").Action{};
const assign = @import("actions/reference/assign_reference_claim_identities.zig").Action{};
const build = @import("actions/reference/build_reference_extraction_ledger.zig").Action{};
const account = @import("actions/reference/validate_reference_extraction_accounting.zig").Action{};
const text_fixture = @import("test_fixtures/reference_text.zig");
const token_fixture = @import("test_fixtures/reference_tokens.zig");

pub const no_claim = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":[{\"literal\":{\"value\":\"This chunk contains no feature claims.\"}}]},\"token_classifications\":[]}";

pub fn reply(allocator: std.mem.Allocator, chunk: evidence.Chunk, text: []const u8) ![]const u8 {
    const claim = .{
        .content = .{ .kind = "business", .text = extraction.text.BusinessText{ .segments = &.{.{ .literal = .{ .value = text } }} } },
        .citations = [_]evidence.CitationProposal{.{ .source_id = chunk.source_id, .block_id = chunk.block_id, .location = chunk.span, .verbatim = null }},
    };
    return std.json.Stringify.valueAlloc(allocator, .{ .kind = "claims", .claims = &.{claim}, .token_classifications = [0]struct {}{} }, .{});
}
pub fn passiveReply(allocator: std.mem.Allocator, chunk: evidence.Chunk, ordinal: u32) ![]const u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .kind = "claims", .claims = &.{.{
        .content = .{ .kind = "business", .text = extraction.text.BusinessText{ .segments = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = ordinal } } }} } },
        .citations = [_]evidence.CitationProposal{.{ .source_id = chunk.source_id, .block_id = chunk.block_id, .location = chunk.span, .verbatim = null }},
    }}, .token_classifications = [0]struct {}{} }, .{});
}
fn raw(inputs: evidence.Inputs, index: usize, bytes: []const u8) extraction.RawResult {
    return .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[index].id }, .result = .{ .response = bytes } };
}
fn finish(allocator: std.mem.Allocator, inputs: evidence.Inputs, results: []const extraction.RawResult) !extraction.Accounted {
    const parsed = try parse.execute(allocator, .{ .entries = results });
    const tokens = try token_fixture.assignments(allocator, inputs, try text_fixture.check(allocator, inputs, parsed));
    const valid = try validate.execute(allocator, inputs, try token_fixture.build.execute(allocator, tokens));
    return account.execute(inputs, tokens, try build.execute(allocator, try assign.execute(allocator, valid)));
}

test "Hello World and unrelated source claims receive only engine assigned IDs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const hello = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/evaluation/wf-001-hello-world/reference/stories.md", allocator, .limited(@import("domain/reference_ingestion.zig").limits.source_file_bytes));
    for ([_][]const u8{ hello, "A librarian can renew a loan.\r\n" }) |bytes| {
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(allocator, &ids, try ingest(allocator, "requirements.md", bytes));
        const results = try allocator.alloc(extraction.RawResult, inputs.chunks.entries.len);
        const available = try token_fixture.candidates(allocator, inputs);
        for (results, inputs.chunks.entries, 0..) |*result, chunk, index| result.* = raw(inputs, index, try token_fixture.wire(allocator, try reply(allocator, chunk, "An unreviewed business claim."), try token_fixture.classifications(allocator, available, chunk)));
        const completed = try finish(allocator, inputs, results);
        try std.testing.expectEqual(.complete, completed.outcome);
        try std.testing.expectEqual(results.len + available.entries.len, completed.ledger.claims.len);
        for (completed.ledger.claims, 1..) |claim, ordinal| {
            try std.testing.expectEqual(ordinal, claim.id.ordinal);
            try std.testing.expectEqual(ordinal, claim.citation_ids[0].ordinal);
        }
        const again = try finish(allocator, inputs, results);
        try std.testing.expectEqualDeep(completed, again);
    }
}

test "closed result parser rejects unknown fields forged IDs malformed variants and classifications" {
    for ([_][]const u8{
        "{}",                                                                                                                                             "[]",                                                                                              "null",                                                                                                           "```json\n{}\n```",                                                                   no_claim ++ "{}",
        "{\"kind\":\"blocked\"}",                                                                                                                         "{\"kind\":\"no_feature_claim\",\"reason\":\"none\",\"token_classifications\":[],\"claim_id\":1}", "{\"kind\":\"no_feature_claim\",\"kind\":\"no_feature_claim\",\"reason\":\"none\",\"token_classifications\":[]}", "{\"kind\":\"no_feature_claim\",\"reason\":\"none\",\"token_classifications\":[{}]}", "{\"kind\":\"no_feature_claim\",\"reason\":\"none\"}",
        "{\"kind\":\"claims\",\"claims\":[{\"content\":{\"kind\":\"business\",\"text\":\"x\"},\"citations\":[],\"id\":1}],\"token_classifications\":[]}", "{\"kind\":\"claims\",\"claims\":[],\"reason\":\"none\",\"token_classifications\":[]}",
    }) |bytes| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidReferenceExtraction, parse.execute(arena.allocator(), .{ .entries = &.{.{ .scope = .{ .state_id = .{ .bytes = "s" }, .chunk_id = .{ .bytes = "c" } }, .result = .{ .response = bytes } }} }));
    }
}

test "every chunk needs exactly one result and engine order owns assignments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(allocator, &ids, try ingest(allocator, "two.md", "line\n" ** 70));
    try std.testing.expectEqual(@as(usize, 2), inputs.chunks.entries.len);
    const first = raw(inputs, 0, try reply(allocator, inputs.chunks.entries[0], "First"));
    const second = raw(inputs, 1, try reply(allocator, inputs.chunks.entries[1], "Second"));
    const ordered = try finish(allocator, inputs, &.{ first, second });
    const reversed = try finish(allocator, inputs, &.{ second, first });
    try std.testing.expectEqualDeep(ordered, reversed);
    for ([_][]const extraction.RawResult{ &.{}, &.{first}, &.{ first, first }, &.{ first, second, second } }) |results| try std.testing.expectError(error.InvalidReferenceExtraction, finish(allocator, inputs, results));
    var foreign = second;
    foreign.scope.state_id.bytes = "another-state";
    try std.testing.expectError(error.InvalidSourceCitation, finish(allocator, inputs, &.{ first, foreign }));
    foreign = second;
    foreign.scope.chunk_id.bytes = "chunk-999";
    try std.testing.expectError(error.InvalidSourceCitation, finish(allocator, inputs, &.{ first, foreign }));
    const empty = raw(inputs, 1, no_claim);
    try std.testing.expectEqual(.complete, (try finish(allocator, inputs, &.{ first, empty })).outcome);
    var blocked = second;
    blocked.result = .{ .blocked = .extraction_failed };
    const incomplete = try finish(allocator, inputs, &.{ first, blocked });
    try std.testing.expectEqual(.blocked, incomplete.outcome);
    try std.testing.expectEqual(@as(usize, 1), incomplete.ledger.claims.len);
}

test "positive no claim evidence and valid citations are mandatory" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(allocator, &ids, try ingest(allocator, "unicode.md", "Café\r\n"));
    try std.testing.expectError(error.InvalidReferenceExtraction, finish(allocator, inputs, &.{raw(inputs, 0, "{\"kind\":\"claims\",\"claims\":[],\"token_classifications\":[]}")}));
    const empty_reason = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":[{\"literal\":{\"value\":\"  \"}}]},\"token_classifications\":[]}";
    try std.testing.expectError(error.InvalidTypedText, finish(allocator, inputs, &.{raw(inputs, 0, empty_reason)}));
    const parsed = try parse.execute(allocator, .{ .entries = &.{raw(inputs, 0, try reply(allocator, inputs.chunks.entries[0], "claim"))} });
    var entry = parsed.entries[0];
    var claim = entry.outcome.claims[0];
    var citation = claim.citations[0];
    citation.verbatim = "Cafe\r\n";
    claim.citations = &.{citation};
    entry.outcome = .{ .claims = &.{claim} };
    try std.testing.expectError(error.InvalidSourceCitation, validate.execute(allocator, inputs, try token_fixture.prepare(allocator, inputs, try text_fixture.check(allocator, inputs, .{ .entries = &.{entry} }))));
    claim.citations = &.{};
    entry.outcome = .{ .claims = &.{claim} };
    try std.testing.expectError(error.InvalidSourceCitation, validate.execute(allocator, inputs, try token_fixture.prepare(allocator, inputs, try text_fixture.check(allocator, inputs, .{ .entries = &.{entry} }))));
    claim.content.business = .{ .segments = &.{.{ .literal = .{ .value = " \t" } }} };
    entry.outcome = .{ .claims = &.{claim} };
    try std.testing.expectError(error.InvalidTypedText, text_fixture.check(allocator, inputs, .{ .entries = &.{entry} }));
}

test "final accounting rejects omitted orphan duplicate and foreign identity joins" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(allocator, &ids, try ingest(allocator, "source.md", "claim\n"));
    const completed = try finish(allocator, inputs, &.{raw(inputs, 0, try reply(allocator, inputs.chunks.entries[0], "Claim"))});
    const tokens = try token_fixture.assignments(allocator, inputs, try text_fixture.check(allocator, inputs, try parse.execute(allocator, .{ .entries = &.{raw(inputs, 0, try reply(allocator, inputs.chunks.entries[0], "Claim"))} })));
    for (0..7) |case| {
        var ledger = completed.ledger;
        var claim = ledger.claims[0];
        var citation = ledger.citations[0];
        switch (case) {
            0 => ledger.chunks = &.{},
            1 => ledger.claims = &.{},
            2 => ledger.citations = &.{},
            3 => ledger.next_claim_ordinal = 1,
            4 => {
                claim.id.ordinal = 2;
                ledger.claims = &.{claim};
            },
            5 => {
                citation.value.block_id.ordinal = 999;
                ledger.citations = &.{citation};
            },
            6 => ledger.claims = &.{ claim, claim },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceExtraction, account.execute(inputs, tokens, ledger));
    }
}

test "allocation failures abandon the extraction candidate" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const temporary = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(temporary, &ids, try ingest(temporary, "source.md", "claim\n"));
    _ = try finish(temporary, inputs, &.{raw(inputs, 0, try reply(temporary, inputs.chunks.entries[0], "Claim"))});
}

test "sealed extraction values retain only owned candidate data after inputs are released" {
    try ownershipCase(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, ownershipCase, .{});
}
fn ownershipCase(allocator: std.mem.Allocator) !void {
    const owned = @import("domain/reference_extraction_value.zig");
    const bindings = @import("application/reference_extraction_workflow.zig");
    const values = @import("application/pipeline_values.zig");
    var source_arena: std.heap.ArenaAllocator = .init(allocator);
    defer source_arena.deinit();
    const source_allocator = source_arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(source_allocator, &ids, try ingest(source_allocator, "owned.md", "A `quoted` requirement.\r\n"));
    const unquoted = try reply(source_allocator, inputs.chunks.entries[0], "Retained claim");
    const quoted = try std.mem.replaceOwned(u8, source_allocator, unquoted, "\"verbatim\":null", "\"verbatim\":\"A `quoted` requirement.\\r\\n\"");
    const bytes = try token_fixture.wire(source_allocator, quoted, try token_fixture.classifications(source_allocator, try token_fixture.candidates(source_allocator, inputs), inputs.chunks.entries[0]));
    const captured = try owned.capture(allocator, .{ .entries = &.{raw(inputs, 0, bytes)} });
    defer owned.destroy(captured);
    var current = try owned.create(allocator, null);
    defer owned.destroy(current);
    current.payload = .{ .parsed = try parse.execute(current.arena.allocator(), owned.view(captured).payload().raw) };
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .text_validated = try text_fixture.check(next.arena.allocator(), inputs, current.payload.parsed) };
        owned.destroy(current);
        current = next;
    }
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .token_classified = try token_fixture.classify.execute(next.arena.allocator(), inputs, try token_fixture.candidates(source_allocator, inputs), current.payload.text_validated) };
        owned.destroy(current);
        current = next;
    }
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .tokens_assigned = try token_fixture.assign.execute(next.arena.allocator(), current.payload.token_classified) };
        owned.destroy(current);
        current = next;
    }
    const tokens = current.payload.tokens_assigned;
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .prepared = try token_fixture.build.execute(next.arena.allocator(), current.payload.tokens_assigned) };
        owned.destroy(current);
        current = next;
    }
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .validated = try validate.execute(next.arena.allocator(), inputs, current.payload.prepared) };
        owned.destroy(current);
        current = next;
    }
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .assigned = try assign.execute(next.arena.allocator(), current.payload.validated) };
        owned.destroy(current);
        current = next;
    }
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .ledger = try build.execute(next.arena.allocator(), current.payload.assigned) };
        owned.destroy(current);
        current = next;
    }
    const terminal = try owned.create(allocator, owned.view(current));
    terminal.payload = .{ .accounted = account.execute(inputs, tokens, current.payload.ledger) catch |err| {
        owned.destroy(terminal);
        return err;
    } };
    const candidate = bindings.publish(allocator, bindings.accounted_schema, terminal, .ok) catch {
        owned.destroy(terminal);
        // The narrow workflow operation maps allocation failure to execution
        // failure. This test injects only allocation failures at that boundary.
        return error.OutOfMemory;
    };
    const value = candidate.delta.data_writes[@intFromEnum(bindings.accounted_schema.key)].?;
    defer values.destroy(value);
    _ = source_arena.reset(.free_all);
    var view: @import("domain/pipeline_data.zig").View = .{};
    view.slots[@intFromEnum(bindings.accounted_schema.key)] = value;
    const retained = try bindings.read(&view, bindings.accounted_schema, .accounted);
    try std.testing.expectEqualStrings("Retained claim", retained.payload().accounted.ledger.claims[0].content.model.business.value.segments[0].literal.value);
    try std.testing.expectEqualStrings("chunk-1", retained.payload().accounted.ledger.claims[0].chunk_id.bytes);
    try std.testing.expectEqualStrings("A `quoted` requirement.\r\n", retained.payload().accounted.ledger.citations[0].value.verbatim.?);
    try std.testing.expectEqualStrings("quoted", retained.payload().accounted.ledger.claims[1].content.preserved_token.value.raw_value.bytes);
}

test "an empty captured source does not acquire invented extraction results" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(arena.allocator(), &ids, try ingest(arena.allocator(), "empty.md", ""));
    const result = try finish(arena.allocator(), inputs, &.{});
    try std.testing.expectEqual(.complete, result.outcome);
    try std.testing.expectEqual(@as(usize, 0), result.ledger.chunks.len);
    try std.testing.expectEqual(@as(usize, 0), result.ledger.claims.len);
}
