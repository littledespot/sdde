//! One closed model-text grammar. Recognition rejects encoded insertions in
//! prose; it never converts prose into nodes or grants reference authority.
const std = @import("std");
const strict = @import("strict_json.zig");
const schema = @import("model_result_schema.zig");
pub const SourceText = struct { source_id: @import("reference_identity.zig").SourceId, bytes: []const u8 };
/// Native response selectors declare raw prose leaves independently of their
/// property names. Identifiers, diagnostic details and code receive no selector.
pub const ProseField = struct {
    field: @import("text_field_policy.zig").Field,
    path: []const schema.ChoiceStep,
};
pub const Issue = enum { embedded_insertion_syntax };

pub fn validProseFields(fields: []const ProseField) bool {
    if (fields.len > schema.max_nodes) return false;
    for (fields, 0..) |field, index| {
        if (field.path.len > schema.max_depth) return false;
        for (field.path) |step| if (step == .property and (step.property.len == 0 or !std.unicode.utf8ValidateSlice(step.property))) return false;
        for (fields[0..index]) |prior| if (samePath(prior.path, field.path)) return false;
    }
    return true;
}

pub fn sameProseFields(left: []const ProseField, right: []const ProseField) bool {
    if (left.len != right.len) return false;
    for (left, right) |l, r| if (l.field != r.field or !samePath(l.path, r.path)) return false;
    return true;
}

fn samePath(left: []const schema.ChoiceStep, right: []const schema.ChoiceStep) bool {
    if (left.len != right.len) return false;
    for (left, right) |l, r| {
        if (std.meta.activeTag(l) != std.meta.activeTag(r)) return false;
        if (l == .property and !std.mem.eql(u8, l.property, r.property)) return false;
    }
    return true;
}

/// Every returned property/path/slice belongs to the caller's allocator.
pub fn cloneProseFields(a: std.mem.Allocator, fields: []const ProseField) std.mem.Allocator.Error![]const ProseField {
    const result = try a.alloc(ProseField, fields.len);
    var initialized: usize = 0;
    errdefer {
        for (result[0..initialized]) |field| {
            for (field.path) |step| if (step == .property) a.free(step.property);
            a.free(field.path);
        }
        a.free(result);
    }
    for (fields, result) |field, *destination| {
        const path = try a.dupe(schema.ChoiceStep, field.path);
        var copied: usize = 0;
        errdefer {
            for (path[0..copied]) |step| if (step == .property) a.free(step.property);
            a.free(path);
        }
        for (path) |*step| {
            if (step.* == .property) step.property = try a.dupe(u8, step.property);
            copied += 1;
        }
        destination.* = .{ .field = field.field, .path = path };
        initialized += 1;
    }
    return result;
}

/// Check selectors against the complete native response schema. A union may
/// omit a selected property, but every matching leaf must be prose or null.
pub fn validProseSchema(fields: []const ProseField, root: *const schema.Node) bool {
    if (!validProseFields(fields)) return false;
    for (fields) |field| if (prosePath(root, field.path) != .prose) return false;
    return true;
}

/// A projected part may omit another part's native prose selector entirely.
pub fn compatibleProseSchema(fields: []const ProseField, root: *const schema.Node) bool {
    if (!validProseFields(fields)) return false;
    for (fields) |field| if (prosePath(root, field.path) == .invalid) return false;
    return true;
}

fn prosePath(node: *const schema.Node, path: []const schema.ChoiceStep) enum { absent, prose, invalid } {
    if (node.* == .one_of) {
        var found = false;
        for (node.one_of) |variant| switch (prosePath(variant, path)) {
            .absent => {},
            .invalid => return .invalid,
            .prose => found = true,
        };
        return if (found) .prose else .absent;
    }
    if (node.* == .null_value) return .absent;
    if (path.len == 0) return if (node.* == .string) .prose else .invalid;
    return switch (path[0]) {
        .property => |name| if (node.* == .object) result: {
            for (node.object) |property| if (std.mem.eql(u8, property.name, name)) break :result prosePath(property.schema, path[1..]);
            break :result .absent;
        } else .absent,
        .items => if (node.* == .array) prosePath(node.array.items, path[1..]) else .absent,
    };
}

