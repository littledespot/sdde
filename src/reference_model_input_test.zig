const std = @import("std");
const input = @import("domain/reference_model_input.zig");
const iteration = @import("domain/reference_model_iteration.zig");
const packets = @import("domain/model_input_packet.zig");
const source = @import("reference_evidence_test.zig");
const extraction = @import("reference_extraction_test.zig");
const reconciliation = @import("test_fixtures/reference_reconciliation.zig");
const text = @import("test_fixtures/reference_text.zig");
const tokens = @import("test_fixtures/reference_tokens.zig");

test "reference model packets preserve exact chunk bytes and engine bound scope" {
    try exercisePackets(std.testing.allocator);
}
test "reference packet and iteration allocations have deterministic cleanup" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exercisePackets, .{});
}

test "shared role context owns its purposes and cleans up every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, roleContextAllocations, .{});
}
fn roleContextAllocations(a: std.mem.Allocator) !void {
    const context = try input.roleContext(a);
    defer {
        for (context.role_definitions) |definition| a.free(definition.purpose);
        a.free(context.role_definitions);
        a.free(context.constraints);
    }
    const r = reconciliation.r;
    try std.testing.expectEqual(std.meta.tags(r.GenerationRole).len, context.role_definitions.len);
    try std.testing.expectEqual(@as(usize, 1), context.constraints.len);
    try std.testing.expectEqual(.supported_role_assignment, context.constraints[0].constraint);
    for (context.role_definitions) |definition| try std.testing.expect(definition.purpose.len != 0);
}

test "reconciliation assignments scope instructions while retaining complete source evidence" {
    for ([_][]const u8{
        "The application must start. Display `Hello, World!` and the current UTC time.\n",
        "Renew a library loan and show its new due date. Display `Loan renewed!`.\n",
    }) |source_text| {
        try exerciseAssignmentPackets(std.testing.allocator, source_text);
        try std.testing.checkAllAllocationFailures(std.testing.allocator, exerciseAssignmentPackets, .{source_text});
    }
}

test "role handoffs offer and accept the same retained groups as authoring and readback" {
    const r = reconciliation.r;
    const stage = @import("domain/reference_reconciliation_stage.zig");
    const refs = @import("domain/reference_support.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const snapshot = @import("domain/reference_snapshot.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 45 }, .attempt = .{ .value = 1 } };
    for ([_][2][]const u8{
        .{ "MOCK Start the application and show a greeting.\n", "MOCK Also display UTC date and time.\n" },
        .{ "MOCK Renew an eligible library loan.\n", "MOCK Also show its new return deadline.\n" },
    }) |sources| for ([_]r.Disposition{ .superseded, .duplicate }) |retired| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &sources);
        defer fixture.deinit();
        const global = try reconciliation.summaries(a, try reconciliation.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        var proposal = try reconciliation.global(a, global);
        const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
        const grouped = try a.dupe(r.SignalProposal, proposal.signals);
        proposal.claim_dispositions = dispositions;
        proposal.signals = grouped;
        const mixed = [_]r.ClaimId{ global.items[0].claim.id, global.items[1].claim.id };
        dispositions[0].disposition = if (retired == .superseded)
            .{ .superseded = .{ .related_claim_ids = &.{mixed[1]} } }
        else
            .{ .duplicate = .{ .target_claim_id = mixed[1] } };
        grouped[0].claim_ids = &mixed;
        const parsed: r.Parsed = .{ .phase = .signals, .input = global, .proposal = .{ .global = proposal } };
        const signals = (try reconciliation.validate_signals.execute(a, (try reconciliation.validate_dispositions.execute(a, parsed)).valid, fixture.context())).valid;
        try std.testing.expect(!try refs.eligibleSelection(signals.prior.dispositions, &mixed));
        try std.testing.expect(try refs.eligibleSelection(signals.prior.dispositions, &.{mixed[1]}));
        try std.testing.expect(!try refs.eligibleSelection(signals.prior.dispositions, &.{}));
        try std.testing.expectError(error.InvalidReferenceReconciliation, refs.eligibleSelection(signals.prior.dispositions, &.{.{ .ordinal = 999 }}));
        const packet = try stage.packet(std.testing.allocator, .{ .roles = signals }, fixture.inputs, fixture.text.registry);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const offered = body.value.object.get("accepted").?.object.get("signals").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), offered.len);
        // Filtering never renumbers the native occurrence or removes source evidence.
        try std.testing.expectEqual(@as(i64, 2), offered[0].object.get("signal_id").?.integer);
        try std.testing.expectEqual(global.items.len, body.value.object.get("claims").?.array.items.len);
        const roles = std.enums.values(r.GenerationRole);
        const bad: stage.Response = .{ .roles = .{ .role_decisions = try reconciliation.roleDecisions(a, &.{.{ .signal_id = .{ .ordinal = 1 }, .generation_roles = roles }}) } };
        var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const resource = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .unlimited));
        const restricted = try @import("domain/model_result_schema.zig").restrict(std.testing.allocator, resource.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer restricted.release();
        const check = @import("model_payload_schema_test.zig").checkDocument;
        try check(restricted.selected().modelBytes(), .{ .bytes = try codec.encodeSelected(stage.Response, a, bad), .rejection = .enum_mismatch, .path = "/role_decisions/title/signal_ids/0" });
        const rejected = try stage.collect(a, .{ .roles = signals }, packet, try codec.encodeSelected(stage.Response, a, bad), origin);
        const failure = (try reconciliation.validate_roles.execute(a, (try reconciliation.validate_signals.execute(a, (try reconciliation.validate_dispositions.execute(a, rejected)).valid, fixture.context())).valid)).invalid;
        try std.testing.expectEqual(.role_assignment, failure.issue.rule);
        try std.testing.expectEqualDeep(origin, failure.origin.?);
        const good: stage.Response = .{ .roles = .{ .role_decisions = try reconciliation.roleDecisions(a, &.{.{ .signal_id = .{ .ordinal = 2 }, .generation_roles = roles }}) } };
        try check(restricted.selected().modelBytes(), .{ .bytes = try codec.encodeSelected(stage.Response, a, good) });
        const accepted = try stage.collect(a, .{ .roles = signals }, packet, try codec.encodeSelected(stage.Response, a, good), origin);
        const complete = (try reconciliation.finish(a, global, accepted.proposal.global, fixture.context())).valid;
        try binding.validate(refs.records(complete), fixture.inputs);
        try std.testing.expectEqual(@as(usize, 1), try binding.recordCount(refs.records(complete)));
        try std.testing.expectEqual(@as(usize, 0), complete.records.signals[0].value.generation_roles.len);
        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
        const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.inputs.chunks.partition);
        const stored = try snapshot.build(.{ .bytes = "references" }, fixture.inputs, fixture.extracted, complete, fixture.text.registry, contract);
        try snapshot.validate(a, stored);
        var forged = stored;
        const changed = try a.dupe(r.Signal, stored.signals);
        changed[0].value.generation_roles = roles;
        forged.signals = changed;
        try std.testing.expectError(error.InvalidReferenceSnapshot, snapshot.validate(a, forged));
    };
}

