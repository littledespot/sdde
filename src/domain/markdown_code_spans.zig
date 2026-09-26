//! Source-coordinate extractor. Values are raw source, not rendered Markdown.
const std = @import("std");
pub const Form = enum { inline_code, code_block, link_destination };
pub const Range = struct { start: usize, end: usize, form: Form = .inline_code };
const Run = struct { start: usize, end: usize, opening: bool, closing: bool = true, next: ?usize = null };

/// Equal-length backtick runs delimit an inline value. Block fences, indented
/// code, blank lines and HTML blocks separate inline regions. No Unicode or
/// Markdown whitespace normalization is applied to the captured interior.
pub fn scan(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const Range {
    const all = try scanAll(allocator, bytes);
    defer allocator.free(all);
    var result: std.ArrayList(Range) = .empty;
    errdefer result.deinit(allocator);
    for (all) |range| if (range.form == .inline_code) try result.append(allocator, range);
    return result.toOwnedSlice(allocator);
}

/// One source-coordinate scan owns opaque code regions and explicit link
/// destinations. The inline-only operation above is a projection of this result.
pub fn scanAll(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const Range {
    var result: std.ArrayList(Range) = .empty;
    errdefer result.deinit(allocator);
    var runs: std.ArrayList(Run) = .empty;
    defer runs.deinit(allocator);
    var excluded_ranges: std.ArrayList(Range) = .empty;
    defer excluded_ranges.deinit(allocator);
    var fence: ?struct { byte: u8, length: usize, start: usize } = null;
    var html_block = false;
    var region_start: ?usize = null;
    var markup_end: usize = 0;
    var offset: usize = 0;
    while (offset < bytes.len) {
        const end = std.mem.indexOfAnyPos(u8, bytes, offset, "\r\n") orelse bytes.len;
        var next = end;
        if (next < bytes.len and bytes[next] == '\r') next += 1;
        if (next < bytes.len and bytes[next] == '\n') next += 1;
        const line = bytes[offset..end];
        var prefix = contentStart(line);
        // Indentation cannot start a code block in the middle of a paragraph.
        // Preserve it as raw inline content, including multiline code spans.
        if (prefix == line.len and std.mem.trim(u8, line, " \t").len != 0 and region_start != null) prefix = 0;
        const content = line[prefix..];
        const heading = isHeading(content);
        if (heading) {
            try flush(allocator, bytes, region_start orelse offset, &markup_end, &runs, &result);
            region_start = null;
        }
        const blank = std.mem.trim(u8, content, " \t").len == 0;
        var excluded = blank or prefix == line.len or isBlockSeparator(content);
        var fenced = fence != null;
        if (fence) |active| {
            excluded = true;
            const length = runLength(content, 0, active.byte);
            if (length >= active.length and std.mem.trim(u8, content[length..], " \t").len == 0) {
                if (offset > active.start) try result.append(allocator, .{ .start = active.start, .end = offset, .form = .code_block });
                fence = null;
            }
        } else if (content.len > 0 and (content[0] == '`' or content[0] == '~')) {
            const length = runLength(content, 0, content[0]);
            if (length >= 3 and (content[0] == '~' or std.mem.indexOfScalar(u8, content[length..], '`') == null)) {
                fence = .{ .byte = content[0], .length = length, .start = next };
                fenced = true;
                excluded = true;
            }
        }
        if (!fenced and html_block) {
            excluded = true;
            if (blank) html_block = false;
        } else if (!fenced and isHtmlBlock(content)) {
            html_block = true;
            excluded = true;
        }
        if (excluded) {
            try excluded_ranges.append(allocator, .{ .start = offset, .end = next });
            try flush(allocator, bytes, region_start orelse offset, &markup_end, &runs, &result);
            region_start = null;
        } else {
            if (region_start == null) region_start = offset + prefix;
            var cursor = offset + prefix;
            while (cursor < end) {
                if (bytes[cursor] == '`') {
                    const length = runLength(bytes, cursor, '`');
                    var slashes: usize = 0;
                    var before = cursor;
                    while (before > offset + prefix and bytes[before - 1] == '\\') : (before -= 1) slashes += 1;
                    // An escaped first backtick is ordinary text. Any remaining
                    // run can still open, while the full run can close code.
                    try runs.append(allocator, .{ .start = cursor, .end = cursor + length, .opening = slashes % 2 == 0 });
                    if (slashes % 2 != 0 and length > 1) try runs.append(allocator, .{ .start = cursor + 1, .end = cursor + length, .opening = true, .closing = false });
                    cursor += length;
                } else cursor += 1;
            }
        }
        if (heading) {
            try flush(allocator, bytes, region_start orelse offset, &markup_end, &runs, &result);
            region_start = null;
        }
        offset = next;
    }
    try flush(allocator, bytes, region_start orelse offset, &markup_end, &runs, &result);
    if (fence) |active| if (active.start < bytes.len) {
        try result.append(allocator, .{ .start = active.start, .end = bytes.len, .form = .code_block });
    };
    // Code regions are opaque to link parsing, including inline literals.
    try excluded_ranges.appendSlice(allocator, result.items);
    std.mem.sort(Range, excluded_ranges.items, {}, less);
    try collectLinks(allocator, bytes, excluded_ranges.items, &result);
    std.mem.sort(Range, result.items, {}, less);
    return result.toOwnedSlice(allocator);
}
fn less(_: void, a: Range, b: Range) bool {
    return a.start < b.start;
}

fn collectLinks(a: std.mem.Allocator, bytes: []const u8, protected: []const Range, output: *std.ArrayList(Range)) std.mem.Allocator.Error!void {
    var i: usize = 0;
    var protected_index: usize = 0;
    var labels: usize = 0;
    while (i < bytes.len) {
        while (protected_index < protected.len and protected[protected_index].end <= i) protected_index += 1;
        if (protected_index < protected.len and i >= protected[protected_index].start) {
            i = protected[protected_index].end;
            continue;
        }
        if (bytes[i] == '\\') {
            i += @min(@as(usize, 2), bytes.len - i);
            continue;
        }
        if (bytes[i] == '<') if (htmlEnd(bytes, i)) |end| {
            i = end;
            continue;
        };
        if (bytes[i] == '[') labels += 1;
        if (bytes[i] == ']' and labels != 0) {
            labels -= 1;
            if (i + 1 < bytes.len and bytes[i + 1] == '(') {
                var examined_end = i + 2;
                if (linkDestination(bytes, i + 2, &examined_end)) |link| {
                    // This bounded extractor does not resolve ambiguous Markdown
                    // precedence. Keep existing exact spans and raw source evidence
                    // instead of emitting overlapping candidate identities.
                    const overlap = for (protected[protected_index..]) |range| {
                        if (range.start >= link.range.end) break false;
                        if (range.end > link.range.start) break true;
                    } else false;
                    if (!overlap) try output.append(a, link.range);
                    i = link.end;
                    continue;
                }
                // Malformed destinations must not repeatedly rescan a long suffix.
                i = examined_end;
                continue;
            }
        }
        if (bytes[i] == '\n') labels = 0;
        i += 1;
    }
}
const Link = struct { range: Range, end: usize };
fn linkDestination(bytes: []const u8, begin: usize, examined_end: *usize) ?Link {
    var i = begin;
    defer examined_end.* = i;
    while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) i += 1;
    if (i == bytes.len) return null;
    const angle = bytes[i] == '<';
    if (angle) i += 1;
    const start = i;
    var depth: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const c = bytes[i];
        if (c == '\\') {
            if (i + 1 == bytes.len) return null;
            i += 1;
            continue;
        }
        if (c == '\r' or c == '\n' or c == '<') return null;
        if (angle) {
            if (c == '>') break;
        } else if (c == '(') {
            depth += 1;
        } else if (c == ')') {
            if (depth == 0) break;
            depth -= 1;
        } else if (c == ' ' or c == '\t') break;
    }
    const end = i;
    if (start == end or depth != 0 or i == bytes.len) return null;
    if (angle) {
        if (bytes[i] != '>') return null;
        i += 1;
    }
    const before_space = i;
    while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) i += 1;
    if (i < bytes.len and i > before_space and (bytes[i] == '\"' or bytes[i] == '\'' or bytes[i] == '(')) {
        const closing: u8 = if (bytes[i] == '(') ')' else bytes[i];
        i += 1;
        while (i < bytes.len and bytes[i] != closing) : (i += 1) {
            if (bytes[i] == '\\') {
                if (i + 1 == bytes.len) return null;
                i += 1;
            }
        }
        if (i == bytes.len) return null;
        i += 1;
        while (i < bytes.len and (bytes[i] == ' ' or bytes[i] == '\t')) i += 1;
    }
    if (i == bytes.len or bytes[i] != ')') return null;
    return .{ .range = .{ .start = start, .end = end, .form = .link_destination }, .end = i + 1 };
}

