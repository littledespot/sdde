const std = @import("std");
const reference = @import("domain/reference_ingestion.zig");
const evidence = @import("domain/reference_evidence.zig");
const assign = @import("actions/reference/assign_reference_identities.zig");
const build = @import("actions/reference/build_reference_chunks.zig");
const validate = @import("actions/reference/validate_reference_chunks.zig");
const cite = @import("actions/reference/validate_source_citations.zig");
const read = @import("reference_ingestion_test.zig").read;
const feature: @import("domain/feature_identity.zig").FeatureId = .{ .bytes = "Chosen/Café" };

pub const IdSource = struct {
    calls: u8 = 0,
    fail: bool = false,
    fn port(self: *IdSource) @import("ports/reference_state_identity.zig").Source {
        return .{ .context = self, .next_fn = next };
    }
    fn next(context: *anyopaque) @import("ports/reference_state_identity.zig").Error![16]u8 {
        const self: *IdSource = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.fail) return error.IdentityUnavailable;
        return @splat(self.calls);
    }
};
pub fn prepare(allocator: std.mem.Allocator, source: *IdSource, inputs: reference.Inputs) !evidence.Inputs {
    const corpus = try (assign.Action{ .identities = source.port() }).execute(allocator, inputs, feature);
    const chunks = try (build.Action{}).execute(allocator, corpus);
    return (validate.Action{}).execute(allocator, inputs, feature, corpus, chunks);
}
fn proposals(inputs: evidence.Inputs, index: usize) evidence.CitationProposals {
    return .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[index].id }, .entries = &.{} };
}
fn proposal(chunk: evidence.Chunk) evidence.CitationProposal {
    return .{ .source_id = chunk.source_id, .block_id = chunk.block_id, .location = chunk.span, .verbatim = null };
}

test "source selections preserve original line endings Unicode repeated text and discontiguous evidence" {
    const selections = @import("domain/source_selections.zig");
    for ([_][]const u8{
        "Hello, World!\n",
        "Café\r\n日本語\r\n",
        "Cafe\u{301}\rrepeated\rrepeated",
        "| key | value |\n| a | b |\n",
        "```\ncode\n```\n",
        "no final newline",
        "é" ** 12000 ++ "\r\nA final line.\n",
    }) |bytes| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var ids: IdSource = .{};
        const inputs = try prepare(a, &ids, try read(a, "evidence.md", bytes));
        try std.testing.expectEqual(@as(u8, 1), ids.calls);
        try std.testing.expectEqualStrings(feature.bytes, inputs.corpus.feature_id.bytes);
        var reconstructed: std.ArrayList(u8) = .empty;
        var end: usize = 0;
        for (inputs.chunks.entries, 0..) |chunk, index| {
            const scope = proposals(inputs, index).scope;
            const view = try evidence.resolve(inputs, scope);
            try std.testing.expectEqual(end, chunk.span.start.byte);
            try std.testing.expectEqualSlices(u8, bytes[chunk.span.start.byte..chunk.span.end.byte], view.bytes);
            const choices = try selections.project(a, inputs, scope);
            for (choices) |choice| {
                try reconstructed.appendSlice(a, choice.text);
                const result = try selections.validate(a, inputs, scope, &.{.{ .first = choice.id, .last = choice.id }});
                try std.testing.expectEqualStrings(choice.text, result.valid.entries[0].verbatim.?);
            }
            const whole = try selections.validate(a, inputs, scope, &.{.{ .first = choices[0].id, .last = choices[choices.len - 1].id }});
            try std.testing.expectEqualStrings(bytes[chunk.span.start.byte..chunk.span.end.byte], whole.valid.entries[0].verbatim.?);
            try std.testing.expectEqualDeep(chunk.span, whole.valid.entries[0].location);
            const separate = try selections.validate(a, inputs, scope, &.{ .{ .first = choices[0].id, .last = choices[0].id }, .{ .first = choices[choices.len - 1].id, .last = choices[choices.len - 1].id } });
            try std.testing.expectEqual(@as(usize, 2), separate.valid.entries.len);
            try std.testing.expectEqualStrings(choices[choices.len - 1].text, separate.valid.entries[1].verbatim.?);
            end = chunk.span.end.byte;
        }
        try std.testing.expectEqual(bytes.len, end);
        try std.testing.expectEqualStrings(bytes, reconstructed.items);
    }
}

