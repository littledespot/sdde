//! Typed validator evidence for observers. This projection grants no repair or
//! workflow authority; the retained validator/authorization values own that.
const std = @import("std");
const spec = @import("specification_repair.zig");
pub const Diagnostic = union(enum) {
    token_classifications: @import("token_classification_validation.zig").Rejection,
    source_selections: @import("reference_selection_validation.zig").Rejection,
    specification_repair: struct {
        owner: @import("model_request_identity.zig").ImmutableUnitOwnerId,
        revision: u64,
        target: spec.Target,
        rule: spec.Rule,
    },

    pub fn origin(self: Diagnostic) ?@import("model_candidate_origin.zig").Origin {
        return switch (self) {
            .token_classifications => |value| value.origin,
            .source_selections => |value| value.origin,
            .specification_repair => null,
        };
    }

    pub fn copy(self: Diagnostic, allocator: std.mem.Allocator) @import("strict_json.zig").Error!Diagnostic {
        const bytes = try std.json.Stringify.valueAlloc(allocator, self, .{});
        defer allocator.free(bytes);
        return @import("strict_json.zig").decode(Diagnostic, allocator, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
    }
};
