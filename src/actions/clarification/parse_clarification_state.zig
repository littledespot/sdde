const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const clarification = @import("../../domain/clarification_inputs.zig");
const parser_port = @import("../../ports/clarification_input_parser.zig");

pub const Action = struct {
    parser: parser_port.StateParser,
    pub const contract: pipeline.NodeContract = .{
        .id = "parse-clarification-state@1",
        .kind = .action,
        .requires = &.{.raw_clarification_inputs},
        .produces = &.{.parsed_clarification_state},
        .side_effect = .none,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, captured: clarification.Captures) clarification.Error!clarification.ParsedState {
        return .{ .value = if (captured.state) |bytes| try self.parser.parse(allocator, bytes) else null };
    }
};
