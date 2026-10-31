//! Syntax-based advisory measurements, with no engine or workflow authority.
//! A function includes its entire lexical body, including nested declarations.
const std = @import("std");
const model = @import("model.zig");

const TokenRange = struct { first: std.zig.Ast.TokenIndex, last: std.zig.Ast.TokenIndex };

/// The caller owns returned data through its arena. AST and scratch allocations
/// are released here; no returned slice borrows the supplied source.
pub fn analyze(a: std.mem.Allocator, path: []const u8, source: []const u8) !model.File {
    const scope = model.scope(path) orelse return error.UnsupportedSourcePath;
    if (source.len > std.math.maxInt(std.zig.Ast.ByteOffset)) return error.SourceTooLarge;
    const terminated = try a.dupeZ(u8, source);
    defer a.free(terminated);
    var tree = try std.zig.Ast.parse(a, terminated, .zig);
    defer tree.deinit(a);
    if (tree.errors.len != 0) return error.InvalidZigSource;

    const lines = physicalLines(source);
    const token_lines = try a.alloc(usize, tree.tokens.len);
    defer a.free(token_lines);
    const occupied = try a.alloc(bool, lines);
    defer a.free(occupied);
    @memset(occupied, false);
    var offset: usize = 0;
    var line: usize = 1;
    for (0..tree.tokens.len) |index| {
        const token: std.zig.Ast.TokenIndex = @intCast(index);
        const start = tree.tokenStart(token);
        while (offset < start) : (offset += 1) if (source[offset] == '\n') {
            line += 1;
        };
        token_lines[index] = line;
        const tag = tree.tokenTag(token);
        if (tag == .eof) continue;
        const bytes = tree.tokenSlice(token);
        const code = !isComment(tag);
        for (bytes) |byte| {
            if (byte == '\n') {
                line += 1;
            } else if (code) occupied[line - 1] = true;
        }
        offset = start + bytes.len;
    }
    var code_lines: usize = 0;
    for (occupied) |code| code_lines += @intFromBool(code);

    var tests: std.ArrayList(TokenRange) = .empty;
    defer tests.deinit(a);
    for (0..tree.nodes.len) |index| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(index);
        if (tree.nodeTag(node) == .test_decl) try tests.append(a, .{
            .first = tree.firstToken(node),
            .last = tree.lastToken(node),
        });
    }

    var functions: std.ArrayList(model.Function) = .empty;
    errdefer functions.deinit(a);
    for (0..tree.nodes.len) |index| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(index);
        if (tree.nodeTag(node) != .fn_decl) continue;
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&buffer, node) orelse return error.InvalidZigSource;
        const body = tree.nodeData(node).node_and_node[1];
        const first = tree.firstToken(body);
        const last = tree.lastToken(body);
        const start_line = token_lines[proto.ast.fn_token];
        const end_line = token_lines[last];
        var in_test = false;
        for (tests.items) |range| if (proto.ast.fn_token >= range.first and last <= range.last) {
            in_test = true;
            break;
        };
        var key: std.ArrayList(u8) = .empty;
        errdefer key.deinit(a);
        var body_tokens: usize = 0;
        var decisions: usize = 0;
        var depth: usize = 0;
        var max_depth: usize = 0;
        for (first..last + 1) |token_index| {
            const token: std.zig.Ast.TokenIndex = @intCast(token_index);
            const tag = tree.tokenTag(token);
            if (isComment(tag)) continue;
            body_tokens += 1;
            decisions += @intFromBool(isDecision(tag));
            switch (tag) {
                .l_brace => {
                    depth += 1;
                    max_depth = @max(max_depth, depth);
                },
                .r_brace => depth -= 1,
                else => {},
            }
            const bytes = tree.tokenSlice(token);
            var prefix: [32]u8 = undefined;
            try key.appendSlice(a, try std.fmt.bufPrint(&prefix, "{d}:", .{bytes.len}));
            try key.appendSlice(a, bytes);
        }
        try functions.append(a, .{
            .name = try a.dupe(u8, tree.tokenSlice(proto.name_token orelse return error.InvalidZigSource)),
            .start_line = start_line,
            .end_line = end_line,
            .lines = end_line - start_line + 1,
            .body_tokens = body_tokens,
            .decision_tokens = decisions,
            .max_brace_depth = max_depth,
            .in_test = in_test,
            .body_key = try key.toOwnedSlice(a),
        });
    }
    std.mem.sort(model.Function, functions.items, {}, lessFunction);

    // Function bodies whose declared return type names `DefinitionId`, and parameters
    // whose type does.
    var definition_bodies: std.ArrayList(TokenRange) = .empty;
    defer definition_bodies.deinit(a);
    var parameters: std.ArrayList(model.Parameter) = .empty;
    errdefer parameters.deinit(a);
    for (0..tree.nodes.len) |index| {
        const node: std.zig.Ast.Node.Index = @enumFromInt(index);
        if (tree.nodeTag(node) != .fn_decl) continue;
        var buffer: [1]std.zig.Ast.Node.Index = undefined;
        const proto = tree.fullFnProto(&buffer, node) orelse return error.InvalidZigSource;
        const name = tree.tokenSlice(proto.name_token orelse return error.InvalidZigSource);
        var params = proto.iterate(&tree);
        var receiver = false;
        var ordinal: usize = 0;
        while (params.next()) |param| : (ordinal += 1) {
            if (ordinal == 0) receiver = if (param.name_token) |token| std.mem.eql(u8, tree.tokenSlice(token), "self") else false;
            const type_expr = param.type_expr orelse continue;
            if (namesDefinitionId(&tree, tree.firstToken(type_expr), tree.lastToken(type_expr)))
                try parameters.append(a, .{ .function = try a.dupe(u8, name), .ordinal = ordinal, .receiver = receiver });
        }
        const returned = proto.ast.return_type.unwrap() orelse continue;
        if (!namesDefinitionId(&tree, tree.firstToken(returned), tree.lastToken(returned))) continue;
        const body = tree.nodeData(node).node_and_node[1];
        try definition_bodies.append(a, .{ .first = tree.firstToken(body), .last = tree.lastToken(body) });
    }
    var literals: std.ArrayList(model.Literal) = .empty;
    errdefer literals.deinit(a);
    var index: usize = 0;
    while (index < tree.tokens.len) : (index += 1) {
        const first: std.zig.Ast.TokenIndex = @intCast(index);
        const value = switch (tree.tokenTag(first)) {
            .string_literal => std.zig.string_literal.parseAlloc(a, tree.tokenSlice(first)) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidZigSource,
            .multiline_string_literal_line => joined: {
                var bytes: std.ArrayList(u8) = .empty;
                errdefer bytes.deinit(a);
                while (index < tree.tokens.len and tree.tokenTag(@intCast(index)) == .multiline_string_literal_line) : (index += 1) {
                    if (index != first) try bytes.append(a, '\n');
                    try bytes.appendSlice(a, std.mem.trimEnd(u8, tree.tokenSlice(@intCast(index))[2..], "\r\n"));
                }
                index -= 1;
                break :joined try bytes.toOwnedSlice(a);
            },
            else => continue,
        };
        const last: std.zig.Ast.TokenIndex = @intCast(index);
        var in_test = false;
        for (tests.items) |range| if (first >= range.first and last <= range.last) {
            in_test = true;
            break;
        };
        const use = try role(a, &tree, first, last, definition_bodies.items);
        try literals.append(a, .{ .line = token_lines[first], .value = value, .in_test = in_test, .role = use.role, .call = use.call });
    }
    return .{
        .path = try a.dupe(u8, path),
        .scope = scope,
        .bytes = source.len,
        .lines = lines,
        .code_lines = code_lines,
        .test_blocks = tests.items.len,
        .functions = try functions.toOwnedSlice(a),
        .literals = try literals.toOwnedSlice(a),
        .definition_parameters = try parameters.toOwnedSlice(a),
    };
}

