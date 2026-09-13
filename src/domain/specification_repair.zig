//! Native-selected replacement of one brief field, story, applicability basis
//! or record. No model-authored target, revision or sibling mutation.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const session = @import("specification_session.zig");
const packets = @import("model_input_packet.zig");
const candidates = @import("specification_candidate.zig");
pub const Candidate = candidates.Candidate;
pub const Target = candidates.Target;
pub const Replacement = candidates.Replacement;
pub const Rule = candidates.Rule;
const atomic = @import("atomic_repair.zig").Contract(Target, Replacement, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = session.Error || atomic.Error || error{InvalidSpecificationRepair};

pub fn authorize(allocator: std.mem.Allocator, current: session.Session, candidate: Candidate, rejection: candidates.Rejection) Error!Authorization {
    const owner = try session.owner(allocator, current);
    if (candidate.revision == 0 or candidate.revision != rejection.revision or
        !@import("model_request_identity.zig").unitOwnerEql(owner, rejection.owner) or
        !std.meta.eql(try session.unit(current.completed), rejection.issue.unit) or
        !std.meta.eql(candidate.origins.at(rejection.issue.field), rejection.origin) or rejection.issue.field != .target) return error.InvalidSpecificationRepair;
    const expected = rejection.issue.observed orelse return error.InvalidSpecificationRepair;
    const target = rejection.issue.field.target;
    if (!try atomic.equal(allocator, try candidates.select(candidate.response, target), expected)) return error.InvalidSpecificationRepair;
    return atomic.authorize(allocator, owner, candidate.revision, target, expected, rejection.issue.rule);
}

pub fn packet(allocator: std.mem.Allocator, current: session.Session, context: p.Context, authorization: Authorization) Error!*packets.Packet {
    const unit = try session.unit(current.completed);
    if (authorization.expected == .record and unit != .records) return error.InvalidSpecificationRepair;
    const base = try session.packet(allocator, current, context);
    defer packets.release(base);
    const definition = switch (authorization.expected) {
        .attributed => "attributed",
        .record => try std.fmt.allocPrint(allocator, "record_{s}", .{@tagName(unit.records)}),
    };
    defer if (authorization.expected == .record) allocator.free(definition);
    return atomic.packet(allocator, authorization, base, .{ .bytes = definition });
}

pub fn parse(allocator: std.mem.Allocator, authorization: Authorization, packet_value: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(allocator, authorization, packet_value, bytes);
}

pub fn merge(allocator: std.mem.Allocator, current: session.Session, candidate: Candidate, authorization: Authorization, replacement: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!Candidate {
    var result = candidate;
    result.revision = try atomic.checkMerge(allocator, try session.owner(allocator, current), candidate.revision, try candidates.select(candidate.response, authorization.target), authorization, replacement);
    result.origins = try candidate.origins.replacing(allocator, authorization.target, origin);
    switch (authorization.target) {
        .title => result.response.content.brief.title = replacement.attributed,
        .description => result.response.content.brief.description = replacement.attributed,
        .primary_goal => result.response.content.brief.primary_goal = replacement.attributed,
        .story => result.response.content.primary_user_story = replacement.attributed,
        .entity_basis => result.response.content.entities.basis = replacement.attributed,
        .record => |index| {
            const records = try allocator.dupe(g.spec.RecordProposal, candidate.response.content.records);
            records[index] = replacement.record;
            result.response.content.records = records;
        },
    }
    return result;
}
