//! The operating-system account adapter (ADR 0025): it observes the account the engine process runs as, behind the
//! authentication port. It holds no credential and reads no file: the account is the process's own user and its name the
//! system password database's entry for it. It authenticates the account, not a person.
const std = @import("std");
const builtin = @import("builtin");
const port = @import("../../ports/actor_authentication.zig");
const clock_port = @import("../../ports/trusted_log_clock.zig");
const evidence = @import("../../domain/actor_evidence.zig");
const lease = @import("../../domain/actor_authentication_lease.zig");
const log_stream = @import("../../domain/feature_log_stream.zig");

/// The operating systems whose password database `getpwuid_r` reads; any other reports `UnsupportedPlatform`.
const supported = switch (builtin.os.tag) {
    .linux, .driverkit, .ios, .maccatalyst, .macos, .tvos, .visionos, .watchos, .freebsd, .openbsd, .netbsd, .dragonfly => true,
    else => false,
};

pub const Adapter = struct {
    clock: clock_port.Clock,
    /// The run's identity, which the feature log owns and hands over when it activates; none before.
    run_id: ?[]const u8 = null,

    pub fn authenticator(self: *Adapter) port.Port {
        return .{ .context = @ptrCast(self), .observe_fn = observe };
    }

    fn observe(context: *port.Context, allocator: std.mem.Allocator) port.Error!evidence.Observation {
        const self: *Adapter = @ptrCast(@alignCast(context));
        const run_id = self.run_id orelse return error.AccountUnavailable;
        const reading = self.clock.now() catch return error.ClockUnavailable;
        const actor_id = try accountName(allocator);
        errdefer allocator.free(actor_id);
        return .{
            .provider = .os_account,
            .actor_id = actor_id,
            .assurance = .invoking_account,
            .run_id = try allocator.dupe(u8, run_id),
            .occurred_at = reading.occurred_at_utc,
        };
    }
};

fn accountName(allocator: std.mem.Allocator) port.Error![]const u8 {
    if (comptime !supported) return error.UnsupportedPlatform;
    var storage: std.c.passwd = undefined;
    var found: ?*std.c.passwd = null;
    var buffer: [4096]u8 = undefined;
    if (std.c.getpwuid_r(std.c.getuid(), &storage, &buffer, buffer.len, &found) != 0) return error.AccountUnavailable;
    const entry = found orelse return error.AccountUnavailable;
    const name = std.mem.span(entry.name orelse return error.AccountUnavailable);
    if (name.len == 0) return error.AccountUnavailable;
    return allocator.dupe(u8, name);
}

const FakeClock = struct {
    fail: bool = false,

    fn clock(self: *FakeClock) clock_port.Clock {
        return .{ .context = self, .now_fn = now };
    }

    fn now(context: *anyopaque) clock_port.Error!log_stream.ClockReading {
        const self: *FakeClock = @ptrCast(@alignCast(context));
        if (self.fail) return error.ClockFailure;
        var reading: log_stream.ClockReading = .{ .occurred_at_utc = undefined, .unix_ms = 0, .monotonic_ms = 0 };
        @memcpy(&reading.occurred_at_utc, "2026-11-23T08:15:00Z");
        return reading;
    }
};

test "the adapter observes the invoking account once, with the run and the trusted time" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var fake: FakeClock = .{};
    var adapter: Adapter = .{ .clock = fake.clock(), .run_id = "RUN-1" };
    var table: lease.Table = .{};
    const granted = try table.issue();
    // An operating system outside the supported families is a typed failure, and the lease is spent all the same.
    if (comptime !supported) {
        try std.testing.expectError(error.UnsupportedPlatform, adapter.authenticator().authenticate(arena.allocator(), .{}, granted));
        try std.testing.expect(granted.consumed());
        return;
    }
    const observed = try adapter.authenticator().authenticate(arena.allocator(), .{}, granted);
    try std.testing.expect(observed.provider == .os_account and observed.assurance == .invoking_account);
    try std.testing.expect(observed.actor_id.len != 0);
    try std.testing.expectEqualStrings("RUN-1", observed.run_id);
    try std.testing.expectEqualStrings("2026-11-23T08:15:00Z", &observed.occurred_at);
    try std.testing.expect(evidence.validUtc(&observed.occurred_at));
    // The lease is spent: a second observation with it is denied.
    try std.testing.expectError(error.AuthenticationDenied, adapter.authenticator().authenticate(arena.allocator(), .{}, granted));
}

test "the adapter observes nothing without a run identity or a trusted clock" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var fake: FakeClock = .{};
    var adapter: Adapter = .{ .clock = fake.clock() };
    var table: lease.Table = .{};
    try std.testing.expectError(error.AccountUnavailable, adapter.authenticator().authenticate(arena.allocator(), .{}, try table.issue()));
    table.finalize(.{ .table = &table, .slot = table.issued });
    adapter.run_id = "RUN-1";
    fake.fail = true;
    try std.testing.expectError(error.ClockUnavailable, adapter.authenticator().authenticate(arena.allocator(), .{}, try table.issue()));
}

test "a runtime that is no longer active cancels before the lease is consumed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var fake: FakeClock = .{};
    var adapter: Adapter = .{ .clock = fake.clock(), .run_id = "RUN-1" };
    var table: lease.Table = .{};
    const granted = try table.issue();
    const stopped: @import("../../domain/pipeline.zig").NodeRuntime = .{ .status_fn = struct {
        fn status(_: ?*anyopaque) @import("../../domain/pipeline.zig").RuntimeStatus {
            return .cancelled;
        }
    }.status };
    try std.testing.expectError(error.Cancelled, adapter.authenticator().authenticate(arena.allocator(), stopped, granted));
    try std.testing.expect(!granted.consumed());
}
