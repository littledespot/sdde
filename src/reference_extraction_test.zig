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

test "prepared reference text retains passive literal and source authority on reuse" {
    for ([_][2][]const u8{
        .{ "requirements.md", "Display the greeting. Consult requirements.md.\n" },
        .{ "policy.md", "Renew eligible loans. Consult policy.md.\n" },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, example[0], example[1]));
        const prepared = try text_fixture.prepare(a, inputs);
        defer prepared.deinit();
        try std.testing.expect(prepared.registry.records.len > 0);
        const literal = prepared.registry.records[0].id;
        const candidate = try parse.execute(a, .{ .entries = &.{raw(inputs, 0, try passiveReply(a, literal.ordinal))} });
        for (0..2) |_| {
            const checked = try prepared.check(a, inputs, candidate);
            try std.testing.expectEqualDeep(literal, checked.entries[0].outcome.no_feature_claim.value.nodes[1].passive.passive_literal_id);
        }
        const unknown = try parse.execute(a, .{ .entries = &.{raw(inputs, 0, try passiveReply(a, 999))} });
        try std.testing.expectError(error.InvalidPassiveLiteral, prepared.check(a, inputs, unknown));
        var foreign = inputs;
        foreign.corpus.state_id.bytes = "foreign-reference-state";
        try std.testing.expectError(error.InvalidPathTokenGrammar, prepared.check(a, foreign, candidate));
    }
}

test "native extraction composition defects cannot authorize unit repair or change candidates" {
    const repair = @import("domain/reference_extraction_text_repair.zig");
    const contexts = @import("domain/reference_extraction_context.zig");
    const atomic = @import("domain/atomic_repair.zig");
    for ([_][]const u8{ "Display the current UTC time. Consult requirements.md.\n", "Renew eligible loans. Consult requirements.md.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", source));
        const context = try text_fixture.prepare(a, inputs);
        defer context.deinit();
        const passive: extraction.text.PassiveReference = .{ .passive_literal_id = context.registry.records[0].id };
        const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id };
        const candidate: extraction.Parsed = .{ .entries = &.{.{ .scope = scope, .token_classifications = &.{}, .outcome = .{ .no_feature_claim = .{ .nodes = &.{.{ .passive = passive }} } } }} };
        const rejection = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, candidate)).invalid;
        try std.testing.expectEqual(.reference_only, rejection.issue.reason);
        const facts = try contexts.textFacts(inputs, context.registry, text_fixture.safety.value(context.owner), candidate);
        const before = try atomic.snapshot(extraction.Parsed, a, candidate);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, facts, rejection));
        try std.testing.expectEqualDeep(before, try atomic.snapshot(extraction.Parsed, a, candidate));
        const repeated = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, candidate)).invalid;
        try std.testing.expectEqualDeep(rejection, repeated);
    }
}