test "source selection diagnostics distinguish missing unknown reversed and stale scope" {
    const selections = @import("domain/source_selections.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: IdSource = .{};
    const inputs = try prepare(a, &ids, try read(a, "shipping.md", "Accept shipments.\nReject expired permits.\n"));
    const scope = proposals(inputs, 0).scope;
    try std.testing.expectEqual(.missing_selection, (try selections.validate(a, inputs, scope, &.{})).invalid.reason);
    const valid: selections.Selection = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 2 } };
    for ([_]u32{ 0, 3, std.math.maxInt(u32) }) |ordinal| {
        var invalid = valid;
        invalid.last.ordinal = ordinal;
        const result = (try selections.validate(a, inputs, scope, &.{ valid, invalid })).invalid;
        try std.testing.expectEqual(.unknown_selection, result.reason);
        try std.testing.expectEqual(@as(usize, 1), result.index);
        try std.testing.expectEqualDeep(invalid, result.rejected.?);
        try std.testing.expectEqualDeep(valid, result.available);
    }
    try std.testing.expectEqual(.reversed_selection, (try selections.validate(a, inputs, scope, &.{.{ .first = .{ .ordinal = 2 }, .last = .{ .ordinal = 1 } }})).invalid.reason);
    var foreign = scope;
    foreign.state_id.bytes = "foreign";
    try std.testing.expectError(error.InvalidSourceCitation, selections.validate(a, inputs, foreign, &.{valid}));
    foreign = scope;
    foreign.chunk_id.bytes = "foreign";
    try std.testing.expectError(error.InvalidSourceCitation, selections.project(a, inputs, foreign));
}

test "global source block identities and total mappings are independent of provisional ordinals" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const a = try read(allocator, "a.md", "alpha\n");
    const b = try read(allocator, "b.md", "beta\n");
    var second = b.documents[0];
    second.source.ordinal = 3; // Directory entries can intervene in the inventory.
    var second_block = second.blocks[0];
    second_block.id.source = second.source;
    second.blocks = &.{second_block};
    var input = a;
    input.documents = &.{ a.documents[0], second };
    var ids: IdSource = .{};
    const result = try prepare(allocator, &ids, input);
    try std.testing.expectEqual(@as(u32, 2), result.corpus.sources[1].id.ordinal);
    try std.testing.expectEqual(@as(u32, 3), result.corpus.source_mappings[1].provisional.ordinal);
    try std.testing.expectEqual(@as(u32, 2), result.corpus.sources[1].blocks[0].id.ordinal);
    try std.testing.expectEqualStrings("chunk-2", result.chunks.entries[1].id.bytes);
    var batch = proposals(result, 0);
    batch.entries = &.{proposal(result.chunks.entries[1])};
    try std.testing.expectError(error.InvalidSourceCitation, (cite.Action{}).execute(allocator, result, batch));
    var reordered_sources = result.corpus;
    reordered_sources.sources = &.{ result.corpus.sources[1], result.corpus.sources[0] };
    try std.testing.expectError(error.InvalidReferenceChunks, (validate.Action{}).execute(allocator, input, feature, reordered_sources, result.chunks));
    var reordered_chunks = result.chunks;
    reordered_chunks.entries = &.{ result.chunks.entries[1], result.chunks.entries[0] };
    try std.testing.expectError(error.InvalidReferenceChunks, (validate.Action{}).execute(allocator, input, feature, result.corpus, reordered_chunks));
}

test "reference scopes reject stale runs unknown chunks and identity-source failure" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: IdSource = .{};
    const source = try read(allocator, "notes.md", "unchanged\n");
    const first = try prepare(allocator, &ids, source);
    const second = try prepare(allocator, &ids, source);
    try std.testing.expect(!first.corpus.state_id.eql(second.corpus.state_id));
    try std.testing.expect(first.chunks.entries[0].id.eql(second.chunks.entries[0].id));
    var batch = proposals(first, 0);
    batch.entries = &.{proposal(first.chunks.entries[0])};
    try std.testing.expectError(error.InvalidSourceCitation, (cite.Action{}).execute(allocator, second, batch));
    batch.scope.state_id = second.corpus.state_id;
    batch.scope.chunk_id = .{ .bytes = "unknown" };
    try std.testing.expectError(error.InvalidSourceCitation, (cite.Action{}).execute(allocator, second, batch));
    ids.fail = true;
    try std.testing.expectError(error.IdentityUnavailable, prepare(allocator, &ids, source));
}

