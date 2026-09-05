const pipeline = @import("../../domain/pipeline.zig");
const provider = @import("../../domain/llm_provider_operation.zig");
const preparation = @import("../../domain/model_request_preparation.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-static-model-request-capacity@1",
        .kind = .action,
        .requires = &.{ .model_request_identity_ledger, .validated_provider_model_binding },
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(_: Action, source: preparation.Source, request: *const provider.IdentifiedProviderNeutralModelRequest) preparation.ValidationError!*const preparation.StaticCapacityEvidence {
        return preparation.validateStaticCapacity(source, request);
    }
};
