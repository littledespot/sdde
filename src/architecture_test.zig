const std = @import("std");

test "unit test import trees cannot discover integration scenarios" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var pending: std.ArrayList([]const u8) = .empty;
    var visited: std.StringHashMap(void) = .init(allocator);
    const project_root = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, ".", allocator);
    for ([_][]const u8{ "tests.zig", "src/root.zig", "src/main.zig" }) |root| {
        try pending.append(allocator, try std.fs.path.resolve(allocator, &.{ project_root, root }));
    }
    while (pending.pop()) |path| {
        if ((try visited.getOrPut(path)).found_existing) continue;
        try validateUnitImportPath(path);
        const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, allocator, .limited(1024 * 1024));
        var tokens = std.zig.Tokenizer.init(try allocator.dupeZ(u8, source));
        while (true) {
            const token = tokens.next();
            if (token.tag == .eof) break;
            if (token.tag != .builtin or !std.mem.eql(u8, source[token.loc.start..token.loc.end], "@import")) continue;
            try std.testing.expectEqual(.l_paren, tokens.next().tag);
            const literal = tokens.next();
            try std.testing.expectEqual(.string_literal, literal.tag);
            const imported = try std.zig.string_literal.parseAlloc(allocator, source[literal.loc.start..literal.loc.end]);
            if (!std.mem.endsWith(u8, imported, ".zig")) continue;
            try pending.append(allocator, try std.fs.path.resolve(allocator, &.{ std.fs.path.dirname(path).?, imported }));
        }
    }
}

fn validateUnitImportPath(path: []const u8) !void {
    if (std.mem.indexOf(u8, path, "/test/integration/") != null or
        std.mem.indexOf(u8, path, "/test/harness/integration/") != null or
        std.mem.endsWith(u8, path, "/integration.zig")) return error.IntegrationTestImport;
}

test "unit import routing accepts internal tests and rejects each integration root" {
    try validateUnitImportPath("/repo/src/workflow_execution_test.zig");
    try validateUnitImportPath("/repo/test/harness/tests.zig");
    try std.testing.expectError(error.IntegrationTestImport, validateUnitImportPath("/repo/test/integration/workflow_tests.zig"));
    try std.testing.expectError(error.IntegrationTestImport, validateUnitImportPath("/repo/test/harness/integration/tests.zig"));
    try std.testing.expectError(error.IntegrationTestImport, validateUnitImportPath("/repo/integration.zig"));
}

// Zig compiles a test only when a compilation root's import graph reaches its file, so a test file that nothing imports
// never runs and nothing fails. The graph is read from `@import` tokens. Reaching a file by text is necessary for its
// tests to run, not sufficient: Zig analyzes a reached file only where a declaration refers to it.
fn isTestFileName(path: []const u8) bool {
    const name = std.fs.path.basename(path);
    return std.mem.endsWith(u8, name, "_test.zig") or std.mem.endsWith(u8, name, "_tests.zig") or std.mem.eql(u8, name, "tests.zig");
}

fn pathLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The test files of `sources` (absolute-style path to bytes) that no root reaches through relative `@import`s, in
/// path order. A root is a file by itself, reached or not by any other.
fn unreachableTestFiles(allocator: std.mem.Allocator, sources: *const std.StringHashMap([]const u8), roots: []const []const u8) ![]const []const u8 {
    var reached: std.StringHashMap(void) = .init(allocator);
    var pending: std.ArrayList([]const u8) = .empty;
    for (roots) |root| try pending.append(allocator, root);
    while (pending.pop()) |path| {
        if ((try reached.getOrPut(path)).found_existing) continue;
        const source = sources.get(path) orelse continue;
        for (try importsOf(allocator, source)) |imported| {
            if (!std.mem.endsWith(u8, imported, ".zig")) continue;
            try pending.append(allocator, try std.fs.path.resolve(allocator, &.{ std.fs.path.dirname(path).?, imported }));
        }
    }
    var missing: std.ArrayList([]const u8) = .empty;
    var iterator = sources.keyIterator();
    while (iterator.next()) |path| {
        if (isTestFileName(path.*) and !reached.contains(path.*)) try missing.append(allocator, path.*);
    }
    std.mem.sort([]const u8, missing.items, {}, pathLessThan);
    return missing.toOwnedSlice(allocator);
}

/// Every `.zig` path that `build.zig` spells as a string, as an absolute-style path: each is a compilation root, so
/// the roots come from the build and not from a list kept here. The set is an upper bound: a path named only as a
/// lint or copy argument also counts, so the check cannot see a test file the build merely names.
fn buildRoots(allocator: std.mem.Allocator, build_source: []const u8) ![]const []const u8 {
    const terminated = try allocator.dupeZ(u8, build_source);
    var roots: std.ArrayList([]const u8) = .empty;
    var tokens = std.zig.Tokenizer.init(terminated);
    while (true) {
        const token = tokens.next();
        if (token.tag == .eof) break;
        if (token.tag != .string_literal) continue;
        const literal = try std.zig.string_literal.parseAlloc(allocator, terminated[token.loc.start..token.loc.end]);
        if (!std.mem.endsWith(u8, literal, ".zig")) continue;
        try roots.append(allocator, try std.fs.path.resolve(allocator, &.{ "/", literal }));
    }
    return roots.toOwnedSlice(allocator);
}

test "every test file in the repository is reachable from a build root" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var sources: std.StringHashMap([]const u8) = .init(allocator);
    var project = try std.Io.Dir.cwd().openDir(io, ".", .{ .iterate = true });
    defer project.close(io);
    var top = project.iterate();
    while (try top.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
        try sources.put(try std.fmt.allocPrint(allocator, "/{s}", .{entry.name}), try project.readFileAlloc(io, entry.name, allocator, .limited(4 * 1024 * 1024)));
    }
    for ([_][]const u8{ "src", "test", "build" }) |name| {
        var directory = try project.openDir(io, name, .{ .iterate = true });
        defer directory.close(io);
        var walker = try directory.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            try sources.put(try std.fmt.allocPrint(allocator, "/{s}/{s}", .{ name, entry.path }), try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024)));
        }
    }
    const roots = try buildRoots(allocator, sources.get("/build.zig").?);
    try std.testing.expect(roots.len != 0);
    const missing = try unreachableTestFiles(allocator, &sources, roots);
    for (missing) |path| std.debug.print("a test file no build root reaches: {s}\n", .{path});
    try std.testing.expectEqual(@as(usize, 0), missing.len);
}

test "test reachability follows imports from every root and reports an orphaned test file" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var sources: std.StringHashMap([]const u8) = .init(allocator);
    try sources.put("/root.zig", "comptime { _ = @import(\"a_test.zig\"); _ = @import(\"std\"); }");
    try sources.put("/a_test.zig", "const b = @import(\"sub/b_tests.zig\");");
    try sources.put("/sub/b_tests.zig", "const helper = @import(\"../helper.zig\");");
    try sources.put("/helper.zig", "");
    // Reached by nothing, but a helper rather than a test file, so it is not reported.
    try sources.put("/unused_helper.zig", "");
    try std.testing.expectEqual(@as(usize, 0), (try unreachableTestFiles(allocator, &sources, &.{"/root.zig"})).len);

    // A test file no root imports, one named `tests.zig` in a directory, and two that a comment or a string spells.
    try sources.put("/orphan_test.zig", "");
    try sources.put("/sub/tests.zig", "");
    try sources.put("/commented_test.zig", "");
    try sources.put("/stringy_test.zig", "");
    try sources.put("/mentions.zig", "// _ = @import(\"commented_test.zig\");\nconst text = \"@import(\\\"stringy_test.zig\\\")\";");
    const roots = [_][]const u8{ "/root.zig", "/mentions.zig" };
    const missing = try unreachableTestFiles(allocator, &sources, &roots);
    try std.testing.expectEqual(@as(usize, 4), missing.len);
    try std.testing.expectEqualStrings("/commented_test.zig", missing[0]);
    try std.testing.expectEqualStrings("/orphan_test.zig", missing[1]);
    try std.testing.expectEqualStrings("/stringy_test.zig", missing[2]);
    try std.testing.expectEqualStrings("/sub/tests.zig", missing[3]);

    // A second root that imports the orphan reaches it, and a root that is itself a test file is not reported.
    try sources.put("/second_root.zig", "const orphan = @import(\"orphan_test.zig\");");
    const rooted = try unreachableTestFiles(allocator, &sources, &.{ "/root.zig", "/mentions.zig", "/second_root.zig", "/stringy_test.zig" });
    try std.testing.expectEqual(@as(usize, 2), rooted.len);
    try std.testing.expectEqualStrings("/commented_test.zig", rooted[0]);
    try std.testing.expectEqualStrings("/sub/tests.zig", rooted[1]);
}

test "build roots are the zig paths build.zig spells in code" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const roots = try buildRoots(allocator,
        \\const a = b.path("src/root.zig"); // b.path("commented.zig")
        \\const names = [_][]const u8{ "tests.zig", "case.json", "src/main.zig" };
    );
    try std.testing.expectEqual(@as(usize, 3), roots.len);
    try std.testing.expectEqualStrings("/src/root.zig", roots[0]);
    try std.testing.expectEqualStrings("/tests.zig", roots[1]);
    try std.testing.expectEqualStrings("/src/main.zig", roots[2]);
}

test "production sources exclude internal evaluation tooling and test environment configuration" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.endsWith(u8, entry.basename, "_test.zig") or
            std.mem.endsWith(u8, entry.basename, "_test_fixture.zig") or
            std.mem.eql(u8, entry.basename, "runtime_tests.zig") or
            std.mem.startsWith(u8, entry.path, "test_fixtures/")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        inline for (.{ "test/harness/", "\"harness.zig\"", ".env.e2e", "TEST_OPENAI_API_KEY", "TEST_AWS_BEARER_TOKEN_BEDROCK", "TEST_EVALUATION_PROVIDER", "TEST_EVALUATION_MODEL", "TEST_EVALUATION_REGION" }) |forbidden| try expectAbsent(source, forbidden);
    }
}

test "CLI and E2E invocation reuse production composition without harness assembly" {
    const io = std.testing.io;
    const source = try std.Io.Dir.cwd().readFileAlloc(io, "test/harness/e2e/invoke.zig", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(source);
    try std.testing.expect(std.mem.indexOf(u8, source, "root.Runtime") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "runtime.invocation(") != null);
    inline for (.{ "/adapters/filesystem/", "/adapters/parsers/", "/adapters/system/", "native_workflow_operations", "model_provider_bootstrap", "model_provider_runtime", "engine_invocation", "runInProjectWithRegistry" }) |forbidden| try expectAbsent(source, forbidden);
    const composition = @embedFile("composition/root.zig");
    try std.testing.expect(std.mem.indexOf(u8, composition, "var assembly: Runtime") != null);
    try std.testing.expect(std.mem.indexOf(u8, composition, "assembly.invocation(") != null);
}

test "the scripted matrix builds its runtime only through the production composition root" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const matrix = try std.Io.Dir.cwd().readFileAlloc(io, "test/integration/workflow_tests.zig", allocator, .limited(8 * 1024 * 1024));
    defer allocator.free(matrix);
    // Every scenario builds `composition.Runtime`; the file assembles no native operations and binds no roots of its own.
    try std.testing.expect(std.mem.indexOf(u8, matrix, "composition.Runtime") != null);
    inline for (.{ "native_workflow_operations", ".bindRoots(", ".bindWorkflows(", ".bindConfiguration(", ".bindPrinciples(" }) |forbidden| try expectAbsent(matrix, forbidden);
    // The one seam is a test-only guarded entry: `init` supplies no hook, and `initWith` cannot compile outside a test.
    try std.testing.expectEqual(@as(?[]const u8, null), runtimeSeamViolation(@embedFile("composition/root.zig")));
    // A source that names the assembly module in code is rejected; one that mentions it in a comment is not.
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const native = @import(\"../../src/composition/native_workflow_operations.zig\");", "native_workflow_operations"));
    try expectAbsent("// native_workflow_operations builds the assembly\nconst runtime = 1;", "native_workflow_operations");
    // The seam checker rejects a missing guard, a third caller of either phase, a second hook call and an optional hook.
    const guard = "if (!builtin.is_test) @compileError(\"Runtime.initWith is a test seam\");";
    const calls = "self.assemble(a);\nself.startup(a);\nself.assemble(a);\nself.startup(a);\nbefore_startup.run(c, n);\n";
    try std.testing.expectEqual(@as(?[]const u8, null), runtimeSeamViolation(guard ++ calls));
    try std.testing.expect(runtimeSeamViolation(calls) != null);
    try std.testing.expect(runtimeSeamViolation(guard ++ calls ++ "self.startup(a);\n") != null);
    try std.testing.expect(runtimeSeamViolation(guard ++ calls ++ "self.assemble(a);\n") != null);
    try std.testing.expect(runtimeSeamViolation(guard ++ calls ++ "before_startup.run(c, n);\n") != null);
    try std.testing.expect(runtimeSeamViolation(guard ++ calls ++ "hook: ?BeforeStartup,\n") != null);
}

test "the scripted driver names no unreachable, @panic or std.debug.panic, so a failed check there is returned" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const driver = try std.Io.Dir.cwd().readFileAlloc(io, "src/test_fixtures/spec_generation_driver.zig", allocator, .limited(2 * 1024 * 1024));
    defer allocator.free(driver);
    // An operation error, an unscripted request or a failed check in a hook is returned through `hookFailed`, which keeps
    // the first failure and fails its scenario; `unreachable` (after `catch`, after `orelse`, or as a switch arm) and a
    // panic would abort the test binary, and every scenario after it with it. A `.?` unwrap and `std.debug.assert` also
    // abort and are not covered by this pin, which guards these spellings only.
    for (aborting_spellings) |spelling| try expectAbsent(driver, spelling);
    // Code that aborts is rejected, whichever way it spells it; a comment that mentions it is not.
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const value = parse(bytes) catch unreachable;", "unreachable"));
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const value = first(bytes) orelse unreachable;", "unreachable"));
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const value = switch (kind) { .known => 1, else => unreachable };", "unreachable"));
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const value = @panic(\"invalid\");", "@panic("));
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const value = std.debug.panic(\"invalid\", .{});", "std.debug.panic("));
    try expectAbsent("// parse(bytes) catch unreachable, an else => unreachable arm, @panic(\"x\") and std.debug.panic(\"x\", .{}) would abort the run\nconst value = 1;", "unreachable");
    try expectAbsent("// @panic(\"x\") and std.debug.panic(\"x\", .{}) would abort the run\nconst value = 1;", "@panic(");
    try expectAbsent("// @panic(\"x\") and std.debug.panic(\"x\", .{}) would abort the run\nconst value = 1;", "std.debug.panic(");
}

/// What aborts the test binary where the scripted driver would fail its scenario.
const aborting_spellings = [_][]const u8{ "unreachable", "@panic(", "std.debug.panic(" };

/// The test seam in `composition/root.zig`: `initWith` is behind a compile-time test guard, `init` and `initWith` are the
/// only callers of the two construction phases (two each: assembly, then startup), and the hook runs once, between them,
/// so no production path holds an optional hook. Returns the failing condition, or null.
fn runtimeSeamViolation(source: []const u8) ?[]const u8 {
    if (countOccurrences(source, "if (!builtin.is_test) @compileError(\"Runtime.initWith is a test seam\");") != 1) return "the test guard";
    if (callCount(source, "self.assemble(") != 2) return "assemble callers";
    if (callCount(source, "self.startup(") != 2) return "startup callers";
    if (callCount(source, "before_startup.run(") != 1) return "hook calls";
    if (std.mem.indexOf(u8, source, "?BeforeStartup") != null) return "an optional hook";
    return null;
}

test "production provider wiring retains fact-only authority and no-I/O lease preparation" {
    const contracts_source = @embedFile("composition/provider_model_contracts.zig");
    try expectAbsent(contracts_source, "/adapters/");
    try expectAbsent(contracts_source, "api_key");
    try expectAbsent(contracts_source, "anyopaque");
    const runtime = @embedFile("composition/model_provider_runtime.zig");
    const validation = std.mem.indexOf(u8, runtime, "try runner.validateModelBindings();").?;
    const capture = std.mem.indexOf(u8, runtime, "source.read(").?;
    try std.testing.expect(validation < capture);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runtime, "source.read("));
    try expectAbsent(runtime, "Table.init");
    try expectAbsent(runtime, "countInputTokens(");
    const source = @embedFile("adapters/system/provider_api_key_source.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "environment.get("));
    inline for (.{ "std.http", "std.Io", "metadata", "getenv", "AWS_ACCESS_KEY_ID", "TEST_" }) |forbidden| try expectAbsent(source, forbidden);
    const authorization = @embedFile("adapters/provider/api_key_authorization.zig");
    inline for (.{ "std.http", "std.Io", "std.process", "provider_api_key_source", "environment", "logger", "/application/" }) |forbidden| try expectAbsent(authorization, forbidden);
    const provider_source = @embedFile("adapters/provider/model_provider.zig");
    inline for (.{ "/actions/", "/application/", "std.process", "std.Io", "workflow_token_accounting", "journal", "maxTokens", "max_tokens" }) |forbidden| try expectAbsent(provider_source, forbidden);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(provider_source, "self.transport.exchange("));
    const http = @embedFile("adapters/provider/model_http_exchange.zig");
    inline for (.{ "Environ", "initDefaultProxies", "ssl_key_log", "getenv", "@constCast" }) |forbidden| try expectAbsent(http, forbidden);
    try std.testing.expect(std.mem.indexOf(u8, http, "pub const Adapter = HttpAdapter(native.request);") != null);
    try std.testing.expect(std.mem.indexOf(u8, http, "@import(\"native_model_http.zig\")") != null);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(http, "try open_request("));
}

test "provider projections hold only their wire contract and never import a sibling provider" {
    const bedrock = .{ @embedFile("adapters/provider/bedrock_request.zig"), @embedFile("adapters/provider/bedrock_response.zig"), @embedFile("adapters/provider/bedrock_endpoint.zig") };
    const anthropic = .{ @embedFile("adapters/provider/anthropic_request.zig"), @embedFile("adapters/provider/anthropic_response.zig"), @embedFile("adapters/provider/anthropic_endpoint.zig") };
    // Projections never consume leases, read credentials, capture, connect or
    // reach workflow policy; the shared owners do.
    inline for (.{ "consume(", ".capture(", "provider_api_key", "api_key_authorization", "std.process", "native_model_http", "open_request", "model_http_exchange", "/application/", "/actions/" }) |forbidden| {
        inline for (bedrock) |projection| try expectAbsent(projection, forbidden);
        inline for (anthropic) |projection| try expectAbsent(projection, forbidden);
    }
    inline for (bedrock) |projection| try expectAbsent(projection, "anthropic_");
    inline for (anthropic) |projection| try expectAbsent(projection, "bedrock_");
    // Shared owners hold no provider wire spelling.
    inline for (.{ @embedFile("adapters/provider/model_text_request.zig"), @embedFile("adapters/provider/provider_response_support.zig"), @embedFile("adapters/provider/provider_response_assembly.zig"), @embedFile("domain/provider_failure.zig") }) |shared| {
        inline for (.{ "bedrock_", "anthropic_", "Converse", "x-api-key", "stopReason", "stop_reason" }) |wire| try expectAbsent(shared, wire);
    }
    // The domain retry classifier reads only neutral facts.
    inline for (.{ "/adapters/", "std.http", "status" }) |forbidden| try expectAbsent(@embedFile("domain/provider_failure.zig"), forbidden);
}
test "all native model HTTP adapters use the test-disabled connection owner" {
    const native = @embedFile("adapters/provider/native_model_http.zig");
    try std.testing.expect(std.mem.indexOf(u8, native, "if (builtin.is_test) false else @import(\"root\").live_model_connections") != null);
    const guard = std.mem.indexOf(u8, native, "if (!enabled) return error.LiveModelCallsDisabled;").?;
    const connect = std.mem.indexOf(u8, native, "return client.request(").?;
    try std.testing.expect(guard < connect);
    try expectAbsent(@embedFile("adapters/provider/model_http_exchange.zig"), "client.request(");
    const evaluator = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/harness/http.zig", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(evaluator);
    try expectAbsent(evaluator, "client.request(");
    try std.testing.expect(std.mem.indexOf(u8, evaluator, "native_model_http.zig\").request(&client,") != null);
}

const bootstrap_root_registry = @import("domain/bootstrap_root_registry.zig");
const bootstrap_root_registry_service = @import("application/bootstrap_root_registry_service.zig");
const workflow_registry = @import("domain/workflow_registry.zig");
const workflow_registry_service = @import("application/workflow_definition_registry_service.zig");
const toolchain_safety = @import("domain/toolchain_safety.zig");
const llm_provider_registry = @import("domain/llm_provider_registry.zig");
const repository_model_allowlist = @import("domain/repository_model_allowlist.zig");
const model_request_identity = @import("domain/model_request_identity.zig");
const model_attempt_accounting = @import("domain/model_attempt_accounting.zig");
const llm_provider_operation = @import("domain/llm_provider_operation.zig");
const llm_provider_interface = @import("ports/llm_provider_interface.zig");
const llm_provider_registry_service = @import("application/llm_provider_registry_service.zig");
const provider_requirement_derivation = @import("domain/provider_requirement_derivation.zig");
const workflow_execution = @import("domain/workflow_execution.zig");

test "workflow filesystem traversal uses the inventory reserved-child policy" {
    const source = @embedFile("adapters/filesystem/workflow_authority_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "inventory.isReservedRootChild(entry.path)") != null);
    try expectAbsent(source, "\"features\"");
    try expectAbsent(source, "\"transactions\"");
}

test "atomic execution exposes no transaction logging or stabilization capability" {
    const telemetry = @import("domain/telemetry.zig");
    inline for (.{ "transaction_prepared", "transaction_applying", "transaction_committed", "transaction_rolled_back", "transaction_recovered" }) |name| {
        try std.testing.expect(std.meta.stringToEnum(telemetry.EventType, name) == null);
    }
    try std.testing.expect(!@hasField(telemetry.Field, "transaction_id"));
    try expectAbsent(@import("domain/feature_log_format.zig").event_heading, "transaction_id");
}

/// Whether a Zig source's code, not its comments, names stabilization. ADR 0009 keeps the atomic run free of any
/// stabilizer, so no engine module carries one: the rule the logging runner's and action set's own pins stood for.
fn namesStabilization(allocator: std.mem.Allocator, source: []const u8) !bool {
    const code = try codeOf(allocator, source);
    defer allocator.free(code);
    return std.mem.indexOf(u8, code, "stabiliz") != null;
}

test "no engine module names stabilization" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.endsWith(u8, entry.basename, "_test.zig") or
            std.mem.endsWith(u8, entry.basename, "_test_fixture.zig") or
            std.mem.eql(u8, entry.basename, "runtime_tests.zig") or
            std.mem.startsWith(u8, entry.path, "test_fixtures/")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(source);
        if (try namesStabilization(allocator, source)) {
            std.debug.print("{s} names stabilization\n", .{entry.path});
            return error.StabilizationNamed;
        }
    }
}

test "stabilization is read from code and not from a comment" {
    const allocator = std.testing.allocator;
    try std.testing.expect(!try namesStabilization(allocator, "// a stabilizer would go here\nconst x = 1;\n"));
    try std.testing.expect(!try namesStabilization(allocator, "pub fn run() void {}\n"));
    try std.testing.expect(try namesStabilization(allocator, "const stabilizer = @import(\"transaction_stabilizer.zig\");\n"));
    try std.testing.expect(try namesStabilization(allocator, "pub fn stabilizeFailure() void {}\n"));
}

test "result schema authority is opaque and compilation remains a kernel concern" {
    const schema = @import("domain/model_result_schema.zig");
    try std.testing.expect(@typeInfo(schema.Schema) == .@"opaque");
    const resource = @import("domain/workflow_compilation.zig").CompiledResource;
    const content = @typeInfo(@FieldType(resource, "content")).@"union";
    try std.testing.expect(content.tag_type.? == @import("domain/workflow_operation.zig").ResourceKind);
    try std.testing.expect(@FieldType(@FieldType(resource, "content"), "result_schema") == *const schema.Schema);
    try std.testing.expect(@FieldType(llm_provider_operation.IdentifiedProviderNeutralModelRequest, "response_schema") == *const schema.Schema);
    const compiler = @embedFile("domain/workflow_graph_compilation.zig");
    try std.testing.expect(std.mem.indexOf(u8, compiler, "result_schema_compiler.compile") != null);
    try expectAbsent(compiler, "std.json");
    try expectAbsent(compiler, "/adapters/");
    const schema_domain = @embedFile("domain/model_result_schema.zig");
    try expectAbsent(schema_domain, "parseFromSlice");
    try expectAbsent(schema_domain, "std.Io");
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try expectAbsent(runner, "model_result_schema_compiler");
    try expectAbsent(runner, "parseFromSlice");
}

/// Whether production source spells a result definition (E8): as a string literal in a
/// `DefinitionId` or `.definition` initializer, as a literal or computed positional argument to a
/// packet constructor, as a name built from an enum tag or a format, or as a `definition` constant. A
/// Spec builder selects one through a member of `specification_result_definitions.zig`; generic code
/// only carries or parses a `DefinitionId`. The rule reads text, so it is a guard on these shapes, not
/// a proof that no other spelling exists; the enums are what make a rename a compile error.
fn spellsDefinitionLiteral(source: []const u8) bool {
    for ([_][]const u8{
        "DefinitionId = .{ .bytes = \"",
        ".definition = .{ .bytes = \"",
        "DefinitionId{ .bytes = \"",
        ".{ .bytes = @tagName(",
        "_assignment\"",
        "\"repair_{s}\"",
        "pub const definition = \"",
    }) |needle| {
        if (std.mem.indexOf(u8, source, needle) != null) return true;
    }
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "packet") == null and std.mem.indexOf(u8, line, "create(") == null and std.mem.indexOf(u8, line, "withIntegerChoices") == null) continue;
        for ([_][]const u8{ ", .{ .bytes = \"", ", .{ .bytes = if (", ", .{ .bytes = switch (" }) |needle| {
            if (std.mem.indexOf(u8, line, needle) != null) return true;
        }
    }
    return false;
}

test "production code selects result definitions only through the closed Spec enums" {
    try std.testing.expect(spellsDefinitionLiteral("const d: DefinitionId = .{ .bytes = \"finding\" };"));
    try std.testing.expect(spellsDefinitionLiteral("x(.{ .definition = .{ .bytes = \"claim\" }, .allowed = ids })"));
    try std.testing.expect(spellsDefinitionLiteral("packets.create(a, body, unit, .initial_generation, .{ .bytes = @tagName(input.purpose) });"));
    try std.testing.expect(spellsDefinitionLiteral("return @tagName(v) ++ \"_assignment\";"));
    try std.testing.expect(spellsDefinitionLiteral("const n = try std.fmt.allocPrint(a, \"repair_{s}\", .{@tagName(kind)});"));
    try std.testing.expect(spellsDefinitionLiteral("pub const definition = \"scenario_link\";"));
    try std.testing.expect(spellsDefinitionLiteral("return atomic.packet(a, authorization, base, .{ .bytes = \"claim\" }, origin, options);"));
    try std.testing.expect(spellsDefinitionLiteral("return atomic.packet(a, authorization, base, .{ .bytes = if (x) \"a\" else \"b\" }, origin, options);"));
    try std.testing.expect(!spellsDefinitionLiteral("const d: DefinitionId = .{ .bytes = try arena.dupe(u8, id.bytes) };"));
    try std.testing.expect(!spellsDefinitionLiteral("x(.{ .definition = definitions.Support.finding.id() })"));
    try std.testing.expect(!spellsDefinitionLiteral("const s = .{ .unit_slot_id = .{ .bytes = \"required-information\" } };"));

    // The generic schema, composition, packet, repair and handoff owners and the ports never import
    // the Spec-owned enums: a YAML-authored definition stays a parsed name (ADR 0003, 0016).
    for ([_][]const u8{
        @embedFile("domain/model_result_schema.zig"),
        @embedFile("domain/json_composition.zig"),
        @embedFile("domain/model_input_packet.zig"),
        @embedFile("domain/atomic_repair.zig"),
        @embedFile("domain/model_request_handoff.zig"),
        @embedFile("ports/workflow_operation_registry.zig"),
        @embedFile("ports/model_result_schema_compiler.zig"),
    }) |generic| try expectAbsent(generic, "specification_result_definitions");

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    for ([_][]const u8{ "src/domain", "src/application", "src/actions", "src/composition" }) |root| {
        var directory = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
        defer directory.close(io);
        var walker = try directory.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            // The owner of the closed enums is the one place a definition is built from a tag.
            if (std.mem.eql(u8, entry.basename, "specification_result_definitions.zig")) continue;
            const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
            defer allocator.free(source);
            try std.testing.expect(!spellsDefinitionLiteral(source));
        }
    }
}

test "every action imports only standard domain and port modules" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);

    var walker = try actions.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) {
            continue;
        }

        const source = try entry.dir.readFileAlloc(
            io,
            entry.basename,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        try expectAllowedActionImports(source);
        try expectSingleActionContract(source);
    }
}

