const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const inventory = @import("../../domain/workflow_inventory.zig");
const source_port = @import("../../ports/workflow_authority_source.zig");

pub const Error = error{ Cancelled, WorkflowResourceReadError };

pub const Action = struct {
    source: source_port.Capturer,

    pub const contract: pipeline.NodeContract = .{
        .id = "capture-workflow-resources@1",
        .kind = .action,
        .requires = &.{ .workflow_authority_inventory, .workflow_resource_manifest },
        .produces = &.{.workflow_resource_captures},
        .side_effect = .filesystem_read,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        inventory_value: inventory.Inventory,
        manifest: inventory.ResourceManifest,
        runtime: pipeline.NodeRuntime,
    ) Error![]const inventory.Capture {
        inventory.validateResourceCaptureBudget(inventory_value, manifest) catch return error.WorkflowResourceReadError;
        const captures = allocator.alloc(inventory.Capture, manifest.resource_ordinals.len) catch return error.WorkflowResourceReadError;
        for (manifest.resource_ordinals, captures) |ordinal, *capture| {
            const descriptor = inventory_value.descriptors[ordinal - 1];
            const bytes = self.source.capture(
                inventory_value.capability,
                descriptor,
                allocator,
                runtime,
            ) catch |failure| return switch (failure) {
                error.Cancelled => error.Cancelled,
                else => error.WorkflowResourceReadError,
            };
            capture.* = .{ .ordinal = ordinal, .bytes = bytes };
        }
        return captures;
    }
};

test "captures only the validated declared resource manifest" {
    const file_identity = @import("../../domain/filesystem_identity.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const descriptors = [_]inventory.InventoryDescriptor{.{
        .path = "prompt.md",
        .kind = .file,
        .identity = file_identity.FileIdentity{ .filesystem_id = 1, .file_id = 1 },
        .size = 3,
    }};
    const accounts = [_]inventory.InventoryAccount{.{
        .ordinal = 1,
        .path = descriptors[0].path,
        .disposition = .resource,
    }};
    const inventory_value: inventory.Inventory = .{
        .capability = undefined,
        .descriptors = &descriptors,
        .accounts = &accounts,
        .definition_ordinals = &.{},
        .resource_ordinals = &.{1},
    };
    var fake: FakeCapturer = .{};
    const action: Action = .{ .source = fake.port() };
    try std.testing.expectError(
        error.WorkflowResourceReadError,
        action.execute(
            arena.allocator(),
            inventory_value,
            .{ .bindings = &.{}, .resource_ordinals = &.{} },
            .{},
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), fake.calls);

    const captured = try action.execute(
        arena.allocator(),
        inventory_value,
        .{ .bindings = &.{}, .resource_ordinals = &.{1} },
        .{},
    );
    try std.testing.expectEqual(@as(usize, 1), fake.calls);
    try std.testing.expectEqualStrings("abc", captured[0].bytes);
}

const FakeCapturer = struct {
    calls: usize = 0,

    fn port(self: *FakeCapturer) source_port.Capturer {
        return .{ .context = self, .capture_fn = capture };
    }

    fn capture(
        context: *anyopaque,
        _: *const @import("../../domain/bootstrap_root_registry.zig").ConfiguredBaseRootCapability,
        _: inventory.InventoryDescriptor,
        allocator: std.mem.Allocator,
        _: pipeline.NodeRuntime,
    ) source_port.Error![]const u8 {
        const self: *FakeCapturer = @ptrCast(@alignCast(context));
        self.calls += 1;
        return allocator.dupe(u8, "abc") catch error.DefinitionReadError;
    }
};
