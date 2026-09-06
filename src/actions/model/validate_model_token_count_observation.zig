const pipeline = @import("../../domain/pipeline.zig");
const provider = @import("../../domain/llm_provider_operation.zig");
const validation = @import("../../domain/model_token_count_validation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-model-token-count-observation",
        .kind = .action,
        .requires = &@import("../../domain/workflow_model_invocation.zig").count_validation_requires,
        .produces = &.{.provider_token_count_validation_result},
        .side_effect = .none,
    };

    pub fn execute(_: Action, call: validation.Call, observation: *const provider.ProviderTokenCountObservation) validation.Error!validation.Result {
        return validation.validate(call, observation);
    }
};
