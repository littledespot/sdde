//! Experiment-wide dispatch accounting. Native provider observations supply
//! actual usage; this ledger never reserves tokens or interprets response bytes.
const std = @import("std");
pub const ProviderUsage = @import("../../../src/domain/llm_provider_operation.zig").ProviderUsage;

pub const Limits = struct {
    maximum_sends: u64,
    maximum_actual_tokens: u64,
};

pub const Send = struct { ordinal: u64 };
pub const Reason = enum {
    send_limit,
    token_limit,
    usage_unavailable,
    uncertain_delivery,
    configuration_drift,
    evidence_failure,
    scoring_disputed,
    operator_stop,
};
pub const Error = error{
    InvalidLimits,
    ExperimentHalted,
    ExchangeInFlight,
    InvalidReconciliation,
    InvalidUsage,
    AccountingOverflow,
};

pub const Snapshot = struct {
    limits: Limits,
    physical_sends: u64,
    reconciled_sends: u64,
    in_flight: ?Send,
    total_accounted_tokens: u128,
    /// Known consumption is retained separately when a send has unknown usage.
    total_actual_tokens: ?u128,
    usage_complete: bool,
    uncertain_delivery: bool,
    halt_reason: ?Reason,
    /// Equality stops new sends. Only consumption above a limit is overshoot.
    overshot: bool,
};

pub const Gate = struct {
    limits: Limits,
    physical_sends: u64 = 0,
    reconciled_sends: u64 = 0,
    in_flight: ?Send = null,
    total_accounted_tokens: u128 = 0,
    usage_complete: bool = true,
    uncertain_delivery: bool = false,
    halt_reason: ?Reason = null,

    pub fn init(limits: Limits) Error!Gate {
        if (limits.maximum_sends == 0 or limits.maximum_actual_tokens == 0) return error.InvalidLimits;
        return .{ .limits = limits };
    }

    /// Called only after request capture succeeds, immediately before the
    /// physical transport attempt. Delivery failure never refunds this send.
    pub fn beforeSend(self: *Gate) Error!Send {
        if (self.halt_reason != null) return error.ExperimentHalted;
        if (self.in_flight != null) return error.ExchangeInFlight;
        if (self.physical_sends >= self.limits.maximum_sends) {
            self.stop(.send_limit);
            return error.ExperimentHalted;
        }
        if (self.total_accounted_tokens >= self.limits.maximum_actual_tokens) {
            self.stop(.token_limit);
            return error.ExperimentHalted;
        }
        // The positive limit and check above prove increment cannot overflow.
        self.physical_sends += 1;
        const send: Send = .{ .ordinal = self.physical_sends };
        self.in_flight = send;
        return send;
    }

    /// Reconcile exactly one charged send after its production accounting
    /// boundary, even if an independent reason already stopped the experiment.
    /// Missing usage and uncertain delivery stop subsequent physical attempts.
    pub fn reconcile(self: *Gate, send: Send, usage: ?ProviderUsage, uncertain_delivery: bool) Error!void {
        const pending = self.in_flight orelse {
            self.stop(.evidence_failure);
            return error.InvalidReconciliation;
        };
        if (send.ordinal != pending.ordinal) {
            self.stop(.evidence_failure);
            return error.InvalidReconciliation;
        }
        if (usage) |value| {
            if (ProviderUsage.init(value.input_tokens, value.output_tokens, value.total_tokens) == null) {
                self.usage_complete = false;
                self.stop(.evidence_failure);
                return error.InvalidUsage;
            }
            self.total_accounted_tokens = std.math.add(u128, self.total_accounted_tokens, value.total_tokens) catch {
                self.usage_complete = false;
                self.stop(.evidence_failure);
                return error.AccountingOverflow;
            };
        } else {
            self.usage_complete = false;
            self.stop(.usage_unavailable);
        }
        self.in_flight = null;
        self.reconciled_sends += 1;
        if (uncertain_delivery) {
            self.uncertain_delivery = true;
            self.stop(.uncertain_delivery);
        }
        if (self.total_accounted_tokens >= self.limits.maximum_actual_tokens) self.stop(.token_limit);
        if (self.physical_sends >= self.limits.maximum_sends) self.stop(.send_limit);
    }

    pub fn stop(self: *Gate, reason: Reason) void {
        if (self.halt_reason == null) self.halt_reason = reason;
    }

    pub fn snapshot(self: *const Gate) Snapshot {
        // An unresolved physical attempt has no complete actual-consumption
        // total, even before its eventual usage-unavailable stop is recorded.
        const complete = self.usage_complete and self.in_flight == null;
        return .{
            .limits = self.limits,
            .physical_sends = self.physical_sends,
            .reconciled_sends = self.reconciled_sends,
            .in_flight = self.in_flight,
            .total_accounted_tokens = self.total_accounted_tokens,
            .total_actual_tokens = if (complete) self.total_accounted_tokens else null,
            .usage_complete = complete,
            .uncertain_delivery = self.uncertain_delivery,
            .halt_reason = self.halt_reason,
            .overshot = self.physical_sends > self.limits.maximum_sends or self.total_accounted_tokens > self.limits.maximum_actual_tokens,
        };
    }
};

