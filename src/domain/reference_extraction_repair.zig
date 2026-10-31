//! Reference validators select the smallest replacement unit. Shared atomic
//! repair owns authorization/CAS; workflow graphs own repetition.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
const evidence = @import("reference_evidence.zig");
const validation = @import("token_classification_validation.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
pub const Target = union(enum) { token_classifications };
pub const Replacement = union(enum) { classifications: struct { token_classifications: []const extraction.tokens.Classification } };
pub const Rule = union(enum) { token_classifications: struct { issues: validation.Issues, choices: validation.Choices } };
pub const Facts = @import("reference_extraction_context.zig").Facts;
const shared = @import("atomic_repair.zig");
const atomic = shared.Contract(Target, Replacement, Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = atomic.Error || extraction.Error;
const Family = enum { classifications };

/// Claims cite admitted source lines (ADR 0036), so a chunk's classification
/// collection is its only native repair target.
pub fn retryPermit(a: std.mem.Allocator, authorization: Authorization) Error!@import("workflow_retry.zig").Permit {
    const candidate = authorization.dependencies.candidate;
    const entry = try entryAt(candidate, try scopeOf(authorization));
    var permit = try shared.permit(Target, Family, a, authorization.owner, authorization.target, .classifications, authorization.id, authorization.revision, 1);
    const scope = .{ .boundary = permit.key.scope, .origin = entry.origin };
    permit.key.scope = (try shared.snapshot(@TypeOf(scope), a, scope)).bytes;
    if (candidate.last_repair) |prior| if (prior.retry) |previous| if (std.mem.eql(u8, &previous.key.scope, &permit.key.scope)) {
        permit.maximum_targets = previous.maximum_targets;
    };
    return permit;
}

pub const Rejection = union(enum) { token_classifications: validation.Rejection };

pub fn authorize(a: std.mem.Allocator, facts: Facts, rejection: Rejection) Error!Authorization {
    const current = facts.candidate;
    const diagnostic = rejection.token_classifications;
    const stamp = diagnostic.dependencies orelse return error.InvalidAtomicRepair;
    if (!std.meta.eql(stamp, try @import("reference_extraction_context.zig").snapshot(a, facts))) return error.InvalidAtomicRepair;
    const entry = try entryAt(current, diagnostic.scope);
    if (current.revision != diagnostic.revision or !std.meta.eql(try validation.rejectionOrigin(entry, diagnostic.issues), diagnostic.origin) or !try atomic.equal(a, .{ .classifications = .{ .token_classifications = entry.token_classifications } }, .{ .classifications = .{ .token_classifications = diagnostic.observed } })) return error.InvalidAtomicRepair;
    var result = try atomic.authorize(a, unit(diagnostic.scope), current.revision, .token_classifications, try select(current, diagnostic.scope), facts, .{ .token_classifications = .{ .issues = diagnostic.issues, .choices = diagnostic.choices } });
    result.retry = try retryPermit(a, result);
    return result;
}
pub fn packet(a: std.mem.Allocator, inputs: evidence.Inputs, literals: @import("passive_literals.zig").Registry, candidates: extraction.tokens.Candidates, current: extraction.TextValidated, authorization: Authorization) Error!*packets.Packet {
    const scope = try scopeOf(authorization);
    try atomic.checkDependencies(a, authorization, .{ .inputs = inputs, .candidates = candidates, .candidate = current });
    if (current.revision != authorization.revision) return error.InvalidAtomicRepair;
    _ = try select(current, scope);
    const base = try @import("reference_model_input.zig").extractionBase(a, inputs, literals, candidates, scope);
    defer packets.release(base);
    const entry = try entryAt(current, scope);
    const rejected_origin = try validation.rejectionOrigin(entry, authorization.rule.token_classifications.issues);
    const producing_origin = if (entry.producers) |producers| producers.classifications else entry.origin;
    return atomic.packet(a, authorization, base, .{ .bytes = "classification_replacement" }, rejected_origin orelse producing_origin, .{ .fields = .{ .replacement = .{ .reference_phase = .extraction } } });
}

pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(a, authorization, input, bytes);
}

pub fn merge(a: std.mem.Allocator, canonical: @import("typed_text.zig").CanonicalText, facts: Facts, authorization: Authorization, proposed_replacement: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!extraction.TextValidated {
    if (!canonical.matchesInputs(facts.inputs)) return error.InvalidAtomicRepair;
    const replacement = try atomic.copyReplacement(a, proposed_replacement);
    const current = facts.candidate;
    const scope = try scopeOf(authorization);
    const merged = try atomic.checkMerge(a, canonical, unit(scope), current.revision, try select(current, scope), facts, authorization, replacement, origin);
    const entries = try a.dupe(extraction.TextValidatedResult, current.entries);
    for (entries) |*entry| if (entry.scope.chunk_id.eql(scope.chunk_id)) {
        entry.token_classifications = try a.dupe(extraction.tokens.Classification, replacement.classifications.token_classifications);
        const origins = try a.alloc(?@import("model_candidate_origin.zig").Origin, entry.token_classifications.len);
        @memset(origins, origin);
        entry.classification_origins = origins;
        if (entry.producers) |*producers| producers.classifications = origin;
    };
    var result = current;
    result.revision = merged.revision_after;
    result.last_repair = merged;
    result.pending_repair = if (authorization.retry) |permit| .{ .permit = permit, .target = authorization.target } else null;
    result.entries = entries;
    return result;
}

pub fn progress(a: std.mem.Allocator, inputs: evidence.Inputs, candidates: extraction.tokens.Candidates, candidate: extraction.TextValidated) Error!?@import("workflow_retry.zig").Transition {
    const pending = candidate.pending_repair orelse return null;
    const merged = candidate.last_repair orelse return error.InvalidAtomicRepair;
    if (merged.owner != .reference_chunk) return error.InvalidAtomicRepair;
    const scope: evidence.Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = .{ .bytes = merged.owner.reference_chunk.chunk_id.bytes } };
    const valid = try validation.validScope(a, inputs, candidates, candidate, scope);
    return .{ .validated = .{ .permit = pending.permit, .revision = candidate.revision, .result = if (valid) .resolved else .recurring } };
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
fn select(current: extraction.TextValidated, scope: evidence.Scope) Error!Replacement {
    return .{ .classifications = .{ .token_classifications = (try entryAt(current, scope)).token_classifications } };
}

/// Source-backed loss uses the same CAS algebra and canonical extraction
/// validator; it cannot replace an entire partly-correct chunk.
pub const Omission = struct {
    const loss = @import("source_omission.zig");
    pub const OmissionTarget = union(enum) { claim: usize, outcome, classification: usize };
    pub const OmissionReplacement = union(enum) {
        claim: extraction.Proposal,
        outcome: union(enum) { no_feature_claim: extraction.text.ReferenceSemanticText, claim: extraction.Proposal },
        classification: extraction.tokens.Classification,
    };
    pub const OmissionFacts = struct { extraction: @import("reference_extraction_context.zig").Facts, support: loss.Support };
    const Atomic = shared.Contract(OmissionTarget, OmissionReplacement, OmissionFacts, @import("required_authority.zig").ReviewEvidence);
    pub const OmissionAuthorization = Atomic.Authorization;
    pub const OmissionError = Atomic.Error || loss.Error;

    pub fn authorize(a: std.mem.Allocator, facts: OmissionFacts) OmissionError!OmissionAuthorization {
        try loss.requireRepairPhase(facts.support.repair_phase);
        const selected = try loss.select(a, facts.extraction.inputs, facts.support);
        const finding = selected.finding.review.?;
        const scope = switch (selected.location) {
            .extraction_claim => |id| evidence.Scope{ .state_id = facts.extraction.inputs.corpus.state_id, .chunk_id = id },
            .token_classification => |id| scope: {
                for (facts.extraction.candidate.entries) |entry| for (entry.token_classifications) |value| {
                    if (std.meta.eql(value.id(), id)) break :scope entry.scope;
                };
                return error.InvalidAtomicRepair;
            },
            else => return error.InvalidAtomicRepair,
        };
        const entry = try entryAt(facts.extraction.candidate, scope);
        const target: OmissionTarget = switch (selected.location) {
            .extraction_claim => if (entry.outcome == .claims) .{ .claim = entry.outcome.claims.len } else .outcome,
            .token_classification => |id| .{ .classification = for (entry.token_classifications, 0..) |value, index| {
                if (std.meta.eql(value.id(), id)) break index;
            } else return error.InvalidAtomicRepair },
            else => unreachable,
        };
        const current = try valueAt(entry, target);
        var result = if (current) |value| try Atomic.authorize(a, unit(scope), facts.extraction.candidate.revision, target, value, facts, finding) else try Atomic.authorizeInsert(a, unit(scope), facts.extraction.candidate.revision, target, .claim, facts, finding);
        result.retry = try Omission.retryPermit(a, result);
        return result;
    }
    pub fn retryPermit(a: std.mem.Allocator, auth: OmissionAuthorization) OmissionError!@import("workflow_retry.zig").Permit {
        const selected = try loss.select(a, auth.dependencies.extraction.inputs, auth.dependencies.support);
        return loss.retryPermit(a, .extraction, auth.owner, auth.id, auth.revision, auth.dependencies.support, selected.finding.requirement, auth.dependencies.extraction.candidate.omission_retry);
    }
    fn scopeOf(auth: OmissionAuthorization) OmissionError!evidence.Scope {
        if (auth.owner != .reference_chunk) return error.InvalidAtomicRepair;
        return .{ .state_id = .{ .bytes = auth.owner.reference_chunk.reference_state_id.bytes }, .chunk_id = .{ .bytes = auth.owner.reference_chunk.chunk_id.bytes } };
    }
    pub fn packet(a: std.mem.Allocator, facts: OmissionFacts, literals: @import("passive_literals.zig").Registry, auth: OmissionAuthorization, guidance: *const @import("packet_guidance.zig").Guidance) OmissionError!*packets.Packet {
        try loss.requireRepairPhase(facts.support.repair_phase);
        try Atomic.checkDependencies(a, auth, facts);
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        const json = @import("model_candidate_json.zig");
        // The old outcome is a native CAS union; both claim repairs and
        // false-empty outcome repairs return the same complete Proposal wire.
        const fields = switch (auth.target) {
            .classification => json.fieldBindings(extraction.tokens.Classification, arena.allocator(), .{}),
            .claim, .outcome => json.fieldBindings(extraction.Proposal, arena.allocator(), .{ .reference_phase = .extraction }),
        } catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidAtomicRepair;
        const input = @import("reference_model_input.zig");
        const scope = try Omission.scopeOf(auth);
        const base = try input.extractionBase(a, facts.extraction.inputs, literals, facts.extraction.candidates, scope);
        defer packets.release(base);
        const result = try Atomic.packetPresenting(a, auth, guidance, base, .{ .bytes = if (auth.target == .classification) "classification" else "claim" }, try Omission.sourceOrigin(facts, auth), .{ .fields = .{ .selected = fields } });
        if (auth.target == .classification) return result;
        defer packets.release(result);
        return input.withCitationChoices(a, result, facts.extraction.inputs, scope, &.{.{ .property = "citations" }});
    }
    fn sourceOrigin(facts: OmissionFacts, auth: OmissionAuthorization) OmissionError!?@import("model_candidate_origin.zig").Origin {
        const entry = try entryAt(facts.extraction.candidate, try Omission.scopeOf(auth));
        return switch (auth.target) {
            .classification => |index| entry.classification_origins[index],
            .claim, .outcome => if (entry.producers) |producers| producers.content else entry.origin,
        };
    }
    pub fn parse(a: std.mem.Allocator, auth: OmissionAuthorization, input: *const packets.Packet, bytes: []const u8) OmissionError!OmissionReplacement {
        _ = try Atomic.checkRequest(auth, input);
        const json = @import("model_candidate_json.zig");
        return switch (auth.target) {
            .classification => .{ .classification = try json.decode(extraction.tokens.Classification, a, bytes) },
            .claim => .{ .claim = try json.decode(extraction.Proposal, a, bytes) },
            .outcome => .{ .outcome = .{ .claim = try json.decode(extraction.Proposal, a, bytes) } },
        };
    }
    pub fn merge(a: std.mem.Allocator, canonical: @import("typed_text.zig").CanonicalText, validator: extraction.text.Validator, literals: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, facts: OmissionFacts, auth: OmissionAuthorization, proposed: OmissionReplacement, origin: ?@import("model_candidate_origin.zig").Origin) OmissionError!extraction.TextValidated {
        try loss.requireRepairPhase(facts.support.repair_phase);
        if (!canonical.matchesInputs(facts.extraction.inputs)) return error.InvalidAtomicRepair;
        const replacement = try Atomic.copyReplacement(a, proposed);
        const scope = try Omission.scopeOf(auth);
        const entry = try entryAt(facts.extraction.candidate, scope);
        const merged = try Atomic.checkMerge(a, canonical, unit(scope), facts.extraction.candidate.revision, try valueAt(entry, auth.target), facts, auth, replacement, origin);
        const entries = try a.dupe(extraction.TextValidatedResult, facts.extraction.candidate.entries);
        for (entries) |*changed| if (changed.scope.chunk_id.eql(scope.chunk_id)) {
            if (auth.target == .classification) {
                const index = auth.target.classification;
                if (!std.meta.eql(entry.token_classifications[index].id(), replacement.classification.id())) return error.InvalidAtomicRepair;
                const classifications = try a.dupe(extraction.tokens.Classification, entry.token_classifications);
                classifications[index] = replacement.classification;
                changed.token_classifications = classifications;
                if (entry.classification_origins.len != classifications.len) return error.InvalidAtomicRepair;
                const origins = try a.dupe(?@import("model_candidate_origin.zig").Origin, entry.classification_origins);
                origins[index] = origin;
                changed.classification_origins = origins;
            } else {
                const claim = if (replacement == .claim) replacement.claim else if (replacement.outcome == .claim) replacement.outcome.claim else return error.InvalidAtomicRepair;
                const checked = try @import("reference_extraction_text.zig").validate(validator, a, literals, current, facts.extraction.inputs, .{ .entries = &.{.{ .scope = scope, .origin = origin, .token_classifications = &.{}, .outcome = .{ .claims = &.{claim} } }} });
                if (checked != .valid) return error.InvalidAtomicRepair;
                var claims: std.ArrayList(extraction.TextValidatedProposal) = .empty;
                if (entry.outcome == .claims) try claims.appendSlice(a, entry.outcome.claims);
                // A proposal spanning several list items quotes one claim per item (ADR 0036, ADR 0038).
                try claims.appendSlice(a, checked.valid.entries[0].outcome.claims);
                changed.outcome = .{ .claims = try claims.toOwnedSlice(a) };
                if (entry.outcome == .no_feature_claim) {
                    // Forced irrelevant choices depended on the retired outcome.
                    // The existing classification validator/repair gate now owns them.
                    changed.token_classifications = &.{};
                    changed.classification_origins = &.{};
                }
            }
        };
        var result = facts.extraction.candidate;
        result.revision = merged.revision_after;
        result.last_repair = merged;
        result.pending_repair = null;
        result.omission_retry = auth.retry orelse return error.InvalidAtomicRepair;
        result.entries = entries;
        return result;
    }
    fn valueAt(entry: extraction.TextValidatedResult, target: OmissionTarget) OmissionError!?OmissionReplacement {
        return switch (target) {
            .claim => |index| if (entry.outcome == .claims and index == entry.outcome.claims.len) null else error.InvalidAtomicRepair,
            .outcome => if (entry.outcome == .no_feature_claim) .{ .outcome = .{ .no_feature_claim = entry.outcome.no_feature_claim.value } } else error.InvalidAtomicRepair,
            .classification => |index| if (index < entry.token_classifications.len) .{ .classification = entry.token_classifications[index] } else error.InvalidAtomicRepair,
        };
    }
    pub const Target = OmissionTarget;
    pub const Replacement = OmissionReplacement;
    pub const Facts = OmissionFacts;
    pub const Authorization = OmissionAuthorization;
    pub const Error = OmissionError;
};
