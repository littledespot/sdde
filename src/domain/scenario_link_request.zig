//! The closed request behind an edge case's outcome link (ADR 0038 Decision 7). An edge case
//! whose records batch holds two or more acceptance criteria naming one of its claims asks the
//! model which of them states its outcome. The packet offers those criteria; the answer is the
//! id of one, so the response schema admits no other value and no text.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
const projection = @import("specification_projection.zig");
const session = @import("specification_session.zig");
const binding = @import("specification_source_binding.zig");
const link = @import("scenario_link.zig");
const json = @import("model_candidate_json.zig");

pub const Error = session.Error || link.Error || projection.Error;

/// The result definition of `links.schema.json`.
pub const definition = "scenario_link";

/// An offered criterion's id within one request; it is not a record ID.
pub const CriterionId = struct {
    pub const model_scalar = "ordinal";
    ordinal: u32,
};
/// The answer: one offered criterion.
pub const Answer = struct { criterion: CriterionId };

const Offered = struct { id: CriterionId, given: []const u8, when: []const u8, then: []const u8 };

/// The records of the completed records unit, in authoring order.
pub fn unitRecords(current: session.Session) Error![]const g.spec.RecordProposal {
    const checked = current.units[session.records_index] orelse return error.InvalidSpecificationUnit;
    if (current.completed != session.unit_count or checked.response != .content) return error.InvalidSpecificationUnit;
    return g.recordCollection(.canonical, checked.response.content) orelse return error.InvalidSpecificationUnit;
}

/// What the completed records unit needs, recomputed from the unit alone. Like `limit` and
/// `begin`, it takes an arena the caller releases (see `scenario_link.plan`).
pub fn planFor(allocator: std.mem.Allocator, current: session.Session) Error!link.Plan {
    return link.plan(allocator, try unitRecords(current));
}

/// The number of edge cases that need a model choice: the native population of the link loop.
pub fn limit(allocator: std.mem.Allocator, current: session.Session) Error!usize {
    return (try planFor(allocator, current)).pending.len;
}

/// Whether the completed records unit can be linked, and how many edge cases need a model choice.
pub const Planned = union(enum) { ready: usize, blocked: binding.Rejection };

/// An edge case no criterion of its records batch serves blocks the run: it has no outcome to
/// print, and neither the engine nor the model supplies one. The rejection names its source
/// group and claims.
pub fn begin(allocator: std.mem.Allocator, current: session.Session, context: p.Context) Error!Planned {
    const plan = try planFor(allocator, current);
    if (plan.unlinkable) |position| {
        const edge = (try unitRecords(current))[position];
        if (edge.source_group_ids.len != 1) return error.InvalidSpecificationUnit;
        return .{ .blocked = try binding.edgeCaseRejection(allocator, context.references, edge.source_group_ids[0], edge.provenance.claim_ids) };
    }
    return .{ .ready = plan.pending.len };
}

fn owner(allocator: std.mem.Allocator, current: session.Session, ordinal: usize) Error!identity.ImmutableUnitOwnerId {
    return .{ .specification_unit = .{
        .reference_state_id = .{ .bytes = current.reference_state.bytes },
        .feature_id = current.feature,
        .unit_slot_id = .{ .bytes = try std.fmt.allocPrint(allocator, "specification-links-{d}", .{ordinal + 1}) },
    } };
}

/// The request for the pending edge case after the `chosen` ones. The caller releases it.
pub fn packet(allocator: std.mem.Allocator, current: session.Session, context: p.Context, chosen: usize) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const records = try unitRecords(current);
    const plan = try link.plan(a, records);
    if (plan.unlinkable != null or chosen >= plan.pending.len) return error.InvalidScenarioLink;
    const pending = plan.pending[chosen];
    const edge = records[pending.edge_case];
    const condition = try projection.recordScalar(a, context, edge, edge.content.edge_case.condition);
    const offered = try a.alloc(Offered, pending.candidates.len);
    for (pending.candidates, offered, 1..) |position, *entry, id| {
        const criterion = records[position];
        const scenario = criterion.content.acceptance_criterion;
        entry.* = .{
            .id = .{ .ordinal = std.math.cast(u32, id) orelse return error.InvalidScenarioLink },
            .given = (try projection.recordScalar(a, context, criterion, scenario.given)).bytes,
            .when = (try projection.recordScalar(a, context, criterion, scenario.when)).bytes,
            .then = (try projection.recordScalar(a, context, criterion, scenario.then)).bytes,
        };
    }
    const payload = .{ .edge_case = condition.bytes, .acceptance_criteria = @as([]const Offered, offered) };
    const body = try json.encodeEvidence(@TypeOf(payload), a, payload);
    const ids = try a.alloc(i64, offered.len);
    for (offered, ids) |entry, *id| id.* = entry.id.ordinal;
    const base = try packets.create(allocator, body, try owner(a, current, chosen), .initial_generation, .{ .bytes = definition });
    defer packets.release(base);
    return packets.withIntegerChoices(allocator, base, &.{.{
        .target = .{ .path = &.{.{ .property = "criterion" }} },
        .definition = .{ .bytes = definition },
        .allowed = ids,
    }});
}

/// The link the model's answer makes for the pending edge case after the `chosen` ones. The
/// packet must be the one native code builds now, and the answer one of its offered criteria.
pub fn admit(allocator: std.mem.Allocator, current: session.Session, context: p.Context, chosen: usize, request: *const packets.Packet, body: []const u8) Error!link.Link {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const expected = try packet(a, current, context, chosen);
    defer packets.release(expected);
    if (!std.mem.eql(u8, expected.body(), request.body()) or
        !identity.unitOwnerEql(expected.unit(), request.unit()) or
        request.purpose() != .initial_generation or
        !std.mem.eql(u8, expected.resultDefinition().?.bytes, (request.resultDefinition() orelse return error.InvalidScenarioLink).bytes)) return error.InvalidScenarioLink;
    const answer = try json.decode(Answer, a, body);
    const plan = try link.plan(a, try unitRecords(current));
    const pending = plan.pending[chosen];
    if (answer.criterion.ordinal == 0 or answer.criterion.ordinal > pending.candidates.len) return error.InvalidScenarioLink;
    const choice: link.Link = .{ .edge_case = pending.edge_case, .criterion = pending.candidates[answer.criterion.ordinal - 1] };
    if (!link.admits(pending, choice)) return error.InvalidScenarioLink;
    return choice;
}
