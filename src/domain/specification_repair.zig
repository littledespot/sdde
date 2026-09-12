//! Native-selected replacement of one brief field, story, applicability basis
//! or record. No model-authored target, revision or sibling mutation.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const session = @import("specification_session.zig");
const packets = @import("model_input_packet.zig");
pub const Candidate = struct { revision: u64 = 1, response: g.Response };
pub const Target = union(enum) { title, description, primary_goal, story, entity_basis, record: usize };
pub const Replacement = union(enum) { attributed: g.spec.AttributedValue, record: g.spec.RecordProposal };
pub const Rule = enum { provenance, typed_text, record_kind, duplicate_record };
const atomic = @import("atomic_repair.zig").Contract(Target, Replacement, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = session.Error || atomic.Error || error{InvalidSpecificationRepair};

pub fn authorize(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, current: session.Session, candidate: Candidate) Error!Authorization {
    if (candidate.revision == 0 or candidate.response != .content) return error.InvalidSpecificationRepair;
    const unit = try session.unit(current.completed);
    const content = candidate.response.content;
    if (@intFromEnum(std.meta.activeTag(unit)) != @intFromEnum(std.meta.activeTag(content))) return error.InvalidSpecificationRepair;
    switch (content) {
        .brief => |brief| {
            inline for (.{ "title", "description", "primary_goal" }) |field| {
                _ = p.attributed(allocator, validator, context, @field(brief, field)) catch |err| {
                    return make(allocator, current, candidate, @unionInit(Target, field, {}), try rule(err));
                };
            }
        },
        .primary_user_story => |story| {
            _ = p.attributed(allocator, validator, context, story) catch |err| return make(allocator, current, candidate, .story, try rule(err));
        },
        .entities => |entities| {
            _ = p.attributed(allocator, validator, context, entities.basis) catch |err| return make(allocator, current, candidate, .entity_basis, try rule(err));
        },
        .records => |records| {
            const normalized = try allocator.alloc(g.spec.RecordProposal, records.len);
            for (records, normalized, 0..) |record, *accepted, index| {
                if (std.meta.activeTag(record.content) != unit.records) return make(allocator, current, candidate, .{ .record = index }, .record_kind);
                accepted.* = p.record(allocator, validator, context, record) catch |err| return make(allocator, current, candidate, .{ .record = index }, try rule(err));
                for (normalized[0..index]) |prior| if (try g.equalContent(allocator, prior.content, accepted.content)) return make(allocator, current, candidate, .{ .record = index }, .duplicate_record);
            }
        },
    }
    return error.InvalidSpecificationRepair;
}

fn rule(err: p.Error) Error!Rule {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidSpecification, error.InvalidReferenceReconciliation, error.InvalidSourceCitation => .provenance,
        error.InvalidTypedText, error.UnboundPathReference, error.InvalidPassiveLiteral => .typed_text,
        // Invalid/stale mechanical authority is never sent to model repair.
        else => error.InvalidSpecificationRepair,
    };
}
fn make(allocator: std.mem.Allocator, current: session.Session, candidate: Candidate, target: Target, selected_rule: Rule) Error!Authorization {
    return atomic.authorize(allocator, try session.owner(allocator, current), candidate.revision, target, try select(candidate.response, target), selected_rule);
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

pub fn merge(allocator: std.mem.Allocator, current: session.Session, candidate: Candidate, authorization: Authorization, replacement: Replacement) Error!Candidate {
    var result = candidate;
    result.revision = try atomic.checkMerge(allocator, try session.owner(allocator, current), candidate.revision, try select(candidate.response, authorization.target), authorization, replacement);
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

fn select(response: g.Response, target: Target) Error!Replacement {
    if (response != .content) return error.InvalidSpecificationRepair;
    const content = response.content;
    return switch (target) {
        .title => if (content == .brief) .{ .attributed = content.brief.title } else error.InvalidSpecificationRepair,
        .description => if (content == .brief) .{ .attributed = content.brief.description } else error.InvalidSpecificationRepair,
        .primary_goal => if (content == .brief) .{ .attributed = content.brief.primary_goal } else error.InvalidSpecificationRepair,
        .story => if (content == .primary_user_story) .{ .attributed = content.primary_user_story } else error.InvalidSpecificationRepair,
        .entity_basis => if (content == .entities) .{ .attributed = content.entities.basis } else error.InvalidSpecificationRepair,
        .record => |index| if (content == .records and index < content.records.len) .{ .record = content.records[index] } else error.InvalidSpecificationRepair,
    };
}
