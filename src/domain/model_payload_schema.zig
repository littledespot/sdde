const std = @import("std");
const envelope = @import("model_envelope.zig");
const schema = @import("model_result_schema.zig");
const statements = @import("statement_ownership.zig");

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

/// The admitted integer key one assignment item names, if present.
fn memberKey(item: envelope.Value, property: []const u8) ?i64 {
    if (item != .object) return null;
    const key = item.object.get(property) orelse return null;
    if (key != .number) return null;
    return exactInteger(key.number) catch null;
}

fn hasKind(item: envelope.Value, kind_property: []const u8, kinds: []const []const u8) bool {
    if (item != .object) return false;
    const tagged = item.object.get(kind_property) orelse return false;
    if (tagged != .object) return false;
    const kind = tagged.object.get("kind") orelse return false;
    if (kind != .string) return false;
    for (kinds) |name| if (std.mem.eql(u8, kind.string, name)) return true;
    return false;
}
fn listedValue(value: envelope.Value) ?i64 {
    if (value != .number) return null;
    return exactInteger(value.number) catch null;
}
/// One naming of a taken value in an exclusive item that also names an untaken one
/// (ADR 0038 Decision 5). A value is taken when an owning item names it anywhere or an
/// earlier exclusive item does. An exclusive item naming only taken values is admitted:
/// its owner deletes it without a model call. Owning items are never constrained.
pub const SharedNaming = struct { item: usize, position: usize };
/// The next such naming at or after `from`, in response order. Admission takes its
/// rejection from the first, and a correction lists every one; it tolerates items that
/// never passed admission.
pub fn nextSharedNaming(items: *const envelope.Array, coverage: schema.Coverage, from: SharedNaming) ?SharedNaming {
    var index = from.item;
    var position = from.position;
    while (index < items.count()) : ({
        index += 1;
        position = 0;
    }) {
        const item = items.at(index).?;
        if (!hasKind(item, coverage.rule.kind_property, coverage.rule.exclusive)) continue;
        const listed = (if (item == .object) item.object.get(coverage.property) else null) orelse continue;
        if (listed != .array) continue;
        if (!namesNew(items, coverage, index, listed.array)) continue;
        while (position < listed.array.count()) : (position += 1) {
            const wanted = listedValue(listed.array.at(position).?) orelse continue;
            if (taken(items, coverage, index, wanted)) return .{ .item = index, .position = position };
        }
    }
    return null;
}

/// Whether `listed`, exclusive item `index`'s values, includes an untaken one.
fn namesNew(items: *const envelope.Array, coverage: schema.Coverage, index: usize, listed: *const envelope.Array) bool {
    for (0..listed.count()) |position| {
        const wanted = listedValue(listed.at(position).?) orelse continue;
        if (!taken(items, coverage, index, wanted)) return true;
    }
    return false;
}

/// Whether `wanted` is taken for exclusive item `index`: an owning item names it, or an
/// exclusive item before `index` does. The rule is `statement_ownership.zig`'s, which the
/// text composition check, unit validation and the session apply to the same records.
fn taken(items: *const envelope.Array, coverage: schema.Coverage, index: usize, wanted: i64) bool {
    return statements.Rule(WireItems).taken(.{ .items = items, .coverage = coverage }, &.{}, index, wanted);
}

/// The items of a covered array as the shared statement rule reads them: an item's kind
/// selects its role and its integer list names its claims. Exact values are the text
/// composition check's to read, so none are held here.
const WireItems = struct {
    items: *const envelope.Array,
    coverage: schema.Coverage,

    pub fn len(self: WireItems) usize {
        return self.items.count();
    }
    pub fn role(self: WireItems, index: usize) statements.Role {
        const item = self.items.at(index).?;
        if (hasKind(item, self.coverage.rule.kind_property, self.coverage.rule.owning)) return .owning;
        if (hasKind(item, self.coverage.rule.kind_property, self.coverage.rule.exclusive)) return .exclusive;
        return .other;
    }
    fn listed(self: WireItems, index: usize) ?*const envelope.Array {
        const item = self.items.at(index).?;
        const values = (if (item == .object) item.object.get(self.coverage.property) else null) orelse return null;
        return if (values == .array) values.array else null;
    }
    pub fn claimCount(self: WireItems, index: usize) usize {
        return if (self.listed(index)) |values| values.count() else 0;
    }
    /// A value that is no integer names no claim.
    pub fn claim(self: WireItems, index: usize, position: usize) i64 {
        return listedValue(self.listed(index).?.at(position).?) orelse statements.no_claim;
    }
    pub fn exactCount(_: WireItems, _: usize) usize {
        return 0;
    }
    pub fn exact(_: WireItems, _: usize, _: usize) i64 {
        return 0;
    }
};