fn sampleUsage(input: u64, output: u64) ProviderUsage {
    return ProviderUsage.init(input, output, input + output).?;
}

test "baseline dispatch validates limits and charges before exactly one serial exchange" {
    try std.testing.expectError(error.InvalidLimits, Gate.init(.{ .maximum_sends = 0, .maximum_actual_tokens = 1 }));
    try std.testing.expectError(error.InvalidLimits, Gate.init(.{ .maximum_sends = 1, .maximum_actual_tokens = 0 }));
    var gate = try Gate.init(.{ .maximum_sends = 3, .maximum_actual_tokens = 100 });
    const first = try gate.beforeSend();
    try std.testing.expectEqual(@as(u64, 1), first.ordinal);
    try std.testing.expectEqual(@as(u64, 1), gate.snapshot().physical_sends);
    try std.testing.expect(!gate.snapshot().usage_complete);
    try std.testing.expect(gate.snapshot().total_actual_tokens == null);
    try std.testing.expectError(error.ExchangeInFlight, gate.beforeSend());
    try gate.reconcile(first, sampleUsage(10, 5), false);
    const second = try gate.beforeSend();
    try std.testing.expectEqual(@as(u64, 2), second.ordinal);
    try gate.reconcile(second, sampleUsage(20, 10), false);
    const observed = gate.snapshot();
    try std.testing.expectEqual(@as(u64, 2), observed.reconciled_sends);
    try std.testing.expectEqual(@as(?u128, 45), observed.total_actual_tokens);
    try std.testing.expect(observed.halt_reason == null and !observed.overshot);
}

test "baseline send and token equality halt further sends without claiming overshoot" {
    for ([_]Limits{
        .{ .maximum_sends = 1, .maximum_actual_tokens = 100 },
        .{ .maximum_sends = 3, .maximum_actual_tokens = 15 },
    }, 0..) |limits, index| {
        var gate = try Gate.init(limits);
        try gate.reconcile(try gate.beforeSend(), sampleUsage(10, 5), false);
        const observed = gate.snapshot();
        try std.testing.expectEqual(@as(?Reason, if (index == 0) .send_limit else .token_limit), observed.halt_reason);
        try std.testing.expect(!observed.overshot and observed.usage_complete);
        try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
        try std.testing.expectEqual(@as(u64, 1), gate.physical_sends);
    }
}

test "baseline counts complete actual overshoot without token reservations" {
    var gate = try Gate.init(.{ .maximum_sends = 3, .maximum_actual_tokens = 20 });
    try gate.reconcile(try gate.beforeSend(), sampleUsage(10, 5), false);
    try gate.reconcile(try gate.beforeSend(), sampleUsage(10, 8), false);
    try std.testing.expectEqual(@as(?u128, 33), gate.snapshot().total_actual_tokens);
    try std.testing.expect(gate.snapshot().overshot);
    try std.testing.expectEqual(@as(?Reason, .token_limit), gate.snapshot().halt_reason);
    try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
}

