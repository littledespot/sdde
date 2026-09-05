const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const invocation = @import("../../domain/provider_invocation_validation.zig");
const envelope = @import("../../domain/model_envelope.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "decode-model-envelope@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, complete: *const invocation.CompleteCandidate) envelope.Error!envelope.Owned {
        return envelope.decode(allocator, complete);
    }
};
