/// The fixed stages of one logical model request (ADR 0030, "How the step runs"). The
/// engine compiles this list; a workflow cannot reorder, skip, add or name a stage.
/// Each stage is one runner-owned child binding with its own narrow ports.
pub const Stage = enum {
    /// 1. Request assignment, binding validation and request building.
    prepare_request,
    /// 2. Attempt accounting.
    advance_attempt,
    /// 3. Provider-operation assignment.
    assign_operation,
    /// 4. Authorization preparation, bound to the catalogue entry's request deadline.
    prepare_authorization,
    /// 5. Request-phase check.
    check_phase,
    /// 6. Request invocation-state advance, on the initial attempt only.
    advance_request,
    /// 7. Provider-operation invocation-state advance.
    advance_operation,
    /// 8. Inference.
    invoke_model,
    /// 9. Observation validation.
    validate_observation,
    /// 10. Provider-operation completion.
    complete_operation,
    /// 11. Response admission: decoding and payload-schema validation.
    admit_response,
    /// 12. Protocol correction or ADR 0039's runaway re-send: the runaway check ...
    check_runaway,
    /// ... then the correction it selects ...
    build_protocol_retry,
    /// ... or the one re-send it selects. Both return to stage 2.
    build_runaway_resend,
    /// 13. Request closure.
    close_request,
    /// 13, pre-call: terminate the provider operation, then the request.
    terminate_operation,
    terminate_request,

    /// The stage's name in events and exhaustion diagnostics: its tag with `-` for `_`.
    pub fn name(self: Stage) []const u8 {
        return switch (self) {
            inline else => |tag| comptime dashed(@tagName(tag)),
        };
    }
};

fn dashed(comptime tag: []const u8) []const u8 {
    comptime var result: [tag.len]u8 = undefined;
    inline for (tag, 0..) |byte, index| result[index] = if (byte == '_') '-' else byte;
    const final = result;
    return &final;
}