const equality_calls = [_][]const u8{ "eql", "startsWith", "endsWith" };
const search_calls = [_][]const u8{ "indexOf", "lastIndexOf", "indexOfPos" };

const Use = struct { role: model.Role, call: ?model.Call = null };

/// The role of the literal spanning `first..last`, from the tokens around it.
fn role(a: std.mem.Allocator, tree: *const std.zig.Ast, first: std.zig.Ast.TokenIndex, last: std.zig.Ast.TokenIndex, definition_bodies: []const TokenRange) !Use {
    var open = opener(tree, first) orelse return .{ .role = .plain };
    // A value chosen by a `switch` is the value of the whole `switch` expression.
    var value = first;
    while (switchKeyword(tree, open)) |keyword| {
        value = keyword;
        open = opener(tree, keyword) orelse return .{ .role = .plain };
    }
    switch (tree.tokenTag(open)) {
        .l_paren => {
            if (open < 1 or tree.tokenTag(open - 1) != .identifier) return .{ .role = .plain };
            const callee = tree.tokenSlice(open - 1);
            if (named(&equality_calls, callee)) return .{ .role = .equality };
            if (named(&search_calls, callee)) {
                const close = closer(tree, last) orelse return .{ .role = .search };
                const compared = close + 2 < tree.tokens.len and tree.tokenTag(close + 1) == .equal_equal and
                    tree.tokenTag(close + 2) == .identifier and std.mem.eql(u8, tree.tokenSlice(close + 2), "null");
                return .{ .role = if (compared) .absence else .search };
            }
            // `DefinitionId.parse("...")`
            if (std.mem.eql(u8, callee, "parse") and open >= 3 and tree.tokenTag(open - 2) == .period and
                tree.tokenTag(open - 3) == .identifier and std.mem.eql(u8, tree.tokenSlice(open - 3), "DefinitionId")) return .{ .role = .definition_id };
            return .{ .role = .plain };
        },
        .l_brace => {
            if (!bytesField(tree, open, value) or open < 1) return .{ .role = .plain };
            // `DefinitionId{ .bytes = ... }`
            if (tree.tokenTag(open - 1) == .identifier) return .{ .role = if (std.mem.eql(u8, tree.tokenSlice(open - 1), "DefinitionId")) .definition_id else .plain };
            if (tree.tokenTag(open - 1) != .period or open < 2) return .{ .role = .plain };
            const before = open - 2;
            switch (tree.tokenTag(before)) {
                // `return .{ .bytes = ... }` in a function returning `DefinitionId`.
                .keyword_return => {
                    for (definition_bodies) |range| if (before > range.first and before < range.last) return .{ .role = .definition_id };
                    return .{ .role = .plain };
                },
                // `f(..., .{ .bytes = ... })`: resolved against parameter types later.
                .l_paren, .comma => {
                    const call = opener(tree, open - 1) orelse return .{ .role = .plain };
                    if (tree.tokenTag(call) != .l_paren or call < 1 or tree.tokenTag(call - 1) != .identifier) return .{ .role = .plain };
                    return .{ .role = .bytes_argument, .call = .{ .function = try a.dupe(u8, tree.tokenSlice(call - 1)), .ordinal = argumentOrdinal(tree, call, open - 1) } };
                },
                // `const name: ?DefinitionId = .{ .bytes = ... }`
                .equal => {
                    var cursor = before;
                    while (cursor > 0) {
                        cursor -= 1;
                        switch (tree.tokenTag(cursor)) {
                            .keyword_const, .keyword_var => return .{ .role = if (namesDefinitionId(tree, cursor, before)) .definition_id else .plain },
                            .semicolon, .l_brace, .r_brace => return .{ .role = .plain },
                            else => {},
                        }
                    }
                    return .{ .role = .plain };
                },
                else => return .{ .role = .plain },
            }
        },
        else => return .{ .role = .plain },
    }
}

