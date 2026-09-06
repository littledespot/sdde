//! One reference-grounded business unit. No Markdown, paths, IDs, status,
//! provider calls, default content or semantic-success policy.
//! Normalized values use the caller's arena; provenance and reference inputs
//! must remain retained by that caller.
const std = @import("std");
pub const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");
pub const Error = provenance.Error || error{InvalidSpecificationUnit};
pub const Unit = union(enum) { brief, primary_user_story, entities, records: spec.Kind };
pub const Brief = struct { title: spec.AttributedValue, description: spec.AttributedValue, primary_goal: spec.AttributedValue };
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
pub const Checked = struct { unit: Unit, response: Response };

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) Error!Response {
    return @import("strict_json.zig").decode(Response, allocator, bytes, .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidSpecificationUnit,
    };
}

pub fn validate(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: provenance.Context, unit: Unit, proposed: Response) Error!Checked {
    var result = proposed;
    switch (proposed) {
        .clarification => |need| {
            result.clarification.question = try provenance.attributed(allocator, validator, context, need.question);
        },
        .content => |content| {
            if (@intFromEnum(std.meta.activeTag(unit)) != @intFromEnum(std.meta.activeTag(content))) return error.InvalidSpecificationUnit;
            switch (content) {
                .brief => |brief| result.content.brief = .{
                    .title = try provenance.attributed(allocator, validator, context, brief.title),
                    .description = try provenance.attributed(allocator, validator, context, brief.description),
                    .primary_goal = try provenance.attributed(allocator, validator, context, brief.primary_goal),
                },
                .primary_user_story => |story| result.content.primary_user_story = try provenance.attributed(allocator, validator, context, story),
                .entities => |entities| result.content.entities.basis = try provenance.attributed(allocator, validator, context, entities.basis),
                .records => |records| {
                    const checked = try allocator.alloc(spec.RecordProposal, records.len);
                    for (records, checked, 0..) |record, *accepted, index| {
                        if (std.meta.activeTag(record.content) != unit.records) return error.InvalidSpecificationUnit;
                        accepted.* = try provenance.record(allocator, validator, context, record);
                        for (checked[0..index]) |prior| if (try equalContent(allocator, prior.content, accepted.content)) return error.InvalidSpecificationUnit;
                    }
                    result.content.records = checked;
                },
            }
        },
    }
    return .{ .unit = unit, .response = result };
}

/// Equality over normalized typed content, never a second rendered text source.
pub fn equalContent(allocator: std.mem.Allocator, a: spec.Content(spec.BusinessValue), b: spec.Content(spec.BusinessValue)) std.mem.Allocator.Error!bool {
    const left = try std.json.Stringify.valueAlloc(allocator, a, .{});
    defer allocator.free(left);
    const right = try std.json.Stringify.valueAlloc(allocator, b, .{});
    defer allocator.free(right);
    return std.mem.eql(u8, left, right);
}
