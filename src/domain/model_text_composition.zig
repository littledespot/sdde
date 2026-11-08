//! Response admission for every native-bound model-text field. This owner
//! aggregates mechanical defects; correction limits and authority stay outside.
const std = @import("std");
const fields = @import("model_text_field.zig");
const wire = @import("model_text_wire.zig");
const typed = @import("typed_text.zig");
const pointer = @import("json_pointer.zig");
const schema = @import("model_result_schema.zig");
const statement = @import("statement_ownership.zig");
const payload = @import("model_payload_schema.zig");
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

/// ADR 0038 Decision 5: the covered array of statement records whose owner deletes some
/// natively. A text defect in a record the owner deletes is no defect of the response, so
/// it is not reported. `path` is the recorded coverage path: the property names leading
/// to the array, `items`, then the property that lists each record's claims.
pub const Statements = struct { path: []const schema.ChoiceStep, rule: schema.ItemCoverage };

/// Missing union branches and malformed wire shapes remain ordinary schema
/// failures. Selectors carry native identity; names/content never select policy.
pub const NativeContext = struct {
    exact_scope: ?@import("model_exact_values.zig").Scope,
    statements: ?Statements = null,
};

/// The statements array a response schema covers (ADR 0038), when it covers exactly one.
pub fn statementsOf(response_schema: *const schema.Schema) ?Statements {
    const choices = response_schema.coverageChoices();
    return if (choices.len == 1) .{ .path = choices[0].path, .rule = choices[0].coverage } else null;
}

/// What one check collects beside its issues: the exact values each record of the
/// statements array holds.
const Walk = struct {
    native: NativeContext,
    held: *std.ArrayList(Held),
};
/// An exact value a record holds; a null claim is a value that can't be identified here:
/// an ambiguous or unrecognizable one, text that is not a valid scalar, or an explicit
/// insertion. Unit validation recognizes the text again as one run, where an insertion's
/// handle need not survive, so no layer relies on it.
const Held = struct { record: usize, claim: ?i64 };
/// An issue and the record of the statements array it belongs to, if any.
const Collected = struct { issue: FieldIssue, record: ?usize };

pub fn check(a: std.mem.Allocator, value: std.json.Value, bindings: []const fields.Binding, prose: []const wire.ProseField, sources: []const wire.SourceText, native: NativeContext) std.mem.Allocator.Error!?Diagnostic {
    var issues: std.ArrayList(Collected) = .empty;
    errdefer {
        for (issues.items) |entry| a.free(entry.issue.path);
        issues.deinit(a);
    }
    var held: std.ArrayList(Held) = .empty;
    defer held.deinit(a);
    const walk: Walk = .{ .native = native, .held = &held };
    var path: std.ArrayList(pointer.Segment) = .empty;
    defer path.deinit(a);
    for (bindings) |binding| try selected(a, value, binding.path, binding.field, sources, walk, &path, &issues);
    for (prose) |binding| try selectedProse(a, value, binding.path, binding.field, sources, walk, &path, &issues);
    if (issues.items.len != 0) if (native.statements) |statements| try dropDeleted(a, value, statements, held.items, &issues);
    if (issues.items.len == 0) {
        issues.deinit(a);
        return null;
    }
    const reported = try a.alloc(FieldIssue, issues.items.len);
    for (issues.items, reported) |entry, *out| out.* = entry.issue;
    issues.deinit(a);
    return .{ .fields = reported };
}
fn selected(a: std.mem.Allocator, value: std.json.Value, remaining: []const fields.Step, field: typed.field_policy.Field, sources: []const wire.SourceText, walk: Walk, path: *std.ArrayList(pointer.Segment), issues: *std.ArrayList(Collected)) std.mem.Allocator.Error!void {
    if (remaining.len == 0) return leaf(a, value, field, sources, walk, path.items, issues);
    switch (remaining[0]) {
        .variant => |kind| if (value == .object) {
            const tag = value.object.get("kind") orelse return;
            if (tag == .string and std.mem.eql(u8, tag.string, kind)) try selected(a, value, remaining[1..], field, sources, walk, path, issues);
        },
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| {
                try path.append(a, .{ .property = name });
                defer _ = path.pop();
                try selected(a, child, remaining[1..], field, sources, walk, path, issues);
            }
        },
        .items => if (value == .array) {
            for (value.array.items, 0..) |child, index| {
                try path.append(a, .{ .index = index });
                defer _ = path.pop();
                try selected(a, child, remaining[1..], field, sources, walk, path, issues);
            }
        },
    }
}
fn selectedProse(a: std.mem.Allocator, value: std.json.Value, remaining: []const @import("model_result_schema.zig").ChoiceStep, field: typed.field_policy.Field, sources: []const wire.SourceText, walk: Walk, path: *std.ArrayList(pointer.Segment), issues: *std.ArrayList(Collected)) std.mem.Allocator.Error!void {
    if (remaining.len == 0) return if (value == .string) leaf(a, value, field, sources, walk, path.items, issues);
    switch (remaining[0]) {
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| {
                try path.append(a, .{ .property = name });
                defer _ = path.pop();
                try selectedProse(a, child, remaining[1..], field, sources, walk, path, issues);
            }
        },
        .items => if (value == .array) {
            for (value.array.items, 0..) |child, index| {
                try path.append(a, .{ .index = index });
                defer _ = path.pop();
                try selectedProse(a, child, remaining[1..], field, sources, walk, path, issues);
            }
        },
    }
}
fn leaf(a: std.mem.Allocator, value: std.json.Value, field: typed.field_policy.Field, sources: []const wire.SourceText, walk: Walk, path: []const pointer.Segment, issues: *std.ArrayList(Collected)) std.mem.Allocator.Error!void {
    const nodes = (try wire.compositionNodes(a, value)) orelse return;
    defer a.free(nodes);
    for (nodes) |node| if (node == .exact_copy) {
        try holdUnidentified(a, walk, path);
        break;
    };
    if (typed.composition(typed.CompositionNode, field, nodes)) |issue| if (issue.isComposition()) {
        try append(a, walk, field, path, issue, issues);
    };
    if (try typed.wireCompositionSources(typed.CompositionNode, a, sources, field, nodes)) |issue| try append(a, walk, field, path, issue, issues);
    if (walk.native.exact_scope) |scope| {
        if (typed.field_policy.get(field).exact_copy != .prohibited) try checkRecognized(a, nodes, field, scope, walk, path, issues);
    }
}

