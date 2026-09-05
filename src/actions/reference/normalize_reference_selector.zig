const std = @import("std");
const selector = @import("../../domain/reference_selector.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    normalizer: unicode.Normalizer,
    pub const contract: pipeline.NodeContract = .{
        .id = "normalize-reference-selector@1",
        .kind = .action,
        .requires = &.{.specify_invocation},
        .produces = &.{.normalized_reference_selector},
        .side_effect = .none,
    };

    pub fn execute(self: Action, allocator: std.mem.Allocator, invocation: @import("../../domain/specify_invocation.zig").Invocation) unicode.Error!selector.NormalizedCandidate {
        const nfc = try self.normalizer.nfc(allocator, invocation.raw_reference, selector.max_bytes);
        defer allocator.free(nfc);
        return .{ .bytes = try @import("../../domain/relative_directory_path.zig").normalize(allocator, nfc) };
    }
};
