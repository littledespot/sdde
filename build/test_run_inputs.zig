//! Ignored locations that offline tests read, and live output roots that they don't.
//!
//! Git doesn't list ignored files, so opt-in test-run reuse (`test_run_reuse.zig`)
//! hashes every `ignored` location into its key. Every string literal in test
//! sources that names a path under `.zig-cache/` or `zig-out/` must be covered here.
//! The test below rejects one that isn't, so a new runtime input can't go unkeyed.
const std = @import("std");

/// Hashed into the key, whether or not they exist. Each covers every entry of its
/// parent directory whose name starts with its last component, recursively.
/// Locations that tests also write are included, at the cost of fewer reuses.
pub const ignored = [_][]const u8{
    ".zig-cache/authoring-associations",
    ".zig-cache/authoring-comparison",
    ".zig-cache/chunk13-admission-",
    ".zig-cache/chunk13-compatible-request",
    ".zig-cache/chunk13-conflict-request",
    ".zig-cache/chunk18-stack-request-after.json",
    ".zig-cache/chunk18-stack-request-before.json",
    ".zig-cache/d1-review",
    ".zig-cache/exact-value-production-admission",
    ".zig-cache/fix002-question-conflict",
    ".zig-cache/membership-extra",
    ".zig-cache/membership-missing",
    ".zig-cache/phase4-complete",
    ".zig-cache/phase4-question",
    ".zig-cache/phase4-unjustified",
    ".zig-cache/principle-citation-alternating",
    ".zig-cache/principle-citation-recovery",
    ".zig-cache/principle-citation-repeated",
    ".zig-cache/provenance-answer-exhaustion",
    ".zig-cache/provenance-answer-recovery",
    ".zig-cache/r35-request",
    ".zig-cache/r36-failure",
    ".zig-cache/r36-recovery",
    ".zig-cache/r37-recovery",
    ".zig-cache/r40-request",
    ".zig-cache/r41-recovery",
    ".zig-cache/r42-recovery",
    ".zig-cache/r43-recovery",
    ".zig-cache/representation-admission",
    ".zig-cache/review-assignment-",
    ".zig-cache/review-decision-greeting",
    ".zig-cache/review-decision-loan",
    ".zig-cache/semantic-simplicity/phase0",
    ".zig-cache/source-loss-citation-completeness-current-contract",
    ".zig-cache/source-review-handoff/current-advisory",
    ".zig-cache/source-review-record",
    ".zig-cache/source-review-scope",
    ".zig-cache/workflow-step-trace",
    "zig-out/baseline/claims",
    "zig-out/e2e-spec/2026-10-11T07-50-47Z-7c05a7d38e4f86264d45ec27a08a4959",
    "zig-out/e2e-spec/MOCK-run",
};

/// Live harness output roots. Only the live launchers write them, and tests use
/// the explicit locations above or their own temporary directories. They hold
/// gigabytes of retained evidence, so they're not hashed.
pub const live_output_roots = [_][]const u8{ "zig-out/e2e-spec", "zig-out/provider-compatibility", "zig-out/baseline", "zig-out/e2e-call" };

/// Literals that name an ignored path without reading the repository's copy of it:
/// path-classification and argument-parsing cases, and a write into a temporary
/// repository. Each applies to one file only.
pub const not_inputs = [_]struct { file: []const u8, literal: []const u8 }{
    .{ .file = "build/code_heuristics/analyze.zig", .literal = "zig-out/copy.zig" },
    .{ .file = "build/code_heuristics/model.zig", .literal = "zig-out/copy/main.zig" },
    .{ .file = "build/code_heuristics/model.zig", .literal = ".zig-cache/main.zig" },
    .{ .file = "build/code_heuristics/inventory.zig", .literal = "zig-out/generated.zig" },
    .{ .file = "build/code_heuristics/main.zig", .literal = "zig-out/code-heuristics" },
};

fn notInput(path: []const u8, literal: []const u8) bool {
    for (not_inputs) |entry| if (std.mem.eql(u8, entry.file, path) and std.mem.eql(u8, entry.literal, literal)) return true;
    return false;
}

/// `fixed` is a literal's text up to any format placeholder. Only a complete
/// literal may name a live output root; a formatted path under one is an input.
pub fn covered(fixed: []const u8, formatted: bool) bool {
    for (ignored) |location| if (std.mem.startsWith(u8, fixed, location)) return true;
    if (!formatted) for (live_output_roots) |root| if (std.mem.eql(u8, fixed, root)) return true;
    return false;
}

