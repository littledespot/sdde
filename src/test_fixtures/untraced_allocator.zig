//! Leak-checked test allocation without per-allocation stack traces.
//!
//! `std.testing.allocator` captures a 10-frame stack trace on every allocation,
//! resize and free; on aarch64 Darwin each capture is a DWARF unwind. Sweeps that
//! allocate millions of times spend most of their run there. This allocator keeps
//! the double-free, invalid-free and size-mismatch checks and drops the traces, so
//! a leak report names the address but not the allocating call. Switch a call site
//! back to `std.testing.allocator` to see where a reported leak came from.
//!
//! Leaks are rejected from a live byte count, so the check holds in every optimize
//! mode. The canary differs from `std.testing.allocator`'s, so freeing through the
//! wrong one of the two is caught. Instances share a canary: use one at a time in a
//! test and don't nest them.
//!
//! Any test may use it. It knows nothing about workflows, drivers or fixtures; a
//! test chooses it once and passes the allocator down.
const std = @import("std");

const Debug = std.heap.DebugAllocator(.{ .stack_trace_frames = 0, .enable_memory_limit = true });

pub const Untraced = struct {
    debug: Debug = .init,

    pub fn allocator(self: *Untraced) std.mem.Allocator {
        return self.debug.allocator();
    }

    /// Rejects any allocation that is still live, without logging.
    pub fn expectNoLeaks(self: *const Untraced) error{MemoryLeakDetected}!void {
        if (self.debug.total_requested_bytes != 0) return error.MemoryLeakDetected;
    }

    /// Calls `body(allocator, args...)` with this allocator, then rejects any leak.
    pub fn run(self: *Untraced, comptime body: anytype, args: ExtraArgs(@TypeOf(body))) !void {
        try @call(.auto, body, .{self.allocator()} ++ args);
        try self.expectNoLeaks();
    }

    /// Runs `std.testing.checkAllAllocationFailures` over this allocator, then
    /// rejects any leak. The standard sweep checks each failure-injected pass
    /// itself; only the backing allocator sees a leak in its first, counting pass.
    pub fn checkAllAllocationFailures(self: *Untraced, comptime test_fn: anytype, extra_args: ExtraArgs(@TypeOf(test_fn))) !void {
        try std.testing.checkAllAllocationFailures(self.allocator(), test_fn, extra_args);
        try self.expectNoLeaks();
    }

    /// Releases the allocator and rejects anything still live. With runtime safety
    /// each remaining allocation is also logged as an error, which fails the test.
    pub fn deinit(self: *Untraced) error{MemoryLeakDetected}!void {
        const live = self.expectNoLeaks();
        const check = self.debug.deinit();
        try live;
        if (check == .leak) return error.MemoryLeakDetected;
    }
};

/// Replaces `std.testing.checkAllAllocationFailures(std.testing.allocator, ...)`.
pub fn checkAllAllocationFailures(comptime test_fn: anytype, extra_args: ExtraArgs(@TypeOf(test_fn))) !void {
    var untraced: Untraced = .{};
    const outcome = untraced.checkAllAllocationFailures(test_fn, extra_args);
    const released = untraced.deinit();
    try outcome;
    try released;
}

/// Calls `body(allocator, args...)` with a fresh untraced allocator, then rejects
/// any leak. Use it for a test body that allocates heavily through one allocator.
pub fn run(comptime body: anytype, args: ExtraArgs(@TypeOf(body))) !void {
    var untraced: Untraced = .{};
    const outcome = untraced.run(body, args);
    const released = untraced.deinit();
    try outcome;
    try released;
}

/// The parameters of `Fn` after its leading allocator.
fn ExtraArgs(comptime Fn: type) type {
    const fields = @typeInfo(std.meta.ArgsTuple(Fn)).@"struct".fields;
    if (fields.len == 0 or fields[0].type != std.mem.Allocator) {
        @compileError("The provided function must have an " ++ @typeName(std.mem.Allocator) ++ " as its first argument");
    }
    var types: [fields.len - 1]type = undefined;
    for (&types, fields[1..]) |*field_type, field| field_type.* = field.type;
    return @Tuple(&types);
}

// Each rejection test frees what it kept before asserting, so a failed assertion
// never leaves the allocator or its allocation behind.

test "untraced allocation accepts a scope that frees everything" {
    var untraced: Untraced = .{};
    const bytes = try untraced.allocator().alloc(u8, 16);
    untraced.allocator().free(bytes);
    const after_free = untraced.expectNoLeaks();
    try untraced.deinit();
    try after_free;
}

test "untraced allocation reports a live allocation as a leak" {
    var untraced: Untraced = .{};
    const bytes = try untraced.allocator().alloc(u8, 16);
    const while_live = untraced.expectNoLeaks();
    untraced.allocator().free(bytes);
    try untraced.deinit();
    try std.testing.expectError(error.MemoryLeakDetected, while_live);
}

test "untraced run passes a fresh allocator to a body that frees everything" {
    const Body = struct {
        fn allocates(allocator: std.mem.Allocator, length: usize, seen: *usize) !void {
            const bytes = try allocator.alloc(u8, length);
            defer allocator.free(bytes);
            seen.* = bytes.len;
        }
    };
    var seen: usize = 0;
    try run(Body.allocates, .{ 32, &seen });
    try std.testing.expectEqual(@as(usize, 32), seen);
}

test "untraced run rejects a body that keeps an allocation" {
    const Body = struct {
        fn keeps(allocator: std.mem.Allocator, kept: *?[]u8) !void {
            kept.* = try allocator.alloc(u8, 8);
        }
    };
    var untraced: Untraced = .{};
    var kept: ?[]u8 = null;
    const outcome = untraced.run(Body.keeps, .{&kept});
    if (kept) |bytes| untraced.allocator().free(bytes);
    try untraced.deinit();
    try std.testing.expectError(error.MemoryLeakDetected, outcome);
}

test "untraced sweep runs every failure index for a case that frees on every path" {
    const Case = struct {
        fn freesOnEveryPath(allocator: std.mem.Allocator, calls: *usize) !void {
            calls.* += 1;
            const first = try allocator.alloc(u8, 1);
            defer allocator.free(first);
            const second = try allocator.alloc(u8, 2);
            defer allocator.free(second);
        }
    };
    var calls: usize = 0;
    try checkAllAllocationFailures(Case.freesOnEveryPath, .{&calls});
    // One counting pass, then one pass per allocation with that allocation failing.
    try std.testing.expectEqual(@as(usize, 3), calls);
}

test "untraced sweep rejects a counting-pass leak that the standard sweep accepts" {
    const Case = struct {
        fn keepsFirstSuccess(allocator: std.mem.Allocator, kept: *?[]u8) !void {
            kept.* = try allocator.alloc(u8, 4);
        }
    };
    // The standard sweep balances bytes only on failure-injected passes.
    var unchecked: ?[]u8 = null;
    const unchecked_sweep = std.testing.checkAllAllocationFailures(std.heap.page_allocator, Case.keepsFirstSuccess, .{&unchecked});
    if (unchecked) |bytes| std.heap.page_allocator.free(bytes);
    try unchecked_sweep;

    var untraced: Untraced = .{};
    var kept: ?[]u8 = null;
    const swept = untraced.checkAllAllocationFailures(Case.keepsFirstSuccess, .{&kept});
    if (kept) |bytes| untraced.allocator().free(bytes);
    try untraced.deinit();
    try std.testing.expectError(error.MemoryLeakDetected, swept);
}
