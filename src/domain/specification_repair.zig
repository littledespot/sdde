//! Authorize and apply one specification value, evidence or record repair.
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
    group: ?candidates.GroupPolicy = null,
};
const dependencies = @import("specification_candidate_context.zig");
const shared = @import("atomic_repair.zig");
const retry = @import("workflow_retry.zig");
const Family = enum { provenance, value, record, attributed, record_evidence };
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
        !std.meta.eql(candidate.origins.at(rejection.issue.field), rejection.origin)) return error.InvalidSpecificationRepair;
    if (rejection.issue.blocked != null and (rejection.issue.membership != null or rejection.issue.field == .target)) return error.UnsafeSpecificationRepair;
    if (rejection.issue.repair_target) |target| {
        const prior = candidate.group_repair orelse return error.InvalidSpecificationRepair;
        const active = (try candidate.origins.currentTarget(prior.target, recordCount(candidate.response))) orelse return error.InvalidSpecificationRepair;
        if (!std.meta.eql(active, target)) return error.InvalidSpecificationRepair;
        return authorizeGroup(allocator, owner, candidate, facts, target, prior.policy, rejection, false);
    }
    if (rejection.issue.membership != null) {
        if (candidate.response != .content or candidate.response.content != .records) return error.InvalidSpecificationRepair;
        const records = candidate.response.content.records;
        const decision = current.units[2].?.response.content.entities.disposition;
        const missing = decision == .required and rejection.issue.field == .unit;
        const target: Target = if (missing) .{ .record = records.len } else if (rejection.issue.field == .target and rejection.issue.field.target == .record) rejection.issue.field.target else return error.InvalidSpecificationRepair;
        if (missing) {
            for (records) |record| if (record.content == .entity) return error.InvalidSpecificationRepair;
        } else if (target.record >= records.len or decision != .not_applicable or records[target.record].content != .entity) return error.InvalidSpecificationRepair;
        return authorizeGroup(allocator, owner, candidate, facts, target, .{ .membership = .{ .disposition = decision, .fixed_provenance = if (missing) null else records[target.record].provenance } }, rejection, missing);
    }
    if (rejection.issue.field != .target) return error.InvalidSpecificationRepair;
    if (rejection.issue.blocked != null) return error.UnsafeSpecificationRepair;
    const expected = rejection.issue.observed orelse return error.InvalidSpecificationRepair;
    const target = rejection.issue.field.target;
    if (!try atomic.equal(allocator, try candidates.select(candidate.response, target), expected)) return error.InvalidSpecificationRepair;
    if (target == .value and rejection.issue.text_issue != null and rejection.issue.text_issue.?.reason == .unknown_exact) {
        const field = target.value;
        const value = try candidates.attributedValue(.model, candidate.response, field.subject, field.field);
        _ = try p.select(allocator, context, value.provenance);
        const pair = rejection.issue.text_issue.?.rejected_exact orelse return error.InvalidSpecificationRepair;
        if (try p.eligibleExactClaim(allocator, context, pair)) |claim| {
            if (!@import("reference_reconciliation.zig").contains(@import("reference_reconciliation.zig").ClaimId, value.provenance.claim_ids, claim)) {
                const coupled: Target = if (field.subject == .record) .{ .record = field.subject.record } else .{ .attributed = field.subject };
                const kind: ?g.spec.Kind = if (field.subject == .record) std.meta.activeTag(candidate.response.content.records[field.subject.record].content) else null;
                return authorizeGroup(allocator, owner, candidate, facts, coupled, .{ .evidence = .{ .record_kind = kind } }, rejection, false);
            }
        }
    }
    const rule: Rule = .{ .text_issue = rejection.issue.text_issue, .value_choices = rejection.issue.value_choices, .requirement = switch (rejection.issue.rule) {
        .provenance => "Select nonempty, unique currently retained claim IDs; clarification responses are unavailable in this generation context.",
        .typed_text, .exact_copy => if (rejection.issue.value_choices) |choices| try choices.correction(allocator, rejection.issue.text_issue orelse return error.InvalidSpecificationRepair) else (rejection.issue.text_issue orelse return error.InvalidSpecificationRepair).description(),
        .duplicate_record => "Remove only the evidence-equivalent redundant occurrence; preserve coverage and sibling order.",
        .entity_membership, .unit_kind, .interpretation => return error.UnsafeSpecificationRepair,
    } };
    var authorization = if (rejection.issue.rule == .duplicate_record)
        try atomic.authorizeDelete(allocator, owner, candidate.revision, target, expected, facts, rule)
    else
        try atomic.authorize(allocator, owner, candidate.revision, target, expected, facts, rule);
    authorization.retry = try retryPermit(allocator, authorization);
    return authorization;
}

