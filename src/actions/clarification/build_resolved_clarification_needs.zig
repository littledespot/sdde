const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const authority = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-resolved-clarification-needs", .kind = .action, .requires = &.{ .citable_reference_inputs, .required_authority_result, .required_authority_gate }, .produces = &.{.clarification_needs}, .side_effect = .none };
    pub fn execute(_: Action, a: std.mem.Allocator, sources: @import("../../domain/reference_evidence.zig").Inputs, result: authority.Result) authority.Error!@import("../../domain/clarification_refresh.zig").Needs {
        if (result.continuation != .all_resolved or !std.mem.eql(u8, result.feature.bytes, sources.corpus.feature_id.bytes)) return error.InvalidRequiredAuthority;
        return .{ .feature = result.feature, .original_sources = @import("../../domain/clarification_refresh.zig").originalSources(a, sources) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidRequiredAuthority, .entries = &.{} };
    }
};
