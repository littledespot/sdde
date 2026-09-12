//! The classification collection is one coupled validation unit. Claims and
//! other chunks stay immutable; shared atomic_repair owns replacement authority.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
const evidence = @import("reference_evidence.zig");
const validation = @import("token_classification_validation.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
pub const Replacement = union(enum) { classifications: struct { token_classifications: []const extraction.tokens.Classification } };
const atomic = @import("atomic_repair.zig").Contract(enum { token_classifications }, Replacement, validation.Issues);
pub const Authorization = atomic.Authorization;
pub const Error = atomic.Error || extraction.Error;

pub fn authorize(a: std.mem.Allocator, inputs: evidence.Inputs, candidates: extraction.tokens.Candidates, current: extraction.TextValidated) Error!Authorization {
    const checked = try validation.validate(a, inputs, candidates, current);
    if (checked != .invalid) return error.InvalidAtomicRepair;
    const diagnostic = checked.invalid;
    return atomic.authorize(a, unit(diagnostic.scope), current.revision, .token_classifications, try select(current, diagnostic.scope), diagnostic.issues);
}

pub fn packet(a: std.mem.Allocator, inputs: evidence.Inputs, literals: @import("passive_literals.zig").Registry, candidates: extraction.tokens.Candidates, current: extraction.TextValidated, authorization: Authorization) Error!*packets.Packet {
    const scope = try scopeOf(authorization);
    if (current.revision != authorization.revision) return error.InvalidAtomicRepair;
    _ = try select(current, scope);
    const base = try @import("reference_model_input.zig").extractionPacket(a, inputs, literals, candidates, scope);
    defer packets.release(base);
    return atomic.packet(a, authorization, base, .{ .bytes = "classification_replacement" });
}

pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(a, authorization, input, bytes);
}

pub fn merge(a: std.mem.Allocator, current: extraction.TextValidated, authorization: Authorization, replacement: Replacement) Error!extraction.TextValidated {
    const scope = try scopeOf(authorization);
    const revision = try atomic.checkMerge(a, unit(scope), current.revision, try select(current, scope), authorization, replacement);
    const entries = try a.dupe(extraction.TextValidatedResult, current.entries);
    for (entries) |*entry| if (entry.scope.chunk_id.eql(scope.chunk_id)) {
        // Classifications contain value IDs/enums only. Own the replacement so
        // the successor need retain only its preceding reference candidate.
        entry.token_classifications = try a.dupe(extraction.tokens.Classification, replacement.classifications.token_classifications);
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
fn select(current: extraction.TextValidated, scope: evidence.Scope) Error!Replacement {
    var result: ?Replacement = null;
    for (current.entries) |entry| {
        if (!entry.scope.state_id.eql(scope.state_id)) return error.InvalidAtomicRepair;
        if (!entry.scope.chunk_id.eql(scope.chunk_id)) continue;
        if (result != null or entry.outcome == .blocked) return error.InvalidAtomicRepair;
        result = .{ .classifications = .{ .token_classifications = entry.token_classifications } };
    }
    return result orelse error.InvalidAtomicRepair;
}
