//! Response admission for every native-bound model-text field. This owner
//! aggregates mechanical defects; correction limits and authority stay outside.
const std = @import("std");
const fields = @import("model_text_field.zig");
const wire = @import("model_text_wire.zig");
const typed = @import("typed_text.zig");
const pointer = @import("json_pointer.zig");
pub const FieldIssue = struct {
    field: typed.field_policy.Field,
    path: []const u8,
    issue: typed.Issue,
};
pub const Diagnostic = struct {
    fields: []const FieldIssue,
    pub fn deinit(self: Diagnostic, a: std.mem.Allocator) void {
        for (self.fields) |field| a.free(field.path);
        a.free(self.fields);
    }
    pub fn copy(self: Diagnostic, a: std.mem.Allocator) std.mem.Allocator.Error!Diagnostic {
        var result: std.ArrayList(FieldIssue) = .empty;
        errdefer {
            for (result.items) |field| a.free(field.path);
            result.deinit(a);
        }
        for (self.fields) |field| {
            const path = try a.dupe(u8, field.path);
            errdefer a.free(path);
            try result.append(a, .{ .field = field.field, .path = path, .issue = field.issue });
        }
        return .{ .fields = try result.toOwnedSlice(a) };
    }
    pub fn eql(self: Diagnostic, other: Diagnostic) bool {
        if (self.fields.len != other.fields.len) return false;
        for (self.fields, other.fields) |left, right| {
            if (left.field != right.field or !std.mem.eql(u8, left.path, right.path) or !std.meta.eql(left.issue, right.issue)) return false;
        }
        return true;
    }
    pub const Description = struct { field: typed.field_policy.Field, path: []const u8, reason: @FieldType(typed.Issue, "reason"), explanation: []const u8 };
    pub fn describe(self: Diagnostic, a: std.mem.Allocator) std.mem.Allocator.Error![]const Description {
        const result = try a.alloc(Description, self.fields.len);
        for (self.fields, result) |field, *item| item.* = .{ .field = field.field, .path = field.path, .reason = field.issue.reason, .explanation = field.issue.description() };
        return result;
    }
};

/// Missing union branches and malformed wire shapes remain ordinary schema
/// failures. Selectors carry native identity; names/content never select policy.
pub fn check(a: std.mem.Allocator, value: std.json.Value, bindings: []const fields.Binding, prose: []const wire.ProseField, sources: []const wire.SourceText) std.mem.Allocator.Error!?Diagnostic {
    var issues: std.ArrayList(FieldIssue) = .empty;
    errdefer {
        for (issues.items) |issue| a.free(issue.path);
        issues.deinit(a);
    }
    var path: std.ArrayList(pointer.Segment) = .empty;
    defer path.deinit(a);
    for (bindings) |binding| try selected(a, value, binding.path, binding.field, sources, &path, &issues);
    for (prose) |binding| try selectedProse(a, value, binding.path, binding.field, sources, &path, &issues);
    if (issues.items.len == 0) {
        issues.deinit(a);
        return null;
    }
    return .{ .fields = try issues.toOwnedSlice(a) };
}
fn selected(a: std.mem.Allocator, value: std.json.Value, remaining: []const fields.Step, field: typed.field_policy.Field, sources: []const wire.SourceText, path: *std.ArrayList(pointer.Segment), issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    if (remaining.len == 0) return leaf(a, value, field, sources, path.items, issues);
    switch (remaining[0]) {
        .variant => |kind| if (value == .object) {
            const tag = value.object.get("kind") orelse return;
            if (tag == .string and std.mem.eql(u8, tag.string, kind)) try selected(a, value, remaining[1..], field, sources, path, issues);
        },
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| {
                try path.append(a, .{ .property = name });
                defer _ = path.pop();
                try selected(a, child, remaining[1..], field, sources, path, issues);
            }
        },
        .items => if (value == .array) {
            for (value.array.items, 0..) |child, index| {
                try path.append(a, .{ .index = index });
                defer _ = path.pop();
                try selected(a, child, remaining[1..], field, sources, path, issues);
            }
        },
    }
}
fn selectedProse(a: std.mem.Allocator, value: std.json.Value, remaining: []const @import("model_result_schema.zig").ChoiceStep, field: typed.field_policy.Field, sources: []const wire.SourceText, path: *std.ArrayList(pointer.Segment), issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    if (remaining.len == 0) return if (value == .string) leaf(a, value, field, sources, path.items, issues);
    switch (remaining[0]) {
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| {
                try path.append(a, .{ .property = name });
                defer _ = path.pop();
                try selectedProse(a, child, remaining[1..], field, sources, path, issues);
            }
        },
        .items => if (value == .array) {
            for (value.array.items, 0..) |child, index| {
                try path.append(a, .{ .index = index });
                defer _ = path.pop();
                try selectedProse(a, child, remaining[1..], field, sources, path, issues);
            }
        },
    }
}
fn leaf(a: std.mem.Allocator, value: std.json.Value, field: typed.field_policy.Field, sources: []const wire.SourceText, path: []const pointer.Segment, issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    const nodes = (try wire.compositionNodes(a, value)) orelse return;
    defer a.free(nodes);
    if (typed.composition(typed.CompositionNode, field, nodes)) |issue| if (issue.isComposition()) {
        try append(a, field, path, issue, issues);
    };
    if (try typed.wireCompositionSources(typed.CompositionNode, a, sources, field, nodes)) |issue| try append(a, field, path, issue, issues);
}
fn append(a: std.mem.Allocator, field: typed.field_policy.Field, path: []const pointer.Segment, issue: typed.Issue, issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    const rendered = try pointer.render(a, path);
    errdefer a.free(rendered);
    for (issues.items) |prior| if (prior.field == field and std.mem.eql(u8, prior.path, rendered) and std.meta.eql(prior.issue, issue)) {
        a.free(rendered);
        return;
    };
    try issues.append(a, .{ .field = field, .path = rendered, .issue = issue });
}