test "every orchestrator and coordinator is capability free" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var application = try std.Io.Dir.cwd().openDir(io, "src/application", .{ .iterate = true });
    defer application.close(io);

    var iterator = application.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or
            (!std.mem.endsWith(u8, entry.name, "_orchestrator.zig") and
                !std.mem.endsWith(u8, entry.name, "_coordinator.zig")))
        {
            continue;
        }
        const source = try application.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        try expectNoImportPathHolding(source, &.{ "/actions/", "/adapters/", "/ports/" });
        try expectAbsent(source, "std.Io");
    }
}

test "every application runner is infrastructure independent" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var application = try std.Io.Dir.cwd().openDir(io, "src/application", .{ .iterate = true });
    defer application.close(io);

    var iterator = application.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, "_runner.zig")) continue;
        const source = try application.readFileAlloc(io, entry.name, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        try expectNoImportPathHolding(source, &.{"/adapters/"});
        try expectAbsent(source, "std.Io");
    }
}

test "domain and port dependency direction is enforced repository wide" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    inline for (.{ "src/domain", "src/ports" }) |directory_path| {
        var directory = try std.Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true });
        defer directory.close(io);
        var walker = try directory.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
            defer allocator.free(source);
            // Domain and port modules sit below actions, the application and adapters: they import none of them.
            try expectNoImportPathHolding(source, &.{ "/actions/", "/application/", "/adapters/", "../actions/", "../application/", "../adapters/" });
        }
    }
}

/// Domain modules the generic workflow engine is made of, and the modules only the Spec stages own. Judged by file
/// name, which the package structure fixes (29-package-structure.md); a rule over imports, not over file contents.
const generic_core_prefixes = [_][]const u8{ "pipeline", "workflow_", "model_request_", "model_attempt_", "provider_", "llm_provider_", "operation_error", "model_envelope", "model_payload_schema", "model_result_schema", "strict_json", "telemetry", "feature_log_", "log_" };
const spec_stage_prefixes = [_][]const u8{ "reference_", "specification", "required_authority", "clarification_", "source_omission", "source_preservation", "scenario_", "incomplete_specification", "specify_invocation" };

fn startsWithAny(name: []const u8, prefixes: []const []const u8) bool {
    for (prefixes) |prefix| if (std.mem.startsWith(u8, name, prefix)) return true;
    return false;
}

/// The generic engine's domain modules that import a Spec stage module (ADR 0003: the four workflows are not
/// special cases in the generic engine). Each is a recorded dependency of the engine's closed error set or
/// registry on a stage's contract. A new importer fails the test; a file that drops its last Spec import must leave
/// the list, so the list only shrinks.
const generic_importers_of_spec_stages = [_][]const u8{ "model_request_identity.zig", "operation_error.zig", "workflow_output.zig" };

test "the generic engine's domain modules import no Spec stage module beyond the recorded ones" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var directory = try std.Io.Dir.cwd().openDir(io, "src/domain", .{ .iterate = true });
    defer directory.close(io);
    var found: std.ArrayList([]const u8) = .empty;
    var iterator = directory.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig") or std.mem.endsWith(u8, entry.name, "_test.zig")) continue;
        if (!startsWithAny(entry.name, &generic_core_prefixes) or startsWithAny(entry.name, &spec_stage_prefixes)) continue;
        const source = try directory.readFileAlloc(io, entry.name, allocator, .limited(1024 * 1024));
        for (try importsOf(allocator, source)) |path| {
            if (!startsWithAny(std.fs.path.basename(path), &spec_stage_prefixes)) continue;
            try found.append(allocator, try allocator.dupe(u8, entry.name));
            break;
        }
    }
    std.mem.sort([]const u8, found.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    try std.testing.expectEqual(generic_importers_of_spec_stages.len, found.items.len);
    for (generic_importers_of_spec_stages, found.items) |expected, actual| try std.testing.expectEqualStrings(expected, actual);
}

test "the outcome association holds no Spec result type and the reference core does not import its dependents" {
    // C21: the association names an owner's outcome, never the owner's result type.
    try expectNoImportOfFile(@embedFile("domain/workflow_outcome_association.zig"), &.{ "required_authority.zig", "clarification_refresh.zig" });
    // C25: the reconciliation core does not depend on the repair, omission or support modules built on it.
    for ([_][]const u8{ @embedFile("domain/reference_reconciliation.zig"), @embedFile("domain/reference_reconciliation_diagnostic.zig") }) |core| {
        try expectNoImportOfFile(core, &.{ "reference_reconciliation_repair.zig", "source_omission.zig", "specification_support.zig" });
    }
}

/// C25: the omission modules import in one direction. This pins the direct imports among the six named modules; it
/// does not claim that the domain is acyclic, because a wider cycle group still runs through some of them. A module
/// imports only listed modules of a strictly lower rank.
const omission_import_ranks = [_]struct { file: []const u8, rank: u8 }{
    .{ .file = "source_omission.zig", .rank = 0 },
    .{ .file = "specification_support.zig", .rank = 1 },
    .{ .file = "source_omission_authority.zig", .rank = 2 },
    .{ .file = "reference_extraction_repair.zig", .rank = 3 },
    .{ .file = "reference_reconciliation_repair.zig", .rank = 3 },
    .{ .file = "source_omission_repair.zig", .rank = 4 },
};

fn omissionRank(file: []const u8) ?u8 {
    for (omission_import_ranks) |entry| if (std.mem.eql(u8, entry.file, file)) return entry.rank;
    return null;
}

/// The first listed module that `source`, the text of listed module `file`, imports at its own rank or a higher one.
/// A module outside the list is not constrained.
fn misorderedOmissionImport(allocator: std.mem.Allocator, file: []const u8, source: []const u8) !?[]const u8 {
    const rank = omissionRank(file) orelse return null;
    for (try importsOf(allocator, source)) |path| {
        const imported = std.fs.path.basename(path);
        if ((omissionRank(imported) orelse continue) >= rank) return imported;
    }
    return null;
}

test "the omission modules import in rank order" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    inline for (omission_import_ranks) |entry| {
        if (try misorderedOmissionImport(arena.allocator(), entry.file, @embedFile("domain/" ++ entry.file))) |imported| {
            std.debug.print("{s} imports {s}, which is not of a lower rank\n", .{ entry.file, imported });
            return error.OmissionImportOrder;
        }
    }
}

test "the omission import order accepts lower-ranked and unlisted imports and rejects an equal or higher rank" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // Accepted: lower-ranked and unlisted imports, and names that only a comment or a string spells.
    try std.testing.expectEqual(@as(?[]const u8, null), try misorderedOmissionImport(allocator, "source_omission_authority.zig",
        \\const loss = @import("source_omission.zig");
        \\const support = @import("../domain/specification_support.zig");
        \\const atomic = @import("atomic_repair.zig");
        \\// const repair = @import("source_omission_repair.zig");
        \\const text = "@import(\"source_omission_repair.zig\")";
    ));
    try std.testing.expectEqual(@as(?[]const u8, null), try misorderedOmissionImport(allocator, "unlisted.zig", "const a = @import(\"source_omission_repair.zig\");"));
    // Rejected: a lower rank importing a higher one, siblings of one rank importing each other, and the top rank
    // imported from below.
    const Case = struct { file: []const u8, source: []const u8, offender: []const u8 };
    for ([_]Case{
        .{ .file = "source_omission.zig", .source = "const x = @import(\"reference_reconciliation_repair.zig\");", .offender = "reference_reconciliation_repair.zig" },
        .{ .file = "source_omission.zig", .source = "const x = @import(\"specification_support.zig\");", .offender = "specification_support.zig" },
        .{ .file = "reference_extraction_repair.zig", .source = "const x = @import(\"reference_reconciliation_repair.zig\");", .offender = "reference_reconciliation_repair.zig" },
        .{ .file = "reference_reconciliation_repair.zig", .source = "const x = @import(\"reference_extraction_repair.zig\");", .offender = "reference_extraction_repair.zig" },
        .{ .file = "reference_extraction_repair.zig", .source = "const x = @import(\"source_omission_repair.zig\");", .offender = "source_omission_repair.zig" },
        .{ .file = "source_omission_authority.zig", .source = "const x = @import(\"../domain/source_omission_repair.zig\");", .offender = "source_omission_repair.zig" },
    }) |case| {
        const found = (try misorderedOmissionImport(allocator, case.file, case.source)) orelse return error.TestExpectedEqual;
        try std.testing.expectEqualStrings(case.offender, found);
    }
    // Two modules that import each other cannot both pass: the edge from the lower rank is the one rejected.
    try std.testing.expect((try misorderedOmissionImport(allocator, "source_omission.zig", "const a = @import(\"source_omission_authority.zig\");")) != null);
    try std.testing.expectEqual(@as(?[]const u8, null), try misorderedOmissionImport(allocator, "source_omission_authority.zig", "const a = @import(\"source_omission.zig\");"));
}

test "the checked reconciliation chain is unwound in its owner alone" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var directory = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer directory.close(io);
    var walker = try directory.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or std.mem.endsWith(u8, entry.basename, "_test.zig") or
            std.mem.startsWith(u8, entry.path, "test_fixtures/") or std.mem.eql(u8, entry.basename, "reference_reconciliation.zig") or
            std.mem.eql(u8, entry.basename, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(2 * 1024 * 1024));
        defer allocator.free(source);
        try expectAbsent(source, "checked.prior.prior");
    }
}

test "shared reference support does not import Spec policy" {
    const source = @embedFile("domain/reference_support.zig");
    try expectAbsent(source, "specification.zig");
    try expectAbsent(source, "specification_provenance.zig");
}

const RoutineViolation = enum {
    imports_outside_domain_and_ports,
    uses_io,
    entry_calls_a_port,
    step_takes_the_port_set,
    step_takes_two_ports,
    step_is_erased,
    routine_is_erased,
};

/// ADR 0032's source rules for an engine routine. It imports `std` and domain and port modules only,
/// and uses no `std.Io` and no `anyopaque`. Its entry function `run` only passes its port set's
/// fields on, so a call through one is a port call. Each step takes at most one port, never the port
/// set, and nothing erased. A struct that bundles ports is not detectable in source text.
fn routineViolation(source: []const u8) ?RoutineViolation {
    var rest = source;
    while (std.mem.indexOf(u8, rest, "@import(\"")) |at| {
        const target = rest[at + "@import(\"".len ..];
        const end = std.mem.indexOfScalar(u8, target, '"') orelse return .imports_outside_domain_and_ports;
        const path = target[0..end];
        const allowed = std.mem.eql(u8, path, "std") or std.mem.startsWith(u8, path, "../domain/") or std.mem.startsWith(u8, path, "../ports/");
        if (!allowed) return .imports_outside_domain_and_ports;
        rest = target[end..];
    }
    if (std.mem.indexOf(u8, source, "std.Io") != null) return .uses_io;
    if (std.mem.indexOf(u8, source, "anyopaque") != null) return .routine_is_erased;
    if (std.mem.indexOf(u8, source, "pub fn run(")) |start| {
        const body_end = std.mem.indexOfPos(u8, source, start, "\n}\n") orelse source.len;
        var body = source[start..body_end];
        while (std.mem.indexOf(u8, body, "ports.")) |at| {
            var end = at + "ports.".len;
            while (end < body.len and (std.ascii.isAlphanumeric(body[end]) or body[end] == '_')) end += 1;
            if (end >= body.len or (body[end] != ',' and body[end] != ')')) return .entry_calls_a_port;
            body = body[end..];
        }
    }
    const steps_start = std.mem.indexOf(u8, source, "pub const steps = struct {") orelse return null;
    var cursor = steps_start;
    while (std.mem.indexOfPos(u8, source, cursor, "fn ")) |at| {
        cursor = at + "fn ".len;
        const parameters = parameterText(source, at) orelse continue;
        if (std.mem.indexOf(u8, parameters, "anytype") != null) return .step_is_erased;
        if (hasWord(parameters, "Ports") or hasWord(parameters, "ports")) return .step_takes_the_port_set;
        if (portCount(parameters) > 1) return .step_takes_two_ports;
    }
    return null;
}

/// Whether the file at `path` (relative to `src/`) imports a `*_routine.zig` it may not. ADR 0032
/// names the callers: the composition root for the startup and provider-bootstrap routines, the provider-bootstrap
/// binding for its own routine, the runtime logging lifecycle for the six feature-logging routines, and composition's
/// feature-logging runtime, which builds their ports and calls the failure routine for a failure no lifecycle reports.
/// Tests and test fixtures may import any routine. An action, an orchestrator, a runner, the log service or any other
/// application or composition module never imports a logging routine.
fn importsRoutineIllegally(path: []const u8, source: []const u8) bool {
    if (std.mem.endsWith(u8, path, "_test.zig") or std.mem.startsWith(u8, path, "test_fixtures/")) return false;
    const in_composition = std.mem.startsWith(u8, path, "composition/");
    var rest = source;
    while (std.mem.indexOf(u8, rest, "_routine.zig\")")) |at| {
        var start = at;
        while (start > 0 and (std.ascii.isAlphanumeric(rest[start - 1]) or rest[start - 1] == '_')) start -= 1;
        const routine = rest[start..at];
        const own_binding = std.mem.eql(u8, path, "application/model_provider_bootstrap_binding.zig") and
            std.mem.eql(u8, routine, "model_provider_bootstrap");
        const logging_lifecycle = std.mem.eql(u8, path, "application/feature_log_runtime_lifecycle.zig") and isLoggingRoutine(routine);
        const composition_caller = in_composition and (!isLoggingRoutine(routine) or std.mem.eql(u8, path, "composition/feature_logging_runtime.zig"));
        if (!own_binding and !logging_lifecycle and !composition_caller) return true;
        rest = rest[at + "_routine.zig\")".len ..];
    }
    return false;
}

/// The six feature-logging routines (ADR 0032): the stream's persist, prepare, close and retention, the close of a
/// crashed prior run's open tail, and the failure report.
fn isLoggingRoutine(routine: []const u8) bool {
    for ([_][]const u8{ "feature_log_persist", "feature_log_prepare", "feature_log_close", "feature_log_retention", "feature_log_prior_finalization", "feature_log_failure" }) |name| {
        if (std.mem.eql(u8, routine, name)) return true;
    }
    return false;
}

test "every engine routine obeys ADR 0032's routine rules and is reached only from its named callers" {
    try std.testing.expectEqual(@as(?RoutineViolation, null), routineViolation(@embedFile("application/startup_routine.zig")));
    try std.testing.expectEqual(@as(?RoutineViolation, null), routineViolation(@embedFile("application/model_provider_bootstrap_routine.zig")));
    // Startup acquires no feature transaction lock: it imports no log, lock or transaction module.
    const startup_source = @embedFile("application/startup_routine.zig");
    try expectAbsent(startup_source, "feature_log");
    try expectAbsent(startup_source, "_lock");
    try expectAbsent(startup_source, "transaction.zig");

    const root = @embedFile("composition/root.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(root, "startup_routine.run("));
    try expectAbsent(root, "ChildBindings");

    const services = @embedFile("application/bootstrap_services.zig");
    try expectAbsent(services, "startup_routine");
    try expectAbsent(services, "std.Io");

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var source_root = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer source_root.close(io);
    var walker = try source_root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(source);
        try std.testing.expect(!importsRoutineIllegally(entry.path, source));
        // A routine found here is held to the routine rules; a new one needs no new test.
        if (std.mem.startsWith(u8, entry.path, "application/") and std.mem.endsWith(u8, entry.basename, "_routine.zig")) {
            try std.testing.expectEqual(@as(?RoutineViolation, null), routineViolation(source));
        }
    }
}

test "routine rules reject a routine that imports an action or adapter, uses I/O, reaches a port in its entry, or takes the port set, two ports or an erased parameter" {
    const head = "const std = @import(\"std\");\nconst a = @import(\"../ports/x_port.zig\");\npub fn run(ports: Ports) void {\n    step(ports.one, ports.two);\n}\npub const steps = struct {\n";
    try std.testing.expectEqual(@as(?RoutineViolation, null), routineViolation(head ++ "    pub fn one(port: x_port.Thing) void {}\n};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .imports_outside_domain_and_ports), routineViolation("const a = @import(\"../actions/x/y.zig\");\n" ++ head ++ "};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .imports_outside_domain_and_ports), routineViolation("const a = @import(\"../adapters/x/y.zig\");\n" ++ head ++ "};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .imports_outside_domain_and_ports), routineViolation("const a = @import(\"sibling.zig\");\n" ++ head ++ "};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .uses_io), routineViolation(head ++ "    pub fn io(x: std.Io) void {}\n};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .routine_is_erased), routineViolation(head ++ "    pub fn raw(context: *anyopaque) void {}\n};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .entry_calls_a_port), routineViolation("pub fn run(ports: Ports) void {\n    ports.locator.locate();\n}\npub const steps = struct {\n};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .entry_calls_a_port), routineViolation("pub fn run(ports: Ports) void {\n    const alias = ports.locator;\n}\npub const steps = struct {\n};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .step_takes_the_port_set), routineViolation(head ++ "    pub fn whole(set: Ports) void {}\n};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .step_takes_two_ports), routineViolation(head ++ "    pub fn two(a: x_port.A, b: y_port.B) void {}\n};\n"));
    try std.testing.expectEqual(@as(?RoutineViolation, .step_is_erased), routineViolation(head ++ "    pub fn bag(capabilities: anytype) void {}\n};\n"));
    // Who may import the startup routine: composition and tests, never an action or an orchestrator.
    const import_startup = "const r = @import(\"../application/startup_routine.zig\");\n";
    const import_provider = "const r = @import(\"model_provider_bootstrap_routine.zig\");\n";
    try std.testing.expect(!importsRoutineIllegally("composition/root.zig", import_startup));
    try std.testing.expect(!importsRoutineIllegally("startup_routine_test.zig", import_startup));
    try std.testing.expect(!importsRoutineIllegally("application/model_provider_bootstrap_binding.zig", import_provider));
    try std.testing.expect(!importsRoutineIllegally("application/some_orchestrator.zig", "const x = @import(\"other.zig\");\n"));
    // An action, an orchestrator, a runner, another application module or the provider binding
    // importing the wrong routine is rejected, for either routine.
    try std.testing.expect(importsRoutineIllegally("actions/workflow/some_action.zig", import_startup));
    try std.testing.expect(importsRoutineIllegally("application/some_orchestrator.zig", import_provider));
    try std.testing.expect(importsRoutineIllegally("application/some_runner.zig", import_startup));
    try std.testing.expect(importsRoutineIllegally("application/model_provider_bootstrap_binding.zig", import_startup));
    try std.testing.expect(importsRoutineIllegally("application/workflow_engine_orchestrator.zig", import_provider));
    // Who may import a feature-logging routine: the runtime logging lifecycle, for each of the six, and composition
    // and tests; never an action, an orchestrator, a runner, the log service, or the lifecycle for another routine.
    for ([_][]const u8{ "persist", "prepare", "close", "retention", "prior_finalization", "failure" }) |name| {
        var buffer: [96]u8 = undefined;
        const import_logging = try std.fmt.bufPrint(&buffer, "const r = @import(\"feature_log_{s}_routine.zig\");\n", .{name});
        try std.testing.expect(!importsRoutineIllegally("application/feature_log_runtime_lifecycle.zig", import_logging));
        try std.testing.expect(!importsRoutineIllegally("composition/feature_logging_runtime.zig", import_logging));
        try std.testing.expect(!importsRoutineIllegally("feature_log_persist_routine_test.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("actions/log/some_action.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("application/some_orchestrator.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("application/feature_log_runner.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("application/log_service.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("application/feature_log_persist_routine.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("application/model_provider_bootstrap_binding.zig", import_logging));
        // Composition reaches a logging routine only in its feature-logging runtime: no other composition module does.
        try std.testing.expect(importsRoutineIllegally("composition/root.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("composition/active_feature_log_runtime.zig", import_logging));
        try std.testing.expect(importsRoutineIllegally("composition/native_workflow_operations.zig", import_logging));
    }
    try std.testing.expect(importsRoutineIllegally("application/feature_log_runtime_lifecycle.zig", import_startup));
    try std.testing.expect(importsRoutineIllegally("application/feature_log_runtime_lifecycle.zig", import_provider));
    try std.testing.expect(isLoggingRoutine("feature_log_close"));
    try std.testing.expect(!isLoggingRoutine("startup"));
    try std.testing.expect(!isLoggingRoutine("feature_log_history"));
}

test "public root does not re-export ports or infrastructure adapters" {
    const source = @embedFile("root.zig");
    try expectAbsent(source, "adapters/");
    try expectAbsent(source, "ports/");
    try expectAbsent(source, "bootstrap_roots");
}

test "validated bootstrap registry authority is opaque" {
    switch (@typeInfo(bootstrap_root_registry.BootstrapRootRegistry)) {
        .@"opaque" => {},
        else => return error.RegistryAuthorityMustBeOpaque,
    }
    switch (@typeInfo(bootstrap_root_registry.ConfiguredBaseRootCapability)) {
        .@"opaque" => {},
        else => return error.RootCapabilityMustBeOpaque,
    }
    switch (@typeInfo(bootstrap_root_registry.LLMProviderConfigCapability)) {
        .@"opaque" => {},
        else => return error.ProviderConfigCapabilityMustBeOpaque,
    }

    const service_source = @embedFile("application/bootstrap_root_registry_service.zig");
    try expectAbsent(service_source, "bootstrap_roots");
    try expectAbsent(service_source, "ValidatedConfiguredRoot");

    const inspector_source = @embedFile("adapters/filesystem/bootstrap_root_inspector.zig");
    try expectAbsent(inspector_source, "workspacePathPolicy");

    const init_type = @typeInfo(@TypeOf(
        bootstrap_root_registry_service.BootstrapRootRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);
    try std.testing.expect(init_type.params[0].type.? == *bootstrap_root_registry.Owner);

    const root_domain = @embedFile("domain/bootstrap_root_registry.zig");
    const provider_adapter = @embedFile("adapters/filesystem/llm_provider_config_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, root_domain, "bindLLMProviderConfigSource") != null);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        provider_adapter,
        "bindLLMProviderConfigSource",
    ));
}

test "configuration domain ownership is independent of the JSON parser" {
    const source = @embedFile("domain/config.zig");
    try expectAbsent(source, "std.json.Parsed");
    try expectAbsent(source, "PublicError");
    try expectAbsent(source, "Registry");
}

test "conditional provider bootstrap has one routine and capture authority" {
    // ADR 0032: one routine owns the provider document's capture, decode and validation; it holds the
    // provider-config port alone, imports no adapter and runs only through the composition-built binding.
    const routine = @embedFile("application/model_provider_bootstrap_routine.zig");
    try expectAbsent(routine, "/actions/");
    try expectAbsent(routine, "/adapters/");
    try expectAbsent(routine, "std.Io");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(routine, "locator.locate("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(routine, "exact.read("));

    const services = @embedFile("application/model_provider_bootstrap_services.zig");
    try expectAbsent(services, "std.json");
    try expectAbsent(services, "llm_provider_document");
    try expectAbsent(services, "config.zig");

    const binding = @embedFile("application/model_provider_bootstrap_binding.zig");
    try expectAbsent(binding, "/adapters/");
    try expectAbsent(binding, "std.Io");

    const assembly = @embedFile("composition/model_provider_bootstrap.zig");
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(assembly, "llm_provider_config_source.Adapter.init("),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        countOccurrences(assembly, "routine.run("),
    );

    const workflow_engine = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(workflow_engine, "/adapters/");
    try expectAbsent(workflow_engine, "std.Io");
    const select_index = std.mem.indexOf(u8, workflow_engine, "invokeSelectWorkflow()") orelse {
        return error.MissingWorkflowSelection;
    };
    const prepare_index = std.mem.indexOf(u8, workflow_engine, "invokePrepareWorkflow()") orelse {
        return error.MissingProviderBootstrapInvocation;
    };
    const execute_index = std.mem.indexOf(u8, workflow_engine, "invokeInvocation()") orelse {
        return error.MissingWorkflowExecution;
    };
    try std.testing.expect(select_index < prepare_index);
    try std.testing.expect(prepare_index < execute_index);

    const root = @embedFile("composition/root.zig");
    try expectAbsent(root, "loadLLMProviderConfigInProject");
    try expectAbsent(root, "model_provider_bootstrap_routine.zig");
}

test "provider catalogue and repository allowlist have one immutable authority each" {
    switch (@typeInfo(llm_provider_registry.ValidatedLLMProviderRegistry)) {
        .@"opaque" => {},
        else => return error.LLMProviderRegistryMustBeOpaque,
    }
    switch (@typeInfo(repository_model_allowlist.ValidatedRepositoryModelAllowlist)) {
        .@"opaque" => {},
        else => return error.RepositoryModelAllowlistMustBeOpaque,
    }

    const service = @embedFile("application/llm_provider_registry_service.zig");
    try expectAbsent(service, "std.json");
    try expectAbsent(service, "llm_provider_document");
    try expectAbsent(service, "config.zig");
    const init_type = @typeInfo(@TypeOf(
        llm_provider_registry_service.LLMProviderRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);
    try std.testing.expect(init_type.params[0].type.? == *llm_provider_registry.Owner);

    const registry = @embedFile("domain/llm_provider_registry.zig");
    try expectAbsent(registry, "/adapters/");
    try expectAbsent(registry, "/ports/");
    try expectAbsent(registry, "anyopaque");

    const allowlist = @embedFile("domain/repository_model_allowlist.zig");
    try expectAbsent(allowlist, "ValidatedProviderConfig");
    try expectAbsent(allowlist, "ProviderModelContract");
    try expectAbsent(allowlist, "/adapters/");
    try expectAbsent(allowlist, "/ports/");
}

test "model capability facts have no local size ceilings or operational authority" {
    const contracts = @import("domain/llm_provider_contracts.zig");
    const operation_contract = @import("domain/workflow_operation.zig");
    const provider_operation = @import("domain/llm_provider_operation.zig");
    try std.testing.expect(@FieldType(contracts.ProviderModelContract, "capabilities") == @import("domain/model_capabilities.zig").Capabilities);
    inline for (.{ contracts.ProviderModelContract, @import("domain/model_capabilities.zig").Capabilities, @import("domain/workflow_model.zig").Requirements, @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding, provider_operation.IdentifiedProviderNeutralModelRequest, provider_operation.InvokedProviderOperation, operation_contract.Contract, @import("ports/workflow_operation_registry.zig").Registry }) |T| {
        inline for (.{ "limits", "capacity", "model_capacity", "receive_budgets" }) |field| try std.testing.expect(!@hasField(T, field));
    }
    try std.testing.expect(!@hasDecl(provider_operation, "ProviderReceiveBudgets"));
    try std.testing.expect(!@hasDecl(provider_operation, "CompleteBoundedOwnedUtf8"));
    try std.testing.expect(!@hasField(provider_operation.ProviderFailureCause, "request_limit_exceeded"));
    try std.testing.expect(!@hasField(provider_operation.ProviderFailureCause, "response_limit_exceeded"));
    try std.testing.expect(!@hasDecl(provider_operation, "EffectiveModelLimits"));
    try std.testing.expect(!@hasField(operation_contract.PolicyProfile, "model_capacity"));
    try std.testing.expect(!@hasField(@import("domain/config.zig").ModelsConfig, "model_capacity"));
    inline for (.{
        @embedFile("domain/model_capabilities.zig"),
        @embedFile("domain/workflow_model.zig"),
        @embedFile("actions/provider/resolve_provider_model_binding.zig"),
    }) |source| {
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "std.process");
    }
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("domain/workflow_graph_compilation.zig"), "contract.requiresModelBinding()") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("application/workflow_pipeline_runner.zig"), "step.model orelse") != null);
}

test "request preparation is pure and reuses the sole request validation boundary" {
    // The prepare stage is the only action that builds a request (the detailed assign, validate and
    // build actions are gone with the request lifecycle steps, ADR 0030); its one builder is domain code.
    const prepare = @import("actions/model/prepare_model_request.zig").Action;
    try std.testing.expectEqual(@as(usize, 0), @typeInfo(prepare).@"struct".fields.len);
    try std.testing.expect(prepare.contract.side_effect == .none);
    try std.testing.expect(prepare.contract.runner_accounting == .none);
    const preparation = @import("domain/model_request_preparation.zig");
    try std.testing.expect(@FieldType(preparation.Owned, "request") == *const llm_provider_operation.IdentifiedProviderNeutralModelRequest);
    try std.testing.expect(!@hasDecl(preparation, "StaticCapacityEvidence"));
    inline for (.{
        @embedFile("domain/model_request_preparation.zig"),
    }) |source| {
        try expectAbsent(source, "/actions/");
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.process");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "countInputTokens");
    }
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("domain/model_protocol_retry.zig"), "preparation.build(") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("domain/model_request_handoff.zig"), "preparation.build(") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("domain/model_request_preparation.zig"), "try validateRequest(source, &request)") != null);
    const validator = @embedFile("domain/model_request_preparation.zig");
    try std.testing.expect(std.mem.indexOf(u8, validator, "request.validate()") != null);
    try std.testing.expect(std.mem.indexOf(u8, validator, "request.matchesBinding(") != null);
}

