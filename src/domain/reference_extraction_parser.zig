const std = @import("std");
const extraction = @import("reference_extraction.zig");
const json = @import("strict_json.zig");

// Native candidate decoding for the lossless Markdown reader, which currently
// supplies no structured-token candidates. Never silently discard classifications.
const Content = struct { kind: std.meta.Tag(extraction.ProposalContent), text: std.json.Value };
const Claim = struct { content: Content, citations: []const @import("reference_evidence.zig").CitationProposal };
const Claims = struct { kind: enum { claims }, claims: []const Claim, token_classifications: [0]struct {} };
const NoClaim = struct { kind: enum { no_feature_claim }, reason: extraction.text.ReferenceSemanticText, token_classifications: [0]struct {} };

/// Caller arena owns all decoded strings/collections; no partial value escapes.
pub fn parse(allocator: std.mem.Allocator, raw: extraction.Raw) extraction.Error!extraction.Parsed {
    const entries = try allocator.alloc(extraction.ParsedResult, raw.entries.len);
    for (raw.entries, entries) |entry, *result| {
        result.scope = .{
            .state_id = .{ .bytes = try allocator.dupe(u8, entry.scope.state_id.bytes) },
            .chunk_id = .{ .bytes = try allocator.dupe(u8, entry.scope.chunk_id.bytes) },
        };
        result.outcome = switch (entry.result) {
            .blocked => |reason| .{ .blocked = reason },
            .response => |bytes| outcome: {
                var document = json.parse(allocator, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }, true) catch |err| return mapError(err);
                defer document.deinit();
                if (document.value != .object) return error.InvalidReferenceExtraction;
                const kind = document.value.object.get("kind") orelse return error.InvalidReferenceExtraction;
                if (kind != .string) return error.InvalidReferenceExtraction;
                if (std.mem.eql(u8, kind.string, "claims")) {
                    const decoded = std.json.parseFromSliceLeaky(Claims, allocator, bytes, .{ .allocate = .alloc_always, .max_value_len = bytes.len }) catch |err| return mapError(err);
                    const claims = try allocator.alloc(extraction.Proposal, decoded.claims.len);
                    for (decoded.claims, claims) |claim, *proposal| {
                        proposal.citations = claim.citations;
                        proposal.content = switch (claim.content.kind) {
                            inline else => |tag| @unionInit(extraction.ProposalContent, @tagName(tag), std.json.parseFromValueLeaky(@FieldType(extraction.ProposalContent, @tagName(tag)), allocator, claim.content.text, .{ .allocate = .alloc_always, .max_value_len = bytes.len }) catch |err| return mapError(err)),
                        };
                    }
                    break :outcome .{ .claims = claims };
                } else if (std.mem.eql(u8, kind.string, "no_feature_claim")) {
                    const decoded = std.json.parseFromSliceLeaky(NoClaim, allocator, bytes, .{ .allocate = .alloc_always, .max_value_len = bytes.len }) catch |err| return mapError(err);
                    break :outcome .{ .no_feature_claim = decoded.reason };
                }
                return error.InvalidReferenceExtraction;
            },
        };
    }
    return .{ .entries = entries };
}
fn mapError(err: anyerror) extraction.Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceExtraction;
}
