const pipeline = @import("../../domain/pipeline.zig");
const stream = @import("../../domain/feature_log_stream.zig");

pub const Error = error{InvalidFeatureLogFinalization};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-feature-log-finalization",
        .kind = .action,
        .requires = &.{.feature_log_runtime_status},
        .produces = &.{.feature_log_finalization_authority},
        .side_effect = .none,
    };

    pub fn execute(_: Action, status: stream.RuntimeStatus) Error!void {
        if (status != .prepared) return error.InvalidFeatureLogFinalization;
    }
};

test "finalization requires a prepared live binding" {
    try (Action{}).execute(.prepared);
    try @import("std").testing.expectError(
        error.InvalidFeatureLogFinalization,
        (Action{}).execute(.unprepared),
    );
    try @import("std").testing.expectError(
        error.InvalidFeatureLogFinalization,
        (Action{}).execute(.retired),
    );
}
