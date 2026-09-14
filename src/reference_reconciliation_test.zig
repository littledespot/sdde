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

test "summary repair changes only a rejected field then inserts missing membership and deletes exact redundancy" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const initial: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const correction: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2));
        const good = try f.summary(a, input);
        try std.testing.expect(good.statements.len >= 2);
        const statements = try a.dupe(r.StatementProposal, good.statements);
        statements[0].claim_ids = &.{.{ .ordinal = 999 }};
        statements[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "source-0.md" } }} } } };
        const parsed: r.Parsed = .{ .source = .{ .origin = initial }, .input = input, .proposal = .{ .summary = .{ .statements = statements } } };
        const rejected = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
        const authorization = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
        const packet = try repair.packet(std.testing.allocator, parsed, fixture.context(), authorization);
        defer @import("domain/model_input_packet.zig").release(packet);
        const replacement: repair.Replacement = .{ .selection = .{ .claim_ids = good.statements[0].claim_ids } };
        const bytes = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
        const selected = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, bytes), correction);
        try std.testing.expectEqualDeep(good.statements[1], selected.proposal.summary.statements[1]);
        const text_rejection = (try f.validate_summary.execute(a, selected, fixture.context())).invalid;
        try std.testing.expectEqual(.typed_text, text_rejection.issue.rule);
        try std.testing.expectEqualDeep(initial, text_rejection.origin.?);
        const text_auth = (try repair.authorize(a, selected, fixture.context(), text_rejection)).model;
        const accepted = try repair.merge(a, selected, fixture.context(), text_auth, .{ .content = good.statements[0].content }, correction);
        _ = (try f.validate_summary.execute(a, accepted, fixture.context())).valid;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, accepted, fixture.context(), text_auth, .{ .content = good.statements[0].content }, correction));
        var changed = parsed;
        changed.proposal.summary.statements = good.statements;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, changed, fixture.context(), rejected));

        const missing: r.Parsed = .{ .input = input, .proposal = .{ .summary = .{ .statements = good.statements[1..] } } };
        const missing_rejection = (try f.validate_summary.execute(a, missing, fixture.context())).invalid;
        const insert = (try repair.authorize(a, missing, fixture.context(), missing_rejection)).model;
        try std.testing.expect(insert.operation == .insert);
        const filled = try repair.merge(a, missing, fixture.context(), insert, .{ .content = good.statements[0].content }, correction);
        _ = (try f.validate_summary.execute(a, filled, fixture.context())).valid;
        try std.testing.expectEqualDeep(missing.proposal.summary.statements[0], filled.proposal.summary.statements[0]);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, filled, fixture.context(), insert, .{ .content = good.statements[0].content }, correction));
        const duplicates = try a.alloc(r.StatementProposal, good.statements.len + 1);
        @memcpy(duplicates[0..good.statements.len], good.statements);
        duplicates[good.statements.len] = good.statements[0];
        const duplicate: r.Parsed = .{ .input = input, .proposal = .{ .summary = .{ .statements = duplicates } } };
        const duplicate_rejection = (try f.validate_summary.execute(a, duplicate, fixture.context())).invalid;
        const deletion = (try repair.authorize(a, duplicate, fixture.context(), duplicate_rejection)).automatic;
        try std.testing.expect(deletion.authorization.operation == .delete);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, duplicate, fixture.context(), deletion.authorization));
        const deduplicated = try repair.merge(a, duplicate, fixture.context(), deletion.authorization, null, null);
        try std.testing.expectEqualDeep(good.statements, deduplicated.proposal.summary.statements);
        _ = (try f.validate_summary.execute(a, deduplicated, fixture.context())).valid;
    }
}

