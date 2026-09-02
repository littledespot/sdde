const runtime = @import("../../domain/feature_log_runtime.zig");

pub const Error = error{InvalidPromptLogFragment};

pub const Action = struct {
    pub fn execute(_: Action, fragment: runtime.SanitizedPromptFragment) Error!void {
        runtime.validateSanitizedPromptFragment(fragment) catch return error.InvalidPromptLogFragment;
    }
};
