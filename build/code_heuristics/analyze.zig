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
    return .{
        .path = try a.dupe(u8, path),
        .scope = scope,
        .bytes = source.len,
        .lines = lines,
        .code_lines = code_lines,
        .test_blocks = tests.items.len,
        .functions = try functions.toOwnedSlice(a),
    };
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
