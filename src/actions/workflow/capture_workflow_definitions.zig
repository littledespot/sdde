const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
const source_port = @import("../../ports/workflow_authority_source.zig");

pub const Error = error{ Cancelled, WorkflowDefinitionReadError };

pub const Action = struct {
    source: source_port.Capturer,

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
        inventory_value: inventory.Inventory,
        runtime: pipeline.NodeRuntime,
    ) Error![]const inventory.Capture {
        inventory.validateCaptureBudget(inventory_value) catch {
            return error.WorkflowDefinitionReadError;
        };
        const captures = allocator.alloc(inventory.Capture, inventory_value.definition_ordinals.len) catch {
            return error.WorkflowDefinitionReadError;
        };
        for (inventory_value.definition_ordinals, captures) |ordinal, *capture| {
            const descriptor = inventory_value.descriptors[ordinal - 1];
            const bytes = self.source.capture(
                inventory_value.capability,
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
