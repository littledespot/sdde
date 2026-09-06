const std = @import("std");
const f = @import("test_fixtures/reference_reconciliation.zig");
const r = f.r;
const text = @import("test_fixtures/reference_text.zig");
const tokens = @import("test_fixtures/reference_tokens.zig");
const extraction = @import("reference_extraction_test.zig");
const Fixture = struct {
    inputs: r.evidence.Inputs,
    extracted: r.extraction.Accounted,
    text: @import("test_fixtures/reference_text.zig").Prepared,
    pub fn deinit(self: Fixture) void {
        self.text.deinit();
    }
    pub fn context(self: Fixture) f.Context {
        return .{ .inputs = self.inputs, .registry = self.text.registry, .current = text.safety.value(self.text.owner) };
    }
};
pub fn prepare(allocator: std.mem.Allocator, sources: []const []const u8) !Fixture {
    const ingestion = @import("domain/reference_ingestion.zig");
    var inputs = try @import("reference_ingestion_test.zig").read(allocator, "base.md", "");
    const documents = try allocator.alloc(ingestion.Document, sources.len);
    for (sources, documents, 0..) |bytes, *document, index| {
        const read = try @import("reference_ingestion_test.zig").read(allocator, try std.fmt.allocPrint(allocator, "source-{d}.md", .{index}), bytes);
        document.* = read.documents[0];
        document.source.ordinal = @intCast(index + 1);
        const blocks = try allocator.dupe(ingestion.Block, document.blocks);
        for (blocks) |*block| block.id.source = document.source;
        document.blocks = blocks;
    }
    inputs.documents = documents;
    var ids: @import("reference_evidence_test.zig").IdSource = .{};
    const citable = try @import("reference_evidence_test.zig").prepare(allocator, &ids, inputs);
    const candidates = try tokens.candidates(allocator, citable);
    const results = try allocator.alloc(r.extraction.RawResult, citable.chunks.entries.len);
    for (citable.chunks.entries, results) |chunk, *result| {
        result.* = .{ .scope = .{ .state_id = citable.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = try tokens.wire(allocator, try extraction.reply(allocator, chunk, "The user can confirm the request."), try tokens.classifications(allocator, candidates, chunk)) } };
    }
    return .{ .inputs = citable, .extracted = try extraction.finish(allocator, citable, results), .text = try text.prepare(allocator, citable) };
}

test "hierarchical reconciliation preserves original meaning citations exact tokens and total membership" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Display `Hello, World!`.\n", "Renew a library loan.\r\n", "Use `Cafe\u{301}`.\r\n", "A fourth requirement.\n", "A fifth requirement.\n", "A sixth requirement.\n", "A seventh requirement.\n", "An eighth requirement.\n", "A ninth requirement.\n" });
    defer fixture.deinit();
    const initial = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    var levels = std.enums.EnumSet(r.Level).initEmpty();
    var recursive_global = false;
    for (initial.plan.partitions) |partition| {
        levels.insert(partition.group.level);
        recursive_global = recursive_global or partition.group.round > 0;
        try std.testing.expect((if (partition.group.level == .within_source) partition.group.claim_ids.len else partition.group.children.len) <= 2);
    }
    try std.testing.expectEqual(@as(usize, 3), levels.count());
    try std.testing.expect(recursive_global);
    const final = try f.summaries(a, initial, fixture.context());
    try std.testing.expectEqual(fixture.extracted.ledger.claims.len, final.items.len);
    for (final.items, fixture.extracted.ledger.claims) |item, original| try std.testing.expectEqualDeep(original, item.claim);
    const result = try f.finish(a, final, try f.global(a, final), fixture.context());
    try std.testing.expectEqual(.complete, result.outcome);
    try std.testing.expectEqual(final.items.len, result.records.signals.len);
    try std.testing.expectEqualDeep(result, try f.finish(a, final, try f.global(a, final), fixture.context()));
    try std.testing.expectEqualStrings("Hello, World!", final.items[1].claim.content.preserved_token.value.raw_value.bytes);
    try std.testing.expectEqualStrings("Cafe\u{301}", final.items[4].claim.content.preserved_token.value.raw_value.bytes);
}

