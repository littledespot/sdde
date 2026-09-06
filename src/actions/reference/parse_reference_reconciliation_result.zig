const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "parse-reference-reconciliation-result", .kind = .action, .requires = &.{.raw_reference_reconciliation}, .produces = &.{.parsed_reference_reconciliation}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, raw: r.Raw) r.Error!r.Parsed {
        @import("../../domain/strict_json.zig").validateTransport(allocator, raw.bytes, .{ .maximum_depth = @import("../../domain/model_result_schema.zig").max_json_depth }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
        const proposal = std.json.parseFromSliceLeaky(@FieldType(r.Parsed, "proposal"), allocator, raw.bytes, .{ .allocate = .alloc_always, .max_value_len = raw.bytes.len }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
        return .{ .input = raw.input, .proposal = proposal };
    }
};
