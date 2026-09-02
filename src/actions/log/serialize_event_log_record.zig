const std = @import("std");
const feature_log_format = @import("../../domain/feature_log_format.zig");
const pipeline = @import("../../domain/pipeline.zig");

pub const Error = error{LogSerializationFailure};
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "serialize-event-log-record@1",
        .kind = .action,
        .requires = &.{.identified_log_event},
        .produces = &.{.serialized_log_record},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, record: feature_log_format.EventRecord) Error![]u8 {
        return feature_log_format.serializeEvent(allocator, record) catch error.LogSerializationFailure;
    }
};