fn exerciseAssignmentPackets(allocator: std.mem.Allocator, source_text: []const u8) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &.{source_text});
    defer fixture.deinit();
    const initial = try reconciliation.initialize(a, fixture.inputs, fixture.extracted, 2);
    const summary = try reconciliation.build_input.execute(a, initial);
    const summary_packet = try input.reconciliationCompositionPacket(allocator, summary, fixture.inputs, fixture.text.registry);
    defer packets.release(summary_packet);
    try std.testing.expect(summary_packet.assignmentContext(.{ .bytes = "summary" }) != null);
    try std.testing.expect(summary_packet.assignmentContext(.{ .bytes = "roles" }) == null);
    const selected_summary = try packets.withAssignmentContext(allocator, summary_packet, .{ .bytes = "summary" });
    defer packets.release(selected_summary);
    try checkSemanticAssignment(a, selected_summary, summary.items, null);
    const global = try reconciliation.summaries(a, initial, fixture.context());
    try std.testing.expectError(error.InvalidReferenceReconciliation, input.reconciliationCompositionPacket(allocator, global, fixture.inputs, fixture.text.registry));
    const stage = @import("domain/reference_reconciliation_stage.zig");
    var candidate: reconciliation.r.Parsed = .{ .phase = .dispositions, .input = global, .proposal = .{ .global = try reconciliation.global(a, global) } };
    const dispositions = (try reconciliation.validate_dispositions.execute(a, candidate)).valid;
    candidate.phase = .signals;
    const signals = (try reconciliation.validate_signals.execute(a, (try reconciliation.validate_dispositions.execute(a, candidate)).valid, fixture.context())).valid;
    var role_candidate = signals;
    role_candidate.prior.phase = .roles;
    const roles = (try reconciliation.validate_roles.execute(a, role_candidate)).valid;
    const full = try input.reconciliationPacket(allocator, global, fixture.inputs, fixture.text.registry, .all);
    defer packets.release(full);
    const full_json = try std.json.parseFromSlice(std.json.Value, a, full.body(), .{});
    defer full_json.deinit();
    for ([_][]const u8{ "dispositions", "signals", "roles", "conflicts" }) |id| {
        const prior: stage.Prior = if (std.mem.eql(u8, id, "dispositions")) .{ .dispositions = global } else if (std.mem.eql(u8, id, "signals")) .{ .signals = dispositions } else if (std.mem.eql(u8, id, "roles")) .{ .roles = signals } else .{ .conflicts = roles };
        const selected = try stage.packet(allocator, prior, fixture.inputs, fixture.text.registry);
        defer packets.release(selected);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, selected.body(), .{});
        defer parsed.deinit();
        try checkProjectedPacket(a, selected.body());
        for ([_][]const u8{ "claims", "citations", "preserved_tokens", "passive_literals" }) |field| {
            try std.testing.expectEqualStrings(
                try std.json.Stringify.valueAlloc(a, full_json.value.object.get(field).?, .{}),
                try std.json.Stringify.valueAlloc(a, parsed.value.object.get(field).?, .{}),
            );
        }
        const assignment = parsed.value.object.get("assignment").?.object;
        if (std.mem.eql(u8, id, "roles")) {
            try std.testing.expect(!assignment.contains("summaries"));
            try std.testing.expect(!assignment.contains("member_summary_ids"));
            const rules = assignment.get("constraints").?.array.items;
            try std.testing.expectEqual(@as(usize, 1), rules.len);
            try std.testing.expectEqualStrings("supported_role_assignment", rules[0].object.get("constraint").?.string);
            try std.testing.expectEqual(@as(usize, 6), assignment.get("role_definitions").?.array.items.len);
            for (assignment.get("role_definitions").?.array.items) |definition| {
                const role = std.meta.stringToEnum(reconciliation.r.GenerationRole, definition.object.get("role").?.string).?;
                try std.testing.expectEqualStrings(try role.purpose(a), definition.object.get("purpose").?.string);
            }
        } else {
            try std.testing.expectEqual(!std.mem.eql(u8, id, "conflicts"), assignment.contains("summaries"));
            const encoded_rules = try std.json.Stringify.valueAlloc(a, assignment.get("constraints").?, .{});
            try std.testing.expect(std.mem.indexOf(u8, encoded_rules, "supported_role_assignment") == null);
            if (std.mem.eql(u8, id, "dispositions")) try std.testing.expect(std.mem.indexOf(u8, encoded_rules, "reciprocal_conflict") != null);
            if (std.mem.eql(u8, id, "signals")) {
                try std.testing.expect(std.mem.indexOf(u8, encoded_rules, "retained_claim_covered") != null);
                try checkSemanticAssignment(a, selected, global.items, dispositions.dispositions);
            }
            if (std.mem.eql(u8, id, "conflicts")) {
                try std.testing.expect(std.mem.indexOf(u8, encoded_rules, "conflict_pair_covered") != null);
                try std.testing.expect(std.mem.indexOf(u8, encoded_rules, "nonempty_unique_allowed_claims") == null);
                try std.testing.expect(!assignment.contains("claim_ids"));
                try std.testing.expect(!assignment.contains("member_claim_ids"));
            }
        }
    }
}

