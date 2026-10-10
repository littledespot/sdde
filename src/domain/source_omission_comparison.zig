//! Native-bound preservation evidence for one admitted omission. This owner
//! validates joins and derives attribution; it neither judges meaning nor grants
//! a repair permission. All consumers use the same admission and derivation.
const std = @import("std");
const loss = @import("source_omission.zig");
const r = @import("reference_reconciliation.zig");
const authority = @import("required_authority.zig");
const selections = @import("source_selections.zig");
const atomic = @import("atomic_repair.zig");
pub const Id = struct {
    pub const model_scalar = "ordinal";
    ordinal: u32,
};
pub const MemberId = struct {
    pub const model_scalar = "ordinal";
    ordinal: u32,
};
pub const Verdict = enum { preserved, lost, uncertain };
pub const Member = struct { id: MemberId, claim_id: r.ClaimId };
pub const View = struct { id: Id, purpose: []const u8, members: []const Member };
pub const Reference = union(enum) { source_premise, deficient_subject, comparison: Id };
pub const Owner = union(enum) {
    existing: loss.Location,
    role_assignment: r.GenerationRole,
    summary: r.SummaryId,
};
/// Consecutive boundaries share the exact same view, not merely claim IDs or
/// matching prose. A collection with several possible owners has no single owner.
pub const Boundary = struct { input: Reference, output: Reference, owner: ?Owner };
pub const Assignment = struct {
    facts: struct {
        feature: @import("feature_identity.zig").FeatureId,
        revision: u64,
        sources: r.evidence.Inputs,
        records: @import("reference_support.zig").Records,
        brief: ?@import("specification.zig").Brief,
        candidate: ?@import("specification.zig").IdentifiedContent,
    },
    finding: struct { ordinal: u32, revision: u64, subject: authority.Id, detail: []const u8, missing_obligation: []const u8, source_ids: []const r.extraction.identity.SourceId },
    sources: []const loss.SourceLines,
    comparisons: []const View,
    boundaries: []const Boundary,
};

pub const Span = struct { chunk_id: r.extraction.identity.ChunkId, lines: selections.Selection };
pub const Assessment = struct { comparison_id: Id, result: Verdict, sources: []const Span, members: []const MemberId, explanation: []const u8 };
pub const Response = struct { assessments: []const Assessment };
pub const Attribution = union(enum) { unresolved, established: Owner };
pub const Evidence = struct {
    assignment: Assignment,
    response: Response,
    origin: ?@import("model_candidate_origin.zig").Origin = null,
};
pub const Error = r.Error || authority.Error || @import("strict_json.zig").Error || error{InvalidPreservationComparison};

fn sameReference(left: Reference, right: Reference) bool {
    return std.meta.eql(left, right);
}

fn view(assignment: Assignment, id: Id) Error!View {
    if (id.ordinal == 0 or id.ordinal > assignment.comparisons.len) return error.InvalidPreservationComparison;
    const selected = assignment.comparisons[id.ordinal - 1];
    if (selected.id.ordinal != id.ordinal) return error.InvalidPreservationComparison;
    return selected;
}

fn result(assignment: Assignment, response: Response, reference: Reference) Error!Verdict {
    return switch (reference) {
        .source_premise => .preserved,
        .deficient_subject => .lost,
        .comparison => |id| blk: {
            _ = try view(assignment, id);
            for (response.assessments) |entry| if (entry.comparison_id.ordinal == id.ordinal) break :blk entry.result;
            return error.InvalidPreservationComparison;
        },
    };
}

