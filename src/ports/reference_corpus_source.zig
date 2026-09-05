const std = @import("std");
const reference = @import("../domain/reference_ingestion.zig");
const roots = @import("../domain/bootstrap_root_registry.zig");
pub const Error = std.mem.Allocator.Error || error{ ReferenceUnavailable, ReferenceInventoryChanged, ReferenceLimitExceeded, Cancelled };
pub const Enumerator = struct {
    context: *anyopaque,
    capability: ?*const roots.ReferenceContentReadCapability = null,
    enumerate_fn: *const fn (*anyopaque, *const roots.ReferenceContentReadCapability, std.mem.Allocator, @import("../domain/reference_selector.zig").Directory) Error!reference.RawInventory,
    pub fn enumerate(self: Enumerator, allocator: std.mem.Allocator, directory: @import("../domain/reference_selector.zig").Directory) Error!reference.RawInventory {
        return self.enumerate_fn(self.context, self.capability orelse return error.ReferenceUnavailable, allocator, directory);
    }
};
pub const Capturer = struct {
    context: *anyopaque,
    capability: ?*const roots.ReferenceContentReadCapability = null,
    capture_fn: *const fn (*anyopaque, *const roots.ReferenceContentReadCapability, std.mem.Allocator, reference.Inventory) Error!reference.CapturedCorpus,
    pub fn capture(self: Capturer, allocator: std.mem.Allocator, inventory: reference.Inventory) Error!reference.CapturedCorpus {
        return self.capture_fn(self.context, self.capability orelse return error.ReferenceUnavailable, allocator, inventory);
    }
};