fn checkSemanticAssignment(a: std.mem.Allocator, packet: *const packets.Packet, items: []const reconciliation.r.Item, dispositions: ?[]const reconciliation.r.ClaimDisposition) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    defer parsed.deinit();
    const assignment = parsed.value.object.get("assignment").?.object;
    try std.testing.expect(!assignment.contains("member_claim_ids"));
    const ids = assignment.get("claim_ids").?.array.items;
    var index: usize = 0;
    for (items) |item| {
        if (item.claim.content != .model) continue;
        if (dispositions) |values| if (!(try @import("domain/reference_reconciliation_validation.zig").signalEligible(values, item.claim.id))) continue;
        try std.testing.expect(index < ids.len);
        try std.testing.expectEqual(@as(i64, item.claim.id.ordinal), ids[index].integer);
        index += 1;
    }
    try std.testing.expectEqual(index, ids.len);
}

test "signal assignments exclude conflicting semantic members while retaining their evidence" {
    const stage = @import("domain/reference_reconciliation_stage.zig");
    const r = reconciliation.r;
    for ([_][3][]const u8{
        .{ "Display the greeting.\n", "Suppress the greeting.\n", "Display the current UTC time and `Ready`.\n" },
        .{ "Approve the renewal.\n", "Reject the renewal.\n", "Retain the receipt and `Recorded`.\n" },
    }) |sources| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &sources);
        defer fixture.deinit();
        const global = try reconciliation.summaries(a, try reconciliation.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        var candidate: r.Parsed = .{ .phase = .dispositions, .input = global, .proposal = .{ .global = try reconciliation.global(a, global) } };
        const values = try a.dupe(r.ClaimDispositionProposal, candidate.proposal.global.claim_dispositions);
        values[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{values[1].claim_id} } };
        values[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{values[0].claim_id} } };
        candidate.proposal.global.claim_dispositions = values;
        candidate.proposal.global.conflict_groups = &.{.{ .claim_ids = &.{ values[0].claim_id, values[1].claim_id } }};
        const accepted = (try reconciliation.validate_dispositions.execute(a, candidate)).valid;
        const packet = try stage.packet(std.testing.allocator, .{ .signals = accepted }, fixture.inputs, fixture.text.registry);
        defer packets.release(packet);
        try checkSemanticAssignment(a, packet, global.items, accepted.dispositions);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const assignment = parsed.value.object.get("assignment").?.object;
        try std.testing.expectEqual(@as(usize, 1), assignment.get("claim_ids").?.array.items.len);
        try std.testing.expectEqual(global.items.len, parsed.value.object.get("claims").?.array.items.len);
        try std.testing.expectEqual(@as(usize, 1), parsed.value.object.get("preserved_tokens").?.array.items.len);
    }
}

