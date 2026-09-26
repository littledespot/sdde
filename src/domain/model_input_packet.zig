//! Immutable native input for one model assignment. Identity and purpose are
//! internal; only body is model-visible. No prompt, schema or provider policy.
const std = @import("std");
const identity = @import("model_request_identity.zig");
const schema = @import("model_result_schema.zig");
const retry = @import("workflow_retry.zig");
const Origin = @import("model_candidate_origin.zig").Origin;
pub const Error = identity.Error || error{InvalidModelInputPacket};
pub const Packet = opaque {
    pub fn body(self: *const Packet) []const u8 {
        return storage(self).body;
    }
    pub fn unit(self: *const Packet) identity.ImmutableUnitOwnerId {
        return storage(self).unit;
    }
    pub fn purpose(self: *const Packet) identity.RequestPurposeBinding {
        return storage(self).purpose;
    }
    pub fn resultDefinition(self: *const Packet) ?schema.DefinitionId {
        return storage(self).result_definition;
    }
    pub fn repairPermit(self: *const Packet) ?retry.Permit {
        return storage(self).repair;
    }
    pub fn repairOrigin(self: *const Packet) ?Origin {
        return storage(self).repair_origin;
    }
    pub fn excludedVariants(self: *const Packet) []const schema.ExcludedVariant {
        return storage(self).excluded_variants;
    }
    pub fn integerChoices(self: *const Packet) []const schema.IntegerChoice {
        return storage(self).integer_choices;
    }
};
const Storage = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    references: usize = 1,
    body: []const u8,
    unit: identity.ImmutableUnitOwnerId,
    purpose: identity.RequestPurposeBinding,
    result_definition: ?schema.DefinitionId = null,
    repair: ?retry.Permit = null,
    repair_origin: ?Origin = null,
    excluded_variants: []const schema.ExcludedVariant = &.{},
    integer_choices: []const schema.IntegerChoice = &.{},
    handle: Handle,
};
const Handle = struct { owner: *Storage };
pub fn create(allocator: std.mem.Allocator, body: []const u8, unit: identity.ImmutableUnitOwnerId, purpose: identity.RequestPurposeBinding, result_definition: ?schema.DefinitionId) Error!*Packet {
    return createBound(allocator, body, unit, purpose, result_definition, null, null);
}
/// Native repair authority is retained out of band; it is never model input.
pub fn createRepair(allocator: std.mem.Allocator, body: []const u8, unit: identity.ImmutableUnitOwnerId, purpose: identity.RequestPurposeBinding, result_definition: ?schema.DefinitionId, permit: retry.Permit, origin: ?Origin) Error!*Packet {
    if (purpose != .atomic_repair or permit.revision == 0 or permit.maximum_targets == 0) return error.InvalidModelInputPacket;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(purpose.atomic_repair.bytes, &digest, .{});
    if (!std.mem.eql(u8, &digest, &permit.authorization)) return error.InvalidModelInputPacket;
    return createBound(allocator, body, unit, purpose, result_definition, permit, origin);
}
fn createBound(allocator: std.mem.Allocator, body: []const u8, unit: identity.ImmutableUnitOwnerId, purpose: identity.RequestPurposeBinding, result_definition: ?schema.DefinitionId, permit: ?retry.Permit, origin: ?Origin) Error!*Packet {
    try identity.validateUnitOwner(unit);
    if (body.len == 0 or !std.unicode.utf8ValidateSlice(body)) return error.InvalidModelInputPacket;
    // Follow-up requests retain their parent through the request ledger, not a
    // loose packet pointer. No such producer is registered at this boundary.
    if (purpose == .context_followup) return error.InvalidModelInputPacket;
    const owner = try allocator.create(Storage);
    owner.* = .{ .allocator = allocator, .arena = .init(allocator), .body = &.{}, .unit = .workflow_step, .purpose = .initial_generation, .handle = .{ .owner = owner } };
    errdefer release(@ptrCast(&owner.handle));
    const arena = owner.arena.allocator();
    owner.body = try arena.dupe(u8, body);
    if (result_definition) |id| {
        _ = schema.DefinitionId.parse(id.bytes) orelse return error.InvalidModelInputPacket;
        owner.result_definition = .{ .bytes = try arena.dupe(u8, id.bytes) };
    }
    owner.unit = try identity.cloneUnitOwner(arena, unit);
    owner.repair = permit;
    owner.repair_origin = origin;
    owner.purpose = switch (purpose) {
        .initial_generation => .initial_generation,
        .atomic_repair => |id| .{ .atomic_repair = .{ .bytes = try arena.dupe(u8, id.bytes) } },
        .semantic_review => |id| .{ .semantic_review = .{ .bytes = try arena.dupe(u8, id.bytes) } },
        .clarification_resolution => |value| .{ .clarification_resolution = .{ .clarification_state_id = .{ .bytes = try arena.dupe(u8, value.clarification_state_id.bytes) }, .clarification_state_revision = value.clarification_state_revision, .clarification_id = .{ .bytes = try arena.dupe(u8, value.clarification_id.bytes) } } },
        .context_followup => unreachable,
    };
    return @ptrCast(&owner.handle);
}
pub fn retain(packet: *const Packet) Error!*const Packet {
    const owner = storage(packet);
    owner.references = std.math.add(usize, owner.references, 1) catch return error.InvalidModelInputPacket;
    return packet;
}
pub fn release(packet: *const Packet) void {
    const owner = storage(packet);
    std.debug.assert(owner.references != 0);
    owner.references -= 1;
    if (owner.references != 0) return;
    owner.arena.deinit();
    owner.allocator.destroy(owner);
}
pub fn view(packet: *const Packet) *const Packet {
    return packet;
}

