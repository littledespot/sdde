//! One reference-grounded business unit. No Markdown, paths, IDs, status,
//! provider calls, default content or semantic-success policy.
//! Normalized values use the caller's arena; provenance and reference inputs
//! must remain retained by that caller.
const std = @import("std");
pub const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");
pub const Error = provenance.Error || error{InvalidSpecificationUnit};
pub const Unit = @import("specification_source_binding.zig").Unit;
pub const Brief = spec.Brief;
pub fn Responses(comptime boundary: spec.Boundary) type {
    const fields = spec.Values(boundary);
    return struct {
        const Self = @This();
        pub const Entities = struct {
            disposition: spec.Applicability,
            basis: fields.AttributedValue,
            records: []const fields.RecordProposal = &.{},

            pub fn decision(self: @This()) fields.ApplicabilityProposal {
                return .{ .disposition = self.disposition, .basis = self.basis };
            }
        };
        pub const Need = struct { reason: NeedReason, question: fields.AttributedValue, record_kind: ?spec.Kind = null };
        pub const Content = union(enum) {
            brief: fields.Brief,
            primary_user_story: fields.AttributedValue,
            entities: Self.Entities,
            records: []const fields.RecordProposal,
        };
        pub const Response = union(enum) { content: Self.Content, clarification: Self.Need, inconclusive: Inconclusive };
    };
}
pub const Inconclusive = struct { detail: []const u8 };
const NeedReason = enum { missing, ambiguous, conflicting };
pub const Need = Responses(.model).Need;
pub const Content = Responses(.model).Content;
pub const Response = Responses(.model).Response;
pub const CanonicalResponse = Responses(.canonical).Response;
/// Record indices are local to their native owning unit. Entity records belong
/// only to the feature-wide entities unit, never a source-group record batch.
pub fn recordCollection(comptime boundary: spec.Boundary, content: Responses(boundary).Content) ?[]const spec.Values(boundary).RecordProposal {
    return switch (content) {
        .entities => |entities| entities.records,
        .records => |records| records,
        .brief, .primary_user_story => null,
    };
}
pub fn recordCollectionPtr(comptime boundary: spec.Boundary, content: *Responses(boundary).Content) ?*[]const spec.Values(boundary).RecordProposal {
    return switch (content.*) {
        .entities => &content.entities.records,
        .records => &content.records,
        .brief, .primary_user_story => null,
    };
}
pub const RecordAssignment = struct {
    reference_state: @import("reference_identity.zig").StateId,
    group_index: usize,
    source_group_id: @import("reference_reconciliation.zig").SignalId,
    references: @import("atomic_repair.zig").Snapshot,
};
pub const Checked = struct { unit: Unit, response: CanonicalResponse, origins: candidate.Origins = .{}, last_repair: ?@import("atomic_repair.zig").Merge = null, record_assignment: ?RecordAssignment = null };
const candidate = @import("specification_candidate.zig");
pub const Validation = union(enum) { valid: Checked, invalid: candidate.Issue };