test "token-only summary assignments are empty while native construction preserves every occurrence" {
    for ([_][]const u8{ "Display `Hello!` and `Goodbye!`.\n", "Display `Loan renewed!` and `Receipt saved!`.\n" }) |source_text| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &.{source_text});
        defer fixture.deinit();
        const candidates = try tokens.candidates(a, fixture.inputs);
        const results = try a.alloc(reconciliation.r.extraction.RawResult, fixture.inputs.chunks.entries.len);
        for (fixture.inputs.chunks.entries, results) |chunk, *result| result.* = .{
            .scope = .{ .state_id = fixture.inputs.corpus.state_id, .chunk_id = chunk.id },
            .result = .{ .response = try tokens.wire(a, "{\"kind\":\"claims\",\"claims\":[]}", try tokens.classifications(a, candidates, chunk)) },
        };
        const extracted = try extraction.finish(a, fixture.inputs, results);
        const summary = try reconciliation.build_input.execute(a, try reconciliation.initialize(a, fixture.inputs, extracted, 2));
        const packet = try input.reconciliationCompositionPacket(std.testing.allocator, summary, fixture.inputs, fixture.text.registry);
        defer packets.release(packet);
        const selected = try packets.withAssignmentContext(std.testing.allocator, packet, .{ .bytes = "summary" });
        defer packets.release(selected);
        try checkSemanticAssignment(a, selected, summary.items, null);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, selected.body(), .{});
        try std.testing.expectEqual(@as(usize, 0), parsed.value.object.get("assignment").?.object.get("claim_ids").?.array.items.len);
        try std.testing.expectEqual(@as(usize, 2), parsed.value.object.get("preserved_tokens").?.array.items.len);
        const native = try reconciliation.parse.execute(a, .{ .input = summary, .bytes = "{\"statements\":[]}" });
        try std.testing.expectEqual(@as(usize, 2), (try reconciliation.validate_summary.execute(a, native, fixture.context())).valid.statements.len);
        for (native.proposal.summary.statements, 0..) |statement, i| {
            try std.testing.expectEqual(.preserved_token, std.meta.activeTag(statement.content));
            try std.testing.expect(native.source.at(.{ .statement = i }, .record) == null);
        }
    }
}

test "shared text choice refresh retains unrelated restrictions and replaces stale text IDs" {
    const base = try packets.create(std.testing.allocator, "{}", .workflow_step, .initial_generation, null);
    defer packets.release(base);
    const fixed = try packets.withExcludedVariants(std.testing.allocator, base, &.{.{ .kind = "source" }});
    defer packets.release(fixed);
    const scoped = try packets.withIntegerChoices(std.testing.allocator, fixed, &.{.{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = .{ .bytes = "selection" }, .allowed = &.{3} }});
    defer packets.release(scoped);
    const first = try input.withTextChoices(std.testing.allocator, scoped, &.{7}, &.{});
    defer packets.release(first);
    try std.testing.expectEqual(@as(usize, 2), first.excludedVariants().len);
    try std.testing.expectEqualStrings("source", first.excludedVariants()[0].kind);
    try std.testing.expectEqualStrings("exact_copy", first.excludedVariants()[1].kind);
    const second = try input.withTextChoices(std.testing.allocator, first, &.{}, &.{2});
    defer packets.release(second);
    try std.testing.expectEqual(@as(usize, 2), second.excludedVariants().len);
    try std.testing.expectEqualStrings("source", second.excludedVariants()[0].kind);
    try std.testing.expectEqualStrings("passive", second.excludedVariants()[1].kind);
    try std.testing.expectEqual(@as(usize, 2), second.integerChoices().len);
    try std.testing.expectEqualDeep(scoped.integerChoices()[0], second.integerChoices()[0]);
    try std.testing.expectEqualStrings("exact_copy", second.integerChoices()[1].target.tagged.kind);
    try std.testing.expectEqualDeep(&[_]i64{2}, second.integerChoices()[1].allowed);
    const third = try input.withTextChoices(std.testing.allocator, second, &.{9}, &.{4});
    defer packets.release(third);
    try std.testing.expectEqualDeep(scoped.integerChoices()[0], third.integerChoices()[0]);
    try std.testing.expectEqualDeep(&[_]i64{9}, third.integerChoices()[1].allowed);
    try std.testing.expectEqualDeep(&[_]i64{4}, third.integerChoices()[2].allowed);
}