test "provider observation validation exposes sealed candidate evidence without execution capabilities" {
    const validator = @import("actions/model/validate_provider_invocation_observation.zig").Action;
    const validated = @import("domain/provider_invocation_validation.zig");
    try std.testing.expectEqual(@as(usize, 0), @typeInfo(validator).@"struct".fields.len);
    try std.testing.expect(validator.contract.side_effect == .none);
    try std.testing.expect(validator.contract.runner_accounting == .none);
    inline for (.{ validated.Evidence, validated.CompleteCandidate }) |T| {
        switch (@typeInfo(T)) {
            .@"opaque" => {},
            else => return error.ProviderObservationEvidenceMustBeOpaque,
        }
    }
    try std.testing.expect(@FieldType(validated.Result, "complete") == *const validated.CompleteCandidate);
    try std.testing.expect(!@hasDecl(validated.Evidence, "content"));
    try std.testing.expect(!@hasField(validated.Result, "invalid"));
    try std.testing.expect(!@hasField(validated.Result, "cancelled"));
    inline for (.{
        @embedFile("actions/model/validate_provider_invocation_observation.zig"),
        @embedFile("domain/provider_invocation_validation.zig"),
    }) |source| {
        try expectAbsent(source, "/actions/");
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.process");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "std.json");
        try expectAbsent(source, "countInputTokens");
        try expectAbsent(source, "workflow_token_accounting");
        try expectAbsent(source, "logger");
    }
    const source = @embedFile("domain/provider_invocation_validation.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "requireInvoked(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "validateInferenceInvocation(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "ProviderUsage.init(") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "CompleteOwnedUtf8.validate(") != null);
}

test "model decoding consumes sealed complete evidence and exposes only immutable JSON views" {
    // The decoder is domain code reached only through response admission (ADR 0030).
    const decoded = @import("domain/model_envelope.zig");
    const validated = @import("domain/provider_invocation_validation.zig");
    const decode = @typeInfo(@TypeOf(decoded.decode)).@"fn";
    try std.testing.expectEqual(@as(usize, 3), decode.params.len);
    try std.testing.expect(decode.params[1].type.? == *const validated.CompleteCandidate);
    try std.testing.expect(decode.params[2].type.? == ?*?decoded.Diagnostic);
    inline for (.{ decoded.Candidate, decoded.Object, decoded.Array }) |T| {
        switch (@typeInfo(T)) {
            .@"opaque" => {},
            else => return error.DecodedModelViewsMustBeOpaque,
        }
    }
    try std.testing.expect(@FieldType(decoded.Owned, "candidate") == *const decoded.Candidate);
    try std.testing.expect(@FieldType(decoded.Value, "object") == *const decoded.Object);
    try std.testing.expect(@FieldType(decoded.Value, "array") == *const decoded.Array);
    try std.testing.expect(@FieldType(decoded.Value, "string") == []const u8);
    try std.testing.expect(@FieldType(decoded.Value, "number") == []const u8);
    inline for (.{
        @embedFile("domain/model_envelope.zig"),
        @embedFile("domain/strict_json.zig"),
    }) |source| {
        inline for (.{ "/actions/", "/ports/", "/adapters/", "anyopaque", "@constCast", "std.Io", "std.http", "std.process", "workflow_token_accounting", "logger", "validateInferenceInvocation", "requireInvoked", "schema.compile" }) |forbidden| {
            try expectAbsent(source, forbidden);
        }
    }
    // Schema transport and model-result transport reuse the syntax boundary;
    // only their distinct owners choose root shape, schema and number policy.
    inline for (.{ @embedFile("domain/model_envelope.zig"), @embedFile("adapters/parsers/model_result_schemas.zig") }) |source| {
        try std.testing.expect(std.mem.indexOf(u8, source, "json.parse(") != null);
        try expectAbsent(source, "std.json.parseFromSlice");
        try expectAbsent(source, "Scanner.initCompleteInput");
    }
}

test "typed JSON documents are decoded only by the shared strict decoder" {
    // `std.json` reads a string from an array of byte values and makes other conversions a
    // closed document must reject. A decode into `std.json.Value` is a dynamic tree.
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    inline for (.{ "src/actions", "src/adapters", "src/application", "src/composition" }) |directory_path| {
        var directory = try std.Io.Dir.cwd().openDir(io, directory_path, .{ .iterate = true });
        defer directory.close(io);
        var walker = try directory.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
            defer allocator.free(source);
            var lines = std.mem.splitScalar(u8, source, '\n');
            while (lines.next()) |text| {
                if (std.mem.indexOf(u8, text, "std.json.Value") != null) continue;
                inline for (.{ "parseFromSlice", "parseFromValue", "parseFromTokenSource", "innerParse(" }) |decode| {
                    if (std.mem.indexOf(u8, text, decode) != null) {
                        std.debug.print("typed JSON decode outside strict_json: {s}/{s}\n", .{ directory_path, entry.path });
                        return error.TypedJsonDecodedOutsideStrictJson;
                    }
                }
            }
        }
    }
}

test "payload validation uses only the retained schema and produces allocation-free candidate evidence" {
    const validation = @import("domain/model_payload_schema.zig");
    const envelope = @import("domain/model_envelope.zig");
    const validate = @typeInfo(@TypeOf(validation.validate)).@"fn";
    try std.testing.expectEqual(@as(usize, 1), validate.params.len);
    try std.testing.expect(validate.params[0].type.? == *const envelope.Candidate);
    try std.testing.expect(validate.return_type.? == validation.Result);
    try std.testing.expect(@FieldType(validation.Result, "valid") == *const validation.Evidence);
    try std.testing.expect(@FieldType(validation.Result, "invalid") == validation.Diagnostic);
    try std.testing.expect(@FieldType(validation.Diagnostic, "reason") == validation.Rejection);
    try std.testing.expect(@FieldType(validation.Diagnostic, "expected") == *const @import("domain/model_result_schema.zig").Node);
    try std.testing.expectEqual(@as(usize, 2), @typeInfo(validation.Result).@"union".fields.len);
    switch (@typeInfo(validation.Evidence)) {
        .@"opaque" => {},
        else => return error.PayloadSchemaEvidenceMustBeOpaque,
    }
    try std.testing.expect(@typeInfo(@TypeOf(validation.Evidence.candidate)).@"fn".return_type.? == *const envelope.Candidate);
    inline for (.{@embedFile("domain/model_payload_schema.zig")}) |source| {
        inline for (.{ "/actions/", "/ports/", "/adapters/", "anyopaque", "@constCast", "std.Io", "std.http", "std.process", "std.json", "parseFloat", "Allocator", "workflow_token_accounting", "logger", "validateInferenceInvocation", "requireInvoked", "schema.compile" }) |forbidden| {
            try expectAbsent(source, forbidden);
        }
    }
    const source = @embedFile("domain/model_payload_schema.zig");
    try std.testing.expect(std.mem.indexOf(u8, source, "candidate.association().request().response_schema") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "schema.findProperty(") != null);
}

test "consolidated response admission remains a pure action over existing response owners" {
    const action = @import("actions/model/admit_model_response.zig").Action;
    try std.testing.expectEqual(@as(usize, 0), @typeInfo(action).@"struct".fields.len);
    try std.testing.expect(action.contract.side_effect == .none);
    try std.testing.expect(action.contract.runner_accounting == .none);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{ .model_envelope_result, .model_payload_schema_result }, action.contract.produces);
    const source = @embedFile("actions/model/admit_model_response.zig");
    inline for (.{ "/actions/", "/application/", "/ports/", "/adapters/", "std.Io", "std.http", "std.process", "workflow_token_accounting", "logger", "schema.compile" }) |forbidden| try expectAbsent(source, forbidden);
}

test "model-binding requirement is immutable data not a provider-call capability" {
    const compilation = @import("domain/workflow_compilation.zig");
    const operation = @import("domain/workflow_operation.zig");
    const registry = @import("ports/workflow_operation_registry.zig");
    try std.testing.expect(@FieldType(compilation.CompiledStep, "model") == ?@import("domain/workflow_model.zig").Requirements);
    try std.testing.expect(@FieldType(@import("domain/workflow_model.zig").Requirements, "slot") == @import("domain/llm_provider_identity.zig").ModelSlotId);
    try std.testing.expect(!@hasField(@import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding, "response_mode"));
    try std.testing.expect(@hasDecl(operation.Contract, "requiresModelBinding"));
    try std.testing.expect(!@hasField(operation.Contract, "model_capacity"));
    try std.testing.expect(@FieldType(registry.StepInput, "model_binding") == ?*const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding);
    try std.testing.expect(!@hasField(registry.StepInput, "provider"));
    // The runner is the only producer of log facts: no action channel carries one in a node delta, and a step knows
    // only its workflow's shortcode.
    try std.testing.expect(!@hasField(registry.StepInput, "log"));
    try std.testing.expect(!@hasDecl(@import("domain/pipeline.zig"), "WorkflowLog"));
    try std.testing.expect(!@hasField(@import("domain/pipeline.zig").NodeDelta, "telemetry_facts"));
    // One cancellation source: the status is active or cancelled, and no run-level deadline status exists. Request
    // deadlines are the lease's and the exchange timer's.
    try std.testing.expectEqual(@as(usize, 2), @typeInfo(@import("domain/pipeline.zig").RuntimeStatus).@"enum".fields.len);
    // The composition entry installs the operator interrupt around the run, and restores the prior action after it.
    const root_source = @embedFile("composition/root.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(root_source, "Interrupt.install()"));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(root_source, "interrupt.restore()"));
    const derive = @embedFile("domain/provider_requirement_derivation.zig");
    try std.testing.expect(std.mem.indexOf(u8, derive, "step.model != null") != null);
    try expectAbsent(derive, "step.parameters");
    try expectAbsent(@embedFile("actions/provider/resolve_provider_model_binding.zig"), "LLMProviderInterface");
}

test "model request identity has one opaque ledger and runner applied mutation boundary" {
    switch (@typeInfo(model_request_identity.ModelRequestIdentityLedger)) {
        .@"opaque" => {},
        else => return error.ModelRequestIdentityLedgerMustBeOpaque,
    }
    switch (@typeInfo(model_request_identity.ModelRequestBindingEvidence)) {
        .@"opaque" => {},
        else => return error.ModelRequestBindingEvidenceMustBeOpaque,
    }

    const builder = @embedFile("actions/model/build_initial_model_request_identity_ledger.zig");
    // The prepare action is the only action that assigns a request; the detailed assign and
    // validate actions are gone with the request lifecycle steps (ADR 0030).
    const assigner = @embedFile("actions/model/prepare_model_request.zig");
    const lifecycle = @embedFile("actions/model/advance_model_request_lifecycle.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        builder,
        ".produces = &.{.model_request_identity_ledger}",
    ));
    try expectAbsent(builder, ".replaces = &.{.model_request_identity_ledger}");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        assigner,
        ".replaces = &.{.model_request_identity_ledger}",
    ));
    try expectAbsent(assigner, ".produces = &.{.model_request_identity_ledger}");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(
        lifecycle,
        ".replaces = &.{.model_request_identity_ledger}",
    ));
    try expectAbsent(lifecycle, "/ports/");
    try expectAbsent(lifecycle, "/adapters/");

    const runner = @embedFile("model_request_identity_runner_test_fixture.zig");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "/ports/");
    try expectAbsent(runner, "std.Io");
    try std.testing.expectEqual(@as(usize, 3), countOccurrences(runner, "envelope.apply("));
}

test "workflow request handoff retains authority without introducing operations or capabilities" {
    const handoff = @import("domain/model_request_handoff.zig");
    try std.testing.expect(@typeInfo(handoff.Request) == .@"opaque");
    try std.testing.expect(!@hasField(model_request_identity.StageRunEpochId, "bytes"));
    try std.testing.expect(@hasField(model_request_identity.ImmutableUnitOwnerId, "workflow_step"));
    try std.testing.expect(!@hasField(model_request_identity.ContentUnitOwnerId, "workflow_step"));
    const source = @embedFile("domain/model_request_handoff.zig");
    inline for (.{ "/application/", "/actions/", "/ports/", "/adapters/", "anyopaque", "@constCast", "std.Io", "std.http", "std.process" }) |forbidden| try expectAbsent(source, forbidden);
    const preparation = @embedFile("application/model_request_workflow.zig");
    inline for (.{ "LLMProviderInterface", "invoke_model", "count_input_tokens", "authorization_lease", "retry_limit", "std.Io", "/adapters/" }) |forbidden| try expectAbsent(preparation, forbidden);
    const assembly = @embedFile("composition/model_request_operations.zig");
    inline for (.{ "requests.Initialize", "requests.Prepare" }) |name| try std.testing.expect(std.mem.indexOf(u8, assembly, name) != null);
    inline for (.{ "requests.Assign", "requests.Validate", "requests.Build" }) |name| try expectAbsent(assembly, name);
    const consolidated = @embedFile("actions/model/prepare_model_request.zig");
    inline for (.{ "/actions/", "/application/", "/ports/", "/adapters/", "std.Io" }) |forbidden| try expectAbsent(consolidated, forbidden);
    try std.testing.expect(std.mem.indexOf(u8, consolidated, "handoff.prepare(") != null);
    try expectAbsent(assembly, "operations.Registry");
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("composition/native_workflow_operations.zig"), "self.model_requests.entries") != null);
}

test "the request-model orchestrator only follows stage outcomes, and only the runner runs a stage" {
    const orchestrator = @embedFile("application/model_request_orchestrator.zig");
    // It holds no count or bound (ADR 0030: the runner owns every retry count): no attempt tally and
    // no allowance, and its transition table is domain data it reads.
    inline for (.{ "/actions/", "/adapters/", "/ports/", "std.Io", "anyopaque", "model_request_workflow", "workflow_pipeline_runner", "envelope", "accounting", "retry_limit", "provider", "attempts", "allowance" }) |forbidden| try expectAbsent(orchestrator, forbidden);
    try std.testing.expect(std.mem.indexOf(u8, orchestrator, "kernel.next(") != null);
    const children = @embedFile("application/model_request_child_bindings.zig");
    inline for (.{ "/actions/", "/adapters/", "/ports/", "std.Io", "workflow_pipeline_runner", "allowance" }) |forbidden| try expectAbsent(children, forbidden);
    // The stage list is domain data: a port and the compiler name it, and a workflow cannot.
    inline for (.{ "/application/", "/actions/", "/adapters/", "std.Io" }) |forbidden| {
        try expectAbsent(@embedFile("domain/model_request_stage.zig"), forbidden);
        try expectAbsent(@embedFile("domain/model_request_kernel.zig"), forbidden);
    }
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    // One orchestrator run per kernel step, and stages execute only through the one step body
    // that applies every check, delta and accounting transition (`executeBound`).
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, "request_orchestrator.run("));
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(runner, "entry.invoke("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, "fn executeBound("));
    // A stage takes no execution of its own: the step counts once toward the ceiling.
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(runner, "self.remaining_step_executions -= 1;"));
    // The runner owns the attempt allowance, in one admission every stage entry passes, and the
    // stage's own checks live only in the one step body.
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, "context.admission.admit("));
    try expectAbsent(runner, "matchesContract(registered.contract");
    // Every consumer that asks "does this step begin one request" asks the one owner.
    inline for (.{ "domain/reference_extraction_contract.zig", "domain/workflow_json_composition.zig" }) |path| {
        const consumer = @embedFile(path);
        try expectAbsent(consumer, "assignsRequest(");
        try std.testing.expect(std.mem.indexOf(u8, consumer, "startsRequest(") != null);
    }
    // Only the composition root builds the kernel entry, and its capabilities derive from the stages.
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("composition/model_request_operations.zig"), "bindRequestKernel(&stage_types)") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("ports/workflow_operation_registry.zig"), "fn validRequestKernel(") != null);
}

test "the contract-variant mechanism has no operation-specific branch and one owner for each rule" {
    const mechanism = .{
        "domain/workflow_operation.zig",
        "domain/workflow_compilation.zig",
        "domain/workflow_graph_compilation.zig",
        "domain/workflow_graph_validation.zig",
        "domain/workflow_registry.zig",
        "ports/workflow_operation_registry.zig",
        "application/workflow_pipeline_runner.zig",
    };
    // The selector is data: a contract names its parameter, and nothing in the mechanism names a
    // selector value, an owner or an operation (ADR 0030, ADR 0033's 12 owners).
    const names = [_][]const u8{
        "\"owner\"",
        "\"reference-text\"",
        "\"reference-extraction\"",
        "\"reference-summary\"",
        "\"reference-dispositions\"",
        "\"reference-signals\"",
        "\"reference-conflicts\"",
        "\"reference-reconciliation\"",
        "\"source-omission\"",
        "\"source-omission-extraction\"",
        "\"source-omission-reconciliation\"",
        "\"specification-unit\"",
        "\"specification-support\"",
        // The kernel operation: the ceiling and the runner key on the stage marker, never on the name.
        "\"request-model\"",
        "authorize-repair",
        "merge-repair",
        "parse-repair",
        "build-repair-input",
    };
    inline for (mechanism) |path| {
        const source = @embedFile(path);
        inline for (names) |name| try expectAbsent(source, name);
    }
    // One lookup picks a variant: the contract's own `resolve`, reached through `selectedContract`
    // (compiled parameters) or `selectDeclared` (declared ones); no consumer matches a selector value.
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("domain/workflow_operation.zig"), "pub fn resolve("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("domain/workflow_compilation.zig"), "pub fn selectedContract("));
    // The compiler selects first and checks everything else against the selected contract alone.
    const compiler = @embedFile("domain/workflow_graph_compilation.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(compiler, "selectDeclared(entry.contract, declared.parameters)"));
    try expectAbsent(compiler, "compileParameters(allocator, entry.contract");
    try expectAbsent(compiler, "validateDeclaredOutcomes(entry.contract");
    try expectAbsent(compiler, "resolveRetryAuthority(item, declared.id, entry.contract");
    // The runner runs a step against its own variant, never the registered contract as a whole.
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, "entry.contractFor(step.parameters)"));
    try expectAbsent(runner, ".contract = entry.contract, .binding = entry.binding");
    // Graph validation and registry publication recheck a compiled step against its variant through
    // the one registry function, and the startup routine gives both the operation registry.
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("domain/workflow_graph_validation.zig"), "operations.stepsMatchVariants("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("domain/workflow_registry.zig"), "operations.stepsMatchVariants("));
    // Only a variant-aware composition function registers such an operation, and it takes a shell.
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("composition/native_workflow_operations.zig"), "pub fn variantEntry(") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("composition/native_workflow_operations.zig"), "isShell()") != null);
}

test "compiled-step checks have one owner: graph validation, never registry publication" {
    const graph = @embedFile("domain/workflow_graph_validation.zig");
    try std.testing.expect(std.mem.indexOf(u8, graph, "for (step.request_stages) |stage| validateStep(graph, stage.step) catch return reject(evidence, .step_contract, graph, step.id.bytes);") != null);
    // Publication imports no module whose only use to it would be a step check, and calls none of
    // the step checks the modules it does import also hold.
    const publication = @embedFile("domain/workflow_registry.zig");
    try expectImportsOnly(publication, &.{
        "std",                                   "pipeline.zig",            "pipeline_data.zig",
        "workflow.zig",                          "workflow_definition.zig", "workflow_compilation.zig",
        "workflow_inventory.zig",                "workflow_subgraphs.zig",  "workflow_source.zig",
        "workflow_model.zig",                    "workflow_gate.zig",       "../ports/workflow_operation_registry.zig",
        "../ports/workflow_contract_source.zig",
    });
    inline for (.{ "validProjection(", "publicationTerminates(", "calculateExecutionLimit(", ".parse(", "isValid()" }) |check| {
        try expectAbsent(publication, check);
    }
}

test "YAML invocation owns one response and uses runner accounting without hidden response work" {
    const native = @import("application/model_invocation_workflow.zig");
    try std.testing.expect(@typeInfo(@import("domain/model_invocation_result.zig").Result) == .@"opaque");
    try std.testing.expect(native.schema.maximum_bytes == null);
    const capabilities = comptime @import("application/workflow_operation_binding.zig").inspect(native.Invoke, &.{});
    try std.testing.expect(capabilities.valid and capabilities.model_provider and !capabilities.provider_authorization);
    try std.testing.expect(native.Invoke.contract.side_effect == .model_call);
    try std.testing.expectEqual(@as(usize, 0), native.Invoke.contract.parameters.len);
    const source = @embedFile("application/model_invocation_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "action.execute("));
    inline for (.{ "/adapters/", "std.Io", "std.json", "countInputTokens", "reconcile", "decode", "retry_limit", "while (" }) |forbidden| try expectAbsent(source, forbidden);
    const accounting_source = @embedFile("application/workflow_model_invocation.zig");
    try std.testing.expect(std.mem.indexOf(u8, accounting_source, "validation.validateUsage(") != null);
    try std.testing.expect(std.mem.indexOf(u8, accounting_source, "accounting.reconcile(") != null);
    inline for (.{ "/adapters/", "std.Io", "std.json", "LLMProviderInterface", "countInputTokens", "decode" }) |forbidden| try expectAbsent(accounting_source, forbidden);
}

test "inference action forwards one provider call without hidden work" {
    const action = @import("actions/model/invoke_model.zig").Action;
    try std.testing.expectEqual(@as(usize, 1), @typeInfo(action).@"struct".fields.len);
    try std.testing.expect(@FieldType(action, "provider") == llm_provider_interface.LLMProviderInterface);
    try std.testing.expect(action.contract.side_effect == .model_call);
    try std.testing.expect(action.contract.runner_accounting == .none);
    const signature = @typeInfo(@TypeOf(action.execute)).@"fn";
    try std.testing.expectEqual(@as(usize, 5), signature.params.len);
    try std.testing.expect(signature.params[1].type.? == *const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding);
    try std.testing.expect(signature.params[2].type.? == *const llm_provider_operation.IdentifiedProviderNeutralModelRequest);
    try std.testing.expect(signature.params[3].type.? == *const llm_provider_operation.ValidatedProviderAuthorizationLeaseRef);
    try std.testing.expect(signature.params[4].type.? == *const llm_provider_operation.InvokedProviderOperation);
    try std.testing.expect(signature.return_type.? == llm_provider_interface.Error!llm_provider_operation.ProviderInvocationObservation);
    const capabilities = comptime @import("application/workflow_operation_binding.zig").inspect(action, &.{});
    try std.testing.expect(capabilities.valid and capabilities.model_provider);
    try std.testing.expect(!capabilities.toolchain_read and !capabilities.toolchain_parser and !capabilities.reference_read);
    const source = @embedFile("actions/model/invoke_model.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.provider."));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.provider.invoke("));
    inline for (.{ "/actions/", "/application/", "/adapters/", "anyopaque", "@constCast", "std.Io", "std.http", "std.process", "std.json", "while (", "for (", "catch", ".deinit(", "validateInferenceInvocation", "validateCountInvocation", "requireInvoked", "schema", "workflow_token_accounting", "logger" }) |forbidden| {
        try expectAbsent(source, forbidden);
    }
    // This increment provides an action, not a production provider activation.
    try expectAbsent(@embedFile("composition/native_workflow_operations.zig"), "invoke_model.zig");
}

test "YAML observation validation reuses the pure validator and retains immutable inputs" {
    const native = @import("application/provider_observation_workflow.zig");
    try std.testing.expect(@typeInfo(native.Result) == .@"opaque");
    try std.testing.expect(@FieldType(native.Outcome, "validated") == *const @import("domain/provider_invocation_validation.zig").Evidence);
    try std.testing.expect(native.schema.maximum_bytes == null);
    const capabilities = comptime @import("application/workflow_operation_binding.zig").inspect(native.Validate, &.{});
    try std.testing.expect(capabilities.valid and !capabilities.model_provider and !capabilities.provider_authorization);
    try std.testing.expect(native.Validate.contract.side_effect == .none);
    try std.testing.expect(native.Validate.contract.runner_accounting == .none);
    try std.testing.expectEqual(@as(usize, 0), native.Validate.contract.parameters.len);
    const source = @embedFile("application/provider_observation_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.action.execute("));
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(source, "values.retain("));
    inline for (.{ "/adapters/", "std.Io", "std.json", "countInputTokens", "reconcile", "validation.validate(", "utf8Validate", "LLMProviderInterface", "retry_limit", "while (" }) |forbidden| try expectAbsent(source, forbidden);
}

test "response admission decodes and validates in one binding without schema or accounting work of its own" {
    const envelope_owner = @import("application/model_envelope_workflow.zig");
    try std.testing.expect(@typeInfo(envelope_owner.Result) == .@"opaque");
    try std.testing.expect(@FieldType(envelope_owner.Outcome, "decoded") == *const @import("domain/model_envelope.zig").Candidate);
    try std.testing.expect(@FieldType(envelope_owner.Outcome, "not_decoded") == *const @import("application/provider_observation_workflow.zig").Result);
    try std.testing.expect(@FieldType(envelope_owner.Rejection, "diagnostic") == @import("domain/model_envelope.zig").Diagnostic);
    try std.testing.expect(envelope_owner.schema.maximum_bytes == null);
    // No separate decode binding exists: the one admission binding owns both results.
    try std.testing.expect(!@hasDecl(envelope_owner, "Decode"));
    const envelope_source = @embedFile("application/model_envelope_workflow.zig");
    inline for (.{ "/adapters/", "std.Io", "std.json", "strict_json", "countInputTokens", "reconcile", "validateUsage", "validateInferenceInvocation", "utf8Validate", "LLMProviderInterface", "model_payload_schema", "retry_limit", "while (" }) |forbidden| try expectAbsent(envelope_source, forbidden);
    const native = @import("application/model_payload_schema_workflow.zig");
    try std.testing.expect(@typeInfo(native.Result) == .@"opaque");
    try std.testing.expect(@FieldType(native.Outcome, "valid") == *const @import("domain/model_payload_schema.zig").Evidence);
    try std.testing.expect(@FieldType(native.Outcome, "not_validated") == *const @import("application/model_envelope_workflow.zig").Result);
    try std.testing.expect(native.schema.maximum_bytes == null);
    try std.testing.expect(!@hasDecl(native, "Validate"));
    inline for (.{native.Admit}) |Binding| {
        const capabilities = comptime @import("application/workflow_operation_binding.zig").inspect(Binding, &.{});
        try std.testing.expect(capabilities.valid and !capabilities.model_provider and !capabilities.provider_authorization);
        try std.testing.expect(Binding.contract.side_effect == .none);
        try std.testing.expect(Binding.contract.runner_accounting == .none);
        try std.testing.expectEqual(@as(usize, 0), Binding.contract.parameters.len);
    }
    const source = @embedFile("application/model_payload_schema_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.action.execute("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "values.retain("));
    inline for (.{ "/adapters/", "std.Io", "std.json", "strict_json", "countInputTokens", "reconcile", "validateUsage", "validateInferenceInvocation", "validation.validate(", "decoding.decode(", "utf8Validate", "LLMProviderInterface", "retry_limit", "while (" }) |forbidden| try expectAbsent(source, forbidden);
}

test "YAML request lifecycle uses its existing action and publishes only a validated ledger successor" {
    const native = @import("application/model_request_lifecycle_workflow.zig");
    const metadata = @import("application/workflow_operation_binding.zig").inspect(native.Advance, &.{});
    try std.testing.expect(metadata.valid and !metadata.model_provider and !metadata.provider_authorization);
    try std.testing.expectEqual(@as(usize, 0), native.Advance.contract.produces.len);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.model_request_identity_ledger}, native.Advance.contract.replaces);
    const source = @embedFile("application/model_request_lifecycle_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.action.execute("));
    inline for (.{ "createLifecycleSuccessor", "invoke_model", "authorization_lease", "retry-limit", "std.Io", "/adapters/" }) |forbidden| try expectAbsent(source, forbidden);
    const validation = @embedFile("application/workflow_model_request_lifecycle.zig");
    inline for (.{ "/actions/", "/adapters/", "createLifecycleSuccessor", "envelope.apply", "std.Io" }) |forbidden| try expectAbsent(validation, forbidden);
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "authorization_binding.requirePrepared(").? < std.mem.indexOf(u8, runner, "var candidate = entry.invoke(.{ .step").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "request_lifecycle_binding.validateReplacement(").? < std.mem.indexOf(u8, runner, "self.envelope.applyOccurrence(").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "self.envelope.applyOccurrence(").? < std.mem.indexOf(u8, runner, "self.model_accounting.?.replaceRequests(").?);
}

test "YAML request closure reuses lifecycle validation without new authority or effects" {
    inline for (.{ @import("application/model_request_completion_workflow.zig").Complete, @import("application/model_request_termination_workflow.zig").Terminate }, .{ "application/model_request_completion_workflow.zig", "application/model_request_termination_workflow.zig" }) |Native, path| {
        const metadata = @import("application/workflow_operation_binding.zig").inspect(Native, &.{});
        try std.testing.expect(metadata.valid and !metadata.model_provider and !metadata.provider_authorization);
        try std.testing.expectEqual(.none, Native.contract.runner_accounting);
        try std.testing.expectEqual(@as(usize, 0), Native.contract.parameters.len);
        try std.testing.expectEqual(@as(usize, 0), Native.contract.produces.len);
        try std.testing.expectEqual(@as(usize, 0), Native.contract.invalidates.len);
        try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.model_request_identity_ledger}, Native.contract.replaces);
        const source = @embedFile(path);
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.action.execute("));
        inline for (.{ "createLifecycleSuccessor", "reconcile", "lease", "std.json", "/adapters/", "envelope.apply", "retry-limit" }) |forbidden| try expectAbsent(source, forbidden);
    }
    const validation = @embedFile("application/workflow_model_request_lifecycle.zig");
    try std.testing.expect(std.mem.indexOf(u8, validation, ".validateRequestClosure(") != null);
    try std.testing.expect(std.mem.indexOf(u8, validation, "outcome != facts.outcome") != null);
}