/// The record of the statements array that `path` lies in holds a value that can't be identified.
fn holdUnidentified(a: std.mem.Allocator, walk: Walk, path: []const pointer.Segment) std.mem.Allocator.Error!void {
    const statements = walk.native.statements orelse return;
    if (recordOf(statements, path)) |record| try walk.held.append(a, .{ .record = record, .claim = null });
}

/// Recognition changes only the composition view. Canonical occurrence identity
/// is reconstructed separately from the same native scope at value admission.
fn checkRecognized(a: std.mem.Allocator, nodes: []const typed.CompositionNode, field: typed.field_policy.Field, scope: @import("model_exact_values.zig").Scope, walk: Walk, path: []const pointer.Segment, issues: *std.ArrayList(Collected)) std.mem.Allocator.Error!void {
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
        // Unit validation skips recognition of a run that is not a valid scalar, so what
        // such a run holds is unidentified, whatever recognition finds here.
        const identified = typed.validScalar(bytes.items);
        if (!identified) try holdUnidentified(a, walk, path);
        const result = try recognition.recognize(a, bytes.items, scope.occurrences, edges);
        defer result.deinit(a);
        switch (result) {
            .rejected => {
                try holdUnidentified(a, walk, path);
                try append(a, walk, field, path, .{ .reason = .invalid_scalar, .first_node = first, .last_node = index - 1, .field = field }, issues);
            },
            .ambiguous => {
                try holdUnidentified(a, walk, path);
                try append(a, walk, field, path, .{ .reason = .ambiguous_exact, .first_node = first, .last_node = index - 1, .field = field }, issues);
            },
            .no_match => try projected.append(a, .{ .literal = .{ .value = bytes.items } }),
            .matched => |found| {
                const matches = try recognition.delimited(temporary, bytes.items, found, scope.occurrences, edges);
                var copied: usize = 0;
                for (matches) |match| {
                    if (copied < match.outerStart()) try projected.append(a, .{ .literal = .{ .value = bytes.items[copied..match.outerStart()] } });
                    try projected.append(a, .exact_copy);
                    if (identified) if (walk.native.statements) |statements| if (recordOf(statements, path)) |record| try walk.held.append(a, .{ .record = record, .claim = match.claim_id.ordinal });
                    copied = match.outerEnd();
                }
                if (copied < bytes.items.len) try projected.append(a, .{ .literal = .{ .value = bytes.items[copied..] } });
            },
        }
    }
    if (typed.composition(typed.CompositionNode, field, projected.items)) |issue| if (issue.isComposition()) try append(a, walk, field, path, issue, issues);
}
fn append(a: std.mem.Allocator, walk: Walk, field: typed.field_policy.Field, path: []const pointer.Segment, issue: typed.Issue, issues: *std.ArrayList(Collected)) std.mem.Allocator.Error!void {
    const rendered = try pointer.render(a, path);
    errdefer a.free(rendered);
    for (issues.items) |prior| if (prior.issue.field == field and std.mem.eql(u8, prior.issue.path, rendered) and std.meta.eql(prior.issue.issue, issue)) {
        a.free(rendered);
        return;
    };
    try issues.append(a, .{ .issue = .{ .field = field, .path = rendered, .issue = issue }, .record = if (walk.native.statements) |statements| recordOf(statements, path) else null });
}

