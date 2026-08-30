const std = @import("std");
const feature_log_format = @import("../../domain/feature_log_format.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");
const telemetry = @import("../../domain/telemetry.zig");

pub const Error = error{InvalidLogEvent};
pub const Action = struct {
    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        binding: *const runtime.ValidatedFeatureLogBinding,
        state: runtime.StreamState,
        reading: runtime.ClockReading,
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