// Traversal is bounded by the already compiled schema and captured response.
// Only the schema compiler owns shape, variant uniqueness and structural limits.
pub fn validateValue(value: envelope.Value, node: *const schema.Node) ?Diagnostic {
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
        .integer_enumeration => |choices| {
            if (value != .number) return reject(.type_mismatch, node);
            const number = exactInteger(value.number) catch |err| return switch (err) {
                error.NotInteger => reject(.type_mismatch, node),
                error.IntegerOutOfRange => reject(.integer_range, node),
            };
            for (choices) |choice| if (choice == number) return null;
            var diagnostic = reject(.enum_mismatch, node);
            diagnostic.rejected = number;
            return diagnostic;
        },
        .array => |contract| {
            if (value != .array) return reject(.type_mismatch, node);
            const count = value.array.count();
            if (count < contract.minimum or count > contract.maximum) return reject(.array_length, node);
            for (0..count) |index| {
                if (validateValue(value.array.at(index).?, contract.items)) |diagnostic| return diagnostic.within(.{ .index = index });
            }
            // Each item already names one allowed member, so a defect is a repeat
            // or, without repeats, a member no item names. When the schema states
            // the member count, a missing member already failed as the item count.
            if (contract.members) |members| {
                for (0..count) |index| {
                    const key = memberKey(value.array.at(index).?, members.property);
                    for (0..index) |prior| if (memberKey(value.array.at(prior).?, members.property) == key) return (reject(.duplicate_member, node)).item(index);
                }
                for (members.values) |wanted| {
                    for (0..count) |index| {
                        if (memberKey(value.array.at(index).?, members.property) == wanted) break;
                    } else {
                        var diagnostic = reject(.missing_member, node);
                        diagnostic.member = wanted;
                        return diagnostic;
                    }
                }
            }
            // ADR 0038 Decision 5: no exclusive item names both taken and untaken values.
            // The location names the partly taken item, whose whole shape the correction
            // offers. Scenario coverage is the session's (Decision 3), not admission's.
            if (contract.coverage) |coverage| {
                if (nextSharedNaming(value.array, coverage, .{ .item = 0, .position = 0 })) |shared| {
                    var diagnostic = reject(.shared_member, contract.items);
                    diagnostic.coverage = coverage;
                    return diagnostic.within(.{ .index = shared.item });
                }
            }
        },
        .one_of => |variants| {
            const shape: schema.JsonType = switch (value) {
                .object => .object,
                .array => .array,
                .string => .string,
                .number => .number,
                .boolean => .boolean,
                .null_value => .null_value,
            };
            var objects: usize = 0;
            var sole_object: ?*const schema.Node = null;
            for (variants) |variant| {
                const expected = schema.jsonType(variant).?;
                if (expected == .object) {
                    objects += 1;
                    sole_object = variant;
                }
                if (shape != .object and shape == expected) return validateValue(value, variant);
            }
            if (shape != .object or objects == 0) return reject(.type_mismatch, node);
            if (objects == 1 and schema.discriminator(sole_object.?) == null) return validateValue(value, sole_object.?);
            const kind = value.object.get("kind") orelse return (reject(.missing_required_property, node)).property("kind");
            if (kind != .string) return (reject(.type_mismatch, node)).property("kind");
            for (variants) |variant| {
                if (variant.* != .object) continue;
                const declared = schema.discriminator(variant).?;
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
