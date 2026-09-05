const std = @import("std");
const rules = @import("domain/naming_rule.zig");
const naming = @import("domain/naming_policy.zig");
const grammar = @import("domain/path_token_grammar.zig");
const scanning = @import("domain/path_token_scan.zig");
const safety = @import("domain/toolchain_safety.zig");
const toolchain = @import("domain/toolchain.zig");
const fixture = @import("reference_evidence_test.zig");
const ingest = @import("reference_ingestion_test.zig").read;
const unicode = @import("unicode_normalization");
const normalize: @import("ports/unicode_normalizer.zig").Normalizer = .{ .normalize_fn = unicode.nfc };
const fold: @import("ports/unicode_normalizer.zig").CaseFolder = .{ .fold_fn = unicode.caseFold };
const classifier: @import("ports/unicode_normalizer.zig").LexicalClassifier = .{ .boundary_fn = unicode.lexicalBoundary };
const compile_action = @import("actions/toolchain/compile_naming_policy.zig").Action{ .normalizer = normalize, .folder = fold };
const build_action = @import("actions/reference/build_superset_path_token_grammar.zig").Action{ .normalizer = normalize, .folder = fold };
const scan_action = @import("actions/reference/scan_path_tokens.zig").Action{ .normalizer = normalize, .folder = fold, .classifier = classifier };

const registry: toolchain.PolicyRegistry = .{ .contracts = &.{
    .{ .id = "core@1", .project_selectable = false, .locked_required = true, .naming = &.{.{ .id = .{ .bytes = "core.reserved" }, .kind = .reserved, .value = "engine.config", .case_sensitive = true }} },
    .{ .id = "language@1", .project_selectable = true, .locked_required = false, .naming = &.{
        .{ .id = .{ .bytes = "language.extension" }, .kind = .extension, .value = ".test.widget", .case_sensitive = false },
        .{ .id = .{ .bytes = "language.exact" }, .kind = .exact, .value = "Dockerfile", .case_sensitive = true },
        .{ .id = .{ .bytes = "language.manifest" }, .kind = .manifest, .value = ".env", .case_sensitive = true },
        .{ .id = .{ .bytes = "language.glob" }, .kind = .glob, .value = "Build[0-9]?*", .case_sensitive = true },
        .{ .id = .{ .bytes = "language.unicode" }, .kind = .exact, .value = "Straße", .case_sensitive = false },
    } },
    .{ .id = "unselected@1", .project_selectable = true, .locked_required = false, .naming = &.{.{ .id = .{ .bytes = "unselected.exact" }, .kind = .exact, .value = "Secretfile", .case_sensitive = true }} },
    .{ .id = "empty@1", .project_selectable = true, .locked_required = false, .naming = &.{} },
} };
fn authority(allocator: std.mem.Allocator) !*safety.Owner {
    return safety.validate(allocator, .{ .packages = &.{"arbitrary@1.0.0"}, .policies = &.{ "language@1", "empty@1" } }, registry);
}

test "closed registered naming rules reject malformed and ambiguous declarations" {
    for ([_]rules.Rule{
        .{ .id = .{ .bytes = "" }, .kind = .exact, .value = "name", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .extension, .value = "widget", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .exact, .value = "src/file", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .exact, .value = "file%252Fname", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .glob, .value = "*.{a,b}", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .glob, .value = "**file", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .glob, .value = "[z-a]", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .glob, .value = "[", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .glob, .value = "[!a]", .case_sensitive = true },
        .{ .id = .{ .bytes = "rule" }, .kind = .exact, .value = "\xff", .case_sensitive = true },
    }) |bad| {
        try std.testing.expectError(error.InvalidNamingRule, rules.validate(&.{bad}));
        const bad_registry: toolchain.PolicyRegistry = .{ .contracts = &.{.{ .id = "unused@1", .project_selectable = true, .locked_required = false, .naming = &.{bad} }} };
        try std.testing.expectError(error.InvalidToolchain, safety.validate(std.testing.allocator, .{ .packages = &.{}, .policies = &.{} }, bad_registry));
    }
    const repeated = registry.contracts[0].naming[0];
    try std.testing.expectError(error.InvalidNamingRule, rules.validate(&.{ repeated, repeated }));
    const overlap: toolchain.PolicyRegistry = .{ .contracts = &.{ registry.contracts[0], .{ .id = "different@1", .project_selectable = true, .locked_required = false, .naming = &.{repeated} } } };
    try std.testing.expectError(error.InvalidToolchain, safety.validate(std.testing.allocator, .{ .packages = &.{}, .policies = &.{} }, overlap));
}

