const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const output = @import("../../domain/workflow_output.zig");
pub const Action = struct {
    writer: ?@import("../../ports/workflow_output.zig").Port = null,
    pub const contract: pipeline.NodeContract = .{
        .id = "publish-workflow-output",
        .kind = .action,
        .requires = &.{.prepared_workflow_output},
        .produces = &.{.published_workflow_output},
        .side_effect = .filesystem_write,
    };
    pub fn execute(self: Action, allocator: std.mem.Allocator, prepared: output.Prepared) output.Error!void {
        return (self.writer orelse return error.OutputWriteFailed).publish(allocator, prepared);
    }
};
