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
pub const Rule = union(enum) { token_classifications: validation.Issues, source_selection: selections.Issue };
const atomic = @import("atomic_repair.zig").Contract(Target, Replacement, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = atomic.Error || extraction.Error;

pub fn authorize(a: std.mem.Allocator, inputs: evidence.Inputs, candidates: extraction.tokens.Candidates, current: extraction.TextValidated) Error!Authorization {
    const checked = try @import("reference_selection_validation.zig").validate(a, inputs, candidates, current);
    if (checked == .token_classifications) {
        const diagnostic = checked.token_classifications;
        return atomic.authorize(a, unit(diagnostic.scope), current.revision, .token_classifications, try select(current, diagnostic.scope, .token_classifications), .{ .token_classifications = diagnostic.issues });
    }
    if (checked != .source_selections) return error.InvalidAtomicRepair;
    const diagnostic = checked.source_selections;
    const target: Target = if (diagnostic.issue.reason == .missing_selection) .{ .missing_citations = .{ .claim_index = diagnostic.claim_index } } else .{ .citation = .{ .claim_index = diagnostic.claim_index, .citation_index = diagnostic.issue.index } };
    return atomic.authorize(a, unit(diagnostic.scope), current.revision, target, try select(current, diagnostic.scope, target), .{ .source_selection = diagnostic.issue });
}

pub fn packet(a: std.mem.Allocator, inputs: evidence.Inputs, literals: @import("passive_literals.zig").Registry, candidates: extraction.tokens.Candidates, current: extraction.TextValidated, authorization: Authorization) Error!*packets.Packet {
    const scope = try scopeOf(authorization);
    if (current.revision != authorization.revision) return error.InvalidAtomicRepair;
    _ = try select(current, scope, authorization.target);
    const base = try @import("reference_model_input.zig").extractionPacket(a, inputs, literals, candidates, scope);
    defer packets.release(base);
    if (authorization.target == .token_classifications) return atomic.packet(a, authorization, base, .{ .bytes = "classification_replacement" });
    // Citation repair needs the unchanged claim's meaning as well as source
    // choices. This is a projection of the retained candidate, not new authority.
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    var input = try @import("strict_json.zig").decode(std.json.Value, scratch, base.body(), .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth });
    const claim = try claimAt(current, scope, claimIndex(authorization.target));
    const content = @import("model_evidence.zig").modelContent(claim.content);
    const encoded = try @import("model_candidate_json.zig").encode(@TypeOf(content), scratch, content);
    try input.object.put(scratch, "claim", try @import("strict_json.zig").decode(std.json.Value, scratch, encoded, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }));
    const contextual = try packets.create(a, try std.json.Stringify.valueAlloc(scratch, input, .{}), base.unit(), base.purpose(), null);
    defer packets.release(contextual);
    return atomic.packet(a, authorization, contextual, .{ .bytes = if (authorization.target == .citation) "source_selection_replacement" else "citation_replacement" });
}

pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(a, authorization, input, bytes);
}

pub fn merge(a: std.mem.Allocator, current: extraction.TextValidated, authorization: Authorization, replacement: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!extraction.TextValidated {
    const scope = try scopeOf(authorization);
    const revision = try atomic.checkMerge(a, unit(scope), current.revision, try select(current, scope, authorization.target), authorization, replacement);
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
    return .{ .revision = revision, .entries = entries };
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
