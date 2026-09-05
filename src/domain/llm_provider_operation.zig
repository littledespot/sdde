const std = @import("std");
const binding = @import("llm_provider_binding.zig");
const request_identity = @import("model_request_identity.zig");
const execution_reference = @import("execution_reference.zig");
const model_limits = @import("model_limits.zig");
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

    pub fn sameAttempt(left: ProviderOperationId, right: ProviderOperationId) bool {
        return left.model_request_id == right.model_request_id and
            left.model_attempt_ordinal.value == right.model_attempt_ordinal.value;
    }
};

pub const ProviderReceiveBudgets = struct {
    maximum_header_count: u16,
    maximum_header_bytes: u32,
    maximum_body_bytes: u32,

    pub fn init(
        maximum_header_count: u16,
        maximum_header_bytes: u32,
        maximum_body_bytes: u32,
    ) ?ProviderReceiveBudgets {
        if (maximum_header_count == 0 or maximum_header_bytes == 0 or maximum_body_bytes == 0) {
            return null;
        }
        return .{
            .maximum_header_count = maximum_header_count,
            .maximum_header_bytes = maximum_header_bytes,
            .maximum_body_bytes = maximum_body_bytes,
        };
    }

    pub fn isValid(self: ProviderReceiveBudgets) bool {
        return self.maximum_header_count != 0 and
            self.maximum_header_bytes != 0 and
            self.maximum_body_bytes != 0;
    }
};

pub const InvokedProviderOperation = struct {
    id: ProviderOperationId,
    deadline_monotonic_ms: u64,
    receive_budgets: ProviderReceiveBudgets,

    pub fn init(
        id: ProviderOperationId,
        deadline_monotonic_ms: u64,
        receive_budgets: ProviderReceiveBudgets,
    ) ?InvokedProviderOperation {
        if (id.model_attempt_ordinal.value == 0 or deadline_monotonic_ms == 0 or
            !receive_budgets.isValid())
        {
            return null;
        }
        return .{
            .id = id,
            .deadline_monotonic_ms = deadline_monotonic_ms,
            .receive_budgets = receive_budgets,
        };
    }

    pub fn isValid(self: InvokedProviderOperation) bool {
        return self.id.model_attempt_ordinal.value != 0 and
            self.deadline_monotonic_ms != 0 and
            self.receive_budgets.isValid();
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
    response_schema: []const u8,
    response_guidance_mode: model_controls.ResponseGuidanceMode,
    controls: model_controls.InferenceControls,
    limits: model_limits.Limits,

    pub fn init(value: IdentifiedProviderNeutralModelRequest) Error!IdentifiedProviderNeutralModelRequest {
        try value.validate();
        return value;
    }

    pub fn validate(self: IdentifiedProviderNeutralModelRequest) Error!void {
        if (!self.model_request_id.model_operation_id.eql(self.model_operation_id) or
            !self.binding_id.operation_id.eql(self.model_operation_id) or
            !self.binding_id.isValid() or
            RequestSchemaId.parse(self.request_schema_id.bytes) == null or
            ResultSchemaId.parse(self.result_schema_id.bytes) == null or
            ModelVisibleInputId.parse(self.model_visible_input_id.bytes) == null or
            self.content.len == 0 or self.response_schema.len == 0 or
            !std.unicode.utf8ValidateSlice(self.response_schema) or
            model_limits.Limits.init(
                self.limits.maximum_input_bytes,
                self.limits.maximum_output_bytes,
                self.limits.maximum_input_tokens,
                self.limits.maximum_output_tokens,
                self.limits.context_window_tokens,
            ) == null or
            (self.controls.temperature != null and
                model_controls.TemperaturePermille.init(self.controls.temperature.?.value) == null))
        {
            return error.InvalidProviderNeutralModelRequest;
        }

        var canonical_bytes: u64 = self.response_schema.len;
        for (self.content) |part| {
            const bytes = part.bytes();
            if (bytes.len == 0 or !std.unicode.utf8ValidateSlice(bytes)) {
                return error.InvalidProviderNeutralModelRequest;
            }
            canonical_bytes = std.math.add(u64, canonical_bytes, bytes.len) catch {
                return error.InvalidProviderNeutralModelRequest;
            };
        }
        if (canonical_bytes > self.limits.maximum_input_bytes) {
            return error.InvalidProviderNeutralModelRequest;
        }
    }

    pub fn matchesBinding(self: IdentifiedProviderNeutralModelRequest, selected: binding.ValidatedProviderModelBinding) bool {
        const supported = selected.registry_entry.capabilities;
        const bounded = model_limits.Capacity.intersect(selected.capacity, supported.capacity) orelse return false;
        return supported.supports(selected.response_mode, selected.controls) and
            self.binding_id.eql(selected.bindingId()) and
            std.meta.eql(bounded, selected.capacity) and
            std.meta.eql(self.limits, selected.capacity.canonical) and
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
    request_limit_exceeded,
    response_invalid,
    response_limit_exceeded,
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
            self.count_operation_id.model_request_id != request.model_request_id or
            !self.binding_id.eql(expected_binding) or
            !self.binding_id.eql(request.binding_id) or
            !self.model_visible_input_id.eql(request.model_visible_input_id))
        {
            return false;
        }
        return request.limits.acceptsInputTokens(self.input_tokens);
    }
};

