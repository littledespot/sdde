//! Reconstructible native dataflow for one fixed omission; no semantic decisions.
const std = @import("std");
const loss = @import("source_omission.zig");
const comparison = loss.comparisons;
const r = @import("reference_reconciliation.zig");
const Records = @import("reference_support.zig").Records;
const authority = @import("required_authority.zig");
const bindings = @import("specification_source_binding.zig");
pub const ComparisonError = comparison.Error || bindings.Error;

/// Build immutable request evidence from canonical facts, never a consumed
/// generation cursor. All slices belong to/borrow the caller's request arena.
/// Production packet retention copies these facts before that arena is released.
pub fn build(a: std.mem.Allocator, inputs: authority.Inputs, source_inputs: r.evidence.Inputs, target: authority.Id, ordinal: u32, review_revision: u64, finding: authority.ReviewEvidence) ComparisonError!comparison.Assignment {
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    if (!@import("specification_support_evidence.zig").validObligation(.candidate_omission, finding.missing_obligation)) return error.InvalidRequiredAuthority;
    if (finding.source_ids.len == 0 or finding.detail.len == 0 or ordinal == 0 or review_revision == 0 or !records.items.state_id.eql(source_inputs.corpus.state_id)) return error.InvalidRequiredAuthority;
    try r.unique(r.extraction.identity.SourceId, finding.source_ids);
    var sources: std.ArrayList(loss.SourceLines) = .empty;
    for (try loss.sourceLines(a, source_inputs)) |source| {
        if (authority.contains(r.extraction.identity.SourceId, finding.source_ids, source.source_id)) try sources.append(a, source);
    }
    for (finding.source_ids) |id| {
        const present = for (sources.items) |source| {
            if (std.meta.eql(id, source.source_id)) break true;
        } else false;
        if (!present) return error.InvalidRequiredAuthority;
    }
    const purpose = try @import("required_authority_description.zig").task(a, target);
    var builder: ComparisonBuilder = .{ .allocator = a, .records = records, .purpose = purpose };
    var extracted: std.ArrayList(r.ClaimId) = .empty;
    for (records.items.entries) |item| {
        if (authority.contains(r.extraction.identity.SourceId, finding.source_ids, item.source_id)) try extracted.append(a, item.claim.id);
    }
    // Whole group membership is evidence. Include related claims before reducing
    // availability; a legitimate duplicate suppression may preserve joint meaning.
    var changed = true;
    while (changed) {
        changed = false;
        for (records.dispositions) |disposition| {
            if (!r.contains(r.ClaimId, extracted.items, disposition.claim_id)) continue;
            for (disposition.related_claim_ids) |id| if (!r.contains(r.ClaimId, extracted.items, id)) {
                try extracted.append(a, id);
                changed = true;
            };
        }
        for (records.signals) |signal| {
            const related = for (signal.value.claim_ids) |id| {
                if (r.contains(r.ClaimId, extracted.items, id)) break true;
            } else false;
            if (!related) continue;
            for (signal.value.claim_ids) |id| if (!r.contains(r.ClaimId, extracted.items, id)) {
                try extracted.append(a, id);
                changed = true;
            };
        }
        for (records.conflicts) |conflict| {
            const related = for (conflict.value.claim_ids) |id| {
                if (r.contains(r.ClaimId, extracted.items, id)) break true;
            } else false;
            if (!related) continue;
            for (conflict.value.claim_ids) |id| if (!r.contains(r.ClaimId, extracted.items, id)) {
                try extracted.append(a, id);
                changed = true;
            };
        }
    }
    const single_chunk = sources.items.len == 1 and for (extracted.items) |id| {
        if (!(try r.item(records.items, id)).claim.chunk_id.eql(sources.items[0].chunk_id)) break false;
    } else true;
    // A claims collection also reflects separately owned exact-token decisions.
    // Its loss cannot distinguish a claim defect from classification loss. Do
    // not turn that composite output into an arbitrary chunk-insertion target.
    const classification_present = for (records.items.extraction) |chunk| {
        const selected = for (sources.items) |source| {
            if (source.chunk_id.eql(chunk.scope.chunk_id)) break true;
        } else false;
        if (selected and chunk.outcome == .claims and chunk.token_classifications.len != 0) break true;
    } else false;
    const extraction_owner: ?comparison.Owner = if (single_chunk and !classification_present) .{ .existing = .{ .extraction_claim = sources.items[0].chunk_id } } else null;
    try builder.append(extracted.items, extraction_owner);
    var retained: std.ArrayList(r.ClaimId) = .empty;
    var rejected: std.ArrayList(r.ClaimId) = .empty;
    for (extracted.items) |id| {
        if (try @import("reference_support.zig").eligibleSelection(records.dispositions, &.{id})) try retained.append(a, id) else try rejected.append(a, id);
    }
    try builder.append(retained.items, if (rejected.items.len == 1) .{ .existing = .{ .reconciliation_disposition = rejected.items[0] } } else null);
    var target_owner: ?comparison.Owner = null;
    switch (target.unit) {
        .feature => {
            const role: r.GenerationRole = switch (target.slot) {
                .display_name => .title,
                .description => .description,
                .primary_goal => .primary_goal,
                .primary_user_story => .primary_user_story,
                .entities => .entity_basis,
                .acceptance_criteria, .functional_requirements, .scenario_coverage => .records,
                else => return error.InvalidRequiredAuthority,
            };
            try builder.append(try bindings.roleClaimIds(a, records, role), .{ .role_assignment = role });
            if (inputs.brief != null or inputs.specification != null) target_owner = .{ .existing = .{ .candidate = .{} } };
        },
        .record => {
            const selected = try @import("specification_authority.zig").recordField(inputs, target) orelse return error.InvalidRequiredAuthority;
            const bound = try bindings.recordForClaims(a, records, source_inputs, selected.record.proposal.provenance.claim_ids);
            try builder.append(bound.records.selection.claim_ids, .{ .role_assignment = .records });
            target_owner = .{ .existing = .{ .candidate = .{} } };
        },
        .signal => |id| {
            const signal = for (records.signals) |item| {
                if (std.meta.eql(item.id, id)) break item;
            } else return error.InvalidRequiredAuthority;
            // Selection is native recorded membership. Supporting signal prose
            // never substitutes for the original claims in this input view.
            try builder.append(signal.value.claim_ids, null);
            target_owner = .{ .existing = .{ .reconciliation_signal = id } };
        },
        .conflict => |id| {
            const conflict = for (records.conflicts) |item| {
                if (std.meta.eql(item.id, id)) break item;
            } else return error.InvalidRequiredAuthority;
            try builder.append(conflict.value.claim_ids, null);
            target_owner = .{ .existing = .{ .reconciliation_conflict = id } };
        },
        // Source preservation is a joint collection obligation, not permission
        // to pick whichever chunk or classification happens to be repairable.
        .source, .token, .decision => {},
    }
    try builder.boundaries.append(a, .{ .input = builder.last, .output = .deficient_subject, .owner = target_owner });
    return .{
        .facts = .{ .feature = inputs.feature, .revision = inputs.revision, .sources = source_inputs, .records = records, .brief = inputs.brief, .candidate = inputs.specification },
        .finding = .{ .ordinal = ordinal, .revision = review_revision, .subject = target, .detail = finding.detail, .missing_obligation = finding.missing_obligation.?, .source_ids = finding.source_ids },
        .sources = sources.items,
        .comparisons = builder.views.items,
        .boundaries = builder.boundaries.items,
    };
}

