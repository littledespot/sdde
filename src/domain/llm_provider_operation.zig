const std = @import("std");
const binding = @import("llm_provider_binding.zig");
const request_identity = @import("model_request_identity.zig");
const execution_reference = @import("execution_reference.zig");
const model_controls = @import("model_controls.zig");

pub const ProviderOperationKind = enum {
    input_token_count,
    inference,
};

pub const ModelAttemptOrdinal = struct {
    value: u32,

    pub fn init(value: u32) ?ModelAttemptOrdinal {
        return if (value == 0) null else .{ .value = value };
    }
};

pub const ProviderOperationId = struct {
    model_request_id: *const request_identity.ModelRequestId,
    model_attempt_ordinal: ModelAttemptOrdinal,
    kind: ProviderOperationKind,

    pub fn eql(left: ProviderOperationId, right: ProviderOperationId) bool {
        return left.model_request_id == right.model_request_id and
            left.model_attempt_ordinal.value == right.model_attempt_ordinal.value and
            left.kind == right.kind;
    }
};

pub const InvokedProviderOperation = struct {
    id: ProviderOperationId,
    deadline_monotonic_ms: u64,

    pub fn init(
        id: ProviderOperationId,
        deadline_monotonic_ms: u64,
    ) ?InvokedProviderOperation {
        if (id.model_attempt_ordinal.value == 0 or deadline_monotonic_ms == 0) {
            return null;
        }
        return .{
            .id = id,
            .deadline_monotonic_ms = deadline_monotonic_ms,
        };
    }

    pub fn isValid(self: InvokedProviderOperation) bool {
        return self.id.model_attempt_ordinal.value != 0 and
            self.deadline_monotonic_ms != 0;
    }
};

pub const RequestSchemaId = struct {
    bytes: []const u8,

    pub fn parse(raw: []const u8) ?RequestSchemaId {
        return if (validAuthorityId(raw)) .{ .bytes = raw } else null;
    }
};

pub const ResultSchemaId = struct {
    bytes: []const u8,

    pub fn parse(raw: []const u8) ?ResultSchemaId {
        return if (validAuthorityId(raw)) .{ .bytes = raw } else null;
    }
};

pub const ModelVisibleInputId = struct {
    bytes: []const u8,

    pub fn parse(raw: []const u8) ?ModelVisibleInputId {
        return if (validAuthorityId(raw)) .{ .bytes = raw } else null;
    }

    pub fn eql(left: ModelVisibleInputId, right: ModelVisibleInputId) bool {
        return std.mem.eql(u8, left.bytes, right.bytes);
    }
};

pub const ModelVisibleContent = union(enum) {
    system: []const u8,
    guidance: []const u8,
    user: []const u8,
    evidence: []const u8,

    pub fn bytes(self: ModelVisibleContent) []const u8 {
        return switch (self) {
            inline else => |value| value,
        };
    }
};

pub const IdentifiedProviderNeutralModelRequest = struct {
    model_request_id: *const request_identity.ModelRequestId,
    model_operation_id: binding.WorkflowModelOperationId,
    binding_id: binding.ProviderModelBindingId,
    request_schema_id: RequestSchemaId,
    result_schema_id: ResultSchemaId,
    model_visible_input_id: ModelVisibleInputId,
    content: []const ModelVisibleContent,
    response_schema: *const @import("model_result_schema.zig").Schema,
    response_guidance_mode: model_controls.ResponseGuidanceMode,
    controls: model_controls.InferenceControls,

    pub fn init(value: IdentifiedProviderNeutralModelRequest) RequestError!IdentifiedProviderNeutralModelRequest {
        try value.validate();
        return value;
    }

    pub fn validate(self: IdentifiedProviderNeutralModelRequest) RequestError!void {
        if (!self.model_request_id.model_operation_id.eql(self.model_operation_id) or
            !self.binding_id.operation_id.eql(self.model_operation_id) or
            !self.binding_id.isValid() or
            RequestSchemaId.parse(self.request_schema_id.bytes) == null or
            ResultSchemaId.parse(self.result_schema_id.bytes) == null or
            ModelVisibleInputId.parse(self.model_visible_input_id.bytes) == null or
            self.content.len == 0 or
            (self.controls.temperature != null and
                model_controls.TemperaturePermille.init(self.controls.temperature.?.value) == null))
        {
            return error.InvalidProviderNeutralModelRequest;
        }

        for (self.content) |part| {
            const bytes = part.bytes();
            if (bytes.len == 0 or !std.unicode.utf8ValidateSlice(bytes)) {
                return error.InvalidProviderNeutralModelRequest;
            }
        }
    }

    pub fn matchesBinding(self: IdentifiedProviderNeutralModelRequest, selected: binding.ValidatedProviderModelBinding) bool {
        const supported = selected.registry_entry.capabilities;
        return supported.supports(selected.response_mode, selected.controls) and
            self.binding_id.eql(selected.bindingId()) and
            self.response_guidance_mode == selected.response_mode and
            std.meta.eql(self.controls, selected.controls);
    }
};

