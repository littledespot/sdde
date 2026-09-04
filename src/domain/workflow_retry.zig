const std = @import("std");
const workflow = @import("workflow.zig");

pub const parameter_id = "retry-limit";

pub const Limit = struct {
    value: u32,

    pub fn within(self: Limit, maximum: u32) bool {
        return maximum != 0 and self.value <= maximum;
    }
};

pub const CompiledAuthority = struct {
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    operation_instance_id: workflow.WorkflowStepId,
    limit: Limit,

    pub fn isValid(self: CompiledAuthority) bool {
        return self.workflow_version != 0 and
            workflow.WorkflowId.parse(self.workflow_id.bytes) != null and
            workflow.WorkflowStepId.parse(self.operation_instance_id.bytes) != null;
    }

    pub fn eql(left: CompiledAuthority, right: CompiledAuthority) bool {
        return left.workflow_version == right.workflow_version and
            left.limit.value == right.limit.value and
            std.mem.eql(u8, left.workflow_id.bytes, right.workflow_id.bytes) and
            std.mem.eql(u8, left.operation_instance_id.bytes, right.operation_instance_id.bytes);
    }
};
