const pipeline = @import("../../domain/pipeline.zig");
const std = @import("std");
const registry = @import("../../domain/principle_registry.zig");
const policy = @import("../../domain/principle_policy.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
pub const Action = struct {
    config: ?policy.Input = null,
    normalizer: unicode.Normalizer,
    case_folder: unicode.CaseFolder,
    pub const contract: pipeline.NodeContract = .{ .id = "build-principle-registry", .kind = .action, .requires = &.{.captured_principles}, .optional = &.{.prior_principle_registry}, .produces = &.{.principle_registry}, .side_effect = .none };
    pub fn execute(self: Action, a: std.mem.Allocator, captured: registry.Captured, prior: ?registry.Registry) registry.Error!registry.Registry {
        const config = self.config orelse return error.InvalidPrinciplePolicy;
        return registry.buildConfigured(a, captured, config, self.normalizer, self.case_folder, prior);
    }
};
