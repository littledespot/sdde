//! Reforecast every declared future phase from the observed baseline envelope.
//! This is cost planning, never a token reservation or dispatch authorization.
const std = @import("std");
const comparison = @import("../generation_comparison.zig");
const feasibility = @import("feasibility.zig");
const dispatch = @import("dispatch.zig");

pub const FuturePhase = struct { phase: feasibility.Phase, workloads: u64 };
pub const Report = struct {
    status: enum { incomplete, outside_declared_scope, fits, exceeds },
    projection: enum { worst_observed_baseline_workflow } = .worst_observed_baseline_workflow,
    consumed_sends: u64,
    known_consumed_tokens: u128,
    consumed_tokens: ?u128,
    future_phases: []const FuturePhase,
    future_workloads: ?u64,
    worst_observed_sends: ?u64,
    worst_observed_tokens: ?u64,
    cost_extent: enum { complete_workflow_observed, stopped_lower_bound },
    projected_total_sends: ?u128,
    projected_total_tokens: ?u128,
    /// Forecasts cannot enforce future dispatch or promise candidate costs.
    dispatch_authority: bool = false,

    pub fn deinit(self: Report, a: std.mem.Allocator) void {
        a.free(self.future_phases);
    }
};

pub fn evaluate(a: std.mem.Allocator, protocol: comparison.Protocol, phases: []const feasibility.Phase, spent: dispatch.Snapshot, required_features: ?u32, observations: []const comparison.Observation) !Report {
    var future: std.ArrayList(FuturePhase) = .empty;
    errdefer future.deinit(a);
    var qualification_covered = false;
    var future_workloads: ?u64 = 0;
    for (phases, 0..) |phase, index| {
        for (phases[0..index]) |prior| if (prior == phase) return error.InvalidQualificationBudget;
        if (phase == .baseline) continue;
        const bounds = try feasibility.phaseWorkloads(protocol, phase);
        const workloads = switch (phase) {
            .baseline => unreachable,
            .selection => bounds.maximum_workloads,
            .qualification => count: {
                qualification_covered = true;
                const count = required_features orelse {
                    future_workloads = null;
                    continue;
                };
                if (protocol.qualification.minimum_features == 0 or bounds.minimum_workloads % protocol.qualification.minimum_features != 0) return error.InvalidQualificationBudget;
                break :count try std.math.mul(u64, count, bounds.minimum_workloads / protocol.qualification.minimum_features);
            },
        };
        try future.append(a, .{ .phase = phase, .workloads = workloads });
        if (future_workloads) |total| future_workloads = try std.math.add(u64, total, workloads);
    }
    var worst_sends: ?u64 = null;
    var worst_tokens: ?u64 = null;
    var usage_complete = true;
    var completed_product_flow = false;
    for (observations) |observation| {
        if (observation.status == .unattempted) continue;
        completed_product_flow = completed_product_flow or (observation.status == .completed and observation.published);
        worst_sends = @max(worst_sends orelse 0, observation.physical_sends);
        if (observation.usage) |usage| {
            const tokens = try std.math.add(u64, usage.input_tokens, usage.output_tokens);
            worst_tokens = @max(worst_tokens orelse 0, tokens);
        } else usage_complete = false;
    }
    const projected_sends = if (future_workloads) |workloads| if (worst_sends) |cost| try std.math.add(u128, spent.physical_sends, try std.math.mul(u128, workloads, cost)) else null else null;
    const projected_tokens = if (spent.total_actual_tokens) |consumed| if (usage_complete and future_workloads != null and worst_tokens != null) try std.math.add(u128, consumed, try std.math.mul(u128, future_workloads.?, worst_tokens.?)) else null else null;
    const status: @FieldType(Report, "status") = if (!qualification_covered)
        .outside_declared_scope
    else if (projected_sends == null or projected_tokens == null or !spent.usage_complete or spent.uncertain_delivery or spent.in_flight != null)
        .incomplete
    else if (projected_sends.? > spent.limits.maximum_sends or projected_tokens.? > spent.limits.maximum_actual_tokens)
        .exceeds
    else if (!completed_product_flow)
        .incomplete
    else
        .fits;
    return .{
        .status = status,
        .consumed_sends = spent.physical_sends,
        .known_consumed_tokens = spent.total_accounted_tokens,
        .consumed_tokens = spent.total_actual_tokens,
        .future_phases = try future.toOwnedSlice(a),
        .future_workloads = future_workloads,
        .worst_observed_sends = worst_sends,
        .worst_observed_tokens = if (usage_complete) worst_tokens else null,
        .cost_extent = if (completed_product_flow) .complete_workflow_observed else .stopped_lower_bound,
        .projected_total_sends = projected_sends,
        .projected_total_tokens = projected_tokens,
    };
}

