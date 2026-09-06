//! ADR 0006 model wire encoding, separate from native/persisted Zig JSON.
//! Discriminated objects become native unions; strict_json remains the closed
//! type/transport validator. No inferred variants or legacy wire reader.
//! Decoded values belong to the caller's arena; encoded bytes are caller-owned.
const std = @import("std");
const json = @import("strict_json.zig");
const limits: json.Limits = .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth };

pub fn decode(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8) json.Error!T {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try json.parse(a, bytes, limits, false);
    const native = try transform(T, a, parsed.value, .native);
    const encoded = try std.json.Stringify.valueAlloc(a, native, .{});
    return json.decode(T, allocator, encoded, limits);
}

pub fn encode(comptime T: type, allocator: std.mem.Allocator, value: T) json.Error![]const u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    const parsed = try json.parse(a, bytes, limits, false);
    const wire = try transform(T, a, parsed.value, .wire);
    return std.json.Stringify.valueAlloc(allocator, wire, .{});
}

const Direction = enum { native, wire };
fn transform(comptime T: type, a: std.mem.Allocator, value: std.json.Value, comptime direction: Direction) json.Error!std.json.Value {
    var result = value;
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (value != .object or value.object.count() != s.fields.len) return error.InvalidJsonDocument;
            result = .{ .object = .{} };
            inline for (s.fields) |field| {
                const child = value.object.get(field.name) orelse return error.InvalidJsonDocument;
                try result.object.put(a, field.name, try transform(field.type, a, child, direction));
            }
        },
        .@"union" => |u| {
            if (u.tag_type == null) @compileError("Model candidates require tagged unions");
            if (value != .object) return error.InvalidJsonDocument;
            const tag = if (direction == .native) blk: {
                const kind = value.object.get("kind") orelse return error.InvalidJsonDocument;
                if (kind != .string) return error.InvalidJsonDocument;
                break :blk kind.string;
            } else blk: {
                if (value.object.count() != 1) return error.InvalidJsonDocument;
                break :blk value.object.keys()[0];
            };
            inline for (u.fields) |field| if (std.mem.eql(u8, tag, field.name)) {
                // A struct's candidate fields are direct. A nested non-struct
                // variant (or a domain field named kind) retains its own name.
                const direct = comptime @typeInfo(field.type) == .@"struct" and !@hasField(field.type, "kind");
                var object: std.json.ObjectMap = .{};
                if (direction == .native) {
                    var child = value;
                    if (direct) {
                        child = .{ .object = .{} };
                        for (value.object.keys(), value.object.values()) |name, item| {
                            if (!std.mem.eql(u8, name, "kind")) try child.object.put(a, name, item);
                        }
                    } else {
                        if (value.object.count() != 2) return error.InvalidJsonDocument;
                        child = value.object.get(field.name) orelse return error.InvalidJsonDocument;
                    }
                    try object.put(a, field.name, try transform(field.type, a, child, direction));
                } else {
                    const child = try transform(field.type, a, value.object.values()[0], direction);
                    if (direct) object = child.object else try object.put(a, field.name, child);
                    try object.put(a, "kind", .{ .string = field.name });
                }
                return .{ .object = object };
            };
            return error.InvalidJsonDocument;
        },
        .pointer => |p| {
            if (p.size != .slice) @compileError("Model candidates require slices");
            if (p.child != u8) {
                if (value != .array) return error.InvalidJsonDocument;
                result = .{ .array = .init(a) };
                for (value.array.items) |child| try result.array.append(try transform(p.child, a, child, direction));
            }
        },
        .optional => |o| if (value != .null) return transform(o.child, a, value, direction),
        .int => if (direction == .native and value == .number_string) {
            // JSON Schema integers include exact decimal/exponent spellings.
            // Reuse the payload validator's arithmetic, never round a float.
            result = .{ .integer = @import("model_payload_schema.zig").exactInteger(value.number_string) catch return error.InvalidJsonDocument };
        },
        else => {}, // strict_json owns scalar wire kinds and ranges
    }
    return result;
}
