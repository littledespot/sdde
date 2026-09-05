const std = @import("std");
const reference = @import("domain/execution_reference.zig");
const pipeline = @import("domain/pipeline.zig");
const data = @import("domain/pipeline_data.zig");
const values = @import("application/pipeline_values.zig");
const envelopes = @import("application/pipeline_envelope.zig");

const key = pipeline.DataKey.workflow_invocation;
const index = @intFromEnum(key);
const produce: pipeline.NodeContract = .{
    .id = "test.reference-producer@1",
    .kind = .action,
    .requires = &.{},
    .produces = &.{key},
    .side_effect = .none,
};
const consume: pipeline.NodeContract = .{
    .id = "test.reference-consumer@1",
    .kind = .action,
    .requires = &.{key},
    .produces = &.{},
    .side_effect = .none,
};

test "execution references retain identity without carrying operational data" {
    const original = try reference.create(std.testing.allocator);
    const retained = original.retain();
    defer retained.release();
    try std.testing.expect(original.eql(retained));
    original.release();

    const unrelated = try reference.create(std.testing.allocator);
    defer unrelated.release();
    try std.testing.expect(!retained.eql(unrelated));
    try std.testing.expectEqual(@as(usize, 1), @typeInfo(reference.Ref).@"struct".fields.len);
    const identity_pointer = @typeInfo(reference.Ref).@"struct".fields[0].type;
    try std.testing.expect(@typeInfo(@typeInfo(identity_pointer).pointer.child) == .@"opaque");
}

test "nested pipeline values retain references and still copy ordinary data" {
    const first = try reference.create(std.testing.allocator);
    defer first.release();
    const second = try reference.create(std.testing.allocator);
    defer second.release();
    const Child = struct { identity: reference.Ref, text: []const u8 };
    const Nested = struct {
        optional: ?reference.Ref,
        array: [2]reference.Ref,
        slice: []const reference.Ref,
        choice: union(enum) { identity: reference.Ref, empty },
        child: *const Child,
    };
    const descriptor = values.schema(key, Nested, 1, 1024);
    var text = "original".*;
    const child: Child = .{ .identity = first, .text = &text };
    const source: Nested = .{
        .optional = first,
        .array = .{ first, second },
        .slice = &.{ second, first },
        .choice = .{ .identity = second },
        .child = &child,
    };
    const value = try values.create(std.testing.allocator, descriptor, Nested, source);
    defer values.destroy(value);
    text[0] = 'X';
    var view: data.View = .{};
    view.slots[index] = value;
    const cloned = try values.read(&view, descriptor, Nested);
    try std.testing.expect(cloned.optional.?.eql(first));
    try std.testing.expect(cloned.array[0].eql(first));
    try std.testing.expect(cloned.array[1].eql(second));
    try std.testing.expect(cloned.slice[0].eql(second));
    try std.testing.expect(cloned.slice[1].eql(first));
    try std.testing.expect(cloned.choice.identity.eql(second));
    try std.testing.expect(cloned.child.identity.eql(first));
    try std.testing.expect(cloned.child != &child);
    try std.testing.expectEqualStrings("original", cloned.child.text);
}

test "envelope references outlive the originating owner without identity reuse" {
    const descriptor = values.schema(key, reference.Ref, 1, 64);
    var envelope = envelopes.PipelineEnvelope.init(&.{descriptor});
    defer envelope.deinit();
    const original = try reference.create(std.testing.allocator);
    const borrowed_identity = original;
    var source_live = true;
    defer if (source_live) original.release();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[index] = try values.create(std.testing.allocator, descriptor, reference.Ref, original);
    try envelope.apply(produce, &delta, .ok);
    original.release();
    source_live = false;

    const next = try reference.create(std.testing.allocator);
    defer next.release();
    const view = try envelope.view(consume);
    const stored = try values.read(&view, descriptor, reference.Ref);
    try std.testing.expect(stored.eql(borrowed_identity));
    try std.testing.expect(!stored.eql(next));
}

test "destroying a reference value does not destroy another retained owner" {
    const original = try reference.create(std.testing.allocator);
    defer original.release();
    const descriptor = values.schema(key, reference.Ref, 1, 64);
    const value = try values.create(std.testing.allocator, descriptor, reference.Ref, original);
    values.destroy(value);
    const still_live = original.retain();
    defer still_live.release();
    try std.testing.expect(still_live.eql(original));
}

test "reference values enforce byte bounds and release partial-clone references" {
    const original = try reference.create(std.testing.allocator);
    defer original.release();
    const undersized = values.schema(key, reference.Ref, 1, @sizeOf(reference.Ref) - 1);
    try std.testing.expectError(error.DataValueLimitExceeded, values.create(std.testing.allocator, undersized, reference.Ref, original));
    const wrapper_only = values.schema(key, reference.Ref, 1, @sizeOf(reference.Ref));
    try std.testing.expectError(error.DataValueLimitExceeded, values.create(std.testing.allocator, wrapper_only, reference.Ref, original));

    const Partial = struct { identity: reference.Ref, bytes: []const u8 };
    const small = values.schema(key, Partial, 1, @sizeOf(Partial) + 32);
    const oversized = [_]u8{'x'} ** 128;
    try std.testing.expectError(error.DataValueLimitExceeded, values.create(std.testing.allocator, small, Partial, .{ .identity = original, .bytes = &oversized }));
    const retained = original.retain();
    defer retained.release();
    try std.testing.expect(retained.eql(original));
}

test "execution reference values clean up at every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    const first = try reference.create(allocator);
    defer first.release();
    const second = try reference.create(allocator);
    defer second.release();
    const Payload = struct {
        identity: reference.Ref,
        nested: []const struct { identity: reference.Ref, bytes: []const u8 },
    };
    const descriptor = values.schema(key, Payload, 1, 2048);
    var envelope = envelopes.PipelineEnvelope.init(&.{descriptor});
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[index] = try values.create(allocator, descriptor, Payload, .{
        .identity = first,
        .nested = &.{ .{ .identity = second, .bytes = "second" }, .{ .identity = first, .bytes = "first" } },
    });
    try envelope.apply(produce, &delta, .ok);
    const view = try envelope.view(consume);
    const stored = try values.read(&view, descriptor, Payload);
    try std.testing.expect(stored.identity.eql(first));
    try std.testing.expect(stored.nested[0].identity.eql(second));
    try std.testing.expect(stored.nested[1].identity.eql(first));
}