test "global repair retains graph siblings and all dependent signal and conflict checks" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Display `Hello, World!`.\n", "Confirm a library loan.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const good = try f.global(a, input);
    const choices = try a.dupe(r.ClaimDispositionProposal, good.claim_dispositions);
    choices[0].disposition = .{ .duplicate = .{ .target_claim_id = choices[0].claim_id } };
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = .{ .claim_dispositions = choices, .signals = good.signals, .conflicts = good.conflicts } } };
    const rejection = (try f.validate_dispositions.execute(a, parsed)).invalid;
    const authorization = (try repair.authorize(a, parsed, fixture.context(), rejection)).model;
    const merged = try repair.merge(a, parsed, fixture.context(), authorization, .{ .disposition = .{ .retained = .{} } }, null);
    try std.testing.expectEqualDeep(good.claim_dispositions[1..], merged.proposal.global.claim_dispositions[1..]);
    try std.testing.expectEqualDeep(good.signals, merged.proposal.global.signals);
    _ = (try f.finish(a, input, merged.proposal.global, fixture.context())).valid;
    const invalid = try repair.merge(a, parsed, fixture.context(), authorization, .{ .disposition = choices[0].disposition }, null);
    try std.testing.expect((try f.validate_dispositions.execute(a, invalid)) == .invalid);

    var missing = merged;
    missing.proposal.global.signals = good.signals[1..];
    const dispositions = (try f.validate_dispositions.execute(a, missing)).valid;
    const coverage = (try f.validate_signals.execute(a, dispositions, fixture.context())).invalid;
    const insert = (try repair.authorize(a, missing, fixture.context(), coverage)).model;
    const filled = try repair.merge(a, missing, fixture.context(), insert, .{ .content = good.signals[0].content }, null);
    _ = (try f.finish(a, input, filled.proposal.global, fixture.context())).valid;
    try std.testing.expectEqualDeep(good.signals[1..], filled.proposal.global.signals[0 .. filled.proposal.global.signals.len - 1]);

    const duplicate_choices = try a.alloc(r.ClaimDispositionProposal, good.claim_dispositions.len + 1);
    @memcpy(duplicate_choices[0..good.claim_dispositions.len], good.claim_dispositions);
    duplicate_choices[good.claim_dispositions.len] = good.claim_dispositions[0];
    var duplicate = merged;
    duplicate.proposal.global.claim_dispositions = duplicate_choices;
    const duplicate_rejection = (try f.validate_dispositions.execute(a, duplicate)).invalid;
    const remove = (try repair.authorize(a, duplicate, fixture.context(), duplicate_rejection)).automatic;
    const deduplicated = try repair.merge(a, duplicate, fixture.context(), remove.authorization, null, null);
    _ = (try f.finish(a, input, deduplicated.proposal.global, fixture.context())).valid;
    duplicate_choices[good.claim_dispositions.len].disposition = .{ .superseded = .{ .related_claim_ids = &.{good.claim_dispositions[1].claim_id} } };
    const competing = (try f.validate_dispositions.execute(a, duplicate)).invalid;
    try std.testing.expectEqual(.competing_entries, (try repair.authorize(a, duplicate, fixture.context(), competing)).blocked);
}

test "summary signal and conflict repair packets retain precise shared text issues" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } };
    const correction: Origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 2 } };
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{ source, "Retain this independent statement.\n" });
        defer fixture.deinit();
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        for (0..3) |stage| {
            const input = if (stage == 0) try f.build_input.execute(a, progress) else try f.summaries(a, progress, fixture.context());
            for (0..@as(usize, if (stage == 2) 4 else 3)) |fault| {
                const bad_text: r.text.BusinessText = .{ .segments = if (fault == 2)
                    &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 999 } } }}
                else
                    &.{.{ .literal = .{ .value = if (fault == 0) "Display \\\"a result\\\"." else " \t" } }} };
                const bad: r.ContentProposal = .{ .model = .{ .business = bad_text } };
                const good: r.ContentProposal = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Display \"a result\"." } }} } } };
                var parsed: r.Parsed = .{ .input = input, .source = .{ .origin = original }, .proposal = undefined };
                var replacement: repair.Replacement = .{ .content = good };
                if (stage == 0) {
                    var proposal = try f.summary(a, input);
                    const statements = try a.dupe(r.StatementProposal, proposal.statements);
                    statements[0].content = bad;
                    proposal.statements = statements;
                    parsed.proposal = .{ .summary = proposal };
                } else {
                    var proposal = try f.global(a, input);
                    if (stage == 1) {
                        const signals = try a.dupe(r.SignalProposal, proposal.signals);
                        signals[0].content = bad;
                        proposal.signals = signals;
                    } else {
                        const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
                        dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[1].claim_id} } };
                        dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
                        proposal.claim_dispositions = dispositions;
                        proposal.signals = proposal.signals[2..];
                        const nodes: []const r.text.ReferenceNode = switch (fault) {
                            2 => &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 999 } } }},
                            3 => &.{.{ .source = .{ .source_id = .{ .ordinal = 999 } } }},
                            else => &.{.{ .literal = bad_text.segments[0].literal }},
                        };
                        proposal.conflicts = &.{.{ .claim_ids = &.{ dispositions[0].claim_id, dispositions[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = nodes }, .resolution = .unresolved }};
                        replacement = .{ .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The supplied assertions disagree." } }} } };
                    }
                    parsed.proposal = .{ .global = proposal };
                }
                const rejected = (try textRejection(a, parsed, fixture.context())).?;
                try std.testing.expectEqual(.typed_text, rejected.issue.rule);
                const issue = rejected.issue.expected.text_issue;
                try std.testing.expectEqual(([_]@FieldType(r.text.Issue, "reason"){ .unbound_path, .blank, .unknown_passive, .unknown_source })[fault], issue.reason);
                if (fault == 0) try std.testing.expectEqualStrings("\\", issue.path_match.?.lexeme);
                const authorization = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
                const packet = try repair.packet(std.testing.allocator, parsed, fixture.context(), authorization);
                defer packets.release(packet);
                const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
                const rule = body.value.object.get("repair").?.object.get("rule").?.object;
                try std.testing.expectEqualStrings(issue.description(), rule.get("requirement").?.string);
                const projected = try json.decode(r.diagnostic.Fact, a, try std.json.Stringify.valueAlloc(a, rule.get("expected").?, .{}));
                try std.testing.expectEqualDeep(issue, projected.text_issue);
                try std.testing.expect(!rule.contains("dependencies") and !rule.contains("origin"));
                try std.testing.expect(body.value.object.get("input").?.object.get("passive_literals").?.array.items.len > 0);
                try std.testing.expectEqualStrings(if (stage == 2) "repair_summary" else "repair_content", packet.resultDefinition().?.bytes);
                const unchanged = try repair.merge(a, parsed, fixture.context(), authorization, authorization.operation.replace, correction);
                try std.testing.expect(!unchanged.source.last_repair.?.changed);
                try std.testing.expectEqualDeep(correction, (try textRejection(a, unchanged, fixture.context())).?.origin.?);
                const accepted = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, try json.encodeSelected(repair.Replacement, a, replacement)), correction);
                try std.testing.expect(accepted.source.last_repair.?.changed);
                try std.testing.expectEqual(@as(u64, 2), accepted.source.last_repair.?.revision_after);
                try std.testing.expect(try textRejection(a, accepted, fixture.context()) == null);
                if (stage == 0) {
                    try std.testing.expectEqualDeep(parsed.proposal.summary.statements[1..], accepted.proposal.summary.statements[1..]);
                    _ = try f.build_summary.execute(a, try f.assign_summary.execute(a, (try f.validate_summary.execute(a, accepted, fixture.context())).valid));
                } else {
                    try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions, accepted.proposal.global.claim_dispositions);
                    const sibling_start: usize = if (stage == 2) 0 else 1;
                    try std.testing.expectEqualDeep(parsed.proposal.global.signals[sibling_start..], accepted.proposal.global.signals[sibling_start..]);
                    const outcome = (try f.finish(a, input, accepted.proposal.global, fixture.context())).valid.outcome;
                    try std.testing.expectEqual(@as(@TypeOf(outcome), if (stage == 2) .blocked else .complete), outcome);
                }
                var stale = fixture.context();
                stale.inputs.corpus.state_id.bytes = "different-source";
                try std.testing.expectError(error.InvalidReferenceReconciliation, textRejection(a, parsed, stale));
                try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, accepted, fixture.context(), authorization, replacement, correction));
            }
        }
    }
}