test "shared repair progress compares canonical prose while exact CAS and native insertions remain unchanged" {
    const atomic = @import("domain/atomic_repair.zig");
    const text = @import("domain/typed_text.zig");
    const source = @import("domain/specification_support_model.zig");
    const Replacement = union(enum) { business: text.BusinessText, reference: text.ReferenceSemanticText, question: source.Detail, finding: source.Canonical };
    const Contract = atomic.Contract(enum { subject }, Replacement, struct { source_revision: u32 }, enum { rejected });
    const story: Replacement = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "Café " } }, .{ .exact_copy = .{ .claim_id = .{ .ordinal = 7 } } }, .{ .literal = .{ .value = " now." } } } } };
    const question: source.Detail = .{ .detail = "Diagnostic Café remains exact.", .question = "Which café applies?" };
    const finding: source.Canonical = .{ .kind = .unsupported, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "Diagnostic Café remains exact.", .question = "Which café applies?" };
    for ([_]struct { old: Replacement, proposed: Replacement, changed: bool }{
        .{ .old = story, .proposed = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "Ca" } }, .{ .literal = .{ .value = "fe\u{301} " } }, .{ .exact_copy = .{ .claim_id = .{ .ordinal = 7 } } }, .{ .literal = .{ .value = " now." } } } } }, .changed = false },
        .{ .old = story, .proposed = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "Café " } }, .{ .exact_copy = .{ .claim_id = .{ .ordinal = 8 } } }, .{ .literal = .{ .value = " now." } } } } }, .changed = true },
        .{ .old = story, .proposed = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "Café " } }, .{ .exact_copy = .{ .claim_id = .{ .ordinal = 7 } } }, .{ .literal = .{ .value = " tomorrow." } } } } }, .changed = true },
        .{ .old = .{ .reference = .{ .nodes = &.{ .{ .literal = .{ .value = "Café source " } }, .{ .source = .{ .source_id = .{ .ordinal = 3 } } } } } }, .proposed = .{ .reference = .{ .nodes = &.{ .{ .literal = .{ .value = "Cafe" } }, .{ .literal = .{ .value = "\u{301} source " } }, .{ .source = .{ .source_id = .{ .ordinal = 3 } } } } } }, .changed = false },
        .{ .old = .{ .question = question }, .proposed = .{ .question = .{ .detail = question.detail, .question = "Which cafe\u{301} applies?" } }, .changed = false },
        .{ .old = .{ .question = question }, .proposed = .{ .question = .{ .detail = "Diagnostic Cafe\u{301} remains exact.", .question = question.question } }, .changed = true },
        .{ .old = .{ .finding = finding }, .proposed = .{ .finding = .{ .kind = finding.kind, .provenance = finding.provenance, .source_ids = finding.source_ids, .detail = finding.detail, .question = "Which cafe\u{301} applies?" } }, .changed = false },
        .{ .old = .{ .question = .{ .detail = "Retained diagnostic.", .authority_gap = .{ .kind = .unsupported, .source_ids = &.{.{ .ordinal = 1 }}, .detail = "Retained gap diagnostic.", .question = "Which café applies?" } } }, .proposed = .{ .question = .{ .detail = "Retained diagnostic.", .authority_gap = .{ .kind = .unsupported, .source_ids = &.{.{ .ordinal = 1 }}, .detail = "Retained gap diagnostic.", .question = "Which cafe\u{301} applies?" } } }, .changed = false },
        // Original literal wire spans retain their exact Unicode bytes while
        // surrounding prose and adjacent fragments use the shared normalizer.
        .{ .old = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Café {\"fragments\":[\"Cafe\u{301}\"]}" } }} } }, .proposed = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "Cafe\u{301} {\"frag" } }, .{ .literal = .{ .value = "ments\":[\"Cafe\u{301}\"]}" } } } } }, .changed = false },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const canonical: text.CanonicalText = .{ .normalizer = text_fixture.normalizer, .original_sources = &.{.{ .source_id = .{ .ordinal = 1 }, .bytes = "Original {\"fragments\":[\"Cafe\u{301}\"]} source." }} };
        const owner: @import("domain/model_request_identity.zig").ImmutableUnitOwnerId = .{ .reference_global = .{ .reference_state_id = .{ .bytes = "source" }, .unit_slot_id = .{ .bytes = "subject" } } };
        var authorization = try Contract.authorize(a, owner, 1, .subject, case.old, .{ .source_revision = 2 }, .rejected);
        authorization.retry = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = @splat(4), .revision = 1, .maximum_targets = 1 };
        const merged = try Contract.checkMerge(a, canonical, owner, 1, case.old, .{ .source_revision = 2 }, authorization, case.proposed, null);
        try std.testing.expectEqual(case.changed, merged.changed);
        if (!case.changed) {
            const retry = @import("domain/workflow_retry.zig");
            for ([_]retry.Transition{ try merged.transition(.dependent_review), try merged.validatedTransition(.resolved) }) |transition| {
                var state = retry.State.init(std.testing.allocator);
                defer state.deinit();
                try state.commit(try state.prepare(.{ .authorized = authorization.retry.? }));
                _ = try state.beginAttempt(.{ .bytes = "merge" }, .{ .value = 64 }, authorization.retry.?);
                const exhausted = (try state.unchangedExhaustion(transition)).?;
                try std.testing.expectEqual(.unchanged_repair, exhausted.reason);
                try std.testing.expectEqual(@as(u64, 1), exhausted.completed_executions);
            }
            if (!try Contract.equal(a, case.old, case.proposed)) try std.testing.expectError(error.InvalidAtomicRepair, Contract.checkMerge(a, canonical, owner, 1, case.proposed, .{ .source_revision = 2 }, authorization, case.proposed, null));
        }
    }
}

pub const no_claim = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":\"This chunk contains no feature claims.\"},\"token_classifications\":[]}";

/// Test response: one business claim citing every citable line of the chunk.
pub fn reply(allocator: std.mem.Allocator, inputs: evidence.Inputs, chunk: evidence.Chunk) ![]const u8 {
    return @import("domain/model_candidate_json.zig").encode(@import("domain/reference_extraction_parser.zig").Response, allocator, .{ .claims = .{ .claims = &.{.{ .category = .business, .citations = try citableLines(allocator, inputs, chunk) }}, .token_classifications = &.{} } });
}
/// Test response: a no-feature-claim reason that names a passive literal.
pub fn passiveReply(allocator: std.mem.Allocator, ordinal: u32) ![]const u8 {
    return @import("domain/model_candidate_json.zig").encode(@import("domain/reference_extraction_parser.zig").Response, allocator, .{ .no_feature_claim = .{
        .reason = .{ .nodes = &.{ .{ .literal = .{ .value = "Read " } }, .{ .passive = .{ .passive_literal_id = .{ .ordinal = ordinal } } } } },
        .token_classifications = &.{},
    } });
}
/// The chunk's nonblank line IDs: what an extraction packet lets a model cite.
pub fn citableLines(allocator: std.mem.Allocator, inputs: evidence.Inputs, chunk: evidence.Chunk) ![]const @import("domain/source_selections.zig").Id {
    var lines: std.ArrayList(@import("domain/source_selections.zig").Id) = .empty;
    const selections = @import("domain/source_selections.zig");
    for (try selections.lines(allocator, inputs, .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id })) |line| if (selections.citable(line.text)) try lines.append(allocator, line.id);
    return lines.toOwnedSlice(allocator);
}
fn raw(inputs: evidence.Inputs, index: usize, bytes: []const u8) extraction.RawResult {
    return .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[index].id }, .result = .{ .response = bytes } };
}
pub fn finish(allocator: std.mem.Allocator, inputs: evidence.Inputs, results: []const extraction.RawResult) !extraction.Accounted {
    const parsed = try parse.execute(allocator, .{ .entries = results });
    return finishText(allocator, inputs, try text_fixture.check(allocator, inputs, parsed));
}
pub fn finishText(allocator: std.mem.Allocator, inputs: evidence.Inputs, candidate: extraction.TextValidated) !extraction.Accounted {
    const tokens = try token_fixture.assignments(allocator, inputs, candidate);
    const valid = try validate.execute(allocator, inputs, try token_fixture.build.execute(allocator, tokens));
    return account.execute(inputs, tokens, try build.execute(allocator, try assign.execute(allocator, valid)));
}

