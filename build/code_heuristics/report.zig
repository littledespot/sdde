//! Pure report assembly and rendering; no source reads or workflow operations.
const std = @import("std");
const model = @import("model.zig");

pub const thresholds = .{
    .file_code_lines = 500,
    .function_lines = 80,
    .decision_tokens = 15,
    .brace_depth = 5,
    .duplicate_body_tokens = 80,
};
pub const Summary = struct {
    scope: model.Scope,
    files: usize = 0,
    lines: usize = 0,
    code_lines: usize = 0,
    functions: usize = 0,
    test_blocks: usize = 0,
};
pub const Location = struct { path: []const u8, name: []const u8, line: usize, scope: model.Scope };
pub const Hotspot = struct {
    location: Location,
    lines: usize,
    decision_tokens: usize,
    brace_depth: usize,
    long_function: bool,
    many_decisions: bool,
    deep_braces: bool,
};
pub const Duplicates = struct { body_tokens: usize, occurrences: []const Location };
pub const Report = struct {
    schema: []const u8 = "code-heuristics/v1",
    advisory_only: bool = true,
    limits: @TypeOf(thresholds) = thresholds,
    summary: [3]Summary,
    files: []const model.File,
    hotspots: []const Hotspot,
    duplicate_groups: []const Duplicates,
};

pub fn build(a: std.mem.Allocator, input: []const model.File) !Report {
    const files = try a.dupe(model.File, input);
    std.mem.sort(model.File, files, {}, fileLess);
    var summary = [3]Summary{ .{ .scope = .production }, .{ .scope = .tests }, .{ .scope = .tooling } };
    var hotspots: std.ArrayList(Hotspot) = .empty;
    defer hotspots.deinit(a);
    const Body = struct { tokens: usize, locations: std.ArrayList(Location) = .empty };
    var bodies: std.StringHashMap(Body) = .init(a);
    defer {
        var values = bodies.valueIterator();
        while (values.next()) |value| value.locations.deinit(a);
        bodies.deinit();
    }
    for (files) |file| {
        const total = &summary[@intFromEnum(file.scope)];
        total.files += 1;
        total.lines += file.lines;
        total.code_lines += file.code_lines;
        total.test_blocks += file.test_blocks;
        for (file.functions) |function| {
            const scope: model.Scope = if (function.in_test) .tests else file.scope;
            summary[@intFromEnum(scope)].functions += 1;
            const location: Location = .{ .path = file.path, .name = function.name, .line = function.start_line, .scope = scope };
            const candidate: Hotspot = .{
                .location = location,
                .lines = function.lines,
                .decision_tokens = function.decision_tokens,
                .brace_depth = function.max_brace_depth,
                .long_function = function.lines >= thresholds.function_lines,
                .many_decisions = function.decision_tokens >= thresholds.decision_tokens,
                .deep_braces = function.max_brace_depth >= thresholds.brace_depth,
            };
            if (candidate.long_function or candidate.many_decisions or candidate.deep_braces) try hotspots.append(a, candidate);
            if (function.body_tokens >= thresholds.duplicate_body_tokens) {
                const entry = try bodies.getOrPut(function.body_key);
                if (!entry.found_existing) entry.value_ptr.* = .{ .tokens = function.body_tokens };
                try entry.value_ptr.locations.append(a, location);
            }
        }
    }
    var duplicates: std.ArrayList(Duplicates) = .empty;
    defer duplicates.deinit(a);
    var entries = bodies.iterator();
    while (entries.next()) |entry| {
        if (entry.value_ptr.locations.items.len < 2) continue;
        try duplicates.append(a, .{ .body_tokens = entry.value_ptr.tokens, .occurrences = try a.dupe(Location, entry.value_ptr.locations.items) });
    }
    std.mem.sort(Hotspot, hotspots.items, {}, hotspotLess);
    std.mem.sort(Duplicates, duplicates.items, {}, duplicateLess);
    return .{ .summary = summary, .files = files, .hotspots = try hotspots.toOwnedSlice(a), .duplicate_groups = try duplicates.toOwnedSlice(a) };
}

