const format = @import("../../domain/feature_log_format.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const prompt_log = @import("../../domain/sanitized_prompt_log.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{InvalidPromptLogRecord};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-prompt-log-record",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_state, .trusted_log_clock, .validated_prompt_fragment },
        .produces = &.{.identified_prompt_log},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        event_id_buffer: *[32]u8,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        state: log_stream.StreamState,
        reading: *const log_stream.ClockReading,
        fragment: prompt_log.SanitizedPromptFragment,
    ) Error!format.PromptRecord {
        const event_id = format.eventId(event_id_buffer, state.next_sequence) orelse return error.InvalidPromptLogRecord;
        return .{
            .log_policy_id = binding.logPolicyId(),
            .binding_id = binding.bindingId(),
            .segment_ordinal = state.segment_ordinal,
            .event_id = event_id,
            .sequence = state.next_sequence,
            .occurred_at_utc = reading.utc(),
            .monotonic_offset = reading.monotonic_ms,
            .run_id = binding.runId(),
            .feature_id = binding.featureId(),
            .fragment = fragment,
        };
    }
};
