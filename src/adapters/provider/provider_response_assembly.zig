//! Exact text and reasoning ownership, and normalized observation assembly,
//! shared by every provider decoder (ADR 0028). Candidate admission, usage
//! charging and retries stay with their domain and application owners.
const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const provider_reasoning = @import("../../domain/provider_reasoning.zig");
const transport = @import("model_http_transport.zig");
const support = @import("provider_response_support.zig");
const classifier = @import("../../domain/provider_failure.zig");

pub const Output = union(enum) { text: []const u8, stopped: operation.ProviderNonCandidateStopReason, invalid: operation.ProviderContentDiagnostic };

/// One decoded inference response. Usage survives a rejected or stopped
/// candidate; provider reasoning never becomes authored content.
pub const Inference = struct {
    usage: operation.ProviderUsage,
    latency_ms: ?u32,
    output: Output,
    reasoning: []const provider_reasoning.Block,

    pub fn deinit(self: *Inference, allocator: std.mem.Allocator) void {
        if (self.output == .text) allocator.free(self.output.text);
        provider_reasoning.deinit(allocator, self.reasoning);
        self.* = undefined;
    }
};

/// Exact in-order text join, adding no characters, plus owned reasoning blocks.
pub const Accumulator = struct {
    allocator: std.mem.Allocator,
    text: std.Io.Writer.Allocating,
    reasoning: std.ArrayList(provider_reasoning.Block) = .empty,
    invalid_content: bool = false,

    pub fn init(allocator: std.mem.Allocator) Accumulator {
        return .{ .allocator = allocator, .text = .init(allocator) };
    }

    pub fn deinit(self: *Accumulator) void {
        self.text.deinit();
        for (self.reasoning.items) |block| block.deinit(self.allocator);
        self.reasoning.deinit(self.allocator);
    }

    pub fn appendText(self: *Accumulator, value: []const u8) std.mem.Allocator.Error!void {
        self.text.writer.writeAll(value) catch return error.OutOfMemory;
    }

    /// Takes ownership of `block` on success and on failure.
    pub fn appendReasoning(self: *Accumulator, block: provider_reasoning.Block) std.mem.Allocator.Error!void {
        errdefer block.deinit(self.allocator);
        try self.reasoning.append(self.allocator, block);
    }

    /// The candidate text, or why the message holds none. A typed provider stop
    /// replaces any text.
    pub fn output(self: *Accumulator, stopped: ?operation.ProviderNonCandidateStopReason) std.mem.Allocator.Error!Output {
        if (stopped) |reason| return .{ .stopped = reason };
        if (self.invalid_content) return .{ .invalid = .invalid_content };
        if (std.mem.trim(u8, self.text.written(), " \r\n\t").len == 0) return .{ .invalid = .missing_final_text };
        return .{ .text = try self.text.toOwnedSlice() };
    }

    pub fn takeReasoning(self: *Accumulator) std.mem.Allocator.Error![]const provider_reasoning.Block {
        return self.reasoning.toOwnedSlice(self.allocator);
    }
};

/// A decoder's Inference as the provider-port observation, in separately
/// owned memory.
pub fn observation(allocator: std.mem.Allocator, decoded: *Inference, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId) (support.Invalid || std.mem.Allocator.Error)!operation.ProviderInvocationObservation {
    var result: operation.RawProviderModelResult = switch (decoded.output) {
        .invalid => |reason| .{ .rejected = .{
            .request_id = request.model_request_id,
            .binding_id = selected.bindingId(),
            .reason = reason,
            .usage = decoded.usage,
            .provider_latency_ms = decoded.latency_ms,
        } },
        .text => |text| .{ .complete = .{
            .request_id = request.model_request_id,
            .binding_id = selected.bindingId(),
            .content = operation.CompleteOwnedUtf8.init(allocator, text) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidResponse,
            .usage = decoded.usage,
            .provider_latency_ms = decoded.latency_ms,
        } },
        .stopped => |reason| .{ .stopped = .{
            .request_id = request.model_request_id,
            .binding_id = selected.bindingId(),
            .reason = reason,
            .usage = decoded.usage,
            .provider_latency_ms = decoded.latency_ms,
        } },
    };
    if (decoded.reasoning.len != 0) switch (result) {
        inline .complete, .stopped, .rejected => |*value| value.reasoning = provider_reasoning.Owned.take(allocator, &decoded.reasoning),
    };
    return .{ .completed = .{ .operation_id = id, .raw_result = result } };
}

pub fn failure(id: operation.ProviderOperationId, cause: operation.ProviderFailureCause, delivery: operation.ProviderDeliveryDisposition) operation.ProviderFailure {
    return .{ .operation_id = id, .cause = cause, .delivery = delivery, .retry_class = classifier.retryClass(.exchange, cause) };
}

pub fn exchangeFailure(cause: operation.ProviderFailureCause, delivery: operation.ProviderDeliveryDisposition) transport.Failure {
    return .{ .cause = cause, .delivery = delivery, .retry_class = classifier.retryClass(.exchange, cause) };
}

pub fn rejected(id: operation.ProviderOperationId, value: transport.Failure) operation.ProviderFailure {
    return .{ .operation_id = id, .cause = value.cause, .retry_class = value.retry_class, .delivery = value.delivery, .transport = value.diagnostic };
}

/// A decoder's error-or-success classification of one exchange.
pub const Classify = fn (std.mem.Allocator, transport.Response) std.mem.Allocator.Error!?transport.Failure;
/// A decoder's closed envelope for one successful body.
pub const Decode = fn (std.mem.Allocator, std.json.Value, *const binding.ValidatedProviderModelBinding, ?*?support.DecodeDiagnostic) (support.Invalid || std.mem.Allocator.Error)!Inference;

/// The shared inference path: classify, parse strictly, decode closed, assemble.
pub fn inference(allocator: std.mem.Allocator, response: transport.Response, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, id: operation.ProviderOperationId, comptime classify: Classify, comptime decode: Decode) std.mem.Allocator.Error!operation.ProviderInvocationObservation {
    if (try classify(allocator, response)) |value| return .{ .failed = rejected(id, value) };
    var parsed = support.parse(allocator, response.received.body) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => .{ .failed = failure(id, .response_invalid, .response_received) },
    };
    defer parsed.deinit();
    var decoded = decode(allocator, parsed.value, selected, null) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidResponse => .{ .failed = failure(id, .response_invalid, .response_received) },
    };
    defer decoded.deinit(allocator);
    return observation(allocator, &decoded, selected, request, id) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidResponse => .{ .failed = failure(id, .response_invalid, .response_received) },
    };
}

pub const Received = @FieldType(transport.Response, "received");
/// A decoder's closed error table: status, retained headers and body together.
pub const DecodeError = fn (std.json.Value, Received) support.Invalid!operation.ProviderFailureCause;

/// Parse an error body strictly, then let the decoder's closed table classify
/// it; anything unrecognized is `response_invalid`.
pub fn classifyErrorBody(allocator: std.mem.Allocator, received: Received, comptime decodeError: DecodeError) std.mem.Allocator.Error!transport.Failure {
    const invalid = exchangeFailure(.response_invalid, .response_received);
    var parsed = support.parse(allocator, received.body) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else invalid;
    defer parsed.deinit();
    const cause = decodeError(parsed.value, received) catch return invalid;
    return exchangeFailure(cause, .response_received);
}