test "source claims and exact tokens receive only engine assigned IDs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    for ([_][]const u8{ "MOCK Display `MOCK READY` when requested.\n", "MOCK A librarian can renew a loan.\r\n" }) |bytes| {
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(allocator, &ids, try ingest(allocator, "requirements.md", bytes));
        const results = try allocator.alloc(extraction.RawResult, inputs.chunks.entries.len);
        const available = try token_fixture.candidates(allocator, inputs);
        for (results, inputs.chunks.entries, 0..) |*result, chunk, index| result.* = raw(inputs, index, try token_fixture.wire(allocator, try reply(allocator, inputs, chunk), try token_fixture.classifications(allocator, available, chunk)));
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
        "{}",                                                                                                                     "[]",                                                                                              "null",                                                                                                                       "```json\n{}\n```",                                                                   no_claim ++ "{}",
        "{\"kind\":\"blocked\"}",                                                                                                 "{\"kind\":\"no_feature_claim\",\"reason\":\"none\",\"token_classifications\":[],\"claim_id\":1}", "{\"kind\":\"no_feature_claim\",\"kind\":\"no_feature_claim\",\"reason\":\"none\",\"token_classifications\":[]}",             "{\"kind\":\"no_feature_claim\",\"reason\":\"none\",\"token_classifications\":[{}]}", "{\"kind\":\"no_feature_claim\",\"reason\":\"none\"}",
        "{\"kind\":\"claims\",\"claims\":[{\"category\":\"business\",\"citations\":[1],\"id\":1}],\"token_classifications\":[]}", "{\"kind\":\"claims\",\"claims\":[],\"reason\":\"none\",\"token_classifications\":[]}",            "{\"kind\":\"claims\",\"claims\":[],\"token_classifications\":[],\"producers\":{\"content\":null,\"classifications\":null}}",
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
    const first = raw(inputs, 0, try reply(allocator, inputs, inputs.chunks.entries[0]));
    const second = raw(inputs, 1, try reply(allocator, inputs, inputs.chunks.entries[1]));
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
    const empty_reason = "{\"kind\":\"no_feature_claim\",\"reason\":{\"nodes\":\"  \"},\"token_classifications\":[]}";
    try std.testing.expectError(error.InvalidTypedText, finish(allocator, inputs, &.{raw(inputs, 0, empty_reason)}));
    // ADR 0036: unknown, blank-only and absent citations quote no source text.
    const parsed = try parse.execute(allocator, .{ .entries = &.{raw(inputs, 0, try reply(allocator, inputs, inputs.chunks.entries[0]))} });
    var entry = parsed.entries[0];
    var claim = entry.outcome.claims[0];
    for ([_][]const @import("domain/source_selections.zig").Id{ &.{.{ .ordinal = 999 }}, &.{} }) |citations| {
        claim.citations = citations;
        entry.outcome = .{ .claims = &.{claim} };
        try std.testing.expectError(error.InvalidReferenceExtraction, text_fixture.check(allocator, inputs, .{ .entries = &.{entry} }));
    }
    const blank = try fixture.prepare(allocator, &ids, try ingest(allocator, "blank.md", "Café\r\n\r\nRenew.\r\n"));
    try std.testing.expectEqual(@as(usize, 1), blank.chunks.entries.len);
    entry = (try parse.execute(allocator, .{ .entries = &.{raw(blank, 0, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"business\",\"citations\":[2]}],\"token_classifications\":[]}")} })).entries[0];
    try std.testing.expectError(error.InvalidReferenceExtraction, text_fixture.check(allocator, blank, .{ .entries = &.{entry} }));
    // A blank line cited beside text is rejected too.
    entry = (try parse.execute(allocator, .{ .entries = &.{raw(blank, 0, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"business\",\"citations\":[1,2]}],\"token_classifications\":[]}")} })).entries[0];
    try std.testing.expectError(error.InvalidReferenceExtraction, text_fixture.check(allocator, blank, .{ .entries = &.{entry} }));
}

