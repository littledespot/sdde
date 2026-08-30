const std = @import("std");
const syntax = @import("bounded_yaml_syntax");
const workflow = @import("../../domain/workflow_registry.zig");
const parser_port = @import("../../ports/workflow_definition_parser.zig");

pub const Adapter = struct {
    pub fn parser(self: *Adapter) parser_port.Parser {
        return .{ .context = self, .parse_fn = parse };
    }

    fn parse(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        captures: []const workflow.Capture,
    ) parser_port.Error![]const workflow.RawDefinition {
        const definitions = allocator.alloc(workflow.RawDefinition, captures.len) catch {
            return error.InvalidWorkflowDefinition;
        };
        for (captures, definitions) |capture, *definition| {
            if (!std.unicode.utf8ValidateSlice(capture.bytes) or
                std.mem.startsWith(u8, capture.bytes, "\xef\xbb\xbf"))
            {
                return error.InvalidWorkflowDefinition;
            }
            var diagnostic: syntax.Diagnostic = .{};
            var loaded = syntax.parse(allocator, capture.bytes, .{
                .max_input_bytes = workflow.max_definition_bytes,
                .max_event_count = workflow.max_yaml_events,
                .max_token_count = workflow.max_yaml_tokens,
                .max_nesting_depth = workflow.max_yaml_nesting_depth,
                .max_scalar_bytes = workflow.max_yaml_scalar_bytes,
            }, &diagnostic) catch return error.InvalidWorkflowDefinition;
            defer loaded.deinit();
            if (loaded.root.* != .mapping) return error.InvalidWorkflowDefinition;
            definition.* = .{
                .ordinal = capture.ordinal,
                .root = convert(allocator, loaded.root) catch {
                    return error.InvalidWorkflowDefinition;
                },
            };
        }
        return definitions;
    }
};

fn convert(allocator: std.mem.Allocator, source: *const syntax.Node) !*workflow.RawNode {
    const destination = try allocator.create(workflow.RawNode);
    destination.* = switch (source.*) {
        .null_value => .null_value,
        .bool_value => |value| .{ .boolean = value.value },
        .int_value => |value| .{ .integer = value.value },
        .float_value => |value| .{ .float = value.value },
        .scalar => |value| .{ .scalar = try allocator.dupe(u8, value.value) },
        .sequence => |sequence| blk: {
            const items = try allocator.alloc(*workflow.RawNode, sequence.items.len);
            for (sequence.items, items) |item, *converted| {
                converted.* = try convert(allocator, item);
            }
            break :blk .{ .sequence = items };
        },
        .mapping => |mapping| blk: {
            const pairs = try allocator.alloc(workflow.RawPair, mapping.pairs.len);
            for (mapping.pairs, pairs) |pair, *converted| {
                converted.* = .{
                    .key = try convert(allocator, pair.key),
                    .value = try convert(allocator, pair.value),
                };
            }
            break :blk .{ .mapping = pairs };
        },
        .alias => return error.InvalidWorkflowDefinition,
    };
    return destination;
}

test "parses strict YAML into a workflow-owned raw value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var adapter: Adapter = .{};
    const captures = [_]workflow.Capture{.{
        .ordinal = 1,
        .bytes =
        \\schemaVersion: "1.0"
        \\workflowId: hello
        \\workflowVersion: 1
        \\workflowShortcode: HELO
        \\invocationContractNodeId: core.empty@1
        \\workflowPolicyProfileId: core.safe@1
        \\entryWorkflowNodeId: run
        \\nodes: []
        \\transitions: []
        ,
    }};
    const definitions = try adapter.parser().parse(arena.allocator(), &captures);
    try std.testing.expectEqual(@as(u16, 1), definitions[0].ordinal);
    try std.testing.expect(definitions[0].root.* == .mapping);
}

