//! Mechanical editable-view codec. Parsing never creates provenance, resolves
//! entity applicability or turns a supplied document into workflow authority.
const std = @import("std");
const spec = @import("specification.zig");
pub const Error = spec.Error || std.mem.Allocator.Error;
const title_prefix = "# Feature Specification: ";
const scenarios = "## User Scenarios & Testing _(mandatory)_";
const story = "### Primary User Story";
const requirements = "## Requirements _(mandatory)_";
const scope = "### Assumptions & Scope Boundaries";

/// The caller has already projected typed values with exact display spans.
/// Rendering requires assigned IDs; it has no lookup or side-effect capability.
pub fn render(allocator: std.mem.Allocator, document: spec.CapturedDocument) Error![]const u8 {
    try spec.validateDocument(document, true);
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    try field(w, title_prefix, document.display_name);
    try line(w, scenarios);
    try line(w, story);
    try field(w, "", document.primary_user_story);
    inline for (comptime std.meta.tags(spec.Kind)) |kind| {
        if (kind == .functional_requirement) try line(w, requirements);
        if (kind == .assumption and hasScope(document)) try line(w, scope);
        if (sectionPresent(document, kind)) {
            try line(w, kind.heading());
            for (document.records) |record| {
                if (record.content != kind) continue;
                const content = @field(record.content, @tagName(kind));
                if (comptime kind == .acceptance_criterion) {
                    try write(w, "- **");
                    try identity(w, record.id.?);
                    try write(w, "**: **Given** ");
                    try scalar(w, content.given);
                    try write(w, ", **When** ");
                    try scalar(w, content.when);
                    try write(w, ", **Then** ");
                    try scalar(w, content.then);
                    try write(w, "\n\n");
                } else if (comptime @hasField(@TypeOf(content), "text")) {
                    try write(w, "- **");
                    try identity(w, record.id.?);
                    try write(w, "**: ");
                    try field(w, "", content.text);
                } else {
                    try write(w, "**");
                    try identity(w, record.id.?);
                    try write(w, "**\n");
                    inline for (@typeInfo(@TypeOf(content)).@"struct".fields) |f| {
                        const value = @field(content, f.name);
                        if (comptime f.type == spec.Scalar) {
                            try inlineField(w, label(f.name), value);
                        } else {
                            for (value) |relationship| try inlineField(w, label(f.name), relationship);
                        }
                    }
                    try write(w, "\n");
                }
            }
        }
    }
    // Helpers leave one blank line between blocks, not at document EOF.
    const bytes = try out.toOwnedSlice();
    defer allocator.free(bytes);
    return allocator.dupe(u8, bytes[0 .. bytes.len - 1]);
}