test "a claim quotes its cited source lines as written" {
    const Selection = @import("domain/source_selections.zig").Selection;
    const one = struct {
        fn of(comptime first: u32, comptime last: u32) []const Selection {
            return &.{.{ .first = .{ .ordinal = first }, .last = .{ .ordinal = last } }};
        }
    }.of;
    for ([_]struct { source: []const u8, category: []const u8, citations: []const u8, text: []const u8, selections: []const Selection }{
        // Citations in any order quote one claim in source order, list markers included.
        .{ .source = "- A borrower must be able to renew a loan.\n- Show `Renewed!` after renewal.\n", .category = "validation", .citations = "[2,1]", .text = "- A borrower must be able to renew a loan.\n- Show `Renewed!` after renewal.", .selections = one(1, 2) },
        .{ .source = "### Renewal\n1. Renew only if\n   - the loan is not overdue.\n2. Never renew twice.\n", .category = "scope_guard", .citations = "[1,2,3,4]", .text = "### Renewal\n1. Renew only if\n   - the loan is not overdue.\n2. Never renew twice.", .selections = one(1, 4) },
        // Indentation outside fenced code is trimmed at a run's ends.
        .{ .source = "1. Renew only if\n   - the loan is not overdue.\n", .category = "scope_guard", .citations = "[2]", .text = "- the loan is not overdue.", .selections = one(2, 2) },
        // A run spans uncited blank lines.
        .{ .source = "- Renew a loan.\n- Refuse overdue loans.\n\nRenewal must not be silent.\n", .category = "design", .citations = "[1,2,4]", .text = "- Renew a loan.\n- Refuse overdue loans.\n\nRenewal must not be silent.", .selections = one(1, 4) },
        // An ellipsis line marks uncited text between runs, and can't complete a JSON value.
        .{ .source = "Renew a loan.\nRefuse overdue loans.\nShow the deadline.\n", .category = "business", .citations = "[1,3]", .text = "Renew a loan.\n…\nShow the deadline.", .selections = &.{ .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } }, .{ .first = .{ .ordinal = 3 }, .last = .{ .ordinal = 3 } } } },
        .{ .source = "Example:\n{\"fragments\": [\n\"x\",\n\"y\"]}\n", .category = "technical", .citations = "[2,4]", .text = "{\"fragments\": [\n…\n\"y\"]}", .selections = &.{ .{ .first = .{ .ordinal = 2 }, .last = .{ .ordinal = 2 } }, .{ .first = .{ .ordinal = 4 }, .last = .{ .ordinal = 4 } } } },
        // Spacing and code spans are kept exactly; only each run's ends are trimmed.
        .{ .source = "Hello-world  must print `Hello,  World!`\n   only if asked.\n", .category = "technical", .citations = "[1,2]", .text = "Hello-world  must print `Hello,  World!`\n   only if asked.", .selections = one(1, 2) },
        // Fenced code lines keep every byte.
        .{ .source = "Configuration:\n\n```yaml\n- name: loan\n- limit: 5\n```\n", .category = "technical", .citations = "[4,5]", .text = "- name: loan\n- limit: 5\n", .selections = one(4, 5) },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", case.source));
        try std.testing.expectEqual(@as(usize, 1), inputs.chunks.entries.len);
        const bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"claims\",\"claims\":[{{\"category\":\"{s}\",\"citations\":{s}}}],\"token_classifications\":[]}}", .{ case.category, case.citations });
        const checked = try text_fixture.check(a, inputs, try parse.execute(a, .{ .entries = &.{raw(inputs, 0, bytes)} }));
        const claims = checked.entries[0].outcome.claims;
        try std.testing.expectEqual(@as(usize, 1), claims.len);
        try std.testing.expectEqualStrings(case.category, @tagName(claims[0].content));
        try std.testing.expectEqualStrings(case.text, quotedText(claims[0].content));
        try std.testing.expectEqualDeep(case.selections, claims[0].citations);
    }
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: fixture.IdSource = .{};
    // A business claim quoting a whole code value keeps ADR 0024's exact-value duty;
    // quoting part of one leaves it free.
    for ([_]struct { source: []const u8, citations: []const u8, forced: bool }{
        .{ .source = "Display `Loan\n  renewed!` after renewal.\n", .citations = "[1,2]", .forced = true },
        .{ .source = "Config:\n\n```\na: 1\n\nb: 2\n```\n", .citations = "[1,3,4,6,7]", .forced = true },
        .{ .source = "Config:\n\n```\na: 1\nb: 2\n```\n", .citations = "[4,5]", .forced = true },
        .{ .source = "Config:\n\n```\na: 1\nb: 2\n```\n", .citations = "[3,4,5]", .forced = true },
        .{ .source = "```\n  key: v\n```\n", .citations = "[2]", .forced = true },
        .{ .source = "Config:\n```\na: 1\n", .citations = "[1,2,3]", .forced = true },
        .{ .source = "Config:\n\n```\na: 1\nb: 2\n```\n", .citations = "[4]", .forced = false },
    }) |case| {
        const exact = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", case.source));
        const available = try token_fixture.candidates(a, exact);
        try std.testing.expectEqual(@as(usize, 1), available.entries.len);
        const body = try std.fmt.allocPrint(a, "{{\"kind\":\"claims\",\"claims\":[{{\"category\":\"business\",\"citations\":{s}}}],\"token_classifications\":[]}}", .{case.citations});
        const wire = try token_fixture.wire(a, body, &.{.{ .irrelevant = available.entries[0].id }});
        const checked = try @import("domain/token_classification_validation.zig").validate(a, exact, available, try text_fixture.check(a, exact, try parse.execute(a, .{ .entries = &.{raw(exact, 0, wire)} })));
        if (case.forced) {
            try std.testing.expectEqualDeep(&[_]extraction.tokens.CandidateId{available.entries[0].id}, checked.invalid.choices.required_preserve);
        } else try std.testing.expect(checked == .valid);
    }
    // Fenced code comes from each whole source, so a chunk can start inside a code block
    // after an earlier one, and each source keeps its own blocks.
    const sources = try fixture.prepare(a, &ids, try @import("reference_ingestion_test.zig").readSources(std.testing.io, a, &.{
        "```\n  a: 1\n```\n" ++ "Context line.\n" ** 60 ++ "```\n  key: v\n```\n",
        "Intro.\n  indented prose  \n```\n  b: 2\n```\n",
    }));
    try std.testing.expectEqual(@as(usize, 3), sources.chunks.entries.len);
    const quoted = try text_fixture.check(a, sources, try parse.execute(a, .{ .entries = &.{
        raw(sources, 0, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"technical\",\"citations\":[2]}],\"token_classifications\":[]}"),
        raw(sources, 1, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"technical\",\"citations\":[1]}],\"token_classifications\":[]}"),
        raw(sources, 2, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"technical\",\"citations\":[2]},{\"category\":\"technical\",\"citations\":[4]}],\"token_classifications\":[]}"),
    } }));
    for ([_][]const u8{ "  a: 1\n", "  key: v\n", "indented prose", "  b: 2\n" }, [_]extraction.Content{
        quoted.entries[0].outcome.claims[0].content,
        quoted.entries[1].outcome.claims[0].content,
        quoted.entries[2].outcome.claims[0].content,
        quoted.entries[2].outcome.claims[1].content,
    }) |expected, content| try std.testing.expectEqualStrings(expected, quotedText(content));
    // A model cannot supply claim wording: the closed proposal has no text field.
    const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", "A borrower must be able to renew a loan.\n"));
    try std.testing.expectError(error.InvalidReferenceExtraction, parse.execute(a, .{ .entries = &.{raw(inputs, 0, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"business\",\"citations\":[1],\"content\":{\"business\":{\"segments\":\"A borrower may renew a loan.\"}}}],\"token_classifications\":[]}")} }));
}
fn quotedText(content: extraction.Content) []const u8 {
    return switch (content) {
        inline .business, .scope_guard => |value| value.value.segments[0].literal.value,
        inline else => |value| value.value.nodes[0].literal.value,
    };
}

