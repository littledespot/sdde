const std = @import("std");
const roots = @import("../domain/bootstrap_root_registry.zig");
const output = @import("../domain/workflow_output.zig");
pub const Port = struct {
    context: *anyopaque,
    capability: ?*const roots.FeatureOutputWriteCapability = null,
    publish_fn: *const fn (*anyopaque, *const roots.FeatureOutputWriteCapability, std.mem.Allocator, output.Prepared) output.Error!void,
    pub fn publish(self: Port, allocator: std.mem.Allocator, prepared: output.Prepared) output.Error!void {
        return self.publish_fn(self.context, self.capability orelse return error.OutputWriteFailed, allocator, prepared);
    }
};