test "provider operation boundary has one capability-limited interface" {
    switch (@typeInfo(llm_provider_interface.Context)) {
        .@"opaque" => {},
        else => return error.LLMProviderContextMustBeOpaque,
    }
    try std.testing.expectEqual(
        @as(usize, 1),
        @typeInfo(llm_provider_interface.LLMProviderInterface.VTable).@"struct".fields.len,
    );

    const port = @embedFile("ports/llm_provider_interface.zig");
    try expectAbsent(port, "anyopaque");
    try expectAbsent(port, "/adapters/");
    try expectAbsent(port, "std.Io");
    try expectAbsent(port, "ExactInputTokenCountEvidence");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(port, "pub const LLMProviderInterface"));

    const contract = @embedFile("domain/llm_provider_operation.zig");
    try expectAbsent(contract, "/adapters/");
    try expectAbsent(contract, "/ports/");
    try expectAbsent(contract, "std.Io");

    const fake = @embedFile("adapters/provider/fake_llm_provider.zig");
    try expectAbsent(fake, "std.Io");
    try expectAbsent(fake, "filesystem");
    try expectAbsent(fake, "process");
    try expectAbsent(fake, "environment");
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "fake_llm_provider");
}

test "YAML provider invocation proposes one lifecycle change without receiving a lease capability" {
    const native = @import("application/provider_operation_lifecycle_workflow.zig");
    const metadata = @import("application/workflow_operation_binding.zig").inspect(native.Advance, &.{});
    try std.testing.expect(metadata.valid and !metadata.model_provider and !metadata.provider_authorization);
    try std.testing.expectEqual(.advance_provider_operation, native.Advance.contract.runner_accounting);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.invoked_provider_operation}, native.Advance.contract.produces);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.assigned_provider_operation}, native.Advance.contract.invalidates);
    try std.testing.expect(@typeInfo(@import("domain/provider_operation_lifecycle.zig").InvokedOperation) == .@"opaque");
    const source = @embedFile("application/provider_operation_lifecycle_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.action.execute("));
    inline for (.{ "lifecycle.apply(", "authorization_leases", "LLMProviderInterface", "timeout-ms", "retry-limit", "std.Io", "/adapters/", "reconcile(" }) |forbidden| try expectAbsent(source, forbidden);
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "authorization_binding.requirePrepared(").? < std.mem.indexOf(u8, runner, "var candidate = entry.invoke(.{ .step").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "pending = state.prepareInvocation(").? < std.mem.indexOf(u8, runner, "self.envelope.applyOccurrence(").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "self.envelope.applyOccurrence(").? < std.mem.indexOf(u8, runner, "self.model_accounting.?.commit(").?);
    const state = @embedFile("application/workflow_model_accounting.zig");
    try std.testing.expect(std.mem.indexOf(u8, state, "authorization_leases.deinit()").? < std.mem.indexOf(u8, state, "lifecycle.deinitOwner(").?);
    inline for (.{ "actions/", "adapters/", "LLMProviderInterface", "std.Io" }) |forbidden| try expectAbsent(state, forbidden);
}

test "YAML provider completion uses one lifecycle action and runner-published terminal evidence" {
    const native = @import("application/provider_operation_completion_workflow.zig");
    const metadata = @import("application/workflow_operation_binding.zig").inspect(native.Complete, &.{});
    try std.testing.expect(metadata.valid and !metadata.model_provider and !metadata.provider_authorization);
    try std.testing.expectEqual(.advance_provider_operation, native.Complete.contract.runner_accounting);
    try std.testing.expectEqual(@as(usize, 0), native.Complete.contract.parameters.len);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.terminal_provider_operation}, native.Complete.contract.produces);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.invoked_provider_operation}, native.Complete.contract.invalidates);
    try std.testing.expect(@typeInfo(@import("domain/provider_operation_lifecycle.zig").TerminalOperation) == .@"opaque");
    const source = @embedFile("application/provider_operation_completion_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.action.execute("));
    inline for (.{ "lifecycle.apply(", "authorization_leases", "LLMProviderInterface", "timeout-ms", "retry-limit", "std.Io", "/adapters/", "reconcile(", "validateUsage", "std.json", "values.adopt(" }) |forbidden| try expectAbsent(source, forbidden);
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "pending = state.prepareCompletion(").? < std.mem.indexOf(u8, runner, "self.envelope.applyOccurrence(").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "self.envelope.applyOccurrence(").? < std.mem.indexOf(u8, runner, "self.model_accounting.?.commit(").?);
}

test "YAML pre-call termination reuses one lifecycle action and canonical terminal publication" {
    const native = @import("application/provider_operation_termination_workflow.zig");
    const metadata = @import("application/workflow_operation_binding.zig").inspect(native.Terminate, &.{});
    try std.testing.expect(metadata.valid and !metadata.model_provider and !metadata.provider_authorization);
    try std.testing.expectEqual(.advance_provider_operation, native.Terminate.contract.runner_accounting);
    try std.testing.expectEqual(@as(usize, 0), native.Terminate.contract.parameters.len);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.terminal_provider_operation}, native.Terminate.contract.produces);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.assigned_provider_operation}, native.Terminate.contract.invalidates);
    try std.testing.expectEqualSlices(@import("domain/workflow.zig").OutcomeTag, &.{ .failed, .cancelled }, native.Terminate.contract.outcomes);
    const source = @embedFile("application/provider_operation_termination_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "self.action.execute("));
    try std.testing.expect(std.mem.indexOf(u8, source, ".validateFailure(") != null);
    inline for (.{ "lifecycle.apply(", "authorization_leases", "LLMProviderInterface", "timeout-ms", "retry-limit", "std.Io", "/adapters/", "reconcile(", "values.adopt(", "envelope.apply(" }) |forbidden| try expectAbsent(source, forbidden);
    const state = @embedFile("application/workflow_model_accounting.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(state, "self.retainOperation(lifecycle.TerminalOperation,"));
}

test "provider authorization exposes only non-operational references and narrow single-use ports" {
    const preparation = @import("ports/provider_operation_authorization.zig");
    const lease = @import("ports/provider_authorization_lease.zig");
    const reference = @import("domain/execution_reference.zig");
    const ref_fields = @typeInfo(llm_provider_operation.ValidatedProviderAuthorizationLeaseRef).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 1), ref_fields.len);
    try std.testing.expect(ref_fields[0].type == reference.Ref);
    try std.testing.expect(!@hasDecl(llm_provider_operation.ValidatedProviderAuthorizationLeaseRef, "init"));
    try std.testing.expect(!@hasDecl(llm_provider_operation.ValidatedProviderAuthorizationLeaseRef, "matches"));
    try std.testing.expect(!@hasField(preparation.Slot, "publish_fn"));
    try std.testing.expect(!@hasField(preparation.Slot, "consume_fn"));
    try std.testing.expect(@hasField(preparation.AllocatedSlot, "publish_fn"));
    try std.testing.expect(!@hasField(lease.Port, "deposit_fn"));
    const native_binding = @import("application/workflow_operation_binding.zig");
    const capability = native_binding.inspect(preparation.Port, &.{});
    try std.testing.expect(capability.valid and capability.provider_authorization and !capability.model_provider);
    try std.testing.expect(!native_binding.inspect(preparation.AllocatedSlot, &.{}).valid);
    try std.testing.expect(@typeInfo(@import("domain/provider_authorization_result.zig").Result) == .@"opaque");
    const yaml_binding = @embedFile("application/provider_authorization_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(yaml_binding, "action.execute("));
    inline for (.{ "Table", "countInputTokens", "InvokeModel", "retry-limit", "/adapters/" }) |forbidden| try expectAbsent(yaml_binding, forbidden);
    // The deadline is the bound catalogue entry's, never a YAML parameter or a
    // fixed replay value (ADR 0030).
    try std.testing.expectEqual(@as(usize, 0), @import("application/provider_authorization_workflow.zig").Prepare.contract.parameters.len);
    inline for (.{ "application/provider_authorization_workflow.zig", "domain/workflow_provider_authorization.zig", "application/workflow_provider_authorization.zig", "application/workflow_pipeline_runner.zig" }) |path| try expectAbsent(@embedFile(path), "timeout-ms");
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("application/workflow_provider_authorization.zig"), "registry_entry.config.requestTimeout()") != null);
    try expectAbsent(@embedFile("adapters/provider/request_replay.zig"), "300_000");
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "Binding.allocate(").? < std.mem.indexOf(u8, runner, "var candidate = entry.invoke(.{ .step").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "bound.validate(result, candidate.outcome)").? < std.mem.indexOf(u8, runner, "const applied = self.applyCandidate(").?);
    try std.testing.expect(std.mem.indexOf(u8, runner, "const applied = self.applyCandidate(").? < std.mem.indexOf(u8, runner, "authorization_published = prepared").?);
    const execution_state = @embedFile("application/workflow_model_accounting.zig");
    try std.testing.expect(std.mem.indexOf(u8, execution_state, "self.authorization_leases.deinit()").? < std.mem.indexOf(u8, execution_state, "lifecycle.deinitOwner(self.operations)").?);

    inline for (.{
        "ports/provider_operation_authorization.zig",
        "ports/provider_authorization_lease.zig",
        "actions/model/prepare_provider_operation_authorization.zig",
        "application/provider_authorization_lease_table.zig",
        "application/workflow_provider_authorization.zig",
        "application/provider_authorization_workflow.zig",
        "adapters/provider/fake_provider_authorization.zig",
    }) |path| {
        const source = @embedFile(path);
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "std.http");
        try expectAbsent(source, "std.process");
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "@constCast");
    }
    const fake = @embedFile("adapters/provider/fake_llm_provider.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(fake, "authorization_leases.consume("));
    try expectAbsent(fake, "/application/");
    const preloader = @embedFile("adapters/provider/fake_provider_authorization.zig");
    try expectAbsent(preloader, "/application/");
    try expectAbsent(preloader, "getEnv");
    const lifecycle_runner = @embedFile("provider_operation_lifecycle_runner_test_fixture.zig");
    try std.testing.expect(std.mem.indexOf(u8, lifecycle_runner, "authorization_leases.deinit()").? < std.mem.indexOf(u8, lifecycle_runner, "lifecycle.deinitOwner(").?);
    try std.testing.expect(std.mem.indexOf(u8, lifecycle_runner, "self.ledger = try lifecycle.apply(").? < std.mem.indexOf(u8, lifecycle_runner, "authorization_leases.update(").?);
    const prepare_action = @embedFile("actions/model/prepare_provider_operation_authorization.zig");
    try expectAbsent(prepare_action, "llm_provider_interface");
    try expectAbsent(prepare_action, "lifecycle.apply");
    try std.testing.expect(std.mem.indexOf(u8, prepare_action, "delta.data_writes[") != null);
}

test "actor authentication has one runner-issued lease, one action that observes the account and one capability-bound port" {
    const pipeline = @import("domain/pipeline.zig");
    const native_binding = @import("application/workflow_operation_binding.zig");
    const port = @import("ports/actor_authentication.zig");
    // The port grants the authentication capability and no other.
    const capability = native_binding.inspect(port.Port, &.{});
    try std.testing.expect(capability.valid and capability.actor_authentication);
    try std.testing.expect(!capability.model_provider and !capability.provider_authorization and !capability.feature_logging and !capability.feature_input_read and !capability.feature_output_write and !capability.feature_read and !capability.reference_read);
    // The runner alone issues and ends a lease: it ends first on every path (a `defer`), issues before the step runs, and
    // checks after the step that an `ok` one consumed it.
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, "authentication_leases.issue("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, "authentication_leases.finalize("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, ".actor_authentication = authentication_lease"));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(runner, ".authentication_unconsumed"));
    const finalize_at = std.mem.indexOf(u8, runner, "authentication_leases.finalize(").?;
    const issue_at = std.mem.indexOf(u8, runner, "authentication_leases.issue(").?;
    const invoke_at = std.mem.indexOf(u8, runner, "var candidate = entry.invoke(.{ .step").?;
    const unconsumed_at = std.mem.indexOf(u8, runner, ".authentication_unconsumed").?;
    try std.testing.expect(finalize_at < issue_at and issue_at < invoke_at and invoke_at < unconsumed_at);
    try std.testing.expect(std.mem.lastIndexOf(u8, runner[0..finalize_at], "defer ") != null);
    // Nothing else holds the table: the port consumes a lease it was given, and the chain's own files name neither the table
    // nor the slot (the next test walks every layer for the table).
    inline for (.{
        "actions/clarification/authenticate_actor.zig",
        "actions/clarification/plan_clarification_authentication.zig",
        "actions/clarification/check_clarification_authentication.zig",
        "actions/clarification/advance_clarification_authentication.zig",
        "actions/clarification/accept_clarification_responses.zig",
        "actions/clarification/check_clarification_cancellation.zig",
        "actions/clarification/prepare_cancelled_clarification_output.zig",
        "actions/specify/prepare_actor_evidence.zig",
        "application/actor_evidence_workflow.zig",
        "composition/native_workflow_operations.zig",
        "ports/actor_authentication.zig",
    }) |path| {
        const source = @embedFile(path);
        try expectAbsent(source, "authentication_leases");
        try expectAbsent(source, "lease.Table");
        try expectAbsent(source, ".issue(");
        try expectAbsent(source, ".finalize(");
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "anyopaque");
        try expectAbsent(source, "@constCast");
    }
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("ports/actor_authentication.zig"), ".consume("));
    inline for (.{ "actions/clarification/authenticate_actor.zig", "application/actor_evidence_workflow.zig", "adapters/system/os_account.zig" }) |path| {
        const source = @embedFile(path);
        const production = source[0 .. std.mem.indexOf(u8, source, "\ntest \"") orelse source.len];
        try expectAbsent(production, ".consume(");
        try expectAbsent(production, "lease.Table");
    }
    // The action observes the account only through the port, once, and passes the lease it was given.
    const observing = @embedFile("actions/clarification/authenticate_actor.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(observing, ".authenticate("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("application/actor_evidence_workflow.zig"), "self.action.execute(scratch.allocator(), input.step.runtime, granted)"));
    // Exactly one action declares the effect, and it is the one that takes the port.
    const io = std.testing.io;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(std.testing.allocator);
    defer walker.deinit();
    var declaring: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        if (std.mem.indexOf(u8, source, ".side_effect = .actor_authentication") != null) {
            declaring += 1;
            try std.testing.expectEqualStrings("authenticate_actor.zig", entry.basename);
        }
        if (std.mem.indexOf(u8, source, "ports/actor_authentication.zig") != null) try std.testing.expectEqualStrings("authenticate_actor.zig", entry.basename);
    }
    try std.testing.expectEqual(@as(usize, 1), declaring);
    const contract = @import("actions/clarification/authenticate_actor.zig").Action.contract;
    try std.testing.expectEqual(pipeline.SideEffect.actor_authentication, contract.side_effect);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, contract.repair_role);
    try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, contract.runner_accounting);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.actor_observation}, contract.produces);
    // The chain's other actions are pure, and the two stage actions are capability-free stages (ADR 0031).
    inline for (.{
        @import("actions/clarification/plan_clarification_authentication.zig").Action.contract,
        @import("actions/clarification/check_clarification_authentication.zig").Action.contract,
        @import("actions/clarification/advance_clarification_authentication.zig").Action.contract,
        @import("actions/clarification/accept_clarification_responses.zig").Action.contract,
        @import("actions/clarification/check_clarification_cancellation.zig").Action.contract,
        @import("actions/clarification/prepare_cancelled_clarification_output.zig").Action.contract,
    }) |pure| try std.testing.expectEqual(pipeline.SideEffect.none, pure.side_effect);
    inline for (.{
        .{ @embedFile("actions/specify/prepare_actor_evidence.zig"), @import("actions/specify/prepare_actor_evidence.zig").Action.contract, pipeline.SideEffect.filesystem_read },
        .{ @embedFile("actions/clarification/accept_clarification_responses.zig"), @import("actions/clarification/accept_clarification_responses.zig").Action.contract, pipeline.SideEffect.none },
    }) |stage| {
        try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(stage[0]));
        try expectAllowedActionImports(stage[0]);
        try expectSingleActionContract(stage[0]);
        try std.testing.expectEqual(stage[2], stage[1].side_effect);
        try std.testing.expectEqual(pipeline.NodeKind.action, stage[1].kind);
        try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, stage[1].repair_role);
        try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, stage[1].runner_accounting);
    }
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{ .raw_actor_evidence, .actor_evidence_registry }, @import("actions/specify/prepare_actor_evidence.zig").Action.contract.produces);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{ .clarification_inputs, .actor_evidence_registry }, @import("actions/clarification/accept_clarification_responses.zig").Action.contract.replaces);
    // The Spec workflow loads the registry after logging and authenticates before it extracts; the subgraph plans, checks,
    // observes, advances and then accepts.
    const spec_workflow = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec.workflow.yaml", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(spec_workflow);
    const logging_at = std.mem.indexOf(u8, spec_workflow, "  logging:\n").?;
    const evidence_at = std.mem.indexOf(u8, spec_workflow, "use: prepare-actor-evidence").?;
    const call_at = std.mem.indexOf(u8, spec_workflow, "call: authenticate-clarifications").?;
    const extract_at = std.mem.indexOf(u8, spec_workflow, "  extract:\n").?;
    try std.testing.expect(logging_at < evidence_at and evidence_at < call_at and call_at < extract_at);
    var cursor: usize = std.mem.indexOf(u8, spec_workflow, "\nsubgraphs:\n  authenticate-clarifications:\n").?;
    inline for (.{ "use: plan-clarification-authentication", "use: check-clarification-authentication", "use: authenticate-actor", "use: advance-clarification-authentication", "use: accept-clarification-responses", "use: check-clarification-cancellation" }) |operation| {
        cursor = std.mem.indexOfPos(u8, spec_workflow, cursor, operation) orelse return error.MissingAuthenticationStep;
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(spec_workflow, operation));
    }
    // A cancel the run accepted is published by its own subgraph, which prepares the cancelled output and then publishes it,
    // with no other operation between the two (ADR 0025).
    const cancellation_at = std.mem.indexOf(u8, spec_workflow, "  cancellation:\n    call: publish-cancellation\n").?;
    try std.testing.expect(call_at < cancellation_at and cancellation_at < extract_at);
    const prepare_at = std.mem.indexOf(u8, spec_workflow, "use: prepare-cancelled-clarification-output").?;
    const publisher_at = std.mem.indexOfPos(u8, spec_workflow, prepare_at, "use: publish-workflow-output").?;
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(spec_workflow, "use: prepare-cancelled-clarification-output"));
    try std.testing.expect(cursor < prepare_at);
    // The slice from the preparation up to the publisher holds the preparation's own `use:` and no other.
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(spec_workflow[prepare_at..publisher_at], "use: "));
    try std.testing.expect(std.mem.indexOf(u8, spec_workflow[prepare_at..publisher_at], "on: {ok: publish, failed: end.failed}") != null);
}

test "only the runner names the authentication lease table, and only the listed modules take a lease" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    // The modules that may import the lease type: the runner issues it, the step's action and the port take it, the adapter's
    // tests spend it, and the registry's step input carries it. None of them but the runner names the table in production.
    const lease_modules = [_][]const u8{ "workflow_pipeline_runner.zig", "authenticate_actor.zig", "actor_authentication.zig", "os_account.zig", "workflow_operation_registry.zig" };
    for ([_][]const u8{ "src/actions", "src/ports", "src/adapters", "src/application", "src/composition" }) |root| {
        var directory = try std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true });
        defer directory.close(io);
        var walker = try directory.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
            const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
            defer allocator.free(source);
            const production = source[0 .. std.mem.indexOf(u8, source, "\ntest \"") orelse source.len];
            if (std.mem.indexOf(u8, production, "authentication_leases") != null) try std.testing.expectEqualStrings("workflow_pipeline_runner.zig", entry.basename);
            if (std.mem.indexOf(u8, production, "actor_authentication_lease.zig") != null) {
                var listed = false;
                for (lease_modules) |name| listed = listed or std.mem.eql(u8, name, entry.basename);
                try std.testing.expect(listed);
            }
        }
    }
}

test "model attempt accounting has one runner-applied transition authority" {
    switch (@typeInfo(model_attempt_accounting.RunnerModelAttemptAccounting)) {
        .@"opaque" => {},
        else => return error.RunnerModelAttemptAccountingMustBeOpaque,
    }

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        const declarations = countOccurrences(source, ".runner_accounting = .increment_model_attempt");
        if (std.mem.eql(u8, entry.path, "model/advance_model_attempt_accounting.zig")) {
            try std.testing.expectEqual(@as(usize, 1), declarations);
        } else {
            try std.testing.expectEqual(@as(usize, 0), declarations);
        }
    }

    const action = @embedFile("actions/model/advance_model_attempt_accounting.zig");
    try expectAbsent(action, "/ports/");
    try expectAbsent(action, "/adapters/");
    try expectAbsent(action, "std.Io");
    const accounting = @embedFile("domain/model_attempt_accounting.zig");
    try expectAbsent(accounting, "/ports/");
    try expectAbsent(accounting, "/adapters/");
    try expectAbsent(accounting, "std.Io");
    try expectAbsent(accounting, "MaximumAttempts");
    try expectAbsent(accounting, "configured");
    try expectAbsent(accounting, "hard");

    const request_identity = @embedFile("domain/model_request_identity.zig");
    try expectAbsent(request_identity, "not_invoked_attempt_ceiling");

    const workflow_operation = @embedFile("domain/workflow_operation.zig");
    try expectAbsent(workflow_operation, "loop_budget");
    try expectAbsent(workflow_operation, "retry_count");

    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try expectAbsent(runner, "/adapters/");
    try expectAbsent(runner, "std.Io");
    const prepare_index = std.mem.indexOf(u8, runner, "pending = state.prepare(").?;
    const validate_index = std.mem.indexOf(u8, runner, "self.envelope.applyOccurrence(").?;
    const commit_index = std.mem.indexOf(u8, runner, "self.model_accounting.?.commit(").?;
    try std.testing.expect(prepare_index < validate_index);
    try std.testing.expect(validate_index < commit_index);
    const state = @embedFile("application/workflow_model_accounting.zig");
    inline for (.{ "/ports/", "/adapters/", "/actions/", "std.Io", "retry_execution_counts" }) |forbidden| try expectAbsent(state, forbidden);
    const native = @embedFile("application/model_attempt_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(native, "self.action.execute("));
    inline for (.{ "accounting.apply(", "lifecycle.apply(", "std.Io", "LLMProviderInterface" }) |forbidden| try expectAbsent(native, forbidden);
    try std.testing.expect(@typeInfo(model_attempt_accounting.AccountedAttempt) == .@"opaque");
}

test "workflow token accounting has one mutation authority and a read-only check" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        const reconciles = countOccurrences(source, ".runner_accounting = .reconcile_workflow_tokens");
        try std.testing.expectEqual(
            @as(usize, if (std.mem.eql(u8, entry.path, "model/reconcile_workflow_token_usage.zig")) 1 else 0),
            reconciles,
        );
    }

    inline for (.{
        "actions/model/check_workflow_token_budget.zig",
        "actions/model/reconcile_workflow_token_usage.zig",
    }) |path| {
        const source = @embedFile(path);
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
    }
    const tokens = @import("domain/workflow_token_accounting.zig");
    try std.testing.expect(!@hasDecl(tokens, "ReservationTransition"));
    try std.testing.expect(!@hasField(tokens.Ledger, "reserved_tokens"));
    try std.testing.expect(@import("actions/model/check_workflow_token_budget.zig").Action.contract.runner_accounting == .none);
}

test "provider lifecycle has one pure action and runner-owned immutable ledger" {
    const lifecycle = @import("domain/provider_operation_lifecycle.zig");
    try std.testing.expect(@FieldType(lifecycle.Command, "assign_inference") == lifecycle.Assignment);
    switch (@typeInfo(lifecycle.Ledger)) {
        .@"opaque" => {},
        else => return error.ProviderOperationLedgerMustBeOpaque,
    }
    try std.testing.expect(!@hasDecl(lifecycle, "Effect"));
    try std.testing.expect(!@hasDecl(lifecycle, "TerminalSummary"));
    try std.testing.expect(!@hasDecl(lifecycle, "projectEffect"));
    try std.testing.expect(!@hasDecl(lifecycle.Transition, "effect"));
    const lifecycle_runner = @import("provider_operation_lifecycle_runner_test_fixture.zig").Runner;
    try std.testing.expect(@typeInfo(@TypeOf(lifecycle_runner.advance)).@"fn".return_type.? == lifecycle.Error!void);

    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        try std.testing.expectEqual(
            @as(usize, if (std.mem.eql(u8, entry.path, "model/advance_provider_operation_lifecycle.zig")) 1 else 0),
            countOccurrences(source, ".runner_accounting = .advance_provider_operation"),
        );
    }
    inline for (.{
        "actions/model/advance_provider_operation_lifecycle.zig",
        "domain/provider_operation_lifecycle.zig",
        "provider_operation_lifecycle_runner_test_fixture.zig",
    }) |path| {
        const source = @embedFile(path);
        try expectAbsent(source, "/ports/");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.Io");
    }
    const action_source = @embedFile("actions/model/advance_provider_operation_lifecycle.zig");
    try expectAbsent(action_source, "lifecycle.apply(");
    try std.testing.expect(@typeInfo(lifecycle.AssignedOperation) == .@"opaque");
    const native = @embedFile("application/provider_operation_workflow.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(native, "self.action.execute("));
    inline for (.{ "lifecycle.apply(", "LLMProviderInterface", "ProviderAuthorization", "std.Io", "reconcile(" }) |forbidden| try expectAbsent(native, forbidden);
    const workflow_runner = @embedFile("application/workflow_pipeline_runner.zig");
    try expectAbsent(workflow_runner, "initial(state.operations)");
    try std.testing.expect(std.mem.indexOf(u8, workflow_runner, "pending = state.prepareAssignment(").? < std.mem.indexOf(u8, workflow_runner, "self.envelope.applyOccurrence(").?);
    try std.testing.expect(std.mem.indexOf(u8, workflow_runner, "self.envelope.applyOccurrence(").? < std.mem.indexOf(u8, workflow_runner, "self.model_accounting.?.commit(").?);
    const runner = @embedFile("provider_operation_lifecycle_runner_test_fixture.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "envelope.applyDelta(").? < std.mem.indexOf(u8, runner, "lifecycle.apply(").?);
    const request_runner = @embedFile("model_request_identity_runner_test_fixture.zig");
    try std.testing.expect(std.mem.indexOf(u8, request_runner, "operations.deinit()").? < std.mem.indexOf(u8, request_runner, "identity.deinitOwner(owner)").?);
}

test "only request identity owners can produce or replace its ledger key" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        const source = try entry.dir.readFileAlloc(
            io,
            entry.basename,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        const produces = countOccurrences(source, ".produces = &.{.model_request_identity_ledger}");
        const replaces = countOccurrences(source, ".replaces = &.{.model_request_identity_ledger}");
        if (std.mem.eql(u8, entry.path, "model/build_initial_model_request_identity_ledger.zig")) {
            try std.testing.expectEqual(@as(usize, 1), produces);
        } else {
            try std.testing.expectEqual(@as(usize, 0), produces);
        }
        if (std.mem.eql(u8, entry.path, "model/prepare_model_request.zig") or
            std.mem.eql(u8, entry.path, "model/advance_model_request_lifecycle.zig"))
        {
            try std.testing.expectEqual(@as(usize, 1), replaces);
        } else {
            try std.testing.expectEqual(@as(usize, 0), replaces);
        }
    }
}

test "provider requirement derives only from one exactly selected compiled workflow" {
    const derivation_source = @embedFile("domain/provider_requirement_derivation.zig");
    try expectAbsent(derivation_source, "/adapters/");
    try expectAbsent(derivation_source, "/ports/");
    try expectAbsent(derivation_source, "std.Io");
    try expectAbsent(derivation_source, "config.zig");
    try expectAbsent(derivation_source, "sddproviders");
    try expectAbsent(derivation_source, "\"specify\"");
    try expectAbsent(derivation_source, "\"implement\"");

    const derive_type = @typeInfo(@TypeOf(provider_requirement_derivation.derive)).@"fn";
    try std.testing.expectEqual(@as(usize, 1), derive_type.params.len);
    try std.testing.expect(derive_type.params[0].type.? == *const workflow_execution.SelectedWorkflow);
}

test "an authority rejection names its reason from one closed enum, raised only where the runner owns the check" {
    // `Rejection.authority` carries the reason, so a bare `.authority` cannot be built (the type refuses it).
    try std.testing.expect(@FieldType(workflow_execution.Rejection, "authority") == workflow_execution.AuthorityReason);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("domain/workflow_execution.zig"), "pub const AuthorityReason = enum"));
    const producers = .{
        @embedFile("application/workflow_pipeline_runner.zig"),
        @embedFile("application/model_request_orchestrator.zig"),
        @embedFile("application/workflow_model_invocation.zig"),
    };
    // Every reason has a producer: a member nothing raises is dead vocabulary. A reason counts as a
    // whole token, so `kernel_stage` is not raised by a `kernel_stage_outcome`.
    inline for (@typeInfo(workflow_execution.AuthorityReason).@"enum".fields) |reason| {
        var raised: usize = 0;
        inline for (producers) |source| raised += countReasonProducers(source, reason.name);
        try std.testing.expect(raised > 0);
    }
    // Only the runner, the request orchestrator and the model-invocation reconciliation raise one: an action
    // proposes a candidate, and no other production file under `src` (an adapter, port, domain value or
    // another application workflow) stops a run on the runner's authority. A reason named in any
    // `.authority = .<reason>`, whether the rejection is an anonymous literal or a named `Rejection{`, is a
    // producer. A reason built any other way (a variable, a cast, a function result) has to name the reason
    // type, which no other production file does.
    const owners = [_][]const u8{ "application/workflow_pipeline_runner.zig", "application/model_request_orchestrator.zig", "application/workflow_model_invocation.zig" };
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    var reached_application = false;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (std.mem.indexOf(u8, entry.basename, "_test") != null or std.mem.startsWith(u8, entry.path, "test_fixtures/")) continue;
        const owner = for (owners) |path| {
            if (std.mem.eql(u8, entry.path, path)) break true;
        } else false;
        if (owner) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(source);
        inline for (@typeInfo(workflow_execution.AuthorityReason).@"enum".fields) |reason| {
            try std.testing.expectEqual(@as(usize, 0), countReasonProducers(source, reason.name));
        }
        if (!std.mem.eql(u8, entry.path, "domain/workflow_execution.zig")) try std.testing.expectEqual(@as(usize, 0), countOccurrences(source, "AuthorityReason"));
        // The scan reached an application workflow that is no owner, which is where a second producer
        // would be added.
        if (std.mem.eql(u8, entry.path, "application/model_request_workflow.zig")) reached_application = true;
    }
    try std.testing.expect(reached_application);
}

