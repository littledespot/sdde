const std = @import("std");
const operation = @import("../domain/llm_provider_operation.zig");
const binding = @import("../domain/llm_provider_binding.zig");
const lease = @import("provider_authorization_lease.zig");
const data = @import("../domain/pipeline_data.zig");

pub const value_schema: data.Schema = .{
    .key = .validated_provider_authorization,
    .version = 1,
    .type_name = @typeName(operation.ValidatedProviderAuthorizationLeaseRef),
    .maximum_bytes = 128,
};

pub const Error = std.mem.Allocator.Error || lease.Error;
pub const Context = opaque {};
pub const SlotIdentity = opaque {};

pub const Facts = struct {
    provider_binding: *const binding.ValidatedProviderModelBinding,
    request: *const operation.IdentifiedProviderNeutralModelRequest,
    operation_id: operation.ProviderOperationId,
    deadline_monotonic_ms: u64,
};

/// Allows deposit into exactly one allocated slot, not table lookup/consumption.
pub const Slot = struct {
    context: *Context,
    identity: *const SlotIdentity,
    deposit_fn: *const fn (*Context, *const SlotIdentity, Facts, *lease.Capability) lease.Error!void,

    pub fn deposit(self: Slot, facts: Facts, capability: *lease.Capability) lease.Error!void {
        return self.deposit_fn(self.context, self.identity, facts, capability);
    }
};

/// Runner-to-action binding. Infrastructure receives only its deposit member.
pub const AllocatedSlot = struct {
    deposit: Slot,
    publish_fn: *const fn (*Context, *const SlotIdentity) Error!*data.Value,

    /// Returns a typed immutable reference value only after the deposit is
    /// validated. It exposes neither table operations nor capability bytes.
    pub fn publish(self: AllocatedSlot) Error!*data.Value {
        return self.publish_fn(self.deposit.context, self.deposit.identity);
    }
};

pub const Observation = union(enum) {
    prepared,
    failed: enum { authentication_failed, authorization_denied },
};

/// Preparation uses only already-loaded material. No I/O or refresh dependency
/// is provided; the concrete adapter owns the closed preloaded payload type.
pub const Port = struct {
    context: *Context,
    prepare_fn: *const fn (*Context, Facts, Slot) Error!Observation,

    pub fn prepare(self: Port, facts: Facts, slot: Slot) Error!Observation {
        return self.prepare_fn(self.context, facts, slot);
    }
};
