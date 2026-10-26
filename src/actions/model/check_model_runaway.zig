const pipeline = @import("../../domain/pipeline.zig");
const provider = @import("../../domain/llm_provider_operation.zig");
const validation = @import("../../domain/provider_invocation_validation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "check-model-runaway", .kind = .action, .requires = &.{ .model_request_identity_ledger, .prepared_model_request, .model_payload_schema_result }, .produces = &.{}, .side_effect = .none };
    /// ADR 0039: `more` when this exact attempt is a first runaway, which takes
    /// its one re-send; otherwise `ok`, for the ordinary correction.
    pub fn execute(_: Action, current: *const provider.IdentifiedProviderNeutralModelRequest, rejected: ?*const validation.Evidence) @import("../../domain/workflow.zig").OutcomeTag {
        const evidence = rejected orelse return .ok;
        return if (evidence.request() == current and evidence.runaway() == .first) .more else .ok;
    }
};
