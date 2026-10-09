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
    if (input.purpose != .summary) return error.InvalidReferenceReconciliation;
    const ids = try @import("reference_reconciliation_projection.zig").semanticClaimIds(allocator, input.items);
    defer allocator.free(ids);
    return reconciliationPacketFor(allocator, input, inputs, registry, .{ .composed = .{ .assignment = .summary, .claim_ids = ids } });
}
pub fn reconciliationPhasePacket(allocator: std.mem.Allocator, prior: @import("reference_reconciliation_stage.zig").Prior, inputs: evidence.Inputs, registry: literals.Registry) ReconciliationError!*packets.Packet {
    const current = @import("reference_reconciliation_stage.zig").input(prior);
    const ids = switch (prior) {
        .dispositions => current.partition.group.claim_ids,
        .signals => |value| try @import("reference_reconciliation_projection.zig").signalClaimIds(allocator, value),
        .roles, .conflicts => &.{},
    };
    defer if (prior == .signals) allocator.free(ids);
    const assignment: Constraint.Assignment = switch (prior) {
        inline else => |_, tag| @field(Constraint.Assignment, @tagName(tag)),
    };
    return reconciliationPacketFor(allocator, current, inputs, registry, .{ .composed = .{ .assignment = assignment, .claim_ids = ids } });
}
const Presentation = union(enum) { shared: Constraint.Scope, composed: struct { assignment: Constraint.Assignment, claim_ids: []const reconciliation.ClaimId } };
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
    const assignment = presentation.composed.assignment;
    const context_body = if (assignment == .roles) roles: {
        break :roles try @import("model_candidate_json.zig").encode(RoleContext, scratch, try roleContext(scratch));
    } else other: {
        const constraints = try reconciliationGuidance(scratch, input.purpose, .{ .assignment = assignment });
        if (assignment == .conflicts) {
            const conflict_context = .{ .constraints = constraints };
            break :other try @import("model_candidate_json.zig").encode(@TypeOf(conflict_context), scratch, conflict_context);
        }
        const assignment_context = .{
            .purpose = hierarchy.purpose,
            .level = hierarchy.level,
            .claim_ids = presentation.composed.claim_ids,
            .member_summary_ids = hierarchy.member_summary_ids,
            .summaries = hierarchy.summaries,
            .constraints = constraints,
        };
        break :other try @import("model_candidate_json.zig").encode(@TypeOf(assignment_context), scratch, assignment_context);
    };
    const contextual = try packets.withAssignmentContexts(allocator, selected, &.{.{ .id = packets.AssignmentContextId.parse(@tagName(assignment)).?, .body = context_body }});
    if (assignment != .summary and assignment != .signals) return contextual;
    defer packets.release(contextual);
    const ids = try scratch.alloc(i64, presentation.composed.claim_ids.len);
    for (ids, presentation.composed.claim_ids) |*id, claim| id.* = claim.ordinal;
    const field = if (assignment == .summary) "statements" else "signals";
    const definition_id: @import("model_result_schema.zig").DefinitionId = .{ .bytes = if (assignment == .summary) "summary" else "signals_assignment" };
    return packets.withIntegerChoices(allocator, contextual, &.{.{ .target = .{ .path = &.{ .{ .property = field }, .{ .items = {} }, .{ .property = "claim_ids" } } }, .definition = definition_id, .allowed = ids }});
}
/// Closed readback of the production role packet, for diagnostic evaluation only.
pub const RoleContext = struct { constraints: []const Guidance, role_definitions: []const RoleDefinition };
pub const RoleInput = struct {
    claims: []const projection.Claim,
    citations: []const extraction.Citation,
    preserved_tokens: []const projection.Token,
    passive_literals: []const literals.Record,
    assignment: RoleContext,
    accepted: @import("reference_role_assignment.zig").Facts,
};
pub const RoleDefinition = struct { role: reconciliation.GenerationRole, purpose: []const u8 };