test "partition coverage rejects omissions duplicates foreign children ordering and invalid group size" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n" });
    defer fixture.deinit();
    const initial = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    for ([_]u32{ 0, 1 }) |size| try std.testing.expectError(error.InvalidReferenceReconciliation, f.partition.execute(a, initial.plan.layout.items, size));
    for (0..4) |scenario| {
        var plan = initial.plan;
        const partitions = try a.dupe(r.Partition, plan.partitions);
        plan.partitions = partitions;
        switch (scenario) {
            0 => plan.partitions = partitions[1..],
            1 => partitions[1] = partitions[0],
            2 => partitions[2].group.children = &.{.{ .value = 999 }},
            3 => partitions[0].group.claim_ids = &.{.{ .ordinal = 2 }},
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_partitions.execute(a, plan));
    }
    var blocked = fixture.extracted;
    blocked.outcome = .blocked;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.build_items.execute(a, fixture.inputs, blocked));
    var stale = fixture.extracted;
    stale.ledger.state_id.bytes = "stale";
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.build_items.execute(a, fixture.inputs, stale));
}

test "summaries reject missing duplicate foreign memberships forged keys kinds and token references" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `Hello, World!`.\n"});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2));
    const valid = try f.summary(a, input);
    for (0..9) |scenario| {
        var proposal = valid;
        const statements = try a.dupe(r.StatementProposal, valid.statements);
        proposal.statements = statements;
        switch (scenario) {
            0 => proposal.member_claim_ids = &.{},
            1 => proposal.member_claim_ids = &.{ valid.member_claim_ids[0], valid.member_claim_ids[0] },
            2 => proposal.member_summary_ids = &.{.{ .ordinal = 9 }},
            3 => proposal.statements = statements[0..1],
            4 => statements[1].claim_ids = statements[0].claim_ids,
            5 => statements[0].claim_ids = &.{.{ .ordinal = 999 }},
            6 => statements[1].local_key = statements[0].local_key,
            7 => statements[0].content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 1 } } },
            8 => statements[1].content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 999 } } },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = proposal } }, fixture.context()));
    }
    var reversed = valid;
    reversed.statements = &.{ valid.statements[1], valid.statements[0] };
    const checked = try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = reversed } }, fixture.context());
    try std.testing.expectEqual(@as(u32, 1), checked.statements[0].local_key);
}

test "closed reconciliation JSON rejects model identities unknown fields union variants and invented resolution" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2));
    for ([_][]const u8{
        "{}",                                                                                                "null",                                                                                                      "[]",                                                                                                                                                                  "{\"global\":{}}",                                                                                                                                                                                                   "{\"global\":{},\"summary\":{}}",
        "{\"kind\":\"global\",\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[],\"conflict_id\":1}", "{\"kind\":\"global\",\"claim_dispositions\":[],\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[]}", "{\"kind\":\"global\",\"claim_dispositions\":[{\"claim_id\":{\"ordinal\":1},\"disposition\":\"resolved\",\"related_claim_ids\":[]}],\"signals\":[],\"conflicts\":[]}", "{\"kind\":\"global\",\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[{\"claim_ids\":[],\"citation_ids\":[],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":[]},\"resolution\":\"source_precedence\"}]}",
    }) |bytes| try std.testing.expectError(error.InvalidReferenceReconciliation, f.parse.execute(a, .{ .input = input, .bytes = bytes }));
}

