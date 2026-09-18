const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const loss = @import("../../domain/source_omission.zig");
const ex = @import("../../domain/reference_extraction_repair.zig").Omission;
const r = @import("../../domain/reference_reconciliation.zig");
const Context = @import("../../domain/reference_reconciliation_validation.zig").TextContext;
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "merge-source-extraction-repair", .kind = .action, .requires = &loss.extraction_requires, .produces = &.{}, .replaces = &.{.text_validated_reference_extraction}, .invalidates = &loss.extraction_dependents, .side_effect = .none };
    validator: r.text.Validator,
    pub fn execute(self: @This(), a: std.mem.Allocator, facts: ex.Facts, ctx: Context, repair: loss.Repair) ex.Error!r.extraction.TextValidated {
        const response = repair.response orelse return error.InvalidAtomicRepair;
        if (repair.authorization != .extraction or response.value != .extraction) return error.InvalidAtomicRepair;
        return ex.merge(a, self.validator, ctx.registry, ctx.current, facts, repair.authorization.extraction, response.value.extraction, response.origin);
    }
};
