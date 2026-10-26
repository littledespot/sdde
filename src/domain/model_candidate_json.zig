//! Shared model input/response wire encoding, separate from native/persisted
//! Zig JSON. Evidence projections remove internal validation wrappers first.
//! Declared compact wrappers, text fields and disjoint values expand to native types;
//! discriminated objects become native unions. strict_json remains the closed
//! type/transport validator. No inferred variants or legacy wire reader.
//! Decoded values belong to the caller's arena; encoded bytes are caller-owned.
const std = @import("std");
const json = @import("strict_json.zig");
const limits: json.Limits = .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth };
pub const FieldOptions = struct { inherited: ?@import("text_field_policy.zig").Field = null, reference_phase: ?@import("text_field_policy.zig").ReferencePhase = null };
pub const FieldError = std.mem.Allocator.Error || error{InvalidModelTextBinding};
pub fn fieldBindings(comptime T: type, a: std.mem.Allocator, options: FieldOptions) FieldError![]const @import("model_text_field.zig").Binding {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    var path: std.ArrayList(@import("model_text_field.zig").Step) = .empty;
    var result: std.ArrayList(@import("model_text_field.zig").Binding) = .empty;
    if (comptime needsEnvelope(T)) try path.append(scratch, .{ .property = "value" });
    try collectFields(T, scratch, options, &path, &result);
    return @import("model_text_field.zig").clone(a, result.items);
}
pub fn selectedFieldBindings(comptime T: type, a: std.mem.Allocator, tag: std.meta.Tag(T), options: FieldOptions) FieldError![]const @import("model_text_field.zig").Binding {
    inline for (@typeInfo(T).@"union".fields) |field| if (tag == @field(std.meta.Tag(T), field.name)) {
        var selected = options;
        selected.inherited = try declaredField(T, field.name, options);
        return fieldBindings(field.type, a, selected);
    };
    unreachable;
}
fn declaredField(comptime T: type, comptime name: []const u8, options: FieldOptions) FieldError!?@import("text_field_policy.zig").Field {
    if (comptime declared(T, "model_fields")) if (comptime @hasField(@TypeOf(T.model_fields), name)) return @field(T.model_fields, name);
    if (comptime declared(T, "model_prose")) if (comptime @hasField(@TypeOf(T.model_prose), name)) return @field(T.model_prose, name);
    if (comptime declared(T, "model_reference_fields")) return switch (options.reference_phase orelse return error.InvalidModelTextBinding) {
        .extraction => @import("text_field_policy.zig").referenceField(.extraction, name),
        .reconciliation => @import("text_field_policy.zig").referenceField(.reconciliation, name),
    };
    return options.inherited;
}
fn collectFields(comptime T: type, a: std.mem.Allocator, options: FieldOptions, path: *std.ArrayList(@import("model_text_field.zig").Step), result: *std.ArrayList(@import("model_text_field.zig").Binding)) FieldError!void {
    // Some domain codecs deliberately separate admitted canonical evidence from
    // their smaller wire value. Only that declared wire shape has model fields.
    if (comptime declared(T, "model_field_projection")) return collectFields(T.model_field_projection, a, options, path, result);
    const old = path.items.len;
    defer path.shrinkRetainingCapacity(old);
    switch (@typeInfo(T)) {
        .@"struct" => |shape| {
            if (comptime declared(T, "model_scalar")) {
                if (comptime declared(T, "model_text")) {
                    try result.append(a, .{ .field = options.inherited orelse return error.InvalidModelTextBinding, .path = try a.dupe(@import("model_text_field.zig").Step, path.items) });
                    return;
                }
                return collectFields(@FieldType(T, T.model_scalar), a, options, path, result);
            }
            inline for (shape.fields) |field| {
                var selected = options;
                selected.inherited = try declaredField(T, field.name, options);
                try path.append(a, .{ .property = field.name });
                if (comptime (declared(T, "model_text") and std.mem.eql(u8, T.model_text, field.name)) or (declared(T, "model_prose") and @hasField(@TypeOf(T.model_prose), field.name))) {
                    try result.append(a, .{ .field = selected.inherited orelse return error.InvalidModelTextBinding, .path = try a.dupe(@import("model_text_field.zig").Step, path.items) });
                } else try collectFields(field.type, a, selected, path, result);
                _ = path.pop();
            }
        },
        .@"union" => |shape| {
            inline for (shape.fields) |field| {
                if (comptime derivedNode(T, field.name)) continue;
                if (comptime declared(T, "model_inline") and @hasField(@TypeOf(T.model_inline), field.name)) continue;
                var selected = options;
                selected.inherited = try declaredField(T, field.name, options);
                try path.append(a, .{ .variant = comptime wireTag(T, field.name) });
                const direct = comptime @typeInfo(field.type) == .@"struct" and !@hasField(field.type, "kind");
                if (!direct) try path.append(a, .{ .property = comptime wireTag(T, field.name) });
                try collectFields(field.type, a, selected, path, result);
                if (!direct) _ = path.pop();
                _ = path.pop();
            }
        },
        .pointer => |pointer| if (pointer.size == .slice and pointer.child != u8) {
            try path.append(a, .items);
            try collectFields(pointer.child, a, options, path, result);
        },
        .optional => |optional| try collectFields(optional.child, a, options, path, result),
        else => {},
    }
}

