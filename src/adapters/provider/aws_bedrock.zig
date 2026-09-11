const std = @import("std");
const operation = @import("../../domain/llm_provider_operation.zig");
const binding = @import("../../domain/llm_provider_binding.zig");
const interface = @import("../../ports/llm_provider_interface.zig");
const lease = @import("../../ports/provider_authorization_lease.zig");
const authorization = @import("bedrock_authorization.zig");
const transport = @import("bedrock_transport.zig");
const encoding = @import("bedrock_request.zig");
const decoding = @import("bedrock_response.zig");

pub const Provider = struct {
    allocator: std.mem.Allocator,
    authorization_leases: lease.Port,
    transport: transport.Port,

    pub fn port(self: *Provider) interface.LLMProviderInterface {
        return .{ .context = @ptrCast(self), .vtable = &.{ .count_input_tokens = count, .invoke = invoke } };
    }

    fn exchange(self: *Provider, allocator: std.mem.Allocator, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation, kind: operation.ProviderOperationKind) interface.Error!transport.Response {
        var capability = self.authorization_leases.consume(reference, selected, request, invoked) catch |err| return switch (err) {
            error.Cancelled => error.Cancelled,
            error.AuthorizationExpired => .{ .failed = .{ .cause = .timeout, .retry_class = .never, .delivery = .not_sent } },
            error.AuthorizationDenied, error.ClockUnavailable => .{ .failed = .{ .cause = .authorization_denied, .retry_class = .never, .delivery = .not_sent } },
        };
        defer capability.deinit();
        const valid = switch (kind) {
            .input_token_count => operation.validateCountInvocation(selected, request, invoked),
            .inference => operation.validateInferenceInvocation(selected, request, invoked),
        };
        if (!valid or selected.registry_entry.config != .aws_bedrock or
            !@import("../../domain/llm_provider_contracts.zig").supportsReasoningEffort(selected.registry_entry.supported_reasoning_efforts, selected.reasoning_effort))
            return .{ .failed = .{ .cause = .request_rejected, .retry_class = .never, .delivery = .not_sent } };
        const secret = authorization.secret(&capability) orelse return .{ .failed = .{ .cause = .authorization_denied, .retry_class = .never, .delivery = .not_sent } };
        const body = encoding.encode(allocator, request, kind) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidRequest => .{ .failed = .{ .cause = .request_rejected, .retry_class = .never, .delivery = .not_sent } },
        };
        // Exactly one transport exchange. The consumed capability stays alive
        // only through this exchange and cannot be reused by either API.
        return self.transport.exchange(allocator, .{
            .region = selected.registry_entry.config.aws_bedrock.region,
            .model = selected.registry_entry.model,
            .kind = kind,
            .body = body,
            .api_key = secret,
            .deadline_monotonic_ms = invoked.deadline_monotonic_ms,
        });
    }

    fn count(context: *interface.Context, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) interface.Error!operation.ProviderTokenCountObservation {
        const self: *Provider = @ptrCast(@alignCast(context));
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const response = try self.exchange(arena.allocator(), selected, request, reference, invoked, .input_token_count);
        return decoding.count(self.allocator, response, selected, request, invoked.id);
    }

    fn invoke(context: *interface.Context, selected: *const binding.ValidatedProviderModelBinding, request: *const operation.IdentifiedProviderNeutralModelRequest, reference: *const operation.ValidatedProviderAuthorizationLeaseRef, invoked: *const operation.InvokedProviderOperation) interface.Error!operation.ProviderInvocationObservation {
        const self: *Provider = @ptrCast(@alignCast(context));
        var arena: std.heap.ArenaAllocator = .init(self.allocator);
        defer arena.deinit();
        const response = try self.exchange(arena.allocator(), selected, request, reference, invoked, .inference);
        // Decode into a separately owned result, never the transport arena.
        return decoding.inference(self.allocator, response, selected, request, invoked.id);
    }
};
