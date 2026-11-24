//! Global-reconciliation protocol candidate faults; only the production runner executes recovery.
const std = @import("std");
const r = @import("../domain/reference_reconciliation.zig");
const native = @import("../application/reference_extraction_workflow.zig");
const workflow = @import("../application/reference_reconciliation_workflow.zig");
const requests = @import("../application/model_request_workflow.zig");
const data = @import("../domain/pipeline_data.zig");
const summary = @import("summary_protocol_sequence.zig");
const Driver = @import("spec_generation_driver.zig").Driver;
pub const Mode = enum { recover, exhaust };

pub fn mixed(a: std.mem.Allocator, input: r.Input, proposal: r.Proposal) !r.Proposal {
    var result = proposal;
    // Both IDs are eligible semantic claims; their incompatible kinds still
    // require native content validation after protocol admission.
    const first = proposal.signals[0];
    const other = for (input.items) |item| {
        if (item.claim.content == .model and std.meta.activeTag(item.claim.content.model) != std.meta.activeTag(first.content.model)) break item.claim.id;
    } else return error.MissingFixtureSemanticKind;
    const signals = try a.dupe(r.SignalProposal, proposal.signals);
    signals[0].claim_ids = try a.dupe(r.ClaimId, &.{ first.claim_ids[0], other });
    result.signals = signals;
    return result;
}

/// `attempt` is the answer's attempt ordinal and `allowance` the attempts the request's step allows: the
/// signals answer is faulty on every attempt before the last one allowed, and on that one too when `mode` exhausts.
pub fn corrupt(a: std.mem.Allocator, body: []const u8, part: []const u8, attempt: u32, allowance: u32, mode: Mode) ![]const u8 {
    if (std.mem.eql(u8, part, "dispositions") and attempt == 1) {
        const at = (std.mem.indexOf(u8, body, ",{\"claim_id\"") orelse return error.MissingFixtureDisposition) + 1;
        return std.mem.concat(a, u8, &.{ body[0..at], "\"", body[at..] });
    }
    if (std.mem.eql(u8, part, "signals") and (attempt < allowance or mode == .exhaust)) {
        // Remove only the signal object's final brace, keeping inner objects
        // intact. Repeating this body exercises the unchanged-error limit.
        const parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
        const first = try std.json.Stringify.valueAlloc(a, parsed.value.object.get("signals").?.array.items[0], .{});
        const marker = (std.mem.indexOf(u8, body, first) orelse return error.MissingFixtureSignal) + first.len - 1;
        try std.testing.expectEqual(@as(u8, '}'), body[marker]);
        return std.mem.concat(a, u8, &.{ body[0..marker], body[marker + 1 ..] });
    }
    return body;
}

pub fn assertMerge(driver: *const Driver, before: *const data.View, after: *const data.View, ordinal: usize) !void {
    if (ordinal == 0) return summary.assertMerge(driver, before, after, ordinal, .first_attempt);
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
    try std.testing.expectEqual(@as(usize, 1), ordinal);
    {
        try std.testing.expectEqual(left.signals.len, right.signals.len);
        try std.testing.expectEqual(@as(usize, 2), left.signals[0].claim_ids.len);
        try std.testing.expectEqual(@as(usize, 1), right.signals[0].claim_ids.len);
        try std.testing.expectEqualDeep(left.signals[0].content, right.signals[0].content);
        try std.testing.expectEqualDeep(left.signals[1..], right.signals[1..]);
        try std.testing.expectEqualDeep(prior.source.at(.{ .signal = 0 }, .content), current.source.at(.{ .signal = 0 }, .content));
        const ledger = try @import("../application/pipeline_values.zig").read(after, requests.ledger_schema, @import("../domain/model_request_identity.zig").ModelRequestIdentityLedger);
        try std.testing.expectEqual(ledger.recordCount(), current.source.at(.{ .signal = 0 }, .selections).?.request.value);
    }
}

/// The global scenarios' requests in call order: the extraction content request (a protocol fault, then its
/// correction), the classification request, the two summary requests, the dispositions assignment (its
/// scripted fault, then its correction), and the signals request (faulty until the last attempt its step
/// allows, which `Mode` recovers or exhausts).
pub const plan = [_]summary.Calls{ .{ .fixed = 2 }, .{ .fixed = 1 }, .{ .fixed = 1 }, .{ .fixed = 1 }, .{ .fixed = 2 }, .allowance };

pub fn verify(driver: *Driver, result: @import("../domain/run_outcome.zig").Outcome) !void {
    const exhausted = driver.global_sequence == .exhaust;
    const ledger = driver.runner.tokenLedger();
    try std.testing.expectEqual(driver.calls, ledger.accounted_operations.items.len);
    try std.testing.expectEqual(@as(u128, driver.calls) * (driver.fake.invocation_plan.complete.input_tokens + driver.fake.invocation_plan.complete.output_tokens), ledger.committed());
    const checked = try summary.checkSequence(driver, &plan);
    const view: data.View = .{ .slots = driver.runner.envelope.slots };
    const extraction = (try native.read(&view, native.parsed_schema, .parsed)).payload().parsed;
    const producers = extraction.entries[0].producers.?;
    try std.testing.expectEqual(@as(u32, 2), producers.content.?.attempt.value);
    try std.testing.expectEqual(@as(u32, 1), producers.classifications.?.attempt.value);
    try std.testing.expectEqual(@as(usize, if (exhausted) 1 else 2), driver.reconciliation_repair_calls);
    try std.testing.expectEqual(@as(usize, if (exhausted) 1 else 2), driver.reconciliation_merges);
    try std.testing.expectEqual(@as(usize, 0), driver.unchanged_reconciliation_merges);
    if (exhausted) {
        try std.testing.expectEqual(checked.calls, driver.calls);
        try std.testing.expect(result == .execution_rejected and result.execution_rejected == .retry_limit);
        try std.testing.expectEqual(checked.allowance - 1, result.execution_rejected.retry_limit.limit.value);
        try std.testing.expectEqual(@as(u64, checked.allowance), result.execution_rejected.retry_limit.completed_executions);
        const parsed = (try native.read(&view, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
        try std.testing.expectEqual(.dispositions, parsed.phase);
        try std.testing.expectEqual(@as(usize, 0), parsed.proposal.global.signals.len);
        try std.testing.expectEqual(@as(u32, 2), parsed.source.at(.dispositions, .record).?.attempt.value);
        try std.testing.expect(!view.contains(.accounted_reference_reconciliation));
        const request = try requests.readCurrent(&view, requests.prepared_schema);
        var arena: std.heap.ArenaAllocator = .init(driver.allocator);
        defer arena.deinit();
        const contents = request.prepared().?.content;
        const previous = try std.json.parseFromSlice(std.json.Value, arena.allocator(), contents[contents.len - 1].bytes(), .{});
        const body = try @import("spec_generation_responses.zig").build(arena.allocator(), view, .{ .global_sequence = .exhaust, .allowance = checked.allowance });
        try std.testing.expectEqualStrings(try corrupt(arena.allocator(), body, "signals", checked.allowance, checked.allowance, .exhaust), previous.value.object.get("rejected_response").?.string);
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
        // The source has no conflict group, so its conflicts answer is the empty collection the engine constructs
        // (ADR 0022): no request and no origin.
        try std.testing.expectEqual(@as(?@TypeOf(dispositions), null), source.at(.conflicts, .record));
        try std.testing.expect(dispositions.request.value != signals.request.value);
        try std.testing.expectEqual(@as(u32, 2), dispositions.attempt.value);
        try std.testing.expectEqual(checked.allowance, signals.attempt.value);
    }
}