fn textRejection(a: std.mem.Allocator, parsed: r.Parsed, ctx: f.Context) !?r.diagnostic.Rejection {
    if (parsed.proposal == .summary) return switch (try f.validate_summary.execute(a, parsed, ctx)) {
        .valid => null,
        .invalid => |issue| issue,
    };
    const dispositions = (try f.validate_dispositions.execute(a, parsed)).valid;
    const signals = switch (try f.validate_signals.execute(a, dispositions, ctx)) {
        .valid => |value| value,
        .invalid => |issue| return issue,
    };
    return switch (try f.validate_conflicts.execute(a, signals, ctx)) {
        .valid => null,
        .invalid => |issue| issue,
    };
}
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

test "canonical citation union preserves selected claim order and overlapping evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First claim.\n", "Second claim.\n" });
    defer fixture.deinit();
    const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    var items = progress.plan.layout.items;
    const entries = try a.dupe(r.Item, items.entries);
    entries[0].claim.citation_ids = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 } };
    entries[1].claim.citation_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 3 } };
    items.entries = entries;
    const Case = struct { claims: []const r.ClaimId, citations: []const r.CitationId };
    for ([_]Case{
        .{ .claims = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, .citations = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 }, .{ .ordinal = 3 } } },
        .{ .claims = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 } }, .citations = &.{ .{ .ordinal = 1 }, .{ .ordinal = 3 }, .{ .ordinal = 2 } } },
        .{ .claims = &.{ .{ .ordinal = 1 }, .{ .ordinal = 1 } }, .citations = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 } } },
        .{ .claims = &.{}, .citations = &.{} },
    }) |case| {
        const citations = try r.citationUnion(std.testing.allocator, items, case.claims);
        defer std.testing.allocator.free(citations);
        try std.testing.expectEqualDeep(case.citations, citations);
    }
    for ([_]u32{ 0, 999 }) |id| try std.testing.expectError(error.InvalidReferenceReconciliation, r.citationUnion(std.testing.allocator, items, &.{.{ .ordinal = id }}));
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
    const result = (try f.finish(a, final, try f.global(a, final), fixture.context())).valid;
    try std.testing.expectEqual(.complete, result.outcome);
    try std.testing.expectEqual(final.items.len, result.records.signals.len);
    try std.testing.expectEqualDeep(result, (try f.finish(a, final, try f.global(a, final), fixture.context())).valid);
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
            0 => proposal.statements = &.{},
            1 => statements[0].claim_ids = &.{ statements[0].claim_ids[0], statements[0].claim_ids[0] },
            2 => statements[0].claim_ids = &.{},
            3 => proposal.statements = statements[0..1],
            4 => statements[1].claim_ids = statements[0].claim_ids,
            5 => statements[0].claim_ids = &.{.{ .ordinal = 999 }},
            6 => statements[1].local_key = statements[0].local_key,
            7 => statements[0].content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 1 } } },
            8 => statements[1].content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 999 } } },
            else => unreachable,
        }
        const rejected = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = proposal } }, fixture.context())).invalid;
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .membership, .claim_selection, .claim_selection, .membership, .content, .claim_selection, .local_key, .content, .content })[scenario], rejected.issue.rule);
    }
    var reversed = valid;
    reversed.statements = &.{ valid.statements[1], valid.statements[0] };
    const checked = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = reversed } }, fixture.context())).valid;
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
        "{}",                                                                            "null",                                                                                  "[]",                                                                                                                                "{\"global\":{}}",                                                                                                                                                           "{\"global\":{},\"summary\":{}}",
        "{\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[],\"conflict_id\":1}", "{\"claim_dispositions\":[],\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[]}", "{\"claim_dispositions\":[{\"claim_id\":{\"ordinal\":1},\"disposition\":{\"kind\":\"resolved\"}}],\"signals\":[],\"conflicts\":[]}", "{\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[{\"claim_ids\":[],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":[]},\"resolution\":\"source_precedence\"}]}",
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
        const values = try a.dupe(r.ClaimDispositionProposal, valid.claim_dispositions);
        proposal.claim_dispositions = values;
        switch (scenario) {
            0 => proposal.claim_dispositions = values[1..],
            1 => values[1] = values[0],
            2 => values[0].claim_id.ordinal = 999,
            3 => values[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{} } },
            4 => values[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{} } },
            5 => {
                values[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{values[0].claim_id} } };
            },
            6 => {
                values[0].disposition = .{ .duplicate = .{ .target_claim_id = .{ .ordinal = 999 } } };
            },
            7 => {
                values[0].disposition = .{ .duplicate = .{ .target_claim_id = values[1].claim_id } };
                values[1].disposition = .{ .duplicate = .{ .target_claim_id = values[0].claim_id } };
            },
            8 => {
                values[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{values[1].claim_id} } };
            },
            else => unreachable,
        }
        const rejected = (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).invalid;
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .cardinality, .duplicate_disposition, .claim_selection, .cardinality, .cardinality, .relationship, .claim_selection, .cycle, .relationship })[scenario], rejected.issue.rule);
    }
    for ([_]r.Disposition{ .duplicate, .superseded }) |kind| {
        var proposal = valid;
        const values = try a.dupe(r.ClaimDispositionProposal, valid.claim_dispositions);
        values[0].disposition = switch (kind) {
            .duplicate => .{ .duplicate = .{ .target_claim_id = values[1].claim_id } },
            .superseded => .{ .superseded = .{ .related_claim_ids = &.{values[1].claim_id} } },
            .retained, .conflicting => unreachable,
        };
        proposal.claim_dispositions = values;
        proposal.signals = valid.signals[1..];
        try std.testing.expectEqual(.complete, ((try f.finish(a, input, proposal, fixture.context())).valid).outcome);
    }
    var chain = valid;
    const chained = try a.dupe(r.ClaimDispositionProposal, valid.claim_dispositions);
    chained[0].disposition = .{ .duplicate = .{ .target_claim_id = chained[1].claim_id } };
    chained[1].disposition = .{ .superseded = .{ .related_claim_ids = &.{chained[2].claim_id} } };
    chain.claim_dispositions = chained;
    chain.signals = valid.signals[2..];
    try std.testing.expectEqual(.complete, ((try f.finish(a, input, chain, fixture.context())).valid).outcome);
    chained[1].disposition.superseded.related_claim_ids = &.{ chained[2].claim_id, chained[2].claim_id };
    try std.testing.expectEqual(.relationship, (try f.finish(a, input, chain, fixture.context())).invalid.issue.rule);
}

