const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const authority = @import("../../domain/required_authority.zig");
const support = @import("../../domain/specification_support.zig");
const stop = @import("../../domain/specification_advice_stop.zig");

pub const Action = struct {
    pub const contract: pipeline.NodeContract = stop.contract(.protocol);

    pub fn execute(_: @This(), comptime purpose: support.Purpose, allocator: std.mem.Allocator, inputs: authority.Inputs, context: @import("../../domain/specification_provenance.zig").Context, prior: ?support.Contract(purpose).Collection, reason: authority.AdviceStop.Reason, origin: ?@import("../../domain/model_candidate_origin.zig").Origin) support.Contract(purpose).Error!support.Contract(purpose).Collection {
        return support.Contract(purpose).stop(allocator, inputs, context, prior, reason, origin);
    }
};
