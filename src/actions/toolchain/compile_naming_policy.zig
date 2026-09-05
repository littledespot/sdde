const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const naming = @import("../../domain/naming_policy.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "compile-naming-policy@1",
        .kind = .action,
        .requires = &.{.valid_toolchain},
        .produces = &.{.compiled_naming_policy},
        .side_effect = .none,
    };
    normalizer: unicode.Normalizer,
    folder: unicode.CaseFolder,
    pub fn execute(self: Action, allocator: std.mem.Allocator, current: *const @import("../../domain/toolchain_safety.zig").ValidToolchain) naming.Error!naming.Compiled {
        return naming.compile(allocator, current, self.normalizer, self.folder);
    }
};
