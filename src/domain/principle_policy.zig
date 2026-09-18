//! One project-owned selection policy. Prose never supplies policy or capabilities.
const std = @import("std");
const unicode = @import("../ports/unicode_normalizer.zig");
const paths = @import("relative_directory_path.zig");
pub const Category = enum { core, architecture, project_structure, security, validation, observability, user_interface, custom };
pub const Stage = enum { spec, plan, tasks, implement };
pub const Scope = struct { stage: Stage, environment: ?[]const u8, fileKind: ?[]const u8 };
pub const Row = struct { stage: Stage, environment: ?[]const u8, fileKind: ?[]const u8, categories: []const Category };
pub const Config = struct { filenameHints: std.json.ArrayHashMap(Category), selections: []const Row };
pub const Input = struct {
    filenames: []const []const u8,
    categories: []const Category,
    selections: []const Row,
    pub fn fromConfig(config: Config) Input {
        return .{ .filenames = config.filenameHints.map.keys(), .categories = config.filenameHints.map.values(), .selections = config.selections };
    }
};
pub const Hint = struct { basename: []const u8, category: Category };
pub const Policy = struct { hints: []const Hint, selections: []const Row };
pub const Error = std.mem.Allocator.Error || error{InvalidPrinciplePolicy};
pub const max_rows = 256;

pub fn compile(a: std.mem.Allocator, raw: Input, normalizer: unicode.Normalizer, folder: unicode.CaseFolder) Error!Policy {
    if (raw.filenames.len > max_rows or raw.filenames.len != raw.categories.len) return error.InvalidPrinciplePolicy;
    const hints = try a.alloc(Hint, raw.filenames.len);
    const keys = try a.alloc([]const u8, hints.len);
    for (raw.filenames, raw.categories, hints, 0..) |name, category_hint, *hint, index| {
        try basename(name);
        const normalized = normalizer.nfc(a, name, paths.max_bytes) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidPrinciplePolicy;
        if (!std.mem.eql(u8, name, normalized)) return error.InvalidPrinciplePolicy;
        keys[index] = folder.key(a, name, paths.max_bytes * 4) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidPrinciplePolicy;
        for (keys[0..index]) |prior| if (std.mem.eql(u8, keys[index], prior)) return error.InvalidPrinciplePolicy;
        hint.* = .{ .basename = try a.dupe(u8, name), .category = category_hint };
    }
    std.mem.sort(Hint, hints, {}, struct {
        fn less(_: void, left: Hint, right: Hint) bool {
            return std.mem.order(u8, left.basename, right.basename) == .lt;
        }
    }.less);
    const policy: Policy = .{ .hints = hints, .selections = raw.selections };
    try validate(policy);
    return policy;
}

pub fn validate(policy: Policy) Error!void {
    if (policy.hints.len > max_rows or policy.selections.len == 0 or policy.selections.len > max_rows) return error.InvalidPrinciplePolicy;
    for (policy.hints, 0..) |hint, index| {
        try basename(hint.basename);
        if (index != 0 and std.mem.order(u8, policy.hints[index - 1].basename, hint.basename) != .lt) return error.InvalidPrinciplePolicy;
    }
    for (policy.selections, 0..) |row, index| {
        if (row.environment) |id| if (!validName(id)) return error.InvalidPrinciplePolicy;
        if (row.fileKind) |id| if (!validName(id)) return error.InvalidPrinciplePolicy;
        if (row.stage == .spec and (row.environment != null or row.fileKind != null)) return error.InvalidPrinciplePolicy;
        var categories: std.EnumSet(Category) = .initEmpty();
        for (row.categories) |category_hint| {
            if (categories.contains(category_hint)) return error.InvalidPrinciplePolicy;
            categories.insert(category_hint);
        }
        if (!categories.contains(.core) or !categories.contains(.custom)) return error.InvalidPrinciplePolicy;
        for (policy.selections[0..index]) |prior| if (prior.stage == row.stage and same(prior.environment, row.environment) and same(prior.fileKind, row.fileKind)) return error.InvalidPrinciplePolicy;
    }
}

pub fn select(policy: Policy, scope: Scope) Error!std.EnumSet(Category) {
    try validate(policy);
    var result: std.EnumSet(Category) = .initEmpty();
    var found = false;
    for (policy.selections) |row| {
        if (row.stage != scope.stage or !matches(row.environment, scope.environment) or !matches(row.fileKind, scope.fileKind)) continue;
        found = true;
        for (row.categories) |category_hint| result.insert(category_hint);
    }
    if (!found) return error.InvalidPrinciplePolicy;
    return result;
}
pub fn category(policy: Policy, path: []const u8) Category {
    const name = std.fs.path.basename(path);
    for (policy.hints) |hint| if (std.mem.eql(u8, hint.basename, name)) return hint.category;
    return .custom;
}
fn basename(name: []const u8) Error!void {
    paths.validate(name) catch return error.InvalidPrinciplePolicy;
    if (std.mem.indexOfScalar(u8, name, '/') != null or !std.mem.endsWith(u8, name, ".md")) return error.InvalidPrinciplePolicy;
}
fn validName(value: []const u8) bool {
    if (value.len == 0 or value.len > 128) return false;
    for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_' and byte != '.') return false;
    return true;
}
fn same(left: ?[]const u8, right: ?[]const u8) bool {
    return if (left) |value| right != null and std.mem.eql(u8, value, right.?) else right == null;
}
fn matches(selected: ?[]const u8, actual: ?[]const u8) bool {
    return selected == null or same(selected, actual);
}