/// Initial authoring owns its supporting-group choice; repair remains value-only.
pub const AuthoringValue = struct { value: spec.BusinessValue, signal_ids: []const @import("reference_reconciliation.zig").SignalId };
pub const AuthoringEntity = struct { content: spec.Content(spec.BusinessValue), signal_ids: []const @import("reference_reconciliation.zig").SignalId };
/// A non-entity record names the claims it supports from its batch's group (ADR 0038).
pub const AuthoringRecord = struct { content: spec.Content(spec.BusinessValue), claim_ids: []const @import("reference_identity.zig").ClaimId };
pub const ModelResponse = union(enum) {
    pub const model_fields = .{ .primary_user_story = @import("text_field_policy.zig").Field.spec_story };
    brief: struct {
        pub const model_fields = .{ .title = @import("text_field_policy.zig").Field.spec_title, .description = @import("text_field_policy.zig").Field.spec_description, .primary_goal = @import("text_field_policy.zig").Field.spec_goal };
        title: AuthoringValue,
        description: AuthoringValue,
        primary_goal: AuthoringValue,
    },
    primary_user_story: AuthoringValue,
    entities: struct {
        pub const model_fields = .{ .basis = @import("text_field_policy.zig").Field.spec_entity_basis };
        disposition: spec.Applicability,
        basis: AuthoringValue,
        records: []const AuthoringEntity,
    },
    records: struct { records: []const AuthoringRecord },
    clarification: struct {
        pub const model_fields = .{ .question = @import("text_field_policy.zig").Field.clarification_question };
        reason: NeedReason,
        question: AuthoringValue,
        record_kind: ?spec.Kind = null,
    },
    inconclusive: Inconclusive,

    pub fn from(allocator: std.mem.Allocator, context: provenance.Context, response: Response) Error!ModelResponse {
        return switch (response) {
            .clarification => |need| .{ .clarification = .{ .reason = need.reason, .question = try wireValue(allocator, context, need.question), .record_kind = need.record_kind } },
            .inconclusive => |failure| .{ .inconclusive = failure },
            .content => |content| switch (content) {
                .brief => |brief| .{ .brief = .{ .title = try wireValue(allocator, context, brief.title), .description = try wireValue(allocator, context, brief.description), .primary_goal = try wireValue(allocator, context, brief.primary_goal) } },
                .primary_user_story => |story| .{ .primary_user_story = try wireValue(allocator, context, story) },
                .entities => |entities| entity: {
                    const records = try allocator.alloc(AuthoringEntity, entities.records.len);
                    for (entities.records, records) |record, *wire| wire.* = .{ .content = try provenance.modelRecord(allocator, @import("reference_support.zig").records(context.references), record.content), .signal_ids = record.source_group_ids };
                    break :entity .{ .entities = .{ .disposition = entities.disposition, .basis = try wireValue(allocator, context, entities.basis), .records = records } };
                },
                .records => |records| blk: {
                    const projected = try allocator.alloc(AuthoringRecord, records.len);
                    for (records, projected) |record, *wire| wire.* = .{ .content = try provenance.modelRecord(allocator, @import("reference_support.zig").records(context.references), record.content), .claim_ids = record.provenance.claim_ids };
                    break :blk .{ .records = .{ .records = projected } };
                },
            },
        };
    }
};
fn wireValue(a: std.mem.Allocator, context: provenance.Context, value: spec.Values(.model).AttributedValue) Error!AuthoringValue {
    return .{ .value = try provenance.modelValue(a, @import("reference_support.zig").records(context.references), value.value), .signal_ids = value.source_group_ids };
}
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8, bound: @import("specification_source_binding.zig").Bound) Error!Response {
    const response = @import("model_candidate_json.zig").decode(ModelResponse, allocator, bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    const available = switch (bound) {
        .brief => |value| value,
        .primary_user_story => |value| value,
        .entities => |value| value,
        .records => |value| value.catalogue,
    };
    return switch (response) {
        .clarification => |need| clarification: {
            if (bound == .records and (need.question.signal_ids.len != 1 or need.question.signal_ids[0].ordinal != bound.records.signal.ordinal)) return error.InvalidSpecificationUnit;
            break :clarification .{ .clarification = .{ .reason = need.reason, .question = try associated(allocator, available, need.question, .question), .record_kind = need.record_kind } };
        },
        .inconclusive => |failure| .{ .inconclusive = failure },
        .brief => |brief| if (bound == .brief) .{ .content = .{ .brief = .{ .title = try associated(allocator, available, brief.title, .content), .description = try associated(allocator, available, brief.description, .content), .primary_goal = try associated(allocator, available, brief.primary_goal, .content) } } } else error.InvalidSpecificationUnit,
        .primary_user_story => |story| if (bound == .primary_user_story) .{ .content = .{ .primary_user_story = try associated(allocator, available, story, .content) } } else error.InvalidSpecificationUnit,
        .entities => |entities| if (bound == .entities) entity: {
            const records = try allocator.alloc(spec.Model.RecordProposal, entities.records.len);
            for (entities.records, records) |wire, *record| {
                if (wire.content != .entity) return error.InvalidSpecificationUnit;
                const selected = @import("specification_source_binding.zig").resolveGroups(allocator, available.records, available.inputs, wire.signal_ids, .content) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
                record.* = .{ .content = wire.content, .source_group_ids = selected.source_group_ids, .provenance = selected.selection };
            }
            break :entity .{ .content = .{ .entities = .{ .disposition = entities.disposition, .basis = try associated(allocator, available, entities.basis, .content), .records = records } } };
        } else error.InvalidSpecificationUnit,
        .records => |batch| if (bound == .records) records: {
            const records = try allocator.alloc(spec.Values(.model).RecordProposal, batch.records.len);
            const ids = try allocator.dupe(@import("reference_reconciliation.zig").SignalId, &.{bound.records.signal});
            for (batch.records, records) |wire, *record| {
                if (wire.content == .entity) return error.InvalidSpecificationUnit;
                record.* = .{ .content = wire.content, .source_group_ids = ids, .provenance = .{ .claim_ids = try groupSubset(allocator, bound.records.selection.claim_ids, wire.claim_ids), .clarification_response_ids = bound.records.selection.clarification_response_ids } };
            }
            break :records .{ .content = .{ .records = records } };
        } else error.InvalidSpecificationUnit,
    };
}
/// The named claims in the group's accepted order. Each must belong to the group,
/// once; model order never becomes canonical order.
fn groupSubset(a: std.mem.Allocator, group: []const @import("reference_identity.zig").ClaimId, named: []const @import("reference_identity.zig").ClaimId) Error![]const @import("reference_identity.zig").ClaimId {
    if (named.len == 0) return error.InvalidSpecificationUnit;
    @import("reference_reconciliation.zig").unique(@import("reference_identity.zig").ClaimId, named) catch return error.InvalidSpecificationUnit;
    var selected: std.ArrayList(@import("reference_identity.zig").ClaimId) = .empty;
    errdefer selected.deinit(a);
    for (group) |id| if (@import("reference_reconciliation.zig").contains(@import("reference_identity.zig").ClaimId, named, id)) try selected.append(a, id);
    if (selected.items.len != named.len) return error.InvalidSpecificationUnit;
    return selected.toOwnedSlice(a);
}
fn associated(a: std.mem.Allocator, available: @import("specification_source_binding.zig").Catalogue, value: AuthoringValue, mode: @import("specification_source_binding.zig").Mode) Error!spec.Values(.model).AttributedValue {
    const selected = @import("specification_source_binding.zig").resolveGroups(a, available.records, available.inputs, value.signal_ids, mode) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    return .{ .value = value.value, .source_group_ids = selected.source_group_ids, .provenance = selected.selection };
}

pub fn validate(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: Response) Error!Validation {
    return check(.model, allocator, validator, context, unit, proposed);
}

/// Full candidate validation retains the native value-repair evidence bound.
/// Recognition during revalidation cannot widen a previously authorized S+E.
pub fn validateCandidate(a: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: candidate.Candidate) Error!Validation {
    if (proposed.group_repair != null and unit != .entities) return error.InvalidSpecificationUnit;
    const result = try validate(a, validator, context, unit, proposed.response);
    if (result != .valid) return result;
    if (proposed.group_repair) |group| if (group.policy.membership.evidence_bound) |bound| {
        var scratch_arena: std.heap.ArenaAllocator = .init(a);
        defer scratch_arena.deinit();
        const scratch_allocator = scratch_arena.allocator();
        const count = if (proposed.response == .content) (if (recordCollection(.model, proposed.response.content)) |entries| entries.len else 0) else 0;
        const selected = (proposed.origins.currentTarget(group.target, count) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit) orelse return error.InvalidSpecificationUnit;
        if (selected != .record or result.valid.response != .content) return error.InvalidSpecificationUnit;
        const record = (recordCollection(.canonical, result.valid.response.content) orelse return error.InvalidSpecificationUnit)[selected.record];
        {
            const fixed = group.policy.membership.fixed_provenance;
            if (fixed.claim_ids.len != record.provenance.claim_ids.len) return error.InvalidSpecificationUnit;
            for (fixed.claim_ids, record.provenance.claim_ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecificationUnit;
            if (fixed.clarification_response_ids.len != record.provenance.clarification_response_ids.len) return error.InvalidSpecificationUnit;
            for (fixed.clarification_response_ids, record.provenance.clarification_response_ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecificationUnit;
        }
        const groups = group.policy.membership.fixed_source_group_ids;
        if (groups.len != record.source_group_ids.len) return error.InvalidSpecificationUnit;
        for (groups, record.source_group_ids) |expected, actual| if (expected.ordinal != actual.ordinal) return error.InvalidSpecificationUnit;
        const resolved = try provenance.lineageForRepair(scratch_allocator, context, .{ .claim_ids = record.provenance.claim_ids, .clarification_response_ids = record.provenance.clarification_response_ids }, try provenance.recordValues(scratch_allocator, record.content));
        const r = @import("reference_reconciliation.zig");
        r.sameSet(r.ClaimId, bound.effective, resolved.effective_claim_ids) catch return error.InvalidSpecificationUnit;
        r.sameSet(r.CitationId, bound.citations, resolved.provenance.citation_ids) catch return error.InvalidSpecificationUnit;
    };
    const bound = proposed.value_bound orelse return result;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const length = if (proposed.response == .content) (if (recordCollection(.model, proposed.response.content)) |entries| entries.len else 0) else 0;
    const target = (proposed.origins.currentTarget(bound.target, length) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit) orelse return error.InvalidSpecificationUnit;
    if (target != .value) return error.InvalidSpecificationUnit;
    const value = candidate.attributedValue(.canonical, result.valid.response, target.value.subject, target.value.field) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    const values = if (target.value.subject == .record) try provenance.recordValues(scratch, (recordCollection(.canonical, result.valid.response.content) orelse return error.InvalidSpecificationUnit)[target.value.subject.record].content) else &.{value.value};
    const resolved = try provenance.lineageForRepair(scratch, context, .{ .claim_ids = value.provenance.claim_ids, .clarification_response_ids = value.provenance.clarification_response_ids }, values);
    if (resolved.provenance.claim_ids.len != bound.explicit.len) return error.InvalidSpecificationUnit;
    for (resolved.provenance.claim_ids, bound.explicit) |actual, expected| if (actual.ordinal != expected.ordinal) return error.InvalidSpecificationUnit;
    const r = @import("reference_reconciliation.zig");
    r.sameSet(r.ClaimId, bound.effective, resolved.effective_claim_ids) catch return error.InvalidSpecificationUnit;
    r.sameSet(r.CitationId, bound.citations, resolved.provenance.citation_ids) catch return error.InvalidSpecificationUnit;
    return result;
}

/// Revalidate complete canonical evidence; never erase and regenerate a corrupt union.
pub fn revalidate(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: CanonicalResponse) Error!Validation {
    return check(.canonical, allocator, validator, context, unit, proposed);
}

fn check(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: Responses(boundary).Response) Error!Validation {
    try provenance.bind(allocator, validator, context);
    var inspection: provenance.Inspection = .{};
    const result: CanonicalResponse = switch (proposed) {
        .inconclusive => |failure| return .{ .invalid = .{ .unit = unit, .field = .interpretation, .rule = .interpretation, .observed = null, .blocked = .inconclusive_review, .detail = failure.detail } },
        .clarification => |need| need: {
            if ((unit == .records) != (need.record_kind != null) or (unit == .records and need.record_kind == .entity)) return .{ .invalid = .{ .unit = unit, .field = .clarification_question, .rule = .unit_kind, .observed = null, .blocked = .clarification_question } };
            break :need .{ .clarification = .{
                .reason = need.reason,
                .record_kind = need.record_kind,
                .question = inspectAuthored(boundary, allocator, validator, context, need.question, .clarification_question, .question, &inspection) catch |err| return rejected(unit, .clarification_question, null, inspection.text_issue, err),
            } };
        },
        .content => |content| blk: {
            if (@intFromEnum(std.meta.activeTag(unit)) != @intFromEnum(std.meta.activeTag(content))) return .{ .invalid = .{ .unit = unit, .field = .unit, .rule = .unit_kind, .observed = null, .blocked = .unit_kind } };
            break :blk .{ .content = switch (content) {
                .brief => |brief| .{ .brief = .{
                    .title = inspectAuthored(boundary, allocator, validator, context, brief.title, .spec_title, .content, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .title, inspection, err),
                    .description = inspectAuthored(boundary, allocator, validator, context, brief.description, .spec_description, .content, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .description, inspection, err),
                    .primary_goal = inspectAuthored(boundary, allocator, validator, context, brief.primary_goal, .spec_goal, .content, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .primary_goal, inspection, err),
                } },
                .primary_user_story => |story| .{ .primary_user_story = inspectAuthored(boundary, allocator, validator, context, story, .spec_story, .content, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .story, inspection, err) },
                .entities => |entities| entity: {
                    const basis = inspectAuthored(boundary, allocator, validator, context, entities.basis, .spec_entity_basis, .content, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .entity_basis, inspection, err);
                    const records = try inspectRecords(boundary, allocator, validator, context, unit, proposed, entities.records, &inspection);
                    if (records == .invalid) return .{ .invalid = records.invalid };
                    if (!spec.entityMembershipSatisfied(entities.disposition, records.valid.len)) return .{ .invalid = .{
                        .unit = .entities,
                        .field = if (records.valid.len == 0) .unit else .{ .target = .{ .record = 0 } },
                        .rule = .entity_membership,
                        .observed = null,
                        .membership = .{ .disposition = entities.disposition, .entity_count = records.valid.len },
                        .detail = if (records.valid.len == 0) "The fixed entity decision requires at least one source-backed entity record." else "Entity records contradict the fixed not_applicable decision.",
                    } };
                    break :entity .{ .entities = .{
                        .disposition = entities.disposition,
                        .basis = basis,
                        .records = records.valid,
                    } };
                },
                .records => |records| records: {
                    const checked = try inspectRecords(boundary, allocator, validator, context, unit, proposed, records, &inspection);
                    if (checked == .invalid) return .{ .invalid = checked.invalid };
                    break :records .{ .records = checked.valid };
                },
            } };
        },
    };
    return .{ .valid = .{ .unit = unit, .response = result } };
}

fn inspectRecords(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: Responses(boundary).Response, records: []const spec.Values(boundary).RecordProposal, inspection: *provenance.Inspection) Error!union(enum) { valid: []const spec.RecordProposal, invalid: candidate.Issue } {
    const checked = try allocator.alloc(spec.RecordProposal, records.len);
    for (records, checked, 0..) |record, *accepted, index| {
        if ((unit == .entities) != (record.content == .entity)) return .{ .invalid = .{ .unit = unit, .field = .{ .target = .{ .record = index } }, .rule = .unit_kind, .observed = null, .blocked = .unit_kind } };
        const observed: ?candidate.Replacement = if (boundary == .model) .{ .record = record } else null;
        accepted.* = provenance.inspectRecord(boundary, allocator, validator, context, record, inspection) catch |err| {
            const rejected_result = try rejectedPart(boundary, unit, proposed, .{ .record = index }, inspection.*, err);
            return .{ .invalid = rejected_result.invalid };
        };
        for (checked[0..index]) |prior| if (try duplicateRecordIssue(allocator, prior, accepted.*, index, observed)) |issue| {
            var owning_issue = issue;
            owning_issue.unit = unit;
            return .{ .invalid = owning_issue };
        };
    }
    return .{ .valid = checked };
}

// Every authored value retains an explicit group occurrence and the owning
// field's composition policy. Prose presence does not establish semantic truth.
fn inspectAuthored(comptime boundary: spec.Boundary, allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, value: spec.Values(boundary).AttributedValue, field: @import("text_field_policy.zig").Field, mode: @import("specification_source_binding.zig").Mode, inspection: *provenance.Inspection) provenance.Error!spec.AttributedValue {
    inspection.* = .{};
    if (value.source_group_ids.len == 0) return error.InvalidSpecification;
    return provenance.inspectAttributedFor(boundary, allocator, validator, context, value, field, mode, inspection);
}

/// Equality over normalized typed content, never a second rendered text source.
pub fn equalContent(allocator: std.mem.Allocator, a: spec.Content(spec.BusinessValue), b: spec.Content(spec.BusinessValue)) std.mem.Allocator.Error!bool {
    return equalTyped(spec.Content(spec.BusinessValue), allocator, a, b);
}
fn equalTyped(comptime T: type, allocator: std.mem.Allocator, a: T, b: T) std.mem.Allocator.Error!bool {
    const left = try std.json.Stringify.valueAlloc(allocator, a, .{});
    defer allocator.free(left);
    const right = try std.json.Stringify.valueAlloc(allocator, b, .{});
    defer allocator.free(right);
    return std.mem.eql(u8, left, right);
}

/// The same duplicate rule applies inside a batch and against earlier batches.
pub fn duplicateRecordIssue(allocator: std.mem.Allocator, prior: spec.RecordProposal, current: spec.RecordProposal, index: usize, observed: ?candidate.Replacement) Error!?candidate.Issue {
    if (!try equalContent(allocator, prior.content, current.content)) return null;
    return .{ .unit = .records, .field = .{ .target = .{ .record = index } }, .rule = .duplicate_record, .observed = observed, .blocked = if (sameGroups(prior.source_group_ids, current.source_group_ids) and try equalEvidence(allocator, prior.provenance, current.provenance)) null else .competing_records };
}

/// The one statement of a single-statement record kind. Acceptance criteria,
/// edge cases and entities compare only as whole same-kind content.
pub fn statement(content: spec.Content(spec.BusinessValue)) ?spec.BusinessValue {
    return switch (content) {
        .acceptance_criterion, .edge_case, .entity => null,
        inline .user_visible_outcome, .functional_requirement, .business_rule, .assumption, .non_goal, .prohibited_behavior => |value| value.text,
    };
}

/// ADR 0035: identical statements in two single-statement kinds are redundant
/// only when the kept occurrence covers the other's evidence. A functional
/// requirement is always kept; otherwise the earlier occurrence is.
pub fn restatement(allocator: std.mem.Allocator, earlier: spec.RecordProposal, later: spec.RecordProposal) Error!?enum { earlier, later } {
    if (std.meta.activeTag(earlier.content) == std.meta.activeTag(later.content)) return null;
    const earlier_statement = statement(earlier.content) orelse return null;
    const later_statement = statement(later.content) orelse return null;
    if (!try equalTyped(spec.BusinessValue, allocator, earlier_statement, later_statement)) return null;
    if (later.content == .functional_requirement) {
        return if (coversEvidence(later.source_group_ids, later.provenance, earlier.source_group_ids, earlier.provenance)) .earlier else null;
    }
    return if (coversEvidence(earlier.source_group_ids, earlier.provenance, later.source_group_ids, later.provenance)) .later else null;
}

/// ADR 0035: a record restates the primary user story when its statement equals
/// the story and the story covers its evidence. The story is never removed, and
/// a functional requirement is always kept.
pub fn restatesStory(allocator: std.mem.Allocator, story: spec.AttributedValue, record: spec.RecordProposal) Error!bool {
    if (record.content == .functional_requirement) return false;
    const record_statement = statement(record.content) orelse return false;
    if (!try equalTyped(spec.BusinessValue, allocator, story.value, record_statement)) return false;
    return coversEvidence(story.source_group_ids, story.provenance, record.source_group_ids, record.provenance);
}

/// A covered restatement; its repair is a native delete with no model call.
pub fn restatementIssue(index: usize, observed: ?candidate.Replacement) candidate.Issue {
    return .{ .unit = .records, .field = .{ .target = .{ .record = index } }, .rule = .restatement, .observed = observed };
}

/// The kept occurrence cites every group, claim, citation and clarification
/// response the removed one cites.
fn coversEvidence(kept_groups: []const @import("reference_reconciliation.zig").SignalId, kept: spec.Provenance, removed_groups: []const @import("reference_reconciliation.zig").SignalId, removed: spec.Provenance) bool {
    return covers(@import("reference_reconciliation.zig").SignalId, kept_groups, removed_groups) and
        covers(@import("reference_reconciliation.zig").ClaimId, kept.claim_ids, removed.claim_ids) and
        covers(@import("reference_extraction.zig").CitationId, kept.citation_ids, removed.citation_ids) and
        covers(spec.ResponseId, kept.clarification_response_ids, removed.clarification_response_ids);
}
fn covers(comptime Id: type, kept: []const Id, removed: []const Id) bool {
    for (removed) |id| if (!@import("reference_reconciliation.zig").contains(Id, kept, id)) return false;
    return true;
}

fn rejected(unit: Unit, field: candidate.Field, observed: ?candidate.Replacement, text_issue: ?@import("typed_text.zig").Issue, err: provenance.Error) Error!Validation {
    if (text_issue == null) switch (err) {
        error.InvalidTypedText, error.InvalidPassiveLiteral => return err,
        else => {},
    };
    const native: @FieldType(candidate.Issue, "native_error") = switch (err) {
        error.InvalidSpecification => .InvalidSpecification,
        error.InvalidReferenceReconciliation => .InvalidReferenceReconciliation,
        error.InvalidSourceCitation => .InvalidSourceCitation,
        error.InvalidTypedText => .InvalidTypedText,
        error.InvalidPassiveLiteral => .InvalidPassiveLiteral,
        else => return err,
    };
    return .{ .invalid = .{ .unit = unit, .field = field, .observed = observed, .native_error = native, .text_issue = text_issue, .blocked = if (field == .clarification_question) .clarification_question else null, .rule = switch (native.?) {
        .InvalidSpecification, .InvalidReferenceReconciliation, .InvalidSourceCitation => .provenance,
        .InvalidTypedText, .InvalidPassiveLiteral => .typed_text,
    } } };
}

fn sameGroups(left: []const @import("reference_reconciliation.zig").SignalId, right: []const @import("reference_reconciliation.zig").SignalId) bool {
    if (left.len != right.len) return false;
    for (left, right) |expected, actual| if (expected.ordinal != actual.ordinal) return false;
    return true;
}
fn equalEvidence(a: std.mem.Allocator, left: spec.Provenance, right: spec.Provenance) std.mem.Allocator.Error!bool {
    return equalTyped(spec.Provenance, a, left, right);
}
fn rejectedPart(comptime boundary: spec.Boundary, unit: Unit, response: Responses(boundary).Response, subject: candidate.Subject, inspection: provenance.Inspection, err: provenance.Error) Error!Validation {
    const target = candidate.locate(subject, inspection.part);
    const observed = if (boundary == .model) candidate.select(response, target) catch return error.InvalidSpecificationUnit else null;
    var result = try rejected(unit, .{ .target = target }, observed, inspection.text_issue, err);
    result.invalid.value_choices = inspection.value_choices;
    if (inspection.part == .value and (result.invalid.rule == .provenance or (inspection.text_issue != null and inspection.text_issue.?.reason == .unknown_exact))) result.invalid.rule = .exact_copy;
    return result;
}