test "naming compilation includes all selected policies and exact rule provenance" {
    const owner = try authority(std.testing.allocator);
    defer safety.deinitOwner(owner);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const compiled = try compile_action.execute(arena.allocator(), safety.value(owner));
    try std.testing.expectEqual(@as(usize, 3), compiled.policy_ids.len);
    try std.testing.expectEqual(@as(usize, 6), compiled.rules.len);
    try std.testing.expectEqualStrings("empty@1", compiled.policy_ids[2]);
    try std.testing.expectEqualStrings("strasse", compiled.rules[5].rule.value);
    try naming.validateBinding(arena.allocator(), compiled, safety.value(owner), normalize, fold);
    for (0..5) |case| {
        var broken = compiled;
        var changed = compiled.rules[0];
        const entries = try arena.allocator().dupe(naming.BoundRule, compiled.rules);
        switch (case) {
            0 => broken.policy_ids = compiled.policy_ids[0..2],
            1 => broken.rules = compiled.rules[0..5],
            2 => {
                changed.rule.value = "altered";
                entries[0] = changed;
                broken.rules = entries;
            },
            3 => {
                changed.rule.case_sensitive = false;
                entries[0] = changed;
                broken.rules = entries;
            },
            4 => {
                entries[1] = entries[0];
                broken.rules = entries;
            },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidNamingPolicy, naming.validateBinding(arena.allocator(), broken, safety.value(owner), normalize, fold));
    }
    const successor = try authority(std.testing.allocator);
    defer safety.deinitOwner(successor);
    try std.testing.expectError(error.StaleNamingPolicy, naming.validateBinding(arena.allocator(), compiled, safety.value(successor), normalize, fold));
}

test "safety owns naming descriptor bytes independently of the input registry" {
    var original = "Ownedfile".*;
    const mutable: toolchain.PolicyRegistry = .{ .contracts = &.{.{ .id = "mutable@1", .project_selectable = true, .locked_required = false, .naming = &.{.{ .id = .{ .bytes = "mutable.exact" }, .kind = .exact, .value = &original, .case_sensitive = true }} }} };
    const owner = try safety.validate(std.testing.allocator, .{ .packages = &.{}, .policies = &.{"mutable@1"} }, mutable);
    defer safety.deinitOwner(owner);
    @memset(&original, 'x');
    try std.testing.expectEqualStrings("Ownedfile", safety.value(owner).policies()[0].naming[0].value);
}

test "one detector recognizes policy reference path and URI tokens with original byte spans" {
    const owner = try authority(std.testing.allocator);
    defer safety.deinitOwner(owner);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(allocator, &ids, try ingest(allocator, "Café.md", "source\n"));
    const compiled = try build_action.execute(allocator, try compile_action.execute(allocator, safety.value(owner)), safety.value(owner), inputs);
    const text = "Plain words, (engine.config), app.TEST.WIDGET; Dockerfile .env Build2αTail STRASSE «Cafe\u{301}.md» src/main.go C:\\temp\\file \\\\server\\share / mailto:a@example.test https://example.test/a?q=1 file%252Fname. Secretfile dockerfile unknown.ext 1.25";
    const result = try scan_action.execute(std.testing.allocator, compiled, safety.value(owner), inputs, text);
    defer scanning.destroy(result);
    const expected = [_][]const u8{ "engine.config", "app.TEST.WIDGET", "Dockerfile", ".env", "Build2αTail", "STRASSE", "Cafe\u{301}.md", "src/main.go", "C:\\temp\\file", "\\\\server\\share", "/", "mailto:a@example.test", "https://example.test/a?q=1", "file%252Fname" };
    try std.testing.expectEqual(expected.len, result.matches.len);
    for (expected, result.matches, 0..) |token, match, index| {
        try std.testing.expectEqualStrings(token, result.text[match.start_byte..match.end_byte]);
        const expected_kind: scanning.Kind = if (index < 7) .display_filename else if (index == 11 or index == 12) .external_uri else .display_path;
        try std.testing.expectEqual(expected_kind, match.kind);
    }
    var changed = inputs;
    changed.corpus.state_id.bytes = "different";
    try std.testing.expectError(error.InvalidPathTokenGrammar, scan_action.execute(std.testing.allocator, compiled, safety.value(owner), changed, text));
    var missing = compiled;
    missing.reference_names = &.{};
    try std.testing.expectError(error.InvalidPathTokenGrammar, scan_action.execute(std.testing.allocator, missing, safety.value(owner), inputs, text));
    var wrong_feature = compiled;
    wrong_feature.feature_id.bytes = "unrelated-feature";
    try std.testing.expectError(error.InvalidPathTokenGrammar, scan_action.execute(std.testing.allocator, wrong_feature, safety.value(owner), inputs, text));
    var wrong_source = compiled;
    var names = [_]grammar.ReferenceName{compiled.reference_names[0]};
    names[0].source_id.ordinal += 1;
    wrong_source.reference_names = &names;
    try std.testing.expectError(error.InvalidPathTokenGrammar, scan_action.execute(std.testing.allocator, wrong_source, safety.value(owner), inputs, text));
    names[0] = compiled.reference_names[0];
    names[0].basename = "other.md";
    try std.testing.expectError(error.InvalidPathTokenGrammar, scan_action.execute(std.testing.allocator, wrong_source, safety.value(owner), inputs, text));
    try std.testing.expectError(error.InvalidPathTokenText, scan_action.execute(std.testing.allocator, compiled, safety.value(owner), inputs, "\xff"));
    try std.testing.expectError(error.InvalidPathTokenText, scan_action.execute(std.testing.allocator, compiled, safety.value(owner), inputs, "source\x00.md"));
    const punctuation = try scan_action.execute(std.testing.allocator, compiled, safety.value(owner), inputs, "Dockerfile? ‘Dockerfile’\u{2003}.env: https://example.test/a?q=1&b=2#part");
    defer scanning.destroy(punctuation);
    const lexemes = [_][]const u8{ "Dockerfile", "Dockerfile", ".env", "https://example.test/a?q=1&b=2#part" };
    try std.testing.expectEqual(lexemes.len, punctuation.matches.len);
    for (lexemes, punctuation.matches) |lexeme, match| try std.testing.expectEqualStrings(lexeme, punctuation.text[match.start_byte..match.end_byte]);
}

