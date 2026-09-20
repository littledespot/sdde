const feature = @import("../domain/feature_directory.zig");
const telemetry = @import("../domain/telemetry.zig");
const run = @import("../domain/run_outcome.zig");

pub const Context = opaque {};
pub const Outcome = union(enum) {
    ready: feature.Directory,
    blocked: @import("../domain/feature_log_stream.zig").FailureCode,
    cancelled,
};

/// Fixed feature-log lifecycle operation; exposes no arbitrary node execution.
pub const Activator = struct {
    context: *Context,
    activate_fn: *const fn (*Context, feature.Directory, telemetry.WorkflowShortcode) Outcome,

    pub fn activate(self: Activator, directory: feature.Directory, shortcode: telemetry.WorkflowShortcode) Outcome {
        return self.activate_fn(self.context, directory, shortcode);
    }
};

pub const Finalizer = struct {
    pub const Reason = union(enum) {
        terminal: run.Outcome,
        publication: @import("../domain/workflow_output.zig").TerminalOutcome,
        pub fn outcome(self: Reason) run.Outcome {
            return switch (self) {
                .terminal => |value| value,
                .publication => |value| .{ .execution = switch (value) {
                    .ok => .ok,
                    .needs_user => .needs_user,
                } },
            };
        }
    };
    context: *Context,
    finish_fn: *const fn (*Context, Reason) run.Outcome,

    pub fn finish(self: Finalizer, outcome: run.Outcome) run.Outcome {
        return self.finish_fn(self.context, .{ .terminal = outcome });
    }
    pub fn beforePublication(self: Finalizer, outcome: @import("../domain/workflow_output.zig").TerminalOutcome) run.Outcome {
        return self.finish_fn(self.context, .{ .publication = outcome });
    }
};