test "claim quoting allocates in proportion to the source, not per chunk" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: fixture.IdSource = .{};
    const source = "Use `x` now.\n" ** (64 * 128);
    const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", source));
    try std.testing.expectEqual(@as(usize, 128), inputs.chunks.entries.len);
    const results = try a.alloc(extraction.RawResult, inputs.chunks.entries.len);
    for (results, 0..) |*result, index| result.* = raw(inputs, index, "{\"kind\":\"claims\",\"claims\":[{\"category\":\"technical\",\"citations\":[1]}],\"token_classifications\":[]}");
    const parsed = try parse.execute(a, .{ .entries = results });
    const context = try text_fixture.prepare(a, inputs);
    defer context.deinit();
    var validation: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer validation.deinit();
    _ = try context.check(validation.allocator(), inputs, parsed);
    // The source's code blocks are scanned once per validation, not once per chunk.
    try std.testing.expect(validation.queryCapacity() < 64 * source.len);
}

test "final accounting rejects omitted orphan duplicate and foreign identity joins" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(allocator, &ids, try ingest(allocator, "source.md", "claim\n"));
    const completed = try finish(allocator, inputs, &.{raw(inputs, 0, try reply(allocator, inputs, inputs.chunks.entries[0]))});
    const tokens = try token_fixture.assignments(allocator, inputs, try text_fixture.check(allocator, inputs, try parse.execute(allocator, .{ .entries = &.{raw(inputs, 0, try reply(allocator, inputs, inputs.chunks.entries[0]))} })));
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
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const temporary = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(temporary, &ids, try ingest(temporary, "source.md", "claim\n"));
    _ = try finish(temporary, inputs, &.{raw(inputs, 0, try reply(temporary, inputs, inputs.chunks.entries[0]))});
}

test "sealed extraction values retain only owned candidate data after inputs are released" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(ownershipCase, .{});
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
    const quoted = try reply(source_allocator, inputs, inputs.chunks.entries[0]);
    const bytes = try token_fixture.wire(source_allocator, quoted, try token_fixture.classifications(source_allocator, try token_fixture.candidates(source_allocator, inputs), inputs.chunks.entries[0]));
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const content: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const classifications: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    var observed = raw(inputs, 0, bytes);
    observed.origin = content;
    observed.producers = .{ .content = content, .classifications = classifications };
    const captured = try owned.capture(allocator, .{ .entries = &.{observed} });
    defer owned.destroy(captured);
    var current = try owned.create(allocator, null);
    defer owned.destroy(current);
    current.payload = .{ .parsed = try parse.execute(current.arena.allocator(), owned.view(captured).payload().raw) };
    {
        const next = try owned.create(allocator, owned.view(current));
        errdefer owned.destroy(next);
        next.payload = .{ .text_validated = try text_fixture.check(next.arena.allocator(), inputs, current.payload.parsed) };
        try std.testing.expectEqualDeep(content, next.payload.text_validated.entries[0].outcome.claims[0].origin.?);
        try std.testing.expectEqualDeep(classifications, next.payload.text_validated.entries[0].classification_origins[0].?);
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
    try std.testing.expectEqualStrings("A `quoted` requirement.", retained.payload().accounted.ledger.claims[0].content.model.business.value.segments[0].literal.value);
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
        .{ .nodes = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} },
        .{ .nodes = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 999 } } }} },
    }, 0..) |reason, scenario| {
        const candidate: extraction.Parsed = .{ .entries = &.{.{ .scope = scope, .token_classifications = &.{}, .outcome = .{ .no_feature_claim = reason } }} };
        const rejection = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, candidate)).invalid;
        try std.testing.expectEqual(@as(@TypeOf(rejection.issue.reason), if (scenario == 0) .invalid_scalar else .unknown_passive), rejection.issue.reason);
        try std.testing.expect(rejection.target == .reason);
        const facts = try contexts.textFacts(inputs, context.registry, text_fixture.safety.value(context.owner), candidate);
        const authorization = try repair.authorize(a, facts, rejection);
        const replacement: repair.Replacement = .{ .reference = .{ .nodes = &.{.{ .literal = .{ .value = "This source supplies background context." } }} } };
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, @import("test_fixtures/reference_text.zig").normalizer, (facts).text.inputs), facts, authorization, replacement, null);
        const valid = (try text_fixture.validate_text.execute(a, context.registry, text_fixture.safety.value(context.owner), inputs, fixed)).valid;
        try std.testing.expect(valid.entries[0].outcome == .no_feature_claim);
        try std.testing.expectEqualDeep(candidate.entries[0].token_classifications, fixed.entries[0].token_classifications);
        const retained = try (@import("domain/candidate_validation_diagnostic.zig").Diagnostic{ .extraction_text = rejection }).copy(a);
        try std.testing.expectEqualDeep(rejection, retained.extraction_text);
    }
}

