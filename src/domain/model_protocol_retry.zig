//! Response-level syntax/schema correction. No semantic reconsideration or ID change.
const std = @import("std");
const schema = @import("model_result_schema.zig");
const preparation = @import("model_request_preparation.zig");
const provider = @import("llm_provider_operation.zig");
pub const Diagnostic = union(enum) { decoder: enum { invalid_json_object }, schema: @import("model_payload_schema.zig").Rejection };
pub fn build(allocator: std.mem.Allocator, source: preparation.Source, original: *const provider.IdentifiedProviderNeutralModelRequest, diagnostic: Diagnostic, prompt: []const u8) preparation.Error!preparation.Owned {
    if (original.model_request_id != source.request_binding.modelRequestId() or original.response_schema != try source.resultSchema()) return error.ModelRequestAssociationInvalid;
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const guidance = try std.json.Stringify.valueAlloc(scratch, .{ .diagnostic = diagnostic, .minimal_schema_example = try example(scratch, original.response_schema.root()) }, .{});
    const parts = try scratch.alloc(provider.ModelVisibleContent, original.content.len + 2);
    @memcpy(parts[0..original.content.len], original.content);
    parts[original.content.len] = .{ .guidance = prompt };
    parts[original.content.len + 1] = .{ .guidance = guidance };
    return preparation.build(allocator, source, parts);
}

/// An illustrative minimum value of the already compiled closed schema, never
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
            for (0..items.minimum) |_| try array.append(try example(allocator, items.items));
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
