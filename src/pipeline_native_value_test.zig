const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const data = @import("domain/pipeline_data.zig");
const values = @import("application/pipeline_values.zig");
const envelope = @import("application/pipeline_envelope.zig");

test "sealed native results keep identity and have one owner on apply discard and invalidation" {
    inline for (.{ SealA, SealB }) |T| {
        inline for (.{ false, true }) |reject| {
            var destroyed: usize = 0;
            const owner = try Owner.create(std.testing.allocator, &destroyed);
            const schema = values.schema(.valid_toolchain, T, 1, @sizeOf(Owner));
            const native = try values.adopt(std.testing.allocator, schema, T, Owner, owner, Access(T).get, Owner.destroy, @sizeOf(Owner));
            var store = envelope.PipelineEnvelope.init(&.{schema});
            defer store.deinit();
            const produce: pipeline.NodeContract = .{ .id = "test.native@1", .kind = .action, .requires = &.{}, .produces = &.{schema.key}, .side_effect = .none };
            var delta: pipeline.NodeDelta = .{};
            delta.data_writes[@intFromEnum(schema.key)] = native;
            if (reject) {
                var denied = produce;
                denied.produces = &.{};
                try std.testing.expectError(error.UndeclaredWrite, store.apply(denied, &delta, .ok));
                store.discard(&delta);
            } else {
                try store.apply(produce, &delta, .ok);
                const view: data.View = .{ .slots = store.slots };
                try std.testing.expect(try values.read(&view, schema, T) == Access(T).get(owner));
                store.discard(&delta);
                try std.testing.expectEqual(@as(usize, 0), destroyed);
                const remove: pipeline.NodeContract = .{ .id = "test.remove@1", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{schema.key}, .side_effect = .none };
                var invalidation: pipeline.NodeDelta = .{ .data_invalidations = .initOne(schema.key) };
                try store.apply(remove, &invalidation, .ok);
            }
            try std.testing.expectEqual(@as(usize, 1), destroyed);
        }
    }
}

test "native ownership transfer rejects wrong type and exceeded bounds without consuming the owner" {
    var destroyed: usize = 0;
    const owner = try Owner.create(std.testing.allocator, &destroyed);
    defer Owner.destroy(owner);
    const schema = values.schema(.valid_toolchain, SealA, 1, @sizeOf(Owner));
    try std.testing.expectError(error.DataSchemaMismatch, values.adopt(std.testing.allocator, schema, SealB, Owner, owner, Access(SealB).get, Owner.destroy, @sizeOf(Owner)));
    try std.testing.expectError(error.DataValueLimitExceeded, values.adopt(std.testing.allocator, schema, SealA, Owner, owner, Access(SealA).get, Owner.destroy, @sizeOf(Owner) + 1));
    try std.testing.expectEqual(@as(usize, 0), destroyed);
}

test "native ownership transfer releases every allocation on allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var destroyed: usize = 0;
    const owner = try Owner.create(allocator, &destroyed);
    const native = values.adopt(allocator, values.schema(.valid_toolchain, SealA, 1, @sizeOf(Owner)), SealA, Owner, owner, Access(SealA).get, Owner.destroy, @sizeOf(Owner)) catch |err| {
        Owner.destroy(owner);
        return err;
    };
    values.destroy(native);
    try std.testing.expectEqual(@as(usize, 1), destroyed);
}

const SealA = opaque {};
const SealB = opaque {};
fn Access(comptime T: type) type {
    return struct {
        fn get(owner: *const Owner) *const T {
            return @ptrCast(&owner.value);
        }
    };
}
const Owner = struct {
    allocator: std.mem.Allocator,
    destroyed: *usize,
    value: u32 = 42,
    fn create(allocator: std.mem.Allocator, destroyed: *usize) !*Owner {
        const owner = try allocator.create(Owner);
        owner.* = .{ .allocator = allocator, .destroyed = destroyed };
        return owner;
    }
    fn destroy(owner: *Owner) void {
        owner.destroyed.* += 1;
        owner.allocator.destroy(owner);
    }
};
