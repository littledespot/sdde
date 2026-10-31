//! Development report data. Measurements are advisory, never workflow authority.
const std = @import("std");

pub const Scope = enum { production, tests, tooling };

pub const Function = struct {
    name: []const u8,
    start_line: usize,
    end_line: usize,
    lines: usize,
    body_tokens: usize,
    decision_tokens: usize,
    max_brace_depth: usize,
    in_test: bool,
    /// Exact token spelling with whitespace/comments removed; retained for
    /// duplicate confirmation, omitted from report serialization.
    body_key: []const u8,

    pub fn jsonStringify(self: Function, writer: *std.json.Stringify) !void {
        try writer.write(.{
            .name = self.name,
            .start_line = self.start_line,
            .end_line = self.end_line,
            .lines = self.lines,
            .body_tokens = self.body_tokens,
            .decision_tokens = self.decision_tokens,
            .max_brace_depth = self.max_brace_depth,
            .in_test = self.in_test,
        });
    }
};

/// How a literal is used, read from the tokens around it. Only direct operands count.
pub const Role = enum {
    plain,
    /// An argument of `eql`, `startsWith` or `endsWith`.
    equality,
    /// An argument of `indexOf`, `lastIndexOf` or `indexOfPos`.
    search,
    /// A `search` operand whose call is compared `== null`.
    absence,
    /// The value of `.bytes` in a `DefinitionId` initializer.
    definition_id,
    /// The value of `.bytes` in an anonymous initializer passed as an argument; it is a
    /// `DefinitionId` initializer when some parameter `Literal.call` names is one.
    bytes_argument,
};

/// The function and argument position a `bytes_argument` literal is passed at.
pub const Call = struct { function: []const u8, ordinal: usize };

/// A function parameter whose type names `DefinitionId`. `receiver` marks a function
/// whose first parameter is `self`, which a method call doesn't pass as an argument.
pub const Parameter = struct { function: []const u8, ordinal: usize, receiver: bool };

/// One string literal with its decoded bytes (a multiline literal's lines joined by
/// newlines).
pub const Literal = struct {
    line: usize,
    value: []const u8,
    in_test: bool,
    role: Role,
    call: ?Call = null,
};

pub const File = struct {
    path: []const u8,
    scope: Scope,
    bytes: usize,
    lines: usize,
    code_lines: usize,
    test_blocks: usize,
    functions: []const Function,
    /// Retained for the brittleness counts, omitted from report serialization.
    literals: []const Literal = &.{},
    definition_parameters: []const Parameter = &.{},

    pub fn jsonStringify(self: File, writer: *std.json.Stringify) !void {
        try writer.write(.{
            .path = self.path,
            .scope = self.scope,
            .bytes = self.bytes,
            .lines = self.lines,
            .code_lines = self.code_lines,
            .test_blocks = self.test_blocks,
            .functions = self.functions,
        });
    }
};

pub fn scope(path: []const u8) ?Scope {
    if (!std.mem.endsWith(u8, path, ".zig")) return null;
    if (std.mem.startsWith(u8, path, "test/") or
        std.mem.startsWith(u8, path, "src/test_fixtures/") or
        std.mem.eql(u8, path, "tests.zig") or
        std.mem.eql(u8, path, "integration.zig") or
        (std.mem.startsWith(u8, path, "src/") and
            (std.mem.endsWith(u8, path, "_test.zig") or
                std.mem.endsWith(u8, path, "_tests.zig") or
                std.mem.endsWith(u8, path, "_test_fixture.zig")))) return .tests;
    if (std.mem.startsWith(u8, path, "src/")) return .production;
    if (std.mem.startsWith(u8, path, "build/") or std.mem.indexOfScalar(u8, path, '/') == null) return .tooling;
    return null;
}

test "source scope separates engine tests and tooling from generated or external code" {
    const cases = .{
        .{ "src/main.zig", Scope.production },
        .{ "src/domain/rules.zig", Scope.production },
        .{ "src/rules_test.zig", Scope.tests },
        .{ "src/adapters/runtime_tests.zig", Scope.tests },
        .{ "src/test_fixtures/rules.zig", Scope.tests },
        .{ "test/harness/exact_value/cli.zig", Scope.tests },
        .{ "tests.zig", Scope.tests },
        .{ "integration.zig", Scope.tests },
        .{ "build/code_heuristics/main.zig", Scope.tooling },
        .{ "harness.zig", Scope.tooling },
        .{ "adjudicate.zig", Scope.tooling },
    };
    inline for (cases) |case| try std.testing.expectEqual(case[1], scope(case[0]).?);
    for ([_][]const u8{ "zig-out/copy/main.zig", ".zig-cache/main.zig", "zig-pkg/dependency/main.zig", "design/example.zig", "README.md" }) |path|
        try std.testing.expectEqual(null, scope(path));
}
