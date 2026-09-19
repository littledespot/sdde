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
    context: *Context,
    finish_fn: *const fn (*Context, run.Outcome) run.Outcome,

    pub fn finish(self: Finalizer, outcome: run.Outcome) run.Outcome {
        return self.finish_fn(self.context, outcome);
    }
};
