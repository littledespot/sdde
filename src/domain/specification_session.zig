//! Execution-local business units. Model content never selects IDs or successors.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
const binding = @import("specification_source_binding.zig");
pub const unit_count = std.meta.fields(g.Unit).len;
pub const records_index = @intFromEnum(std.meta.Tag(g.Unit).records);
pub const Session = struct {
    feature: @import("feature_identity.zig").FeatureId,
    reference_state: @import("reference_identity.zig").StateId,
    revision: u64 = 1,
    completed: usize = 0,
    record_cursor: usize = 0,
    record_group_count: usize = 0,
    record_batches: []const g.Checked = &.{},
    units: [unit_count]?g.Checked = @splat(null),
    starting_ledger: @import("specification_identity.zig").Ledger = .{},
    omission_target_bound: ?u32 = null,
    pending_coverage_repair: ?@import("atomic_repair.zig").Pending(@import("specification_coverage.zig").TokenSubject) = null,
};
pub const Error = @import("strict_json.zig").Error || g.Error || packets.Error || binding.Error;

pub fn unit(index: usize) error{InvalidSpecificationUnit}!g.Unit {
    return switch (index) {
        0 => .brief,
        1 => .primary_user_story,
        2 => .entities,
        records_index => .records,
        else => error.InvalidSpecificationUnit,
    };
}

pub fn initialize(feature: @import("feature_identity.zig").FeatureId, context: p.Context) Error!Session {
    if (@import("feature_identity.zig").FeatureId.parse(feature.bytes) == null or !p.generationReady(context.references)) return error.InvalidSpecificationUnit;
    _ = try p.items(context);
    try binding.validate(@import("reference_support.zig").records(context.references), context.inputs);
    return .{ .feature = feature, .reference_state = context.inputs.corpus.state_id, .record_group_count = try binding.recordCount(@import("reference_support.zig").records(context.references)) };
}

