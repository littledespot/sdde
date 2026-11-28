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

const Form = struct { subject: c.Subject, options: []const c.Option, key: []const u8 };

/// A state whose Specify forms are each resolved with the option at its `key`, one response each.
fn choices(allocator: std.mem.Allocator, forms: []const Form) ![]const resolution.ConflictChoice {
    const records = try allocator.alloc(c.Record, forms.len);
    const responses = try allocator.alloc(c.Response, forms.len);
    for (forms, records, responses, 1..) |form, *record, *response, ordinal| {
        const id = try std.fmt.allocPrint(allocator, "S{d:0>2}", .{ordinal});
        record.* = fixture.record(id);
        record.subject = form.subject;
        record.answer_schema = .{ .select_one = form.options };
        record.status = .resolved_by_user;
        record.response_id = @intCast(ordinal);
        response.* = .{ .id = @intCast(ordinal), .clarification_id = id, .input_state_ordinal = 1, .input_state_revision = 1, .input_record_revision = 1, .submitted_form_bytes = "form", .answer = .{ .selected_option = form.key }, .actor_id = "fixture-user", .authentication_evidence_id = try std.fmt.allocPrint(allocator, "AE-{d}", .{ordinal}), .answered_at = "2026-09-05T00:00:00Z" };
    }
    var state = fixture.state(records);
    state.responses = responses;
    return resolution.choices(allocator, .{ .value = state });
}

/// The form of the conflict holding exactly `members`, answered by keeping `keep`.
fn formFor(allocator: std.mem.Allocator, reference: anytype, held: support.Records, members: []const r.ClaimId, keep: r.ClaimId) !Form {
    const conflict = for (held.conflicts) |candidate| {
        if (validation.sameMembers(candidate.value.claim_ids, members)) break candidate;
    } else return error.TestUnexpectedResult;
    const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, conflict);
    const subject = try clarifications.subjectFor(allocator, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = conflict.id }, .slot = .disposition });
    const at = for (conflict.value.claim_ids, 0..) |claim, index| {
        if (claim.ordinal == keep.ordinal) break index;
    } else return error.TestUnexpectedResult;
    return .{ .subject = subject, .options = options, .key = options[at].key };
}

/// The persisted snapshot of an answered reconciliation validates on readback.
fn expectSnapshot(allocator: std.mem.Allocator, reference: anytype, result: r.Records) !void {
    const account = try (@import("actions/reference/validate_reference_reconciliation_completeness.zig").Action{}).execute(allocator, result);
    const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(allocator);
    const contract = try @import("domain/reference_extraction_contract.zig").capture(allocator, contracts.authority, reference.inputs.chunks.partition);
    const snapshot = @import("domain/reference_snapshot.zig");
    try snapshot.validate(allocator, try snapshot.build(.{ .bytes = "references" }, reference.inputs, reference.extracted, account, reference.text.registry, contract), @import("test_fixtures/reference_text.zig").normalizer);
}

