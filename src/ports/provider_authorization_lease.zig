const operation = @import("../domain/llm_provider_operation.zig");
const binding = @import("../domain/llm_provider_binding.zig");
const pipeline = @import("../domain/pipeline.zig");

pub const Error = error{ AuthorizationDenied, AuthorizationExpired, ClockUnavailable, Cancelled };
pub const Context = opaque {};
pub const CapabilityPayload = opaque {};

/// One owned, nonserializable capability. The payload and destructor belong to
/// infrastructure. Transfer by take(), never copy a live owner.
pub const Capability = struct {
    payload: ?*CapabilityPayload,
    destroy_fn: *const fn (*CapabilityPayload) void,

    pub fn take(self: *Capability) Error!Capability {
        if (self.payload == null) return error.AuthorizationDenied;
        const result = self.*;
        self.payload = null;
        return result;
    }

    pub fn deinit(self: *Capability) void {
        if (self.payload) |payload| self.destroy_fn(payload);
        self.payload = null;
    }
};

/// Trusted monotonic clock injected by composition, not by workflow/model data.
pub const Clock = struct {
    context: *Context,
    now_fn: *const fn (*Context) error{ClockUnavailable}!u64,

    pub fn now(self: Clock) error{ClockUnavailable}!u64 {
        return self.now_fn(self.context);
    }
};

pub const Port = struct {
    context: *Context,
    clock: Clock,
    runtime: pipeline.NodeRuntime,
    consume_fn: *const fn (
        *Context,
        *const operation.ValidatedProviderAuthorizationLeaseRef,
        *const binding.ValidatedProviderModelBinding,
        *const operation.IdentifiedProviderNeutralModelRequest,
        *const operation.InvokedProviderOperation,
        Error!u64,
    ) Error!Capability,

    pub fn consume(
        self: Port,
        reference: *const operation.ValidatedProviderAuthorizationLeaseRef,
        provider_binding: *const binding.ValidatedProviderModelBinding,
        request: *const operation.IdentifiedProviderNeutralModelRequest,
        invoked: *const operation.InvokedProviderOperation,
    ) Error!Capability {
        const now: Error!u64 = switch (self.runtime.status()) {
            .active => self.clock.now(),
            .cancelled => error.Cancelled,
            .deadline_exhausted => error.AuthorizationExpired,
        };
        return self.consume_fn(self.context, reference, provider_binding, request, invoked, now);
    }
};
