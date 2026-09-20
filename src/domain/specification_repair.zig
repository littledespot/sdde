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
    requirement: []const u8,
    text_issue: ?@import("typed_text.zig").Issue,
    value_choices: ?p.ValueChoices,
};
const dependencies = @import("specification_candidate_context.zig");
const shared = @import("atomic_repair.zig");
const retry = @import("workflow_retry.zig");
const atomic = shared.Contract(Target, Replacement, dependencies.Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = session.Error || atomic.Error || candidates.Error || error{ InvalidSpecificationRepair, UnsafeSpecificationRepair };

pub fn authorize(allocator: std.mem.Allocator, current: session.Session, context: p.Context, candidate: Candidate, rejection: candidates.Rejection) Error!Authorization {
    const facts = try dependencies.capture(allocator, current, context, candidate);
    defer allocator.free(facts.references.lineage.history);
    const stamp = rejection.dependencies orelse return error.InvalidSpecificationRepair;
    if (!std.meta.eql(stamp, try shared.snapshot(dependencies.Facts, allocator, facts))) return error.InvalidSpecificationRepair;
    const owner = try session.owner(allocator, current);
    if (candidate.revision == 0 or candidate.revision != rejection.revision or
        !@import("model_request_identity.zig").unitOwnerEql(owner, rejection.owner) or
        !std.meta.eql(try session.unit(current.completed), rejection.issue.unit) or
        !std.meta.eql(candidate.origins.at(rejection.issue.field), rejection.origin) or rejection.issue.field != .target) return error.InvalidSpecificationRepair;
    if (rejection.issue.blocked != null) return error.UnsafeSpecificationRepair;
    var expected = rejection.issue.observed orelse return error.InvalidSpecificationRepair;
    var target = rejection.issue.field.target;
    if (!try atomic.equal(allocator, try candidates.select(candidate.response, target), expected)) return error.InvalidSpecificationRepair;
    var selected_rule = rejection.issue.rule;
    if (candidate.pending_repair) |pending| if (pending.target.value == .record) {
        if (try candidate.origins.currentTarget(pending.target, recordCount(candidate.response))) |prior| {
            const subject: candidates.Subject = switch (target) {
                .record => |index| .{ .record = index },
                .provenance => |subject| subject,
                .value => |field| field.subject,
            };
            if (subject == .record and subject.record == prior.record and target != .record) {
                target = prior;
                expected = try candidates.select(candidate.response, target);
                selected_rule = .record_kind;
            }
        }
    };
    const rule: Rule = .{ .text_issue = rejection.issue.text_issue, .value_choices = rejection.issue.value_choices, .requirement = switch (selected_rule) {
        .provenance => "Select nonempty, unique currently retained claim IDs; clarification responses are unavailable in this generation context.",
        .typed_text => (rejection.issue.text_issue orelse return error.InvalidSpecificationRepair).description(),
        .exact_copy => "Use an allowed value representation supported by the unchanged provenance; exact copies must select a supplied token/citation pair.",
        .record_kind => "Supply one record of the requested kind with valid content and evidence selections.",
        .duplicate_record => "Remove only the evidence-equivalent redundant occurrence; preserve coverage and sibling order.",
        .unit_kind => return error.UnsafeSpecificationRepair,
    } };
    var authorization = if (rejection.issue.rule == .duplicate_record)
        try atomic.authorizeDelete(allocator, owner, candidate.revision, target, expected, facts, rule)
    else
        try atomic.authorize(allocator, owner, candidate.revision, target, expected, facts, rule);
    authorization.retry = try retryPermit(allocator, authorization);
    return authorization;
}

pub fn retryPermit(a: std.mem.Allocator, authorization: Authorization) Error!retry.Permit {
    const candidate = authorization.dependencies.candidate;
    const target = try candidate.origins.stableTarget(authorization.target, recordCount(candidate.response));
    const bound = candidate.origins.repair_target_bound orelse try targetBound(candidate.response);
    var permit = try shared.permit(candidates.StableTarget, std.meta.Tag(Target), a, authorization.owner, target, std.meta.activeTag(authorization.target), authorization.id, authorization.revision, bound);
    const Scope = struct { owner: @import("model_request_identity.zig").ImmutableUnitOwnerId, origin: ?@import("model_candidate_origin.zig").Origin };
    permit.key.scope = if (candidate.pending_repair) |pending| pending.permit.key.scope else (try shared.snapshot(Scope, a, .{ .owner = authorization.owner, .origin = candidate.origins.initial })).bytes;
    return permit;
}

fn recordCount(response: g.Response) usize {
    return if (response == .content and response.content == .records) response.content.records.len else 0;
}
fn targetBound(response: g.Response) Error!u32 {
    if (response != .content) return error.InvalidSpecificationRepair;
    var count: usize = 0;
    switch (response.content) {
        .brief => count = 6,
        .primary_user_story, .entities => count = 2,
        .records => |records| for (records) |record| {
            count = std.math.add(usize, count, 2) catch return error.InvalidSpecificationRepair;
            switch (record.content) {
                inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                    count = std.math.add(usize, count, if (comptime field.type == g.spec.BusinessValue) 1 else @field(fields, field.name).len) catch return error.InvalidSpecificationRepair;
                },
            }
        },
    }
    if (count == 0) return error.InvalidSpecificationRepair;
    return std.math.cast(u32, count) orelse error.InvalidSpecificationRepair;
}

