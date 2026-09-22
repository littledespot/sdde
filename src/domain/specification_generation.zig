//! One reference-grounded business unit. No Markdown, paths, IDs, status,
//! provider calls, default content or semantic-success policy.
//! Normalized values use the caller's arena; provenance and reference inputs
//! must remain retained by that caller.
const std = @import("std");
pub const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");
pub const Error = provenance.Error || error{InvalidSpecificationUnit};
pub const Unit = union(enum) { brief, primary_user_story, entities, records: spec.Kind };
pub const Brief = spec.Brief;
pub fn Responses(comptime boundary: spec.Boundary) type {
    const fields = spec.Values(boundary);
    return struct {
        const Self = @This();
        pub const Need = struct { reason: NeedReason, question: fields.AttributedValue };
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
pub const Checked = struct { unit: Unit, response: CanonicalResponse, origins: candidate.Origins = .{}, last_repair: ?@import("atomic_repair.zig").Merge = null };
const candidate = @import("specification_candidate.zig");
pub const Validation = union(enum) { valid: Checked, invalid: candidate.Issue };

/// Compact model result, without the native IR's content wrapper.
pub const ModelResponse = union(enum) {
    brief: spec.Model.Brief,
    primary_user_story: spec.Model.AttributedValue,
    entities: spec.Model.ApplicabilityProposal,
    records: struct { records: []const spec.Model.RecordProposal },
    clarification: Need,
    inconclusive: Inconclusive,

    pub fn from(response: Response) ModelResponse {
        return switch (response) {
            .clarification => |need| .{ .clarification = need },
            .inconclusive => |failure| .{ .inconclusive = failure },
            .content => |content| switch (content) {
                .records => |records| .{ .records = .{ .records = records } },
                inline else => |value, tag| @unionInit(ModelResponse, @tagName(tag), value),
            },
        };
    }
};

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) Error!Response {
    const response = @import("model_candidate_json.zig").decode(ModelResponse, allocator, bytes) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidSpecificationUnit,
    };
    return switch (response) {
        .clarification => |need| .{ .clarification = need },
        .inconclusive => |failure| .{ .inconclusive = failure },
        .records => |records| .{ .content = .{ .records = records.records } },
        inline else => |value, tag| .{ .content = @unionInit(Content, @tagName(tag), value) },
    };
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
        .clarification => |need| .{ .clarification = .{
            .reason = need.reason,
            .question = provenance.inspectAttributed(boundary, allocator, validator, context, need.question, &inspection) catch |err| return rejected(unit, .clarification_question, null, inspection.text_issue, err),
        } },
        .content => |content| blk: {
            if (@intFromEnum(std.meta.activeTag(unit)) != @intFromEnum(std.meta.activeTag(content))) return .{ .invalid = .{ .unit = unit, .field = .unit, .rule = .unit_kind, .observed = null, .blocked = .unit_kind } };
            break :blk .{ .content = switch (content) {
                .brief => |brief| .{ .brief = .{
                    .title = provenance.inspectAttributed(boundary, allocator, validator, context, brief.title, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .title, inspection, err),
                    .description = provenance.inspectAttributed(boundary, allocator, validator, context, brief.description, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .description, inspection, err),
                    .primary_goal = provenance.inspectAttributed(boundary, allocator, validator, context, brief.primary_goal, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .primary_goal, inspection, err),
                } },
                .primary_user_story => |story| .{ .primary_user_story = provenance.inspectAttributed(boundary, allocator, validator, context, story, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .story, inspection, err) },
                .entities => |entities| .{ .entities = .{
                    .disposition = entities.disposition,
                    .basis = provenance.inspectAttributed(boundary, allocator, validator, context, entities.basis, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .entity_basis, inspection, err),
                } },
                .records => |records| records: {
                    const checked = try allocator.alloc(spec.RecordProposal, records.len);
                    for (records, checked, 0..) |record, *accepted, index| {
                        const observed: ?candidate.Replacement = if (boundary == .model) .{ .record = record } else null;
                        if (std.meta.activeTag(record.content) != unit.records) return .{ .invalid = .{ .unit = unit, .field = .{ .target = .{ .record = index } }, .rule = .record_kind, .observed = observed } };
                        accepted.* = provenance.inspectRecord(boundary, allocator, validator, context, record, &inspection) catch |err| return rejectedPart(boundary, unit, proposed, .{ .record = index }, inspection, err);
                        for (checked[0..index]) |prior| if (try equalContent(allocator, prior.content, accepted.content)) return .{ .invalid = .{ .unit = unit, .field = .{ .target = .{ .record = index } }, .rule = .duplicate_record, .observed = observed, .blocked = if (try equalEvidence(allocator, prior.provenance, accepted.provenance)) null else .competing_records } };
                    }
                    break :records .{ .records = checked };
                },
            } };
        },
    };
    return .{ .valid = .{ .unit = unit, .response = result } };
}

/// Equality over normalized typed content, never a second rendered text source.
pub fn equalContent(allocator: std.mem.Allocator, a: spec.Content(spec.BusinessValue), b: spec.Content(spec.BusinessValue)) std.mem.Allocator.Error!bool {
    const left = try std.json.Stringify.valueAlloc(allocator, a, .{});
    defer allocator.free(left);
    const right = try std.json.Stringify.valueAlloc(allocator, b, .{});
    defer allocator.free(right);
    return std.mem.eql(u8, left, right);
}

fn rejected(unit: Unit, field: candidate.Field, observed: ?candidate.Replacement, text_issue: ?@import("typed_text.zig").Issue, err: provenance.Error) Error!Validation {
    if (text_issue == null) switch (err) {
        error.InvalidTypedText, error.UnboundPathReference, error.InvalidPassiveLiteral => return err,
        else => {},
    };
    const native: @FieldType(candidate.Issue, "native_error") = switch (err) {
        error.InvalidSpecification => .InvalidSpecification,
        error.InvalidReferenceReconciliation => .InvalidReferenceReconciliation,
        error.InvalidSourceCitation => .InvalidSourceCitation,
        error.InvalidTypedText => .InvalidTypedText,
        error.UnboundPathReference => .UnboundPathReference,
        error.InvalidPassiveLiteral => .InvalidPassiveLiteral,
        else => return err,
    };
    return .{ .invalid = .{ .unit = unit, .field = field, .observed = observed, .native_error = native, .text_issue = text_issue, .blocked = if (field == .clarification_question) .clarification_question else null, .rule = switch (native.?) {
        .InvalidSpecification, .InvalidReferenceReconciliation, .InvalidSourceCitation => .provenance,
        .InvalidTypedText, .UnboundPathReference, .InvalidPassiveLiteral => .typed_text,
    } } };
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
    if (inspection.part == .value and result.invalid.rule == .provenance) result.invalid.rule = .exact_copy;
    return result;
}
