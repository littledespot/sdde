const std = @import("std");
const grammar_module = @import("path_token_grammar.zig");
const naming = @import("naming_policy.zig");
const rules = @import("naming_rule.zig");
const unicode = @import("../ports/unicode_normalizer.zig");
const paths = @import("configured_path_policy.zig");
pub const Error = grammar_module.Error || error{InvalidPathTokenText};
pub const Kind = enum { external_uri, display_path, display_filename };
pub const Match = struct { start_byte: usize, end_byte: usize, kind: Kind };

pub const Result = opaque {
    pub fn text(self: *const Result) []const u8 {
        return storage(self).text;
    }
    pub fn matches(self: *const Result) []const Match {
        return storage(self).matches;
    }
};
pub const Owner = struct { allocator: std.mem.Allocator, arena: std.heap.ArenaAllocator, text: []const u8, matches: []const Match };
pub fn view(owner: *const Owner) *const Result {
    return @ptrCast(owner);
}
pub fn destroy(owner: *Owner) void {
    const allocator = owner.allocator;
    owner.arena.deinit();
    allocator.destroy(owner);
}
fn storage(result: *const Result) *const Owner {
    return @ptrCast(@alignCast(result));
}

/// Raw-byte spans remain tied to the owned original text, never NFC offsets.
/// The caller validates current grammar bindings before invoking this lexer.
pub fn scan(allocator: std.mem.Allocator, grammar: grammar_module.Grammar, text: []const u8, normalizer: unicode.Normalizer, folder: unicode.CaseFolder, classifier: unicode.LexicalClassifier) Error!*Owner {
    if (!std.unicode.utf8ValidateSlice(text) or std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidPathTokenText;
    const owner = try allocator.create(Owner);
    owner.* = .{ .allocator = allocator, .arena = .init(allocator), .text = &.{}, .matches = &.{} };
    errdefer destroy(owner);
    const arena = owner.arena.allocator();
    owner.text = try arena.dupe(u8, text);
    var matches: std.ArrayList(Match) = .empty;
    var start: ?usize = null;
    var index: usize = 0;
    while (index <= text.len) {
        const length = if (index < text.len) std.unicode.utf8ByteSequenceLength(text[index]) catch return error.InvalidPathTokenText else 0;
        const scalar = if (length != 0) std.unicode.utf8Decode(text[index..][0..length]) catch return error.InvalidPathTokenText else 0;
        const boundary = length == 0 or isBoundary(scalar, if (start) |begin| text[begin..index] else "", classifier);
        if (boundary) {
            if (start) |begin| {
                var end = index;
                while (end > begin and (text[end - 1] == '.' or (text[end - 1] == ':' and !(end - begin == 2 and std.ascii.isAlphabetic(text[begin]))))) end -= 1;
                if (end > begin) {
                    var scratch: std.heap.ArenaAllocator = .init(allocator);
                    defer scratch.deinit();
                    if (try classify(scratch.allocator(), grammar, text[begin..end], normalizer, folder)) |kind| try matches.append(arena, .{ .start_byte = begin, .end_byte = end, .kind = kind });
                }
                start = null;
            }
        } else if (start == null) start = index;
        if (length == 0) break;
        index += length;
    }
    // Exact registered names may contain spaces/punctuation. Recognize those
    // complete names as well as ordinary lexer tokens; neither consumer adds
    // its own filename exception or second extension list.
    for (grammar.policy.rules) |bound| switch (bound.rule.kind) {
        .exact, .manifest, .reserved => try collectName(allocator, arena, &matches, text, bound.rule.value, bound.rule.case_sensitive, normalizer, folder, classifier),
        .extension, .glob => {},
    };
    for (grammar.reference_names) |name| try collectName(allocator, arena, &matches, text, name.basename, true, normalizer, folder, classifier);
    std.mem.sort(Match, matches.items, {}, struct {
        fn less(_: void, a: Match, b: Match) bool {
            return if (a.start_byte == b.start_byte) a.end_byte > b.end_byte else a.start_byte < b.start_byte;
        }
    }.less);
    var count: usize = 0;
    for (matches.items) |match| {
        if (count != 0 and match.start_byte < matches.items[count - 1].end_byte) continue;
        matches.items[count] = match;
        count += 1;
    }
    matches.items.len = count;
    owner.matches = try matches.toOwnedSlice(arena);
    return owner;
}

fn isBoundary(scalar: u21, prefix: []const u8, classifier: unicode.LexicalClassifier) bool {
    // These punctuation characters are internal to path/URI/name lexemes.
    return switch (scalar) {
        '/', '\\', '.', ':', '-', '_', '%', '@', '+', '~', '=', '#', '&' => false,
        '?' => !uriPrefix(prefix),
        else => classifier.isBoundary(scalar) or scalar == '<' or scalar == '>' or scalar == '`',
    };
}

fn classify(allocator: std.mem.Allocator, grammar: grammar_module.Grammar, token: []const u8, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error!?Kind {
    if (token.len >= 2 and std.ascii.isAlphabetic(token[0]) and token[1] == ':' and
        (token.len == 2 or token[2] == '/' or token[2] == '\\')) return .display_path;
    if (uriPrefix(token)) return .external_uri;
    if (paths.hasEncodedDotOrSeparator(token)) return .display_path;
    if (token[0] == '/' or token[0] == '\\') return .display_path;
    if (std.mem.indexOfAny(u8, token, "/\\") != null) return .display_path;
    const normalized = try naming.normalize(allocator, token, true, normalizer, folder);
    var folded: ?[]const u8 = null;
    for (grammar.policy.rules) |bound| {
        if (!bound.rule.case_sensitive and folded == null) folded = try naming.normalize(allocator, token, false, normalizer, folder);
        if (rules.matches(bound.rule, if (bound.rule.case_sensitive) normalized else folded.?)) return .display_filename;
    }
    for (grammar.reference_names) |name| if (std.mem.eql(u8, normalized, name.basename)) return .display_filename;
    return null;
}

fn collectName(allocator: std.mem.Allocator, output_allocator: std.mem.Allocator, matches: *std.ArrayList(Match), text: []const u8, name: []const u8, case_sensitive: bool, normalizer: unicode.Normalizer, folder: unicode.CaseFolder, classifier: unicode.LexicalClassifier) Error!void {
    var name_points = (std.unicode.Utf8View.init(name) catch return error.InvalidPathTokenText).iterator();
    var multi_token = false;
    while (name_points.nextCodepoint()) |point| if (isBoundary(point, "", classifier)) {
        multi_token = true;
        break;
    };
    if (!multi_token) return;
    // NFC can compose several input scalars. This search window derives from
    // the exact registered name, not a limit on scanned/model text.
    const window = std.math.add(usize, std.math.mul(usize, name.len, 4) catch return error.OutOfMemory, 4) catch return error.OutOfMemory;
    var start: usize = 0;
    var left_boundary = true;
    while (start < text.len) {
        const length = std.unicode.utf8ByteSequenceLength(text[start]) catch return error.InvalidPathTokenText;
        const point = std.unicode.utf8Decode(text[start..][0..length]) catch return error.InvalidPathTokenText;
        if (left_boundary) {
            var end = start;
            while (end < text.len and end - start < window) {
                end += std.unicode.utf8ByteSequenceLength(text[end]) catch return error.InvalidPathTokenText;
                if (end < text.len) {
                    const next_length = std.unicode.utf8ByteSequenceLength(text[end]) catch return error.InvalidPathTokenText;
                    const next = std.unicode.utf8Decode(text[end..][0..next_length]) catch return error.InvalidPathTokenText;
                    if (!classifier.isBoundary(next)) continue;
                }
                const normalized = try naming.normalize(allocator, text[start..end], case_sensitive, normalizer, folder);
                defer allocator.free(normalized);
                if (std.mem.eql(u8, normalized, name)) try matches.append(output_allocator, .{ .start_byte = start, .end_byte = end, .kind = .display_filename });
            }
        }
        left_boundary = classifier.isBoundary(point);
        start += length;
    }
}

fn uriPrefix(token: []const u8) bool {
    const colon = std.mem.indexOfScalar(u8, token, ':') orelse return false;
    if (colon == 0 or colon + 1 == token.len or !std.ascii.isAlphabetic(token[0])) return false;
    for (token[1..colon]) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '+' and byte != '-' and byte != '.') return false;
    return true;
}
