const pipeline = @import("../../domain/pipeline.zig");
const envelope = @import("../../domain/model_envelope.zig");
const validation = @import("../../domain/model_payload_schema.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-model-payload-schema@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .side_effect = .none,
    };

    pub fn execute(_: Action, candidate: *const envelope.Candidate) validation.Result {
        return validation.validate(candidate);
    }
};
