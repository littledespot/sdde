const logging = @import("../../domain/logging.zig");
const runtime = @import("../../domain/feature_log_runtime.zig");

pub const Decision = enum { capture, drop };

pub const Action = struct {
    pub fn execute(
        _: Action,
        policy: logging.CompiledLoggingPolicy,
        fragment: runtime.SanitizedPromptFragment,
    ) Decision {
        var direction = false;
        var body_class = fragment.body_class == .ordinary;
        for (policy.prompt_capture) |selector| switch (selector) {
            .request => if (fragment.direction == .request) {
                direction = true;
            },
            .response => if (fragment.direction == .response) {
                direction = true;
            },
            .reference_body => if (fragment.body_class == .reference_body) {
                body_class = true;
            },
            .code_body => if (fragment.body_class == .code_body) {
                body_class = true;
            },
        };
        return if (direction and body_class) .capture else .drop;
    }
};