const ComparisonBuilder = struct {
    allocator: std.mem.Allocator,
    records: Records,
    purpose: []const u8,
    last: comparison.Reference = .source_premise,
    views: std.ArrayList(comparison.View) = .empty,
    boundaries: std.ArrayList(comparison.Boundary) = .empty,

    fn append(self: *ComparisonBuilder, ids: []const r.ClaimId, owner: ?comparison.Owner) ComparisonError!void {
        try r.unique(r.ClaimId, ids);
        const members = try self.allocator.alloc(comparison.Member, ids.len);
        for (ids, members, 1..) |id, *member, ordinal| member.* = .{ .id = .{ .ordinal = @intCast(ordinal) }, .claim_id = (try r.item(self.records.items, id)).claim.id };
        // Only identical occurrences, values, purpose and current dependency
        // binding share a view. Equal text from different claims never merges.
        if (self.last == .comparison) {
            const previous = self.views.items[self.last.comparison.ordinal - 1];
            const before = try @import("atomic_repair.zig").snapshot([]const comparison.Member, self.allocator, previous.members);
            const after = try @import("atomic_repair.zig").snapshot([]const comparison.Member, self.allocator, members);
            if (std.mem.eql(u8, &before.bytes, &after.bytes)) return;
        }
        const id: comparison.Id = .{ .ordinal = @intCast(self.views.items.len + 1) };
        try self.views.append(self.allocator, .{ .id = id, .purpose = self.purpose, .members = members });
        try self.boundaries.append(self.allocator, .{ .input = self.last, .output = .{ .comparison = id }, .owner = owner });
        self.last = .{ .comparison = id };
    }
};
