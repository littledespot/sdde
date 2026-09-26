//! Total mechanical claim/token accounting; semantic relevance remains reviewed.
const std = @import("std");
const spec = @import("specification.zig");
const g = @import("specification_generation.zig");
const r = @import("reference_reconciliation.zig");
const provenance = @import("specification_provenance.zig");
pub const Key = union(enum) { title, description, primary_goal, primary_user_story, entities, record: spec.Id };
pub const Account = struct {
    claim_id: r.ClaimId,
    disposition: union(enum) { mapped: []const Key, context_only: []const r.SignalId },
};
pub const Obligation = struct { claim_id: r.ClaimId, exact_targets: []const Key, context_signals: []const r.SignalId };
pub const Coverage = struct { accounts: []const Account, obligations: []const Obligation };
pub const TokenSubject = r.ClaimId;
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
    if (references.outcome != .complete) return error.InvalidSpecificationCoverage;
    return checkRecords(allocator, @import("reference_support.zig").records(references), brief, candidate);
}

pub fn checkRecords(allocator: std.mem.Allocator, references: @import("reference_support.zig").Records, brief: g.Brief, candidate: spec.IdentifiedContent) Error!Result {
    const items = references.items;
    var accounts: std.ArrayList(Account) = .empty;
    var obligations: std.ArrayList(Obligation) = .empty;
    for (references.dispositions) |disposition| {
        if (!@import("specification_provenance.zig").eligibleClaim(disposition.disposition)) continue;
        const item = r.item(items, disposition.claim_id) catch return error.InvalidSpecificationCoverage;
        var targets: std.ArrayList(Key) = .empty;
        for (singletons(brief, candidate)) |entry| {
            const claims = provenance.effectiveClaims(allocator, entry.value.provenance.claim_ids, &.{entry.value.value}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationCoverage;
            if (r.contains(r.ClaimId, claims, item.claim.id)) try targets.append(allocator, entry.key);
        }
        for (candidate.records) |record| {
            const values = provenance.recordValues(allocator, record.proposal.content) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationCoverage;
            const claims = provenance.effectiveClaims(allocator, record.proposal.provenance.claim_ids, values) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationCoverage;
            if (r.contains(r.ClaimId, claims, item.claim.id)) try targets.append(allocator, .{ .record = record.id });
        }
        var signals: std.ArrayList(r.SignalId) = .empty;
        for (references.signals) |signal| if (r.contains(r.ClaimId, signal.value.claim_ids, item.claim.id)) try signals.append(allocator, signal.id);
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
            const exact = try exactTargets(allocator, brief, candidate, item.claim.id);
            if (token.value.kind == .business_exact_string and exact.len == 0) return .{ .invalid = .{ .claim_id = item.claim.id, .issue = .{ .missing_exact_copy = token }, .targets = targets.items } };
            if (exact.len == 0 and signals.items.len == 0) return .{ .invalid = .{ .claim_id = item.claim.id, .issue = .missing_context_mapping, .targets = targets.items } };
            try obligations.append(allocator, .{ .claim_id = item.claim.id, .exact_targets = exact, .context_signals = signals.items });
        }
    }
    return .{ .valid = .{ .accounts = accounts.items, .obligations = obligations.items } };
}
const AttributedTarget = struct { key: Key, value: spec.AttributedValue };
fn singletons(brief: g.Brief, candidate: spec.IdentifiedContent) [5]AttributedTarget {
    return .{
        .{ .key = .title, .value = brief.title },                 .{ .key = .description, .value = brief.description },
        .{ .key = .primary_goal, .value = brief.primary_goal },   .{ .key = .primary_user_story, .value = candidate.primary_user_story },
        .{ .key = .entities, .value = candidate.entities.basis },
    };
}
pub fn exactTargets(a: std.mem.Allocator, brief: g.Brief, candidate: spec.IdentifiedContent, claim_id: r.ClaimId) Error![]const Key {
    var exact: std.ArrayList(Key) = .empty;
    for (singletons(brief, candidate)) |entry| if (copies(entry.value.value, claim_id)) try exact.append(a, entry.key);
    for (candidate.records) |record| if (recordCopies(record.proposal.content, claim_id)) try exact.append(a, .{ .record = record.id });
    return exact.toOwnedSlice(a);
}
fn copies(value: spec.BusinessValue, claim_id: r.ClaimId) bool {
    for (value.segments) |segment| if (segment == .exact_copy and segment.exact_copy.claim_id.ordinal == claim_id.ordinal) return true;
    return false;
}
fn recordCopies(content: spec.Content(spec.BusinessValue), claim_id: r.ClaimId) bool {
    switch (content) {
        inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            const value = @field(fields, field.name);
            if (comptime field.type == spec.BusinessValue) {
                if (copies(value, claim_id)) return true;
            } else for (value) |relationship| if (copies(relationship, claim_id)) return true;
        },
    }
    return false;
}