/// Full unit validation still runs first. This checks the selected occurrence
/// even when a different sibling is now the unit validator's first rejection.
pub fn retryValidation(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: session.Session, context: p.Context, candidate: Candidate) Error!?retry.Transition {
    const pending = candidate.pending_repair orelse return null;
    const merged = candidate.last_repair orelse return error.InvalidSpecificationRepair;
    if (candidate.revision != merged.revision_after or !std.meta.eql(merged.retry orelse return error.InvalidSpecificationRepair, pending.permit)) return error.InvalidSpecificationRepair;
    try p.bind(a, validator, context);
    const target = try candidate.origins.currentTarget(pending.target, recordCount(candidate.response));
    const accepted = if (target) |selected| try targetValid(a, validator, context, try session.unit(current.completed), candidate.response, selected) else merged.operation == .delete;
    return .{ .validated = .{ .permit = pending.permit, .revision = candidate.revision, .result = if (accepted) .resolved else .recurring } };
}
fn targetValid(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, unit: g.Unit, response: g.Response, target: Target) Error!bool {
    const selected = try candidates.select(response, target);
    switch (target) {
        .provenance => _ = p.select(a, context, selected.provenance) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false,
        .value => |field| _ = p.checkAttributed(.model, a, validator, context, try candidates.attributedValue(.model, response, field.subject, field.field)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false,
        .record => |index| {
            if (unit != .records or std.meta.activeTag(selected.record.content) != unit.records) return false;
            const checked = p.checkRecord(.model, a, validator, context, selected.record) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
            for (response.content.records[0..index]) |record| {
                const sibling = p.checkRecord(.model, a, validator, context, record) catch |err| {
                    if (err == error.OutOfMemory) return error.OutOfMemory;
                    continue;
                };
                if (try g.equalContent(a, checked.content, sibling.content)) return false;
            }
        },
    }
    return true;
}

pub fn packet(allocator: std.mem.Allocator, current: session.Session, context: p.Context, authorization: Authorization) Error!*packets.Packet {
    const facts = try dependencies.capture(allocator, current, context, authorization.dependencies.candidate);
    defer allocator.free(facts.references.lineage.history);
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
    const contextual = try packets.withContext(candidates.ReadContext, allocator, base, "candidate", try candidates.readContext(authorization.dependencies.candidate.response, authorization.target));
    defer packets.release(contextual);
    return atomic.packet(allocator, authorization, contextual, .{ .bytes = definition }, authorization.dependencies.candidate.origins.at(.{ .target = authorization.target }));
}

pub fn parse(allocator: std.mem.Allocator, authorization: Authorization, packet_value: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(allocator, authorization, packet_value, bytes);
}

pub fn merge(allocator: std.mem.Allocator, current: session.Session, context: p.Context, candidate: Candidate, authorization: Authorization, proposed_replacement: ?Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!Candidate {
    const facts = try dependencies.capture(allocator, current, context, candidate);
    defer allocator.free(facts.references.lineage.history);
    var result = candidate;
    const merged = try atomic.checkMerge(allocator, try session.owner(allocator, current), candidate.revision, try candidates.select(candidate.response, authorization.target), facts, authorization, proposed_replacement, origin);
    result.revision = merged.revision_after;
    result.last_repair = merged;
    const permit = authorization.retry orelse return error.InvalidSpecificationRepair;
    result.pending_repair = .{ .permit = permit, .target = try candidate.origins.stableTarget(authorization.target, recordCount(candidate.response)) };
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
            result.origins = try candidate.origins.deleting(allocator, index, old.len);
        },
        .insert => return error.InvalidSpecificationRepair,
    }
    result.origins.repair_target_bound = permit.maximum_targets;
    return result;
}
