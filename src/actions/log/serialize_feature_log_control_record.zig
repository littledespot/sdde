const std = @import("std");
const format = @import("../../domain/feature_log_format.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LogSerializationFailure};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "serialize-feature-log-control-record@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_stream_state, .trusted_log_clock },
        .produces = &.{.serialized_log_control_record},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        stream: log_stream.Stream,
        kind: format.ControlKind,
        binding: *const log_binding.ValidatedFeatureLogBinding,
        segment_ordinal: u16,
        final_sequence: ?u64,
        occurred_at_utc: []const u8,
    ) Error![]u8 {
        const record: format.EventControlRecord = .{
            .kind = kind,
            .log_policy_id = binding.logPolicyId(),
            .binding_id = binding.bindingId(),
            .segment_ordinal = segment_ordinal,
            .final_sequence = final_sequence,
            .occurred_at_utc = occurred_at_utc,
            .run_id = binding.runId(),
            .feature_id = binding.featureId(),
        };
        return switch (stream) {
            .event => format.serializeEventControl(allocator, record),
            .prompt => format.serializePromptControl(allocator, record),
        } catch error.LogSerializationFailure;
    }
};