test "reason text repair binds its packet, origin, progress and authority to current policy" {
    const repair = @import("domain/reference_extraction_text_repair.zig");
    const contexts = @import("domain/reference_extraction_context.zig");
    const classifications = @import("domain/token_classification_validation.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const first: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const content: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const correction: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "Background: `Loan renewed!`. Consult requirements.md.\n", "History: `Hello, World!`. Consult requirements.md.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", source));
        const context = try text_fixture.prepare(a, inputs);
        defer context.deinit();
        const current = text_fixture.safety.value(context.owner);
        const available = try token_fixture.candidates(a, inputs);
        const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id };
        var unknown = available.entries[0].id;
        unknown.ordinal += 1;
        const candidate: extraction.Parsed = .{ .entries = &.{.{ .scope = scope, .origin = first, .producers = .{ .content = content, .classifications = first }, .token_classifications = &.{.{ .irrelevant = unknown }}, .outcome = .{ .no_feature_claim = .{ .nodes = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } }} };
        const rejection = (try text_fixture.validate_text.execute(a, context.registry, current, inputs, candidate)).invalid;
        try std.testing.expectEqual(.invalid_scalar, rejection.issue.reason);
        try std.testing.expectEqualDeep(content, rejection.origin.?);
        const facts = try contexts.textFacts(inputs, context.registry, current, candidate);
        const authorization = try repair.authorize(a, facts, rejection);
        const replacement: repair.Replacement = .{ .reference = .{ .nodes = &.{ .{ .literal = .{ .value = "Consult " } }, .{ .passive = .{ .passive_literal_id = context.registry.records[0].id } } } } };
        const packet = try repair.packet(std.testing.allocator, facts, context.registry, current, available, authorization);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualDeep(content, packet.repairOrigin().?);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const rule = body.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expectEqualStrings(rejection.issue.description(), rule.get("requirement").?.string);
        const projected = try @import("domain/model_candidate_json.zig").decode(extraction.text.Issue, a, try std.json.Stringify.valueAlloc(a, rule.get("issue").?, .{}));
        try std.testing.expectEqualDeep(rejection.issue, projected);
        const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
        var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schema = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/extraction.schema.json", a, .limited(1_048_576)));
        try @import("test_fixtures/prepared_model_repair.zig").check(a, packet, schema, wire, null);
        const canonical = try extraction.text.CanonicalText.fromInputs(a, text_fixture.normalizer, inputs);
        const merged = try repair.merge(a, canonical, facts, authorization, try repair.parse(a, authorization, packet, wire), correction);
        try std.testing.expectEqualDeep(candidate.entries[0].token_classifications, merged.entries[0].token_classifications);
        try std.testing.expectEqualDeep(correction, extraction.textOrigin(merged.entries[0], .reason).?);
        const checked = (try text_fixture.validate_text.execute(a, context.registry, current, inputs, merged)).valid;
        try std.testing.expectEqual(.resolved, (try repair.progress(a, text_fixture.validator, context.registry, current, inputs, merged)).?.validated.result);
        try std.testing.expectEqualDeep(merged.last_repair.?, checked.last_repair.?);
        try std.testing.expect(checked.last_repair.?.changed);
        // The reason's repair leaves the classification defect for its own route.
        const remaining = (try classifications.validate(a, inputs, available, checked)).invalid;
        try std.testing.expectEqualDeep(first, remaining.origin.?);
        try std.testing.expectEqualDeep(&[_]extraction.tokens.CandidateId{unknown}, remaining.issues.unknown);
        const merged_facts = try contexts.textFacts(inputs, context.registry, current, merged);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, canonical, merged_facts, authorization, replacement, correction));
        var changed_registry = context.registry;
        const names = try a.dupe(@import("domain/path_token_grammar.zig").ReferenceName, changed_registry.grammar.reference_names);
        names[0].basename = "changed.md";
        changed_registry.grammar.reference_names = names;
        const changed_facts = try contexts.textFacts(inputs, changed_registry, current, candidate);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, changed_facts, rejection));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, facts, changed_registry, current, available, authorization));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, canonical, changed_facts, authorization, replacement, correction));
        const foreign_policy = try text_fixture.prepare(a, inputs);
        defer foreign_policy.deinit();
        try std.testing.expectError(error.StaleNamingPolicy, contexts.textFacts(inputs, context.registry, text_fixture.safety.value(foreign_policy.owner), candidate));
        var stale = facts;
        stale.text.policy_ids = &.{"different-policy"};
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, stale, rejection));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, canonical, stale, authorization, replacement, correction));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, .{ .normalizer = text_fixture.normalizer, .original_sources = &.{} }, facts, authorization, authorization.operation.replace, correction));
        const again = try repair.merge(a, canonical, facts, authorization, authorization.operation.replace, correction);
        try std.testing.expect(!again.last_repair.?.changed);
        try std.testing.expectEqual(.recurring, (try repair.progress(a, text_fixture.validator, context.registry, current, inputs, again)).?.validated.result);
        const repeated = (try text_fixture.validate_text.execute(a, context.registry, current, inputs, again)).invalid;
        try std.testing.expectEqual(.invalid_scalar, repeated.issue.reason);
        try std.testing.expectEqualDeep(correction, repeated.origin.?);
        const retry = try repair.authorize(a, try contexts.textFacts(inputs, context.registry, current, again), repeated);
        try std.testing.expectEqualDeep(authorization.retry.?.key, retry.retry.?.key);
        var registry = context.registry;
        registry.grammar.reference_state_id.bytes = "stale-state";
        try std.testing.expectError(error.InvalidPathTokenGrammar, text_fixture.validate_text.execute(a, registry, current, inputs, candidate));
    }
}

