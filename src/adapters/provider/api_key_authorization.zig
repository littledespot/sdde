//! One in-memory API-key authorization mechanism for every key-based provider
//! family. Each deposited capability names its family, so another family's
//! capability never yields this family's key. No reads or network I/O.
const std = @import("std");
const preparation = @import("../../ports/provider_operation_authorization.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");
const key = @import("provider_api_key.zig");

pub const Adapter = struct {
    allocator: std.mem.Allocator,
    materials: key.Materials = .{},

    pub fn deinit(self: *Adapter) void {
        self.materials.deinit();
    }

    pub fn port(self: *Adapter) preparation.Port {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare };
    }

    fn prepare(context: *preparation.Context, facts: preparation.Facts, slot: preparation.Slot) preparation.Error!preparation.Observation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const family = key.Family.of(facts.provider_binding.registry_entry.config) orelse return .{ .failed = .authorization_denied };
        const snapshot = switch (self.materials.get(family).*) {
            .unavailable => return .{ .failed = .authentication_failed },
            .allocation_failed => return error.OutOfMemory,
            .ready => |*value| value,
        };
        const payload = try self.allocator.create(Payload);
        payload.* = .{ .allocator = self.allocator, .family = family, .snapshot = snapshot };
        var capability: lease.Capability = .{ .payload = @ptrCast(payload), .destroy_fn = destroy };
        defer capability.deinit();
        try slot.deposit(facts, &capability);
        return .prepared;
    }
};

// The invocation-owned snapshot outlives the runner's table and each call.
const Payload = struct { allocator: std.mem.Allocator, family: key.Family, snapshot: *const key.Snapshot };

/// The key of a capability deposited for exactly this family.
pub fn secret(capability: *const lease.Capability, family: key.Family) ?[]const u8 {
    if (capability.destroy_fn != destroy) return null;
    const raw = capability.payload orelse return null;
    const payload: *const Payload = @ptrCast(@alignCast(raw));
    if (payload.family != family) return null;
    return payload.snapshot.bytes;
}

fn destroy(raw: *lease.CapabilityPayload) void {
    const payload: *Payload = @ptrCast(@alignCast(raw));
    payload.allocator.destroy(payload);
}

fn foreignDestroy(_: *lease.CapabilityPayload) void {}

test "a deposited capability yields its key only to its own family" {
    const a = std.testing.allocator;
    var snapshot = (try key.Snapshot.capture(a, "family-key")).?;
    defer snapshot.deinit();
    const payload = try a.create(Payload);
    payload.* = .{ .allocator = a, .family = .aws_bedrock, .snapshot = &snapshot };
    var capability: lease.Capability = .{ .payload = @ptrCast(payload), .destroy_fn = destroy };
    defer capability.deinit();
    try std.testing.expectEqualStrings("family-key", secret(&capability, .aws_bedrock).?);
    try std.testing.expect(secret(&capability, .anthropic) == null);
    // A payload behind another mechanism's destructor is never read as a key.
    const foreign: lease.Capability = .{ .payload = capability.payload, .destroy_fn = foreignDestroy };
    try std.testing.expect(secret(&foreign, .aws_bedrock) == null);
    const empty: lease.Capability = .{ .payload = null, .destroy_fn = destroy };
    try std.testing.expect(secret(&empty, .aws_bedrock) == null);
}
