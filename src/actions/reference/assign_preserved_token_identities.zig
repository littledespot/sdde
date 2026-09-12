const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const extraction = @import("../../domain/reference_extraction.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "assign-preserved-token-identities", .kind = .action, .requires = &.{.validated_reference_selections}, .produces = &.{.preserved_token_identities}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, classified: extraction.Classified) extraction.Error!extraction.TokenAssignments {
        var assignments: std.ArrayList(extraction.tokens.Assignment) = .empty;
        var next: u32 = 1;
        for (classified.selections, 0..) |selection, index| switch (selection.decision) {
            .preserve => {
                try assignments.append(allocator, .{ .selection_index = index, .id = .{ .ordinal = next } });
                next = std.math.add(u32, next, 1) catch return error.InvalidStructuredTokens;
            },
            .irrelevant, .blocked => {},
        };
        return .{ .classified = classified, .entries = try assignments.toOwnedSlice(allocator), .next_token_ordinal = next };
    }
};
