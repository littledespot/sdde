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
    try write(w, title_prefix);
    try scalar(w, document.display_name, .inline_text, .heading);
    try write(w, "\n\n");
    try line(w, scenarios);
    try line(w, story);
    try scalar(w, document.primary_user_story, .block_start, .text);
    try write(w, "\n\n");
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
                    try scalar(w, content.given, .inline_text, .text);
                    try write(w, clauseSeparator(content.given));
                    try write(w, "**When** ");
                    try scalar(w, content.when, .inline_text, .text);
                    try write(w, clauseSeparator(content.when));
                    try write(w, "**Then** ");
                    try scalar(w, content.then, .inline_text, .text);
                    try write(w, "\n\n");
                    try sourceLine(w, nested_source, record.sources);
                } else if (comptime @hasField(@TypeOf(content), "text")) {
                    try write(w, "- **");
                    try identity(w, record.id.?);
                    try write(w, "**: ");
                    try field(w, "", content.text);
                    try sourceLine(w, nested_source, record.sources);
                } else {
                    try write(w, "**");
                    try identity(w, record.id.?);
                    try write(w, "**\n");
                    inline for (@typeInfo(@TypeOf(content)).@"struct".fields) |f| try inlineField(w, label(f.name), @field(content, f.name));
                    if (record.outcome) |outcome| try inlineField(w, outcome_label, outcome);
                    if (record.related.len != 0) {
                        try write(w, related_label);
                        for (record.related, 0..) |id, at| {
                            if (at != 0) try write(w, ", ");
                            try identity(w, id);
                        }
                        try write(w, "\n");
                    }
                    if (record.sources.len != 0) {
                        try write(w, field_source);
                        try sourceList(w, record.sources);
                        try write(w, "\n");
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
                var related: []const spec.Id = &.{};
                var outcome: ?spec.Scalar = null;
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
                    inline for (@typeInfo(Body).@"struct".fields) |f| @field(body, f.name) = try readField(allocator, &cursor, label(f.name));
                    if (comptime kind.showsOutcome()) outcome = try readField(allocator, &cursor, outcome_label);
                    if (comptime kind == .entity) related = try readRelated(allocator, &cursor);
                    break :blk key;
                };
                const sources: []const spec.SourceLines = if (comptime kind.showsSources())
                    try readSources(allocator, &cursor, if (comptime kind == .entity) field_source else nested_source)
                else
                    &.{};
                try records.append(allocator, .{ .id = id, .content = @unionInit(spec.Content(spec.Scalar), @tagName(kind), body), .sources = sources, .related = related, .outcome = outcome });
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
    var separators: [3]usize = .{ 0, 0, 0 };
    var found: usize = 0;
    var span_index: usize = 0;
    for (input, 0..) |_, offset| {
        while (span_index < spans.len and spans[span_index].end <= offset + frame.len) span_index += 1;
        if (span_index < spans.len and spans[span_index].start <= offset + frame.len) continue;
        for (labels, 0..) |marker, index| if (std.mem.startsWith(u8, input[offset..], marker)) {
            if (index != found) return error.InvalidSpecification;
            // An escaped comma ends the clause's own text, so only an unescaped ", " separates.
            if (index != 0) separators[index] = if (offset >= 2 and std.mem.eql(u8, input[offset - 2 .. offset], ", ") and !escaped(input, offset - 2)) 2 else if (offset >= 1 and input[offset - 1] == ' ') 1 else return error.InvalidSpecification;
            positions[index] = offset;
            found += 1;
        };
    }
    if (found != labels.len) return error.InvalidSpecification;
    if (positions[1] - separators[1] < labels[0].len or positions[2] - separators[2] < positions[1] + labels[1].len) return error.InvalidSpecification;
    const given = try unescape(allocator, input[labels[0].len .. positions[1] - separators[1]]);
    const when = try unescape(allocator, input[positions[1] + labels[1].len .. positions[2] - separators[2]]);
    // Only the separator the renderer derives from each clause round-trips.
    if (!std.mem.eql(u8, clauseSeparator(given), input[positions[1] - separators[1] .. positions[1]]) or
        !std.mem.eql(u8, clauseSeparator(when), input[positions[2] - separators[2] .. positions[2]])) return error.InvalidSpecification;
    return .{ .given = given, .when = when, .then = try unescape(allocator, input[positions[2] + labels[2].len ..]) };
}

