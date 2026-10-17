//! Exact eligibility and duties over the complete native equal-byte token group.
//! Semantic kinds remain on every original occurrence; a representative cannot
//! discard another occurrence's native or existing kind-specific exact duty.
const r = @import("reference_reconciliation.zig");
const native = @import("reference_token_disposition.zig");
const appearance = @import("exact_token_obligation.zig");

pub const Policy = struct {
    representative: r.ClaimId,
    recognizable: bool,
    mandatory: bool,
};

pub fn policy(items: r.Items, id: r.ClaimId) r.Error!Policy {
    var result: Policy = .{
        .representative = try native.representative(items, id),
        .recognizable = false,
        .mandatory = false,
    };
    for (items.entries) |item| {
        if (item.claim.content != .preserved_token or !try native.sameBytes(items, id, item.claim.id)) continue;
        const kind = item.claim.content.preserved_token.value.kind;
        const required = try appearance.itemRequired(items, item.claim.id);
        result.recognizable = result.recognizable or kind != .code_sample or required;
        result.mandatory = result.mandatory or kind == .business_exact_string or required;
    }
    return result;
}

/// Only one current handle represents equal bytes. Every original obligation
/// remains addressable separately through that native representative.
pub fn permits(items: r.Items, id: r.ClaimId) r.Error!bool {
    const result = try policy(items, id);
    return result.recognizable and result.representative.ordinal == id.ordinal;
}
