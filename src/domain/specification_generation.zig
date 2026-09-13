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
pub const Need = struct {
    reason: enum { missing, ambiguous, conflicting },
    question: spec.AttributedValue,
};
pub const Content = union(enum) {
    brief: Brief,
    primary_user_story: spec.AttributedValue,
    entities: spec.ApplicabilityProposal,
    records: []const spec.RecordProposal,
};
pub const Response = union(enum) { content: Content, clarification: Need };
pub const Checked = struct { unit: Unit, response: Response, origins: candidate.Origins = .{} };
const candidate = @import("specification_candidate.zig");
pub const Validation = union(enum) { valid: Checked, invalid: candidate.Issue };

/// Compact model result, without the native IR's content wrapper.
pub const ModelResponse = union(enum) {
    brief: Brief,
    primary_user_story: spec.AttributedValue,
    entities: spec.ApplicabilityProposal,
    records: struct { records: []const spec.RecordProposal },
    clarification: Need,

    pub fn from(response: Response) ModelResponse {
        return switch (response) {
            .clarification => |need| .{ .clarification = need },
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
        .records => |records| .{ .content = .{ .records = records.records } },
        inline else => |value, tag| .{ .content = @unionInit(Content, @tagName(tag), value) },
    };
}

pub fn validate(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: Response) Error!Validation {
    try provenance.bind(allocator, validator, context);
    var result = proposed;
    switch (proposed) {
        .clarification => |need| {
            result.clarification.question = provenance.attributed(allocator, validator, context, need.question) catch |err| return rejected(unit, .clarification_question, .{ .attributed = need.question }, err);
        },
        .content => |content| {
            if (@intFromEnum(std.meta.activeTag(unit)) != @intFromEnum(std.meta.activeTag(content))) return .{ .invalid = .{ .unit = unit, .field = .unit, .rule = .unit_kind, .observed = null } };
            switch (content) {
                .brief => |brief| result.content.brief = .{
                    .title = provenance.attributed(allocator, validator, context, brief.title) catch |err| return rejected(unit, .{ .target = .title }, .{ .attributed = brief.title }, err),
                    .description = provenance.attributed(allocator, validator, context, brief.description) catch |err| return rejected(unit, .{ .target = .description }, .{ .attributed = brief.description }, err),
                    .primary_goal = provenance.attributed(allocator, validator, context, brief.primary_goal) catch |err| return rejected(unit, .{ .target = .primary_goal }, .{ .attributed = brief.primary_goal }, err),
                },
                .primary_user_story => |story| result.content.primary_user_story = provenance.attributed(allocator, validator, context, story) catch |err| return rejected(unit, .{ .target = .story }, .{ .attributed = story }, err),
                .entities => |entities| result.content.entities.basis = provenance.attributed(allocator, validator, context, entities.basis) catch |err| return rejected(unit, .{ .target = .entity_basis }, .{ .attributed = entities.basis }, err),
                .records => |records| {
                    const checked = try allocator.alloc(spec.RecordProposal, records.len);
                    for (records, checked, 0..) |record, *accepted, index| {
                        if (std.meta.activeTag(record.content) != unit.records) return .{ .invalid = .{ .unit = unit, .field = .{ .target = .{ .record = index } }, .rule = .record_kind, .observed = .{ .record = record } } };
                        accepted.* = provenance.record(allocator, validator, context, record) catch |err| return rejected(unit, .{ .target = .{ .record = index } }, .{ .record = record }, err);
                        for (checked[0..index]) |prior| if (try equalContent(allocator, prior.content, accepted.content)) return .{ .invalid = .{ .unit = unit, .field = .{ .target = .{ .record = index } }, .rule = .duplicate_record, .observed = .{ .record = record } } };
                    }
                    result.content.records = checked;
                },
            }
        },
    }
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

fn rejected(unit: Unit, field: candidate.Field, observed: candidate.Replacement, err: provenance.Error) Error!Validation {
    const native: @FieldType(candidate.Issue, "native_error") = switch (err) {
        error.InvalidSpecification => .InvalidSpecification,
        error.InvalidReferenceReconciliation => .InvalidReferenceReconciliation,
        error.InvalidSourceCitation => .InvalidSourceCitation,
        error.InvalidTypedText => .InvalidTypedText,
        error.UnboundPathReference => .UnboundPathReference,
        error.InvalidPassiveLiteral => .InvalidPassiveLiteral,
        else => return err,
    };
    return .{ .invalid = .{ .unit = unit, .field = field, .observed = observed, .native_error = native, .rule = switch (native.?) {
        .InvalidSpecification, .InvalidReferenceReconciliation, .InvalidSourceCitation => .provenance,
        .InvalidTypedText, .UnboundPathReference, .InvalidPassiveLiteral => .typed_text,
    } } };
}
