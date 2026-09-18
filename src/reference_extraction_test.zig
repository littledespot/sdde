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

pub const no_claim = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":[{\"kind\":\"literal\",\"value\":\"This chunk contains no feature claims.\"}]},\"token_classifications\":[]}";

pub fn reply(allocator: std.mem.Allocator, chunk: evidence.Chunk, text: []const u8) ![]const u8 {
    const claim = .{
        .content = extraction.ProposalContent{ .business = .{ .segments = &.{.{ .literal = .{ .value = text } }} } },
        .citations = [_]@import("domain/source_selections.zig").Selection{wholeChunk(chunk)},
    };
    return @import("domain/model_candidate_json.zig").encode(@import("domain/reference_extraction_parser.zig").Response, allocator, .{ .claims = .{ .claims = &.{.{ .content = claim.content, .citations = &claim.citations }}, .token_classifications = &.{} } });
}
pub fn passiveReply(allocator: std.mem.Allocator, chunk: evidence.Chunk, ordinal: u32) ![]const u8 {
    return @import("domain/model_candidate_json.zig").encode(@import("domain/reference_extraction_parser.zig").Response, allocator, .{ .claims = .{ .claims = &.{.{
        .content = .{ .business = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = ordinal } } }} } },
        .citations = &.{wholeChunk(chunk)},
    }}, .token_classifications = &.{} } });
}
fn raw(inputs: evidence.Inputs, index: usize, bytes: []const u8) extraction.RawResult {
    return .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[index].id }, .result = .{ .response = bytes } };
}
pub fn finish(allocator: std.mem.Allocator, inputs: evidence.Inputs, results: []const extraction.RawResult) !extraction.Accounted {
    const parsed = try parse.execute(allocator, .{ .entries = results });
    return finishText(allocator, inputs, try text_fixture.check(allocator, inputs, parsed));
}
pub fn finishText(allocator: std.mem.Allocator, inputs: evidence.Inputs, candidate: extraction.TextValidated) !extraction.Accounted {
    const checked = try @import("domain/reference_selection_validation.zig").validate(allocator, inputs, try token_fixture.candidates(allocator, inputs), candidate);
    if (checked != .valid) return error.InvalidSourceCitation;
    const tokens = try token_fixture.assign.execute(allocator, checked.valid);
    const valid = try validate.execute(allocator, inputs, try token_fixture.build.execute(allocator, tokens));
    return account.execute(inputs, tokens, try build.execute(allocator, try assign.execute(allocator, switch (valid) {
        .valid => |value| value,
        .invalid => return error.InvalidSourceCitation,
    })));
}

test "Hello World and unrelated source claims receive only engine assigned IDs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const hello = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/e2e/wf-001-hello-world/reference/stories.md", allocator, .limited(@import("domain/reference_ingestion.zig").limits.source_file_bytes));
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
    const empty_reason = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":[{\"kind\":\"literal\",\"value\":\"  \"}]},\"token_classifications\":[]}";
    try std.testing.expectError(error.InvalidTypedText, finish(allocator, inputs, &.{raw(inputs, 0, empty_reason)}));
    const parsed = try parse.execute(allocator, .{ .entries = &.{raw(inputs, 0, try reply(allocator, inputs.chunks.entries[0], "claim"))} });
    var entry = parsed.entries[0];
    var claim = entry.outcome.claims[0];
    var citation = claim.citations[0];
    citation.last.ordinal = 999;
    claim.citations = &.{citation};
    entry.outcome = .{ .claims = &.{claim} };
    try std.testing.expectEqual(.unknown_selection, (try validate.execute(allocator, inputs, try token_fixture.prepare(allocator, inputs, try text_fixture.check(allocator, inputs, .{ .entries = &.{entry} })))).invalid.issue.reason);
    claim.citations = &.{};
    entry.outcome = .{ .claims = &.{claim} };
    try std.testing.expectEqual(.missing_selection, (try validate.execute(allocator, inputs, try token_fixture.prepare(allocator, inputs, try text_fixture.check(allocator, inputs, .{ .entries = &.{entry} })))).invalid.issue.reason);
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
    const owned = @import("domain/reference_candidate_value.zig");
    const bindings = @import("application/reference_extraction_workflow.zig");
    const values = @import("application/pipeline_values.zig");
    var source_arena: std.heap.ArenaAllocator = .init(allocator);
    defer source_arena.deinit();
    const source_allocator = source_arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(source_allocator, &ids, try ingest(source_allocator, "owned.md", "A `quoted` requirement.\r\n"));
    const quoted = try reply(source_allocator, inputs.chunks.entries[0], "Retained claim");
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
        next.payload = .{ .selections_validated = try token_fixture.classify.execute(next.arena.allocator(), inputs, try token_fixture.candidates(source_allocator, inputs), current.payload.text_validated) };
        owned.destroy(current);
        current = next;
    }
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .tokens_assigned = try token_fixture.assign.execute(next.arena.allocator(), current.payload.selections_validated) };
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
        next.payload = .{ .validated = (try validate.execute(next.arena.allocator(), inputs, current.payload.prepared)).valid };
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

