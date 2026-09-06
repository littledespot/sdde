//! Immutable native input for one model assignment. Identity and purpose are
//! internal; only body is model-visible. No prompt, schema or provider policy.
const std = @import("std");
const identity = @import("model_request_identity.zig");
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
};
const Storage = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    references: usize = 1,
    body: []const u8,
    unit: identity.ImmutableUnitOwnerId,
    purpose: identity.RequestPurposeBinding,
    handle: Handle,
};
const Handle = struct { owner: *Storage };
pub fn create(allocator: std.mem.Allocator, body: []const u8, unit: identity.ImmutableUnitOwnerId, purpose: identity.RequestPurposeBinding) Error!*Packet {
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
    owner.unit = try identity.cloneUnitOwner(arena, unit);
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
fn storage(packet: *const Packet) *Storage {
    const handle: *const Handle = @ptrCast(@alignCast(packet));
    return handle.owner;
}