test "two answers that change one conflict, or one that would drop another answered conflict, apply nothing; disjoint answers both apply" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const texts: []const []const u8 = &.{ "Renew a loan not renewed before.\n", "Renew a loan once.\n", "Renew a loan twice.\n", "Renew a loan thrice.\n" };
    {
        // Two genuine conflicts share claim 1.
        const reference = try reconciled.prepare(allocator, texts[0..3]);
        defer reference.deinit();
        const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
        const accounted = (try f.finish(allocator, final, try grouped(allocator, final, &.{ &.{ 0, 1 }, &.{ 1, 2 } }), reference.context())).valid;
        const held = support.records(accounted);
        const ids = final.partition.group.claim_ids;
        const first: []const r.ClaimId = &.{ ids[0], ids[1] };
        const second: []const r.ClaimId = &.{ ids[1], ids[2] };
        // Alone, keeping 2 drops the first conflict, whose last claim stands alone.
        const deciding = try formFor(allocator, reference, held, second, ids[2]);
        const alone = try answered.apply(allocator, reference.inputs, accounted.records, try choices(allocator, &.{deciding}));
        try std.testing.expectEqual(@as(usize, 0), alone.conflicts.len);
        // The conflict the answer dropped is recorded by the subject its own form carries, with the answer that decided it. The
        // answered conflict is not: its form is the user's.
        try std.testing.expectEqual(@as(usize, 1), alone.answer_dropped.len);
        try std.testing.expect(c.sameSubject((try formFor(allocator, reference, held, first, ids[0])).subject, alone.answer_dropped[0].subject));
        try std.testing.expect(!c.sameSubject(deciding.subject, alone.answer_dropped[0].subject));
        try std.testing.expectEqual(@as(u64, 1), alone.answer_dropped[0].response_id);
        try std.testing.expectEqualStrings(deciding.key, alone.answer_dropped[0].key);
        // Only the claim the user chose is kept by the answer: the last claim of the conflict it dropped was not decided by one.
        try std.testing.expectEqual(@as(usize, 1), alone.answer_retained.len);
        try std.testing.expectEqual(ids[2].ordinal, alone.answer_retained[0].ordinal);
        for ([_][2]r.ClaimId{
            // The user kept 1 in the first form, which cannot apply while the second conflict holds it; the second answer
            // would drop the first conflict and retain claim 0 against that choice.
            .{ ids[1], ids[2] },
            // Both answers apply alone, each dropping the other's conflict.
            .{ ids[0], ids[2] },
        }) |keep| {
            const both = try choices(allocator, &.{ try formFor(allocator, reference, held, first, keep[0]), try formFor(allocator, reference, held, second, keep[1]) });
            const result = try answered.apply(allocator, reference.inputs, accounted.records, both);
            try std.testing.expectEqual(@as(usize, 2), result.conflicts.len);
            try std.testing.expectEqual(@as(usize, 0), result.answer_superseded.len);
            try std.testing.expectEqual(@as(usize, 0), result.answer_retained.len);
            try std.testing.expectEqual(@as(usize, 0), result.answer_dropped.len);
            for (support.records(.{ .records = result, .outcome = .blocked }).dispositions) |value| try std.testing.expectEqual(r.Disposition.conflicting, value.disposition);
        }
    }
    {
        // Two conflicts that share nothing: both answers apply, in conflict order.
        const reference = try reconciled.prepare(allocator, texts);
        defer reference.deinit();
        const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
        const accounted = (try f.finish(allocator, final, try grouped(allocator, final, &.{ &.{ 0, 1 }, &.{ 2, 3 } }), reference.context())).valid;
        const held = support.records(accounted);
        const ids = final.partition.group.claim_ids;
        const both = try choices(allocator, &.{ try formFor(allocator, reference, held, &.{ ids[0], ids[1] }, ids[0]), try formFor(allocator, reference, held, &.{ ids[2], ids[3] }, ids[3]) });
        const result = try answered.apply(allocator, reference.inputs, accounted.records, both);
        try std.testing.expectEqual(@as(usize, 0), result.conflicts.len);
        try std.testing.expectEqual(accounted.records.signals.len + 2, result.signals.len);
        try std.testing.expectEqual(ids[0].ordinal, result.signals[result.signals.len - 2].value.claim_ids[0].ordinal);
        try std.testing.expectEqual(ids[3].ordinal, result.signals[result.signals.len - 1].value.claim_ids[0].ordinal);
        try std.testing.expectEqual(@as(usize, 2), result.answer_superseded.len);
        try std.testing.expect(r.contains(r.ClaimId, result.answer_superseded, ids[1]) and r.contains(r.ClaimId, result.answer_superseded, ids[2]));
        try std.testing.expectEqual(@as(usize, 2), result.answer_retained.len);
        try std.testing.expect(r.contains(r.ClaimId, result.answer_retained, ids[0]) and r.contains(r.ClaimId, result.answer_retained, ids[3]));
        // Two conflicts that share nothing drop none: each answer removes only its own.
        try std.testing.expectEqual(@as(usize, 0), result.answer_dropped.len);
        try expectOrdinary(allocator, reference, result);
        try expectSnapshot(allocator, reference, result);
    }
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
    const normalizer = @import("test_fixtures/reference_text.zig").normalizer;
    try snapshot.validate(allocator, saved, normalizer);
    // The snapshot carries the claim the answer kept, and readback accepts only what an answered reconciliation leaves: a
    // retained model claim that stands alone in a signal. A repeated claim, a superseded one and an unknown one are not.
    try std.testing.expectEqual(@as(usize, 1), saved.answer_retained.len);
    try std.testing.expectEqual(chosen_claim.ordinal, saved.answer_retained[0].ordinal);
    for ([_][]const r.ClaimId{ &.{ chosen_claim, chosen_claim }, &.{other_claim}, &.{.{ .ordinal = 99 }} }) |forged| {
        var forged_snapshot = saved;
        forged_snapshot.answer_retained = forged;
        try std.testing.expectError(error.InvalidReferenceSnapshot, snapshot.validate(allocator, forged_snapshot, normalizer));
    }
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
        try conflicts.append(allocator, .{ .claim_ids = members, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The references disagree about the required behavior." } }} } });
        try held.append(allocator, .{ .claim_ids = members });
    }
    // A claim in several groups relates to the members of every one of them, in claim order.
    for (dispositions, 0..) |*disposition, position| {
        var related: std.ArrayList(r.ClaimId) = .empty;
        var grouped_claim = false;
        for (groups) |group| {
            if (std.mem.indexOfScalar(usize, group, position) == null) continue;
            grouped_claim = true;
            for (group) |other| if (other != position and !r.contains(r.ClaimId, related.items, ids[other])) try related.append(allocator, ids[other]);
        }
        std.mem.sort(r.ClaimId, related.items, {}, struct {
            fn less(_: void, left: r.ClaimId, right: r.ClaimId) bool {
                return left.ordinal < right.ordinal;
            }
        }.less);
        if (grouped_claim) disposition.disposition = .{ .conflicting = .{ .related_claim_ids = try related.toOwnedSlice(allocator) } };
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

const Overlap = struct { before: r.Records, after: r.Records, ids: []const r.ClaimId };

/// Answers the conflict holding exactly the claims at `members` (positions) in a reconciliation of the prepared reference
/// whose conflicts are `groups`, keeping the claim at position `keep`.
fn answerOverlap(allocator: std.mem.Allocator, reference: anytype, groups: []const []const usize, members: []const usize, keep: usize) !Overlap {
    const final = try f.summaries(allocator, try f.initialize(allocator, reference.inputs, reference.extracted, 2), reference.context());
    const accounted = (try f.finish(allocator, final, try grouped(allocator, final, groups), reference.context())).valid;
    const held = support.records(accounted);
    const ids = final.partition.group.claim_ids;
    const target = for (held.conflicts) |conflict| {
        if (conflict.value.claim_ids.len != members.len) continue;
        const same = for (members) |position| {
            if (!r.contains(r.ClaimId, conflict.value.claim_ids, ids[position])) break false;
        } else true;
        if (same) break conflict;
    } else return error.TestUnexpectedResult;
    const options = try resolution.conflictOptions(allocator, reference.inputs.corpus.sources, held, target);
    const subject = try clarifications.subjectFor(allocator, reference.inputs, held, .{ .kind = .reference_meaning, .unit = .{ .conflict = target.id }, .slot = .disposition });
    const at = for (target.value.claim_ids, 0..) |claim, index| {
        if (claim.ordinal == ids[keep].ordinal) break index;
    } else return error.TestUnexpectedResult;
    const after = try answered.apply(allocator, reference.inputs, accounted.records, try choice(allocator, subject, options, options[at].key));
    return .{ .before = accounted.records, .after = after, .ids = ids };
}

test "an answer drops another conflict its supersession leaves with one claim, whose claim then stands alone" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const texts: []const []const u8 = &.{ "Renew a loan not renewed before.\n", "Renew a loan once.\n", "Renew a loan twice.\n" };
    // The genuine conflict holds claims 1 and 2, the false one claims 0 and 2, sharing claim 2, in both declaration orders.
    for ([_][]const []const usize{ &.{ &.{ 1, 2 }, &.{ 0, 2 } }, &.{ &.{ 0, 2 }, &.{ 1, 2 } } }) |groups| {
        const reference = try reconciled.prepare(allocator, texts);
        defer reference.deinit();
        const result = try answerOverlap(allocator, reference, groups, &.{ 1, 2 }, 1);
        try std.testing.expectEqual(@as(usize, 2), result.before.conflicts.len);
        try std.testing.expectEqual(@as(usize, 0), result.after.conflicts.len);
        const after = support.records(.{ .records = result.after, .outcome = .complete });
        try std.testing.expectEqual(r.Disposition.retained, after.dispositions[result.ids[1].ordinal - 1].disposition);
        try std.testing.expectEqual(r.Disposition.superseded, after.dispositions[result.ids[2].ordinal - 1].disposition);
        try std.testing.expectEqual(result.ids[1].ordinal, after.dispositions[result.ids[2].ordinal - 1].related_claim_ids[0].ordinal);
        // The false conflict's other claim is retained, with a signal of its own beside the kept claim's.
        try std.testing.expectEqual(r.Disposition.retained, after.dispositions[result.ids[0].ordinal - 1].disposition);
        try std.testing.expectEqual(result.before.signals.len + 2, result.after.signals.len);
        try std.testing.expectEqual(result.ids[1].ordinal, result.after.signals[result.after.signals.len - 2].value.claim_ids[0].ordinal);
        try std.testing.expectEqual(result.ids[0].ordinal, result.after.signals[result.after.signals.len - 1].value.claim_ids[0].ordinal);
        try expectOrdinary(allocator, reference, result.after);
        // The answer records the claim it superseded, and authoring text loses that claim's line but keeps the chosen one's.
        try std.testing.expectEqual(@as(usize, 1), result.after.answer_superseded.len);
        try std.testing.expectEqual(result.ids[2].ordinal, result.after.answer_superseded[0].ordinal);
        const items = after.items;
        const shown = try model_evidence.answeredSources(allocator, reference.inputs, items, result.after.answer_superseded);
        for ([_]struct { claim: r.ClaimId, present: bool }{ .{ .claim = result.ids[2], .present = false }, .{ .claim = result.ids[1], .present = true }, .{ .claim = result.ids[0], .present = true } }) |expected| {
            const item = try r.item(items, expected.claim);
            const text = for (shown) |source| {
                if (source.id.ordinal == item.source_id.ordinal) break source.text;
            } else return error.TestUnexpectedResult;
            const original = reference.inputs.corpus.sources[item.source_id.ordinal - 1].bytes;
            for (item.citations) |citation| {
                const quoted = std.mem.trim(u8, original[citation.value.location.start.byte..citation.value.location.end.byte], "\n");
                try std.testing.expectEqual(expected.present, std.mem.indexOf(u8, text, quoted) != null);
            }
        }
        // Without an answered supersession the authoring text is the sources' bytes.
        for (try model_evidence.answeredSources(allocator, reference.inputs, items, &.{}), reference.inputs.corpus.sources) |source, original| try std.testing.expectEqualStrings(original.bytes, source.text);
        // The persisted snapshot of the answered reconciliation validates on readback.
        const account = try (@import("actions/reference/validate_reference_reconciliation_completeness.zig").Action{}).execute(allocator, result.after);
        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(allocator);
        const contract = try @import("domain/reference_extraction_contract.zig").capture(allocator, contracts.authority, reference.inputs.chunks.partition);
        const snapshot = @import("domain/reference_snapshot.zig");
        try snapshot.validate(allocator, try snapshot.build(.{ .bytes = "references" }, reference.inputs, reference.extracted, account, reference.text.registry, contract), @import("test_fixtures/reference_text.zig").normalizer);
    }
    // An answer of three claims that supersedes two drops the conflict one of them shares.
    {
        const reference = try reconciled.prepare(allocator, &.{ "Confirm immediately.\n", "Request approval first.\n", "Never confirm.\n", "Confirm later.\n" });
        defer reference.deinit();
        const result = try answerOverlap(allocator, reference, &.{ &.{ 0, 1, 2 }, &.{ 2, 3 } }, &.{ 0, 1, 2 }, 0);
        try std.testing.expectEqual(@as(usize, 0), result.after.conflicts.len);
        const after = support.records(.{ .records = result.after, .outcome = .complete });
        try std.testing.expectEqual(r.Disposition.retained, after.dispositions[result.ids[3].ordinal - 1].disposition);
        try expectOrdinary(allocator, reference, result.after);
        try expectSnapshot(allocator, reference, result.after);
    }
}

test "an answer under overlap applies nothing when what it keeps is shared or another conflict would be left changed" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const three: []const []const u8 = &.{ "Renew a loan not renewed before.\n", "Renew a loan once.\n", "Renew a loan twice.\n" };
    const four: []const []const u8 = &.{ "Renew a loan not renewed before.\n", "Renew a loan once.\n", "Renew a loan twice.\n", "Renew a loan thrice.\n" };
    for ([_]struct { texts: []const []const u8, groups: []const []const usize, members: []const usize = &.{ 1, 2 }, keep: usize }{
        // The kept claim is the shared one, which would have to stay conflicting.
        .{ .texts = three, .groups = &.{ &.{ 1, 2 }, &.{ 0, 2 } }, .keep = 2 },
        // The other conflict would be left with two claims under a summary written for three.
        .{ .texts = four, .groups = &.{ &.{ 1, 2 }, &.{ 0, 2, 3 } }, .keep = 1 },
        // The other conflict's last claim is in a third conflict too.
        .{ .texts = four, .groups = &.{ &.{ 1, 2 }, &.{ 0, 2 }, &.{ 0, 3 } }, .keep = 1 },
        // The other conflict is nested in the answered one and would be left with no claim.
        .{ .texts = three, .groups = &.{ &.{ 0, 1, 2 }, &.{ 0, 1 } }, .members = &.{ 0, 1, 2 }, .keep = 2 },
    }) |case| {
        const reference = try reconciled.prepare(allocator, case.texts);
        defer reference.deinit();
        const result = try answerOverlap(allocator, reference, case.groups, case.members, case.keep);
        try std.testing.expectEqual(result.before.conflicts.len, result.after.conflicts.len);
        for (support.records(.{ .records = result.after, .outcome = .blocked }).dispositions) |value| try std.testing.expectEqual(r.Disposition.conflicting, value.disposition);
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
