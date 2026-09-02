const std = @import("std");
const format = @import("../../domain/feature_log_format.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");

pub const Error = error{LogSerializationFailure};

pub const Action = struct {
    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        stream: runtime.Stream,
        kind: format.ControlKind,
        binding: *const runtime.ValidatedFeatureLogBinding,
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