/// Test response selects the complete supplied chunk without returning its bytes.
pub fn wholeChunk(chunk: evidence.Chunk) @import("domain/source_selections.zig").Selection {
    return .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = chunk.span.end.line - chunk.span.start.line + @as(u32, if (chunk.span.end.column != 1) 1 else 0) } };
}

test "citation repair changes only the selected reference and retains exact diagnostic origins" {
    const repair = @import("domain/reference_extraction_repair.zig");
    const selections = @import("domain/source_selections.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original_origin: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const repair_origin: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 2 } };
    for ([_][]const u8{ "Display a greeting.\n", "Renew a library loan.\r\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", try std.fmt.allocPrint(a, "{s}" ++ "Unchanged context.\n" ** 70, .{source})));
        const first = inputs.chunks.entries[0];
        const second = inputs.chunks.entries[1];
        var original = raw(inputs, 0, try reply(a, first, "Preserve the requirement's meaning."));
        original.origin = original_origin;
        const parsed = try parse.execute(a, .{ .entries = &.{ original, raw(inputs, 1, try reply(a, second, "An unrelated claim.")) } });
        const entries = try a.dupe(extraction.ParsedResult, parsed.entries);
        var claim = entries[0].outcome.claims[0];
        const good: selections.Selection = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } };
        const bad: selections.Selection = .{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } };
        claim.citations = &.{ good, bad, bad };
        entries[0].outcome = .{ .claims = &.{claim} };
        const candidate = try text_fixture.check(a, inputs, .{ .entries = entries });
        const available = try token_fixture.candidates(a, inputs);
        const rejection = (try @import("domain/reference_selection_validation.zig").validate(a, inputs, available, candidate)).source_selections;
        const authorization = try repair.authorize(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, .{ .source_selections = rejection });
        try std.testing.expectEqual(@as(usize, 1), authorization.target.citation.citation_index);
        for (0..4) |scenario| {
            var foreign_rejection = rejection;
            switch (scenario) {
                0 => foreign_rejection.scope.state_id.bytes = "foreign-state",
                1 => foreign_rejection.revision += 1,
                2 => foreign_rejection.origin = repair_origin,
                3 => foreign_rejection.observed = &.{good},
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, .{ .source_selections = foreign_rejection }));
        }
        const before = (try validate.execute(a, inputs, try token_fixture.prepare(a, inputs, candidate))).invalid;
        try std.testing.expectEqualDeep(original_origin, before.origin.?);
        const context = try text_fixture.prepare(a, inputs);
        defer context.deinit();
        const packet = try repair.packet(std.testing.allocator, inputs, context.registry, available, candidate, authorization);
        defer packets.release(packet);
        try std.testing.expectEqualStrings("source_selection_replacement", packet.resultDefinition().?.bytes);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Preserve the requirement's meaning.") != null);
        const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, .{ .citation = good });
        const replacement = try repair.parse(a, authorization, packet, wire);
        const merged = try repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, authorization, replacement, repair_origin);
        try std.testing.expectEqualDeep(candidate.entries[0].outcome.claims[0].content, merged.entries[0].outcome.claims[0].content);
        try std.testing.expectEqualDeep(candidate.entries[0].token_classifications, merged.entries[0].token_classifications);
        try std.testing.expectEqualDeep(candidate.entries[1], merged.entries[1]);
        try std.testing.expectEqualDeep(good, merged.entries[0].outcome.claims[0].citations[0]);
        try std.testing.expectEqualDeep(bad, candidate.entries[0].outcome.claims[0].citations[1]);
        const remaining = (try validate.execute(a, inputs, try token_fixture.prepare(a, inputs, merged))).invalid;
        try std.testing.expectEqual(@as(usize, 2), remaining.issue.index);
        try std.testing.expectEqualDeep(original_origin, remaining.origin.?);
        try std.testing.expectEqualDeep(repair_origin, merged.entries[0].outcome.claims[0].citation_origins[1].?);
        const retry = try repair.authorize(a, .{ .inputs = inputs, .candidates = available, .candidate = merged }, .{ .source_selections = remaining });
        const completed = try repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = merged }, retry, .{ .citation = good }, repair_origin);
        try std.testing.expect((try validate.execute(a, inputs, try token_fixture.prepare(a, inputs, completed))) == .valid);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = merged }, authorization, replacement, repair_origin));
        var altered = candidate;
        altered.entries = merged.entries;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = altered }, authorization, replacement, repair_origin));
        var foreign = authorization;
        foreign.owner.reference_chunk.reference_state_id.bytes = "different-source-state";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, foreign, replacement, repair_origin));
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, "{\"first\":{\"ordinal\":1},\"last\":{\"ordinal\":1},\"verbatim\":\"invented\"}"));
        const invalid_repair = try repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, authorization, .{ .citation = bad }, repair_origin);
        const rejected = (try validate.execute(a, inputs, try token_fixture.prepare(a, inputs, invalid_repair))).invalid;
        try std.testing.expectEqualDeep(repair_origin, rejected.origin.?);
    }
}

