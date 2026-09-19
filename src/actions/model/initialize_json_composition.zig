const std = @import("std");
const runtime = @import("../../domain/json_composition_runtime.zig");
const pipeline = @import("../../domain/pipeline.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "initialize-json-composition",
        .kind = .action,
        .requires = &.{ .model_input_packet, .model_request_identity_ledger },
        .produces = &.{.json_composition},
        .side_effect = .none,
    };
    pub fn execute(_: Action, allocator: std.mem.Allocator, plan: *const @import("../../domain/json_composition.zig").Plan, base: *const @import("../../domain/model_input_packet.zig").Packet, epoch: @import("../../domain/model_request_identity.zig").StageRunEpochId) !runtime.State {
        return runtime.State.init(allocator, plan, base, epoch);
    }
};