test "summary and signal schemas restrict semantic claim choices while retaining native token evidence" {
    const r = reconciliation.r;
    const stage = @import("domain/reference_reconciliation_stage.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    const schema = @import("domain/model_result_schema.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .unlimited));
    for ([_][]const u8{ "MOCK Start and display `MOCK Hello!`.\n", "MOCK Renew and display `MOCK Renewed!`.\n" }) |source_text| {
        const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &.{source_text});
        defer fixture.deinit();
        const initial = try reconciliation.initialize(a, fixture.inputs, fixture.extracted, 2);
        const summary = try reconciliation.build_input.execute(a, initial);
        const summary_packet = try input.reconciliationCompositionPacket(std.testing.allocator, summary, fixture.inputs, fixture.text.registry);
        defer packets.release(summary_packet);
        const global = try reconciliation.summaries(a, initial, fixture.context());
        const candidate: r.Parsed = .{ .phase = .dispositions, .input = global, .proposal = .{ .global = try reconciliation.global(a, global) } };
        const disposition = (try reconciliation.validate_dispositions.execute(a, candidate)).valid;
        const signal_packet = try stage.packet(std.testing.allocator, .{ .signals = disposition }, fixture.inputs, fixture.text.registry);
        defer packets.release(signal_packet);
        const semantic = for (summary.items) |item| {
            if (item.claim.content == .model) break item.claim.id;
        } else return error.MissingSemanticClaim;
        const token = for (summary.items) |item| {
            if (item.claim.content == .preserved_token) break item.claim.id;
        } else return error.MissingTokenClaim;
        for ([_]*const packets.Packet{ summary_packet, signal_packet }, [_][]const u8{ "statements", "signals" }) |packet, field| {
            const selected = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer selected.release();
            for ([_]r.ClaimId{ semantic, token, .{ .ordinal = 999 } }, 0..) |claim, index| {
                const bytes = try std.fmt.allocPrint(a, "{{\"{s}\":[{{\"claim_ids\":[{d}],\"content\":{{\"kind\":\"model\",\"model\":{{\"kind\":\"business\",\"segments\":[\"MOCK authored meaning\"]}}}}}}]}}", .{ field, claim.ordinal });
                try check(selected.selected().modelBytes(), .{ .bytes = bytes, .rejection = if (index == 0) null else .enum_mismatch, .path = if (index == 0) null else if (packet == summary_packet) "/statements/0/claim_ids/0" else "/signals/0/claim_ids/0" });
            }
            // Membership enums do not replace native coverage or provenance checks.
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try std.testing.expectEqual(summary.items.len, body.get("claims").?.array.items.len);
            try std.testing.expectEqual(@as(usize, 1), body.get("preserved_tokens").?.array.items.len);
        }
        const disposition_packet = try stage.packet(std.testing.allocator, .{ .dispositions = global }, fixture.inputs, fixture.text.registry);
        defer packets.release(disposition_packet);
        const selected = try schema.restrict(std.testing.allocator, schemas.select(disposition_packet.resultDefinition().?).?, disposition_packet.excludedVariants(), disposition_packet.integerChoices());
        defer selected.release();
        const choices = @import("domain/reference_conflict_groups.zig");
        for ([_]r.ClaimId{ semantic, .{ .ordinal = 999 } }, 0..) |claim, index| {
            const bytes = try codec.encode(choices.Selection, a, .{ .claim_dispositions = &.{.{ .claim_id = claim, .disposition = .{ .retained = .{} } }}, .conflict_groups = &.{} });
            try check(selected.selected().modelBytes(), .{ .bytes = bytes, .rejection = if (index == 0) null else .enum_mismatch, .path = if (index == 0) null else "/claim_dispositions/0/claim_id" });
        }
    }
}