fn fileLess(_: void, left: model.File, right: model.File) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}
fn locationLess(left: Location, right: Location) bool {
    const order = std.mem.order(u8, left.path, right.path);
    if (order != .eq) return order == .lt;
    if (left.line != right.line) return left.line < right.line;
    return std.mem.lessThan(u8, left.name, right.name);
}
fn hotspotLess(_: void, left: Hotspot, right: Hotspot) bool {
    if (left.decision_tokens != right.decision_tokens) return left.decision_tokens > right.decision_tokens;
    if (left.lines != right.lines) return left.lines > right.lines;
    return locationLess(left.location, right.location);
}
fn duplicateLess(_: void, left: Duplicates, right: Duplicates) bool {
    if (left.body_tokens != right.body_tokens) return left.body_tokens > right.body_tokens;
    return locationLess(left.occurrences[0], right.occurrences[0]);
}

pub fn markdown(a: std.mem.Allocator, report: Report) ![]const u8 {
    var output: std.Io.Writer.Allocating = .init(a);
    defer output.deinit();
    const w = &output.writer;
    try w.writeAll("# Code heuristics report\n\nRerun: `zig build code-heuristics`. Full measurements: `report.json`.\n\n");
    try w.writeAll("Advisory source-structure signals for review; no correctness, security, coverage or semantic-quality verdict is implied. Thresholds never fail CI.\n\n");
    try w.writeAll("## Scope and method\n\nGit-tracked and unignored untracked Zig files in the repository root, `src/`, `test/` and `build/`; tracked deletions are excluded. Generated outputs, dependencies, design examples and ignored files are excluded. Invalid or unreadable selected source fails the report.\n\n");
    try w.writeAll("Code lines contain non-comment Zig tokens, including multiline literal contents. Function spans include the signature and body. Decision tokens count `if`, `for`, `while`, `switch`, `catch`, `orelse`, `and`, `or`; this is a syntactic complexity proxy, not cyclomatic complexity (switch arms are not counted). Brace depth includes the outer body and initializer/container braces. Nested function tokens also contribute to enclosing functions.\n\n");
    try w.writeAll("Duplicate candidates have identical complete function-body token spellings after removing whitespace and comments; identifiers and literal values remain significant. Only bodies with at least 80 tokens qualify. Partial or renamed clones are not detected. Shared bodies can be intentional.\n\n");
    try w.writeAll("Production/test/tooling scopes follow directory and test-file naming conventions. Inline test blocks are counted in their source file; functions inside tests are attributed to tests. File line totals include inline tests. This is source inventory, not executable reachability analysis.\n\n");
    try w.writeAll("## Inventory\n\n| Scope | Files | Physical lines | Code lines | Functions | Test blocks |\n| --- | ---: | ---: | ---: | ---: | ---: |\n");
    for (report.summary) |row| try w.print("| {s} | {d} | {d} | {d} | {d} | {d} |\n", .{ @tagName(row.scope), row.files, row.lines, row.code_lines, row.functions, row.test_blocks });
    try w.print("\nReview thresholds (inclusive): file ≥{d} code lines; function ≥{d} physical lines; ≥{d} decision tokens; brace depth ≥{d}.\n", .{ thresholds.file_code_lines, thresholds.function_lines, thresholds.decision_tokens, thresholds.brace_depth });
    for (std.enums.values(model.Scope)) |scope| {
        try w.print("\n## {s} function review candidates\n\n", .{@tagName(scope)});
        try w.writeAll("Highest decision counts first, then longest spans; first 30 shown. All candidates appear in JSON.\n\n| Source | Function | Lines | Decisions | Brace depth | Signals |\n| --- | --- | ---: | ---: | ---: | --- |\n");
        var count: usize = 0;
        for (report.hotspots) |item| {
            if (item.location.scope != scope) continue;
            if (count == 30) break;
            count += 1;
            try w.writeAll("| ");
            try cell(w, item.location.path);
            try w.print(":{d} | ", .{item.location.line});
            try cell(w, item.location.name);
            try w.print(" | {d} | {d} | {d} |", .{ item.lines, item.decision_tokens, item.brace_depth });
            if (item.long_function) try w.writeAll(" long");
            if (item.many_decisions) try w.writeAll(" decisions");
            if (item.deep_braces) try w.writeAll(" depth");
            try w.writeAll(" |\n");
        }
        if (count == 0) try w.writeAll("\nNo function crosses these thresholds.\n");
    }
    try w.writeAll("\n## Large files\n\nAll files at or above the code-line threshold, sorted by code lines.\n\n| Source | Scope | Code lines | Physical lines |\n| --- | --- | ---: | ---: |\n");
    const ranked = try a.dupe(model.File, report.files);
    defer a.free(ranked);
    std.mem.sort(model.File, ranked, {}, struct {
        fn less(_: void, l: model.File, r: model.File) bool {
            if (l.code_lines != r.code_lines) return l.code_lines > r.code_lines;
            return fileLess({}, l, r);
        }
    }.less);
    var large: usize = 0;
    for (ranked) |file| {
        if (file.code_lines < thresholds.file_code_lines) continue;
        large += 1;
        try w.writeAll("| ");
        try cell(w, file.path);
        try w.print(" | {s} | {d} | {d} |\n", .{ @tagName(file.scope), file.code_lines, file.lines });
    }
    if (large == 0) try w.writeAll("\nNo file crosses this threshold.\n");
    try w.print("\n## Repeated function bodies\n\n{d} groups; first 20 shown, largest token count first. Full membership is in JSON. Review shared ownership before extracting helpers.\n", .{report.duplicate_groups.len});
    for (report.duplicate_groups[0..@min(20, report.duplicate_groups.len)], 1..) |group, index| {
        try w.print("\n### Group {d}: {d} tokens, {d} occurrences\n\n", .{ index, group.body_tokens, group.occurrences.len });
        for (group.occurrences) |location| {
            try w.writeAll("- ");
            try cell(w, location.path);
            try w.print(":{d} — ", .{location.line});
            try cell(w, location.name);
            try w.print(" ({s})\n", .{@tagName(location.scope)});
        }
    }
    return output.toOwnedSlice();
}

