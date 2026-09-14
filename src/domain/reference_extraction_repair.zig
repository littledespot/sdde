//! Reference validators select the smallest replacement unit. Shared atomic
//! repair owns authorization/CAS; workflow graphs own repetition.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
const evidence = @import("reference_evidence.zig");
const validation = @import("token_classification_validation.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
const selections = @import("source_selections.zig");
pub const Target = union(enum) { token_classifications, citation: struct { claim_index: usize, citation_index: usize }, missing_citations: struct { claim_index: usize } };
pub const Replacement = union(enum) { classifications: struct { token_classifications: []const extraction.tokens.Classification }, citation: selections.Selection, citations: struct { citations: []const selections.Selection } };
pub const Rule = union(enum) { token_classifications: struct { issues: validation.Issues, choices: validation.Choices }, source_selection: selections.Issue };
pub const Facts = @import("reference_extraction_context.zig").Facts;
const shared = @import("atomic_repair.zig");
const atomic = shared.Contract(Target, Replacement, Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = atomic.Error || extraction.Error;

pub const Rejection = union(enum) { token_classifications: validation.Rejection, source_selections: @import("reference_selection_validation.zig").Rejection };

pub fn authorize(a: std.mem.Allocator, facts: Facts, rejection: Rejection) Error!Authorization {
    const current = facts.candidate;
    const stamp = switch (rejection) {
        inline else => |value| value.dependencies orelse return error.InvalidAtomicRepair,
    };
    if (!std.meta.eql(stamp, try @import("reference_extraction_context.zig").snapshot(a, facts))) return error.InvalidAtomicRepair;
    switch (rejection) {
        .token_classifications => |diagnostic| {
            const entry = try entryAt(current, diagnostic.scope);
            if (current.revision != diagnostic.revision or !std.meta.eql(entry.classification_origin, diagnostic.origin) or !try atomic.equal(a, .{ .classifications = .{ .token_classifications = entry.token_classifications } }, .{ .classifications = .{ .token_classifications = diagnostic.observed } })) return error.InvalidAtomicRepair;
            return atomic.authorize(a, unit(diagnostic.scope), current.revision, .token_classifications, try select(current, diagnostic.scope, .token_classifications), facts, .{ .token_classifications = .{ .issues = diagnostic.issues, .choices = diagnostic.choices } });
        },
        .source_selections => |diagnostic| {
            const claim = try claimAt(current, diagnostic.scope, diagnostic.claim_index);
            if (current.revision != diagnostic.revision or !std.meta.eql(try claim.rejectionOrigin(diagnostic.issue), diagnostic.origin) or !try atomic.equal(a, .{ .citations = .{ .citations = claim.citations } }, .{ .citations = .{ .citations = diagnostic.observed } })) return error.InvalidAtomicRepair;
            const target: Target = if (diagnostic.issue.reason == .missing_selection) .{ .missing_citations = .{ .claim_index = diagnostic.claim_index } } else .{ .citation = .{ .claim_index = diagnostic.claim_index, .citation_index = diagnostic.issue.index } };
            return atomic.authorize(a, unit(diagnostic.scope), current.revision, target, try select(current, diagnostic.scope, target), facts, .{ .source_selection = diagnostic.issue });
        },
    }
}
pub fn packet(a: std.mem.Allocator, inputs: evidence.Inputs, literals: @import("passive_literals.zig").Registry, candidates: extraction.tokens.Candidates, current: extraction.TextValidated, authorization: Authorization) Error!*packets.Packet {
    const scope = try scopeOf(authorization);
    try atomic.checkDependencies(a, authorization, .{ .inputs = inputs, .candidates = candidates, .candidate = current });
    if (current.revision != authorization.revision) return error.InvalidAtomicRepair;
    _ = try select(current, scope, authorization.target);
    const base = try @import("reference_model_input.zig").extractionPacket(a, inputs, literals, candidates, scope);
    defer packets.release(base);
    if (authorization.target == .token_classifications) return atomic.packet(a, authorization, base, .{ .bytes = "classification_replacement" });
    // Citation repair needs the unchanged claim's meaning as well as source
    // choices. This is a projection of the retained candidate, not new authority.
    const claim = try claimAt(current, scope, claimIndex(authorization.target));
    const content = @import("model_evidence.zig").modelContent(claim.content);
    const contextual = try packets.withContext(@TypeOf(content), a, base, "claim", content);
    defer packets.release(contextual);
    return atomic.packet(a, authorization, contextual, .{ .bytes = if (authorization.target == .citation) "source_selection_replacement" else "citation_replacement" });
}

pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(a, authorization, input, bytes);
}

pub fn merge(a: std.mem.Allocator, facts: Facts, authorization: Authorization, proposed_replacement: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!extraction.TextValidated {
    const replacement = try atomic.copyReplacement(a, proposed_replacement);
    const current = facts.candidate;
    const scope = try scopeOf(authorization);
    const merged = try atomic.checkMerge(a, unit(scope), current.revision, try select(current, scope, authorization.target), facts, authorization, replacement, origin);
    const entries = try a.dupe(extraction.TextValidatedResult, current.entries);
    for (entries) |*entry| if (entry.scope.chunk_id.eql(scope.chunk_id)) {
        switch (authorization.target) {
            .token_classifications => {
                entry.token_classifications = try a.dupe(extraction.tokens.Classification, replacement.classifications.token_classifications);
                entry.classification_origin = origin;
            },
            .citation, .missing_citations => {
                const index = claimIndex(authorization.target);
                const claims = try a.dupe(extraction.TextValidatedProposal, entry.outcome.claims);
                claims[index].citations = switch (authorization.target) {
                    .citation => |target| citations: {
                        const copied = try a.dupe(selections.Selection, claims[index].citations);
                        copied[target.citation_index] = replacement.citation;
                        const origins = try a.dupe(?@import("model_candidate_origin.zig").Origin, claims[index].citation_origins);
                        origins[target.citation_index] = origin;
                        claims[index].citation_origins = origins;
                        break :citations copied;
                    },
                    .missing_citations => citations: {
                        const origins = try a.alloc(?@import("model_candidate_origin.zig").Origin, replacement.citations.citations.len);
                        @memset(origins, origin);
                        claims[index].citation_origins = origins;
                        claims[index].origin = origin;
                        break :citations try a.dupe(selections.Selection, replacement.citations.citations);
                    },
                    .token_classifications => unreachable,
                };
                entry.outcome = .{ .claims = claims };
            },
        }
    };
    return .{ .revision = merged.revision_after, .last_repair = merged, .entries = entries };
}

fn unit(scope: evidence.Scope) identity.ImmutableUnitOwnerId {
    return .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = scope.state_id.bytes }, .chunk_id = .{ .bytes = scope.chunk_id.bytes } } };
}
fn scopeOf(authorization: Authorization) Error!evidence.Scope {
    if (authorization.owner != .reference_chunk) return error.InvalidAtomicRepair;
    return .{ .state_id = .{ .bytes = authorization.owner.reference_chunk.reference_state_id.bytes }, .chunk_id = .{ .bytes = authorization.owner.reference_chunk.chunk_id.bytes } };
}
fn entryAt(current: extraction.TextValidated, scope: evidence.Scope) Error!extraction.TextValidatedResult {
    var result: ?extraction.TextValidatedResult = null;
    for (current.entries) |entry| {
        if (!entry.scope.state_id.eql(scope.state_id)) return error.InvalidAtomicRepair;
        if (!entry.scope.chunk_id.eql(scope.chunk_id)) continue;
        if (result != null or entry.outcome == .blocked) return error.InvalidAtomicRepair;
        result = entry;
    }
    return result orelse error.InvalidAtomicRepair;
}
fn claimAt(current: extraction.TextValidated, scope: evidence.Scope, index: usize) Error!extraction.TextValidatedProposal {
    const entry = try entryAt(current, scope);
    if (entry.outcome != .claims or index >= entry.outcome.claims.len) return error.InvalidAtomicRepair;
    return entry.outcome.claims[index];
}
fn claimIndex(target: Target) usize {
    return switch (target) {
        .citation => |value| value.claim_index,
        .missing_citations => |value| value.claim_index,
        .token_classifications => unreachable,
    };
}
fn select(current: extraction.TextValidated, scope: evidence.Scope, target: Target) Error!Replacement {
    if (target == .token_classifications) return .{ .classifications = .{ .token_classifications = (try entryAt(current, scope)).token_classifications } };
    const claim = try claimAt(current, scope, claimIndex(target));
    if (claim.citations.len != claim.citation_origins.len) return error.InvalidAtomicRepair;
    return switch (target) {
        .citation => |value| if (value.citation_index < claim.citations.len) .{ .citation = claim.citations[value.citation_index] } else error.InvalidAtomicRepair,
        .missing_citations => if (claim.citations.len == 0) .{ .citations = .{ .citations = claim.citations } } else error.InvalidAtomicRepair,
        .token_classifications => unreachable,
    };
}
