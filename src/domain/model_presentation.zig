//! Model-input presentation of stored native values (ADR 0016 packet-guidance
//! amendment). A stored type that declares `model_presentation_required` omits
//! workflow guidance its request form carries, and declares `Presented` and
//! `present(a, guidance)`. Model input encodes only presented values, so no
//! stored copy of guidance text can stand in for the workflow resource.
const std = @import("std");
const Guidance = @import("packet_guidance.zig").Guidance;
pub const Error = @import("required_authority.zig").Error;

/// Whether `T` reaches a stored value that model input must present.
pub fn required(comptime T: type) bool {
    return search(T, &.{}).found;
}

const Search = struct { found: bool, seen: []const type };
fn search(comptime T: type, comptime seen: []const type) Search {
    @setEvalBranchQuota(1_000_000);
    for (seen) |prior| if (prior == T) return .{ .found = false, .seen = seen };
    var current: []const type = seen ++ [_]type{T};
    const children: []const type = switch (@typeInfo(T)) {
        .@"struct" => |info| fields: {
            if (@hasDecl(T, "model_presentation_required")) return .{ .found = true, .seen = current };
            var types: [info.fields.len]type = undefined;
            for (info.fields, &types) |field, *child| child.* = field.type;
            const fixed = types;
            break :fields &fixed;
        },
        .@"union" => |info| fields: {
            var types: [info.fields.len]type = undefined;
            for (info.fields, &types) |field, *child| child.* = field.type;
            const fixed = types;
            break :fields &fixed;
        },
        .optional => |info| &.{info.child},
        .pointer => |info| &.{info.child},
        .array => |info| &.{info.child},
        else => &.{},
    };
    for (children) |child| {
        const result = search(child, current);
        if (result.found) return result;
        current = result.seen;
    }
    return .{ .found = false, .seen = current };
}

/// `T` as model input presents it: each presentation-required value becomes
/// its `Presented` form. Every other name, field order and default is T's, so
/// the rest of the value encodes unchanged.
pub fn Presentation(comptime T: type) type {
    if (!required(T)) return T;
    if (declaresPresentation(T)) return T.Presented;
    return switch (@typeInfo(T)) {
        .optional => |info| ?Presentation(info.child),
        .pointer => |info| if (info.size == .slice and info.is_const) []const Presentation(info.child) else @compileError("presented values are reached through const slices"),
        .@"struct" => |info| presented: {
            var types: [info.fields.len]type = undefined;
            for (info.fields, &types) |field, *child| child.* = Presentation(field.type);
            break :presented Rebuilt(T, &types);
        },
        else => @compileError("presented values are reached through structs, optionals and slices"),
    };
}

/// The result borrows `value` and `guidance`; `a` must be an arena that the
/// caller releases with them, including after a rejected presentation.
pub fn present(comptime T: type, a: std.mem.Allocator, guidance: *const Guidance, value: T) Error!Presentation(T) {
    if (comptime !required(T)) return value;
    if (comptime declaresPresentation(T)) return value.present(a, guidance);
    switch (@typeInfo(T)) {
        .optional => |info| return if (value) |inner| try present(info.child, a, guidance, inner) else null,
        .pointer => |info| {
            const result = try a.alloc(Presentation(info.child), value.len);
            for (value, result) |item, *presented| presented.* = try present(info.child, a, guidance, item);
            return result;
        },
        .@"struct" => |info| {
            var result: Presentation(T) = undefined;
            inline for (info.fields) |field| @field(result, field.name) = try present(field.type, a, guidance, @field(value, field.name));
            return result;
        },
        else => comptime unreachable,
    }
}

fn declaresPresentation(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "model_presentation_required");
}

/// `T` with one field's type replaced; the building block of a `Presented` form.
pub fn Retyped(comptime T: type, comptime name: []const u8, comptime Field: type) type {
    const fields = @typeInfo(T).@"struct".fields;
    var types: [fields.len]type = undefined;
    var found = false;
    for (fields, &types) |field, *child| {
        const replaced = std.mem.eql(u8, field.name, name);
        found = found or replaced;
        child.* = if (replaced) Field else field.type;
    }
    if (!found) @compileError("a presentation replaces a declared field");
    return Rebuilt(T, &types);
}

/// `value` in a `Retyped` form: every field copied except `name`.
pub fn retype(comptime Presented: type, comptime T: type, value: T, comptime name: []const u8, replacement: @FieldType(Presented, name)) Presented {
    comptime {
        const stored = std.meta.fieldNames(T);
        const presented = std.meta.fieldNames(Presented);
        if (stored.len != presented.len) @compileError("a retyped value keeps every field");
        for (stored, presented) |left, right| if (!std.mem.eql(u8, left, right)) @compileError("a retyped value keeps every field in order");
    }
    var result: Presented = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        @field(result, field.name) = if (comptime std.mem.eql(u8, field.name, name)) replacement else @field(value, field.name);
    }
    return result;
}

/// The rebuilt struct keeps T's names, order and defaults; a replaced field
/// keeps only an absent default. Declarations that change the model encoding
/// would be lost, so T may declare none of them.
fn Rebuilt(comptime T: type, comptime types: []const type) type {
    const info = @typeInfo(T).@"struct";
    for ([_][]const u8{ "model_scalar", "model_text", "model_inline", "model_tags", "model_derived_nodes", "jsonStringify", "jsonParse" }) |decl| {
        if (@hasDecl(T, decl)) @compileError(@typeName(T) ++ " declares an encoding that a presentation would drop");
    }
    if (info.layout != .auto or info.is_tuple) @compileError("presentations rebuild plain structs only");
    var names: [info.fields.len][:0]const u8 = undefined;
    var attributes: [info.fields.len]std.builtin.Type.StructField.Attributes = undefined;
    for (info.fields, types, &names, &attributes) |field, Field, *name, *attribute| {
        if (field.is_comptime or field.alignment != null) @compileError("presentations rebuild plain fields only");
        name.* = field.name;
        attribute.* = .{ .default_value_ptr = if (Field == field.type or field.default_value_ptr == null) field.default_value_ptr else absent: {
            if (@typeInfo(Field) != .optional or field.defaultValue().? != null) @compileError("a presented field keeps only an absent default");
            const value: Field = null;
            break :absent &value;
        } };
    }
    const fields: [info.fields.len]type = types[0..info.fields.len].*;
    return @Struct(.auto, null, &names, &fields, &attributes);
}