// A nonserializable identity, not a capability. Only its execution-owned table
// can resolve it; never dereference an unrecognized or foreign reference.
pub const ValidatedProviderAuthorizationLeaseRef = struct {
    identity: execution_reference.Ref,
};

pub const ProviderFailureCause = enum {
    authentication_failed,
    authorization_denied,
    request_rejected,
    model_unavailable,
    throttled,
    timeout,
    service_unavailable,
    transport_failed,
    response_invalid,
    exact_token_count_unavailable,
};

pub const ProviderRetryClass = enum {
    never,
    policy_eligible,
};

pub const ProviderDeliveryDisposition = enum {
    not_sent,
    response_received,
    accepted_or_unknown,
};

pub const ProviderFailure = struct {
    operation_id: ProviderOperationId,
    cause: ProviderFailureCause,
    retry_class: ProviderRetryClass,
    delivery: ProviderDeliveryDisposition,
};

pub const ProviderTokenCountObservation = union(enum) {
    counted: struct {
        operation_id: ProviderOperationId,
        binding_id: binding.ProviderModelBindingId,
        model_visible_input_id: ModelVisibleInputId,
        input_tokens: u64,
    },
    failed: ProviderFailure,
};

pub const ExactInputTokenCountEvidence = struct {
    count_operation_id: ProviderOperationId,
    binding_id: binding.ProviderModelBindingId,
    model_visible_input_id: ModelVisibleInputId,
    input_tokens: u64,

    pub fn fromObservation(
        observation: ProviderTokenCountObservation,
        request: IdentifiedProviderNeutralModelRequest,
        provider_binding: binding.ValidatedProviderModelBinding,
    ) Error!ExactInputTokenCountEvidence {
        if (!request.matchesBinding(provider_binding)) return error.InvalidExactTokenCountEvidence;
        const counted = switch (observation) {
            .counted => |value| value,
            .failed => return error.ExactTokenCountEvidenceUnavailable,
        };
        const expected_binding = provider_binding.bindingId();
        const evidence: ExactInputTokenCountEvidence = .{
            .count_operation_id = counted.operation_id,
            .binding_id = counted.binding_id,
            .model_visible_input_id = counted.model_visible_input_id,
            .input_tokens = counted.input_tokens,
        };
        if (!evidence.isValidFor(request, expected_binding)) {
            return error.InvalidExactTokenCountEvidence;
        }
        return evidence;
    }

    pub fn isValidFor(
        self: ExactInputTokenCountEvidence,
        request: IdentifiedProviderNeutralModelRequest,
        expected_binding: binding.ProviderModelBindingId,
    ) bool {
        if (self.count_operation_id.kind != .input_token_count or
            self.count_operation_id.model_attempt_ordinal.value == 0 or
            self.count_operation_id.model_request_id != request.model_request_id or
            !self.binding_id.eql(expected_binding) or
            !self.binding_id.eql(request.binding_id) or
            !self.model_visible_input_id.eql(request.model_visible_input_id))
        {
            return false;
        }
        return true;
    }
};

