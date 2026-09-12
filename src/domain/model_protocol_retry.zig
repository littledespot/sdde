//! Response-level syntax/schema correction. No semantic reconsideration or ID change.
const std = @import("std");
const schema = @import("model_result_schema.zig");
const preparation = @import("model_request_preparation.zig");
const provider = @import("llm_provider_operation.zig");
pub const Diagnostic = union(enum) { decoder: @import("strict_json.zig").Diagnostic, schema: @import("model_payload_schema.zig").Diagnostic };
pub fn build(allocator: std.mem.Allocator, source: preparation.Source, rejected: *const @import("provider_invocation_validation.zig").CompleteCandidate, diagnostic: Diagnostic, prompt: []const u8) preparation.Error!preparation.Owned {
    const original = rejected.association().request();
    if (original.model_request_id != source.request_binding.modelRequestId() or original.response_schema != try source.resultSchema()) return error.ModelRequestAssociationInvalid;
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const guidance = switch (diagnostic) {
        .decoder => |reason| try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .decoder = reason }, .schema_example = try example(scratch, original.response_schema.root()) }, .{}),
        .schema => |reason| try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = .{ .schema = try reason.describe(scratch) }, .example_path = (try reason.describeExpected(scratch)).path, .expected_shape_examples = try examples(scratch, reason.expected) }, .{}),
    };
    const response = try std.json.Stringify.valueAlloc(scratch, .{ .rejected_response = rejected.content() }, .{});
    const parts = try scratch.alloc(provider.ModelVisibleContent, original.content.len + 3);
    @memcpy(parts[0..original.content.len], original.content);
    parts[original.content.len] = .{ .guidance = prompt };
    parts[original.content.len + 1] = .{ .guidance = guidance };
    parts[original.content.len + 2] = .{ .evidence = response };
    return preparation.build(allocator, source, parts);
}

/// An illustrative value of the already compiled closed schema, never
/// candidate content or a semantic default. Callers own the scratch arena.
pub fn example(allocator: std.mem.Allocator, node: *const schema.Node) std.mem.Allocator.Error!std.json.Value {
    return switch (node.*) {
        .object => |fields| result: {
            var object: std.json.ObjectMap = .{};
            for (fields) |field| if (field.required) try object.put(allocator, field.name, try example(allocator, field.schema));
            break :result .{ .object = object };
        },
        .array => |items| result: {
            var array: std.array_list.Managed(std.json.Value) = .init(allocator);
            const count = @max(items.minimum, @min(1, items.maximum));
            for (0..count) |_| try array.append(try example(allocator, items.items));
            break :result .{ .array = array };
        },
        .string => |bounds| result: {
            const bytes = try allocator.alloc(u8, bounds.minimum);
            @memset(bytes, 'x');
            break :result .{ .string = bytes };
        },
        .integer => |bounds| .{ .integer = bounds.minimum },
        .boolean => .{ .bool = false },
        .null_value => .null,
        .constant => |scalar| switch (scalar) {
            .string => |value| .{ .string = value },
            .integer => |value| .{ .integer = value },
            .boolean => |value| .{ .bool = value },
            .null_value => .null,
        },
        .enumeration => |choices| .{ .string = choices[0] },
        .one_of => |choices| try example(allocator, choices[0]),
    };
}

fn examples(allocator: std.mem.Allocator, node: *const schema.Node) std.mem.Allocator.Error![]const std.json.Value {
    const nodes: []const *const schema.Node = if (node.* == .one_of) node.one_of else &.{node};
    const values = try allocator.alloc(std.json.Value, nodes.len);
    for (nodes, values) |choice, *value| value.* = try example(allocator, choice);
    return values;
}
