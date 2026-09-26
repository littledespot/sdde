//! Shared model input/response wire encoding, separate from native/persisted
//! Zig JSON. Evidence projections remove internal validation wrappers first.
//! Declared compact wrappers and disjoint values expand to native types;
//! discriminated objects become native unions. strict_json remains the closed
//! type/transport validator. No inferred variants or legacy wire reader.
//! Decoded values belong to the caller's arena; encoded bytes are caller-owned.
const std = @import("std");
const json = @import("strict_json.zig");
const limits: json.Limits = .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth };

pub fn decode(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8) json.Error!T {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try json.parse(a, bytes, limits, false, null);
    const input = if (comptime needsEnvelope(T)) blk: {
        if (parsed.value != .object or parsed.value.object.count() != 1) return error.InvalidJsonDocument;
        break :blk parsed.value.object.get("value") orelse return error.InvalidJsonDocument;
    } else parsed.value;
    const native = try transform(T, a, input, .native);
    const encoded = try std.json.Stringify.valueAlloc(a, native, .{});
    return json.decode(T, allocator, encoded, limits);
}

pub fn encode(comptime T: type, allocator: std.mem.Allocator, value: T) json.Error![]const u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    const parsed = try json.parse(a, bytes, limits, false, null);
    var wire = try transform(T, a, parsed.value, .wire);
    if (comptime needsEnvelope(T)) {
        var object: std.json.ObjectMap = .{};
        try object.put(a, "value", wire);
        wire = .{ .object = object };
    }
    return std.json.Stringify.valueAlloc(allocator, wire, .{});
}

/// A single result kind is selected by retained engine authority. Its payload
/// has no redundant root discriminator; nested unions keep their wire contract.
pub fn decodeSelected(comptime T: type, allocator: std.mem.Allocator, tag: std.meta.Tag(T), bytes: []const u8) json.Error!T {
    inline for (@typeInfo(T).@"union".fields) |field| {
        if (tag == @field(std.meta.Tag(T), field.name)) return @unionInit(T, field.name, try decode(field.type, allocator, bytes));
    }
    unreachable;
}

pub fn encodeSelected(comptime T: type, allocator: std.mem.Allocator, value: T) json.Error![]const u8 {
    return switch (value) {
        inline else => |payload| encode(@TypeOf(payload), allocator, payload),
    };
}

/// Declarations describe lossless wire structure only, never evidence policy.
fn declared(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union" => @hasDecl(T, name),
        else => false,
    };
}
fn needsEnvelope(comptime T: type) bool {
    return declared(T, "model_scalar") or declared(T, "model_inline");
}
fn inlineShape(comptime T: type) enum { string, array, number, boolean } {
    return switch (@typeInfo(T)) {
        .pointer => |p| if (p.size == .slice) (if (p.child == u8) .string else .array) else @compileError("Compact values require slices"),
        .int => .number,
        .bool => .boolean,
        else => @compileError("Inline model variants require a scalar or array"),
    };
}
fn checkInline(comptime T: type) void {
    const fields = @typeInfo(@TypeOf(T.model_inline)).@"struct".fields;
    inline for (fields, 0..) |entry, index| {
        const Payload = @FieldType(T, entry.name);
        const member = @field(T.model_inline, entry.name);
        if (@typeInfo(Payload) != .@"struct" or @typeInfo(Payload).@"struct".fields.len != 1) @compileError("Inline variants must wrap one field");
        const shape = inlineShape(@FieldType(Payload, member));
        inline for (fields[0..index]) |prior| {
            if (shape == inlineShape(@FieldType(@FieldType(T, prior.name), @field(T.model_inline, prior.name)))) @compileError("Inline variants must have disjoint JSON types");
        }
    }
}
fn scalarMatches(comptime T: type, value: std.json.Value) bool {
    return switch (comptime inlineShape(T)) {
        .string => value == .string,
        .array => value == .array,
        .number => value == .integer or value == .number_string,
        .boolean => value == .bool,
    };
}

const Direction = enum { native, wire };
fn transform(comptime T: type, a: std.mem.Allocator, value: std.json.Value, comptime direction: Direction) json.Error!std.json.Value {
    var result = value;
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (comptime declared(T, "model_scalar")) {
                const name = T.model_scalar;
                if (s.fields.len != 1 or !@hasField(T, name)) @compileError("A compact wrapper must have exactly its declared field");
                if (direction == .wire) {
                    if (value != .object or value.object.count() != 1) return error.InvalidJsonDocument;
                    return transform(@FieldType(T, name), a, value.object.get(name) orelse return error.InvalidJsonDocument, direction);
                }
                var object: std.json.ObjectMap = .{};
                try object.put(a, name, try transform(@FieldType(T, name), a, value, direction));
                return .{ .object = object };
            }
            return transformFields(T, a, value, direction);
        },
        .@"union" => |u| {
            if (u.tag_type == null) @compileError("Model candidates require tagged unions");
            if (comptime declared(T, "model_inline")) {
                comptime checkInline(T);
                inline for (u.fields) |field| if (comptime @hasField(@TypeOf(T.model_inline), field.name)) {
                    const member = @field(T.model_inline, field.name);
                    const Child = @FieldType(field.type, member);
                    if (direction == .native and scalarMatches(Child, value)) {
                        var payload: std.json.ObjectMap = .{};
                        try payload.put(a, member, try transform(Child, a, value, direction));
                        var object: std.json.ObjectMap = .{};
                        try object.put(a, field.name, .{ .object = payload });
                        return .{ .object = object };
                    }
                    if (direction == .wire and value == .object and value.object.count() == 1) {
                        if (value.object.get(field.name)) |payload| {
                            if (payload != .object or payload.object.count() != 1) return error.InvalidJsonDocument;
                            return transform(Child, a, payload.object.get(member) orelse return error.InvalidJsonDocument, direction);
                        }
                    }
                };
            }
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
                if (comptime declared(T, "model_inline")) {
                    if (comptime @hasField(@TypeOf(T.model_inline), field.name)) return error.InvalidJsonDocument;
                }
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
                    try object.put(a, field.name, if (comptime direct) try transformFields(field.type, a, child, direction) else try transform(field.type, a, child, direction));
                } else {
                    const child = if (comptime direct) try transformFields(field.type, a, value.object.values()[0], direction) else try transform(field.type, a, value.object.values()[0], direction);
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

fn transformFields(comptime T: type, a: std.mem.Allocator, value: std.json.Value, comptime direction: Direction) json.Error!std.json.Value {
    const s = @typeInfo(T).@"struct";
    var result: std.json.Value = .{ .object = .{} };
    if (value != .object or value.object.count() > s.fields.len) return error.InvalidJsonDocument;
    for (value.object.keys()) |key| {
        var known = false;
        inline for (s.fields) |field| if (std.mem.eql(u8, key, field.name)) {
            known = true;
        };
        if (!known) return error.InvalidJsonDocument;
    }
    inline for (s.fields) |field| {
        const child = value.object.get(field.name) orelse if (@typeInfo(field.type) == .optional and field.default_value_ptr != null) .null else return error.InvalidJsonDocument;
        if (!(direction == .wire and @typeInfo(field.type) == .optional and field.default_value_ptr != null and child == .null)) try result.object.put(a, field.name, try transform(field.type, a, child, direction));
    }
    return result;
}
