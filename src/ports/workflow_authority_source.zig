const std = @import("std");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const inventory = @import("../domain/workflow_inventory.zig");

pub const Error = error{ Cancelled, DeadlineExhausted, InventoryInvalid, DefinitionReadError };
pub const Source = struct {
    context: *anyopaque,
    enumerate_fn: *const fn (
        *anyopaque,
        *const bootstrap_root_registry.ConfiguredBaseRootCapability,
        std.mem.Allocator,
        pipeline.NodeRuntime,
    ) Error![]inventory.InventoryDescriptor,
    capture_fn: *const fn (
        *anyopaque,
        *const bootstrap_root_registry.ConfiguredBaseRootCapability,
        inventory.InventoryDescriptor,
        std.mem.Allocator,
        pipeline.NodeRuntime,
    ) Error![]const u8,

    pub fn enumerate(
        self: Source,
        capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) Error![]inventory.InventoryDescriptor {
        return self.enumerate_fn(self.context, capability, allocator, runtime);
    }
    pub fn capture(
        self: Source,
        capability: *const bootstrap_root_registry.ConfiguredBaseRootCapability,
        descriptor: inventory.InventoryDescriptor,
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
    ) Error![]const u8 {
        return self.capture_fn(self.context, capability, descriptor, allocator, runtime);
    }
};
