//! Execution-local business units. Model content never selects IDs or successors.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
pub const unit_count = 3 + std.meta.tags(g.spec.Kind).len;
pub const Session = struct {
    feature: @import("feature_identity.zig").FeatureId,
    reference_state: @import("reference_identity.zig").StateId,
    revision: u64 = 1,
    completed: usize = 0,
    units: [unit_count]?g.Checked = @splat(null),
    starting_ledger: @import("specification_identity.zig").Ledger = .{},
};
pub const Error = @import("strict_json.zig").Error || g.Error || packets.Error;

pub fn unit(index: usize) error{InvalidSpecificationUnit}!g.Unit {
    return switch (index) {
        0 => .brief,
        1 => .primary_user_story,
        2 => .entities,
        3...unit_count - 1 => .{ .records = @enumFromInt(index - 3) },
        else => error.InvalidSpecificationUnit,
    };
}

pub fn initialize(feature: @import("feature_identity.zig").FeatureId, context: p.Context) Error!Session {
    if (@import("feature_identity.zig").FeatureId.parse(feature.bytes) == null or context.references.outcome != .complete) return error.InvalidSpecificationUnit;
    _ = try p.items(context);
    return .{ .feature = feature, .reference_state = context.inputs.corpus.state_id };
}

pub fn owner(allocator: std.mem.Allocator, current: Session) Error!identity.ImmutableUnitOwnerId {
    return .{
        .specification_unit = .{
            .reference_state_id = .{ .bytes = current.reference_state.bytes },
            // Feature directory is the feature identity; no second ownership registry.
            .feature_id = current.feature,
            .unit_slot_id = .{ .bytes = try std.fmt.allocPrint(allocator, "specification-{d}", .{current.completed + 1}) },
        },
    };
}

pub fn packet(allocator: std.mem.Allocator, current: Session, context: p.Context) Error!*packets.Packet {
    if (!current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    const all = try p.items(context);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var claims: std.ArrayList(@import("reference_reconciliation.zig").Item) = .empty;
    var scopes: std.ArrayList(@import("reference_evidence.zig").Scope) = .empty;
    for (context.references.records.assignments.checked.prior.prior.dispositions) |disposition| {
        if (disposition.disposition != .retained) continue;
        const item = try @import("reference_reconciliation.zig").item(all, disposition.claim_id);
        try claims.append(a, item);
        try scopes.append(a, .{ .state_id = all.state_id, .chunk_id = item.claim.chunk_id });
    }
    const projected = try @import("model_evidence.zig").project(a, claims.items);
    const payload = .{
        .unit = try unit(current.completed),
        .brief = if (current.units[0]) |checked| checked.response.content.brief else null,
        .claims = projected.claims,
        .citations = projected.citations,
        .preserved_tokens = projected.preserved_tokens,
        .signals = try @import("model_evidence.zig").signals(a, context.references.records.signals),
        .passive_literals = try @import("reference_model_input.zig").passiveChoices(a, context.registry, context.inputs, scopes.items),
    };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), a, payload);
    const selected = try unit(current.completed);
    return packets.create(allocator, body, try owner(a, current), .initial_generation, .{ .bytes = switch (selected) {
        .brief => "brief",
        .primary_user_story => "primary_user_story",
        .entities => "entities",
        .records => |kind| @tagName(kind),
    } });
}

pub fn append(current: Session, checked: g.Checked) Error!Session {
    if (!std.meta.eql(try unit(current.completed), checked.unit) or checked.response != .content) return error.InvalidSpecificationUnit;
    var next = current;
    if (next.units[current.completed] != null) return error.InvalidSpecificationUnit;
    next.units[current.completed] = checked;
    next.completed += 1;
    next.revision = std.math.add(u64, current.revision, 1) catch return error.InvalidSpecificationUnit;
    // An evidence-backed non-applicable entity decision creates no entity call
    // or invented entity. The empty family is an engine-owned structural fact.
    if (next.completed == unit_count - 1 and next.units[2].?.response.content.entities.disposition == .not_applicable) {
        next.units[next.completed] = .{ .unit = .{ .records = .entity }, .response = .{ .content = .{ .records = &.{} } } };
        next.completed += 1;
    }
    return next;
}

pub fn assemble(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, current: Session) Error!@import("specification_identity.zig").Assigned {
    if (current.completed != unit_count or !current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    var records: std.ArrayList(g.spec.RecordProposal) = .empty;
    for (current.units, 0..) |entry, index| {
        const checked = entry orelse return error.InvalidSpecificationUnit;
        // Full-candidate revalidation uses the same owning unit validator.
        const result = try g.validate(allocator, validator, context, try unit(index), checked.response);
        if (result.response != .content) return error.InvalidSpecificationUnit;
        if (result.response.content == .records) try records.appendSlice(allocator, result.response.content.records);
    }
    const entities = current.units[2].?.response.content.entities;
    const entity_records = current.units[unit_count - 1].?.response.content.records;
    if ((entities.disposition == .required and entity_records.len == 0) or (entities.disposition == .not_applicable and entity_records.len != 0)) return error.InvalidSpecificationUnit;
    return @import("specification_identity.zig").assign(allocator, .{
        .display_name = current.units[0].?.response.content.brief.title,
        .primary_user_story = current.units[1].?.response.content.primary_user_story,
        .entities = entities,
        .records = records.items,
    }, current.starting_ledger);
}
