const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const provider = @import("../../domain/llm_provider_operation.zig");
const validation = @import("../../domain/provider_invocation_validation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-provider-invocation-observation",
        .kind = .action,
        .requires = &@import("../../domain/workflow_model_invocation.zig").validation_requires,
        .produces = &.{.provider_invocation_validation_result},
        .side_effect = .none,
    };

    pub fn execute(_: Action, allocator: std.mem.Allocator, call: validation.Call, observation: *const provider.ProviderInvocationObservation) validation.Error!validation.Owned {
        return validation.validate(allocator, call, observation);
    }
};
