const bootstrap_root_registry = @import("../../domain/bootstrap_root_registry.zig");
const pipeline = @import("../../domain/pipeline.zig");
const inventory = @import("../../domain/workflow_inventory.zig");

pub const Error = error{WorkflowAuthorityInventoryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-workflow-authority-layout@1",
        .kind = .action,
        .requires = &.{.bootstrap_root_registry},
        .produces = &.{.workflow_authority_layout},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        registry: *const bootstrap_root_registry.BootstrapRootRegistry,
    ) Error!inventory.Layout {
        return .{ .capability = registry.workflowAuthority() };
    }
};