test "classification repair requests retain the frozen outcome and permitted decisions" {
    const repair = @import("domain/reference_extraction_repair.zig");
    const classifications = @import("domain/token_classification_validation.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(a, &ids, try ingest(a, "receipt.md", "The receipt is visible.\nDisplay `Receipt issued!`.\n"));
    const context = try text_fixture.prepare(a, inputs);
    defer context.deinit();
    const available = try token_fixture.candidates(a, inputs);
    try std.testing.expect(available.entries.len > 0);
    for ([_]bool{ false, true }) |has_claims| {
        // The claim quotes only line 1, so the token on line 2 may be irrelevant.
        const wire = if (has_claims) "{\"kind\":\"claims\",\"claims\":[{\"category\":\"business\",\"citations\":[1]}],\"token_classifications\":[]}" else no_claim;
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
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, @import("test_fixtures/reference_text.zig").normalizer, (facts).inputs), facts, auth, .{ .classifications = .{ .token_classifications = replacement } }, null);
        try std.testing.expectEqualDeep(candidate.entries[0].outcome, merged.entries[0].outcome);
        _ = (try classifications.validate(a, inputs, available, merged)).valid;
        if (!has_claims) {
            const forbidden = try token_fixture.classifications(a, available, inputs.chunks.entries[0]);
            const invalid = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, @import("test_fixtures/reference_text.zig").normalizer, (facts).inputs), facts, auth, .{ .classifications = .{ .token_classifications = forbidden } }, null);
            try std.testing.expect((try classifications.validate(a, inputs, available, invalid)).invalid.issues.forbidden.len > 0);
        }
    }
}

test "classification repair cannot erase a native literal-byte preservation duty" {
    const repair = @import("domain/reference_extraction_repair.zig");
    const classifications = @import("domain/token_classification_validation.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][]const u8{ "ACTIVE", "Loan renewed!" }) |bytes| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", try std.fmt.allocPrint(a, "Display `{s}`.", .{bytes})));
        const context = try text_fixture.prepare(a, inputs);
        defer context.deinit();
        const available = try token_fixture.candidates(a, inputs);
        // The quoted claim keeps the code span's bytes, so the token must be preserved.
        const candidate = try text_fixture.check(a, inputs, try parse.execute(a, .{ .entries = &.{raw(inputs, 0, try reply(a, inputs, inputs.chunks.entries[0]))} }));
        const rejected = (try classifications.validate(a, inputs, available, candidate)).invalid;
        try std.testing.expectEqualDeep(&[_]extraction.tokens.CandidateId{available.entries[0].id}, rejected.choices.required_preserve);
        const facts: repair.Facts = .{ .inputs = inputs, .candidates = available, .candidate = candidate };
        const auth = try repair.authorize(a, facts, .{ .token_classifications = rejected });
        const packet = try repair.packet(a, inputs, context.registry, available, candidate, auth);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const required = body.value.object.get("repair").?.object.get("rule").?.object.get("choices").?.object.get("required_preserve").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), required.len);
        const canonical = try extraction.text.CanonicalText.fromInputs(a, text_fixture.normalizer, inputs);
        const forbidden = try repair.merge(a, canonical, facts, auth, .{ .classifications = .{ .token_classifications = &.{.{ .irrelevant = available.entries[0].id }} } }, null);
        const still_invalid = (try classifications.validate(a, inputs, available, forbidden)).invalid;
        try std.testing.expectEqualDeep(rejected.choices.required_preserve, still_invalid.issues.forbidden);
        try std.testing.expectEqualDeep(candidate.entries[0].outcome, forbidden.entries[0].outcome);
        const fixed = try repair.merge(a, canonical, facts, auth, .{ .classifications = .{ .token_classifications = &.{.{ .preserve = .{ .token_candidate_id = available.entries[0].id, .kind = .code_sample } }} } }, null);
        try std.testing.expect((try classifications.validate(a, inputs, available, fixed)) == .valid);
        try std.testing.expectEqualDeep(candidate.entries[0].outcome, fixed.entries[0].outcome);
    }
}

