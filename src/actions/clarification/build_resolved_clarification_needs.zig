const pipeline = @import("../../domain/pipeline.zig");
const authority = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-resolved-clarification-needs", .kind = .action, .requires = &.{ .required_authority_result, .required_authority_gate }, .produces = &.{.clarification_needs}, .side_effect = .none };
    pub fn execute(_: Action, result: authority.Result) authority.Error!@import("../../domain/clarification_refresh.zig").Needs {
        if (result.continuation != .all_resolved) return error.InvalidRequiredAuthority;
        return .{ .feature = result.feature, .entries = &.{} };
    }
};
