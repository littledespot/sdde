//! Model-visible projections over already validated reference authorities.
//! No provider selection, prompts, response interpretation or scope from JSON.
const std = @import("std");
const evidence = @import("reference_evidence.zig");
const extraction = @import("reference_extraction.zig");
const reconciliation = @import("reference_reconciliation.zig");
const literals = @import("passive_literals.zig");
const packets = @import("model_input_packet.zig");
const projection = @import("model_evidence.zig");
pub const Error = @import("strict_json.zig").Error || packets.Error || extraction.Error;

pub fn extractionPacket(allocator: std.mem.Allocator, inputs: evidence.Inputs, registry: literals.Registry, tokens: extraction.tokens.Candidates, scope: evidence.Scope) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const chunk = try evidence.resolve(inputs, scope);
    if (!tokens.state_id.eql(scope.state_id)) return error.InvalidReferenceExtraction;
    var selected: std.ArrayList(projection.ExactCandidate) = .empty;
    for (tokens.entries) |token| if (token.fact.scope.chunk_id.eql(scope.chunk_id)) {
        if (!token.fact.scope.state_id.eql(scope.state_id)) return error.InvalidReferenceExtraction;
        try selected.append(scratch, projection.exactCandidate(token));
    };
    const payload = .{
        .source_id = chunk.chunk.source_id,
        .block_id = chunk.chunk.block_id,
        .source_lines = try @import("source_selections.zig").project(scratch, inputs, scope),
        .passive_literals = try passiveChoices(scratch, registry, inputs, &.{scope}),
        .exact_candidates = selected.items,
    };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
    return packets.create(allocator, body, .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = scope.state_id.bytes }, .chunk_id = .{ .bytes = scope.chunk_id.bytes } } }, .initial_generation, null);
}

pub fn reconciliationPacket(allocator: std.mem.Allocator, input: reconciliation.Input, inputs: evidence.Inputs, registry: literals.Registry) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    if (!input.progress.plan.layout.items.state_id.eql(inputs.corpus.state_id)) return error.InvalidReferenceExtraction;
    const scopes = try scratch.alloc(evidence.Scope, input.items.len);
    for (input.items, scopes) |item, *scope| scope.* = .{ .state_id = inputs.corpus.state_id, .chunk_id = item.claim.chunk_id };
    const projected = try projection.project(scratch, input.items);
    const payload = .{
        .purpose = input.purpose,
        .level = input.partition.group.level,
        .member_claim_ids = input.partition.group.claim_ids,
        .member_summary_ids = input.member_summary_ids,
        .claims = projected.claims,
        .citations = projected.citations,
        .preserved_tokens = projected.preserved_tokens,
        .summaries = try projection.summaries(scratch, input.summaries),
        .passive_literals = try passiveChoices(scratch, registry, inputs, scopes),
    };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
    const slot = try std.fmt.allocPrint(scratch, "reconciliation-{d}", .{input.partition.id.ordinal});
    return packets.create(allocator, body, .{ .reference_global = .{ .reference_state_id = .{ .bytes = inputs.corpus.state_id.bytes }, .unit_slot_id = .{ .bytes = slot } } }, .initial_generation, .{ .bytes = @tagName(input.purpose) });
}

/// Use the same exact-scope resolver as typed-text validation. Display choices
/// never grant a read, fetch, command or other operational capability.
pub fn passiveChoices(allocator: std.mem.Allocator, registry: literals.Registry, inputs: evidence.Inputs, scopes: []const evidence.Scope) Error![]const literals.Record {
    var result: std.ArrayList(literals.Record) = .empty;
    for (registry.records) |record| {
        const allowed = literals.resolveIn(registry, inputs, scopes, record.id) catch |err| switch (err) {
            error.InvalidPassiveLiteral => continue,
            else => return err,
        };
        try result.append(allocator, allowed);
    }
    return result.toOwnedSlice(allocator);
}
