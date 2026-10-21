const std = @import("std");
const acquire = @import("../actions/log/acquire_feature_log_stream_lock.zig");
const authorize = @import("../actions/log/build_feature_log_retention_authorization.zig");
const prune = @import("../actions/log/prune_feature_log_segments.zig");
const release = @import("../actions/log/release_feature_log_stream_lock.zig");
const resolve_stream = @import("../actions/log/resolve_feature_log_retention_stream.zig");
const binding = @import("../domain/feature_log_binding.zig");
const log_policy = @import("../domain/log_policy.zig");
const retention = @import("../domain/feature_log_retention.zig");
const stream = @import("../domain/feature_log_stream.zig");
const bindings = @import("feature_log_retention_child_bindings.zig");

pub const Runner = struct {
    allocator: std.mem.Allocator,
    policy: *const log_policy.CompiledLoggingPolicy,
    current: *const binding.ValidatedFeatureLogBinding,
    historical: *const binding.ValidatedFeatureLogBinding,
    target_stream: stream.Stream,
    authorize_action: authorize.Action,
    authorization: ?*retention.AuthorizationOwner = null,
    resolve_action: resolve_stream.Action = .{},
    acquire_action: acquire.Action,
    prune_action: prune.Action,
    release_action: release.Action,
    selected_stream: ?stream.Stream = null,

    pub fn childBindings(self: *Runner) bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    pub fn deinit(self: *Runner) void {
        if (self.authorization) |owner| retention.deinit(owner);
        self.authorization = null;
    }

    fn invokeAuthorize(context: *anyopaque) bindings.StepOutcome {
        const self = cast(context);
        if (self.authorization != null) return .{ .failed = .LOG_SINK_FAILURE };
        self.authorization = self.authorize_action.execute(self.allocator, self.policy, self.current, self.historical, self.target_stream) catch return .{ .failed = .LOG_SINK_FAILURE };
        return .ok;
    }

    fn invokeResolve(context: *anyopaque) bindings.StepOutcome {
        const self = cast(context);
        self.selected_stream = self.resolve_action.execute(
            self.authorization orelse return .{ .failed = .LOG_SINK_FAILURE },
            self.current,
            self.historical,
        ) catch return .{ .failed = .LOG_SINK_FAILURE };
        return .ok;
    }
    fn invokeAcquire(context: *anyopaque) bindings.StepOutcome {
        const self = cast(context);
        self.acquire_action.execute(self.historical, self.selected_stream.?) catch return .{ .failed = .LOG_LOCK_TIMEOUT };
        return .ok;
    }
    fn invokePrune(context: *anyopaque) bindings.StepOutcome {
        const self = cast(context);
        self.prune_action.execute(self.historical, self.authorization orelse return .{ .failed = .LOG_SINK_FAILURE }) catch return .{ .failed = .LOG_SINK_FAILURE };
        return .ok;
    }
    fn invokeRelease(context: *anyopaque) bindings.StepOutcome {
        cast(context).release_action.execute() catch return .{ .failed = .LOG_RELEASE_FAILURE };
        return .ok;
    }
    fn cast(context: *anyopaque) *Runner {
        return @ptrCast(@alignCast(context));
    }
};

const vtable: bindings.ChildBindings.VTable = .{
    .authorize = Runner.invokeAuthorize,
    .resolve_stream = Runner.invokeResolve,
    .acquire = Runner.invokeAcquire,
    .prune = Runner.invokePrune,
    .release = Runner.invokeRelease,
};
