const workflow = @import("../domain/workflow_registry.zig");

pub const WorkflowDefinitionRegistryService = struct {
    owner: *workflow.Owner,

    pub fn init(owner: *workflow.Owner) WorkflowDefinitionRegistryService {
        return .{ .owner = owner };
    }

    pub fn registry(self: *const WorkflowDefinitionRegistryService) *const workflow.ValidatedWorkflowDefinitionRegistry {
        return workflow.registry(self.owner);
    }

    pub fn deinit(self: *WorkflowDefinitionRegistryService) void {
        workflow.deinitOwner(self.owner);
        self.* = undefined;
    }
};
