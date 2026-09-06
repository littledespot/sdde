//! Ownership for execution-local authority projections. Retain native inputs;
//! never deep-copy reference history or impose a model-payload byte ceiling.
const std = @import("std");
const a = @import("../domain/required_authority.zig");
const data = @import("../domain/pipeline_data.zig");
const values = @import("pipeline_values.zig");
pub const Payload = union(enum) { inputs: a.Inputs, ledger: a.Ledger, raw: []const u8, observations: a.Observations, result: a.Result, content: @import("../domain/specification.zig").IdentifiedContent, rejected: enum { invalid_contract } };
pub const Value = opaque {};
pub const Owner = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    parents: data.Slots = data.empty_slots,
    payload: Payload = .{ .rejected = .invalid_contract },
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
    for (owner.parents) |slot| if (slot) |value| {
        values.destroy(value);
    };
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
pub fn read(inputs: *const data.View, schema: data.Schema, comptime tag: std.meta.Tag(Payload)) !@FieldType(Payload, @tagName(tag)) {
    const value = try values.read(inputs, schema, Value);
    const current = payload(value);
    if (current.* != tag) return error.InvalidRequiredAuthority;
    return @field(current, @tagName(tag));
}
pub fn publish(allocator: std.mem.Allocator, schema: data.Schema, owner: *Owner, outcome: @import("../domain/workflow.zig").OutcomeTag) !@import("../domain/workflow_execution.zig").Candidate {
    var delta: @import("../domain/pipeline.zig").NodeDelta = .{};
    delta.data_writes[@intFromEnum(schema.key)] = try values.adopt(allocator, schema, Value, Owner, owner, view, destroy, null);
    return .{ .outcome = outcome, .delta = delta };
}
