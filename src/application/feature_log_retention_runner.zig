const acquire = @import("../actions/log/acquire_feature_log_stream_lock.zig");
const prune = @import("../actions/log/prune_feature_log_segments.zig");
const release = @import("../actions/log/release_feature_log_stream_lock.zig");
const resolve_stream = @import("../actions/log/resolve_feature_log_retention_stream.zig");
const binding = @import("../domain/feature_log_binding.zig");
const retention = @import("../domain/feature_log_retention.zig");
const stream = @import("../domain/feature_log_stream.zig");
const bindings = @import("feature_log_retention_child_bindings.zig");

pub const Runner = struct {
    current: *const binding.ValidatedFeatureLogBinding,
    historical: *const binding.ValidatedFeatureLogBinding,
    authorization: *retention.AuthorizationOwner,
    resolve_action: resolve_stream.Action = .{},
    acquire_action: acquire.Action,
    prune_action: prune.Action,
    release_action: release.Action,
    selected_stream: ?stream.Stream = null,

    pub fn childBindings(self: *Runner) bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn invokeResolve(context: *anyopaque) bindings.StepOutcome {
        const self = cast(context);
        self.selected_stream = self.resolve_action.execute(
            self.authorization,
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
        self.prune_action.execute(self.historical, self.authorization) catch return .{ .failed = .LOG_SINK_FAILURE };
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
    .resolve_stream = Runner.invokeResolve,
    .acquire = Runner.invokeAcquire,
    .prune = Runner.invokePrune,
    .release = Runner.invokeRelease,
};
