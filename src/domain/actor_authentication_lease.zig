//! The runner-owned authentication lease (ADR 0025): one single-use slot for each invocation of an `actor_authentication`
//! step. The runner issues it before the step runs, the step's port consumes it once, and the runner checks afterwards that
//! an `ok` step consumed it. A lease carries no credential: what it grants is the one observation of the invoking account.
const std = @import("std");

/// One lease for each form a run can accept.
pub const max_leases = @import("clarification_inputs.zig").max_forms;
pub const Error = error{ LeaseUnavailable, AuthenticationDenied };

pub const Lease = struct {
    table: *Table,
    slot: u32,

    /// Take the lease once. A lease that was consumed or finalized, or whose slot the table did not issue, is denied. A lease
    /// carries its own table, so one table's lease cannot be spent on another's: an execution has one runner and one table.
    pub fn consume(self: Lease) Error!void {
        return self.table.consume(self.slot);
    }

    pub fn consumed(self: Lease) bool {
        return self.table.isConsumed(self.slot);
    }
};

pub const Table = struct {
    issued: u32 = 0,
    active: ?Active = null,

    const Active = struct { slot: u32, consumed: bool };

    /// One lease is outstanding at a time, and an execution issues at most `max_leases`.
    pub fn issue(self: *Table) Error!Lease {
        if (self.active != null or self.issued >= max_leases) return error.LeaseUnavailable;
        self.issued += 1;
        self.active = .{ .slot = self.issued, .consumed = false };
        return .{ .table = self, .slot = self.issued };
    }

    fn consume(self: *Table, slot: u32) Error!void {
        const active = &(self.active orelse return error.AuthenticationDenied);
        if (active.slot != slot or active.consumed) return error.AuthenticationDenied;
        active.consumed = true;
    }

    fn isConsumed(self: *const Table, slot: u32) bool {
        const active = self.active orelse return false;
        return active.slot == slot and active.consumed;
    }

    /// Ends the lease on every path of the step, consumed or not: nothing consumes it afterwards.
    pub fn finalize(self: *Table, lease: Lease) void {
        if (self.active) |active| if (active.slot == lease.slot) {
            self.active = null;
        };
    }
};

test "a lease is consumed once and only while it is the outstanding one" {
    var table: Table = .{};
    const first = try table.issue();
    try std.testing.expect(!first.consumed());
    try std.testing.expectError(error.LeaseUnavailable, table.issue());
    try first.consume();
    try std.testing.expect(first.consumed());
    try std.testing.expectError(error.AuthenticationDenied, first.consume());
    table.finalize(first);
    try std.testing.expect(!first.consumed());
    try std.testing.expectError(error.AuthenticationDenied, first.consume());
    const second = try table.issue();
    try std.testing.expect(second.slot != first.slot);
    try std.testing.expectError(error.AuthenticationDenied, first.consume());
    try second.consume();
}

test "a lease for a slot the table did not issue is denied" {
    var left: Table = .{};
    var right: Table = .{};
    const own = try left.issue();
    _ = try right.issue();
    const foreign: Lease = .{ .table = &right, .slot = own.slot + 1 };
    try std.testing.expectError(error.AuthenticationDenied, foreign.consume());
    try own.consume();
}

test "an execution issues at most one lease for each form it can accept" {
    var table: Table = .{};
    for (0..max_leases) |_| {
        const lease = try table.issue();
        try lease.consume();
        table.finalize(lease);
    }
    try std.testing.expectError(error.LeaseUnavailable, table.issue());
}