pub fn conflicting(allocator: std.mem.Allocator, input: r.Input) !r.Proposal {
    var proposal = try f.global(allocator, input);
    const dispositions = try allocator.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    if (dispositions.len != 2) return error.InvalidReferenceReconciliation;
    dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = try allocator.dupe(r.ClaimId, &.{dispositions[1].claim_id}) } };
    dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = try allocator.dupe(r.ClaimId, &.{dispositions[0].claim_id}) } };
    proposal.claim_dispositions = dispositions;
    proposal.signals = &.{};
    const conflicts = try allocator.alloc(r.ConflictProposal, 1);
    conflicts[0] = .{ .claim_ids = input.partition.group.claim_ids, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The references disagree about the required behavior." } }} }, .resolution = .unresolved };
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
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
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
            2 => conflicts[0].claim_ids = &.{ input.items[0].claim.id, .{ .ordinal = 999 } },
            3 => conflicts[0].claim_ids = &.{.{ .ordinal = 999 }},
            4 => invalid.signals = (try f.global(a, input)).signals,
            else => unreachable,
        }
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .conflict_coverage, .duplicate_conflict, .claim_selection, .cardinality, .relationship })[scenario], (try f.finish(a, input, invalid, fixture.context())).invalid.issue.rule);
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
            1 => signals[0].claim_ids = &.{},
            2 => signals[0].claim_ids = &.{ signals[0].claim_ids[0], signals[0].claim_ids[0] },
            3 => signals[0].claim_ids = &.{.{ .ordinal = 999 }},
            4 => signals[1].content.preserved_token.token_id.ordinal = 999,
            5 => signals[1].content = signals[0].content,
            6 => proposal.signals = &.{ signals[0], signals[1], signals[0] },
            else => unreachable,
        }
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .signal_coverage, .claim_selection, .claim_selection, .claim_selection, .content, .content, .duplicate_signal })[scenario], (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
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
    try std.testing.expectEqual(.complete, ((try f.finish(a, input, try f.global(a, input), fixture.context())).valid).outcome);
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `exact`.\n"});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    _ = (try f.finish(a, input, try f.global(a, input), fixture.context())).valid;
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
        const result = (try f.finish(a, input, try f.global(a, input), fixture.context())).valid;
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
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
    for (0..6) |scenario| {
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
            5 => {
                const progress = &records.assignments.checked.prior.prior.input.progress;
                progress.summary_count = 0;
                progress.latest = null;
                progress.next_statement_ordinal = 1;
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
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    dispositions[1].disposition = .{ .duplicate = .{ .target_claim_id = dispositions[3].claim_id } };
    proposal.claim_dispositions = dispositions;
    try std.testing.expectEqual(.relationship, (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
    dispositions[1].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[3].claim_id} } };
    // Supersession retains the original token and obligation as provenance.
    try std.testing.expectEqual(.complete, ((try f.finish(a, input, proposal, fixture.context())).valid).outcome);
    proposal.signals = &.{ proposal.signals[0], proposal.signals[2], proposal.signals[3] };
    try std.testing.expectEqual(.signal_coverage, (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
    // A model claim cannot duplicate or supersede a preserved-token claim.
    for ([_]r.Disposition{ .duplicate, .superseded }) |kind| {
        dispositions[0].disposition = switch (kind) {
            .duplicate => .{ .duplicate = .{ .target_claim_id = dispositions[1].claim_id } },
            .superseded => .{ .superseded = .{ .related_claim_ids = &.{dispositions[1].claim_id} } },
            .retained, .conflicting => unreachable,
        };
        try std.testing.expectEqual(.same_content_kind, (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).invalid.issue.expected.constraint);
    }
}

test "duplicate and superseded selections cannot terminate in conflicting claims" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm immediately.\n", "Require approval.\n", "Skip approval.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try f.global(a, input);
    const choices = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    proposal.claim_dispositions = choices;
    choices[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{choices[2].claim_id} } };
    choices[2].disposition = .{ .conflicting = .{ .related_claim_ids = &.{choices[1].claim_id} } };
    _ = (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).valid;
    for ([_]r.Disposition{ .duplicate, .superseded }) |kind| {
        choices[0].disposition = switch (kind) {
            .duplicate => .{ .duplicate = .{ .target_claim_id = choices[1].claim_id } },
            .superseded => .{ .superseded = .{ .related_claim_ids = &.{choices[1].claim_id} } },
            .retained, .conflicting => unreachable,
        };
        try std.testing.expectEqual(.nonconflicting_target, (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).invalid.issue.expected.constraint);
    }
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
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    for (dispositions) |*value| value.disposition = .{ .conflicting = .{ .related_claim_ids = &.{} } };
    dispositions[0].disposition.conflicting.related_claim_ids = &.{ dispositions[1].claim_id, dispositions[2].claim_id };
    dispositions[1].disposition.conflicting.related_claim_ids = &.{dispositions[0].claim_id};
    dispositions[2].disposition.conflicting.related_claim_ids = &.{dispositions[0].claim_id};
    proposal.claim_dispositions = dispositions;
    proposal.signals = &.{};
    const conflicts = try a.alloc(r.ConflictProposal, 2);
    for (conflicts, 1..) |*conflict, index| {
        conflict.* = .{ .claim_ids = try a.dupe(r.ClaimId, &.{ dispositions[0].claim_id, dispositions[index].claim_id }), .kind = .scope_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The scopes disagree." } }} }, .resolution = .unresolved };
    }
    proposal.conflicts = conflicts;
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
    try std.testing.expectEqual(.blocked, result.outcome);
    try std.testing.expectEqual(@as(usize, 2), result.records.conflicts.len);
    proposal.conflicts = conflicts[0..1];
    try std.testing.expectEqual(.conflict_coverage, (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
}

test "reconciliation diagnostics retain native facts and origin while stale context remains an error" {
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm the request.\n", "Renew the loan.\n" });
    defer fixture.deinit();
    const initial = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    const summary_input = try f.build_input.execute(a, initial);
    var summary = try f.summary(a, summary_input);
    summary.statements = &.{};
    const summary_bytes = try @import("domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), a, .{ .summary = summary });
    const parsed_summary = try f.parse.execute(a, .{ .input = summary_input, .bytes = summary_bytes, .source = .{ .revision = 3, .origin = origin } });
    const rejected = (try f.validate_summary.execute(a, parsed_summary, fixture.context())).invalid;
    try std.testing.expectEqual(.membership, rejected.issue.rule);
    try std.testing.expectEqualDeep(summary_input.partition.group.claim_ids, rejected.issue.expected.claims);
    try std.testing.expectEqual(@as(usize, 0), rejected.issue.observed.claims.len);
    try std.testing.expectEqual(@as(u64, 3), rejected.revision);
    try std.testing.expectEqualDeep(origin, rejected.origin.?);
    var stale = parsed_summary;
    stale.input.partition.id.ordinal += 1;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_summary.execute(a, stale, fixture.context()));
    const input = try f.summaries(a, initial, fixture.context());
    var proposal = try f.global(a, input);
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    dispositions[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
    proposal.claim_dispositions = dispositions;
    const invalid = (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal }, .source = .{ .origin = origin } })).invalid;
    try std.testing.expectEqual(.no_self_relation, invalid.issue.expected.constraint);
    try std.testing.expectEqualDeep(try dispositions[0].canonical(a), invalid.issue.observed.disposition);
    const packet = try @import("domain/reference_model_input.zig").reconciliationPacket(a, input, fixture.inputs, fixture.text.registry);
    defer @import("domain/model_input_packet.zig").release(packet);
    const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    defer body.deinit();
    const expected = invalid.issue.expected.constraint;
    for (body.value.object.get("constraints").?.array.items) |guidance| {
        if (!std.mem.eql(u8, guidance.object.get("constraint").?.string, @tagName(expected))) continue;
        try std.testing.expectEqualStrings(expected.description(), guidance.object.get("requirement").?.string);
        break;
    } else return error.MissingNativeRuleGuidance;
    const diagnostic: @import("domain/candidate_validation_diagnostic.zig").Diagnostic = .{ .reconciliation = invalid };
    try std.testing.expectEqualDeep(diagnostic, try diagnostic.copy(a));
    var changed = input;
    changed.progress.latest = null;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_dispositions.execute(a, .{ .input = changed, .proposal = .{ .global = proposal } }));
}

test "summary lineage and overlapping signal evidence are constructed from current selections" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm a reservation.\n", "Issue a receipt.\n", "Notify the visitor.\n" });
    defer fixture.deinit();
    var progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    while (progress.summary_count + 1 < progress.plan.partitions.len) {
        const input = try f.build_input.execute(a, progress);
        const checked = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = try f.summary(a, input) } }, fixture.context())).valid;
        progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
        try std.testing.expectEqualDeep(input.partition.group.claim_ids, progress.latest.?.value.member_claim_ids);
        try std.testing.expectEqualDeep(input.member_summary_ids, progress.latest.?.value.member_summary_ids);
    }
    const input = try f.build_input.execute(a, progress);
    var proposal = try f.global(a, input);
    const signals = try a.dupe(r.SignalProposal, proposal.signals[0..2]);
    signals[0].claim_ids = &.{ input.items[1].claim.id, input.items[0].claim.id };
    signals[1].claim_ids = &.{ input.items[1].claim.id, input.items[2].claim.id };
    proposal.signals = signals;
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
    for (result.records.signals, signals) |signal, selected| {
        try std.testing.expectEqualDeep(selected.claim_ids, signal.value.claim_ids);
        try std.testing.expectEqualDeep(try r.citationUnion(a, input.progress.plan.layout.items, selected.claim_ids), signal.value.citation_ids);
    }
    try std.testing.expectEqualDeep(input.items[1].claim.citation_ids[0], result.records.signals[0].value.citation_ids[0]);
    try std.testing.expectEqualDeep(input.items[0].claim.citation_ids[0], result.records.signals[0].value.citation_ids[1]);
}

