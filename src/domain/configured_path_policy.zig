const std = @import("std");
const roots = @import("bootstrap_roots.zig");

pub const Error = error{InvalidConfiguredPath};

pub fn normalize(
    policy: roots.WorkspacePathPolicy,
    allocator: std.mem.Allocator,
    raw_path: []const u8,
    allow_trailing_separator: bool,
) Error![]u8 {
    if (raw_path.len == 0 or raw_path.len > policy.max_relative_path_bytes or
        !std.unicode.utf8ValidateSlice(raw_path) or isAbsoluteOrDrivePath(raw_path))
    {
        return error.InvalidConfiguredPath;
    }
    if (!allow_trailing_separator and raw_path[raw_path.len - 1] == '/') {
        return error.InvalidConfiguredPath;
    }
    const normalized_length = if (raw_path[raw_path.len - 1] == '/') raw_path.len - 1 else raw_path.len;
    if (normalized_length == 0) return error.InvalidConfiguredPath;
    const normalized = raw_path[0..normalized_length];

    var iterator = std.mem.splitScalar(u8, normalized, '/');
    while (iterator.next()) |component| try validateComponent(policy, component);
    if (hasEncodedDotOrSeparator(normalized)) return error.InvalidConfiguredPath;
    return allocator.dupe(u8, normalized) catch error.InvalidConfiguredPath;
}

fn isAbsoluteOrDrivePath(path: []const u8) bool {
    if (path[0] == '/' or path[0] == '\\') return true;
    return path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':';
}

fn validateComponent(policy: roots.WorkspacePathPolicy, component: []const u8) Error!void {
    if (component.len == 0 or component.len > policy.max_component_bytes or
        std.mem.eql(u8, component, ".") or std.mem.eql(u8, component, "..") or
        component[component.len - 1] == '.' or component[component.len - 1] == ' ')
    {
        return error.InvalidConfiguredPath;
    }
    for (component) |byte| {
        if (byte < 0x20 or byte == 0x7f or byte >= 0x80) return error.InvalidConfiguredPath;
        switch (byte) {
            '\\', '<', '>', ':', '"', '|', '?', '*' => return error.InvalidConfiguredPath,
            else => {},
        }
    }
    if (isReservedPortableName(component)) return error.InvalidConfiguredPath;
}

fn isReservedPortableName(component: []const u8) bool {
    const stem_end = std.mem.indexOfScalar(u8, component, '.') orelse component.len;
    const stem = component[0..stem_end];
    if (std.ascii.eqlIgnoreCase(stem, "con") or std.ascii.eqlIgnoreCase(stem, "prn") or
        std.ascii.eqlIgnoreCase(stem, "aux") or std.ascii.eqlIgnoreCase(stem, "nul")) return true;
    if (stem.len != 4) return false;
    return (std.ascii.eqlIgnoreCase(stem[0..3], "com") or std.ascii.eqlIgnoreCase(stem[0..3], "lpt")) and
        stem[3] >= '1' and stem[3] <= '9';
}

fn hasEncodedDotOrSeparator(path: []const u8) bool {
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        if (path[index] != '%') continue;
        var token_index = index + 1;
        while (token_index + 1 < path.len and std.ascii.toLower(path[token_index]) == '2' and
            std.ascii.toLower(path[token_index + 1]) == '5') token_index += 2;
        if (token_index + 1 >= path.len) continue;
        const first = std.ascii.toLower(path[token_index]);
        const second = std.ascii.toLower(path[token_index + 1]);
        if ((first == '2' and (second == 'e' or second == 'f')) or
            (first == '5' and second == 'c')) return true;
    }
    return false;
}
