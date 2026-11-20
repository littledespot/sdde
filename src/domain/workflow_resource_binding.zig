const std = @import("std");
const definition = @import("workflow_definition.zig");
const inventory = @import("workflow_inventory.zig");
const rejection = @import("definition_rejection.zig");

pub const Error = error{WorkflowAuthorityInventoryInvalid};

/// Binds every definition's declared resource to one inventory resource, and requires every
/// inventory resource to be declared by some definition. A rejection records the definition and the
/// resource it names in `evidence`, when one is supplied; an inventory resource no definition declares
/// names neither.
pub fn resolve(
    allocator: std.mem.Allocator,
    inventory_value: inventory.Inventory,
    definitions: []const definition.Definition,
    evidence: ?*rejection.Slot,
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
                if (std.mem.eql(u8, prior.name, resource.name)) return unbound(evidence, item.source_ordinal, resource.id.bytes);
            }
            const ordinal = findResourceOrdinal(inventory_value, resource.name) orelse return unbound(evidence, item.source_ordinal, resource.id.bytes);
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
        // The file is an inventory entry no definition declares, so the entry names it.
        if (!referenced) return unbound(evidence, ordinal, null);
    }
    return .{
        .bindings = bindings,
        .resource_ordinals = allocator.dupe(u16, inventory_value.resource_ordinals) catch return invalid(),
    };
}

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

/// The family's one error with the binding rule, the definition and the resource recorded.
fn unbound(evidence: ?*rejection.Slot, ordinal: ?u16, resource: ?[]const u8) Error {
    rejection.record(evidence, .resource_binding, ordinal, resource);
    return invalid();
}

test "all regular resources must be explicitly and uniquely declared" {
    const workflow = @import("workflow.zig");
    const telemetry = @import("telemetry.zig");
    const file_identity = @import("filesystem_identity.zig");
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
        .invocation_operation_id = workflow.OperationId.parse("core.empty").?,
        .policy_profile_id = workflow.RegisteredRef.parse("core.safe@1").?,
        .start_step_id = workflow.WorkflowStepId.parse("run").?,
        .resources = &declared,
        .steps = &.{},
    };
    const manifest = try resolve(arena.allocator(), inventory_value, &.{item}, null);
    try std.testing.expectEqual(@as(u16, 2), manifest.bindings[0].resource_ordinal);

    var missing = item;
    missing.resources = &.{};
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, resolve(arena.allocator(), inventory_value, &.{missing}, null));

    // An inventory resource no definition declares is a binding rejection that names that file by its
    // inventory entry and no step or resource of a definition.
    var undeclared: rejection.Slot = .{};
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, resolve(arena.allocator(), inventory_value, &.{missing}, &undeclared));
    try std.testing.expectEqual(rejection.Rule.resource_binding, undeclared.evidence.rule.?);
    try std.testing.expectEqual(@as(u16, 2), undeclared.evidence.ordinal.?);
    try std.testing.expect(undeclared.evidence.subject == null);
    // A declared resource the inventory does not hold names the definition and the resource.
    var absent_declared = declared;
    absent_declared[0].name = "prompts/other.md";
    var unbound_item = item;
    unbound_item.resources = &absent_declared;
    var not_in_inventory: rejection.Slot = .{};
    try std.testing.expectError(error.WorkflowAuthorityInventoryInvalid, resolve(arena.allocator(), inventory_value, &.{unbound_item}, &not_in_inventory));
    try std.testing.expectEqual(rejection.Rule.resource_binding, not_in_inventory.evidence.rule.?);
    try std.testing.expectEqual(@as(u16, 1), not_in_inventory.evidence.ordinal.?);
    try std.testing.expectEqualStrings("prompt", not_in_inventory.evidence.subject.?.text());
}