test "citation proof preserves Unicode decomposed scalars BOM and CRLF exactly" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const bytes = "\xef\xbb\xbfCafe\u{301}\r\n日本語\n";
    var ids: IdSource = .{};
    const input = try prepare(allocator, &ids, try read(allocator, "Café.md", bytes));
    var batch = proposals(input, 0);
    const valid: evidence.CitationProposal = .{
        .source_id = input.chunks.entries[0].source_id,
        .block_id = input.chunks.entries[0].block_id,
        .location = .{ .start = .{ .byte = 3, .line = 1, .column = 2 }, .end = .{ .byte = 9, .line = 1, .column = 7 } },
        .verbatim = "Cafe\u{301}",
    };
    batch.entries = &.{valid};
    const result = try (cite.Action{}).execute(allocator, input, batch);
    try std.testing.expectEqualSlices(u8, "Cafe\u{301}", result.entries[0].verbatim.?);
    try std.testing.expect(result.entries[0].verbatim.?.ptr == input.corpus.sources[0].bytes[3..].ptr);
    for ([_]enum { normalized, byte_split, column, crlf_split, out_of_range, empty, source, block }{
        .normalized, .byte_split, .column, .crlf_split, .out_of_range, .empty, .source, .block,
    }) |fault| {
        var bad = valid;
        switch (fault) {
            .normalized => bad.verbatim = "Café",
            .byte_split => bad.location.end.byte = 8,
            .column => bad.location.end.column += 1,
            .crlf_split => {
                bad.location.end = .{ .byte = 10, .line = 2, .column = 1 };
                bad.verbatim = null;
            },
            .out_of_range => bad.location.end.byte = bytes.len + 1,
            .empty => bad.location.end = bad.location.start,
            .source => bad.source_id.ordinal = 0,
            .block => bad.block_id.ordinal += 1,
        }
        batch.entries = &.{bad};
        try std.testing.expectError(error.InvalidSourceCitation, (cite.Action{}).execute(allocator, input, batch));
    }
}

test "a real citation in a sibling chunk is not authorized by the supplied chunk" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var body: std.Io.Writer.Allocating = .init(allocator);
    for (0..130) |_| try body.writer.writeAll("other requirement\n");
    var ids: IdSource = .{};
    const input = try prepare(allocator, &ids, try read(allocator, "long.md", body.written()));
    try std.testing.expect(input.chunks.entries.len > 1);
    var batch = proposals(input, 0);
    batch.entries = &.{proposal(input.chunks.entries[1])};
    try std.testing.expectError(error.InvalidSourceCitation, (cite.Action{}).execute(allocator, input, batch));
    var forged = proposal(input.chunks.entries[0]);
    forged.location.end = input.chunks.entries[1].span.end;
    batch.entries = &.{forged};
    try std.testing.expectError(error.InvalidSourceCitation, (cite.Action{}).execute(allocator, input, batch));
}

test "citable input validation rejects incomplete duplicate reordered and forged mappings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: IdSource = .{};
    const raw = try read(allocator, "notes.md", "original\n");
    const inputs = try prepare(allocator, &ids, raw);
    for ([_]enum { missing, duplicate, state, ordinal, range, bytes, source_map, block_map, feature }{
        .missing, .duplicate, .state, .ordinal, .range, .bytes, .source_map, .block_map, .feature,
    }) |fault| {
        var corpus = inputs.corpus;
        var chunks = inputs.chunks;
        var chunk = chunks.entries[0];
        switch (fault) {
            .missing => chunks.entries = &.{},
            .duplicate => chunks.entries = &.{ chunk, chunk },
            .state => chunks.state_id = .{ .bytes = "foreign" },
            .ordinal => {
                chunk.id = .{ .bytes = "chunk-2" };
                chunks.entries = &.{chunk};
            },
            .range => {
                chunk.span.end.byte -= 1;
                chunks.entries = &.{chunk};
            },
            .bytes => {
                var source = corpus.sources[0];
                source.bytes = "changed!\n";
                corpus.sources = try allocator.dupe(evidence.Source, &.{source});
            },
            .source_map => corpus.source_mappings = &.{},
            .block_map => corpus.block_mappings = &.{},
            .feature => corpus.feature_id = .{ .bytes = "Other" },
        }
        try std.testing.expectError(error.InvalidReferenceChunks, (validate.Action{}).execute(allocator, raw, feature, corpus, chunks));
    }
}