/// Whether `source` returns `error.<name>`, naming the cause as a whole token in code: outside every
/// comment (a whole line or a trailing one), every string literal and every `test` block (a formatted
/// file opens one with `test "` and closes it with `}`, both at the start of a line).
fn returnsError(source: []const u8, comptime name: []const u8) bool {
    const needle = "error." ++ name;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, source, from, needle)) |index| : (from = index + needle.len) {
        const after = index + needle.len;
        if (after < source.len and (std.ascii.isAlphanumeric(source[after]) or source[after] == '_')) continue;
        if (index > 0 and (std.ascii.isAlphanumeric(source[index - 1]) or source[index - 1] == '_')) continue;
        if (!inCode(source, index)) continue;
        const before = source[0..index];
        const opened = std.mem.lastIndexOf(u8, before, "\ntest \"");
        const closed = std.mem.lastIndexOf(u8, before, "\n}");
        if (opened != null and (closed == null or closed.? < opened.?)) continue;
        return true;
    }
    return false;
}

/// Whether the byte at `index` is code of its own line: after no `//` and inside no string literal or
/// multiline string. A quote in a character literal opens no string.
fn inCode(source: []const u8, index: usize) bool {
    const line_start = if (std.mem.lastIndexOfScalar(u8, source[0..index], '\n')) |newline| newline + 1 else 0;
    const line = source[line_start..index];
    if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " "), "\\\\")) return false;
    var in_string = false;
    var position: usize = 0;
    while (position < line.len) : (position += 1) {
        const byte = line[position];
        if (in_string) {
            if (byte == '\\') position += 1 else if (byte == '"') in_string = false;
            continue;
        }
        switch (byte) {
            '"' => in_string = true,
            '\'' => position = closingQuote(line, position),
            '/' => if (position + 1 < line.len and line[position + 1] == '/') return false,
            else => {},
        }
    }
    return !in_string;
}

/// The position of the quote that closes the character literal opened at `open`, or `open` when none does.
fn closingQuote(line: []const u8, open: usize) usize {
    var position = open + 1;
    if (position < line.len and line[position] == '\\') position += 1;
    position += 1;
    return if (position < line.len and line[position] == '\'') position else open;
}

/// How often `source` raises `.authority = .<reason>`, counting the reason as a whole token.
fn countReasonProducers(source: []const u8, comptime reason: []const u8) usize {
    const needle = ".authority = ." ++ reason;
    var count: usize = 0;
    var remaining = source;
    while (std.mem.indexOf(u8, remaining, needle)) |index| {
        const after = index + needle.len;
        const longer = after < remaining.len and (std.ascii.isAlphanumeric(remaining[after]) or remaining[after] == '_');
        if (!longer) count += 1;
        remaining = remaining[after..];
    }
    return count;
}

test "a reason counts as produced only as a whole token, and a cause as returned only outside comments and test blocks" {
    try std.testing.expectEqual(@as(usize, 1), countReasonProducers(".{ .authority = .kernel_stage }", "kernel_stage"));
    try std.testing.expectEqual(@as(usize, 1), countReasonProducers("execution.Rejection{ .authority = .kernel_stage }", "kernel_stage"));
    try std.testing.expectEqual(@as(usize, 0), countReasonProducers(".{ .authority = .kernel_stage_outcome }", "kernel_stage"));
    try std.testing.expectEqual(@as(usize, 0), countReasonProducers(".{ .authority = .gate_drift }", "kernel_stage"));
    try std.testing.expect(returnsError("fn f() !void { return error.Foo; }", "Foo"));
    try std.testing.expect(returnsError("\ntest \"t\" {\n}\n\nfn f() !void { return error.Foo; }\n", "Foo"));
    try std.testing.expect(!returnsError("fn f() !void { return error.FooBar; }", "Foo"));
    try std.testing.expect(!returnsError("// raised as error.Foo\n", "Foo"));
    try std.testing.expect(!returnsError("fn f() void {}\n\ntest \"t\" {\n    try expectError(error.Foo, f());\n}\n", "Foo"));
    // A cause named after a comment opens, inside a string literal or on a multiline string line is not
    // returned; a quote in a character literal or an escaped quote in a string hides no code after it.
    try std.testing.expect(!returnsError("fn f() !void { return error.Other; } // would return error.Foo\n", "Foo"));
    try std.testing.expect(!returnsError("const s = \"return error.Foo\";\n", "Foo"));
    try std.testing.expect(!returnsError("const s =\n    \\\\return error.Foo\n;\n", "Foo"));
    try std.testing.expect(returnsError("fn f() !void { _ = '\"'; return error.Foo; }\n", "Foo"));
    try std.testing.expect(returnsError("const s = \"a\\\"b\"; fn f() !void { return error.Foo; }\n", "Foo"));
}

test "the reasons the runner contract tabulates are the reasons the enum declares" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const document = try std.Io.Dir.cwd().readFileAlloc(io, "design/contracts/06-pipeline-nodes.md", allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(document);
    const heading = "#### Runner rejection reasons";
    const start = std.mem.indexOf(u8, document, heading) orelse return error.ReasonTableMissing;
    const after = document[start + heading.len ..];
    const section = after[0 .. std.mem.indexOf(u8, after, "\n#### ") orelse after.len];
    const reasons = @typeInfo(workflow_execution.AuthorityReason).@"enum".fields;
    var listed = [_]usize{0} ** reasons.len;
    var rows: usize = 0;
    var lines = std.mem.splitScalar(u8, section, '\n');
    while (lines.next()) |line| {
        // A row of the table opens with its reason in code ticks.
        if (!std.mem.startsWith(u8, line, "| `")) continue;
        const name = line["| `".len..][0 .. std.mem.indexOfScalar(u8, line["| `".len..], '`') orelse return error.ReasonTableMalformed];
        const known = inline for (reasons, 0..) |reason, index| {
            if (std.mem.eql(u8, name, reason.name)) {
                listed[index] += 1;
                break true;
            }
        } else false;
        // A row names a reason the enum declares; the enum has no member the table lacks, or lists twice.
        try std.testing.expect(known);
        rows += 1;
    }
    try std.testing.expectEqual(reasons.len, rows);
    for (listed) |count| try std.testing.expectEqual(@as(usize, 1), count);
}

test "a first cause is one closed type, kept by the runner alone and built only where a replacement happens" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    var defined: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (std.mem.indexOf(u8, entry.basename, "_test") != null or std.mem.startsWith(u8, entry.path, "test_fixtures/")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(source);
        defined += countOccurrences(source, "pub const FirstCause = ");
        // Only the runner sets the record, in one place where the earliest replacement wins; the log
        // finalizer reports what it replaced and the runner decides whether to keep it.
        const runner = std.mem.eql(u8, entry.path, "application/workflow_pipeline_runner.zig");
        try std.testing.expectEqual(@as(usize, if (runner) 1 else 0), countOccurrences(source, ".first_cause = "));
        // Only a place that replaces a rejection builds one: the runner's one replacement and the log finalizer's.
        const builds: usize = if (runner or std.mem.eql(u8, entry.path, "composition/feature_logging_runtime.zig")) 1 else 0;
        try std.testing.expectEqual(builds, countOccurrences(source, "FirstCause.replacedBy("));
    }
    try std.testing.expectEqual(@as(usize, 1), defined);
    // The engine finalizes through the runner that keeps it, falling back to the bare finalizer only when no runner exists.
    const assembly = @embedFile("composition/engine_invocation.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(assembly, "runner.finish(outcome)"));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(assembly, "finalizer.finish(outcome)"));
}

test "workflow compiler and service preserve their authority boundaries" {
    switch (@typeInfo(workflow_registry.ValidatedWorkflowDefinitionRegistry)) {
        .@"opaque" => {},
        else => return error.WorkflowRegistryAuthorityMustBeOpaque,
    }
    const compiler = @embedFile("domain/workflow_graph_compilation.zig");
    try expectAbsent(compiler, "adapters/");
    try expectAbsent(compiler, "filesystem");
    try expectAbsent(compiler, "std.Io");
    try std.testing.expect(std.mem.indexOf(u8, compiler, "resolveOperation") != null);
    try expectAbsent(compiler, "spec.section.generate");
    try expectAbsent(compiler, "implementation.operation.generate");

    const operation_port = @embedFile("ports/workflow_operation_registry.zig");
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "operations: []const Entry") != null);
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "contract.kind == .invocation") != null);
    try std.testing.expect(std.mem.indexOf(u8, operation_port, "contract.kind != .step") != null);
    try expectAbsent(operation_port, "CompilerRegistry");
    try expectAbsent(operation_port, "NodeImplementation");

    const operation_bindings = @embedFile("composition/core_workflow_operations.zig");
    try expectAbsent(operation_bindings, "specify");
    try expectAbsent(operation_bindings, "plan");
    try expectAbsent(operation_bindings, "tasks");
    try expectAbsent(operation_bindings, "implement");

    const workflow_runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(workflow_runner, "resolveOperation"));
    try expectAbsent(workflow_runner, "resolveInvocation");
    try expectAbsent(workflow_runner, "resolveNode");
    try expectAbsent(workflow_runner, "workflow_node_implementation");

    const service = @embedFile("application/workflow_definition_registry_service.zig");
    try expectAbsent(service, "Inventory");
    try expectAbsent(service, "RawDefinition");
    const init_type = @typeInfo(@TypeOf(
        workflow_registry_service.WorkflowDefinitionRegistryService.init,
    )).@"fn";
    try std.testing.expectEqual(@as(usize, 1), init_type.params.len);

    const domain = @embedFile("domain/bootstrap_root_registry.zig");
    const adapter = @embedFile("adapters/filesystem/workflow_authority_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, domain, "bindWorkflowAuthorityAdapter") != null);
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(
        adapter,
        "bindWorkflowAuthorityAdapter",
    ));

    const parser_step = @embedFile("application/startup_routine.zig");
    try std.testing.expect(std.mem.indexOf(u8, parser_step, "workflow_definition_parser.zig") != null);
    try expectAbsent(parser_step, "std.json");
    try expectAbsent(parser_step, "bounded_yaml_syntax");
    try expectAbsent(parser_step, "/adapters/");
    const parser_adapter = @embedFile("adapters/parsers/workflow_definitions.zig");
    try std.testing.expect(std.mem.indexOf(u8, parser_adapter, "bounded_yaml_syntax") != null);
    try std.testing.expect(std.mem.indexOf(u8, parser_adapter, "workflow_definition_parser.zig") != null);
    const workflow_domain = @embedFile("domain/workflow_registry.zig");
    try expectAbsent(workflow_domain, "std.json");
    try expectAbsent(workflow_domain, "bounded_yaml_syntax");
    try expectAbsent(workflow_domain, "validInventoryPath");
    try expectAbsent(workflow_domain, "classifyInventoryDescriptor");
    try expectAbsent(workflow_domain, "RawNode");
    try expectAbsent(workflow_domain, "CompilerRegistry");

    const vocabulary = @embedFile("domain/workflow.zig");
    try expectAbsent(vocabulary, "InventoryDescriptor");
    try expectAbsent(vocabulary, "RawDefinition");
    try expectAbsent(vocabulary, "CompiledWorkflow");
    try expectAbsent(vocabulary, "ValidatedWorkflowDefinitionRegistry");

    const inventory_domain = @embedFile("domain/workflow_inventory.zig");
    try expectAbsent(inventory_domain, "RawDefinition");
    try expectAbsent(inventory_domain, "CompilerRegistry");
    try expectAbsent(inventory_domain, "CompiledWorkflow");

    const definition_domain = @embedFile("domain/workflow_definition.zig");
    try expectAbsent(definition_domain, "InventoryDescriptor");
    try expectAbsent(definition_domain, "CompilerRegistry");
    try expectAbsent(definition_domain, "ValidatedWorkflowDefinitionRegistry");

    const compilation_domain = @embedFile("domain/workflow_compilation.zig");
    try expectAbsent(compilation_domain, "InventoryDescriptor");
    try expectAbsent(compilation_domain, "RawDefinition");
    try expectAbsent(compilation_domain, "ValidatedWorkflowDefinitionRegistry");

    const capture = @embedFile("application/startup_routine.zig");
    const budget_index = std.mem.indexOf(u8, capture, "validateCaptureBudget") orelse return error.MissingWorkflowCaptureBudget;
    const read_index = std.mem.indexOf(u8, capture, "capturer.capture") orelse return error.MissingWorkflowCapture;
    try std.testing.expect(budget_index < read_index);
}

test "toolchain safety authority is opaque and path handoff has one adapter consumer" {
    switch (@typeInfo(toolchain_safety.ValidToolchain)) {
        .@"opaque" => {},
        else => return error.ValidToolchainMustBeOpaque,
    }
    const domain = @embedFile("domain/bootstrap_root_registry.zig");
    const adapter = @embedFile("adapters/filesystem/toolchain_authority_source.zig");
    try std.testing.expect(std.mem.indexOf(u8, domain, "bindToolchainAuthorityAdapter") != null);
    try std.testing.expectEqual(@as(usize, 3), countOccurrences(adapter, "bindToolchainAuthorityAdapter"));
    const startup = @embedFile("application/startup_routine.zig");
    try expectAbsent(startup, "invokeBootstrapToolchain");
    const stage = @embedFile("actions/toolchain/prepare_toolchain.zig");
    const capture_step = std.mem.indexOf(u8, stage, "pub fn capturePresets") orelse return error.MissingCaptureStep;
    const parse_step = std.mem.indexOf(u8, stage, "pub fn parseDocuments") orelse return error.MissingParseStep;
    const validate_step = std.mem.indexOf(u8, stage, "pub fn validateProject") orelse return error.MissingValidateStep;
    try std.testing.expect(capture_step < parse_step and parse_step < validate_step);
    const capture = stage[capture_step..parse_step];
    const budget_index = std.mem.indexOf(u8, capture, "validateCaptureBudget") orelse return error.MissingCaptureBudget;
    const read_index = std.mem.indexOf(u8, capture, "source.capturePreset(") orelse return error.MissingPresetCapture;
    try std.testing.expect(budget_index < read_index);
    try expectAbsent(stage[parse_step..validate_step], "validateCaptureBudget");

    const contracts = @embedFile("domain/toolchain.zig");
    try expectAbsent(contracts, "validateCaptureBudget(");
    try expectAbsent(contracts, "parseProject(");
    try expectAbsent(contracts, "parseRegistry(");
    try expectAbsent(contracts, "validateCompleteRegistry(");
    try expectAbsent(contracts, "pub fn resolve(");
    try expectAbsent(contracts, "pub fn compose(");
    try expectAbsent(contracts, "pub fn validate(");
    try expectAbsent(contracts, "pub const Owner");

    const accounting = @embedFile("domain/toolchain_accounting.zig");
    try expectAbsent(accounting, "parseProject(");
    try expectAbsent(accounting, "resolve(");
    try expectAbsent(accounting, "compose(");
    const schema = @embedFile("domain/toolchain_schema.zig");
    try expectAbsent(schema, "validateCaptureBudget(");
    try expectAbsent(schema, "validateCompleteRegistry(");
    try expectAbsent(schema, "compose(");
    const inheritance = @embedFile("domain/toolchain_inheritance.zig");
    try expectAbsent(inheritance, "parseProject(");
    try expectAbsent(inheritance, "compose(");
    const composition = @embedFile("domain/toolchain_composition.zig");
    try expectAbsent(composition, "parseProject(");
    try expectAbsent(composition, "resolve(");
    try expectAbsent(composition, "pub fn validate(");
    const safety = @embedFile("domain/toolchain_safety.zig");
    try expectAbsent(safety, "parseProject(");
    try expectAbsent(safety, "validateCompleteRegistry(");
    try expectAbsent(safety, "compose(");
}

test "bootstrap source ports and workflow inventory stages remain single purpose" {
    const workflow_ports = @embedFile("ports/workflow_authority_source.zig");
    try expectAbsent(workflow_ports, "pub const Source");
    try std.testing.expect(std.mem.indexOf(u8, workflow_ports, "pub const Enumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, workflow_ports, "pub const Capturer") != null);

    const toolchain_ports = @embedFile("ports/toolchain_authority_source.zig");
    try expectAbsent(toolchain_ports, "pub const Source");
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const ProjectCapturer") != null);
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const PresetEnumerator") != null);
    try std.testing.expect(std.mem.indexOf(u8, toolchain_ports, "pub const PresetCapturer") != null);

    const startup = @embedFile("application/startup_routine.zig");
    try expectAbsent(startup, "inventory_workflow_authority.zig");
    // Each inventory stage is one single-purpose step of the startup routine, declared once.
    for ([_][]const u8{
        "pub fn enumerateWorkflowResources(",
        "pub fn normalizeWorkflowEntries(",
        "pub fn buildWorkflowAccounts(",
        "pub fn buildWorkflowInventory(",
        "pub fn validateWorkflowInventory(",
    }) |step| {
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(startup, step));
    }
}

test "the toolchain runner imports no startup action" {
    const toolchain_runner = @embedFile("application/toolchain_workflow_runner.zig");
    try expectAbsent(toolchain_runner, "/actions/config/");
    try expectAbsent(toolchain_runner, "/actions/bootstrap/");
    try expectAbsent(toolchain_runner, "/actions/workflow/");
}

const StageViolation = enum {
    execute_reaches_a_port,
    execute_lacks_the_node_runtime,
    internal_step_takes_the_action,
    internal_step_takes_two_ports,
    internal_step_is_erased,
    absorbs_a_gate_or_model_module,
};

/// The text between the parentheses of the function whose `fn` keyword is at `at`, across lines.
fn parameterText(source: []const u8, at: usize) ?[]const u8 {
    const open = std.mem.indexOfPos(u8, source, at, "(") orelse return null;
    var depth: usize = 0;
    var index = open;
    while (index < source.len) : (index += 1) switch (source[index]) {
        '(' => depth += 1,
        ')' => {
            depth -= 1;
            if (depth == 0) return source[open + 1 .. index];
        },
        else => {},
    };
    return null;
}

/// The alias a stage action gives the Unicode text services' port module (`unicode_normalizer.zig`).
/// The user's ruling (12 November 2026) counts its three types (normalizer, case folder, lexical
/// classifier) as one port family for ADR 0031's one-port rule; no other module has that exemption.
const text_family_alias = "text_port";

/// The number of ports a step's parameter list takes: each `*_port.` type counts as one, except that
/// every type of the text services' module together counts as one.
fn portCount(parameters: []const u8) usize {
    var count: usize = 0;
    var text_family = false;
    var rest = parameters;
    while (std.mem.indexOf(u8, rest, "_port.")) |at| {
        var start = at;
        while (start > 0 and (std.ascii.isAlphanumeric(rest[start - 1]) or rest[start - 1] == '_')) start -= 1;
        if (std.mem.eql(u8, rest[start .. at + "_port".len], text_family_alias)) text_family = true else count += 1;
        rest = rest[at + "_port.".len ..];
    }
    return count + @intFromBool(text_family);
}

/// Whether `word` occurs in `text` as a whole identifier, so `Input` matches `operations.Input` but
/// not `evidence.Inputs`.
fn hasWord(text: []const u8, word: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, word)) |at| : (from = at + word.len) {
        const before = at == 0 or !(std.ascii.isAlphanumeric(text[at - 1]) or text[at - 1] == '_');
        const end = at + word.len;
        const after = end == text.len or !(std.ascii.isAlphanumeric(text[end]) or text[end] == '_');
        if (before and after) return true;
    }
    return false;
}

/// ADR 0031's source rules for a stage action. `execute` takes the capability-free runtime and no
/// other runtime handle, and only passes its receiver's fields on: any other use of a field, such
/// as a call through it or an alias of it, reaches a port. Each internal step takes at most one
/// port and never the `Action` value, a receiver or an erased parameter, and the stage absorbs no
/// gate or model module. A struct that bundles ports is not detectable in source text.
fn stageViolation(source: []const u8) ?StageViolation {
    for ([_][]const u8{ "workflow_gate", "domain/model_", "provider_" }) |module| {
        if (std.mem.indexOf(u8, source, module) != null) return .absorbs_a_gate_or_model_module;
    }
    if (std.mem.indexOf(u8, source, "pub fn execute")) |start| {
        const parameters = parameterText(source, start) orelse return .execute_lacks_the_node_runtime;
        if (countOccurrences(parameters, "runtime: pipeline.NodeRuntime") != 1 or countOccurrences(parameters, "Runtime") != 1 or hasWord(parameters, "Input") or hasWord(parameters, "StepInput")) return .execute_lacks_the_node_runtime;
        const receiver = std.mem.trim(u8, parameters[0 .. std.mem.indexOfScalar(u8, parameters, ':') orelse return .execute_lacks_the_node_runtime], " \n");
        var needle_buffer: [64]u8 = undefined;
        const needle = std.fmt.bufPrint(&needle_buffer, "{s}.", .{receiver}) catch return .execute_reaches_a_port;
        var rest = source[start .. std.mem.indexOfPos(u8, source, start, "\n};") orelse source.len];
        while (std.mem.indexOf(u8, rest, needle)) |at| {
            var end = at + needle.len;
            while (end < rest.len and (std.ascii.isAlphanumeric(rest[end]) or rest[end] == '_')) end += 1;
            if (end >= rest.len or (rest[end] != ',' and rest[end] != ')')) return .execute_reaches_a_port;
            rest = rest[end..];
        }
    }
    const steps_start = std.mem.indexOf(u8, source, "pub const steps = struct {") orelse return null;
    var cursor = steps_start;
    while (std.mem.indexOfPos(u8, source, cursor, "fn ")) |at| {
        cursor = at + "fn ".len;
        const parameters = parameterText(source, at) orelse continue;
        if (std.mem.indexOf(u8, parameters, "anytype") != null or std.mem.indexOf(u8, parameters, "anyopaque") != null) return .internal_step_is_erased;
        if (std.mem.indexOf(u8, parameters, "Action") != null or std.mem.indexOf(u8, parameters, "self") != null) return .internal_step_takes_the_action;
        if (portCount(parameters) > 1) return .internal_step_takes_two_ports;
    }
    return null;
}

/// A step that turns a candidate value into a validated one returns a type distinct from its
/// input, and the next step requires exactly that type.
fn validatedHandoff(comptime Input: type, comptime Output: type, comptime NextInput: type) bool {
    return Input != Output and Output == NextInput;
}

fn ReturnPayload(comptime function: anytype) type {
    return @typeInfo(@typeInfo(@TypeOf(function)).@"fn".return_type.?).error_union.payload;
}

fn ParameterType(comptime function: anytype, comptime index: usize) type {
    return @typeInfo(@TypeOf(function)).@"fn".params[index].type.?;
}

test "the prepare-toolchain stage action obeys ADR 0031's stage rules" {
    const stage = @embedFile("actions/toolchain/prepare_toolchain.zig");
    try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(stage));
    try expectAllowedActionImports(stage);
    try expectSingleActionContract(stage);
    const pipeline = @import("domain/pipeline.zig");
    const action = @import("actions/toolchain/prepare_toolchain.zig");
    const contract = action.Action.contract;
    try std.testing.expect(contract.side_effect == .none or contract.side_effect == .filesystem_read);
    try std.testing.expectEqual(pipeline.NodeKind.action, contract.kind);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, contract.repair_role);
    try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, contract.runner_accounting);
    // The stage reads no retained model request and replaces or produces only its own edge key.
    try std.testing.expectEqual(@as(usize, 0), contract.requires.len + contract.optional.len + contract.replaces.len + contract.invalidates.len);
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.valid_toolchain}, contract.produces);
}

test "stage rules reject a stage that reaches a port, lacks the node runtime, takes the action, two ports or an erased parameter, or absorbs a gate or model module" {
    const execute_head = "pub const Action = struct {\n    pub fn execute(self: Action, runtime: pipeline.NodeRuntime) void {\n";
    const clean_head = execute_head ++ "        step(self.source, runtime);\n    }\n};\npub const steps = struct {\n";
    const steps_tail = "    }\n};\npub const steps = struct {\n};\n";
    // A call through a port field, an alias of one, and a receiver under another name reach a port.
    try std.testing.expectEqual(@as(?StageViolation, .execute_reaches_a_port), stageViolation(execute_head ++ "        self.source.read();\n" ++ steps_tail));
    try std.testing.expectEqual(@as(?StageViolation, .execute_reaches_a_port), stageViolation(execute_head ++ "        const alias = self.source;\n" ++ steps_tail));
    try std.testing.expectEqual(@as(?StageViolation, .execute_reaches_a_port), stageViolation("pub const Action = struct {\n    pub fn execute(stage: Action, runtime: pipeline.NodeRuntime) void {\n        stage.source.read();\n" ++ steps_tail));
    // `execute` takes exactly the capability-free runtime: none, or another handle besides it, rejects.
    try std.testing.expectEqual(@as(?StageViolation, .execute_lacks_the_node_runtime), stageViolation("pub const Action = struct {\n    pub fn execute(self: Action) void {\n" ++ steps_tail));
    try std.testing.expectEqual(@as(?StageViolation, .execute_lacks_the_node_runtime), stageViolation("pub const Action = struct {\n    pub fn execute(self: Action, runtime: pipeline.NodeRuntime, input: StepInput) void {\n" ++ steps_tail));
    // The registry's `Input` union carries the step input, so it is as forbidden as `StepInput`; a domain
    // type that merely contains the letters, such as `evidence.Inputs`, is not.
    try std.testing.expectEqual(@as(?StageViolation, .execute_lacks_the_node_runtime), stageViolation("pub const Action = struct {\n    pub fn execute(self: Action, runtime: pipeline.NodeRuntime, input: operations.Input) void {\n" ++ steps_tail));
    try std.testing.expectEqual(@as(?StageViolation, null), stageViolation("pub const Action = struct {\n    pub fn execute(self: Action, runtime: pipeline.NodeRuntime, inputs: evidence.Inputs) void {\n" ++ steps_tail));
    // A signature split across lines is read whole.
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn two(\n        a: source_port.ProjectCapturer,\n        b: parser_port.Parser,\n    ) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_is_erased), stageViolation(clean_head ++ "    pub fn split(\n        allocator: std.mem.Allocator,\n        context: *anyopaque,\n    ) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(clean_head ++ "    pub fn one(port: source_port.ProjectCapturer) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn two(a: source_port.ProjectCapturer, b: parser_port.Parser) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_the_action), stageViolation(clean_head ++ "    pub fn whole(stage: Action) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_the_action), stageViolation(clean_head ++ "    pub fn method(self: *Self) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_is_erased), stageViolation(clean_head ++ "    pub fn bag(capabilities: anytype) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_is_erased), stageViolation(clean_head ++ "    pub fn raw(context: *anyopaque) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .absorbs_a_gate_or_model_module), stageViolation("const g = @import(\"../../domain/workflow_gate.zig\");\n" ++ clean_head ++ "};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .absorbs_a_gate_or_model_module), stageViolation("const m = @import(\"../../domain/model_request.zig\");\n" ++ clean_head ++ "};\n"));
}

test "stage steps that validate hand the next step a distinct validated type" {
    const steps = @import("actions/toolchain/prepare_toolchain.zig").steps;
    try std.testing.expect(validatedHandoff(ParameterType(steps.validateProject, 1), ReturnPayload(steps.validateProject), ParameterType(steps.resolveInheritance, 1)));
    try std.testing.expect(validatedHandoff(ParameterType(steps.validateRegistry, 1), ReturnPayload(steps.validateRegistry), ParameterType(steps.resolveInheritance, 2)));
    try std.testing.expect(validatedHandoff(ParameterType(steps.resolveInheritance, 2), ReturnPayload(steps.resolveInheritance), ParameterType(steps.compose, 2)));
    try std.testing.expect(validatedHandoff(ParameterType(steps.compose, 2), ReturnPayload(steps.compose), ParameterType(steps.validateSafety, 1)));
    // Only the safety step yields the owner of the valid toolchain.
    try std.testing.expect(ReturnPayload(steps.validateSafety) == *toolchain_safety.Owner);
    // A step that returns its own input type, or a type the next step does not take, is rejected.
    try std.testing.expect(!validatedHandoff(u8, u8, u8));
    try std.testing.expect(!validatedHandoff(u8, u16, u32));
}

