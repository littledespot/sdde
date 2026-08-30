const std = @import("std");
const roots = @import("../../domain/bootstrap_root_registry.zig");
const toolchain = @import("../../domain/toolchain.zig");
const accounting = @import("../../domain/toolchain_accounting.zig");
const source_port = @import("../../ports/toolchain_authority_source.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    source: source_port.Source,
    pub const contract: pipeline.NodeContract = .{ .id = "capture-toolchain-presets@1", .kind = .action, .requires = &.{ .project_toolchain_capture, .toolchain_preset_inventory }, .produces = &.{.toolchain_preset_captures}, .side_effect = .filesystem_read };
    pub fn execute(self: Action, allocator: std.mem.Allocator, registry: *const roots.BootstrapRootRegistry, project: toolchain.Capture, entries: []const toolchain.Entry) toolchain.Error![]const toolchain.Capture {
        try accounting.validateCaptureBudget(project, entries);
        const captures = allocator.alloc(toolchain.Capture, entries.len) catch return error.InvalidToolchain;
        for (entries, captures) |entry, *capture| {
            capture.* = self.source.capturePreset(registry.toolchainPresetRegistry(), entry, allocator) catch return error.InvalidToolchain;
        }
        return captures;
    }
};
