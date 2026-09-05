const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const binding = @import("llm_provider_binding.zig");
const lifecycle = @import("provider_operation_lifecycle.zig");

/// Exact runner-retained call inputs. No identity is recovered from model text.
pub const Call = struct {
    request: *const provider.IdentifiedProviderNeutralModelRequest,
    provider_binding: *const binding.ValidatedProviderModelBinding,
    operations: *const lifecycle.Ledger,
    operation_id: provider.ProviderOperationId,
};

pub const ValidationError = error{
    InvalidProviderInvocationContext,
    ProviderInvocationAssociationInvalid,
    InvalidProviderTokenUsage,
};
pub const Error = ValidationError || std.mem.Allocator.Error;

pub const Result = union(enum) {
    complete: *const CompleteCandidate,
    stopped: provider.ProviderNonCandidateStopReason,
    failed: provider.ProviderFailure,
};

/// An association/content-safety proof, not schema validity, usage accounting,
/// workflow success or permission to send another request.
pub const Evidence = opaque {
    pub fn request(self: *const Evidence) *const provider.IdentifiedProviderNeutralModelRequest {
        return storage(self).request;
    }

    pub fn operationId(self: *const Evidence) provider.ProviderOperationId {
        return storage(self).operation_id;
    }

    pub fn usage(self: *const Evidence) ?provider.ProviderUsage {
        return storage(self).usage;
    }

    pub fn providerLatencyMs(self: *const Evidence) ?u32 {
        return storage(self).provider_latency_ms;
    }

    pub fn delivery(self: *const Evidence) provider.ProviderDeliveryDisposition {
        return switch (storage(self).result) {
            .complete, .stopped => .response_received,
            .failed => |failure| failure.delivery,
        };
    }

    pub fn result(self: *const Evidence) Result {
        return switch (storage(self).result) {
            .complete => .{ .complete = @ptrCast(self) },
            .stopped => |reason| .{ .stopped = reason },
            .failed => |failure| .{ .failed = failure },
        };
    }
};

/// Only the complete branch can produce this decoder input. Its content remains
/// untrusted; the decoder uses the retained request's exact compiled schema.
pub const CompleteCandidate = opaque {
    pub fn association(self: *const CompleteCandidate) *const Evidence {
        return @ptrCast(self);
    }

    pub fn content(self: *const CompleteCandidate) []const u8 {
        return storage(self.association()).result.complete;
    }
};

/// Owns only the immutable proof metadata. Request/graph authority and complete
/// response bytes are borrowed and must outlive it. Validation never consumes,
/// clones or frees the caller's observation, including on rejection or OOM.
pub const Owned = struct {
    allocator: std.mem.Allocator,
    evidence: *const Evidence,

    pub fn deinit(self: *Owned) void {
        self.allocator.destroy(storage(self.evidence));
        self.* = undefined;
    }
};

const Storage = struct {
    request: *const provider.IdentifiedProviderNeutralModelRequest,
    operation_id: provider.ProviderOperationId,
    usage: ?provider.ProviderUsage = null,
    provider_latency_ms: ?u32 = null,
    result: union(enum) {
        complete: []const u8,
        stopped: provider.ProviderNonCandidateStopReason,
        failed: provider.ProviderFailure,
    },
};

fn storage(evidence: *const Evidence) *const Storage {
    return @ptrCast(@alignCast(evidence));
}

pub fn validate(allocator: std.mem.Allocator, call: Call, observation: *const provider.ProviderInvocationObservation) Error!Owned {
    const request = call.request;
    const invoked = call.operations.requireInvoked(call.operation_id) catch return error.InvalidProviderInvocationContext;
    const record = call.operations.record(call.operation_id) orelse return error.InvalidProviderInvocationContext;
    if (!provider.validateInferenceInvocation(call.provider_binding, request, invoked) or
        !record.binding_id.eql(request.binding_id) or
        !record.model_visible_input_id.eql(request.model_visible_input_id)) return error.InvalidProviderInvocationContext;
    var validated: Storage = .{
        .request = request,
        .operation_id = invoked.id,
        .result = undefined,
    };
    switch (observation.*) {
        .failed => |failure| {
            if (!failure.operation_id.eql(invoked.id)) return error.ProviderInvocationAssociationInvalid;
            validated.result = .{ .failed = failure };
        },
        .completed => |completed| {
            if (!completed.operation_id.eql(invoked.id)) return error.ProviderInvocationAssociationInvalid;
            switch (completed.raw_result) {
                inline .complete, .stopped => |result| {
                    if (result.request_id != request.model_request_id or
                        !result.binding_id.eql(request.binding_id)) return error.ProviderInvocationAssociationInvalid;
                    validated.usage = provider.ProviderUsage.init(result.usage.input_tokens, result.usage.output_tokens, result.usage.total_tokens) orelse return error.InvalidProviderTokenUsage;
                    validated.provider_latency_ms = result.provider_latency_ms;
                },
            }
            validated.result = switch (completed.raw_result) {
                .stopped => |result| .{ .stopped = result.reason },
                .complete => |result| complete: {
                    provider.CompleteOwnedUtf8.validate(result.content.bytes) catch {
                        // Keep valid reported usage even when content is unsafe.
                        // This is a provider-boundary failure, never JSON repair.
                        break :complete .{ .failed = .{
                            .operation_id = invoked.id,
                            .cause = .response_invalid,
                            .retry_class = .never,
                            .delivery = .response_received,
                        } };
                    };
                    break :complete .{ .complete = result.content.bytes };
                },
            };
        },
    }
    const owned = try allocator.create(Storage);
    owned.* = validated;
    return .{ .allocator = allocator, .evidence = @ptrCast(owned) };
}
