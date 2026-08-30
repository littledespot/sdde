const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const workflow = @import("../../domain/workflow_registry.zig");

pub const Error = error{WorkflowRegistryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-workflow-definition-registry@1",
        .kind = .action,
        .requires = &.{
            .workflow_authority_inventory,
            .workflow_definition_captures,
            .declarative_workflow_definitions,
            .validated_workflow_graphs,
        },
        .produces = &.{.workflow_definition_registry_candidate},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        inventory: workflow.Inventory,
        captures: []const workflow.Capture,
        definitions: []const workflow.Definition,
        validated: workflow.ValidatedGraphs,
    ) Error!workflow.RegistryCandidate {
        const graphs = allocator.dupe(workflow.CompiledWorkflow, validated.values) catch {
            return error.WorkflowRegistryInvalid;
        };
        std.mem.sort(workflow.CompiledWorkflow, graphs, {}, lessThan);
        return .{ .inventory = inventory, .captures = captures, .definitions = definitions, .graphs = graphs };
    }
};

fn lessThan(_: void, left: workflow.CompiledWorkflow, right: workflow.CompiledWorkflow) bool {
    return std.mem.order(
        u8,
        left.authority.workflow_id.bytes,
        right.authority.workflow_id.bytes,
    ) == .lt;
}
