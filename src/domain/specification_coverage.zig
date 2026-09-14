//! Total mechanical claim/token accounting; semantic relevance remains reviewed.
const std = @import("std");
const spec = @import("specification.zig");
const g = @import("specification_generation.zig");
const r = @import("reference_reconciliation.zig");
pub const Key = union(enum) { title, description, primary_goal, primary_user_story, entities, record: spec.Id };
pub const Account = struct {
    claim_id: r.ClaimId,
    disposition: union(enum) { mapped: []const Key, context_only: []const r.SignalId },
};
pub const Obligation = struct { token_id: r.extraction.tokens.Id, citation_id: r.CitationId, exact_targets: []const Key, context_signals: []const r.SignalId };
pub const Coverage = struct { accounts: []const Account, obligations: []const Obligation };
pub const Error = std.mem.Allocator.Error || error{InvalidSpecificationCoverage};

pub const Issue = union(enum) {
    open_question_mapped,
    missing_business_mapping,
    missing_context_mapping,
    missing_exact_copy: r.extraction.tokens.Token,
};
pub const Rejection = struct {
    claim_id: r.ClaimId,
    issue: Issue,
    targets: []const Key,
    revision: u64 = 0,
    origin: ?@import("model_candidate_origin.zig").Origin = null,
    dependencies: ?@import("atomic_repair.zig").Snapshot = null,
    blocked: ?enum { no_independent_supported_target } = null,
};
pub const Result = union(enum) { valid: Coverage, invalid: Rejection };
pub fn validate(a: std.mem.Allocator, references: r.Accounted, brief: g.Brief, candidate: spec.IdentifiedContent) Error!Coverage {
    return switch (try check(a, references, brief, candidate)) {
        .valid => |value| value,
        .invalid => error.InvalidSpecificationCoverage,
    };
}
pub fn check(allocator: std.mem.Allocator, references: r.Accounted, brief: g.Brief, candidate: spec.IdentifiedContent) Error!Result {
    const items = references.records.assignments.checked.prior.prior.input.progress.plan.layout.items;
    if (references.outcome != .complete) return error.InvalidSpecificationCoverage;
    var accounts: std.ArrayList(Account) = .empty;
    var obligations: std.ArrayList(Obligation) = .empty;
    for (references.records.assignments.checked.prior.prior.dispositions) |disposition| {
        if (!@import("specification_provenance.zig").eligibleClaim(disposition.disposition)) continue;
        const item = r.item(items, disposition.claim_id) catch return error.InvalidSpecificationCoverage;
        var targets: std.ArrayList(Key) = .empty;
        const singletons = [_]struct { key: Key, value: spec.AttributedValue }{
            .{ .key = .title, .value = brief.title },                 .{ .key = .description, .value = brief.description },
            .{ .key = .primary_goal, .value = brief.primary_goal },   .{ .key = .primary_user_story, .value = candidate.primary_user_story },
            .{ .key = .entities, .value = candidate.entities.basis },
        };
        for (singletons) |entry| if (r.contains(r.ClaimId, entry.value.provenance.claim_ids, item.claim.id)) try targets.append(allocator, entry.key);
        for (candidate.records) |record| if (r.contains(r.ClaimId, record.proposal.provenance.claim_ids, item.claim.id)) try targets.append(allocator, .{ .record = record.id });
        var signals: std.ArrayList(r.SignalId) = .empty;
        for (references.records.signals) |signal| if (r.contains(r.ClaimId, signal.value.claim_ids, item.claim.id)) try signals.append(allocator, signal.id);
        const context_only = switch (item.claim.content) {
            .model => |model| switch (model) {
                .business, .scope_guard => false,
                .design, .technical, .validation, .implementation_assumption, .open_question => true,
            },
            .preserved_token => |token| token.value.kind != .business_exact_string,
        };
        if (item.claim.content == .model and item.claim.content.model == .open_question and targets.items.len != 0) return .{ .invalid = .{ .claim_id = item.claim.id, .issue = .open_question_mapped, .targets = targets.items } };
        if (targets.items.len == 0 and (!context_only or signals.items.len == 0)) return .{ .invalid = .{ .claim_id = item.claim.id, .issue = if (context_only) .missing_context_mapping else .missing_business_mapping, .targets = targets.items } };
        try accounts.append(allocator, .{ .claim_id = item.claim.id, .disposition = if (targets.items.len != 0) .{ .mapped = targets.items } else .{ .context_only = signals.items } });
        if (item.claim.content == .preserved_token) {
            const token = item.claim.content.preserved_token;
            var exact: std.ArrayList(Key) = .empty;
            for (singletons) |entry| if (copies(entry.value.value, token)) try exact.append(allocator, entry.key);
            for (candidate.records) |record| if (recordCopies(record.proposal.content, token)) try exact.append(allocator, .{ .record = record.id });
            if (token.value.kind == .business_exact_string and exact.items.len == 0) return .{ .invalid = .{ .claim_id = item.claim.id, .issue = .{ .missing_exact_copy = token }, .targets = targets.items } };
            if (exact.items.len == 0 and signals.items.len == 0) return .{ .invalid = .{ .claim_id = item.claim.id, .issue = .missing_context_mapping, .targets = targets.items } };
            try obligations.append(allocator, .{ .token_id = token.value.id, .citation_id = token.citation_id, .exact_targets = exact.items, .context_signals = signals.items });
        }
    }
    return .{ .valid = .{ .accounts = accounts.items, .obligations = obligations.items } };
}
fn copies(value: spec.BusinessValue, token: r.extraction.tokens.Token) bool {
    return value == .exact_copy and value.exact_copy.token_id.ordinal == token.value.id.ordinal and value.exact_copy.citation_id.ordinal == token.citation_id.ordinal;
}
fn recordCopies(content: spec.Content(spec.BusinessValue), token: r.extraction.tokens.Token) bool {
    switch (content) {
        inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            const value = @field(fields, field.name);
            if (comptime field.type == spec.BusinessValue) {
                if (copies(value, token)) return true;
            } else for (value) |relationship| if (copies(relationship, token)) return true;
        },
    }
    return false;
}
