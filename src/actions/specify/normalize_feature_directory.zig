const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const feature = @import("../../domain/feature_directory.zig");
const path = @import("../../domain/relative_directory_path.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");

pub const Action = struct {
    normalizer: unicode.Normalizer,
    pub const contract: pipeline.NodeContract = .{
        .id = "normalize-feature-directory@1",
        .kind = .action,
        .requires = &.{.specify_invocation},
        .produces = &.{.normalized_feature_directory},
        .side_effect = .none,
    };

    pub fn execute(self: Action, allocator: std.mem.Allocator, invocation: @import("../../domain/specify_invocation.zig").Invocation) unicode.Error!feature.NormalizedCandidate {
        const nfc = try self.normalizer.nfc(allocator, invocation.raw_feature, path.max_bytes);
        defer allocator.free(nfc);
        return .{ .bytes = try path.normalize(allocator, nfc) };
    }
};
