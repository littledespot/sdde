const std = @import("std");
const envelope = @import("model_envelope.zig");
const schema = @import("model_result_schema.zig");

pub const Rejection = @import("model_schema_diagnostic.zig").Reason;
pub const Diagnostic = @import("model_schema_diagnostic.zig").Diagnostic;

pub const Result = union(enum) {
    valid: *const Evidence,
    invalid: Diagnostic,
};

/// A schema-valid view of the original candidate, not semantic correctness,
/// workflow success or commit authority. Borrows the candidate and its existing
/// invocation/request/schema owners; no new allocation or identity is created.
pub const Evidence = opaque {
    pub fn candidate(self: *const Evidence) *const envelope.Candidate {
        return @ptrCast(self);
    }
};

pub fn validate(candidate: *const envelope.Candidate) Result {
    const bound_schema = candidate.association().request().response_schema;
    if (validateValue(.{ .object = candidate.root() }, bound_schema.root())) |reason| return .{ .invalid = reason };
    return .{ .valid = @ptrCast(candidate) };
}

// Traversal is bounded by the already compiled schema and captured response.
// Only the schema compiler owns shape, variant uniqueness and structural limits.
fn validateValue(value: envelope.Value, node: *const schema.Node) ?Diagnostic {
    switch (node.*) {
        .object => |properties| {
            if (value != .object) return reject(.type_mismatch, node);
            const object = value.object;
            for (0..object.count()) |index| {
                const name = object.at(index).?.name;
                if (schema.findProperty(properties, name) == null) return (reject(.unknown_property, node)).property(name);
            }
            for (properties) |property| {
                const child = object.get(property.name) orelse {
                    if (property.required) return (reject(.missing_required_property, node)).property(property.name);
                    continue;
                };
                if (validateValue(child, property.schema)) |diagnostic| return diagnostic.within(.{ .property = property.name });
            }
        },
        .string => |bounds| {
            if (value != .string) return reject(.type_mismatch, node);
            // The decoder has already proven complete Unicode strings.
            const length = std.unicode.utf8CountCodepoints(value.string) catch unreachable;
            if (length < bounds.minimum or length > bounds.maximum) return reject(.string_length, node);
        },
        .integer => |bounds| {
            if (value != .number) return reject(.type_mismatch, node);
            const number = exactInteger(value.number) catch |err| return switch (err) {
                error.NotInteger => reject(.type_mismatch, node),
                error.IntegerOutOfRange => reject(.integer_range, node),
            };
            if (number < bounds.minimum or number > bounds.maximum) return reject(.integer_range, node);
        },
        .boolean => if (value != .boolean) return reject(.type_mismatch, node),
        .null_value => if (value != .null_value) return reject(.type_mismatch, node),
        .constant => |expected| {
            const matches = switch (expected) {
                .string => |text| value == .string and std.mem.eql(u8, value.string, text),
                .integer => |number| value == .number and integerEquals(value.number, number),
                .boolean => |boolean| value == .boolean and value.boolean == boolean,
                .null_value => value == .null_value,
            };
            if (!matches) return reject(.constant_mismatch, node);
        },
        .enumeration => |choices| {
            if (value != .string) return reject(.type_mismatch, node);
            for (choices) |choice| {
                if (std.mem.eql(u8, value.string, choice)) return null;
            }
            return reject(.enum_mismatch, node);
        },
        .array => |contract| {
            if (value != .array) return reject(.type_mismatch, node);
            const count = value.array.count();
            if (count < contract.minimum or count > contract.maximum) return reject(.array_length, node);
            for (0..count) |index| {
                if (validateValue(value.array.at(index).?, contract.items)) |diagnostic| return diagnostic.within(.{ .index = index });
            }
        },
        .one_of => |variants| {
            if (value != .object) return reject(.type_mismatch, node);
            const kind = value.object.get("kind") orelse return (reject(.missing_required_property, node)).property("kind");
            if (kind != .string) return (reject(.type_mismatch, node)).property("kind");
            for (variants) |variant| {
                const declared = schema.findProperty(variant.object, "kind").?.schema.constant.string;
                if (std.mem.eql(u8, kind.string, declared)) return validateValue(value, variant);
            }
            return (reject(.unknown_variant, node)).property("kind");
        },
    }
    return null;
}

fn reject(reason: Rejection, node: *const schema.Node) Diagnostic {
    return .{ .reason = reason, .expected = node };
}

fn integerEquals(number: []const u8, expected: i64) bool {
    return (exactInteger(number) catch return false) == expected;
}

/// Interpret a decoder-proven JSON number as an exact i64, not a float. JSON
/// Schema treats 1, 1.0 and 1e0 alike. Remove only insignificant zeroes, then
/// account for the decimal point and exponent before checking the i64 range.
pub fn exactInteger(number: []const u8) error{ NotInteger, IntegerOutOfRange }!i64 {
    const negative = number[0] == '-';
    const exponent_at = std.mem.indexOfAny(u8, number, "eE") orelse number.len;
    const mantissa = number[@intFromBool(negative)..exponent_at];
    const fraction = if (std.mem.indexOfScalar(u8, mantissa, '.')) |point| mantissa.len - point - 1 else 0;
    var digits: usize = 0;
    var first: ?usize = null;
    var last: usize = 0;
    for (mantissa) |digit| {
        if (digit == '.') continue;
        if (digit != '0') {
            if (first == null) first = digits;
            last = digits;
        }
        digits += 1;
    }
    const start = first orelse return 0;
    const exponent: i64 = if (exponent_at == number.len) 0 else std.fmt.parseInt(i64, number[exponent_at + 1 ..], 10) catch |err| switch (err) {
        error.Overflow => return if (number[exponent_at + 1] == '-') error.NotInteger else error.IntegerOutOfRange,
        error.InvalidCharacter => unreachable, // Syntax was already decoded.
    };
    // i128 prevents overflow when a representable exponent is adjusted by the
    // (byte-bounded) mantissa length. No arbitrary-precision allocation is needed.
    const shift = @as(i128, exponent) + @as(i128, digits - last - 1) - @as(i128, fraction);
    if (shift < 0) return error.NotInteger;
    const significant = last - start + 1;
    if (@as(i128, significant) + shift > 19) return error.IntegerOutOfRange;
    var magnitude: u64 = 0;
    var index: usize = 0;
    for (mantissa) |digit| {
        if (digit == '.') continue;
        if (index >= start and index <= last) magnitude = magnitude * 10 + digit - '0';
        index += 1;
    }
    for (0..@intCast(shift)) |_| magnitude *= 10;
    const minimum_magnitude: u64 = @as(u64, 1) << 63;
    if (magnitude > (if (negative) minimum_magnitude else std.math.maxInt(i64))) return error.IntegerOutOfRange;
    if (negative and magnitude == minimum_magnitude) return std.math.minInt(i64);
    const result: i64 = @intCast(magnitude);
    return if (negative) -result else result;
}
