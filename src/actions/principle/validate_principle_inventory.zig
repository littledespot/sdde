const pipeline = @import("../../domain/pipeline.zig");
const std = @import("std");
const registry = @import("../../domain/principle_registry.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
pub const Action = struct {
    normalizer: unicode.Normalizer,
    case_folder: unicode.CaseFolder,
    pub const contract: pipeline.NodeContract = .{ .id = "validate-principle-inventory", .kind = .action, .requires = &.{.raw_principle_inventory}, .produces = &.{.principle_inventory}, .side_effect = .none };
    pub fn execute(self: Action, a: std.mem.Allocator, raw: registry.Raw) registry.Error!registry.Inventory {
        return registry.classify(a, raw, self.normalizer, self.case_folder);
    }
};
