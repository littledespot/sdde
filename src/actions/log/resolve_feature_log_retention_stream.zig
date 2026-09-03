const binding = @import("../../domain/feature_log_binding.zig");
const pipeline = @import("../../domain/pipeline.zig");
const retention = @import("../../domain/feature_log_retention.zig");
const stream = @import("../../domain/feature_log_stream.zig");

pub const Error = error{FeatureLogRetentionAuthorizationInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "resolve-feature-log-retention-stream@1",
        .kind = .action,
        .requires = &.{ .feature_log_binding, .feature_log_retention_authorization },
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        authorization: *const retention.AuthorizationOwner,
        current: *const binding.ValidatedFeatureLogBinding,
        historical: *const binding.ValidatedFeatureLogBinding,
    ) Error!stream.Stream {
        return retention.authorizedStream(authorization, current, historical) orelse {
            return error.FeatureLogRetentionAuthorizationInvalid;
        };
    }
};
