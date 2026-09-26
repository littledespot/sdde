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

/// Locate a bound node in the complete selected projection, not in candidate
/// data or the resource's unselected definitions. Foreign nodes have no locator.
pub fn locate(allocator: std.mem.Allocator, selected: *const schema.Schema, target: *const schema.Node) std.mem.Allocator.Error!?[]const u8 {
    const pointer = @import("json_pointer.zig");
    var path: [schema.max_depth * 2 + 2]pointer.Segment = undefined;
    const length = locateNode(selected.root(), target, &path, 0) orelse return null;
    return try pointer.render(allocator, path[0..length]);
}

fn locateNode(node: *const schema.Node, target: *const schema.Node, path: []@import("json_pointer.zig").Segment, depth: usize) ?usize {
    if (node == target) return depth;
    switch (node.*) {
        .object => |properties| for (properties) |property| {
            path[depth] = .{ .property = "properties" };
            path[depth + 1] = .{ .property = property.name };
            if (locateNode(property.schema, target, path, depth + 2)) |length| return length;
        },
        .array => |items| {
            path[depth] = .{ .property = "items" };
            return locateNode(items.items, target, path, depth + 1);
        },
        .one_of => |choices| for (choices, 0..) |choice, index| {
            path[depth] = .{ .property = "oneOf" };
            path[depth + 1] = .{ .index = index };
            if (locateNode(choice, target, path, depth + 2)) |length| return length;
        },
        else => {},
    }
    return null;
}

/// Immediate fields, child-object requirements and tags, without child schemas.
/// This is guidance only; the complete selected schema retains every constraint.
pub fn outline(allocator: std.mem.Allocator, node: *const schema.Node) std.mem.Allocator.Error!std.json.Value {
    switch (node.*) {
        .object => |properties| {
            var object: std.json.ObjectMap = .{};
            var fields: std.json.ObjectMap = .{};
            for (properties) |property| {
                try fields.put(allocator, property.name, try fieldOutline(allocator, property.schema));
            }
            try object.put(allocator, "fields", .{ .object = fields });
            try object.put(allocator, "required", try requiredFields(allocator, properties));
            return .{ .object = object };
        },
        .one_of => |choices| {
            var alternatives: std.array_list.Managed(std.json.Value) = .init(allocator);
            for (choices) |choice| try alternatives.append(try outline(allocator, choice));
            var object: std.json.ObjectMap = .{};
            try object.put(allocator, "alternatives", .{ .array = alternatives });
            return .{ .object = object };
        },
        .array => |items| {
            var object = (try fieldOutline(allocator, node)).object;
            try object.put(allocator, "minItems", .{ .integer = items.minimum });
            try object.put(allocator, "maxItems", .{ .integer = items.maximum });
            return .{ .object = object };
        },
        .integer_enumeration => {
            var object: std.json.ObjectMap = .{};
            try object.put(allocator, "type", .{ .string = "integer" });
            return .{ .object = object };
        },
        else => return value(allocator, node, .complete),
    }
}

fn fieldOutline(allocator: std.mem.Allocator, node: *const schema.Node) std.mem.Allocator.Error!std.json.Value {
    var object: std.json.ObjectMap = .{};
    switch (node.*) {
        .object => |properties| {
            try object.put(allocator, "type", .{ .string = "object" });
            try object.put(allocator, "required", try requiredFields(allocator, properties));
        },
        .array => try object.put(allocator, "type", .{ .string = "array" }),
        .one_of => |choices| {
            var tags: std.array_list.Managed(std.json.Value) = .init(allocator);
            var types: std.array_list.Managed(std.json.Value) = .init(allocator);
            for (choices) |choice| {
                if (choice.* == .object) try tags.append(.{ .string = schema.findProperty(choice.object, "kind").?.schema.constant.string }) else try types.append(.{ .string = if (schema.jsonType(choice).? == .null_value) "null" else @tagName(schema.jsonType(choice).?) });
            }
            if (tags.items.len != 0) try object.put(allocator, "kind", .{ .array = tags });
            if (types.items.len != 0) try object.put(allocator, "types", .{ .array = types });
        },
        .integer_enumeration => try object.put(allocator, "type", .{ .string = "integer" }),
        else => return value(allocator, node, .complete),
    }
    return .{ .object = object };
}

fn requiredFields(allocator: std.mem.Allocator, properties: []const schema.Property) std.mem.Allocator.Error!std.json.Value {
    var required: std.array_list.Managed(std.json.Value) = .init(allocator);
    for (properties) |property| {
        if (property.required) try required.append(.{ .string = property.name });
    }
    return .{ .array = required };
}

pub fn value(allocator: std.mem.Allocator, node: *const schema.Node, profile: Profile) std.mem.Allocator.Error!std.json.Value {
    var object: std.json.ObjectMap = .{};
    switch (node.*) {
        .object => |properties| {
            try object.put(allocator, "type", .{ .string = "object" });
            var fields_value: std.json.ObjectMap = .{};
            for (properties) |property| {
                try fields_value.put(allocator, property.name, try value(allocator, property.schema, profile));
            }
            try object.put(allocator, "properties", .{ .object = fields_value });
            try object.put(allocator, "required", try requiredFields(allocator, properties));
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
        .integer_enumeration => |choices| {
            var list: std.array_list.Managed(std.json.Value) = .init(allocator);
            for (choices) |choice| try list.append(.{ .integer = choice });
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
            // The compiler proves disjoint JSON types or distinct constant kind tags.
            try object.put(allocator, if (profile == .complete) "oneOf" else "anyOf", .{ .array = list });
        },
    }
    return .{ .object = object };
}
