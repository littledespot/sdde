//! FIX06 T5 brittleness counts: exact matches only, never word lists. Pure; the
//! inventory supplies every input. T5.4 needs the compiled workflow graph and is
//! counted by hand in the fix record.
const std = @import("std");
const model = @import("model.zig");
const suffix = @import("suffix.zig");

/// A workflow asset under `design/workflows/`: a prompt or a JSON resource.
pub const Asset = struct { path: []const u8, bytes: []const u8 };

pub const Inputs = struct {
    files: []const model.File,
    assets: []const Asset,
    /// Distinct `guidance` parts, `protocol_prompt` and `schema` values of the freeze.
    freeze: []const []const u8,
    /// Catalogue model IDs and model families.
    models: []const []const u8,
    /// Case, feature and reference IDs.
    cases: []const []const u8,
    /// Case source texts.
    case_sources: []const []const u8,
};

pub const Site = struct { path: []const u8, line: usize, text: []const u8 };
pub const Count = struct { total: usize, sites: []const Site };
pub const Instruction = struct { text: []const u8, sites: []const Site };

pub const Result = struct {
    /// T5.1: test literals of three or more whitespace-separated runs found in A or M,
    /// plus absence assertions whose literal A or M holds.
    tests_copying_model_text: Count,
    /// T5.2: production `$defs` keys used as comparison operands or `DefinitionId`
    /// initializers; test sites are reported beside them.
    schema_name_branches: Count,
    schema_name_branches_in_tests: Count,
    /// T5.3: maximal exact spans of at least 40 bytes at two or more sites of A ∪ M.
    repeated_instructions: struct { instructions: usize, sites: usize, items: []const Instruction },
    /// T5.5.
    model_or_case_branches: Count,
    /// T5.6: M literals outside the owner (`design/workflows/**`), so every M literal.
    model_text_outside_owner: struct { total: usize, files: usize, sites: []const Site },
};

pub const span_minimum = 40;
pub const minimum_runs = 3;
const owner_prefix = "design/workflows/";
const provider_adapters = "src/adapters/provider/";

/// Returned storage belongs to `a`.
pub fn count(a: std.mem.Allocator, inputs: Inputs) !Result {
    // A: every prompt and JSON string value, unescaped and whitespace-collapsed.
    var a_units: std.ArrayList([]const u8) = .empty;
    var a_sites: std.ArrayList(Site) = .empty;
    var definitions: std.StringHashMapUnmanaged(void) = .empty;
    for (inputs.assets) |asset| {
        if (!std.mem.startsWith(u8, asset.path, owner_prefix)) return error.ForeignAsset;
        if (std.mem.endsWith(u8, asset.path, ".md")) {
            try a_units.append(a, try collapse(a, asset.bytes));
            try a_sites.append(a, .{ .path = asset.path, .line = 0, .text = "" });
        } else if (std.mem.endsWith(u8, asset.path, ".json")) {
            const value = try std.json.parseFromSliceLeaky(std.json.Value, a, asset.bytes, .{});
            try strings(a, value, asset.path, &a_units, &a_sites);
            if (std.mem.endsWith(u8, asset.path, ".schema.json")) if (value == .object) if (value.object.get("$defs")) |defs| if (defs == .object) {
                for (defs.object.keys()) |key| try definitions.put(a, key, {});
            };
        }
    }
    const a_index = try suffix.Index.build(a, a_units.items);
    const freeze_index = try suffix.Index.build(a, inputs.freeze);
    const case_index = try suffix.Index.build(a, inputs.case_sources);

    // M: production literals of three or more runs, outside tests, whose exact bytes the
    // freeze sent and A lacks.
    var m_units: std.ArrayList([]const u8) = .empty;
    var m_sites: std.ArrayList(Site) = .empty;
    var m_files: usize = 0;
    for (inputs.files) |file| {
        if (file.scope != .production) continue;
        const before = m_sites.items.len;
        for (file.literals) |literal| {
            if (literal.in_test or runs(literal.value) < minimum_runs or !freeze_index.contains(literal.value)) continue;
            const collapsed = try collapse(a, literal.value);
            if (a_index.contains(collapsed)) continue;
            try m_units.append(a, collapsed);
            try m_sites.append(a, .{ .path = file.path, .line = literal.line, .text = literal.value });
        }
        m_files += @intFromBool(m_sites.items.len != before);
    }

    const both_units = try std.mem.concat(a, []const u8, &.{ a_units.items, m_units.items });
    const both_sites = try std.mem.concat(a, Site, &.{ a_sites.items, m_sites.items });
    const both = try suffix.Index.build(a, both_units);

    var parameters: std.ArrayList(model.Parameter) = .empty;
    for (inputs.files) |file| try parameters.appendSlice(a, file.definition_parameters);

    var copies: std.ArrayList(Site) = .empty;
    var branches: std.ArrayList(Site) = .empty;
    var test_branches: std.ArrayList(Site) = .empty;
    var specific: std.ArrayList(Site) = .empty;
    for (inputs.files) |file| {
        if (file.scope == .tooling) continue;
        for (file.literals) |literal| {
            const site: Site = .{ .path = file.path, .line = literal.line, .text = literal.value };
            const in_tests = file.scope == .tests or literal.in_test;
            if (in_tests and (literal.role == .absence or runs(literal.value) >= minimum_runs)) {
                const collapsed = try collapse(a, literal.value);
                if (collapsed.len != 0 and both.contains(collapsed)) try copies.append(a, site);
            }
            const used = effective(literal, parameters.items);
            const named = (used == .equality or used == .definition_id) and definitions.contains(literal.value);
            if (named) try (if (in_tests) &test_branches else &branches).append(a, site);
            if (!in_tests and decision(used) and specificTo(inputs, case_index, file.path, literal.value)) try specific.append(a, site);
        }
    }

    var instructions: std.ArrayList(Instruction) = .empty;
    var instruction_sites: usize = 0;
    for (try both.repeats(a, span_minimum)) |repeat| {
        const sites = try a.alloc(Site, repeat.offsets.len);
        for (sites, repeat.offsets) |*site, offset| site.* = both_sites[both.unit(offset)];
        const start = repeat.offsets[0];
        const text = try a.alloc(u8, repeat.length);
        for (text, both.text[start..][0..repeat.length]) |*byte, symbol| byte.* = @intCast(symbol);
        try instructions.append(a, .{ .text = text, .sites = sites });
        instruction_sites += sites.len;
    }
    std.mem.sort(Instruction, instructions.items, {}, instructionLess);

    return .{
        .tests_copying_model_text = .{ .total = copies.items.len, .sites = copies.items },
        .schema_name_branches = .{ .total = branches.items.len, .sites = branches.items },
        .schema_name_branches_in_tests = .{ .total = test_branches.items.len, .sites = test_branches.items },
        .repeated_instructions = .{ .instructions = instructions.items.len, .sites = instruction_sites, .items = instructions.items },
        .model_or_case_branches = .{ .total = specific.items.len, .sites = specific.items },
        .model_text_outside_owner = .{ .total = m_sites.items.len, .files = m_files, .sites = m_sites.items },
    };
}

