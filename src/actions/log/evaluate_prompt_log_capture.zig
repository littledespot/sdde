const log_policy = @import("../../domain/log_policy.zig");
const prompt_log = @import("../../domain/sanitized_prompt_log.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Decision = enum { capture, drop };

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "evaluate-prompt-log-capture",
        .kind = .action,
        .requires = &.{ .logging_policy, .validated_prompt_fragment },
        .produces = &.{.prompt_capture_decision},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        policy: log_policy.CompiledLoggingPolicy,
        _: prompt_log.SanitizedPromptFragment,
    ) Decision {
        return if (log_policy.promptCaptureEnabled(policy)) .capture else .drop;
    }
};
