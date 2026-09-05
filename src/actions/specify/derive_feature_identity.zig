const std = @import("std");
const identity = @import("../../domain/feature_identity.zig");
const reference = @import("../../domain/reference_selector.zig");
const unicode = @import("../../ports/unicode_normalizer.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Action = struct {
    normalizer: unicode.Normalizer,
    pub const contract: pipeline.NodeContract = .{
        .id = "derive-feature-identity@1",
        .kind = .action,
        .requires = &.{.relative_reference_selector},
        .produces = &.{.feature_identity_seed},
        .side_effect = .none,
    };

    pub fn execute(self: Action, allocator: std.mem.Allocator, selector: reference.RelativeSelector, policy: identity.NamingPolicy) (identity.Error || reference.Error || unicode.Error)!identity.FeatureIdentitySeed {
        _ = try reference.validate(.{ .bytes = selector.bytes });
        if (policy.maximum_length == 0) return error.InvalidFeatureNamingPolicy;
        const folded = try self.normalizer.fold(allocator, selector.bytes, identity.maximum_folded_bytes);
        defer allocator.free(folded);
        return .{
            .reference_selector = selector,
            .naming_policy = policy,
            .feature_id = try identity.fromFolded(allocator, folded, policy),
        };
    }
};
