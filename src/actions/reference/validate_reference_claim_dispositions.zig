const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const r = @import("../../domain/reference_reconciliation.zig");
const v = @import("../../domain/reference_reconciliation_validation.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "validate-reference-claim-dispositions", .kind = .action, .requires = &.{.parsed_reference_reconciliation}, .produces = &.{.validated_reference_dispositions}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, parsed: r.Parsed) r.Error!r.CheckedDispositions {
        if (parsed.input.purpose != .global or parsed.proposal != .global or parsed.input.partition.group.level != .global) return error.InvalidReferenceReconciliation;
        try v.history(allocator, parsed.input.progress);
        const items = parsed.input.progress.plan.layout.items;
        const supplied = parsed.proposal.global.claim_dispositions;
        if (supplied.len != items.entries.len) return error.InvalidReferenceReconciliation;
        const dispositions = try allocator.alloc(r.ClaimDisposition, supplied.len);
        const seen = try allocator.alloc(bool, supplied.len);
        @memset(seen, false);
        for (supplied) |value| {
            const original = try r.item(items, value.claim_id);
            const index = value.claim_id.ordinal - 1;
            if (seen[index]) return error.InvalidReferenceReconciliation;
            seen[index] = true;
            try r.unique(r.ClaimId, value.related_claim_ids);
            for (value.related_claim_ids) |related| {
                const target = try r.item(items, related);
                if (related.ordinal == value.claim_id.ordinal) return error.InvalidReferenceReconciliation;
                if (value.disposition == .duplicate or value.disposition == .superseded) {
                    if (std.meta.activeTag(original.claim.content) != std.meta.activeTag(target.claim.content)) return error.InvalidReferenceReconciliation;
                    switch (original.claim.content) {
                        .model => |model| if (std.meta.activeTag(model) != std.meta.activeTag(target.claim.content.model)) return error.InvalidReferenceReconciliation,
                        .preserved_token => |token| if (value.disposition == .duplicate and
                            (token.value.kind != target.claim.content.preserved_token.value.kind or !std.mem.eql(u8, token.value.raw_value.bytes, target.claim.content.preserved_token.value.raw_value.bytes))) return error.InvalidReferenceReconciliation,
                    }
                }
            }
            switch (value.disposition) {
                .retained => if (value.related_claim_ids.len != 0) return error.InvalidReferenceReconciliation,
                .duplicate => if (value.related_claim_ids.len != 1) return error.InvalidReferenceReconciliation,
                .superseded, .conflicting => if (value.related_claim_ids.len == 0) return error.InvalidReferenceReconciliation,
            }
            dispositions[index] = value;
        }
        // Relationships terminate at retained originals, never a chain/cycle
        // that could hide an unresolved claim behind another disposition.
        for (dispositions) |value| for (value.related_claim_ids) |id| {
            const target = dispositions[id.ordinal - 1];
            switch (value.disposition) {
                .retained => unreachable,
                .duplicate, .superseded => if (target.disposition != .retained) return error.InvalidReferenceReconciliation,
                .conflicting => if (target.disposition != .conflicting or !r.contains(r.ClaimId, target.related_claim_ids, value.claim_id)) return error.InvalidReferenceReconciliation,
            }
        };
        return .{ .input = parsed.input, .proposal = parsed.proposal.global, .dispositions = dispositions };
    }
};
