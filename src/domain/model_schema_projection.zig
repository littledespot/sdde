//! Deterministic serialization of one authoritative compiled result schema.
const std = @import("std");
const schema = @import("model_result_schema.zig");

/// Provider grammar is generation guidance; only the complete schema accepts data.
pub const Profile = enum { complete, bedrock };

pub fn render(allocator: std.mem.Allocator, selected: *const schema.Schema, profile: Profile) std.mem.Allocator.Error![]const u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    return std.json.Stringify.valueAlloc(allocator, try value(arena.allocator(), selected.root(), profile), .{});
}

pub fn value(allocator: std.mem.Allocator, node: *const schema.Node, profile: Profile) std.mem.Allocator.Error!std.json.Value {
    var object: std.json.ObjectMap = .{};
    switch (node.*) {
        .object => |properties| {
            try object.put(allocator, "type", .{ .string = "object" });
            var fields_value: std.json.ObjectMap = .{};
            var required: std.array_list.Managed(std.json.Value) = .init(allocator);
            for (properties) |property| {
                try fields_value.put(allocator, property.name, try value(allocator, property.schema, profile));
                if (property.required) try required.append(.{ .string = property.name });
            }
            try object.put(allocator, "properties", .{ .object = fields_value });
            try object.put(allocator, "required", .{ .array = required });
            try object.put(allocator, "additionalProperties", .{ .bool = false });
        },
        .string => |bounds| {
            try object.put(allocator, "type", .{ .string = "string" });
            if (profile == .complete) {
                if (bounds.minimum != 0) try object.put(allocator, "minLength", .{ .integer = bounds.minimum });
                try object.put(allocator, "maxLength", .{ .integer = bounds.maximum });
            }
        },
        .integer => |bounds| {
            try object.put(allocator, "type", .{ .string = "integer" });
            if (profile == .complete) {
                try object.put(allocator, "minimum", .{ .integer = bounds.minimum });
                try object.put(allocator, "maximum", .{ .integer = bounds.maximum });
            }
        },
        .boolean, .null_value => try object.put(allocator, "type", .{ .string = if (node.* == .boolean) "boolean" else "null" }),
        .constant => |scalar| try object.put(allocator, "const", switch (scalar) {
            .string => |v| .{ .string = v },
            .integer => |v| .{ .integer = v },
            .boolean => |v| .{ .bool = v },
            .null_value => .null,
        }),
        .enumeration => |choices| {
            var list: std.array_list.Managed(std.json.Value) = .init(allocator);
            for (choices) |choice| try list.append(.{ .string = choice });
            try object.put(allocator, "enum", .{ .array = list });
        },
        .array => |items| {
            try object.put(allocator, "type", .{ .string = "array" });
            try object.put(allocator, "items", try value(allocator, items.items, profile));
            if (items.minimum != 0) try object.put(allocator, "minItems", .{ .integer = if (profile == .complete) items.minimum else 1 });
            if (profile == .complete) try object.put(allocator, "maxItems", .{ .integer = items.maximum });
        },
        .one_of => |choices| {
            var list: std.array_list.Managed(std.json.Value) = .init(allocator);
            for (choices) |choice| try list.append(try value(allocator, choice, profile));
            // The schema compiler proves variants have distinct constant kind tags.
            try object.put(allocator, if (profile == .complete) "oneOf" else "anyOf", .{ .array = list });
        },
    }
    return .{ .object = object };
}
