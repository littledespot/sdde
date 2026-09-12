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
    return (validate.Action{}).execute(inputs, feature, corpus, chunks);
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
        var reconstructed: std.ArrayList(u8) = .empty;
        for (inputs.chunks.entries, 0..) |chunk, index| {
            const scope = proposals(inputs, index).scope;
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
        }
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

test "Hello World references receive citable identities with exact chunk coverage" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/e2e/wf-001-hello-world/reference/stories.md", allocator, .limited(reference.limits.source_file_bytes));
    var ids: IdSource = .{};
    const inputs = try prepare(allocator, &ids, try read(allocator, "stories.md", bytes));
    try std.testing.expectEqual(@as(u8, 1), ids.calls);
    try std.testing.expectEqualStrings(feature.bytes, inputs.corpus.feature_id.bytes);
    var end: usize = 0;
    for (inputs.chunks.entries, 0..) |chunk, index| {
        const view = try evidence.resolve(inputs, proposals(inputs, index).scope);
        try std.testing.expectEqual(end, chunk.span.start.byte);
        try std.testing.expectEqualSlices(u8, bytes[chunk.span.start.byte..chunk.span.end.byte], view.bytes);
        var batch = proposals(inputs, index);
        var candidate = proposal(chunk);
        candidate.verbatim = view.bytes;
        batch.entries = &.{candidate};
        const citations = try (cite.Action{}).execute(allocator, inputs, batch);
        try std.testing.expectEqualSlices(u8, view.bytes, citations.entries[0].verbatim.?);
        end = chunk.span.end.byte;
    }
    try std.testing.expectEqual(bytes.len, end);
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
    try std.testing.expectError(error.InvalidReferenceChunks, (validate.Action{}).execute(input, feature, reordered_sources, result.chunks));
    var reordered_chunks = result.chunks;
    reordered_chunks.entries = &.{ result.chunks.entries[1], result.chunks.entries[0] };
    try std.testing.expectError(error.InvalidReferenceChunks, (validate.Action{}).execute(input, feature, result.corpus, reordered_chunks));
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
        try std.testing.expectError(error.InvalidReferenceChunks, (validate.Action{}).execute(raw, feature, corpus, chunks));
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
