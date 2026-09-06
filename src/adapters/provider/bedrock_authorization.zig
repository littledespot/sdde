const std = @import("std");
const preparation = @import("../../ports/provider_operation_authorization.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");
const key = @import("bedrock_api_key.zig");

pub const Adapter = struct {
    allocator: std.mem.Allocator,
    material: key.Material = .unavailable,

    pub fn deinit(self: *Adapter) void {
        self.material.deinit();
    }

    pub fn port(self: *Adapter) preparation.Port {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare };
    }

    fn prepare(context: *preparation.Context, facts: preparation.Facts, slot: preparation.Slot) preparation.Error!preparation.Observation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        if (facts.provider_binding.registry_entry.config != .aws_bedrock) return .{ .failed = .authorization_denied };
        const snapshot = switch (self.material) {
            .unavailable => return .{ .failed = .authentication_failed },
            .allocation_failed => return error.OutOfMemory,
            .ready => |*value| value,
        };
        const payload = try self.allocator.create(Payload);
        payload.* = .{ .allocator = self.allocator, .snapshot = snapshot };
        var capability: lease.Capability = .{ .payload = @ptrCast(payload), .destroy_fn = destroy };
        defer capability.deinit();
        try slot.deposit(facts, &capability);
        return .prepared;
    }
};

// The invocation-owned snapshot outlives the runner's table and each call.
const Payload = struct { allocator: std.mem.Allocator, snapshot: *const key.Snapshot };

pub fn secret(capability: *const lease.Capability) ?[]const u8 {
    if (capability.destroy_fn != destroy) return null;
    const raw = capability.payload orelse return null;
    const payload: *const Payload = @ptrCast(@alignCast(raw));
    return payload.snapshot.bytes;
}

fn destroy(raw: *lease.CapabilityPayload) void {
    const payload: *Payload = @ptrCast(@alignCast(raw));
    payload.allocator.destroy(payload);
}
