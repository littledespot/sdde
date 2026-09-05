const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const values = @import("pipeline_values.zig");
const std = @import("std");
const gate = @import("../domain/workflow_gate.zig");
const workflow = @import("../domain/workflow.zig");

pub const Error = pipeline.DeltaError || error{
    DataSchemaMismatch,
    UnregisteredDataSchema,
    AliasedDataValue,
    DataGenerationExhausted,
};

/// Sole owner of accumulated workflow values. A node receives only a filtered
/// immutable view; replacements become visible together after complete validation.
pub const PipelineEnvelope = struct {
    schemas: []const data.Schema,
    slots: data.Slots = data.empty_slots,
    origins: [data.key_count]?data.Origin = @splat(null),
    generation: u64 = 0,

    pub fn init(schemas: []const data.Schema) PipelineEnvelope {
        return .{ .schemas = schemas };
    }

    pub fn deinit(self: *PipelineEnvelope) void {
        for (&self.slots) |*slot| {
            if (slot.*) |value| values.destroy(value);
            slot.* = null;
        }
        self.origins = @splat(null);
    }

    pub fn view(self: *const PipelineEnvelope, contract: pipeline.NodeContract) Error!data.View {
        try self.shape().validateInvocation(contract);
        var result: data.View = .{};
        for (contract.requires) |key| result.slots[@intFromEnum(key)] = self.slots[@intFromEnum(key)];
        for (contract.optional) |key| result.slots[@intFromEnum(key)] = self.slots[@intFromEnum(key)];
        return result;
    }

    pub fn apply(self: *PipelineEnvelope, contract: pipeline.NodeContract, delta: *pipeline.NodeDelta, outcome: workflow.OutcomeTag) Error!void {
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

        const generation = std.math.add(u64, self.generation, 1) catch return error.DataGenerationExhausted;
        var origin: data.Origin = .{ .generation = generation, .producer = contract.id, .outcome = outcome, .inputs = @splat(null) };
        inline for (.{ contract.requires, contract.optional }) |keys| {
            for (keys) |key| if (self.origins[@intFromEnum(key)]) |input| {
                origin.inputs[@intFromEnum(key)] = input.generation;
            };
        }
        // No allocation or fallible operation is allowed beyond this boundary.
        self.generation = generation;
        var invalidations = delta.data_invalidations.iterator();
        while (invalidations.next()) |key| {
            const slot = &self.slots[@intFromEnum(key)];
            values.destroy(slot.*.?);
            slot.* = null;
            self.origins[@intFromEnum(key)] = null;
        }
        for (&delta.data_replacements, 0..) |*slot, index| {
            if (slot.*) |value| {
                values.destroy(self.slots[index].?);
                self.slots[index] = value;
                self.origins[index] = origin;
                slot.* = null;
            }
        }
        for (&delta.data_writes, 0..) |*slot, index| {
            if (slot.*) |value| {
                self.slots[index] = value;
                self.origins[index] = origin;
                slot.* = null;
            }
        }
    }

    pub fn checkGate(self: *const PipelineEnvelope, contract: gate.Contract) ?gate.Rejection {
        const index = @intFromEnum(contract.evidence);
        const value = self.slots[index] orelse return .missing_evidence;
        const origin = self.origins[index] orelse return .invalid_evidence;
        const schema = data.find(self.schemas, contract.evidence) orelse return .invalid_evidence;
        var input: data.View = .{};
        input.slots[index] = value;
        const decision = values.read(&input, schema, gate.Decision) catch return .invalid_evidence;
        var current: [data.key_count]?u64 = @splat(null);
        for (contract.authority) |key| if (self.origins[@intFromEnum(key)]) |authority| {
            current[@intFromEnum(key)] = authority.generation;
        };
        return gate.check(contract, decision.*, origin, current);
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
