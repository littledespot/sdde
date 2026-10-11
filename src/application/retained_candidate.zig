//! Shared ownership for native immutable candidates borrowing declared inputs.
const std = @import("std");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");

pub fn Storage(comptime Payload: type, comptime initial: Payload) type {
    return struct {
        pub const Value = opaque {};
        pub const Owner = struct {
            allocator: std.mem.Allocator,
            arena: std.heap.ArenaAllocator,
            parents: data.Slots = data.empty_slots,
            payload: Payload = initial,
            rejection: ?@import("../domain/workflow_execution.zig").OperationError = null,
        };
        pub fn create(allocator: std.mem.Allocator, inputs: data.View) !*Owner {
            const owner = try allocator.create(Owner);
            owner.* = .{ .allocator = allocator, .arena = .init(allocator) };
            errdefer destroy(owner);
            for (inputs.slots, 0..) |slot, index| if (slot) |value| {
                owner.parents[index] = try values.retain(value);
            };
            return owner;
        }
        pub fn destroy(owner: *Owner) void {
            for (owner.parents) |slot| if (slot) |value| values.destroy(value);
            owner.arena.deinit();
            owner.allocator.destroy(owner);
        }
        pub fn view(owner: *const Owner) *const Value {
            return @ptrCast(owner);
        }
        pub fn payload(value: *const Value) *const Payload {
            const owner: *const Owner = @ptrCast(@alignCast(value));
            return &owner.payload;
        }
        pub fn rejection(value: *const Value) ?@import("../domain/workflow_execution.zig").OperationError {
            const owner: *const Owner = @ptrCast(@alignCast(value));
            return owner.rejection;
        }
        pub fn retainsCurrentInputs(value: *const Value, inputs: *const data.View) bool {
            const owner: *const Owner = @ptrCast(@alignCast(value));
            var retained = false;
            for (owner.parents, inputs.slots) |parent, current| if (parent) |source| {
                retained = true;
                if (current != source) return false;
            };
            return retained;
        }
        pub fn read(inputs: *const data.View, schema: data.Schema, comptime tag: std.meta.Tag(Payload)) values.Error!@FieldType(Payload, @tagName(tag)) {
            const current = payload(try values.read(inputs, schema, Value));
            if (current.* != tag) return error.InvalidCandidatePayload;
            return @field(current, @tagName(tag));
        }
        pub fn publish(allocator: std.mem.Allocator, schema: data.Schema, owner: *Owner, outcome: @import("../domain/workflow.zig").OutcomeTag) !@import("../domain/workflow_execution.zig").Candidate {
            var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
            delta.data_writes[@intFromEnum(schema.key)] = try values.adopt(allocator, schema, Value, Owner, owner, view, destroy, null);
            return .{ .outcome = outcome, .delta = delta, .diagnostic = owner.rejection };
        }
    };
}

test "retained native result requires exact current inputs and cannot replay foreign or stale values" {
    const Result = Storage(union(enum) { rejected }, .rejected);
    const source_schema = values.schema(.parsed_reference_extraction, u8, 1, 16);
    const context_schema = values.schema(.logging_policy, u8, 1, 16);
    const source = try values.create(std.testing.allocator, source_schema, u8, 1);
    defer values.destroy(source);
    const foreign = try values.create(std.testing.allocator, source_schema, u8, 1);
    defer values.destroy(foreign);
    const replacement = try values.create(std.testing.allocator, source_schema, u8, 2);
    defer values.destroy(replacement);
    const context = try values.create(std.testing.allocator, context_schema, u8, 3);
    defer values.destroy(context);
    const changed_context = try values.create(std.testing.allocator, context_schema, u8, 4);
    defer values.destroy(changed_context);
    var inputs: data.View = .{};
    inputs.slots[@intFromEnum(source_schema.key)] = source;
    inputs.slots[@intFromEnum(context_schema.key)] = context;
    const owner = try Result.create(std.testing.allocator, inputs);
    defer Result.destroy(owner);
    const result = Result.view(owner);
    try std.testing.expect(Result.retainsCurrentInputs(result, &inputs));
    for ([_]?*data.Value{ foreign, replacement, null }) |current| {
        var replay = inputs;
        replay.slots[@intFromEnum(source_schema.key)] = current;
        try std.testing.expect(!Result.retainsCurrentInputs(result, &replay));
    }
    var stale = inputs;
    stale.slots[@intFromEnum(context_schema.key)] = changed_context;
    try std.testing.expect(!Result.retainsCurrentInputs(result, &stale));
    try std.testing.expect(Result.retainsCurrentInputs(result, &inputs));
    const empty = try Result.create(std.testing.allocator, .{});
    defer Result.destroy(empty);
    try std.testing.expect(!Result.retainsCurrentInputs(Result.view(empty), &inputs));
}
