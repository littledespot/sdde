const pipeline = @import("../../domain/pipeline.zig");
const refresh = @import("../../domain/clarification_refresh.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "check-clarification-progress",
        .kind = .action,
        .requires = &.{.refreshed_clarification_state},
        .produces = &.{},
        .side_effect = .none,
    };
    pub fn execute(_: Action, result: refresh.Result) @import("../../domain/workflow.zig").OutcomeTag {
        if (result == .blocked) return .blocked;
        const state = result.ready.value orelse return .blocked;
        for (state.records) |record| if (record.status == .open) return .needs_user;
        return .ok;
    }
};