pub fn currentBinding(a: std.mem.Allocator, current: Session, context: p.Context) Error!binding.Bound {
    if (!current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    if (current.record_group_count != try binding.recordCount(@import("reference_support.zig").records(context.references))) return error.InvalidSpecificationUnit;
    return binding.forUnit(a, @import("reference_support.zig").records(context.references), context.inputs, try unit(current.completed), current.record_cursor);
}

pub fn owner(allocator: std.mem.Allocator, current: Session) Error!identity.ImmutableUnitOwnerId {
    return ownerFor(allocator, current, current.completed);
}
pub fn ownerFor(allocator: std.mem.Allocator, current: Session, index: usize) Error!identity.ImmutableUnitOwnerId {
    _ = try unit(index);
    return .{
        .specification_unit = .{
            .reference_state_id = .{ .bytes = current.reference_state.bytes },
            // Feature directory is the feature identity; no second ownership registry.
            .feature_id = current.feature,
            .unit_slot_id = .{ .bytes = if (index == records_index and current.completed == records_index) try std.fmt.allocPrint(allocator, "specification-{d}-group-{d}", .{ index + 1, current.record_cursor + 1 }) else try std.fmt.allocPrint(allocator, "specification-{d}", .{index + 1}) },
        },
    };
}

pub fn packet(allocator: std.mem.Allocator, current: Session, context: p.Context) Error!*packets.Packet {
    return packetFor(allocator, current, context, current.completed);
}
pub fn packetFor(allocator: std.mem.Allocator, current: Session, context: p.Context, index: usize) Error!*packets.Packet {
    return packetForChoices(allocator, current, context, index, null);
}

/// Repair retains all source claims but offers exact-copy choices only from the
/// bound owning unit. Initial generation passes null and offers current claims.
pub fn packetForChoices(allocator: std.mem.Allocator, current: Session, context: p.Context, index: usize, allowed: ?[]const @import("reference_reconciliation.zig").ClaimId) Error!*packets.Packet {
    if (!current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    const all = try p.items(context);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const assigned = try binding.forUnit(a, @import("reference_support.zig").records(context.references), context.inputs, try unit(index), current.record_cursor);
    var claims: std.ArrayList(@import("reference_reconciliation.zig").Item) = .empty;
    var scopes: std.ArrayList(@import("reference_evidence.zig").Scope) = .empty;
    for (context.references.records.assignments.checked.prior.prior.dispositions) |disposition| {
        if (!p.eligibleClaim(disposition.disposition)) continue;
        const item = try @import("reference_reconciliation.zig").item(all, disposition.claim_id);
        try claims.append(a, item);
        try scopes.append(a, .{ .state_id = all.state_id, .chunk_id = item.claim.chunk_id });
    }
    const projected = try @import("model_evidence.zig").project(a, claims.items);
    var exact_choices: std.ArrayList(@import("model_evidence.zig").Token) = .empty;
    for (projected.preserved_tokens) |token| {
        if (!p.permitsExactKind(token.kind)) continue;
        if (allowed == null or @import("reference_reconciliation.zig").contains(@import("reference_reconciliation.zig").ClaimId, allowed.?, token.claim_id)) try exact_choices.append(a, token);
    }
    const offered_scopes = if (allowed) |ids|
        (@import("reference_support.zig").select(a, all, context.inputs, ids) catch |err| switch (err) {
            error.InvalidReferenceState => return error.InvalidSpecificationUnit,
            else => |other| return other,
        }).scopes
    else
        scopes.items;
    const payload = .{
        .unit = try unit(index),
        .source_assignment = assigned,
        .brief = if (current.units[0]) |checked| checked.response.content.brief else null,
        .entities = if (current.units[2]) |checked| checked.response.content.entities else null,
        .claims = projected.claims,
        .citations = projected.citations,
        .preserved_tokens = exact_choices.items,
        .sources = try @import("model_evidence.zig").sources(a, context.inputs),
        .passive_literals = try @import("reference_model_input.zig").passiveChoices(a, context.registry, context.inputs, offered_scopes),
    };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), a, payload);
    const selected = try unit(index);
    const result = try packets.create(allocator, body, try ownerFor(a, current, index), .initial_generation, .{ .bytes = switch (selected) {
        .brief => "brief",
        .primary_user_story => "primary_user_story",
        .entities => "entities",
        .records => "records",
    } });
    defer packets.release(result);
    const exact_ids = try a.alloc(i64, exact_choices.items.len);
    for (exact_choices.items, exact_ids) |choice, *id| id.* = choice.claim_id.ordinal;
    const input = @import("reference_model_input.zig");
    const passive_ids = try input.passiveIds(a, payload.passive_literals);
    if (selected == .records) {
        const entities = current.units[2] orelse return error.InvalidSpecificationUnit;
        if (entities.unit != .entities or entities.response != .content or entities.response.content != .entities) return error.InvalidSpecificationUnit;
        if (entities.response.content.entities.disposition == .not_applicable) {
            const fixed = try packets.withExcludedVariants(allocator, result, &.{.{ .kind = "entity" }});
            defer packets.release(fixed);
            return input.withTextChoices(allocator, fixed, passive_ids, exact_ids);
        }
    }
    return input.withTextChoices(allocator, result, passive_ids, exact_ids);
}

/// A value-only repair cannot borrow choices from unchanged sibling evidence.
pub fn withSelectionChoices(a: std.mem.Allocator, base: *const packets.Packet, context: p.Context, selection: g.spec.Selection) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const choices = try p.choicesFor(arena.allocator(), context, selection);
    const scratch = arena.allocator();
    const passive_ids = try scratch.alloc(i64, choices.passive.len);
    for (choices.passive, passive_ids) |choice, *id| id.* = choice.ordinal;
    const exact_ids = try scratch.alloc(i64, choices.exact_copy.len);
    for (choices.exact_copy, exact_ids) |choice, *id| id.* = choice.claim_id.ordinal;
    const visible = try narrowDisplayCatalogues(a, base, passive_ids, exact_ids);
    defer packets.release(visible);
    return @import("reference_model_input.zig").withTextChoices(a, visible, passive_ids, exact_ids);
}

