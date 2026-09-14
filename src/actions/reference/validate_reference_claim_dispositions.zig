const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
const dispositions = @import("../../domain/reference_disposition_validation.zig");
const d = r.diagnostic;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-claim-dispositions", .kind = .action, .requires = &.{.parsed_reference_reconciliation}, .produces = &.{.validated_reference_dispositions}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, parsed: r.Parsed) r.Error!d.Result(r.CheckedDispositions) {
        if (parsed.input.purpose != .global or parsed.proposal != .global or parsed.input.partition.group.level != .global) return error.InvalidReferenceReconciliation;
        try v.input(allocator, parsed.input);
        if (parsed.source.revision == 0) return error.InvalidReferenceReconciliation;
        var result = try dispositions.validate(allocator, parsed);
        if (result == .invalid) {
            result.invalid.relations = try dispositions.redundancy(allocator, parsed);
            result.invalid.dependencies = try @import("../../domain/reference_reconciliation_context.zig").snapshot(allocator, parsed, null);
        }
        return result;
    }
};