test "runner-owned grammar retains rules reference names and exact identity after producer cleanup" {
    const values = @import("application/pipeline_values.zig");
    const schema = @import("application/path_token_workflow.zig").grammar_schema;
    const retained = retained: {
        const owner = try authority(std.testing.allocator);
        defer safety.deinitOwner(owner);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        var ids: fixture.IdSource = .{};
        const inputs = try fixture.prepare(arena.allocator(), &ids, try ingest(arena.allocator(), "notes.md", "source\n"));
        const compiled = try build_action.execute(arena.allocator(), try compile_action.execute(arena.allocator(), safety.value(owner)), safety.value(owner), inputs);
        break :retained try values.create(std.testing.allocator, schema, grammar.Grammar, compiled);
    };
    defer values.destroy(retained);
    var data: @import("domain/pipeline_data.zig").View = .{};
    data.slots[@intFromEnum(schema.key)] = retained;
    const compiled = try values.read(&data, schema, grammar.Grammar);
    try std.testing.expectEqualStrings("notes.md", compiled.reference_names[0].basename);
    try std.testing.expectEqualStrings("strasse", compiled.policy.rules[5].rule.value);
    const successor = try authority(std.testing.allocator);
    defer safety.deinitOwner(successor);
    try std.testing.expectError(error.StaleNamingPolicy, naming.validateBinding(std.testing.allocator, compiled.policy, safety.value(successor), normalize, fold));
}

test "basename glob matching is whole-token Unicode-aware and has no regex fallback" {
    const rule: rules.Rule = .{ .id = .{ .bytes = "r" }, .kind = .glob, .value = "file[0-9]?*", .case_sensitive = true };
    try rules.validate(&.{rule});
    for ([_][]const u8{ "file1é", "file2ab", "file3界tail" }) |value| try std.testing.expect(rules.matches(rule, value));
    for ([_][]const u8{ "file1", "xfile1a", "filea1", "file[0-9]a" }) |value| try std.testing.expect(!rules.matches(rule, value));
}

test "path-token preparation and scanning clean up after every allocation failure" {
    try allocationCase(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}
fn allocationCase(allocator: std.mem.Allocator) !void {
    const owner = authority(allocator) catch |err| return if (err == error.InvalidToolchain) error.OutOfMemory else err;
    defer safety.deinitOwner(owner);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var ids: fixture.IdSource = .{};
    const inputs = try fixture.prepare(arena.allocator(), &ids, try ingest(arena.allocator(), "source.md", "source\n"));
    const policy = try compile_action.execute(arena.allocator(), safety.value(owner));
    const compiled = try build_action.execute(arena.allocator(), policy, safety.value(owner), inputs);
    const result = try scan_action.execute(allocator, compiled, safety.value(owner), inputs, "source.md Dockerfile src/main.go");
    defer scanning.destroy(result);
    try std.testing.expectEqual(@as(usize, 3), result.matches.len);
}
