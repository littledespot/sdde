//! Scoped repair of mechanically invalid review data, never of a negative verdict.
const std = @import("std");
const review = @import("specification_support.zig");
const authority = @import("required_authority.zig");
const evidence = @import("reference_evidence.zig");
const shared = @import("atomic_repair.zig");
const p = @import("specification_provenance.zig");
const packets = @import("model_input_packet.zig");
const Origin = @import("model_candidate_origin.zig").Origin;
const Target = struct { requirement: authority.Id, ordinal: u32, index: usize };
const Selection = struct { provenance: @import("specification.zig").Selection, source_ids: []const @import("reference_identity.zig").SourceId };
pub const Replacement = union(enum) { finding: review.Value, selection: Selection, detail: struct { detail: []const u8 }, disposition: struct { disposition: @FieldType(review.Value, "disposition") } };
const Facts = struct { inputs: authority.Inputs, sources: evidence.Inputs, candidate: review.Candidate };
const Rule = struct {
    rejection: review.Rejection,
    finding: ?review.Value,
    pub fn guidance(self: @This()) struct { issue: review.Issue, finding: ?review.Value } {
        return .{ .issue = self.rejection.issue, .finding = self.finding };
    }
};
const atomic = shared.Contract(Target, Replacement, Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const State = struct { authorization: Authorization, response: ?struct { value: Replacement, origin: ?Origin } = null };
pub const Error = review.Error || atomic.Error || error{UnsafeSupportRepair};

pub fn authorize(a: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, rejected: @FieldType(review.Collection, "rejected")) Error!Authorization {
    const candidate = rejected.candidate orelse return error.UnsafeSupportRepair;
    const current = try review.validate(a, inputs, context.inputs, candidate);
    if (current != .rejected or !std.meta.eql(try shared.snapshot(review.Rejection, a, current.rejected.rejection), try shared.snapshot(review.Rejection, a, rejected.rejection))) return error.InvalidAtomicRepair;
    const rejection = rejected.rejection;
    const id = rejection.requirement orelse return error.UnsafeSupportRepair;
    if (authority.policy(id) == null) return error.UnsafeSupportRepair;
    const ordinal = rejection.ordinal orelse return error.UnsafeSupportRepair;
    const base = try review.packet(a, inputs, context);
    defer packets.release(base);
    const facts: Facts = .{ .inputs = inputs, .sources = context.inputs, .candidate = candidate };
    if (rejection.issue == .missing_requirement) return atomic.authorizeInsert(a, base.unit(), candidate.revision, .{ .requirement = id, .ordinal = ordinal, .index = candidate.review.entries.len }, .finding, facts, .{ .rejection = rejection, .finding = null });
    const first = for (candidate.review.entries, 0..) |finding, index| {
        if (finding.requirement_ordinal == ordinal) break index;
    } else return error.InvalidAtomicRepair;
    var target: Target = .{ .requirement = id, .ordinal = ordinal, .index = first };
    const value = candidate.review.entries[first].value;
    if (rejection.issue == .duplicate_requirement) {
        for (candidate.review.entries[first + 1 ..], first + 1..) |finding, index| {
            if (finding.requirement_ordinal != ordinal) continue;
            if (!try atomic.equal(a, .{ .finding = value }, .{ .finding = finding.value })) return error.UnsafeSupportRepair;
            target.index = index;
            return atomic.authorizeDelete(a, base.unit(), candidate.revision, target, .{ .finding = value }, facts, .{ .rejection = rejection, .finding = value });
        }
        return error.InvalidAtomicRepair;
    }
    const expected: Replacement = switch (rejection.issue) {
        .invalid_detail => .{ .detail = .{ .detail = value.detail } },
        .invalid_disposition => .{ .disposition = .{ .disposition = value.disposition } },
        .invalid_provenance => .{ .selection = .{ .provenance = value.provenance, .source_ids = value.source_ids } },
        .invalid_json, .unknown_requirement, .duplicate_requirement, .missing_requirement => return error.UnsafeSupportRepair,
    };
    return atomic.authorize(a, base.unit(), candidate.revision, target, expected, facts, .{ .rejection = rejection, .finding = value });
}
pub fn packet(a: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, candidate: review.Candidate, authorization: Authorization) Error!*packets.Packet {
    try atomic.checkDependencies(a, authorization, .{ .inputs = inputs, .sources = context.inputs, .candidate = candidate });
    const base = try review.packetFor(a, inputs, context, authorization.target.requirement);
    defer packets.release(base);
    const kind = switch (authorization.operation) {
        .replace => |value| std.meta.activeTag(value),
        .insert => |value| value,
        .delete => return error.InvalidAtomicRepair,
    };
    return atomic.packet(a, authorization, base, .{ .bytes = @tagName(kind) });
}
pub const parse = atomic.parse;
pub fn merge(a: std.mem.Allocator, inputs: authority.Inputs, context: p.Context, candidate: review.Candidate, authorization: Authorization, replacement: ?Replacement, origin: ?Origin) Error!review.Collection {
    const target = authorization.target;
    const base = try review.packet(a, inputs, context);
    defer packets.release(base);
    const expected: ?Replacement = if (authorization.operation == .insert) null else valueAt(candidate, target.index, std.meta.activeTag(if (authorization.operation == .replace) authorization.operation.replace else authorization.operation.delete));
    const facts: Facts = .{ .inputs = inputs, .sources = context.inputs, .candidate = candidate };
    const merged = try atomic.checkMerge(a, base.unit(), candidate.revision, expected, facts, authorization, replacement, origin);
    var entries: std.ArrayList(review.Finding) = .empty;
    var origins: std.ArrayList(?Origin) = .empty;
    for (candidate.review.entries, candidate.origins, 0..) |finding, previous_origin, index| {
        if (authorization.operation == .delete and index == target.index) continue;
        var next = finding;
        if (authorization.operation == .replace and index == target.index) switch (try atomic.copyReplacement(a, replacement.?)) {
            .detail => |value| next.value.detail = value.detail,
            .disposition => |value| next.value.disposition = value.disposition,
            .selection => |value| {
                next.value.provenance = value.provenance;
                next.value.source_ids = value.source_ids;
            },
            .finding => return error.InvalidAtomicRepair,
        };
        try entries.append(a, next);
        try origins.append(a, if (authorization.operation == .replace and index == target.index) origin else previous_origin);
    }
    if (authorization.operation == .insert) {
        if (target.index != entries.items.len or replacement.? != .finding) return error.InvalidAtomicRepair;
        try entries.append(a, .{ .requirement_ordinal = target.ordinal, .value = (try atomic.copyReplacement(a, replacement.?)).finding });
        try origins.append(a, origin);
    }
    return review.validate(a, inputs, context.inputs, .{ .review = .{ .entries = try entries.toOwnedSlice(a) }, .revision = merged.revision_after, .origin = candidate.origin, .origins = try origins.toOwnedSlice(a), .last_repair = merged });
}
fn valueAt(candidate: review.Candidate, index: usize, kind: std.meta.Tag(Replacement)) ?Replacement {
    if (index >= candidate.review.entries.len) return null;
    const value = candidate.review.entries[index].value;
    return switch (kind) {
        .finding => .{ .finding = value },
        .detail => .{ .detail = .{ .detail = value.detail } },
        .disposition => .{ .disposition = .{ .disposition = value.disposition } },
        .selection => .{ .selection = .{ .provenance = value.provenance, .source_ids = value.source_ids } },
    };
}