test "each disposition is total unique current and has a valid terminal relationship" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n", "Third\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const valid = try f.global(a, input);
    for (0..9) |scenario| {
        var proposal = valid;
        const values = try a.dupe(r.ClaimDisposition, valid.claim_dispositions);
        proposal.claim_dispositions = values;
        switch (scenario) {
            0 => proposal.claim_dispositions = values[1..],
            1 => values[1] = values[0],
            2 => values[0].claim_id.ordinal = 999,
            3 => values[0].related_claim_ids = &.{values[1].claim_id},
            4 => values[0].disposition = .duplicate,
            5 => {
                values[0].disposition = .superseded;
                values[0].related_claim_ids = &.{values[0].claim_id};
            },
            6 => {
                values[0].disposition = .duplicate;
                values[0].related_claim_ids = &.{.{ .ordinal = 999 }};
            },
            7 => {
                values[0].disposition = .duplicate;
                values[0].related_claim_ids = &.{values[1].claim_id};
                values[1].disposition = .duplicate;
                values[1].related_claim_ids = &.{values[0].claim_id};
            },
            8 => {
                values[0].disposition = .conflicting;
                values[0].related_claim_ids = &.{values[1].claim_id};
            },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } }));
    }
    for ([_]r.Disposition{ .duplicate, .superseded }) |kind| {
        var proposal = valid;
        const values = try a.dupe(r.ClaimDisposition, valid.claim_dispositions);
        values[0].disposition = kind;
        values[0].related_claim_ids = &.{values[1].claim_id};
        proposal.claim_dispositions = values;
        proposal.signals = valid.signals[1..];
        try std.testing.expectEqual(.complete, (try f.finish(a, input, proposal, fixture.context())).outcome);
    }
    var chain = valid;
    const chained = try a.dupe(r.ClaimDisposition, valid.claim_dispositions);
    chained[0].disposition = .duplicate;
    chained[0].related_claim_ids = &.{chained[1].claim_id};
    chained[1].disposition = .superseded;
    chained[1].related_claim_ids = &.{chained[2].claim_id};
    chain.claim_dispositions = chained;
    chain.signals = valid.signals[2..];
    try std.testing.expectEqual(.complete, (try f.finish(a, input, chain, fixture.context())).outcome);
    chained[1].related_claim_ids = &.{ chained[2].claim_id, chained[2].claim_id };
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, chain, fixture.context()));
}

pub fn conflicting(allocator: std.mem.Allocator, input: r.Input) !r.Proposal {
    var proposal = try f.global(allocator, input);
    const dispositions = try allocator.dupe(r.ClaimDisposition, proposal.claim_dispositions);
    if (dispositions.len != 2) return error.InvalidReferenceReconciliation;
    dispositions[0].disposition = .conflicting;
    dispositions[0].related_claim_ids = try allocator.dupe(r.ClaimId, &.{dispositions[1].claim_id});
    dispositions[1].disposition = .conflicting;
    dispositions[1].related_claim_ids = try allocator.dupe(r.ClaimId, &.{dispositions[0].claim_id});
    proposal.claim_dispositions = dispositions;
    proposal.signals = &.{};
    const citations = try allocator.dupe(r.CitationId, &.{ input.items[0].claim.citation_ids[0], input.items[1].claim.citation_ids[0] });
    const conflicts = try allocator.alloc(r.ConflictProposal, 1);
    conflicts[0] = .{ .claim_ids = input.partition.group.claim_ids, .citation_ids = citations, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The references disagree about the required behavior." } }} }, .resolution = .unresolved };
    proposal.conflicts = conflicts;
    return proposal;
}

test "unresolved conflicts are engine identified and blocking and cannot disappear or leak into signals" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const proposal = try conflicting(a, input);
    const result = try f.finish(a, input, proposal, fixture.context());
    try std.testing.expectEqual(.blocked, result.outcome);
    try std.testing.expectEqual(@as(u32, 1), result.records.conflicts[0].id.ordinal);
    try std.testing.expectEqual(.unresolved, result.records.conflicts[0].value.resolution);
    for (0..5) |scenario| {
        var invalid = proposal;
        const conflicts = try a.dupe(r.ConflictProposal, proposal.conflicts);
        invalid.conflicts = conflicts;
        switch (scenario) {
            0 => invalid.conflicts = &.{},
            1 => invalid.conflicts = &.{ conflicts[0], conflicts[0] },
            2 => conflicts[0].citation_ids = &.{},
            3 => conflicts[0].claim_ids = &.{.{ .ordinal = 999 }},
            4 => invalid.signals = (try f.global(a, input)).signals,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, invalid, fixture.context()));
    }
    var dropped = result.records;
    dropped.conflicts = &.{};
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.account.execute(a, dropped));
}

test "signal projection requires exact citation token kind and retained-claim coverage" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `Hello, World!`.\n"});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const valid = try f.global(a, input);
    for (0..7) |scenario| {
        var proposal = valid;
        const signals = try a.dupe(r.SignalProposal, valid.signals);
        proposal.signals = signals;
        switch (scenario) {
            0 => proposal.signals = signals[0..1],
            1 => signals[0].citation_ids = signals[1].citation_ids,
            2 => signals[0].citation_ids = &.{ signals[0].citation_ids[0], signals[0].citation_ids[0] },
            3 => signals[0].claim_ids = &.{.{ .ordinal = 999 }},
            4 => signals[1].content.preserved_token.token_id.ordinal = 999,
            5 => signals[1].content = signals[0].content,
            6 => proposal.signals = &.{ signals[0], signals[1], signals[0] },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, proposal, fixture.context()));
    }
}

