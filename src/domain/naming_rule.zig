//! Registered lexical rules, not file kinds, path grants or project operations.
const std = @import("std");
const paths = @import("configured_path_policy.zig");
pub const Id = struct { bytes: []const u8 };
pub const Kind = enum { extension, exact, glob, manifest, reserved };
pub const Rule = struct { id: Id, kind: Kind, value: []const u8, case_sensitive: bool };
pub const Error = error{InvalidNamingRule};
pub const max_rules = 256;

pub fn validate(rules: []const Rule) Error!void {
    if (rules.len > max_rules) return error.InvalidNamingRule;
    for (rules, 0..) |rule, index| {
        if (rule.id.bytes.len == 0 or rule.id.bytes.len > 128) return error.InvalidNamingRule;
        for (rule.id.bytes) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_' and byte != '.') return error.InvalidNamingRule;
        for (rules[0..index]) |prior| if (std.mem.eql(u8, prior.id.bytes, rule.id.bytes)) return error.InvalidNamingRule;
        if (!std.unicode.utf8ValidateSlice(rule.value) or std.mem.indexOfScalar(u8, rule.value, '/') != null or paths.hasEncodedDotOrSeparator(rule.value)) return error.InvalidNamingRule;
        if (rule.kind == .glob) {
            try validateGlob(rule.value);
        } else {
            paths.validateComponent(255, rule.value, .unicode) catch return error.InvalidNamingRule;
            if (rule.kind == .extension and (rule.value.len < 2 or rule.value[0] != '.')) return error.InvalidNamingRule;
        }
    }
}

/// Basename-only path-pattern/v1 subset. No brace expansion, separators,
/// globstar, negation or regex fallthrough. Unsupported syntax rejects policy.
fn validateGlob(pattern: []const u8) Error!void {
    if (pattern.len == 0 or pattern.len > 255) return error.InvalidNamingRule;
    var index: usize = 0;
    while (index < pattern.len) : (index += 1) {
        const byte = pattern[index];
        if (byte < 0x20 or byte == 0x7f or std.mem.indexOfScalar(u8, "\\/:{}!\"|<>", byte) != null) return error.InvalidNamingRule;
        if (byte == '*' and index + 1 < pattern.len and pattern[index + 1] == '*') return error.InvalidNamingRule;
        if (byte == '[') {
            const start = index + 1;
            index = std.mem.indexOfScalarPos(u8, pattern, start, ']') orelse return error.InvalidNamingRule;
            if (start == index) return error.InvalidNamingRule;
            for (pattern[start..index], 0..) |item, offset| {
                if (item < 0x20 or item >= 0x7f or std.mem.indexOfScalar(u8, "[!^\\/*?{}", item) != null) return error.InvalidNamingRule;
                if (item == '-' and (offset == 0 or start + offset + 1 == index or pattern[start + offset - 1] > pattern[start + offset + 1])) return error.InvalidNamingRule;
            }
        } else if (byte == ']') return error.InvalidNamingRule;
    }
}

/// Inputs are normalized, with the rule's case policy already applied.
pub fn matches(rule: Rule, value: []const u8) bool {
    return switch (rule.kind) {
        .extension => value.len > rule.value.len and std.mem.endsWith(u8, value, rule.value),
        .exact, .manifest, .reserved => std.mem.eql(u8, value, rule.value),
        .glob => globMatches(rule.value, value),
    };
}

fn globMatches(pattern: []const u8, value: []const u8) bool {
    var p: usize = 0;
    var v: usize = 0;
    var star: ?usize = null;
    var retry: usize = 0;
    while (v < value.len) {
        if (p < pattern.len and pattern[p] == '*') {
            star = p;
            p += 1;
            retry = v;
            continue;
        }
        if (p < pattern.len) {
            const plen = std.unicode.utf8ByteSequenceLength(pattern[p]) catch return false;
            const vlen = std.unicode.utf8ByteSequenceLength(value[v]) catch return false;
            if (pattern[p] == '?' or (pattern[p] != '[' and plen == vlen and p + plen <= pattern.len and std.mem.eql(u8, pattern[p..][0..plen], value[v..][0..vlen]))) {
                p += plen;
                v += vlen;
                continue;
            }
            if (pattern[p] == '[') {
                const end = std.mem.indexOfScalarPos(u8, pattern, p + 1, ']') orelse return false;
                if (vlen == 1 and classMatches(pattern[p + 1 .. end], value[v])) {
                    p = end + 1;
                    v += 1;
                    continue;
                }
            }
        }
        if (star) |position| {
            retry += std.unicode.utf8ByteSequenceLength(value[retry]) catch return false;
            v = retry;
            p = position + 1;
        } else return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}
fn classMatches(class: []const u8, byte: u8) bool {
    var index: usize = 0;
    while (index < class.len) : (index += 1) {
        if (index + 2 < class.len and class[index + 1] == '-') {
            if (byte >= class[index] and byte <= class[index + 2]) return true;
            index += 2;
        } else if (byte == class[index]) return true;
    }
    return false;
}