/// Caller-owned arena retains the complete captured value on every path.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) Error!spec.CapturedDocument {
    if (!std.unicode.utf8ValidateSlice(bytes) or std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) return error.InvalidSpecification;
    var cursor: Cursor = .{ .bytes = bytes };
    const title = try readField(allocator, &cursor, title_prefix);
    try cursor.expect(scenarios);
    try cursor.expect(story);
    const primary = try readField(allocator, &cursor, "");
    var records: std.ArrayList(spec.CapturedRecord) = .empty;
    var entity_section: @FieldType(spec.CapturedDocument, "entity_section") = .omitted;
    var scope_present = false;
    var scope_records: usize = 0;
    inline for (comptime std.meta.tags(spec.Kind)) |kind| {
        if (kind == .functional_requirement) try cursor.expect(requirements);
        if (kind == .assumption and cursor.is(scope)) {
            try cursor.expect(scope);
            scope_present = true;
        }
        if (mandatory(kind) or cursor.is(kind.heading())) {
            if (isScope(kind) and !scope_present) return error.InvalidSpecification;
            try cursor.expect(kind.heading());
            if (kind == .entity) entity_section = .present;
            const Body = @FieldType(spec.Content(spec.Scalar), @tagName(kind));
            const start = records.items.len;
            while (cursor.peek()) |next| {
                if (std.mem.startsWith(u8, next, "#")) break;
                const header = try cursor.take();
                var body: Body = undefined;
                const id: ?spec.Id = if (comptime kind == .acceptance_criterion or @hasField(Body, "text")) blk: {
                    if (!std.mem.startsWith(u8, header, "- **")) return error.InvalidSpecification;
                    const end = std.mem.indexOf(u8, header[4..], "**: ") orelse return error.InvalidSpecification;
                    const key = try readId(header[4 .. 4 + end], kind);
                    if (comptime kind == .acceptance_criterion) {
                        body = try acceptance(allocator, try continuedBytes(allocator, &cursor, header[8 + end ..]));
                    } else body.text = try continuation(allocator, &cursor, header[8 + end ..]);
                    break :blk key;
                } else blk: {
                    if (!std.mem.startsWith(u8, header, "**") or !std.mem.endsWith(u8, header, "**") or header.len <= 4) return error.InvalidSpecification;
                    const key = try readId(header[2 .. header.len - 2], kind);
                    inline for (@typeInfo(Body).@"struct".fields) |f| {
                        if (comptime f.type == spec.Scalar) {
                            @field(body, f.name) = try readField(allocator, &cursor, label(f.name));
                        } else {
                            var relationships: std.ArrayList(spec.Scalar) = .empty;
                            while (cursor.peek()) |peek| {
                                if (!std.mem.startsWith(u8, peek, label(f.name))) break;
                                try relationships.append(allocator, try readField(allocator, &cursor, label(f.name)));
                            }
                            @field(body, f.name) = try relationships.toOwnedSlice(allocator);
                        }
                    }
                    break :blk key;
                };
                try records.append(allocator, .{ .id = id, .content = @unionInit(spec.Content(spec.Scalar), @tagName(kind), body) });
            }
            if (!mandatory(kind) and kind != .entity and records.items.len == start) return error.InvalidSpecification;
            if (isScope(kind)) scope_records += records.items.len - start;
        }
    }
    if (scope_present and scope_records == 0) return error.InvalidSpecification;
    if (cursor.peek() != null) return error.InvalidSpecification;
    const document: spec.CapturedDocument = .{
        .display_name = title,
        .primary_user_story = primary,
        .records = try records.toOwnedSlice(allocator),
        .entity_section = entity_section,
    };
    try spec.validateDocument(document, false);
    return document;
}

fn mandatory(kind: spec.Kind) bool {
    return spec.requiresRecords(kind);
}
fn isScope(kind: spec.Kind) bool {
    return kind == .assumption or kind == .non_goal or kind == .prohibited_behavior;
}
fn sectionPresent(document: spec.CapturedDocument, kind: spec.Kind) bool {
    if (mandatory(kind)) return true;
    if (kind == .entity) return document.entity_section == .present;
    for (document.records) |record| if (record.content == kind) return true;
    return false;
}
fn hasScope(document: spec.CapturedDocument) bool {
    for (document.records) |record| if (isScope(record.content)) return true;
    return false;
}

fn acceptance(allocator: std.mem.Allocator, input: []const u8) Error!@FieldType(spec.Content(spec.Scalar), "acceptance_criterion") {
    const labels = [_][]const u8{ "**Given** ", "**When** ", "**Then** " };
    if (!std.mem.startsWith(u8, input, labels[0])) return error.InvalidSpecification;
    // Exact copy spans may themselves contain label-shaped text. The shared
    // Markdown scanner, not a substring split, determines those boundaries.
    const frame = "field ";
    const framed = try std.mem.concat(allocator, u8, &.{ frame, input });
    const spans = try @import("markdown_code_spans.zig").scan(allocator, framed);
    defer allocator.free(spans);
    var positions: [3]usize = undefined;
    var found: usize = 0;
    var span_index: usize = 0;
    for (input, 0..) |_, offset| {
        while (span_index < spans.len and spans[span_index].end <= offset + frame.len) span_index += 1;
        if (span_index < spans.len and spans[span_index].start <= offset + frame.len) continue;
        for (labels, 0..) |marker, index| if (std.mem.startsWith(u8, input[offset..], marker)) {
            if (index != found or (index != 0 and (offset < 2 or !std.mem.eql(u8, input[offset - 2 .. offset], ", ")))) return error.InvalidSpecification;
            positions[index] = offset;
            found += 1;
        };
    }
    if (found != labels.len) return error.InvalidSpecification;
    return .{
        .given = try unescape(allocator, input[labels[0].len .. positions[1] - 2]),
        .when = try unescape(allocator, input[positions[1] + labels[1].len .. positions[2] - 2]),
        .then = try unescape(allocator, input[positions[2] + labels[2].len ..]),
    };
}