test "scoped reconciliation prose reuses the shared path gate across multiple sources" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n", "Third\n" });
    defer fixture.deinit();
    const items = try f.build_items.execute(a, fixture.inputs, fixture.extracted);
    const context = try @import("domain/reference_reconciliation_validation.zig").scopes(a, items, &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, fixture.context());
    const allowed: r.text.ReferenceSemanticText = .{ .nodes = &.{ .{ .source = .{ .source_id = .{ .ordinal = 1 } } }, .{ .source = .{ .source_id = .{ .ordinal = 2 } } } } };
    _ = try text.validator.referenceIn(a, context, allowed);
    try std.testing.expectError(error.InvalidTypedText, text.validator.referenceIn(a, context, .{ .nodes = &.{.{ .source = .{ .source_id = .{ .ordinal = 3 } } }} }));
    try std.testing.expectError(error.UnboundPathReference, text.validator.referenceIn(a, context, .{ .nodes = &.{.{ .literal = .{ .value = "Read src/main.zig." } }} }));
    try std.testing.expectError(error.InvalidTypedText, text.validator.reference(a, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scope = context.scopes[0] }, allowed));
}

test "empty fully accounted references reconcile without fabricated membership" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{""});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    try std.testing.expectEqual(@as(usize, 0), input.items.len);
    try std.testing.expectEqual(.complete, (try f.finish(a, input, try f.global(a, input), fixture.context())).outcome);
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `exact`.\n"});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    _ = try f.finish(a, input, try f.global(a, input), fixture.context());
}
test "reconciliation releases allocation failures throughout all stages" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "every existing claim kind uses the same reconciliation text and signal contracts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"An independently supported claim.\n"});
    defer fixture.deinit();
    inline for (comptime std.meta.tags(r.extraction.Kind)) |kind| {
        var extracted = fixture.extracted;
        const claims = try a.dupe(r.extraction.Claim, extracted.ledger.claims);
        claims[0].content = .{ .model = @unionInit(r.extraction.Content, @tagName(kind), if (comptime kind == .business or kind == .scope_guard)
            r.text.ValidatedBusinessText{ .value = .{ .segments = &.{.{ .literal = .{ .value = "An independently supported claim." } }} } }
        else
            r.text.ValidatedReferenceSemanticText{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "An independently supported claim." } }} } }) };
        extracted.ledger.claims = claims;
        const input = try f.summaries(a, try f.initialize(a, fixture.inputs, extracted, 2), fixture.context());
        const result = try f.finish(a, input, try f.global(a, input), fixture.context());
        try std.testing.expectEqual(kind, std.meta.activeTag(result.records.signals[0].value.content.model));
    }
}

test "final lineage rejects removed summaries altered membership and changed canonical records" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const proposal = try f.global(a, input);
    for (0..4) |scenario| {
        var altered = input;
        const latest = try a.create(r.SummaryHistory);
        latest.* = input.progress.latest.?.*;
        altered.progress.latest = latest;
        switch (scenario) {
            0 => altered.progress.latest = latest.previous,
            1 => latest.value.member_claim_ids = &.{},
            2 => latest.value.member_summary_ids = &.{},
            3 => latest.value.statements = &.{},
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, altered, proposal, fixture.context()));
    }
    const result = try f.finish(a, input, proposal, fixture.context());
    for (0..5) |scenario| {
        var records = result.records;
        const signals = try a.dupe(r.Signal, records.signals);
        records.signals = signals;
        switch (scenario) {
            0 => records.signals = signals[1..],
            1 => signals[0].id.ordinal += 1,
            2 => signals[0].value.claim_ids = &.{},
            3 => records.assignments.checked.prior.prior.dispositions = &.{},
            4 => {
                const dispositions = try a.dupe(r.ClaimDisposition, records.assignments.checked.prior.prior.dispositions);
                dispositions[0].related_claim_ids = &.{.{ .ordinal = 999 }};
                records.assignments.checked.prior.prior.dispositions = dispositions;
            },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.account.execute(a, records));
    }
}

