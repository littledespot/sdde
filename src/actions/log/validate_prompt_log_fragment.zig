const prompt_log = @import("../../domain/sanitized_prompt_log.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{InvalidPromptLogFragment};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-prompt-log-fragment@1",
        .kind = .action,
        .requires = &.{.sanitized_prompt_fragment},
        .produces = &.{.validated_prompt_fragment},
        .side_effect = .none,
    };

    pub fn execute(_: Action, fragment: prompt_log.SanitizedPromptFragment) Error!void {
        prompt_log.validate(fragment) catch return error.InvalidPromptLogFragment;
    }
};
