const pipeline = @import("../../domain/pipeline.zig");
const guidance = @import("../../domain/packet_guidance.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "capture-packet-guidance", .kind = .action, .requires = &.{}, .produces = &.{.packet_guidance}, .side_effect = .none };
    /// The compiler already validated the workflow resource; consumers read only
    /// this run value, never the resource.
    pub fn execute(_: Action, compiled: *const guidance.Compiled) guidance.Guidance {
        return compiled.guidance;
    }
};