/// Select only explicit native prose fields. Missing variant properties and
/// malformed shapes remain the ordinary payload validator's responsibility.
pub fn checkProseFields(a: std.mem.Allocator, value: std.json.Value, fields: []const ProseField, sources: []const SourceText) std.mem.Allocator.Error!?Issue {
    for (fields) |field| if (try checkSelected(a, value, field.path, sources)) |issue| return issue;
    return null;
}

fn checkSelected(a: std.mem.Allocator, value: std.json.Value, path: []const schema.ChoiceStep, sources: []const SourceText) std.mem.Allocator.Error!?Issue {
    if (path.len == 0) return if (value == .string) checkProse(a, value.string, sources) else null;
    switch (path[0]) {
        .property => |name| if (value == .object) {
            if (value.object.get(name)) |child| return checkSelected(a, child, path[1..], sources);
        },
        .items => if (value == .array) {
            for (value.array.items) |child| if (try checkSelected(a, child, path[1..], sources)) |issue| return issue;
        },
    }
    return null;
}

pub fn validSources(sources: []const SourceText) bool {
    for (sources, 0..) |source, index| {
        if (source.source_id.ordinal == 0 or !std.unicode.utf8ValidateSlice(source.bytes)) return false;
        for (sources[0..index]) |prior| if (prior.source_id.ordinal == source.source_id.ordinal) return false;
    }
    return true;
}

/// Exact wire-object bytes must occur in an original captured source. Matching
/// display text, model output, guidance and derived claims cannot grant this
/// exception. Whitespace/escaping within the object is never canonicalized.
pub fn checkProse(a: std.mem.Allocator, prose: []const u8, sources: []const SourceText) std.mem.Allocator.Error!?Issue {
    var scan: ProseScan = .{ .prose = prose, .sources = sources };
    while (try scan.next(a)) |span| if (!span.source_backed) return .embedded_insertion_syntax;
    return null;
}

/// Exact source-backed grammar objects remain byte-for-byte quotations inside
/// prose. Normalization of surrounding prose uses the existing Unicode owner.
/// This does not accept unbacked grammar objects or convert text to insertions;
/// callers still apply checkProse and their native composition validators.
pub fn normalizeProse(a: std.mem.Allocator, prose: []const u8, sources: []const SourceText, normalizer: @import("../ports/unicode_normalizer.zig").Normalizer) @import("naming_policy.zig").Error![]const u8 {
    const naming = @import("naming_policy.zig");
    if (!validSources(sources)) return error.InvalidNamingPolicy;
    var scan: ProseScan = .{ .prose = prose, .sources = sources };
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(a);
    var copied: usize = 0;
    while (try scan.next(a)) |span| {
        if (!span.source_backed) continue;
        const before = try naming.normalizeNfc(a, prose[copied..span.start], normalizer);
        defer a.free(before);
        try result.appendSlice(a, before);
        try result.appendSlice(a, prose[span.start..span.end]);
        copied = span.end;
    }
    const after = try naming.normalizeNfc(a, prose[copied..], normalizer);
    defer a.free(after);
    try result.appendSlice(a, after);
    return result.toOwnedSlice(a);
}

const ProseSpan = struct { start: usize, end: usize, source_backed: bool };

/// Recognition, exact source matching and nested-object handling have one
/// owner for rejection and normalization. Returned spans borrow only prose.
const ProseScan = struct {
    prose: []const u8,
    sources: []const SourceText,
    cursor: usize = 0,

    fn next(self: *ProseScan, a: std.mem.Allocator) std.mem.Allocator.Error!?ProseSpan {
        while (std.mem.indexOfScalarPos(u8, self.prose, self.cursor, '{')) |opening| {
            self.cursor = opening + 1;
            const end = objectEnd(self.prose, opening) orelse continue;
            const bytes = self.prose[opening..end];
            var parsed = strict.parse(a, bytes, .{ .maximum_depth = schema.max_json_depth }, false, null) catch |err| {
                if (err == error.OutOfMemory) return error.OutOfMemory;
                continue;
            };
            defer parsed.deinit();
            if (!wireObject(parsed.value)) continue;
            const source_backed = for (self.sources) |source| {
                if (std.mem.indexOf(u8, source.bytes, bytes) != null) break true;
            } else false;
            // A complete recognized grammar object owns its nested objects.
            self.cursor = end;
            return .{ .start = opening, .end = end, .source_backed = source_backed };
        }
        return null;
    }
};