/// Whether the byte at `index` follows an odd run of backslashes, so it is escaped text.
fn escaped(input: []const u8, index: usize) bool {
    var count: usize = 0;
    while (count < index and input[index - count - 1] == '\\') count += 1;
    return count % 2 == 1;
}

/// A clause that already ends in terminal punctuation is followed by a space, not a
/// comma, so its own bytes, including an exact value such as `Done.`, stay unchanged.
/// The boundary owner holds the one terminal-punctuation policy (§23).
fn clauseSeparator(clause: spec.Scalar) []const u8 {
    return if (@import("exact_value_boundary.zig").endsWithTerminal(clause.bytes)) " " else ", ";
}

/// §23 source lines. A criterion or requirement shows its line as a nested item after
/// a blank line, because a two-space line directly under a field continues that
/// field; an entity shows it as its last field line.
const nested_source = "  - Source: ";
const field_source = "- Source: ";

fn sourceLine(w: *std.Io.Writer, prefix: []const u8, files: []const spec.SourceLines) Error!void {
    if (files.len == 0) return;
    try write(w, prefix);
    try sourceList(w, files);
    try write(w, "\n\n");
}

/// `path` line N, or `path` lines A–B, C; several files join with "; ".
fn sourceList(w: *std.Io.Writer, files: []const spec.SourceLines) Error!void {
    for (files, 0..) |file, index| {
        if (index != 0) try write(w, "; ");
        try code(w, file.path);
        try write(w, if (singleLine(file)) " line " else " lines ");
        for (file.ranges, 0..) |range, at| {
            if (at != 0) try write(w, ", ");
            w.print("{d}", .{range.first}) catch return error.OutOfMemory;
            if (range.last != range.first) w.print("–{d}", .{range.last}) catch return error.OutOfMemory;
        }
    }
}
fn singleLine(file: spec.SourceLines) bool {
    return file.ranges.len == 1 and file.ranges[0].first == file.ranges[0].last;
}

/// An edge case's outcome line, after its condition: the Then of the acceptance criterion it
/// links to, derived by the projection. Like the source line it is a display that never becomes
/// provenance, so publication's byte comparison with the projection owns its content.
const outcome_label = "- **EXPECTED OUTCOME** ";

/// An entity's related-statements line, between its fields and its source line. It lists
/// statement IDs only: like the source line it is a display that never becomes provenance,
/// so the document check owns its shape and publication's byte comparison with the
/// projection owns its derivation.
const related_label = "- **RELATED STATEMENTS** ";

fn readRelated(allocator: std.mem.Allocator, cursor: *Cursor) Error![]const spec.Id {
    const next = cursor.peek() orelse return &.{};
    if (!std.mem.startsWith(u8, next, related_label)) return &.{};
    var ids: std.ArrayList(spec.Id) = .empty;
    var parts = std.mem.splitSequence(u8, (try cursor.take())[related_label.len..], ", ");
    while (parts.next()) |part| {
        const id = spec.Id.parse(part) orelse return error.InvalidSpecification;
        try ids.append(allocator, id);
    }
    return ids.toOwnedSlice(allocator);
}

