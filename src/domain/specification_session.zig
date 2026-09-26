//! Execution-local business units. Model content never selects IDs or successors.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
pub const unit_count = std.meta.fields(g.Unit).len;
pub const records_index = @intFromEnum(std.meta.Tag(g.Unit).records);
pub const Session = struct {
    feature: @import("feature_identity.zig").FeatureId,
    reference_state: @import("reference_identity.zig").StateId,
    revision: u64 = 1,
    completed: usize = 0,
    units: [unit_count]?g.Checked = @splat(null),
    starting_ledger: @import("specification_identity.zig").Ledger = .{},
    omission_target_bound: ?u32 = null,
    pending_coverage_repair: ?@import("atomic_repair.zig").Pending(@import("specification_coverage.zig").TokenSubject) = null,
};
pub const Error = @import("strict_json.zig").Error || g.Error || packets.Error;

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
    return .{ .feature = feature, .reference_state = context.inputs.corpus.state_id };
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
            .unit_slot_id = .{ .bytes = try std.fmt.allocPrint(allocator, "specification-{d}", .{index + 1}) },
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
    return @import("reference_model_input.zig").withTextChoices(allocator, result, payload.passive_literals.len != 0, exact_choices.items.len != 0);
}

/// A value-only repair cannot borrow choices from unchanged sibling evidence.
pub fn withSelectionChoices(a: std.mem.Allocator, base: *const packets.Packet, context: p.Context, selection: g.spec.Selection) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const choices = try p.choicesFor(arena.allocator(), context, selection);
    return @import("reference_model_input.zig").withTextChoices(a, base, choices.passive.len != 0, choices.exact_copy.len != 0);
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

/// Cross-unit consistency belongs to the session, not individual content fields.
/// The same check governs admission, completed replacements and assembly.
pub fn checkMembership(current: Session, checked: g.Checked) Error!?@import("specification_candidate.zig").Issue {
    if (checked.response != .content) return null;
    const proposed = checked.response.content;
    if (proposed != .records and proposed != .entities) return null;
    const entities = if (proposed == .entities) proposed.entities else (current.units[2] orelse return error.InvalidSpecificationUnit).response.content.entities;
    const records = if (proposed == .records) proposed.records else if (current.units[records_index]) |entry| entry.response.content.records else return null;
    var count: usize = 0;
    var first: ?usize = null;
    for (records, 0..) |record, index| if (record.content == .entity) {
        count += 1;
        if (first == null) first = index;
    };
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
        if (try checkMembership(current, result) != null) return error.InvalidSpecificationUnit;
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
    if (try checkMembership(next, checked) != null) return error.InvalidSpecificationUnit;
    return next;
}
