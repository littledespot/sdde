//! Execution-local identities for candidate occurrences. Array edits move an
//! identity with its value; neither model text nor changing positions mint it.
const std = @import("std");
pub const Id = struct { ordinal: u32 };
pub const Error = std.mem.Allocator.Error || error{InvalidRepairOccurrence};

pub const Set = struct {
    values: []const Id = &.{},
    next_ordinal: u32 = 0,

    pub fn at(self: Set, index: usize, length: usize) Error!Id {
        if (index >= length) return error.InvalidRepairOccurrence;
        if (self.next_ordinal == 0) {
            if (self.values.len != 0) return error.InvalidRepairOccurrence;
            return .{ .ordinal = std.math.cast(u32, index + 1) orelse return error.InvalidRepairOccurrence };
        }
        if (self.values.len != length) return error.InvalidRepairOccurrence;
        const value = self.values[index];
        if (value.ordinal == 0 or value.ordinal >= self.next_ordinal) return error.InvalidRepairOccurrence;
        return value;
    }

    pub fn deleting(self: Set, a: std.mem.Allocator, index: usize, length: usize) Error!Set {
        _ = try self.at(index, length);
        const values = try a.alloc(Id, length - 1);
        errdefer a.free(values);
        for (values, 0..) |*value, output| value.* = try self.at(if (output < index) output else output + 1, length);
        return .{ .values = values, .next_ordinal = try self.next(length) };
    }

    pub fn inserting(self: Set, a: std.mem.Allocator, index: usize, length: usize) Error!Set {
        if (index > length) return error.InvalidRepairOccurrence;
        const assigned = try self.next(length);
        const next_ordinal = std.math.add(u32, assigned, 1) catch return error.InvalidRepairOccurrence;
        const size = std.math.add(usize, length, 1) catch return error.InvalidRepairOccurrence;
        const values = try a.alloc(Id, size);
        errdefer a.free(values);
        for (values, 0..) |*value, output| value.* = if (output == index)
            .{ .ordinal = assigned }
        else
            try self.at(if (output < index) output else output - 1, length);
        return .{ .values = values, .next_ordinal = next_ordinal };
    }

    /// A batch reserves every identity it has assigned, including deleted ones.
    /// Concatenation must use that span rather than its current live length.
    pub fn reservedSpan(self: Set, length: usize) Error!u32 {
        return (try self.next(length)) - 1;
    }

    /// Join independent occurrence owners without reusing either owner's gaps.
    /// Left identities stay fixed; right identities move by the left's complete
    /// reserved span. This is the same projection used by retained-batch views.
    pub fn concatenating(self: Set, a: std.mem.Allocator, length: usize, right: Set, right_length: usize) Error!Set {
        const offset = try self.reservedSpan(length);
        const span = std.math.add(u32, offset, try right.reservedSpan(right_length)) catch return error.InvalidRepairOccurrence;
        const next_ordinal = std.math.add(u32, span, 1) catch return error.InvalidRepairOccurrence;
        const size = std.math.add(usize, length, right_length) catch return error.InvalidRepairOccurrence;
        const values = try a.alloc(Id, size);
        errdefer a.free(values);
        for (values[0..length], 0..) |*value, index| value.* = try self.at(index, length);
        for (values[length..], 0..) |*value, index| value.* = .{
            .ordinal = std.math.add(u32, offset, (try right.at(index, right_length)).ordinal) catch return error.InvalidRepairOccurrence,
        };
        return .{ .values = values, .next_ordinal = next_ordinal };
    }

    fn next(self: Set, length: usize) Error!u32 {
        if (self.next_ordinal != 0) {
            if (self.values.len != length) return error.InvalidRepairOccurrence;
            return self.next_ordinal;
        }
        if (self.values.len != 0) return error.InvalidRepairOccurrence;
        const count = std.math.cast(u32, length) orelse return error.InvalidRepairOccurrence;
        return std.math.add(u32, count, 1) catch error.InvalidRepairOccurrence;
    }
};

test "deleting and inserting preserve sibling identity without reusing a deleted ordinal" {
    const a = std.testing.allocator;
    const initial: Set = .{};
    const last = try initial.at(2, 3);
    const removed = try initial.deleting(a, 1, 3);
    defer a.free(removed.values);
    try std.testing.expectEqual(last, try removed.at(1, 2));
    const inserted = try removed.inserting(a, 1, 2);
    defer a.free(inserted.values);
    try std.testing.expectEqual(last, try inserted.at(2, 3));
    try std.testing.expectEqual(@as(u32, 4), (try inserted.at(1, 3)).ordinal);
    try std.testing.expectError(error.InvalidRepairOccurrence, inserted.at(0, 2));
}

test "concatenation preserves deleted identity gaps and reserves them for later inserts" {
    const a = std.testing.allocator;
    const left: Set = .{ .values = &.{.{ .ordinal = 2 }}, .next_ordinal = 4 };
    const right: Set = .{ .values = &.{ .{ .ordinal = 1 }, .{ .ordinal = 3 } }, .next_ordinal = 5 };
    const joined = try left.concatenating(a, 1, right, 2);
    defer a.free(joined.values);
    try std.testing.expectEqual(@as(u32, 3), try left.reservedSpan(1));
    try std.testing.expectEqualDeep(&[_]Id{ .{ .ordinal = 2 }, .{ .ordinal = 4 }, .{ .ordinal = 6 } }, joined.values);
    try std.testing.expectEqual(@as(u32, 8), joined.next_ordinal);
    const inserted = try joined.inserting(a, 3, 3);
    defer a.free(inserted.values);
    try std.testing.expectEqual(@as(u32, 8), (try inserted.at(3, 4)).ordinal);
    try std.testing.expectError(error.InvalidRepairOccurrence, left.concatenating(a, 2, right, 2));
    try std.testing.expectError(error.InvalidRepairOccurrence, (Set{ .next_ordinal = std.math.maxInt(u32) }).concatenating(a, 0, .{}, 1));
}
