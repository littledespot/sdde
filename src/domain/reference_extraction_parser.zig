const std = @import("std");
const extraction = @import("reference_extraction.zig");
const json = @import("strict_json.zig");

const Content = struct { kind: std.meta.Tag(extraction.ProposalContent), text: std.json.Value };
const Claim = struct { content: Content, citations: []const @import("reference_evidence.zig").CitationProposal };
const Claims = struct { kind: enum { claims }, claims: []const Claim, token_classifications: []const std.json.Value };
const NoClaim = struct { kind: enum { no_feature_claim }, reason: extraction.text.ReferenceSemanticText, token_classifications: []const std.json.Value };

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
                var document = json.parse(allocator, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }, true) catch |err| return mapError(err);
                defer document.deinit();
                if (document.value != .object) return error.InvalidReferenceExtraction;
                const kind = document.value.object.get("kind") orelse return error.InvalidReferenceExtraction;
                if (kind != .string) return error.InvalidReferenceExtraction;
                if (std.mem.eql(u8, kind.string, "claims")) {
                    const decoded = std.json.parseFromSliceLeaky(Claims, allocator, bytes, .{ .allocate = .alloc_always, .max_value_len = bytes.len }) catch |err| return mapError(err);
                    result.token_classifications = try classifications(allocator, decoded.token_classifications);
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
                    result.token_classifications = try classifications(allocator, decoded.token_classifications);
                    break :outcome .{ .no_feature_claim = decoded.reason };
                }
                return error.InvalidReferenceExtraction;
            },
        };
    }
    return .{ .entries = entries };
}
fn classifications(allocator: std.mem.Allocator, entries: []const std.json.Value) extraction.Error![]const extraction.tokens.Classification {
    const result = try allocator.alloc(extraction.tokens.Classification, entries.len);
    for (entries, result) |entry, *value| {
        if (entry != .object) return error.InvalidReferenceExtraction;
        const decision = entry.object.get("decision") orelse return error.InvalidReferenceExtraction;
        if (decision != .string) return error.InvalidReferenceExtraction;
        if (std.mem.eql(u8, decision.string, "preserve")) {
            const Shape = struct { decision: enum { preserve }, token_candidate_id: extraction.tokens.CandidateId, kind: extraction.tokens.Kind };
            const decoded = std.json.parseFromValueLeaky(Shape, allocator, entry, .{ .allocate = .alloc_always }) catch |err| return mapError(err);
            value.* = .{ .preserve = .{ .token_candidate_id = decoded.token_candidate_id, .kind = decoded.kind } };
        } else if (std.mem.eql(u8, decision.string, "irrelevant")) {
            const Shape = struct { decision: enum { irrelevant }, token_candidate_id: extraction.tokens.CandidateId };
            const decoded = std.json.parseFromValueLeaky(Shape, allocator, entry, .{ .allocate = .alloc_always }) catch |err| return mapError(err);
            value.* = .{ .irrelevant = decoded.token_candidate_id };
        } else return error.InvalidReferenceExtraction;
    }
    return result;
}
fn mapError(err: anyerror) extraction.Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceExtraction;
}