fn authorizeGroup(a: std.mem.Allocator, owner: @import("model_request_identity.zig").ImmutableUnitOwnerId, candidate: Candidate, facts: dependencies.Facts, target: Target, policy: candidates.GroupPolicy, rejection: candidates.Rejection, insert: bool) Error!Authorization {
    const requirement = switch (policy) {
        .membership => |membership| if (insert)
            "Insert one source-backed entity required by the fixed applicability decision. Preserve all existing records."
        else if (membership.disposition == .not_applicable)
            "Replace only this record with source-backed non-entity content. Preserve its exact evidence selection, source obligations and all siblings."
        else
            "Return the complete corrected entity record, preserving its source meaning and all siblings.",
        .evidence => "Correct the selected content and its claim selection together. The rejected candidate misbound an available exact-copy reference. Express the source-backed behavior, cite each exact-copy's supporting claim, and preserve the record kind and all outside siblings. Return only the complete selected replacement.",
    };
    const rule: Rule = .{ .requirement = requirement, .text_issue = rejection.issue.text_issue, .value_choices = null, .group = policy };
    var authorization = if (insert)
        try atomic.authorizeInsert(a, owner, candidate.revision, target, .record, facts, rule)
    else
        try atomic.authorize(a, owner, candidate.revision, target, try candidates.select(candidate.response, target), facts, rule);
    authorization.retry = try retryPermit(a, authorization);
    return authorization;
}

pub fn retryPermit(a: std.mem.Allocator, authorization: Authorization) Error!retry.Permit {
    const candidate = authorization.dependencies.candidate;
    const target = try repairTarget(a, candidate, authorization);
    const bound = candidate.origins.repair_target_bound orelse try targetBound(candidate.response);
    const family: Family = switch (authorization.target) {
        .provenance => .provenance,
        .value => .value,
        .attributed => .attributed,
        .record => if (authorization.rule.group != null and authorization.rule.group.? == .evidence) .record_evidence else .record,
    };
    var permit = try shared.permit(candidates.StableTarget, Family, a, authorization.owner, target, family, authorization.id, authorization.revision, bound);
    const Scope = struct { owner: @import("model_request_identity.zig").ImmutableUnitOwnerId, origin: ?@import("model_candidate_origin.zig").Origin };
    permit.key.scope = if (candidate.pending_repair) |pending| pending.permit.key.scope else (try shared.snapshot(Scope, a, .{ .owner = authorization.owner, .origin = candidate.origins.initial })).bytes;
    return permit;
}

fn repairTarget(a: std.mem.Allocator, candidate: Candidate, authorization: Authorization) Error!candidates.StableTarget {
    var origins = candidate.origins;
    const length = recordCount(candidate.response);
    if (authorization.operation == .insert) {
        origins.record_occurrences = try origins.record_occurrences.inserting(a, authorization.target.record, length);
        defer a.free(origins.record_occurrences.values);
        return origins.stableTarget(authorization.target, length + 1);
    }
    return origins.stableTarget(authorization.target, length);
}

/// Keep an authorized coupled repair one bounded assignment even when its
/// next rejection moves between fields. Sibling defects retain their own targets.
pub fn retainGroupTarget(candidate: Candidate, result: *g.Validation) Error!void {
    const prior = candidate.group_repair orelse return;
    if (result.* != .invalid or result.invalid.field != .target) return;
    // Session membership is checked only after all field/evidence joins pass.
    // Let that distinct defect use its existing kind-changing authority once
    // the same-kind evidence repair has resolved.
    if (prior.policy == .evidence and (result.invalid.membership != null or result.invalid.rule == .duplicate_record)) return;
    const target = (try candidate.origins.currentTarget(prior.target, recordCount(candidate.response))) orelse return;
    if (candidates.contains(target, result.invalid.field.target)) result.invalid.repair_target = target;
}

