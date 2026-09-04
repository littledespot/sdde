const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const values = @import("pipeline_values.zig");

pub const Error = pipeline.DeltaError || error{
    DataSchemaMismatch,
    UnregisteredDataSchema,
    AliasedDataValue,
};

/// Sole owner of accumulated workflow values. A node receives only a filtered
/// immutable view; replacements become visible together after complete validation.
pub const PipelineEnvelope = struct {
    schemas: []const data.Schema,
    slots: data.Slots = data.empty_slots,

    pub fn init(schemas: []const data.Schema) PipelineEnvelope {
        return .{ .schemas = schemas };
    }

    pub fn deinit(self: *PipelineEnvelope) void {
        for (&self.slots) |*slot| {
            if (slot.*) |value| values.destroy(value);
            slot.* = null;
        }
    }

    pub fn view(self: *const PipelineEnvelope, contract: pipeline.NodeContract) Error!data.View {
        try self.shape().validateInvocation(contract);
        var result: data.View = .{};
        for (contract.requires) |key| result.slots[@intFromEnum(key)] = self.slots[@intFromEnum(key)];
        for (contract.optional) |key| result.slots[@intFromEnum(key)] = self.slots[@intFromEnum(key)];
        return result;
    }

    pub fn apply(self: *PipelineEnvelope, contract: pipeline.NodeContract, delta: *pipeline.NodeDelta) Error!void {
        _ = try self.shape().applyDelta(contract, delta);
        var seen: [data.key_count * 2]?*data.Value = @splat(null);
        var count: usize = 0;
        inline for (.{ delta.data_writes, delta.data_replacements }) |slots| {
            for (slots, 0..) |slot, index| {
                const value = slot orelse continue;
                if (self.owns(value) or contains(seen[0..count], value)) return error.AliasedDataValue;
                seen[count] = value;
                count += 1;
                const key: pipeline.DataKey = @enumFromInt(index);
                const expected = data.find(self.schemas, key) orelse return error.UnregisteredDataSchema;
                if (!expected.eql(values.valueSchema(value))) return error.DataSchemaMismatch;
            }
        }

        // No allocation or fallible operation is allowed beyond this boundary.
        var invalidations = delta.data_invalidations.iterator();
        while (invalidations.next()) |key| {
            const slot = &self.slots[@intFromEnum(key)];
            values.destroy(slot.*.?);
            slot.* = null;
        }
        for (&delta.data_replacements, 0..) |*slot, index| {
            if (slot.*) |value| {
                values.destroy(self.slots[index].?);
                self.slots[index] = value;
                slot.* = null;
            }
        }
        for (&delta.data_writes, 0..) |*slot, index| {
            if (slot.*) |value| {
                self.slots[index] = value;
                slot.* = null;
            }
        }
    }

    /// Releases rejected/unapplied candidates exactly once, including aliased
    /// malformed deltas, without freeing any value still owned by the envelope.
    pub fn discard(self: *const PipelineEnvelope, delta: *pipeline.NodeDelta) void {
        var seen: [data.key_count * 2]?*data.Value = @splat(null);
        var count: usize = 0;
        inline for (.{ &delta.data_writes, &delta.data_replacements }) |slots| {
            for (slots) |*slot| {
                if (slot.*) |value| {
                    if (!self.owns(value) and !contains(seen[0..count], value)) {
                        seen[count] = value;
                        count += 1;
                        values.destroy(value);
                    }
                    slot.* = null;
                }
            }
        }
    }

    fn shape(self: *const PipelineEnvelope) pipeline.DataShape {
        var result = pipeline.DataShape.init(&.{});
        for (self.slots, 0..) |slot, index| result.available[index] = slot != null;
        return result;
    }

    fn owns(self: *const PipelineEnvelope, value: *data.Value) bool {
        return contains(&self.slots, value);
    }
};

fn contains(slots: []const ?*data.Value, value: *data.Value) bool {
    for (slots) |slot| if (slot == value) return true;
    return false;
}