test "disposition repair schemas reuse canonical eligibility without authorizing foreign relationships" {
    const schema = @import("domain/model_result_schema.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .unlimited));
    for ([_][2][]const u8{
        .{ "MOCK Start the application.\n", "MOCK Display the timestamp.\n" },
        .{ "MOCK Renew the loan.\n", "MOCK Display the deadline.\n" },
    }) |sources| {
        const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &sources);
        defer fixture.deinit();
        const global = try reconciliation.summaries(a, try reconciliation.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        const proposal = try reconciliation.global(a, global);
        const native = (try @import("domain/reference_disposition_validation.zig").repairChoices(a, global.progress.plan.layout.items, proposal.claim_dispositions, 0, proposal.claim_dispositions[0].claim_id)).?;
        try std.testing.expect(native.duplicate_targets.len != 0);
        const base = try packets.create(std.testing.allocator, "{}", .workflow_step, .initial_generation, .{ .bytes = "repair_disposition" });
        defer packets.release(base);
        const packet = try input.withDispositionChoices(std.testing.allocator, base, global.partition.group.claim_ids, native, false);
        defer packets.release(packet);
        const restricted = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer restricted.release();
        const good = try std.fmt.allocPrint(a, "{{\"kind\":\"duplicate\",\"target_claim_id\":{d}}}", .{native.duplicate_targets[0].ordinal});
        try check(restricted.selected().modelBytes(), .{ .bytes = good });
        try check(restricted.selected().modelBytes(), .{ .bytes = "{\"kind\":\"duplicate\",\"target_claim_id\":999}", .rejection = .enum_mismatch, .path = "/target_claim_id" });
    }
}
fn exercisePackets(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: source.IdSource = .{};
    const inputs = try source.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "requirements.md", "Display `Hello, World!`.\n"));
    const passive = try text.prepare(a, inputs);
    defer passive.deinit();
    const candidates = try tokens.candidates(a, inputs);
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const content: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const classified: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const producers: @import("domain/reference_extraction.zig").ProducerOrigins = .{ .content = content, .classifications = classified };
    var progress = try iteration.initialize(a, inputs);
    for (inputs.chunks.entries) |chunk| {
        const scope = iteration.current(progress).?;
        const packet = try input.extractionPacket(allocator, inputs, passive.registry, candidates, scope);
        defer packets.release(packet);
        try std.testing.expectEqual(.reference_chunk, std.meta.activeTag(packet.unit()));
        try std.testing.expectEqualStrings(chunk.id.bytes, packet.unit().reference_chunk.chunk_id.bytes);
        var body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        defer body.deinit();
        var reconstructed: std.ArrayList(u8) = .empty;
        defer reconstructed.deinit(a);
        for (body.value.object.get("source_lines").?.array.items, 1..) |line, ordinal| {
            try std.testing.expectEqual(@as(i64, @intCast(ordinal)), line.object.get("id").?.integer);
            try reconstructed.appendSlice(a, line.object.get("text").?.string);
        }
        try std.testing.expectEqualStrings(inputs.corpus.sources[0].bytes[chunk.span.start.byte..chunk.span.end.byte], reconstructed.items);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Hello, World!") != null);
        const response = try tokens.wire(a, try extraction.reply(a, chunk, "The application displays a greeting."), try tokens.classifications(a, candidates, chunk));
        progress = try iteration.append(a, progress, scope, response, content, producers);
    }
    try std.testing.expect(iteration.current(progress) == null);
    const raw = try iteration.finish(a, progress);
    try std.testing.expectEqualDeep(content, raw.entries[0].origin.?);
    try std.testing.expectEqualDeep(producers, raw.entries[0].producers.?);
    const extracted = try extraction.finish(a, inputs, raw.entries);
    const context: reconciliation.Context = .{ .inputs = inputs, .registry = passive.registry, .current = text.safety.value(passive.owner) };
    const initial = try reconciliation.initialize(a, inputs, extracted, 2);
    const global = try reconciliation.summaries(a, initial, context);
    const packet = try input.reconciliationPacket(allocator, global, inputs, passive.registry, .all);
    defer packets.release(packet);
    try checkProjectedPacket(a, packet.body());
    try std.testing.expectEqual(.reference_global, std.meta.activeTag(packet.unit()));
    try std.testing.expectEqualStrings("global", packet.resultDefinition().?.bytes);
    const projected = try @import("domain/model_evidence.zig").project(a, global.items);
    try std.testing.expectEqual(global.items.len, projected.claims.len);
    var body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    defer body.deinit();
    try std.testing.expectEqual(global.items.len, body.value.object.get("claims").?.array.items.len);
    try std.testing.expectEqual(projected.citations.len, body.value.object.get("citations").?.array.items.len);
    for (global.items, projected.claims) |item, claim| {
        try std.testing.expectEqualDeep(item.claim.id, claim.id);
        try std.testing.expectEqualDeep(item.claim.citation_ids, claim.citation_ids);
        switch (item.claim.content) {
            .model => |value| try std.testing.expectEqualDeep(@import("domain/model_evidence.zig").modelContent(value), claim.content.model),
            .preserved_token => |token| {
                try std.testing.expectEqualDeep(token.value.id, claim.content.preserved_token.token_id);
                const copy = projected.preserved_tokens[0];
                try std.testing.expectEqualStrings(token.value.raw_value.bytes, copy.value);
                try std.testing.expectEqualDeep(token.value.id, copy.id);
            },
        }
        for (item.citations) |citation| {
            var matches: usize = 0;
            for (projected.citations) |copy| if (copy.id.ordinal == citation.id.ordinal) {
                matches += 1;
                try std.testing.expectEqualDeep(citation, copy);
            };
            try std.testing.expectEqual(@as(usize, 1), matches);
        }
    }
    for ([_][]const u8{ "chunk_id", "reference_state_id", "result_definition", "extractor", "raw_value" }) |internal| {
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), internal) == null);
    }
    const accounted = (try reconciliation.finish(a, global, try reconciliation.global(a, global), context)).valid;
    try std.testing.expectEqual(.complete, accounted.outcome);
    try std.testing.expectEqual(extracted.ledger.claims.len, global.items.len);
}

