//! Spec authoring assignments over validated reference signals. Signal roles
//! are semantic choices; this module only resolves their recorded occurrences.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const refs = @import("reference_support.zig");
const spec = @import("specification.zig");
const evidence = @import("reference_evidence.zig");

pub const Error = r.Error || spec.Error || error{InvalidSpecificationBinding};
pub const Unit = union(enum) { brief, primary_user_story, entities, records };
pub const Bound = union(enum) {
    brief: struct { title: spec.Selection, description: spec.Selection, primary_goal: spec.Selection },
    primary_user_story: spec.Selection,
    entities: spec.Selection,
    records: struct { signal: r.SignalId, selection: spec.Selection },
};

/// Presentation of the already bound source selection. Claims and their meaning
/// remain in the packet's single evidence catalogue; this view grants no authority.
pub const FieldGuidance = struct { purpose: []const u8, claim_ids: []const r.ClaimId };
pub const Guidance = union(enum) {
    brief: struct { title: FieldGuidance, description: FieldGuidance, primary_goal: FieldGuidance },
    primary_user_story: FieldGuidance,
    entities: FieldGuidance,
    records: struct { purpose: []const u8, signal: r.SignalId, claim_ids: []const r.ClaimId },
};

pub fn guidance(a: std.mem.Allocator, bound: Bound) Error!Guidance {
    return switch (bound) {
        .brief => |value| .{ .brief = .{
            .title = try fieldGuidance(a, .title, value.title),
            .description = try fieldGuidance(a, .description, value.description),
            .primary_goal = try fieldGuidance(a, .primary_goal, value.primary_goal),
        } },
        .primary_user_story => |value| .{ .primary_user_story = try fieldGuidance(a, .primary_user_story, value) },
        .entities => |value| .{ .entities = try fieldGuidance(a, .entity_basis, value) },
        .records => |value| .{ .records = .{
            .purpose = try rolePurpose(a, .records),
            .signal = value.signal,
            .claim_ids = value.selection.claim_ids,
        } },
    };
}

fn fieldGuidance(a: std.mem.Allocator, role: r.GenerationRole, selected: spec.Selection) Error!FieldGuidance {
    return .{ .purpose = try rolePurpose(a, role), .claim_ids = selected.claim_ids };
}
fn rolePurpose(a: std.mem.Allocator, role: r.GenerationRole) Error![]const u8 {
    return role.purpose(a) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidRequiredAuthority => error.InvalidSpecificationBinding,
    };
}

fn hasRole(signal: r.Signal, role: r.GenerationRole) bool {
    return std.mem.indexOfScalar(r.GenerationRole, signal.value.generation_roles, role) != null;
}

fn activeSignal(records: refs.Records, signal: r.Signal) Error!bool {
    if (signal.value.claim_ids.len == 0) return error.InvalidSpecificationBinding;
    for (signal.value.claim_ids) |id| {
        const disposition = for (records.dispositions) |value| {
            if (value.claim_id.ordinal == id.ordinal) break value.disposition;
        } else return error.InvalidSpecificationBinding;
        if (disposition != .retained) return false;
    }
    return true;
}

fn checked(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, claims: []const r.ClaimId) Error!spec.Selection {
    if (claims.len == 0) return error.InvalidSpecificationBinding;
    const selected = refs.select(a, records.items, inputs, claims) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidSpecificationBinding,
    };
    defer a.free(selected.citation_ids);
    defer a.free(selected.scopes);
    for (selected.claim_ids) |id| {
        for (records.dispositions) |disposition| {
            if (disposition.claim_id.ordinal != id.ordinal) continue;
            if (disposition.disposition != .retained) return error.InvalidSpecificationBinding;
            break;
        } else return error.InvalidSpecificationBinding;
    }
    return .{ .claim_ids = selected.claim_ids, .clarification_response_ids = &.{} };
}

pub fn roleClaims(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, role: r.GenerationRole) Error!spec.Selection {
    var claims: std.ArrayList(r.ClaimId) = .empty;
    for (records.signals) |signal| {
        if (!hasRole(signal, role) or !try activeSignal(records, signal)) continue;
        for (signal.value.claim_ids) |id| if (!r.contains(r.ClaimId, claims.items, id)) try claims.append(a, id);
    }
    return checked(a, records, inputs, claims.items);
}

pub fn recordCount(records: refs.Records) Error!usize {
    var count: usize = 0;
    for (records.signals) |signal| if (hasRole(signal, .records)) {
        if (try activeSignal(records, signal)) count += 1;
    };
    return count;
}

pub fn record(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, index: usize) Error!Bound {
    var cursor: usize = 0;
    for (records.signals) |signal| {
        if (!hasRole(signal, .records) or !try activeSignal(records, signal)) continue;
        if (cursor == index) return .{ .records = .{ .signal = signal.id, .selection = try checked(a, records, inputs, signal.value.claim_ids) } };
        cursor += 1;
    }
    return error.InvalidSpecificationBinding;
}

pub fn forUnit(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, unit: Unit, record_index: usize) Error!Bound {
    return switch (unit) {
        .brief => .{ .brief = .{
            .title = try roleClaims(a, records, inputs, .title),
            .description = try roleClaims(a, records, inputs, .description),
            .primary_goal = try roleClaims(a, records, inputs, .primary_goal),
        } },
        .primary_user_story => .{ .primary_user_story = try roleClaims(a, records, inputs, .primary_user_story) },
        .entities => .{ .entities = try roleClaims(a, records, inputs, .entity_basis) },
        .records => record(a, records, inputs, record_index),
    };
}

/// Validate role coverage and stale or ineligible groups before any model call.
pub fn validate(records: refs.Records, inputs: evidence.Inputs) Error!void {
    if (!records.items.state_id.eql(inputs.corpus.state_id)) return error.InvalidSpecificationBinding;
    inline for (std.meta.tags(r.GenerationRole)) |role| {
        var found = false;
        for (records.signals) |signal| if (hasRole(signal, role)) {
            if (!try activeSignal(records, signal)) continue;
            found = true;
            break;
        };
        if (!found) return error.InvalidSpecificationBinding;
    }
    for (records.signals) |signal| {
        if (signal.value.generation_roles.len == 0) continue;
        if (signal.value.claim_ids.len == 0) return error.InvalidSpecificationBinding;
        try r.unique(r.ClaimId, signal.value.claim_ids);
        if (!try activeSignal(records, signal)) continue;
        for (signal.value.claim_ids) |id| {
            const item = try r.item(records.items, id);
            var retained = false;
            for (records.dispositions) |disposition| if (disposition.claim_id.ordinal == id.ordinal) {
                retained = disposition.disposition == .retained;
                break;
            };
            if (!retained) return error.InvalidSpecificationBinding;
            _ = evidence.resolve(inputs, .{ .state_id = records.items.state_id, .chunk_id = item.claim.chunk_id }) catch return error.InvalidSpecificationBinding;
        }
    }
}
