//! One registered action publishes the workflow's packet guidance for the run.
//! Consumers declare `.packet_guidance` and read it from run data.
const std = @import("std");
const guidance = @import("../domain/packet_guidance.zig");
const values = @import("pipeline_values.zig");
const operations = @import("../ports/workflow_operation_registry.zig");
const execution = @import("../domain/workflow_execution.zig");
pub const schema = values.schema(.packet_guidance, guidance.Guidance, 1, guidance.max_bytes + @sizeOf(guidance.Guidance));
pub const schemas = [_]@import("../domain/pipeline_data.zig").Schema{schema};

pub const Capture = struct {
    pub const Action = @import("../actions/model/capture_packet_guidance.zig").Action;
    pub const parameters = [_]@import("../domain/workflow_operation.zig").ParameterDescriptor{.{ .id = "guidance", .kind = .resource, .resource_kind = .packet_guidance, .required = true, .workflow_definition_safe = true }};
    allocator: std.mem.Allocator,
    action: Action = .{},
    pub fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const selected = @import("model_request_workflow.zig").resource(input.step, "guidance") orelse return error.OperationExecutionFailed;
        if (selected.content != .packet_guidance) return error.OperationExecutionFailed;
        return @import("workflow_candidate.zig").publish(self.allocator, schema, guidance.Guidance, self.action.execute(selected.content.packet_guidance));
    }
};

pub fn read(view: *const @import("../domain/pipeline_data.zig").View) operations.Error!*const guidance.Guidance {
    return values.read(view, schema, guidance.Guidance) catch |operation_error| operation_error;
}