fn flush(allocator: std.mem.Allocator, bytes: []const u8, region_start: usize, markup_end: *usize, runs: *std.ArrayList(Run), result: *std.ArrayList(Range)) std.mem.Allocator.Error!void {
    // Index runs once: unmatched delimiters must not cause quadratic rescans.
    var following: std.AutoHashMap(usize, usize) = .init(allocator);
    defer following.deinit();
    var cursor = runs.items.len;
    while (cursor > 0) {
        cursor -= 1;
        const run = &runs.items[cursor];
        run.next = following.get(run.end - run.start);
        if (run.closing) try following.put(run.end - run.start, cursor);
    }
    cursor = 0;
    var plain = @max(region_start, markup_end.*);
    while (cursor < runs.items.len) {
        const run = runs.items[cursor];
        // Inline HTML is opaque only outside code. A comment/tag spelled inside
        // an already matched span is part of that exact scalar, not markup.
        while (plain < run.start) {
            if (bytes[plain] == '<') if (htmlEnd(bytes, plain)) |end| {
                plain = end;
                markup_end.* = end;
                continue;
            };
            plain += 1;
        }
        if (run.start < plain) {
            cursor += 1;
            continue;
        }
        if (run.opening) if (run.next) |closing| {
            const stop = runs.items[closing];
            if (run.end < stop.start) {
                // A code span cannot cross a blank/block boundary (flush), and
                // its raw scalar may include ordinary single line endings.
                std.debug.assert(stop.start <= bytes.len);
                try result.append(allocator, .{ .start = run.end, .end = stop.start });
                plain = stop.end;
                cursor = closing + 1;
                continue;
            }
        };
        cursor += 1;
    }
    runs.clearRetainingCapacity();
}