test "empty source is accounted but cannot provide a fabricated citation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var ids: IdSource = .{};
    const input = try prepare(arena.allocator(), &ids, try read(arena.allocator(), "empty.md", ""));
    try std.testing.expectEqual(@as(usize, 1), input.corpus.sources.len);
    try std.testing.expectEqual(@as(usize, 0), input.chunks.entries.len);
    try std.testing.expectError(error.InvalidSourceCitation, evidence.resolve(input, .{ .state_id = input.corpus.state_id, .chunk_id = .{ .bytes = "chunk-1" } }));
}

test "reference evidence and citation preparation clean up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(backing: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(backing);
    defer arena.deinit();
    var ids: IdSource = .{};
    const input = try prepare(arena.allocator(), &ids, try read(arena.allocator(), "日本語.md", "# α\r\n"));
    var batch = proposals(input, 0);
    batch.entries = &.{proposal(input.chunks.entries[0])};
    _ = try (cite.Action{}).execute(arena.allocator(), input, batch);
}

const partition = @import("domain/reference_chunk_partition.zig");

/// One expected chunk: its exact source bytes and the lead-in lines it carries.
const Expected = struct { text: []const u8, lead_in: []const []const u8 = &.{} };

fn expectChunks(a: std.mem.Allocator, bytes: []const u8, expected: []const Expected) !void {
    var ids: IdSource = .{};
    const inputs = try prepare(a, &ids, try read(a, "requirements.md", bytes));
    try std.testing.expectEqual(partition.id, inputs.chunks.partition);
    try std.testing.expectEqual(expected.len, inputs.chunks.entries.len);
    var end: usize = 0;
    for (inputs.chunks.entries, expected, 1..) |chunk, wanted, ordinal| {
        // Chunks tile the source in order and never cross their block.
        try std.testing.expectEqual(end, chunk.span.start.byte);
        const block = inputs.corpus.sources[0].blocks[chunk.block_id.ordinal - 1];
        try std.testing.expect(chunk.span.start.byte >= block.span.start.byte and chunk.span.end.byte <= block.span.end.byte);
        var id_buffer: [32]u8 = undefined;
        try std.testing.expect(chunk.id.eql(evidence.identity.formatChunkId(&id_buffer, @intCast(ordinal))));
        try std.testing.expectEqualStrings(wanted.text, bytes[chunk.span.start.byte..chunk.span.end.byte]);
        try std.testing.expectEqual(wanted.lead_in.len, chunk.lead_in.len);
        for (wanted.lead_in, chunk.lead_in) |text, span| {
            try std.testing.expectEqualStrings(text, std.mem.trimEnd(u8, bytes[span.start.byte..span.end.byte], "\r\n"));
            try std.testing.expect(span.end.byte <= chunk.span.start.byte);
        }
        end = chunk.span.end.byte;
    }
    try std.testing.expectEqual(bytes.len, end);
    // Exact-value spans stay inside one chunk, so token extraction still binds.
    _ = try @import("domain/structured_tokens.zig").extract(a, inputs);
}