const prefixes = [_][]const u8{ "\".zig-cache/", "\"zig-out/" };

/// Appends each uncovered literal in `source` to `uncovered` as `<path>: <literal>`.
fn scan(a: std.mem.Allocator, path: []const u8, source: []const u8, uncovered: *std.ArrayList([]const u8)) !void {
    var index: usize = 0;
    while (index < source.len) : (index += 1) {
        const prefix = for (prefixes) |candidate| {
            if (std.mem.startsWith(u8, source[index..], candidate)) break candidate;
        } else continue;
        const start = index + 1;
        const end = std.mem.indexOfScalarPos(u8, source, start + prefix.len - 1, '"') orelse source.len;
        const text = source[start..end];
        // A format placeholder ends the fixed part of a path.
        const placeholder = std.mem.indexOfScalar(u8, text, '{');
        const fixed = std.mem.trimEnd(u8, text[0 .. placeholder orelse text.len], "/");
        if (!covered(fixed, placeholder != null) and !notInput(path, text)) try uncovered.append(a, try std.fmt.allocPrint(a, "{s}: {s}", .{ path, text }));
        index = end;
    }
}

fn scanTree(a: std.mem.Allocator, io: std.Io, root: []const u8, skipped: []const u8, uncovered: *std.ArrayList([]const u8)) !void {
    var directory = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
    defer directory.close(io);
    var walker = try directory.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or std.mem.eql(u8, entry.path, skipped)) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, a, .limited(16 * 1024 * 1024));
        try scan(a, try std.fmt.allocPrint(a, "{s}/{s}", .{ root, entry.path }), source, uncovered);
    }
}

test "every ignored path that test sources name is keyed or a live output root" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var uncovered: std.ArrayList([]const u8) = .empty;
    try scanTree(a, io, "src", "", &uncovered);
    try scanTree(a, io, "test", "", &uncovered);
    // This file's own tests name uncovered paths on purpose.
    try scanTree(a, io, "build", "test_run_inputs.zig", &uncovered);
    var root = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer root.close(io);
    var entries = root.iterate();
    while (try entries.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
        try scan(a, entry.name, try root.readFileAlloc(io, entry.name, a, .limited(16 * 1024 * 1024)), &uncovered);
    }
    for (uncovered.items) |item| std.debug.print("unkeyed ignored path: {s}\n", .{item});
    try std.testing.expectEqual(@as(usize, 0), uncovered.items.len);
}

test "ignored-path coverage accepts listed locations and rejects new ones" {
    try std.testing.expect(covered(".zig-cache/authoring-associations/v14-text", false));
    try std.testing.expect(covered(".zig-cache/review-assignment-", true));
    try std.testing.expect(covered("zig-out/e2e-spec", false));
    try std.testing.expect(!covered("zig-out/e2e-spec", true));
    try std.testing.expect(!covered("zig-out/e2e-spec/2026-01-01T00-00-00Z-new-run", false));
    try std.testing.expect(!covered(".zig-cache/new-evidence", false));

    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var uncovered: std.ArrayList([]const u8) = .empty;
    try scan(arena.allocator(), "sample.zig", "const a = \".zig-cache/new-evidence/{s}.json\"; const b = \".zig-cache/d1-review\"; const c = \"zig-out/e2e-spec/{s}/report.json\";", &uncovered);
    try std.testing.expectEqual(@as(usize, 2), uncovered.items.len);
    try std.testing.expectEqualStrings("sample.zig: .zig-cache/new-evidence/{s}.json", uncovered.items[0]);
    try std.testing.expectEqualStrings("sample.zig: zig-out/e2e-spec/{s}/report.json", uncovered.items[1]);

    // An exception names one file; the same literal elsewhere is still checked.
    uncovered.clearRetainingCapacity();
    try scan(arena.allocator(), "build/code_heuristics/analyze.zig", "\"zig-out/copy.zig\"", &uncovered);
    try std.testing.expectEqual(@as(usize, 0), uncovered.items.len);
    try scan(arena.allocator(), "src/reader.zig", "\"zig-out/copy.zig\"", &uncovered);
    try std.testing.expectEqual(@as(usize, 1), uncovered.items.len);
}
