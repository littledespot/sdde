const std = @import("std");
const runtime = @import("../../domain/json_composition_runtime.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "retain-json-part",
        .kind = .action,
        .requires = &.{ .json_composition, .model_request_identity_ledger, .prepared_model_request, .model_payload_schema_result },
        .produces = &.{},
        .replaces = &.{.json_composition},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, state: runtime.State, binding: runtime.Binding, proof: *const @import("../../domain/model_payload_schema.zig").Evidence, origin: @import("../../domain/model_candidate_origin.zig").Origin, ledger: *const @import("../../domain/model_request_identity.zig").ModelRequestIdentityLedger) !runtime.State {
        return state.retain(allocator, binding, proof, origin, ledger);
    }
};
