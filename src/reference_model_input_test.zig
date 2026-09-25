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
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const content: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const classified: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const producers: @import("domain/reference_extraction.zig").ProducerOrigins = .{ .content = content, .classifications = classified };
    var progress = try iteration.initialize(a, inputs);
    for (inputs.chunks.entries) |chunk| {
        const scope = iteration.current(progress).?;
        const packet = try input.extractionPacket(allocator, inputs, passive.registry, candidates, scope);
        defer packets.release(packet);
        try std.testing.expectEqual(.reference_chunk, std.meta.activeTag(packet.unit()));
        try std.testing.expectEqualStrings(chunk.id.bytes, packet.unit().reference_chunk.chunk_id.bytes);
        var body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        defer body.deinit();
        var reconstructed: std.ArrayList(u8) = .empty;
        defer reconstructed.deinit(a);
        for (body.value.object.get("source_lines").?.array.items, 1..) |line, ordinal| {
            try std.testing.expectEqual(@as(i64, @intCast(ordinal)), line.object.get("id").?.integer);
            try reconstructed.appendSlice(a, line.object.get("text").?.string);
        }
        try std.testing.expectEqualStrings(inputs.corpus.sources[0].bytes[chunk.span.start.byte..chunk.span.end.byte], reconstructed.items);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Hello, World!") != null);
        const response = try tokens.wire(a, try extraction.reply(a, chunk, "The application displays a greeting."), try tokens.classifications(a, candidates, chunk));
        progress = try iteration.append(a, progress, scope, response, content, producers);
    }
    try std.testing.expect(iteration.current(progress) == null);
    const raw = try iteration.finish(a, progress);
    try std.testing.expectEqualDeep(content, raw.entries[0].origin.?);
    try std.testing.expectEqualDeep(producers, raw.entries[0].producers.?);
    const extracted = try extraction.finish(a, inputs, raw.entries);
    const context: reconciliation.Context = .{ .inputs = inputs, .registry = passive.registry, .current = text.safety.value(passive.owner) };
    const initial = try reconciliation.initialize(a, inputs, extracted, 2);
    const global = try reconciliation.summaries(a, initial, context);
    const packet = try input.reconciliationPacket(allocator, global, inputs, passive.registry, .all);
    defer packets.release(packet);
    try checkProjectedPacket(a, packet.body());
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
            .model => |value| try std.testing.expectEqualDeep(@import("domain/model_evidence.zig").modelContent(value), claim.content.model),
            .preserved_token => |token| {
                try std.testing.expectEqualDeep(token.value.id, claim.content.preserved_token.token_id);
                const copy = projected.preserved_tokens[0];
                try std.testing.expectEqualStrings(token.value.raw_value.bytes, copy.value);
                try std.testing.expectEqualDeep(token.value.id, copy.id);
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
    const accounted = (try reconciliation.finish(a, global, try reconciliation.global(a, global), context)).valid;
    try std.testing.expectEqual(.complete, accounted.outcome);
    try std.testing.expectEqual(extracted.ledger.claims.len, global.items.len);
}