const Test = struct {
    fn protocol(a: std.mem.Allocator) !comparison.Protocol {
        return comparison.parseProtocol(a, @embedFile("../../calibration/semantic-simplicity/protocol.json"));
    }
    const duties = [_]comparison.DutyAssessment{.{ .id = "duty", .preserved = true }};
    fn observation() comparison.Observation {
        return .{ .trial_ordinal = 1, .initial = .{ .status = .completed, .duties = &duties, .questions_correct = true, .structural_valid = true, .issues = .{} }, .status = .completed, .duties = &duties, .questions_correct = true, .structural_valid = true, .published = true, .corrective_sends = 0, .physical_sends = 2, .issues = .{}, .usage = .{ .input_tokens = 7000, .output_tokens = 1000 }, .elapsed_ns = 1, .uncertain_delivery = false, .scoring_disputed = false };
    }
    fn spent() dispatch.Snapshot {
        var gate = dispatch.Gate.init(.{ .maximum_sends = 1000, .maximum_actual_tokens = 2000000 }) catch unreachable;
        for (0..72) |_| gate.reconcile(gate.beforeSend() catch unreachable, dispatch.ProviderUsage.init(7000, 1000, 8000).?, false) catch unreachable;
        return gate.snapshot();
    }
};

test "qualification reforecast retains selection demand instead of silently spending its allowance" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try Test.protocol(a);
    const observation = Test.observation();
    const qualification_only = try evaluate(a, protocol, &.{ .baseline, .qualification }, Test.spent(), 8, &.{observation});
    try std.testing.expectEqual(.fits, qualification_only.status);
    try std.testing.expectEqual(@as(?u128, 1728000), qualification_only.projected_total_tokens);
    const all_phases = try evaluate(a, protocol, &.{ .baseline, .selection, .qualification }, Test.spent(), 8, &.{observation});
    try std.testing.expectEqual(.exceeds, all_phases.status);
    try std.testing.expectEqual(@as(?u128, 2880000), all_phases.projected_total_tokens);
    try std.testing.expectEqual(@as(?u64, 288), all_phases.future_workloads);
    try std.testing.expectEqual(@as(usize, 2), all_phases.future_phases.len);
    try std.testing.expect(!all_phases.dispatch_authority);
}

test "unknown usage missing sizing and undeclared qualification cannot become a fitting forecast" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const protocol = try Test.protocol(a);
    var observation = Test.observation();
    observation.usage = null;
    const unknown = try evaluate(a, protocol, &.{ .baseline, .qualification }, Test.spent(), 8, &.{observation});
    try std.testing.expectEqual(.incomplete, unknown.status);
    try std.testing.expect(unknown.projected_total_tokens == null and unknown.worst_observed_tokens == null);
    const unsized = try evaluate(a, protocol, &.{ .baseline, .selection, .qualification }, Test.spent(), null, &.{Test.observation()});
    try std.testing.expectEqual(.incomplete, unsized.status);
    try std.testing.expect(unsized.future_workloads == null);
    const undeclared = try evaluate(a, protocol, &.{.baseline}, Test.spent(), 8, &.{Test.observation()});
    try std.testing.expectEqual(.outside_declared_scope, undeclared.status);
    observation = Test.observation();
    observation.status = .blocked;
    observation.published = false;
    const stopped = try evaluate(a, protocol, &.{ .baseline, .qualification }, Test.spent(), 8, &.{observation});
    try std.testing.expectEqual(.incomplete, stopped.status);
    try std.testing.expectEqual(.stopped_lower_bound, stopped.cost_extent);
    try std.testing.expectError(error.InvalidQualificationBudget, evaluate(a, protocol, &.{ .baseline, .qualification, .qualification }, Test.spent(), 8, &.{Test.observation()}));
}
