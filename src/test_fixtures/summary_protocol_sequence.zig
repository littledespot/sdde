//! R35-shaped scripted responses and assertions; production owns every transition.
const std = @import("std");
const r = @import("../domain/reference_reconciliation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const workflow = @import("../application/reference_reconciliation_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
pub const Mode = enum { recover, exhaust };

pub fn response(a: std.mem.Allocator, input: r.Input, attempt: u32, mode: Mode) ![]const u8 {
    var proposal = try @import("reference_reconciliation.zig").summary(a, input);
    const first = input.progress.summary_count == 0;
    if (first) {
        // After shape admission, native validation must discover both mixed
        // content and the token coverage defect exposed by repairing selection.
        try std.testing.expect(proposal.statements.len >= 2);
        const statements = try a.dupe(r.StatementProposal, proposal.statements);
        statements[0].claim_ids = try a.dupe(r.ClaimId, &.{ input.items[0].claim.id, input.items[1].claim.id });
        const retained = try a.alloc(r.StatementProposal, statements.len - 1);
        retained[0] = statements[0];
        @memcpy(retained[1..], statements[2..]);
        proposal.statements = retained;
    }
    const body = try @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), a, .{ .summary = proposal });
    if (input.progress.summary_count > 1 or (attempt == 3 and (first or mode == .recover))) return body;
    var parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    const statement = &parsed.value.object.getPtr("statements").?.array.items[0];
    const content = statement.object.getPtr("content").?;
    const kind = content.object.get("kind").?;
    _ = content.object.swapRemove("kind");
    if (!first and attempt > 1) try statement.object.put(a, "kind", kind);
    // The independent summary also nests a token payload incorrectly. Fixing
    // the first diagnostic alone cannot establish complete shape conformance.
    if (!first and attempt == 1) {
        const token = parsed.value.object.getPtr("statements").?.array.items[1].object.getPtr("content").?;
        const id = token.object.get("token_id").?;
        _ = token.object.swapRemove("token_id");
        var wrapper: std.json.ObjectMap = .{};
        try wrapper.put(a, "token_id", id);
        try token.object.put(a, "preserved_token", .{ .object = wrapper });
    }
    return std.json.Stringify.valueAlloc(a, parsed.value, .{});
}

pub fn assertMerge(before: *const data.View, after: *const data.View, ordinal: usize, initial_attempt: u32) !void {
    const prior = (try native.read(before, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
    const current = (try native.read(after, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
    const left = prior.proposal.summary.statements;
    const right = current.proposal.summary.statements;
    try std.testing.expectEqual(@as(u64, ordinal + 1), prior.source.revision);
    try std.testing.expectEqual(prior.source.revision + 1, current.source.revision);
    try std.testing.expectEqualDeep(prior.source.origin, current.source.origin);
    try std.testing.expectEqual(initial_attempt, current.source.origin.?.attempt.value);
    if (ordinal == 0) {
        try std.testing.expectEqual(left.len, right.len);
        try std.testing.expectEqual(@as(usize, 2), left[0].claim_ids.len);
        try std.testing.expectEqual(@as(usize, 1), right[0].claim_ids.len);
        try std.testing.expectEqualDeep(left[0].content, right[0].content);
        try std.testing.expectEqualDeep(left[1..], right[1..]);
        try std.testing.expectEqualDeep(prior.source.at(.{ .statement = 0 }, .content), current.source.at(.{ .statement = 0 }, .content));
        const identities = try @import("../application/pipeline_values.zig").read(after, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        try std.testing.expectEqual(identities.recordCount(), current.source.at(.{ .statement = 0 }, .selections).?.request.value);
        try std.testing.expect(identities.latestRecord().?.model_request_id.purpose == .atomic_repair);
    } else {
        try std.testing.expectEqual(@as(usize, 1), ordinal);
        try std.testing.expectEqual(left.len + 1, right.len);
        for (left, 0..) |statement, index| {
            const preserved = for (right) |candidate| {
                if (candidate.local_key == statement.local_key) break candidate;
            } else return error.MissingSibling;
            try std.testing.expectEqualDeep(statement, preserved);
            try std.testing.expectEqualDeep(prior.source.at(.{ .statement = index }, .content), current.source.at(.{ .statement = index }, .content));
        }
        try std.testing.expect(current.source.last_repair.?.origin == null);
    }
}

pub fn verify(driver: *@import("spec_generation_driver.zig").Driver, result: @import("../domain/run_outcome.zig").Outcome) !void {
    const runner = driver.runner;
    try std.testing.expectEqual(@as(usize, 1), driver.reconciliation_repair_calls);
    try std.testing.expectEqual(@as(usize, 2), driver.reconciliation_merges);
    try std.testing.expectEqual(@as(usize, 0), driver.unchanged_reconciliation_merges);
    const ledger = runner.tokenLedger();
    try std.testing.expectEqual(driver.calls, ledger.accounted_operations.items.len);
    try std.testing.expectEqual(@as(u128, driver.calls) * (driver.fake.invocation_plan.complete.input_tokens + driver.fake.invocation_plan.complete.output_tokens), ledger.committed());
    const operations = ledger.accounted_operations.items;
    try std.testing.expect(operations.len >= 10);
    const ordinals = [_]u32{ 1, 2, 1, 1, 2, 3, 1, 1, 2, 3 };
    const requests_by_call = [_]usize{ 0, 0, 2, 3, 3, 3, 6, 7, 7, 7 };
    for (operations[0..10], ordinals, requests_by_call) |operation, attempt, first_call| {
        try std.testing.expectEqual(attempt, operation.id.model_attempt_ordinal.value);
        try std.testing.expect(operation.id.model_request_id == operations[first_call].id.model_request_id);
    }
    try std.testing.expect(operations[3].id.model_request_id != operations[7].id.model_request_id);
    const view: data.View = .{ .slots = runner.envelope.slots };
    const extraction = (try native.read(&view, native.parsed_schema, .parsed)).payload().parsed;
    const producers = extraction.entries[0].producers.?;
    try std.testing.expectEqual(@as(u32, 2), producers.content.?.attempt.value);
    try std.testing.expectEqual(@as(u32, 1), producers.classifications.?.attempt.value);
    try std.testing.expect(producers.content.?.request.value != producers.classifications.?.request.value);
    if (driver.summary_sequence == .exhaust) {
        try std.testing.expectEqual(@as(usize, 10), driver.calls);
        try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
        try std.testing.expectEqual(@as(u32, 2), result.execution_rejected.retry_limit.limit.value);
        try std.testing.expectEqual(@as(u64, 3), result.execution_rejected.retry_limit.completed_executions);
        try std.testing.expect(!view.contains(.published_workflow_output));
    } else {
        try std.testing.expectEqual(.ok, result.executionStatus().?);
        try std.testing.expect(view.contains(.published_workflow_output));
        const accounted = (try native.read(&view, workflow.accounted_schema, .reconciliation_accounted)).payload().reconciliation_accounted;
        try std.testing.expectEqual(.complete, accounted.outcome);
        try std.testing.expectEqual(extraction.entries[0].outcome.claims.len + extraction.entries[0].token_classifications.len, accounted.records.signals.len);
    }
}
