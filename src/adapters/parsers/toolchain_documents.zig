const std = @import("std");
const syntax = @import("bounded_yaml_syntax");
const toolchain = @import("../../domain/toolchain.zig");
const toolchain_schema = @import("../../domain/toolchain_schema.zig");
const parser_port = @import("../../ports/toolchain_document_parser.zig");
pub const Adapter = struct {
    pub fn parser(self: *Adapter) parser_port.Parser {
        return .{ .context = self, .parse_fn = parse };
    }
    fn parse(_: *anyopaque, allocator: std.mem.Allocator, captures: []const toolchain.Capture) parser_port.Error![]const toolchain.RawDocument {
        const result = allocator.alloc(toolchain.RawDocument, captures.len) catch return error.InvalidToolchainDocument;
        for (captures, result) |capture, *document| {
            var diagnostic: syntax.Diagnostic = .{};
            var loaded = syntax.parse(allocator, capture.bytes, .{
                .max_input_bytes = toolchain.max_document_bytes,
                .max_event_count = toolchain.max_yaml_events,
                .max_token_count = toolchain.max_yaml_tokens,
                .max_nesting_depth = toolchain.max_yaml_nesting_depth,
                .max_scalar_bytes = toolchain.max_yaml_scalar_bytes,
            }, &diagnostic) catch return error.InvalidToolchainDocument;
            defer loaded.deinit();
            document.* = .{ .name = capture.name, .root = convert(allocator, loaded.root) catch return error.InvalidToolchainDocument };
        }
        return result;
    }
};
fn convert(allocator: std.mem.Allocator, source: *const syntax.Node) toolchain.Error!*toolchain.RawNode {
    const destination = allocator.create(toolchain.RawNode) catch return error.InvalidToolchain;
    destination.* = switch (source.*) {
        .scalar => |value| .{ .scalar = allocator.dupe(u8, value.value) catch return error.InvalidToolchain },
        .sequence => |sequence| blk: {
            const items = allocator.alloc(*const toolchain.RawNode, sequence.items.len) catch return error.InvalidToolchain;
            for (sequence.items, items) |item, *converted| converted.* = try convert(allocator, item);
            break :blk .{ .sequence = items };
        },
        .mapping => |mapping| blk: {
            const pairs = allocator.alloc(toolchain.Pair, mapping.pairs.len) catch return error.InvalidToolchain;
            for (mapping.pairs, pairs) |pair, *converted| converted.* = .{ .key = try convert(allocator, pair.key), .value = try convert(allocator, pair.value) };
            break :blk .{ .mapping = pairs };
        },
        else => return error.InvalidToolchain,
    };
    return destination;
}

test "parses the closed project and preset YAML shapes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var adapter: Adapter = .{};
    const captures = [_]toolchain.Capture{
        .{ .name = toolchain.project_filename, .bytes = "schema: project-toolchain/v1\npresets: [app@1.0.0]\npolicies: []\n" },
        .{ .name = "app.toolchain-preset.yaml", .bytes = "schema: toolchain-preset/v1\npackage: app@1.0.0\nlayer: framework\nextends: []\npolicies: []\n" },
    };
    const documents = try adapter.parser().parse(arena.allocator(), &captures);
    const project = try toolchain_schema.parseProject(arena.allocator(), documents[0]);
    const registry = try toolchain_schema.parseRegistry(arena.allocator(), documents[1..]);
    try std.testing.expectEqualStrings("app@1.0.0", project.presets[0]);
    try std.testing.expectEqualStrings("app@1.0.0", registry.presets[0].package);
}

test "rejects unsafe YAML and closed-schema violations" {
    const syntax_invalid = [_][]const u8{
        "schema: project-toolchain/v1\nschema: duplicate\npresets: []\npolicies: []\n",
        "base: &base value\ncopy: *base\n",
        "value: !custom tagged\n",
        "---\nschema: project-toolchain/v1\n---\nschema: project-toolchain/v1\n",
    };
    for (syntax_invalid) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var adapter: Adapter = .{};
        const captures = [_]toolchain.Capture{.{ .name = toolchain.project_filename, .bytes = bytes }};
        try std.testing.expectError(
            error.InvalidToolchainDocument,
            adapter.parser().parse(arena.allocator(), &captures),
        );
    }

    const schema_invalid = [_][]const u8{
        "schema: project-toolchain/v1\npresets: []\npolicies: []\nunknown: rejected\n",
        "schema: project-toolchain/v1\npresets: latest\npolicies: []\n",
        "version: \"1.0\"\nframework: placeholder\n",
    };
    for (schema_invalid) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var adapter: Adapter = .{};
        const captures = [_]toolchain.Capture{.{ .name = toolchain.project_filename, .bytes = bytes }};
        const documents = try adapter.parser().parse(arena.allocator(), &captures);
        try std.testing.expectError(
            error.InvalidToolchain,
            toolchain_schema.parseProject(arena.allocator(), documents[0]),
        );
    }
}

test "enforces the compiler-owned scalar limit" {
    const scalar = try std.testing.allocator.alloc(u8, toolchain.max_yaml_scalar_bytes + 1);
    defer std.testing.allocator.free(scalar);
    @memset(scalar, 'a');
    const bytes = try std.fmt.allocPrint(std.testing.allocator, "value: {s}\n", .{scalar});
    defer std.testing.allocator.free(bytes);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var adapter: Adapter = .{};
    const captures = [_]toolchain.Capture{.{ .name = toolchain.project_filename, .bytes = bytes }};
    try std.testing.expectError(
        error.InvalidToolchainDocument,
        adapter.parser().parse(arena.allocator(), &captures),
    );
}
