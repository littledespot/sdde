const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "retire-required-authority-projection", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &@import("../../domain/required_authority.zig").projection_keys, .side_effect = .none };
    pub fn execute(_: Action) pipeline.NodeDelta {
        var delta: pipeline.NodeDelta = .{};
        for (contract.invalidates) |key| delta.data_invalidations.insert(key);
        return delta;
    }
};