/// Keep Spec's presented display choices aligned with the bound native scope.
/// Other source facts in the packet remain available for semantic judgment.
fn narrowDisplayCatalogues(a: std.mem.Allocator, base: *const packets.Packet, passive: []const i64, exact: []const i64) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    var parsed = try @import("strict_json.zig").parse(scratch, base.body(), .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }, false, null);
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidModelInputPacket;
    for ([_]struct { name: []const u8, id: []const u8, allowed: []const i64 }{
        .{ .name = "passive_literals", .id = "id", .allowed = passive },
        .{ .name = "preserved_tokens", .id = "claim_id", .allowed = exact },
    }) |catalogue| {
        const list = parsed.value.object.getPtr(catalogue.name) orelse return error.InvalidModelInputPacket;
        if (list.* != .array) return error.InvalidModelInputPacket;
        var index: usize = 0;
        while (index < list.array.items.len) {
            const entry = list.array.items[index];
            if (entry != .object) return error.InvalidModelInputPacket;
            const id = entry.object.get(catalogue.id) orelse return error.InvalidModelInputPacket;
            if (id != .number_string) return error.InvalidModelInputPacket;
            const number = std.fmt.parseInt(i64, id.number_string, 10) catch return error.InvalidModelInputPacket;
            var permitted = false;
            for (catalogue.allowed) |allowed| if (number == allowed) {
                permitted = true;
                break;
            };
            if (permitted) index += 1 else _ = list.array.orderedRemove(index);
        }
    }
    const body = try std.json.Stringify.valueAlloc(scratch, parsed.value, .{});
    const projected = if (base.repairPermit()) |permit|
        packets.createRepair(a, body, base.unit(), base.purpose(), base.resultDefinition(), permit, base.repairOrigin())
    else
        packets.create(a, body, base.unit(), base.purpose(), base.resultDefinition());
    const unbound = try projected;
    defer packets.release(unbound);
    return packets.withRestrictions(a, unbound, base.excludedVariants(), base.integerChoices());
}

pub fn append(current: Session, checked: g.Checked) Error!Session {
    if (!std.meta.eql(try unit(current.completed), checked.unit) or checked.response != .content) return error.InvalidSpecificationUnit;
    var next = current;
    if (next.units[current.completed] != null) return error.InvalidSpecificationUnit;
    next.units[current.completed] = checked;
    next.completed += 1;
    next.revision = std.math.add(u64, current.revision, 1) catch return error.InvalidSpecificationUnit;
    return next;
}

/// Preserve each source-bound record batch until all groups have been authored.
/// The completed unit remains one canonical owner for repair, coverage and IDs.
pub fn appendBound(a: std.mem.Allocator, current: Session, checked: g.Checked) Error!Session {
    if (current.completed != records_index) return append(current, checked);
    if (checked.unit != .records or checked.response != .content or checked.response.content != .records or
        current.record_group_count == 0 or current.record_cursor >= current.record_group_count or
        current.record_batches.len != current.record_cursor) return error.InvalidSpecificationUnit;
    const batches = try a.alloc(g.Checked, current.record_batches.len + 1);
    @memcpy(batches[0..current.record_batches.len], current.record_batches);
    batches[current.record_batches.len] = checked;
    var next = current;
    next.record_batches = batches;
    next.record_cursor += 1;
    if (next.record_cursor < next.record_group_count) {
        next.revision = std.math.add(u64, current.revision, 1) catch return error.InvalidSpecificationUnit;
        return next;
    }
    var total: usize = 0;
    for (batches) |batch| total = std.math.add(usize, total, batch.response.content.records.len) catch return error.InvalidSpecificationUnit;
    const records = try a.alloc(g.spec.RecordProposal, total);
    const origins = try a.alloc(@import("specification_candidate.zig").FieldOrigin, total);
    var offset: usize = 0;
    for (batches) |batch| {
        for (batch.response.content.records, 0..) |record, index| {
            records[offset] = record;
            origins[offset] = .{ .target = .{ .record = offset }, .origin = batch.origins.at(.{ .target = .{ .record = index } }) };
            offset += 1;
        }
    }
    var combined = checked;
    combined.response.content.records = records;
    combined.origins = .{ .fields = origins };
    return append(next, combined);
}