/// One presentation of the registered purposes and native role-admission rule.
/// The caller owns constraints, role_definitions and each definition's purpose.
pub fn roleContext(a: std.mem.Allocator) (std.mem.Allocator.Error || error{InvalidReferenceReconciliation})!RoleContext {
    var scratch: std.heap.ArenaAllocator = .init(a);
    defer scratch.deinit();
    const constraints = try reconciliationGuidance(a, .global, .{ .assignment = .roles });
    errdefer a.free(constraints);
    const definitions = try a.alloc(RoleDefinition, std.meta.tags(reconciliation.GenerationRole).len);
    errdefer a.free(definitions);
    var initialized: usize = 0;
    errdefer for (definitions[0..initialized]) |definition| a.free(definition.purpose);
    for (std.meta.tags(reconciliation.GenerationRole), definitions) |role, *definition| {
        const purpose = role.purpose(scratch.allocator()) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidRequiredAuthority => error.InvalidReferenceReconciliation,
        };
        definition.* = .{
            .role = role,
            .purpose = try a.dupe(u8, purpose),
        };
        initialized += 1;
    }
    return .{ .constraints = constraints, .role_definitions = definitions };
}

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
    var choices: std.ArrayList(schema.IntegerChoice) = .empty;
    defer choices.deinit(a);
    for (packet.integerChoices()) |entry| {
        if (entry.target == .tagged and (std.mem.eql(u8, entry.target.tagged.kind, "passive") or std.mem.eql(u8, entry.target.tagged.kind, "exact_copy"))) continue;
        try choices.append(a, entry);
    }
    if (passive.len != 0) {
        try choices.append(a, .{ .target = .{ .tagged = .{ .kind = "passive", .field = "passive_literal_id" } }, .allowed = passive });
    }
    if (exact_copy.len != 0) {
        try choices.append(a, .{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = exact_copy });
    }
    return packets.withRestrictions(a, packet, excluded.items, choices.items);
}

/// Project the native disposition scope into its selected response shape.
/// Repair eligibility comes from the canonical checker, never another policy.
pub fn withDispositionChoices(a: std.mem.Allocator, packet: *const packets.Packet, members: []const reconciliation.ClaimId, selected: ?@import("reference_disposition_validation.zig").RepairChoices, grouped: bool) packets.Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const schema = @import("model_result_schema.zig");
    var excluded: std.ArrayList(schema.ExcludedVariant) = .empty;
    try excluded.appendSlice(scratch, packet.excludedVariants());
    var choices: std.ArrayList(schema.IntegerChoice) = .empty;
    try choices.appendSlice(scratch, packet.integerChoices());
    if (grouped) for ([_][]const schema.ChoiceStep{
        &.{ .{ .property = "claim_dispositions" }, .{ .items = {} }, .{ .property = "claim_id" } },
        &.{ .{ .property = "conflict_groups" }, .{ .items = {} }, .{ .property = "claim_ids" } },
    }) |path| try choices.append(scratch, .{ .target = .{ .path = path }, .definition = packet.resultDefinition(), .allowed = try claimOrdinals(scratch, members) });
    for ([_]struct { tag: []const u8, field: []const u8, ids: []const reconciliation.ClaimId }{
        .{ .tag = "duplicate", .field = "target_claim_id", .ids = if (selected) |value| value.duplicate_targets else members },
        .{ .tag = "superseded", .field = "related_claim_ids", .ids = if (selected) |value| value.superseded_targets else members },
    }) |value| {
        if (value.ids.len == 0) {
            try excluded.append(scratch, .{ .kind = value.tag });
        } else try choices.append(scratch, .{ .target = .{ .tagged = .{ .kind = value.tag, .field = value.field } }, .definition = packet.resultDefinition(), .allowed = try claimOrdinals(scratch, value.ids) });
    }
    if (selected) |value| {
        if (!value.retained) try excluded.append(scratch, .{ .kind = "retained" });
        if (value.conflicting_with_all.len == 0) try excluded.append(scratch, .{ .kind = "conflicting" });
    }
    return packets.withRestrictions(a, packet, excluded.items, choices.items);
}
fn claimOrdinals(a: std.mem.Allocator, ids: []const reconciliation.ClaimId) std.mem.Allocator.Error![]const i64 {
    const result = try a.alloc(i64, ids.len);
    for (result, ids) |*value, id| value.* = id.ordinal;
    return result;
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
pub const Guidance = struct { constraint: Constraint, requirement: []const u8 };
/// Project native rule identities alongside current claim facts. Corrections
/// retain this packet, with no separate prompt rules table.
fn reconciliationGuidance(allocator: std.mem.Allocator, purpose: @FieldType(reconciliation.Input, "purpose"), scope: Constraint.Scope) std.mem.Allocator.Error![]const Guidance {
    var result: std.ArrayList(Guidance) = .empty;
    errdefer result.deinit(allocator);
    for (std.enums.values(Constraint)) |constraint| if (constraint.appliesTo(purpose, scope)) {
        try result.append(allocator, .{ .constraint = constraint, .requirement = constraint.description() });
    };
    return result.toOwnedSlice(allocator);
}