test "atomic reconciliation insert delete and packet construction release allocation failures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm a reservation.\n", "Issue a receipt.\n", "Notify the visitor.\n" });
    defer fixture.deinit();
    const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    const input = try f.build_input.execute(a, progress);
    const good = try f.summary(a, input);
    var missing = good;
    missing.statements = good.statements[1..];
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .summary = missing } };
    const rejection = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, reconciliationRepairAllocation, .{ parsed, fixture.context(), rejection, good.statements[0].content });
}
fn reconciliationRepairAllocation(allocator: std.mem.Allocator, parsed: r.Parsed, context: f.Context, rejection: r.diagnostic.Rejection, content: r.ContentProposal) !void {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const authorization = (try repair.authorize(a, parsed, context, rejection)).model;
    const packet = try repair.packet(allocator, parsed, context, authorization);
    defer @import("domain/model_input_packet.zig").release(packet);
    const replacement: repair.Replacement = .{ .content = content };
    const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
    const merged = try repair.merge(a, parsed, context, authorization, try repair.parse(a, authorization, packet, wire), null);
    _ = (try f.validate_summary.execute(a, merged, context)).valid;
    const duplicate = try a.alloc(r.StatementProposal, merged.proposal.summary.statements.len + 1);
    @memcpy(duplicate[0 .. duplicate.len - 1], merged.proposal.summary.statements);
    duplicate[duplicate.len - 1] = duplicate[0];
    var redundant = merged;
    redundant.proposal.summary.statements = duplicate;
    const repeated = (try f.validate_summary.execute(a, redundant, context)).invalid;
    const deletion = (try repair.authorize(a, redundant, context, repeated)).automatic;
    const removed = try repair.merge(a, redundant, context, deletion.authorization, null, null);
    _ = (try f.validate_summary.execute(a, removed, context)).valid;
    try std.testing.expectEqualDeep(parsed.proposal.summary.statements, merged.proposal.summary.statements[0..parsed.proposal.summary.statements.len]);
}

