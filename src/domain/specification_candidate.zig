//! Execution-local candidate identity, field selection and retained rejection.
const std = @import("std");
const g = @import("specification_generation.zig");
const identity = @import("model_request_identity.zig");
const Origin = @import("model_candidate_origin.zig").Origin;
pub const Subject = union(enum) { title, description, primary_goal, story, entity_basis, record: usize };
pub const ValueField = union(enum) { value, given, when, then, text, condition, expected_outcome, name, business_meaning, relationship: usize };
pub const Part = union(enum) { provenance, value: ValueField };
pub const Target = union(enum) { provenance: Subject, value: struct { subject: Subject, field: ValueField }, record: usize };
pub const Replacement = union(enum) { provenance: g.spec.Selection, value: g.spec.BusinessValue, record: g.spec.Model.RecordProposal };
pub const Rule = enum { provenance, typed_text, exact_copy, record_kind, duplicate_record, unit_kind };
pub const Blocked = enum { competing_records, unit_kind, clarification_question };
pub const Field = union(enum) { target: Target, unit, clarification_question };
pub const Issue = struct {
    unit: g.Unit,
    field: Field,
    rule: Rule,
    observed: ?Replacement,
    blocked: ?Blocked = null,
    text_issue: ?@import("typed_text.zig").Issue = null,
    native_error: ?enum { InvalidSpecification, InvalidReferenceReconciliation, InvalidSourceCitation, InvalidTypedText, UnboundPathReference, InvalidPassiveLiteral } = null,
};
pub const Rejection = struct { owner: identity.ImmutableUnitOwnerId, revision: u64, origin: ?Origin, issue: Issue, last_repair: ?@import("atomic_repair.zig").Merge = null, dependencies: ?@import("atomic_repair.zig").Snapshot = null };
pub const FieldOrigin = struct { target: Target, origin: ?Origin };
pub const Origins = struct {
    initial: ?Origin = null,
    fields: []const FieldOrigin = &.{},
    pub fn at(self: Origins, field: Field) ?Origin {
        if (field == .target) {
            for (self.fields) |entry| if (std.meta.eql(entry.target, field.target)) return entry.origin;
            if (recordIndex(field.target)) |index| for (self.fields) |entry| {
                if (entry.target == .record and entry.target.record == index) return entry.origin;
            };
        }
        return self.initial;
    }
    pub fn replacing(self: Origins, a: std.mem.Allocator, target: Target, origin: ?Origin) std.mem.Allocator.Error!Origins {
        var result: std.ArrayList(FieldOrigin) = .empty;
        for (self.fields) |entry| {
            if (std.meta.eql(entry.target, target)) continue;
            if (target == .record and recordIndex(entry.target) == target.record) continue;
            try result.append(a, entry);
        }
        try result.append(a, .{ .target = target, .origin = origin });
        return .{ .initial = self.initial, .fields = try result.toOwnedSlice(a) };
    }
    pub fn deleting(self: Origins, a: std.mem.Allocator, index: usize) std.mem.Allocator.Error!Origins {
        var result: std.ArrayList(FieldOrigin) = .empty;
        for (self.fields) |entry| {
            var next = entry;
            if (recordIndex(entry.target)) |ordinal| {
                if (ordinal == index) continue;
                if (ordinal > index) switch (next.target) {
                    .record => |*value| value.* -= 1,
                    .provenance => |*value| value.record -= 1,
                    .value => |*value| value.subject.record -= 1,
                };
            }
            try result.append(a, next);
        }
        return .{ .initial = self.initial, .fields = try result.toOwnedSlice(a) };
    }
};
pub const Candidate = struct { revision: u64 = 1, last_repair: ?@import("atomic_repair.zig").Merge = null, response: g.Response, origins: Origins = .{} };
pub const Raw = struct { body: []const u8, origin: ?Origin };
pub const Result = union(enum) { valid: g.Checked, invalid: Rejection };
pub const Error = error{InvalidSpecificationRepair} || std.mem.Allocator.Error;
pub fn locate(subject: Subject, part: Part) Target {
    return switch (part) {
        .provenance => .{ .provenance = subject },
        .value => |field| .{ .value = .{ .subject = subject, .field = field } },
    };
}
fn recordIndex(selected: Target) ?usize {
    const subject: Subject = switch (selected) {
        .record => |index| return index,
        .provenance => |value| value,
        .value => |value| value.subject,
    };
    return if (subject == .record) subject.record else null;
}
fn attributed(comptime boundary: g.spec.Boundary, content: *g.Responses(boundary).Content, subject: Subject) Error!*g.spec.Values(boundary).AttributedValue {
    return switch (subject) {
        .title => if (content.* == .brief) &content.brief.title else error.InvalidSpecificationRepair,
        .description => if (content.* == .brief) &content.brief.description else error.InvalidSpecificationRepair,
        .primary_goal => if (content.* == .brief) &content.brief.primary_goal else error.InvalidSpecificationRepair,
        .story => if (content.* == .primary_user_story) &content.primary_user_story else error.InvalidSpecificationRepair,
        .entity_basis => if (content.* == .entities) &content.entities.basis else error.InvalidSpecificationRepair,
        .record => error.InvalidSpecificationRepair,
    };
}
fn valueField(content: *g.spec.Content(g.spec.BusinessValue), field: ValueField) Error!g.spec.BusinessValue {
    return valueAccess(content, field, null);
}
fn valueAccess(content: *g.spec.Content(g.spec.BusinessValue), selected: ValueField, replacement: ?g.spec.BusinessValue) Error!g.spec.BusinessValue {
    switch (content.*) {
        inline else => |*fields| inline for (@typeInfo(@TypeOf(fields.*)).@"struct".fields) |field| {
            if (comptime field.type == g.spec.BusinessValue) {
                if (std.meta.activeTag(selected) == @field(std.meta.Tag(ValueField), field.name)) {
                    const old = @field(fields, field.name);
                    if (replacement) |value| @field(fields, field.name) = value;
                    return old;
                }
            } else if (selected == .relationship and selected.relationship < @field(fields, field.name).len) {
                // Mutation of array members is handled by replace after copying.
                if (replacement != null) return error.InvalidSpecificationRepair;
                return @field(fields, field.name)[selected.relationship];
            }
        },
    }
    return error.InvalidSpecificationRepair;
}
pub fn select(response: g.Response, selected: Target) Error!Replacement {
    if (response != .content) return error.InvalidSpecificationRepair;
    var content = response.content;
    if (recordIndex(selected)) |index| {
        if (content != .records or index >= content.records.len) return error.InvalidSpecificationRepair;
        var record = content.records[index];
        return switch (selected) {
            .record => .{ .record = record },
            .provenance => .{ .provenance = record.provenance },
            .value => |field| .{ .value = try valueField(&record.content, field.field) },
        };
    }
    return switch (selected) {
        .provenance => |subject| .{ .provenance = (try attributed(.model, &content, subject)).provenance },
        .value => |field| if (field.field == .value) .{ .value = (try attributed(.model, &content, field.subject)).value } else error.InvalidSpecificationRepair,
        .record => unreachable,
    };
}
pub fn replace(a: std.mem.Allocator, response: g.Response, selected: Target, replacement: Replacement) Error!g.Response {
    _ = try select(response, selected);
    var result = response;
    if (recordIndex(selected)) |index| {
        const records = try a.dupe(g.spec.Model.RecordProposal, response.content.records);
        result.content.records = records;
        switch (selected) {
            .record => records[index] = replacement.record,
            .provenance => records[index].provenance = replacement.provenance,
            .value => |field| {
                if (field.field == .relationship) {
                    const relationships = try a.dupe(g.spec.BusinessValue, records[index].content.entity.relationships);
                    relationships[field.field.relationship] = replacement.value;
                    records[index].content.entity.relationships = relationships;
                } else _ = try valueAccess(&records[index].content, field.field, replacement.value);
            },
        }
    } else switch (selected) {
        .provenance => |subject| (try attributed(.model, &result.content, subject)).provenance = replacement.provenance,
        .value => |field| (try attributed(.model, &result.content, field.subject)).value = replacement.value,
        .record => unreachable,
    }
    return result;
}

