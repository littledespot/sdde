const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-reference-reconciliation-result", .kind = .action, .requires = &.{.raw_reference_reconciliation}, .produces = &.{.parsed_reference_reconciliation}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, raw: r.Raw) r.Error!r.Parsed {
        const proposal = @import("../../domain/model_candidate_json.zig").decode(@FieldType(r.Parsed, "proposal"), allocator, raw.bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
        return .{ .input = raw.input, .proposal = proposal };
    }
};