test "missing citation repair is restricted to the empty collection and materializes captured bytes" {
    const repair = @import("domain/reference_extraction_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: fixture.IdSource = .{};
    const bytes = "Hello, World!\n";
    const inputs = try fixture.prepare(a, &ids, try ingest(a, "source.md", bytes));
    const parsed = try parse.execute(a, .{ .entries = &.{raw(inputs, 0, try reply(a, inputs.chunks.entries[0], "Display the greeting."))} });
    var entry = parsed.entries[0];
    var claim = entry.outcome.claims[0];
    claim.citations = &.{};
    entry.outcome = .{ .claims = &.{claim} };
    const candidate = try text_fixture.check(a, inputs, .{ .entries = &.{entry} });
    const available = try token_fixture.candidates(a, inputs);
    const rejection = (try @import("domain/reference_selection_validation.zig").validate(a, inputs, available, candidate)).source_selections;
    const authorization = try repair.authorize(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, .{ .source_selections = rejection });
    try std.testing.expect(authorization.target == .missing_citations);
    const updated = try repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, authorization, .{ .citations = .{ .citations = &.{wholeChunk(inputs.chunks.entries[0])} } }, null);
    const accepted = (try validate.execute(a, inputs, try token_fixture.prepare(a, inputs, updated))).valid;
    try std.testing.expectEqualStrings(bytes, accepted.entries[0].outcome.claims[0].citations[0].verbatim.?);
    try std.testing.expectEqualDeep(candidate.entries[0].outcome.claims[0].content, updated.entries[0].outcome.claims[0].content);
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, .{ .inputs = inputs, .candidates = available, .candidate = candidate }, authorization, .{ .classifications = .{ .token_classifications = &.{} } }, null));
}