test "mixed claim kinds choose independent selection repair across summaries and signals" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        for ([_]bool{ false, true }) |global| {
            const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
            const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
            const business = input.items[0].claim.id;
            const token = input.items[1].claim.id;
            var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try f.global(a, input) } else .{ .summary = try f.summary(a, input) } };
            if (global) {
                const values = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
                values[0].claim_ids = &.{ business, token };
                parsed.proposal.global.signals = values;
            } else {
                const values = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
                values[0].claim_ids = &.{ business, token };
                parsed.proposal.summary.statements = values[0..1]; // token must be inserted after selection repair
            }
            const rejected = if (global) (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).invalid else (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
            try std.testing.expectEqual(.content, rejected.issue.rule);
            try std.testing.expect(rejected.relations.content == null);
            try std.testing.expectEqualDeep(&[_]r.ClaimId{business}, rejected.relations.selection);
            const authorization = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
            try std.testing.expectEqual(@as(usize, 0), if (global) authorization.target.signal_selection else authorization.target.statement_selection);
            const packet = try repair.packet(a, parsed, fixture.context(), authorization);
            defer packets.release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const choices = body.value.object.get("repair").?.object.get("rule").?.object.get("choices").?.object;
            try std.testing.expectEqual(@as(i64, business.ordinal), choices.get("selection").?.array.items[0].object.get("ordinal").?.integer);
            const constraints = body.value.object.get("input").?.object.get("constraints").?.array.items;
            var content_rule = false;
            var token_rule = false;
            for (constraints) |constraint| {
                content_rule = content_rule or std.mem.eql(u8, constraint.object.get("constraint").?.string, "matching_claim_content");
                token_rule = token_rule or std.mem.eql(u8, constraint.object.get("constraint").?.string, "exact_selected_token");
            }
            try std.testing.expect(content_rule and token_rule);
            const wire = try std.fmt.allocPrint(a, "{{\"claim_ids\":[{{\"ordinal\":{d}}}]}}", .{business.ordinal});
            var merged = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, wire), null);
            if (global) {
                try std.testing.expectEqualDeep(parsed.proposal.global.signals[0].content, merged.proposal.global.signals[0].content);
                try std.testing.expectEqualDeep(parsed.proposal.global.signals[1..], merged.proposal.global.signals[1..]);
                try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions, merged.proposal.global.claim_dispositions);
                _ = (try f.finish(a, input, merged.proposal.global, fixture.context())).valid;
            } else {
                const missing = (try f.validate_summary.execute(a, merged, fixture.context())).invalid;
                try std.testing.expectEqual(.membership, missing.issue.rule);
                const insertion = (try repair.authorize(a, merged, fixture.context(), missing)).automatic;
                merged = try repair.merge(a, merged, fixture.context(), insertion.authorization, insertion.replacement, null);
                try std.testing.expectEqualDeep(parsed.proposal.summary.statements[0].content, merged.proposal.summary.statements[0].content);
                _ = (try f.validate_summary.execute(a, merged, fixture.context())).valid;
            }
            // The exact old snapshot remains mandatory even for an equivalent edit.
            try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, merged, fixture.context(), authorization, .{ .selection = .{ .claim_ids = &.{business} } }, null));
            var changed_purpose = parsed;
            changed_purpose.input.purpose = if (global) .summary else .global;
            try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, changed_purpose, fixture.context(), authorization));
            var context = fixture.context();
            const names = try a.dupe(@import("domain/path_token_grammar.zig").ReferenceName, context.registry.grammar.reference_names);
            names[0].basename = "different.md";
            context.registry.grammar.reference_names = names;
            try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, parsed, context, rejected));
            try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, context, authorization));
        }
    }
}

