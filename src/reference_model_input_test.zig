const std = @import("std");
const input = @import("domain/reference_model_input.zig");
const iteration = @import("domain/reference_model_iteration.zig");
const packets = @import("domain/model_input_packet.zig");
const source = @import("reference_evidence_test.zig");
const extraction = @import("reference_extraction_test.zig");
const reconciliation = @import("test_fixtures/reference_reconciliation.zig");
const text = @import("test_fixtures/reference_text.zig");
const tokens = @import("test_fixtures/reference_tokens.zig");

test "reference model packets preserve exact chunk bytes and engine bound scope" {
    try exercisePackets(std.testing.allocator);
}
test "reference packet and iteration allocations have deterministic cleanup" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercisePackets, .{});
}
fn exercisePackets(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: source.IdSource = .{};
    const inputs = try source.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "requirements.md", "Display `Hello, World!`.\n"));
    const passive = try text.prepare(a, inputs);
    defer passive.deinit();
    const candidates = try tokens.candidates(a, inputs);
    var progress = try iteration.initialize(a, inputs);
    for (inputs.chunks.entries) |chunk| {
        const scope = iteration.current(progress).?;
        const packet = try input.extractionPacket(allocator, inputs, passive.registry, candidates, scope);
        defer packets.release(packet);
        try std.testing.expectEqual(.reference_chunk, std.meta.activeTag(packet.unit()));
        try std.testing.expectEqualStrings(chunk.id.bytes, packet.unit().reference_chunk.chunk_id.bytes);
        var body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        defer body.deinit();
        try std.testing.expectEqualStrings(inputs.corpus.sources[0].bytes[chunk.span.start.byte..chunk.span.end.byte], body.value.object.get("text").?.string);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Hello, World!") != null);
        const response = try tokens.wire(a, try extraction.reply(a, chunk, "The application displays a greeting."), try tokens.classifications(a, candidates, chunk));
        progress = try iteration.append(a, progress, scope, response);
    }
    try std.testing.expect(iteration.current(progress) == null);
    const raw = try iteration.finish(a, progress);
    const extracted = try extraction.finish(a, inputs, raw.entries);
    const context: reconciliation.Context = .{ .inputs = inputs, .registry = passive.registry, .current = text.safety.value(passive.owner) };
    const initial = try reconciliation.initialize(a, inputs, extracted, 2);
    const global = try reconciliation.summaries(a, initial, context);
    const packet = try input.reconciliationPacket(allocator, global, inputs, passive.registry);
    defer packets.release(packet);
    try std.testing.expectEqual(.reference_global, std.meta.activeTag(packet.unit()));
    try std.testing.expectEqualStrings("global", packet.resultDefinition().?.bytes);
    const projected = try @import("domain/model_evidence.zig").project(a, global.items);
    try std.testing.expectEqual(global.items.len, projected.claims.len);
    var body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    defer body.deinit();
    try std.testing.expectEqual(global.items.len, body.value.object.get("claims").?.array.items.len);
    try std.testing.expectEqual(projected.citations.len, body.value.object.get("citations").?.array.items.len);
    for (global.items, projected.claims) |item, claim| {
        try std.testing.expectEqualDeep(item.claim.id, claim.id);
        try std.testing.expectEqualDeep(item.claim.citation_ids, claim.citation_ids);
        switch (item.claim.content) {
            .model => |value| try std.testing.expectEqualDeep(value, claim.content.model),
            .preserved_token => |token| {
                try std.testing.expectEqualStrings(token.value.raw_value.bytes, claim.content.preserved_token.value);
                try std.testing.expectEqualDeep(token.value.id, claim.content.preserved_token.id);
            },
        }
        for (item.citations) |citation| {
            var matches: usize = 0;
            for (projected.citations) |copy| if (copy.id.ordinal == citation.id.ordinal) {
                matches += 1;
                try std.testing.expectEqualDeep(citation, copy);
            };
            try std.testing.expectEqual(@as(usize, 1), matches);
        }
    }
    for ([_][]const u8{ "chunk_id", "reference_state_id", "result_definition", "extractor", "raw_value" }) |internal| {
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), internal) == null);
    }
    const accounted = try reconciliation.finish(a, global, try reconciliation.global(a, global), context);
    try std.testing.expectEqual(.complete, accounted.outcome);
    try std.testing.expectEqual(extracted.ledger.claims.len, global.items.len);
}
test "extraction collection rejects missing duplicate foreign and out of order scope" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: source.IdSource = .{};
    const inputs = try source.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "renewals.md", "A librarian renews loans.\n" ** 70));
    const initial = try iteration.initialize(a, inputs);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.finish(a, initial));
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, initial, initial.scopes[1], extraction.no_claim));
    var foreign = initial.scopes[0];
    foreign.state_id.bytes = "foreign";
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, initial, foreign, extraction.no_claim));
    const once = try iteration.append(a, initial, initial.scopes[0], extraction.no_claim);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, once, initial.scopes[0], extraction.no_claim));
    const complete = try iteration.append(a, once, initial.scopes[1], extraction.no_claim);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, complete, initial.scopes[1], extraction.no_claim));
    try std.testing.expectEqual(@as(usize, 2), (try iteration.finish(a, complete)).entries.len);
}
test "packet body and domain identity are owned independently of caller allocations" {
    var bytes = [_]u8{'x'};
    var selector = "answer".*;
    const packet = try packets.create(std.testing.allocator, &bytes, .{ .reference_global = .{ .reference_state_id = .{ .bytes = "reference-current" }, .unit_slot_id = .{ .bytes = "meaning" } } }, .initial_generation, .{ .bytes = &selector });
    bytes[0] = 'y';
    @memset(&selector, 'x');
    const retained = try packets.retain(packet);
    packets.release(packet);
    defer packets.release(retained);
    try std.testing.expectEqualStrings("x", retained.body());
    try std.testing.expectEqualStrings("reference-current", retained.unit().reference_global.reference_state_id.bytes);
    try std.testing.expectEqualStrings("answer", retained.resultDefinition().?.bytes);
    try std.testing.expectError(error.InvalidModelInputPacket, packets.create(std.testing.allocator, "", .workflow_step, .initial_generation, null));
    try std.testing.expectError(error.InvalidModelInputPacket, packets.create(std.testing.allocator, "{}", .workflow_step, .initial_generation, .{ .bytes = "../answer" }));
}