fn htmlEnd(bytes: []const u8, start: usize) ?usize {
    if (std.mem.startsWith(u8, bytes[start..], "<!--")) return if (std.mem.indexOfPos(u8, bytes, start + 4, "-->")) |end| end + 3 else bytes.len;
    var cursor = start + 1;
    if (cursor < bytes.len and bytes[cursor] == '/') cursor += 1;
    if (cursor == bytes.len or !std.ascii.isAlphabetic(bytes[cursor])) return null;
    var quote: ?u8 = null;
    while (cursor < bytes.len) : (cursor += 1) {
        const byte = bytes[cursor];
        if (quote) |active| {
            if (byte == active) quote = null;
        } else if (byte == '\'' or byte == '"') {
            quote = byte;
        } else if (byte == '>') return cursor + 1;
    }
    return null;
}

fn runLength(bytes: []const u8, start: usize, byte: u8) usize {
    var cursor = start;
    while (cursor < bytes.len and bytes[cursor] == byte) cursor += 1;
    return cursor - start;
}

fn isHeading(line: []const u8) bool {
    const count = runLength(line, 0, '#');
    return count > 0 and count <= 6 and (count == line.len or line[count] == ' ' or line[count] == '\t');
}

fn isBlockSeparator(line: []const u8) bool {
    if (line.len == 0 or std.mem.indexOfScalar(u8, "-_*=", line[0]) == null) return false;
    var count: usize = 0;
    for (line) |byte| {
        if (byte == line[0]) count += 1 else if (byte != ' ' and byte != '\t') return false;
    }
    return count >= 3 or (count > 0 and (line[0] == '=' or line[0] == '-'));
}

fn contentStart(line: []const u8) usize {
    var cursor: usize = 0;
    while (cursor < line.len) {
        var spaces: usize = 0;
        while (cursor < line.len and line[cursor] == ' ') : (cursor += 1) spaces += 1;
        if (spaces >= 4 or (cursor < line.len and line[cursor] == '\t')) return line.len;
        if (cursor < line.len and line[cursor] == '>') {
            cursor += 1;
            if (cursor < line.len and line[cursor] == ' ') cursor += 1;
            continue;
        }
        const marker = cursor;
        if (cursor < line.len and std.mem.indexOfScalar(u8, "-+*", line[cursor]) != null) {
            cursor += 1;
        } else {
            while (cursor < line.len and std.ascii.isDigit(line[cursor]) and cursor - marker < 9) cursor += 1;
            if (cursor > marker and cursor < line.len and (line[cursor] == '.' or line[cursor] == ')')) cursor += 1 else cursor = marker;
        }
        if (cursor > marker and cursor < line.len and (line[cursor] == ' ' or line[cursor] == '\t')) {
            cursor += 1;
            continue;
        }
        return marker;
    }
    return cursor;
}

fn isHtmlBlock(line: []const u8) bool {
    if (line.len < 2 or line[0] != '<') return false;
    // Block HTML has no inline Markdown interpretation. Comments are handled
    // separately so Markdown after an inline closing comment remains eligible.
    const names = [_][]const u8{ "address", "article", "aside", "blockquote", "body", "div", "dl", "fieldset", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "html", "li", "main", "nav", "ol", "p", "pre", "script", "section", "style", "table", "tbody", "td", "th", "thead", "tr", "ul" };
    const start: usize = if (line[1] == '/') 2 else 1;
    for (names) |name| {
        if (line.len > start + name.len and std.ascii.eqlIgnoreCase(line[start..][0..name.len], name) and std.mem.indexOfScalar(u8, " \t>/", line[start + name.len]) != null) return true;
    }
    return false;
}
