const std = @import("std");
const operations = @import("../ports/workflow_operation_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const execution = @import("../domain/workflow_execution.zig");
const envelope = @import("../domain/model_envelope.zig");
const observation = @import("provider_observation_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

pub const schema = values.schema(.model_envelope_result, Result, 1, null).captured().recorded();
pub const Rejection = struct {
    reason: envelope.Rejection,
    diagnostic: envelope.Diagnostic,
};
pub const Outcome = union(enum) {
    decoded: *const envelope.Candidate,
    protocol_rejected: Rejection,
    not_decoded: *const observation.Result,
};

/// Syntax and mechanical text composition only; the original observation owns association.
pub const Result = opaque {
    pub fn source(self: *const Result) *const observation.Result {
        return storage(self).source;
    }

    pub fn outcome(self: *const Result) Outcome {
        const owner = storage(self);
        return switch (owner.outcome) {
            .decoded => |owned| .{ .decoded = owned.candidate },
            .protocol_rejected => |reason| .{ .protocol_rejected = reason },
            .not_decoded => .{ .not_decoded = owner.source },
        };
    }
};

pub fn complete(source: *const observation.Result) ?*const @import("../domain/provider_invocation_validation.zig").CompleteCandidate {
    return switch (source.outcome()) {
        .validated => |evidence| switch (evidence.result()) {
            .complete => |candidate| candidate,
            .stopped, .failed => null,
        },
        .rejected, .cancelled => null,
    };
}

/// Consumes the decoder tree/diagnostic on every path and retains its observation.
/// Response admission publishes this sealed result.
pub fn capture(allocator: std.mem.Allocator, view: *const data.View, decoded: ?envelope.Error!envelope.Owned, diagnostic: ?envelope.Diagnostic) operations.Error!*data.Value {
    var outcome: Decoded = if (decoded) |result| decoded_result: {
        const owned = result catch |err| break :decoded_result switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidModelEnvelope => .{ .protocol_rejected = .{ .reason = error.InvalidModelEnvelope, .diagnostic = diagnostic orelse return error.ProtocolDiagnosticMissing } },
        };
        break :decoded_result .{ .decoded = owned };
    } else .not_decoded;
    errdefer release(allocator, &outcome);
    const source = try observation.readCurrent(view);
    if ((complete(source) != null) != (decoded != null)) return error.DecodeEvidenceInconsistent;
    if (outcome == .decoded and outcome.decoded.candidate.association() != complete(source).?.association()) return error.DecodeEvidenceInconsistent;
    const owner = allocator.create(Owner) catch |operation_error| return operation_error;
    errdefer allocator.destroy(owner);
    const retained = values.retain(view.slots[@intFromEnum(observation.schema.key)].?) catch |operation_error| return operation_error;
    errdefer values.destroy(retained);
    owner.* = .{ .allocator = allocator, .retained = retained, .source = source, .outcome = outcome };
    return values.adopt(allocator, schema, Result, Owner, owner, Owner.view, Owner.destroy, null) catch |operation_error| operation_error;
}

const Decoded = union(enum) { decoded: envelope.Owned, protocol_rejected: Rejection, not_decoded };

fn release(allocator: std.mem.Allocator, outcome: *Decoded) void {
    switch (outcome.*) {
        .decoded => |*owned| owned.deinit(),
        .protocol_rejected => |rejected| rejected.diagnostic.deinit(allocator),
        .not_decoded => {},
    }
}

/// The sealed source owns association; consumers do not revalidate provider data.
pub fn readCurrent(view: *const data.View) operations.Error!*const Result {
    const result = values.read(view, schema, Result) catch |operation_error| return operation_error;
    try observation.requireCurrent(view, result.source());
    return result;
}

pub fn status(result: *const Result) @import("../domain/workflow.zig").OutcomeTag {
    return switch (result.outcome()) {
        .decoded => .ok,
        .protocol_rejected => .invalid,
        .not_decoded => |source| switch (source.outcome()) {
            // A missing final answer takes correction, and a first runaway its
            // one re-send (ADR 0039); neither is a candidate.
            .validated => |evidence| if (evidence.missingFinalText() or evidence.runaway() == .first) .invalid else observation.status(source),
            .rejected, .cancelled => observation.status(source),
        },
    };
}

const Owner = struct {
    allocator: std.mem.Allocator,
    retained: *data.Value,
    source: *const observation.Result,
    outcome: Decoded,

    fn view(self: *const Owner) *const Result {
        return @ptrCast(self);
    }

    fn destroy(self: *Owner) void {
        release(self.allocator, &self.outcome);
        values.destroy(self.retained);
        self.allocator.destroy(self);
    }
};

fn storage(result: *const Result) *const Owner {
    return @ptrCast(@alignCast(result));
}