fn label(comptime name: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, name, "condition")) return "- **CONDITION** ";
    if (comptime std.mem.eql(u8, name, "expected_outcome")) return "- **EXPECTED OUTCOME** ";
    if (comptime std.mem.eql(u8, name, "name")) return "- **NAME** ";
    if (comptime std.mem.eql(u8, name, "business_meaning")) return "- **BUSINESS MEANING** ";
    if (comptime std.mem.eql(u8, name, "relationships")) return "- **RELATIONSHIP** ";
    @compileError("Unregistered specification field label");
}

fn write(w: *std.Io.Writer, bytes: []const u8) Error!void {
    w.writeAll(bytes) catch return error.OutOfMemory;
}
fn line(w: *std.Io.Writer, bytes: []const u8) Error!void {
    try write(w, bytes);
    try write(w, "\n\n");
}
fn identity(w: *std.Io.Writer, id: spec.Id) Error!void {
    w.print("{s}-{d:0>3}", .{ id.kind.prefix(), id.ordinal }) catch return error.OutOfMemory;
}
fn field(w: *std.Io.Writer, prefix: []const u8, value: spec.Scalar) Error!void {
    try inlineField(w, prefix, value);
    try write(w, "\n");
}
fn inlineField(w: *std.Io.Writer, prefix: []const u8, value: spec.Scalar) Error!void {
    try write(w, prefix);
    try scalar(w, value);
    try write(w, "\n");
}
fn scalar(w: *std.Io.Writer, value: spec.Scalar) Error!void {
    var offset: usize = 0;
    for (value.code_spans) |span| {
        try literal(w, value.bytes[offset..span.start]);
        try code(w, value.bytes[span.start..span.end]);
        offset = span.end;
    }
    try literal(w, value.bytes[offset..]);
}
pub fn literal(w: *std.Io.Writer, bytes: []const u8) Error!void {
    for (bytes) |byte| switch (byte) {
        '\n' => try write(w, "&#10;"),
        '\r' => try write(w, "&#13;"),
        '\t' => try write(w, "&#9;"),
        else => {
            if (std.ascii.isPunctuation(byte)) try write(w, "\\");
            w.writeByte(byte) catch return error.OutOfMemory;
        },
    };
}
pub fn code(w: *std.Io.Writer, bytes: []const u8) Error!void {
    var longest: usize = 0;
    var run: usize = 0;
    for (bytes) |byte| {
        run = if (byte == '`') run + 1 else 0;
        longest = @max(longest, run);
    }
    const padded = bytes[0] == '`' or bytes[bytes.len - 1] == '`' or
        (bytes[0] == ' ' and bytes[bytes.len - 1] == ' ' and std.mem.trim(u8, bytes, " ").len != 0);
    for (0..longest + 1) |_| try write(w, "`");
    if (padded) try write(w, " ");
    for (bytes) |byte| {
        w.writeByte(byte) catch return error.OutOfMemory;
        if (byte == '\n') try write(w, "  ");
    }
    if (padded) try write(w, " ");
    for (0..longest + 1) |_| try write(w, "`");
}

