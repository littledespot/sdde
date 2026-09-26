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
    const packet = try packets.create(allocator, body, .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = scope.state_id.bytes }, .chunk_id = .{ .bytes = scope.chunk_id.bytes } } }, .initial_generation, null);
    defer packets.release(packet);
    return withTextChoices(allocator, packet, try passiveIds(scratch, payload.passive_literals), &.{});
}

pub fn reconciliationPacket(allocator: std.mem.Allocator, input: reconciliation.Input, inputs: evidence.Inputs, registry: literals.Registry, guidance_scope: Constraint.Scope) Error!*packets.Packet {
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
        .constraints = try reconciliationGuidance(scratch, input.purpose, guidance_scope),
        .passive_literals = try passiveChoices(scratch, registry, inputs, scopes),
    };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
    const slot = try std.fmt.allocPrint(scratch, "reconciliation-{d}", .{input.partition.id.ordinal});
    const packet = try packets.create(allocator, body, .{ .reference_global = .{ .reference_state_id = .{ .bytes = inputs.corpus.state_id.bytes }, .unit_slot_id = .{ .bytes = slot } } }, .initial_generation, .{ .bytes = @tagName(input.purpose) });
    defer packets.release(packet);
    return withTextChoices(allocator, packet, try passiveIds(scratch, payload.passive_literals), &.{});
}

/// Availability projects existing evidence, not semantics or a second registry.
/// Reference text has no exact-copy variant; its owner leaves that choice alone.
pub fn withTextChoices(a: std.mem.Allocator, packet: *const packets.Packet, passive: []const i64, exact_copy: []const i64) packets.Error!*packets.Packet {
    var excluded: [2]@import("model_result_schema.zig").ExcludedVariant = undefined;
    var count: usize = 0;
    if (passive.len == 0) {
        excluded[count] = .{ .kind = "passive" };
        count += 1;
    }
    if (exact_copy.len == 0) {
        excluded[count] = .{ .kind = "exact_copy" };
        count += 1;
    }
    var choices: [2]@import("model_result_schema.zig").IntegerChoice = undefined;
    var selected: usize = 0;
    if (passive.len != 0) {
        choices[selected] = .{ .kind = "passive", .field = "passive_literal_id", .allowed = passive };
        selected += 1;
    }
    if (exact_copy.len != 0) {
        choices[selected] = .{ .kind = "exact_copy", .field = "claim_id", .allowed = exact_copy };
        selected += 1;
    }
    return packets.withRestrictions(a, packet, excluded[0..count], choices[0..selected]);
}

pub fn passiveIds(a: std.mem.Allocator, records: []const literals.Record) std.mem.Allocator.Error![]const i64 {
    const ids = try a.alloc(i64, records.len);
    for (records, ids) |record, *id| id.* = record.id.ordinal;
    return ids;
}

/// Use the same exact-scope resolver as typed-text validation. Display choices
/// never grant a read, fetch, command or other operational capability.
pub fn passiveChoices(allocator: std.mem.Allocator, registry: literals.Registry, inputs: evidence.Inputs, scopes: []const evidence.Scope) literals.Error![]const literals.Record {
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

const Constraint = reconciliation.diagnostic.Constraint;
const Guidance = struct { constraint: Constraint, requirement: []const u8 };
/// Project native rule identities alongside current claim facts. Corrections
/// retain this packet, with no separate prompt rules table.
fn reconciliationGuidance(allocator: std.mem.Allocator, purpose: @FieldType(reconciliation.Input, "purpose"), scope: Constraint.Scope) std.mem.Allocator.Error![]const Guidance {
    var result: std.ArrayList(Guidance) = .empty;
    for (std.enums.values(Constraint)) |constraint| if (constraint.appliesTo(purpose, scope)) {
        try result.append(allocator, .{ .constraint = constraint, .requirement = constraint.description() });
    };
    return result.toOwnedSlice(allocator);
}