fn recordCount(response: g.Response) usize {
    return if (response == .content and response.content == .records) response.content.records.len else 0;
}
fn targetBound(response: g.Response) Error!u32 {
    if (response != .content) return error.InvalidSpecificationRepair;
    var count: usize = 1; // One conditional insertion is a whole-record repair target.
    switch (response.content) {
        .brief => count = 9,
        .primary_user_story, .entities => count = 3,
        .records => |records| for (records) |record| {
            count = std.math.add(usize, count, 3) catch return error.InvalidSpecificationRepair;
            switch (record.content) {
                inline else => |fields| inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
                    count = std.math.add(usize, count, if (comptime field.type == g.spec.BusinessValue) 1 else @field(fields, field.name).len) catch return error.InvalidSpecificationRepair;
                },
            }
        },
    }
    return std.math.cast(u32, count) orelse error.InvalidSpecificationRepair;
}

/// Full unit validation still runs first. This checks the selected occurrence
/// even when a different sibling is now the unit validator's first rejection.
pub fn retryValidation(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, current: session.Session, context: p.Context, candidate: Candidate) Error!?retry.Transition {
    const pending = candidate.pending_repair orelse return null;
    if (candidate.response != .content or @intFromEnum(std.meta.activeTag(try session.unit(current.completed))) != @intFromEnum(std.meta.activeTag(candidate.response.content))) return error.InvalidSpecificationRepair;
    const merged = candidate.last_repair orelse return error.InvalidSpecificationRepair;
    if (candidate.revision != merged.revision_after or !std.meta.eql(merged.retry orelse return error.InvalidSpecificationRepair, pending.permit)) return error.InvalidSpecificationRepair;
    try p.bind(a, validator, context);
    const target = try candidate.origins.currentTarget(pending.target, recordCount(candidate.response));
    const accepted = if (target) |selected| try targetValid(a, validator, context, current, candidate, selected) else merged.operation == .delete;
    return .{ .validated = .{ .permit = pending.permit, .revision = candidate.revision, .result = if (accepted) .resolved else .recurring } };
}
fn targetValid(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, current: session.Session, candidate: Candidate, target: Target) Error!bool {
    const response = candidate.response;
    const selected = try candidates.select(response, target);
    switch (target) {
        .provenance => _ = p.select(a, context, selected.provenance) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false,
        .value => |field| _ = p.checkAttributed(.model, a, validator, context, try candidates.attributedValue(.model, response, field.subject, field.field)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false,
        .attributed => _ = p.checkAttributed(.model, a, validator, context, selected.attributed) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false,
        .record => {
            if (candidate.group_repair) |group| if (group.policy == .membership) {
                if (!g.spec.entityMembershipSatisfied(current.units[2].?.response.content.entities.disposition, @intFromBool(selected.record.content == .entity))) return false;
            };
            _ = p.checkRecord(.model, a, validator, context, selected.record) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
        },
    }
    return true;
}

pub fn packet(allocator: std.mem.Allocator, current: session.Session, context: p.Context, authorization: Authorization) Error!*packets.Packet {
    const facts = try dependencies.capture(allocator, current, context, authorization.dependencies.candidate);
    defer allocator.free(facts.references.lineage.history);
    try atomic.checkDependencies(allocator, authorization, facts);
    const unit = try session.unit(current.completed);
    if (authorization.operation == .delete) return error.InvalidSpecificationRepair;
    const kind = if (authorization.operation == .replace) std.meta.activeTag(authorization.operation.replace) else authorization.operation.insert;
    if (kind == .record and unit != .records) return error.InvalidSpecificationRepair;
    const base = try session.packet(allocator, current, context);
    defer packets.release(base);
    const definition = switch (kind) {
        .provenance => "provenance",
        .value => "value",
        .attributed => "attributed_value",
        .record => switch (authorization.rule.group orelse return error.InvalidSpecificationRepair) {
            .membership => |membership| if (membership.disposition == .required) "repair_record_entity" else "repair_record_non_entity",
            .evidence => "record",
        },
    };
    if (authorization.operation == .insert) return atomic.packet(allocator, authorization, base, .{ .bytes = definition }, authorization.dependencies.candidate.origins.initial);
    // current_value already carries the whole selected record. Containing-field
    // context is needed only when a smaller value/provenance selection is writable.
    if (kind == .record or kind == .attributed) {
        if (kind == .record and authorization.rule.group.? == .evidence) {
            const selected_kind = authorization.rule.group.?.evidence.record_kind orelse return error.InvalidSpecificationRepair;
            var excluded: std.ArrayList(@import("model_result_schema.zig").ExcludedVariant) = .empty;
            defer excluded.deinit(allocator);
            try excluded.appendSlice(allocator, base.excludedVariants());
            for (std.enums.values(g.spec.Kind)) |record_kind| if (record_kind != selected_kind) {
                try excluded.append(allocator, .{ .kind = @tagName(record_kind) });
            };
            const narrowed = try packets.withExcludedVariants(allocator, base, excluded.items);
            defer packets.release(narrowed);
            return atomic.packet(allocator, authorization, narrowed, .{ .bytes = definition }, authorization.dependencies.candidate.origins.at(.{ .target = authorization.target }));
        }
        const fixed = if (authorization.rule.group) |group| (if (group == .membership) group.membership.fixed_provenance else null) else null;
        const narrowed = if (fixed) |selection|
            try session.withSelectionChoices(allocator, base, context, selection)
        else
            try packets.withExcludedVariants(allocator, base, base.excludedVariants());
        defer packets.release(narrowed);
        return atomic.packet(allocator, authorization, narrowed, .{ .bytes = definition }, authorization.dependencies.candidate.origins.at(.{ .target = authorization.target }));
    }
    if (kind == .value) {
        const value = try candidates.attributedValue(.model, authorization.dependencies.candidate.response, authorization.target.value.subject, authorization.target.value.field);
        // The rejected value is already in current_value; only its pinned
        // provenance is needed as containing-field context.
        const contextual = if (authorization.target.value.subject == .record)
            try packets.withContext(candidates.ReadContext, allocator, base, "candidate", try candidates.readContext(authorization.dependencies.candidate.response, authorization.target))
        else
            try packets.withContext(g.spec.Selection, allocator, base, "provenance", value.provenance);
        defer packets.release(contextual);
        const narrowed = try session.withSelectionChoices(allocator, contextual, context, value.provenance);
        defer packets.release(narrowed);
        return atomic.packet(allocator, authorization, narrowed, .{ .bytes = definition }, authorization.dependencies.candidate.origins.at(.{ .target = authorization.target }));
    }
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
    const prior_value = if (authorization.operation == .insert) null else try candidates.select(candidate.response, authorization.target);
    const merged = try atomic.checkMerge(allocator, try session.owner(allocator, current), candidate.revision, prior_value, facts, authorization, proposed_replacement, origin);
    if (authorization.rule.group) |group| {
        const proposed = proposed_replacement orelse return error.InvalidSpecificationRepair;
        switch (group) {
            .membership => |membership| {
                if (proposed != .record or !g.spec.entityMembershipSatisfied(membership.disposition, @intFromBool(proposed.record.content == .entity))) return error.InvalidSpecificationRepair;
                if (membership.fixed_provenance) |fixed| if (!try atomic.equal(allocator, .{ .provenance = fixed }, .{ .provenance = proposed.record.provenance })) return error.InvalidSpecificationRepair;
            },
            .evidence => |evidence| if (evidence.record_kind) |kind| {
                if (proposed != .record or std.meta.activeTag(proposed.record.content) != kind) return error.InvalidSpecificationRepair;
            } else if (proposed != .attributed) return error.InvalidSpecificationRepair,
        }
    }
    result.revision = merged.revision_after;
    result.last_repair = merged;
    const permit = authorization.retry orelse return error.InvalidSpecificationRepair;
    result.pending_repair = .{ .permit = permit, .target = try repairTarget(allocator, candidate, authorization) };
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
        .insert => {
            if (authorization.target != .record or (authorization.rule.group == null or authorization.rule.group.? != .membership or authorization.rule.group.?.membership.disposition != .required) or authorization.target.record != recordCount(candidate.response)) return error.InvalidSpecificationRepair;
            const old_records = candidate.response.content.records;
            const records = try allocator.alloc(g.spec.Model.RecordProposal, old_records.len + 1);
            @memcpy(records[0..old_records.len], old_records);
            records[old_records.len] = (try atomic.copyReplacement(allocator, proposed_replacement.?)).record;
            result.response.content.records = records;
            result.origins = try candidate.origins.replacing(allocator, authorization.target, origin);
            result.origins.record_occurrences = try candidate.origins.record_occurrences.inserting(allocator, old_records.len, old_records.len);
        },
    }
    if (authorization.rule.group) |group| result.group_repair = .{ .target = result.pending_repair.?.target, .policy = group };
    result.origins.repair_target_bound = permit.maximum_targets;
    return result;
}