test "text repair preserves siblings and exposes remaining classification defects across content kinds" {
    const repair = @import("domain/reference_extraction_text_repair.zig");
    const contexts = @import("domain/reference_extraction_context.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const first: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const correction: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    inline for (.{ extraction.Kind.business, extraction.Kind.technical, extraction.Kind.scope_guard }) |kind| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", "Display `Loan renewed!`.\n"));
        const context = try text_fixture.prepare(a, inputs);
        defer context.deinit();
        const available = try token_fixture.candidates(a, inputs);
        const bad: extraction.ProposalContent = @unionInit(extraction.ProposalContent, @tagName(kind), if (kind == .business or kind == .scope_guard)
            extraction.text.BusinessText{ .segments = &.{.{ .literal = .{ .value = "requirements.md" } }} }
        else
            extraction.text.ReferenceSemanticText{ .nodes = &.{.{ .literal = .{ .value = "requirements.md" } }} });
        const good: extraction.ProposalContent = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Retain this independent claim." } }} } };
        const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id };
        var unknown = available.entries[0].id;
        unknown.ordinal += 1;
        const candidate: extraction.Parsed = .{ .entries = &.{.{ .scope = scope, .origin = first, .token_classifications = &.{.{ .irrelevant = unknown }}, .outcome = .{ .claims = &.{
            .{ .content = good, .citations = &.{wholeChunk(inputs.chunks.entries[0])} },
            .{ .content = bad, .citations = &.{wholeChunk(inputs.chunks.entries[0])} },
        } } }} };
        const rejection = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, candidate)).invalid;
        try std.testing.expectEqual(.unbound_path, rejection.issue.reason);
        try std.testing.expectEqual(@as(usize, 1), rejection.target.claim);
        try std.testing.expectEqualDeep(first, rejection.origin.?);
        const facts = try contexts.textFacts(inputs, context.registry, text_fixture.safety.value(context.owner), candidate);
        const authorization = try repair.authorize(a, facts, rejection);
        const passive: extraction.text.PassiveReference = .{ .passive_literal_id = context.registry.records[0].id };
        const replacement: repair.Replacement = if (kind == .business or kind == .scope_guard)
            .{ .business = .{ .segments = &.{.{ .passive = passive }} } }
        else
            .{ .reference = .{ .nodes = &.{.{ .passive = passive }} } };
        const packet = try repair.packet(std.testing.allocator, facts, context.registry, text_fixture.safety.value(context.owner), available, authorization);
        defer @import("domain/model_input_packet.zig").release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const rule = body.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expectEqualStrings(rejection.issue.description(), rule.get("requirement").?.string);
        const projected = try @import("domain/model_candidate_json.zig").decode(extraction.text.Issue, a, try std.json.Stringify.valueAlloc(a, rule.get("issue").?, .{}));
        try std.testing.expectEqualDeep(rejection.issue, projected);
        try std.testing.expectEqualStrings("requirements.md", projected.path_match.?.lexeme);
        const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
        const merged = try repair.merge(a, facts, authorization, try repair.parse(a, authorization, packet, wire), correction);
        try std.testing.expectEqualDeep(candidate.entries[0].outcome.claims[0], merged.entries[0].outcome.claims[0]);
        try std.testing.expectEqualDeep(candidate.entries[0].outcome.claims[1].citations, merged.entries[0].outcome.claims[1].citations);
        try std.testing.expectEqualDeep(candidate.entries[0].token_classifications, merged.entries[0].token_classifications);
        const checked = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, merged)).valid;
        try std.testing.expectEqualDeep(merged.last_repair.?, checked.last_repair.?);
        try std.testing.expect(checked.last_repair.?.changed);
        try std.testing.expectEqualDeep(correction, checked.entries[0].outcome.claims[1].origin.?);
        try std.testing.expectEqualDeep(first, checked.entries[0].outcome.claims[0].origin.?);
        const remaining = (try @import("domain/reference_selection_validation.zig").validate(a, inputs, available, checked)).token_classifications;
        try std.testing.expectEqualDeep(first, remaining.origin.?);
        try std.testing.expectEqualDeep(&[_]extraction.tokens.CandidateId{unknown}, remaining.issues.unknown);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try contexts.textFacts(inputs, context.registry, text_fixture.safety.value(context.owner), merged), authorization, replacement, correction));
        var changed_registry = context.registry;
        const names = try a.dupe(@import("domain/path_token_grammar.zig").ReferenceName, changed_registry.grammar.reference_names);
        names[0].basename = "changed.md";
        changed_registry.grammar.reference_names = names;
        const changed_facts = try contexts.textFacts(inputs, changed_registry, text_fixture.safety.value(context.owner), candidate);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, changed_facts, rejection));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, facts, changed_registry, text_fixture.safety.value(context.owner), available, authorization));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, changed_facts, authorization, replacement, correction));
        const foreign_policy = try text_fixture.prepare(a, inputs);
        defer foreign_policy.deinit();
        try std.testing.expectError(error.StaleNamingPolicy, contexts.textFacts(inputs, context.registry, text_fixture.safety.value(foreign_policy.owner), candidate));
        var stale = facts;
        stale.text.policy_ids = &.{"different-policy"};
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, stale, rejection));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, stale, authorization, replacement, correction));
        const again = try repair.merge(a, facts, authorization, authorization.operation.replace, correction);
        try std.testing.expect(!again.last_repair.?.changed);
        const repeated = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, again)).invalid;
        try std.testing.expectEqual(.unbound_path, repeated.issue.reason);
        try std.testing.expectEqualDeep(correction, repeated.origin.?);
        var registry = context.registry;
        registry.grammar.reference_state_id.bytes = "stale-state";
        try std.testing.expectError(error.InvalidPathTokenGrammar, text_fixture.validate_text.execute(a, registry, text_fixture.safety.value(context.owner), inputs, candidate));
    }
}