/// The `switch` keyword whose body `open` opens, if it opens one.
fn switchKeyword(tree: *const std.zig.Ast, open: std.zig.Ast.TokenIndex) ?std.zig.Ast.TokenIndex {
    if (tree.tokenTag(open) != .l_brace or open < 1 or tree.tokenTag(open - 1) != .r_paren) return null;
    const condition = opener(tree, open - 1) orelse return null;
    if (condition < 1 or tree.tokenTag(condition - 1) != .keyword_switch) return null;
    return condition - 1;
}

/// The zero-based position of the argument starting at `argument` in the call opened
/// at `call`.
fn argumentOrdinal(tree: *const std.zig.Ast, call: std.zig.Ast.TokenIndex, argument: std.zig.Ast.TokenIndex) usize {
    var depth: usize = 0;
    var ordinal: usize = 0;
    for (call + 1..argument) |index| switch (tree.tokenTag(@intCast(index))) {
        .l_paren, .l_bracket, .l_brace => depth += 1,
        .r_paren, .r_bracket, .r_brace => depth -= 1,
        .comma => ordinal += @intFromBool(depth == 0),
        else => {},
    };
    return ordinal;
}

/// The nearest unmatched `(`, `[` or `{` before `token` within its statement.
fn opener(tree: *const std.zig.Ast, token: std.zig.Ast.TokenIndex) ?std.zig.Ast.TokenIndex {
    var depth: usize = 0;
    var cursor = token;
    while (cursor > 0) {
        cursor -= 1;
        switch (tree.tokenTag(cursor)) {
            .r_paren, .r_bracket, .r_brace => depth += 1,
            .l_paren, .l_bracket, .l_brace => {
                if (depth == 0) return cursor;
                depth -= 1;
            },
            .semicolon => if (depth == 0) return null,
            else => {},
        }
    }
    return null;
}