test "projection compatibility handles model kinds and indivisible exact tokens without a solver" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Show `Receipt issued!` and `Renewal accepted!`.\n"});
    defer fixture.deinit();
    for ([_]bool{ false, true }) |global| for (0..5) |scenario| {
        var progress = try f.initialize(a, fixture.inputs, fixture.extracted, 8);
        const entries = try a.dupe(r.Item, progress.plan.layout.items.entries);
        try std.testing.expectEqual(@as(usize, 3), entries.len);
        if (scenario == 1) entries[2].claim.content = .{ .model = .{ .scope_guard = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Eligible loans only." } }} } } } };
        progress.plan.layout.items.entries = entries;
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try f.global(a, input) } else .{ .summary = try f.summary(a, input) } };
        const index: usize = if (scenario == 0 or scenario == 3) 1 else 0;
        const original = if (global) parsed.proposal.global.signals[index] else r.SignalProposal{ .claim_ids = parsed.proposal.summary.statements[index].claim_ids, .content = parsed.proposal.summary.statements[index].content };
        var invalid = original;
        switch (scenario) {
            0 => invalid.claim_ids = &.{ entries[1].claim.id, entries[2].claim.id },
            1 => invalid.claim_ids = &.{ entries[0].claim.id, entries[2].claim.id },
            2 => invalid.content = .{ .model = .{ .scope_guard = .{ .segments = &.{.{ .literal = .{ .value = "Only eligible renewals are allowed." } }} } } },
            3 => invalid.content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 999 } } },
            4 => invalid.content = .{ .preserved_token = .{ .token_id = entries[1].claim.content.preserved_token.value.id } },
            else => unreachable,
        }
        if (global) {
            const values = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
            values[index] = invalid;
            parsed.proposal.global.signals = values;
        } else {
            const values = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
            values[index].claim_ids = invalid.claim_ids;
            values[index].content = invalid.content;
            parsed.proposal.summary.statements = values;
        }
        const rejected = if (global) (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).invalid else (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
        if (scenario == 4) try std.testing.expectEqual(.matching_claim_content, rejected.issue.expected.constraint);
        const auth = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
        if (scenario < 2) {
            try std.testing.expectEqual(index, if (global) auth.target.signal_selection else auth.target.statement_selection);
            try std.testing.expect(rejected.relations.content == null);
        } else {
            try std.testing.expectEqual(index, if (global) auth.target.signal_content else auth.target.statement_content);
            try std.testing.expect(rejected.relations.content != null);
        }
        const merged = try repair.merge(a, parsed, fixture.context(), auth, if (scenario < 2) .{ .selection = .{ .claim_ids = original.claim_ids } } else .{ .content = original.content }, null);
        if (global) _ = (try f.finish(a, input, merged.proposal.global, fixture.context())).valid else _ = (try f.validate_summary.execute(a, merged, fixture.context())).valid;
    };
}

