//! The authentication of a run's closed forms (ADR 0025): which forms await an account, and the observations made so far,
//! one for each form already advanced past. Pure; the runner's iteration bounds the loop by the number of pending forms,
//! and each pass runs under its own lease.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const acceptance = @import("clarification_acceptance.zig");
const evidence = @import("actor_evidence.zig");

pub const Progress = struct {
    /// The forms to authenticate, in the registry's order.
    pending: []const c.Id,
    /// The observation made for each form already advanced past, in the same order.
    observations: []const evidence.Observation,
};
pub const Error = std.mem.Allocator.Error || error{InvalidClarificationInput};

pub fn plan(allocator: std.mem.Allocator, inputs: c.Inputs) std.mem.Allocator.Error!Progress {
    return .{ .pending = try acceptance.pending(allocator, inputs), .observations = &.{} };
}

/// Whether a form still awaits its observation.
pub fn more(progress: Progress) bool {
    return progress.observations.len < progress.pending.len;
}

/// Joins the next form's observation. An observation beyond the planned forms is no form's.
pub fn advance(allocator: std.mem.Allocator, progress: Progress, observation: evidence.Observation) Error!Progress {
    if (!more(progress)) return error.InvalidClarificationInput;
    const observations = try allocator.alloc(evidence.Observation, progress.observations.len + 1);
    @memcpy(observations[0..progress.observations.len], progress.observations);
    observations[progress.observations.len] = observation;
    return .{ .pending = progress.pending, .observations = observations };
}