/// Restore only engine-determined fields from the same native choices that
/// selected the response schema. Raw provider bytes remain untouched evidence.
/// This does not infer support, choose among alternatives or accept echoed IDs.
pub fn constructBound(allocator: std.mem.Allocator, bytes: []const u8, choices: []const @import("model_result_schema.zig").IntegerChoice) json.Error![]const u8 {
    var needed = false;
    for (choices) |choice| if (choice.constructedValue() != null) {
        if (choice.target != .tagged or choice.definition != null) return error.InvalidJsonDocument;
        needed = true;
    };
    if (!needed) return allocator.dupe(u8, bytes);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parsed = try json.parse(a, bytes, limits, false, null);
    try constructFields(a, &parsed.value, choices);
    return std.json.Stringify.valueAlloc(allocator, parsed.value, .{});
}

fn constructFields(a: std.mem.Allocator, value: *std.json.Value, choices: []const @import("model_result_schema.zig").IntegerChoice) json.Error!void {
    switch (value.*) {
        .object => |*object| {
            for (object.values()) |*child| try constructFields(a, child, choices);
            const tag = object.get("kind") orelse return;
            if (tag != .string) return;
            for (choices) |choice| {
                const native = choice.constructedValue() orelse continue;
                const target = choice.target.tagged;
                if (!std.mem.eql(u8, target.kind, tag.string)) continue;
                if (object.contains(target.field)) return error.InvalidJsonDocument;
                try object.put(a, target.field, .{ .integer = native });
            }
        },
        .array => |*array| for (array.items) |*child| try constructFields(a, child, choices),
        else => {},
    }
}

pub fn decode(comptime T: type, allocator: std.mem.Allocator, bytes: []const u8) json.Error!T {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const parsed = try json.parse(a, bytes, limits, false, null);
    const input = if (comptime needsEnvelope(T)) blk: {
        if (parsed.value != .object or parsed.value.object.count() != 1) return error.InvalidJsonDocument;
        break :blk parsed.value.object.get("value") orelse return error.InvalidJsonDocument;
    } else parsed.value;
    const native = try transform(T, a, input, .native, .model_response);
    const encoded = try std.json.Stringify.valueAlloc(a, native, .{});
    return json.decode(T, allocator, encoded, limits);
}

pub fn encode(comptime T: type, allocator: std.mem.Allocator, value: T) json.Error![]const u8 {
    return encodeFor(T, allocator, value, .model_response);
}

/// Native input evidence retains engine-derived identities as sealed facts.
/// This purpose never changes model response schemas or decoding authority.
pub fn encodeEvidence(comptime T: type, allocator: std.mem.Allocator, value: T) json.Error![]const u8 {
    return encodeFor(T, allocator, value, .native_evidence);
}

