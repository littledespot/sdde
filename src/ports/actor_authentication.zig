const std = @import("std");
const evidence = @import("../domain/actor_evidence.zig");
const lease = @import("../domain/actor_authentication_lease.zig");
const pipeline = @import("../domain/pipeline.zig");

pub const Error = @import("../domain/operation_error.zig").ActorAuthentication;
pub const Context = opaque {};

/// The authentication port (ADR 0025): it observes the invoking account once, for one runner-issued lease. An account that
/// cannot be read, an unsupported operating system and a failing clock are typed errors, never an observation.
pub const Port = struct {
    context: *Context,
    observe_fn: *const fn (*Context, std.mem.Allocator) Error!evidence.Observation,

    /// A runtime that is no longer active cancels first. The lease is consumed before the account is read, so a second
    /// call with it, or a call with a lease that is no longer the outstanding one, observes nothing. The caller's
    /// allocator owns the observation.
    pub fn authenticate(self: Port, allocator: std.mem.Allocator, runtime: pipeline.NodeRuntime, granted: lease.Lease) Error!evidence.Observation {
        if (runtime.status() != .active) return error.Cancelled;
        granted.consume() catch return error.AuthenticationDenied;
        return self.observe_fn(self.context, allocator);
    }
};
