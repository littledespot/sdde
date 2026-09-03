const log_policy = @import("../../domain/log_policy.zig");
const prompt_log = @import("../../domain/sanitized_prompt_log.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Decision = enum { capture, drop };

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "evaluate-prompt-log-capture@1",
        .kind = .action,
        .requires = &.{ .logging_policy, .validated_prompt_fragment },
        .produces = &.{.prompt_capture_decision},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        policy: log_policy.CompiledLoggingPolicy,
        fragment: prompt_log.SanitizedPromptFragment,
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