fn decision(role: model.Role) bool {
    return switch (role) {
        .equality, .search, .absence, .definition_id => true,
        .plain, .bytes_argument => false,
    };
}

/// A `bytes_argument` passed where some function of that name takes a `DefinitionId`
/// is a `DefinitionId` initializer. Functions are matched by name only.
fn effective(literal: model.Literal, parameters: []const model.Parameter) model.Role {
    if (literal.role != .bytes_argument) return literal.role;
    const call = literal.call orelse return .plain;
    for (parameters) |parameter| {
        if (!std.mem.eql(u8, parameter.function, call.function)) continue;
        if (call.ordinal == parameter.ordinal or (parameter.receiver and call.ordinal + 1 == parameter.ordinal)) return .definition_id;
    }
    return .plain;
}

/// T5.5's operand test: a catalogue model ID or family outside the provider adapters,
/// a case, feature or reference ID, or a 40-byte span of case sources.
fn specificTo(inputs: Inputs, case_index: suffix.Index, path: []const u8, value: []const u8) bool {
    if (!std.mem.startsWith(u8, path, provider_adapters)) for (inputs.models) |name| if (std.mem.eql(u8, name, value)) return true;
    for (inputs.cases) |name| if (std.mem.eql(u8, name, value)) return true;
    if (value.len < span_minimum) return false;
    for (0..value.len - span_minimum + 1) |start| if (case_index.contains(value[start..][0..span_minimum])) return true;
    return false;
}

/// Every string value of a JSON document, member names excluded.
fn strings(a: std.mem.Allocator, value: std.json.Value, path: []const u8, units: *std.ArrayList([]const u8), sites: *std.ArrayList(Site)) !void {
    switch (value) {
        .string => |text| {
            try units.append(a, try collapse(a, text));
            try sites.append(a, .{ .path = path, .line = 0, .text = "" });
        },
        .array => |items| for (items.items) |item| try strings(a, item, path, units, sites),
        .object => |members| for (members.values()) |item| try strings(a, item, path, units, sites),
        else => {},
    }
}

/// Runs of whitespace become one space; leading and trailing whitespace go.
pub fn collapse(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    var output: std.ArrayList(u8) = .empty;
    var words = std.mem.tokenizeAny(u8, text, &std.ascii.whitespace);
    while (words.next()) |word| {
        if (output.items.len != 0) try output.append(a, ' ');
        try output.appendSlice(a, word);
    }
    return output.toOwnedSlice(a);
}

