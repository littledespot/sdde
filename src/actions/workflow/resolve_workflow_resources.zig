const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const definition = @import("../../domain/workflow_definition.zig");
const inventory = @import("../../domain/workflow_inventory.zig");

pub const Error = error{WorkflowAuthorityInventoryInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "resolve-workflow-resources@1",
        .kind = .action,
        .requires = &.{ .workflow_authority_inventory, .declarative_workflow_definitions },
        .produces = &.{.workflow_resource_manifest},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        inventory_value: inventory.Inventory,
        definitions: []const definition.Definition,
    ) Error!inventory.ResourceManifest {
        var binding_count: usize = 0;
        for (definitions) |item| {
            binding_count = std.math.add(usize, binding_count, item.resources.len) catch return invalid();
        }
        const bindings = allocator.alloc(inventory.ResourceBinding, binding_count) catch return invalid();
        var binding_index: usize = 0;
        for (definitions) |item| {
            for (item.resources, 0..) |resource, index| {
                for (item.resources[0..index]) |prior| {
                    if (std.mem.eql(u8, prior.name, resource.name)) return invalid();
                }
                const ordinal = findResourceOrdinal(inventory_value, resource.name) orelse return invalid();
                bindings[binding_index] = .{
                    .definition_ordinal = item.source_ordinal,
                    .resource_id = resource.id,
                    .resource_ordinal = ordinal,
                };
                binding_index += 1;
            }
        }
        std.mem.sort(inventory.ResourceBinding, bindings, {}, bindingLessThan);
        for (inventory_value.resource_ordinals) |ordinal| {
            var referenced = false;
            for (bindings) |binding| if (binding.resource_ordinal == ordinal) {
                referenced = true;
                break;
            };
            if (!referenced) return invalid();
        }
        return .{
            .bindings = bindings,
            .resource_ordinals = allocator.dupe(u16, inventory_value.resource_ordinals) catch return invalid(),
        };
    }
};

fn findResourceOrdinal(inventory_value: inventory.Inventory, name: []const u8) ?u16 {
    var found: ?u16 = null;
    for (inventory_value.descriptors, inventory_value.accounts) |descriptor, account| {
        if (!std.mem.eql(u8, descriptor.path, name)) continue;
        if (account.disposition != .resource or found != null) return null;
        found = account.ordinal;
    }
    return found;
}

fn bindingLessThan(_: void, left: inventory.ResourceBinding, right: inventory.ResourceBinding) bool {
    if (left.definition_ordinal != right.definition_ordinal) return left.definition_ordinal < right.definition_ordinal;
    return std.mem.order(u8, left.resource_id.bytes, right.resource_id.bytes) == .lt;
}

fn invalid() Error {
    return error.WorkflowAuthorityInventoryInvalid;
}

test "all regular resources must be explicitly and uniquely declared" {
    const workflow = @import("../../domain/workflow.zig");
    const telemetry = @import("../../domain/telemetry.zig");
    const file_identity = @import("../../domain/filesystem_identity.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const descriptors = [_]inventory.InventoryDescriptor{
        .{ .path = "flow.workflow.yaml", .kind = .file, .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 1 }, .size = 1 },
        .{ .path = "prompts/generate.md", .kind = .file, .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 2 }, .size = 1 },
    };
    const accounts = [_]inventory.InventoryAccount{
        .{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition },
        .{ .ordinal = 2, .path = descriptors[1].path, .disposition = .resource },
    };
    const inventory_value: inventory.Inventory = .{
        .capability = undefined,
        .descriptors = &descriptors,
        .accounts = &accounts,
        .definition_ordinals = &.{1},
        .resource_ordinals = &.{2},
    };
    const declared = [_]workflow.ResourceDeclaration{.{
        .id = workflow.WorkflowResourceId.parse("prompt").?,
        .name = descriptors[1].path,
    }};
    const item: definition.Definition = .{
        .source_ordinal = 1,
        .workflow_id = workflow.WorkflowId.parse("flow").?,
        .workflow_version = 1,
        .shortcode = telemetry.WorkflowShortcode.parse("FLOW") catch unreachable,
        .invocation_operation_id = workflow.RegisteredRef.parse("core.empty@1").?,
        .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
        .start_step_id = workflow.WorkflowStepId.parse("run").?,
        .resources = &declared,
        .steps = &.{},
    };
    const manifest = try (Action{}).execute(arena.allocator(), inventory_value, &.{item});
    try std.testing.expectEqual(@as(u16, 2), manifest.bindings[0].resource_ordinal);

    var missing = item;
    missing.resources = &.{};
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, (Action{}).execute(arena.allocator(), inventory_value, &.{missing}));
}