/// The index of the statements array's record that `path` lies in, if it does.
fn recordOf(statements: Statements, path: []const pointer.Segment) ?usize {
    if (statements.path.len < 2) return null;
    const array = statements.path[0 .. statements.path.len - 2];
    if (path.len <= array.len) return null;
    for (array, path[0..array.len]) |step, segment| {
        if (step != .property or segment != .property or !std.mem.eql(u8, step.property, segment.property)) return null;
    }
    return switch (path[array.len]) {
        .index => |index| index,
        .property => null,
    };
}

/// The records of the statements array in `value`, if the response has one.
fn recordsIn(value: std.json.Value, statements: Statements) ?[]const std.json.Value {
    if (statements.path.len < 2) return null;
    var node = value;
    for (statements.path[0 .. statements.path.len - 2]) |step| {
        if (step != .property or node != .object) return null;
        node = node.object.get(step.property) orelse return null;
    }
    return if (node == .array) node.array.items else null;
}

fn roleOf(item: std.json.Value, rule: schema.ItemCoverage) statement.Role {
    if (item != .object) return .other;
    const tagged = item.object.get(rule.kind_property) orelse return .other;
    if (tagged != .object) return .other;
    const kind = tagged.object.get("kind") orelse return .other;
    if (kind != .string) return .other;
    for (rule.owning) |name| if (std.mem.eql(u8, kind.string, name)) return .owning;
    for (rule.exclusive) |name| if (std.mem.eql(u8, kind.string, name)) return .exclusive;
    return .other;
}

/// A claim a record lists, read as payload admission reads it; a value that is no integer
/// names no claim. The sole producer parses numbers as strings (`model_envelope.value`).
fn claimOf(value: std.json.Value) i64 {
    if (value != .number_string) return statement.no_claim;
    return payload.exactInteger(value.number_string) catch statement.no_claim;
}

/// ADR 0038 Decision 5: removes the issues of every record the owner deletes natively,
/// judged by the shared statement rule over the response's claims and recognized exact
/// values. The owner deletes such a record after admission, so its text never publishes.
/// A record with an unidentified value is never judged deletable.
fn dropDeleted(a: std.mem.Allocator, value: std.json.Value, statements: Statements, held: []const Held, issues: *std.ArrayList(Collected)) std.mem.Allocator.Error!void {
    const items = recordsIn(value, statements) orelse return;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const property = switch (statements.path[statements.path.len - 1]) {
        .property => |name| name,
        .items => return,
    };
    const prepared = try scratch.alloc(statement.Record, items.len);
    for (items, prepared, 0..) |item, *record, index| {
        var claims: std.ArrayList(i64) = .empty;
        if (item == .object) if (item.object.get(property)) |listed| if (listed == .array) {
            for (listed.array.items) |entry| try claims.append(scratch, claimOf(entry));
        };
        var exact: std.ArrayList(i64) = .empty;
        for (held) |entry| if (entry.record == index) try exact.append(scratch, entry.claim orelse statement.unidentified(index));
        record.* = .{ .role = roleOf(item, statements.rule), .claims = claims.items, .exact = exact.items };
    }
    const removed = try scratch.alloc(bool, items.len);
    @memset(removed, false);
    statement.Rule(statement.Prepared).sequence(.{ .records = prepared }, removed);
    var kept: usize = 0;
    for (issues.items) |entry| {
        if (entry.record) |index| if (index < removed.len and removed[index]) {
            a.free(entry.issue.path);
            continue;
        };
        issues.items[kept] = entry;
        kept += 1;
    }
    issues.shrinkRetainingCapacity(kept);
}