/// The `)` that closes the call whose argument ends at `token`.
fn closer(tree: *const std.zig.Ast, token: std.zig.Ast.TokenIndex) ?std.zig.Ast.TokenIndex {
    var depth: usize = 0;
    var cursor = token + 1;
    while (cursor < tree.tokens.len) : (cursor += 1) {
        switch (tree.tokenTag(cursor)) {
            .l_paren, .l_bracket, .l_brace => depth += 1,
            .r_paren, .r_bracket, .r_brace => {
                if (depth == 0) return if (tree.tokenTag(cursor) == .r_paren) cursor else null;
                depth -= 1;
            },
            else => {},
        }
    }
    return null;
}

/// Whether the literal at `token` is the value of the `.bytes` field opened at `open`.
fn bytesField(tree: *const std.zig.Ast, open: std.zig.Ast.TokenIndex, token: std.zig.Ast.TokenIndex) bool {
    var depth: usize = 0;
    var cursor = token;
    while (cursor > open + 1) {
        cursor -= 1;
        switch (tree.tokenTag(cursor)) {
            .r_paren, .r_bracket, .r_brace => depth += 1,
            .l_paren, .l_bracket, .l_brace => depth -= 1,
            .comma => if (depth == 0) return false,
            .equal => if (depth == 0) return cursor >= 2 and tree.tokenTag(cursor - 2) == .period and
                tree.tokenTag(cursor - 1) == .identifier and std.mem.eql(u8, tree.tokenSlice(cursor - 1), "bytes"),
            else => {},
        }
    }
    return false;
}

fn namesDefinitionId(tree: *const std.zig.Ast, first: std.zig.Ast.TokenIndex, last: std.zig.Ast.TokenIndex) bool {
    for (first..last + 1) |index| {
        const token: std.zig.Ast.TokenIndex = @intCast(index);
        if (tree.tokenTag(token) == .identifier and std.mem.eql(u8, tree.tokenSlice(token), "DefinitionId")) return true;
    }
    return false;
}

fn named(names: []const []const u8, name: []const u8) bool {
    for (names) |candidate| if (std.mem.eql(u8, candidate, name)) return true;
    return false;
}

fn physicalLines(source: []const u8) usize {
    if (source.len == 0) return 0;
    return std.mem.countScalar(u8, source, '\n') + @intFromBool(source[source.len - 1] != '\n');
}