/// Cross-batch and cross-unit consistency belongs to the session. The same
/// check governs admission, completed replacements and assembly.
pub fn checkConsistency(a: std.mem.Allocator, current: Session, checked: g.Checked) Error!?@import("specification_candidate.zig").Issue {
    if (checked.response != .content) return null;
    const proposed = checked.response.content;
    if (proposed != .records and proposed != .entities) return null;
    if (proposed == .records and current.completed == records_index) for (proposed.records, 0..) |record, index| {
        for (current.record_batches) |batch| for (batch.response.content.records) |prior| {
            if (try g.duplicateRecordIssue(a, prior, record, index, null)) |issue| return issue;
        };
    };
    const entities = if (proposed == .entities) proposed.entities else (current.units[2] orelse return error.InvalidSpecificationUnit).response.content.entities;
    const records = if (proposed == .records) proposed.records else if (current.units[records_index]) |entry| entry.response.content.records else return null;
    var count: usize = 0;
    var first: ?usize = null;
    for (records, 0..) |record, index| if (record.content == .entity) {
        count += 1;
        if (first == null) first = index;
    };
    if (proposed == .records) {
        for (current.record_batches) |batch| for (batch.response.content.records) |record| if (record.content == .entity) {
            count += 1;
        };
        if (entities.disposition == .required and count == 0 and current.record_cursor + 1 < current.record_group_count) return null;
    }
    if (g.spec.entityMembershipSatisfied(entities.disposition, count)) return null;
    return .{
        .unit = checked.unit,
        .field = if (proposed == .records and first != null) .{ .target = .{ .record = first.? } } else .unit,
        .rule = .entity_membership,
        .observed = null,
        .membership = .{ .disposition = entities.disposition, .entity_count = count },
        .detail = if (count == 0) "The fixed entity decision requires at least one entity record; none was supplied." else "Entity records contradict the fixed not_applicable decision.",
    };
}

pub fn assemble(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, current: Session) Error!@import("specification_identity.zig").Assigned {
    if (current.completed != unit_count or !current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    var records: std.ArrayList(g.spec.RecordProposal) = .empty;
    for (current.units, 0..) |entry, index| {
        const checked = entry orelse return error.InvalidSpecificationUnit;
        // Full-candidate revalidation uses the same owning unit validator.
        const result = switch (try g.revalidate(allocator, validator, context, try unit(index), checked.response)) {
            .valid => |valid| valid,
            .invalid => return error.InvalidSpecificationUnit,
        };
        if (result.response != .content) return error.InvalidSpecificationUnit;
        if (try checkConsistency(allocator, current, result) != null) return error.InvalidSpecificationUnit;
        if (result.response.content == .records) {
            // Canonical section order is a projection; candidate indices and
            // repair origins retain the model's order throughout the session.
            for (std.enums.values(g.spec.Kind)) |kind| for (result.response.content.records) |record| {
                if (record.content == kind) try records.append(allocator, record);
            };
        }
    }
    const entities = current.units[2].?.response.content.entities;
    return @import("specification_identity.zig").assign(allocator, .{
        .display_name = current.units[0].?.response.content.brief.title,
        .primary_user_story = current.units[1].?.response.content.primary_user_story,
        .entities = entities,
        .records = records.items,
    }, current.starting_ledger);
}

/// Locate a canonical ID in the retained request order, without reordering
/// candidate values or their per-field repair origins.
pub fn recordIndex(current: Session, id: g.spec.Id) Error!usize {
    if (current.completed != unit_count) return error.InvalidSpecificationUnit;
    const checked = current.units[records_index] orelse return error.InvalidSpecificationUnit;
    if (checked.unit != .records or checked.response != .content or checked.response.content != .records) return error.InvalidSpecificationUnit;
    var ordinal = current.starting_ledger.next[@intFromEnum(id.kind)];
    for (checked.response.content.records, 0..) |record, index| {
        if (record.content != id.kind) continue;
        if (ordinal == id.ordinal) return index;
        ordinal = std.math.add(u32, ordinal, 1) catch return error.InvalidSpecificationUnit;
    }
    return error.InvalidSpecificationUnit;
}

/// A completed unit may change only through an exact authorized merge. This
/// boundary revalidates the whole affected unit before it becomes checked data.
pub fn replaceCompleted(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, current: Session, index: usize, response: g.CanonicalResponse, merged: @import("atomic_repair.zig").Merge, origins: @import("specification_candidate.zig").Origins) Error!Session {
    if (current.completed != unit_count or index >= unit_count or current.units[index] == null or current.revision != merged.revision_before) return error.InvalidSpecificationUnit;
    var checked = switch (try g.revalidate(allocator, validator, context, try unit(index), response)) {
        .valid => |value| value,
        .invalid => return error.InvalidSpecificationUnit,
    };
    checked.origins = origins;
    checked.last_repair = merged;
    var next = current;
    next.revision = merged.revision_after;
    next.units[index] = checked;
    if (try checkConsistency(allocator, next, checked) != null) return error.InvalidSpecificationUnit;
    return next;
}
