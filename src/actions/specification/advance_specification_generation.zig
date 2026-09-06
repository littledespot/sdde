const pipeline = @import("../../domain/pipeline.zig");
const session = @import("../../domain/specification_session.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "advance-specification-generation", .kind = .action, .requires = &.{ .specification_generation_session, .validated_specification_unit }, .produces = &.{}, .replaces = &.{.specification_generation_session}, .invalidates = &.{ .raw_specification_unit, .parsed_specification_unit, .validated_specification_unit }, .side_effect = .none };
    pub fn execute(_: Action, current: session.Session, checked: @import("../../domain/specification_generation.zig").Checked) session.Error!session.Session {
        return session.append(current, checked);
    }
};