test "baseline unknown or uncertain consumption stops without refunding failed attempts" {
    for (0..3) |failure| {
        var gate = try Gate.init(.{ .maximum_sends = 4, .maximum_actual_tokens = 100 });
        try gate.reconcile(try gate.beforeSend(), sampleUsage(10, 5), false);
        try gate.reconcile(try gate.beforeSend(), if (failure == 0 or failure == 2) null else sampleUsage(1, 2), failure != 0);
        const observed = gate.snapshot();
        try std.testing.expectEqual(@as(u64, 2), observed.physical_sends);
        try std.testing.expectEqual(@as(u64, 2), observed.reconciled_sends);
        try std.testing.expectEqual(@as(u128, if (failure == 1) 18 else 15), observed.total_accounted_tokens);
        try std.testing.expectEqual(failure == 1, observed.usage_complete);
        try std.testing.expectEqual(failure != 0, observed.uncertain_delivery);
        try std.testing.expectEqual(@as(?Reason, if (failure == 1) .uncertain_delivery else .usage_unavailable), observed.halt_reason);
        try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
    }
}

test "baseline rejects duplicate foreign and malformed usage without double accounting" {
    for (0..3) |failure| {
        var gate = try Gate.init(.{ .maximum_sends = 5, .maximum_actual_tokens = 100 });
        const first = try gate.beforeSend();
        switch (failure) {
            0 => {
                try gate.reconcile(first, sampleUsage(10, 5), false);
                try std.testing.expectError(error.InvalidReconciliation, gate.reconcile(first, sampleUsage(10, 5), false));
            },
            1 => try std.testing.expectError(error.InvalidReconciliation, gate.reconcile(.{ .ordinal = first.ordinal + 1 }, sampleUsage(10, 5), false)),
            2 => try std.testing.expectError(error.InvalidUsage, gate.reconcile(first, .{ .input_tokens = 10, .output_tokens = 5, .total_tokens = 1 }, false)),
            else => unreachable,
        }
        try std.testing.expectEqual(@as(u128, if (failure == 0) 15 else 0), gate.total_accounted_tokens);
        try std.testing.expectEqual(@as(?Reason, .evidence_failure), gate.halt_reason);
        try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
    }
}

test "baseline explicit stops are sticky and do not discard inflight usage" {
    for ([_]Reason{ .configuration_drift, .evidence_failure, .scoring_disputed, .operator_stop }) |reason| {
        var gate = try Gate.init(.{ .maximum_sends = 1, .maximum_actual_tokens = 5 });
        const first = try gate.beforeSend();
        gate.stop(reason);
        gate.stop(.operator_stop);
        try gate.reconcile(first, sampleUsage(4, 4), false);
        try std.testing.expectEqual(@as(?Reason, reason), gate.snapshot().halt_reason);
        try std.testing.expectEqual(@as(?u128, 8), gate.snapshot().total_actual_tokens);
        try std.testing.expect(gate.snapshot().overshot);
        try std.testing.expectError(error.ExperimentHalted, gate.beforeSend());
    }
}

test "baseline aggregate usage exceeds u64 without truncation" {
    var gate = try Gate.init(.{ .maximum_sends = 3, .maximum_actual_tokens = std.math.maxInt(u64) });
    const half = std.math.maxInt(u64) / 2;
    try gate.reconcile(try gate.beforeSend(), sampleUsage(half, 0), false);
    try gate.reconcile(try gate.beforeSend(), sampleUsage(half, 4), false);
    try std.testing.expectEqual(@as(?u128, @as(u128, std.math.maxInt(u64)) + 3), gate.snapshot().total_actual_tokens);
    try std.testing.expect(gate.snapshot().overshot);
}
