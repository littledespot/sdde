//! The operator's interrupt (SIGINT) as the run's one cancellation source. The handler only records that an interrupt
//! arrived; the run reads that through the capability-free `NodeRuntime` at its own boundaries and at each timer
//! slice of a model request, never inside a log sink call, so a cancellation stops the run between steps and the
//! logs close cleanly. The handler is one-shot (`RESETHAND`): a second interrupt ends the process as the default
//! action does. The flag is never cleared by `install`, so a process that runs several workflows in turn stops
//! each of the later ones at its first check.
const std = @import("std");
const builtin = @import("builtin");
const pipeline = @import("../../domain/pipeline.zig");

var requested: std.atomic.Value(bool) = .init(false);

fn onInterrupt(_: std.posix.SIG) callconv(.c) void {
    requested.store(true, .release);
}

fn status(_: ?*anyopaque) pipeline.RuntimeStatus {
    return if (requested.load(.acquire)) .cancelled else .active;
}

pub const Interrupt = struct {
    previous: std.posix.Sigaction,

    /// Installs the one-shot handler and keeps the action it replaced.
    pub fn install() Interrupt {
        const action: std.posix.Sigaction = .{
            .handler = .{ .handler = onInterrupt },
            .mask = std.posix.sigemptyset(),
            .flags = std.posix.SA.RESETHAND,
        };
        var previous: std.posix.Sigaction = undefined;
        std.posix.sigaction(.INT, &action, &previous);
        return .{ .previous = previous };
    }

    pub fn restore(self: *const Interrupt) void {
        std.posix.sigaction(.INT, &self.previous, null);
    }

    /// The status handle every runtime consumer reads. It carries no capability.
    pub fn runtime(_: *const Interrupt) pipeline.NodeRuntime {
        return .{ .status_fn = status };
    }
};

/// Clears the flag between tests; a production process never clears it.
fn resetForTest() void {
    if (!builtin.is_test) @compileError("test-only interrupt reset");
    requested.store(false, .release);
}

test "an interrupt cancels the run once, then the default action returns, and restore reinstates the prior one" {
    resetForTest();
    defer resetForTest();
    var interrupt = Interrupt.install();
    const runtime = interrupt.runtime();
    try std.testing.expectEqual(pipeline.RuntimeStatus.active, runtime.status());
    try std.posix.raise(.INT);
    try std.testing.expectEqual(pipeline.RuntimeStatus.cancelled, runtime.status());
    // The handler was one-shot: the disposition is the default again, so a second interrupt would end the process.
    var current: std.posix.Sigaction = undefined;
    std.posix.sigaction(.INT, null, &current);
    try std.testing.expect(current.handler.handler == std.posix.SIG.DFL);
    interrupt.restore();
    var restored: std.posix.Sigaction = undefined;
    std.posix.sigaction(.INT, null, &restored);
    try std.testing.expect(restored.handler.handler == interrupt.previous.handler.handler);
}
