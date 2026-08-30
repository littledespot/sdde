const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const definition = @import("../../domain/workflow_definition.zig");
const compilation = @import("../../domain/workflow_compilation.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
const registry = @import("../../domain/workflow_registry.zig");

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
        inventory_value: inventory.Inventory,
        captures: []const inventory.Capture,
        definitions: []const definition.Definition,
        validated: compilation.ValidatedGraphs,
    ) Error!registry.RegistryCandidate {
        const graphs = allocator.dupe(compilation.CompiledWorkflow, validated.values) catch {
            return error.WorkflowRegistryInvalid;
        };
        std.mem.sort(compilation.CompiledWorkflow, graphs, {}, lessThan);
        return .{ .inventory = inventory_value, .captures = captures, .definitions = definitions, .graphs = graphs };
    }
};

fn lessThan(_: void, left: compilation.CompiledWorkflow, right: compilation.CompiledWorkflow) bool {
    return std.mem.order(
        u8,
        left.authority.workflow_id.bytes,
        right.authority.workflow_id.bytes,
    ) == .lt;
}