/// The same model content must decode under the response contract wherever it
/// appears as evidence. This checks production packet bytes, not native views.
pub fn checkProjectedPacket(a: std.mem.Allocator, bytes: []const u8) !void {
    const r = @import("domain/reference_reconciliation.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    const body = if (parsed.value.object.get("input")) |base| base.object else parsed.value.object;
    for (body.get("claims").?.array.items) |claim| {
        const raw = try std.json.Stringify.valueAlloc(a, claim.object.get("content").?, .{});
        const content = try codec.decode(r.ContentProposal, a, raw);
        if (content == .preserved_token) {
            const id = content.preserved_token.token_id;
            for (body.get("preserved_tokens").?.array.items) |token| {
                if (token.object.get("id").?.integer == id.ordinal) {
                    try std.testing.expect(token.object.get("value").?.string.len != 0);
                    break;
                }
            } else return error.MissingTokenEvidence;
        }
    }
    if (body.get("summaries")) |summaries| for (summaries.array.items) |summary| {
        for (summary.object.get("statements").?.array.items) |statement| {
            _ = try codec.decode(r.ContentProposal, a, try std.json.Stringify.valueAlloc(a, statement.object.get("content").?, .{}));
        }
    };
    if (body.get("signals")) |signals| for (signals.array.items) |signal| {
        _ = try codec.decode(@FieldType(@import("domain/model_evidence.zig").Signal, "value"), a, try std.json.Stringify.valueAlloc(a, signal.object.get("value").?, .{}));
    };
    if (body.get("conflicts")) |conflicts| for (conflicts.array.items) |conflict| {
        _ = try codec.decode(@FieldType(@import("domain/model_evidence.zig").Conflict, "value"), a, try std.json.Stringify.valueAlloc(a, conflict.object.get("value").?, .{}));
    };
    if (body.get("brief")) |brief| if (brief != .null) {
        _ = try codec.decode(@import("domain/specification.zig").Brief, a, try std.json.Stringify.valueAlloc(a, brief, .{}));
    };
}

test "every reference content kind projects validated text into the shared model wire contract" {
    const r = @import("domain/reference_reconciliation.zig");
    const projection = @import("domain/model_evidence.zig");
    const codec = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (comptime std.meta.tags(r.extraction.Kind)) |kind| {
        const value: r.Content = .{ .model = @unionInit(r.extraction.Content, @tagName(kind), switch (kind) {
            .business, .scope_guard => .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "A librarian renews a loan." } }} } },
            else => .{ .value = .{ .nodes = &.{.{ .literal = .{ .value = "A librarian renews a loan." } }} } },
        }) };
        const projected = projection.content(value);
        const wire = try codec.encode(r.ContentProposal, a, projected);
        try std.testing.expectEqualDeep(projected, try codec.decode(r.ContentProposal, a, wire));
        const parsed = try std.json.parseFromSlice(std.json.Value, a, wire, .{});
        try std.testing.expectEqualStrings("model", parsed.value.object.get("kind").?.string);
        const model = parsed.value.object.get("model").?.object;
        try std.testing.expectEqualStrings(@tagName(kind), model.get("kind").?.string);
        try std.testing.expect(model.get("value") == null);
        const nodes = model.get(if (kind == .business or kind == .scope_guard) "segments" else "nodes").?.array.items;
        try std.testing.expectEqualStrings("A librarian renews a loan.", nodes[0].string);
    }
}
test "extraction collection rejects missing duplicate foreign and out of order scope" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: source.IdSource = .{};
    const inputs = try source.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "renewals.md", "A librarian renews loans.\n" ** 70));
    const initial = try iteration.initialize(a, inputs);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.finish(a, initial));
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, initial, initial.scopes[1], extraction.no_claim, null, null));
    var foreign = initial.scopes[0];
    foreign.state_id.bytes = "foreign";
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, initial, foreign, extraction.no_claim, null, null));
    const once = try iteration.append(a, initial, initial.scopes[0], extraction.no_claim, null, null);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, once, initial.scopes[0], extraction.no_claim, null, null));
    const complete = try iteration.append(a, once, initial.scopes[1], extraction.no_claim, null, null);
    try std.testing.expectError(error.InvalidReferenceExtraction, iteration.append(a, complete, initial.scopes[1], extraction.no_claim, null, null));
    try std.testing.expectEqual(@as(usize, 2), (try iteration.finish(a, complete)).entries.len);
}
test "packet body and domain identity are owned independently of caller allocations" {
    var bytes = [_]u8{'x'};
    var selector = "answer".*;
    const packet = try packets.create(std.testing.allocator, &bytes, .{ .reference_global = .{ .reference_state_id = .{ .bytes = "reference-current" }, .unit_slot_id = .{ .bytes = "meaning" } } }, .initial_generation, .{ .bytes = &selector });
    bytes[0] = 'y';
    @memset(&selector, 'x');
    const retained = try packets.retain(packet);
    packets.release(packet);
    defer packets.release(retained);
    try std.testing.expectEqualStrings("x", retained.body());
    try std.testing.expectEqualStrings("reference-current", retained.unit().reference_global.reference_state_id.bytes);
    try std.testing.expectEqualStrings("answer", retained.resultDefinition().?.bytes);
    try std.testing.expectError(error.InvalidModelInputPacket, packets.create(std.testing.allocator, "", .workflow_step, .initial_generation, null));
    try std.testing.expectError(error.InvalidModelInputPacket, packets.create(std.testing.allocator, "{}", .workflow_step, .initial_generation, .{ .bytes = "../answer" }));
}

test "typed and admitted packet context preserve exact numbers and assignment ownership" {
    try packetContextPrecision(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, packetContextPrecision, .{});
    const base = try packets.create(std.testing.allocator, "{\"candidate\":{}}", .workflow_step, .initial_generation, null);
    defer packets.release(base);
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withContext(struct {}, std.testing.allocator, base, "candidate", .{}));
}