/// Copy native availability facts across packet projections. No model bytes
/// can create or change these restrictions.
pub fn withExcludedVariants(allocator: std.mem.Allocator, base: *const Packet, excluded: []const schema.ExcludedVariant) Error!*Packet {
    return withRestrictions(allocator, base, excluded, base.integerChoices());
}

pub fn withRestrictions(allocator: std.mem.Allocator, base: *const Packet, excluded: []const schema.ExcludedVariant, choices: []const schema.IntegerChoice) Error!*Packet {
    const result = try createBound(allocator, base.body(), base.unit(), base.purpose(), base.resultDefinition(), base.repairPermit(), base.repairOrigin());
    errdefer release(result);
    const a = storage(result).arena.allocator();
    const copy = try a.alloc(schema.ExcludedVariant, excluded.len);
    for (excluded, copy) |entry, *destination| destination.* = .{ .kind = try a.dupe(u8, entry.kind) };
    storage(result).excluded_variants = copy;
    const selected = try a.alloc(schema.IntegerChoice, choices.len);
    for (choices, selected) |entry, *destination| {
        destination.* = .{
            .kind = try a.dupe(u8, entry.kind),
            .field = try a.dupe(u8, entry.field),
            .allowed = try a.dupe(i64, entry.allowed),
        };
    }
    storage(result).integer_choices = selected;
    return result;
}
/// Add one typed read-context projection without changing request ownership.
pub fn withContext(comptime T: type, allocator: std.mem.Allocator, base: *const Packet, comptime field: []const u8, context: T) (Error || @import("strict_json.zig").Error)!*Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const bytes = try @import("model_candidate_json.zig").encode(T, scratch, context);
    var parsed = try @import("strict_json.zig").parse(scratch, bytes, .{ .maximum_depth = schema.max_json_depth }, false, null);
    defer parsed.deinit();
    return withJsonContext(allocator, base, field, parsed.value);
}

/// Already admitted JSON uses the same packet projection as typed context.
pub fn withJsonContext(allocator: std.mem.Allocator, base: *const Packet, comptime field: []const u8, context: std.json.Value) (Error || @import("strict_json.zig").Error)!*Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const strict = @import("strict_json.zig");
    const limits: strict.Limits = .{ .maximum_depth = schema.max_json_depth };
    // Context placement is structural: retain number lexemes instead of
    // converting evidence to machine floats or integers and back.
    var input = try strict.parse(scratch, base.body(), limits, false, null);
    defer input.deinit();
    if (input.value != .object or input.value.object.contains(field)) return error.InvalidModelInputPacket;
    try input.value.object.put(input.arena.allocator(), field, context);
    const body = try std.json.Stringify.valueAlloc(scratch, input.value, .{});
    const result = if (base.repairPermit()) |permit| try createRepair(allocator, body, base.unit(), base.purpose(), base.resultDefinition(), permit, base.repairOrigin()) else try create(allocator, body, base.unit(), base.purpose(), base.resultDefinition());
    defer release(result);
    return withRestrictions(allocator, result, base.excludedVariants(), base.integerChoices());
}
fn storage(packet: *const Packet) *Storage {
    const handle: *const Handle = @ptrCast(@alignCast(packet));
    return handle.owner;
}

/// Omit absent presentation fields only; retained native evidence is unchanged.
pub fn omitAbsent(value: *std.json.Value) void {
    if (value.* != .object) return;
    var index: usize = 0;
    while (index < value.object.count()) {
        if (value.object.values()[index] == .null) {
            value.object.orderedRemoveAt(index);
        } else index += 1;
    }
}
