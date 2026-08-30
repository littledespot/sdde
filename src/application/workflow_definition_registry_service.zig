const workflow_registry = @import("../domain/workflow_registry.zig");

pub const WorkflowDefinitionRegistryService = struct {
    owner: *workflow_registry.Owner,

    pub fn init(owner: *workflow_registry.Owner) WorkflowDefinitionRegistryService {
        return .{ .owner = owner };
    }

    pub fn registry(self: *const WorkflowDefinitionRegistryService) *const workflow_registry.ValidatedWorkflowDefinitionRegistry {
        return workflow_registry.registry(self.owner);
    }

    pub fn deinit(self: *WorkflowDefinitionRegistryService) void {
        workflow_registry.deinitOwner(self.owner);
        self.* = undefined;
    }
};
