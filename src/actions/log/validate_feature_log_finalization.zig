const pipeline = @import("../../domain/pipeline.zig");
const stream = @import("../../domain/feature_log_stream.zig");

pub const Error = error{InvalidFeatureLogFinalization};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-feature-log-finalization@1",
        .kind = .action,
        .requires = &.{.feature_log_runtime_status},
        .produces = &.{.feature_log_finalization_authority},
        .side_effect = .none,
    };

    pub fn execute(_: Action, mode: stream.FinalizationMode, status: stream.RuntimeStatus) Error!void {
        if (status == .retired or (mode == .active and status != .prepared)) {
            return error.InvalidFeatureLogFinalization;
        }
    }
};

test "active finalization requires a prepared live binding" {
    try (Action{}).execute(.active, .prepared);
    try (Action{}).execute(.historical, .unprepared);
    try @import("std").testing.expectError(
        error.InvalidFeatureLogFinalization,
        (Action{}).execute(.active, .unprepared),
    );
    try @import("std").testing.expectError(
        error.InvalidFeatureLogFinalization,
        (Action{}).execute(.historical, .retired),
    );
}