pub const ProviderUsage = struct {
    input_tokens: u64,
    output_tokens: u64,
    total_tokens: u64,

    pub fn init(input_tokens: u64, output_tokens: u64, total_tokens: u64) ?ProviderUsage {
        const sum = std.math.add(u64, input_tokens, output_tokens) catch return null;
        if (total_tokens != sum) return null;
        return .{
            .input_tokens = input_tokens,
            .output_tokens = output_tokens,
            .total_tokens = total_tokens,
        };
    }
};

pub const CompleteOwnedUtf8 = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,

    pub const ValidationError = error{
        InvalidUtf8,
    };
    pub const InitError = std.mem.Allocator.Error || ValidationError;

    pub fn validate(source: []const u8) ValidationError!void {
        if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidUtf8;
    }

    pub fn init(
        allocator: std.mem.Allocator,
        source: []const u8,
    ) InitError!CompleteOwnedUtf8 {
        try validate(source);
        return .{ .allocator = allocator, .bytes = try allocator.dupe(u8, source) };
    }

    pub fn deinit(self: *CompleteOwnedUtf8) void {
        self.allocator.free(self.bytes);
        self.* = undefined;
    }
};

pub const ProviderNonCandidateStopReason = enum {
    output_limit,
    content_filtered,
    unsupported_tool_request,
    malformed_output,
    context_limit,
};

pub const RawProviderModelResult = union(enum) {
    complete: struct {
        request_id: *const request_identity.ModelRequestId,
        binding_id: binding.ProviderModelBindingId,
        content: CompleteOwnedUtf8,
        usage: ProviderUsage,
        provider_latency_ms: ?u32,
    },
    stopped: struct {
        request_id: *const request_identity.ModelRequestId,
        binding_id: binding.ProviderModelBindingId,
        reason: ProviderNonCandidateStopReason,
        usage: ProviderUsage,
        provider_latency_ms: ?u32,
    },

    pub fn deinit(self: *RawProviderModelResult) void {
        switch (self.*) {
            .complete => |*value| value.content.deinit(),
            .stopped => {},
        }
        self.* = undefined;
    }
};

pub const ProviderInvocationObservation = union(enum) {
    completed: struct {
        operation_id: ProviderOperationId,
        raw_result: RawProviderModelResult,
    },
    failed: ProviderFailure,

    pub fn deinit(self: *ProviderInvocationObservation) void {
        switch (self.*) {
            .completed => |*value| value.raw_result.deinit(),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub fn validateCountInvocation(
    provider_binding: *const binding.ValidatedProviderModelBinding,
    request: *const IdentifiedProviderNeutralModelRequest,
    operation: *const InvokedProviderOperation,
) bool {
    request.validate() catch return false;
    return operation.id.kind == .input_token_count and
        provider_binding.registry_entry.capabilities.input_token_count and
        provider_binding.registry_entry.capabilities.exact_token_counter == .provider_input_token_count and
        operation.isValid() and
        operation.id.model_request_id == request.model_request_id and
        request.matchesBinding(provider_binding.*);
}

pub fn validateInferenceInvocation(
    provider_binding: *const binding.ValidatedProviderModelBinding,
    request: *const IdentifiedProviderNeutralModelRequest,
    operation: *const InvokedProviderOperation,
) bool {
    request.validate() catch return false;
    return operation.id.kind == .inference and
        request.matchesBinding(provider_binding.*) and
        operation.isValid() and
        operation.id.model_request_id == request.model_request_id;
}

pub const RequestError = error{InvalidProviderNeutralModelRequest};
pub const Error = RequestError || error{
    ExactTokenCountEvidenceUnavailable,
    InvalidExactTokenCountEvidence,
};

fn validAuthorityId(raw: []const u8) bool {
    if (raw.len == 0 or raw.len > 128) return false;
    for (raw) |byte| if (byte < 0x21 or byte > 0x7e) return false;
    return true;
}
