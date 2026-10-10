const std = @import("std");

test "collection producers survive field repairs and native insertions without a synthetic root origin" {
    const d = @import("domain/reference_reconciliation_diagnostic.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const dispositions: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 2 } };
    const signals: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 3 } };
    const conflicts: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    const repair: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 1 } };
    const source: d.Source = .{ .fields = &.{
        .{ .unit = .dispositions, .field = .record, .origin = dispositions },
        .{ .unit = .signals, .field = .record, .origin = signals },
        .{ .unit = .conflicts, .field = .record, .origin = conflicts },
        .{ .unit = .{ .signal = 0 }, .field = .selections, .origin = repair },
        .{ .unit = .{ .signal = 2 }, .field = .record, .origin = null },
    } };
    try std.testing.expect(source.origin == null);
    try std.testing.expectEqualDeep(dispositions, source.at(.{ .disposition = 0 }, .relationship).?);
    try std.testing.expectEqualDeep(signals, source.at(.{ .signal = 0 }, .content).?);
    try std.testing.expectEqualDeep(repair, source.at(.{ .signal = 0 }, .selections).?);
    try std.testing.expectEqualDeep(signals, source.at(.{ .signal = 1 }, .record).?);
    try std.testing.expectEqualDeep(conflicts, source.at(.{ .conflict = 0 }, .content).?);
    try std.testing.expect(source.at(.{ .signal = 2 }, .content) == null);
    try std.testing.expectEqualDeep(signals, source.at(.signals, .record).?);
}
const f = @import("test_fixtures/reference_reconciliation.zig");
const r = f.r;

/// Grouping and repair cases construct reference-only proposals; role routing
/// is exercised separately against the same native validator.
fn globalWithoutSpecRoles(allocator: std.mem.Allocator, input: r.Input) !r.Proposal {
    var proposal = try f.global(allocator, input);
    proposal.role_decisions = try f.roleDecisions(allocator, &.{});
    return proposal;
}
/// A fresh mocked role assessment for reference-only repair tests. This is
/// explicit candidate data, not a default in the production repair/validator.
fn mockUnsupportedRoles(allocator: std.mem.Allocator, proposal: r.Proposal) !r.Proposal {
    var result = proposal;
    result.role_decisions = try f.roleDecisions(allocator, &.{});
    return result;
}

const text = @import("test_fixtures/reference_text.zig");
const tokens = @import("test_fixtures/reference_tokens.zig");
const extraction = @import("reference_extraction_test.zig");