test "empty relationship choices block before model dispatch and genuine conflicts survive canonical deduplication" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Renew the loan.\n", "Reject the renewal.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const good = try f.global(a, input);
    var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = good } };
    parsed.proposal.global.conflicts = &.{.{ .claim_ids = input.partition.group.claim_ids, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "Outcomes differ." } }} }, .resolution = .unresolved }};
    const retained = (try f.validate_dispositions.execute(a, parsed)).valid;
    const rejected_conflict = (try f.validate_conflicts.execute(a, (try f.validate_signals.execute(a, retained, fixture.context())).valid, fixture.context())).invalid;
    try std.testing.expectEqual(@as(usize, 0), rejected_conflict.relations.conflicting_pairs.len);
    try std.testing.expectEqual(.no_independent_target, (try repair.authorize(a, parsed, fixture.context(), rejected_conflict)).blocked);
    const dispositions = try a.dupe(r.ClaimDispositionProposal, good.claim_dispositions);
    dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[1].claim_id} } };
    dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
    parsed.proposal.global.claim_dispositions = dispositions;
    const rejected_signal = (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).invalid;
    try std.testing.expectEqual(@as(usize, 0), rejected_signal.relations.selection.len);
    try std.testing.expectEqual(.no_independent_target, (try repair.authorize(a, parsed, fixture.context(), rejected_signal)).blocked);
    parsed.proposal.global.signals = &.{};
    const conflicts = try a.dupe(r.ConflictProposal, &.{ parsed.proposal.global.conflicts[0], parsed.proposal.global.conflicts[0] });
    conflicts[1].summary = .{ .nodes = &.{ .{ .literal = .{ .value = "Outcomes " } }, .{ .literal = .{ .value = "differ." } } } };
    parsed.proposal.global.conflicts = conflicts;
    const duplicate = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
    const removal = (try repair.authorize(a, parsed, fixture.context(), duplicate)).automatic;
    const merged = try repair.merge(a, parsed, fixture.context(), removal.authorization, null, null);
    try std.testing.expectEqual(.blocked, (try f.finish(a, input, merged.proposal.global, fixture.context())).valid.outcome);
    conflicts[1].summary = .{ .nodes = &.{.{ .literal = .{ .value = "Eligibility differs." } }} };
    const competing = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
    try std.testing.expectEqual(.competing_entries, (try repair.authorize(a, parsed, fixture.context(), competing)).blocked);
}

test "canonical summary and signal redundancy preserves evidence and rejects competing meanings" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm a renewal.\n", "Display a receipt.\n" });
    defer fixture.deinit();
    for ([_]bool{ false, true }) |global| {
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try f.global(a, input) } else .{ .summary = try f.summary(a, input) } };
        const segmented: r.ContentProposal = .{ .model = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "The user can " } }, .{ .literal = .{ .value = "confirm the request." } } } } } };
        if (global) {
            const old = parsed.proposal.global.signals;
            const values = try a.alloc(r.SignalProposal, old.len + 1);
            @memcpy(values[0..old.len], old);
            values[old.len] = old[0];
            values[old.len].content = segmented;
            parsed.proposal.global.signals = values;
        } else {
            const old = parsed.proposal.summary.statements;
            const values = try a.alloc(r.StatementProposal, old.len + 1);
            @memcpy(values[0..old.len], old);
            values[old.len] = old[0];
            values[old.len].local_key = @intCast(old.len + 1);
            values[old.len].content = segmented;
            parsed.proposal.summary.statements = values;
        }
        const rejected = if (global) (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid else (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
        const removal = (try repair.authorize(a, parsed, fixture.context(), rejected)).automatic;
        const merged = try repair.merge(a, parsed, fixture.context(), removal.authorization, null, null);
        if (global) _ = (try f.finish(a, input, merged.proposal.global, fixture.context())).valid else _ = (try f.validate_summary.execute(a, merged, fixture.context())).valid;
        if (global) {
            const values = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
            values[values.len - 1].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different supported meaning." } }} } } };
            parsed.proposal.global.signals = values;
            const competing = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
            try std.testing.expectEqual(.competing_entries, (try repair.authorize(a, parsed, fixture.context(), competing)).blocked);
        }
    }
}
