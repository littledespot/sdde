const std = @import("std");
const feature_log_format = @import("../../domain/feature_log_format.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const telemetry = @import("../../domain/telemetry.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{InvalidLogEvent};
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-log-event-record@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_state, .trusted_log_clock, .workflow_telemetry_fact },
        .produces = &.{.identified_log_event},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        state: log_stream.StreamState,
        reading: log_stream.ClockReading,
        attributed: telemetry.WorkflowTelemetryFact,
    ) Error!feature_log_format.EventRecord {
        if (state.next_sequence == 0) return error.InvalidLogEvent;
        const event_id_bytes = std.fmt.allocPrint(allocator, "EVENT-{d}", .{state.next_sequence}) catch {
            return error.InvalidLogEvent;
        };
        const event_id = telemetry.Identifier.validate(event_id_bytes) orelse return error.InvalidLogEvent;
        return .{
            .log_policy_id = binding.logPolicyId(),
            .binding_id = binding.bindingId(),
            .segment_ordinal = state.segment_ordinal,
            .workflow_shortcode = attributed.workflow_shortcode,
            .event_id = event_id,
            .sequence = state.next_sequence,
            .occurred_at_utc = reading.utc(),
            .monotonic_offset = reading.monotonic_ms,
            .run_id = binding.runId(),
            .feature_id = binding.featureId(),
            .fact = attributed.fact,
        };
    }
};