/// Compare with a freshly reconstructed assignment before interpreting a reply.
/// Both assignments borrow their caller's arena. No response or verdict escapes
/// into authority without this complete admission, and no returned owner borrows
/// model response memory.
pub fn admit(a: std.mem.Allocator, retained: Assignment, current: Assignment, sources: r.evidence.Inputs, response: Response) Error!Attribution {
    const before = try atomic.snapshot(Assignment, a, retained);
    const now = try atomic.snapshot(Assignment, a, current);
    if (!std.mem.eql(u8, &before.bytes, &now.bytes)) return error.InvalidPreservationComparison;
    if (current.finding.ordinal == 0 or current.finding.source_ids.len == 0 or std.mem.trim(u8, current.finding.detail, " \r\n\t").len == 0) return error.InvalidPreservationComparison;
    if (!@import("specification_support_evidence.zig").validObligation(.candidate_omission, current.finding.missing_obligation)) return error.InvalidPreservationComparison;
    if (response.assessments.len != current.comparisons.len) return error.InvalidPreservationComparison;
    for (current.comparisons, 1..) |assigned, ordinal| {
        if (assigned.id.ordinal != ordinal or assigned.purpose.len == 0) return error.InvalidPreservationComparison;
        for (assigned.members, 1..) |member, index| if (member.id.ordinal != index) return error.InvalidPreservationComparison;
    }
    for (response.assessments, 0..) |entry, index| {
        const assigned = try view(current, entry.comparison_id);
        for (response.assessments[0..index]) |prior| if (prior.comparison_id.ordinal == entry.comparison_id.ordinal) return error.InvalidPreservationComparison;
        if (std.mem.trim(u8, entry.explanation, " \r\n\t").len == 0 or entry.sources.len == 0) return error.InvalidPreservationComparison;
        if ((assigned.members.len == 0 and entry.members.len != 0) or (assigned.members.len != 0 and entry.members.len == 0)) return error.InvalidPreservationComparison;
        if (entry.result == .preserved and assigned.members.len == 0) return error.InvalidPreservationComparison;
        for (entry.members, 0..) |member, at| {
            if (member.ordinal == 0 or member.ordinal > assigned.members.len) return error.InvalidPreservationComparison;
            for (entry.members[0..at]) |prior| if (prior.ordinal == member.ordinal) return error.InvalidPreservationComparison;
        }
        for (entry.sources) |span| {
            const offered = for (current.sources) |source| {
                if (source.chunk_id.eql(span.chunk_id)) break source;
            } else return error.InvalidPreservationComparison;
            if (!authority.contains(r.extraction.identity.SourceId, current.finding.source_ids, offered.source_id)) return error.InvalidPreservationComparison;
            const resolved = try r.evidence.resolve(sources, .{ .state_id = sources.corpus.state_id, .chunk_id = span.chunk_id });
            if (!std.meta.eql(resolved.source.id, offered.source_id)) return error.InvalidPreservationComparison;
            switch (try selections.validate(a, sources, .{ .state_id = sources.corpus.state_id, .chunk_id = span.chunk_id }, &.{span.lines})) {
                .invalid => return error.InvalidPreservationComparison,
                .valid => |valid| a.free(valid.entries),
            }
        }
    }
    if (current.comparisons.len == 0 or current.boundaries.len == 0) return .unresolved;
    // This is a domain-bound chain of actual supplied collections, not a generic
    // dependency graph or a search for any repairable producer.
    for (current.boundaries, 0..) |boundary, index| {
        if (boundary.input == .deficient_subject or boundary.output == .source_premise or sameReference(boundary.input, boundary.output)) return error.InvalidPreservationComparison;
        if (index == 0) {
            if (boundary.input != .source_premise) return error.InvalidPreservationComparison;
        } else if (!sameReference(current.boundaries[index - 1].output, boundary.input)) return error.InvalidPreservationComparison;
        if (boundary.output == .deficient_subject and index + 1 != current.boundaries.len) return error.InvalidPreservationComparison;
        if (boundary.owner) |owner| if (owner == .existing and owner.existing == .unlocalized) return error.InvalidPreservationComparison;
        _ = try result(current, response, boundary.input);
        _ = try result(current, response, boundary.output);
    }
    if (current.boundaries[current.boundaries.len - 1].output != .deficient_subject) return error.InvalidPreservationComparison;
    var cursor = current.boundaries.len;
    while (cursor != 0) {
        cursor -= 1;
        const boundary = current.boundaries[cursor];
        if (try result(current, response, boundary.output) != .lost) return .unresolved;
        switch (try result(current, response, boundary.input)) {
            .preserved => return if (boundary.owner) |owner| .{ .established = owner } else .unresolved,
            .uncertain => return .unresolved,
            .lost => {},
        }
    }
    return .unresolved;
}

/// Stored evidence is compared with fresh canonical facts and native dataflow.
/// No request log or persisted digest acts as authority.
pub fn validate(a: std.mem.Allocator, inputs: authority.Inputs, sources: r.evidence.Inputs, target: authority.Id, review: authority.ReviewEvidence, evidence: Evidence) Error!Attribution {
    const fixed = evidence.assignment.finding;
    if (!std.meta.eql(fixed.subject, target) or fixed.revision == 0) return error.InvalidPreservationComparison;
    const ledger = try authority.build(a, inputs);
    if (fixed.ordinal == 0 or fixed.ordinal > ledger.requirements.len or !std.meta.eql(ledger.requirements[fixed.ordinal - 1].seed.id, target)) return error.InvalidPreservationComparison;
    const current = @import("source_omission_binding.zig").build(a, inputs, sources, target, fixed.ordinal, fixed.revision, review) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidPreservationComparison;
    return admit(a, evidence.assignment, current, sources, evidence.response);
}

pub fn location(attribution: Attribution) loss.Location {
    return switch (attribution) {
        .unresolved => .{ .unlocalized = .{} },
        .established => |owner| switch (owner) {
            .existing => |value| value,
            .role_assignment => |role| .{ .unsupported_role = role },
            .summary => |id| .{ .unsupported_summary = id },
        },
    };
}
