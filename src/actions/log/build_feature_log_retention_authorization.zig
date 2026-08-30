const std = @import("std");
const logging = @import("../../domain/logging.zig");
const pipeline = @import("../../domain/pipeline.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");
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
        policy: *const logging.CompiledLoggingPolicy,
        current: *const runtime.ValidatedFeatureLogBinding,
        historical: *const runtime.ValidatedFeatureLogBinding,
        stream: runtime.Stream,
    ) Error!*runtime.RetentionAuthorizationOwner {
        const reading = self.clock.now() catch return error.FeatureLogRetentionAuthorizationInvalid;
        return runtime.createRetentionAuthorization(
            allocator,
            policy,
            current,
            historical,
            stream,
            reading.unix_ms,
        ) catch error.FeatureLogRetentionAuthorizationInvalid;
    }
};
