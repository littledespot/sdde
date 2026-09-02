const std = @import("std");
const feature_log_format = @import("../../domain/feature_log_format.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LogSerializationFailure};
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "serialize-prompt-log-record@1",
        .kind = .action,
        .requires = &.{.sanitized_prompt_fragment},
        .produces = &.{.serialized_log_record},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, record: feature_log_format.PromptRecord) Error![]u8 {
        return feature_log_format.serializePrompt(allocator, record) catch error.LogSerializationFailure;
    }
};
