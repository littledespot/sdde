const validate_finalization = @import("../actions/log/validate_feature_log_finalization.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const telemetry = @import("../domain/telemetry.zig");
const bindings = @import("feature_log_finalization_child_bindings.zig");
const feature_log_runner = @import("feature_log_runner.zig");

pub const Runner = struct {
    target: *feature_log_runner.Runner,
    mode: log_stream.FinalizationMode,
    shortcode: telemetry.WorkflowShortcode,
    validate_action: validate_finalization.Action = .{},

    pub fn childBindings(self: *Runner) bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn targetBinding(context: *anyopaque) bindings.Target {
        const self = cast(context);
        return .{ .identity = self.target.childBindings().identity(), .mode = self.mode };
    }

    fn invokeValidate(context: *anyopaque) bindings.ValidationOutcome {
        const self = cast(context);
        const status: log_stream.RuntimeStatus = if (self.target.retired)
            .retired
        else if (self.target.prepared)
            .prepared
        else
            .unprepared;
        self.validate_action.execute(self.mode, status) catch return .invalid;
        return .valid;
    }

    fn invokePrepare(context: *anyopaque) log_stream.Outcome {
        const self = cast(context);
        return self.target.prepare(self.shortcode);
    }

    fn invokeClose(context: *anyopaque) log_stream.Outcome {
        const self = cast(context);
        return self.target.close(self.shortcode);
    }

    fn cast(context: *anyopaque) *Runner {
        return @ptrCast(@alignCast(context));
    }
};

const vtable: bindings.ChildBindings.VTable = .{
    .target = Runner.targetBinding,
    .validate = Runner.invokeValidate,
    .prepare = Runner.invokePrepare,
    .close = Runner.invokeClose,
};
