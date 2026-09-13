//! Execution-local candidate identity, field selection and retained rejection.
//! This contract contains no validation rules or repair authorization.
const std = @import("std");
const g = @import("specification_generation.zig");
const identity = @import("model_request_identity.zig");
const Origin = @import("model_candidate_origin.zig").Origin;
pub const Target = union(enum) { title, description, primary_goal, story, entity_basis, record: usize };
pub const Replacement = union(enum) { attributed: g.spec.Model.AttributedValue, record: g.spec.Model.RecordProposal };
pub const Rule = enum { provenance, typed_text, record_kind, duplicate_record, unit_kind };
pub const Field = union(enum) { target: Target, unit, clarification_question };
pub const Issue = struct {
    unit: g.Unit,
    field: Field,
    rule: Rule,
    observed: ?Replacement,
    native_error: ?enum { InvalidSpecification, InvalidReferenceReconciliation, InvalidSourceCitation, InvalidTypedText, UnboundPathReference, InvalidPassiveLiteral } = null,
};
pub const Rejection = struct { owner: identity.ImmutableUnitOwnerId, revision: u64, origin: ?Origin, issue: Issue };
pub const FieldOrigin = struct { target: Target, origin: ?Origin };
pub const Origins = struct {
    initial: ?Origin = null,
    fields: []const FieldOrigin = &.{},
    pub fn at(self: Origins, field: Field) ?Origin {
        if (field == .target) for (self.fields) |entry| {
            if (std.meta.eql(entry.target, field.target)) return entry.origin;
        };
        return self.initial;
    }
    pub fn replacing(self: Origins, a: std.mem.Allocator, target: Target, origin: ?Origin) std.mem.Allocator.Error!Origins {
        var result: std.ArrayList(FieldOrigin) = .empty;
        try result.appendSlice(a, self.fields);
        for (result.items) |*entry| if (std.meta.eql(entry.target, target)) {
            entry.origin = origin;
            return .{ .initial = self.initial, .fields = try result.toOwnedSlice(a) };
        };
        try result.append(a, .{ .target = target, .origin = origin });
        return .{ .initial = self.initial, .fields = try result.toOwnedSlice(a) };
    }
};
pub const Candidate = struct { revision: u64 = 1, response: g.Response, origins: Origins = .{} };
pub const Raw = struct { body: []const u8, origin: ?Origin };
pub const Result = union(enum) { valid: g.Checked, invalid: Rejection };
pub const Error = error{InvalidSpecificationRepair} || std.mem.Allocator.Error;

pub fn select(response: g.Response, target: Target) Error!Replacement {
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