pub const ProviderUsage = struct {
    input_tokens: u64,
    output_tokens: u64,
    total_tokens: u64,

    pub fn init(input_tokens: u64, output_tokens: u64, total_tokens: u64) ?ProviderUsage {
        if (total_tokens < input_tokens or total_tokens < output_tokens) return null;
        return .{
            .input_tokens = input_tokens,
            .output_tokens = output_tokens,
            .total_tokens = total_tokens,
        };
    }
};

pub const CompleteBoundedOwnedUtf8 = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,

    pub const InitError = std.mem.Allocator.Error || error{
        InvalidUtf8,
        LimitExceeded,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        source: []const u8,
        maximum_bytes: u32,
    ) InitError!CompleteBoundedOwnedUtf8 {
        if (!std.unicode.utf8ValidateSlice(source)) return error.InvalidUtf8;
        if (source.len > maximum_bytes) return error.LimitExceeded;
        return .{ .allocator = allocator, .bytes = try allocator.dupe(u8, source) };
    }

    pub fn deinit(self: *CompleteBoundedOwnedUtf8) void {
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
        content: CompleteBoundedOwnedUtf8,
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
        receiveBudgetsFit(operation.receive_budgets, provider_binding.capacity.wire) and
        operation.isValid() and
        operation.id.model_request_id == request.model_request_id and
        request.matchesBinding(provider_binding.*);
}

pub fn validateInferenceInvocation(
    provider_binding: *const binding.ValidatedProviderModelBinding,
    request: *const IdentifiedProviderNeutralModelRequest,
    count_evidence: *const ExactInputTokenCountEvidence,
    operation: *const InvokedProviderOperation,
) bool {
    request.validate() catch return false;
    const binding_id = provider_binding.bindingId();
    return operation.id.kind == .inference and
        receiveBudgetsFit(operation.receive_budgets, provider_binding.capacity.wire) and
        request.matchesBinding(provider_binding.*) and
        operation.isValid() and
        operation.id.model_request_id == request.model_request_id and
        operation.id.sameAttempt(count_evidence.count_operation_id) and
        count_evidence.isValidFor(request.*, binding_id);
}

fn receiveBudgetsFit(receive: ProviderReceiveBudgets, capacity: model_limits.WireBudgets) bool {
    return receive.isValid() and capacity.isValid() and
        receive.maximum_header_count <= capacity.maximum_response_header_count and
        receive.maximum_header_bytes <= capacity.maximum_response_header_bytes and
        receive.maximum_body_bytes <= capacity.maximum_response_body_bytes;
}

pub const Error = error{
    InvalidProviderNeutralModelRequest,
    ExactTokenCountEvidenceUnavailable,
    InvalidExactTokenCountEvidence,
};

fn validAuthorityId(raw: []const u8) bool {
    if (raw.len == 0 or raw.len > 128) return false;
    for (raw) |byte| if (byte < 0x21 or byte > 0x7e) return false;
    return true;
}
