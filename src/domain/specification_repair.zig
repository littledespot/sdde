//! Repair one independent specification value or evidence selection.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const session = @import("specification_session.zig");
const packets = @import("model_input_packet.zig");
const candidates = @import("specification_candidate.zig");
pub const Candidate = candidates.Candidate;
pub const Target = candidates.Target;
pub const Replacement = candidates.Replacement;
pub const Rule = struct {
    validator: enum { specification_generation_v1 } = .specification_generation_v1,
    rule: candidates.Rule,
    native_error: @FieldType(candidates.Issue, "native_error"),
    requirement: []const u8,
};
const dependencies = @import("specification_candidate_context.zig");
const shared = @import("atomic_repair.zig");
const atomic = shared.Contract(Target, Replacement, dependencies.Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = session.Error || atomic.Error || error{ InvalidSpecificationRepair, UnsafeSpecificationRepair };

pub fn authorize(allocator: std.mem.Allocator, current: session.Session, context: p.Context, candidate: Candidate, rejection: candidates.Rejection) Error!Authorization {
    const facts = try dependencies.capture(allocator, current, context, candidate);
    defer allocator.free(facts.input);
    const stamp = rejection.dependencies orelse return error.InvalidSpecificationRepair;
    if (!std.meta.eql(stamp, try shared.snapshot(dependencies.Facts, allocator, facts))) return error.InvalidSpecificationRepair;
    const owner = try session.owner(allocator, current);
    if (candidate.revision == 0 or candidate.revision != rejection.revision or
        !@import("model_request_identity.zig").unitOwnerEql(owner, rejection.owner) or
        !std.meta.eql(try session.unit(current.completed), rejection.issue.unit) or
        !std.meta.eql(candidate.origins.at(rejection.issue.field), rejection.origin) or rejection.issue.field != .target) return error.InvalidSpecificationRepair;
    if (rejection.issue.blocked != null) return error.UnsafeSpecificationRepair;
    const expected = rejection.issue.observed orelse return error.InvalidSpecificationRepair;
    const target = rejection.issue.field.target;
    if (!try atomic.equal(allocator, try candidates.select(candidate.response, target), expected)) return error.InvalidSpecificationRepair;
    const rule: Rule = .{ .rule = rejection.issue.rule, .native_error = rejection.issue.native_error, .requirement = switch (rejection.issue.rule) {
        .provenance => "Select nonempty, unique currently retained claim IDs; clarification responses are unavailable in this generation context.",
        .typed_text => "Use valid nonblank business text and only supplied scoped passive references for path-like text.",
        .exact_copy => "Select a preserved token and its citation supported by this field's unchanged provenance.",
        .record_kind => "Supply one record of the requested kind with valid content and evidence selections.",
        .duplicate_record => "Remove only the evidence-equivalent redundant occurrence; preserve coverage and sibling order.",
        .unit_kind => return error.UnsafeSpecificationRepair,
    } };
    return if (rejection.issue.rule == .duplicate_record)
        atomic.authorizeDelete(allocator, owner, candidate.revision, target, expected, facts, rule)
    else
        atomic.authorize(allocator, owner, candidate.revision, target, expected, facts, rule);
}

pub fn packet(allocator: std.mem.Allocator, current: session.Session, context: p.Context, authorization: Authorization) Error!*packets.Packet {
    const facts = try dependencies.capture(allocator, current, context, authorization.dependencies.candidate);
    defer allocator.free(facts.input);
    try atomic.checkDependencies(allocator, authorization, facts);
    const unit = try session.unit(current.completed);
    if (authorization.operation != .replace) return error.InvalidSpecificationRepair;
    if (authorization.operation.replace == .record and unit != .records) return error.InvalidSpecificationRepair;
    const base = try session.packet(allocator, current, context);
    defer packets.release(base);
    const definition = switch (authorization.operation.replace) {
        .provenance => "provenance",
        .value => "value",
        .record => try std.fmt.allocPrint(allocator, "record_{s}", .{@tagName(unit.records)}),
    };
    defer if (authorization.operation.replace == .record) allocator.free(definition);
    return atomic.packet(allocator, authorization, base, .{ .bytes = definition });
}

pub fn parse(allocator: std.mem.Allocator, authorization: Authorization, packet_value: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(allocator, authorization, packet_value, bytes);
}

pub fn merge(allocator: std.mem.Allocator, current: session.Session, context: p.Context, candidate: Candidate, authorization: Authorization, proposed_replacement: ?Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!Candidate {
    const facts = try dependencies.capture(allocator, current, context, candidate);
    defer allocator.free(facts.input);
    var result = candidate;
    result.revision = try atomic.checkMerge(allocator, try session.owner(allocator, current), candidate.revision, try candidates.select(candidate.response, authorization.target), facts, authorization, proposed_replacement);
    result.last_repair_changed = try atomic.changed(allocator, authorization, proposed_replacement);
    switch (authorization.operation) {
        .replace => {
            const replacement = try atomic.copyReplacement(allocator, proposed_replacement.?);
            result.response = try candidates.replace(allocator, candidate.response, authorization.target, replacement);
            result.origins = try candidate.origins.replacing(allocator, authorization.target, origin);
        },
        .delete => {
            if (authorization.target != .record) return error.InvalidSpecificationRepair;
            const index = authorization.target.record;
            const old = candidate.response.content.records;
            const records = try allocator.alloc(g.spec.Model.RecordProposal, old.len - 1);
            @memcpy(records[0..index], old[0..index]);
            @memcpy(records[index..], old[index + 1 ..]);
            result.response.content.records = records;
            result.origins = try candidate.origins.deleting(allocator, index);
        },
        .insert => return error.InvalidSpecificationRepair,
    }
    return result;
}
