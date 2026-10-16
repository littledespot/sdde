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
        pub const Need = struct { reason: NeedReason, question: fields.AttributedValue, record_kind: ?spec.Kind = null };
        pub const Content = union(enum) {
            brief: fields.Brief,
            primary_user_story: fields.AttributedValue,
            entities: fields.ApplicabilityProposal,
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
    },
    records: struct { records: []const spec.Wire.RecordProposal },
    clarification: struct {
        pub const model_fields = .{ .question = @import("text_field_policy.zig").Field.clarification_question };
        reason: NeedReason,
        question: AuthoringValue,
        record_kind: ?spec.Kind = null,
    },
    inconclusive: Inconclusive,

    pub fn from(allocator: std.mem.Allocator, response: Response) std.mem.Allocator.Error!ModelResponse {
        return switch (response) {
            .clarification => |need| .{ .clarification = .{ .reason = need.reason, .question = wireValue(need.question), .record_kind = need.record_kind } },
            .inconclusive => |failure| .{ .inconclusive = failure },
            .content => |content| switch (content) {
                .brief => |brief| .{ .brief = .{ .title = wireValue(brief.title), .description = wireValue(brief.description), .primary_goal = wireValue(brief.primary_goal) } },
                .primary_user_story => |story| .{ .primary_user_story = wireValue(story) },
                .entities => |entities| .{ .entities = .{ .disposition = entities.disposition, .basis = wireValue(entities.basis) } },
                .records => |records| blk: {
                    const projected = try allocator.alloc(spec.Wire.RecordProposal, records.len);
                    for (records, projected) |record, *wire| wire.* = .{ .content = record.content };
                    break :blk .{ .records = .{ .records = projected } };
                },
            },
        };
    }
};
fn wireValue(value: spec.Values(.model).AttributedValue) AuthoringValue {
    return .{ .value = value.value, .signal_ids = value.source_group_ids };
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
        .entities => |entities| if (bound == .entities) .{ .content = .{ .entities = .{ .disposition = entities.disposition, .basis = try associated(allocator, available, entities.basis, .content) } } } else error.InvalidSpecificationUnit,
        .records => |batch| if (bound == .records) records: {
            const records = try allocator.alloc(spec.Values(.model).RecordProposal, batch.records.len);
            const ids = try allocator.dupe(@import("reference_reconciliation.zig").SignalId, &.{bound.records.signal});
            for (batch.records, records) |wire, *record| record.* = .{ .content = wire.content, .source_group_ids = ids, .provenance = bound.records.selection };
            break :records .{ .content = .{ .records = records } };
        } else error.InvalidSpecificationUnit,
    };
}
fn associated(a: std.mem.Allocator, available: @import("specification_source_binding.zig").Catalogue, value: AuthoringValue, mode: @import("specification_source_binding.zig").Mode) Error!spec.Values(.model).AttributedValue {
    const selected = @import("specification_source_binding.zig").resolveGroups(a, available.records, available.inputs, value.signal_ids, mode) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    return .{ .value = value.value, .source_group_ids = selected.source_group_ids, .provenance = selected.selection };
}

pub fn validate(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: Response) Error!Validation {
    return check(.model, allocator, validator, context, unit, proposed);
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
            if ((unit == .records) != (need.record_kind != null)) return .{ .invalid = .{ .unit = unit, .field = .clarification_question, .rule = .unit_kind, .observed = null, .blocked = .clarification_question } };
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
                .entities => |entities| .{ .entities = .{
                    .disposition = entities.disposition,
                    .basis = inspectAuthored(boundary, allocator, validator, context, entities.basis, .spec_entity_basis, .content, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .entity_basis, inspection, err),
                } },
                .records => |records| records: {
                    const checked = try allocator.alloc(spec.RecordProposal, records.len);
                    for (records, checked, 0..) |record, *accepted, index| {
                        const observed: ?candidate.Replacement = if (boundary == .model) .{ .record = record } else null;
                        accepted.* = provenance.inspectRecord(boundary, allocator, validator, context, record, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .{ .record = index }, inspection, err);
                        for (checked[0..index]) |prior| if (try duplicateRecordIssue(allocator, prior, accepted.*, index, observed)) |issue| return .{ .invalid = issue };
                    }
                    break :records .{ .records = checked };
                },
            } };
        },
    };
    return .{ .valid = .{ .unit = unit, .response = result } };
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
    const lhs = try std.json.Stringify.valueAlloc(a, left, .{});
    defer a.free(lhs);
    const rhs = try std.json.Stringify.valueAlloc(a, right, .{});
    defer a.free(rhs);
    return std.mem.eql(u8, lhs, rhs);
}
fn rejectedPart(comptime boundary: spec.Boundary, unit: Unit, response: Responses(boundary).Response, subject: candidate.Subject, inspection: provenance.Inspection, err: provenance.Error) Error!Validation {
    const target = candidate.locate(subject, inspection.part);
    const observed = if (boundary == .model) candidate.select(response, target) catch return error.InvalidSpecificationUnit else null;
    var result = try rejected(unit, .{ .target = target }, observed, inspection.text_issue, err);
    result.invalid.value_choices = inspection.value_choices;
    if (inspection.part == .value and (result.invalid.rule == .provenance or (inspection.text_issue != null and inspection.text_issue.?.reason == .unknown_exact))) result.invalid.rule = .exact_copy;
    return result;
}