fn runs(text: []const u8) usize {
    var words = std.mem.tokenizeAny(u8, text, &std.ascii.whitespace);
    var total: usize = 0;
    while (words.next()) |_| total += 1;
    return total;
}

fn instructionLess(_: void, left: Instruction, right: Instruction) bool {
    if (left.sites.len != right.sites.len) return left.sites.len > right.sites.len;
    if (left.text.len != right.text.len) return left.text.len > right.text.len;
    return std.mem.lessThan(u8, left.text, right.text);
}

fn literalAt(line: usize, value: []const u8, in_test: bool, role: model.Role) model.Literal {
    return .{ .line = line, .value = value, .in_test = in_test, .role = role };
}

fn passedAt(line: usize, value: []const u8, function: []const u8, ordinal: usize) model.Literal {
    return .{ .line = line, .value = value, .in_test = false, .role = .bytes_argument, .call = .{ .function = function, .ordinal = ordinal } };
}

fn sourceFile(path: []const u8, scope: model.Scope, literals: []const model.Literal) model.File {
    return .{ .path = path, .scope = scope, .bytes = 0, .lines = 0, .code_lines = 0, .test_blocks = 0, .functions = &.{}, .literals = literals };
}

const instruction = "Return one object whose members follow the supplied schema exactly.";
const inputs_template: Inputs = .{
    .files = &.{},
    .assets = &.{
        .{ .path = "design/workflows/demo/task.prompt.md", .bytes = "Summarise   the\nnotes.\n" ++ instruction },
        .{ .path = "design/workflows/demo/result.schema.json", .bytes = "{\"$defs\":{\"note\":{\"description\":\"" ++ instruction ++ "\"}},\"type\":\"object\"}" },
    },
    .freeze = &.{ "Summarise the notes.", "Native code keeps each identifier unchanged.", "{\"type\":\"object\"}" },
    .models = &.{ "vendor.model-a", "family-x" },
    .cases = &.{"room-booking"},
    .case_sources = &.{"A reservation links one registered room, its requester, and a start time."},
};

test "M is production text the freeze sent that no asset holds" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var inputs = inputs_template;
    inputs.files = &.{
        sourceFile("src/domain/a.zig", .production, &.{
            literalAt(1, "Native code keeps each identifier unchanged.", false, .plain), // M
            literalAt(2, "Summarise the notes.", false, .plain), // in A
            literalAt(3, "Never sent to any model.", false, .plain),
            literalAt(4, "Native code keeps each identifier unchanged.", true, .plain), // a test
            literalAt(5, "", false, .plain),
            literalAt(6, "type", false, .plain), // sent in the schema, but one run
        }),
        sourceFile("src/test_fixtures/b.zig", .tests, &.{literalAt(1, "Native code keeps each identifier unchanged.", false, .plain)}),
    };
    inputs.freeze = &.{ "Native code keeps each identifier unchanged.", "Summarise  the notes." };
    inputs.files = &.{
        inputs.files[0], inputs.files[1],
        sourceFile("src/domain/c.zig", .production, &.{
            literalAt(1, "Summarise  the notes.", false, .plain), // sent exactly; A holds it once collapsed
        }),
    };
    const result = try count(arena.allocator(), inputs);
    try std.testing.expectEqual(@as(usize, 1), result.model_text_outside_owner.total);
    try std.testing.expectEqual(@as(usize, 1), result.model_text_outside_owner.files);
    try std.testing.expectEqual(@as(usize, 1), result.model_text_outside_owner.sites[0].line);
}

test "T5.1 counts test copies of A or M with three runs, and absence assertions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var inputs = inputs_template;
    inputs.files = &.{
        sourceFile("src/domain/a.zig", .production, &.{
            literalAt(1, "Native code keeps each identifier unchanged.", false, .plain),
            literalAt(2, "Summarise the notes.", false, .plain), // production, not counted
            literalAt(3, "Summarise the\n  notes.", true, .plain), // inline test, collapsed copy of A
        }),
        sourceFile("test/demo.zig", .tests, &.{
            literalAt(1, "keeps each identifier", false, .plain), // part of M
            literalAt(2, "the notes.", false, .plain), // two runs
            literalAt(3, "words found nowhere at all", false, .plain),
            literalAt(4, "absent", false, .absence), // absence of text no model receives
            literalAt(5, "notes.", false, .absence),
        }),
        sourceFile("build/tool.zig", .tooling, &.{literalAt(1, "Summarise the notes.", true, .plain)}),
    };
    const result = try count(arena.allocator(), inputs);
    try std.testing.expectEqual(@as(usize, 3), result.tests_copying_model_text.total);
    const lines = [_]usize{ 3, 1, 5 };
    for (result.tests_copying_model_text.sites, lines) |site, line| try std.testing.expectEqual(line, site.line);
}

