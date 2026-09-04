const std = @import("std");
const preparation = @import("../../ports/provider_operation_authorization.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");

pub const Plan = union(enum) {
    prepared,
    failed: @FieldType(preparation.Observation, "failed"),
    cancelled,
};

/// Test infrastructure with preloaded material and no I/O dependency. Each
/// successful preparation deposits a distinct owned payload into its one slot.
pub const FakeProviderAuthorization = struct {
    allocator: std.mem.Allocator,
    plan: Plan = .prepared,
    prepare_count: usize = 0,
    prepared_count: usize = 0,
    destroyed_count: usize = 0,

    pub fn port(self: *FakeProviderAuthorization) preparation.Port {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare };
    }

    fn prepare(context: *preparation.Context, facts: preparation.Facts, slot: preparation.Slot) preparation.Error!preparation.Observation {
        const self: *FakeProviderAuthorization = @ptrCast(@alignCast(context));
        self.prepare_count += 1;
        switch (self.plan) {
            .failed => |cause| return .{ .failed = cause },
            .cancelled => return error.Cancelled,
            .prepared => {},
        }
        const payload = try self.allocator.create(Payload);
        payload.* = .{ .owner = self };
        self.prepared_count += 1;
        var capability: lease.Capability = .{ .payload = @ptrCast(payload), .destroy_fn = destroy };
        defer capability.deinit();
        try slot.deposit(facts, &capability);
        return .prepared;
    }
};

const Payload = struct { owner: *FakeProviderAuthorization };

fn destroy(raw: *lease.CapabilityPayload) void {
    const payload: *Payload = @ptrCast(@alignCast(raw));
    const owner = payload.owner;
    owner.destroyed_count += 1;
    owner.allocator.destroy(payload);
}