fn isComment(tag: std.zig.Token.Tag) bool {
    return tag == .doc_comment or tag == .container_doc_comment;
}

fn isDecision(tag: std.zig.Token.Tag) bool {
    return switch (tag) {
        .keyword_if,
        .keyword_for,
        .keyword_while,
        .keyword_switch,
        .keyword_catch,
        .keyword_orelse,
        .keyword_and,
        .keyword_or,
        => true,
        else => false,
    };
}

fn lessFunction(_: void, left: model.Function, right: model.Function) bool {
    if (left.start_line != right.start_line) return left.start_line < right.start_line;
    if (left.end_line != right.end_line) return left.end_line > right.end_line;
    return std.mem.lessThan(u8, left.name, right.name);
}

test "comments strings and multiline literals cannot invent code or decisions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const file = try analyze(arena.allocator(), "src/sample.zig",
        \\//! fn invented() { if (true) {} }
        \\
        \\/// while for catch and or
        \\fn real() void {
        \\    // fn ignored() {} switch
        \\    const text = "if for while { }";
        \\    const multiline =
        \\        \\\\switch catch orelse {
        \\        \\\\} and or
        \\    ;
        \\}
        \\
    );
    try std.testing.expectEqual(@as(usize, 11), file.lines);
    try std.testing.expectEqual(@as(usize, 7), file.code_lines);
    try std.testing.expectEqual(@as(usize, 1), file.functions.len);
    const function = file.functions[0];
    try std.testing.expectEqualStrings("real", function.name);
    try std.testing.expectEqual(@as(usize, 4), function.start_line);
    try std.testing.expectEqual(@as(usize, 11), function.end_line);
    try std.testing.expectEqual(@as(usize, 8), function.lines);
    try std.testing.expectEqual(@as(usize, 0), function.decision_tokens);
    try std.testing.expectEqual(@as(usize, 1), function.max_brace_depth);
}

test "multiline signatures extern prototypes nested functions and test blocks are distinct" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const file = try analyze(arena.allocator(), "src/sample.zig",
        \\extern fn foreign(value: u8) void;
        \\pub fn outer(
        \\    value: bool,
        \\) void {
        \\    const Nested = struct {
        \\        fn inner() void {
        \\            if (true) {}
        \\        }
        \\    };
        \\    if (value) {}
        \\}
        \\test "case" {
        \\    const Helper = struct {
        \\        fn helper() void {}
        \\    };
        \\}
        \\test {}
    );
    try std.testing.expectEqual(@as(usize, 2), file.test_blocks);
    try std.testing.expectEqual(@as(usize, 3), file.functions.len);
    const outer = file.functions[0];
    try std.testing.expectEqualStrings("outer", outer.name);
    try std.testing.expectEqual(@as(usize, 2), outer.start_line);
    try std.testing.expectEqual(@as(usize, 11), outer.end_line);
    try std.testing.expectEqual(@as(usize, 10), outer.lines);
    try std.testing.expectEqual(@as(usize, 2), outer.decision_tokens);
    try std.testing.expectEqual(@as(usize, 4), outer.max_brace_depth);
    try std.testing.expect(!outer.in_test);
    try std.testing.expectEqualStrings("inner", file.functions[1].name);
    try std.testing.expectEqual(@as(usize, 1), file.functions[1].decision_tokens);
    try std.testing.expect(!file.functions[1].in_test);
    try std.testing.expectEqualStrings("helper", file.functions[2].name);
    try std.testing.expect(file.functions[2].in_test);
    try std.testing.expect(outer.body_tokens > file.functions[1].body_tokens);
}

test "decision token proxy counts each declared token without a baseline" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const file = try analyze(arena.allocator(), "src/decisions.zig",
        \\fn count(values: []const bool, maybe: ?bool) !void {
        \\    if (true and false or true) {}
        \\    for (values) |_| {}
        \\    while (false) {}
        \\    switch (maybe orelse false) { true => {}, false => {} }
        \\    attempt() catch {};
        \\}
        \\fn empty() void {}
    );
    try std.testing.expectEqual(@as(usize, 8), file.functions[0].decision_tokens);
    try std.testing.expectEqual(@as(usize, 0), file.functions[1].decision_tokens);
    try std.testing.expectEqual(@as(usize, 2), file.functions[1].body_tokens);
}