test "packet projections replace native contexts while preserving repair authority and ownership" {
    try repairPacketContexts(std.testing.allocator);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, repairPacketContexts, .{});
}
fn repairPacketContexts(allocator: std.mem.Allocator) !void {
    const authorization = "native-repair";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(authorization, &digest, .{});
    const permit: @import("domain/workflow_retry.zig").Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) }, .authorization = digest, .revision = 7, .maximum_targets = 1 };
    const producer: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 3 } };
    const derived = owned: {
        const base = try packets.createRepair(allocator, "{\"evidence\":1e0}", .workflow_step, .{ .atomic_repair = .{ .bytes = authorization } }, .{ .bytes = "replacement" }, permit, producer);
        defer packets.release(base);
        const original = try packets.withAssignmentContexts(allocator, base, &.{.{ .id = .{ .bytes = "old" }, .body = "{}" }});
        defer packets.release(original);
        const replaced = try packets.withAssignmentContexts(allocator, original, &.{.{ .id = .{ .bytes = "current" }, .body = "{\"instruction\":\"Preserve evidence\"}" }});
        defer packets.release(replaced);
        const restricted = try packets.withRestrictions(allocator, replaced, &.{.{ .kind = "unavailable" }}, &.{.{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = &.{7} }});
        defer packets.release(restricted);
        const selected = try packets.withAssignmentContext(allocator, restricted, .{ .bytes = "current" });
        defer packets.release(selected);
        const scoped = try packets.withIntegerChoices(allocator, selected, &.{.{ .target = .{ .path = &.{ .{ .property = "records" }, .{ .items = {} }, .{ .property = "source_ids" } } }, .definition = .{ .bytes = "replacement" }, .allowed = &.{ 3, 8 } }});
        defer packets.release(scoped);
        break :owned try packets.withContext(struct { value: bool }, allocator, scoped, "prerequisites", .{ .value = true });
    };
    defer packets.release(derived);
    try std.testing.expectEqualStrings("{\"evidence\":1e0,\"assignment\":{\"instruction\":\"Preserve evidence\"},\"prerequisites\":{\"value\":true}}", derived.body());
    try std.testing.expect(derived.assignmentContext(.{ .bytes = "old" }) == null);
    try std.testing.expectEqualStrings("{\"instruction\":\"Preserve evidence\"}", derived.assignmentContext(.{ .bytes = "current" }).?);
    try std.testing.expectEqualDeep(permit, derived.repairPermit().?);
    try std.testing.expectEqualDeep(producer, derived.repairOrigin().?);
    try std.testing.expect(derived.unit() == .workflow_step);
    try std.testing.expectEqualStrings(authorization, derived.purpose().atomic_repair.bytes);
    try std.testing.expectEqualStrings("replacement", derived.resultDefinition().?.bytes);
    try std.testing.expectEqual(@as(usize, 2), derived.integerChoices().len);
    try std.testing.expectEqualStrings("exact_copy", derived.integerChoices()[0].target.tagged.kind);
    try std.testing.expectEqualStrings("claim_id", derived.integerChoices()[0].target.tagged.field);
    try std.testing.expectEqualSlices(i64, &.{7}, derived.integerChoices()[0].allowed);
    try std.testing.expectEqualStrings("replacement", derived.integerChoices()[1].definition.?.bytes);
    try std.testing.expectEqualSlices(i64, &.{ 3, 8 }, derived.integerChoices()[1].allowed);
    try std.testing.expectEqualStrings("source_ids", derived.integerChoices()[1].target.path[2].property);
    try std.testing.expectEqual(@as(usize, 1), derived.excludedVariants().len);
    try std.testing.expectEqualStrings("unavailable", derived.excludedVariants()[0].kind);
}

fn packetContextPrecision(allocator: std.mem.Allocator) !void {
    const body = "{\"amount\":9007199254740993.0,\"rate\":0.10000000000000000000000000001,\"items\":[1e0,-0.0]}";
    const unit: @import("domain/model_request_identity.zig").ImmutableUnitOwnerId = .{ .plan_unit = .{
        .plan_input_authority_state_id = .{ .bytes = "plan-current" },
        .unit_slot_id = .{ .bytes = "limits" },
    } };
    const base = try packets.create(allocator, body, unit, .{ .semantic_review = .{ .bytes = "precision" } }, .{ .bytes = "limits" });
    defer packets.release(base);
    const Context = struct { offset: f64, note: []const u8 };
    const context: Context = .{ .offset = -0.0, .note = "keep exact" };
    const encoded = try @import("domain/model_candidate_json.zig").encode(Context, allocator, context);
    defer allocator.free(encoded);
    var parsed = try @import("domain/strict_json.zig").parse(allocator, encoded, .{ .maximum_depth = 8 }, false, null);
    defer parsed.deinit();
    const expected = try std.fmt.allocPrint(allocator, "{s},\"prerequisites\":{s}}}", .{ body[0 .. body.len - 1], encoded });
    defer allocator.free(expected);
    for ([_]bool{ false, true }) |typed| {
        const derived = if (typed)
            try packets.withContext(Context, allocator, base, "prerequisites", context)
        else
            try packets.withJsonContext(allocator, base, "prerequisites", parsed.value);
        defer packets.release(derived);
        try std.testing.expectEqualStrings(expected, derived.body());
        try std.testing.expectEqualStrings(body, base.body());
        try std.testing.expectEqualDeep(base.unit(), derived.unit());
        try std.testing.expectEqualDeep(base.purpose(), derived.purpose());
        try std.testing.expectEqualStrings(base.resultDefinition().?.bytes, derived.resultDefinition().?.bytes);
    }
}
