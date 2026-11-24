//! Every repair merge a run's steps retained, once for each authorization and in the order first seen.
//!
//! The report reads a candidate's last merge from the run's final state, so a merge that a later merge
//! or a later unit replaced is gone by then. The trace sees each step's state, so it keeps them here.
//! The log reads facts the engine retained and decides nothing.
const std = @import("std");
const Merge = @import("../../../src/domain/atomic_repair.zig").Merge;

pub const Log = struct {
    /// Owns the list and every merge it holds.
    arena: std.heap.ArenaAllocator,
    merges: std.ArrayList(Merge) = .empty,

    pub fn init(allocator: std.mem.Allocator) Log {
        return .{ .arena = .init(allocator) };
    }

    pub fn deinit(self: *Log) void {
        self.arena.deinit();
    }

    /// Keep each merge of one step's state that the log hasn't seen. A merge the step still retains and
    /// the log holds is the same merge (one authorization makes one), so it adds nothing.
    pub fn observe(self: *Log, retained: []const Merge) !void {
        const a = self.arena.allocator();
        next: for (retained) |merge| {
            for (self.merges.items) |seen| if (std.mem.eql(u8, seen.authorization.bytes, merge.authorization.bytes)) continue :next;
            try self.merges.append(a, try merge.copy(a));
        }
    }

    /// The merges seen, in the order first seen, copied into the caller's arena.
    pub fn project(self: *const Log, a: std.mem.Allocator) ![]const Merge {
        const result = try a.alloc(Merge, self.merges.items.len);
        for (self.merges.items, result) |merge, *copy| copy.* = try merge.copy(a);
        return result;
    }

    /// A run's merges: the steps' and then any the run's final state retains that no step saw.
    pub fn finish(self: *Log, a: std.mem.Allocator, final: []const Merge) ![]const Merge {
        try self.observe(final);
        return self.project(a);
    }
};

fn merged(authorization: []const u8, before: u64, changed: bool) Merge {
    return .{ .authorization = .{ .bytes = authorization }, .owner = .workflow_step, .operation = .replace, .revision_before = before, .revision_after = before + 1, .changed = changed, .origin = null };
}

test "a merge that later steps no longer retain is still reported, once, in the order first seen" {
    var log: Log = .init(std.testing.allocator);
    defer log.deinit();
    // Each step's state is its own storage, released before the next step: the log keeps copies.
    const steps = [_][]const Merge{
        &.{merged("a", 1, true)},
        // The first unit's merge is still retained beside the second's.
        &.{ merged("a", 1, true), merged("b", 1, false) },
        // A later merge of the second unit replaced b, and a later unit dropped a.
        &.{merged("c", 2, true)},
        &.{merged("c", 2, true)},
        &.{},
    };
    for (steps) |retained| {
        var state: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer state.deinit();
        const copies = try state.allocator().alloc(Merge, retained.len);
        for (retained, copies) |merge, *copy| copy.* = try merge.copy(state.allocator());
        try log.observe(copies);
    }
    var report: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer report.deinit();
    const projected = try log.project(report.allocator());
    try std.testing.expectEqual(@as(usize, 3), projected.len);
    for ([_][]const u8{ "a", "b", "c" }, projected) |authorization, merge| try std.testing.expectEqualStrings(authorization, merge.authorization.bytes);
    // Each merge keeps its own facts.
    try std.testing.expectEqual(true, projected[0].changed);
    try std.testing.expectEqual(false, projected[1].changed);
    try std.testing.expectEqual(@as(u64, 3), projected[2].revision_after);
    // Reading the log changes nothing, and a read is independent of the log's storage.
    const again = try log.project(report.allocator());
    try std.testing.expectEqualDeep(projected, again);
}

test "a merge only the final state holds follows those the steps saw, and an empty final state drops none" {
    var log: Log = .init(std.testing.allocator);
    defer log.deinit();
    try log.observe(&.{merged("a", 1, true)});
    var report: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer report.deinit();
    const final = [_]Merge{ merged("a", 1, true), merged("z", 4, true) };
    const projected = try log.finish(report.allocator(), &final);
    try std.testing.expectEqual(@as(usize, 2), projected.len);
    for ([_][]const u8{ "a", "z" }, projected) |authorization, merge| try std.testing.expectEqualStrings(authorization, merge.authorization.bytes);
    try std.testing.expectEqual(@as(usize, 2), (try log.finish(report.allocator(), &.{})).len);
}

test "a log with no retained merge reports none" {
    var log: Log = .init(std.testing.allocator);
    defer log.deinit();
    try log.observe(&.{});
    var report: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer report.deinit();
    try std.testing.expectEqual(@as(usize, 0), (try log.project(report.allocator())).len);
}