test "exact body keys ignore trivia but preserve identifiers literals and token boundaries" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const file = try analyze(arena.allocator(), "test/keys.zig",
        \\fn first() u8 { return 1; }
        \\fn second() u8 {
        \\    // comment
        \\    return 1;
        \\}
        \\fn changed() u8 { return 2; }
        \\fn a() u8 { return alpha + beta; }
        \\fn b() u8 { return alph + abeta; }
        \\fn literal_a() []const u8 { return "a b"; }
        \\fn literal_b() []const u8 { return "ab"; }
        \\fn separated() u8 { return a; }
        \\fn combined() u8 { returna; }
    );
    try std.testing.expectEqualStrings(file.functions[0].body_key, file.functions[1].body_key);
    try std.testing.expect(!std.mem.eql(u8, file.functions[0].body_key, file.functions[2].body_key));
    try std.testing.expect(!std.mem.eql(u8, file.functions[3].body_key, file.functions[4].body_key));
    try std.testing.expect(!std.mem.eql(u8, file.functions[5].body_key, file.functions[6].body_key));
    try std.testing.expect(!std.mem.eql(u8, file.functions[7].body_key, file.functions[8].body_key));
    const again = try analyze(arena.allocator(), "test/again.zig", "fn first() u8 { return 1; }");
    try std.testing.expectEqualStrings(file.functions[0].body_key, again.functions[0].body_key);
}

test "empty comments-only invalid and unsupported sources have explicit results" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const empty = try analyze(a, "src/empty.zig", "");
    try std.testing.expectEqual(@as(usize, 0), empty.lines);
    try std.testing.expectEqual(@as(usize, 0), empty.code_lines);
    try std.testing.expectEqual(@as(usize, 0), empty.functions.len);
    const comments = try analyze(a, "src/comments.zig", "//! comment\n\n// ordinary\n");
    try std.testing.expectEqual(@as(usize, 3), comments.lines);
    try std.testing.expectEqual(@as(usize, 0), comments.code_lines);
    const crlf = try analyze(a, "src/crlf.zig", "// comment\r\nfn real() void {}\r\n\r\n");
    try std.testing.expectEqual(@as(usize, 3), crlf.lines);
    try std.testing.expectEqual(@as(usize, 1), crlf.code_lines);
    try std.testing.expectEqual(@as(usize, 2), crlf.functions[0].start_line);
    try std.testing.expectError(error.InvalidZigSource, analyze(a, "src/invalid.zig", "fn broken( {"));
    try std.testing.expectError(error.UnsupportedSourcePath, analyze(a, "zig-out/copy.zig", ""));
}