/// The same field lens serves validated canonical session values during coverage
/// repair; it never removes or reconstructs their provenance.
pub fn canonicalValue(response: g.CanonicalResponse, subject: Subject, field: ValueField) Error!g.spec.AttributedValue {
    if (response != .content) return error.InvalidSpecificationRepair;
    var content = response.content;
    if (subject != .record) {
        if (field != .value) return error.InvalidSpecificationRepair;
        return (try attributed(.canonical, &content, subject)).*;
    }
    if (content != .records or subject.record >= content.records.len) return error.InvalidSpecificationRepair;
    var record = content.records[subject.record];
    return .{ .value = try valueField(&record.content, field), .provenance = record.provenance };
}
pub fn replaceCanonicalValue(a: std.mem.Allocator, response: g.CanonicalResponse, subject: Subject, field: ValueField, value: g.spec.BusinessValue) Error!g.CanonicalResponse {
    _ = try canonicalValue(response, subject, field);
    var result = response;
    if (subject != .record) {
        (try attributed(.canonical, &result.content, subject)).value = value;
    } else {
        const records = try a.dupe(g.spec.RecordProposal, response.content.records);
        result.content.records = records;
        if (field == .relationship) {
            const relationships = try a.dupe(g.spec.BusinessValue, records[subject.record].content.entity.relationships);
            relationships[field.relationship] = value;
            records[subject.record].content.entity.relationships = relationships;
        } else _ = try valueAccess(&records[subject.record].content, field, value);
    }
    return result;
}
