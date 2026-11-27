const std = @import("std");
const c = @import("domain/clarification_inputs.zig");
const r = @import("domain/reference_reconciliation.zig");
const support = @import("domain/reference_support.zig");
const resolution = @import("domain/clarification_resolution.zig");
const answered = @import("domain/answered_reconciliation.zig");
const clarifications = @import("domain/required_authority_clarifications.zig");
const validation = @import("domain/reference_reconciliation_validation.zig");
const dispositions_check = @import("domain/reference_disposition_validation.zig");
const model_evidence = @import("domain/model_evidence.zig");
const fixture = @import("test_fixtures/clarification_inputs.zig");
const f = @import("test_fixtures/reference_reconciliation.zig");
const reconciled = @import("reference_reconciliation_test.zig");

/// A state whose one Specify form for the conflict's subject is resolved with the option at `pick`.
fn choice(allocator: std.mem.Allocator, subject: c.Subject, options: []const c.Option, key: []const u8) ![]const resolution.ConflictChoice {
    var record = fixture.record("S01");
    record.subject = subject;
    record.answer_schema = .{ .select_one = options };
    record.status = .resolved_by_user;
    record.response_id = 1;
    const records = try allocator.dupe(c.Record, &.{record});
    var state = fixture.state(records);
    state.responses = try allocator.dupe(c.Response, &.{.{ .id = 1, .clarification_id = "S01", .input_state_ordinal = 1, .input_state_revision = 1, .input_record_revision = 1, .submitted_form_bytes = "form", .answer = .{ .selected_option = key }, .actor_id = "fixture-user", .authentication_evidence_id = "AE-1", .answered_at = "2026-09-05T00:00:00Z" }});
    return resolution.choices(allocator, .{ .value = state });
}

test "an answered conflict leaves an ordinary reconciliation that keeps the chosen claim and drops the others" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const reference = try reconciled.prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try reconciled.conflicting(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    const conflict = held.conflicts[0];
    const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, conflict);
    const subject = try clarifications.subjectFor(allocator, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = conflict.id }, .slot = .disposition });
    // The user chose the second claim.
    const chosen_claim = conflict.value.claim_ids[1];
    const other_claim = conflict.value.claim_ids[0];
    const result = try answered.apply(allocator, reference.inputs, accounted.records, try choice(allocator, subject, options, options[1].key));
    try std.testing.expectEqual(@as(usize, 0), result.conflicts.len);
    try std.testing.expectEqual(accounted.records.signals.len + 1, result.signals.len);
    const records = support.records(.{ .records = result, .outcome = .complete });
    for (records.dispositions) |value| {
        if (value.claim_id.ordinal == chosen_claim.ordinal) {
            try std.testing.expectEqual(r.Disposition.retained, value.disposition);
            try std.testing.expectEqual(@as(usize, 0), value.related_claim_ids.len);
        } else if (value.claim_id.ordinal == other_claim.ordinal) {
            try std.testing.expectEqual(r.Disposition.superseded, value.disposition);
            try std.testing.expectEqual(chosen_claim.ordinal, value.related_claim_ids[0].ordinal);
        }
    }
    const signal = result.signals[result.signals.len - 1];
    try std.testing.expectEqual(chosen_claim.ordinal, signal.value.claim_ids[0].ordinal);
    try std.testing.expectEqual(@as(u32, @intCast(result.signals.len)), signal.id.ordinal);
    // Every rule an ordinary reconciliation answers to holds: the completeness check, the dispositions' graph and the
    // signal and conflict coverage that the persisted snapshot is validated against.
    const account = try (@import("actions/reference/validate_reference_reconciliation_completeness.zig").Action{}).execute(allocator, result);
    try std.testing.expectEqual(.complete, account.outcome);
    try std.testing.expect(try dispositions_check.check(allocator, records.items, records.dispositions) == .valid);
    const proposals = try allocator.alloc(r.SignalProposal, records.signals.len);
    for (records.signals, proposals) |held_signal, *proposal| {
        proposal.* = .{ .claim_ids = held_signal.value.claim_ids, .content = model_evidence.content(held_signal.value.content) };
        try std.testing.expect(try validation.contentIssue(records.items, proposal.claim_ids, proposal.content) == null);
    }
    try std.testing.expect(try validation.signalCoverage(allocator, records.items, records.dispositions, proposals) == null);
    try std.testing.expect(try validation.conflictCoverage(allocator, records.items, records.dispositions, &.{}) == null);
    // The persisted snapshot of the answered reconciliation validates on readback: the one claim the ADR rests on.
    const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(allocator);
    const contract = try @import("domain/reference_extraction_contract.zig").capture(allocator, contracts.authority, reference.inputs.chunks.partition);
    const snapshot = @import("domain/reference_snapshot.zig");
    const saved = try snapshot.build(.{ .bytes = "references" }, reference.inputs, reference.extracted, account, reference.text.registry, contract);
    try snapshot.validate(allocator, saved, @import("test_fixtures/reference_text.zig").normalizer);
    // The conflict seed is gone: the authority ledger sees the sources as one claim.
    const inputs = try (@import("actions/authority/build_specification_authority_requirements.zig").Action{}).execute(allocator, reference.inputs.corpus.feature_id, account, .first);
    try std.testing.expectEqual(@as(usize, 0), inputs.forced_gaps.len);
}