test "top-level list items become chunks carrying their heading and lead-in paragraph" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A flat requirements list under headings, the shape of both development cases.
    try expectChunks(a, "# Hello World Application\n\n## Requirements\n\n- The application must start.\n- Display `Hello, World!`.\n- Output the UTC time\n", &.{
        .{ .text = "# Hello World Application\n\n## Requirements\n\n" },
        .{ .text = "- The application must start.\n", .lead_in = &.{"## Requirements"} },
        .{ .text = "- Display `Hello, World!`.\n", .lead_in = &.{"## Requirements"} },
        .{ .text = "- Output the UTC time\n", .lead_in = &.{"## Requirements"} },
    });
    // An ordered list keeps the condition its lead-in paragraph states.
    try expectChunks(a, "# Loans\n\nWhen a loan is overdue:\n\n1. Send a reminder.\n2) Add a late fee.\n", &.{
        .{ .text = "# Loans\n\nWhen a loan is overdue:\n\n" },
        .{ .text = "1. Send a reminder.\n", .lead_in = &.{ "# Loans", "When a loan is overdue:" } },
        .{ .text = "2) Add a late fee.\n", .lead_in = &.{ "# Loans", "When a loan is overdue:" } },
    });
    // Nested items, continuation and lazy continuation stay with their parent.
    try expectChunks(a, "- Refuse renewal when:\n  - the loan is inactive\n  - it was renewed\n  and keep the due date\nlazily continued\n- Display `Renewal refused.`\n", &.{
        .{ .text = "- Refuse renewal when:\n  - the loan is inactive\n  - it was renewed\n  and keep the due date\nlazily continued\n" },
        .{ .text = "- Display `Renewal refused.`\n" },
    });
    // An outdented paragraph after a blank line ends the list and introduces the next one.
    try expectChunks(a, "- First.\n\nThen, for staff:\n- Second.\n", &.{
        .{ .text = "- First.\n\n" },
        .{ .text = "Then, for staff:\n" },
        .{ .text = "- Second.\n", .lead_in = &.{"Then, for staff:"} },
    });
    // Fenced code is opaque, inside or outside a list, and never starts a chunk.
    try expectChunks(a, "```\n- not an item\n```\n- Item with code:\n  ```\n  - still code\n  ```\n- Next item.\n", &.{
        .{ .text = "```\n- not an item\n```\n" },
        .{ .text = "- Item with code:\n  ```\n  - still code\n  ```\n" },
        .{ .text = "- Next item.\n" },
    });
    // Thematic breaks and headings end a list; "* * *" is not a bullet. A break
    // that ends a list stays with its last item instead of costing a chunk.
    try expectChunks(a, "* * *\n- A.\n---\n- B.\n## Later\n- C.\n", &.{
        .{ .text = "* * *\n" },
        .{ .text = "- A.\n---\n" },
        .{ .text = "- B.\n" },
        .{ .text = "## Later\n" },
        .{ .text = "- C.\n", .lead_in = &.{"## Later"} },
    });
    // CRLF sources keep their line endings; prose without a list is one chunk.
    try expectChunks(a, "## R\r\n\r\n- A.\r\n- B.\r\n", &.{
        .{ .text = "## R\r\n\r\n" },
        .{ .text = "- A.\r\n", .lead_in = &.{"## R"} },
        .{ .text = "- B.\r\n", .lead_in = &.{"## R"} },
    });
    try expectChunks(a, "A borrower can renew a loan once.\nRenewal extends the due date.\n", &.{
        .{ .text = "A borrower can renew a loan once.\nRenewal extends the due date.\n" },
    });
}