fn cell(w: *std.Io.Writer, value: []const u8) !void {
    for (value) |byte| switch (byte) {
        '|', '\\', '`', '*', '_', '[', ']', '#' => {
            try w.writeByte('\\');
            try w.writeByte(byte);
        },
        '<' => try w.writeAll("&lt;"),
        '>' => try w.writeAll("&gt;"),
        '&' => try w.writeAll("&amp;"),
        '\n', '\r' => try w.writeByte(' '),
        else => try w.writeByte(byte),
    };
}

test "report is deterministic across inventory ordering and scopes test functions separately" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const analyze = @import("analyze.zig").analyze;
    const engine = try analyze(a, "src/demo.zig", "fn alpha() void {}\ntest { const T = struct { fn helper() void {} }; _ = T; }\n");
    const tests = try analyze(a, "test/demo.zig", "fn beta() void {}\n");
    const first = try build(a, &.{ engine, tests });
    const second = try build(a, &.{ tests, engine });
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, first, .{}), try std.json.Stringify.valueAlloc(a, second, .{}));
    try std.testing.expectEqualStrings(try markdown(a, first), try markdown(a, second));
    try std.testing.expectEqual(@as(usize, 1), first.summary[0].functions);
    try std.testing.expectEqual(@as(usize, 2), first.summary[1].functions);
    const json = try std.json.Stringify.valueAlloc(a, first, .{});
    try std.testing.expect(std.mem.indexOf(u8, json, "body_key") == null);
}

test "inclusive review thresholds and exact duplicate body confirmation" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base: model.Function = .{ .name = "a|`", .start_line = 1, .end_line = 80, .lines = 80, .body_tokens = 80, .decision_tokens = 15, .max_brace_depth = 5, .in_test = false, .body_key = "exact" };
    var other = base;
    other.name = "b";
    var different = base;
    different.name = "c";
    different.body_key = "different";
    var below = base;
    below.name = "d";
    below.lines = 79;
    below.decision_tokens = 14;
    below.max_brace_depth = 4;
    below.body_tokens = 79;
    const report = try build(a, &.{.{ .path = "src/a.zig", .scope = .production, .bytes = 0, .lines = 0, .code_lines = 0, .test_blocks = 0, .functions = &.{ base, other, different, below } }});
    try std.testing.expectEqual(@as(usize, 3), report.hotspots.len);
    try std.testing.expectEqual(@as(usize, 1), report.duplicate_groups.len);
    try std.testing.expectEqual(@as(usize, 2), report.duplicate_groups[0].occurrences.len);
    const md = try markdown(a, report);
    try std.testing.expect(std.mem.indexOf(u8, md, "a\\|\\`") != null);
}

test "empty inventory produces valid report without review candidates" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const report = try build(arena.allocator(), &.{});
    try std.testing.expectEqual(@as(usize, 0), report.hotspots.len);
    try std.testing.expectEqual(@as(usize, 0), report.duplicate_groups.len);
    try std.testing.expect(std.mem.indexOf(u8, try markdown(arena.allocator(), report), "No file crosses") != null);
}