test "literals carry decoded bytes, test scope and the role of the tokens around them" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const file = try analyze(arena.allocator(), "src/roles.zig",
        \\fn f(x: []const u8) bool {
        \\    const named: ?schema.DefinitionId = .{ .bytes = if (x.len == 0) "one" else "two" };
        \\    _ = DefinitionId.parse("three");
        \\    _ = std.mem.indexOf(u8, x, "four") == null;
        \\    _ = std.mem.indexOf(u8, x, "five");
        \\    _ = std.mem.eql(u8, x, "six");
        \\    _ = .{ .name = "seven" };
        \\    _ = call("eight", std.mem.startsWith(u8, x, "nine"));
        \\    const multi =
        \\        \\line one
        \\        \\line two
        \\    ;
        \\    return named != null and multi.len != 0;
        \\}
        \\fn g() DefinitionId { return .{ .bytes = "ten" }; }
        \\fn h() Other { return .{ .bytes = "eleven" }; }
        \\const other: Other = .{ .bytes = "twelve" };
        \\test "t\tq" { _ = std.mem.eql(u8, x, "thirteen"); }
        \\const imported: ?@import("s.zig").DefinitionId = .{ .bytes = "fourteen" };
        \\fn k() void { x = .{ .bytes = "fifteen" }; }
    );
    const expected = [_]struct { []const u8, model.Role, bool, usize }{
        .{ "one", .definition_id, false, 2 },
        .{ "two", .definition_id, false, 2 },
        .{ "three", .definition_id, false, 3 },
        .{ "four", .absence, false, 4 },
        .{ "five", .search, false, 5 },
        .{ "six", .equality, false, 6 },
        .{ "seven", .plain, false, 7 },
        .{ "eight", .plain, false, 8 },
        .{ "nine", .equality, false, 8 },
        .{ "line one\nline two", .plain, false, 10 },
        .{ "ten", .definition_id, false, 15 },
        .{ "eleven", .plain, false, 16 },
        .{ "twelve", .plain, false, 17 },
        .{ "t\tq", .plain, true, 18 },
        .{ "thirteen", .equality, true, 18 },
        .{ "s.zig", .plain, false, 19 },
        .{ "fourteen", .definition_id, false, 19 },
        .{ "fifteen", .plain, false, 20 },
    };
    try std.testing.expectEqual(expected.len, file.literals.len);
    for (expected, file.literals) |want, got| {
        try std.testing.expectEqualStrings(want[0], got.value);
        try std.testing.expectEqual(want[1], got.role);
        try std.testing.expectEqual(want[2], got.in_test);
        try std.testing.expectEqual(want[3], got.line);
    }
}

test "initializers passed as arguments or chosen by a switch record their call, and DefinitionId parameters are collected" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const file = try analyze(arena.allocator(), "src/calls.zig",
        \\fn create(a: Allocator, body: []const u8, definition: ?schema.DefinitionId) void {}
        \\fn one() void { create(a, body, .{ .bytes = "first" }); }
        \\fn two(k: K) void { create(a, f(b, c), .{ .bytes = switch (k) { .x => "second", .y => "third" } }); }
        \\const Packet = struct { fn packet(self: Packet, d: DefinitionId) void {} };
        \\fn three() void { create(.{ .name = "fourth" }); }
        \\fn four() void { _ = std.mem.eql(u8, x, switch (k) { .x => "fifth", .y => "sixth" }); }
        \\fn five() void { if (x) { create(a, "seventh"); } }
    );
    const expected = [_]struct { []const u8, model.Role, ?model.Call }{
        .{ "first", .bytes_argument, .{ .function = "create", .ordinal = 2 } },
        .{ "second", .bytes_argument, .{ .function = "create", .ordinal = 2 } },
        .{ "third", .bytes_argument, .{ .function = "create", .ordinal = 2 } },
        .{ "fourth", .plain, null },
        .{ "fifth", .equality, null },
        .{ "sixth", .equality, null },
        .{ "seventh", .plain, null },
    };
    try std.testing.expectEqual(expected.len, file.literals.len);
    for (expected, file.literals) |want, got| {
        try std.testing.expectEqualStrings(want[0], got.value);
        try std.testing.expectEqual(want[1], got.role);
        try std.testing.expectEqual(want[2] == null, got.call == null);
        if (want[2]) |call| {
            try std.testing.expectEqualStrings(call.function, got.call.?.function);
            try std.testing.expectEqual(call.ordinal, got.call.?.ordinal);
        }
    }
    try std.testing.expectEqual(@as(usize, 2), file.definition_parameters.len);
    try std.testing.expectEqualStrings("create", file.definition_parameters[0].function);
    try std.testing.expectEqual(@as(usize, 2), file.definition_parameters[0].ordinal);
    try std.testing.expect(!file.definition_parameters[0].receiver);
    try std.testing.expectEqualStrings("packet", file.definition_parameters[1].function);
    try std.testing.expectEqual(@as(usize, 1), file.definition_parameters[1].ordinal);
    try std.testing.expect(file.definition_parameters[1].receiver);
}
