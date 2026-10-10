//! Offline mock evidence for loss-admission mechanics; never semantic proof.
const std = @import("std");
const loss = @import("../domain/source_omission.zig");
const authority = @import("../domain/required_authority.zig");
const refs = @import("../domain/reference_reconciliation.zig");

pub fn comparison(inputs: authority.Inputs, location: loss.Location) !?loss.Comparison {
    if (!loss.isUpstream(location)) return null;
    const records = inputs.references orelse return error.InvalidFixture;
    const chunk_id = switch (location) {
        .unlocalized, .candidate => unreachable,
        .extraction_claim => |id| id,
        .token_classification => |id| found: {
            for (records.items.extraction) |chunk| for (chunk.token_classifications) |classification| {
                if (std.meta.eql(classification.id(), id)) break :found chunk.scope.chunk_id;
            };
            return error.InvalidFixture;
        },
        .reconciliation_signal, .reconciliation_disposition, .reconciliation_conflict => found: {
            const claims = loss.diagnosticClaims(records, location) orelse return error.InvalidFixture;
            if (claims.len == 0) return error.InvalidFixture;
            break :found (try refs.item(records.items, claims[0])).claim.chunk_id;
        },
    };
    return .{ .source = .{ .chunk_id = chunk_id, .lines = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } } }, .producer_loss = "MOCK The selected producer omits the source obligation." };
}

pub fn encode(a: std.mem.Allocator, inputs: authority.Inputs, location: loss.Location) ![]const u8 {
    const assessment: loss.Assessment = switch (location) {
        .unlocalized => .{ .unlocalized = .{} },
        .candidate => .{ .candidate = .{} },
        else => .{ .localized = .{ .location = location, .comparison = (try comparison(inputs, location)).? } },
    };
    return @import("../domain/model_candidate_json.zig").encode(loss.Assessment, a, assessment);
}