test "no absorbed toolchain operation remains registered or bound" {
    const absorbed = [_][]const u8{
        "capture-project-toolchain",
        "inventory-toolchain-presets",
        "capture-toolchain-presets",
        "parse-toolchain-documents",
        "validate-project-toolchain-schema",
        "validate-toolchain-preset-registry",
        "resolve-toolchain-inheritance",
        "compose-toolchain",
        "validate-toolchain-safety",
    };
    const sources = [_][]const u8{
        @embedFile("composition/native_workflow_operations.zig"),
        @embedFile("application/toolchain_workflow_runner.zig"),
        @embedFile("test_fixtures/toolchain.workflow.yaml"),
    };
    for (absorbed) |id| for (sources) |source| try expectAbsent(source, id);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("composition/native_workflow_operations.zig"), "runners.PrepareToolchain") != null);
}

test "the prepare-inputs stage action obeys ADR 0031's stage rules" {
    const stage = @embedFile("actions/specify/prepare_inputs.zig");
    try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(stage));
    try expectAllowedActionImports(stage);
    try expectSingleActionContract(stage);
    const pipeline = @import("domain/pipeline.zig");
    const contract = @import("actions/specify/prepare_inputs.zig").Action.contract;
    try std.testing.expect(contract.side_effect == .none or contract.side_effect == .filesystem_read);
    try std.testing.expectEqual(pipeline.NodeKind.action, contract.kind);
    try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, contract.repair_role);
    try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, contract.runner_accounting);
    // The stage reads only the invocation, replaces and invalidates nothing, and produces only its
    // own edge keys: none of its intermediates and no gate or captured-retention key.
    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.specify_invocation}, contract.requires);
    try std.testing.expectEqual(@as(usize, 0), contract.optional.len + contract.replaces.len + contract.invalidates.len);
    try std.testing.expectEqual(@as(usize, 8), contract.produces.len);
}

test "a stage rejects a step that takes two ports under this stage's port aliases" {
    const clean_head = "pub const Action = struct {\n    pub fn execute(self: Action, runtime: pipeline.NodeRuntime) void {\n        step(self.source, runtime);\n    }\n};\npub const steps = struct {\n";
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn two(a: feature_port.Inspector, b: state_port.Capturer) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn two(a: input_port.Capturer, b: parser_port.StateParser) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(clean_head ++ "    pub fn one(a: input_port.Capturer, allocator: std.mem.Allocator) void {}\n};\n"));
}

test "a stage counts only the Unicode text services as one port family and rejects every other pair of ports" {
    const clean_head = "pub const Action = struct {\n    pub fn execute(self: Action, runtime: pipeline.NodeRuntime) void {\n        step(self.source, runtime);\n    }\n};\npub const steps = struct {\n";
    // The text services are three types of one port module: one family, however many a step takes.
    try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(clean_head ++ "    pub fn texts(a: text_port.Normalizer, b: text_port.CaseFolder, c: text_port.LexicalClassifier) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn mixed(a: text_port.Normalizer, b: identity_port.Source) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn mixed(\n        a: text_port.Normalizer,\n        b: text_port.CaseFolder,\n        c: corpus_port.Capturer,\n    ) void {}\n};\n"));
    // No other module is a family: two types of one non-text module are two ports.
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn pair(a: corpus_port.Enumerator, b: corpus_port.Capturer) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn pair(a: source_port.ProjectCapturer, b: source_port.PresetCapturer) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, .internal_step_takes_two_ports), stageViolation(clean_head ++ "    pub fn pair(a: parser_port.StateParser, b: parser_port.FormParser) void {}\n};\n"));
    try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(clean_head ++ "    pub fn one(a: corpus_port.Capturer, allocator: std.mem.Allocator) void {}\n};\n"));
}

test "the reference preparation stage actions obey ADR 0031's stage rules" {
    const pipeline = @import("domain/pipeline.zig");
    const key = pipeline.DataKey;
    inline for (.{
        .{ @embedFile("actions/reference/prepare_reference_evidence.zig"), @import("actions/reference/prepare_reference_evidence.zig").Action.contract },
        .{ @embedFile("actions/reference/prepare_reference_tokens.zig"), @import("actions/reference/prepare_reference_tokens.zig").Action.contract },
    }) |stage| {
        try std.testing.expectEqual(@as(?StageViolation, null), stageViolation(stage[0]));
        try expectAllowedActionImports(stage[0]);
        try expectSingleActionContract(stage[0]);
        try expectAbsent(stage[0], "std.Io");
        try expectAbsent(stage[0], "/adapters/");
        try std.testing.expect(stage[1].side_effect == .none or stage[1].side_effect == .filesystem_read);
        try std.testing.expectEqual(pipeline.NodeKind.action, stage[1].kind);
        try std.testing.expectEqual(@import("domain/workflow_retry.zig").Role.none, stage[1].repair_role);
        try std.testing.expectEqual(pipeline.RunnerAccountingCapability.none, stage[1].runner_accounting);
        try std.testing.expectEqual(@as(usize, 0), stage[1].optional.len + stage[1].replaces.len + stage[1].invalidates.len);
    }
    // The evidence stage reads the filesystem; the token stage reads nothing and is capability free.
    const evidence = @import("actions/reference/prepare_reference_evidence.zig").Action.contract;
    const tokens = @import("actions/reference/prepare_reference_tokens.zig").Action.contract;
    try std.testing.expectEqual(pipeline.SideEffect.filesystem_read, evidence.side_effect);
    try std.testing.expectEqual(pipeline.SideEffect.none, tokens.side_effect);
    try std.testing.expectEqualSlices(key, &.{ .reference_directory, .feature_directory }, evidence.requires);
    try std.testing.expectEqualSlices(key, &.{.citable_reference_inputs}, evidence.produces);
    try std.testing.expectEqualSlices(key, &.{ .compiled_naming_policy, .valid_toolchain, .citable_reference_inputs }, tokens.requires);
    try std.testing.expectEqualSlices(key, &.{ .path_token_grammar, .reference_passive_literals, .structured_token_candidates }, tokens.produces);
}

fn namesDataKey(keys: []const @import("domain/pipeline.zig").DataKey, wanted: @import("domain/pipeline.zig").DataKey) bool {
    for (keys) |key| if (key == wanted) return true;
    return false;
}

test "the valid toolchain has one producer and is required only by the two stages that read the toolchain" {
    const wanted: @import("domain/pipeline.zig").DataKey = .valid_toolchain;
    // The toolchain stage produces it and neither requires, replaces nor invalidates it.
    const producer = @import("actions/toolchain/prepare_toolchain.zig").Action.contract;
    try std.testing.expect(namesDataKey(producer.produces, wanted));
    try std.testing.expect(!namesDataKey(producer.requires, wanted) and !namesDataKey(producer.optional, wanted) and !namesDataKey(producer.replaces, wanted) and !namesDataKey(producer.invalidates, wanted));
    // The naming-policy compiler and the reference token stage require it and write nothing to it. No downstream
    // stage re-checks the toolchain: nothing replaces or invalidates it, so nothing downstream can find it stale.
    inline for (.{ @import("actions/toolchain/compile_naming_policy.zig").Action.contract, @import("actions/reference/prepare_reference_tokens.zig").Action.contract }) |reader| {
        try std.testing.expect(namesDataKey(reader.requires, wanted));
        try std.testing.expect(!namesDataKey(reader.optional, wanted) and !namesDataKey(reader.produces, wanted) and !namesDataKey(reader.replaces, wanted) and !namesDataKey(reader.invalidates, wanted));
    }
    // No variant of the four generic repair operations names it.
    const generic = @import("application/repair_workflow.zig");
    inline for (.{ generic.AuthorizeRepair, generic.BuildRepairInput, generic.ParseRepair, generic.MergeRepair }) |G| {
        for (G.contract.variants) |variant| {
            try std.testing.expect(!namesDataKey(variant.requires, wanted) and !namesDataKey(variant.optional, wanted) and !namesDataKey(variant.produces, wanted));
            try std.testing.expect(!namesDataKey(variant.replaces, wanted) and !namesDataKey(variant.invalidates, wanted));
        }
    }
    // No other production file names the key: those four are every file that does, so no other contract,
    // repair owner effect or binding can require, optionally read, produce, replace or invalidate it.
    const named = [_][]const u8{
        "actions/toolchain/prepare_toolchain.zig",
        "actions/toolchain/compile_naming_policy.zig",
        "actions/reference/prepare_reference_tokens.zig",
        "application/toolchain_workflow_values.zig",
    };
    // The schema alias `valid` of `toolchain_workflow_values.zig` names the key too, so a contract could
    // reach it without the literal: exactly these files import that module.
    const importers = [_][]const u8{
        "application/path_token_workflow.zig",
        "application/reference_token_preparation_workflow.zig",
        "application/toolchain_workflow_runner.zig",
        "composition/native_workflow_operations.zig",
    };
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    var reached: usize = 0;
    var importing: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (std.mem.indexOf(u8, entry.basename, "_test") != null or std.mem.startsWith(u8, entry.path, "test_fixtures/")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(source);
        const expected: usize = for (named) |path| {
            if (std.mem.eql(u8, entry.path, path)) break 1;
        } else 0;
        try std.testing.expectEqual(expected, countOccurrences(source, ".valid_toolchain"));
        reached += expected;
        const imports: usize = for (importers) |path| {
            if (std.mem.eql(u8, entry.path, path)) break 1;
        } else 0;
        try std.testing.expectEqual(imports, countOccurrences(source, "toolchain_workflow_values.zig"));
        importing += imports;
    }
    try std.testing.expectEqual(named.len, reached);
    try std.testing.expectEqual(importers.len, importing);
}

test "the reference preparation steps that validate hand the next step a distinct validated type" {
    const evidence_steps = @import("actions/reference/prepare_reference_evidence.zig").steps;
    const token_steps = @import("actions/reference/prepare_reference_tokens.zig").steps;
    try std.testing.expect(validatedHandoff(ParameterType(evidence_steps.validateInventory, 3), ReturnPayload(evidence_steps.validateInventory), ParameterType(evidence_steps.captureSources, 2)));
    try std.testing.expect(validatedHandoff(ParameterType(evidence_steps.validateAccounting, 1), ReturnPayload(evidence_steps.validateAccounting), ParameterType(evidence_steps.assignIdentities, 2)));
    try std.testing.expect(validatedHandoff(ParameterType(evidence_steps.validateChunks, 0), ReturnPayload(evidence_steps.validateChunks), @import("domain/reference_evidence.zig").Inputs));
    try std.testing.expect(validatedHandoff(ParameterType(token_steps.validateLiterals, 4), ReturnPayload(token_steps.validateLiterals), @import("domain/passive_literals.zig").Registry));
    // Each token step takes exactly the type its predecessor returns.
    try std.testing.expect(ReturnPayload(token_steps.buildGrammar) == ParameterType(token_steps.scanLiterals, 4));
    try std.testing.expect(ReturnPayload(token_steps.scanLiterals) == ParameterType(token_steps.assignLiterals, 1));
    try std.testing.expect(ReturnPayload(token_steps.assignLiterals) == ParameterType(token_steps.validateLiterals, 4));
    try std.testing.expect(ReturnPayload(token_steps.extractFacts) == ParameterType(token_steps.assignCandidates, 2));
}

test "no absorbed reference preparation operation remains registered, bound or placed in a workflow, and naming stays separate" {
    const absorbed = [_][]const u8{
        "inventory-reference-sources",
        "validate-reference-inventory",
        "capture-reference-sources",
        "decode-reference-markdown",
        "validate-reference-accounting",
        "assign-reference-identities",
        "build-reference-chunks",
        "validate-reference-chunks",
        "build-superset-path-token-grammar",
        "scan-reference-passive-literals",
        "assign-passive-literal-identities",
        "validate-reference-passive-literals",
        "extract-structured-reference-facts",
        "assign-structured-token-candidate-identities",
    };
    const io = std.testing.io;
    const spec_workflow = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec.workflow.yaml", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(spec_workflow);
    const sources = [_][]const u8{
        @embedFile("composition/native_workflow_operations.zig"),
        @embedFile("application/reference_evidence_preparation_workflow.zig"),
        @embedFile("application/reference_token_preparation_workflow.zig"),
        @embedFile("test_fixtures/reference-ingestion.workflow.yaml"),
        @embedFile("test_fixtures/path_token_workflow.zig"),
        spec_workflow,
    };
    for (absorbed) |id| for (sources) |source| try expectAbsent(source, id);
    const native = @embedFile("composition/native_workflow_operations.zig");
    try std.testing.expect(std.mem.indexOf(u8, native, "evidence_preparation.PrepareReferenceEvidence") != null);
    try std.testing.expect(std.mem.indexOf(u8, native, "token_preparation.PrepareReferenceTokens") != null);
    // The naming policy compiles in its own step, between the two stages (SPEC01 E2c).
    const evidence_at = std.mem.indexOf(u8, spec_workflow, "use: prepare-reference-evidence") orelse return error.MissingEvidenceStage;
    const naming_at = std.mem.indexOf(u8, spec_workflow, "use: compile-naming-policy") orelse return error.MissingNamingStep;
    const tokens_at = std.mem.indexOf(u8, spec_workflow, "use: prepare-reference-tokens") orelse return error.MissingTokenStage;
    try std.testing.expect(evidence_at < naming_at and naming_at < tokens_at);
}

test "the actor-evidence stage steps hand each next step the type the step before it produced" {
    const prepare = @import("actions/specify/prepare_actor_evidence.zig");
    const accept = @import("actions/clarification/accept_clarification_responses.zig");
    // Preparing: the registry as read is a distinct type from the validated one the stage hands on.
    try std.testing.expect(ReturnPayload(prepare.steps.parseRegistry) == ParameterType(prepare.steps.validateRegistry, 0));
    try std.testing.expect(validatedHandoff(ParameterType(prepare.steps.validateRegistry, 0), ReturnPayload(prepare.steps.validateRegistry), @FieldType(prepare.Outputs, "registry")));
    // Accepting: each step takes what an earlier one returned, and the join check reads the state the acceptance built.
    try std.testing.expect(ReturnPayload(accept.steps.bindForms) == ParameterType(accept.steps.acceptResponses, 3));
    try std.testing.expect(ReturnPayload(accept.steps.recordEvidence) == ParameterType(accept.steps.acceptResponses, 4));
    try std.testing.expect(ReturnPayload(accept.steps.acceptResponses) == ParameterType(accept.steps.validateResponses, 1));
    try std.testing.expect(ReturnPayload(accept.steps.acceptResponses) == @FieldType(accept.Outputs, "inputs"));
}

test "the prepare-inputs stage steps that validate hand the next step a distinct validated type" {
    const steps = @import("actions/specify/prepare_inputs.zig").steps;
    try std.testing.expect(validatedHandoff(ParameterType(steps.validateFeature, 1), ReturnPayload(steps.validateFeature), ParameterType(steps.inspectFeature, 2)));
    try std.testing.expect(validatedHandoff(ParameterType(steps.validateReference, 0), ReturnPayload(steps.validateReference), ParameterType(steps.inspectReference, 2)));
    try std.testing.expect(validatedHandoff(ParameterType(steps.validateClarificationState, 0), ReturnPayload(steps.validateClarificationState), ParameterType(steps.validateClarificationForms, 2)));
    // Observation precedes path resolution and the prior state is parsed from bytes the capture read.
    try std.testing.expect(ReturnPayload(steps.inspectFeature) == ParameterType(steps.resolvePaths, 2));
    try std.testing.expect(ReturnPayload(steps.captureState) == ?[]const u8 and ParameterType(steps.parseState, 4) == ?[]const u8);
}

test "no absorbed input-preparation operation remains registered, bound or placed in a workflow" {
    const absorbed = [_][]const u8{
        "normalize-feature-directory",
        "validate-feature-directory",
        "inspect-feature-directory",
        "resolve-feature-artifact-paths",
        "normalize-reference-selector",
        "validate-reference-selector",
        "inspect-reference-directory",
        "capture-workflow-state",
        "parse-specification-state",
        "capture-clarification-inputs",
        "parse-clarification-state",
        "validate-clarification-state",
        "validate-clarification-forms",
    };
    const io = std.testing.io;
    const spec_workflow = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec.workflow.yaml", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(spec_workflow);
    const sources = [_][]const u8{
        @embedFile("composition/native_workflow_operations.zig"),
        @embedFile("application/input_preparation_workflow.zig"),
        @embedFile("test_fixtures/reference-preflight.workflow.yaml"),
        @embedFile("test_fixtures/reference-ingestion.workflow.yaml"),
        spec_workflow,
    };
    for (absorbed) |id| for (sources) |source| try expectAbsent(source, id);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("composition/native_workflow_operations.zig"), "input_preparation.PrepareInputs") != null);
    try std.testing.expect(std.mem.indexOf(u8, spec_workflow, "use: prepare-inputs") != null);
}

test "configured path policy and resolution have distinct startup steps over one domain owner" {
    const startup = @embedFile("application/startup_routine.zig");
    try expectAbsent(startup, "validate_engine_path_policy.zig");
    try std.testing.expect(std.mem.indexOf(u8, startup, "bootstrap_root_derivation.zig") != null);
    for ([_][]const u8{
        "pub fn validateRootPaths(",
        "pub fn validateProviderPath(",
        "pub fn resolveRoots(",
        "pub fn resolveProviderPath(",
    }) |step| {
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(startup, step));
    }
    const derivation = @embedFile("domain/bootstrap_root_derivation.zig");
    for ([_][]const u8{ "pub fn normalizeRootPath(", "pub fn normalizeProviderPath(", "pub fn resolveRoot(", "pub fn resolveProviderPath(" }) |function| {
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(derivation, function));
    }
}

test "feature log paths have one opaque artifact authority and one sink consumer" {
    const artifacts = @import("domain/workflow_artifact_registry.zig");
    switch (@typeInfo(artifacts.WorkflowArtifactRegistry)) {
        .@"opaque" => {},
        else => return error.WorkflowArtifactRegistryMustBeOpaque,
    }
    const root_domain = @embedFile("domain/bootstrap_root_registry.zig");
    const artifact_domain = @embedFile("domain/workflow_artifact_registry.zig");
    const sink = @embedFile("adapters/filesystem/feature_log_sink.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(root_domain, "bindSpecsArtifactRegistry("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(artifact_domain, "bindSpecsArtifactRegistry("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(sink, "bindFeatureLogSinkAdapter"));
    try expectAbsent(root_domain, "physical_identity: ?roots.PhysicalDirectoryIdentity");
    try expectAbsent(sink, "createDirPathOpen");
    // Prior-run paths come only from the registry, one stream at a time, and
    // only the retention adapter and the prior-run tail adapter receive them (ADR 0026).
    const historical = @embedFile("adapters/filesystem/feature_log_historical_stream.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(historical, "bindHistoricalFeatureLogStream("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("adapters/filesystem/feature_log_historical_tail.zig"), "bindHistoricalFeatureLogStream("));
    try expectAbsent(sink, "bindHistoricalFeatureLogStream");
    try expectAbsent(@embedFile("adapters/filesystem/feature_log_history.zig"), "bindHistoricalFeatureLogStream");
}

test "feature log activation owns only registered target write authority" {
    const activation = @import("application/feature_logging_workflow.zig");
    const inspection = comptime @import("application/workflow_operation_binding.zig").inspect(activation.Activate, &.{});
    try std.testing.expect(inspection.valid and inspection.feature_logging);
    try std.testing.expect(!inspection.model_provider and !inspection.feature_output_write);
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "domain/bootstrap_root_registry.zig") or
            std.mem.eql(u8, entry.path, "domain/workflow_artifact_registry.zig") or
            std.mem.eql(u8, entry.path, "adapters/filesystem/feature_log_layout.zig") or
            std.mem.eql(u8, entry.path, "adapters/filesystem/workflow_output.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "bindFeatureOutputAdapter");
    }
    const adapter = @embedFile("adapters/filesystem/feature_log_layout.zig");
    try expectAbsent(adapter, "*const roots.BootstrapRootRegistry");
    try expectAbsent(adapter, "bindFeatureInputAdapter");
    try expectAbsent(@embedFile("application/feature_logging_workflow.zig"), "/adapters/");
}

const ApplicationViolation = enum { imports_an_adapter, uses_io, creates_a_directory };

/// ADR 0026, ADR 0032: an application module (the runtime logging lifecycle and the log service included) reaches the
/// filesystem only through ports its composition root supplies, so it imports no adapter, names no `std.Io` and creates
/// no directory. Read from code, not from comments.
fn applicationViolation(allocator: std.mem.Allocator, source: []const u8) !?ApplicationViolation {
    const code = try codeOf(allocator, source);
    defer allocator.free(code);
    if (std.mem.indexOf(u8, code, "/adapters/") != null) return .imports_an_adapter;
    if (std.mem.indexOf(u8, code, "std.Io") != null) return .uses_io;
    if (std.mem.indexOf(u8, code, "createDir") != null) return .creates_a_directory;
    return null;
}

test "no application module holds adapter or filesystem authority" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var application = try std.Io.Dir.cwd().openDir(io, "src/application", .{ .iterate = true });
    defer application.close(io);
    var walker = try application.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or std.mem.endsWith(u8, entry.basename, "_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(4 * 1024 * 1024));
        defer allocator.free(source);
        if (try applicationViolation(allocator, source)) |violation| {
            std.debug.print("application/{s}: {s}\n", .{ entry.path, @tagName(violation) });
            return error.ApplicationFilesystemAuthority;
        }
    }
}

test "application modules are held to no adapter, no std.Io and no directory creation" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(@as(?ApplicationViolation, null), try applicationViolation(allocator, "const port = @import(\"../ports/feature_log_sink.zig\");\n// std.Io and createDir in a comment\n"));
    try std.testing.expectEqual(@as(?ApplicationViolation, .imports_an_adapter), try applicationViolation(allocator, "const sink = @import(\"../adapters/filesystem/feature_log_sink.zig\");\n"));
    try std.testing.expectEqual(@as(?ApplicationViolation, .uses_io), try applicationViolation(allocator, "pub fn open(io: std.Io) void {}\n"));
    try std.testing.expectEqual(@as(?ApplicationViolation, .creates_a_directory), try applicationViolation(allocator, "fn prepare(dir: Dir) void { dir.createDirPath(); }\n"));
}

test "the active logger is installed by composition and the pipeline reaches it through the barrier" {
    const invocation_assembly = @embedFile("composition/engine_invocation.zig");
    try std.testing.expect(std.mem.indexOf(u8, invocation_assembly, "services.logs.barrier()") != null);
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "feature_log_lifecycle.Lifecycle");
    try expectAbsent(composition, "unbound_telemetry_barrier");
}

test "feature logging policy execution and filesystem operations have focused owners" {
    const port = @embedFile("ports/feature_log_sink.zig");
    try expectAbsent(port, "pub const Sink");
    try expectAbsent(port, "pub const VTable");

    // The logging runner is the run's typed state and ports and calls nothing: the runtime logging lifecycle runs the
    // routines on it (ADR 0032), so it declares no function and imports no routine. Reaching infrastructure only
    // through the ports a routine's step takes is the routine rules' and the runner glob rule's, which the sink, clock,
    // console and emergency import absences this test once held stood for.
    const runner = @embedFile("application/feature_log_runner.zig");
    try expectAbsent(runner, "fn ");
    try expectAbsent(runner, "_routine.zig");

    const domain_modules = [_][]const u8{
        @embedFile("domain/feature_log_binding.zig"),
        @embedFile("domain/feature_log_stream.zig"),
        @embedFile("domain/feature_log_retention.zig"),
        @embedFile("domain/log_event_registry.zig"),
        @embedFile("domain/log_policy.zig"),
        @embedFile("domain/sanitized_prompt_log.zig"),
    };
    for (domain_modules) |source| {
        try expectAbsent(source, "BarrierOutcome");
    }

    const adapter = @embedFile("adapters/filesystem/feature_log_sink.zig");
    try expectAbsent(adapter, ".iterate(");
    try expectAbsent(adapter, ".openFile(");
    try expectAbsent(adapter, ".createFile(");
    try expectAbsent(adapter, "validateEncodedRow");
    try expectAbsent(adapter, "allocRemaining");
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_lock.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_recovery.zig") != null);
    // Only the historical stream adapter prunes; the current run's sink cannot.
    try expectAbsent(adapter, "feature_log_retention_store.zig");
    try expectAbsent(adapter, "segmentPruner");
    try std.testing.expect(std.mem.indexOf(u8, adapter, "feature_log_segment_store.zig") != null);

    // Prior-run discovery only reads, through recovery's one segment validator.
    const discovery = @embedFile("adapters/filesystem/feature_log_history.zig");
    for ([_][]const u8{ "deleteFile", "createFile", "setLength", "writeFile", "deleteTree", ".read_write", ".truncate", "recovery.recover(", "feature_log_retention_store.zig", "feature_log_segment_store.zig", "feature_log_lock.zig" }) |forbidden| try expectAbsent(discovery, forbidden);
    try std.testing.expect(std.mem.indexOf(u8, discovery, "recovery.inspectGroup(") != null);
    try expectAbsent(discovery, "validatePersistedIdentityRow");
    try expectAbsent(discovery, "validatePersistedControlRow");
    // The historical stream offers lock, prune and release only.
    const historical = @embedFile("adapters/filesystem/feature_log_historical_stream.zig");
    for ([_][]const u8{ "feature_log_segment_store.zig", "segmentCreator", "segmentRotator", "streamCloser", "recordAppender", "streamRecoverer", "recovery.recover(", ".truncate" }) |forbidden| try expectAbsent(historical, forbidden);
    try std.testing.expect(std.mem.indexOf(u8, historical, "recovery.inspectGroup(") != null);
    try std.testing.expectEqual(@as(?[]const u8, null), try tailAdapterViolation(std.testing.allocator, @embedFile("adapters/filesystem/feature_log_historical_tail.zig")));

    const recovery = @embedFile("adapters/filesystem/feature_log_recovery.zig");
    try std.testing.expect(std.mem.indexOf(u8, recovery, "domain/feature_log_format.zig") != null);
    try expectAbsent(recovery, "fn cellAt");
    try expectAbsent(recovery, "fn parseUtc");
}

/// ADR 0026: the prior-run tail adapter closes the active tail a crash left. It reads the group, recovers the tail,
/// writes one trailer and holds the prior run's lock. It creates, rotates, appends and prunes nothing and deletes
/// nothing, so retention's adapter stays the only prior-run adapter that removes a file. Read from code, not comments;
/// the result is the first forbidden text the source holds, or the first required text it lacks.
fn tailAdapterViolation(allocator: std.mem.Allocator, source: []const u8) !?[]const u8 {
    const code = try codeOf(allocator, source);
    defer allocator.free(code);
    for ([_][]const u8{ "segmentCreator", "segmentRotator", "recordAppender", "segmentPruner", "feature_log_retention_store.zig", "segment_store.create(", "segment_store.rotate(", "segment_store.append(", "deleteFile", "deleteTree", "createFile", "createDir" }) |forbidden| {
        if (std.mem.indexOf(u8, code, forbidden) != null) return forbidden;
    }
    for ([_][]const u8{ "recovery.recover(", "recovery.inspectGroup(", "segment_store.close(", "lock.acquire(", "lock.release(" }) |required| {
        if (std.mem.indexOf(u8, code, required) == null) return required;
    }
    return null;
}

test "the prior-run tail adapter's capability accepts what closes a tail and rejects a create, rotate, append, prune or delete" {
    const allocator = std.testing.allocator;
    // Sources are Zig, so that comments are masked as in the real file.
    const holds = "pub const held = .{ recovery.recover(), recovery.inspectGroup(), segment_store.close(), lock.acquire(), lock.release() };\n";
    try std.testing.expectEqual(@as(?[]const u8, null), try tailAdapterViolation(allocator, holds));
    // A forbidden capability named only in a comment is no capability.
    try std.testing.expectEqual(@as(?[]const u8, null), try tailAdapterViolation(allocator, "// segment_store.append( deleteFile\n" ++ holds));
    for ([_][]const u8{ "segmentCreator", "segmentRotator", "recordAppender", "segmentPruner", "feature_log_retention_store.zig", "segment_store.create(", "segment_store.rotate(", "segment_store.append(", "deleteFile", "deleteTree", "createFile", "createDir" }) |forbidden| {
        const source = try std.fmt.allocPrint(allocator, "{s}pub const forbidden = \"{s}\";\n", .{ holds, forbidden });
        defer allocator.free(source);
        try std.testing.expectEqualStrings(forbidden, (try tailAdapterViolation(allocator, source)).?);
    }
    // An adapter that no longer closes, recovers, reads or locks is no tail adapter.
    try std.testing.expectEqualStrings("segment_store.close(", (try tailAdapterViolation(allocator, "pub const held = .{ recovery.recover(), recovery.inspectGroup(), lock.acquire(), lock.release() };\n")).?);
    try std.testing.expectEqualStrings("recovery.recover(", (try tailAdapterViolation(allocator, "pub const held = .{ recovery.inspectGroup(), segment_store.close(), lock.acquire(), lock.release() };\n")).?);
}

/// The orchestrations that coordinate runner-owned child bindings through a `*_child_bindings.zig` (AGENTS.md "Actions,
/// orchestrators, and runner"). Feature logging is no longer one: its sequences are ADR 0032 routines, so a logging
/// child-bindings file is a regression, and a new orchestration adds its name here with its own change.
const child_bindings_files = [_][]const u8{
    "workflow_engine_child_bindings.zig",
    "model_request_child_bindings.zig",
    "specify_invocation_child_bindings.zig",
    "workflow_pipeline_child_bindings.zig",
};

fn isUnlistedChildBindings(basename: []const u8) bool {
    if (!std.mem.endsWith(u8, basename, "_child_bindings.zig")) return false;
    for (child_bindings_files) |listed| if (std.mem.eql(u8, basename, listed)) return false;
    return true;
}

test "only the four listed orchestrations carry a child-bindings file, and feature logging carries none" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    var seen: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (isUnlistedChildBindings(entry.basename)) {
            std.debug.print("unlisted child bindings: {s}\n", .{entry.path});
            return error.UnlistedChildBindings;
        }
        if (std.mem.endsWith(u8, entry.basename, "_child_bindings.zig")) seen += 1;
    }
    // A row for a file that no longer exists is stale.
    try std.testing.expectEqual(child_bindings_files.len, seen);
}

