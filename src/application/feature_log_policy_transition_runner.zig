const validate_transition = @import("../actions/log/validate_feature_log_policy_transition.zig");
const telemetry = @import("../domain/telemetry.zig");
const bindings = @import("feature_log_policy_transition_child_bindings.zig");
const log_stream = @import("../domain/feature_log_stream.zig");
const feature_log_runner = @import("feature_log_runner.zig");

pub const Runner = struct {
    current: *feature_log_runner.Runner,
    next: *feature_log_runner.Runner,
    shortcode: telemetry.WorkflowShortcode,
    validate_action: validate_transition.Action = .{},

    pub fn childBindings(self: *Runner) bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn participants(context: *anyopaque) bindings.Participants {
        const self = cast(context);
        return .{
            .current_identity = self.current.childBindings().identity(),
            .next = self.next.childBindings(),
        };
    }

    fn invokeValidate(context: *anyopaque) bindings.ValidationOutcome {
        const self = cast(context);
        if (self.current.retired or self.next.retired) return .invalid;
        self.validate_action.execute(
            self.current.binding,
            self.current.policy,
            self.next.binding,
            self.next.policy,
        ) catch return .invalid;
        return .valid;
    }

    fn invokeCloseCurrent(context: *anyopaque) log_stream.Outcome {
        const self = cast(context);
        return self.current.close(self.shortcode);
    }

    fn invokePrepareNext(context: *anyopaque) log_stream.Outcome {
        const self = cast(context);
        return self.next.prepare(self.shortcode);
    }

    fn cast(context: *anyopaque) *Runner {
        return @ptrCast(@alignCast(context));
    }
};

const vtable: bindings.ChildBindings.VTable = .{
    .participants = Runner.participants,
    .validate = Runner.invokeValidate,
    .close_current = Runner.invokeCloseCurrent,
    .prepare_next = Runner.invokePrepareNext,
};