/// The same model content must decode under the response contract wherever it
/// appears as evidence. This checks production packet bytes, not native views.
pub fn checkProjectedPacket(a: std.mem.Allocator, bytes: []const u8) !void {
    const r = @import("domain/reference_reconciliation.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    const body = if (parsed.value.object.get("input")) |base| base.object else parsed.value.object;
    for (body.get("claims").?.array.items) |claim| {
        const raw = try std.json.Stringify.valueAlloc(a, claim.object.get("content").?, .{});
        const content = try codec.decode(r.ContentProposal, a, raw);
        if (content == .preserved_token) {
            const id = content.preserved_token.token_id;
            for (body.get("preserved_tokens").?.array.items) |token| {
                if (token.object.get("id").?.integer == id.ordinal) {
                    try std.testing.expect(token.object.get("value").?.string.len != 0);
                    break;
                }
            } else return error.MissingTokenEvidence;
        }
    }
    if (body.get("summaries")) |summaries| for (summaries.array.items) |summary| {
        for (summary.object.get("statements").?.array.items) |statement| {
            _ = try codec.decode(r.ContentProposal, a, try std.json.Stringify.valueAlloc(a, statement.object.get("content").?, .{}));
        }
    };
    if (body.get("signals")) |signals| for (signals.array.items) |signal| {
        _ = try codec.decode(@FieldType(@import("domain/model_evidence.zig").Signal, "value"), a, try std.json.Stringify.valueAlloc(a, signal.object.get("value").?, .{}));
    };
    if (body.get("conflicts")) |conflicts| for (conflicts.array.items) |conflict| {
        _ = try codec.decode(@FieldType(@import("domain/model_evidence.zig").Conflict, "value"), a, try std.json.Stringify.valueAlloc(a, conflict.object.get("value").?, .{}));
    };
    if (body.get("brief")) |brief| if (brief != .null) {
        _ = try codec.decode(@import("domain/specification.zig").Brief, a, try std.json.Stringify.valueAlloc(a, brief, .{}));
    };
}

test "every reference content kind projects validated text into the shared model wire contract" {
    const r = @import("domain/reference_reconciliation.zig");
    const projection = @import("domain/model_evidence.zig");
    const codec = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (comptime std.meta.tags(r.extraction.Kind)) |kind| {
        const value: r.Content = .{ .model = @unionInit(r.extraction.Content, @tagName(kind), switch (kind) {
            .business, .scope_guard => .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "A librarian renews a loan." } }} } },
            else => .{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "A librarian renews a loan." } }} } },
        }) };
        const projected = projection.content(value);
        const wire = try codec.encode(r.ContentProposal, a, projected);
        try std.testing.expectEqualDeep(projected, try codec.decode(r.ContentProposal, a, wire));
        const parsed = try std.json.parseFromSlice(std.json.Value, a, wire, .{});
        try std.testing.expectEqualStrings("model", parsed.value.object.get("kind").?.string);
        const model = parsed.value.object.get("model").?.object;
        try std.testing.expectEqualStrings(@tagName(kind), model.get("kind").?.string);
        try std.testing.expect(model.get("value") == null);
        const nodes = model.get(if (kind == .business or kind == .scope_guard) "segments" else "nodes").?.array.items;
        try std.testing.expectEqualStrings("A librarian renews a loan.", nodes[0].string);
    }
}
test "extraction collection rejects missing duplicate foreign and out of order scope" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: source.IdSource = .{};
    const inputs = try source.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "renewals.md", "A librarian renews loans.\n" ** 70));
    const initial = try iteration.initialize(a, inputs);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.finish(a, initial));
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, initial, initial.scopes[1], extraction.no_claim, null, null));
    var foreign = initial.scopes[0];
    foreign.state_id.bytes = "foreign";
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, initial, foreign, extraction.no_claim, null, null));
    const once = try iteration.append(a, initial, initial.scopes[0], extraction.no_claim, null, null);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, once, initial.scopes[0], extraction.no_claim, null, null));
    const complete = try iteration.append(a, once, initial.scopes[1], extraction.no_claim, null, null);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, complete, initial.scopes[1], extraction.no_claim, null, null));
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

test "typed and admitted packet context preserve exact numbers and assignment ownership" {
    try packetContextPrecision(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, packetContextPrecision, .{});
    const base = try packets.create(std.testing.allocator, "{\"candidate\":{}}", .workflow_step, .initial_generation, null);
    defer packets.release(base);
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withContext(struct {}, std.testing.allocator, base, "candidate", .{}));
}

fn packetContextPrecision(allocator: std.mem.Allocator) !void {
    const body = "{\"amount\":9007199254740993.0,\"rate\":0.10000000000000000000000000001,\"items\":[1e0,-0.0]}";
    const unit: @import("domain/model_request_identity.zig").ImmutableUnitOwnerId = .{ .plan_unit = .{
        .plan_input_authority_state_id = .{ .bytes = "plan-current" },
        .unit_slot_id = .{ .bytes = "limits" },
    } };
    const base = try packets.create(allocator, body, unit, .{ .semantic_review = .{ .bytes = "precision" } }, .{ .bytes = "limits" });
    defer packets.release(base);
    const Context = struct { offset: f64, note: []const u8 };
    const context: Context = .{ .offset = -0.0, .note = "keep exact" };
    const encoded = try @import("domain/model_candidate_json.zig").encode(Context, allocator, context);
    defer allocator.free(encoded);
    var parsed = try @import("domain/strict_json.zig").parse(allocator, encoded, .{ .maximum_depth = 8 }, false, null);
    defer parsed.deinit();
    const expected = try std.fmt.allocPrint(allocator, "{s},\"prerequisites\":{s}}}", .{ body[0 .. body.len - 1], encoded });
    defer allocator.free(expected);
    for ([_]bool{ false, true }) |typed| {
        const derived = if (typed)
            try packets.withContext(Context, allocator, base, "prerequisites", context)
        else
            try packets.withJsonContext(allocator, base, "prerequisites", parsed.value);
        defer packets.release(derived);
        try std.testing.expectEqualStrings(expected, derived.body());
        try std.testing.expectEqualStrings(body, base.body());
        try std.testing.expectEqualDeep(base.unit(), derived.unit());
        try std.testing.expectEqualDeep(base.purpose(), derived.purpose());
        try std.testing.expectEqualStrings(base.resultDefinition().?.bytes, derived.resultDefinition().?.bytes);
    }
}
