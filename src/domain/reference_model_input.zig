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
pub const ReconciliationError = Error || reconciliation.Error;

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

pub fn reconciliationPacket(allocator: std.mem.Allocator, input: reconciliation.Input, inputs: evidence.Inputs, registry: literals.Registry, guidance_scope: Constraint.Scope) ReconciliationError!*packets.Packet {
    return reconciliationPacketFor(allocator, input, inputs, registry, .{ .shared = guidance_scope });
}
pub fn reconciliationCompositionPacket(allocator: std.mem.Allocator, input: reconciliation.Input, inputs: evidence.Inputs, registry: literals.Registry) ReconciliationError!*packets.Packet {
    return reconciliationPacketFor(allocator, input, inputs, registry, .composed);
}
const Presentation = union(enum) { shared: Constraint.Scope, composed };
fn reconciliationPacketFor(allocator: std.mem.Allocator, input: reconciliation.Input, inputs: evidence.Inputs, registry: literals.Registry, presentation: Presentation) ReconciliationError!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    if (!input.progress.plan.layout.items.state_id.eql(inputs.corpus.state_id)) return error.InvalidReferenceExtraction;
    const scopes = try scratch.alloc(evidence.Scope, input.items.len);
    for (input.items, scopes) |item, *scope| scope.* = .{ .state_id = inputs.corpus.state_id, .chunk_id = item.claim.chunk_id };
    const projected = try projection.project(scratch, input.items);
    const common = .{
        .claims = projected.claims,
        .citations = projected.citations,
        .preserved_tokens = projected.preserved_tokens,
        .passive_literals = try passiveChoices(scratch, registry, inputs, scopes),
    };
    const hierarchy = .{
        .purpose = input.purpose,
        .level = input.partition.group.level,
        .member_claim_ids = input.partition.group.claim_ids,
        .member_summary_ids = input.member_summary_ids,
        .summaries = try projection.summaries(scratch, input.summaries),
    };
    const body = if (presentation == .shared) shared: {
        const payload = .{
            .purpose = hierarchy.purpose,
            .level = hierarchy.level,
            .member_claim_ids = hierarchy.member_claim_ids,
            .member_summary_ids = hierarchy.member_summary_ids,
            .claims = common.claims,
            .citations = common.citations,
            .preserved_tokens = common.preserved_tokens,
            .summaries = hierarchy.summaries,
            .constraints = try reconciliationGuidance(scratch, input.purpose, presentation.shared),
            .passive_literals = common.passive_literals,
        };
        break :shared try @import("model_candidate_json.zig").encode(@TypeOf(payload), scratch, payload);
    } else try @import("model_candidate_json.zig").encode(@TypeOf(common), scratch, common);
    const slot = try std.fmt.allocPrint(scratch, "reconciliation-{d}", .{input.partition.id.ordinal});
    const packet = try packets.create(allocator, body, .{ .reference_global = .{ .reference_state_id = .{ .bytes = inputs.corpus.state_id.bytes }, .unit_slot_id = .{ .bytes = slot } } }, .initial_generation, .{ .bytes = @tagName(input.purpose) });
    defer packets.release(packet);
    const selected = try withTextChoices(allocator, packet, try passiveIds(scratch, common.passive_literals), &.{});
    if (presentation == .shared) return selected;
    defer packets.release(selected);
    const assignments: []const Constraint.Assignment = if (input.purpose == .summary) &.{.summary} else &.{ .dispositions, .signals, .roles, .conflicts };
    const contexts = try scratch.alloc(packets.AssignmentContext, assignments.len);
    for (assignments, contexts) |assignment, *context| {
        const constraints = try reconciliationGuidance(scratch, input.purpose, .{ .assignment = assignment });
        const context_body = if (assignment == .roles) roles: {
            const definitions = try scratch.alloc(RoleDefinition, std.meta.tags(reconciliation.GenerationRole).len);
            for (std.meta.tags(reconciliation.GenerationRole), definitions) |role, *definition| definition.* = .{
                .role = role,
                .purpose = role.purpose(scratch) catch |err| return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidRequiredAuthority => error.InvalidReferenceReconciliation,
                },
            };
            const role_context = .{ .constraints = constraints, .role_definitions = definitions };
            break :roles try @import("model_candidate_json.zig").encode(@TypeOf(role_context), scratch, role_context);
        } else other: {
            const assignment_context = .{
                .purpose = hierarchy.purpose,
                .level = hierarchy.level,
                .member_claim_ids = hierarchy.member_claim_ids,
                .member_summary_ids = hierarchy.member_summary_ids,
                .summaries = hierarchy.summaries,
                .constraints = constraints,
            };
            break :other try @import("model_candidate_json.zig").encode(@TypeOf(assignment_context), scratch, assignment_context);
        };
        context.* = .{ .id = packets.AssignmentContextId.parse(@tagName(assignment)).?, .body = context_body };
    }
    return packets.withAssignmentContexts(allocator, selected, contexts);
}
const RoleDefinition = struct { role: reconciliation.GenerationRole, purpose: []const u8 };

/// Availability projects existing evidence, not semantics or a second registry.
/// Reference text has no exact-copy variant; its owner leaves that choice alone.
pub fn withTextChoices(a: std.mem.Allocator, packet: *const packets.Packet, passive: []const i64, exact_copy: []const i64) packets.Error!*packets.Packet {
    const schema = @import("model_result_schema.zig");
    var excluded: std.ArrayList(schema.ExcludedVariant) = .empty;
    defer excluded.deinit(a);
    // Narrow text availability without discarding unrelated decisions already
    // bound to this packet (for example, Spec's fixed entity disposition).
    for (packet.excludedVariants()) |entry| {
        if (std.mem.eql(u8, entry.kind, "passive") or std.mem.eql(u8, entry.kind, "exact_copy")) continue;
        try excluded.append(a, entry);
    }
    if (passive.len == 0) {
        try excluded.append(a, .{ .kind = "passive" });
    }
    if (exact_copy.len == 0) {
        try excluded.append(a, .{ .kind = "exact_copy" });
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
    return packets.withRestrictions(a, packet, excluded.items, choices[0..selected]);
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