fn objectEnd(bytes: []const u8, start: usize) ?usize {
    var depth: usize = 0;
    var quoted = false;
    var escaped = false;
    for (bytes[start..], start..) |byte, index| {
        if (quoted) {
            if (escaped) escaped = false else if (byte == '\\') escaped = true else if (byte == '"') quoted = false;
        } else switch (byte) {
            '"' => quoted = true,
            '{', '[' => {
                if (depth == schema.max_json_depth) return null;
                depth += 1;
            },
            '}', ']' => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) return index + 1;
            },
            else => {},
        }
    }
    return null;
}

fn positive(value: std.json.Value) bool {
    if (value != .number_string) return false;
    const number = @import("model_payload_schema.zig").exactInteger(value.number_string) catch return false;
    return number > 0 and number <= std.math.maxInt(u32);
}
fn insertion(value: std.json.Value) bool {
    if (value != .object) return false;
    const kind = value.object.get("kind") orelse return false;
    if (kind != .string) return false;
    if (std.mem.eql(u8, kind.string, "exact_copy")) {
        if (value.object.count() == 1) return true; // Engine-constructed singleton handle.
        return value.object.count() == 2 and positive(value.object.get("claim_id") orelse return false);
    }
    const field: []const u8 = if (std.mem.eql(u8, kind.string, "passive")) "passive_literal_id" else if (std.mem.eql(u8, kind.string, "source")) "source_id" else return false;
    return value.object.count() == 2 and positive(value.object.get(field) orelse return false);
}
fn wireObject(value: std.json.Value) bool {
    if (insertion(value)) return true;
    if (value != .object or value.object.count() != 1) return false;
    const fragments = value.object.get("fragments") orelse return false;
    if (fragments != .array or fragments.array.items.len == 0) return false;
    for (fragments.array.items) |fragment| {
        if (fragment == .string) {
            if (fragment.string.len == 0) return false;
        } else if (!insertion(fragment)) return false;
    }
    return true;
}

/// The closed string-or-fragments shape declares a model text value. Plain
/// strings in unrelated schemas (identifiers, diagnostics, code) are unaffected.
fn textContract(node: *const schema.Node) bool {
    if (node.* != .one_of or node.one_of.len != 2) return false;
    var prose = false;
    var composition = false;
    for (node.one_of) |variant| switch (variant.*) {
        .string => prose = true,
        .object => |properties| {
            if (properties.len != 1 or !properties[0].required or !std.mem.eql(u8, properties[0].name, "fragments") or properties[0].schema.* != .array) return false;
            const items = properties[0].schema.array.items;
            if (items.* != .string and items.* != .one_of) return false;
            composition = true;
        },
        else => return false,
    };
    return prose and composition;
}

/// Traverse only schema-declared model-text leaves. Shape validation remains
/// with the allocation-free payload validator; malformed shapes are ignored
/// here and rejected there, without changing their existing diagnostics.
pub fn checkValue(a: std.mem.Allocator, value: std.json.Value, node: *const schema.Node, sources: []const SourceText) std.mem.Allocator.Error!?Issue {
    if (textContract(node)) {
        if (value == .string) return checkProse(a, value.string, sources);
        if (value == .object) if (value.object.get("fragments")) |fragments| if (fragments == .array) {
            // Adjacent prose fragments concatenate before text validation. A
            // split wire object cannot escape by occupying several strings.
            var prose: std.ArrayList(u8) = .empty;
            defer prose.deinit(a);
            for (fragments.array.items) |fragment| {
                if (fragment == .string) {
                    try prose.appendSlice(a, fragment.string);
                } else {
                    if (try checkProse(a, prose.items, sources)) |issue| return issue;
                    prose.clearRetainingCapacity();
                }
            }
            return checkProse(a, prose.items, sources);
        };
        return null;
    }
    switch (node.*) {
        .object => |properties| if (value == .object) {
            for (properties) |property| if (value.object.get(property.name)) |child| {
                if (try checkValue(a, child, property.schema, sources)) |issue| return issue;
            };
        },
        .array => |array| if (value == .array) {
            for (value.array.items) |child| if (try checkValue(a, child, array.items, sources)) |issue| return issue;
        },
        .one_of => |variants| {
            for (variants) |variant| {
                if (@import("model_payload_schema.zig").validateValue(@import("model_envelope.zig").value(&value), variant) == null) return checkValue(a, value, variant, sources);
            }
        },
        else => {},
    }
    return null;
}
