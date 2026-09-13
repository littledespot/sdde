//! Typed validator evidence for observers. This projection grants no repair or
//! workflow authority; the retained validator/authorization values own that.
const std = @import("std");
pub const Diagnostic = union(enum) {
    reconciliation: @import("reference_reconciliation_diagnostic.zig").Rejection,
    token_classifications: @import("token_classification_validation.zig").Rejection,
    source_selections: @import("reference_selection_validation.zig").Rejection,
    specification: @import("specification_candidate.zig").Rejection,

    pub fn origin(self: Diagnostic) ?@import("model_candidate_origin.zig").Origin {
        return switch (self) {
            .reconciliation => |value| value.origin,
            .token_classifications => |value| value.origin,
            .source_selections => |value| value.origin,
            .specification => |value| value.origin,
        };
    }

    pub fn copy(self: Diagnostic, allocator: std.mem.Allocator) @import("strict_json.zig").Error!Diagnostic {
        const bytes = try std.json.Stringify.valueAlloc(allocator, self, .{});
        defer allocator.free(bytes);
        return @import("strict_json.zig").decode(Diagnostic, allocator, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
    }
};
