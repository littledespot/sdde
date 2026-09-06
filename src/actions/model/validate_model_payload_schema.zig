const pipeline = @import("../../domain/pipeline.zig");
const envelope = @import("../../domain/model_envelope.zig");
const validation = @import("../../domain/model_payload_schema.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-model-payload-schema",
        .kind = .action,
        .requires = &@import("../../domain/workflow_model_invocation.zig").payload_schema_requires,
        .produces = &.{.model_payload_schema_result},
        .side_effect = .none,
    };

    pub fn execute(_: Action, candidate: *const envelope.Candidate) validation.Result {
        return validation.validate(candidate);
    }
};
