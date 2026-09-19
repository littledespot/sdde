//! R36 candidate faults; only the production runner executes recovery.
const std = @import("std");
const r = @import("../domain/reference_reconciliation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const workflow = @import("../application/reference_reconciliation_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
pub const Mode = enum { recover, exhaust };

pub fn mixed(a: std.mem.Allocator, input: r.Input, proposal: r.Proposal) !r.Proposal {
    var result = proposal;
    const token = for (input.items) |item| {
        if (item.claim.content == .preserved_token) break item.claim.id;
    } else return error.MissingFixtureToken;
    var signals: std.ArrayList(r.SignalProposal) = .empty;
    for (proposal.signals) |signal| {
        if (signal.content == .preserved_token and signal.claim_ids[0].ordinal == token.ordinal) continue;
        try signals.append(a, signal);
    }
    signals.items[0].claim_ids = try a.dupe(r.ClaimId, &.{ signals.items[0].claim_ids[0], token });
    result.signals = try signals.toOwnedSlice(a);
    return result;
}

pub fn corrupt(a: std.mem.Allocator, body: []const u8, part: []const u8, attempt: u32, mode: Mode) ![]const u8 {
    if (std.mem.eql(u8, part, "dispositions") and attempt == 1) {
        const at = (std.mem.indexOf(u8, body, ",{\"claim_id\"") orelse return error.MissingFixtureDisposition) + 1;
        return std.mem.concat(a, u8, &.{ body[0..at], "\"", body[at..] });
    }
    if (std.mem.eql(u8, part, "signals") and (attempt < 3 or mode == .exhaust)) {
        // Remove only the signal object's final brace, keeping inner objects
        // intact. Repeating this body exercises the unchanged-error limit.
        const marker = std.mem.indexOf(u8, body, "}}}") orelse return error.MissingFixtureSignal;
        return std.mem.concat(a, u8, &.{ body[0 .. marker + 2], body[marker + 3 ..] });
    }
    return body;
}

pub fn assertMerge(before: *const data.View, after: *const data.View, ordinal: usize) !void {
    if (ordinal < 2) return @import("summary_protocol_sequence.zig").assertMerge(before, after, ordinal, 1);
    const prior = (try native.read(before, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
    const current = (try native.read(after, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
    const left = prior.proposal.global;
    const right = current.proposal.global;
    try std.testing.expectEqual(prior.source.revision + 1, current.source.revision);
    try std.testing.expect(prior.source.origin == null and current.source.origin == null);
    try std.testing.expectEqualDeep(left.claim_dispositions, right.claim_dispositions);
    try std.testing.expectEqualDeep(left.conflicts, right.conflicts);
    for ([_]r.diagnostic.Unit{ .dispositions, .signals, .conflicts }) |unit|
        try std.testing.expectEqualDeep(prior.source.at(unit, .record), current.source.at(unit, .record));
    if (ordinal == 2) {
        try std.testing.expectEqual(left.signals.len, right.signals.len);
        try std.testing.expectEqual(@as(usize, 2), left.signals[0].claim_ids.len);
        try std.testing.expectEqual(@as(usize, 1), right.signals[0].claim_ids.len);
        try std.testing.expectEqualDeep(left.signals[0].content, right.signals[0].content);
        try std.testing.expectEqualDeep(left.signals[1..], right.signals[1..]);
        try std.testing.expectEqualDeep(prior.source.at(.{ .signal = 0 }, .content), current.source.at(.{ .signal = 0 }, .content));
        const ledger = try @import("../application/pipeline_values.zig").read(after, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        try std.testing.expectEqual(ledger.recordCount(), current.source.at(.{ .signal = 0 }, .selections).?.request.value);
    } else {
        try std.testing.expectEqual(@as(usize, 3), ordinal);
        try std.testing.expectEqual(left.signals.len + 1, right.signals.len);
        try std.testing.expectEqualDeep(left.signals, right.signals[0..left.signals.len]);
        try std.testing.expect(current.source.at(.{ .signal = left.signals.len }, .record) == null);
        try std.testing.expect(current.source.last_repair.?.origin == null);
    }
}

pub fn verify(driver: *@import("spec_generation_driver.zig").Driver, result: @import("../domain/run_outcome.zig").Outcome) !void {
    const exhausted = driver.global_sequence == .exhaust;
    const ledger = driver.runner.tokenLedger();
    try std.testing.expectEqual(driver.calls, ledger.accounted_operations.items.len);
    try std.testing.expectEqual(@as(u128, driver.calls) * (driver.fake.invocation_plan.complete.input_tokens + driver.fake.invocation_plan.complete.output_tokens), ledger.committed());
    const operations = ledger.accounted_operations.items;
    const attempts = [_]u32{ 1, 2, 1, 1, 1, 1, 2, 1, 2, 1, 2, 3 };
    const assignments = [_]usize{ 0, 0, 2, 3, 4, 5, 5, 7, 7, 9, 9, 9 };
    for (operations[0..12], attempts, assignments) |operation, attempt, first| {
        try std.testing.expectEqual(attempt, operation.id.model_attempt_ordinal.value);
        try std.testing.expect(operation.id.model_request_id == operations[first].id.model_request_id);
    }
    try std.testing.expect(operations[7].id.model_request_id != operations[9].id.model_request_id);
    const view: data.View = .{ .slots = driver.runner.envelope.slots };
    const extraction = (try native.read(&view, native.parsed_schema, .parsed)).payload().parsed;
    const producers = extraction.entries[0].producers.?;
    try std.testing.expectEqual(@as(u32, 2), producers.content.?.attempt.value);
    try std.testing.expectEqual(@as(u32, 1), producers.classifications.?.attempt.value);
    try std.testing.expectEqual(@as(usize, if (exhausted) 1 else 2), driver.reconciliation_repair_calls);
    try std.testing.expectEqual(@as(usize, if (exhausted) 2 else 4), driver.reconciliation_merges);
    try std.testing.expectEqual(@as(usize, 0), driver.unchanged_reconciliation_merges);
    if (exhausted) {
        try std.testing.expectEqual(@as(usize, 12), driver.calls);
        try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
        try std.testing.expectEqual(@as(u32, 2), result.execution_rejected.retry_limit.limit.value);
        try std.testing.expectEqual(@as(u64, 3), result.execution_rejected.retry_limit.completed_executions);
        const state = try @import("../application/json_composition_workflow.zig").readState(&view);
        try std.testing.expect(state.entries[0] != null and state.entries[1] == null and state.entries[2] == null);
        try std.testing.expectEqual(@as(u32, 2), state.entries[0].?.origin.attempt.value);
        const request = try requests.readCurrent(&view, requests.prepared_schema);
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const contents = request.prepared().?.content;
        const previous = try std.json.parseFromSlice(std.json.Value, arena.allocator(), contents[contents.len - 1].bytes(), .{});
        const observation = try @import("../application/model_payload_schema_workflow.zig").readCurrent(&view);
        try std.testing.expectEqualStrings(previous.value.object.get("rejected_response").?.string, @import("../application/model_envelope_workflow.zig").complete(observation.source().source()).?.content());
        try std.testing.expect(!view.contains(.published_workflow_output));
    } else {
        try std.testing.expectEqual(.ok, result.executionStatus().?);
        try std.testing.expect(view.contains(.published_workflow_output));
        try std.testing.expect(!view.contains(.json_composition) and !view.contains(.assembled_json));
        const accounted = (try native.read(&view, workflow.accounted_schema, .reconciliation_accounted)).payload().reconciliation_accounted;
        try std.testing.expectEqual(.complete, accounted.outcome);
        try std.testing.expectEqual(extraction.entries[0].outcome.claims.len + extraction.entries[0].token_classifications.len, accounted.records.signals.len);
        const source = accounted.records.assignments.checked.prior.prior.source;
        try std.testing.expect(source.origin == null);
        const dispositions = source.at(.dispositions, .record).?;
        const signals = source.at(.signals, .record).?;
        const conflicts = source.at(.conflicts, .record).?;
        try std.testing.expect(dispositions.request.value != signals.request.value and conflicts.request.value != signals.request.value);
        try std.testing.expectEqual(@as(u32, 2), dispositions.attempt.value);
        try std.testing.expectEqual(@as(u32, 3), signals.attempt.value);
        try std.testing.expectEqual(@as(u32, 1), conflicts.attempt.value);
    }
}
