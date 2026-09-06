const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "retire-required-authority-projection", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{ .required_authority_inputs, .required_authority_ledger, .required_authority_observations, .required_authority_result, .required_authority_gate }, .side_effect = .none };
    pub fn execute(_: Action) pipeline.NodeDelta {
        var delta: pipeline.NodeDelta = .{};
        for (contract.invalidates) |key| delta.data_invalidations.insert(key);
        return delta;
    }
};