test "list boundaries respect exact values, fences, tabs, setext headings and paragraph interruption" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A lead-in with an exact value keeps its list whole, so the value's
    // native duty stays within one chunk (ADR 0024).
    try expectChunks(a, "## Flags\n\nWhen `--force` is set:\n\n- Delete the cache.\n- Skip confirmation.\n", &.{
        .{ .text = "## Flags\n\nWhen `--force` is set:\n\n- Delete the cache.\n- Skip confirmation.\n" },
    });
    try expectChunks(a, "## The `renew` command\n\n- Renews a loan.\n- Extends the due date.\n", &.{
        .{ .text = "## The `renew` command\n\n- Renews a loan.\n- Extends the due date.\n" },
    });
    // A fence after a list ends it, and a fence can open an item.
    try expectChunks(a, "- A.\n- B.\n\n```sh\nmake\n```\n\nProse.\n", &.{
        .{ .text = "- A.\n" },
        .{ .text = "- B.\n\n" },
        .{ .text = "```sh\nmake\n```\n\nProse.\n" },
    });
    try expectChunks(a, "- A.\n- ```\n  x\n  ```\n- C.\n", &.{
        .{ .text = "- A.\n" },
        .{ .text = "- ```\n  x\n  ```\n" },
        .{ .text = "- C.\n" },
    });
    // A tab reaches the next four-column stop, so it continues the item.
    try expectChunks(a, "1. Step one.\n\n\tMore detail.\n\n2. Step two.\n", &.{
        .{ .text = "1. Step one.\n\n\tMore detail.\n\n" },
        .{ .text = "2. Step two.\n" },
    });
    // A setext heading is the nearest heading.
    try expectChunks(a, "# Guide\n\nRenewal\n-------\n\nWhen overdue:\n\n- Send a reminder.\n", &.{
        .{ .text = "# Guide\n\nRenewal\n-------\n\nWhen overdue:\n\n" },
        .{ .text = "- Send a reminder.\n", .lead_in = &.{ "Renewal\n-------", "When overdue:" } },
    });
    // Only a bullet or a list starting at 1 interrupts a paragraph.
    try expectChunks(a, "The policy was approved in\n2024. Borrowers must renew online.\n", &.{
        .{ .text = "The policy was approved in\n2024. Borrowers must renew online.\n" },
    });
    try expectChunks(a, "Steps:\n1. Renew.\n2. Pay.\n", &.{
        .{ .text = "Steps:\n" },
        .{ .text = "1. Renew.\n", .lead_in = &.{"Steps:"} },
        .{ .text = "2. Pay.\n", .lead_in = &.{"Steps:"} },
    });
    // A line that starts inside a multi-line inline span never starts a chunk.
    try expectChunks(a, "- A `x\n- y` z\n- B.\n", &.{
        .{ .text = "- A `x\n- y` z\n" },
        .{ .text = "- B.\n" },
    });
    // A column-0 fence ends a list even without a blank line, so the paragraph
    // after it introduces the next list; a heading nested in an item stays.
    try expectChunks(a, "- A.\n```\ncode\n```\nWhen overdue:\n- B.\n", &.{
        .{ .text = "- A.\n" },
        .{ .text = "```\ncode\n```\nWhen overdue:\n" },
        .{ .text = "- B.\n", .lead_in = &.{"When overdue:"} },
    });
    try expectChunks(a, "- Renewal\n  ## Limits\n  At most twice.\n- Returns\n", &.{
        .{ .text = "- Renewal\n  ## Limits\n  At most twice.\n" },
        .{ .text = "- Returns\n" },
    });
    // A separator that ends a list stays with its item; the text after it is a
    // chunk of its own.
    try expectChunks(a, "- A.\n---\nClosing note.\n", &.{
        .{ .text = "- A.\n---\n" },
        .{ .text = "Closing note.\n" },
    });
    // An exact value outside the lead-in still lets the list split; one in a
    // setext heading keeps it whole, also when a separator ends it.
    try expectChunks(a, "Run `renew` first.\n\n## Steps\n\n- A.\n- B.\n", &.{
        .{ .text = "Run `renew` first.\n\n## Steps\n\n" },
        .{ .text = "- A.\n", .lead_in = &.{"## Steps"} },
        .{ .text = "- B.\n", .lead_in = &.{"## Steps"} },
    });
    try expectChunks(a, "The `renew` tool\n================\n\n- A.\n- B.\n***\nAfter.\n", &.{
        .{ .text = "The `renew` tool\n================\n\n- A.\n- B.\n***\nAfter.\n" },
    });
    // CR-only line endings split like LF.
    try expectChunks(a, "## R\r\r- A.\r- B.\r", &.{
        .{ .text = "## R\r\r" },
        .{ .text = "- A.\r", .lead_in = &.{"## R"} },
        .{ .text = "- B.\r", .lead_in = &.{"## R"} },
    });
}

