//! The one provider-port implementation for every provider family (ADR 0028):
//! consume one lease, validate the invocation and binding, encode with the
//! family's codec, capture, perform exactly one exchange and decode into a
//! separately owned observation. Codecs never consume leases, capture or send.
const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const interface = @import("../../ports/llm_provider_interface.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");
const capture_port = @import("../../ports/model_exchange_capture.zig");
const classifier = @import("../../domain/provider_failure.zig");
const authorization = @import("api_key_authorization.zig");
const key = @import("provider_api_key.zig");
const transport = @import("model_http_transport.zig");
const bedrock_request = @import("bedrock_request.zig");
const bedrock_response = @import("bedrock_response.zig");
const anthropic_request = @import("anthropic_request.zig");
const anthropic_response = @import("anthropic_response.zig");

pub const Provider = struct {
    allocator: std.mem.Allocator,
    authorization_leases: lease.Port,
    transport: transport.Port,
    capture: ?capture_port.Port = null,

    pub fn port(self: *Provider) interface.LLMProviderInterface {
        return .{ .context = @ptrCast(self), .vtable = &.{ .count_input_tokens = count, .invoke = invoke } };
    }

    /// The validated wire request for one family, or the reason it cannot be sent.
    const Prepared = struct { target: transport.Target, body: []const u8 };

    fn prepare(allocator: std.mem.Allocator, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, kind: operation.ProviderOperationKind) (std.mem.Allocator.Error || error{InvalidRequest})!Prepared {
        const entry = selected.registry_entry;
        return switch (entry.config) {
            .aws_bedrock => |config| .{
                .target = .{ .aws_bedrock = .{ .region = config.region, .model = entry.model, .kind = kind } },
                .body = try bedrock_request.encode(allocator, request, kind, config.family, config.max_output_tokens),
            },
            // The Messages API has no exact counter (ADR 0028).
            .anthropic => |config| if (kind != .inference) error.InvalidRequest else .{
                .target = .anthropic,
                .body = try anthropic_request.encode(allocator, request, entry.model.bytes, config.max_output_tokens),
            },
            .empty_object => error.InvalidRequest,
        };
    }

    fn exchange(self: *Provider, allocator: std.mem.Allocator, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation, kind: operation.ProviderOperationKind) interface.Error!transport.Response {
        var capability = self.authorization_leases.consume(reference, selected, request, invoked) catch |err| return switch (err) {
            error.Cancelled => cancelled: {
                if (self.capture) |capture| _ = capture.capture(.response, .{ .transport_outcome = .{ .outcome = .cancelled, .delivery = .not_sent } }, &.{});
                break :cancelled error.Cancelled;
            },
            error.AuthorizationExpired => self.rejectedBeforeSend(.timeout),
            error.AuthorizationDenied, error.ClockUnavailable => self.rejectedBeforeSend(.authorization_denied),
        };
        defer capability.deinit();
        const valid = switch (kind) {
            .input_token_count => operation.validateCountInvocation(selected, request, invoked),
            .inference => operation.validateInferenceInvocation(selected, request, invoked),
        };
        const family = key.Family.of(selected.registry_entry.config) orelse return self.rejectedBeforeSend(.request_rejected);
        if (!valid or !@import("../../domain/llm_provider_contracts.zig").supportsReasoningEffort(selected.registry_entry.supported_reasoning_efforts, selected.reasoning_effort))
            return self.rejectedBeforeSend(.request_rejected);
        // A capability deposited for another family never yields a key here.
        const secret = authorization.secret(&capability, family) orelse return self.rejectedBeforeSend(.authorization_denied);
        const prepared = prepare(allocator, selected, request, kind) catch |err| return switch (err) {
            error.OutOfMemory => failed: {
                if (self.capture) |capture| _ = capture.capture(.response, .{ .transport_outcome = .{ .outcome = .allocation_failed, .delivery = .not_sent } }, &.{});
                break :failed error.OutOfMemory;
            },
            error.InvalidRequest => self.rejectedBeforeSend(.request_rejected),
        };
        // Exactly one transport exchange. The consumed capability stays alive
        // only through this exchange and cannot be reused by either API.
        if (self.capture) |capture| if (capture.capture(.request, .{ .provider_body = prepared.body }, &.{secret}) == .blocked) return error.ModelLoggingBlocked;
        var body_on_error: ?transport.ResponseBody = null;
        const response = self.transport.exchange(allocator, .{
            .target = prepared.target,
            .body = prepared.body,
            .api_key = secret,
            .deadline_monotonic_ms = invoked.deadline_monotonic_ms,
            .response_body_on_error = &body_on_error,
        }) catch |err| {
            if (self.capture) |capture| {
                if (body_on_error) |received| captureBody(capture, received, secret);
                _ = capture.capture(.response, .{ .transport_outcome = .{ .outcome = if (err == error.Cancelled) .cancelled else .allocation_failed } }, &.{secret});
            }
            return err;
        };
        if (self.capture) |capture| {
            // Preserve the provider observation for unconditional usage accounting
            // even if recording the response blocks further workflow execution.
            switch (response) {
                .received => |received| captureBody(capture, .{ .bytes = received.body, .complete = true }, secret),
                .failed => |failure| {
                    if (failure.body) |received| captureBody(capture, received, secret);
                    _ = capture.capture(.response, .{ .transport_outcome = .{ .outcome = .transport_failed, .failure = failure.metadata() } }, &.{secret});
                },
            }
        }
        return response;
    }

    fn rejectedBeforeSend(self: *Provider, cause: operation.ProviderFailureCause) transport.Response {
        const failure: transport.Failure = .{ .cause = cause, .retry_class = classifier.retryClass(.before_send, cause), .delivery = .not_sent };
        if (self.capture) |capture| {
            _ = capture.capture(.response, .{ .transport_outcome = .{ .outcome = .rejected_before_send, .failure = failure.metadata() } }, &.{});
        }
        return .{ .failed = failure };
    }

    fn captureBody(capture: capture_port.Port, body: transport.ResponseBody, secret: []const u8) void {
        _ = capture.capture(.response, if (body.complete) .{ .provider_body = body.bytes } else .{ .partial_provider_body = body.bytes }, &.{secret});
    }

    fn count(context: *interface.Context, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) interface.Error!operation.ProviderTokenCountObservation {
        const self: *Provider = @ptrCast(@alignCast(context));
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const response = try self.exchange(arena.allocator(), selected, request, reference, invoked, .input_token_count);
        // Only Bedrock registers exact counting; any other family was rejected
        // before send, and its failure carries no counter wire to decode.
        return bedrock_response.count(self.allocator, response, selected, request, invoked.id);
    }

    fn invoke(context: *interface.Context, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) interface.Error!operation.ProviderInvocationObservation {
        const self: *Provider = @ptrCast(@alignCast(context));
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const response = try self.exchange(arena.allocator(), selected, request, reference, invoked, .inference);
        // Decode into a separately owned result, never the transport arena.
        return switch (selected.registry_entry.config) {
            .aws_bedrock => bedrock_response.inference(self.allocator, response, selected, request, invoked.id),
            .anthropic => anthropic_response.inference(self.allocator, response, selected, request, invoked.id),
            // No codec exists, so the exchange rejected the call before send.
            .empty_object => switch (response) {
                .failed => |failure| .{ .failed = @import("provider_response_assembly.zig").rejected(invoked.id, failure) },
                .received => unreachable,
            },
        };
    }
};