test "rejects duplicate keys aliases custom tags multiple documents and scalar overflow" {
    const invalid = [_][]const u8{
        "value: one\nvalue: two\n",
        "base: &base value\ncopy: *base\n",
        "value: !custom tagged\n",
        "---\nvalue: one\n---\nvalue: two\n",
        "- one\n- two\n",
        "{unterminated\n",
        "\xef\xbb\xbfvalue: one\n",
        "value: \xff\n",
    };
    for (invalid) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        var adapter: Adapter = .{};
        const captures = [_]workflow.Capture{.{ .ordinal = 1, .bytes = bytes }};
        try std.testing.expectError(
            error.InvalidWorkflowDefinition,
            adapter.parser().parse(arena.allocator(), &captures),
        );
    }

    const exact = try std.testing.allocator.alloc(u8, workflow.max_yaml_scalar_bytes);
    defer std.testing.allocator.free(exact);
    @memset(exact, 'a');
    const exact_bytes = try std.fmt.allocPrint(std.testing.allocator, "value: {s}\n", .{exact});
    defer std.testing.allocator.free(exact_bytes);
    var exact_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exact_arena.deinit();
    var exact_adapter: Adapter = .{};
    const exact_capture = [_]workflow.Capture{.{ .ordinal = 1, .bytes = exact_bytes }};
    _ = try exact_adapter.parser().parse(exact_arena.allocator(), &exact_capture);

    const oversized = try std.testing.allocator.alloc(u8, workflow.max_yaml_scalar_bytes + 1);
    defer std.testing.allocator.free(oversized);
    @memset(oversized, 'a');
    const bytes = try std.fmt.allocPrint(std.testing.allocator, "value: {s}\n", .{oversized});
    defer std.testing.allocator.free(bytes);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var adapter: Adapter = .{};
    const captures = [_]workflow.Capture{.{ .ordinal = 1, .bytes = bytes }};
    try std.testing.expectError(
        error.InvalidWorkflowDefinition,
        adapter.parser().parse(arena.allocator(), &captures),
    );
}

test "comments and equivalent block and flow YAML have identical raw authority" {
    const block =
        \\# comment has no authority
        \\schemaVersion: "1.0"
        \\workflowId: hello
        \\workflowVersion: 1
        \\workflowShortcode: HELO
        \\invocationContractNodeId: core.empty@1
        \\workflowPolicyProfileId: core.safe@1
        \\entryWorkflowNodeId: run
        \\nodes: []
        \\transitions: []
    ;
    const flow = "{schemaVersion: '1.0', workflowId: hello, workflowVersion: 1, workflowShortcode: HELO, invocationContractNodeId: core.empty@1, workflowPolicyProfileId: core.safe@1, entryWorkflowNodeId: run, nodes: [], transitions: []}\n";
    var block_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer block_arena.deinit();
    var flow_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer flow_arena.deinit();
    var adapter: Adapter = .{};
    const block_values = try adapter.parser().parse(block_arena.allocator(), &.{.{ .ordinal = 1, .bytes = block }});
    const flow_values = try adapter.parser().parse(flow_arena.allocator(), &.{.{ .ordinal = 1, .bytes = flow }});
    try std.testing.expectEqualDeep(block_values[0].root.*, flow_values[0].root.*);
}

test "workflow YAML nesting accepts the exact limit and rejects one more" {
    const exact = try nestedMapping(std.testing.allocator, workflow.max_yaml_nesting_depth);
    defer std.testing.allocator.free(exact);
    var exact_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exact_arena.deinit();
    var adapter: Adapter = .{};
    _ = try adapter.parser().parse(exact_arena.allocator(), &.{.{ .ordinal = 1, .bytes = exact }});

    const exceeded = try nestedMapping(std.testing.allocator, workflow.max_yaml_nesting_depth + 1);
    defer std.testing.allocator.free(exceeded);
    var exceeded_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer exceeded_arena.deinit();
    try std.testing.expectError(
        error.InvalidWorkflowDefinition,
        adapter.parser().parse(exceeded_arena.allocator(), &.{.{ .ordinal = 1, .bytes = exceeded }}),
    );
}

fn nestedMapping(allocator: std.mem.Allocator, depth: usize) ![]const u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);
    for (0..depth) |index| {
        for (0..index) |_| try bytes.appendSlice(allocator, "  ");
        try bytes.appendSlice(allocator, if (index + 1 == depth) "key: value\n" else "key:\n");
    }
    return bytes.toOwnedSlice(allocator);
}
