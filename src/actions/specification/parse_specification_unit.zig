const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const g = @import("../../domain/specification_generation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-specification-unit", .kind = .action, .requires = &.{ .raw_specification_unit, .specification_generation_session, .citable_reference_inputs, .accounted_reference_reconciliation, .reference_passive_literals, .valid_toolchain }, .produces = &.{.parsed_specification_unit}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, bytes: []const u8, current: @import("../../domain/specification_session.zig").Session, context: @import("../../domain/specification_provenance.zig").Context) @import("../../domain/specification_session.zig").Error!g.Response {
        const session = @import("../../domain/specification_session.zig");
        return g.parse(allocator, bytes, try session.currentBinding(allocator, current, context));
    }
};