test "child-bindings files are held to the listed orchestrations" {
    try std.testing.expect(!isUnlistedChildBindings("workflow_pipeline_child_bindings.zig"));
    try std.testing.expect(!isUnlistedChildBindings("feature_log_runner.zig"));
    try std.testing.expect(isUnlistedChildBindings("feature_log_child_bindings.zig"));
    try std.testing.expect(isUnlistedChildBindings("feature_log_retention_child_bindings.zig"));
    try std.testing.expect(isUnlistedChildBindings("another_child_bindings.zig"));
}

test "workflow engine selection is workflow-name agnostic while composition binds focused runners" {
    const composition = @embedFile("composition/root.zig");
    try expectAbsent(composition, "parse_workflow_invocation.zig");
    try expectAbsent(composition, "select_compiled_workflow.zig");
    const orchestrator = @embedFile("application/workflow_engine_orchestrator.zig");
    inline for (.{ "\"specify\"", "\"implement\"" }) |name| {
        try expectAbsent(orchestrator, name);
        try expectAbsent(@embedFile("application/workflow_pipeline_runner.zig"), name);
    }
    try std.testing.expect(std.mem.indexOf(u8, orchestrator, "invokeParseInvocation()") != null);
    try std.testing.expect(std.mem.indexOf(u8, orchestrator, "invokeSelectWorkflow()") != null);
    const selection_runner = @embedFile("application/workflow_selection_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, selection_runner, "parse_workflow_invocation.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, selection_runner, "select_compiled_workflow.zig") != null);
}

test "active feature logging concrete assembly remains in composition" {
    const assembly = @embedFile("composition/active_feature_log_runtime.zig");
    try std.testing.expect(std.mem.indexOf(u8, assembly, "adapters/filesystem/feature_log_sink.zig") != null);
}

test "workflow values have one runner-owned store and no key-only candidate API" {
    const pipeline = @import("domain/pipeline.zig");
    const data = @import("domain/pipeline_data.zig");
    try std.testing.expect(!@hasDecl(pipeline.NodeDelta, "successful"));
    try std.testing.expect(@FieldType(pipeline.NodeDelta, "data_writes") == data.Slots);
    try std.testing.expect(@FieldType(pipeline.NodeDelta, "data_replacements") == data.Slots);
    const runner = @embedFile("application/workflow_pipeline_runner.zig");
    try std.testing.expect(std.mem.indexOf(u8, runner, "self.envelope.view(") != null);
    try std.testing.expectEqual(@as(usize, 2), countOccurrences(runner, "defer self.envelope.discard(&candidate.delta)"));
    const envelope = @embedFile("application/pipeline_envelope.zig");
    try expectAbsent(envelope, "@ptrCast");
    try expectAbsent(envelope, "/adapters/");
    try expectAbsent(@embedFile("domain/pipeline_data.zig"), "@ptrCast");
}

test "workflow operation capabilities have one typed binding authority" {
    const operations = @import("ports/workflow_operation_registry.zig");
    try std.testing.expect(!@hasField(@import("domain/workflow_operation.zig").Contract, "capabilities"));
    try std.testing.expect(!@hasField(operations.Registry, "capabilities"));
    try std.testing.expect(!@hasField(operations.Entry, "invoke_fn"));
    try std.testing.expect(!@hasField(operations.Entry, "context"));
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "application/workflow_operation_binding.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        defer allocator.free(source);
        try expectAbsent(source, ".implementation =");
    }
}

test "toolchain setup has no unconditional startup path or second result owner" {
    try std.testing.expect(!@hasField(@import("application/bootstrap_services.zig").BootstrapServices, "toolchain"));
    try expectAbsent(@embedFile("application/startup_routine.zig"), "Toolchain");
    try expectAbsent(@embedFile("application/startup_routine.zig"), "prepare_toolchain");
    const bindings = @embedFile("application/toolchain_workflow_runner.zig");
    try expectAbsent(bindings, "successor");
    try expectAbsent(bindings, "bootstrap_root_registry");
    try std.testing.expect(std.mem.indexOf(u8, bindings, "values.adopt(") != null);
}

test "reference preflight shares path safety without leaking normalization or read capabilities" {
    inline for (.{ @embedFile("application/input_preparation_workflow.zig"), @embedFile("actions/specify/prepare_inputs.zig") }) |actions| {
        try expectAbsent(actions, "std.Io.Dir");
        try expectAbsent(actions, "/adapters/");
        try expectAbsent(actions, "bootstrap_root_registry");
    }
    const selector = @embedFile("domain/reference_selector.zig");
    try expectAbsent(selector, "@cImport");
    try expectAbsent(selector, "/adapters/");
    try std.testing.expect(std.mem.indexOf(u8, selector, "path.validate") != null);
    const shared = @embedFile("domain/relative_directory_path.zig");
    try std.testing.expect(std.mem.indexOf(u8, shared, "policy.validateComponent") != null);
    try std.testing.expect(std.mem.indexOf(u8, shared, "policy.hasEncodedDotOrSeparator") != null);
    const filesystem = @embedFile("adapters/filesystem/reference_directory_inspector.zig");
    try std.testing.expect(std.mem.indexOf(u8, filesystem, "bindReferenceSourcesAdapter") != null);
    try std.testing.expect(std.mem.indexOf(u8, filesystem, "directories.open") != null);
    try expectAbsent(filesystem, "createDir");
    try expectAbsent(filesystem, "writeFile");
    const engine = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(engine, "specify");
    try expectAbsent(engine, "reference");
}

test "reference root path handoff has one authorized adapter consumer" {
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "domain/bootstrap_root_registry.zig") or
            std.mem.eql(u8, entry.path, "adapters/filesystem/reference_directory_inspector.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "bindReferenceSourcesAdapter");
    }
}

test "the request stage gate is set only by the E2E harness trace and owned only by the runner" {
    // The gate lets a caller stop a `request-model` step before a stage with one of two typed stops.
    // Nothing else in production code may name it, and in the harness only `Trace` sets it.
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.endsWith(u8, entry.basename, "_test.zig") or
            std.mem.startsWith(u8, entry.path, "test_fixtures/") or
            std.mem.eql(u8, entry.path, "application/workflow_pipeline_runner.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(4 * 1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "request_stage_gate");
        try expectAbsent(source, "StageGate");
    }
    var harness = try std.Io.Dir.cwd().openDir(io, "test", .{ .iterate = true });
    defer harness.close(io);
    var harness_walker = try harness.walk(std.testing.allocator);
    defer harness_walker.deinit();
    while (try harness_walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "harness/e2e/trace.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(4 * 1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "request_stage_gate");
    }
}

test "feature directory selection shares path policy and has no generated identity authority" {
    const domain = @embedFile("domain/feature_identity.zig");
    try expectAbsent(domain, "@cImport");
    try expectAbsent(domain, "/adapters/");
    try std.testing.expect(std.mem.indexOf(u8, domain, "path.validate") != null);
    const action = @embedFile("actions/specify/prepare_inputs.zig");
    try expectAbsent(action, "std.Io.Dir");
    try expectAbsent(action, "/adapters/");
    try expectAbsent(action, "model_provider");
    try std.testing.expect(std.mem.indexOf(u8, action, "normalizer.nfc") != null);
    const runner = @embedFile("application/feature_directory_workflow.zig");
    try expectAbsent(runner, "std.Io.Dir");
    try expectAbsent(runner, "/adapters/");
    const engine = @embedFile("application/workflow_engine_orchestrator.zig");
    try expectAbsent(engine, "feature_identity");
    try expectAbsent(engine, "feature_directory");
    const filesystem = @embedFile("adapters/filesystem/feature_directory_inspector.zig");
    try std.testing.expect(std.mem.indexOf(u8, filesystem, "bindFeatureDirectoryAdapter") != null);
    try std.testing.expect(std.mem.indexOf(u8, filesystem, "directories.open") != null);
    try expectAbsent(filesystem, "createDir");
    try expectAbsent(filesystem, "writeFile");
}

test "feature inspection root handoff has one narrow consumer and cannot mix configured roots" {
    try std.testing.expectEqual(.filesystem_read, @import("actions/specify/prepare_inputs.zig").Action.contract.side_effect);
    const roots = @import("domain/bootstrap_root_registry.zig");
    const inspector = @import("ports/feature_directory_inspector.zig").Inspector;
    try std.testing.expect(@FieldType(inspector, "capability") == ?*const roots.FeatureDirectoryReadCapability);
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "domain/bootstrap_root_registry.zig") or
            std.mem.eql(u8, entry.path, "adapters/filesystem/feature_directory_inspector.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "bindFeatureDirectoryAdapter");
    }
}

test "clarification input operations have narrow read-only ports and no workflow-name authority" {
    const binding = @import("application/workflow_operation_binding.zig");
    const inputs = comptime binding.inspect(@import("application/input_preparation_workflow.zig").PrepareInputs, &.{});
    // Reads the feature's inputs through the narrow input port, with no model or output capability.
    try std.testing.expect(inputs.valid and inputs.feature_input_read);
    try std.testing.expectEqual(.filesystem_read, @import("actions/specify/prepare_inputs.zig").Action.contract.side_effect);
    try std.testing.expect(!inputs.model_provider and !inputs.feature_output_write and !inputs.toolchain_read);
    inline for (.{
        @embedFile("actions/specify/prepare_inputs.zig"),
        @embedFile("application/clarification_input_workflow.zig"),
        @embedFile("application/input_preparation_workflow.zig"),
    }) |source| {
        try expectAbsent(source, "std.Io.Dir");
        try expectAbsent(source, "std.json");
        try expectAbsent(source, "/adapters/");
    }
    const source = @embedFile("adapters/filesystem/feature_input_source.zig");
    try expectAbsent(source, "writeFile");
    try expectAbsent(source, "createDir");
    try expectAbsent(source, "delete");
    try std.testing.expect(std.mem.indexOf(u8, source, "directories.openObserved") != null);
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "clarification");
}

test "feature input filesystem handoff has exactly one authorized consumer" {
    const port = @import("ports/feature_input_source.zig").Capturer;
    try std.testing.expect(@FieldType(port, "capability") == ?*const @import("domain/bootstrap_root_registry.zig").FeatureInputReadCapability);
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "domain/bootstrap_root_registry.zig") or
            std.mem.eql(u8, entry.path, "adapters/filesystem/feature_input_source.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "bindFeatureInputAdapter");
    }
}

test "reference evidence has shared identity types and pure chunk citation boundaries" {
    const evidence = @import("domain/reference_evidence.zig");
    const model = @import("domain/model_request_identity.zig");
    try std.testing.expect(model.ReferenceStateId == evidence.identity.StateId);
    try std.testing.expect(model.ReferenceChunkId == evidence.identity.ChunkId);
    const binding = @import("application/workflow_operation_binding.zig");
    // The stage reads the reference content and draws identities, and nothing else.
    const preparing = comptime binding.inspect(@import("application/reference_evidence_preparation_workflow.zig").PrepareReferenceEvidence, &.{});
    try std.testing.expect(preparing.valid and preparing.reference_identity and preparing.reference_content_read);
    try std.testing.expect(!preparing.reference_read and !preparing.model_provider and !preparing.feature_input_read and !preparing.feature_output_write);
    inline for (.{
        @embedFile("domain/reference_evidence.zig"),
        @embedFile("actions/reference/prepare_reference_evidence.zig"),
        @embedFile("application/reference_evidence_workflow.zig"),
    }) |source| {
        try expectAbsent(source, "std.Io");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "std.json");
    }
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "reference_evidence");
    try std.testing.expect(!@hasField(evidence.CitationProposal, "state_id"));
    try std.testing.expect(!@hasField(evidence.CitationProposal, "chunk_id"));
    try std.testing.expect(!@hasField(evidence.CitationProposal, "citation_id"));
}

test "extraction candidates reuse citation and identity owners without gaining capabilities" {
    const extraction = @import("domain/reference_extraction.zig");
    const identity = @import("domain/reference_identity.zig");
    const operations = @import("application/reference_extraction_workflow.zig");
    const binding = @import("application/workflow_operation_binding.zig");
    try std.testing.expect(extraction.ClaimId == identity.ClaimId);
    try std.testing.expect(extraction.CitationId == identity.CitationId);
    inline for (.{ operations.Parse, operations.ValidateTokenClassifications, operations.Validate, operations.Assign, operations.Build, operations.Account }) |T| {
        try std.testing.expectEqual(binding.Inspection{}, comptime binding.inspect(T, &.{}));
        try std.testing.expectEqual(@as(usize, 0), @typeInfo(T.Action).@"struct".fields.len);
        try std.testing.expect(T.Action.contract.side_effect == .none);
    }
    for (operations.schemas) |schema| try std.testing.expect(schema.maximum_bytes == null);
    try std.testing.expect(@FieldType(extraction.Proposal, "citations") == []const @import("domain/source_selections.zig").Id);
    // ADR 0036: a model proposal carries no wording; it is quoted from the cited lines.
    for ([_][]const u8{ "state_id", "chunk_id", "claim_id", "citation_id", "disposition", "content" }) |field| {
        inline for (@typeInfo(extraction.Proposal).@"struct".fields) |proposal_field| try std.testing.expect(!std.mem.eql(u8, field, proposal_field.name));
    }
    inline for (.{@embedFile("actions/reference/validate_reference_claims.zig")}) |source| {
        try std.testing.expect(std.mem.indexOf(u8, source, "domain/source_citations.zig") != null);
        try expectAbsent(source, "reference.advance");
    }
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "reference_extraction");
}

test "path-token rules share toolchain authority and their bindings are capability free" {
    const bindings = @import("application/workflow_operation_binding.zig");
    const operations = @import("application/path_token_workflow.zig");
    inline for (.{ operations.Compile, @import("application/reference_token_preparation_workflow.zig").PrepareReferenceTokens }) |T| {
        try std.testing.expectEqual(bindings.Inspection{}, comptime bindings.inspect(T, &.{}));
        try std.testing.expect(T.Action.contract.side_effect == .none);
    }
    const policy = @import("domain/toolchain.zig").PolicyContract;
    try std.testing.expect(@FieldType(policy, "naming") == []const @import("domain/naming_rule.zig").Rule);
    const scanner = @embedFile("domain/path_token_scan.zig");
    try expectAbsent(scanner, "\".zig\""); // No extension allowlist belongs in the scanner.
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "path_token");
    inline for (.{ @embedFile("domain/path_token_grammar.zig"), scanner, @embedFile("domain/naming_rule.zig"), @embedFile("domain/naming_policy.zig") }) |source| {
        try expectAbsent(source, "std.Io.Dir");
        try expectAbsent(source, "/adapters/");
        try expectAbsent(source, "readFile");
    }
}

test "typed content has one shared boundary and no passive or exact operational capability" {
    const binding = @import("application/workflow_operation_binding.zig");
    const operations = @import("application/reference_token_preparation_workflow.zig");
    const extraction = @import("application/reference_extraction_workflow.zig");
    inline for (.{ operations.PrepareReferenceTokens, extraction.ValidateText }) |T| {
        try std.testing.expectEqual(binding.Inspection{}, comptime binding.inspect(T, &.{}));
        try std.testing.expect(T.Action.contract.side_effect == .none);
    }
    try std.testing.expect(extraction.text_schema.maximum_bytes == null);
    const text = @import("domain/typed_text.zig");
    try std.testing.expect(!@hasField(text.BusinessSegment, "source"));
    try std.testing.expect(!@hasField(text.BusinessSegment, "file"));
    try std.testing.expect(!@hasField(text.ReferenceNode, "file"));
    try std.testing.expect(!@hasField(text.PassiveReference, "value"));
    try expectAbsent(@embedFile("domain/typed_text.zig"), "hasEncodedDotOrSeparator");
    try expectAbsent(@embedFile("domain/typed_text.zig"), "path_token_scan.zig");
    try std.testing.expect(@hasField(text.BusinessSegment, "exact_copy"));
    try std.testing.expect(!@hasField(text.ExactCopy, "value"));
    try std.testing.expect(!@hasField(text.ExactCopy, "path"));
    try std.testing.expect(!@hasField(text.ExactCopy, "operation"));
    try expectAbsent(@embedFile("actions/reference/validate_reference_claims.zig"), "nonempty");
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "passive_literal");
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{ .citable_reference_inputs, .prepared_reference_claims }, extraction.Validate.Action.contract.requires);
}

test "preservation is a generic YAML boundary with source-only scalars and mandatory accounting" {
    const native = @import("application/structured_token_workflow.zig");
    const selection = @import("application/reference_extraction_workflow.zig").ValidateTokenClassifications;
    const binding = @import("application/workflow_operation_binding.zig");
    const key = @import("domain/pipeline.zig").DataKey;
    inline for (.{ @import("application/reference_token_preparation_workflow.zig").PrepareReferenceTokens, selection, native.AssignTokens, native.BuildClaims }) |T| {
        try std.testing.expectEqual(binding.Inspection{}, comptime binding.inspect(T, &.{}));
        try std.testing.expectEqual(.none, T.Action.contract.side_effect);
    }
    try std.testing.expectEqualSlices(key, &.{ .citable_reference_inputs, .structured_token_candidates, .text_validated_reference_extraction }, selection.Action.contract.requires);
    try std.testing.expectEqualSlices(key, &.{.preserved_token_identities}, native.BuildClaims.Action.contract.requires);
    try std.testing.expectEqualSlices(key, &.{ .citable_reference_inputs, .preserved_token_identities, .reference_extraction_ledger }, @import("actions/reference/validate_reference_extraction_accounting.zig").Action.contract.requires);
    try std.testing.expect(@import("application/reference_extraction_workflow.zig").classifications_schema.maximum_bytes == null);
    const classification = @import("domain/structured_tokens.zig").Classification;
    try std.testing.expect(!@hasField(@FieldType(classification, "preserve"), "raw_value"));
    try std.testing.expect(!@hasField(@FieldType(classification, "preserve"), "citation_id"));
    try expectAbsent(@embedFile("domain/reference_extraction_parser.zig"), "[0]struct {}");
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "structured_token");
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("domain/structured_tokens.zig"), "markdown_code_spans.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, @embedFile("adapters/parsers/markdown_reference.zig"), "markdown_code_spans.zig") != null);
}

test "reconciliation is YAML visible capability free and preserves closed candidate authority" {
    const native = @import("application/reference_reconciliation_workflow.zig");
    const binding = @import("application/workflow_operation_binding.zig");
    const r = @import("domain/reference_reconciliation.zig");
    inline for (.{ native.BuildItems, native.Partition, native.AssignPartitions, native.ValidatePartitions, native.BuildInput, native.Parse, native.ValidateSummary, native.AssignSummary, native.BuildSummary, native.ValidateDispositions, native.ValidateSignals, native.ValidateConflicts, native.AssignRecords, native.BuildRecords, native.Account }) |T| {
        try std.testing.expectEqual(binding.Inspection{}, comptime binding.inspect(T, &.{}));
        try std.testing.expectEqual(.none, T.Action.contract.side_effect);
    }
    for (native.schemas) |schema| try std.testing.expect(schema.maximum_bytes == null);
    try std.testing.expectEqual(@as(i64, 2), native.Partition.parameters[0].integer_min);
    try std.testing.expect(native.Partition.parameters[0].required);
    try std.testing.expect(!@hasField(r.ConflictProposal, "resolution"));
    try std.testing.expect(!@hasField(r.SignalProposal, "id"));
    try std.testing.expect(!@hasField(r.ConflictProposal, "id"));
    try std.testing.expect(!@hasField(r.SummaryProposal, "partition_id"));
    try std.testing.expect(@FieldType(r.ContentProposal, "model") == @import("domain/reference_extraction.zig").ProposalContent);
    try std.testing.expect(@FieldType(r.Item, "claim") == @import("domain/reference_extraction.zig").Claim);
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.answered_reference_reconciliation_records}, native.Account.Action.contract.requires);
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "reconciliation");
    try expectAbsent(@embedFile("domain/reference_reconciliation.zig"), "precedenceRule");
}

test "required authority has capability-free registered bindings and no model continuation authority" {
    const native = @import("application/required_authority_workflow.zig");
    const binding = @import("application/workflow_operation_binding.zig");
    const authority = @import("domain/required_authority.zig");
    inline for (.{ native.ProjectSpecification, native.Build, native.Reconcile, native.Validate }) |T| {
        try std.testing.expectEqual(binding.Inspection{}, comptime binding.inspect(T, &.{}));
        try std.testing.expectEqual(.none, T.Action.contract.side_effect);
    }
    try std.testing.expectEqual(@import("domain/clarification_inputs.zig").Stage, authority.Stage);
    // Post-generation review is removed: no outcome records advisory assessment.
    try std.testing.expect(!@hasField(authority.Outcome, "assessment_complete"));
    try std.testing.expect(!@hasField(authority.Outcome, "assessment_incomplete"));
    try std.testing.expect(!@hasField(authority.Observation, "outcome"));
    try std.testing.expect(!@hasField(authority.Observation, "owner"));
    try std.testing.expect(!@hasField(authority.Observation, "score"));
    try expectAbsent(@embedFile("application/workflow_engine_orchestrator.zig"), "required_authority");
}

test "feature document filenames and headings agree" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var features = try std.Io.Dir.cwd().openDir(io, "design/features", .{ .iterate = true });
    defer features.close(io);

    var iterator = features.iterate();
    while (try iterator.next(io)) |entry| {
        if (entry.kind != .file or
            !std.mem.startsWith(u8, entry.name, "F") or
            !std.mem.endsWith(u8, entry.name, ".md"))
        {
            continue;
        }

        const source = try features.readFileAlloc(
            io,
            entry.name,
            allocator,
            .limited(1024 * 1024),
        );
        defer allocator.free(source);
        const heading_end = std.mem.indexOfScalar(u8, source, '\n') orelse source.len;
        const heading = std.mem.trimEnd(u8, source[0..heading_end], "\r");
        const stem = entry.name[0 .. entry.name.len - ".md".len];
        const separator = std.mem.indexOfScalar(u8, stem, '-') orelse {
            return error.InvalidFeatureDocumentName;
        };
        try std.testing.expect(std.mem.startsWith(u8, heading, "# "));
        const heading_body = heading[2..];
        const heading_separator = std.mem.indexOf(u8, heading_body, " — ") orelse {
            return error.InvalidFeatureDocumentHeading;
        };
        try std.testing.expectEqualStrings(stem[0..separator], heading_body[0..heading_separator]);
        try std.testing.expectEqualStrings(stem[separator + 1 ..], heading_body[heading_separator + " — ".len ..]);
    }
}

/// The source with every comment overwritten by spaces, so a rule about code never reads a comment: a comment that
/// names a forbidden word changes no boundary. Strings stay, because an import path or a literal is code. A source
/// that is not Zig (a heading, a document) has no comments to mask and is judged as it is.
fn codeOf(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    const terminated = try allocator.dupeZ(u8, source);
    defer allocator.free(terminated);
    var ast = try std.zig.Ast.parse(allocator, terminated, .zig);
    defer ast.deinit(allocator);
    const masked = try allocator.dupe(u8, source);
    errdefer allocator.free(masked);
    if (ast.errors.len != 0) return masked;
    var tokens = std.zig.Tokenizer.init(terminated);
    var gap_start: usize = 0;
    while (true) {
        const token = tokens.next();
        blankLineComments(masked, gap_start, token.loc.start);
        switch (token.tag) {
            .doc_comment, .container_doc_comment => @memset(masked[token.loc.start..token.loc.end], ' '),
            else => {},
        }
        if (token.tag == .eof) return masked;
        gap_start = token.loc.end;
    }
}

/// Between two tokens there is only white space and `//` comments, so a `//` there starts a comment.
fn blankLineComments(masked: []u8, start: usize, end: usize) void {
    var index = start;
    while (index + 1 < end) : (index += 1) {
        if (masked[index] != '/' or masked[index + 1] != '/') continue;
        while (index < end and masked[index] != '\n') : (index += 1) masked[index] = ' ';
    }
}

fn expectAbsent(source: []const u8, forbidden: []const u8) !void {
    const code = try codeOf(std.testing.allocator, source);
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, forbidden) == null);
}

/// The path of every `@import` in a Zig source, read from its tokens, so a comment or a string that spells an import
/// is not one. The caller owns the result (an arena is the usual owner).
fn importsOf(allocator: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    const terminated = try allocator.dupeZ(u8, source);
    defer allocator.free(terminated);
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer paths.deinit(allocator);
    var tokens = std.zig.Tokenizer.init(terminated);
    while (true) {
        const token = tokens.next();
        if (token.tag == .eof) break;
        if (token.tag != .builtin or !std.mem.eql(u8, terminated[token.loc.start..token.loc.end], "@import")) continue;
        if (tokens.next().tag != .l_paren) continue;
        const literal = tokens.next();
        if (literal.tag != .string_literal) continue;
        const text = terminated[literal.loc.start..literal.loc.end];
        try paths.append(allocator, try allocator.dupe(u8, text[1 .. text.len - 1]));
    }
    return paths.toOwnedSlice(allocator);
}

fn expectAllowedActionImports(source: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try importsOf(arena.allocator(), source)) |path| {
        try std.testing.expect(
            std.mem.eql(u8, path, "std") or
                std.mem.eql(u8, path, "builtin") or
                std.mem.startsWith(u8, path, "../../domain/") or
                std.mem.startsWith(u8, path, "../../ports/"),
        );
    }
}

fn expectImportsOnly(source: []const u8, allowed: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    for (try importsOf(arena.allocator(), source)) |path| {
        for (allowed) |candidate| {
            if (std.mem.eql(u8, candidate, path)) break;
        } else {
            std.debug.print("import not allowed: {s}\n", .{path});
            return error.TestUnexpectedResult;
        }
    }
}

/// The first import of the source whose path holds one of the fragments (`/adapters/`, `../actions/`), or null.
fn importHolding(allocator: std.mem.Allocator, source: []const u8, fragments: []const []const u8) !?[]const u8 {
    for (try importsOf(allocator, source)) |path| {
        for (fragments) |fragment| if (std.mem.indexOf(u8, path, fragment) != null) return path;
    }
    return null;
}

/// The first import of the source that names one of the files, whatever directory it is reached through, or null.
fn importOfFile(allocator: std.mem.Allocator, source: []const u8, files: []const []const u8) !?[]const u8 {
    for (try importsOf(allocator, source)) |path| {
        for (files) |file| if (std.mem.eql(u8, std.fs.path.basename(path), file)) return path;
    }
    return null;
}

/// No import of the source names a path that holds one of the fragments.
fn expectNoImportPathHolding(source: []const u8, fragments: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    if (try importHolding(arena.allocator(), source, fragments)) |path| {
        std.debug.print("import {s} crosses a layer\n", .{path});
        return error.TestUnexpectedResult;
    }
}

/// No import of the source names one of the files.
fn expectNoImportOfFile(source: []const u8, files: []const []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    if (try importOfFile(arena.allocator(), source, files)) |path| {
        std.debug.print("import {s} reaches a module this file must not depend on\n", .{path});
        return error.TestUnexpectedResult;
    }
}

test "a comment never trips a rule about code, and an import is read from its tokens" {
    // Rejected: the word in code, in a string, or in an import.
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const plan = 1;", "plan"));
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const text = \"hard limit\";", "hard"));
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("const x = @import(\"../adapters/file.zig\");", "/adapters/"));
    // Accepted: the word only in a line comment, a doc comment or a container doc comment.
    try expectAbsent("// the plan is hard\nconst a = 1;\n", "plan");
    try expectAbsent("/// hard reference\nconst a = 1; // plan\n", "hard");
    try expectAbsent("//! reference\nconst a = 1;\n", "reference");
    // Text that is not Zig is judged as it is: a URL's slashes start no comment there.
    try std.testing.expectError(error.TestUnexpectedResult, expectAbsent("see https://x.example/plan for the plan", "plan"));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const imports = try importsOf(arena.allocator(), "// @import(\"../adapters/a.zig\")\nconst s = \"@import(\\\"b.zig\\\")\";\nconst c = @import(\"../ports/c.zig\");\n");
    try std.testing.expectEqual(@as(usize, 1), imports.len);
    try std.testing.expectEqualStrings("../ports/c.zig", imports[0]);
    try std.testing.expect(try importHolding(arena.allocator(), "const c = @import(\"../ports/c.zig\");", &.{ "/adapters/", "/actions/" }) == null);
    try std.testing.expectEqualStrings("../adapters/c.zig", (try importHolding(arena.allocator(), "const c = @import(\"../adapters/c.zig\");", &.{"/adapters/"})).?);
    try std.testing.expect(try importOfFile(arena.allocator(), "const c = @import(\"a/specification.zig\");", &.{"required_authority.zig"}) == null);
    try std.testing.expectEqualStrings("../domain/required_authority.zig", (try importOfFile(arena.allocator(), "const c = @import(\"../domain/required_authority.zig\");", &.{"required_authority.zig"})).?);
}

