const std = @import("std");
const log_policy = @import("../../domain/log_policy.zig");
const pipeline = @import("../../domain/pipeline.zig");
const log_binding = @import("../../domain/feature_log_binding.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");
const log_retention = @import("../../domain/feature_log_retention.zig");
const clock_port = @import("../../ports/trusted_log_clock.zig");

pub const Error = error{FeatureLogRetentionAuthorizationInvalid};

pub const Action = struct {
    clock: clock_port.Clock,

    pub const contract: pipeline.NodeContract = .{
        .id = "build-feature-log-retention-authorization@1",
        .kind = .action,
        .requires = &.{ .logging_policy, .feature_log_binding },
        .produces = &.{.feature_log_retention_authorization},
        .side_effect = .none,
    };

    pub fn execute(
        self: Action,
        allocator: std.mem.Allocator,
        policy: *const log_policy.CompiledLoggingPolicy,
        current: *const log_binding.ValidatedFeatureLogBinding,
        historical: *const log_binding.ValidatedFeatureLogBinding,
        stream: log_stream.Stream,
    ) Error!*log_retention.AuthorizationOwner {
        const reading = self.clock.now() catch return error.FeatureLogRetentionAuthorizationInvalid;
        return log_retention.create(
            allocator,
            policy,
            current,
            historical,
            stream,
            reading.unix_ms,
        ) catch error.FeatureLogRetentionAuthorizationInvalid;
    }
};
