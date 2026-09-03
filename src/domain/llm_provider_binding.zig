const std = @import("std");
const identity = @import("llm_provider_identity.zig");
const provider_registry = @import("llm_provider_registry.zig");
const workflow = @import("workflow.zig");

pub const WorkflowModelOperationId = struct {
    workflow_id: workflow.WorkflowId,
    workflow_version: u32,
    workflow_step_id: workflow.WorkflowStepId,

    pub fn isValid(self: WorkflowModelOperationId) bool {
        return self.workflow_version != 0 and
            workflow.WorkflowId.parse(self.workflow_id.bytes) != null and
            workflow.WorkflowStepId.parse(self.workflow_step_id.bytes) != null;
    }

    pub fn eql(left: WorkflowModelOperationId, right: WorkflowModelOperationId) bool {
        return left.workflow_version == right.workflow_version and
            std.mem.eql(u8, left.workflow_id.bytes, right.workflow_id.bytes) and
            std.mem.eql(u8, left.workflow_step_id.bytes, right.workflow_step_id.bytes);
    }
};

pub const ValidatedProviderModelBinding = struct {
    operation_id: WorkflowModelOperationId,
    slot_id: identity.ModelSlotId,
    registry_entry: *const provider_registry.Entry,
    reasoning_effort: ?[]const u8,
};