test "an item longer than one reader block is clipped at the block boundary" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const long = try a.alloc(u8, reference.limits.block_bytes + 512);
    @memset(long, 'x');
    const bytes = try std.mem.concat(a, u8, &.{ "## R\n\n- ", long, "\n- B.\n" });
    var ids: IdSource = .{};
    const inputs = try prepare(a, &ids, try read(a, "requirements.md", bytes));
    try std.testing.expect(inputs.corpus.sources[0].blocks.len >= 2);
    var end: usize = 0;
    var mid_line = false;
    for (inputs.chunks.entries) |chunk| {
        try std.testing.expectEqual(end, chunk.span.start.byte);
        const block = inputs.corpus.sources[0].blocks[chunk.block_id.ordinal - 1];
        try std.testing.expect(chunk.span.start.byte >= block.span.start.byte and chunk.span.end.byte <= block.span.end.byte);
        mid_line = mid_line or chunk.span.start.column != 1;
        end = chunk.span.end.byte;
    }
    try std.testing.expectEqual(bytes.len, end);
    try std.testing.expect(mid_line);
    // Both parts of the clipped item, and the next item, carry the item's lead-in.
    for (inputs.chunks.entries[1..]) |chunk| try std.testing.expectEqual(@as(usize, 1), chunk.lead_in.len);
}

test "a list longer than one reader block keeps every item whole and in order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var bytes: std.ArrayList(u8) = .empty;
    try bytes.appendSlice(a, "## Requirements\n\n");
    for (0..80) |index| try bytes.print(a, "- Requirement {d}.\n", .{index + 1});
    var ids: IdSource = .{};
    const inputs = try prepare(a, &ids, try read(a, "requirements.md", bytes.items));
    try std.testing.expect(inputs.corpus.sources[0].blocks.len > 1);
    try std.testing.expectEqual(@as(usize, 81), inputs.chunks.entries.len);
    var ordinal_in_block: u32 = 0;
    var block: u32 = 0;
    for (inputs.chunks.entries[1..], 1..) |chunk, index| {
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "- Requirement {d}.\n", .{index}), bytes.items[chunk.span.start.byte..chunk.span.end.byte]);
        try std.testing.expectEqual(@as(usize, 1), chunk.lead_in.len);
        if (chunk.block_id.ordinal != block) {
            block = chunk.block_id.ordinal;
            ordinal_in_block = if (block == 1) 1 else 0;
        }
        ordinal_in_block += 1;
        try std.testing.expectEqual(ordinal_in_block, chunk.ordinal);
    }
}

test "chunks that are not the canonical partition are rejected" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = try read(a, "requirements.md", "## Requirements\n\n- Renew a loan.\n- Show the due date.\n");
    var ids: IdSource = .{};
    const inputs = try prepare(a, &ids, raw);
    try std.testing.expectEqual(@as(usize, 3), inputs.chunks.entries.len);
    const Fault = enum { merged_items, shifted_boundary, missing_lead_in, foreign_lead_in, ordinal, reordered };
    for (std.enums.values(Fault)) |fault| {
        var chunks = inputs.chunks;
        const entries = try a.dupe(evidence.Chunk, inputs.chunks.entries);
        switch (fault) {
            // One chunk per block, as the superseded partition built it.
            .merged_items => {
                var whole = entries[0];
                whole.span.end = entries[2].span.end;
                chunks.entries = &.{whole};
            },
            .shifted_boundary => {
                entries[1].span.end.byte -= 1;
                entries[2].span.start.byte -= 1;
                chunks.entries = entries;
            },
            .missing_lead_in => {
                entries[1].lead_in = &.{};
                chunks.entries = entries;
            },
            .foreign_lead_in => {
                entries[2].lead_in = &.{entries[1].span};
                chunks.entries = entries;
            },
            .ordinal => {
                entries[2].ordinal = 1;
                chunks.entries = entries;
            },
            .reordered => {
                std.mem.swap(evidence.Chunk, &entries[1], &entries[2]);
                chunks.entries = entries;
            },
        }
        try std.testing.expectError(error.InvalidReferenceChunks, partition.validate(a, inputs.corpus, chunks));
        try std.testing.expectError(error.InvalidReferenceChunks, (validate.Action{}).execute(a, raw, feature, inputs.corpus, chunks));
    }
    try partition.validate(a, inputs.corpus, inputs.chunks);
}