test "no-feature-claim text repair retains native failures and immutable classification decisions" {
    const repair = @import("domain/reference_extraction_text_repair.zig");
    const contexts = @import("domain/reference_extraction_context.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(a, &ids, try ingest(a, "guidance.md", "Background context only."));
    const context = try text_fixture.prepare(a, inputs);
    defer context.deinit();
    const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id };
    for ([_]extraction.text.ReferenceSemanticText{
        .{ .nodes = &.{.{ .literal = .{ .value = "https://example.invalid/context" } }} },
        .{ .nodes = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 999 } } }} },
    }, 0..) |reason, scenario| {
        const candidate: extraction.Parsed = .{ .entries = &.{.{ .scope = scope, .token_classifications = &.{}, .outcome = .{ .no_feature_claim = reason } }} };
        const rejection = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, candidate)).invalid;
        try std.testing.expectEqual(@as(@TypeOf(rejection.issue.reason), if (scenario == 0) .unbound_path else .unknown_passive), rejection.issue.reason);
        try std.testing.expect(rejection.target == .reason);
        const facts = try contexts.textFacts(inputs, context.registry, text_fixture.safety.value(context.owner), candidate);
        const authorization = try repair.authorize(a, facts, rejection);
        const replacement: repair.Replacement = .{ .reference = .{ .nodes = &.{.{ .literal = .{ .value = "This source supplies background context." } }} } };
        const fixed = try repair.merge(a, facts, authorization, replacement, null);
        const valid = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, fixed)).valid;
        try std.testing.expect(valid.entries[0].outcome == .no_feature_claim);
        try std.testing.expectEqualDeep(candidate.entries[0].token_classifications, fixed.entries[0].token_classifications);
        const retained = try (@import("domain/candidate_validation_diagnostic.zig").Diagnostic{ .extraction_text = rejection }).copy(a);
        try std.testing.expectEqualDeep(rejection, retained.extraction_text);
    }
}