const Cursor = struct {
    bytes: []const u8,
    offset: usize = 0,
    fn raw(self: *Cursor) ?[]const u8 {
        if (self.offset == self.bytes.len) return null;
        const start = self.offset;
        const end = if (std.mem.indexOfScalarPos(u8, self.bytes, start, '\n')) |at| at else self.bytes.len;
        self.offset = end + @intFromBool(end < self.bytes.len);
        return self.bytes[start..end];
    }
    fn peek(self: *Cursor) ?[]const u8 {
        var copy = self.*;
        while (copy.raw()) |value| {
            if (value.len == 0) continue;
            return value;
        }
        return null;
    }
    fn take(self: *Cursor) Error![]const u8 {
        while (self.raw()) |value| if (value.len != 0) return value;
        return error.InvalidSpecification;
    }
    fn expect(self: *Cursor, expected: []const u8) Error!void {
        if (!std.mem.eql(u8, try self.take(), expected)) return error.InvalidSpecification;
    }
    fn is(self: *Cursor, expected: []const u8) bool {
        return std.mem.eql(u8, self.peek() orelse return false, expected);
    }
};
fn readId(bytes: []const u8, kind: spec.Kind) Error!?spec.Id {
    // A new user-authored record may omit the ordinal, never forge an old ID.
    if (std.mem.eql(u8, bytes, kind.prefix())) return null;
    const id = spec.Id.parse(bytes) orelse return error.InvalidSpecification;
    if (id.kind != kind) return error.InvalidSpecification;
    return id;
}
fn readField(allocator: std.mem.Allocator, cursor: *Cursor, prefix: []const u8) Error!spec.Scalar {
    const first = try cursor.take();
    if (!std.mem.startsWith(u8, first, prefix)) return error.InvalidSpecification;
    return continuation(allocator, cursor, first[prefix.len..]);
}
fn continuation(allocator: std.mem.Allocator, cursor: *Cursor, first: []const u8) Error!spec.Scalar {
    return unescape(allocator, try continuedBytes(allocator, cursor, first));
}
fn continuedBytes(allocator: std.mem.Allocator, cursor: *Cursor, first: []const u8) Error![]const u8 {
    var joined: std.ArrayList(u8) = .empty;
    try joined.appendSlice(allocator, first);
    while (true) {
        var look = cursor.*;
        const next = look.raw() orelse break;
        if (!std.mem.startsWith(u8, next, "  ")) break;
        cursor.* = look;
        try joined.append(allocator, '\n');
        try joined.appendSlice(allocator, next[2..]);
    }
    return joined.toOwnedSlice(allocator);
}
fn unescape(allocator: std.mem.Allocator, input: []const u8) Error!spec.Scalar {
    // Give the shared source parser an inline context, not a possible fence at
    // column zero. It alone owns backtick matching and escaped delimiters.
    const frame = "field ";
    const framed = try std.mem.concat(allocator, u8, &.{ frame, input });
    const ranges = try @import("markdown_code_spans.zig").scan(allocator, framed);
    defer allocator.free(ranges);
    var range_index: usize = 0;
    var bytes: std.ArrayList(u8) = .empty;
    var spans: std.ArrayList(spec.CodeSpan) = .empty;
    var index: usize = 0;
    while (index < input.len) {
        if (input[index] == '\\') {
            index += 1;
            if (index == input.len or !std.ascii.isPunctuation(input[index])) return error.InvalidSpecification;
        } else if (input[index] == '&') {
            var matched = false;
            inline for (.{ .{ "&#10;", '\n' }, .{ "&#13;", '\r' }, .{ "&#9;", '\t' } }) |entity| {
                if (std.mem.startsWith(u8, input[index..], entity[0])) {
                    try bytes.append(allocator, entity[1]);
                    index += entity[0].len;
                    matched = true;
                }
            }
            if (matched) continue;
        } else if (input[index] == '`') {
            if (range_index == ranges.len) return error.InvalidSpecification;
            const range = ranges[range_index];
            const start = range.start - frame.len;
            const end = range.end - frame.len;
            if (start <= index or end > input.len) return error.InvalidSpecification;
            const count = start - index;
            for (input[index..start]) |byte| if (byte != '`') return error.InvalidSpecification;
            if (count > input.len - end) return error.InvalidSpecification;
            var value = input[start..end];
            if (value.len >= 2 and value[0] == ' ' and value[value.len - 1] == ' ' and std.mem.trim(u8, value, " ").len != 0) value = value[1 .. value.len - 1];
            const offset = bytes.items.len;
            try bytes.appendSlice(allocator, value);
            try spans.append(allocator, .{ .start = offset, .end = bytes.items.len });
            index = end + count;
            range_index += 1;
            continue;
        }
        try bytes.append(allocator, input[index]);
        index += 1;
    }
    return .{ .bytes = try bytes.toOwnedSlice(allocator), .code_spans = try spans.toOwnedSlice(allocator) };
}