test "an answer that cannot be applied leaves the conflict unresolved" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const reference = try reconciled.prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try reconciled.conflicting(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    const conflict = held.conflicts[0];
    const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, conflict);
    const subject = try clarifications.subjectFor(allocator, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = conflict.id }, .slot = .disposition });
    // No answer, an answer to another subject, and an option that no claim of the conflict offers (the sources changed
    // under a protected form) apply nothing and return the records as they were.
    const none = try answered.apply(allocator, reference.inputs, accounted.records, &.{});
    try std.testing.expectEqual(accounted.records.conflicts.len, none.conflicts.len);
    const elsewhere: c.Subject = .{ .requirement = subject.requirement, .unit = subject.unit, .slot = subject.slot, .sources = &.{.{ .path = "other.md", .lines = null }} };
    const other = try answered.apply(allocator, reference.inputs, accounted.records, try choice(allocator, elsewhere, options, options[0].key));
    try std.testing.expectEqual(accounted.records.conflicts.len, other.conflicts.len);
    const stale = try answered.apply(allocator, reference.inputs, accounted.records, try choice(allocator, subject, &.{ .{ .key = "gone.1", .label = "Gone." }, options[0] }, "gone.1"));
    try std.testing.expectEqual(accounted.records.conflicts.len, stale.conflicts.len);
    for (support.records(.{ .records = stale, .outcome = .blocked }).dispositions) |value| try std.testing.expectEqual(r.Disposition.conflicting, value.disposition);
    // A conflict whose claim is in another conflict cannot be answered, since that claim must stay conflicting.
    var entangled = accounted.records;
    const second = try allocator.dupe(r.Conflict, &.{ conflict, .{ .id = .{ .ordinal = 2 }, .value = conflict.value } });
    entangled.conflicts = second;
    const refused = try answered.apply(allocator, reference.inputs, entangled, try choice(allocator, subject, options, options[0].key));
    try std.testing.expectEqual(@as(usize, 2), refused.conflicts.len);
}