test "constructed claim rejection retains the original source selection repair authority" {
    const repair = @import("domain/reference_extraction_repair.zig");
    const retention = @import("actions/reference/retain_reference_claim_rejection.zig").Action{};
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(a, &ids, try ingest(a, "renewal.md", "The borrower sees the renewal receipt."));
    const context = try text_fixture.prepare(a, inputs);
    defer context.deinit();
    const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id };
    const available = try token_fixture.candidates(a, inputs);
    const parsed: extraction.Parsed = .{ .entries = &.{.{ .scope = scope, .token_classifications = &.{}, .outcome = .{ .claims = &.{.{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A receipt is visible." } }} } }, .citations = &.{.{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } }} }} } }} };
    const typed = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, parsed)).valid;
    const original = (try @import("domain/reference_selection_validation.zig").validate(a, inputs, available, typed)).source_selections;
    const prepared: extraction.Prepared = .{ .dependencies = original.dependencies, .revision = typed.revision, .entries = &.{.{ .scope = scope, .outcome = .{ .claims = &.{.{ .model = typed.entries[0].outcome.claims[0] }} } }} };
    const rejected = (try validate.execute(a, inputs, prepared)).invalid;
    const retained = retention.execute(rejected);
    try std.testing.expectEqualDeep(original, retained);
    const facts: repair.Facts = .{ .inputs = inputs, .candidates = available, .candidate = typed };
    const authorization = try repair.authorize(a, facts, .{ .source_selections = retained });
    const fixed = try repair.merge(a, facts, authorization, .{ .citation = wholeChunk(inputs.chunks.entries[0]) }, null);
    try std.testing.expect((try @import("domain/reference_selection_validation.zig").validate(a, inputs, available, fixed)) == .valid);
    var corrupt = prepared;
    corrupt.entries = &.{};
    try std.testing.expectError(error.InvalidReferenceExtraction, validate.execute(a, inputs, corrupt));
}

test "classification repair requests retain the frozen outcome and permitted decisions" {
    const repair = @import("domain/reference_extraction_repair.zig");
    const classifications = @import("domain/token_classification_validation.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(a, &ids, try ingest(a, "receipt.md", "Display `Receipt issued!`."));
    const context = try text_fixture.prepare(a, inputs);
    defer context.deinit();
    const available = try token_fixture.candidates(a, inputs);
    try std.testing.expect(available.entries.len > 0);
    for ([_]bool{ false, true }) |has_claims| {
        const wire = if (has_claims) try reply(a, inputs.chunks.entries[0], "The receipt is visible.") else no_claim;
        const candidate = try text_fixture.check(a, inputs, try parse.execute(a, .{ .entries = &.{raw(inputs, 0, wire)} }));
        const rejected = (try classifications.validate(a, inputs, available, candidate)).invalid;
        const facts: repair.Facts = .{ .inputs = inputs, .candidates = available, .candidate = candidate };
        const auth = try repair.authorize(a, facts, .{ .token_classifications = rejected });
        const packet = try repair.packet(a, inputs, context.registry, available, candidate, auth);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const choices = body.value.object.get("repair").?.object.get("rule").?.object.get("choices").?.object;
        try std.testing.expectEqualStrings(if (has_claims) "claims" else "no_feature_claim", choices.get("outcome").?.string);
        const decisions = choices.get("decisions").?.array.items;
        try std.testing.expectEqual(@as(usize, if (has_claims) 2 else 1), decisions.len);
        try std.testing.expectEqualStrings("irrelevant", decisions[decisions.len - 1].string);
        const replacement = try a.alloc(extraction.tokens.Classification, available.entries.len);
        for (available.entries, replacement) |item, *value| value.* = .{ .irrelevant = item.id };
        const merged = try repair.merge(a, facts, auth, .{ .classifications = .{ .token_classifications = replacement } }, null);
        try std.testing.expectEqualDeep(candidate.entries[0].outcome, merged.entries[0].outcome);
        _ = (try classifications.validate(a, inputs, available, merged)).valid;
        if (!has_claims) {
            const forbidden = try token_fixture.classifications(a, available, inputs.chunks.entries[0]);
            const invalid = try repair.merge(a, facts, auth, .{ .classifications = .{ .token_classifications = forbidden } }, null);
            try std.testing.expect((try classifications.validate(a, inputs, available, invalid)).invalid.issues.forbidden.len > 0);
        }
    }
}