test "composed extraction preserves producer attribution and stable native repair identity" {
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const repair = @import("domain/reference_extraction_repair.zig");
    const classifications = @import("domain/token_classification_validation.zig");
    const anchor: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const content: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 2 } };
    const classified: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "Show `Hello, World!`.\n", "Display `Renewed!` and `Due today`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", source));
        const available = try token_fixture.candidates(a, inputs);
        var unknown = available.entries[0].id;
        unknown.ordinal = 999;
        var response = raw(inputs, 0, try token_fixture.wire(a, try reply(a, inputs, inputs.chunks.entries[0]), &.{.{ .irrelevant = unknown }}));
        response.origin = anchor;
        response.producers = .{ .content = content, .classifications = classified };
        const parsed = try parse.execute(a, .{ .entries = &.{response} });
        const context = try text_fixture.prepare(a, inputs);
        defer context.deinit();
        const checked = try context.check(a, inputs, parsed);
        try std.testing.expectEqualDeep(anchor, checked.entries[0].origin.?);
        try std.testing.expectEqualDeep(content, checked.entries[0].outcome.claims[0].origin.?);
        try std.testing.expectEqualDeep(classified, checked.entries[0].classification_origins[0].?);
        const invalid = (try classifications.validate(a, inputs, available, checked)).invalid;
        try std.testing.expectEqualDeep(classified, invalid.origin.?);
        const repair_facts: repair.Facts = .{ .inputs = inputs, .candidates = available, .candidate = checked };
        const authorization = try repair.authorize(a, repair_facts, .{ .token_classifications = invalid });
        const classification_packet = try repair.packet(a, inputs, context.registry, available, checked, authorization);
        defer @import("domain/model_input_packet.zig").release(classification_packet);
        try std.testing.expectEqualDeep(classified, classification_packet.repairOrigin().?);
        const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, @import("test_fixtures/reference_text.zig").normalizer, (repair_facts).inputs), repair_facts, authorization, authorization.operation.replace, corrected);
        const repeated = (try classifications.validate(a, inputs, available, unchanged)).invalid;
        try std.testing.expectEqualDeep(corrected, repeated.origin.?);
        const again = try repair.authorize(a, .{ .inputs = inputs, .candidates = available, .candidate = unchanged }, .{ .token_classifications = repeated });
        try std.testing.expectEqualDeep(authorization.retry.?.key, again.retry.?.key);
        const complete = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, @import("test_fixtures/reference_text.zig").normalizer, (repair_facts).inputs), repair_facts, authorization, .{ .classifications = .{ .token_classifications = try token_fixture.classifications(a, available, inputs.chunks.entries[0]) } }, corrected);
        try std.testing.expectEqualDeep(checked.entries[0].outcome, complete.entries[0].outcome);
        try std.testing.expectEqualDeep(anchor, complete.entries[0].origin.?);
        for (complete.entries[0].classification_origins) |origin| try std.testing.expectEqualDeep(corrected, origin.?);
        try std.testing.expectEqual(.complete, (try finishText(a, inputs, complete)).outcome);
        const absent = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, @import("test_fixtures/reference_text.zig").normalizer, (repair_facts).inputs), repair_facts, authorization, .{ .classifications = .{ .token_classifications = &.{} } }, corrected);
        const missing = (try classifications.validate(a, inputs, available, absent)).invalid;
        try std.testing.expect(missing.origin == null and missing.issues.missing.len == available.entries.len);
        const missing_auth = try repair.authorize(a, .{ .inputs = inputs, .candidates = available, .candidate = absent }, .{ .token_classifications = missing });
        const missing_packet = try repair.packet(a, inputs, context.registry, available, absent, missing_auth);
        defer @import("domain/model_input_packet.zig").release(missing_packet);
        try std.testing.expectEqualDeep(corrected, missing_packet.repairOrigin().?);
        const entries = try a.dupe(extraction.TextValidatedResult, complete.entries);
        entries[0].classification_origins = &.{};
        var malformed = complete;
        malformed.entries = entries;
        try std.testing.expectError(error.InvalidReferenceExtraction, classifications.validate(a, inputs, available, malformed));
    }
}

test "token-only extraction preserves exact claims without weakening no-feature classification policy" {
    const classifications = @import("domain/token_classification_validation.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const content: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const classified: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "Show `Hello, World!`.\n", "Display `Renewed!` and `Due today`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", source));
        const available = try token_fixture.candidates(a, inputs);
        const preserved = try token_fixture.classifications(a, available, inputs.chunks.entries[0]);
        try std.testing.expect(available.entries.len > 0);
        var response = raw(inputs, 0, try token_fixture.wire(a, "{\"kind\":\"claims\",\"claims\":[],\"token_classifications\":[]}", preserved));
        response.origin = content;
        response.producers = .{ .content = content, .classifications = classified };
        const candidate = try text_fixture.check(a, inputs, try parse.execute(a, .{ .entries = &.{response} }));
        try std.testing.expectEqual(@as(usize, 0), candidate.entries[0].outcome.claims.len);
        const completed = try finishText(a, inputs, candidate);
        try std.testing.expectEqual(.complete, completed.outcome);
        try std.testing.expectEqual(available.entries.len, completed.ledger.claims.len);
        try std.testing.expectEqual(available.entries.len, completed.ledger.chunks[0].outcome.claims.len);
        for (available.entries, completed.ledger.claims) |token, claim| {
            try std.testing.expectEqualDeep(token.id, claim.content.preserved_token.value.candidate_id);
            try std.testing.expectEqualStrings(token.fact.citation.verbatim.?, claim.content.preserved_token.value.raw_value.bytes);
        }
        response.result = .{ .response = try token_fixture.wire(a, no_claim, preserved) };
        const rejected_candidate = try text_fixture.check(a, inputs, try parse.execute(a, .{ .entries = &.{response} }));
        const rejected = (try classifications.validate(a, inputs, available, rejected_candidate)).invalid;
        try std.testing.expectEqual(available.entries.len, rejected.issues.forbidden.len);
        try std.testing.expectEqualDeep(classified, rejected.origin.?);
        try std.testing.expectEqualSlices(std.meta.Tag(extraction.tokens.Classification), &.{.irrelevant}, rejected.choices.decisions);
    }
}

test "forced classifications distinguish empty chunks, no-feature outcomes and positive token-only claims" {
    const forced = @import("actions/reference/construct_forced_token_classifications.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A librarian can renew a loan.\n", "Display `Loan renewed!`.\n" }) |source| {
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(a, &ids, try ingest(a, "requirements.md", source));
        const candidates = try token_fixture.candidates(a, inputs);
        const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id };
        const negative = (try forced.classifications(a, scope, candidates, .no_feature_claim)).?;
        try std.testing.expectEqual(candidates.entries.len, negative.len);
        for (negative, candidates.entries) |classification, candidate| try std.testing.expectEqualDeep(candidate.id, classification.irrelevant);
        const positive = try forced.classifications(a, scope, candidates, .claims);
        if (candidates.entries.len == 0) {
            try std.testing.expectEqual(@as(usize, 0), positive.?.len);
        } else {
            try std.testing.expect(positive == null);
        }
        const foreign: evidence.Scope = .{ .state_id = scope.state_id, .chunk_id = .{ .bytes = "another-chunk" } };
        try std.testing.expectEqual(@as(usize, 0), (try forced.classifications(a, foreign, candidates, .claims)).?.len);
    }
}
