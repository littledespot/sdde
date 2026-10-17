//! Native exact-value duty from original canonical business/scope literals.
//! Semantic token kinds and source association remain separate authority.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
const text = @import("typed_text.zig");
const reconciliation = @import("reference_reconciliation.zig");

/// Adjacent literal fragments form one byte run. Insertions are opaque: their
/// display values never complete a match or establish an exact-value duty.
/// No case, whitespace or Unicode normalization runs at this boundary.
pub fn containsLiteralBytes(value: text.BusinessText, bytes: []const u8) bool {
    if (bytes.len == 0) return false;
    for (value.segments, 0..) |node, node_index| {
        if (node != .literal) continue;
        for (node.literal.value, 0..) |byte, offset| {
            if (byte != bytes[0]) continue;
            var index = node_index;
            var at = offset;
            var matched: usize = 0;
            while (index < value.segments.len and value.segments[index] == .literal) : (index += 1) {
                const literal = value.segments[index].literal.value;
                const count = @min(literal.len - at, bytes.len - matched);
                if (!std.mem.eql(u8, literal[at .. at + count], bytes[matched .. matched + count])) break;
                matched += count;
                if (matched == bytes.len) return true;
                at = 0;
            }
        }
    }
    return false;
}

pub fn contentRequires(content: extraction.Content, bytes: []const u8) bool {
    return switch (content) {
        inline .business, .scope_guard => |value| containsLiteralBytes(value.value, bytes),
        .design, .technical, .validation, .implementation_assumption, .open_question => false,
    };
}

pub fn candidateRequired(entry: extraction.TextValidatedResult, candidate: extraction.tokens.Candidate) bool {
    if (!entry.scope.state_id.eql(candidate.fact.scope.state_id) or !entry.scope.chunk_id.eql(candidate.fact.scope.chunk_id) or entry.outcome != .claims) return false;
    const bytes = candidate.fact.citation.verbatim orelse return false;
    for (entry.outcome.claims) |claim| if (contentRequires(claim.content, bytes)) return true;
    return false;
}

fn requiredBy(original: extraction.Claim, token: extraction.Claim) bool {
    return token.content == .preserved_token and original.content == .model and
        original.chunk_id.eql(token.chunk_id) and contentRequires(original.content.model, token.content.preserved_token.value.raw_value.bytes);
}

pub fn claimRequired(original_claims: []const extraction.Claim, token: extraction.Claim) bool {
    for (original_claims) |original| if (requiredBy(original, token)) return true;
    return false;
}

pub fn itemRequired(items: reconciliation.Items, claim_id: reconciliation.ClaimId) reconciliation.Error!bool {
    const token = (try reconciliation.item(items, claim_id)).claim;
    for (items.entries) |original| if (requiredBy(original.claim, token)) return true;
    return false;
}
