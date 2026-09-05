const std = @import("std");
const pipeline = @import("pipeline.zig");

pub const key_count = @typeInfo(pipeline.DataKey).@"enum".fields.len;

/// Runner-recorded, same-envelope provenance; never a model-supplied fact.
/// The producer identity borrows the compiled contract's envelope-long lifetime.
pub const Origin = struct {
    generation: u64,
    producer: []const u8,
    outcome: @import("workflow.zig").OutcomeTag,
    inputs: [key_count]?u64,
};

/// Compiled native value schema. Workflows reference keys, never supply schemas
/// or executable serializers. The operation registry owns these descriptors.
pub const Schema = struct {
    key: pipeline.DataKey,
    version: u32,
    type_name: []const u8,
    maximum_bytes: ?u32,

    pub fn valid(self: Schema) bool {
        return self.version != 0 and self.type_name.len != 0 and (self.maximum_bytes == null or self.maximum_bytes.? != 0);
    }

    pub fn eql(self: Schema, other: Schema) bool {
        return self.key == other.key and self.version == other.version and
            self.maximum_bytes == other.maximum_bytes and std.mem.eql(u8, self.type_name, other.type_name);
    }
};

/// Non-operational data handle. Representation, casts, allocation and destruction
/// are sealed inside the runner's value owner; nodes cannot dereference it.
pub const Value = opaque {};
pub const Slots = [key_count]?*Value;
pub const empty_slots: Slots = @splat(null);

/// A bounded immutable view containing only the current operation's inputs.
pub const View = struct {
    slots: Slots = empty_slots,

    pub fn contains(self: *const View, key: pipeline.DataKey) bool {
        return self.slots[@intFromEnum(key)] != null;
    }
};

pub fn find(schemas: []const Schema, key: pipeline.DataKey) ?Schema {
    var result: ?Schema = null;
    for (schemas) |schema| {
        if (schema.key != key) continue;
        if (result != null) return null;
        result = schema;
    }
    return result;
}