/// The conflicting fixture with the claims in `groups` (positions of the partition's claims) in one conflict each.
fn grouped(allocator: std.mem.Allocator, input: r.Input, groups: []const []const usize) !r.Proposal {
    var proposal = try f.global(allocator, input);
    const dispositions = try allocator.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    const ids = input.partition.group.claim_ids;
    var conflicts: std.ArrayList(r.ConflictProposal) = .empty;
    var held: std.ArrayList(@import("domain/reference_conflict_groups.zig").Group) = .empty;
    for (groups) |group| {
        const members = try allocator.alloc(r.ClaimId, group.len);
        for (group, members) |position, *member| member.* = ids[position];
        for (group) |position| {
            var related: std.ArrayList(r.ClaimId) = .empty;
            for (group) |other| if (other != position) try related.append(allocator, ids[other]);
            dispositions[position].disposition = .{ .conflicting = .{ .related_claim_ids = try related.toOwnedSlice(allocator) } };
        }
        try conflicts.append(allocator, .{ .claim_ids = members, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The references disagree about the required behavior." } }} } });
        try held.append(allocator, .{ .claim_ids = members });
    }
    proposal.claim_dispositions = dispositions;
    proposal.signals = &.{};
    proposal.conflicts = try conflicts.toOwnedSlice(allocator);
    proposal.conflict_groups = try held.toOwnedSlice(allocator);
    return proposal;
}

fn expectOrdinary(allocator: std.mem.Allocator, reference: anytype, result: r.Records) !void {
    const account = try (@import("actions/reference/validate_reference_reconciliation_completeness.zig").Action{}).execute(allocator, result);
    const records = support.records(account);
    try std.testing.expect(try dispositions_check.check(allocator, records.items, records.dispositions) == .valid);
    const proposals = try allocator.alloc(r.SignalProposal, records.signals.len);
    for (records.signals, proposals, 1..) |held_signal, *proposal, ordinal| {
        proposal.* = .{ .claim_ids = held_signal.value.claim_ids, .content = model_evidence.content(held_signal.value.content) };
        try std.testing.expectEqual(@as(u32, @intCast(ordinal)), held_signal.id.ordinal);
        try std.testing.expect(try validation.contentIssue(records.items, proposal.claim_ids, proposal.content) == null);
    }
    try std.testing.expect(try validation.signalCoverage(allocator, records.items, records.dispositions, proposals) == null);
    const conflicts = try allocator.alloc(r.ConflictProposal, records.conflicts.len);
    for (records.conflicts, conflicts, 1..) |conflict, *proposal, ordinal| {
        proposal.* = .{ .claim_ids = conflict.value.claim_ids, .kind = conflict.value.kind, .summary = conflict.value.summary.value };
        try std.testing.expectEqual(@as(u32, @intCast(ordinal)), conflict.id.ordinal);
    }
    try std.testing.expect(try validation.conflictCoverage(allocator, records.items, records.dispositions, conflicts) == null);
    _ = reference;
}

test "answers apply by claim whatever the order of the proposal, to three claims, and with several conflicts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    // One conflict of three claims, answered by its second.
    {
        const reference = try reconciled.prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n", "Never confirm.\n" });
        defer reference.deinit();
        const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
        const accounted = (try f.finish(allocator, final, try grouped(allocator, final, &.{&.{ 0, 1, 2 }}), reference.context())).valid;
        const held = support.records(accounted);
        const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, held.conflicts[0]);
        try std.testing.expectEqual(@as(usize, 3), options.len);
        const subject = try clarifications.subjectFor(allocator, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = held.conflicts[0].id }, .slot = .disposition });
        // The proposal lists the dispositions in the reverse of the claims' order, as a model may.
        const global = accounted.records.assignments.global();
        var proposal = global.proposal;
        const reversed = try allocator.dupe(r.ClaimDispositionProposal, global.proposal.claim_dispositions);
        std.mem.reverse(r.ClaimDispositionProposal, reversed);
        proposal.claim_dispositions = reversed;
        var records = accounted.records;
        records.assignments = records.assignments.rebuilt(global.dispositions, proposal, records.assignments.checked.prior.signals, records.assignments.signal_ids, records.assignments.checked.conflicts, records.assignments.conflict_ids);
        const result = try answered.apply(allocator, reference.inputs, records, try choice(allocator, subject, options, options[1].key));
        try std.testing.expectEqual(@as(usize, 0), result.conflicts.len);
        const kept = support.records(.{ .records = result, .outcome = .complete });
        for (kept.dispositions) |value| {
            const expected: r.Disposition = if (value.claim_id.ordinal == held.conflicts[0].value.claim_ids[1].ordinal) .retained else .superseded;
            try std.testing.expectEqual(expected, value.disposition);
        }
        try expectOrdinary(allocator, reference, result);
    }
    // Two conflicts, one answered: the other stays, is renumbered, and its claims stay conflicting.
    {
        const reference = try reconciled.prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n", "Display red.\n", "Display blue.\n" });
        defer reference.deinit();
        const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
        const accounted = (try f.finish(allocator, final, try grouped(allocator, final, &.{ &.{ 0, 1 }, &.{ 2, 3 } }), reference.context())).valid;
        const held = support.records(accounted);
        try std.testing.expectEqual(@as(usize, 2), held.conflicts.len);
        const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, held.conflicts[0]);
        const subject = try clarifications.subjectFor(allocator, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = held.conflicts[0].id }, .slot = .disposition });
        const result = try answered.apply(allocator, reference.inputs, accounted.records, try choice(allocator, subject, options, options[0].key));
        try std.testing.expectEqual(@as(usize, 1), result.conflicts.len);
        try std.testing.expectEqual(@as(u32, 1), result.conflicts[0].id.ordinal);
        try std.testing.expectEqual(held.conflicts[1].value.claim_ids[0].ordinal, result.conflicts[0].value.claim_ids[0].ordinal);
        const after = support.records(.{ .records = result, .outcome = .blocked });
        for (held.conflicts[1].value.claim_ids) |claim| try std.testing.expectEqual(r.Disposition.conflicting, after.dispositions[claim.ordinal - 1].disposition);
        try expectOrdinary(allocator, reference, result);
    }
}

test "an answer whose label the claim no longer shows applies nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const reference = try reconciled.prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try reconciled.conflicting(allocator, final), reference.context())).valid;
    const held = support.records(accounted);
    const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, held.conflicts[0]);
    const subject = try clarifications.subjectFor(allocator, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = held.conflicts[0].id }, .slot = .disposition });
    // The form showed another quotation under the same lines: the text was edited in place after the answer.
    const shown: []const c.Option = &.{ .{ .key = options[0].key, .label = "Confirm later." }, options[1] };
    const result = try answered.apply(allocator, reference.inputs, accounted.records, try choice(allocator, subject, shown, options[0].key));
    try std.testing.expectEqual(accounted.records.conflicts.len, result.conflicts.len);
}

test "applying an answer releases every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(sweep, .{});
}
fn sweep(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const scratch = arena.allocator();
    const reference = try reconciled.prepare(scratch, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer reference.deinit();
    const final = try f.summaries(scratch, try f.initialize(scratch, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(scratch, final, try reconciled.conflicting(scratch, final), reference.context())).valid;
    const held = support.records(accounted);
    const options = try resolution.conflictOptions(scratch, reference.inputs.corpus.sources, held, held.conflicts[0]);
    const subject = try clarifications.subjectFor(scratch, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = held.conflicts[0].id }, .slot = .disposition });
    const chosen = try choice(scratch, subject, options, options[0].key);
    var applied: std.heap.ArenaAllocator = .init(allocator);
    defer applied.deinit();
    _ = try answered.apply(applied.allocator(), reference.inputs, accounted.records, chosen);
}