test "different exact scalars cannot be declared duplicates and token obligations survive supersession" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Use `grey`.\n", "Use `blue`.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try f.global(a, input);
    const dispositions = try a.dupe(r.ClaimDisposition, proposal.claim_dispositions);
    dispositions[1].disposition = .duplicate;
    dispositions[1].related_claim_ids = &.{dispositions[3].claim_id};
    proposal.claim_dispositions = dispositions;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, proposal, fixture.context()));
    dispositions[1].disposition = .superseded;
    // Supersession retains the original token and obligation as provenance.
    try std.testing.expectEqual(.complete, (try f.finish(a, input, proposal, fixture.context())).outcome);
    proposal.signals = &.{ proposal.signals[0], proposal.signals[2], proposal.signals[3] };
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, proposal, fixture.context()));
}

test "shared multi-source scope rejects unrelated passive literals and stale empty context" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n", "Third\n" });
    defer fixture.deinit();
    const items = try f.build_items.execute(a, fixture.inputs, fixture.extracted);
    const context = try @import("domain/reference_reconciliation_validation.zig").scopes(a, items, &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, fixture.context());
    for (fixture.text.registry.occurrences) |occurrence| {
        if (occurrence.origin != .reference_name) continue;
        const candidate: r.text.BusinessText = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = occurrence.id } }} };
        if (occurrence.origin.reference_name.ordinal <= 2) {
            _ = try text.validator.businessIn(a, context, candidate);
        } else try std.testing.expectError(error.InvalidPassiveLiteral, text.validator.businessIn(a, context, candidate));
    }
    const empty = try prepare(a, &.{});
    defer empty.deinit();
    const input = try f.summaries(a, try f.initialize(a, empty.inputs, empty.extracted, 2), empty.context());
    var stale = empty.context();
    stale.inputs.corpus.state_id.bytes = "a-successor-state";
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, try f.global(a, input), stale));
}

test "reference candidate ownership retains predecessors and cleans deep histories iteratively" {
    const owned = @import("domain/reference_candidate_value.zig");
    var current = try owned.create(std.testing.allocator, null);
    defer owned.destroy(current);
    current.payload = .{ .reconciliation_items = .{ .state_id = .{ .bytes = try current.arena.allocator().dupe(u8, "retained-reference-state") }, .entries = &.{} } };
    for (0..4096) |_| {
        const successor = try owned.create(std.testing.allocator, owned.view(current));
        successor.payload = current.payload;
        owned.destroy(current);
        current = successor;
    }
    try std.testing.expectEqualStrings("retained-reference-state", current.payload.reconciliation_items.state_id.bytes);
}

test "overlapping conflicts conserve every declared conflict relationship" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n", "Third\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try f.global(a, input);
    const dispositions = try a.dupe(r.ClaimDisposition, proposal.claim_dispositions);
    for (dispositions) |*value| value.disposition = .conflicting;
    dispositions[0].related_claim_ids = &.{ dispositions[1].claim_id, dispositions[2].claim_id };
    dispositions[1].related_claim_ids = &.{dispositions[0].claim_id};
    dispositions[2].related_claim_ids = &.{dispositions[0].claim_id};
    proposal.claim_dispositions = dispositions;
    proposal.signals = &.{};
    const conflicts = try a.alloc(r.ConflictProposal, 2);
    for (conflicts, 1..) |*conflict, index| {
        conflict.* = .{ .claim_ids = try a.dupe(r.ClaimId, &.{ dispositions[0].claim_id, dispositions[index].claim_id }), .citation_ids = try a.dupe(r.CitationId, &.{ input.items[0].claim.citation_ids[0], input.items[index].claim.citation_ids[0] }), .kind = .scope_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The scopes disagree." } }} }, .resolution = .unresolved };
    }
    proposal.conflicts = conflicts;
    const result = try f.finish(a, input, proposal, fixture.context());
    try std.testing.expectEqual(.blocked, result.outcome);
    try std.testing.expectEqual(@as(usize, 2), result.records.conflicts.len);
    proposal.conflicts = conflicts[0..1];
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, proposal, fixture.context()));
}