/// An absent line means no shown sources. A present line must have the renderer's
/// structure; like every field, an escaped or longer-fenced spelling of it parses but
/// re-renders differently, so publication's byte checks reject it. It is a display
/// that never becomes provenance.
fn readSources(allocator: std.mem.Allocator, cursor: *Cursor, prefix: []const u8) Error![]const spec.SourceLines {
    const next = cursor.peek() orelse return &.{};
    if (!std.mem.startsWith(u8, next, prefix)) return &.{};
    const input = (try cursor.take())[prefix.len..];
    const listed = try unescape(allocator, input);
    var files: std.ArrayList(spec.SourceLines) = .empty;
    var offset: usize = 0;
    for (listed.code_spans, 0..) |span, index| {
        if (span.start != offset) return error.InvalidSpecification;
        const tail_end = if (index + 1 == listed.code_spans.len) listed.bytes.len else listed.code_spans[index + 1].start;
        var tail = listed.bytes[span.end..tail_end];
        if (index + 1 != listed.code_spans.len) {
            if (!std.mem.endsWith(u8, tail, "; ")) return error.InvalidSpecification;
            tail = tail[0 .. tail.len - 2];
        }
        const file: spec.SourceLines = .{ .path = listed.bytes[span.start..span.end], .ranges = try readRanges(allocator, tail) };
        try files.append(allocator, file);
        offset = tail_end;
    }
    if (files.items.len == 0) return error.InvalidSpecification;
    return files.toOwnedSlice(allocator);
}
fn readRanges(allocator: std.mem.Allocator, input: []const u8) Error![]const spec.LineRange {
    const single = std.mem.startsWith(u8, input, " line ");
    if (!single and !std.mem.startsWith(u8, input, " lines ")) return error.InvalidSpecification;
    var ranges: std.ArrayList(spec.LineRange) = .empty;
    var parts = std.mem.splitSequence(u8, input[if (single) " line ".len else " lines ".len..], ", ");
    while (parts.next()) |part| {
        const dash = std.mem.indexOf(u8, part, "–");
        const first = try lineNumber(if (dash) |at| part[0..at] else part);
        const last = if (dash) |at| try lineNumber(part[at + "–".len ..]) else first;
        if (dash != null and last <= first) return error.InvalidSpecification;
        try ranges.append(allocator, .{ .first = first, .last = last });
    }
    const file: spec.SourceLines = .{ .path = "", .ranges = ranges.items };
    if (single != singleLine(file)) return error.InvalidSpecification;
    return ranges.toOwnedSlice(allocator);
}
fn lineNumber(digits: []const u8) Error!u32 {
    if (digits.len == 0 or digits[0] == '0') return error.InvalidSpecification;
    for (digits) |digit| if (!std.ascii.isDigit(digit)) return error.InvalidSpecification;
    return std.fmt.parseInt(u32, digits, 10) catch error.InvalidSpecification;
}

fn label(comptime name: []const u8) []const u8 {
    if (comptime std.mem.eql(u8, name, "condition")) return "- **CONDITION** ";
    if (comptime std.mem.eql(u8, name, "name")) return "- **NAME** ";
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
    try scalar(w, value, .inline_text, .text);
    try write(w, "\n");
}
/// One value: its literal runs escaped, its exact spans as inline code. What ends the value
/// stays escaped when it would read as more than text: a comma, so an acceptance-criterion
/// clause never reads as joined by ", ", and, on a heading line, a closing run of `#`.
fn scalar(w: *std.Io.Writer, value: spec.Scalar, position: Position, context: Context) Error!void {
    var offset: usize = 0;
    for (value.code_spans) |span| {
        try escape(w, value.bytes[offset..span.start], if (offset == 0) position else .inline_text, null);
        try code(w, value.bytes[span.start..span.end]);
        offset = span.end;
    }
    try escape(w, value.bytes[offset..], if (offset == 0) position else .inline_text, .{ .context = context, .begins_value = offset == 0 });
}

/// Where a text sits on its line. Text that opens a block line, such as the primary story or
/// a list item's content, could read as a heading or a list marker; text after other text
/// could not.
pub const Position = enum { inline_text, block_start };

/// What a value is the text of. A heading line ends at a closing run of `#`.
const Context = enum { text, heading };

/// How a run ends its value. A value begins after its field's prefix, which ends in a space.
const End = struct { context: Context, begins_value: bool };

/// The one place text is escaped (§23.1). A backslash precedes each byte Markdown reads as
/// inline markup, and, as the first text of a block line only, a byte that opens a heading,
/// a list item or an ordered list item. Line breaks and tabs are written as entities. Every
/// other byte, ordinary punctuation included, is written as it is.
pub fn literal(w: *std.Io.Writer, bytes: []const u8, position: Position) Error!void {
    return escape(w, bytes, position, null);
}

