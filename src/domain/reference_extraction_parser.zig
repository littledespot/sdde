const std = @import("std");
const extraction = @import("reference_extraction.zig");

pub const Response = union(enum) {
    claims: struct { claims: []const extraction.Proposal, token_classifications: []const extraction.tokens.Classification },
    no_feature_claim: struct { reason: extraction.text.ReferenceSemanticText, token_classifications: []const extraction.tokens.Classification },
};

/// Caller arena owns all decoded strings/collections; no partial value escapes.
pub fn parse(allocator: std.mem.Allocator, raw: extraction.Raw) extraction.Error!extraction.Parsed {
    const entries = try allocator.alloc(extraction.ParsedResult, raw.entries.len);
    for (raw.entries, entries) |entry, *result| {
        result.scope = .{
            .state_id = .{ .bytes = try allocator.dupe(u8, entry.scope.state_id.bytes) },
            .chunk_id = .{ .bytes = try allocator.dupe(u8, entry.scope.chunk_id.bytes) },
        };
        result.token_classifications = &.{};
        result.outcome = switch (entry.result) {
            .blocked => |reason| .{ .blocked = reason },
            .response => |bytes| outcome: {
                const response = @import("model_candidate_json.zig").decode(Response, allocator, bytes) catch |err| return switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    error.InvalidJsonDocument => error.InvalidReferenceExtraction,
                };
                switch (response) {
                    .claims => |value| {
                        result.token_classifications = value.token_classifications;
                        break :outcome .{ .claims = value.claims };
                    },
                    .no_feature_claim => |value| {
                        result.token_classifications = value.token_classifications;
                        break :outcome .{ .no_feature_claim = value.reason };
                    },
                }
            },
        };
    }
    return .{ .entries = entries };
}
