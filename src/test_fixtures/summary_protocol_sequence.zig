//! Summary-reconciliation protocol scripted responses and assertions; production owns every transition.
const std = @import("std");
const r = @import("../domain/reference_reconciliation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const workflow = @import("../application/reference_reconciliation_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const Driver = @import("spec_generation_driver.zig").Driver;
pub const Mode = enum { recover, exhaust };

/// The calls one scripted request takes. A request the script answers wrongly until its step's retry limit
/// is spent takes every attempt the compiled workflow allows it, so its count follows from that limit and
/// is never typed (SPEC01 C45); any other request takes the count its script fixes.
pub const Calls = union(enum) { fixed: u32, allowance };

/// For each call of a run, in order: its attempt ordinal and the call that opened its request.
pub const Shape = struct {
    ordinals: []u32,
    first_calls: []usize,
};

/// The calls of `requests_plan` in order, where a request answered until the limit is spent takes `allowance` calls.
pub fn expand(a: std.mem.Allocator, requests_plan: []const Calls, allowance: u32) std.mem.Allocator.Error!Shape {
    var ordinals: std.ArrayList(u32) = .empty;
    var first_calls: std.ArrayList(usize) = .empty;
    for (requests_plan) |entry| {
        const count: u32 = switch (entry) {
            .fixed => |fixed| fixed,
            .allowance => allowance,
        };
        const first = ordinals.items.len;
        for (1..@as(usize, count) + 1) |ordinal| {
            try ordinals.append(a, @intCast(ordinal));
            try first_calls.append(a, first);
        }
    }
    return .{ .ordinals = try ordinals.toOwnedSlice(a), .first_calls = try first_calls.toOwnedSlice(a) };
}

/// The shape of the accounted calls: each one's attempt ordinal, and the first call of the request it belongs to.
pub fn observe(a: std.mem.Allocator, operations: []const @import("../domain/workflow_token_accounting.zig").AccountedOperation) std.mem.Allocator.Error!Shape {
    const ordinals = try a.alloc(u32, operations.len);
    const first_calls = try a.alloc(usize, operations.len);
    for (operations, 0..) |operation, call| {
        ordinals[call] = operation.id.model_attempt_ordinal.value;
        first_calls[call] = if (call != 0 and operations[call - 1].id.model_request_id == operation.id.model_request_id) first_calls[call - 1] else call;
    }
    return .{ .ordinals = ordinals, .first_calls = first_calls };
}

pub fn expectShape(expected: Shape, observed: Shape) !void {
    try std.testing.expectEqualSlices(u32, expected.ordinals, observed.ordinals);
    try std.testing.expectEqualSlices(usize, expected.first_calls, observed.first_calls);
}

/// The call that opens the first request answered until the limit is spent, or null for a plan with none.
pub fn firstAllowanceCall(requests_plan: []const Calls) ?usize {
    var calls: usize = 0;
    for (requests_plan) |entry| switch (entry) {
        .fixed => |fixed| calls += fixed,
        .allowance => return calls,
    };
    return null;
}

pub const Checked = struct { allowance: u32, calls: usize };

/// Checks the run's accounted calls against `requests_plan`, expanded for the attempts the compiled workflow
/// allows the request the plan answers until the limit is spent. The allowance is read from that request's
/// own step, so changing a step's `retry-limit` changes the expected positions with it, and every other such
/// request must have the same allowance.
pub fn checkSequence(driver: *Driver, requests_plan: []const Calls) !Checked {
    var arena: std.heap.ArenaAllocator = .init(driver.allocator);
    defer arena.deinit();
    const operations = driver.runner.tokenLedger().accounted_operations.items;
    const opening = firstAllowanceCall(requests_plan) orelse return error.PlanHasNoAllowanceRequest;
    try std.testing.expect(operations.len > opening);
    const allowance = try driver.allowance(operations[opening].id.model_request_id);
    const shape = try expand(arena.allocator(), requests_plan, allowance);
    try std.testing.expect(operations.len >= shape.ordinals.len);
    try expectShape(shape, try observe(arena.allocator(), operations[0..shape.ordinals.len]));
    // Every planned request is its own, and each one answered until the limit is spent has that allowance.
    var call: usize = 0;
    var previous: ?usize = null;
    for (requests_plan) |entry| {
        if (previous) |opened| try std.testing.expect(operations[opened].id.model_request_id != operations[call].id.model_request_id);
        switch (entry) {
            .fixed => |fixed| {
                previous = call;
                call += fixed;
            },
            .allowance => {
                try std.testing.expectEqual(allowance, try driver.allowance(operations[call].id.model_request_id));
                previous = call;
                call += allowance;
            },
        }
    }
    return .{ .allowance = allowance, .calls = shape.ordinals.len };
}

/// `attempt` is the answer's attempt ordinal and `allowance` the attempts the request's step allows: the
/// script answers wrongly on every attempt before the last one allowed, and rightly on it unless `mode` exhausts.
pub fn response(a: std.mem.Allocator, input: r.Input, attempt: u32, allowance: u32, mode: Mode) ![]const u8 {
    var proposal = try @import("reference_reconciliation.zig").summary(a, input);
    const first = input.progress.summary_count == 0;
    if (first) {
        // Native validation rejects eligible semantic IDs mixing content kinds;
        // mandatory token projections are constructed independently.
        try std.testing.expect(proposal.statements.len >= 2);
        const statements = try a.dupe(r.StatementProposal, proposal.statements);
        statements[0].claim_ids = try a.dupe(r.ClaimId, &.{ input.items[0].claim.id, input.items[1].claim.id });
        proposal.statements = statements;
    }
    const body = try @import("reference_reconciliation.zig").modelWire(a, .{ .summary = proposal });
    if (input.progress.summary_count > 1 or (attempt == allowance and (first or mode == .recover))) return body;
    var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    const statements = parsed.value.object.getPtr("statements").?;
    if (statements.array.items.len == 0) {
        // A token-only partition has no semantic statements to echo. Distinct
        // malformed collection shapes still exercise bounded correction.
        statements.* = if (attempt == 1) .{ .string = "invalid" } else .null;
    } else {
        const statement = &statements.array.items[0];
        const content = statement.object.getPtr("content").?;
        const kind = content.object.get("kind").?;
        _ = content.object.swapRemove("kind");
        if (!first and attempt > 1) try statement.object.put(a, "kind", kind);
    }
    return std.json.Stringify.valueAlloc(a, parsed.value, .{});
}

/// The attempt that produced the candidate a merge repairs: the first, or the last its request's step allows.
pub const Initial = enum { first_attempt, last_allowed_attempt };

pub fn assertMerge(driver: *const Driver, before: *const data.View, after: *const data.View, ordinal: usize, initial: Initial) !void {
    const prior = (try native.read(before, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
    const current = (try native.read(after, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
    const identities = try @import("../application/pipeline_values.zig").read(after, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
    const left = prior.proposal.summary.statements;
    const right = current.proposal.summary.statements;
    try std.testing.expectEqual(@as(u64, ordinal + 1), prior.source.revision);
    try std.testing.expectEqual(prior.source.revision + 1, current.source.revision);
    try std.testing.expectEqualDeep(prior.source.origin, current.source.origin);
    const initial_attempt: u32 = switch (initial) {
        .first_attempt => 1,
        .last_allowed_attempt => try driver.originAllowance(identities, current.source.origin.?),
    };
    try std.testing.expectEqual(initial_attempt, current.source.origin.?.attempt.value);
    try std.testing.expectEqual(@as(usize, 0), ordinal);

    try std.testing.expectEqual(left.len, right.len);
    try std.testing.expectEqual(@as(usize, 2), left[0].claim_ids.len);
    try std.testing.expectEqual(@as(usize, 1), right[0].claim_ids.len);
    try std.testing.expectEqualDeep(left[0].content, right[0].content);
    try std.testing.expectEqualDeep(left[1..], right[1..]);
    try std.testing.expectEqualDeep(prior.source.at(.{ .statement = 0 }, .content), current.source.at(.{ .statement = 0 }, .content));
    try std.testing.expectEqual(identities.recordCount(), current.source.at(.{ .statement = 0 }, .selections).?.request.value);
    try std.testing.expect(identities.latestRecord().?.model_request_id.purpose == .atomic_repair);
}

/// The summary scenarios' requests in call order: the extraction content request (a protocol fault, then its
/// correction), the classification request, the first summary request (faulty until the last attempt its step
/// allows), the repair of that candidate, and the second summary request, which `Mode` recovers or exhausts.
pub const plan = [_]Calls{ .{ .fixed = 2 }, .{ .fixed = 1 }, .allowance, .{ .fixed = 1 }, .allowance };

pub fn verify(driver: *Driver, result: @import("../domain/run_outcome.zig").Outcome) !void {
    const runner = driver.runner;
    try std.testing.expectEqual(@as(usize, 1), driver.reconciliation_repair_calls);
    try std.testing.expectEqual(@as(usize, 1), driver.reconciliation_merges);
    try std.testing.expectEqual(@as(usize, 0), driver.unchanged_reconciliation_merges);
    const ledger = runner.tokenLedger();
    try std.testing.expectEqual(driver.calls, ledger.accounted_operations.items.len);
    try std.testing.expectEqual(@as(u128, driver.calls) * (driver.fake.invocation_plan.complete.input_tokens + driver.fake.invocation_plan.complete.output_tokens), ledger.committed());
    const checked = try checkSequence(driver, &plan);
    const view: data.View = .{ .slots = runner.envelope.slots };
    const extraction = (try native.read(&view, native.parsed_schema, .parsed)).payload().parsed;
    const producers = extraction.entries[0].producers.?;
    try std.testing.expectEqual(@as(u32, 2), producers.content.?.attempt.value);
    try std.testing.expectEqual(@as(u32, 1), producers.classifications.?.attempt.value);
    try std.testing.expect(producers.content.?.request.value != producers.classifications.?.request.value);
    if (driver.summary_sequence == .exhaust) {
        try std.testing.expectEqual(checked.calls, driver.calls);
        try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
        try std.testing.expectEqual(checked.allowance - 1, result.execution_rejected.retry_limit.limit.value);
        try std.testing.expectEqual(@as(u64, checked.allowance), result.execution_rejected.retry_limit.completed_executions);
        try std.testing.expect(!view.contains(.published_workflow_output));
    } else {
        try std.testing.expectEqual(.ok, result.executionStatus().?);
        try std.testing.expect(view.contains(.published_workflow_output));
        const accounted = (try native.read(&view, workflow.accounted_schema, .reconciliation_accounted)).payload().reconciliation_accounted;
        try std.testing.expectEqual(.complete, accounted.outcome);
        try std.testing.expectEqual(extraction.entries[0].outcome.claims.len + extraction.entries[0].token_classifications.len, accounted.records.signals.len);
    }
}
