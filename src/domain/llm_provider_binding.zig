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

pub const ProviderModelBindingId = struct {
    operation_id: WorkflowModelOperationId,
    slot_id: identity.ModelSlotId,
    registry_entry_id: provider_registry.RegistryEntryId,
    reasoning_effort: ?[]const u8,

    pub fn eql(left: ProviderModelBindingId, right: ProviderModelBindingId) bool {
        return left.operation_id.eql(right.operation_id) and
            left.slot_id.eql(right.slot_id) and
            left.registry_entry_id.eql(right.registry_entry_id) and
            optionalStringEql(left.reasoning_effort, right.reasoning_effort);
    }

    pub fn isValid(self: ProviderModelBindingId) bool {
        return self.operation_id.isValid() and
            identity.ModelSlotId.parse(self.slot_id.bytes) != null and
            self.registry_entry_id.ordinal != 0 and
            (self.reasoning_effort == null or
                (self.reasoning_effort.?.len > 0 and
                    std.unicode.utf8ValidateSlice(self.reasoning_effort.?)));
    }
};

pub const ValidatedProviderModelBinding = struct {
    operation_id: WorkflowModelOperationId,
    slot_id: identity.ModelSlotId,
    registry_entry: *const provider_registry.Entry,
    reasoning_effort: ?[]const u8,
    response_mode: @import("model_controls.zig").ResponseGuidanceMode,
    controls: @import("model_controls.zig").InferenceControls,

    pub fn bindingId(self: ValidatedProviderModelBinding) ProviderModelBindingId {
        return .{
            .operation_id = self.operation_id,
            .slot_id = self.slot_id,
            .registry_entry_id = self.registry_entry.id,
            .reasoning_effort = self.reasoning_effort,
        };
    }
};

fn optionalStringEql(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}
