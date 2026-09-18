const data = @import("../domain/pipeline_data.zig");
const pipeline = @import("../domain/pipeline.zig");
const values = @import("pipeline_values.zig");
const std = @import("std");
const gate = @import("../domain/workflow_gate.zig");
const workflow = @import("../domain/workflow.zig");
const reference = @import("../domain/execution_reference.zig");

pub const Error = pipeline.DeltaError || std.mem.Allocator.Error || error{
    DataSchemaMismatch,
    UnregisteredDataSchema,
    AliasedDataValue,
    DataGenerationExhausted,
    DataReferenceOverflow,
    InvalidInformationOccurrence,
    InformationConflict,
    InvalidRepairRenewal,
};

/// Native placement identity, never a model key or an execution receipt.
pub const Occurrence = struct { scope: reference.Ref, ordinal: u64, producer: []const u8 };
pub const Record = struct {
    occurrence: Occurrence,
    value: *data.Value,
    origin: data.Origin,

    pub fn key(self: *const Record) pipeline.DataKey {
        return values.valueSchema(self.value).key;
    }
};
pub const Placement = union(enum) { inserted: *const Record, already_present: *const Record };

/// Sole owner of accumulated workflow values. A node receives only a filtered
/// immutable view; replacements become visible together after complete validation.
pub const PipelineEnvelope = struct {
    allocator: std.mem.Allocator,
    schemas: []const data.Schema,
    slots: data.Slots = data.empty_slots,
    origins: [data.key_count]?*data.Origin = @splat(null),
    generation: u64 = 0,
    scope: ?reference.Ref = null,
    occurrence_count: u64 = 0,
    records: std.ArrayList(*const Record) = .empty,

    pub fn init(allocator: std.mem.Allocator, schemas: []const data.Schema) PipelineEnvelope {
        return .{ .allocator = allocator, .schemas = schemas };
    }

    pub fn deinit(self: *PipelineEnvelope) void {
        for (self.records.items) |record| self.releaseRecord(record);
        self.records.deinit(self.allocator);
        for (&self.slots) |*slot| {
            if (slot.*) |value| values.destroy(value);
            slot.* = null;
        }
        for (&self.origins) |*origin| {
            if (origin.*) |value| self.allocator.destroy(value);
            origin.* = null;
        }
        if (self.scope) |scope| scope.release();
    }

    pub fn beginOccurrence(self: *PipelineEnvelope, producer: []const u8) Error!Occurrence {
        if (producer.len == 0) return error.InvalidInformationOccurrence;
        const ordinal = std.math.add(u64, self.occurrence_count, 1) catch return error.DataGenerationExhausted;
        if (self.scope == null) self.scope = try reference.create(self.allocator);
        self.occurrence_count = ordinal;
        return .{ .scope = self.scope.?, .ordinal = ordinal, .producer = producer };
    }

    /// Same sealed value and origin for the same occurrence is a no-op. The
    /// canonical immutable value owner supplies identity, not serialized text.
    pub fn place(self: *PipelineEnvelope, occurrence: Occurrence, value: *data.Value, origin: data.Origin) Error!Placement {
        if (try self.existing(occurrence, value, origin)) |record| return .{ .already_present = record };
        const index = @intFromEnum(values.valueSchema(value).key);
        const current_origin = self.origins[index] orelse return error.InvalidInformationOccurrence;
        if (self.slots[index] != value or !sameOrigin(current_origin.*, origin)) return error.InvalidInformationOccurrence;
        const record = try self.prepareRecord(occurrence, value, origin);
        errdefer self.releaseRecord(record);
        try self.records.append(self.allocator, record);
        return .{ .inserted = record };
    }

    /// Historical information is available only through the requested native
    /// key. It never re-enters the current slots or satisfies an authority gate.
    pub fn latestInformation(self: *const PipelineEnvelope, key: pipeline.DataKey) data.View {
        var result: data.View = .{};
        var index = self.records.items.len;
        while (index != 0) {
            index -= 1;
            const record = self.records.items[index];
            if (record.key() == key) {
                result.slots[@intFromEnum(key)] = record.value;
                break;
            }
        }
        return result;
    }

    pub fn view(self: *const PipelineEnvelope, contract: pipeline.NodeContract) Error!data.View {
        try self.shape().validateInvocation(contract);
        var result: data.View = .{};
        for (contract.requires) |key| result.slots[@intFromEnum(key)] = self.slots[@intFromEnum(key)];
        for (contract.optional) |key| result.slots[@intFromEnum(key)] = self.slots[@intFromEnum(key)];
        return result;
    }

    pub fn apply(self: *PipelineEnvelope, contract: pipeline.NodeContract, delta: *pipeline.NodeDelta, outcome: workflow.OutcomeTag) Error!void {
        return self.applyOccurrence(try self.beginOccurrence(contract.id), contract, delta, outcome);
    }

    pub fn applyOccurrence(self: *PipelineEnvelope, occurrence: Occurrence, contract: pipeline.NodeContract, delta: *pipeline.NodeDelta, outcome: workflow.OutcomeTag) Error!void {
        try self.checkOccurrence(occurrence);
        if (!std.mem.eql(u8, occurrence.producer, contract.id)) return error.InvalidInformationOccurrence;
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

        const renewal = if (delta.repair_transition) |transition| transition == .merged and transition.merged.validation == .dependent_review and contract.replaces.len != 0 else false;
        var superseded = std.enums.EnumSet(pipeline.DataKey).initEmpty();
        if (renewal) {
            // These effects are locked to the native merge contract, never YAML
            // parameters or model data. The runner admits the exact repair first.
            if (contract.replaces.len == 0 or contract.produces.len != 0 or contract.invalidates.len == 0) return error.InvalidRepairRenewal;
            superseded = delta.data_invalidations;
            for (contract.replaces) |key| superseded.insert(key);
            for (self.schemas) |schema| {
                if (schema.retention != .current or superseded.contains(schema.key) or self.origins[@intFromEnum(schema.key)] == null) continue;
                var visited = std.enums.EnumSet(pipeline.DataKey).initEmpty();
                if (self.dependsOn(schema.key, superseded, &visited)) return error.InvalidRepairRenewal;
            }
        }
        const generation = std.math.add(u64, self.generation, 1) catch return error.DataGenerationExhausted;
        var origin: data.Origin = .{ .generation = generation, .occurrence = occurrence.ordinal, .producer = contract.id, .outcome = outcome, .inputs = @splat(null) };
        inline for (.{ contract.requires, contract.optional }) |keys| {
            for (keys) |key| if (self.origins[@intFromEnum(key)]) |input| {
                origin.inputs[@intFromEnum(key)] = input.generation;
                const schema = data.find(self.schemas, key) orelse return error.UnregisteredDataSchema;
                if (schema.retention == .current) {
                    if (!superseded.contains(key)) mergeGeneration(&origin, @intFromEnum(key), input.generation);
                } else if (schema.retention == .captured) {
                    origin.lineage_conflicts.setUnion(input.lineage_conflicts.differenceWith(superseded));
                    for (input.lineage, 0..) |expected, index| if (expected) |value| {
                        if (!superseded.contains(@enumFromInt(index))) mergeGeneration(&origin, index, value);
                    };
                }
            };
        }
        if (renewal) {
            if (origin.lineage_conflicts.count() != 0) return error.InvalidRepairRenewal;
            var checked = std.enums.EnumSet(pipeline.DataKey).initEmpty();
            for (origin.lineage, 0..) |expected, index| if (expected) |value| {
                const current = self.origins[index] orelse return error.InvalidRepairRenewal;
                if (current.generation != value or self.checkAuthorityLineage(@enumFromInt(index), &checked) != null) return error.InvalidRepairRenewal;
            };
        }
        // Prepare lineage before committing any output. Keep the quadratic
        // authority table off the runner's stack, with explicit envelope ownership.
        var prepared_origins: [data.key_count]?*data.Origin = @splat(null);
        errdefer for (prepared_origins) |prepared| if (prepared) |value| self.allocator.destroy(value);
        for (&prepared_origins, 0..) |*prepared, index| {
            if (delta.data_writes[index] == null and delta.data_replacements[index] == null) continue;
            prepared.* = try self.allocator.create(data.Origin);
            prepared.*.?.* = origin;
        }
        var prepared_records: std.ArrayList(*const Record) = .empty;
        defer prepared_records.deinit(self.allocator);
        errdefer for (prepared_records.items) |record| self.releaseRecord(record);
        inline for (.{ delta.data_writes, delta.data_replacements }) |slots| for (slots) |slot| {
            const value = slot orelse continue;
            if (values.valueSchema(value).history != .execution) continue;
            if (try self.existing(occurrence, value, origin) != null) return error.InformationConflict;
            const record = try self.prepareRecord(occurrence, value, origin);
            prepared_records.append(self.allocator, record) catch |err| {
                self.releaseRecord(record);
                return err;
            };
        };
        try self.records.ensureUnusedCapacity(self.allocator, prepared_records.items.len);
        // No allocation or fallible operation is allowed beyond this boundary.
        self.records.appendSliceAssumeCapacity(prepared_records.items);
        self.generation = generation;
        var invalidations = delta.data_invalidations.iterator();
        while (invalidations.next()) |key| {
            const slot = &self.slots[@intFromEnum(key)];
            values.destroy(slot.*.?);
            slot.* = null;
            self.allocator.destroy(self.origins[@intFromEnum(key)].?);
            self.origins[@intFromEnum(key)] = null;
        }
        for (&delta.data_replacements, 0..) |*slot, index| {
            if (slot.*) |value| {
                values.destroy(self.slots[index].?);
                self.slots[index] = value;
                self.allocator.destroy(self.origins[index].?);
                self.origins[index] = prepared_origins[index];
                slot.* = null;
            }
        }
        for (&delta.data_writes, 0..) |*slot, index| {
            if (slot.*) |value| {
                self.slots[index] = value;
                self.origins[index] = prepared_origins[index];
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
        if (gate.check(contract, decision.*, origin.*, current)) |rejection| return rejection;
        var checked = std.enums.EnumSet(pipeline.DataKey).initEmpty();
        for (contract.authority) |key| if (self.checkAuthorityLineage(key, &checked)) |rejection| return rejection;
        return null;
    }

    // A projection cannot keep a gate current after one of its sources changes.
    // Replacement's self-input is the superseded revision, not a dependency on
    // itself; all other recorded input generations must still be available.
    fn checkAuthorityLineage(self: *const PipelineEnvelope, key: pipeline.DataKey, checked: *std.enums.EnumSet(pipeline.DataKey)) ?gate.Rejection {
        if (checked.contains(key)) return null;
        checked.insert(key);
        const origin = self.origins[@intFromEnum(key)] orelse return .missing_authority;
        if (origin.lineage_conflicts.count() != 0) return .stale_authority;
        for (origin.lineage, 0..) |generation, index| {
            const expected = generation orelse continue;
            // Only a directly consumed prior revision is a replacement's
            // self-input. A captured dependency cannot turn stale authority into
            // a self-input merely because a later projection reuses its key.
            if (index == @intFromEnum(key) and origin.inputs[index] == expected) continue;
            const current = self.origins[index] orelse return .missing_authority;
            if (current.generation != expected) return .stale_authority;
            if (self.checkAuthorityLineage(@enumFromInt(index), checked)) |rejection| return rejection;
        }
        return null;
    }

    fn dependsOn(self: *const PipelineEnvelope, key: pipeline.DataKey, changed: std.enums.EnumSet(pipeline.DataKey), visited: *std.enums.EnumSet(pipeline.DataKey)) bool {
        if (changed.contains(key)) return true;
        if (visited.contains(key)) return false;
        visited.insert(key);
        const origin = self.origins[@intFromEnum(key)] orelse return false;
        for (origin.inputs, 0..) |input, index| {
            const generation = input orelse continue;
            if (index == @intFromEnum(key)) continue;
            const input_key: pipeline.DataKey = @enumFromInt(index);
            const schema = data.find(self.schemas, input_key) orelse continue;
            if (schema.retention == .execution_control) continue;
            if (changed.contains(input_key)) return true;
            // Reused transport slots may now describe a different request. Only
            // follow the captured generation; current authority is also retained
            // in the flattened lineage below.
            const current = self.origins[index] orelse continue;
            if (current.generation == generation and self.dependsOn(input_key, changed, visited)) return true;
        }
        for (origin.lineage, 0..) |input, index| {
            if (input != null and index != @intFromEnum(key) and changed.contains(@enumFromInt(index))) return true;
        }
        return false;
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
        if (contains(&self.slots, value)) return true;
        for (self.records.items) |record| if (record.value == value) return true;
        return false;
    }

    fn checkOccurrence(self: *const PipelineEnvelope, occurrence: Occurrence) Error!void {
        const scope = self.scope orelse return error.InvalidInformationOccurrence;
        if (!scope.eql(occurrence.scope) or occurrence.ordinal == 0 or occurrence.ordinal > self.occurrence_count)
            return error.InvalidInformationOccurrence;
    }

    fn existing(self: *const PipelineEnvelope, occurrence: Occurrence, value: *data.Value, origin: data.Origin) Error!?*const Record {
        try self.checkOccurrence(occurrence);
        const schema = values.valueSchema(value);
        const expected = data.find(self.schemas, schema.key) orelse return error.UnregisteredDataSchema;
        if (!expected.eql(schema) or schema.history != .execution) return error.DataSchemaMismatch;
        if (origin.occurrence != occurrence.ordinal or !std.mem.eql(u8, occurrence.producer, origin.producer)) return error.InvalidInformationOccurrence;
        for (self.records.items) |record| {
            if (record.occurrence.ordinal != occurrence.ordinal or record.key() != schema.key) continue;
            if (record.value != value or !sameOrigin(record.origin, origin)) return error.InformationConflict;
            return record;
        }
        return null;
    }

    fn prepareRecord(self: *PipelineEnvelope, occurrence: Occurrence, value: *data.Value, origin: data.Origin) Error!*const Record {
        const record = try self.allocator.create(Record);
        errdefer self.allocator.destroy(record);
        const producer = try self.allocator.dupe(u8, occurrence.producer);
        errdefer self.allocator.free(producer);
        record.* = .{ .occurrence = .{ .scope = occurrence.scope, .ordinal = occurrence.ordinal, .producer = producer }, .value = try values.retain(value), .origin = origin };
        record.origin.producer = producer;
        return record;
    }

    fn releaseRecord(self: *PipelineEnvelope, record: *const Record) void {
        values.destroy(record.value);
        self.allocator.free(record.occurrence.producer);
        self.allocator.destroy(record);
    }
};

fn sameOrigin(left: data.Origin, right: data.Origin) bool {
    return left.generation == right.generation and left.occurrence == right.occurrence and std.mem.eql(u8, left.producer, right.producer) and left.outcome == right.outcome and
        std.meta.eql(left.inputs, right.inputs) and std.meta.eql(left.lineage, right.lineage) and left.lineage_conflicts.eql(right.lineage_conflicts);
}

fn mergeGeneration(origin: *data.Origin, index: usize, generation: u64) void {
    if (origin.lineage[index]) |prior| {
        if (prior != generation) origin.lineage_conflicts.insert(@enumFromInt(index));
    } else origin.lineage[index] = generation;
}

fn contains(slots: []const ?*data.Value, value: *data.Value) bool {
    for (slots) |slot| if (slot == value) return true;
    return false;
}