test "semantic summary authoring leaves exact tokens native and rejects model-authored token membership" {
    const projection = @import("domain/reference_reconciliation_projection.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "Display `Hello, World!` and the UTC time.\n", "Renew the loan and display `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2));
        const semantic = try projection.semanticClaimIds(a, input.items);
        var statements: std.ArrayList(projection.SemanticStatement) = .empty;
        for (semantic) |id| try statements.append(a, .{ .claim_ids = try a.dupe(r.ClaimId, &.{id}), .content = .{ .model = f.content((try r.item(input.progress.plan.layout.items, id)).claim).model } });
        const parsed = try f.parse.execute(a, .{ .input = input, .bytes = try codec.encode(projection.SemanticSummary, a, .{ .statements = statements.items }), .source = .{ .origin = origin } });
        try std.testing.expectEqual(input.items.len, (try f.validate_summary.execute(a, parsed, fixture.context())).valid.statements.len);
        const native = parsed.proposal.summary.statements[semantic.len];
        try std.testing.expectEqual(.preserved_token, std.meta.activeTag(native.content));
        try std.testing.expect(parsed.source.at(.{ .statement = semantic.len }, .record) == null);
        const token = try r.item(input.progress.plan.layout.items, native.claim_ids[0]);
        try statements.append(a, .{ .claim_ids = native.claim_ids, .content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = token.claim.content.preserved_token.value.raw_value.bytes } }} } } } });
        const invalid = try f.parse.execute(a, .{ .input = input, .bytes = try codec.encode(projection.SemanticSummary, a, .{ .statements = statements.items }), .source = .{ .origin = origin } });
        const rejected = (try f.validate_summary.execute(a, invalid, fixture.context())).invalid;
        try std.testing.expectEqualDeep(r.diagnostic.Unit{ .statement = semantic.len }, rejected.unit);
        try std.testing.expectEqual(.content, rejected.issue.rule);
        try std.testing.expectEqual(.matching_claim_content, rejected.issue.expected.constraint);
        try std.testing.expectEqualDeep(origin, rejected.origin.?);
    }
}

test "authoring roles are assigned after grouping and reject duplicate or foreign groups" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `Hello, World!`.\n"});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const proposal = try f.global(a, input);
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = proposal } };
    const dispositions = (try f.validate_dispositions.execute(a, parsed)).valid;
    const groups = (try f.validate_signals.execute(a, dispositions, fixture.context())).valid;
    for (groups.signals) |signal| try std.testing.expectEqual(@as(usize, 0), signal.generation_roles.len);
    const assigned = (try f.validate_roles.execute(a, groups)).valid;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, checkRoleAllocations, .{groups});
    var found_records = false;
    for (assigned.signals) |signal| {
        if (signal.content == .preserved_token) try std.testing.expectEqual(@as(usize, 0), signal.generation_roles.len);
        if (std.mem.indexOfScalar(r.GenerationRole, signal.generation_roles, .records) != null) found_records = true;
    }
    try std.testing.expect(found_records);

    var duplicate_roles = groups;
    var decisions = proposal.role_decisions.?;
    const first = decisions.records.supported.signal_ids[0];
    decisions.records = .{ .supported = .{ .signal_ids = &.{ first, first } } };
    duplicate_roles.prior.proposal.role_decisions = decisions;
    try std.testing.expectEqual(.role_assignment, (try f.validate_roles.execute(a, duplicate_roles)).invalid.issue.rule);

    var changed = groups;
    decisions = proposal.role_decisions.?;
    decisions.records = .{ .supported = .{ .signal_ids = &.{.{ .ordinal = 999 }} } };
    changed.prior.proposal.role_decisions = decisions;
    try std.testing.expectEqual(.role_assignment, (try f.validate_roles.execute(a, changed)).invalid.issue.rule);
}
fn checkRoleAllocations(allocator: std.mem.Allocator, groups: r.CheckedSignals) !void {
    const result = try f.validate_roles.execute(allocator, groups);
    try std.testing.expect(result == .valid);
    for (result.valid.signals) |signal| allocator.free(signal.generation_roles);
    allocator.free(result.valid.signals);
}
test "role assignment permits shared roles and rejects unknown native group selections" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Renew the library loan.\n", "Show its new due date.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try f.global(a, input);
    var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = proposal } };
    const separate = (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).valid;
    const assigned = (try f.validate_roles.execute(a, separate)).valid;
    var record_groups: usize = 0;
    for (assigned.signals) |signal| if (std.mem.indexOfScalar(r.GenerationRole, signal.generation_roles, .records) != null) {
        record_groups += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), record_groups);
    const ids = [_]r.ClaimId{ proposal.signals[0].claim_ids[0], proposal.signals[1].claim_ids[0] };
    proposal.signals = &.{.{ .claim_ids = &ids, .content = proposal.signals[0].content }};
    proposal.role_decisions = try f.roleDecisions(a, &.{.{ .signal_id = .{ .ordinal = 1 }, .generation_roles = &.{ .title, .records } }});
    parsed.proposal.global = proposal;
    const grouped = (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).valid;
    try std.testing.expectEqual(@as(usize, 2), (try f.validate_roles.execute(a, grouped)).valid.signals[0].generation_roles.len);
    for ([_]u32{ 0, 2, 99 }) |bad| {
        var changed = grouped;
        changed.prior.proposal.role_decisions = try f.roleDecisions(a, &.{.{ .signal_id = .{ .ordinal = bad }, .generation_roles = &.{.records} }});
        try std.testing.expectEqual(.role_assignment, (try f.validate_roles.execute(a, changed)).invalid.issue.rule);
    }
}
const Fixture = struct {
    inputs: r.evidence.Inputs,
    extracted: r.extraction.Accounted,
    text: @import("test_fixtures/reference_text.zig").Prepared,
    pub fn deinit(self: Fixture) void {
        self.text.deinit();
    }
    pub fn context(self: Fixture) f.Context {
        return .{ .inputs = self.inputs, .registry = self.text.registry, .current = text.safety.value(self.text.owner) };
    }
};

test "summary repair changes only a rejected field then inserts missing membership before normalization" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const initial: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const correction: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2));
        const good = try f.summary(a, input);
        try std.testing.expect(good.statements.len >= 2);
        const statements = try a.dupe(r.StatementProposal, good.statements);
        statements[0].claim_ids = &.{.{ .ordinal = 999 }};
        statements[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } };
        const parsed: r.Parsed = .{ .source = .{ .origin = initial }, .input = input, .proposal = .{ .summary = .{ .statements = statements } } };
        const rejected = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
        const authorization = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
        const packet = try repair.packet(std.testing.allocator, parsed, fixture.context(), authorization);
        defer @import("domain/model_input_packet.zig").release(packet);
        const replacement: repair.Replacement = .{ .selection = .{ .claim_ids = good.statements[0].claim_ids } };
        const bytes = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
        const selected = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, bytes), correction);
        try std.testing.expectEqualDeep(good.statements[1], selected.proposal.summary.statements[1]);
        const text_rejection = (try f.validate_summary.execute(a, selected, fixture.context())).invalid;
        try std.testing.expectEqual(.typed_text, text_rejection.issue.rule);
        try std.testing.expectEqualDeep(initial, text_rejection.origin.?);
        const text_auth = (try repair.authorize(a, selected, fixture.context(), text_rejection)).model;
        const accepted = try repair.merge(a, selected, fixture.context(), text_auth, .{ .content = good.statements[0].content }, correction);
        _ = (try f.validate_summary.execute(a, accepted, fixture.context())).valid;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, accepted, fixture.context(), text_auth, .{ .content = good.statements[0].content }, correction));
        var changed = parsed;
        changed.proposal.summary.statements = good.statements;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, changed, fixture.context(), rejected));

        const missing: r.Parsed = .{ .input = input, .proposal = .{ .summary = .{ .statements = good.statements[1..] } } };
        const missing_rejection = (try f.validate_summary.execute(a, missing, fixture.context())).invalid;
        const insert = (try repair.authorize(a, missing, fixture.context(), missing_rejection)).model;
        try std.testing.expect(insert.operation == .insert);
        const filled = try repair.merge(a, missing, fixture.context(), insert, .{ .content = good.statements[0].content }, correction);
        _ = (try f.validate_summary.execute(a, filled, fixture.context())).valid;
        try std.testing.expectEqualDeep(missing.proposal.summary.statements[0], filled.proposal.summary.statements[0]);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, filled, fixture.context(), insert, .{ .content = good.statements[0].content }, correction));
        const duplicates = try a.alloc(r.StatementProposal, good.statements.len + 1);
        @memcpy(duplicates[0..good.statements.len], good.statements);
        duplicates[good.statements.len] = good.statements[0];
        const duplicate: r.Parsed = .{ .input = input, .proposal = .{ .summary = .{ .statements = duplicates } } };
        const deduplicated = (try f.validate_summary.execute(a, duplicate, fixture.context())).valid;
        try std.testing.expectEqual(good.statements.len, deduplicated.statements.len);
        try std.testing.expectEqualDeep(good.statements[0].claim_ids, deduplicated.statements[0].claim_ids);
        try std.testing.expectEqualDeep(good.statements[1].claim_ids, deduplicated.statements[1].claim_ids);
        try std.testing.expectEqual(duplicates.len, duplicate.proposal.summary.statements.len);
        try std.testing.expectEqual(@as(u64, 1), duplicate.source.revision);
    }
}

test "disposition insertion ignores response metadata and preserves dependent validation" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const correction: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } };
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        const good = try globalWithoutSpecRoles(a, input);
        var missing: r.Parsed = .{ .source = .{ .origin = correction }, .input = input, .proposal = .{ .global = good } };
        missing.proposal.global.claim_dispositions = good.claim_dispositions[0..1];
        const signals = try a.dupe(r.SignalProposal, good.signals);
        signals[0].claim_ids = &.{ input.items[0].claim.id, input.items[1].claim.id };
        missing.proposal.global.signals = signals[0..1];
        const rejection = (try f.validate_dispositions.execute(a, missing)).invalid;
        const authorization = (try repair.authorize(a, missing, fixture.context(), rejection)).model;
        const packet = try repair.packet(a, missing, fixture.context(), authorization);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const task = body.value.object.get("repair").?.object;
        const target = task.get("target").?.object;
        try std.testing.expectEqual(@as(usize, 2), target.count());
        try std.testing.expectEqualStrings("insert_disposition", target.get("unit").?.string);
        try std.testing.expectEqual(@as(i64, 2), target.get("claim").?.integer);
        try std.testing.expectEqualStrings("repair_disposition", packet.resultDefinition().?.bytes);
        try std.testing.expect(task.get("rule").?.object.get("disposition_choices").?.object.get("retained").?.bool);
        try std.testing.expectEqual(@as(usize, 2), task.get("rule").?.object.count());
        const constraints = body.value.object.get("input").?.object.get("constraints").?.array.items;
        try std.testing.expectEqual(@as(usize, 0), constraints.len);
        for ([_][]const u8{
            "{\"index\":1,\"unit\":\"signals\"}",
            "{\"kind\":\"count\",\"count\":2}",
            "{\"claim_dispositions\":[{\"kind\":\"retained\"}]}",
        }) |echo| try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, echo));

        // R26: both changed responses remain invalid. The canonical checker,
        // origins and revisions agree even when the model ignores the choices.
        var rejected_candidate = missing;
        var selected = authorization;
        for ([_][]const u8{
            "{\"kind\":\"duplicate\",\"target_claim_id\":1}",
            "{\"kind\":\"superseded\",\"related_claim_ids\":[1]}",
        }, 0..) |bytes, i| {
            const origin: Origin = .{ .request = .{ .value = @intCast(5 + i) }, .attempt = .{ .value = 1 } };
            const request = try repair.packet(a, rejected_candidate, fixture.context(), selected);
            defer packets.release(request);
            rejected_candidate = try repair.merge(a, rejected_candidate, fixture.context(), selected, try repair.parse(a, selected, request, bytes), origin);
            const invalid = (try f.validate_dispositions.execute(a, rejected_candidate)).invalid;
            try std.testing.expectEqual(.same_content_kind, invalid.issue.expected.constraint);
            try std.testing.expectEqual(@as(u64, 2 + i), invalid.revision);
            try std.testing.expectEqualDeep(origin, invalid.origin.?);
            try std.testing.expect(rejected_candidate.source.last_repair.?.changed);
            try std.testing.expectEqual(@as(usize, 0), rejected_candidate.proposal.global.signals.len);
            try std.testing.expectEqual(.dispositions, rejected_candidate.phase);
            try std.testing.expectEqualDeep(good.claim_dispositions[0], rejected_candidate.proposal.global.claim_dispositions[0]);
            selected = (try repair.authorize(a, rejected_candidate, fixture.context(), invalid)).model;
            try std.testing.expect(selected.rule.disposition_choices.?.retainedOnly());
        }
        const origin: Origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 1 } };
        var filled = try repair.merge(a, missing, fixture.context(), authorization, try repair.parse(a, authorization, packet, "{\"kind\":\"retained\"}"), origin);
        try std.testing.expectEqual(@as(usize, 0), filled.proposal.global.signals.len);
        filled.proposal.global.signals = missing.proposal.global.signals;
        filled.source.signals = .{};
        filled.phase = .signals;
        try std.testing.expectEqualDeep(missing.proposal.global.claim_dispositions, filled.proposal.global.claim_dispositions[0..1]);
        const dispositions = (try f.validate_dispositions.execute(a, filled)).valid;
        const mixed = (try f.validate_signals.execute(a, dispositions, fixture.context())).invalid;
        try std.testing.expectEqual(.content, mixed.issue.rule);
        try std.testing.expectEqualDeep(correction, mixed.origin.?);
        const selection = (try repair.authorize(a, filled, fixture.context(), mixed)).model;
        const projected = try repair.merge(a, filled, fixture.context(), selection, .{ .selection = .{ .claim_ids = selection.rule.rejection.relations.selection } }, .{ .request = .{ .value = 6 }, .attempt = .{ .value = 1 } });
        try std.testing.expectEqualDeep(filled.proposal.global.claim_dispositions, projected.proposal.global.claim_dispositions);
        try std.testing.expectEqualDeep(filled.proposal.global.signals[0].content, projected.proposal.global.signals[0].content);
        const coverage = (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, projected)).valid, fixture.context())).invalid;
        try std.testing.expectEqual(.signal_coverage, coverage.issue.rule);
        const token = (try repair.authorize(a, projected, fixture.context(), coverage)).automatic;
        const complete = try repair.merge(a, projected, fixture.context(), token.authorization, token.replacement, null);
        try std.testing.expectEqualDeep(projected.proposal.global.signals, complete.proposal.global.signals[0..1]);
        try std.testing.expectEqualDeep(good.signals[1], complete.proposal.global.signals[1]);
        try std.testing.expectEqual(@as(u64, 4), complete.source.revision);
        _ = (try f.finish(a, input, try mockUnsupportedRoles(a, complete.proposal.global), fixture.context())).valid;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, complete, fixture.context(), authorization, .{ .disposition = .{ .retained = .{} } }, origin));
    }
}

test "disposition choices reuse canonical graph validation with fixed siblings" {
    const owner = @import("domain/reference_disposition_validation.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm the booking.\n", "Issue the receipt.\n", "Notify the traveller.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const items = input.progress.plan.layout.items;
    const good = try globalWithoutSpecRoles(a, input);
    const values = try a.dupe(r.ClaimDispositionProposal, good.claim_dispositions);
    const first = values[0].claim_id;
    const second = values[1].claim_id;
    const third = values[2].claim_id;
    const choices = (try owner.repairChoices(a, items, values, 0, first)).?;
    try std.testing.expect(choices.retained);
    try std.testing.expectEqualDeep(&[_]r.ClaimId{ second, third }, choices.duplicate_targets);
    try std.testing.expectEqualDeep(choices.duplicate_targets, choices.superseded_targets);
    try std.testing.expectEqual(@as(usize, 0), choices.conflicting_with_all.len);
    var distinct = items;
    const distinct_entries = try a.dupe(r.Item, items.entries);
    distinct.entries = distinct_entries;
    distinct_entries[1].claim.content = .{ .model = .{ .technical = .{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "A technical constraint." } }} } } } };
    const typed = (try owner.repairChoices(a, distinct, values, 0, first)).?;
    try std.testing.expectEqualDeep(&[_]r.ClaimId{third}, typed.duplicate_targets);
    try std.testing.expectEqualDeep(typed.duplicate_targets, typed.superseded_targets);
    values[1].disposition = .{ .duplicate = .{ .target_claim_id = first } };
    const acyclic = (try owner.repairChoices(a, items, values, 0, first)).?;
    try std.testing.expectEqualDeep(&[_]r.ClaimId{third}, acyclic.duplicate_targets);
    try std.testing.expectEqualDeep(acyclic.duplicate_targets, acyclic.superseded_targets);
    values[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{ first, third } } };
    values[2].disposition = .{ .conflicting = .{ .related_claim_ids = &.{ first, second } } };
    const reciprocal = (try owner.repairChoices(a, items, values, 0, first)).?;
    try std.testing.expect(!reciprocal.retained);
    try std.testing.expectEqual(@as(usize, 0), reciprocal.duplicate_targets.len + reciprocal.superseded_targets.len);
    try std.testing.expectEqualDeep(&[_]r.ClaimId{ second, third }, reciprocal.conflicting_with_all);
    values[1].disposition = .{ .duplicate = .{ .target_claim_id = .{ .ordinal = 999 } } };
    try std.testing.expect((try owner.repairChoices(a, items, values, 0, first)) == null);
    try std.testing.expect((try owner.repairChoices(a, items, good.claim_dispositions[0..1], 1, second)) == null);
    // A complete, unrelated conflict forbids either peer as a directed target.
    values[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{third} } };
    values[2].disposition = .{ .conflicting = .{ .related_claim_ids = &.{second} } };
    try std.testing.expect((try owner.repairChoices(a, items, values, 0, first)).?.retainedOnly());
}

test "disposition choices distinguish exact values without selecting token semantics" {
    const owner = @import("domain/reference_disposition_validation.zig");
    for ([_][]const u8{ "Display `Approved!`.\n", "Display `Declined!`.\n" }, 0..) |other, scenario| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{ "Show `Approved!`.\n", other });
        defer fixture.deinit();
        const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        const good = try globalWithoutSpecRoles(a, input);
        var token_ids: std.ArrayList(r.ClaimId) = .empty;
        var index: usize = 0;
        for (input.items, 0..) |item, i| if (item.claim.content == .preserved_token) {
            if (token_ids.items.len == 0) index = i;
            try token_ids.append(a, item.claim.id);
        };
        const choices = (try owner.repairChoices(a, input.progress.plan.layout.items, good.claim_dispositions, index, token_ids.items[0])).?;
        try std.testing.expect(choices.retained);
        try std.testing.expectEqual(@as(usize, if (scenario == 0) 1 else 0), choices.duplicate_targets.len);
        try std.testing.expectEqualDeep(token_ids.items[1..], choices.superseded_targets);
        try std.testing.expectEqual(@as(usize, 0), choices.conflicting_with_all.len);
    }
}

test "canonical dispositions establish cardinalities before relationship traversal" {
    const owner = @import("domain/reference_disposition_validation.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Issue a receipt.\n", "Confirm a library loan.\n", "Confirm a booking.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const good = try globalWithoutSpecRoles(a, input);
    const records = try a.alloc(r.ClaimDisposition, good.claim_dispositions.len);
    for (good.claim_dispositions, records) |proposal, *record| record.* = try proposal.canonical(a);
    _ = (try owner.check(a, input.progress.plan.layout.items, records)).valid;
    for (0..3) |fault| {
        const broken = try a.dupe(r.ClaimDisposition, records);
        broken[0].disposition = if (fault == 0) .retained else .duplicate;
        broken[0].related_claim_ids = switch (fault) {
            0 => &.{records[1].claim_id},
            1 => &.{},
            else => &.{ records[1].claim_id, records[2].claim_id },
        };
        try std.testing.expectEqual(.cardinality, (try owner.check(a, input.progress.plan.layout.items, broken)).invalid.issue.rule);
    }
}

test "global repair retains graph siblings and all dependent signal and conflict checks" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Display `Hello, World!`.\n", "Confirm a library loan.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const good = try globalWithoutSpecRoles(a, input);
    const choices = try a.dupe(r.ClaimDispositionProposal, good.claim_dispositions);
    choices[0].disposition = .{ .duplicate = .{ .target_claim_id = choices[0].claim_id } };
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = .{ .claim_dispositions = choices, .signals = good.signals, .conflicts = good.conflicts } } };
    const rejection = (try f.validate_dispositions.execute(a, parsed)).invalid;
    const authorization = (try repair.authorize(a, parsed, fixture.context(), rejection)).model;
    const merged = try repair.merge(a, parsed, fixture.context(), authorization, .{ .disposition = .{ .retained = .{} } }, null);
    try std.testing.expectEqualDeep(good.claim_dispositions[1..], merged.proposal.global.claim_dispositions[1..]);
    try std.testing.expectEqualDeep(good.signals[1..], merged.proposal.global.signals);
    try std.testing.expectEqual(.dispositions, merged.phase);
    try std.testing.expect((try f.validate_dispositions.execute(a, merged)) == .valid);
    const invalid = try repair.merge(a, parsed, fixture.context(), authorization, .{ .disposition = choices[0].disposition }, null);
    try std.testing.expect((try f.validate_dispositions.execute(a, invalid)) == .invalid);

    var missing = merged;
    missing.phase = .signals;
    missing.proposal.global.signals = good.signals[1..];
    const dispositions = (try f.validate_dispositions.execute(a, missing)).valid;
    const coverage = (try f.validate_signals.execute(a, dispositions, fixture.context())).invalid;
    const insert = (try repair.authorize(a, missing, fixture.context(), coverage)).model;
    const insert_packet = try repair.packet(a, missing, fixture.context(), insert);
    defer @import("domain/model_input_packet.zig").release(insert_packet);
    try std.testing.expectEqualStrings("business_text", insert_packet.resultDefinition().?.bytes);
    const insert_body = (try std.json.parseFromSlice(std.json.Value, a, insert_packet.body(), .{})).value.object;
    const insert_task = insert_body.get("repair").?.object;
    const insert_rule = insert_task.get("rule").?.object;
    try std.testing.expect(!insert_rule.contains("requirement"));
    try std.testing.expectEqualStrings(r.diagnostic.Constraint.retained_claim_covered.description(), insert_rule.get("failed_requirement").?.string);
    try std.testing.expectEqualStrings(insert.rule.requirement, insert_rule.get("failed_requirement").?.string);
    const insert_target = insert_task.get("target").?.object;
    try std.testing.expectEqualStrings("insert_signal", insert_target.get("unit").?.string);
    try std.testing.expectEqual(@as(i64, insert.target.insert_signal.claim.ordinal), insert_target.get("claim").?.integer);
    const insert_constraints = insert_body.get("input").?.object.get("constraints").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), insert_constraints.len);
    try std.testing.expectEqualStrings("matching_claim_content", insert_constraints[0].object.get("constraint").?.string);
    const filled = try repair.merge(a, missing, fixture.context(), insert, .{ .content = good.signals[0].content }, null);
    _ = (try f.finish(a, input, try mockUnsupportedRoles(a, filled.proposal.global), fixture.context())).valid;
    try std.testing.expectEqualDeep(good.signals[1..], filled.proposal.global.signals[0 .. filled.proposal.global.signals.len - 1]);

    const duplicate_choices = try a.alloc(r.ClaimDispositionProposal, good.claim_dispositions.len + 1);
    @memcpy(duplicate_choices[0..good.claim_dispositions.len], good.claim_dispositions);
    duplicate_choices[good.claim_dispositions.len] = good.claim_dispositions[0];
    var duplicate = merged;
    duplicate.proposal.global.signals = good.signals;
    duplicate.phase = .complete;
    duplicate.proposal.global.claim_dispositions = duplicate_choices;
    const duplicate_rejection = (try f.validate_dispositions.execute(a, duplicate)).invalid;
    const remove = (try repair.authorize(a, duplicate, fixture.context(), duplicate_rejection)).automatic;
    const deduplicated = try repair.merge(a, duplicate, fixture.context(), remove.authorization, null, null);
    _ = (try f.finish(a, input, try mockUnsupportedRoles(a, deduplicated.proposal.global), fixture.context())).valid;
    duplicate_choices[good.claim_dispositions.len].disposition = .{ .superseded = .{ .related_claim_ids = &.{good.claim_dispositions[1].claim_id} } };
    const competing = (try f.validate_dispositions.execute(a, duplicate)).invalid;
    try std.testing.expectEqual(.competing_entries, (try repair.authorize(a, duplicate, fixture.context(), competing)).blocked);
}

test "summary signal and conflict repair packets retain precise shared text issues" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } };
    const correction: Origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 2 } };
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{ source, "Retain this independent statement.\n" });
        defer fixture.deinit();
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        for (0..3) |stage| {
            const input = if (stage == 0) try f.build_input.execute(a, progress) else try f.summaries(a, progress, fixture.context());
            for (0..@as(usize, if (stage == 2) 4 else 3)) |fault| {
                const bad_text: r.text.BusinessText = .{ .segments = if (fault == 2)
                    &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 999 } } }}
                else
                    &.{.{ .literal = .{ .value = if (fault == 0) "Invalid\x01text" else " \t" } }} };
                const bad: r.ContentProposal = .{ .model = .{ .business = bad_text } };
                const good: r.ContentProposal = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Display a result." } }} } } };
                var parsed: r.Parsed = .{ .input = input, .source = .{ .origin = original }, .proposal = undefined };
                var replacement: repair.Replacement = .{ .content = good };
                if (stage == 0) {
                    var proposal = try f.summary(a, input);
                    const statements = try a.dupe(r.StatementProposal, proposal.statements);
                    statements[0].content = bad;
                    proposal.statements = statements;
                    parsed.proposal = .{ .summary = proposal };
                } else {
                    var proposal = try globalWithoutSpecRoles(a, input);
                    if (stage == 1) {
                        const signals = try a.dupe(r.SignalProposal, proposal.signals);
                        signals[0].content = bad;
                        proposal.signals = signals;
                    } else {
                        const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
                        dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[1].claim_id} } };
                        dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
                        proposal.claim_dispositions = dispositions;
                        proposal.signals = proposal.signals[2..];
                        const nodes: []const r.text.ReferenceNode = switch (fault) {
                            2 => &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 999 } } }},
                            3 => &.{.{ .source = .{ .source_id = .{ .ordinal = 999 } } }},
                            else => &.{.{ .literal = bad_text.segments[0].literal }},
                        };
                        proposal.conflicts = &.{.{ .claim_ids = &.{ dispositions[0].claim_id, dispositions[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = nodes } }};
                        replacement = .{ .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The supplied assertions disagree." } }} } };
                    }
                    parsed.proposal = .{ .global = proposal };
                }
                const rejected = (try textRejection(a, parsed, fixture.context())).?;
                try std.testing.expectEqual(.typed_text, rejected.issue.rule);
                const issue = rejected.issue.expected.text_issue;
                try std.testing.expectEqual(([_]@FieldType(r.text.Issue, "reason"){ .invalid_scalar, .blank, .unknown_passive, .unknown_source })[fault], issue.reason);
                const authorization = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
                const packet = try repair.packet(std.testing.allocator, parsed, fixture.context(), authorization);
                defer packets.release(packet);
                const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
                const repair_input = body.value.object.get("input").?.object;
                try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Together, the statements must cover every assigned claim ID") == null);
                if (stage == 0) {
                    const initial_packet = try @import("domain/reference_model_input.zig").reconciliationCompositionPacket(std.testing.allocator, input, fixture.inputs, fixture.text.registry);
                    defer packets.release(initial_packet);
                    const initial_body = (try std.json.parseFromSlice(std.json.Value, a, initial_packet.body(), .{})).value.object;
                    const purpose = initial_body.get("summary_purpose").?.string;
                    try std.testing.expect(purpose.len != 0);
                    try std.testing.expectEqualStrings(purpose, repair_input.get("summary_purpose").?.string);
                    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, packet.body(), purpose));
                } else try std.testing.expect(!repair_input.contains("summary_purpose"));
                const rule = body.value.object.get("repair").?.object.get("rule").?.object;
                try std.testing.expect(!rule.contains("requirement"));
                try std.testing.expectEqualStrings(issue.description(), rule.get("failed_requirement").?.string);
                const projected = try json.decode(r.diagnostic.Fact, a, try std.json.Stringify.valueAlloc(a, rule.get("expected").?, .{}));
                try std.testing.expectEqualDeep(issue, projected.text_issue);
                try std.testing.expect(!rule.contains("dependencies") and !rule.contains("origin"));
                try std.testing.expectEqual(@as(usize, 0), body.value.object.get("input").?.object.get("passive_literals").?.array.items.len);
                try std.testing.expectEqualStrings("passive", packet.excludedVariants()[0].kind);
                try std.testing.expectEqualStrings(if (stage == 2) "repair_summary" else "business_text", packet.resultDefinition().?.bytes);
                const unchanged = try repair.merge(a, parsed, fixture.context(), authorization, authorization.operation.replace, correction);
                try std.testing.expect(!unchanged.source.last_repair.?.changed);
                try std.testing.expectEqualDeep(correction, (try textRejection(a, unchanged, fixture.context())).?.origin.?);
                const accepted = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, try f.repairResponse(a, replacement)), correction);
                try std.testing.expect(accepted.source.last_repair.?.changed);
                try std.testing.expectEqual(@as(u64, 2), accepted.source.last_repair.?.revision_after);
                try std.testing.expect(try textRejection(a, accepted, fixture.context()) == null);
                if (stage == 0) {
                    try std.testing.expectEqualDeep(parsed.proposal.summary.statements[1..], accepted.proposal.summary.statements[1..]);
                    _ = try f.build_summary.execute(a, try f.assign_summary.execute(a, (try f.validate_summary.execute(a, accepted, fixture.context())).valid));
                } else {
                    try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions, accepted.proposal.global.claim_dispositions);
                    const sibling_start: usize = if (stage == 2) 0 else 1;
                    try std.testing.expectEqualDeep(parsed.proposal.global.signals[sibling_start..], accepted.proposal.global.signals[sibling_start..]);
                    const outcome = (try f.finish(a, input, try mockUnsupportedRoles(a, accepted.proposal.global), fixture.context())).valid.outcome;
                    try std.testing.expectEqual(@as(@TypeOf(outcome), if (stage == 2) .blocked else .complete), outcome);
                }
                var stale = fixture.context();
                stale.inputs.corpus.state_id.bytes = "different-source";
                try std.testing.expectError(error.InvalidReferenceReconciliation, textRejection(a, parsed, stale));
                try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, accepted, fixture.context(), authorization, replacement, correction));
            }
        }
    }
}

fn textRejection(a: std.mem.Allocator, parsed: r.Parsed, ctx: f.Context) !?r.diagnostic.Rejection {
    if (parsed.proposal == .summary) return switch (try f.validate_summary.execute(a, parsed, ctx)) {
        .valid => null,
        .invalid => |issue| issue,
    };
    const dispositions = (try f.validate_dispositions.execute(a, parsed)).valid;
    const signals = switch (try f.validate_signals.execute(a, dispositions, ctx)) {
        .valid => |value| value,
        .invalid => |issue| return issue,
    };
    if (parsed.phase != .complete) return null;
    return switch (try f.validate_conflicts.execute(a, signals, ctx)) {
        .valid => null,
        .invalid => |issue| issue,
    };
}
pub fn prepare(allocator: std.mem.Allocator, sources: []const []const u8) !Fixture {
    const inputs = try @import("reference_ingestion_test.zig").readSources(std.testing.io, allocator, sources);
    var ids: @import("reference_evidence_test.zig").IdSource = .{};
    const citable = try @import("reference_evidence_test.zig").prepare(allocator, &ids, inputs);
    const candidates = try tokens.candidates(allocator, citable);
    const results = try allocator.alloc(r.extraction.RawResult, citable.chunks.entries.len);
    for (citable.chunks.entries, results) |chunk, *result| {
        result.* = .{ .scope = .{ .state_id = citable.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = try tokens.wire(allocator, try extraction.reply(allocator, chunk, "The user can confirm the request."), try tokens.classifications(allocator, candidates, chunk)) } };
    }
    return .{ .inputs = citable, .extracted = try extraction.finish(allocator, citable, results), .text = try text.prepare(allocator, citable) };
}

test "reference lineage preserves selections and frees owned memory across ledger sizes" {
    const support = @import("domain/reference_support.zig");
    for ([_]usize{ 1, 16 }) |count| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const sources = try a.alloc([]const u8, count);
        for (sources, 0..) |*source, index| source.* = try std.fmt.allocPrint(a, "Record outcome {d}.\n", .{index});
        const fixture = try prepare(a, sources);
        defer fixture.deinit();
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const items = progress.plan.layout.items;
        var claims: std.ArrayList(r.ClaimId) = .empty;
        for (items.entries) |entry| if (entry.claim.content == .model) try claims.append(a, entry.claim.id);
        try std.testing.expect(claims.items.len >= count);

        var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const measured = counted.allocator();
        const lineage = try support.lineage(measured, claims.items, &.{});
        const resolved = try support.select(measured, items, fixture.inputs, lineage);
        try std.testing.expectEqualDeep(claims.items, resolved.claim_ids);
        measured.free(resolved.citation_ids);
        measured.free(resolved.scopes);
        measured.free(lineage);
        try std.testing.expectEqual(counted.allocated_bytes, counted.freed_bytes);
        var backing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        var measured_arena: std.heap.ArenaAllocator = .init(backing.allocator());
        const arena_lineage = try support.lineage(measured_arena.allocator(), claims.items, &.{});
        _ = try support.select(measured_arena.allocator(), items, fixture.inputs, arena_lineage);
        measured_arena.deinit();
        try std.testing.expectEqual(backing.allocated_bytes, backing.freed_bytes);
    }
}

test "canonical citation union preserves selected claim order and overlapping evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First claim.\n", "Second claim.\n" });
    defer fixture.deinit();
    const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    var items = progress.plan.layout.items;
    const entries = try a.dupe(r.Item, items.entries);
    entries[0].claim.citation_ids = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 } };
    entries[1].claim.citation_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 3 } };
    items.entries = entries;
    const Case = struct { claims: []const r.ClaimId, citations: []const r.CitationId };
    for ([_]Case{
        .{ .claims = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, .citations = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 }, .{ .ordinal = 3 } } },
        .{ .claims = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 } }, .citations = &.{ .{ .ordinal = 1 }, .{ .ordinal = 3 }, .{ .ordinal = 2 } } },
        .{ .claims = &.{ .{ .ordinal = 1 }, .{ .ordinal = 1 } }, .citations = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 } } },
        .{ .claims = &.{}, .citations = &.{} },
    }) |case| {
        const citations = try r.citationUnion(std.testing.allocator, items, case.claims);
        defer std.testing.allocator.free(citations);
        try std.testing.expectEqualDeep(case.citations, citations);
    }
    for ([_]u32{ 0, 999 }) |id| try std.testing.expectError(error.InvalidReferenceReconciliation, r.citationUnion(std.testing.allocator, items, &.{.{ .ordinal = id }}));
}

test "shared reference support resolves ordered claims without Spec policy" {
    const support = @import("domain/reference_support.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First claim.\n", "Second claim.\n" });
    defer fixture.deinit();
    const items = (try f.initialize(a, fixture.inputs, fixture.extracted, 2)).plan.layout.items;
    const claims = [_]r.ClaimId{ .{ .ordinal = 2 }, .{ .ordinal = 1 } };
    const selected = try support.select(std.testing.allocator, items, fixture.inputs, &claims);
    defer std.testing.allocator.free(selected.scopes);
    defer std.testing.allocator.free(selected.citation_ids);
    try std.testing.expectEqualDeep(&claims, selected.claim_ids);
    try std.testing.expectEqualDeep(&[_]r.CitationId{ .{ .ordinal = 2 }, .{ .ordinal = 1 } }, selected.citation_ids);
    try std.testing.expectEqualDeep(items.entries[1].claim.chunk_id, selected.scopes[0].chunk_id);
    try std.testing.expectEqualDeep(items.entries[0].claim.chunk_id, selected.scopes[1].chunk_id);

    try std.testing.expectError(error.InvalidReferenceReconciliation, support.select(std.testing.allocator, items, fixture.inputs, &.{ claims[0], claims[0] }));
    try std.testing.expectError(error.InvalidReferenceReconciliation, support.select(std.testing.allocator, items, fixture.inputs, &.{.{ .ordinal = 999 }}));
    var stale = items;
    stale.state_id.bytes = "stale";
    try std.testing.expectError(error.InvalidReferenceState, support.select(std.testing.allocator, stale, fixture.inputs, &claims));
    const bad_entries = try a.dupe(r.Item, items.entries);
    bad_entries[1].claim.chunk_id.bytes = "missing";
    var invalid_scope = items;
    invalid_scope.entries = bad_entries;
    try std.testing.expectError(error.InvalidSourceCitation, support.select(std.testing.allocator, invalid_scope, fixture.inputs, &claims));
}

test "shared reference support releases allocations on every failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, supportAllocationCase, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, lineageAllocationCase, .{});
}

fn lineageAllocationCase(allocator: std.mem.Allocator) !void {
    const support = @import("domain/reference_support.zig");
    const explicit = [_]r.ClaimId{.{ .ordinal = 1 }};
    const extra = [_]r.ClaimId{ .{ .ordinal = 2 }, .{ .ordinal = 3 }, .{ .ordinal = 2 }, .{ .ordinal = 4 }, .{ .ordinal = 5 }, .{ .ordinal = 6 }, .{ .ordinal = 7 }, .{ .ordinal = 8 }, .{ .ordinal = 9 }, .{ .ordinal = 10 } };
    const selected = try support.lineage(allocator, &explicit, &extra);
    defer allocator.free(selected);
    try std.testing.expectEqual(@as(usize, 10), selected.len);
    try std.testing.expectEqualDeep(explicit[0], selected[0]);
}

fn supportAllocationCase(backing: std.mem.Allocator) !void {
    const support = @import("domain/reference_support.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"An application starts.\n"});
    defer fixture.deinit();
    const items = (try f.initialize(a, fixture.inputs, fixture.extracted, 2)).plan.layout.items;
    const resolved = try support.select(backing, items, fixture.inputs, &.{.{ .ordinal = 1 }});
    defer backing.free(resolved.scopes);
    defer backing.free(resolved.citation_ids);
    try std.testing.expectEqual(@as(usize, 1), resolved.scopes.len);
}

test "hierarchical reconciliation preserves original meaning citations exact tokens and total membership" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Display `Hello, World!`.\n", "Renew a library loan.\r\n", "Use `Cafe\u{301}`.\r\n", "A fourth requirement.\n", "A fifth requirement.\n", "A sixth requirement.\n", "A seventh requirement.\n", "An eighth requirement.\n", "A ninth requirement.\n" });
    defer fixture.deinit();
    const initial = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    var levels = std.enums.EnumSet(r.Level).initEmpty();
    var recursive_global = false;
    for (initial.plan.partitions) |partition| {
        levels.insert(partition.group.level);
        recursive_global = recursive_global or partition.group.round > 0;
        try std.testing.expect((if (partition.group.level == .within_source) partition.group.claim_ids.len else partition.group.children.len) <= 2);
    }
    try std.testing.expectEqual(@as(usize, 3), levels.count());
    try std.testing.expect(recursive_global);
    const final = try f.summaries(a, initial, fixture.context());
    try std.testing.expectEqual(fixture.extracted.ledger.claims.len, final.items.len);
    for (final.items, fixture.extracted.ledger.claims) |item, original| try std.testing.expectEqualDeep(original, item.claim);
    const result = (try f.finish(a, final, try globalWithoutSpecRoles(a, final), fixture.context())).valid;
    try std.testing.expectEqual(.complete, result.outcome);
    try std.testing.expectEqual(final.items.len, result.records.signals.len);
    try std.testing.expectEqualDeep(result, (try f.finish(a, final, try globalWithoutSpecRoles(a, final), fixture.context())).valid);
    try std.testing.expectEqualStrings("Hello, World!", final.items[1].claim.content.preserved_token.value.raw_value.bytes);
    try std.testing.expectEqualStrings("Cafe\u{301}", final.items[4].claim.content.preserved_token.value.raw_value.bytes);
}

test "partition coverage rejects omissions duplicates foreign children ordering and invalid group size" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n" });
    defer fixture.deinit();
    const initial = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    for ([_]u32{ 0, 1 }) |size| try std.testing.expectError(error.InvalidReferenceReconciliation, f.partition.execute(a, initial.plan.layout.items, size));
    for (0..4) |scenario| {
        var plan = initial.plan;
        const partitions = try a.dupe(r.Partition, plan.partitions);
        plan.partitions = partitions;
        switch (scenario) {
            0 => plan.partitions = partitions[1..],
            1 => partitions[1] = partitions[0],
            2 => partitions[2].group.children = &.{.{ .value = 999 }},
            3 => partitions[0].group.claim_ids = &.{.{ .ordinal = 2 }},
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_partitions.execute(a, plan));
    }
    var blocked = fixture.extracted;
    blocked.outcome = .blocked;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.build_items.execute(a, fixture.inputs, blocked));
    var stale = fixture.extracted;
    stale.ledger.state_id.bytes = "stale";
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.build_items.execute(a, fixture.inputs, stale));
}

test "summaries reject missing duplicate foreign memberships incompatible kinds and token references" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `Hello, World!`.\n"});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2));
    const valid = try f.summary(a, input);
    for (0..8) |scenario| {
        var proposal = valid;
        const statements = try a.dupe(r.StatementProposal, valid.statements);
        proposal.statements = statements;
        switch (scenario) {
            0 => proposal.statements = &.{},
            1 => statements[0].claim_ids = &.{ statements[0].claim_ids[0], statements[0].claim_ids[0] },
            2 => statements[0].claim_ids = &.{},
            3 => proposal.statements = statements[0..1],
            4 => statements[1].claim_ids = statements[0].claim_ids,
            5 => statements[0].claim_ids = &.{.{ .ordinal = 999 }},
            6 => statements[0].content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 1 } } },
            7 => statements[1].content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 999 } } },
            else => unreachable,
        }
        const rejected = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = proposal } }, fixture.context())).invalid;
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .membership, .claim_selection, .claim_selection, .membership, .content, .claim_selection, .content, .content })[scenario], rejected.issue.rule);
    }
    var reversed = valid;
    reversed.statements = &.{ valid.statements[1], valid.statements[0] };
    const checked = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = reversed } }, fixture.context())).valid;
    try std.testing.expectEqualDeep(valid.statements[1].claim_ids, checked.statements[0].claim_ids);
}

test "closed reconciliation JSON rejects model identities unknown fields union variants and invented resolution" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2));
    for ([_][]const u8{
        "{}",                                                                            "null",                                                                                  "[]",                                                                                                                  "{\"global\":{}}",                                                                                                                                                           "{\"global\":{},\"summary\":{}}",
        "{\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[],\"conflict_id\":1}", "{\"claim_dispositions\":[],\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[]}", "{\"claim_dispositions\":[{\"claim_id\":1,\"disposition\":{\"kind\":\"resolved\"}}],\"signals\":[],\"conflicts\":[]}", "{\"claim_dispositions\":[],\"signals\":[],\"conflicts\":[{\"claim_ids\":[],\"kind\":\"value_mismatch\",\"summary\":{\"nodes\":[]},\"resolution\":\"source_precedence\"}]}",
    }) |bytes| try std.testing.expectError(error.InvalidReferenceReconciliation, f.parse.execute(a, .{ .input = input, .bytes = bytes }));
}

test "each disposition is total unique current and has a valid terminal relationship" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n", "Third\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const valid = try globalWithoutSpecRoles(a, input);
    for (0..9) |scenario| {
        var proposal = valid;
        const values = try a.dupe(r.ClaimDispositionProposal, valid.claim_dispositions);
        proposal.claim_dispositions = values;
        switch (scenario) {
            0 => proposal.claim_dispositions = values[1..],
            1 => values[1] = values[0],
            2 => values[0].claim_id.ordinal = 999,
            3 => values[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{} } },
            4 => values[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{} } },
            5 => {
                values[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{values[0].claim_id} } };
            },
            6 => {
                values[0].disposition = .{ .duplicate = .{ .target_claim_id = .{ .ordinal = 999 } } };
            },
            7 => {
                values[0].disposition = .{ .duplicate = .{ .target_claim_id = values[1].claim_id } };
                values[1].disposition = .{ .duplicate = .{ .target_claim_id = values[0].claim_id } };
            },
            8 => {
                values[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{values[1].claim_id} } };
            },
            else => unreachable,
        }
        const rejected = (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).invalid;
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .cardinality, .duplicate_disposition, .claim_selection, .cardinality, .cardinality, .relationship, .claim_selection, .cycle, .relationship })[scenario], rejected.issue.rule);
    }
    for ([_]r.Disposition{ .duplicate, .superseded }) |kind| {
        var proposal = valid;
        const values = try a.dupe(r.ClaimDispositionProposal, valid.claim_dispositions);
        values[0].disposition = switch (kind) {
            .duplicate => .{ .duplicate = .{ .target_claim_id = values[1].claim_id } },
            .superseded => .{ .superseded = .{ .related_claim_ids = &.{values[1].claim_id} } },
            .retained, .conflicting => unreachable,
        };
        proposal.claim_dispositions = values;
        proposal.signals = valid.signals[1..];
        try std.testing.expectEqual(.complete, ((try f.finish(a, input, proposal, fixture.context())).valid).outcome);
    }
    var chain = valid;
    const chained = try a.dupe(r.ClaimDispositionProposal, valid.claim_dispositions);
    chained[0].disposition = .{ .duplicate = .{ .target_claim_id = chained[1].claim_id } };
    chained[1].disposition = .{ .superseded = .{ .related_claim_ids = &.{chained[2].claim_id} } };
    chain.claim_dispositions = chained;
    chain.signals = valid.signals[2..];
    try std.testing.expectEqual(.complete, ((try f.finish(a, input, chain, fixture.context())).valid).outcome);
    chained[1].disposition.superseded.related_claim_ids = &.{ chained[2].claim_id, chained[2].claim_id };
    try std.testing.expectEqual(.relationship, (try f.finish(a, input, chain, fixture.context())).invalid.issue.rule);
}

pub fn conflicting(allocator: std.mem.Allocator, input: r.Input) !r.Proposal {
    var proposal = try globalWithoutSpecRoles(allocator, input);
    const dispositions = try allocator.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    if (dispositions.len != 2) return error.InvalidReferenceReconciliation;
    dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = try allocator.dupe(r.ClaimId, &.{dispositions[1].claim_id}) } };
    dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = try allocator.dupe(r.ClaimId, &.{dispositions[0].claim_id}) } };
    proposal.claim_dispositions = dispositions;
    proposal.signals = &.{};
    const conflicts = try allocator.alloc(r.ConflictProposal, 1);
    conflicts[0] = .{ .claim_ids = input.partition.group.claim_ids, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The references disagree about the required behavior." } }} } };
    proposal.conflicts = conflicts;
    proposal.conflict_groups = try allocator.dupe(@import("domain/reference_conflict_groups.zig").Group, &.{.{ .claim_ids = input.partition.group.claim_ids }});
    return proposal;
}

test "unresolved conflicts are engine identified and blocking and cannot disappear or leak into signals" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm immediately.\n", "Request approval first.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const proposal = try conflicting(a, input);
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
    try std.testing.expectEqual(.blocked, result.outcome);
    try std.testing.expectEqual(@as(u32, 1), result.records.conflicts[0].id.ordinal);
    try std.testing.expectEqual(.unresolved, result.records.conflicts[0].value.resolution);
    for (0..5) |scenario| {
        var invalid = proposal;
        const conflicts = try a.dupe(r.ConflictProposal, proposal.conflicts);
        invalid.conflicts = conflicts;
        switch (scenario) {
            0 => invalid.conflicts = &.{},
            1 => invalid.conflicts = &.{ conflicts[0], conflicts[0] },
            2 => conflicts[0].claim_ids = &.{ input.items[0].claim.id, .{ .ordinal = 999 } },
            3 => conflicts[0].claim_ids = &.{.{ .ordinal = 999 }},
            4 => invalid.signals = (try globalWithoutSpecRoles(a, input)).signals,
            else => unreachable,
        }
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .conflict_coverage, .duplicate_conflict, .claim_selection, .cardinality, .relationship })[scenario], (try f.finish(a, input, invalid, fixture.context())).invalid.issue.rule);
    }
    var dropped = result.records;
    dropped.conflicts = &.{};
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.account.execute(a, dropped));
}

test "signal projection requires exact citation token kind and retained-claim coverage" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `Hello, World!`.\n"});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const valid = try globalWithoutSpecRoles(a, input);
    for (0..7) |scenario| {
        var proposal = valid;
        const signals = try a.dupe(r.SignalProposal, valid.signals);
        proposal.signals = signals;
        switch (scenario) {
            0 => proposal.signals = signals[0..1],
            1 => signals[0].claim_ids = &.{},
            2 => signals[0].claim_ids = &.{ signals[0].claim_ids[0], signals[0].claim_ids[0] },
            3 => signals[0].claim_ids = &.{.{ .ordinal = 999 }},
            4 => signals[1].content.preserved_token.token_id.ordinal = 999,
            5 => signals[1].content = signals[0].content,
            6 => proposal.signals = &.{ signals[0], signals[1], signals[0] },
            else => unreachable,
        }
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .signal_coverage, .claim_selection, .claim_selection, .claim_selection, .content, .content, .duplicate_signal })[scenario], (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
    }
}

test "scoped reconciliation text validates explicit references across multiple sources" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n", "Third\n" });
    defer fixture.deinit();
    const items = try f.build_items.execute(a, fixture.inputs, fixture.extracted);
    const context = try @import("domain/reference_reconciliation_validation.zig").scopes(a, items, &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, fixture.context());
    const allowed: r.text.ReferenceSemanticText = .{ .nodes = &.{ .{ .source = .{ .source_id = .{ .ordinal = 1 } } }, .{ .source = .{ .source_id = .{ .ordinal = 2 } } } } };
    _ = try text.validator.referenceIn(a, context, allowed);
    try std.testing.expectError(error.InvalidTypedText, text.validator.referenceIn(a, context, .{ .nodes = &.{.{ .source = .{ .source_id = .{ .ordinal = 3 } } }} }));
    _ = try text.validator.referenceIn(a, context, .{ .nodes = &.{.{ .literal = .{ .value = "Read src/main.zig." } }} });
    try std.testing.expectError(error.InvalidTypedText, text.validator.reference(a, .{ .registry = context.registry, .current = context.current, .inputs = context.inputs, .scope = context.scopes[0] }, allowed));
}

test "empty fully accounted references reconcile without fabricated membership" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{""});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    try std.testing.expectEqual(@as(usize, 0), input.items.len);
    try std.testing.expectEqual(.complete, ((try f.finish(a, input, try globalWithoutSpecRoles(a, input), fixture.context())).valid).outcome);
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display `exact`.\n"});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    _ = (try f.finish(a, input, try globalWithoutSpecRoles(a, input), fixture.context())).valid;
}
test "reconciliation releases allocation failures throughout all stages" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

test "every existing claim kind uses the same reconciliation text and signal contracts" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"An independently supported claim.\n"});
    defer fixture.deinit();
    inline for (comptime std.meta.tags(r.extraction.Kind)) |kind| {
        var extracted = fixture.extracted;
        const claims = try a.dupe(r.extraction.Claim, extracted.ledger.claims);
        claims[0].content = .{ .model = @unionInit(r.extraction.Content, @tagName(kind), if (comptime kind == .business or kind == .scope_guard)
            r.text.ValidatedBusinessText{ .value = .{ .segments = &.{.{ .literal = .{ .value = "An independently supported claim." } }} } }
        else
            r.text.ValidatedReferenceSemanticText{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "An independently supported claim." } }} } }) };
        extracted.ledger.claims = claims;
        const input = try f.summaries(a, try f.initialize(a, fixture.inputs, extracted, 2), fixture.context());
        const result = (try f.finish(a, input, try globalWithoutSpecRoles(a, input), fixture.context())).valid;
        try std.testing.expectEqual(kind, std.meta.activeTag(result.records.signals[0].value.content.model));
    }
}

test "authorized content payloads cover every kind across statement and signal insertion and replacement" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    const correction: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 9 }, .attempt = .{ .value = 2 } };
    inline for (comptime std.meta.tags(r.extraction.Kind)) |kind| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{ "Display a greeting on startup.\n", "Keep the independent requirement.\n" });
        defer fixture.deinit();
        var extracted = fixture.extracted;
        const claims = try a.dupe(r.extraction.Claim, extracted.ledger.claims);
        claims[0].content = .{ .model = @unionInit(r.extraction.Content, @tagName(kind), if (comptime kind == .business or kind == .scope_guard)
            r.text.ValidatedBusinessText{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Display a greeting on startup." } }} } }
        else
            r.text.ValidatedReferenceSemanticText{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "Display a greeting on startup." } }} } }) };
        extracted.ledger.claims = claims;
        const progress = try f.initialize(a, fixture.inputs, extracted, 8);
        for ([_]bool{ false, true }) |global| for ([_]bool{ false, true }) |insert| {
            const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
            var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try globalWithoutSpecRoles(a, input) } else .{ .summary = try f.summary(a, input) } };
            const good: repair.Replacement = .{ .content = if (global) parsed.proposal.global.signals[0].content else parsed.proposal.summary.statements[0].content };
            const bad: repair.Replacement = .{ .content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 1 } } } };
            if (global) {
                const signals = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
                if (!insert) signals[0].content = bad.content;
                parsed.proposal.global.signals = signals[@intFromBool(insert)..];
            } else {
                const statements = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
                if (!insert) statements[0].content = bad.content;
                parsed.proposal.summary.statements = statements[@intFromBool(insert)..];
            }
            const rejection = (try textRejection(a, parsed, fixture.context())).?;
            const auth = (try repair.authorize(a, parsed, fixture.context(), rejection)).model;
            const packet = try repair.packet(a, parsed, fixture.context(), auth);
            defer packets.release(packet);
            try std.testing.expectEqual(kind, auth.rule.rejection.relations.content.?.model);
            try std.testing.expectEqualStrings(if (kind == .business or kind == .scope_guard) "business_text" else "reference_text", packet.resultDefinition().?.bytes);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const repair_input = body.value.object.get("repair").?.object;
            try std.testing.expect(!repair_input.contains("expected"));
            try std.testing.expectEqual(!insert, repair_input.contains("current_value"));
            if (!insert) try std.testing.expectEqualStrings("preserved_token", repair_input.get("current_value").?.object.get("kind").?.string);
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "exact_selected_token") == null);
            for ([_][]const u8{ "{\"kind\":\"preserved_token\",\"token_id\":1}", "{\"token_id\":1}", "{}", "{\"current_value\":{}}" }) |wire|
                try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, auth, packet, wire));
            const replacement = try repair.parse(a, auth, packet, try f.repairResponse(a, good));
            try std.testing.expectEqualDeep(good, replacement);
            const merged = try repair.merge(a, parsed, fixture.context(), auth, replacement, correction);
            try std.testing.expect((try textRejection(a, merged, fixture.context())) == null);
            try std.testing.expect(merged.source.last_repair.?.changed);
            try std.testing.expectEqualDeep(correction, merged.source.last_repair.?.origin.?);
            try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, merged, fixture.context(), auth, replacement, correction));
            if (global) {
                try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions, merged.proposal.global.claim_dispositions);
                try std.testing.expectEqualDeep(parsed.proposal.global.conflicts, merged.proposal.global.conflicts);
                try std.testing.expectEqualDeep(parsed.proposal.global.signals[@intFromBool(!insert)..], merged.proposal.global.signals[@intFromBool(!insert)..parsed.proposal.global.signals.len]);
                _ = (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid;
            } else try std.testing.expectEqualDeep(parsed.proposal.summary.statements[@intFromBool(!insert)..], merged.proposal.summary.statements[@intFromBool(!insert)..parsed.proposal.summary.statements.len]);

            // Replay R22's native merge sequence: malformed semantics never gain
            // authority, even when an unchanged value has a new request origin.
            if (kind == .business and global and insert) {
                const invalid = try repair.merge(a, parsed, fixture.context(), auth, bad, correction);
                const rejected = (try textRejection(a, invalid, fixture.context())).?;
                try std.testing.expectEqual(.content, rejected.issue.rule);
                const retry = (try repair.authorize(a, invalid, fixture.context(), rejected)).model;
                const unchanged = try repair.merge(a, invalid, fixture.context(), retry, bad, correction);
                try std.testing.expect(!unchanged.source.last_repair.?.changed);
                try std.testing.expectEqual(@as(u64, 3), unchanged.source.revision);
                const next = (try textRejection(a, unchanged, fixture.context())).?;
                const recovery = (try repair.authorize(a, unchanged, fixture.context(), next)).model;
                const recovery_packet = try repair.packet(a, unchanged, fixture.context(), recovery);
                defer packets.release(recovery_packet);
                const recovered = try repair.merge(a, unchanged, fixture.context(), recovery, try repair.parse(a, recovery, recovery_packet, try f.repairResponse(a, good)), correction);
                _ = (try f.finish(a, input, try mockUnsupportedRoles(a, recovered.proposal.global), fixture.context())).valid;
                try std.testing.expectError(error.InvalidAtomicRepair, repair.parse(a, recovery, packet, try f.repairResponse(a, good)));
            }
        };
    }
}

test "final lineage rejects removed summaries altered membership and changed canonical records" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const proposal = try globalWithoutSpecRoles(a, input);
    for (0..4) |scenario| {
        var altered = input;
        const latest = try a.create(r.SummaryHistory);
        latest.* = input.progress.latest.?.*;
        altered.progress.latest = latest;
        switch (scenario) {
            0 => altered.progress.latest = latest.previous,
            1 => latest.value.member_claim_ids = &.{},
            2 => latest.value.member_summary_ids = &.{},
            3 => latest.value.statements = &.{},
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, altered, proposal, fixture.context()));
    }
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
    for (0..6) |scenario| {
        var records = result.records;
        const signals = try a.dupe(r.Signal, records.signals);
        records.signals = signals;
        switch (scenario) {
            0 => records.signals = signals[1..],
            1 => signals[0].id.ordinal += 1,
            2 => signals[0].value.claim_ids = &.{},
            3 => records.assignments.checked.prior.prior.dispositions = &.{},
            4 => {
                const dispositions = try a.dupe(r.ClaimDisposition, records.assignments.checked.prior.prior.dispositions);
                dispositions[0].related_claim_ids = &.{.{ .ordinal = 999 }};
                records.assignments.checked.prior.prior.dispositions = dispositions;
            },
            5 => {
                const progress = &records.assignments.checked.prior.prior.input.progress;
                progress.summary_count = 0;
                progress.latest = null;
                progress.next_statement_ordinal = 1;
            },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.account.execute(a, records));
    }
}

test "different exact scalars cannot be declared duplicates and token obligations survive supersession" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Use `grey`.\n", "Use `blue`.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try globalWithoutSpecRoles(a, input);
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    dispositions[1].disposition = .{ .duplicate = .{ .target_claim_id = dispositions[3].claim_id } };
    proposal.claim_dispositions = dispositions;
    try std.testing.expectEqual(.relationship, (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
    dispositions[1].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[3].claim_id} } };
    // Supersession retains the original token and obligation as provenance.
    try std.testing.expectEqual(.complete, ((try f.finish(a, input, proposal, fixture.context())).valid).outcome);
    proposal.signals = &.{ proposal.signals[0], proposal.signals[2], proposal.signals[3] };
    try std.testing.expectEqual(.signal_coverage, (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
    // A model claim cannot duplicate or supersede a preserved-token claim.
    for ([_]r.Disposition{ .duplicate, .superseded }) |kind| {
        dispositions[0].disposition = switch (kind) {
            .duplicate => .{ .duplicate = .{ .target_claim_id = dispositions[1].claim_id } },
            .superseded => .{ .superseded = .{ .related_claim_ids = &.{dispositions[1].claim_id} } },
            .retained, .conflicting => unreachable,
        };
        try std.testing.expectEqual(.same_content_kind, (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).invalid.issue.expected.constraint);
    }
}

test "duplicate and superseded selections cannot terminate in conflicting claims" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm immediately.\n", "Require approval.\n", "Skip approval.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try globalWithoutSpecRoles(a, input);
    const choices = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    proposal.claim_dispositions = choices;
    choices[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{choices[2].claim_id} } };
    choices[2].disposition = .{ .conflicting = .{ .related_claim_ids = &.{choices[1].claim_id} } };
    _ = (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).valid;
    for ([_]r.Disposition{ .duplicate, .superseded }) |kind| {
        choices[0].disposition = switch (kind) {
            .duplicate => .{ .duplicate = .{ .target_claim_id = choices[1].claim_id } },
            .superseded => .{ .superseded = .{ .related_claim_ids = &.{choices[1].claim_id} } },
            .retained, .conflicting => unreachable,
        };
        try std.testing.expectEqual(.nonconflicting_target, (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal } })).invalid.issue.expected.constraint);
    }
}

test "shared multi-source scope rejects unrelated passive literals and stale empty context" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First report.zig\n", "Second report.zig\n", "Third other.zig\n" });
    defer fixture.deinit();
    const items = try f.build_items.execute(a, fixture.inputs, fixture.extracted);
    const context = try @import("domain/reference_reconciliation_validation.zig").scopes(a, items, &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, fixture.context());
    try std.testing.expectEqual(@as(usize, 3), fixture.text.registry.occurrences.len);
    for (fixture.text.registry.occurrences) |occurrence| {
        const candidate: r.text.BusinessText = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = occurrence.id } }} };
        if (occurrence.origin.source_id.ordinal <= 2) {
            _ = try text.validator.businessIn(a, context, candidate);
        } else try std.testing.expectError(error.InvalidPassiveLiteral, text.validator.businessIn(a, context, candidate));
    }
    const empty = try prepare(a, &.{});
    defer empty.deinit();
    const input = try f.summaries(a, try f.initialize(a, empty.inputs, empty.extracted, 2), empty.context());
    var stale = empty.context();
    stale.inputs.corpus.state_id.bytes = "a-successor-state";
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.finish(a, input, try globalWithoutSpecRoles(a, input), stale));
}

test "reference candidate ownership retains predecessors and cleans deep histories iteratively" {
    const owned = @import("domain/reference_candidate_value.zig");
    var current = try owned.create(std.testing.allocator, null);
    defer owned.destroy(current);
    current.payload = .{ .reconciliation_items = .{ .state_id = .{ .bytes = try current.arena.allocator().dupe(u8, "retained-reference-state") }, .entries = &.{} } };
    for (0..4096) |_| {
        const successor = try owned.create(std.testing.allocator, owned.view(current));
        successor.payload = current.payload;
        owned.destroy(current);
        current = successor;
    }
    try std.testing.expectEqualStrings("retained-reference-state", current.payload.reconciliation_items.state_id.bytes);
}

test "overlapping conflicts conserve every declared conflict relationship" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "First\n", "Second\n", "Third\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try globalWithoutSpecRoles(a, input);
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    for (dispositions) |*value| value.disposition = .{ .conflicting = .{ .related_claim_ids = &.{} } };
    dispositions[0].disposition.conflicting.related_claim_ids = &.{ dispositions[1].claim_id, dispositions[2].claim_id };
    dispositions[1].disposition.conflicting.related_claim_ids = &.{dispositions[0].claim_id};
    dispositions[2].disposition.conflicting.related_claim_ids = &.{dispositions[0].claim_id};
    proposal.claim_dispositions = dispositions;
    proposal.signals = &.{};
    const conflicts = try a.alloc(r.ConflictProposal, 2);
    for (conflicts, 1..) |*conflict, index| {
        conflict.* = .{ .claim_ids = try a.dupe(r.ClaimId, &.{ dispositions[0].claim_id, dispositions[index].claim_id }), .kind = .scope_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The scopes disagree." } }} } };
    }
    proposal.conflicts = conflicts;
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
    try std.testing.expectEqual(.blocked, result.outcome);
    try std.testing.expectEqual(@as(usize, 2), result.records.conflicts.len);
    proposal.conflicts = conflicts[0..1];
    try std.testing.expectEqual(.conflict_coverage, (try f.finish(a, input, proposal, fixture.context())).invalid.issue.rule);
}

test "reconciliation diagnostics retain native facts and origin while stale context remains an error" {
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm the request.\n", "Renew the loan.\n" });
    defer fixture.deinit();
    const initial = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    const summary_input = try f.build_input.execute(a, initial);
    var summary = try f.summary(a, summary_input);
    summary.statements = &.{};
    const summary_bytes = try @import("domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), a, .{ .summary = summary });
    const parsed_summary = try f.parse.execute(a, .{ .input = summary_input, .bytes = summary_bytes, .source = .{ .revision = 3, .origin = origin } });
    const rejected = (try f.validate_summary.execute(a, parsed_summary, fixture.context())).invalid;
    try std.testing.expectEqual(.membership, rejected.issue.rule);
    try std.testing.expectEqualDeep(summary_input.partition.group.claim_ids, rejected.issue.expected.claims);
    try std.testing.expectEqual(@as(usize, 0), rejected.issue.observed.claims.len);
    try std.testing.expectEqual(@as(u64, 3), rejected.revision);
    try std.testing.expectEqualDeep(origin, rejected.origin.?);
    var stale = parsed_summary;
    stale.input.partition.id.ordinal += 1;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_summary.execute(a, stale, fixture.context()));
    const input = try f.summaries(a, initial, fixture.context());
    var proposal = try globalWithoutSpecRoles(a, input);
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    dispositions[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
    proposal.claim_dispositions = dispositions;
    const invalid = (try f.validate_dispositions.execute(a, .{ .input = input, .proposal = .{ .global = proposal }, .source = .{ .origin = origin } })).invalid;
    try std.testing.expectEqual(.no_self_relation, invalid.issue.expected.constraint);
    try std.testing.expectEqualDeep(try dispositions[0].canonical(a), invalid.issue.observed.disposition);
    const packet = try @import("domain/reference_model_input.zig").reconciliationPacket(a, input, fixture.inputs, fixture.text.registry, .all);
    defer @import("domain/model_input_packet.zig").release(packet);
    const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    defer body.deinit();
    const expected = invalid.issue.expected.constraint;
    for (body.value.object.get("constraints").?.array.items) |guidance| {
        if (!std.mem.eql(u8, guidance.object.get("constraint").?.string, @tagName(expected))) continue;
        try std.testing.expectEqualStrings(expected.description(), guidance.object.get("requirement").?.string);
        break;
    } else return error.MissingNativeRuleGuidance;
    const diagnostic: @import("domain/candidate_validation_diagnostic.zig").Diagnostic = .{ .reconciliation = invalid };
    try std.testing.expectEqualDeep(diagnostic, try diagnostic.copy(a));
    var changed = input;
    changed.progress.latest = null;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_dispositions.execute(a, .{ .input = changed, .proposal = .{ .global = proposal } }));
}

test "summary union coverage and overlapping signal evidence preserve original claims" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm a reservation.\n", "Issue a receipt.\n", "Notify the visitor.\n" });
    defer fixture.deinit();
    var progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    while (progress.summary_count + 1 < progress.plan.partitions.len) {
        const input = try f.build_input.execute(a, progress);
        const good = try f.summary(a, input);
        const checked = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = good } }, fixture.context())).valid;
        const missing = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = .{ .statements = good.statements[1..] } } }, fixture.context())).invalid;
        try std.testing.expectEqual(.membership, missing.issue.rule);
        try std.testing.expectEqualDeep(input.partition.group.claim_ids, missing.issue.expected.claims);
        try std.testing.expectEqual(input.partition.group.claim_ids.len - 1, missing.issue.observed.claims.len);
        const duplicates = try a.alloc(r.StatementProposal, good.statements.len + 1);
        @memcpy(duplicates[0..good.statements.len], good.statements);
        duplicates[good.statements.len] = good.statements[0];
        const repeated = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = .{ .statements = duplicates } } }, fixture.context())).valid;
        try std.testing.expectEqual(checked.statements.len, repeated.statements.len);
        if (good.statements.len > 1) {
            const overlapping = try a.dupe(r.StatementProposal, good.statements);
            overlapping[0].claim_ids = &.{ good.statements[0].claim_ids[0], good.statements[1].claim_ids[0] };
            const overlap = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = .{ .statements = overlapping } } }, fixture.context())).valid;
            try std.testing.expectEqual(overlapping.len, overlap.statements.len);
            try std.testing.expectEqualDeep(overlapping[0].claim_ids, overlap.statements[0].claim_ids);
            progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, overlap));
        } else {
            progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, repeated));
        }
        try std.testing.expectEqualDeep(input.partition.group.claim_ids, progress.latest.?.value.member_claim_ids);
        try std.testing.expectEqualDeep(input.member_summary_ids, progress.latest.?.value.member_summary_ids);
    }
    const input = try f.build_input.execute(a, progress);
    var proposal = try globalWithoutSpecRoles(a, input);
    const signals = try a.dupe(r.SignalProposal, proposal.signals[0..2]);
    signals[0].claim_ids = &.{ input.items[1].claim.id, input.items[0].claim.id };
    signals[1].claim_ids = &.{ input.items[1].claim.id, input.items[2].claim.id };
    proposal.signals = signals;
    const result = (try f.finish(a, input, proposal, fixture.context())).valid;
    for (result.records.signals, signals) |signal, selected| {
        try std.testing.expectEqualDeep(selected.claim_ids, signal.value.claim_ids);
        try std.testing.expectEqualDeep(try r.citationUnion(a, input.progress.plan.layout.items, selected.claim_ids), signal.value.citation_ids);
    }
    try std.testing.expectEqualDeep(input.items[1].claim.citation_ids[0], result.records.signals[0].value.citation_ids[0]);
    try std.testing.expectEqualDeep(input.items[0].claim.citation_ids[0], result.records.signals[0].value.citation_ids[1]);
}

fn crossSourceSummaryInput(a: std.mem.Allocator, fixture: Fixture) !r.Input {
    var progress = try f.initialize(a, fixture.inputs, fixture.extracted, 8);
    while (true) {
        const input = try f.build_input.execute(a, progress);
        if (input.partition.group.level == .cross_source) return input;
        const checked = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = try f.summary(a, input) } }, fixture.context())).valid;
        progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
    }
}

const reuse_summary = @import("actions/reference/reuse_reference_reconciliation_summary.zig").Action{ .validator = f.validate_summary.validator };
const check_summary_reuse = @import("actions/reference/check_reference_summary_reuse.zig").Action{ .validator = f.validate_summary.validator };

test "native summaries preserve normalized child content tokens and original producer lineage" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, nativeSummaryCase, .{});
}
fn nativeSummaryCase(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"MOCK Display `MOCK READY` and preserve another occurrence `MOCK READY`.\n"});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 8));
    const good = try f.summary(a, input);
    const statements = try a.alloc(r.StatementProposal, good.statements.len + 1);
    @memcpy(statements[0..good.statements.len], good.statements);
    statements[good.statements.len] = good.statements[0];
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 2 } };
    const checked = (try f.validate_summary.execute(a, .{ .input = input, .source = .{ .origin = origin }, .proposal = .{ .summary = .{ .statements = statements } } }, fixture.context())).valid;
    const previous = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
    const current = try f.build_input.execute(a, previous);
    const native = try reuse_summary.execute(a, current, fixture.context());
    try std.testing.expectEqualDeep(r.diagnostic.Source{}, native.source);
    try std.testing.expectEqualDeep(previous.latest.?.value.id, native.carried_from.?);
    try std.testing.expectEqual(checked.statements.len, native.proposal.summary.statements.len);
    const carried = (try f.validate_summary.execute(a, native, fixture.context())).valid;
    try std.testing.expectEqualDeep(checked.statements, carried.statements);
    const next = try f.build_summary.execute(a, try f.assign_summary.execute(a, carried));
    try std.testing.expectEqualDeep(previous.latest.?.value, next.latest.?.previous.?.value);
    try std.testing.expectEqual(statements.len, next.latest.?.previous.?.value.projection.originals.len);
    try std.testing.expectEqualDeep(origin, next.latest.?.previous.?.value.projection.source.origin.?);
    try std.testing.expect(next.latest.?.value.projection.source.origin == null);
    try std.testing.expectEqualDeep(current.member_summary_ids, next.latest.?.value.member_summary_ids);
    try std.testing.expectEqual(previous.next_statement_ordinal, next.latest.?.value.statements[0].id.ordinal);
    var token_count: usize = 0;
    for (next.latest.?.value.statements) |statement| if (statement.content == .preserved_token) {
        token_count += 1;
    };
    try std.testing.expectEqual(@as(usize, 2), token_count);
    try std.testing.expectEqualDeep(previous.latest.?.value.validation, next.latest.?.previous.?.value.validation);
    const final = try f.build_input.execute(a, next);
    try std.testing.expectEqual(.semantic, try check_summary_reuse.execute(a, final, fixture.context()));
    try std.testing.expectError(error.InvalidReferenceReconciliation, reuse_summary.execute(a, final, fixture.context()));
    try @import("domain/reference_reconciliation_validation.zig").history(a, next);
}

test "summary reuse preserves model work for empty leaf multi-child and final partitions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "MOCK First.\n", "MOCK Second.\n", "MOCK Third.\n", "MOCK Fourth.\n", "MOCK Fifth.\n", "MOCK Sixth.\n", "MOCK Seventh.\n", "MOCK Eighth.\n", "MOCK Ninth.\n" });
    defer fixture.deinit();
    var progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    var cross_reuse = false;
    var global_reuse = false;
    var repeated_reuse = false;
    var multi_child = false;
    while (true) {
        const input = try f.build_input.execute(a, progress);
        const result = try check_summary_reuse.execute(a, input, fixture.context());
        if (input.purpose == .global) {
            try std.testing.expectEqual(.semantic, result);
            break;
        }
        const eligible = input.partition.group.children.len == 1;
        try std.testing.expectEqual(eligible, result == .reusable);
        if (result == .reusable) {
            cross_reuse = cross_reuse or input.partition.group.level == .cross_source;
            global_reuse = global_reuse or input.partition.group.level == .global;
            repeated_reuse = repeated_reuse or input.summaries[0].projection.carried_from != null;
        } else multi_child = multi_child or input.partition.group.children.len > 1;
        const parsed: r.Parsed = if (result == .reusable) try reuse_summary.execute(a, input, fixture.context()) else .{ .input = input, .proposal = .{ .summary = try f.summary(a, input) } };
        const checked = (try f.validate_summary.execute(a, parsed, fixture.context())).valid;
        progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
    }
    try std.testing.expect(cross_reuse and global_reuse and repeated_reuse and multi_child);
    try @import("domain/reference_reconciliation_validation.zig").history(a, progress);
    const empty = try prepare(a, &.{});
    defer empty.deinit();
    const empty_input = try f.build_input.execute(a, try f.initialize(a, empty.inputs, empty.extracted, 2));
    try std.testing.expectEqual(.semantic, try check_summary_reuse.execute(a, empty_input, empty.context()));
}

test "summary reuse rejects substituted child payloads and altered accepted history under unchanged IDs" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"MOCK Confirm the reservation.\n"});
    defer fixture.deinit();
    const input = try crossSourceSummaryInput(a, fixture);
    for ([_]bool{ false, true }) |alter_history| {
        var changed = input;
        const latest = try a.create(r.SummaryHistory);
        latest.* = input.progress.latest.?.*;
        const statements = try a.dupe(r.Statement, latest.value.statements);
        const originals = try a.dupe(r.ValidatedStatement, latest.value.projection.originals);
        statements[0].content = .{ .model = .{ .business = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Cancel the reservation." } }} } } } };
        originals[0].content = statements[0].content;
        latest.value.statements = statements;
        latest.value.projection.originals = originals;
        changed.summaries = try a.dupe(r.Summary, &.{latest.value});
        if (alter_history) changed.progress.latest = latest;
        try std.testing.expectError(error.InvalidReferenceReconciliation, reuse_summary.execute(a, changed, fixture.context()));
    }
}

test "summary reuse rejects changed source claim citation and passive evidence even when IDs match" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"MOCK Display `MOCK READY`.\n"});
    defer fixture.deinit();
    const input = try crossSourceSummaryInput(a, fixture);
    for (0..5) |change| {
        var current = input;
        var context = fixture.context();
        switch (change) {
            0 => {
                const sources = try a.dupe(r.evidence.Source, context.inputs.corpus.sources);
                const bytes = try a.dupe(u8, sources[0].bytes);
                bytes[0] = 'X';
                sources[0].bytes = bytes;
                context.inputs.corpus.sources = sources;
            },
            1 => {
                const items = try a.dupe(r.Item, current.items);
                items[0].claim.content = .{ .model = .{ .business = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "MOCK A different requirement." } }} } } } };
                current.items = items;
            },
            2 => {
                const entries = try a.dupe(r.Item, current.progress.plan.layout.items.entries);
                const citations = try a.dupe(r.extraction.Citation, entries[0].citations);
                citations[0].value.location.end.byte -= 1;
                entries[0].citations = citations;
                current.progress.plan.layout.items.entries = entries;
                current.items = entries;
            },
            3 => context.registry.records = &.{.{ .id = .{ .ordinal = 1 }, .kind = .display_filename, .value = "MOCK.txt" }},
            4 => current.partition.group.claim_ids = current.partition.group.claim_ids[1..],
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, reuse_summary.execute(a, current, context));
    }
    var stale_policy = fixture.context();
    stale_policy.registry.grammar.policy.rules = &.{};
    try std.testing.expectError(error.InvalidNamingPolicy, reuse_summary.execute(a, input, stale_policy));
    const other_text = try text.prepare(a, fixture.inputs);
    defer other_text.deinit();
    var stale_toolchain = fixture.context();
    stale_toolchain.current = text.safety.value(other_text.owner);
    try std.testing.expectError(error.StaleNamingPolicy, reuse_summary.execute(a, input, stale_toolchain));
}

test "native summary proposals are revalidated and corrupted native content cannot enter model repair" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"MOCK Display `MOCK READY`.\n"});
    defer fixture.deinit();
    const input = try crossSourceSummaryInput(a, fixture);
    const native = try reuse_summary.execute(a, input, fixture.context());
    for (0..8) |change| {
        var changed = native;
        const statements = try a.dupe(r.StatementProposal, native.proposal.summary.statements);
        changed.proposal.summary.statements = statements;
        switch (change) {
            0 => statements[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Different accepted-looking meaning." } }} } } },
            1 => changed.proposal.summary.statements = statements[1..],
            2 => statements[1].content.preserved_token.token_id.ordinal += 1,
            3 => statements[0].claim_ids = &.{.{ .ordinal = 999 }},
            4 => changed.source.origin = .{ .request = .{ .value = 9 }, .attempt = .{ .value = 1 } },
            5 => changed.source.revision += 1,
            6 => changed.carried_from.?.ordinal += 1,
            7 => changed.phase = .signals,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_summary.execute(a, changed, fixture.context()));
    }
}

test "native summary parent starts a native source while retaining repaired child receipts in history" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"MOCK Record the inspection.\n"});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 8));
    const good = try f.summary(a, input);
    const statements = try a.dupe(r.StatementProposal, good.statements);
    statements[0].content.model.business.segments = &.{.{ .literal = .{ .value = "MOCK\x01invalid" } }};
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .summary = .{ .statements = statements } } };
    const rejection = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
    const auth = (try repair.authorize(a, parsed, fixture.context(), rejection)).model;
    const repaired = try repair.merge(a, parsed, fixture.context(), auth, .{ .content = good.statements[0].content }, null);
    const checked = (try f.validate_summary.execute(a, repaired, fixture.context())).valid;
    const previous = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
    try std.testing.expect(previous.latest.?.value.projection.source.pending_repair != null);
    const native = try reuse_summary.execute(a, try f.build_input.execute(a, previous), fixture.context());
    try std.testing.expectEqualDeep(r.diagnostic.Source{}, native.source);
    const parent = try f.build_summary.execute(a, try f.assign_summary.execute(a, (try f.validate_summary.execute(a, native, fixture.context())).valid));
    try std.testing.expectEqualDeep(repaired.source, parent.latest.?.previous.?.value.projection.source);
    try std.testing.expectEqualDeep(r.diagnostic.Source{}, parent.latest.?.value.projection.source);
}

test "native reuse binding retains its child after the preceding pipeline value is released" {
    const owned = @import("domain/reference_candidate_value.zig");
    const native = @import("application/reference_extraction_workflow.zig");
    const workflow = @import("application/reference_reconciliation_workflow.zig");
    const values = @import("application/pipeline_values.zig");
    const inputs_schema = @import("application/reference_evidence_workflow.zig").inputs_schema;
    const registry_schema = @import("application/passive_literal_workflow.zig").registry_schema;
    const toolchain_schema = @import("application/toolchain_workflow_values.zig").valid;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const fixture = try prepare(arena.allocator(), &.{"MOCK Complete the inspection.\n"});
    var transferred = false;
    defer if (!transferred) fixture.deinit();
    const current = try values.adopt(std.testing.allocator, toolchain_schema, text.safety.ValidToolchain, text.safety.Owner, fixture.text.owner, text.safety.value, text.safety.deinitOwner, text.safety.retainedBytes(fixture.text.owner));
    transferred = true;
    defer values.destroy(current);
    const inputs = try values.create(std.testing.allocator, inputs_schema, r.evidence.Inputs, fixture.inputs);
    defer values.destroy(inputs);
    const registry = try values.create(std.testing.allocator, registry_schema, text.literals.Registry, fixture.text.registry);
    defer values.destroy(registry);
    const captured = capture: {
        const owner = try owned.create(std.testing.allocator, null);
        errdefer owned.destroy(owner);
        owner.payload = .{ .reconciliation_input = try crossSourceSummaryInput(owner.arena.allocator(), fixture) };
        break :capture try native.publish(std.testing.allocator, workflow.input_schema, owner, .ok);
    };
    const prior = captured.delta.data_writes[@intFromEnum(workflow.input_schema.key)].?;
    const carried = carry: {
        defer values.destroy(prior);
        var view: @import("domain/pipeline_data.zig").View = .{};
        view.slots[@intFromEnum(workflow.input_schema.key)] = prior;
        view.slots[@intFromEnum(inputs_schema.key)] = inputs;
        view.slots[@intFromEnum(registry_schema.key)] = registry;
        view.slots[@intFromEnum(toolchain_schema.key)] = current;
        const contract = workflow.ReuseSummary.Action.contract;
        const step: @import("domain/workflow_compilation.zig").CompiledStep = .{ .id = .{ .bytes = "reuse-summary" }, .operation_id = .{ .bytes = contract.id }, .parameters = &.{}, .requires = contract.requires, .produces = contract.produces, .replaces = contract.replaces, .invalidates = contract.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
        var binding: workflow.ReuseSummary = .{ .allocator = std.testing.allocator, .action = reuse_summary };
        break :carry try workflow.ReuseSummary.invoke(&binding, .{ .step = .{ .data = view, .step = &step, .resources = &.{}, .model_binding = null, .log = .init(try @import("domain/telemetry.zig").WorkflowShortcode.parse("SGEN")) } });
    };
    try std.testing.expectEqual(.ok, carried.outcome);
    const retained = carried.delta.data_writes[@intFromEnum(workflow.parsed_schema.key)].?;
    defer values.destroy(retained);
    const parsed = (try native.read(&.{ .slots = carried.delta.data_writes }, workflow.parsed_schema, .reconciliation_parsed)).payload().reconciliation_parsed;
    try std.testing.expectEqualDeep(parsed.input.summaries[0].id, parsed.carried_from.?);
    const checked = (try f.validate_summary.execute(arena.allocator(), parsed, fixture.context())).valid;
    try std.testing.expectEqualDeep(parsed.input.summaries[0].statements[0].content, checked.statements[0].content);
    try std.testing.expectEqual(@as(usize, 1), parsed.input.progress.latest.?.value.projection.originals.len);
}

test "summary normalization preserves occurrence provenance and distinct source literals" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, summaryNormalizationCase, .{});
}

fn summaryNormalizationCase(allocator: std.mem.Allocator) !void {
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const first: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    const second: Origin = .{ .request = .{ .value = 4 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "MOCK Display `MOCK READY`.\n", "MOCK Display `MOCK READY`.\n" });
    defer fixture.deinit();
    const input = try crossSourceSummaryInput(a, fixture);
    const good = try f.summary(a, input);
    try std.testing.expectEqual(@as(usize, 4), good.statements.len);
    const statements = try a.alloc(r.StatementProposal, 7);
    @memcpy(statements[0..4], good.statements);
    statements[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Confirm the operation." } }} } } };
    statements[4] = .{ .claim_ids = &.{ good.statements[0].claim_ids[0], good.statements[2].claim_ids[0] }, .content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Confirm both operations." } }} } } } };
    statements[5] = statements[4];
    statements[5].claim_ids = &.{ good.statements[2].claim_ids[0], good.statements[0].claim_ids[0] };
    statements[6] = statements[0];
    statements[6].content = .{ .model = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "MOCK Confirm " } }, .{ .literal = .{ .value = "the operation." } } } } } };
    const parsed: r.Parsed = .{ .input = input, .source = .{
        .revision = 7,
        .origin = first,
        .fields = &.{.{ .unit = .{ .statement = 6 }, .field = .content, .origin = second }},
        .statements = .{ .values = &.{ .{ .ordinal = 11 }, .{ .ordinal = 12 }, .{ .ordinal = 13 }, .{ .ordinal = 14 }, .{ .ordinal = 15 }, .{ .ordinal = 16 }, .{ .ordinal = 17 } }, .next_ordinal = 18 },
    }, .proposal = .{ .summary = .{ .statements = statements } } };
    const before = try std.json.Stringify.valueAlloc(a, parsed.proposal, .{});
    const checked = (try f.validate_summary.execute(a, parsed, fixture.context())).valid;
    try std.testing.expectEqual(@as(usize, 5), checked.statements.len);
    try std.testing.expectEqualDeep(&[_]usize{ 0, 1, 2, 3, 4, 4, 0 }, checked.projection.statement_indices);
    try std.testing.expectEqualDeep(parsed.source, checked.projection.source);
    try std.testing.expectEqualDeep(first, checked.projection.source.at(.{ .statement = 0 }, .content).?);
    try std.testing.expectEqualDeep(second, checked.projection.source.at(.{ .statement = 6 }, .content).?);
    try std.testing.expectEqual(@as(u32, 17), (try checked.projection.source.statements.at(6, checked.projection.originals.len)).ordinal);
    try std.testing.expectEqualDeep(statements[4].claim_ids, checked.statements[4].claim_ids);
    try std.testing.expect(checked.statements[1].content.preserved_token.token_id.ordinal != checked.statements[3].content.preserved_token.token_id.ordinal);
    try std.testing.expectEqualStrings(before, try std.json.Stringify.valueAlloc(a, parsed.proposal, .{}));
    try std.testing.expectEqualDeep(checked, (try f.validate_summary.execute(a, parsed, fixture.context())).valid);

    // Reapplying normalization to its retained statements changes no value.
    var normalized = parsed;
    normalized.source = .{};
    normalized.proposal.summary.statements = statements[0..5];
    const again = (try f.validate_summary.execute(a, normalized, fixture.context())).valid;
    try std.testing.expectEqualDeep(checked.statements, again.statements);
    try std.testing.expectEqualDeep(&[_]usize{ 0, 1, 2, 3, 4 }, again.projection.statement_indices);
    const progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
    try std.testing.expectEqualDeep(checked.projection, progress.latest.?.value.projection);
    try std.testing.expectEqual(input.progress.next_statement_ordinal + 5, progress.next_statement_ordinal);
    const final = try f.summaries(a, progress, fixture.context());
    const packet = try @import("domain/reference_model_input.zig").reconciliationPacket(allocator, final, fixture.inputs, fixture.text.registry, .all);
    defer @import("domain/model_input_packet.zig").release(packet);
    const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    const supplied_summaries = body.value.object.get("summaries").?.array.items;
    try std.testing.expectEqual(@as(usize, 1), supplied_summaries.len);
    const supplied = supplied_summaries[0].object;
    try std.testing.expectEqual(@as(usize, 5), supplied.get("statements").?.array.items.len);
    for ([_][]const u8{ "projection", "originals", "statement_indices", "source" }) |native_field|
        try std.testing.expect(!supplied.contains(native_field));
    _ = (try f.finish(a, final, try globalWithoutSpecRoles(a, final), fixture.context())).valid;
}

test "summary admission validates every repeated occurrence before normalization" {
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"MOCK Display `MOCK READY`.\n"});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 8));
    const good = try f.summary(a, input);
    for (0..5) |scenario| {
        const statements = try a.alloc(r.StatementProposal, good.statements.len + 1);
        @memcpy(statements[0..good.statements.len], good.statements);
        const last = statements.len - 1;
        statements[last] = statements[0];
        switch (scenario) {
            0 => statements[last].claim_ids = &.{},
            1 => statements[last].claim_ids = &.{.{ .ordinal = 999 }},
            2 => statements[last].claim_ids = &.{ statements[0].claim_ids[0], statements[0].claim_ids[0] },
            3 => statements[last].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Invalid\x01text" } }} } } },
            4 => statements[last].content = statements[1].content,
            else => unreachable,
        }
        const parsed: r.Parsed = .{ .input = input, .source = .{ .fields = &.{.{ .unit = .{ .statement = last }, .field = .record, .origin = origin }} }, .proposal = .{ .summary = .{ .statements = statements } } };
        const rejected = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
        try std.testing.expectEqualDeep(r.diagnostic.Unit{ .statement = last }, rejected.unit);
        try std.testing.expectEqualDeep(origin, rejected.origin.?);
        try std.testing.expectEqual(([_]r.diagnostic.Rule{ .claim_selection, .claim_selection, .claim_selection, .typed_text, .content })[scenario], rejected.issue.rule);
        try std.testing.expectEqual(statements.len, parsed.proposal.summary.statements.len);
    }
}

test "summary normalization retains repair occurrence identity and inserts missing coverage before collapsing repeats" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 6 }, .attempt = .{ .value = 1 } };
    const correction: Origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 1 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "MOCK Confirm the reservation.\n", "MOCK Issue the receipt.\n" });
    defer fixture.deinit();
    const input = try crossSourceSummaryInput(a, fixture);
    const good = try f.summary(a, input);
    const statements = try a.dupe(r.StatementProposal, &.{ good.statements[0], good.statements[0], good.statements[1] });
    var parsed: r.Parsed = .{ .input = input, .source = .{ .origin = origin, .statements = .{ .values = &.{ .{ .ordinal = 4 }, .{ .ordinal = 8 }, .{ .ordinal = 10 } }, .next_ordinal = 11 } }, .proposal = .{ .summary = .{ .statements = statements } } };
    const checked = (try f.validate_summary.execute(a, parsed, fixture.context())).valid;
    try std.testing.expectEqualDeep(&[_]usize{ 0, 0, 1 }, checked.projection.statement_indices);
    statements[1].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Invalid\x01text" } }} } } };
    const rejected = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
    const authorization = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
    const merged = try repair.merge(a, parsed, fixture.context(), authorization, .{ .content = good.statements[0].content }, correction);
    const repaired = (try f.validate_summary.execute(a, merged, fixture.context())).valid;
    try std.testing.expectEqualDeep(&[_]usize{ 0, 0, 1 }, repaired.projection.statement_indices);
    try std.testing.expectEqual(@as(u32, 8), (try repaired.projection.source.statements.at(1, repaired.projection.originals.len)).ordinal);
    try std.testing.expectEqualDeep(correction, repaired.projection.source.at(.{ .statement = 1 }, .content).?);
    try std.testing.expectEqualDeep(origin, repaired.projection.source.at(.{ .statement = 0 }, .content).?);
    try std.testing.expectEqual(parsed.source.revision + 1, repaired.projection.source.revision);
    try std.testing.expect(merged.source.pending_repair != null);
    try std.testing.expect(merged.source.last_repair != null);
    try std.testing.expectEqualDeep(merged.source.pending_repair, repaired.projection.source.pending_repair);
    try std.testing.expectEqualDeep(merged.source.last_repair, repaired.projection.source.last_repair);
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, merged, fixture.context(), authorization, .{ .content = good.statements[0].content }, correction));

    parsed = .{ .input = input, .proposal = .{ .summary = .{ .statements = &.{ good.statements[0], good.statements[0] } } } };
    const missing = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
    try std.testing.expectEqual(.membership, missing.issue.rule);
    const insertion = (try repair.authorize(a, parsed, fixture.context(), missing)).model;
    try std.testing.expect(insertion.operation == .insert);
    const filled = try repair.merge(a, parsed, fixture.context(), insertion, .{ .content = good.statements[1].content }, correction);
    try std.testing.expectEqual(@as(usize, 3), filled.proposal.summary.statements.len);
    try std.testing.expectEqual(@as(u64, 2), filled.source.revision);
    const normalized = (try f.validate_summary.execute(a, filled, fixture.context())).valid;
    try std.testing.expectEqualDeep(&[_]usize{ 0, 0, 1 }, normalized.projection.statement_indices);
    try std.testing.expectEqualDeep(parsed.proposal.summary.statements, filled.proposal.summary.statements[0..2]);
}

test "summary history rejects corrupted normalization maps and invalid per-statement coverage" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "MOCK Confirm the reservation.\n", "MOCK Issue the receipt.\n" });
    defer fixture.deinit();
    const input = try crossSourceSummaryInput(a, fixture);
    const good = try f.summary(a, input);
    const checked = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = .{ .statements = &.{ good.statements[0], good.statements[0], good.statements[1] } } } }, fixture.context())).valid;
    const progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
    for (0..9) |scenario| {
        var changed = progress;
        const latest = try a.create(r.SummaryHistory);
        latest.* = progress.latest.?.*;
        changed.latest = latest;
        const statements = try a.dupe(r.Statement, latest.value.statements);
        latest.value.statements = statements;
        const indices = try a.dupe(usize, latest.value.projection.statement_indices);
        latest.value.projection.statement_indices = indices;
        switch (scenario) {
            0 => indices[1] = statements.len,
            1 => indices[1] = 1,
            2 => latest.value.projection.originals = latest.value.projection.originals[1..],
            3 => latest.value.projection.source.revision = 0,
            4 => statements[0].claim_ids = &.{ statements[0].claim_ids[0], statements[0].claim_ids[0] },
            5 => statements[0].claim_ids = &.{.{ .ordinal = 999 }},
            6 => statements[1].claim_ids = statements[0].claim_ids,
            7 => statements[0].content = .{ .model = .{ .business = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Changed the retained meaning." } }} } } } },
            8 => latest.value.projection.source.statements = .{ .values = &.{ .{ .ordinal = 5 }, .{ .ordinal = 5 }, .{ .ordinal = 6 } }, .next_ordinal = 7 },
            else => unreachable,
        }
        const changed_input = try f.build_input.execute(a, changed);
        try std.testing.expectError(error.InvalidReferenceReconciliation, @import("domain/reference_reconciliation_validation.zig").input(a, changed_input));
    }
}

test "overlapping repeated summaries normalize once without changing coverage repair revision or occurrences" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const requirements = [_][]const u8{ "MOCK Open the inspection.\n", "MOCK Record the measurement.\n", "MOCK Close the inspection.\n" };
    var fixture = try prepare(a, &requirements);
    defer fixture.deinit();
    const claims = try a.dupe(r.extraction.Claim, fixture.extracted.ledger.claims);
    try std.testing.expectEqual(requirements.len, claims.len);
    for (claims, requirements) |*claim, requirement| {
        claim.content = .{ .model = .{ .business = .{ .value = .{ .segments = try a.dupe(r.text.BusinessSegment, &.{.{ .literal = .{ .value = std.mem.trimEnd(u8, requirement, "\n") } }}) } } } };
    }
    fixture.extracted.ledger.claims = claims;
    const input = try crossSourceSummaryInput(a, fixture);
    const good = try f.summary(a, input);
    const aggregate: r.StatementProposal = .{ .claim_ids = input.partition.group.claim_ids, .content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Open the inspection, record the measurement, and close the inspection." } }} } } } };
    for ([_]usize{ 1, 91 }) |count| {
        const statements = try a.alloc(r.StatementProposal, count);
        statements[0] = aggregate;
        for (statements[1..], 0..) |*statement, index| statement.* = good.statements[index % good.statements.len];
        const parsed: r.Parsed = .{ .input = input, .proposal = .{ .summary = .{ .statements = statements } } };
        const checked = (try f.validate_summary.execute(a, parsed, fixture.context())).valid;
        const retained: usize = if (count == 1) 1 else 4;
        try std.testing.expectEqual(retained, checked.statements.len);
        try std.testing.expectEqual(count, checked.projection.originals.len);
        try std.testing.expectEqualDeep(parsed.source, checked.projection.source);
        for (checked.projection.statement_indices, 0..) |index, original| {
            try std.testing.expectEqual(if (original == 0) @as(usize, 0) else 1 + (original - 1) % 3, index);
            try std.testing.expectEqual(original + 1, (try checked.projection.source.statements.at(original, count)).ordinal);
        }
        const progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, checked));
        try std.testing.expectEqual(input.progress.next_statement_ordinal + retained, progress.next_statement_ordinal);
        try std.testing.expectEqualDeep(input.partition.group.claim_ids, progress.latest.?.value.member_claim_ids);
        const final = try f.summaries(a, progress, fixture.context());
        try std.testing.expectEqual(.complete, (try f.finish(a, final, try globalWithoutSpecRoles(a, final), fixture.context())).valid.outcome);
    }
}

test "partition validation binds native iteration to the actual non-final population" {
    const owned = @import("domain/reference_candidate_value.zig");
    const native = @import("application/reference_extraction_workflow.zig");
    const workflow = @import("application/reference_reconciliation_workflow.zig");
    const values = @import("application/pipeline_values.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const []const u8{ &.{}, &.{"MOCK Confirm the decision.\n"}, &.{ "MOCK Inspect the sample.\n", "MOCK Record the result.\n" } }) |sources| {
        const fixture = try prepare(a, sources);
        defer fixture.deinit();
        const expected = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const plan_value = plan: {
            const owner = try owned.create(std.testing.allocator, null);
            errdefer owned.destroy(owner);
            owner.payload = .{ .reconciliation_plan = expected.plan };
            break :plan try values.adopt(std.testing.allocator, workflow.plan_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
        };
        defer values.destroy(plan_value);
        var view: @import("domain/pipeline_data.zig").View = .{};
        view.slots[@intFromEnum(workflow.plan_schema.key)] = plan_value;
        const contract = workflow.ValidatePartitions.Action.contract;
        const step: @import("domain/workflow_compilation.zig").CompiledStep = .{ .id = .{ .bytes = "validate-partitions" }, .operation_id = .{ .bytes = contract.id }, .parameters = &.{}, .requires = contract.requires, .produces = contract.produces, .replaces = contract.replaces, .invalidates = contract.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
        var binding: workflow.ValidatePartitions = .{ .allocator = std.testing.allocator };
        const initialized = try workflow.ValidatePartitions.invoke(&binding, .{ .step = .{ .data = view, .step = &step, .resources = &.{}, .model_binding = null, .log = .init(try @import("domain/telemetry.zig").WorkflowShortcode.parse("SGEN")) } });
        const progress_value = initialized.delta.data_writes[@intFromEnum(workflow.progress_schema.key)].?;
        defer values.destroy(progress_value);
        view.slots[@intFromEnum(workflow.progress_schema.key)] = progress_value;
        try std.testing.expectEqualDeep(@import("domain/workflow_iteration.zig").Transition{ .limit = expected.plan.partitions.len - 1, .before = 0, .after = 0 }, initialized.iteration.?);
        try std.testing.expect(std.meta.eql(expected, (try native.read(&view, workflow.progress_schema, .reconciliation_progress)).payload().reconciliation_progress));
    }
    try std.testing.expect(!@hasDecl(workflow.ReuseSummary, "retry_limit"));
    try std.testing.expect(!@hasDecl(workflow.ReuseSummary, "parameters"));
}

test "summary binding requires current progress and retains normalization evidence after input release" {
    const owned = @import("domain/reference_candidate_value.zig");
    const native = @import("application/reference_extraction_workflow.zig");
    const workflow = @import("application/reference_reconciliation_workflow.zig");
    const values = @import("application/pipeline_values.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"MOCK Confirm the decision.\n"});
    defer fixture.deinit();
    const input = try f.build_input.execute(a, try f.initialize(a, fixture.inputs, fixture.extracted, 8));
    const captured = capture: {
        const owner = try owned.create(std.testing.allocator, null);
        errdefer owned.destroy(owner);
        const pa = owner.arena.allocator();
        const good = try f.summary(pa, input);
        const statements = try pa.dupe(r.StatementProposal, &.{ good.statements[0], good.statements[0] });
        const fields = try pa.dupe(r.diagnostic.FieldOrigin, &.{.{ .unit = .{ .statement = 1 }, .field = .content, .origin = .{ .request = .{ .value = 9 }, .attempt = .{ .value = 2 } } }});
        const checked = (try f.validate_summary.execute(pa, .{ .input = input, .source = .{ .fields = fields }, .proposal = .{ .summary = .{ .statements = statements } } }, fixture.context())).valid;
        owner.payload = .{ .reconciliation_summary_ids = try f.assign_summary.execute(pa, checked) };
        break :capture try native.publish(std.testing.allocator, workflow.summary_ids_schema, owner, .ok);
    };
    const prior = captured.delta.data_writes[@intFromEnum(workflow.summary_ids_schema.key)].?;
    const built = build: {
        defer values.destroy(prior);
        var view: @import("domain/pipeline_data.zig").View = .{};
        view.slots[@intFromEnum(workflow.summary_ids_schema.key)] = prior;
        const plan_value = plan: {
            const owner = try owned.create(std.testing.allocator, null);
            errdefer owned.destroy(owner);
            owner.payload = .{ .reconciliation_plan = input.progress.plan };
            break :plan try values.adopt(std.testing.allocator, workflow.plan_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
        };
        defer values.destroy(plan_value);
        view.slots[@intFromEnum(workflow.plan_schema.key)] = plan_value;
        const contract = workflow.BuildSummary.Action.contract;
        const step: @import("domain/workflow_compilation.zig").CompiledStep = .{ .id = .{ .bytes = "build-summary" }, .operation_id = .{ .bytes = contract.id }, .parameters = &.{}, .requires = contract.requires, .produces = contract.produces, .replaces = contract.replaces, .invalidates = contract.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
        var binding: workflow.BuildSummary = .{ .allocator = std.testing.allocator };
        for (0..4) |scenario| {
            var current = input.progress;
            switch (scenario) {
                0 => current.plan.partitions = try a.dupe(r.Partition, current.plan.partitions),
                1 => current.summary_count += 1,
                2 => current.next_statement_ordinal += 1,
                3 => {},
                else => unreachable,
            }
            const progress_value = progress: {
                const owner = try owned.create(std.testing.allocator, null);
                errdefer owned.destroy(owner);
                owner.payload = .{ .reconciliation_progress = current };
                break :progress try values.adopt(std.testing.allocator, workflow.progress_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
            };
            defer values.destroy(progress_value);
            view.slots[@intFromEnum(workflow.progress_schema.key)] = progress_value;
            const invoked = workflow.BuildSummary.invoke(&binding, .{ .step = .{ .data = view, .step = &step, .resources = &.{}, .model_binding = null, .log = .init(try @import("domain/telemetry.zig").WorkflowShortcode.parse("SGEN")) } });
            if (scenario == 3) break :build try invoked;
            try std.testing.expectError(error.InvalidReferenceReconciliation, invoked);
        }
        unreachable;
    };
    try std.testing.expectEqualDeep(@import("domain/workflow_iteration.zig").Transition{ .limit = input.progress.plan.partitions.len - 1, .before = 0, .after = 1 }, built.iteration.?);
    const retained = built.delta.data_replacements[@intFromEnum(workflow.progress_schema.key)].?;
    defer values.destroy(retained);
    var view: @import("domain/pipeline_data.zig").View = .{};
    view.slots[@intFromEnum(workflow.progress_schema.key)] = retained;
    const progress = (try native.read(&view, workflow.progress_schema, .reconciliation_progress)).payload().reconciliation_progress;
    const projection = progress.latest.?.value.projection;
    try std.testing.expectEqualDeep(&[_]usize{ 0, 0 }, projection.statement_indices);
    try std.testing.expectEqual(@as(usize, 2), projection.originals.len);
    try std.testing.expectEqual(@as(u64, 9), projection.source.at(.{ .statement = 1 }, .content).?.request.value);
    const next = try f.build_input.execute(a, progress);
    try @import("domain/reference_reconciliation_validation.zig").input(a, next);
}

test "atomic reconciliation insertion normalization and packet construction release allocation failures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm a reservation.\n", "Issue a receipt.\n", "Notify the visitor.\n" });
    defer fixture.deinit();
    const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    const input = try f.build_input.execute(a, progress);
    const good = try f.summary(a, input);
    var missing = good;
    missing.statements = good.statements[1..];
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .summary = missing } };
    const rejection = (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, reconciliationRepairAllocation, .{ parsed, fixture.context(), rejection, good.statements[0].content });
}
fn reconciliationRepairAllocation(allocator: std.mem.Allocator, parsed: r.Parsed, context: f.Context, rejection: r.diagnostic.Rejection, content: r.ContentProposal) !void {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const authorization = (try repair.authorize(a, parsed, context, rejection)).model;
    const packet = try repair.packet(allocator, parsed, context, authorization);
    defer @import("domain/model_input_packet.zig").release(packet);
    const replacement: repair.Replacement = .{ .content = content };
    const wire = try f.repairResponse(a, replacement);
    const merged = try repair.merge(a, parsed, context, authorization, try repair.parse(a, authorization, packet, wire), null);
    _ = (try f.validate_summary.execute(a, merged, context)).valid;
    const duplicate = try a.alloc(r.StatementProposal, merged.proposal.summary.statements.len + 1);
    @memcpy(duplicate[0 .. duplicate.len - 1], merged.proposal.summary.statements);
    duplicate[duplicate.len - 1] = duplicate[0];
    var redundant = merged;
    redundant.source.statements = try merged.source.statements.inserting(a, merged.proposal.summary.statements.len, merged.proposal.summary.statements.len);
    redundant.proposal.summary.statements = duplicate;
    const normalized = (try f.validate_summary.execute(a, redundant, context)).valid;
    try std.testing.expectEqual(merged.proposal.summary.statements.len, normalized.statements.len);
    try std.testing.expectEqualDeep(parsed.proposal.summary.statements, merged.proposal.summary.statements[0..parsed.proposal.summary.statements.len]);
}

test "mixed claim kinds choose independent selection repair across summaries and signals" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        for ([_]bool{ false, true }) |global| {
            const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
            const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
            const business = input.items[0].claim.id;
            const token = input.items[1].claim.id;
            var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try globalWithoutSpecRoles(a, input) } else .{ .summary = try f.summary(a, input) } };
            if (global) {
                const values = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
                values[0].claim_ids = &.{ business, token };
                parsed.proposal.global.signals = values;
            } else {
                const values = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
                values[0].claim_ids = &.{ business, token };
                parsed.proposal.summary.statements = values[0..1]; // token must be inserted after selection repair
            }
            const rejected = if (global) (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).invalid else (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
            try std.testing.expectEqual(.content, rejected.issue.rule);
            try std.testing.expect(rejected.relations.content == null);
            try std.testing.expectEqualDeep(&[_]r.ClaimId{business}, rejected.relations.selection);
            const authorization = (try repair.authorize(a, parsed, fixture.context(), rejected)).model;
            try std.testing.expectEqual(@as(usize, 0), if (global) authorization.target.signal_selection else authorization.target.statement_selection);
            const packet = try repair.packet(a, parsed, fixture.context(), authorization);
            defer packets.release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const choices = body.value.object.get("repair").?.object.get("rule").?.object;
            try std.testing.expectEqual(@as(i64, business.ordinal), choices.get("selection").?.array.items[0].integer);
            const repair_input = body.value.object.get("input").?.object;
            try std.testing.expectEqual(!global, repair_input.contains("summary_purpose"));
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Together, the statements must cover every assigned claim ID") == null);
            const constraints = repair_input.get("constraints").?.array.items;
            var selection_rule = false;
            for (constraints) |constraint| {
                const name = constraint.object.get("constraint").?.string;
                selection_rule = selection_rule or std.mem.eql(u8, name, "nonempty_unique_allowed_claims");
                if (std.mem.eql(u8, name, "nonempty_unique_allowed_claims")) try std.testing.expect(std.mem.indexOf(u8, constraint.object.get("requirement").?.string, "repair.rule.selection") != null);
                try std.testing.expect(!std.mem.eql(u8, name, "matching_claim_content"));
                try std.testing.expect(!std.mem.eql(u8, name, "exact_selected_token"));
            }
            try std.testing.expect(selection_rule);
            const wire = try std.fmt.allocPrint(a, "{{\"claim_ids\":[{d}]}}", .{business.ordinal});
            var merged = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, wire), null);
            if (global) {
                try std.testing.expectEqualDeep(parsed.proposal.global.signals[0].content, merged.proposal.global.signals[0].content);
                try std.testing.expectEqualDeep(parsed.proposal.global.signals[1..], merged.proposal.global.signals[1..]);
                try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions, merged.proposal.global.claim_dispositions);
                _ = (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid;
            } else {
                const missing = (try f.validate_summary.execute(a, merged, fixture.context())).invalid;
                try std.testing.expectEqual(.membership, missing.issue.rule);
                const insertion = (try repair.authorize(a, merged, fixture.context(), missing)).automatic;
                merged = try repair.merge(a, merged, fixture.context(), insertion.authorization, insertion.replacement, null);
                try std.testing.expectEqualDeep(parsed.proposal.summary.statements[0].content, merged.proposal.summary.statements[0].content);
                _ = (try f.validate_summary.execute(a, merged, fixture.context())).valid;
            }
            // The exact old snapshot remains mandatory even for an equivalent edit.
            try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, merged, fixture.context(), authorization, .{ .selection = .{ .claim_ids = &.{business} } }, null));
            if (!global) {
                var changed_lineage = parsed;
                changed_lineage.carried_from = .{ .ordinal = 1 };
                try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, changed_lineage, fixture.context(), rejected));
                try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, changed_lineage, fixture.context(), authorization, .{ .selection = .{ .claim_ids = &.{business} } }, null));
            }
            var changed_purpose = parsed;
            changed_purpose.input.purpose = if (global) .summary else .global;
            try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, changed_purpose, fixture.context(), authorization));
            var context = fixture.context();
            const names = try a.dupe(@import("domain/path_token_grammar.zig").ReferenceName, context.registry.grammar.reference_names);
            names[0].basename = "different.md";
            context.registry.grammar.reference_names = names;
            try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, parsed, context, rejected));
            try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, context, authorization));
        }
    }
}

test "projection compatibility handles model kinds and indivisible exact tokens without a solver" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Show `Receipt issued!` and `Renewal accepted!`.\n"});
    defer fixture.deinit();
    for ([_]bool{ false, true }) |global| for (0..5) |scenario| {
        var progress = try f.initialize(a, fixture.inputs, fixture.extracted, 8);
        const entries = try a.dupe(r.Item, progress.plan.layout.items.entries);
        try std.testing.expectEqual(@as(usize, 3), entries.len);
        if (scenario == 1) entries[2].claim.content = .{ .model = .{ .scope_guard = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Eligible loans only." } }} } } } };
        progress.plan.layout.items.entries = entries;
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try globalWithoutSpecRoles(a, input) } else .{ .summary = try f.summary(a, input) } };
        const index: usize = if (scenario == 0 or scenario == 3) 1 else 0;
        const original = if (global) parsed.proposal.global.signals[index] else r.SignalProposal{ .claim_ids = parsed.proposal.summary.statements[index].claim_ids, .content = parsed.proposal.summary.statements[index].content };
        var invalid = original;
        switch (scenario) {
            0 => invalid.claim_ids = &.{ entries[1].claim.id, entries[2].claim.id },
            1 => invalid.claim_ids = &.{ entries[0].claim.id, entries[2].claim.id },
            2 => invalid.content = .{ .model = .{ .scope_guard = .{ .segments = &.{.{ .literal = .{ .value = "Only eligible renewals are allowed." } }} } } },
            3 => invalid.content = .{ .preserved_token = .{ .token_id = .{ .ordinal = 999 } } },
            4 => invalid.content = .{ .preserved_token = .{ .token_id = entries[1].claim.content.preserved_token.value.id } },
            else => unreachable,
        }
        if (global) {
            const values = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
            values[index] = invalid;
            parsed.proposal.global.signals = values;
        } else {
            const values = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
            values[index].claim_ids = invalid.claim_ids;
            values[index].content = invalid.content;
            parsed.proposal.summary.statements = values;
        }
        const rejected = if (global) (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).invalid else (try f.validate_summary.execute(a, parsed, fixture.context())).invalid;
        if (scenario == 4) try std.testing.expectEqual(.matching_claim_content, rejected.issue.expected.constraint);
        const decision = try repair.authorize(a, parsed, fixture.context(), rejected);
        const auth = if (decision == .automatic) decision.automatic.authorization else decision.model;
        if (scenario < 2) {
            try std.testing.expectEqual(index, if (global) auth.target.signal_selection else auth.target.statement_selection);
            try std.testing.expect(rejected.relations.content == null);
        } else {
            try std.testing.expectEqual(index, if (global) auth.target.signal_content else auth.target.statement_content);
            try std.testing.expect(rejected.relations.content != null);
        }
        const replacement: repair.Replacement = if (scenario < 2) .{ .selection = .{ .claim_ids = original.claim_ids } } else .{ .content = original.content };
        const merged = if (decision == .automatic) automatic: {
            try std.testing.expectEqualDeep(replacement, decision.automatic.replacement.?);
            try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, fixture.context(), auth));
            break :automatic try repair.merge(a, parsed, fixture.context(), auth, decision.automatic.replacement, null);
        } else model: {
            const packet = try repair.packet(a, parsed, fixture.context(), auth);
            defer @import("domain/model_input_packet.zig").release(packet);
            break :model try repair.merge(a, parsed, fixture.context(), auth, try repair.parse(a, auth, packet, try f.repairResponse(a, replacement)), null);
        };
        if (global) _ = (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid else _ = (try f.validate_summary.execute(a, merged, fixture.context())).valid;
    };
}

test "empty relationship choices block before model dispatch and genuine conflicts survive canonical deduplication" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Renew the loan.\n", "Reject the renewal.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const good = try globalWithoutSpecRoles(a, input);
    var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = good } };
    parsed.proposal.global.conflicts = &.{.{ .claim_ids = input.partition.group.claim_ids, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "Outcomes differ." } }} } }};
    const retained = (try f.validate_dispositions.execute(a, parsed)).valid;
    const rejected_conflict = (try f.validate_conflicts.execute(a, (try f.validate_signals.execute(a, retained, fixture.context())).valid, fixture.context())).invalid;
    try std.testing.expectEqual(@as(usize, 0), rejected_conflict.relations.conflicting_pairs.len);
    try std.testing.expectEqual(.no_independent_target, (try repair.authorize(a, parsed, fixture.context(), rejected_conflict)).blocked);
    const dispositions = try a.dupe(r.ClaimDispositionProposal, good.claim_dispositions);
    dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[1].claim_id} } };
    dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
    parsed.proposal.global.claim_dispositions = dispositions;
    const rejected_signal = (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).invalid;
    try std.testing.expectEqual(@as(usize, 0), rejected_signal.relations.selection.len);
    try std.testing.expectEqual(.no_independent_target, (try repair.authorize(a, parsed, fixture.context(), rejected_signal)).blocked);
    parsed.proposal.global.signals = &.{};
    const conflicts = try a.dupe(r.ConflictProposal, &.{ parsed.proposal.global.conflicts[0], parsed.proposal.global.conflicts[0] });
    conflicts[1].summary = .{ .nodes = &.{ .{ .literal = .{ .value = "Outcomes " } }, .{ .literal = .{ .value = "differ." } } } };
    parsed.proposal.global.conflicts = conflicts;
    const duplicate = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
    const removal = (try repair.authorize(a, parsed, fixture.context(), duplicate)).automatic;
    const merged = try repair.merge(a, parsed, fixture.context(), removal.authorization, null, null);
    try std.testing.expectEqual(.blocked, (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid.outcome);
    conflicts[1].summary = .{ .nodes = &.{.{ .literal = .{ .value = "Eligibility differs." } }} };
    const competing = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
    try std.testing.expectEqual(.competing_entries, (try repair.authorize(a, parsed, fixture.context(), competing)).blocked);
}

test "canonical summary redundancy normalizes while signal redundancy retains repair authority" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Confirm a renewal.\n", "Display a receipt.\n" });
    defer fixture.deinit();
    for ([_]bool{ false, true }) |global| {
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try globalWithoutSpecRoles(a, input) } else .{ .summary = try f.summary(a, input) } };
        const segmented: r.ContentProposal = .{ .model = .{ .business = .{ .segments = &.{ .{ .literal = .{ .value = "The user can " } }, .{ .literal = .{ .value = "confirm the request." } } } } } };
        if (global) {
            const old = parsed.proposal.global.signals;
            const values = try a.alloc(r.SignalProposal, old.len + 1);
            @memcpy(values[0..old.len], old);
            values[old.len] = old[0];
            values[old.len].content = segmented;
            parsed.proposal.global.signals = values;
        } else {
            const old = parsed.proposal.summary.statements;
            const values = try a.alloc(r.StatementProposal, old.len + 1);
            @memcpy(values[0..old.len], old);
            values[old.len] = old[0];
            values[old.len].content = segmented;
            parsed.proposal.summary.statements = values;
        }
        if (global) {
            const rejected = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
            const removal = (try repair.authorize(a, parsed, fixture.context(), rejected)).automatic;
            const merged = try repair.merge(a, parsed, fixture.context(), removal.authorization, null, null);
            _ = (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid;
            const values = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
            values[values.len - 1].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different supported meaning." } }} } } };
            parsed.proposal.global.signals = values;
            const competing = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
            try std.testing.expectEqual(.competing_entries, (try repair.authorize(a, parsed, fixture.context(), competing)).blocked);
        } else {
            const normalized = (try f.validate_summary.execute(a, parsed, fixture.context())).valid;
            try std.testing.expectEqual(parsed.proposal.summary.statements.len - 1, normalized.statements.len);
            const values = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
            values[values.len - 1].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "MOCK A distinct assertion must remain for semantic review." } }} } } };
            parsed.proposal.summary.statements = values;
            const distinct = (try f.validate_summary.execute(a, parsed, fixture.context())).valid;
            try std.testing.expectEqual(values.len, distinct.statements.len);
        }
    }
}

test "misbound extra projections recover by proven deletion with intact siblings and exact dependencies" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const origin: Origin = .{ .request = .{ .value = 6 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| for ([_]bool{ false, true }) |global| for ([_]bool{ false, true }) |first| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        const good: r.Parsed = .{ .source = .{ .origin = origin }, .input = input, .proposal = if (global) .{ .global = try globalWithoutSpecRoles(a, input) } else .{ .summary = try f.summary(a, input) } };
        try std.testing.expect((try textRejection(a, good, fixture.context())) == null);
        // Both independent obligations already have valid projections. Add the
        // business projection again, incorrectly bound to the token claim.
        const business = good.input.items[0].claim;
        const token = good.input.items[1].claim;
        try std.testing.expect(business.content == .model and token.content == .preserved_token);
        var parsed = good;
        const count = if (global) good.proposal.global.signals.len else good.proposal.summary.statements.len;
        const index: usize = if (first) 0 else count;
        if (global) {
            const values = try a.alloc(r.SignalProposal, count + 1);
            @memcpy(values[0..index], good.proposal.global.signals[0..index]);
            values[index] = .{ .claim_ids = &.{token.id}, .content = f.content(business) };
            @memcpy(values[index + 1 ..], good.proposal.global.signals[index..]);
            parsed.proposal.global.signals = values;
        } else {
            const values = try a.alloc(r.StatementProposal, count + 1);
            @memcpy(values[0..index], good.proposal.summary.statements[0..index]);
            values[index] = .{ .claim_ids = &.{token.id}, .content = f.content(business) };
            @memcpy(values[index + 1 ..], good.proposal.summary.statements[index..]);
            parsed.proposal.summary.statements = values;
        }
        const rejected = (try textRejection(a, parsed, fixture.context())).?;
        try std.testing.expectEqual(.content, rejected.issue.rule);
        try std.testing.expectEqual(.matching_claim_content, rejected.issue.expected.constraint);
        try std.testing.expectEqualDeep(origin, rejected.origin.?);
        try std.testing.expectEqual(index, if (global) rejected.unit.signal else rejected.unit.statement);
        if (global) {
            try std.testing.expect(rejected.relations.content == null);
            try std.testing.expectEqual(@as(usize, 0), rejected.relations.selection.len);
        } else {
            try std.testing.expect(rejected.relations.content.? == .preserved_token);
            try std.testing.expectEqualDeep(&[_]r.ClaimId{business.id}, rejected.relations.selection);
        }
        try std.testing.expectEqual(index, rejected.relations.redundant.?);
        if (global and first) try std.testing.checkAllAllocationFailures(std.testing.allocator, redundantDeletionAllocation, .{ parsed, fixture.context() });
        const automatic = (try repair.authorize(a, parsed, fixture.context(), rejected)).automatic;
        try std.testing.expect(automatic.authorization.operation == .delete);
        const merged = try repair.merge(a, parsed, fixture.context(), automatic.authorization, null, null);
        var expected = good.proposal;
        if (expected == .global) expected.global.role_decisions = null;
        try std.testing.expectEqualDeep(expected, merged.proposal);
        try std.testing.expectEqual(@as(u64, 2), merged.source.revision);
        for (0..count) |sibling| {
            const unit: r.diagnostic.Unit = if (global) .{ .signal = sibling } else .{ .statement = sibling };
            try std.testing.expectEqualDeep(origin, merged.source.at(unit, .record).?);
        }
        try std.testing.expect((try textRejection(a, merged, fixture.context())) == null);
        if (global) try std.testing.expectEqual(.complete, (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid.outcome);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, merged, fixture.context(), automatic.authorization, null, null));
        // Even a valid sibling change invalidates the entire original proof.
        const changed_content: r.ContentProposal = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different supported requirement." } }} } } };
        var changed = parsed;
        const business_index: usize = if (first) 1 else 0;
        if (global) {
            const values = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
            values[business_index].content = changed_content;
            changed.proposal.global.signals = values;
        } else {
            const values = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
            values[business_index].content = changed_content;
            changed.proposal.summary.statements = values;
        }
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, changed, fixture.context(), rejected));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, changed, fixture.context(), automatic.authorization, null, null));
        var stale = fixture.context();
        stale.inputs.corpus.state_id.bytes = "different-source";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, parsed, stale, rejected));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, parsed, stale, automatic.authorization, null, null));
    };
}

fn redundantDeletionAllocation(allocator: std.mem.Allocator, parsed: r.Parsed, ctx: f.Context) !void {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const rejected = (try textRejection(a, parsed, ctx)).?;
    const automatic = (try repair.authorize(a, parsed, ctx, rejected)).automatic;
    const merged = try repair.merge(a, parsed, ctx, automatic.authorization, null, null);
    try std.testing.expect((try textRejection(a, merged, ctx)) == null);
}

test "misbound projection deletion rejects missing coverage invalid survivors and novel content" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const Failure = enum { novel, missing_token, missing_business, invalid_survivor, foreign_claim, empty_claims, repeated_claim, invalid_text };
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| for ([_]bool{ false, true }) |global| for (std.meta.tags(Failure)) |failure| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        const business = input.items[0].claim;
        const token = input.items[1].claim;
        var extra: r.SignalProposal = .{ .claim_ids = &.{token.id}, .content = f.content(business) };
        switch (failure) {
            .novel => extra.content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different proposed meaning." } }} } } },
            .invalid_text => extra.content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } },
            .foreign_claim => extra.claim_ids = &.{.{ .ordinal = 999 }},
            .empty_claims => extra.claim_ids = &.{},
            .repeated_claim => extra.claim_ids = &.{ token.id, token.id },
            else => {},
        }
        var parsed: r.Parsed = .{ .input = input, .proposal = undefined };
        if (global) {
            var proposal = try globalWithoutSpecRoles(a, input);
            var values: std.ArrayList(r.SignalProposal) = .empty;
            try values.append(a, extra);
            for (proposal.signals) |value| {
                if (failure == .missing_token and value.content == .preserved_token) continue;
                if (failure == .missing_business and value.content == .model) continue;
                var sibling = value;
                if (failure == .invalid_survivor and value.content == .preserved_token) sibling.claim_ids = &.{};
                try values.append(a, sibling);
            }
            proposal.signals = try values.toOwnedSlice(a);
            parsed.proposal = .{ .global = proposal };
        } else {
            const proposal = try f.summary(a, input);
            var values: std.ArrayList(r.StatementProposal) = .empty;
            try values.append(a, .{ .claim_ids = extra.claim_ids, .content = extra.content });
            for (proposal.statements) |value| {
                if (failure == .missing_token and value.content == .preserved_token) continue;
                if (failure == .missing_business and value.content == .model) continue;
                var sibling = value;
                if (failure == .invalid_survivor and value.content == .preserved_token) sibling.claim_ids = &.{};
                try values.append(a, sibling);
            }
            parsed.proposal = .{ .summary = .{ .statements = try values.toOwnedSlice(a) } };
        }
        const rejected = (try textRejection(a, parsed, fixture.context())).?;
        try std.testing.expect(rejected.relations.redundant == null);
        const decision = try repair.authorize(a, parsed, fixture.context(), rejected);
        if (decision == .automatic) try std.testing.expect(decision.automatic.authorization.operation != .delete);
    };
}

test "misbound token deletion and overlapping summary content retain distinct validation contracts" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Display `Accepted` and `Rejected`.\n", "Record the decision.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 8), fixture.context());
    const good = try globalWithoutSpecRoles(a, input);
    var tokens_selected: std.ArrayList(r.SignalProposal) = .empty;
    for (good.signals) |signal| if (signal.content == .preserved_token) try tokens_selected.append(a, signal);
    try std.testing.expectEqual(@as(usize, 2), tokens_selected.items.len);
    for ([_]bool{ false, true }) |missing| {
        var values: std.ArrayList(r.SignalProposal) = .empty;
        try values.append(a, .{ .claim_ids = tokens_selected.items[1].claim_ids, .content = tokens_selected.items[0].content });
        for (good.signals) |signal| {
            if (missing and std.meta.eql(signal.content, tokens_selected.items[0].content)) continue;
            try values.append(a, signal);
        }
        var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = good } };
        parsed.proposal.global.signals = try values.toOwnedSlice(a);
        const rejected = (try textRejection(a, parsed, fixture.context())).?;
        try std.testing.expectEqual(.exact_selected_token, rejected.issue.expected.constraint);
        const decision = try repair.authorize(a, parsed, fixture.context(), rejected);
        if (missing) {
            try std.testing.expect(rejected.relations.redundant == null and decision != .automatic);
        } else {
            const merged = try repair.merge(a, parsed, fixture.context(), decision.automatic.authorization, null, null);
            var expected = good;
            expected.role_decisions = null;
            try std.testing.expectEqualDeep(expected, merged.proposal.global);
            try std.testing.expectEqual(.complete, (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid.outcome);
        }
    }
    // Same text selected from different source claims is not duplicate evidence.
    // Overlap alone cannot prove that the extra statement is semantically wrong.
    const summary_fixture = try prepare(a, &.{ "Confirm the request.\n", "Record the decision.\n" });
    defer summary_fixture.deinit();
    var progress = try f.initialize(a, summary_fixture.inputs, summary_fixture.extracted, 8);
    var summary_input = try f.build_input.execute(a, progress);
    while (summary_input.partition.group.level == .within_source) {
        const candidate: r.Parsed = .{ .input = summary_input, .proposal = .{ .summary = try f.summary(a, summary_input) } };
        progress = try f.build_summary.execute(a, try f.assign_summary.execute(a, (try f.validate_summary.execute(a, candidate, summary_fixture.context())).valid));
        summary_input = try f.build_input.execute(a, progress);
    }
    var original = try f.summary(a, summary_input);
    const distinct = try a.dupe(r.StatementProposal, original.statements);
    distinct[1].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Record the decision." } }} } } };
    original.statements = distinct;
    const statements = try a.alloc(r.StatementProposal, original.statements.len + 1);
    @memcpy(statements[0..original.statements.len], original.statements);
    statements[original.statements.len] = original.statements[0];
    statements[original.statements.len].claim_ids = original.statements[1].claim_ids;
    const parsed: r.Parsed = .{ .input = summary_input, .proposal = .{ .summary = .{ .statements = statements } } };
    const checked = (try f.validate_summary.execute(a, parsed, summary_fixture.context())).valid;
    try std.testing.expectEqual(statements.len, checked.statements.len);
    try std.testing.expectEqualDeep(statements[0].claim_ids, checked.statements[0].claim_ids);
    try std.testing.expectEqualDeep(statements[2].claim_ids, checked.statements[2].claim_ids);
}

test "redundant signal deletion cannot discard a selected superseded claim" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Display `Accepted`.\n", "Record the decision.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 8), fixture.context());
    var proposal = try globalWithoutSpecRoles(a, input);
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    try std.testing.expectEqual(@as(usize, 3), dispositions.len);
    dispositions[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{dispositions[2].claim_id} } };
    proposal.claim_dispositions = dispositions;
    const original = proposal.signals;
    proposal.signals = original[1..];
    // Coverage alone permits omitting this superseded non-token claim.
    _ = (try f.finish(a, input, proposal, fixture.context())).valid;
    const signals = try a.dupe(r.SignalProposal, original);
    signals[0].content = signals[1].content;
    proposal.signals = signals;
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = proposal } };
    const rejected = (try textRejection(a, parsed, fixture.context())).?;
    try std.testing.expect(rejected.relations.redundant == null);
    const decision = try repair.authorize(a, parsed, fixture.context(), rejected);
    if (decision == .automatic) try std.testing.expect(decision.automatic.authorization.operation != .delete);
}

test "summary selection permits overlap while occupied signal membership blocks impossible selections" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    for ([_][]const u8{ "Display `Hello, World!`.\n", "Confirm `Loan renewed!`.\n" }) |source| for ([_]bool{ false, true }) |global| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &.{source});
        defer fixture.deinit();
        const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        try std.testing.expectEqual(@as(usize, 2), input.items.len);
        const extra: r.ContentProposal = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "A different proposed meaning." } }} } } };
        var parsed: r.Parsed = .{ .input = input, .proposal = undefined };
        if (global) {
            const good = try globalWithoutSpecRoles(a, input);
            _ = (try f.finish(a, input, good, fixture.context())).valid;
            const signals = try a.alloc(r.SignalProposal, good.signals.len + 1);
            @memcpy(signals[0..good.signals.len], good.signals);
            signals[good.signals.len] = .{ .claim_ids = &.{}, .content = extra };
            var bad = good;
            bad.signals = signals;
            parsed.proposal = .{ .global = bad };
        } else {
            const good = try f.summary(a, input);
            _ = (try f.validate_summary.execute(a, .{ .input = input, .proposal = .{ .summary = good } }, fixture.context())).valid;
            const statements = try a.alloc(r.StatementProposal, good.statements.len + 1);
            @memcpy(statements[0..good.statements.len], good.statements);
            statements[good.statements.len] = .{ .claim_ids = &.{}, .content = extra };
            parsed.proposal = .{ .summary = .{ .statements = statements } };
        }
        const rejection = (try textRejection(a, parsed, fixture.context())).?;
        try std.testing.expectEqual(.claim_selection, rejection.issue.rule);
        const decision = try repair.authorize(a, parsed, fixture.context(), rejection);
        if (global) {
            try std.testing.expectEqual(@as(usize, 0), rejection.relations.selection.len);
            try std.testing.expectEqual(.no_independent_target, decision.blocked);
        } else {
            try std.testing.expectEqual(@as(usize, 1), rejection.relations.selection.len);
            const repaired = try repair.merge(a, parsed, fixture.context(), decision.model, .{ .selection = .{ .claim_ids = rejection.relations.selection } }, null);
            const checked = (try f.validate_summary.execute(a, repaired, fixture.context())).valid;
            try std.testing.expectEqual(parsed.proposal.summary.statements.len, checked.statements.len);
        }
    };
}

test "equivalent disposition permutations delete only redundant edges and preserve exact preconditions" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    for ([_][3][]const u8{
        .{ "Show the greeting.\n", "Show the result.\n", "Confirm the result.\n" },
        .{ "Renew the loan.\n", "Issue a receipt.\n", "Confirm the renewal.\n" },
    }) |sources| for ([_]bool{ false, true }) |has_conflict| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &sources);
        defer fixture.deinit();
        const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        const good = try globalWithoutSpecRoles(a, input);
        try std.testing.expectEqual(@as(usize, 3), good.claim_dispositions.len);
        const values = try a.alloc(r.ClaimDispositionProposal, 4);
        @memcpy(values[0..3], good.claim_dispositions);
        values[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{ values[1].claim_id, values[2].claim_id } } };
        if (has_conflict) {
            values[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{ values[1].claim_id, values[2].claim_id } } };
            values[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{values[0].claim_id} } };
            values[2].disposition = .{ .conflicting = .{ .related_claim_ids = &.{values[0].claim_id} } };
        }
        values[3] = values[0];
        if (has_conflict) values[3].disposition.conflicting.related_claim_ids = &.{ values[2].claim_id, values[1].claim_id } else values[3].disposition.superseded.related_claim_ids = &.{ values[2].claim_id, values[1].claim_id };
        var original = good;
        original.claim_dispositions = values[0..3];
        if (has_conflict) {
            original.signals = &.{};
            const conflict: r.ConflictProposal = .{ .claim_ids = &.{ values[0].claim_id, values[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The requested outcomes differ." } }} } };
            var other = conflict;
            other.claim_ids = &.{ values[0].claim_id, values[2].claim_id };
            original.conflicts = &.{ conflict, other };
        }
        _ = (try f.finish(a, input, original, fixture.context())).valid;
        var permuted = original;
        permuted.claim_dispositions = &.{ values[3], values[1], values[2] };
        _ = (try f.finish(a, input, permuted, fixture.context())).valid;
        var duplicate = original;
        duplicate.claim_dispositions = values;
        const parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = duplicate } };
        const rejected = (try f.validate_dispositions.execute(a, parsed)).invalid;
        try std.testing.expectEqual(.cardinality, rejected.issue.rule);
        const decision = try repair.authorize(a, parsed, fixture.context(), rejected);
        const automatic = decision.automatic;
        try std.testing.expectEqual(@as(usize, 3), rejected.relations.redundant.?);
        try std.testing.expect(automatic.authorization.operation == .delete);
        const merged = try repair.merge(a, parsed, fixture.context(), automatic.authorization, null, null);
        try std.testing.expectEqualDeep(original, merged.proposal.global);
        try std.testing.expectEqual(@as(@FieldType(r.Accounted, "outcome"), if (has_conflict) .blocked else .complete), (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid.outcome);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, merged, fixture.context(), automatic.authorization, null, null));
        // An equivalent permutation still changes the exact dependency/old value.
        const changed_values = try a.dupe(r.ClaimDispositionProposal, values);
        changed_values[3] = values[0];
        var changed = parsed;
        changed.proposal.global.claim_dispositions = changed_values;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, changed, fixture.context(), rejected));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, changed, fixture.context(), automatic.authorization, null, null));
        changed_values[3] = values[3];
        changed_values[1].disposition = .{ .retained = .{} };
        if (!has_conflict) changed_values[1].disposition = .{ .superseded = .{ .related_claim_ids = &.{values[2].claim_id} } };
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, changed, fixture.context(), automatic.authorization, null, null));
    };
}

test "signal selection admits available and overlapping sets but blocks exhausted membership" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][2][]const u8{
        .{ "Show the greeting.\n", "Confirm the result.\n" },
        .{ "Renew the loan.\n", "Issue a receipt.\n" },
    }) |sources| for (0..3) |scenario| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &sources);
        defer fixture.deinit();
        const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        const good = try globalWithoutSpecRoles(a, input);
        const all = input.partition.group.claim_ids;
        try std.testing.expectEqual(@as(usize, 2), all.len);
        const signals = try a.alloc(r.SignalProposal, scenario + 2);
        @memcpy(signals[0..2], good.signals);
        if (scenario == 2) signals[2] = .{ .claim_ids = all, .content = good.signals[0].content };
        const selected: usize = if (scenario == 0) 0 else signals.len - 1;
        signals[selected] = .{ .claim_ids = &.{}, .content = good.signals[0].content };
        var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = good } };
        parsed.proposal.global.signals = signals;
        const rejection = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
        const decision = try repair.authorize(a, parsed, fixture.context(), rejection);
        if (scenario == 2) {
            try std.testing.expectEqual(.no_independent_target, decision.blocked);
            try std.testing.expectEqual(@as(usize, 0), rejection.relations.selection.len);
            continue;
        }
        const authorization = decision.model;
        const packet = try repair.packet(a, parsed, fixture.context(), authorization);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const choices = body.value.object.get("repair").?.object.get("rule").?.object.get("selection").?.array.items;
        try std.testing.expectEqual(@as(usize, 2), choices.len);
        const ids = try a.alloc(r.ClaimId, if (scenario == 0) 1 else 2);
        for (ids, 0..) |*id, index| id.* = .{ .ordinal = @intCast(choices[index].integer) };
        const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, .{ .selection = .{ .claim_ids = ids } });
        const merged = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, wire), null);
        for (signals, 0..) |sibling, index| if (index != selected) try std.testing.expectEqualDeep(sibling, merged.proposal.global.signals[index]);
        try std.testing.expectEqual(.complete, (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid.outcome);
        // A model may ignore the choices; the native uniqueness gate still rejects.
        const duplicate = try repair.merge(a, parsed, fixture.context(), authorization, .{ .selection = .{ .claim_ids = good.signals[1].claim_ids } }, null);
        try std.testing.expectEqual(.duplicate_signal, (try f.finish(a, input, duplicate.proposal.global, fixture.context())).invalid.issue.rule);
    };
}

test "selection repair response bounds follow authorized compatible claims rather than the original assignment" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    const schema = @import("domain/model_result_schema.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .unlimited));
    for ([_][3][]const u8{
        .{ "MOCK Display `MOCK Greeting`.\n", "MOCK Display the current time.\n", "MOCK Use the declared architecture.\n" },
        .{ "MOCK Renew the loan with `MOCK Renewed`.\n", "MOCK Issue a receipt.\n", "MOCK Use the declared architecture.\n" },
    }) |sources| for ([_]bool{ false, true }) |global| {
        const fixture = try prepare(a, &sources);
        defer fixture.deinit();
        var extracted = fixture.extracted;
        const claims = try a.dupe(r.extraction.Claim, extracted.ledger.claims);
        claims[claims.len - 1].content = .{ .model = .{ .design = .{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "MOCK Use the declared architecture." } }} } } } };
        extracted.ledger.claims = claims;
        const progress = try f.initialize(a, fixture.inputs, extracted, 8);
        const input = if (global) try f.summaries(a, progress, fixture.context()) else try f.build_input.execute(a, progress);
        var parsed: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try globalWithoutSpecRoles(a, input) } else .{ .summary = try f.summary(a, input) } };
        if (global) {
            const signals = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
            signals[0].claim_ids = &.{};
            parsed.proposal.global.signals = signals;
        } else {
            const statements = try a.dupe(r.StatementProposal, parsed.proposal.summary.statements);
            statements[0].claim_ids = &.{};
            parsed.proposal.summary.statements = statements;
        }
        const rejection = (try textRejection(a, parsed, fixture.context())).?;
        const auth = (try repair.authorize(a, parsed, fixture.context(), rejection)).model;
        const packet = try repair.packet(a, parsed, fixture.context(), auth);
        defer packets.release(packet);
        const allowed = auth.rule.rejection.relations.selection;
        try std.testing.expectEqual(@as(usize, if (global) 2 else 1), allowed.len);
        try std.testing.expect(allowed.len < input.partition.group.claim_ids.len);
        const choice = packet.integerChoices()[packet.integerChoices().len - 1];
        try std.testing.expectEqual(.unique_subset, choice.collection);
        try std.testing.expectEqual(allowed.len, choice.allowed.len);
        for (choice.allowed, allowed) |ordinal, claim| try std.testing.expectEqual(@as(i64, claim.ordinal), ordinal);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        const evidence = body.get("input").?.object;
        try std.testing.expect(!evidence.contains("assignment"));
        try std.testing.expectEqual(input.items.len, evidence.get("claims").?.array.items.len);
        const guidance = try std.json.Stringify.valueAlloc(a, evidence.get("constraints").?, .{});
        try std.testing.expect(std.mem.indexOf(u8, guidance, "repair.rule.selection") != null);
        for ([_][]const u8{ "assignment.claim_ids", "accepted.signals", "retained_claim_covered", "token_projected", "conflict_claim_covered", "conflict_pair_covered" }) |unrelated|
            try std.testing.expect(std.mem.indexOf(u8, guidance, unrelated) == null);
        const selected = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer selected.release();
        const valid = try std.fmt.allocPrint(a, "{{\"claim_ids\":[{d}]}}", .{allowed[0].ordinal});
        try check(selected.selected().modelBytes(), .{ .bytes = valid });
        const foreign = try std.fmt.allocPrint(a, "{{\"claim_ids\":[{d}]}}", .{claims[claims.len - 1].id.ordinal});
        try check(selected.selected().modelBytes(), .{ .bytes = foreign, .rejection = .enum_mismatch, .path = "/claim_ids/0" });
        const repeated = try a.alloc(r.ClaimId, allowed.len + 1);
        @memset(repeated, allowed[0]);
        const too_many = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, .{ .selection = .{ .claim_ids = repeated } });
        try check(selected.selected().modelBytes(), .{ .bytes = too_many, .rejection = .array_length, .path = "/claim_ids" });
        if (global) {
            // The closed schema profile has no uniqueness keyword. Native
            // validation still rejects repeated IDs within the projected bound.
            const duplicate: repair.Replacement = .{ .selection = .{ .claim_ids = repeated[0..allowed.len] } };
            const bytes = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, duplicate);
            try check(selected.selected().modelBytes(), .{ .bytes = bytes });
            const merged = try repair.merge(a, parsed, fixture.context(), auth, duplicate, null);
            try std.testing.expectEqual(.claim_selection, (try textRejection(a, merged, fixture.context())).?.issue.rule);
        }
    };
}

test "disposition redundancy rejects changed identities meanings and invalid repeated edges" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Renew the loan.\n", "Issue a receipt.\n", "Confirm the renewal.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const good = try globalWithoutSpecRoles(a, input);
    const ids = input.partition.group.claim_ids;
    for (0..8) |scenario| {
        const values = try a.alloc(r.ClaimDispositionProposal, 4);
        @memcpy(values[0..3], good.claim_dispositions);
        values[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{ ids[1], ids[2] } } };
        values[3] = values[0];
        switch (scenario) {
            0 => values[3].disposition.superseded.related_claim_ids = &.{ids[1]},
            1 => values[3].disposition = .{ .retained = .{} },
            2 => values[3].claim_id = ids[1],
            3 => values[3].claim_id = .{ .ordinal = 999 },
            4 => values[3].disposition.superseded.related_claim_ids = &.{ ids[1], ids[1] },
            5 => values[3].disposition.superseded.related_claim_ids = &.{ids[0]},
            6 => values[3].disposition.superseded.related_claim_ids = &.{},
            7 => values[3].disposition.superseded.related_claim_ids = &.{.{ .ordinal = 999 }},
            else => unreachable,
        }
        // Invalid identical records must not acquire redundancy proof either.
        if (scenario >= 4) values[0] = values[3];
        var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = good } };
        parsed.proposal.global.claim_dispositions = values;
        const rejection = (try f.validate_dispositions.execute(a, parsed)).invalid;
        try std.testing.expect(rejection.relations.redundant == null);
        const decision = try repair.authorize(a, parsed, fixture.context(), rejection);
        try std.testing.expectEqual(@as(repair.Block, if (scenario == 3) .no_independent_target else .competing_entries), decision.blocked);
    }
}

test "relationship rejection facts and repair paths retain ownership under allocation failure" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Renew a loan.\n", "Issue a receipt.\n", "Confirm the renewal.\n" });
    defer fixture.deinit();
    const progress = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
    const input = try f.summaries(a, progress, fixture.context());
    const good = try globalWithoutSpecRoles(a, input);
    for (0..3) |scenario| {
        var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = good } };
        if (scenario == 0) {
            parsed.input = try f.build_input.execute(a, progress);
            const summary = try f.summary(a, parsed.input);
            const statements = try a.dupe(r.StatementProposal, summary.statements);
            statements[0].claim_ids = &.{};
            parsed.proposal = .{ .summary = .{ .statements = statements } };
        } else if (scenario == 1) {
            const signals = try a.dupe(r.SignalProposal, good.signals);
            signals[0].claim_ids = &.{};
            parsed.proposal.global.signals = signals;
        } else {
            const values = try a.alloc(r.ClaimDispositionProposal, 4);
            @memcpy(values[0..3], good.claim_dispositions);
            values[0].disposition = .{ .superseded = .{ .related_claim_ids = &.{ values[1].claim_id, values[2].claim_id } } };
            values[3] = values[0];
            values[3].disposition.superseded.related_claim_ids = &.{ values[2].claim_id, values[1].claim_id };
            parsed.proposal.global.claim_dispositions = values;
        }
        try std.testing.checkAllAllocationFailures(std.testing.allocator, relationRepairAllocation, .{ parsed, fixture.context() });
    }
}

fn relationRepairAllocation(allocator: std.mem.Allocator, parsed: r.Parsed, ctx: f.Context) !void {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const Diagnostic = @import("domain/candidate_validation_diagnostic.zig").Diagnostic;
    var retained: std.heap.ArenaAllocator = .init(allocator);
    defer retained.deinit();
    var copied: Diagnostic = undefined;
    {
        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const rejection = if (parsed.proposal == .summary) (try f.validate_summary.execute(a, parsed, ctx)).invalid else (try f.finish(a, parsed.input, parsed.proposal.global, ctx)).invalid;
        copied = try (Diagnostic{ .reconciliation = rejection }).copy(retained.allocator());
        const decision = try repair.authorize(a, parsed, ctx, rejection);
        const merged = switch (decision) {
            .model => |authorization| model: {
                const packet = try repair.packet(allocator, parsed, ctx, authorization);
                defer @import("domain/model_input_packet.zig").release(packet);
                const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, .{ .selection = .{ .claim_ids = rejection.relations.selection } });
                break :model try repair.merge(a, parsed, ctx, authorization, try repair.parse(a, authorization, packet, wire), null);
            },
            .automatic => |automatic| try repair.merge(a, parsed, ctx, automatic.authorization, automatic.replacement, null),
            .blocked => return error.UnexpectedRepairBlock,
        };
        try std.testing.expectEqual(parsed.source.revision + 1, merged.source.revision);
        if (merged.proposal == .summary) _ = (try f.validate_summary.execute(a, merged, ctx)).valid else _ = (try f.finish(a, merged.input, try mockUnsupportedRoles(a, merged.proposal.global), ctx)).valid;
    }
    // Owned diagnostics must remain serializable after native facts/packets die.
    const bytes = try std.json.Stringify.valueAlloc(allocator, copied, .{});
    defer allocator.free(bytes);
    try std.testing.expect(bytes.len != 0);
    if (parsed.proposal == .summary or copied.reconciliation.unit == .signal) try std.testing.expect(copied.reconciliation.relations.selection.len != 0) else try std.testing.expectEqual(@as(usize, 3), copied.reconciliation.relations.redundant.?);
}

test "conflict selection respects occupied pairs without conflating conflict kinds" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    for ([_][2][]const u8{
        .{ "Show the greeting.\n", "Suppress the greeting.\n" },
        .{ "Renew the loan.\n", "Reject the renewal.\n" },
    }) |sources| for ([_]bool{ false, true }) |same_kind| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &sources);
        defer fixture.deinit();
        const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        const good = try conflicting(a, input);
        const conflicts = try a.dupe(r.ConflictProposal, &.{ good.conflicts[0], good.conflicts[0] });
        conflicts[1].claim_ids = &.{};
        conflicts[1].summary = .{ .nodes = &.{.{ .literal = .{ .value = "The eligibility conditions differ." } }} };
        if (!same_kind) conflicts[1].kind = .scope_mismatch;
        var parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = good } };
        parsed.proposal.global.conflicts = conflicts;
        const rejected = (try f.finish(a, input, parsed.proposal.global, fixture.context())).invalid;
        const decision = try repair.authorize(a, parsed, fixture.context(), rejected);
        if (same_kind) {
            try std.testing.expect(decision == .blocked);
            try std.testing.expectEqual(.no_independent_target, decision.blocked);
            try std.testing.expectEqual(@as(usize, 0), rejected.relations.conflicting_pairs.len);
        } else {
            const authorization = decision.model;
            const packet = try repair.packet(a, parsed, fixture.context(), authorization);
            defer @import("domain/model_input_packet.zig").release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const pairs = body.value.object.get("repair").?.object.get("rule").?.object.get("conflicting_pairs").?.array.items;
            try std.testing.expectEqual(@as(usize, 1), pairs.len);
            try std.testing.expectEqualStrings("repair_conflict_selection", packet.resultDefinition().?.bytes);
            try std.testing.expectEqual(.sequence, packet.integerChoices()[packet.integerChoices().len - 1].collection);
            try std.testing.expectEqual(@as(usize, 0), body.value.object.get("input").?.object.get("constraints").?.array.items.len);
            try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, "{\"claim_ids\":[1,2]}"));
            const wire = "{\"group_id\":1}";
            const merged = try repair.merge(a, parsed, fixture.context(), authorization, try repair.parse(a, authorization, packet, wire), null);
            try std.testing.expectEqualDeep(conflicts[0], merged.proposal.global.conflicts[0]);
            try std.testing.expectEqual(.blocked, (try f.finish(a, input, try mockUnsupportedRoles(a, merged.proposal.global), fixture.context())).valid.outcome);
        }
    };
}

test "repair progress separates restored membership from invalid inserted content" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const retry = @import("domain/workflow_retry.zig");
    for ([_][2][]const u8{
        .{ "Confirm the reservation.\n", "Issue a receipt.\n" },
        .{ "Renew the loan.\n", "Notify the visitor.\n" },
    }) |sources| for ([_]bool{ false, true }) |global| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try prepare(a, &sources);
        defer fixture.deinit();
        const initial = try f.initialize(a, fixture.inputs, fixture.extracted, 2);
        const input = if (global) try f.summaries(a, initial, fixture.context()) else try f.build_input.execute(a, initial);
        const good: r.Parsed = .{ .input = input, .proposal = if (global) .{ .global = try globalWithoutSpecRoles(a, input) } else .{ .summary = try f.summary(a, input) } };
        var missing = good;
        if (global) missing.proposal.global.signals = good.proposal.global.signals[1..] else missing.proposal.summary.statements = good.proposal.summary.statements[1..];
        const original = if (global) good.proposal.global.signals[0].content else good.proposal.summary.statements[0].content;
        const insert = (try repair.authorize(a, missing, fixture.context(), (try textRejection(a, missing, fixture.context())).?)).model;
        try std.testing.expect(insert.operation == .insert);
        const bad: r.ContentProposal = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } };
        const inserted = try repair.merge(a, missing, fixture.context(), insert, .{ .content = bad }, null);
        const rejection = (try textRejection(a, inserted, fixture.context())).?;
        try std.testing.expectEqual(.typed_text, rejection.issue.rule);
        const dispositions = if (global) (try f.validate_dispositions.execute(a, inserted)).valid.dispositions else &.{};
        const stage: repair.ValidationStage = if (global) .signals else .summary;
        const membership = (try repair.progress(a, text.validator, fixture.context(), inserted, stage, dispositions)).?.validated;
        try std.testing.expectEqual(.resolved, membership.result);
        var state = retry.State.init(std.testing.allocator);
        defer state.deinit();
        try state.commit(try state.prepare(.{ .authorized = insert.retry.? }));
        try state.commit(try state.prepare(.{ .merged = .{ .permit = insert.retry.?, .revision_after = inserted.source.revision } }));
        try state.commit(try state.prepare(.{ .validated = membership }));
        const correction = (try repair.authorize(a, inserted, fixture.context(), rejection)).model;
        try std.testing.expect(!std.meta.eql(correction.retry.?.key, insert.retry.?.key));
        try state.commit(try state.prepare(.{ .authorized = correction.retry.? }));
        const unchanged = try repair.merge(a, inserted, fixture.context(), correction, .{ .content = bad }, null);
        _ = (try textRejection(a, unchanged, fixture.context())).?;
        const repeated = (try repair.progress(a, text.validator, fixture.context(), unchanged, stage, dispositions)).?.validated;
        try std.testing.expectEqual(.recurring, repeated.result);
        try state.commit(try state.prepare(.{ .merged = .{ .permit = correction.retry.?, .revision_after = unchanged.source.revision } }));
        try state.commit(try state.prepare(.{ .validated = repeated }));
        const again = (try repair.authorize(a, unchanged, fixture.context(), (try textRejection(a, unchanged, fixture.context())).?)).model;
        try std.testing.expectEqualDeep(correction.retry.?.key, again.retry.?.key);
        try state.commit(try state.prepare(.{ .authorized = again.retry.? }));
        const repaired = try repair.merge(a, unchanged, fixture.context(), again, .{ .content = original }, null);
        try std.testing.expectEqual(@as(?r.diagnostic.Rejection, null), try textRejection(a, repaired, fixture.context()));
        const completed = (try repair.progress(a, text.validator, fixture.context(), repaired, stage, dispositions)).?.validated;
        try state.commit(try state.prepare(.{ .merged = .{ .permit = again.retry.?, .revision_after = repaired.source.revision } }));
        try state.commit(try state.prepare(.{ .validated = completed }));
        try std.testing.expectEqual(.resolved, completed.result);
        if (global) {
            try std.testing.expectEqualDeep(missing.proposal.global.signals, repaired.proposal.global.signals[0..missing.proposal.global.signals.len]);
            _ = (try f.finish(a, input, try mockUnsupportedRoles(a, repaired.proposal.global), fixture.context())).valid;
        } else try std.testing.expectEqualDeep(missing.proposal.summary.statements, repaired.proposal.summary.statements[0..missing.proposal.summary.statements.len]);
    };
}

test "semantic conflict groups expand direct pairs without inventing transitive conflicts" {
    const groups = @import("domain/reference_conflict_groups.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const choices = [_]groups.Choice{
        .{ .claim_id = .{ .ordinal = 1 }, .disposition = .{ .conflicting = .{} } },
        .{ .claim_id = .{ .ordinal = 2 }, .disposition = .{ .conflicting = .{} } },
        .{ .claim_id = .{ .ordinal = 3 }, .disposition = .{ .conflicting = .{} } },
    };
    const ab = [_]r.ClaimId{ .{ .ordinal = 1 }, .{ .ordinal = 2 } };
    const bc = [_]r.ClaimId{ .{ .ordinal = 2 }, .{ .ordinal = 3 } };
    const chain = try groups.expand(a, .{ .claim_dispositions = &choices, .conflict_groups = &.{ .{ .claim_ids = &ab }, .{ .claim_ids = &bc } } });
    try std.testing.expectEqualDeep(&[_]r.ClaimId{.{ .ordinal = 2 }}, chain[0].disposition.conflicting.related_claim_ids);
    try std.testing.expectEqualDeep(&[_]r.ClaimId{ .{ .ordinal = 1 }, .{ .ordinal = 3 } }, chain[1].disposition.conflicting.related_claim_ids);
    try std.testing.expectEqualDeep(&[_]r.ClaimId{.{ .ordinal = 2 }}, chain[2].disposition.conflicting.related_claim_ids);
    const triangle = try groups.expand(a, .{ .claim_dispositions = &choices, .conflict_groups = &.{.{ .claim_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 }, .{ .ordinal = 3 } } }} });
    for (triangle) |value| try std.testing.expectEqual(@as(usize, 2), value.disposition.conflicting.related_claim_ids.len);
    const explanations = try groups.explain(a, &.{.{ .claim_ids = &ab }}, &.{
        .{ .group_id = .{ .ordinal = 1 }, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The values differ." } }} } },
        .{ .group_id = .{ .ordinal = 1 }, .kind = .scope_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The scopes differ." } }} } },
        .{ .group_id = .{ .ordinal = 999 }, .kind = .value_mismatch, .summary = .{ .nodes = &.{} } },
    });
    try std.testing.expectEqualDeep(ab[0..], explanations[0].claim_ids);
    try std.testing.expectEqualDeep(ab[0..], explanations[1].claim_ids);
    try std.testing.expectEqual(@as(usize, 0), explanations[2].claim_ids.len);
}

test "phase assignments reject premature and stale handoffs and retain role diagnostics without request data" {
    const stage = @import("domain/reference_reconciliation_stage.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{"Display the renewal date and `Loan renewed!`.\n"});
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 13 }, .attempt = .{ .value = 2 } };
    const choices = try a.alloc(@import("domain/reference_conflict_groups.zig").Choice, input.items.len);
    for (input.items, choices) |item, *choice| choice.* = .{ .claim_id = item.claim.id, .disposition = .{ .retained = .{} } };
    const disposition_packet = try stage.packet(a, .{ .dispositions = input }, fixture.inputs, fixture.context().registry);
    defer @import("domain/model_input_packet.zig").release(disposition_packet);
    const admitted = try stage.collect(a, .{ .dispositions = input }, disposition_packet, try json.encodeSelected(stage.Response, a, .{ .dispositions = .{ .claim_dispositions = choices, .conflict_groups = &.{} } }), origin);
    try std.testing.expect(admitted.source.origin == null);
    try std.testing.expectEqualDeep(origin, admitted.source.at(.dispositions, .record).?);
    var parsed: r.Parsed = .{ .phase = .dispositions, .input = input, .proposal = .{ .global = try globalWithoutSpecRoles(a, input) } };
    const dispositions = (try f.validate_dispositions.execute(a, parsed)).valid;
    try std.testing.expectError(error.InvalidReferenceReconciliation, f.validate_signals.execute(a, dispositions, fixture.context()));
    parsed.phase = .signals;
    const signals = (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).valid;
    const packet = try stage.packet(a, .{ .roles = signals }, fixture.inputs, fixture.context().registry);
    defer @import("domain/model_input_packet.zig").release(packet);
    const invalid = try stage.collect(a, .{ .roles = signals }, packet, try json.encodeSelected(stage.Response, a, .{ .roles = .{ .role_decisions = try f.roleDecisions(a, &.{.{ .signal_id = .{ .ordinal = 999 }, .generation_roles = &.{.records} }}) } }), origin);
    const roles = try f.validate_roles.execute(a, (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, invalid)).valid, fixture.context())).valid);
    try std.testing.expectEqual(.role_assignment, roles.invalid.issue.rule);
    try std.testing.expectEqualDeep(origin, roles.invalid.origin.?);
    var stale = signals;
    stale.prior.source.revision += 1;
    try std.testing.expectError(error.InvalidReferenceReconciliation, stage.collect(a, .{ .roles = stale }, packet, "{}", origin));
    var changed = signals;
    const changed_signals = try a.dupe(r.ValidatedSignal, signals.signals);
    changed_signals[0].content = .{ .model = .{ .business = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "A different accepted meaning." } }} } } } };
    changed.signals = changed_signals;
    try std.testing.expectError(error.InvalidReferenceReconciliation, stage.collect(a, .{ .roles = changed }, packet, "{}", origin));
    const owner = try @import("domain/reference_candidate_value.zig").create(std.testing.allocator, null);
    owner.payload = .{ .reconciliation_rejected = roles.invalid };
    const descriptor = @import("application/reference_reconciliation_workflow.zig").roles_schema;
    const published = try @import("application/reference_extraction_workflow.zig").publish(std.testing.allocator, descriptor, owner, .invalid);
    const value = published.delta.data_writes[@intFromEnum(descriptor.key)].?;
    defer @import("application/pipeline_values.zig").destroy(value);
    var view: @import("domain/pipeline_data.zig").View = .{};
    view.slots[@intFromEnum(descriptor.key)] = value;
    const retained = (try @import("application/candidate_validation_diagnostics.zig").read(&view)).?;
    try std.testing.expectEqualDeep(origin, retained.reconciliation.origin.?);
    try std.testing.expectEqual(.role_assignment, retained.reconciliation.issue.rule);
}

test "checked phase facts retire resolved receipts and preserve repairs owned by later validators" {
    const repair = @import("domain/reference_reconciliation_repair.zig");
    const native = @import("application/reference_extraction_workflow.zig");
    const workflow = @import("application/reference_reconciliation_workflow.zig");
    const values = @import("application/pipeline_values.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try prepare(a, &.{ "Renew the loan.\n", "Retain the receipt.\n" });
    defer fixture.deinit();
    const input = try f.summaries(a, try f.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    for ([_]bool{ false, true }) |later| {
        var parsed: r.Parsed = .{ .phase = .dispositions, .input = input, .proposal = .{ .global = try globalWithoutSpecRoles(a, input) } };
        if (later) {
            const signals = try a.dupe(r.SignalProposal, parsed.proposal.global.signals);
            signals[0].content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} } } };
            parsed.proposal.global.signals = signals;
            parsed.phase = .signals;
            const rejection = (try f.validate_signals.execute(a, (try f.validate_dispositions.execute(a, parsed)).valid, fixture.context())).invalid;
            const auth = (try repair.authorize(a, parsed, fixture.context(), rejection)).model;
            parsed = try repair.merge(a, parsed, fixture.context(), auth, auth.operation.replace, null);
        } else {
            const dispositions = try a.alloc(r.ClaimDispositionProposal, parsed.proposal.global.claim_dispositions.len + 1);
            @memcpy(dispositions[0 .. dispositions.len - 1], parsed.proposal.global.claim_dispositions);
            dispositions[dispositions.len - 1] = dispositions[0];
            parsed.proposal.global.claim_dispositions = dispositions;
            const rejection = (try f.validate_dispositions.execute(a, parsed)).invalid;
            const auth = (try repair.authorize(a, parsed, fixture.context(), rejection)).automatic;
            parsed = try repair.merge(a, parsed, fixture.context(), auth.authorization, null, null);
        }
        try std.testing.expect(parsed.source.pending_repair != null);
        const owner = try @import("domain/reference_candidate_value.zig").create(std.testing.allocator, null);
        owner.payload = .{ .reconciliation_parsed = parsed };
        const captured = try native.publish(std.testing.allocator, workflow.parsed_schema, owner, .ok);
        const raw_value = captured.delta.data_writes[@intFromEnum(workflow.parsed_schema.key)].?;
        defer values.destroy(raw_value);
        var view: @import("domain/pipeline_data.zig").View = .{};
        view.slots[@intFromEnum(workflow.parsed_schema.key)] = raw_value;
        const step: @import("domain/workflow_compilation.zig").CompiledStep = .{ .id = .{ .bytes = "check-dispositions" }, .operation_id = .{ .bytes = workflow.ValidateDispositions.Action.contract.id }, .parameters = &.{}, .requires = workflow.ValidateDispositions.Action.contract.requires, .produces = workflow.ValidateDispositions.Action.contract.produces, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{ .ok, .invalid, .failed }, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
        var binding: workflow.ValidateDispositions = .{ .allocator = std.testing.allocator, .action = .{} };
        const checked = try workflow.ValidateDispositions.invoke(&binding, .{ .step = .{ .data = view, .step = &step, .resources = &.{}, .model_binding = null, .log = .init(try @import("domain/telemetry.zig").WorkflowShortcode.parse("SGEN")) } });
        const checked_value = checked.delta.data_writes[@intFromEnum(workflow.dispositions_schema.key)].?;
        defer values.destroy(checked_value);
        try std.testing.expectEqual(.ok, checked.outcome);
        try std.testing.expectEqual(later, checked.delta.repair_transition == null);
        const facts = (try native.read(&.{ .slots = checked.delta.data_writes }, workflow.dispositions_schema, .reconciliation_dispositions)).payload().reconciliation_dispositions;
        try std.testing.expectEqual(later, facts.source.pending_repair != null);
        if (!later) try std.testing.expectEqual(.resolved, checked.delta.repair_transition.?.validated.result);
    }
}

test {
    _ = @import("reference_role_assignment_test.zig");
}
