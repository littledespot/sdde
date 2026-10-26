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
pub const NativeContext = struct {
    exact_scope: ?@import("model_exact_values.zig").Scope,
};

pub fn check(a: std.mem.Allocator, value: std.json.Value, bindings: []const fields.Binding, prose: []const wire.ProseField, sources: []const wire.SourceText, native: NativeContext) std.mem.Allocator.Error!?Diagnostic {
    var issues: std.ArrayList(FieldIssue) = .empty;
    errdefer {
        for (issues.items) |issue| a.free(issue.path);
        issues.deinit(a);
    }
    var path: std.ArrayList(pointer.Segment) = .empty;
    defer path.deinit(a);
    for (bindings) |binding| try selected(a, value, binding.path, binding.field, sources, native, &path, &issues);
    for (prose) |binding| try selectedProse(a, value, binding.path, binding.field, sources, native, &path, &issues);
    if (issues.items.len == 0) {
        issues.deinit(a);
        return null;
    }
    return .{ .fields = try issues.toOwnedSlice(a) };
}
fn selected(a: std.mem.Allocator, value: std.json.Value, remaining: []const fields.Step, field: typed.field_policy.Field, sources: []const wire.SourceText, native: NativeContext, path: *std.ArrayList(pointer.Segment), issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    if (remaining.len == 0) return leaf(a, value, field, sources, native, path.items, issues);
    switch (remaining[0]) {
        .variant => |kind| if (value == .object) {
            const tag = value.object.get("kind") orelse return;
            if (tag == .string and std.mem.eql(u8, tag.string, kind)) try selected(a, value, remaining[1..], field, sources, native, path, issues);
        },
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| {
                try path.append(a, .{ .property = name });
                defer _ = path.pop();
                try selected(a, child, remaining[1..], field, sources, native, path, issues);
            }
        },
        .items => if (value == .array) {
            for (value.array.items, 0..) |child, index| {
                try path.append(a, .{ .index = index });
                defer _ = path.pop();
                try selected(a, child, remaining[1..], field, sources, native, path, issues);
            }
        },
    }
}
fn selectedProse(a: std.mem.Allocator, value: std.json.Value, remaining: []const @import("model_result_schema.zig").ChoiceStep, field: typed.field_policy.Field, sources: []const wire.SourceText, native: NativeContext, path: *std.ArrayList(pointer.Segment), issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    if (remaining.len == 0) return if (value == .string) leaf(a, value, field, sources, native, path.items, issues);
    switch (remaining[0]) {
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| {
                try path.append(a, .{ .property = name });
                defer _ = path.pop();
                try selectedProse(a, child, remaining[1..], field, sources, native, path, issues);
            }
        },
        .items => if (value == .array) {
            for (value.array.items, 0..) |child, index| {
                try path.append(a, .{ .index = index });
                defer _ = path.pop();
                try selectedProse(a, child, remaining[1..], field, sources, native, path, issues);
            }
        },
    }
}
fn leaf(a: std.mem.Allocator, value: std.json.Value, field: typed.field_policy.Field, sources: []const wire.SourceText, native: NativeContext, path: []const pointer.Segment, issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    const nodes = (try wire.compositionNodes(a, value)) orelse return;
    defer a.free(nodes);
    if (typed.composition(typed.CompositionNode, field, nodes)) |issue| if (issue.isComposition()) {
        try append(a, field, path, issue, issues);
    };
    if (try typed.wireCompositionSources(typed.CompositionNode, a, sources, field, nodes)) |issue| try append(a, field, path, issue, issues);
    if (native.exact_scope) |scope| {
        if (typed.field_policy.get(field).exact_copy != .prohibited) try checkRecognized(a, nodes, field, scope, path, issues);
    }
}

/// Recognition changes only the composition view. Canonical occurrence identity
/// is reconstructed separately from the same native scope at value admission.
fn checkRecognized(a: std.mem.Allocator, nodes: []const typed.CompositionNode, field: typed.field_policy.Field, scope: @import("model_exact_values.zig").Scope, path: []const pointer.Segment, issues: *std.ArrayList(FieldIssue)) std.mem.Allocator.Error!void {
    const recognition = @import("exact_value_recognition.zig");
    var projected: std.ArrayList(typed.CompositionNode) = .empty;
    defer projected.deinit(a);
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const temporary = arena.allocator();
    var index: usize = 0;
    while (index < nodes.len) {
        if (nodes[index] != .literal) {
            try projected.append(a, nodes[index]);
            index += 1;
            continue;
        }
        const first = index;
        var bytes: std.ArrayList(u8) = .empty;
        while (index < nodes.len and nodes[index] == .literal) : (index += 1) try bytes.appendSlice(temporary, nodes[index].literal.value);
        const edges: @import("exact_value_boundary.zig").Edges = .{ .left = if (first == 0) .field_edge else .reference_boundary, .right = if (index == nodes.len) .field_edge else .reference_boundary };
        const result = try recognition.recognize(a, bytes.items, scope.occurrences, edges);
        defer result.deinit(a);
        switch (result) {
            .rejected => try append(a, field, path, .{ .reason = .invalid_scalar, .first_node = first, .last_node = index - 1, .field = field }, issues),
            .ambiguous => try append(a, field, path, .{ .reason = .ambiguous_exact, .first_node = first, .last_node = index - 1, .field = field }, issues),
            .no_match => try projected.append(a, .{ .literal = .{ .value = bytes.items } }),
            .matched => |found| {
                const matches = try recognition.delimited(temporary, bytes.items, found, scope.occurrences, edges);
                var copied: usize = 0;
                for (matches) |match| {
                    if (copied < match.outerStart()) try projected.append(a, .{ .literal = .{ .value = bytes.items[copied..match.outerStart()] } });
                    try projected.append(a, .exact_copy);
                    copied = match.outerEnd();
                }
                if (copied < bytes.items.len) try projected.append(a, .{ .literal = .{ .value = bytes.items[copied..] } });
            },
        }
    }
    if (typed.composition(typed.CompositionNode, field, projected.items)) |issue| if (issue.isComposition()) try append(a, field, path, issue, issues);
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
