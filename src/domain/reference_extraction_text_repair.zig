//! One parsed extraction content field, before text acceptance. Atomic repair
//! owns CAS; the shared text validator and workflow own acceptance/repetition.
const std = @import("std");
const e = @import("reference_extraction.zig");
const context = @import("reference_extraction_context.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
pub const Target = struct {
    scope: e.identity.ChunkId,
    field: e.TextTarget,
    pub fn guidance(self: Target) e.TextTarget {
        return self.field;
    }
};
pub const Replacement = union(enum) { business: e.text.BusinessText, reference: e.text.ReferenceSemanticText };
pub const Rule = struct {
    issue: e.text.Issue,
    requirement: []const u8,
};
const shared = @import("atomic_repair.zig");
const atomic = shared.Contract(Target, Replacement, context.TextFacts, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = atomic.Error || e.Error;
pub const Facts = context.TextFacts;
const Family = enum { typed_text };

pub fn retryPermit(a: std.mem.Allocator, authorization: Authorization) Error!@import("workflow_retry.zig").Permit {
    const candidate = authorization.dependencies.candidate;
    const entry = try entryAt(candidate, authorization.target);
    const count: usize = switch (entry.outcome) {
        .claims => |claims| claims.len,
        .no_feature_claim => 1,
        .blocked => return error.InvalidAtomicRepair,
    };
    var permit = try shared.permit(e.TextTarget, Family, a, authorization.owner, authorization.target.field, .typed_text, authorization.id, authorization.revision, std.math.cast(u32, count) orelse return error.InvalidAtomicRepair);
    const scope = .{ .boundary = permit.key.scope, .origin = entry.origin };
    permit.key.scope = (try shared.snapshot(@TypeOf(scope), a, scope)).bytes;
    if (candidate.last_repair) |prior| if (prior.retry) |previous| if (std.mem.eql(u8, &previous.key.scope, &permit.key.scope)) {
        permit.maximum_targets = previous.maximum_targets;
    };
    return permit;
}

pub fn authorize(a: std.mem.Allocator, facts: Facts, rejection: e.TextRejection) Error!Authorization {
    const parsed = facts.candidate;
    if (parsed.revision != rejection.revision or !facts.text.inputs.corpus.state_id.eql(rejection.scope.state_id) or
        !std.meta.eql(rejection.dependencies, try shared.snapshot(Facts, a, facts))) return error.InvalidAtomicRepair;
    const target: Target = .{ .scope = rejection.scope.chunk_id, .field = rejection.target };
    const entry = try entryAt(parsed, target);
    if (!std.meta.eql(e.textOrigin(entry, target.field), rejection.origin)) return error.InvalidAtomicRepair;
    const expected = try select(parsed, target);
    const observed: Replacement = switch (rejection.observed) {
        .reason => |value| .{ .reference = value },
        .content => |content| switch (content) {
            .business, .scope_guard => |value| .{ .business = value },
            inline else => |value| .{ .reference = value },
        },
    };
    if (!try atomic.equal(a, expected, observed)) return error.InvalidAtomicRepair;
    var result = try atomic.authorize(a, unit(rejection.scope), parsed.revision, target, expected, facts, .{ .issue = rejection.issue, .requirement = rejection.issue.description() });
    result.retry = try retryPermit(a, result);
    return result;
}
pub fn packet(a: std.mem.Allocator, facts: Facts, registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, candidates: e.tokens.Candidates, authorization: Authorization) Error!*packets.Packet {
    try atomic.checkDependencies(a, authorization, facts);
    try atomic.checkDependencies(a, authorization, try context.textFacts(facts.text.inputs, registry, current, facts.candidate));
    const scope: @import("reference_evidence.zig").Scope = .{ .state_id = facts.text.inputs.corpus.state_id, .chunk_id = authorization.target.scope };
    const base = try @import("reference_model_input.zig").extractionPacket(a, facts.text.inputs, registry, candidates, scope);
    defer packets.release(base);
    return atomic.packet(a, authorization, base, .{ .bytes = switch (authorization.operation.replace) {
        .business => "business_text_replacement",
        .reference => "reference_text_replacement",
    } }, e.textOrigin(try entryAt(facts.candidate, authorization.target), authorization.target.field));
}
pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(a, authorization, input, bytes);
}
pub fn merge(a: std.mem.Allocator, facts: Facts, authorization: Authorization, proposed_replacement: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!e.Parsed {
    const replacement = try atomic.copyReplacement(a, proposed_replacement);
    const target = authorization.target;
    const scope: @import("reference_evidence.zig").Scope = .{ .state_id = facts.text.inputs.corpus.state_id, .chunk_id = target.scope };
    const merged = try atomic.checkMerge(a, unit(scope), facts.candidate.revision, try select(facts.candidate, target), facts, authorization, replacement, origin);
    const entries = try a.dupe(e.ParsedResult, facts.candidate.entries);
    for (entries) |*entry| if (entry.scope.chunk_id.eql(target.scope)) {
        switch (target.field) {
            .reason => entry.outcome.no_feature_claim = replacement.reference,
            .claim => |index| {
                const claims = try a.dupe(e.Proposal, entry.outcome.claims);
                claims[index].content = switch (claims[index].content) {
                    inline .business, .scope_guard => |_, tag| @unionInit(e.ProposalContent, @tagName(tag), replacement.business),
                    inline else => |_, tag| @unionInit(e.ProposalContent, @tagName(tag), replacement.reference),
                };
                entry.outcome = .{ .claims = claims };
            },
        }
        var origins: std.ArrayList(e.TextOrigin) = .empty;
        for (entry.text_origins) |value| if (!std.meta.eql(value.target, target.field)) try origins.append(a, value);
        try origins.append(a, .{ .target = target.field, .origin = origin });
        entry.text_origins = try origins.toOwnedSlice(a);
    };
    return .{ .revision = merged.revision_after, .last_repair = merged, .pending_repair = if (authorization.retry) |permit| .{ .permit = permit, .target = .{ .field = target.field, .scope = .{ .bytes = try a.dupe(u8, target.scope.bytes) } } } else null, .entries = entries };
}

pub fn progress(a: std.mem.Allocator, validator: e.text.Validator, registry: @import("passive_literals.zig").Registry, current: *const @import("toolchain_safety.zig").ValidToolchain, inputs: @import("reference_evidence.zig").Inputs, candidate: e.Parsed) Error!?@import("workflow_retry.zig").Transition {
    const pending = candidate.pending_repair orelse return null;
    const scope: @import("reference_evidence.zig").Scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = pending.target.scope };
    const valid = try @import("reference_extraction_text.zig").validTarget(validator, a, registry, current, inputs, candidate, scope, pending.target.field);
    return .{ .validated = .{ .permit = pending.permit, .revision = candidate.revision, .result = if (valid) .resolved else .recurring } };
}
fn entryAt(parsed: e.Parsed, target: Target) Error!e.ParsedResult {
    var result: ?e.ParsedResult = null;
    for (parsed.entries) |entry| if (entry.scope.chunk_id.eql(target.scope)) {
        if (result != null or entry.outcome == .blocked) return error.InvalidAtomicRepair;
        result = entry;
    };
    return result orelse error.InvalidAtomicRepair;
}
fn select(parsed: e.Parsed, target: Target) Error!Replacement {
    const entry = try entryAt(parsed, target);
    return switch (target.field) {
        .reason => if (entry.outcome == .no_feature_claim) .{ .reference = entry.outcome.no_feature_claim } else error.InvalidAtomicRepair,
        .claim => |index| if (entry.outcome == .claims and index < entry.outcome.claims.len) switch (entry.outcome.claims[index].content) {
            .business, .scope_guard => |value| .{ .business = value },
            inline else => |value| .{ .reference = value },
        } else error.InvalidAtomicRepair,
    };
}
fn unit(scope: @import("reference_evidence.zig").Scope) identity.ImmutableUnitOwnerId {
    return .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = scope.state_id.bytes }, .chunk_id = .{ .bytes = scope.chunk_id.bytes } } };
}
