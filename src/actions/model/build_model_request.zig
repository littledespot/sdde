const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const provider = @import("../../domain/llm_provider_operation.zig");
const preparation = @import("../../domain/model_request_preparation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "build-model-request",
        .kind = .action,
        .requires = &.{ .model_request_identity_ledger, .validated_provider_model_binding },
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, source: preparation.Source, content: []const provider.ModelVisibleContent) preparation.Error!preparation.Owned {
        return preparation.build(allocator, source, content);
    }
};
