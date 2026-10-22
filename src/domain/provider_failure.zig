//! One retry-eligibility classifier for every provider family (ADR 0028). It
//! reads only neutral facts: no HTTP response code, header, wire error or adapter.
//! Retry execution stays with workflow policy.
const operation = @import("llm_provider_operation.zig");

pub const Stage = enum {
    /// Nothing reached the provider: an expired or denied lease, a rejected
    /// request or a missing credential. Never eligible, even for a timeout.
    before_send,
    /// The exchange started: transport failure or a classified provider reply.
    exchange,
};

pub fn retryClass(stage: Stage, cause: operation.ProviderFailureCause) operation.ProviderRetryClass {
    return switch (stage) {
        .before_send => .never,
        .exchange => switch (cause) {
            .throttled, .timeout, .service_unavailable, .transport_failed => .policy_eligible,
            .authentication_failed, .authorization_denied, .request_rejected, .model_unavailable, .response_invalid, .exact_token_count_unavailable => .never,
        },
    };
}

test "pre-send failures never retry and exchange failures follow their cause" {
    const std = @import("std");
    for (std.enums.values(operation.ProviderFailureCause)) |cause| {
        try std.testing.expectEqual(operation.ProviderRetryClass.never, retryClass(.before_send, cause));
    }
    for ([_]operation.ProviderFailureCause{ .throttled, .timeout, .service_unavailable, .transport_failed }) |cause| {
        try std.testing.expectEqual(operation.ProviderRetryClass.policy_eligible, retryClass(.exchange, cause));
    }
    for ([_]operation.ProviderFailureCause{ .authentication_failed, .authorization_denied, .request_rejected, .model_unavailable, .response_invalid, .exact_token_count_unavailable }) |cause| {
        try std.testing.expectEqual(operation.ProviderRetryClass.never, retryClass(.exchange, cause));
    }
}
