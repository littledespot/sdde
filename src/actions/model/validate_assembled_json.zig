const runtime = @import("../../domain/json_composition_runtime.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-assembled-json",
        .kind = .action,
        .requires = &.{.assembled_json},
        .produces = &.{.validated_assembled_json},
        .side_effect = .none,
    };
    pub fn execute(_: Action, candidate: *const runtime.Candidate) ?@import("../../domain/model_payload_schema.zig").Diagnostic {
        return candidate.validate();
    }
};