fn expectSingleActionContract(source: []const u8) !void {
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub const Action = struct"));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "pub const contract: pipeline.NodeContract"));
}

fn countOccurrences(source: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var remaining = source;
    while (std.mem.indexOf(u8, remaining, needle)) |index| {
        count += 1;
        remaining = remaining[index + needle.len ..];
    }
    return count;
}

/// The occurrences of `needle` that are calls, not definitions: a `fn ` before it makes it the definition.
fn callCount(source: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, source, from, needle)) |at| : (from = at + needle.len) {
        if (at >= 3 and std.mem.eql(u8, source[at - 3 .. at], "fn ")) continue;
        count += 1;
    }
    return count;
}

const EmergencySites = struct { path: []const u8, writers: usize, reporters: usize };

/// ADR 0032 and F0002: the emergency line is written exactly once per logging failure, and only by a fixed set of
/// sites. A writer runs the failure routine (`failure_routine.run(`); a reporter calls `reportFailure` or
/// `invokeReportFailure`, which reach a writer through the active logger. The table is every non-test source file
/// with a site; a file not in it has none: the runtime logging lifecycle and composition's `Assembly.fail` are the two
/// writers, and a site in a new file, or a second writer, fails it.
const emergency_sites = [_]EmergencySites{
    .{ .path = "application/feature_log_runtime_lifecycle.zig", .writers = 1, .reporters = 0 },
    .{ .path = "application/log_service.zig", .writers = 0, .reporters = 1 },
    .{ .path = "application/model_exchange_capture.zig", .writers = 0, .reporters = 1 },
    .{ .path = "composition/feature_logging_runtime.zig", .writers = 1, .reporters = 1 },
};

test "call counting counts a call and skips a definition" {
    try std.testing.expectEqual(@as(usize, 1), callCount("pub fn invokeReportFailure(a: u8) void {}\nx.invokeReportFailure(a);\n", "invokeReportFailure("));
    try std.testing.expectEqual(@as(usize, 2), callCount("a.reportFailure(x);\nb.reportFailure(y);\n", ".reportFailure("));
    try std.testing.expectEqual(@as(usize, 0), callCount("pub fn reportFailure(x: u8) void {}\n", "reportFailure("));
}

test "the emergency line has a fixed set of writer and reporter sites" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(allocator);
    defer walker.deinit();
    var seen: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.endsWith(u8, entry.basename, "_test.zig") or
            std.mem.endsWith(u8, entry.basename, "_test_fixture.zig") or
            std.mem.eql(u8, entry.basename, "runtime_tests.zig") or
            std.mem.startsWith(u8, entry.path, "test_fixtures/")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, allocator, .limited(1024 * 1024));
        const code = try codeOf(allocator, source);
        const writers = callCount(code, "failure_routine.run(");
        const reporters = callCount(code, ".reportFailure(") + callCount(code, "invokeReportFailure(");
        var expected_writers: usize = 0;
        var expected_reporters: usize = 0;
        for (emergency_sites) |site| if (std.mem.eql(u8, site.path, entry.path)) {
            expected_writers = site.writers;
            expected_reporters = site.reporters;
            seen += 1;
        };
        if (writers != expected_writers or reporters != expected_reporters) {
            std.debug.print("emergency sites in {s}: {d} writers and {d} reporters, expected {d} and {d}\n", .{ entry.path, writers, reporters, expected_writers, expected_reporters });
            return error.UnexpectedEmergencySites;
        }
    }
    // A row for a file that no longer exists is stale.
    try std.testing.expectEqual(emergency_sites.len, seen);
}

test "candidate repairs share authority and expose only native scoped operations" {
    const binding = @import("application/workflow_operation_binding.zig");
    const tokens = @import("application/reference_extraction_repair_workflow.zig");
    const spec = @import("application/specification_repair_workflow.zig");
    const lexical = @import("application/reference_text_repair_workflow.zig");
    const reconciliation = @import("application/reference_reconciliation_repair_workflow.zig");
    const support = @import("application/specification_support_repair_workflow.zig");
    const source_omission = @import("application/source_omission_repair_workflow.zig");
    inline for (.{ tokens.Authorize, tokens.BuildInput, tokens.Parse, tokens.Merge, spec.Authorize, spec.BuildInput, spec.Parse, spec.Merge, lexical.Authorize, lexical.BuildInput, lexical.Parse, lexical.Merge, reconciliation.Authorize(.summary), reconciliation.Authorize(.dispositions), reconciliation.Authorize(.signals), reconciliation.Authorize(.conflicts), reconciliation.BuildInput, reconciliation.Parse, reconciliation.Merge, support.Authorize, support.BuildInput, support.Parse, support.Merge, source_omission.Authorize, source_omission.BuildInput, source_omission.Parse, source_omission.Merge(.extraction), source_omission.Merge(.reconciliation) }) |T| {
        try std.testing.expectEqual(binding.Inspection{}, comptime binding.inspect(T, &.{}));
        // An owner's step is capability-free and carries its data effects once, in its own binding.
        try std.testing.expect(@TypeOf(T.effects) == @import("domain/repair_owner.zig").Effects);
    }
    // No owner's repair step has a side effect: every variant of the four generic operations says so.
    const generic = @import("application/repair_workflow.zig");
    inline for (.{ generic.AuthorizeRepair, generic.BuildRepairInput, generic.ParseRepair, generic.MergeRepair }) |G| {
        try std.testing.expectEqual(binding.Inspection{}, comptime binding.inspect(G, &.{}));
        for (G.contract.variants) |variant| try std.testing.expectEqual(@import("domain/pipeline.zig").SideEffect.none, variant.side_effect);
    }
    inline for (.{ source_omission.Authorize, source_omission.BuildInput, source_omission.Merge(.extraction), source_omission.Merge(.reconciliation) }) |T| {
        try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &@import("domain/specification_generation_phase.zig").optional, T.effects.optional);
    }
    inline for (.{ @embedFile("domain/reference_extraction_repair.zig"), @embedFile("domain/specification_repair.zig"), @embedFile("domain/reference_extraction_text_repair.zig"), @embedFile("domain/reference_reconciliation_repair.zig"), @embedFile("domain/specification_support_repair.zig") }) |source| {
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "atomic_repair.zig"));
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "atomic.checkMerge("));
        try expectAbsent(source, "candidate.revision + 1");
        try expectAbsent(source, "retry_limit");
    }
    // Dependency capture cannot silently become a lossy request projection.
    const specification_facts = @embedFile("domain/specification_candidate_context.zig");
    try expectAbsent(specification_facts, "session.packet");
    try expectAbsent(specification_facts, "input: []const u8");
    inline for (.{ specification_facts, @embedFile("domain/reference_extraction_context.zig"), @embedFile("domain/reference_reconciliation_context.zig") }) |source| {
        try expectAbsent(source, "policy_ids:");
        try expectAbsent(source, "passive_records:");
    }
    const reconciliation_owner = @embedFile("domain/reference_reconciliation_repair.zig");
    try expectAbsent(reconciliation_owner, "equivalentStatement");
    try expectAbsent(reconciliation_owner, "checkBusinessIn");
    try expectAbsent(reconciliation_owner, "checkReferenceIn");
    try std.testing.expectEqualSlices(@import("domain/pipeline.zig").DataKey, &.{.text_validated_reference_extraction}, tokens.Merge.effects.replaces);
    try std.testing.expectEqualSlices(@import("domain/workflow.zig").OutcomeTag, &.{ .ok, .invalid, .failed }, &@import("application/reference_extraction_workflow.zig").ValidateTokenClassifications.outcomes);
}

test "the generic repair operations select owner rules through one exhaustive switch and hold none themselves" {
    const generic = @embedFile("application/repair_workflow.zig");
    const owners = @embedFile("domain/repair_owner.zig");
    // One `switch` over the closed owner enum in each of the four operations' `invoke`, and nothing else
    // that selects: no default branch, no inline-else, no function-pointer or callback table, no
    // dynamic field access, no dispatcher field (ADR 0033).
    try std.testing.expectEqual(@as(usize, 4), countOccurrences(generic, "switch (try ownerOf(contract, input))"));
    try expectAbsent(generic, "else =>");
    try expectAbsent(generic, "*const fn");
    try expectAbsent(generic, "@field(");
    try expectAbsent(generic, "@call(");
    try expectAbsent(generic, "anyopaque");
    // The owner's rules stay in the owner's own binding: the generic file runs no action, reads no
    // data, builds no delta and names no data key or schema.
    try expectAbsent(generic, ".execute(");
    try expectAbsent(generic, "@import(\"../actions/");
    try expectAbsent(generic, "DataKey");
    try expectAbsent(generic, "values.read");
    try expectAbsent(generic, "NodeDelta");
    try expectAbsent(generic, "data_replacements");
    try expectAbsent(generic, "_schema");
    // The owner enum is plain domain data: it reads no compiled step, so no code that exists only for a
    // test fixture (a step selector) lives in the domain.
    try expectAbsent(owners, "workflow_compilation");
    try expectAbsent(owners, "CompiledStep");
    // Each arm runs the binding its own owner holds: the arm for `.x` invokes the binding in field `x`.
    // The field's type is the owner's binding (`repair_operations_test` pins each field to its owner's
    // variant) and the arm cannot invoke another type on it, so a swapped arm cannot compile and a
    // consistent swap of arm and field breaks this pairing.
    var arms: usize = 0;
    var generic_lines = std.mem.splitScalar(u8, generic, '\n');
    while (generic_lines.next()) |line| {
        const marker = ".invoke(&self.";
        const at = std.mem.indexOf(u8, line, marker) orelse continue;
        const arrow = std.mem.indexOf(u8, line, " => ") orelse return error.TestUnexpectedResult;
        const tag = std.mem.trim(u8, line[0..arrow], " .");
        const rest = line[at + marker.len ..];
        const field = rest[0 .. std.mem.indexOfScalar(u8, rest, ',') orelse return error.TestUnexpectedResult];
        try std.testing.expectEqualStrings(tag, field);
        arms += 1;
    }
    try std.testing.expectEqual(@as(usize, 28), arms);
    // Its imports are exactly the contract types and the six owner bindings.
    try std.testing.expectEqual(@as(usize, 6), countOccurrences(generic, "_workflow.zig\")"));
    try std.testing.expectEqual(@as(usize, 12), countOccurrences(generic, "@import(\""));
    // Each variant is held to the descriptor check registry admission and graph validation apply, so a
    // `blocked` outcome with no reader stops the build (ADR 0033 "Blocked authorizers").
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(generic, "variant.validAssociation()"));
    // An owner function has one definition: each owner binding's `invoke` is declared once in its own file,
    // so the generic operation holds it once and no second path to it exists.
    inline for (.{
        .{ @embedFile("application/reference_text_repair_workflow.zig"), 4 },
        .{ @embedFile("application/reference_extraction_repair_workflow.zig"), 4 },
        .{ @embedFile("application/reference_reconciliation_repair_workflow.zig"), 4 },
        .{ @embedFile("application/source_omission_repair_workflow.zig"), 4 },
        .{ @embedFile("application/specification_repair_workflow.zig"), 4 },
        .{ @embedFile("application/specification_support_repair_workflow.zig"), 4 },
    }) |pair| try std.testing.expectEqual(@as(usize, pair[1]), countOccurrences(pair[0], "pub fn invoke("));
    // The owner enum's rules are exhaustive switches too: only `id` may use an inline-else prong.
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(owners, "else =>"));
    try expectAbsent(owners, "default");
    // No per-owner branch in the mechanism: it names no owner (ADR 0030 "Contract variants").
    inline for (.{ @embedFile("domain/workflow_operation.zig"), @embedFile("ports/workflow_operation_registry.zig"), @embedFile("domain/workflow_graph_compilation.zig"), @embedFile("application/workflow_pipeline_runner.zig") }) |source| {
        try expectAbsent(source, "repair_owner");
        try expectAbsent(source, "RepairOwner");
    }
}

test "an operation type registers by what it declares: its action, closed variants or its own contract, never neither" {
    const native = @import("composition/native_workflow_operations.zig");
    const invocation = @import("application/specify_invocation_runner.zig");
    const generic_repair = @import("application/repair_workflow.zig");
    try std.testing.expect(comptime native.shapeOf(invocation.ValidateArguments) == .action);
    try std.testing.expect(comptime native.shapeOf(generic_repair.AuthorizeRepair) == .shell);
    try std.testing.expect(comptime native.shapeOf(invocation.Invocation) == .direct);
    // A type with neither an action nor a contract is not an operation; registering one does not compile.
    try std.testing.expect(comptime native.shapeOf(struct { allocator: u8 }) == null);
    // The invocation parse is the invocation step by its own declarations, not by a branch in the table; an
    // ordinary action keeps the step kind and the default outcomes.
    var parse: invocation.ParseInvocation = .{ .allocator = std.testing.allocator };
    const invoked = native.entry(invocation.ParseInvocation, &parse);
    try std.testing.expectEqual(.invocation, invoked.contract.kind);
    try std.testing.expectEqual(@as(usize, 1), invoked.contract.outcomes.len);
    try std.testing.expectEqual(.ok, invoked.contract.outcomes[0]);
    var validate: invocation.ValidateArguments = .{ .allocator = std.testing.allocator };
    const ordinary = native.entry(invocation.ValidateArguments, &validate);
    try std.testing.expectEqual(.step, ordinary.contract.kind);
    try std.testing.expectEqual(@as(usize, 2), ordinary.contract.outcomes.len);
}

test "the request assembly holds its two context structs and the two tables derived from them, and no context of its own" {
    // The compiler already requires a context for each stage and a contract for each operation. What it leaves to a
    // person is a context field returning to the assembly beside the structs it derives from.
    const assembly = @import("composition/model_request_operations.zig");
    try std.testing.expectEqual(@as(usize, 4), std.meta.fieldNames(assembly.Assembly).len);
    inline for (.{ "selectable", "stages", "request_stages", "entries" }) |name| try std.testing.expect(@hasField(assembly.Assembly, name));
}

test "no per-owner repair operation remains: the four generic operations are the only registered repair operations" {
    // The registry registers the four generic operations and no per-owner one (ADR 0033): the operations table
    // holds each generic repair type once, and no other field declares closed variants.
    @setEvalBranchQuota(100_000);
    const native = @import("composition/native_workflow_operations.zig");
    const generic_repair = @import("application/repair_workflow.zig");
    inline for (.{ generic_repair.AuthorizeRepair, generic_repair.BuildRepairInput, generic_repair.ParseRepair, generic_repair.MergeRepair }) |generic| {
        var fields: usize = 0;
        inline for (std.meta.fields(native.Operations)) |field| fields += @intFromBool(field.type == generic);
        try std.testing.expectEqual(@as(usize, 1), fields);
    }
    var shells: usize = 0;
    inline for (std.meta.fields(native.Operations)) |field| shells += @intFromBool(comptime native.shapeOf(field.type) == .shell);
    try std.testing.expectEqual(@as(usize, 4), shells);
    // No owner binding is an operation: no type an owner module declares is a field of the table.
    inline for (.{
        @import("application/reference_text_repair_workflow.zig"),
        @import("application/reference_extraction_repair_workflow.zig"),
        @import("application/reference_reconciliation_repair_workflow.zig"),
        @import("application/source_omission_repair_workflow.zig"),
        @import("application/specification_repair_workflow.zig"),
        @import("application/specification_support_repair_workflow.zig"),
    }) |owner_module| {
        inline for (@typeInfo(owner_module).@"struct".decls) |decl| {
            const member = @field(owner_module, decl.name);
            if (@TypeOf(member) != type) continue;
            inline for (std.meta.fields(native.Operations)) |field| try std.testing.expect(field.type != member);
        }
    }
    // Each owner's binding is an owner module: it declares its data effects and rules, imports no action
    // and registers no contract of its own.
    inline for (.{
        @embedFile("application/reference_text_repair_workflow.zig"),
        @embedFile("application/reference_extraction_repair_workflow.zig"),
        @embedFile("application/reference_reconciliation_repair_workflow.zig"),
        @embedFile("application/source_omission_repair_workflow.zig"),
        @embedFile("application/specification_repair_workflow.zig"),
        @embedFile("application/specification_support_repair_workflow.zig"),
    }) |source| {
        try expectAbsent(source, "@import(\"../actions/");
        try expectAbsent(source, "Action.contract");
        try expectAbsent(source, "action: Action");
        // A merge's retry accounting goes through the shared `repair_owner` transition, which keeps its
        // causes: no binding calls the domain transition itself or discards a cause it returns.
        try expectAbsent(source, ".transition(");
        try expectAbsent(source, ".validatedTransition(");
        try expectAbsent(source, "catch return error.");
        // A binding states no retry rule: a merge takes a `retry-limit` exactly where the owner table
        // (`repair_owner.retryMaximum`) gives a maximum, and the generic operation builds the parameter
        // and the variant's descriptor from that one value.
        try expectAbsent(source, "retry_limit");
        try expectAbsent(source, "retry-limit");
    }
    // Each of the six bindings that merge reaches its merge transition through the shared helper exactly
    // once, so the cause it forwards is the helper's (tested once, and through the real text and support
    // bindings): a binding that built a transition by hand would leave this count at zero.
    inline for (.{
        @embedFile("application/reference_text_repair_workflow.zig"),
        @embedFile("application/reference_extraction_repair_workflow.zig"),
        @embedFile("application/reference_reconciliation_repair_workflow.zig"),
        @embedFile("application/source_omission_repair_workflow.zig"),
        @embedFile("application/specification_repair_workflow.zig"),
    }) |source| {
        try std.testing.expectEqual(@as(usize, 1), countOccurrences(source, "repair_owner.mergeTransition("));
    }
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("application/specification_support_repair_workflow.zig"), "repair_owner.validatedMergeTransition("));
    // No action file declares a repair step, and no domain code reaches a repair rule through an action.
    const io = std.testing.io;
    var actions = try std.Io.Dir.cwd().openDir(io, "src/actions", .{ .iterate = true });
    defer actions.close(io);
    var walker = try actions.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        try std.testing.expect(std.mem.indexOf(u8, entry.basename, "repair") == null);
    }
}

test "the engine binds each acceptance criterion to its slot, and the scenarios step runs the shared generation operations" {
    // ADR 0038 Decision 3: a record's group and claims are bound by one writer, whichever response the
    // record comes from. The scenarios answer carries no claim, kind or group, so it binds through that
    // writer and builds no provenance of its own; a records response cannot carry a criterion.
    const generation = @embedFile("domain/specification_generation.zig");
    const request = @embedFile("domain/scenario_request.zig");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(generation, "pub fn batchRecord("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(generation, "try batchRecord("));
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(request, "g.batchRecord("));
    for ([_][]const u8{ "source_group_ids", "bound.selection" }) |binding| try expectAbsent(request, binding);
    // The family the scenarios step writes is declared once, beside the mandatory families, and the
    // records response rejects it where it reads that declaration.
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("domain/specification.zig"), "pub const scenario_family: Kind = .acceptance_criterion;"));
    try expectAbsent(@embedFile("domain/specification_session.zig"), "pub const scenario_family");
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(generation, "std.meta.activeTag(wire.content) == spec.scenario_family"));
    // No repair inserts or replaces a whole criterion: its result definition, its schema entry and its
    // group policy are gone, and the one repair a criterion takes is the field-level value repair.
    try expectAbsent(@embedFile("domain/specification_result_definitions.zig"), "repair_record_acceptance_criterion");
    try expectAbsent(@embedFile("domain/specification_repair.zig"), "repair_record_acceptance_criterion");
    try expectAbsent(@embedFile("domain/specification_candidate.zig"), "scenario: FixedRecord");
    const io = std.testing.io;
    const schema = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec/generation.schema.json", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(schema);
    try expectAbsent(schema, "repair_record_acceptance_criterion");
    // The scenarios step has four operations of its own, the plan of its population, its progress,
    // its admission and its completion; its request, collection, parsing, validation and repair are
    // the operations the unit steps run (each appears in both subgraphs), so no second model path
    // exists. Collection and validation run on the group's batch unchanged; building the request and
    // parsing the answer switch on the session's scenarios phase.
    const scenario_generation = @import("application/scenario_generation_workflow.zig");
    inline for (.{ scenario_generation.Plan, scenario_generation.Check, scenario_generation.Advance, scenario_generation.Complete }) |operation| {
        var fields: usize = 0;
        inline for (std.meta.fields(@import("composition/native_workflow_operations.zig").Operations)) |field| fields += @intFromBool(field.type == operation);
        try std.testing.expectEqual(@as(usize, 1), fields);
    }
    // One transition completes the records unit: the completion operation is the only caller of
    // `completeScenarios`. The plan only measures the population, the admission only joins a group's
    // criteria, and the progress check only reads, so none of them completes it.
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(@embedFile("actions/specification/complete_scenario_generation.zig"), "session.completeScenarios("));
    for ([_][]const u8{
        @embedFile("actions/specification/plan_scenario_generation.zig"),
        @embedFile("actions/specification/advance_scenario_generation.zig"),
        @embedFile("actions/specification/check_scenario_generation_progress.zig"),
        @embedFile("application/scenario_generation_workflow.zig"),
    }) |source| try expectAbsent(source, "completeScenarios");
    const workflow = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec.workflow.yaml", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(workflow);
    try std.testing.expectEqual(@as(usize, 1), countOccurrences(workflow, "use: complete-scenario-generation"));
    for ([_][]const u8{ "use: build-specification-model-input", "use: collect-specification-model-result", "use: parse-specification-unit", "use: validate-specification-unit" }) |shared| {
        try std.testing.expectEqual(@as(usize, 2), countOccurrences(workflow, shared));
    }
    // It runs after generation and before linking, which needs the criteria it writes.
    const generate_at = std.mem.indexOf(u8, workflow, "call: generate-specification") orelse return error.MissingGenerationStep;
    const scenarios_at = std.mem.indexOf(u8, workflow, "call: generate-scenarios") orelse return error.MissingScenariosStep;
    const link_at = std.mem.indexOf(u8, workflow, "call: link-scenarios") orelse return error.MissingLinkStep;
    try std.testing.expect(generate_at < scenarios_at and scenarios_at < link_at);
}

test "the scenarios context repeats the generation context's shared rules and offers no answer its schema lacks" {
    // A request takes one context resource, so the scenarios context carries copies of the generation
    // context's rules. They must not drift apart, and it must leave out the answers a scenarios response
    // cannot take. This compares the two resources with each other; it names no wording.
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const generation_bytes = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec/generation.context.json", allocator, .limited(64 * 1024));
    defer allocator.free(generation_bytes);
    const scenarios_bytes = try std.Io.Dir.cwd().readFileAlloc(io, "design/workflows/spec/scenarios.context.json", allocator, .limited(64 * 1024));
    defer allocator.free(scenarios_bytes);
    var generation = try std.json.parseFromSlice(std.json.Value, allocator, generation_bytes, .{});
    defer generation.deinit();
    var scenarios = try std.json.parseFromSlice(std.json.Value, allocator, scenarios_bytes, .{});
    defer scenarios.deinit();
    const owner = generation.value.object;
    const copy = scenarios.value.object;
    // The scenarios context holds exactly the rules a scenarios request can use: how values are written,
    // how references are used and what the sources establish; never the clarification or inconclusive answers.
    try std.testing.expectEqual(@as(usize, 3), copy.count());
    for ([_][]const u8{ "business_value", "references", "sources" }) |key| try std.testing.expect(copy.contains(key) and owner.contains(key));
    for ([_][]const u8{ "clarification", "inconclusive" }) |key| try std.testing.expect(!copy.contains(key));
    for ([_][]const u8{ "business_value", "references" }) |key| {
        const shared = owner.get(key) orelse return error.TestUnexpectedResult;
        const repeated = copy.get(key) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(shared.string, repeated.string);
    }
    // Its sources rule is the generation rule's opening, without the part about fields a scenarios request lacks.
    const full = (owner.get("sources") orelse return error.TestUnexpectedResult).string;
    const opening = (copy.get("sources") orelse return error.TestUnexpectedResult).string;
    try std.testing.expect(opening.len < full.len and std.mem.startsWith(u8, full, opening));
}

test "principle root access stays in its narrow source adapter and shares physical traversal" {
    inline for (.{@import("actions/principle/capture_principle_registry.zig").Action}) |Action| {
        try std.testing.expectEqual(.filesystem_read, Action.contract.side_effect);
        try std.testing.expect(@import("application/workflow_operation_binding.zig").inspect(Action, &.{}).principle_read);
    }
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.eql(u8, entry.path, "domain/bootstrap_root_registry.zig") or
            std.mem.eql(u8, entry.path, "adapters/filesystem/principle_source.zig") or
            std.mem.eql(u8, entry.path, "architecture_test.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "bindPrincipleSourcesAdapter");
    }
    inline for (.{ @embedFile("adapters/filesystem/principle_source.zig"), @embedFile("adapters/filesystem/reference_corpus_source.zig") }) |source| {
        try std.testing.expect(std.mem.indexOf(u8, source, "directory_inventory.zig") != null);
        try std.testing.expect(std.mem.indexOf(u8, source, "files.capture(") != null);
    }
}

test "the principle context reaches a request only through the records request builder" {
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    var importers: usize = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig") or
            std.mem.endsWith(u8, entry.basename, "_test.zig") or std.mem.startsWith(u8, entry.path, "test_fixtures/") or
            std.mem.eql(u8, entry.path, "domain/specification_principles.zig")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        if (std.mem.indexOf(u8, source, "specification_principles.zig") != null) {
            try std.testing.expectEqualStrings("actions/specification/build_specification_model_input.zig", entry.path);
            importers += 1;
        }
        // No other producer places a `principles` part into a request.
        try expectAbsent(source, "\"principles\", ");
    }
    try std.testing.expectEqual(@as(usize, 1), importers);
}

test "every binding failure cause is closed, declared once in its owner area and returned by production code" {
    const step_binding = @import("domain/step_binding_error.zig");
    @setEvalBranchQuota(20_000);
    const sets = .{ step_binding.RequestPreparation, step_binding.ProviderLifecycle, step_binding.StepBinding, step_binding.Invocation, @import("domain/repair_owner.zig").Error };
    const Code = @import("domain/operation_error.zig").Code(@import("domain/workflow_execution.zig").OperationError);
    const names = comptime blk: {
        var total: usize = 0;
        for (sets) |Set| total += @typeInfo(Set).error_set.?.len;
        var list: [total][]const u8 = undefined;
        var at: usize = 0;
        for (sets) |Set| for (@typeInfo(Set).error_set.?) |cause| {
            list[at] = cause.name;
            at += 1;
        };
        break :blk list;
    };
    // Closed: each cause is a member of the serialized operation set, which names no generic failure.
    try std.testing.expect(!@hasField(Code, "OperationExecutionFailed"));
    inline for (names) |name| try std.testing.expect(@hasField(Code, name));
    // Declared once: the same cause is never named by two area sets.
    for (names, 0..) |name, index| for (names[index + 1 ..]) |other| try std.testing.expect(!std.mem.eql(u8, name, other));
    // Returned by production code, so none is dead, and the removed generic failure is named nowhere.
    var returned = [_]bool{false} ** names.len;
    const io = std.testing.io;
    var sources = try std.Io.Dir.cwd().openDir(io, "src", .{ .iterate = true });
    defer sources.close(io);
    var walker = try sources.walk(std.testing.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".zig")) continue;
        if (std.mem.indexOf(u8, entry.basename, "_test") != null or std.mem.startsWith(u8, entry.path, "test_fixtures/")) continue;
        const source = try entry.dir.readFileAlloc(io, entry.basename, std.testing.allocator, .limited(1024 * 1024));
        defer std.testing.allocator.free(source);
        try expectAbsent(source, "OperationExecutionFailed");
        inline for (names, 0..) |name, index| {
            if (returnsError(source, name)) returned[index] = true;
        }
    }
    // The E2E harness stops its own run with one cause that no production file raises, so the engine's
    // closed set carries it for the harness alone (its trace names it, and a `Rejection.operation_failed`
    // can hold only a member of that set). That one cause is pinned to the harness; every other cause
    // must be returned by production code, and the harness's word never counts for it.
    const harness_only = "HarnessFailureStopped";
    const trace = try std.Io.Dir.cwd().readFileAlloc(io, "test/harness/e2e/trace.zig", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(trace);
    inline for (names, 0..) |name, index| {
        if (comptime std.mem.eql(u8, name, harness_only)) {
            try std.testing.expect(returnsError(trace, name));
            try std.testing.expect(!returned[index]);
        } else {
            if (!returned[index]) std.debug.print("binding failure cause never returned by production code: {s}\n", .{name});
            try std.testing.expect(returned[index]);
        }
    }
}
