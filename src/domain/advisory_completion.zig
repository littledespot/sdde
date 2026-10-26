//! Classify only sealed native evidence for an explicitly bound assessment.
const handoff = @import("model_request_handoff.zig");
const invocation = @import("model_invocation_result.zig");
const validation = @import("provider_invocation_validation.zig");
const authority = @import("required_authority.zig");
const attempts = @import("model_attempt_decision.zig");

pub const Reason = authority.AdviceStop.Reason;

pub fn eligible(request: *const handoff.Request) bool {
    return request.advisoryAssessment() != null;
}

pub fn protocolReason(request: *const handoff.Request, receipt: *const attempts.StopReceipt) ?Reason {
    if (!eligible(request) or receipt.request() != request or request.protocolCorrection() == null) return null;
    return .protocol_exhausted;
}

/// Association/usage validation happens first. Native validation failures never
/// become missing advice, even when accounting also observed unavailable usage.
pub fn invocationReason(request: *const handoff.Request, result: *const invocation.Result, evidence: ?*const validation.Evidence) ?Reason {
    if (!eligible(request) or result.operationId().model_request_id != request.id()) return null;
    const raw = result.outcome() orelse return null;
    switch (raw.*) {
        .observation => {
            const observed = evidence orelse return null;
            if (observed.request() != request.prepared() or !observed.operationId().eql(result.operationId())) return null;
            switch (observed.result()) {
                .failed => |failure| {
                    if (observed.missingFinalText() and result.accountingStop() == null) return null;
                    switch (failure.cause) {
                        .authentication_failed, .authorization_denied, .timeout => return null,
                        .transport_failed => if (failure.transport) |transport| switch (transport.cause) {
                            .tls, .timeout => return null,
                            else => {},
                        },
                        else => {},
                    }
                    return if (result.accountingStop() != null) .usage_unavailable else .provider_failure;
                },
                // A first runaway is re-sent before it can end advice (ADR 0039).
                .stopped => |stop| return if (result.accountingStop() != null) .usage_unavailable else if (stop != .output_limit) .provider_failure else if (observed.runaway() == .first) null else .provider_output_limit,
                .complete => return if (result.accountingStop() != null) .usage_unavailable else null,
            }
        },
        .cancelled, .allocation_failed, .logging_blocked_before_send => return null,
    }
}
