const std = @import("std");
const routine = @import("application/feature_log_retention_routine.zig");
const feature_identity = @import("domain/feature_identity.zig");
const log_binding = @import("domain/feature_log_binding.zig");
const log_limits = @import("domain/feature_log_limits.zig");
const log_policy = @import("domain/log_policy.zig");
const log_stream = @import("domain/feature_log_stream.zig");
const telemetry = @import("domain/telemetry.zig");
const clock_port = @import("ports/trusted_log_clock.zig");
const sink_port = @import("ports/feature_log_sink.zig");

const now_unix_ms: u64 = 1_788_087_330_000;

const Call = enum { clock, acquire, prune, release };

/// Fake ports that record the order of their calls and fail where told.
const Fake = struct {
    calls: [8]Call = undefined,
    count: usize = 0,
    clock_fails: bool = false,
    acquire_fails: ?sink_port.Error = null,
    prune_fails: ?sink_port.Error = null,
    release_fails: ?sink_port.Error = null,
    pruned_stream: ?log_stream.Stream = null,
    pruned_cutoff: ?u64 = null,

    fn ports(self: *Fake) routine.Ports {
        return .{
            .clock = .{ .context = self, .now_fn = now },
            .acquirer = .{ .context = self, .acquire_fn = acquire },
            .pruner = .{ .context = self, .prune_fn = prune },
            .releaser = .{ .context = self, .release_fn = release },
        };
    }

    fn record(self: *Fake, call: Call) void {
        self.calls[self.count] = call;
        self.count += 1;
    }

    fn order(self: *const Fake) []const Call {
        return self.calls[0..self.count];
    }

    fn now(context: *anyopaque) clock_port.Error!log_stream.ClockReading {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.clock);
        if (self.clock_fails) return error.ClockFailure;
        return .{ .occurred_at_utc = "2026-08-30T10:15:30Z".*, .unix_ms = now_unix_ms, .monotonic_ms = 1 };
    }
    fn acquire(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, _: log_stream.Stream, _: u16) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.acquire);
        if (self.acquire_fails) |failure| return failure;
    }
    fn prune(context: *anyopaque, _: *const log_binding.ValidatedFeatureLogBinding, selected: log_stream.Stream, cutoff_unix_ms: u64) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.prune);
        self.pruned_stream = selected;
        self.pruned_cutoff = cutoff_unix_ms;
        if (self.prune_fails) |failure| return failure;
    }
    fn release(context: *anyopaque) sink_port.Error!void {
        const self: *Fake = @ptrCast(@alignCast(context));
        self.record(.release);
        if (self.release_fails) |failure| return failure;
    }
};

const policy: log_policy.CompiledLoggingPolicy = .{ .level = .{ .threshold = .debug, .alias_evidence = .none }, .console = false };

fn candidate(run: []const u8, feature: []const u8) log_binding.BindingCandidate {
    return .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .run_id = telemetry.Identifier.validate(run).?,
        .feature_id = feature_identity.FeatureId.parse(feature).?,
    };
}

/// One prune of `stream` for a prior run of `feature`, against the current run's binding.
fn exercise(fake: *Fake, feature: []const u8, stream: log_stream.Stream, diagnostic: *routine.Diagnostic) !routine.Outcome {
    const current_owner = try log_binding.createValidated(std.testing.allocator, candidate("RUN-CURRENT", "F0002"));
    defer log_binding.deinitOwner(current_owner);
    const historical_owner = try log_binding.createValidated(std.testing.allocator, candidate("RUN-HIST", feature));
    defer log_binding.deinitOwner(historical_owner);
    return routine.run(fake.ports(), .{
        .allocator = std.testing.allocator,
        .policy = &policy,
        .current = log_binding.binding(current_owner),
        .historical = log_binding.binding(historical_owner),
        .target_stream = stream,
    }, diagnostic);
}

test "retention authorizes from the trusted clock, locks the prior run's stream, prunes the cutoff and releases, in either stream" {
    inline for (.{ log_stream.Stream.event, log_stream.Stream.prompt }) |stream| {
        var fake: Fake = .{};
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, "F0002", stream, &diagnostic);
        try std.testing.expect(outcome == .ok);
        try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire, .prune, .release }, fake.order());
        try std.testing.expectEqual(@as(?log_stream.Stream, stream), fake.pruned_stream);
        try std.testing.expectEqual(@as(?u64, now_unix_ms - log_limits.retention_period_ms), fake.pruned_cutoff);
        try std.testing.expectEqual(@as(?routine.Step, null), diagnostic.step);
    }
}

test "an authorization that cannot be built stops before any lock is taken" {
    // The trusted clock fails.
    {
        var fake: Fake = .{ .clock_fails = true };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, "F0002", .event, &diagnostic);
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .authorize), diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{.clock}, fake.order());
    }
    // A prior run of another feature is no run this feature may prune: the unrelated member of the class.
    {
        var fake: Fake = .{};
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, "F0003", .event, &diagnostic);
        try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .authorize), diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{.clock}, fake.order());
    }
}