const EncodingPurpose = enum { model_response, native_evidence };
fn encodeFor(comptime T: type, allocator: std.mem.Allocator, value: T, comptime purpose: EncodingPurpose) json.Error![]const u8 {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    const parsed = try json.parse(a, bytes, limits, false, null);
    var wire = try transform(T, a, parsed.value, .wire, purpose);
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

/// A native authorization may expose the selected old value as evidence while
/// its independently selected response contract still excludes derived nodes.
pub fn encodeSelectedEvidence(comptime T: type, allocator: std.mem.Allocator, value: T) json.Error![]const u8 {
    return switch (value) {
        inline else => |payload| encodeEvidence(@TypeOf(payload), allocator, payload),
    };
}

/// Declarations describe lossless wire structure only, never evidence policy.
fn declared(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union" => @hasDecl(T, name),
        else => false,
    };
}
/// Canonical node contracts explicitly distinguish engine-derived variants
/// from values a model may supply. Persistence uses strict_json directly; authored
/// model values reject derived nodes. Explicit native-evidence encoding can
/// retain them as input facts; response decoding always rejects them.
fn derivedNode(comptime T: type, comptime name: []const u8) bool {
    if (comptime !declared(T, "model_derived_nodes")) return false;
    comptime {
        if (@typeInfo(T) != .@"union") @compileError("Derived model nodes require a tagged union");
        for (@typeInfo(@TypeOf(T.model_derived_nodes)).@"struct".fields) |field| {
            if (!@hasField(T, field.name)) @compileError("A derived node must name a canonical union variant");
        }
    }
    return @hasField(@TypeOf(T.model_derived_nodes), name);
}
/// A union may declare `model_tags` to show a variant under another model-visible
/// name (ADR 0043). Native tags, persistence and strict_json keep their names; the
/// declared name is the only one this codec accepts or emits for that variant.
fn wireTag(comptime T: type, comptime name: []const u8) []const u8 {
    if (comptime !declared(T, "model_tags")) return name;
    comptime {
        if (@typeInfo(T) != .@"union") @compileError("Model tags require a tagged union");
        for (@typeInfo(@TypeOf(T.model_tags)).@"struct".fields) |entry| {
            if (!@hasField(T, entry.name)) @compileError("A model tag must name a canonical union variant");
            const shown: []const u8 = @field(T.model_tags, entry.name);
            for (@typeInfo(T).@"union".fields) |other| {
                if (std.mem.eql(u8, shown, other.name)) @compileError("A model tag must not reuse a variant name");
            }
        }
    }
    return if (@hasField(@TypeOf(T.model_tags), name)) @field(T.model_tags, name) else name;
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

/// Only a declared typed-text field has this wire form. Ordinary prose becomes
/// one literal node; explicit composition retains every node and its identity.
/// Neither path inserts separators, normalizes text or infers reference handles.
fn transformText(comptime T: type, a: std.mem.Allocator, value: std.json.Value, comptime direction: Direction, comptime purpose: EncodingPurpose) json.Error!std.json.Value {
    const pointer = @typeInfo(T);
    if (pointer != .pointer or pointer.pointer.size != .slice) @compileError("Model text fields require a slice of declared text nodes");
    const Node = pointer.pointer.child;
    if (comptime @typeInfo(Node) != .@"union" or !declared(Node, "model_inline")) @compileError("Model text nodes require disjoint inline prose");
    comptime checkInline(Node);
    comptime {
        var prose = false;
        for (@typeInfo(@TypeOf(Node.model_inline)).@"struct".fields) |field| {
            const Payload = @FieldType(Node, field.name);
            const Child = @FieldType(Payload, @field(Node.model_inline, field.name));
            prose = prose or inlineShape(Child) == .string;
        }
        if (!prose) @compileError("Model text nodes require an inline string variant");
    }
    if (direction == .native) {
        const fragments = if (value == .string) one: {
            if (value.string.len == 0) return error.InvalidJsonDocument;
            var array: std.json.Array = .init(a);
            try array.append(value);
            break :one std.json.Value{ .array = array };
        } else explicit: {
            if (value != .object or value.object.count() != 1) return error.InvalidJsonDocument;
            const array = value.object.get("fragments") orelse return error.InvalidJsonDocument;
            if (array != .array or array.array.items.len == 0) return error.InvalidJsonDocument;
            for (array.array.items) |fragment| if (fragment == .string and fragment.string.len == 0) return error.InvalidJsonDocument;
            break :explicit array;
        };
        return transform(T, a, fragments, direction, purpose);
    }
    const fragments = try transform(T, a, value, direction, purpose);
    if (fragments != .array or fragments.array.items.len == 0) return error.InvalidJsonDocument;
    for (fragments.array.items) |fragment| if (fragment == .string and fragment.string.len == 0) return error.InvalidJsonDocument;
    if (fragments.array.items.len == 1 and fragments.array.items[0] == .string) return fragments.array.items[0];
    var object: std.json.ObjectMap = .{};
    try object.put(a, "fragments", fragments);
    return .{ .object = object };
}

fn transformField(comptime T: type, comptime name: []const u8, a: std.mem.Allocator, value: std.json.Value, comptime direction: Direction, comptime purpose: EncodingPurpose) json.Error!std.json.Value {
    if (comptime declared(T, "model_text") and !@hasField(T, T.model_text)) @compileError("A model text declaration must name its native field");
    if (comptime declared(T, "model_text") and std.mem.eql(u8, T.model_text, name)) return transformText(@FieldType(T, name), a, value, direction, purpose);
    return transform(@FieldType(T, name), a, value, direction, purpose);
}

const Direction = enum { native, wire };
fn transform(comptime T: type, a: std.mem.Allocator, value: std.json.Value, comptime direction: Direction, comptime purpose: EncodingPurpose) json.Error!std.json.Value {
    var result = value;
    switch (@typeInfo(T)) {
        .@"struct" => |s| {
            if (comptime declared(T, "model_scalar")) {
                const name = T.model_scalar;
                if (s.fields.len != 1 or !@hasField(T, name)) @compileError("A compact wrapper must have exactly its declared field");
                if (direction == .wire) {
                    if (value != .object or value.object.count() != 1) return error.InvalidJsonDocument;
                    return transformField(T, name, a, value.object.get(name) orelse return error.InvalidJsonDocument, direction, purpose);
                }
                var object: std.json.ObjectMap = .{};
                try object.put(a, name, try transformField(T, name, a, value, direction, purpose));
                return .{ .object = object };
            }
            return transformFields(T, a, value, direction, purpose);
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
                        try payload.put(a, member, try transform(Child, a, value, direction, purpose));
                        var object: std.json.ObjectMap = .{};
                        try object.put(a, field.name, .{ .object = payload });
                        return .{ .object = object };
                    }
                    if (direction == .wire and value == .object and value.object.count() == 1) {
                        if (value.object.get(field.name)) |payload| {
                            if (payload != .object or payload.object.count() != 1) return error.InvalidJsonDocument;
                            return transform(Child, a, payload.object.get(member) orelse return error.InvalidJsonDocument, direction, purpose);
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
            inline for (u.fields) |field| if (std.mem.eql(u8, tag, if (direction == .native) comptime wireTag(T, field.name) else field.name)) {
                if (comptime derivedNode(T, field.name) and (direction == .native or purpose == .model_response)) return error.InvalidJsonDocument;
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
                        child = value.object.get(comptime wireTag(T, field.name)) orelse return error.InvalidJsonDocument;
                    }
                    try object.put(a, field.name, if (comptime direct) try transformFields(field.type, a, child, direction, purpose) else try transform(field.type, a, child, direction, purpose));
                } else {
                    const child = if (comptime direct) try transformFields(field.type, a, value.object.values()[0], direction, purpose) else try transform(field.type, a, value.object.values()[0], direction, purpose);
                    if (direct) object = child.object else try object.put(a, comptime wireTag(T, field.name), child);
                    try object.put(a, "kind", .{ .string = comptime wireTag(T, field.name) });
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
                for (value.array.items) |child| try result.array.append(try transform(p.child, a, child, direction, purpose));
            }
        },
        .optional => |o| if (value != .null) return transform(o.child, a, value, direction, purpose),
        .int => if (direction == .native and value == .number_string) {
            // JSON Schema integers include exact decimal/exponent spellings.
            // Reuse the payload validator's arithmetic, never round a float.
            result = .{ .integer = @import("model_payload_schema.zig").exactInteger(value.number_string) catch return error.InvalidJsonDocument };
        },
        else => {}, // strict_json owns scalar wire kinds and ranges
    }
    return result;
}

fn transformFields(comptime T: type, a: std.mem.Allocator, value: std.json.Value, comptime direction: Direction, comptime purpose: EncodingPurpose) json.Error!std.json.Value {
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
        if (!(direction == .wire and @typeInfo(field.type) == .optional and field.default_value_ptr != null and child == .null)) try result.object.put(a, field.name, try transformField(T, field.name, a, child, direction, purpose));
    }
    return result;
}
