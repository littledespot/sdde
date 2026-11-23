const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const acceptance = @import("../../domain/clarification_acceptance.zig");
const authentication = @import("../../domain/clarification_authentication.zig");
const evidence = @import("../../domain/actor_evidence.zig");

/// The closed set of internal steps, in execution order (ADR 0031).
pub const Step = enum { bind_forms, record_evidence, accept_responses, validate_responses };

/// Stage-owned diagnostic slot: the step a failing run stopped at, or the step a cancelled run did not start.
pub const Diagnostic = struct { step: ?Step = null };

pub const Error = evidence.Error || clarification.Error || error{Cancelled};

/// What crosses the stage edge: the clarification inputs with every authenticated form recorded as a response, and the
/// registry that holds the evidence of those responses.
pub const Outputs = struct { inputs: clarification.Inputs, registry: evidence.Registry };

/// The exact captured bytes of each pending form, in the order of the pending forms.
pub const Bound = struct { forms: []const []const u8 };

/// One stage: pair each authenticated form with its captured bytes, append the run's evidence to the registry in one
/// revision, accept each form as a response, and check that the responses join the registry (ADR 0025). Nothing is written
/// here: the accepted state and the registry stay in memory until the run publishes them.
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "accept-clarification-responses",
        .kind = .action,
        .requires = &.{ .clarification_inputs, .raw_clarification_inputs, .actor_evidence_registry, .authentication_progress },
        .produces = &.{},
        .replaces = &.{ .clarification_inputs, .actor_evidence_registry },
        .side_effect = .none,
    };

    pub fn execute(_: Action, scratch: std.mem.Allocator, runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic, inputs: clarification.Inputs, captures: clarification.Captures, prior: evidence.Registry, progress: authentication.Progress) Error!Outputs {
        try checkpoint(diagnostic, runtime, .bind_forms);
        const bound = steps.bindForms(scratch, inputs, captures, progress) catch |err| return stopped(diagnostic, .bind_forms, err);
        try checkpoint(diagnostic, runtime, .record_evidence);
        const recorded = steps.recordEvidence(scratch, prior, progress) catch |err| return stopped(diagnostic, .record_evidence, err);
        try checkpoint(diagnostic, runtime, .accept_responses);
        const accepted = steps.acceptResponses(scratch, inputs, progress, bound, recorded) catch |err| return stopped(diagnostic, .accept_responses, err);
        try checkpoint(diagnostic, runtime, .validate_responses);
        steps.validateResponses(recorded.registry, accepted) catch |err| return stopped(diagnostic, .validate_responses, err);
        return .{ .inputs = accepted, .registry = recorded.registry };
    }
};

fn stopped(diagnostic: *Diagnostic, step: Step, err: Error) Error {
    diagnostic.step = step;
    return err;
}

fn checkpoint(diagnostic: *Diagnostic, runtime: pipeline.NodeRuntime, next: Step) Error!void {
    if (runtime.status() != .active) return stopped(diagnostic, next, error.Cancelled);
}

/// The four internal steps. Each is one typed function with its own tests; none is registered, addressable or composable
/// from workflow YAML, and none reaches a port.
pub const steps = struct {
    /// The loop authenticated exactly the forms that still await an account, each once.
    pub fn bindForms(allocator: std.mem.Allocator, inputs: clarification.Inputs, captures: clarification.Captures, progress: authentication.Progress) clarification.Error!Bound {
        const expected = try acceptance.pending(allocator, inputs);
        if (progress.pending.len != expected.len or progress.observations.len != progress.pending.len) return error.InvalidClarificationInput;
        const forms = try allocator.alloc([]const u8, progress.pending.len);
        for (progress.pending, expected, forms) |id, planned, *bytes| {
            if (id.index() != planned.index()) return error.InvalidClarificationInput;
            bytes.* = for (captures.forms) |capture| {
                if (capture.id.index() == id.index()) break capture.bytes;
            } else return error.InvalidClarificationInput;
        }
        return .{ .forms = forms };
    }

    pub fn recordEvidence(allocator: std.mem.Allocator, prior: evidence.Registry, progress: authentication.Progress) evidence.Error!evidence.Recorded {
        return evidence.record(allocator, prior, progress.observations);
    }

    pub fn acceptResponses(allocator: std.mem.Allocator, inputs: clarification.Inputs, progress: authentication.Progress, bound: Bound, recorded: evidence.Recorded) clarification.Error!clarification.Inputs {
        const accepted = try allocator.alloc(acceptance.Accepted, progress.pending.len);
        for (progress.pending, bound.forms, recorded.appended, accepted) |id, bytes, entry, *item| item.* = .{ .id = id, .form_bytes = bytes, .evidence = entry };
        return acceptance.accept(allocator, inputs, accepted);
    }

    /// The accepted state's responses join the registry that now holds their evidence.
    pub fn validateResponses(registry: evidence.Registry, accepted: clarification.Inputs) evidence.Error!void {
        if (accepted.state.value) |state| try evidence.validateJoin(registry, state);
    }
};