test "each retention step takes its one port or domain rule and answers for itself" {
    const log_retention = @import("domain/feature_log_retention.zig");
    const current_owner = try log_binding.createValidated(std.testing.allocator, candidate("RUN-CURRENT", "F0002"));
    defer log_binding.deinitOwner(current_owner);
    const historical_owner = try log_binding.createValidated(std.testing.allocator, candidate("RUN-HIST", "F0002"));
    defer log_binding.deinitOwner(historical_owner);
    const other_owner = try log_binding.createValidated(std.testing.allocator, candidate("RUN-OTHER", "F0003"));
    defer log_binding.deinitOwner(other_owner);
    const current = log_binding.binding(current_owner);
    const historical = log_binding.binding(historical_owner);
    const other = log_binding.binding(other_owner);
    var fake: Fake = .{};
    // Authorizing reads the trusted clock once and builds the single-use authorization. A clock that fails, or a prior
    // run of another feature, builds none.
    const authorization = try routine.steps.authorize(fake.ports().clock, std.testing.allocator, &policy, current, historical, .event);
    defer log_retention.deinit(authorization);
    var broken: Fake = .{ .clock_fails = true };
    try std.testing.expectError(error.FeatureLogRetentionAuthorizationInvalid, routine.steps.authorize(broken.ports().clock, std.testing.allocator, &policy, current, historical, .event));
    try std.testing.expectError(error.FeatureLogRetentionAuthorizationInvalid, routine.steps.authorize(fake.ports().clock, std.testing.allocator, &policy, current, other, .event));
    // The authorization names the stream it was made for, for the bindings it was made for, and no other.
    try std.testing.expectEqual(log_stream.Stream.event, try routine.steps.resolveStream(authorization, current, historical));
    try std.testing.expectError(error.FeatureLogRetentionAuthorizationInvalid, routine.steps.resolveStream(authorization, current, other));
    // A lock: taken, or stopped with the code of its kind.
    try std.testing.expect(routine.steps.acquire(fake.ports().acquirer, historical, .event) == null);
    for ([_]struct { failure: sink_port.Error, stop: log_stream.Stop }{
        .{ .failure = error.LockUnavailable, .stop = .{ .blocked = .LOG_LOCK_TIMEOUT } },
        .{ .failure = error.SinkFailure, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var failing: Fake = .{ .acquire_fails = case.failure };
        try std.testing.expectEqual(case.stop, routine.steps.acquire(failing.ports().acquirer, historical, .event).?);
    }
    // Pruning consumes the authorization: the first prune reaches the port with the cutoff, a second reaches nothing.
    try std.testing.expect(routine.steps.prune(fake.ports().pruner, historical, authorization) == null);
    try std.testing.expectEqual(@as(?u64, now_unix_ms - log_limits.retention_period_ms), fake.pruned_cutoff);
    const pruned_before = fake.count;
    try std.testing.expectEqual(log_stream.Stop{ .blocked = .LOG_SINK_FAILURE }, routine.steps.prune(fake.ports().pruner, historical, authorization).?);
    try std.testing.expectEqual(pruned_before, fake.count);
    // A prune the sink refuses, or cancels, is its own stop.
    const again = try routine.steps.authorize(fake.ports().clock, std.testing.allocator, &policy, current, historical, .prompt);
    defer log_retention.deinit(again);
    var refusing: Fake = .{ .prune_fails = error.Cancelled };
    try std.testing.expectEqual(log_stream.Stop.cancelled, routine.steps.prune(refusing.ports().pruner, historical, again).?);
    // A release that worked, and one that failed.
    try std.testing.expect(routine.steps.release(fake.ports().releaser));
    var stuck: Fake = .{ .release_fails = error.ReleaseFailure };
    try std.testing.expect(!routine.steps.release(stuck.ports().releaser));
}

test "a lock held elsewhere is a timeout, a sink failure and a cancellation are their own stops, and none releases a lock it never took" {
    const Case = struct { failure: sink_port.Error, stop: log_stream.Stop };
    for ([_]Case{
        .{ .failure = error.LockUnavailable, .stop = .{ .blocked = .LOG_LOCK_TIMEOUT } },
        .{ .failure = error.SinkFailure, .stop = .{ .blocked = .LOG_SINK_FAILURE } },
        .{ .failure = error.Cancelled, .stop = .cancelled },
    }) |case| {
        var fake: Fake = .{ .acquire_fails = case.failure };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, "F0002", .event, &diagnostic);
        try std.testing.expectEqual(case.stop, outcome.stopped);
        try std.testing.expectEqual(@as(?routine.Step, .acquire), diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire }, fake.order());
    }
}

test "the lock is released after any prune outcome and the prune stop is the one kept" {
    const Case = struct { prune: ?sink_port.Error, release: ?sink_port.Error, stop: ?log_stream.Stop, step: ?routine.Step };
    for ([_]Case{
        // A failed prune.
        .{ .prune = error.SinkFailure, .release = null, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .prune },
        // A cancelled prune is a cancellation, and the lock is still released.
        .{ .prune = error.Cancelled, .release = null, .stop = .cancelled, .step = .prune },
        // A lock that cannot be released after a failed or cancelled prune does not replace the stop that came first.
        .{ .prune = error.SinkFailure, .release = error.ReleaseFailure, .stop = .{ .blocked = .LOG_SINK_FAILURE }, .step = .prune },
        .{ .prune = error.Cancelled, .release = error.ReleaseFailure, .stop = .cancelled, .step = .prune },
        // A release that fails after a good prune is a logging failure of its own.
        .{ .prune = null, .release = error.ReleaseFailure, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .release },
        // A release that reports a cancellation has failed to release.
        .{ .prune = null, .release = error.Cancelled, .stop = .{ .blocked = .LOG_RELEASE_FAILURE }, .step = .release },
    }) |case| {
        var fake: Fake = .{ .prune_fails = case.prune, .release_fails = case.release };
        var diagnostic: routine.Diagnostic = .{};
        const outcome = try exercise(&fake, "F0002", .event, &diagnostic);
        try std.testing.expectEqual(case.stop.?, outcome.stopped);
        try std.testing.expectEqual(case.step, diagnostic.step);
        try std.testing.expectEqualSlices(Call, &.{ .clock, .acquire, .prune, .release }, fake.order());
    }
}