/// `end` is set for the run that ends its value.
fn escape(w: *std.Io.Writer, bytes: []const u8, position: Position, end: ?End) Error!void {
    const first = if (position == .block_start) std.mem.indexOfNone(u8, bytes, " ") orelse bytes.len else bytes.len;
    const hashes = if (end) |ending| (if (ending.context == .heading) closingHashes(bytes, ending.begins_value) else null) else null;
    for (bytes, 0..) |byte, index| switch (byte) {
        '\n' => try write(w, "&#10;"),
        '\r' => try write(w, "&#13;"),
        '\t' => try write(w, "&#9;"),
        else => {
            const closing = if (hashes) |run| index >= run.start and index < run.end else false;
            const final_comma = end != null and byte == ',' and index + 1 == bytes.len;
            if (markup(byte) or opensBlock(bytes, first, index) or closing or final_comma) try write(w, "\\");
            w.writeByte(byte) catch return error.OutOfMemory;
        },
    };
}

const Hashes = struct { start: usize, end: usize };

/// The closing run of `#` of a heading's text. Markdown ends the heading before a run of `#`
/// that follows a space, or begins the text when `begins_value`, and is followed by spaces only.
fn closingHashes(bytes: []const u8, begins_value: bool) ?Hashes {
    var end = bytes.len;
    while (end > 0 and bytes[end - 1] == ' ') end -= 1;
    var start = end;
    while (start > 0 and bytes[start - 1] == '#') start -= 1;
    if (start == end) return null;
    if (if (start == 0) !begins_value else bytes[start - 1] != ' ') return null;
    return .{ .start = start, .end = end };
}

/// Bytes Markdown reads as inline markup wherever they stand: escapes, code, emphasis,
/// strikethrough, links, raw HTML and entities. `&` also keeps the entities this codec
/// writes for line breaks unambiguous.
fn markup(byte: u8) bool {
    return switch (byte) {
        '\\', '`', '*', '_', '~', '[', ']', '<', '>', '&' => true,
        else => false,
    };
}

/// Whether the byte at `index` opens a block when `first` is where the line's text begins:
/// `#` (heading), `-` and `+` (list items), or the `.` or `)` that follows a leading digit
/// run (ordered list item).
fn opensBlock(bytes: []const u8, first: usize, index: usize) bool {
    if (first >= bytes.len) return false;
    return switch (bytes[index]) {
        '#', '-', '+' => index == first,
        '.', ')' => index > first and std.mem.indexOfNone(u8, bytes[first..index], "0123456789") == null,
        else => false,
    };
}
fn codeFenceLength(bytes: []const u8) usize {
    var longest: usize = 0;
    var run: usize = 0;
    for (bytes) |byte| {
        run = if (byte == '`') run + 1 else 0;
        longest = @max(longest, run);
    }
    return longest + 1;
}
pub fn codeBlock(w: *std.Io.Writer, bytes: []const u8) Error!void {
    const length = @max(@as(usize, 3), codeFenceLength(bytes));
    try write(w, "\n");
    for (0..length) |_| try write(w, "`");
    try write(w, "\n");
    try write(w, bytes);
    if (bytes.len == 0 or bytes[bytes.len - 1] != '\n') try write(w, "\n");
    for (0..length) |_| try write(w, "`");
    try write(w, "\n\n");
}
pub fn code(w: *std.Io.Writer, bytes: []const u8) Error!void {
    const length = codeFenceLength(bytes);
    const padded = bytes[0] == '`' or bytes[bytes.len - 1] == '`' or
        (bytes[0] == ' ' and bytes[bytes.len - 1] == ' ' and std.mem.trim(u8, bytes, " ").len != 0);
    for (0..length) |_| try write(w, "`");
    if (padded) try write(w, " ");
    for (bytes) |byte| {
        w.writeByte(byte) catch return error.OutOfMemory;
        if (byte == '\n') try write(w, "  ");
    }
    if (padded) try write(w, " ");
    for (0..length) |_| try write(w, "`");
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
            // Any ASCII punctuation may follow, not only the bytes the renderer escapes. Text that
            // escapes a byte the renderer does not reads back to the same value and re-renders
            // differently, which publication's byte comparison rejects.
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
