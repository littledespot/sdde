const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow_registry.zig");
const source_port = @import("../../ports/workflow_authority_source.zig");

pub const Error = error{ Cancelled, WorkflowDefinitionReadError };

pub const Action = struct {
    source: source_port.Source,

    pub const contract: pipeline.NodeContract = .{
        .id = "capture-workflow-definitions@1",
        .kind = .action,
        .requires = &.{.workflow_authority_inventory},
        .produces = &.{.workflow_definition_captures},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        inventory: workflow.Inventory,
        runtime: pipeline.NodeRuntime,
    ) Error![]const workflow.Capture {
        workflow.validateCaptureBudget(inventory) catch {
            return error.WorkflowDefinitionReadError;
        };
        const captures = allocator.alloc(workflow.Capture, inventory.definition_ordinals.len) catch {
            return error.WorkflowDefinitionReadError;
        };
        for (inventory.definition_ordinals, captures) |ordinal, *capture| {
            const descriptor = inventory.descriptors[ordinal - 1];
            const bytes = self.source.capture(
                inventory.capability,
                descriptor,
                allocator,
                runtime,
            ) catch |failure| return switch (failure) {
                error.Cancelled => error.Cancelled,
                else => error.WorkflowDefinitionReadError,
            };
            capture.* = .{ .ordinal = ordinal, .bytes = bytes };
        }
        return captures;
    }
};