test "T5.2 counts schema definition names used as comparisons or definition IDs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var inputs = inputs_template;
    inputs.files = &.{
        sourceFile("src/domain/a.zig", .production, &.{
            literalAt(1, "note", false, .equality),
            literalAt(2, "note", false, .definition_id),
            literalAt(3, "note", false, .plain), // not a branch
            literalAt(4, "description", false, .equality), // not a definition name
            literalAt(5, "note", true, .equality), // inline test
            passedAt(6, "note", "create", 2), // create's third parameter is a DefinitionId
            passedAt(7, "note", "create", 1),
            passedAt(8, "note", "packet", 0), // a method call skips `self`
            passedAt(9, "note", "other", 0),
        }),
        sourceFile("src/test_fixtures/b.zig", .tests, &.{literalAt(1, "note", false, .equality)}),
    };
    var declaring = sourceFile("src/domain/packets.zig", .production, &.{});
    declaring.definition_parameters = &.{
        .{ .function = "create", .ordinal = 2, .receiver = false },
        .{ .function = "packet", .ordinal = 1, .receiver = true },
    };
    inputs.files = &.{ inputs.files[0], inputs.files[1], declaring };
    const result = try count(arena.allocator(), inputs);
    try std.testing.expectEqual(@as(usize, 4), result.schema_name_branches.total);
    try std.testing.expectEqual(@as(usize, 2), result.schema_name_branches_in_tests.total);
}

test "T5.3 finds one instruction repeated across an asset and a schema" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const result = try count(arena.allocator(), inputs_template);
    try std.testing.expectEqual(@as(usize, 1), result.repeated_instructions.instructions);
    try std.testing.expectEqual(@as(usize, 2), result.repeated_instructions.sites);
    try std.testing.expect(std.mem.endsWith(u8, instruction, result.repeated_instructions.items[0].text));
    // An M literal repeating the instruction is a further site, named by its line.
    var engine = inputs_template;
    engine.freeze = &.{"Answer only. " ++ instruction};
    engine.files = &.{sourceFile("src/domain/a.zig", .production, &.{literalAt(9, "Answer only. " ++ instruction, false, .plain)})};
    // The prompt and the literal also share the longer ". Return one …", a second
    // maximal repeat with two sites.
    const repeated = (try count(arena.allocator(), engine)).repeated_instructions;
    try std.testing.expectEqual(@as(usize, 2), repeated.instructions);
    try std.testing.expectEqual(@as(usize, 5), repeated.sites);
    try std.testing.expectEqualStrings(instruction, repeated.items[0].text);
    try std.testing.expectEqual(@as(usize, 3), repeated.items[0].sites.len);
    try std.testing.expectEqual(@as(usize, 9), repeated.items[0].sites[2].line);
    var short = inputs_template;
    short.assets = &.{
        .{ .path = "design/workflows/demo/a.prompt.md", .bytes = instruction[0 .. span_minimum - 1] },
        .{ .path = "design/workflows/demo/b.prompt.md", .bytes = instruction[0 .. span_minimum - 1] },
    };
    try std.testing.expectEqual(@as(usize, 0), (try count(arena.allocator(), short)).repeated_instructions.instructions);
}

test "T5.5 counts model, case and source-specific decisions outside the provider adapters" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var inputs = inputs_template;
    inputs.files = &.{
        sourceFile("src/domain/a.zig", .production, &.{
            literalAt(1, "family-x", false, .equality),
            literalAt(2, "room-booking", false, .search),
            literalAt(3, "links one registered room, its requester, and", false, .equality), // 40-byte source span
            literalAt(4, "family-x", false, .plain), // not a decision
            literalAt(5, "room-booking", true, .equality), // inline test
            literalAt(6, "links one registered desk, its requester, and", false, .equality), // no 40-byte source span
        }),
        sourceFile("src/adapters/provider/request.zig", .production, &.{
            literalAt(1, "vendor.model-a", false, .equality), // the adapter's own model IDs
            literalAt(2, "room-booking", false, .equality),
        }),
    };
    const result = try count(arena.allocator(), inputs);
    try std.testing.expectEqual(@as(usize, 4), result.model_or_case_branches.total);
}

test "assets outside the workflow root are refused" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var inputs = inputs_template;
    inputs.assets = &.{.{ .path = "design/templates/spec.md", .bytes = "text" }};
    try std.testing.expectError(error.ForeignAsset, count(arena.allocator(), inputs));
}
