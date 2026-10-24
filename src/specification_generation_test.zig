const std = @import("std");
const g = @import("domain/specification_generation.zig");
const spec = g.spec;
const provenance = @import("domain/specification_provenance.zig");
const identifiers = @import("domain/specification_identity.zig");
const references = @import("test_fixtures/reference_reconciliation.zig");
const evidence = @import("reference_evidence_test.zig");
const extraction = @import("reference_extraction_test.zig");
const text = @import("test_fixtures/reference_text.zig");
const validate_unit = @import("actions/specification/validate_specification_unit.zig").Action{ .validator = text.validator };
const tokens = @import("test_fixtures/reference_tokens.zig");

// Native review tests can construct a complete collection directly. Production
// model admission accepts the complete native unit or collection assignment,
// not this unconstrained complete-ledger wire shape.
fn collectReview(comptime Review: type, allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, bytes: []const u8, origin: ?@import("domain/model_candidate_origin.zig").Origin) !Review.Collection {
    const proposed = try @import("domain/model_candidate_json.zig").decode(Review.Review, allocator, bytes);
    const origins = try allocator.alloc(?@import("domain/model_candidate_origin.zig").Origin, proposed.entries.len);
    @memset(origins, origin);
    return Review.validate(allocator, inputs, context.inputs, .{
        .review = proposed,
        .origin = origin,
        .origins = origins,
        .omission_conflict_claims = if (Review == @import("domain/specification_support.zig").Source) context.references.records.assignments.checked.prior.prior.source.omission_conflict_claims else &.{},
    });
}

fn reviewPacketAt(comptime Review: type, allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, index: usize) !*@import("domain/model_input_packet.zig").Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const ledger = try @import("domain/required_authority.zig").build(arena.allocator(), inputs);
    return Review.packetFor(allocator, inputs, context, .{ .finding = ledger.requirements[index].seed.id });
}

test "source review record grouping calibration validates current association and assignment mechanics offline" {
    try @import("test_fixtures/source_review_record_calibration.zig").run();
}

test "authoring association qualification uses current production packets and native admission offline" {
    try @import("test_fixtures/authoring_association_calibration.zig").run();
}

test "draft readiness requires selectable provenance while source interpretation remains model assisted" {
    const check = @import("actions/specification/check_specification_source_readiness.zig").Action{};
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Start the application and display the current UTC time.", "Renew eligible loans and report their new deadline." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        try std.testing.expectEqual(.ok, check.execute(fixture.context.references));
        var blocked = fixture.context.references;
        blocked.outcome = .blocked;
        try std.testing.expectEqual(.blocked, check.execute(blocked));
        // Complete accounting does not imply that generation has positive evidence.
        var empty = try Fixture.initExtraction(a, source, null, false);
        defer empty.deinit();
        try std.testing.expectEqual(.complete, empty.context.references.outcome);
        try std.testing.expectEqual(.blocked, check.execute(empty.context.references));
        try std.testing.expectError(error.InvalidSpecificationUnit, @import("domain/specification_session.zig").initialize(a, .{ .bytes = "selected" }, empty.context));
    }
}

test "source preservation reviews the corpus before fields exist and reuses bounded omission repair" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const loss = @import("domain/source_omission.zig");
    const projector = @import("actions/authority/build_source_preservation_requirements.zig").Action{};
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][2][]const u8{
        .{ "# Startup display\nStart successfully and display the current UTC date and time.\n", "Display the time." },
        .{ "# Loan renewal\nRenew eligible loans; keep the deadline when renewal is refused.\n", "Renew loans." },
    }) |example| {
        var fixture = try Fixture.initContent(a, example[0], null, true, example[1], 1);
        defer fixture.deinit();
        const inputs = try projector.execute(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, fixture.context.inputs);
        const identity = @import("domain/model_request_identity.zig");
        const requests = try identity.createInitial(a, identity.RequestPurposeRegistry.all());
        defer identity.deinitOwner(requests);
        try std.testing.expect((try (@import("actions/specification/initialize_specification_review.zig").Action{}).execute(a, inputs, .{}, identity.ledger(requests))) == .initial);
        for ([_]@FieldType(authority.Inputs, "projection"){ .principle_assessment, .registered_obligations }) |projection| {
            var foreign = inputs;
            foreign.projection = projection;
            try std.testing.expectError(error.InvalidRequiredAuthority, (@import("actions/specification/initialize_specification_review.zig").Action{}).execute(a, foreign, .{}, identity.ledger(requests)));
        }
        const ledger = try authority.build(a, inputs);
        try std.testing.expectEqual(fixture.context.inputs.corpus.sources.len, ledger.requirements.len);
        const id = ledger.requirements[0].seed.id;
        try std.testing.expect(id.unit == .source);
        const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = id });
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("preservation_finding", packet.resultDefinition().?.bytes);
        const json = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        try std.testing.expect(!json.value.object.get("subject").?.object.contains("candidate"));
        try std.testing.expectEqualStrings(example[0], json.value.object.get("sources").?.array.items[0].object.get("text").?.string);
        try std.testing.expectEqual(@as(usize, 1), json.value.object.get("requirements").?.array.items.len);

        // Inserting a missing review keeps the same closed finding schema.
        const review_repair = @import("domain/specification_support_repair.zig").Source;
        const missing = try support.validate(a, inputs, fixture.context.inputs, .{ .review = .{ .entries = &.{} }, .origin = null, .origins = &.{} });
        try std.testing.expect(missing == .rejected);
        const missing_authority = try review_repair.authorize(a, inputs, fixture.context, missing.rejected);
        const replacement_packet = try review_repair.packet(std.testing.allocator, inputs, fixture.context, missing.rejected.candidate.?, missing_authority);
        defer @import("domain/model_input_packet.zig").release(replacement_packet);
        try std.testing.expectEqualStrings("preservation_finding", replacement_packet.resultDefinition().?.bytes);

        // The same shared collector/gate admits source loss and selects its producer.
        var finding: support.Finding = .{ .requirement_ordinal = 1, .value = .{
            .kind = .candidate_omission,
            .missing_obligation = example[0],
            .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} },
            .source_ids = &.{id.unit.source},
            .detail = "Extraction lost the named feature and its conditions.",
            .loss = .{ .extraction_claim = fixture.extracted.ledger.chunks[0].scope.chunk_id },
        } };
        finding.value.preservation = try @import("test_fixtures/source_omission_evidence.zig").proof(a, inputs, fixture.context.inputs, finding);
        const admitted = try support.validate(a, inputs, fixture.context.inputs, .{ .review = .{ .entries = &.{finding} }, .origin = null, .origins = &.{null} });
        try std.testing.expect(admitted == .accepted);
        const checked = try authority.build(a, admitted.accepted.inputs);
        const observations = try authority.buildObservations(a, checked);
        const result = try authority.reconcile(a, checked, observations);
        try std.testing.expectEqual(.invalid, result.continuation);
        const negative: loss.Support = .{ .repair_phase = .pre_generation, .review = admitted.accepted.candidate, .inputs = admitted.accepted.inputs, .observations = observations, .result = result };
        try std.testing.expect((try loss.select(a, fixture.context.inputs, negative)).location == .extraction_claim);
        const authorization = try @import("domain/reference_extraction_repair.zig").Omission.authorize(a, .{ .extraction = .{ .inputs = fixture.context.inputs, .candidates = try tokens.candidates(a, fixture.context.inputs), .candidate = fixture.extracted_text }, .support = negative });

        // Progress is judged against the stable original-source obligation.
        const rule = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, id);
        finding.value = .{ .kind = .supported, .provenance = .{ .claim_ids = rule.eligible_claim_ids, .clarification_response_ids = &.{} }, .source_ids = &.{id.unit.source}, .detail = "" };
        const positive = try support.validate(a, inputs, fixture.context.inputs, .{ .review = .{ .entries = &.{finding} }, .origin = null, .origins = &.{null} });
        try std.testing.expect(positive == .accepted);
        const transition = (try loss.admittedValidation(a, authorization.retry.?, positive.accepted)).?;
        try std.testing.expectEqual(.resolved, transition.validated.result);

        // Matching source IDs cannot substitute changed captured source bytes.
        var stale = fixture.context.inputs;
        const changed = try a.dupe(@import("domain/reference_evidence.zig").Source, stale.corpus.sources);
        changed[0].bytes = try std.mem.concat(a, u8, &.{ changed[0].bytes, "Another requirement.\n" });
        stale.corpus.sources = changed;
        try std.testing.expect((try support.validate(a, inputs, stale, .{ .review = .{ .entries = &.{finding} }, .origin = null, .origins = &.{null} })) == .rejected);

        // Neither a missing seed nor a model-authored question can widen this check.
        var incomplete = inputs;
        incomplete.seeds = &.{};
        try std.testing.expectError(error.InvalidRequiredAuthority, authority.build(a, incomplete));
        for (0..3) |mutation| {
            var tampered = inputs;
            const seeds = try a.dupe(authority.Seed, inputs.seeds);
            switch (mutation) {
                0 => seeds[0].id.slot = .text,
                1 => seeds[0].requiredness = .{ .accepted_authority = inputs.authorities[0] },
                2 => seeds[0].input_authorities = &.{},
                else => unreachable,
            }
            tampered.seeds = seeds;
            try std.testing.expectError(error.InvalidRequiredAuthority, authority.build(a, tampered));
        }
        for ([_]support.Decision{ .unsupported, .ambiguous, .conflicting }) |decision| {
            finding.value.kind = decision;
            finding.value.detail = "";
            finding.value.question = "";
            const forbidden = try support.validate(a, inputs, fixture.context.inputs, .{ .review = .{ .entries = &.{finding} }, .origin = null, .origins = &.{null} });
            try std.testing.expect(forbidden == .rejected);
            try std.testing.expectEqual(.invalid_decision, forbidden.rejected.rejection.selected().?.issue);
            try std.testing.expectEqual(.invalid_finding, forbidden.rejected.rejection.selected().?.evidence.?.issue);
            try std.testing.expectError(error.UnsafeSupportRepair, review_repair.authorize(a, inputs, fixture.context, forbidden.rejected));
        }
        finding.value.kind = .supported;
        finding.value.question = null;
        finding.value.source_ids = &.{.{ .ordinal = 999 }};
        try std.testing.expect((try support.validate(a, inputs, fixture.context.inputs, .{ .review = .{ .entries = &.{finding} }, .origin = null, .origins = &.{null} })) == .rejected);
    }
}

test "source preservation accounts for meaningful sources with empty extraction" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initExtraction(a, "# Known feature\nIts requirements are undecided.\n", null, false);
    defer fixture.deinit();
    const inputs = try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs);
    const id = inputs.seeds[0].id;
    const required = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, id);
    try std.testing.expectEqual(@as(usize, 0), required.eligible_claim_ids.len);
    try std.testing.expectEqual(.claim_or_source_required, required.rule(.supported, .{ .unlocalized = .{} }).minimum);
    const finding_packet = try support.packetFor(a, inputs, fixture.context, .{ .finding = id });
    defer @import("domain/model_input_packet.zig").release(finding_packet);
    const omitted = try support.collectFocused(a, inputs, fixture.context, null, finding_packet, "{\"kind\":\"candidate_omission\",\"source_ids\":[1],\"detail\":\"The supplied identity was discarded.\",\"missing_obligation\":\"MOCK The feature is named Known feature.\"}", null);
    try std.testing.expect(omitted == .accepted);
    try std.testing.expect(omitted.accepted.candidate.pending_localization != null);
    const packet = try support.packetForLoss(std.testing.allocator, inputs, fixture.context, omitted.accepted.candidate);
    defer @import("domain/model_input_packet.zig").release(packet);
    const foreign = try @import("domain/model_input_packet.zig").create(a, packet.body(), packet.unit(), .{ .semantic_review = .{ .bytes = "foreign-review" } }, packet.resultDefinition());
    defer @import("domain/model_input_packet.zig").release(foreign);
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collectLoss(a, inputs, fixture.context, omitted, foreign, "{}", null));
    const localized = try support.collectLoss(a, inputs, fixture.context, omitted, packet, try @import("test_fixtures/source_omission_evidence.zig").encode(a, try support.comparisonAssignment(a, inputs, fixture.context, omitted.accepted.candidate), .{ .extraction_claim = fixture.extracted.ledger.chunks[0].scope.chunk_id }), null);
    try std.testing.expect(localized == .accepted);
    const ledger = try authority.build(a, localized.accepted.inputs);
    const result = try authority.reconcile(a, ledger, try authority.buildObservations(a, ledger));
    try std.testing.expectEqual(.invalid, result.continuation);
}

test "draft generation and selected repair retain original source meaning without a parallel signal projection" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][2][]const u8{
        .{ "# Startup display\nStart successfully. Display the current time in UTC.\n", "Display the current time." },
        .{ "# Loan renewal\nRenew eligible loans. Keep the original deadline when renewal is refused.\n", "Renew loans." },
    }) |example| {
        var fixture = try Fixture.initContent(a, example[0], null, true, example[1], 1);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        const original = try sessions.packet(std.testing.allocator, current, fixture.context);
        defer packets.release(original);
        const good = try fixture.proposal(example[1]);
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = bad, .description = good, .primary_goal = good } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection);
        const correction = try repair.packet(std.testing.allocator, current, fixture.context, authorization);
        defer packets.release(correction);
        for ([_]*const packets.Packet{ original, correction }) |packet| {
            const decoded = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const input = if (packet == original) decoded.value else decoded.value.object.get("input").?;
            const sources = input.object.get("sources").?.array.items;
            try std.testing.expectEqual(fixture.context.inputs.corpus.sources.len, sources.len);
            for (fixture.context.inputs.corpus.sources, sources) |source, projected| {
                try std.testing.expectEqual(source.id.ordinal, projected.object.get("id").?.integer);
                try std.testing.expectEqualStrings(source.bytes, projected.object.get("text").?.string);
            }
            try std.testing.expect(!input.object.contains("signals"));
            try std.testing.expect(input.object.get("source_assignment").? == .object);
            try std.testing.expect(!input.object.contains("claims"));
            try std.testing.expect(!input.object.contains("citations"));
            const assignment = input.object.get("source_assignment").?.object;
            if (packet == original) {
                try std.testing.expectEqualStrings("A description of intended user-visible behavior.", assignment.get("description").?.object.get("purpose").?.string);
                try std.testing.expect(!input.object.contains("task"));
            } else {
                try std.testing.expect(!assignment.get("description").?.object.contains("purpose"));
                try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .display_name }), try selectedNativeRepairTask(input));
            }
            const groups = try @import("domain/model_candidate_json.zig").decode([]const @import("domain/specification_source_binding.zig").GroupGuidance, a, try std.json.Stringify.valueAlloc(a, input.object.get("source_groups").?, .{}));
            try expectAssignedRequirements(good.provenance.claim_ids, groups[0].requirements);
        }
        // Added source context does not widen valid provenance or authorize lost content.
        try std.testing.expectError(error.InvalidReferenceReconciliation, provenance.select(a, fixture.context, .{ .claim_ids = &.{.{ .ordinal = 999 }}, .clarification_response_ids = &.{} }));
        const recovered = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = good.value }, null);
        const validated = (try validate_unit.execute(a, current, fixture.context, recovered)).valid;
        try std.testing.expectEqualDeep(good.provenance.claim_ids, validated.response.content.brief.title.provenance.claim_ids);
        try std.testing.expectEqualDeep(candidate.response.content.brief.description, recovered.response.content.brief.description);
        try std.testing.expectEqualDeep(candidate.response.content.brief.primary_goal, recovered.response.content.brief.primary_goal);
    }
}

test "authoring assignments retain field purpose bound meaning and exact choices across source cases" {
    const sessions = @import("domain/specification_session.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const packets = @import("domain/model_input_packet.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const schema = @import("domain/model_result_schema.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
    // Retained call 9's lost title, an unrelated business domain, a legitimate
    // exact name, and an undecided source. These are packet/shape regressions;
    // the exported requests permit separate live semantic comparison.
    const cases = [_]struct { name: []const u8, source: []const u8, claim: []const u8 }{
        .{ .name = "hello", .source = "# MOCK Hello World Application\n\n## Requirements\n\n- The application must start successfully.\n- When started, the application must display `MOCK Hello, World!`.\n- Must also output date and time in UTC\n", .claim = "The application must start successfully.When started, the application must display `MOCK Hello, World!`.The application must also output date and time in UTC." },
        .{ .name = "renewal", .source = "# Library Loan Renewal\nA borrower may renew an eligible loan for fourteen days and sees `Loan renewed` and the new due date. Refused renewals retain the old due date.\n", .claim = "Borrowers renew eligible loans for fourteen days and see confirmation and the new due date. Refused renewals retain the old due date." },
        .{ .name = "exact-name", .source = "The feature must be named `Ready!`. It lets an operator confirm readiness and displays that same exact message after confirmation.\n", .claim = "The feature is named Ready! and lets an operator confirm readiness, then displays the required readiness message." },
        .{ .name = "missing-choice", .source = "# Renewal Policy\nBorrowers can renew eligible loans and see the new due date. The renewal duration is undecided and must be supplied by the owner.\n", .claim = "Borrowers renew eligible loans and see the new due date; the owner has not decided the renewal duration." },
    };
    try std.Io.Dir.cwd().createDirPath(std.testing.io, ".zig-cache/authoring-comparison");
    for (cases) |example| {
        var fixture = try Fixture.initContent(a, example.source, .business_exact_string, true, example.claim, 1);
        defer fixture.deinit();
        var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const good = try fixture.proposal(example.claim);
        for (0..sessions.unit_count) |index| {
            current.completed = index;
            if (index != 0) current.units[0] = (try g.validate(a, text.validator, fixture.context, .brief, .{ .content = .{ .brief = .{ .title = good, .description = good, .primary_goal = good } } })).valid;
            if (index == sessions.records_index) current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = good } } })).valid;
            const bound = try sessions.currentBinding(a, current, fixture.context);
            const before = try codec.encode(binding.Bound, a, bound);
            const packet = try sessions.packet(std.testing.allocator, current, fixture.context);
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try std.testing.expectEqual(index >= 2, body.contains("brief"));
            try std.testing.expectEqual(index == sessions.records_index, body.contains("entities"));
            if (body.get("brief")) |brief| {
                try std.testing.expectEqual(@as(usize, 3), brief.object.count());
                for ([_][]const u8{ "title", "description", "primary_goal" }) |field| try std.testing.expectEqualStrings(example.claim, brief.object.get(field).?.string);
            }
            if (body.get("entities")) |entities| {
                try std.testing.expectEqual(@as(usize, 2), entities.object.count());
                try std.testing.expectEqualStrings("not_applicable", entities.object.get("disposition").?.string);
                try std.testing.expectEqualStrings(example.claim, entities.object.get("basis").?.string);
            }
            if (index >= 2) try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(generationPacketAllocationCase, .{ current, fixture.context });
            const assigned = try codec.decode(binding.Guidance, a, try std.json.Stringify.valueAlloc(a, body.get("source_assignment").?, .{}));
            try std.testing.expectEqualStrings(before, try codec.encode(binding.Bound, a, bound));
            try std.testing.expectEqualStrings(example.source, body.get("sources").?.array.items[0].object.get("text").?.string);
            try std.testing.expectEqualStrings("write", body.get("operation").?.string);
            try std.testing.expect(!body.contains("claims"));
            try std.testing.expect(!body.contains("citations"));
            try std.testing.expect(!body.contains("unit"));
            const selected_requirements = if (assigned == .records) assigned.records.requirements else (try codec.decode([]const binding.GroupGuidance, a, try std.json.Stringify.valueAlloc(a, body.get("source_groups").?, .{})))[0].requirements;
            try std.testing.expectEqualStrings(example.claim, selected_requirements[0].meaning);
            for (body.get("context_requirements").?.array.items) |requirement| try std.testing.expect(!binding.assigns(assigned, .{ .ordinal = @intCast(requirement.object.get("claim_id").?.integer) }));
            switch (assigned) {
                .brief => |brief| {
                    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .display_name }), brief.title.purpose.?);
                    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .description }), brief.description.purpose.?);
                    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .primary_goal }), brief.primary_goal.purpose.?);
                    const selected = try schema.restrict(a, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
                    defer selected.release();
                    if (body.get("preserved_tokens").?.array.items.len != 0) {
                        const id = body.get("preserved_tokens").?.array.items[0].object.get("claim_id").?.integer;
                        const segment = if (body.get("preserved_tokens").?.array.items.len == 1) "{\"kind\":\"exact_copy\"}" else try std.fmt.allocPrint(a, "{{\"kind\":\"exact_copy\",\"claim_id\":{d}}}", .{id});
                        const wire = try std.fmt.allocPrint(a, "{{\"kind\":\"brief\",\"title\":{{\"signal_ids\":[1],\"value\":{{\"fragments\":[{s}]}}}},\"description\":{{\"signal_ids\":[1],\"value\":{{\"fragments\":[{s}]}}}},\"primary_goal\":{{\"signal_ids\":[1],\"value\":{{\"fragments\":[{s}]}}}}}}", .{ segment, segment, segment });
                        // Occurrence handles are native facts, never accepted
                        // model-text variants, even when their ID is known.
                        try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = wire, .rejection = .type_mismatch });
                        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, try codec.constructBound(a, wire, packet.integerChoices()), bound));
                    }
                    const export_value = .{ .input = std.json.Value{ .object = body }, .prior_assignment = (try std.json.parseFromSlice(std.json.Value, a, before, .{})).value, .schema = selected.selected().modelBytes() };
                    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, ".zig-cache/authoring-comparison/{s}.json", .{example.name}), .data = try std.json.Stringify.valueAlloc(a, export_value, .{}) });
                },
                .primary_user_story => |story| {
                    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .primary_user_story }), story.purpose.?);
                },
                .entities => |entities| {
                    try std.testing.expect(std.mem.indexOf(u8, entities.purpose.?, try @import("domain/required_authority_description.zig").task(a, .{ .kind = .entity_applicability, .unit = .{ .feature = .singleton }, .slot = .entities })) != null);
                    try std.testing.expect(std.mem.indexOf(u8, entities.purpose.?, try @import("domain/required_authority_description.zig").record(a, .entity)) != null);
                },
                .records => |records| {
                    try expectAssignedRequirements(bound.records.selection.claim_ids, records.requirements);
                    try std.testing.expectEqualDeep(bound.records.signal, records.signal);
                    const descriptions = @import("domain/required_authority_description.zig");
                    inline for (comptime std.meta.tags(spec.Kind)) |kind| try std.testing.expectEqual(kind != .entity, std.mem.indexOf(u8, records.purpose.?, descriptions.recordFamily(kind)) != null);
                },
            }
        }
    }
}

test "dependent authoring context resolves exact and passive values and follows selected family restrictions" {
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    const schema = @import("domain/model_result_schema.zig");
    const descriptions = @import("domain/required_authority_description.zig");
    for ([_][]const u8{ "MOCK Display `Ready!` with the current UTC time and export stories.md.", "MOCK Display `Renewed!` with the new loan deadline and export stories.md." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const token = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token) break entry.claim;
        } else return error.MissingExactToken;
        const filename = fixture.context.registry.records[0];
        var proposed = try fixture.proposal("MOCK dependent context");
        proposed.value = .{ .segments = &.{
            .{ .literal = .{ .value = "MOCK Display " } },
            .{ .exact_copy = .{ .claim_id = token.id } },
            .{ .literal = .{ .value = " from " } },
            .{ .passive = .{ .passive_literal_id = filename.id } },
        } };
        const accepted = try provenance.checkAttributed(.model, a, text.validator, fixture.context, proposed, .spec_story);
        const expected = try std.mem.concat(a, u8, &.{ "MOCK Display ", token.content.preserved_token.value.raw_value.bytes, " from ", filename.value });
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        current.units[0].?.response.content.brief = .{ .title = accepted, .description = accepted, .primary_goal = accepted };
        var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const canonical = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
        for (std.meta.tags(spec.Applicability)) |disposition| {
            current.units[2].?.response.content.entities = .{ .disposition = disposition, .basis = accepted };
            const before = try json.encode(@TypeOf(current.units), a, current.units);
            for ([_]?[]const u8{ null, try descriptions.recordTask(a, .functional_requirement, .text) }) |task| {
                const packet = try sessions.packetForOptions(std.testing.allocator, current, fixture.context, sessions.records_index, .{ .task = task });
                defer packets.release(packet);
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                const brief = body.get("brief").?.object;
                try std.testing.expectEqual(@as(usize, 3), brief.count());
                for ([_][]const u8{ "title", "description", "primary_goal" }) |field| try std.testing.expectEqualStrings(expected, brief.get(field).?.string);
                const entities = body.get("entities").?.object;
                try std.testing.expectEqual(@as(usize, 2), entities.count());
                try std.testing.expectEqualStrings(expected, entities.get("basis").?.string);
                try std.testing.expectEqualStrings(@tagName(disposition), entities.get("disposition").?.string);
                try std.testing.expectEqualStrings(source, body.get("sources").?.array.items[0].object.get("text").?.string);
                try std.testing.expectEqualStrings(token.content.preserved_token.value.raw_value.bytes, body.get("preserved_tokens").?.array.items[0].object.get("value").?.string);
                const selected = try schema.restrict(a, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
                defer selected.release();
                const selected_bytes = selected.selected().modelBytes();
                inline for (comptime std.meta.tags(spec.Kind)) |kind| {
                    const permitted = kind != .entity;
                    try std.testing.expectEqual(permitted, std.mem.indexOf(u8, selected_bytes, "\"const\":\"" ++ @tagName(kind) ++ "\"") != null);
                    if (task == null) try std.testing.expectEqual(permitted, std.mem.indexOf(u8, body.get("source_assignment").?.object.get("purpose").?.string, descriptions.recordFamily(kind)) != null);
                }
                if (task != null) try std.testing.expect(!body.get("source_assignment").?.object.contains("purpose"));
            }
            try std.testing.expectEqualStrings(before, try json.encode(@TypeOf(current.units), a, current.units));
        }
    }
}

fn expectAssignedRequirements(expected: []const references.r.ClaimId, actual: []const @import("domain/model_evidence.zig").Requirement) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |id, requirement| {
        try std.testing.expectEqualDeep(id, requirement.claim_id);
        try std.testing.expect(requirement.meaning.len != 0);
        try std.testing.expect(requirement.kind.len != 0);
        try std.testing.expect(requirement.source_id.ordinal != 0);
    }
}

fn checkAuthoringPacket(a: std.mem.Allocator, bytes: []const u8) !void {
    const parsed = (try std.json.parseFromSlice(std.json.Value, a, bytes, .{})).value.object;
    const body = if (parsed.get("input")) |input| input.object else parsed;
    try std.testing.expect(!body.contains("claims"));
    try std.testing.expect(!body.contains("citations"));
    for (body.get("preserved_tokens").?.array.items) |token| {
        try std.testing.expectEqual(@as(usize, 3), token.object.count());
        try std.testing.expect(token.object.get("claim_id").?.integer > 0);
        try std.testing.expect(token.object.get("value").?.string.len != 0);
        try std.testing.expect(token.object.get("source_id").?.integer > 0);
    }
    if (body.get("source_assignment").? == .object) {
        const assigned = try @import("domain/model_candidate_json.zig").decode(@import("domain/specification_source_binding.zig").Guidance, a, try std.json.Stringify.valueAlloc(a, body.get("source_assignment").?, .{}));
        for (body.get("context_requirements").?.array.items) |requirement| try std.testing.expect(!@import("domain/specification_source_binding.zig").assigns(assigned, .{ .ordinal = @intCast(requirement.object.get("claim_id").?.integer) }));
    }
}

fn generationPacketAllocationCase(allocator: std.mem.Allocator, current: @import("domain/specification_session.zig").Session, context: provenance.Context) !void {
    const packet = try @import("domain/specification_session.zig").packet(allocator, current, context);
    defer @import("domain/model_input_packet.zig").release(packet);
}

test "story generation and repair omit sibling drafts while retaining source evidence and native dependencies" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{
        "The application starts successfully and displays the date and time in UTC.",
        "A borrower renews an eligible loan and sees the new deadline; refused renewals retain the old deadline.",
    }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const good = try fixture.proposal(source);
        const short = try fixture.proposal("Short display name");
        const brief = (try g.validate(a, text.validator, fixture.context, .brief, .{ .content = .{ .brief = .{ .title = short, .description = short, .primary_goal = short } } })).valid;
        const current = try sessions.append((try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready, brief);
        const initial = try sessions.packet(std.testing.allocator, current, fixture.context);
        defer packets.release(initial);
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .primary_user_story = bad } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
        const correction = try repair.packet(std.testing.allocator, current, fixture.context, auth);
        defer packets.release(correction);
        const original = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
        const corrected = (try std.json.parseFromSlice(std.json.Value, a, correction.body(), .{})).value.object.get("input").?.object;
        for ([_]std.json.ObjectMap{ original, corrected }) |body| {
            try std.testing.expect(!body.contains("brief"));
            try std.testing.expect(!body.contains("entities"));
            try std.testing.expectEqualStrings(source, body.get("sources").?.array.items[0].object.get("text").?.string);
            for ([_][]const u8{ "context_requirements", "preserved_tokens", "sources" }) |field|
                try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, original.get(field).?, .{}), try std.json.Stringify.valueAlloc(a, body.get(field).?, .{}));
        }
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, original.get("source_groups").?, .{}), try std.json.Stringify.valueAlloc(a, corrected.get("source_groups").?, .{}));
        try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .primary_user_story }), try selectedNativeRepairTask(.{ .object = corrected }));
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, auth, .{ .value = good.value }, null);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, merged)) == .valid);
        try std.testing.expectEqualDeep(brief, current.units[0].?);
        var stale = current;
        stale.units[0].?.response.content.brief.title = try fixture.value(source);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(std.testing.allocator, stale, fixture.context, auth));
    }
}

test "specification choices acceptance and coverage share retained claim eligibility" {
    const r = references.r;
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    const coverage = @import("domain/specification_coverage.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A visitor sees a greeting.", "A librarian renews a loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const value = try fixture.value(source);
        const proposal = try fixture.proposal(source);
        const id = value.provenance.claim_ids[0];
        const original = fixture.context.references.records.assignments.checked.prior.prior.dispositions;
        const content = (try identifiers.assign(a, .{ .display_name = value, .primary_user_story = value, .records = &.{}, .entities = .{ .disposition = .not_applicable, .basis = value } }, .{})).content;
        const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        const variants = std.meta.tags(r.Disposition);
        // The final case removes the selected claim's disposition account.
        for (0..variants.len + 1) |index| {
            var dispositions: std.ArrayList(r.ClaimDisposition) = .empty;
            for (original) |account| {
                var changed = account;
                if (account.claim_id.ordinal == id.ordinal) {
                    if (index == variants.len) continue;
                    changed.disposition = variants[index];
                }
                try dispositions.append(a, changed);
            }
            var context = fixture.context;
            context.references.records.assignments.checked.prior.prior.dispositions = dispositions.items;
            const eligible = index < variants.len and variants[index] == .retained;
            if (eligible) {
                const packet = try sessions.packet(std.testing.allocator, current, context);
                defer packets.release(packet);
                const repair = @import("domain/specification_repair.zig");
                var bad = proposal;
                bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
                const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = bad, .description = proposal, .primary_goal = proposal } } } };
                const rejection = (try validate_unit.execute(a, current, context, candidate)).invalid;
                const authorization = try repair.authorize(a, current, context, candidate, rejection);
                const repair_packet = try repair.packet(std.testing.allocator, current, context, authorization);
                defer packets.release(repair_packet);
                for ([_]*const packets.Packet{ packet, repair_packet }) |request| {
                    const body = try std.json.parseFromSlice(std.json.Value, a, request.body(), .{});
                    const input = if (request.purpose() == .atomic_repair) body.value.object.get("input").? else body.value;
                    const assigned = try @import("domain/model_candidate_json.zig").decode(@import("domain/specification_source_binding.zig").Guidance, a, try std.json.Stringify.valueAlloc(a, input.object.get("source_assignment").?, .{}));
                    const groups = try @import("domain/specification_source_binding.zig").catalogue(a, @import("domain/reference_support.zig").records(context.references), .content);
                    try std.testing.expect(@import("domain/reference_reconciliation.zig").contains(@import("domain/reference_reconciliation.zig").ClaimId, groups[0].claim_ids, id));
                    try std.testing.expect(!@import("domain/specification_source_binding.zig").assigns(assigned, .{ .ordinal = 999 }));
                    for (input.object.get("context_requirements").?.array.items) |claim| try std.testing.expect(claim.object.get("claim_id").?.integer != 999);
                }
            } else if (index == variants.len) {
                try std.testing.expectError(error.InvalidSpecificationBinding, sessions.packet(std.testing.allocator, current, context));
            } else {
                // A question can still select retained source groups when no
                // group is eligible to establish business content.
                const packet = try sessions.packet(std.testing.allocator, current, context);
                defer packets.release(packet);
                try std.testing.expect(packet.excludedVariants().len != 0);
                try std.testing.expectError(error.InvalidSpecificationBinding, @import("domain/specification_source_binding.zig").resolveGroups(a, @import("domain/reference_support.zig").records(context.references), context.inputs, proposal.source_group_ids, .content));
            }
            if (eligible) {
                try std.testing.expectEqualDeep(value.provenance, try provenance.select(a, context, proposal.provenance));
                _ = try provenance.scopes(a, context, value.provenance);
            } else {
                try std.testing.expectError(error.InvalidSpecification, provenance.select(a, context, proposal.provenance));
                try std.testing.expectError(error.InvalidSpecification, provenance.scopes(a, context, value.provenance));
            }
            const accounted = try coverage.validate(a, context.references, .{ .title = value, .description = value, .primary_goal = value }, content);
            var covered = false;
            for (accounted.accounts) |account| if (account.claim_id.ordinal == id.ordinal) {
                covered = true;
            };
            try std.testing.expectEqual(eligible, covered);
            const missing: r.ClaimId = .{ .ordinal = 999 };
            try std.testing.expect(!@import("domain/reference_support.zig").eligibleClaim(null));
            try std.testing.expectError(error.InvalidReferenceReconciliation, provenance.select(a, context, .{ .claim_ids = &.{missing}, .clarification_response_ids = &.{} }));
        }
    }
}

test "authoring group catalogue rejects empty stale foreign and unauthorized selections" {
    const binding = @import("domain/specification_source_binding.zig");
    const sessions = @import("domain/specification_session.zig");
    const refs = @import("domain/reference_support.zig");
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "MOCK Startup behavior.", "MOCK Renew a loan." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        const records = refs.records(fixture.context.references);
        const groups = try binding.catalogue(a, records, .content);
        try std.testing.expectEqual(@as(usize, 2), groups.len);
        const selected = try binding.resolveGroups(a, records, fixture.context.inputs, &.{ groups[1].signal_id, groups[0].signal_id }, .content);
        try std.testing.expectEqualDeep(&[_]r.SignalId{ groups[0].signal_id, groups[1].signal_id }, selected.source_group_ids);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{ .{ .ordinal = 1 }, .{ .ordinal = 2 } }, selected.selection.claim_ids);
        for ([_][]const r.SignalId{ &.{}, &.{ groups[0].signal_id, groups[0].signal_id }, &.{.{ .ordinal = 9999 }} }) |ids| {
            if (binding.resolveGroups(a, records, fixture.context.inputs, ids, .content)) |_| return error.ExpectedRejection else |err| try std.testing.expect(err == error.InvalidSpecificationBinding or err == error.InvalidReferenceReconciliation);
        }
        var duplicated_catalogue = records;
        duplicated_catalogue.signals = &.{ records.signals[0], records.signals[0] };
        // Duplicate occurrences cannot make a foreign requested ID look covered
        // merely because selected and requested cardinalities happen to match.
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.resolveGroups(a, duplicated_catalogue, fixture.context.inputs, &.{ groups[0].signal_id, .{ .ordinal = 9999 } }, .content));
        var stale = fixture.context.inputs;
        stale.corpus.state_id.bytes = "MOCK foreign state";
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.resolveGroups(a, records, stale, &.{groups[0].signal_id}, .content));
        var empty = fixture.context;
        empty.references.records.signals = &.{};
        const gap = (try sessions.initialize(a, empty.inputs.corpus.feature_id, empty)).blocked;
        try std.testing.expectEqual(.empty_catalogue, gap.reason);
        try std.testing.expectEqual(@as(usize, 0), gap.eligible_signals.len);
        const dispositions = try a.dupe(r.ClaimDisposition, records.dispositions);
        for (dispositions) |*entry| if (entry.claim_id.ordinal == 1) {
            entry.disposition = .superseded;
            entry.related_claim_ids = &.{.{ .ordinal = 2 }};
        };
        var altered = records;
        altered.dispositions = dispositions;
        try std.testing.expectEqual(@as(usize, 1), try binding.recordCount(altered));
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.resolveGroups(a, altered, fixture.context.inputs, &.{groups[0].signal_id}, .content));
        // The superseded group leaves one record batch, bound to the surviving group.
        try std.testing.expectEqualDeep(groups[1].signal_id, (try binding.record(a, altered, fixture.context.inputs, 0)).records.signal);
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.record(a, altered, fixture.context.inputs, 1));
        dispositions[0].claim_id.ordinal = 9999;
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.recordCount(altered));
    }
}

test "authoring schema reuse keeps positive support separate from open question evidence" {
    const sessions = @import("domain/specification_session.zig");
    const schema = @import("domain/model_result_schema.zig");
    const json = @import("domain/model_candidate_json.zig");
    const extraction_contract = @import("domain/reference_extraction.zig");
    const checkDocument = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
    const Case = struct { behavior: []const u8, question: []const u8 };
    for ([_]Case{
        .{ .behavior = "MOCK Show the startup time.", .question = "MOCK Which timezone applies?" },
        .{ .behavior = "MOCK Renew an eligible loan.", .question = "MOCK Which renewal period applies?" },
    }) |case| {
        const claims = [_]extraction_contract.Proposal{
            .{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = case.behavior } }} } }, .citations = &.{.{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } }} },
            .{ .content = .{ .open_question = .{ .nodes = &.{.{ .literal = .{ .value = case.question } }} } }, .citations = &.{.{ .first = .{ .ordinal = 2 }, .last = .{ .ordinal = 2 } }} },
        };
        var fixture = try Fixture.initClaims(a, try std.fmt.allocPrint(a, "{s}\n{s}\n", .{ case.behavior, case.question }), null, .{ .selected = &claims });
        defer fixture.deinit();
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const packet = try sessions.packet(a, current, fixture.context);
        defer @import("domain/model_input_packet.zig").release(packet);
        const selected = try schema.restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer selected.release();
        const good = try fixture.proposal(case.behavior);
        const response: g.Response = .{ .content = .{ .brief = .{ .title = good, .description = good, .primary_goal = good } } };
        try checkDocument(selected.selected().modelBytes(), .{ .bytes = try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)) });
        var wrong = response;
        wrong.content.brief.title.source_group_ids = &.{fixture.context.references.records.signals[1].id};
        wrong.content.brief.title.provenance.claim_ids = &.{.{ .ordinal = 2 }};
        const wrong_wire = try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, wrong));
        try checkDocument(selected.selected().modelBytes(), .{ .bytes = wrong_wire, .rejection = .enum_mismatch, .path = "/title/signal_ids/0" });
        const bound = try sessions.currentBinding(a, current, fixture.context);
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, wrong_wire, bound));
        try std.testing.expectEqual(.provenance, (try g.validate(a, text.validator, fixture.context, .brief, wrong)).invalid.rule);
        var question = good;
        question.value = .{ .segments = &.{.{ .literal = .{ .value = case.question } }} };
        question.source_group_ids = wrong.content.brief.title.source_group_ids;
        question.provenance.claim_ids = wrong.content.brief.title.provenance.claim_ids;
        const need: g.Response = .{ .clarification = .{ .reason = .missing, .question = question } };
        const wire = try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, need));
        try checkDocument(selected.selected().modelBytes(), .{ .bytes = wire });
        const admitted = (try g.validate(a, text.validator, fixture.context, .brief, try g.parse(a, wire, bound))).valid;
        try std.testing.expectEqualDeep(question.source_group_ids, admitted.response.clarification.question.source_group_ids);
        try std.testing.expectEqualDeep(question.provenance, selection(admitted.response.clarification.question.provenance));
    }
}

test "record authoring excludes only complete preserved-token groups and keeps sparse native assignments" {
    const binding = @import("domain/specification_source_binding.zig");
    const sessions = @import("domain/specification_session.zig");
    const refs = @import("domain/reference_support.zig");
    const r = references.r;
    for ([_]struct { source: []const u8, prose: []const u8 }{
        .{ .source = "Display `Hello, World!` and `UTC` on startup.", .prose = "The visitor sees Hello, World! beside UTC." },
        .{ .source = "Export `report.csv` with status `READY`.", .prose = "The operator exports report.csv with status READY." },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, case.source, .business_exact_string, true, "The user receives the requested result.", 3);
        defer fixture.deinit();
        const original = fixture.context.references.records.assignments.checked.prior.prior;
        const items = original.input.items;
        try std.testing.expectEqual(@as(usize, 5), items.len);
        var proposed = original.proposal;
        proposed.signals = &.{
            original.proposal.signals[0], original.proposal.signals[3], original.proposal.signals[1],
            original.proposal.signals[4], original.proposal.signals[2],
        };
        fixture.context.references = (try references.finish(a, original.input, proposed, .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current })).valid;
        const records = refs.records(fixture.context.references);
        const catalogue = try binding.catalogue(a, records, .question);
        try std.testing.expectEqual(@as(usize, 5), catalogue.len);
        try std.testing.expectEqual(@as(usize, 3), try binding.recordCount(records));
        for ([_]usize{ 0, 2, 4 }, 0..) |signal_index, index| {
            const bound = (try binding.record(a, records, fixture.context.inputs, index)).records;
            try std.testing.expectEqualDeep(records.signals[signal_index].id, bound.signal);
            try std.testing.expectEqualDeep(records.signals[signal_index].value.claim_ids, bound.selection.claim_ids);
        }
        for ([_]usize{ 1, 3 }) |index| {
            try std.testing.expect(try binding.tokenOnly(records, records.signals[index].id));
            // The scheduling decision does not remove selectable native evidence.
            _ = try binding.resolveGroups(a, records, fixture.context.inputs, &.{records.signals[index].id}, .content);
        }
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.record(a, records, fixture.context.inputs, 3));
        const initialized = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        try std.testing.expectEqual(@as(usize, 6), (try sessions.iterationProgress(initialized)).limit);
        const completed = try completedFixture(&fixture, false);
        try sessions.validateRecordAssignments(a, completed, fixture.context);
        try std.testing.expectEqual(@as(usize, 3), completed.record_batches.len);
        for (completed.record_batches, [_]usize{ 0, 2, 4 }, 0..) |batch, signal_index, index| {
            try std.testing.expectEqual(index, batch.record_assignment.?.group_index);
            try std.testing.expectEqualDeep(records.signals[signal_index].id, batch.record_assignment.?.source_group_id);
        }
        // E remains eligible beyond the remaining assignment's explicit S.
        const raw = try fixture.proposal(case.prose);
        const recognized = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{ .content = .{ .functional_requirement = .{ .text = raw.value } }, .source_group_ids = raw.source_group_ids, .provenance = raw.provenance });
        try std.testing.expectEqualDeep(raw.provenance.claim_ids, recognized.provenance.claim_ids);
        const effective = try provenance.effectiveClaims(a, recognized.provenance.claim_ids, &.{recognized.content.functional_requirement.text});
        try std.testing.expect(r.contains(r.ClaimId, effective, items[3].claim.id));
        try std.testing.expect(r.contains(r.ClaimId, effective, items[4].claim.id));
        // Synthetic membership tests exercise the binding predicate directly;
        // they are not canonically validated reconciliation signals or sessions.
        var mixed = records;
        const mixed_signals = try a.dupe(r.Signal, records.signals);
        mixed_signals[2].value.claim_ids = &.{ items[1].claim.id, items[4].claim.id };
        mixed_signals[1].value.claim_ids = &.{ items[3].claim.id, items[4].claim.id };
        mixed.signals = mixed_signals;
        try std.testing.expectEqual(@as(usize, 3), try binding.recordCount(mixed));
        try std.testing.expect(!try binding.tokenOnly(mixed, mixed.signals[2].id));
        const mixed_bound = (try binding.record(a, mixed, fixture.context.inputs, 1)).records;
        try std.testing.expectEqualDeep(mixed.signals[2].id, mixed_bound.signal);
        try std.testing.expectEqualDeep(mixed.signals[2].value.claim_ids, mixed_bound.selection.claim_ids);
        try std.testing.expect(try binding.tokenOnly(mixed, mixed.signals[1].id));
        var stale = fixture.context.inputs;
        stale.corpus.state_id.bytes = "foreign-reference-state";
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.record(a, records, stale, 0));
        for (0..2) |mode| {
            var malformed = records;
            const signals = try a.dupe(r.Signal, records.signals);
            if (mode == 0) signals[1].id = signals[0].id else signals[1].value.claim_ids = &.{};
            malformed.signals = signals;
            try std.testing.expectError(error.InvalidSpecificationBinding, binding.recordCount(malformed));
            try std.testing.expectError(error.InvalidSpecificationBinding, binding.record(a, malformed, fixture.context.inputs, 0));
        }
    }
}

test "record authoring retains every non-token claim class and rejects a token-only population explicitly" {
    const binding = @import("domain/specification_source_binding.zig");
    const sessions = @import("domain/specification_session.zig");
    const refs = @import("domain/reference_support.zig");
    const contract = @import("domain/reference_extraction.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (comptime std.meta.tags(contract.Kind)) |kind| {
        const prose = "The source describes the requested behavior.";
        const content: contract.ProposalContent = @unionInit(contract.ProposalContent, @tagName(kind), if (kind == .business or kind == .scope_guard) .{ .segments = &.{.{ .literal = .{ .value = prose } }} } else .{ .nodes = &.{.{ .literal = .{ .value = prose } }} });
        var fixture = try Fixture.initClaims(a, prose, null, .{ .selected = &.{.{ .content = content, .citations = &.{.{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } }} }} });
        defer fixture.deinit();
        const records = refs.records(fixture.context.references);
        try std.testing.expectEqual(@as(usize, 1), try binding.recordCount(records));
        try std.testing.expect(!try binding.tokenOnly(records, records.signals[0].id));
        try std.testing.expectEqual(@as(usize, 1), (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready.record_group_count);
    }
    for ([_][]const u8{ "Display `Hello, World!`.", "Export `report.csv` and display `READY`." }) |source| {
        var fixture = try Fixture.initClaims(a, source, .business_exact_string, .{ .selected = &.{} });
        defer fixture.deinit();
        // A positive claims result can contain native tokens without semantic
        // claims. It is fully accounted and distinct from no_feature_claim.
        const token_only = fixture.context.references;
        const records = refs.records(token_only);
        try std.testing.expectEqual(@as(usize, 0), try binding.recordCount(records));
        const rejected = try binding.rejection(a, token_only);
        try std.testing.expectEqual(.no_record_authoring_groups, rejected.reason);
        try std.testing.expect(rejected.eligible_signals.len > 0);
        try std.testing.expectEqualDeep(try binding.catalogue(a, records, .question), rejected.eligible_signals);
        try std.testing.expectEqualDeep(records.items.state_id, rejected.state_id);
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.record(a, records, fixture.context.inputs, 0));
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.validate(records, fixture.context.inputs));
        try std.testing.expectEqual(.no_record_authoring_groups, (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).blocked.reason);
    }
}

test "registered authoring iteration covers narratives and every group through one current finite population" {
    const sessions = @import("domain/specification_session.zig");
    const native = @import("application/specification_workflow.zig");
    const iteration = @import("domain/workflow_iteration.zig");
    const advance_action = @import("actions/specification/advance_specification_generation.zig").Action{};
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var begin: native.Initialize = .{ .allocator = a };
    var advance: native.Advance = .{ .allocator = a };
    const begin_entry = @import("composition/native_workflow_operations.zig").entry(native.Initialize, &begin);
    const advance_entry = @import("composition/native_workflow_operations.zig").entry(native.Advance, &advance);
    try std.testing.expect(iteration.validContract(begin_entry.contract, begin_entry.binding.capabilities()));
    try std.testing.expect(iteration.validContract(advance_entry.contract, advance_entry.binding.capabilities()));
    try std.testing.expectEqualDeep(native.Initialize.iteration, begin_entry.contract.iteration.?);
    try std.testing.expectEqualDeep(native.Advance.iteration, advance_entry.contract.iteration.?);
    for ([_]usize{ 1, 37 }) |groups| {
        var fixture = try Fixture.initContent(a, "MOCK Display the current status.", null, true, "MOCK The current status is visible.", groups);
        defer fixture.deinit();
        var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        var state: iteration.State = .{};
        const initial = try sessions.iterationProgress(current);
        try std.testing.expectEqual(sessions.records_index + groups, initial.limit);
        try state.commit(try state.prepare(native.Initialize.iteration, .{ .limit = initial.limit, .before = 0, .after = initial.position }, 1, null), 1);
        const good = try fixture.proposal("MOCK The user sees the current status.");
        const unchanged = state;
        const question = (try g.validate(a, text.validator, fixture.context, .brief, .{ .clarification = .{ .reason = .missing, .question = good } })).valid;
        try std.testing.expectError(error.InvalidSpecificationUnit, advance_action.execute(a, current, question));
        try std.testing.expectError(error.InvalidSpecificationUnit, advance_action.execute(a, current, .{ .unit = .brief, .response = .{ .inconclusive = .{ .detail = "MOCK Uncertain interpretation." } } }));
        try std.testing.expectEqualDeep(unchanged, state);
        var generation: u64 = 1;
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = good, .description = good, .primary_goal = good } },
                .primary_user_story => .{ .primary_user_story = good },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
                .records => .{ .records = &.{} },
            } };
            const checked = try sessions.admit(a, current, fixture.context, (try g.validate(a, text.validator, fixture.context, unit, response)).valid);
            const before = try sessions.iterationProgress(current);
            const next = try advance_action.execute(a, current, checked);
            const after = try sessions.iterationProgress(next);
            try std.testing.expectEqual(before.position + 1, after.position);
            const transition: iteration.Transition = .{ .limit = after.limit, .before = before.position, .after = after.position };
            const accepted = try state.prepare(native.Advance.iteration, transition, 1, generation);
            generation += 1;
            try state.commit(accepted, generation);
            try std.testing.expectError(error.InvalidNativeIteration, state.prepare(native.Advance.iteration, transition, 1, generation));
            current = next;
        }
        try std.testing.expectEqual(initial.limit, (try sessions.iterationProgress(current)).position);
        try std.testing.expectEqual(groups, current.record_batches.len);
        // Completed repairs do not call Advance. Upstream rebuilding retires
        // Session and supplies a newer accounted-reference scope before restart.
        try std.testing.expectError(error.InvalidNativeIteration, state.prepare(native.Initialize.iteration, .{ .limit = initial.limit, .before = 0, .after = 0 }, 1, null));
        const restarted = try state.prepare(native.Initialize.iteration, .{ .limit = initial.limit, .before = 0, .after = 0 }, 2, null);
        try state.commit(restarted, generation + 1);
    }
}

test "specification text repair uses shared localized guidance and preserves evidence" {
    const repair = @import("domain/specification_repair.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "The visitor sees a greeting.", "The borrower receives a renewal confirmation." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const current = (try @import("domain/specification_session.zig").initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        const good = try fixture.proposal(source);
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid\x01text" } }} };
        const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const issue = rejected.issue.text_issue.?;
        try std.testing.expectEqual(.invalid_scalar, issue.reason);
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const rule = body.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expectEqualStrings(issue.description(), rule.get("requirement").?.string);
        try std.testing.expectEqualDeep(issue, try json.decode(@import("domain/typed_text.zig").Issue, a, try std.json.Stringify.valueAlloc(a, rule.get("text_issue").?, .{})));
        const replacement: repair.Replacement = .{ .value = good.value };
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, try repair.parse(a, authorization, packet, try json.encodeSelected(repair.Replacement, a, replacement)), null);
        try std.testing.expectEqualDeep(bad.provenance, merged.response.content.brief.description.provenance);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.title);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.primary_goal);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, merged)) == .valid);
    }
}

test "reference-grounded projections round trip all record families and reject changed rendering" {
    const projection = @import("domain/specification_projection.zig");
    const codec = @import("domain/specification_markdown.zig");
    const validate = @import("actions/specification/validate_specification_rendering.zig").Action{};
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A visitor sees a greeting.", "A librarian renews a loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const value = try fixture.value(source);
        var records: std.ArrayList(spec.RecordProposal) = .empty;
        inline for (comptime std.meta.tags(spec.Kind)) |kind| try records.append(a, .{
            .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, value.value)),
            .provenance = value.provenance,
        });
        const content = (try identifiers.assign(a, .{ .display_name = value, .primary_user_story = value, .records = records.items, .entities = .{ .disposition = .required, .basis = value } }, .{})).content;
        const document = try projection.project(a, fixture.context, content);
        const bytes = try codec.render(a, document);
        try validate.execute(a, document, bytes);
        try std.testing.expectEqualDeep(document, try codec.parse(a, bytes));
        try std.testing.expectError(error.InvalidSpecification, validate.execute(a, document, try std.mem.concat(a, u8, &.{ bytes, "\n" })));
        var stale = fixture.context;
        stale.inputs.corpus.state_id.bytes = "foreign";
        try std.testing.expectError(error.InvalidSpecification, projection.project(a, stale, content));
    }
}

test "specification display resolves exact values without normalization and passive values as code" {
    const projection = @import("domain/specification_projection.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Show `Cafe\u{301}` and consult stories.md.");
    defer fixture.deinit();
    const packet = try @import("domain/specification_session.zig").packet(std.testing.allocator, (try @import("domain/specification_session.zig").initialize(a, .{ .bytes = "selected" }, fixture.context)).ready, fixture.context);
    defer @import("domain/model_input_packet.zig").release(packet);
    try std.testing.expectEqual(@as(usize, 0), packet.excludedVariants().len);
    const items = try provenance.items(fixture.context);
    var exact_count: usize = 0;
    for (items.entries) |item| {
        if (item.claim.content != .preserved_token) continue;
        exact_count += 1;
        const value: spec.AttributedValue = .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = item.claim.id } }} }, .provenance = .{ .claim_ids = &.{item.claim.id}, .citation_ids = item.claim.citation_ids, .clarification_response_ids = &.{} } };
        try std.testing.expectEqualStrings("Cafe\u{301}", (try projection.scalar(a, fixture.context, value)).bytes);
        var invalid = value;
        var invalid_copy = invalid.value.segments[0].exact_copy;
        invalid_copy.claim_id.ordinal = 999;
        invalid.value.segments = &.{.{ .exact_copy = invalid_copy }};
        try std.testing.expectError(error.InvalidSpecification, projection.scalar(a, fixture.context, invalid));
    }
    try std.testing.expectEqual(@as(usize, 1), exact_count);
    var passive_count: usize = 0;
    for (fixture.context.registry.records) |record| {
        if (!std.mem.eql(u8, record.value, "stories.md")) continue;
        passive_count += 1;
        var value = try fixture.value("unused");
        value.value = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = record.id } }} };
        const scalar = try projection.scalar(a, fixture.context, value);
        try std.testing.expectEqualStrings("stories.md", scalar.bytes);
        try std.testing.expectEqual(@as(usize, 1), scalar.code_spans.len);
    }
    try std.testing.expectEqual(@as(usize, 1), passive_count);
}

test "complete specification sessions preserve unit order provenance and conditional entities" {
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A customer views a greeting.", "A librarian renews a loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        var current = (try sessions.initialize(a, .{ .bytes = "requested-feature" }, fixture.context)).ready;
        const first = current;
        const value = try fixture.proposal(source);
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, current));
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const packet = try sessions.packet(std.testing.allocator, current, fixture.context);
            defer @import("domain/model_input_packet.zig").release(packet);
            try checkAuthoringPacket(a, packet.body());
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "principles") == null);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
                .primary_user_story => .{ .primary_user_story = value },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
                .records => result: {
                    const records = try a.dupe(spec.Model.RecordProposal, &.{.{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance }});
                    break :result .{ .records = records };
                },
            } };
            current = try appendMockResponse(a, current, fixture.context, response);
        }
        const identified = try sessions.assemble(a, text.validator, fixture.context, current);
        try std.testing.expectEqual(@as(usize, 1), identified.content.records.len);
        try std.testing.expectEqual(spec.Id{ .kind = .functional_requirement, .ordinal = 1 }, identified.content.records[0].id);
        try std.testing.expectEqual(@as(usize, 0), first.completed);
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.append(current, current.units[0].?));
        var stale = fixture.context;
        stale.inputs.corpus.state_id.bytes = "changed";
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, stale, current));
    }
}

test "specification semantic review retains scoped advice at the shared gate" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A visitor sees a greeting.");
    defer fixture.deinit();
    const initial = try completedSupportInputs(&fixture);
    const findings = try a.dupe(support.Finding, (try reviewFor(a, initial, fixture.context.inputs)).entries);
    const value = try fixture.value("A greeting is visible.");
    const bytes = try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings });
    const reviewed = try collectSupport(a, initial, fixture.context, bytes);
    for (reviewed.evidence) |proof| try std.testing.expectEqual(.model_assisted, proof.method);
    const current = try authority.build(a, reviewed);
    const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, current);
    const result = try authority.reconcile(a, current, observations);
    try std.testing.expect(try authority.validate(a, reviewed, observations, result));
    findings[0].value.kind = .ambiguous;
    findings[0].value.detail = "MOCK The source leaves this deadline decision unsettled.";
    findings[0].value.question = "Which deadline should apply? State the duration and starting event.";
    findings[0].value.provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} };
    findings[0].value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
    try bindReviewClaims(a, initial, fixture.context, findings);
    const gap = try collectSupport(a, initial, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings }));
    const gap_ledger = try authority.build(a, gap);
    const gap_observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, gap_ledger);
    try std.testing.expectEqual(.all_resolved, (try authority.reconcile(a, gap_ledger, gap_observations)).continuation);
    const absent = try collectSupport(a, initial, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings }));
    try std.testing.expectEqual(.ambiguous, absent.evidence[0].finding);
    findings[0].value.provenance.clarification_response_ids = &.{.{ .ordinal = 1 }};
    try std.testing.expectError(error.InvalidRequiredAuthority, collectSupport(a, initial, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings })));
    findings[0].value.provenance = selection(value.provenance);
    findings[0].requirement_ordinal = 999;
    try std.testing.expectError(error.InvalidRequiredAuthority, collectSupport(a, initial, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings })));
}

test "specification units validate every section family without creating IDs or filler" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A librarian renews a loan.");
    defer fixture.deinit();
    const value = try fixture.proposal("A librarian renews a loan.");
    inline for (comptime std.meta.tags(spec.Kind)) |kind| {
        const fields = Fields(kind, value.value);
        const record: spec.Model.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), fields), .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        const unit: g.Unit = if (kind == .entity) .entities else .records;
        const response: g.Response = .{ .content = if (kind == .entity) .{ .entities = .{ .disposition = .required, .basis = value, .records = &.{record} } } else .{ .records = &.{record} } };
        const result = (try g.validate(a, text.validator, fixture.context, unit, response)).valid;
        try std.testing.expectEqual(kind, std.meta.activeTag(g.recordCollection(.canonical, result.response.content).?[0].content));
        const wire = try @import("domain/model_candidate_json.zig").encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response));
        const bound = try @import("domain/specification_source_binding.zig").forUnit(a, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs, unit, 0);
        try std.testing.expectEqualDeep(result.response, (try g.validate(a, text.validator, fixture.context, unit, try g.parse(a, wire, bound))).valid.response);
        _ = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{} } })).valid;
        var duplicate = response;
        g.recordCollectionPtr(.model, &duplicate.content).?.* = &.{ record, record };
        try std.testing.expectEqual(.duplicate_record, (try g.validate(a, text.validator, fixture.context, unit, duplicate)).invalid.rule);
    }
    const brief: g.Response = .{ .content = .{ .brief = .{ .title = value, .description = value, .primary_goal = value } } };
    _ = (try g.validate(a, text.validator, fixture.context, .brief, brief)).valid;
    try std.testing.expectEqual(.unit_kind, (try g.validate(a, text.validator, fixture.context, .primary_user_story, brief)).invalid.rule);
    const question = (try g.validate(a, text.validator, fixture.context, .primary_user_story, .{ .clarification = .{ .reason = .ambiguous, .question = try fixture.proposal("Which renewal limit applies?") } })).valid;
    try std.testing.expectEqual(.clarification, std.meta.activeTag(question.response));
}

test "record generation and selected value repairs retain every family purpose without requiring optional records" {
    const sessions = @import("domain/specification_session.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const repair = @import("domain/specification_repair.zig");
    const descriptions = @import("domain/required_authority_description.zig");
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 41 }, .attempt = .{ .value = 1 } };
    for ([_][]const u8{ "MOCK A visitor sees the startup greeting.", "MOCK A borrower renews an eligible loan." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const value = try fixture.proposal(source);
        const records = try a.alloc(spec.Model.RecordProposal, std.meta.fields(spec.Kind).len);
        inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| records[index] = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, value.value)), .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        records[records.len - 1].content.entity.relationships = &.{ value.value, value.value };
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .required, .basis = value, .records = records[records.len - 1 ..] } } })).valid;
        const initial = try sessions.packet(std.testing.allocator, current, fixture.context);
        defer packets.release(initial);
        const initial_body = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
        const initial_purpose = initial_body.get("source_assignment").?.object.get("purpose").?.string;
        try std.testing.expectEqualStrings(try descriptions.recordsFor(a, std.meta.tags(spec.Kind)[0 .. std.meta.tags(spec.Kind).len - 1]), initial_purpose);
        inline for (comptime std.meta.tags(spec.Kind)) |kind| try std.testing.expectEqual(kind != .entity, std.mem.indexOf(u8, initial_purpose, descriptions.recordFamily(kind)) != null);
        const response: g.Response = .{ .content = .{ .records = records[0 .. records.len - 1] } };
        var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schema_owner = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
        try @import("test_fixtures/prepared_model_repair.zig").check(a, initial, schema_owner, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)), null);
        const valid = (try validate_unit.execute(a, current, fixture.context, .{ .response = response, .origins = .{ .initial = origin } })).valid;
        try std.testing.expectEqual(records.len - 1, valid.response.content.records.len);
        for (records[0 .. records.len - 1], valid.response.content.records) |proposed, accepted| try std.testing.expectEqualDeep(proposed.content, accepted.content);
        // Equal wording in distinct families, including FR and AC, remains
        // distinct candidate data. Purpose guidance creates no deduplication rule.
        const complete = try appendMockChecked(a, current, fixture.context, valid);
        const identified = (try sessions.assemble(a, text.validator, fixture.context, complete)).content;
        try std.testing.expectEqual(records.len, identified.records.len);
        inline for (comptime std.meta.tags(spec.Kind)) |kind| try std.testing.expectEqual(spec.Id{ .kind = kind, .ordinal = 1 }, for (identified.records) |record| {
            if (record.id.kind == kind) break record.id;
        } else return error.MissingRecordFamily);

        inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| {
            inline for (std.meta.fields(@FieldType(spec.Content(spec.BusinessValue), @tagName(kind)))) |field| {
                const slot: @import("domain/required_authority.zig").Slot = @field(@import("domain/required_authority.zig").Slot, if (std.mem.eql(u8, field.name, "relationships")) "relationship" else field.name);
                const count: usize = if (field.type == spec.BusinessValue) 1 else 2;
                for (0..count) |member| {
                    const selected: candidates.ValueField = if (comptime slot == .relationship) .{ .relationship = member } else @unionInit(candidates.ValueField, @tagName(slot), {});
                    var selected_current = current;
                    const owned_response: g.Response = if (kind == .entity) .{ .content = .{ .entities = .{ .disposition = .required, .basis = value, .records = records[records.len - 1 ..] } } } else response;
                    if (kind == .entity) {
                        selected_current.completed = sessions.entities_index;
                        selected_current.units[sessions.entities_index] = null;
                    }
                    const local_index = if (kind == .entity) 0 else index;
                    const target: candidates.Target = .{ .value = .{ .subject = .{ .record = local_index }, .field = selected } };
                    const candidate: repair.Candidate = .{
                        .response = try candidates.replace(a, owned_response, target, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} } }),
                        .origins = .{ .initial = origin },
                    };
                    const rejected = (try validate_unit.execute(a, selected_current, fixture.context, candidate)).invalid;
                    try std.testing.expectEqualDeep(target, rejected.issue.field.target);
                    const authorization = try repair.authorize(a, selected_current, fixture.context, candidate, rejected);
                    const packet = try repair.packet(std.testing.allocator, selected_current, fixture.context, authorization);
                    defer packets.release(packet);
                    const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                    const input = body.get("input").?.object;
                    try std.testing.expect(!input.contains("record_requirements"));
                    try std.testing.expectEqualStrings(try descriptions.recordTask(a, kind, slot), try selectedNativeRepairTask(body.get("input").?));
                    const selected_record = try json.decode(candidates.ReadContext, a, try std.json.Stringify.valueAlloc(a, input.get("candidate").?, .{}));
                    try std.testing.expectEqualDeep(g.recordCollection(.model, candidate.response.content).?[local_index], selected_record.record);
                    try std.testing.expectEqualDeep(origin, authorization.dependencies.candidate.origins.initial.?);
                    try @import("test_fixtures/prepared_model_repair.zig").check(a, packet, schema_owner, try json.encodeSelected(repair.Replacement, a, .{ .value = value.value }), null);
                    const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), selected_current, fixture.context, candidate, authorization, .{ .value = value.value }, null);
                    try std.testing.expectEqualDeep(owned_response, fixed.response);
                    _ = (try validate_unit.execute(a, selected_current, fixture.context, fixed)).valid;
                }
            }
        }
        // Missing optional families remain allowed under the existing native
        // applicability decision; guidance does not demand nine populated sections.
        current.units[2].?.response.content.entities.disposition = .not_applicable;
        current.units[2].?.response.content.entities.records = &.{};
        const minimum = [_]spec.Model.RecordProposal{ records[0], records[@intFromEnum(spec.Kind.functional_requirement)] };
        const sparse = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &minimum } } })).valid;
        const sparse_complete = try appendMockChecked(a, current, fixture.context, sparse);
        const sparse_content = (try sessions.assemble(a, text.validator, fixture.context, sparse_complete)).content;
        try std.testing.expectEqual(@as(usize, 2), sparse_content.records.len);
        try std.testing.expectEqual(.not_applicable, sparse_content.entities.disposition);
    }
}

test "record requirements apply across bound groups while native assembled family gaps remain enforced" {
    const sessions = @import("domain/specification_session.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    for ([_][]const u8{ "MOCK A visitor receives a startup greeting.", "MOCK A borrower receives a renewal receipt." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        const value = try fixture.proposal(source);
        const fr: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        const ac: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        for (0..3) |mode| {
            var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
            while (current.completed < sessions.records_index) {
                const unit = try sessions.unit(current.completed);
                const packet = try sessions.packet(a, current, fixture.context);
                defer packets.release(packet);
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                try std.testing.expect(!body.contains("record_requirements"));
                const response: g.Response = .{ .content = switch (unit) {
                    .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
                    .primary_user_story => .{ .primary_user_story = value },
                    .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
                    .records => unreachable,
                } };
                const parsed = try g.parse(a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)), try sessions.currentBinding(a, current, fixture.context));
                current = try sessions.append(current, (try validate_unit.execute(a, current, fixture.context, .{ .response = parsed })).valid);
            }
            try std.testing.expectEqual(@as(usize, 2), current.record_group_count);
            var previous_signal: ?i64 = null;
            for (0..2) |group| {
                const packet = try sessions.packet(a, current, fixture.context);
                defer packets.release(packet);
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                const requirements = body.get("record_requirements").?.object;
                try std.testing.expectEqualStrings("assembled_specification", requirements.get("scope").?.string);
                const required = requirements.get("required_families").?.array.items;
                try std.testing.expectEqual(@as(usize, 2), required.len);
                try std.testing.expectEqualStrings("acceptance_criterion", required[0].string);
                try std.testing.expectEqualStrings("functional_requirement", required[1].string);
                const assigned = body.get("source_assignment").?.object;
                const signal = assigned.get("signal").?.integer;
                if (previous_signal) |prior| try std.testing.expect(prior != signal);
                previous_signal = signal;
                // Each group emits only its selected family; no group receives
                // a per-group floor or optional filler requirement.
                const records: []const spec.Model.RecordProposal = if (group == 0) &.{if (mode == 2) ac else fr} else if (mode == 0) &.{ac} else &.{};
                const raw: g.Response = .{ .content = .{ .records = records } };
                const selected = try sessions.currentBinding(a, current, fixture.context);
                const response = try g.parse(a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, raw)), selected);
                const checked = (try validate_unit.execute(a, current, fixture.context, .{ .response = response })).valid;
                try std.testing.expectEqual(group, checked.record_assignment.?.group_index);
                try std.testing.expectEqualDeep(selected.records.signal, checked.record_assignment.?.source_group_id);
                try std.testing.expect(checked.record_assignment.?.reference_state.eql(current.reference_state));
                var no_assignment = checked;
                no_assignment.record_assignment = null;
                try std.testing.expectError(error.InvalidSpecificationUnit, sessions.appendBound(a, current, no_assignment));
                var stale_assignment = checked;
                stale_assignment.record_assignment.?.reference_state.bytes = "MOCK stale reference state";
                try std.testing.expectError(error.InvalidSpecificationUnit, sessions.appendBound(a, current, stale_assignment));
                var wrong_index = checked;
                wrong_index.record_assignment.?.group_index += 1;
                try std.testing.expectError(error.InvalidSpecificationUnit, sessions.appendBound(a, current, wrong_index));
                if (checked.response.content.records.len != 0) {
                    var wrong_group = checked;
                    const changed = try a.dupe(spec.RecordProposal, checked.response.content.records);
                    changed[0].source_group_ids = &.{fixture.context.references.records.signals[1 - group].id};
                    wrong_group.response.content.records = changed;
                    wrong_group.record_assignment = null;
                    try std.testing.expectError(error.InvalidSpecificationUnit, sessions.admit(a, current, fixture.context, wrong_group));
                }
                for (checked.response.content.records) |record| try std.testing.expectEqualDeep(selected.records.selection.claim_ids, record.provenance.claim_ids);
                try std.testing.expectEqualDeep(try binding.record(a, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs, group), selected);
                current = try sessions.appendBound(a, current, checked);
            }
            try sessions.validateRecordAssignments(a, current, fixture.context);
            var stale_history = current;
            const altered_batches = try a.dupe(g.Checked, current.record_batches);
            altered_batches[1].record_assignment.?.source_group_id = altered_batches[0].record_assignment.?.source_group_id;
            stale_history.record_batches = altered_batches;
            try std.testing.expectError(error.InvalidSpecificationUnit, sessions.validateRecordAssignments(a, stale_history, fixture.context));
            altered_batches[1].record_assignment = current.record_batches[1].record_assignment;
            altered_batches[1].record_assignment.?.references.bytes[0] ^= 1;
            try std.testing.expectError(error.InvalidSpecificationUnit, sessions.validateRecordAssignments(a, stale_history, fixture.context));
            var changed_context = fixture.context;
            const changed_signals = try a.dupe(references.r.Signal, fixture.context.references.records.signals);
            changed_signals[1].value.content.model.business.value.segments = &.{.{ .literal = .{ .value = "MOCK A different requirement under the same occurrence ID." } }};
            changed_context.references.records.signals = changed_signals;
            // The empty second batch in modes 1/2 still carries dependencies.
            try std.testing.expectError(error.InvalidSpecificationUnit, sessions.validateRecordAssignments(a, current, changed_context));
            const content = (try sessions.assemble(a, text.validator, fixture.context, current)).content;
            try std.testing.expectEqual(@as(usize, if (mode == 0) 2 else 1), content.records.len);
            for (content.records) |record| try std.testing.expect(record.id.kind == .acceptance_criterion or record.id.kind == .functional_requirement);
            const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, content, current.units[0].?.response.content.brief);
            try std.testing.expectEqual(@as(usize, if (mode == 0) 0 else 1), inputs.forced_gaps.len);
            if (mode != 0) try std.testing.expectEqual(@as(authority.Slot, if (mode == 1) .acceptance_criteria else .functional_requirements), inputs.forced_gaps[0].requirement.slot);
            const good = try reviewFor(a, inputs, fixture.context.inputs);
            const reviewed = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, good), null)).accepted;
            const decision = try supportDecision(a, reviewed.inputs);
            try std.testing.expectEqual(@as(@TypeOf(decision.result.continuation), if (mode == 0) .all_resolved else .invalid), decision.result.continuation);
            try std.testing.expectEqual(mode == 0, try authority.validate(a, reviewed.inputs, decision.observations, decision.result));
        }
    }
}

test "feature entity membership repair preserves fixed support origins and retry identity" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const candidate_type = @import("domain/specification_candidate.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const first: Origin = .{ .request = .{ .value = 11 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 12 }, .attempt = .{ .value = 1 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "MOCK Track equipment and annual inspections.", "MOCK Track borrowers and loan renewals." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.entities_index;
        current.units[sessions.entities_index] = null;
        current.units[sessions.records_index] = null;
        current.record_cursor = 0;
        current.record_batches = &.{};
        const groups = fixture.context.references.records.signals;
        const association = try binding.resolveGroups(a, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs, &.{ groups[0].id, groups[1].id }, .content);
        var basis = try fixture.proposal("MOCK This feature manages the source-required business data.");
        basis.source_group_ids = association.source_group_ids;
        basis.provenance = association.selection;
        const proposed: repair.Candidate = .{ .response = .{ .content = .{ .entities = .{ .disposition = .required, .basis = basis } } }, .origins = .{ .initial = first } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        try std.testing.expectEqual(.entities, rejection.issue.unit);
        try std.testing.expectEqual(.entity_membership, rejection.issue.rule);
        try std.testing.expect(rejection.issue.blocked == null);
        const auth = try repair.authorize(a, current, fixture.context, proposed, rejection);
        try std.testing.expect(auth.operation == .insert);
        try std.testing.expectEqualDeep(association.selection, auth.rule.group.?.membership.fixed_provenance);
        try std.testing.expectEqualDeep(association.source_group_ids, auth.rule.group.?.membership.fixed_source_group_ids);
        const packet = try repair.packet(a, current, fixture.context, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("repair_record_entity", packet.resultDefinition().?.bytes);
        const record: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = basis.value, .business_meaning = basis.value, .relationships = &.{basis.value} } }, .source_group_ids = association.source_group_ids, .provenance = association.selection };
        const canonical = try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs);
        const merged = try repair.merge(a, canonical, current, fixture.context, proposed, auth, .{ .record = record }, corrected);
        try std.testing.expectEqualDeep(first, merged.origins.at(.{ .target = .{ .attributed = .entity_basis } }).?);
        try std.testing.expectEqualDeep(corrected, merged.origins.at(.{ .target = .{ .record = 0 } }).?);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
        _ = (try validate_unit.execute(a, current, fixture.context, merged)).valid;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, canonical, current, fixture.context, merged, auth, .{ .record = record }, corrected));
        var foreign = record;
        foreign.source_group_ids = &.{groups[0].id};
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, canonical, current, fixture.context, proposed, auth, .{ .record = foreign }, corrected));
        var broken = record;
        broken.content.entity.business_meaning = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const invalid = try repair.merge(a, canonical, current, fixture.context, proposed, auth, .{ .record = broken }, corrected);
        const invalid_rejection = (try validate_unit.execute(a, current, fixture.context, invalid)).invalid;
        const next_auth = try repair.authorize(a, current, fixture.context, invalid, invalid_rejection);
        try std.testing.expectEqualDeep(auth.retry.?.key, next_auth.retry.?.key);
        try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, invalid)).?.validated.result);
        const recovered = try repair.merge(a, canonical, current, fixture.context, invalid, next_auth, .{ .record = record }, corrected);
        _ = (try validate_unit.execute(a, current, fixture.context, recovered)).valid;
        // A not-applicable feature removes only its contradictory entity. It
        // cannot move the record into another business-content family.
        var contradictory = proposed;
        contradictory.response.content.entities = .{ .disposition = .not_applicable, .basis = basis, .records = &.{record} };
        const contradiction = (try validate_unit.execute(a, current, fixture.context, contradictory)).invalid;
        const deletion = try repair.authorize(a, current, fixture.context, contradictory, contradiction);
        try std.testing.expect(deletion.operation == .delete);
        const removed = try repair.merge(a, canonical, current, fixture.context, contradictory, deletion, null, null);
        try std.testing.expectEqual(@as(usize, 0), removed.response.content.entities.records.len);
        try std.testing.expectEqualDeep(basis, removed.response.content.entities.basis);
        _ = (try validate_unit.execute(a, current, fixture.context, removed)).valid;
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, removed)).?.validated.result);
        const title_target: candidate_type.Target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .name } };
        const named = try candidate_type.replace(a, merged.response, title_target, .{ .value = (try fixture.proposal("MOCK A supported identity")).value });
        try std.testing.expectEqualDeep(record.provenance, named.content.entities.records[0].provenance);
        try std.testing.expectEqualDeep(record.content.entity.relationships, named.content.entities.records[0].content.entity.relationships);
    }
}

test "feature entities keep independent support and record batches reject every entity entry path" {
    const sessions = @import("domain/specification_session.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const schema = @import("domain/model_result_schema.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical_schema = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
    for ([_][]const u8{ "MOCK Track equipment and maintenance records.", "MOCK Register borrowers and their loans." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        const basis = try fixture.proposal("MOCK Business data is required.");
        const second = try binding.resolveGroups(a, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs, &.{fixture.context.references.records.signals[1].id}, .content);
        const entity: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = basis.value, .business_meaning = basis.value, .relationships = &.{basis.value} } }, .source_group_ids = second.source_group_ids, .provenance = second.selection };
        current.completed = sessions.entities_index;
        current.units[sessions.entities_index] = null;
        current.units[sessions.records_index] = null;
        current.record_cursor = 0;
        current.record_batches = &.{};
        const response: g.Response = .{ .content = .{ .entities = .{ .disposition = .required, .basis = basis, .records = &.{entity} } } };
        const packet = try sessions.packet(a, current, fixture.context);
        defer @import("domain/model_input_packet.zig").release(packet);
        const selected = try schema.restrict(a, canonical_schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer selected.release();
        const bytes = try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response));
        try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = bytes });
        const parsed = try g.parse(a, bytes, try sessions.currentBinding(a, current, fixture.context));
        try std.testing.expectEqualDeep(second.selection, parsed.content.entities.records[0].provenance);
        const checked = (try validate_unit.execute(a, current, fixture.context, .{ .response = parsed })).valid;
        current = try sessions.appendBound(a, current, checked);
        try std.testing.expectEqual(sessions.records_index, current.completed);
        const batch_wire = try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, .{ .content = .{ .records = &.{entity} } }));
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, batch_wire, try sessions.currentBinding(a, current, fixture.context)));
        try std.testing.expectEqual(.unit_kind, (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{entity} } })).invalid.rule);
        const batch = try sessions.packet(a, current, fixture.context);
        defer @import("domain/model_input_packet.zig").release(batch);
        const batch_schema = try schema.restrict(a, canonical_schema.select(batch.resultDefinition().?).?, batch.excludedVariants(), batch.integerChoices());
        defer batch_schema.release();
        try @import("model_payload_schema_test.zig").checkDocument(batch_schema.selected().modelBytes(), .{ .bytes = batch_wire, .rejection = .unknown_variant, .path = "/records/0/content/kind" });
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.admit(a, current, fixture.context, .{ .unit = .records, .response = .{ .content = .{ .records = &.{try provenance.checkRecord(.model, a, text.validator, fixture.context, entity)} } } }));
        var wrong = response;
        const ordinary: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = basis.value } }, .source_group_ids = basis.source_group_ids, .provenance = basis.provenance };
        wrong.content.entities.records = &.{ordinary};
        try std.testing.expectEqual(.unit_kind, (try g.validate(a, text.validator, fixture.context, .entities, wrong)).invalid.rule);
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, wrong)), .{ .entities = .{ .records = @import("domain/reference_support.zig").records(fixture.context.references), .inputs = fixture.context.inputs } }));
        // An admitted entity unit is projected once, independent of the number
        // of business record batches. Every original source group still runs.
        while (current.completed == sessions.records_index) {
            const bound = (try sessions.currentBinding(a, current, fixture.context)).records;
            const value: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "MOCK Required observable behavior {d}.", .{current.record_cursor}) } }} };
            const records = [_]spec.Model.RecordProposal{
                .{ .content = .{ .functional_requirement = .{ .text = value } }, .source_group_ids = &.{bound.signal}, .provenance = bound.selection },
                .{ .content = .{ .acceptance_criterion = .{ .given = value, .when = value, .then = value } }, .source_group_ids = &.{bound.signal}, .provenance = bound.selection },
            };
            current = try sessions.appendBound(a, current, (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &records } } })).valid);
        }
        const assembled = try sessions.assemble(a, text.validator, fixture.context, current);
        var count: usize = 0;
        for (assembled.content.records) |record| if (record.id.kind == .entity) {
            count += 1;
            try std.testing.expectEqualDeep(second.selection.claim_ids, record.proposal.provenance.claim_ids);
            try std.testing.expectEqual(@as(usize, 0), try sessions.recordIndex(current, record.id));
        };
        try std.testing.expectEqual(@as(usize, 1), count);
        try std.testing.expectEqual(@as(usize, 2), current.record_batches.len);
        var forged_batch = current.units[sessions.records_index].?;
        const canonical_entity = current.units[sessions.entities_index].?.response.content.entities.records[0];
        forged_batch.response.content.records = try std.mem.concat(a, spec.RecordProposal, &.{ forged_batch.response.content.records, &.{canonical_entity} });
        try std.testing.expectEqual(.unit_kind, (try g.revalidate(a, text.validator, fixture.context, .records, forged_batch.response)).invalid.rule);
        var forged_entities = current.units[sessions.entities_index].?;
        forged_entities.response.content.entities.records = current.units[sessions.records_index].?.response.content.records[0..1];
        try std.testing.expectEqual(.unit_kind, (try g.revalidate(a, text.validator, fixture.context, .entities, forged_entities.response)).invalid.rule);
        var before_entities = current;
        before_entities.completed = sessions.entities_index;
        before_entities.units[sessions.entities_index] = null;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.append(before_entities, forged_entities));
        _ = (try @import("domain/specification_coverage.zig").check(a, fixture.context.references, current.units[0].?.response.content.brief, assembled.content)).valid;
        try provenance.validateStored(a, fixture.context.inputs, .{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences }, @import("domain/reference_support.zig").records(fixture.context.references), current.units[0].?.response.content.brief, assembled.content);
    }
}

test "record packets project current family presence without exposing prior drafts or per-group floors" {
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "MOCK Inspect registered equipment.", "MOCK Renew an eligible library loan." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 3);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.records_index;
        current.units[sessions.records_index] = null;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[2].?.response.content.entities.disposition = .required;
        const first = try sessions.packet(std.testing.allocator, current, fixture.context);
        defer packets.release(first);
        const first_requirements = (try std.json.parseFromSlice(std.json.Value, a, first.body(), .{})).value.object.get("record_requirements").?.object;
        try std.testing.expectEqual(@as(usize, 0), first_requirements.get("present_families").?.array.items.len);
        try std.testing.expectEqualDeep(first_requirements.get("required_families").?.array.items, first_requirements.get("unmet_required_families").?.array.items);
        const value = try fixture.proposal("MOCK PRIOR DRAFT NOT FOR COPYING");
        const response: g.Response = .{ .content = .{ .records = &.{
            .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance },
            .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance },
        } } };
        current = try sessions.appendBound(a, current, (try validate_unit.execute(a, current, fixture.context, .{ .response = response })).valid);
        const later = try sessions.packet(std.testing.allocator, current, fixture.context);
        defer packets.release(later);
        try std.testing.expect(std.mem.indexOf(u8, later.body(), "MOCK PRIOR DRAFT NOT FOR COPYING") == null);
        const body = (try std.json.parseFromSlice(std.json.Value, a, later.body(), .{})).value.object;
        try std.testing.expect(!body.contains("record_assembly"));
        const requirements = body.get("record_requirements").?.object;
        const present = requirements.get("present_families").?.array.items;
        try std.testing.expectEqual(@as(usize, 2), present.len);
        try std.testing.expectEqualStrings("acceptance_criterion", present[0].string);
        try std.testing.expectEqualStrings("functional_requirement", present[1].string);
        const unmet = requirements.get("unmet_required_families").?.array.items;
        try std.testing.expectEqual(@as(usize, 0), unmet.len);
        const narrowed = try sessions.withSelectionChoices(std.testing.allocator, later, fixture.context, value.provenance);
        defer packets.release(narrowed);
        const narrowed_body = (try std.json.parseFromSlice(std.json.Value, a, narrowed.body(), .{})).value.object;
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, body.get("record_requirements").?, .{}), try std.json.Stringify.valueAlloc(a, narrowed_body.get("record_requirements").?, .{}));
        const repair_packet = try sessions.packetForOptions(std.testing.allocator, current, fixture.context, sessions.records_index, .{ .task = "MOCK Repair one authorized field." });
        defer packets.release(repair_packet);
        try std.testing.expect(!(try std.json.parseFromSlice(std.json.Value, a, repair_packet.body(), .{})).value.object.contains("record_requirements"));
        const empty: g.Response = .{ .content = .{ .records = &.{} } };
        current = try sessions.appendBound(a, current, (try validate_unit.execute(a, current, fixture.context, .{ .response = empty })).valid);
        const after_empty = try sessions.packet(std.testing.allocator, current, fixture.context);
        defer packets.release(after_empty);
        const empty_requirements = (try std.json.parseFromSlice(std.json.Value, a, after_empty.body(), .{})).value.object.get("record_requirements").?;
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, body.get("record_requirements").?, .{}), try std.json.Stringify.valueAlloc(a, empty_requirements, .{}));
        var stale = current;
        const batches = try a.dupe(g.Checked, current.record_batches);
        stale.record_batches = batches;
        batches[1].record_assignment = null;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, stale, fixture.context));
        batches[1].record_assignment = current.record_batches[1].record_assignment;
        batches[1].record_assignment.?.references.bytes[0] ^= 1;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, stale, fixture.context));
        var incomplete = current;
        incomplete.record_batches = incomplete.record_batches[0..1];
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, incomplete, fixture.context));
        var mismatched = fixture.context;
        const signals = try a.dupe(references.r.Signal, fixture.context.references.records.signals);
        signals[0].value.content.model.business.value.segments = &.{.{ .literal = .{ .value = "MOCK Changed requirement under the same source group." } }};
        mismatched.references.records.signals = signals;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, current, mismatched));
        // Presence is a set and follows the canonical family order. It does not
        // make the semantic contents available as a draft for later copying.
        try std.testing.expectEqual(@as(usize, 2), current.record_batches[0].response.content.records.len);
    }
}

test "native record dispatch keeps clarifications bound without treating them as completed batches" {
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "MOCK Display the startup clock.", "MOCK Renew an eligible loan." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        const question = try fixture.proposal("MOCK Which condition permits this behavior?");
        const response: g.Response = .{ .clarification = .{ .reason = .missing, .question = question, .record_kind = .functional_requirement } };
        const admitted = (try validate_unit.execute(a, current, fixture.context, .{ .response = response })).valid;
        try std.testing.expect(admitted.response == .clarification);
        try std.testing.expect(admitted.record_assignment == null);
        try std.testing.expectEqualDeep(question.source_group_ids, admitted.response.clarification.question.source_group_ids);
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.appendBound(a, current, admitted));
        var foreign = response;
        foreign.clarification.question.source_group_ids = &.{fixture.context.references.records.signals[1].id};
        foreign.clarification.question.provenance.claim_ids = &.{.{ .ordinal = 2 }};
        const checked = (try g.validate(a, text.validator, fixture.context, .records, foreign)).valid;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.admit(a, current, fixture.context, checked));
        try std.testing.expectError(error.InvalidSpecificationUnit, validate_unit.execute(a, current, fixture.context, .{ .response = foreign }));
    }
}

test "record assembly requirements and narrowed packets exclude feature-owned entities" {
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    const schema = @import("domain/model_result_schema.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
    var fixture = try Fixture.initContent(a, "Renew a loan and display `MOCK Loan renewed!` with its new deadline.", .business_exact_string, true, "The requested action completes successfully.", 2);
    defer fixture.deinit();
    var current = try completedFixture(&fixture, false);
    current.completed = sessions.records_index;
    current.units[sessions.records_index] = null;
    current.record_cursor = 0;
    current.record_batches = &.{};
    const value = try fixture.proposal("The requested action completes successfully.");
    const ordinary: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const entity: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = value.value, .business_meaning = value.value, .relationships = &.{} } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const ordinary_wire = try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, .{ .content = .{ .records = &.{ordinary} } }));
    const entity_wire = try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, .{ .content = .{ .records = &.{entity} } }));
    for ([_]bool{ false, true }) |required| {
        current.units[2].?.response.content.entities.disposition = if (required) .required else .not_applicable;
        const initial = try sessions.packet(a, current, fixture.context);
        defer packets.release(initial);
        const body = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
        const families = body.get("record_requirements").?.object.get("required_families").?.array.items;
        try std.testing.expectEqual(@as(usize, 2), families.len);
        try std.testing.expectEqualStrings("acceptance_criterion", families[0].string);
        try std.testing.expectEqualStrings("functional_requirement", families[1].string);
        const selected = try schema.restrict(a, canonical.select(initial.resultDefinition().?).?, initial.excludedVariants(), initial.integerChoices());
        defer selected.release();
        try check(selected.selected().modelBytes(), .{ .bytes = ordinary_wire });
        try check(selected.selected().modelBytes(), .{ .bytes = entity_wire, .rejection = .unknown_variant, .path = "/records/0/content/kind" });
        const empty: g.Response = .{ .content = .{ .records = &.{} } };
        const early = (try validate_unit.execute(a, current, fixture.context, .{ .response = empty })).valid;
        const advanced = try sessions.appendBound(a, current, early);
        try std.testing.expectEqual(@as(usize, 1), advanced.record_cursor);
        try std.testing.expectEqual(@as(usize, 0), advanced.record_batches[0].response.content.records.len);
        const narrowed = try sessions.withSelectionChoices(a, initial, fixture.context, entity.provenance);
        defer packets.release(narrowed);
        const narrowed_body = (try std.json.parseFromSlice(std.json.Value, a, narrowed.body(), .{})).value.object;
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, body.get("record_requirements").?, .{}), try std.json.Stringify.valueAlloc(a, narrowed_body.get("record_requirements").?, .{}));
        const narrowed_schema = try schema.restrict(a, canonical.select(narrowed.resultDefinition().?).?, narrowed.excludedVariants(), narrowed.integerChoices());
        defer narrowed_schema.release();
        try check(narrowed_schema.selected().modelBytes(), .{ .bytes = ordinary_wire });
        try check(narrowed_schema.selected().modelBytes(), .{ .bytes = entity_wire, .rejection = .unknown_variant, .path = "/records/0/content/kind" });
    }
    current.units[2] = null;
    try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, current, fixture.context));
}

test "native record batch assembly preserves corrected field and unchanged sibling producers" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const json = @import("domain/model_candidate_json.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const first: Origin = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 9 }, .attempt = .{ .value = 1 } };
    const second: Origin = .{ .request = .{ .value = 10 }, .attempt = .{ .value = 1 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A visitor receives a startup greeting.", "A borrower receives a renewal receipt." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        try std.testing.expectEqual(@as(usize, 2), current.record_group_count);
        const good = try fixture.proposal("The requested result is observable.");
        const response: g.Response = .{ .content = .{ .records = &.{.{
            .content = .{ .acceptance_criterion = .{
                .given = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} },
                .when = good.value,
                .then = good.value,
            } },
            .source_group_ids = good.source_group_ids,
            .provenance = good.provenance,
        }} } };
        const initial: candidates.Candidate = .{
            .response = try g.parse(a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)), try sessions.currentBinding(a, current, fixture.context)),
            .origins = .{ .initial = first },
        };
        const invalid = (try validate_unit.execute(a, current, fixture.context, initial)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, initial, invalid);
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, initial, authorization, .{ .value = good.value }, corrected);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, fixed)).?.validated.result);
        const first_checked = (try validate_unit.execute(a, current, fixture.context, fixed)).valid;
        current = try sessions.appendBound(a, current, first_checked);
        try std.testing.expectEqual(sessions.records_index, current.completed);
        const next_response: g.Response = .{ .content = .{ .records = &.{.{
            .content = .{ .functional_requirement = .{ .text = good.value } },
            .source_group_ids = good.source_group_ids,
            .provenance = good.provenance,
        }} } };
        const later: candidates.Candidate = .{
            .response = try g.parse(a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, next_response)), try sessions.currentBinding(a, current, fixture.context)),
            .origins = .{ .initial = second },
        };
        current = try sessions.appendBound(a, current, (try validate_unit.execute(a, current, fixture.context, later)).valid);
        const combined = current.units[sessions.records_index].?;
        const given: candidates.Field = .{ .target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .given } } };
        const when: candidates.Field = .{ .target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .when } } };
        const later_text: candidates.Field = .{ .target = .{ .value = .{ .subject = .{ .record = 1 }, .field = .text } } };
        try std.testing.expectEqualDeep(corrected, combined.origins.at(given).?);
        try std.testing.expectEqualDeep(first, combined.origins.at(when).?);
        try std.testing.expectEqualDeep(second, combined.origins.at(later_text).?);
        try std.testing.expectEqualDeep(try first_checked.origins.stableTarget(given.target, 1), try combined.origins.stableTarget(given.target, 2));
        _ = try sessions.assemble(a, text.validator, fixture.context, current);
    }
}

test "record origin concatenation projects every field and preserves occurrence gaps" {
    const candidates = @import("domain/specification_candidate.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const first: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const second: Origin = .{ .request = .{ .value = 3 }, .attempt = .{ .value = 1 } };
    const a = std.testing.allocator;
    const left: candidates.Origins = .{
        .initial = first,
        .fields = &.{.{ .target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .given } }, .origin = corrected }},
        .record_occurrences = .{ .values = &.{.{ .ordinal = 2 }}, .next_ordinal = 4 },
    };
    const right: candidates.Origins = .{ .initial = second };
    const combined = try left.appendingRecords(a, 1, right, 1);
    defer a.free(combined.fields);
    defer a.free(combined.record_occurrences.values);
    const given: candidates.Field = .{ .target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .given } } };
    const when: candidates.Field = .{ .target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .when } } };
    try std.testing.expectEqualDeep(corrected, combined.at(given).?);
    try std.testing.expectEqualDeep(first, combined.at(when).?);
    try std.testing.expectEqualDeep(second, combined.at(.{ .target = .{ .record = 1 } }).?);
    try std.testing.expectEqualDeep(try left.stableTarget(given.target, 1), try combined.stableTarget(given.target, 2));
    const later = try combined.stableTarget(.{ .record = 1 }, 2);
    try std.testing.expectEqual(@as(usize, 3), later.value.record);
    try std.testing.expectEqualDeep(@as(?candidates.Target, .{ .record = 1 }), try combined.currentTarget(later, 2));
    try std.testing.expectError(error.InvalidSpecificationRepair, (candidates.Origins{ .fields = &.{.{ .target = .{ .value = .{ .subject = .title, .field = .value } }, .origin = corrected }} }).appendingRecords(a, 0, right, 1));
}

test "consolidated records preserve mixed siblings origins and competing-evidence rejection" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 1 } };
    const correction: Origin = .{ .request = .{ .value = 9 }, .attempt = .{ .value = 1 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display a startup greeting. Remote synchronization is excluded.", "Renew library loans. Assume an existing borrower account; purchases are excluded." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        const good = try fixture.proposal("The requested outcome is observable.");
        const assumption = try fixture.proposal("An existing account is available.");
        const exclusion = try fixture.proposal("Purchases are outside this feature.");
        const bad: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const records = [_]spec.Model.RecordProposal{
            .{ .content = .{ .functional_requirement = .{ .text = good.value } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance },
            .{ .content = .{ .assumption = .{ .text = bad } }, .source_group_ids = assumption.source_group_ids, .provenance = assumption.provenance },
            .{ .content = .{ .acceptance_criterion = .{ .given = good.value, .when = good.value, .then = good.value } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance },
            .{ .content = .{ .non_goal = .{ .text = exclusion.value } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance },
        };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .records = &records } }, .origins = .{ .initial = original } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqualDeep(@as(@import("domain/specification_candidate.zig").Target, .{ .value = .{ .subject = .{ .record = 1 }, .field = .text } }), rejected.issue.field.target);
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected);
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = assumption.value }, correction);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, fixed)).?.validated.result);
        for ([_]usize{ 0, 2, 3 }) |index| {
            try std.testing.expectEqualDeep(records[index], fixed.response.content.records[index]);
            try std.testing.expectEqualDeep(original, fixed.origins.at(.{ .target = .{ .provenance = .{ .record = index } } }).?);
        }
        const checked = (try validate_unit.execute(a, current, fixture.context, fixed)).valid;
        current = try appendMockChecked(a, current, fixture.context, checked);
        current.starting_ledger.next[@intFromEnum(spec.Kind.functional_requirement)] = 7;
        const assembled = try sessions.assemble(a, text.validator, fixture.context, current);
        try std.testing.expectEqual(.acceptance_criterion, assembled.content.records[0].id.kind);
        for (assembled.content.records) |record| {
            const index = try sessions.recordIndex(current, record.id);
            try std.testing.expectEqualDeep(record.proposal, checked.response.content.records[index]);
        }
        var required_entities = current;
        required_entities.units[2].?.response.content.entities.disposition = .required;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, required_entities));
        required_entities.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .required, .basis = good, .records = &.{.{ .content = .{ .entity = .{ .name = good.value, .business_meaning = good.value, .relationships = &.{} } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance }} } } })).valid;
        _ = try sessions.assemble(a, text.validator, fixture.context, required_entities);
        required_entities.units[2].?.response.content.entities.disposition = .not_applicable;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, required_entities));
        try std.testing.expectEqual(@as(usize, 0), try sessions.recordIndex(current, .{ .kind = .functional_requirement, .ordinal = 7 }));
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.recordIndex(current, .{ .kind = .functional_requirement, .ordinal = 1 }));
        // R46: duplicate optional content with different valid claim evidence
        // remains unsafe; consolidation cannot silently delete or publish it.
        var misclassified = records[3];
        misclassified.content.non_goal.text = good.value;
        var competing = misclassified;
        competing.provenance.claim_ids = &.{.{ .ordinal = 2 }};
        competing.source_group_ids = &.{fixture.context.references.records.signals[1].id};
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        const duplicate: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ records[0], misclassified, competing } } } };
        const failure = (try validate_unit.execute(a, current, fixture.context, duplicate)).invalid;
        try std.testing.expectEqual(.duplicate_record, failure.issue.rule);
        try std.testing.expectEqual(.competing_records, failure.issue.blocked.?);
        try std.testing.expectError(error.UnsafeSpecificationRepair, repair.authorize(a, current, fixture.context, duplicate, failure));
    }
}

test "completed repair packets retire authoring assignments while pending record groups remain bound" {
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display the startup time in UTC.", "Renew a loan and issue a receipt." }, 1..) |source, group_count| {
        var fixture = try Fixture.initContent(a, source, null, true, source, group_count);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, true);
        try std.testing.expectEqual(group_count, current.record_group_count);
        current.record_cursor = group_count;
        const completed = try sessions.packetFor(a, current, fixture.context, sessions.records_index);
        defer @import("domain/model_input_packet.zig").release(completed);
        const complete_json = try std.json.parseFromSlice(std.json.Value, a, completed.body(), .{});
        try std.testing.expect(complete_json.value.object.get("source_assignment").? == .null);
        for (0..sessions.unit_count) |index| {
            const selected = try sessions.packetForOptions(a, current, fixture.context, index, .{ .task = "MOCK selected completed replacement." });
            defer @import("domain/model_input_packet.zig").release(selected);
            const input = (try std.json.parseFromSlice(std.json.Value, a, selected.body(), .{})).value;
            try std.testing.expect(input.object.get("source_assignment").? == .null);
            try std.testing.expectEqualStrings("MOCK selected completed replacement.", try selectedNativeRepairTask(input));
        }
        var pending = current;
        pending.completed = sessions.records_index;
        pending.units[sessions.records_index] = null;
        try std.testing.expectError(error.InvalidSpecificationBinding, sessions.packetFor(a, pending, fixture.context, sessions.records_index));
        pending.record_cursor -= 1;
        pending.record_batches = pending.record_batches[0..pending.record_cursor];
        const assigned = try sessions.packetFor(a, pending, fixture.context, sessions.records_index);
        defer @import("domain/model_input_packet.zig").release(assigned);
        const assignment_json = try std.json.parseFromSlice(std.json.Value, a, assigned.body(), .{});
        try std.testing.expectEqualStrings("records", assignment_json.value.object.get("source_assignment").?.object.get("kind").?.string);
    }
}

test "source-bound record batches reject duplicates without merging their evidence" {
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "Display a startup greeting. Show the current UTC date and time.";
    var fixture = try Fixture.initContent(a, source, null, true, source, 2);
    defer fixture.deinit();
    var current = try completedFixture(&fixture, false);
    current.completed = sessions.records_index;
    current.record_cursor = 0;
    current.units[sessions.records_index] = null;
    const value = try fixture.proposal("The startup result is visible.");
    const first: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const previous = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{first} } })).valid;
    current.record_batches = &.{previous};
    current.record_cursor = 1;
    current.record_group_count = 2;
    const repeated = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{first} } })).valid;
    const same = (try sessions.checkConsistency(a, current, fixture.context, repeated)).?;
    try std.testing.expectEqual(.duplicate_record, same.rule);
    try std.testing.expect(same.blocked == null);
    var competing = first;
    competing.provenance.claim_ids = &.{.{ .ordinal = 2 }};
    competing.source_group_ids = &.{fixture.context.references.records.signals[1].id};
    const checked = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{competing} } })).valid;
    const issue = (try sessions.checkConsistency(a, current, fixture.context, checked)).?;
    try std.testing.expectEqual(.duplicate_record, issue.rule);
    try std.testing.expectEqual(.competing_records, issue.blocked.?);
    var distinct = first;
    distinct.content.functional_requirement.text = (try fixture.proposal("The clock result is visible.")).value;
    const different = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{distinct} } })).valid;
    try std.testing.expect((try sessions.checkConsistency(a, current, fixture.context, different)) == null);
}

test "grouped record clarifications retain family subjects and reject absent or foreign assignment selectors" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A librarian renews a loan.");
    defer fixture.deinit();
    const value = try fixture.proposal("Which renewal duration applies? State its duration and starting event.");
    for (std.enums.values(spec.Kind)) |kind| {
        const proposal: g.Response = .{ .clarification = .{ .reason = .missing, .question = value, .record_kind = kind } };
        if (kind == .entity) {
            try std.testing.expect((try g.validate(a, text.validator, fixture.context, .records, proposal)) == .invalid);
            const feature_question: g.Response = .{ .clarification = .{ .reason = .missing, .question = value } };
            const checked_entity = (try g.validate(a, text.validator, fixture.context, .entities, feature_question)).valid;
            const entity_needs = try (@import("actions/clarification/build_specification_clarification_need.zig").Action{}).execute(a, fixture.context.inputs.corpus.feature_id, fixture.context, checked_entity);
            try std.testing.expectEqualStrings("entities", entity_needs.entries[0].subject.unit);
            continue;
        }
        const checked = (try g.validate(a, text.validator, fixture.context, .records, proposal)).valid;
        const needs = try (@import("actions/clarification/build_specification_clarification_need.zig").Action{}).execute(a, fixture.context.inputs.corpus.feature_id, fixture.context, checked);
        try std.testing.expectEqualStrings(@tagName(kind), needs.entries[0].subject.unit);
        try std.testing.expect((try g.validate(a, text.validator, fixture.context, .primary_user_story, proposal)) == .invalid);
    }
    try std.testing.expect((try g.validate(a, text.validator, fixture.context, .records, .{ .clarification = .{ .reason = .missing, .question = value } })) == .invalid);
}

test "specification provenance rejects foreign missing duplicate stale and unaccepted support" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A customer books a visit.");
    defer fixture.deinit();
    const good = try fixture.value("A customer books a visit.");
    _ = try provenance.checkAttributed(.canonical, a, text.validator, fixture.context, good, .spec_story);
    for (0..6) |scenario| {
        var changed = good;
        switch (scenario) {
            0 => changed.provenance.claim_ids = &.{},
            1 => changed.provenance.claim_ids = &.{.{ .ordinal = 999 }},
            2 => changed.provenance.claim_ids = &.{ good.provenance.claim_ids[0], good.provenance.claim_ids[0] },
            3 => changed.provenance.citation_ids = &.{},
            4 => changed.provenance.citation_ids = &.{.{ .ordinal = 999 }},
            5 => changed.provenance.clarification_response_ids = &.{.{ .ordinal = 1 }},
            else => unreachable,
        }
        if (provenance.checkAttributed(.canonical, a, text.validator, fixture.context, changed, .spec_story)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.InvalidSpecification, error.InvalidReferenceReconciliation => {},
            else => return err,
        }
    }
    var stale = fixture.context;
    stale.inputs.corpus.state_id.bytes = "different-reference-state";
    try std.testing.expectError(error.InvalidSpecification, provenance.checkAttributed(.canonical, a, text.validator, stale, good, .spec_story));
    _ = try provenance.checkAttributed(.canonical, a, text.validator, fixture.context, try fixture.value("Write src/main.zig."), .spec_story);
}

test "exact specification values retain token references and never accept replacement display bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Show `MOCK Hello, World!`.", "Show `MOCK Booking confirmed!`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        for (all.entries, 0..) |item, index| if (item.claim.content == .preserved_token) {
            const ids = try a.dupe(references.r.ClaimId, &.{item.claim.id});
            const proposed: spec.AttributedValue = .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = item.claim.id } }} }, .source_group_ids = &.{fixture.context.references.records.signals[index].id}, .provenance = .{ .claim_ids = ids, .citation_ids = item.claim.citation_ids, .clarification_response_ids = &.{} } };
            const accepted = try provenance.checkAttributed(.canonical, a, text.validator, fixture.context, proposed, .entity_name);
            try std.testing.expectEqualDeep(proposed, accepted);
            const model: spec.Model.AttributedValue = .{ .value = proposed.value, .source_group_ids = proposed.source_group_ids, .provenance = selection(proposed.provenance) };
            try std.testing.expectEqualDeep(accepted, try provenance.checkAttributed(.model, a, text.validator, fixture.context, model, .entity_name));
            var wrong_model = model;
            var wrong_model_copy = wrong_model.value.segments[0].exact_copy;
            wrong_model_copy.claim_id.ordinal = 999;
            wrong_model.value.segments = &.{.{ .exact_copy = wrong_model_copy }};
            try std.testing.expectError(error.InvalidTypedText, provenance.checkAttributed(.model, a, text.validator, fixture.context, wrong_model, .entity_name));
            var wrong = proposed;
            var wrong_copy = wrong.value.segments[0].exact_copy;
            wrong_copy.claim_id.ordinal = 999;
            wrong.value.segments = &.{.{ .exact_copy = wrong_copy }};
            try std.testing.expectError(error.InvalidTypedText, provenance.checkAttributed(.canonical, a, text.validator, fixture.context, wrong, .entity_name));
        };
    }
}

test "native exact recognition derives occurrence lineage beyond fixed authored source groups" {
    const r = @import("domain/reference_reconciliation.zig");
    const projection = @import("domain/specification_projection.zig");
    const cases = [_]struct { source: []const u8, prose: []const u8, changed: []const u8 }{
        .{ .source = "Display `ACTIVE` to the visitor.", .prose = "The visitor sees ACTIVE.", .changed = "The visitor sees ACTIVE-PENDING." },
        .{ .source = "Use version `1.2` for the export.", .prose = "The export uses (1.2).", .changed = "The export uses 1.2.3." },
    };
    for (cases) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, case.source);
        defer fixture.deinit();
        const original = try fixture.proposal(case.prose);
        const all = try provenance.items(fixture.context);
        const token = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token) break entry.claim;
        } else return error.MissingTestToken;
        try std.testing.expect(!r.contains(r.ClaimId, original.provenance.claim_ids, token.id));
        const accepted = try provenance.checkAttributed(.model, a, text.validator, fixture.context, original, .spec_story);
        try std.testing.expectEqualDeep(original.source_group_ids, accepted.source_group_ids);
        try std.testing.expectEqualDeep(original.provenance.claim_ids, accepted.provenance.claim_ids);
        const effective = try provenance.effectiveClaims(a, accepted.provenance.claim_ids, &.{accepted.value});
        try std.testing.expect(r.contains(r.ClaimId, effective, token.id));
        try std.testing.expectEqualStrings(case.prose, (try projection.scalar(a, fixture.context, accepted)).bytes);
        _ = try provenance.checkAttributed(.canonical, a, text.validator, fixture.context, accepted, .spec_story);

        // A matching raw literal cannot masquerade as canonical occurrence data.
        var missing = accepted;
        missing.value = original.value;
        try std.testing.expectError(error.InvalidTypedText, provenance.checkAttributed(.canonical, a, text.validator, fixture.context, missing, .spec_story));
        const extended = try provenance.checkAttributed(.model, a, text.validator, fixture.context, try fixture.proposal(case.changed), .spec_story);
        try std.testing.expect(!r.contains(r.ClaimId, try provenance.effectiveClaims(a, extended.provenance.claim_ids, &.{extended.value}), token.id));
        const prohibited = try provenance.checkAttributed(.model, a, text.validator, fixture.context, original, .spec_title);
        try std.testing.expectEqualDeep(original.value, prohibited.value);

        // Repair eligibility cannot acquire a new E merely from matching bytes.
        const fixed = try provenance.recognizeValue(a, @import("domain/reference_support.zig").records(fixture.context.references), original.value, .spec_story, original.provenance.claim_ids);
        for (fixed.segments) |segment| try std.testing.expect(segment != .exact_copy);
    }
}

test "native exact recognition shares equal bytes but rejects distinct overlapping values and retains required prose" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var repeated = try Fixture.init(a, "Display `ACTIVE` beside another `ACTIVE` occurrence.");
    defer repeated.deinit();
    const original = try repeated.proposal("Display ACTIVE.");
    const accepted = try provenance.checkAttributed(.model, a, text.validator, repeated.context, original, .spec_story);
    try std.testing.expectEqualDeep(original.provenance.claim_ids, accepted.provenance.claim_ids);
    const originals = try @import("domain/reference_token_disposition.zig").originals(a, try provenance.items(repeated.context), .{ .ordinal = 2 });
    try std.testing.expectEqual(@as(usize, 2), originals.len);
    var exact_count: usize = 0;
    for (accepted.value.segments) |segment| if (segment == .exact_copy) {
        exact_count += 1;
        try std.testing.expectEqualDeep(originals[0], segment.exact_copy.claim_id);
    };
    try std.testing.expectEqual(@as(usize, 1), exact_count);
    var ambiguous = try Fixture.init(a, "Display `ACTIVE` or the distinct value `ACTIVE VALUE`.");
    defer ambiguous.deinit();
    var inspection: provenance.Inspection = .{};
    try std.testing.expectError(error.InvalidTypedText, provenance.inspectAttributed(.model, a, text.validator, ambiguous.context, try ambiguous.proposal("Display ACTIVE VALUE."), .spec_story, &inspection));
    try std.testing.expectEqual(.ambiguous_exact, inspection.text_issue.?.reason);

    var unique = try Fixture.init(a, "Display `ACTIVE` to the visitor.");
    defer unique.deinit();
    inspection = .{};
    try std.testing.expectError(error.InvalidTypedText, provenance.inspectAttributed(.model, a, text.validator, unique.context, try unique.proposal("ACTIVE"), .spec_story, &inspection));
    try std.testing.expectEqual(.reference_only, inspection.text_issue.?.reason);
    const incidental = try provenance.checkAttributed(.model, a, text.validator, unique.context, try unique.proposal("ACTIVE"), .entity_name);
    try std.testing.expectEqual(@as(usize, 1), incidental.value.segments.len);
    try std.testing.expect(incidental.value.segments[0] == .exact_copy);
}

test "full candidate revalidation cannot widen a fixed native repair occurrence scope" {
    const candidates = @import("domain/specification_candidate.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `ACTIVE` to the visitor.", "Export `report.csv` for the borrower." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const token = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token) break entry.claim;
        } else return error.MissingTestToken;
        const raw = try fixture.proposal(try std.fmt.allocPrint(a, "The user sees {s}.", .{token.content.preserved_token.value.raw_value.bytes}));
        const selected = try provenance.select(a, fixture.context, raw.provenance);
        const origins: candidates.Origins = .{};
        const target: candidates.Target = .{ .value = .{ .subject = .story, .field = .value } };
        var proposed: candidates.Candidate = .{
            .response = .{ .content = .{ .primary_user_story = raw } },
            .value_bound = .{
                .target = try origins.stableTarget(target, 0),
                .explicit = selected.claim_ids,
                .effective = selected.claim_ids,
                .citations = selected.citation_ids,
            },
        };
        try std.testing.expectError(error.InvalidSpecificationUnit, g.validateCandidate(a, text.validator, fixture.context, .primary_user_story, proposed));
        const accepted = try provenance.checkAttributed(.model, a, text.validator, fixture.context, raw, .spec_story);
        const retained = try provenance.lineageForRepair(a, fixture.context, raw.provenance, &.{accepted.value});
        proposed.value_bound.?.effective = retained.effective_claim_ids;
        proposed.value_bound.?.citations = retained.provenance.citation_ids;
        try std.testing.expect((try g.validateCandidate(a, text.validator, fixture.context, .primary_user_story, proposed)) == .valid);
    }
}

test "native exact recognition stays stable across prose normalization without creating byte authority" {
    const projection = @import("domain/specification_projection.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var composed = try Fixture.init(a, "Display `Café` to the visitor.");
    defer composed.deinit();
    var inspection: provenance.Inspection = .{};
    try std.testing.expectError(error.InvalidTypedText, provenance.inspectAttributed(.model, a, text.validator, composed.context, try composed.proposal("The visitor sees Cafe\u{301}."), .spec_story, &inspection));
    try std.testing.expectEqual(.unknown_exact, inspection.text_issue.?.reason);
    const exact = try provenance.checkAttributed(.model, a, text.validator, composed.context, try composed.proposal("The visitor sees Café."), .spec_story);
    _ = try provenance.checkAttributed(.canonical, a, text.validator, composed.context, exact, .spec_story);

    var decomposed = try Fixture.init(a, "Display `Cafe\u{301}` to the borrower.");
    defer decomposed.deinit();
    const prose = "The borrower sees Cafe\u{301}.";
    const accepted = try provenance.checkAttributed(.model, a, text.validator, decomposed.context, try decomposed.proposal(prose), .spec_story);
    try std.testing.expectEqualStrings(prose, (try projection.scalar(a, decomposed.context, accepted)).bytes);
    _ = try provenance.checkAttributed(.canonical, a, text.validator, decomposed.context, accepted, .spec_story);
}

test "stored native exact spans reject missing authority with consistent citations and forged eligible spans" {
    const refs = @import("domain/reference_support.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A user sees `ACTIVE` and exports `report.csv`.");
    defer fixture.deinit();
    const base = try fixture.proposal("The user observes the operation result.");
    const descriptive = try provenance.checkAttributed(.model, a, text.validator, fixture.context, base, .spec_title);
    const story = try provenance.checkAttributed(.model, a, text.validator, fixture.context, base, .spec_story);
    const record = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
        .content = .{ .functional_requirement = .{ .text = .{ .segments = &.{.{ .literal = .{ .value = "The user sees ACTIVE and exports report.csv." } }} } } },
        .source_group_ids = base.source_group_ids,
        .provenance = base.provenance,
    });
    const brief: g.Brief = .{ .title = descriptive, .description = descriptive, .primary_goal = descriptive };
    const content = (try identifiers.assign(a, .{ .display_name = descriptive, .primary_user_story = story, .records = &.{record}, .entities = .{ .disposition = .not_applicable, .basis = descriptive } }, .{})).content;
    const references_stored = refs.records(fixture.context.references);
    const passive = @import("domain/passive_literals.zig").Captured{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences };
    try provenance.validateStored(a, fixture.context.inputs, passive, references_stored, brief, content);

    // Remove both native spans and their derived citations. The forged S-only
    // lineage is internally consistent, so rejection must come from recomputing
    // the missing occurrence witnesses rather than an old citation mismatch.
    var missing = content;
    const missing_records = try a.dupe(spec.IdentifiedRecord, content.records);
    missing_records[0].proposal.content.functional_requirement.text = try provenance.modelValue(a, references_stored, record.content.functional_requirement.text);
    missing_records[0].proposal.provenance = descriptive.provenance;
    missing.records = missing_records;
    const literal_values = try provenance.recordValues(a, missing_records[0].proposal.content);
    const literal_lineage = try provenance.lineageForRepair(a, fixture.context, base.provenance, literal_values);
    try std.testing.expectEqualDeep(base.provenance.claim_ids, literal_lineage.effective_claim_ids);
    try std.testing.expectEqualDeep(descriptive.provenance.citation_ids, literal_lineage.provenance.citation_ids);
    try std.testing.expectError(error.InvalidTypedText, provenance.validateStored(a, fixture.context.inputs, passive, references_stored, brief, missing));

    // A real eligible handle also cannot assert a span inside a longer value.
    // Its captured bytes and citation union are valid; the delimiter witness is
    // forged. The same check covers an identifier suffix and a file extension.
    const all = try provenance.items(fixture.context);
    for ([_]struct { exact: []const u8, suffix: []const u8 }{
        .{ .exact = "ACTIVE", .suffix = "-PENDING." },
        .{ .exact = "report.csv", .suffix = ".bak." },
    }) |case| {
        const exact = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token and std.mem.eql(u8, entry.claim.content.preserved_token.value.raw_value.bytes, case.exact)) break entry.claim.id;
        } else return error.MissingTestToken;
        var forged = content;
        const forged_records = try a.dupe(spec.IdentifiedRecord, content.records);
        const forged_value: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = "The user sees " } }, .{ .exact_copy = .{ .claim_id = exact } }, .{ .literal = .{ .value = case.suffix } } } };
        forged_records[0].proposal.content.functional_requirement.text = forged_value;
        forged_records[0].proposal.provenance = (try provenance.lineageForRepair(a, fixture.context, base.provenance, &.{forged_value})).provenance;
        forged.records = forged_records;
        try std.testing.expectError(error.InvalidTypedText, provenance.validateStored(a, fixture.context.inputs, passive, references_stored, brief, forged));
    }
}

test "mixed prose and exact references survive repair coverage rendering and persisted validation" {
    const projection = @import("domain/specification_projection.zig");
    const markdown = @import("domain/specification_markdown.zig");
    const coverage = @import("domain/specification_coverage.zig");
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    const Segment = @import("domain/typed_text.zig").BusinessSegment;
    const Case = struct { source: []const u8, prefix: []const u8, suffix: []const u8 };
    for ([_]Case{
        .{ .source = "Display `MOCK Hello, World!` and the current UTC date/time.", .prefix = "Display ", .suffix = " and the current UTC date/time." },
        .{ .source = "Export `report.csv` with each input/output summary.", .prefix = "Export ", .suffix = " with each input/output summary." },
    }) |case| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, case.source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const token_claim = for (all.entries) |item| {
            if (item.claim.content == .preserved_token) break item.claim;
        } else return error.MissingTestToken;
        const token = token_claim.content.preserved_token;
        const fixed = try provenance.select(a, fixture.context, .{ .claim_ids = &.{ all.entries[0].claim.id, token_claim.id }, .clarification_response_ids = &.{} });
        const segments: []const Segment = &.{ .{ .literal = .{ .value = case.prefix } }, .{ .exact_copy = .{ .claim_id = token_claim.id } }, .{ .literal = .{ .value = case.suffix } } };
        const model: spec.Model.AttributedValue = .{ .value = .{ .segments = segments }, .source_group_ids = &.{ fixture.context.references.records.signals[0].id, fixture.context.references.records.signals[1].id }, .provenance = selection(fixed) };
        const value = try provenance.checkAttributed(.model, a, text.validator, fixture.context, model, .spec_story);
        const displayed = try projection.scalar(a, fixture.context, value);
        try std.testing.expectEqualStrings(try std.mem.concat(a, u8, &.{ case.prefix, token.value.raw_value.bytes, case.suffix }), displayed.bytes);
        try std.testing.expectEqual(@as(usize, 1), displayed.code_spans.len);
        const record = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = &.{fixture.context.references.records.signals[0].id}, .provenance = .{ .claim_ids = &.{all.entries[0].claim.id}, .clarification_response_ids = &.{} } });
        const descriptive = try provenance.checkAttributed(.model, a, text.validator, fixture.context, try fixture.proposal("The user receives the requested output."), .spec_title);
        const content = (try identifiers.assign(a, .{ .display_name = descriptive, .primary_user_story = value, .records = &.{record}, .entities = .{ .disposition = .not_applicable, .basis = descriptive } }, .{})).content;
        const brief: g.Brief = .{ .title = descriptive, .description = value, .primary_goal = descriptive };
        _ = try coverage.validate(a, fixture.context.references, brief, content);
        const document = try projection.project(a, fixture.context, content);
        const rendered = try markdown.render(a, document);
        try std.testing.expectEqualDeep(document, try markdown.parse(a, rendered));
        const persisted = try @import("domain/strict_json.zig").decode(spec.IdentifiedContent, a, try std.json.Stringify.valueAlloc(a, content, .{}), .{ .maximum_bytes = 100000, .maximum_depth = 32 });
        const references_stored = @import("domain/reference_support.zig").records(fixture.context.references);
        const passive = @import("domain/passive_literals.zig").Captured{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences };
        try provenance.validateStored(a, fixture.context.inputs, passive, references_stored, brief, persisted);
        var wrong = model;
        var selected = segments[1].exact_copy;
        selected.claim_id.ordinal += 100;
        wrong.value.segments = &.{ segments[0], .{ .exact_copy = selected }, segments[2] };
        const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        const plain_model: spec.Model.AttributedValue = .{ .value = descriptive.value, .source_group_ids = descriptive.source_group_ids, .provenance = selection(descriptive.provenance) };
        var repair_wrong = wrong;
        repair_wrong.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = plain_model, .description = repair_wrong, .primary_goal = plain_model } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(.typed_text, rejection.issue.rule);
        const authorized = try repair.authorize(a, current, fixture.context, candidate, rejection);
        const packet = try repair.packet(a, current, fixture.context, authorized);
        defer @import("domain/model_input_packet.zig").release(packet);
        const replacement: repair.Replacement = .{ .value = model.value };
        const plain = try provenance.modelValue(a, @import("domain/reference_support.zig").records(fixture.context.references), model.value);
        const wire = try @import("domain/model_candidate_json.zig").encode(struct { value: spec.BusinessValue }, a, .{ .value = plain });
        const decoded = try repair.parse(a, authorized, packet, wire);
        try std.testing.expectEqualDeep(repair.Replacement{ .value = plain }, decoded);
        try std.testing.expectError(error.InvalidJsonDocument, @import("domain/model_candidate_json.zig").encode(repair.Replacement, a, replacement));
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorized, decoded, null);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, merged)) == .valid);
        try std.testing.expectEqualDeep(candidate.response.content.brief.title, merged.response.content.brief.title);
        try std.testing.expectEqualDeep(candidate.response.content.brief.primary_goal, merged.response.content.brief.primary_goal);
        try std.testing.expectEqualDeep(wrong.provenance, merged.response.content.brief.description.provenance);
        var broken = persisted;
        broken.primary_user_story.value = wrong.value;
        try std.testing.expectError(error.InvalidTypedText, provenance.validateStored(a, fixture.context.inputs, passive, references_stored, brief, broken));
        var stale = fixture.context;
        stale.inputs.corpus.state_id.bytes = "other-source-state";
        try std.testing.expectError(error.InvalidSpecification, projection.scalar(a, stale, value));
    }
}

test "authored values and pending questions retain groups even when exact-only support is valid" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "MOCK Display `Completed!` after startup.");
    defer fixture.deinit();
    const all = try provenance.items(fixture.context);
    const token = all.entries[all.entries.len - 1].claim;
    const exact_only: spec.Model.AttributedValue = .{
        .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = token.id } }} },
        .source_group_ids = &.{},
        .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} },
    };
    // General exact-lineage inspection remains valid outside authored units.
    const inspected = try provenance.checkAttributed(.model, a, text.validator, fixture.context, exact_only, .entity_name);
    try std.testing.expectEqualDeep(token.citation_ids, inspected.provenance.citation_ids);
    const good = try fixture.proposal("MOCK The user sees the completed state.");
    const proposed: g.Response = .{ .content = .{ .brief = .{ .title = exact_only, .description = good, .primary_goal = good } } };
    const rejected = (try g.validate(a, text.validator, fixture.context, .brief, proposed)).invalid;
    try std.testing.expectEqual(.provenance, rejected.rule);
    const question: g.Response = .{ .clarification = .{ .reason = .missing, .question = exact_only } };
    try std.testing.expectEqual(.clarification_question, (try g.validate(a, text.validator, fixture.context, .brief, question)).invalid.blocked.?);
    const canonical = try fixture.value("MOCK The user sees the completed state.");
    const content: spec.IdentifiedContent = .{ .display_name = canonical, .primary_user_story = canonical, .entities = .{ .disposition = .not_applicable, .basis = canonical }, .records = &.{} };
    const brief: spec.Brief = .{ .title = inspected, .description = canonical, .primary_goal = canonical };
    try std.testing.expectEqual(.provenance, (try g.revalidate(a, text.validator, fixture.context, .brief, .{ .content = .{ .brief = brief } })).invalid.rule);
    try std.testing.expectError(error.InvalidSpecification, provenance.validateStored(a, fixture.context.inputs, .{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences }, @import("domain/reference_support.zig").records(fixture.context.references), brief, content));
}

test "code samples remain reference evidence and cannot be copied into business specification fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = "print(\"sample\")\n``` inside the example\n";
    var fixture = try Fixture.initClassified(a, "Example:\n~~~~text\n" ++ raw ++ "~~~~\n", .code_sample);
    defer fixture.deinit();
    const all = try provenance.items(fixture.context);
    const claim = for (all.entries) |item| {
        if (item.claim.content == .preserved_token) break item.claim;
    } else return error.MissingTestToken;
    const fixed = try provenance.select(a, fixture.context, .{ .claim_ids = &.{claim.id}, .clarification_response_ids = &.{} });
    const proposed: spec.Model.AttributedValue = .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = claim.id } }} }, .source_group_ids = &.{fixture.context.references.records.signals[all.entries.len - 1].id}, .provenance = selection(fixed) };
    try std.testing.expectError(error.InvalidTypedText, provenance.checkAttributed(.model, a, text.validator, fixture.context, proposed, .spec_story));
    try std.testing.expectEqual(@as(usize, 0), (try provenance.choicesFor(a, fixture.context, proposed.provenance)).exact_copy.len);
    const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
    const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
    const snapshot = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "references" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
    try @import("domain/reference_snapshot.zig").validate(a, snapshot);
    var forged = snapshot;
    const claims = try a.dupe(@import("domain/reference_extraction.zig").Claim, forged.extraction.claims);
    for (claims) |*entry| if (entry.content == .preserved_token) {
        entry.content.preserved_token.value.candidate_id.extractor_id = .markdown_inline_code_v1;
    };
    forged.extraction.claims = claims;
    try std.testing.expectError(error.InvalidReferenceSnapshot, @import("domain/reference_snapshot.zig").validate(a, forged));
    // Reusing the shared segment type cannot smuggle downstream token selections
    // into an extraction claim when reading canonical source evidence.
    const invalid_claims = try a.dupe(@import("domain/reference_extraction.zig").Claim, snapshot.extraction.claims);
    invalid_claims[0].content = .{ .model = .{ .business = .{ .value = .{ .segments = proposed.value.segments } } } };
    var invalid_extraction = snapshot.extraction;
    invalid_extraction.claims = invalid_claims;
    try std.testing.expectError(error.InvalidReferenceReconciliation, @import("domain/reference_claim_items.zig").build(a, snapshot.inputs, invalid_extraction));
    const bytes = try @import("domain/reference_context.zig").render(a, snapshot, null, null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "````\n" ++ raw ++ "````\n") != null);
}

test "unit parsing rejects model authority and ID ledger allocation remains engine owned" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Users view a greeting.");
    defer fixture.deinit();
    const value = try fixture.value("Users view a greeting.");
    const response: g.Response = .{ .content = .{ .primary_user_story = try fixture.proposal("Users view a greeting.") } };
    const bytes = try @import("domain/model_candidate_json.zig").encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response));
    const bound = try @import("domain/specification_source_binding.zig").forUnit(a, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs, .primary_user_story, 0);
    _ = try g.parse(a, bytes, bound);
    for ([_][]const u8{ "id", "completed", "path", "approved", "open_questions" }) |key| {
        const forged = try std.fmt.allocPrint(a, "{{\"{s}\":true,{s}", .{ key, bytes[1..] });
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, forged, bound));
    }
    const record: spec.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const content: spec.ContentProposal = .{ .display_name = value, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = &.{record} };
    const first = try identifiers.assign(a, content, .{});
    try std.testing.expectEqual(@as(u32, 1), first.content.records[0].id.ordinal);
    const next = try identifiers.assign(a, content, first.ledger);
    try std.testing.expectEqual(@as(u32, 2), next.content.records[0].id.ordinal);
    var exhausted = first.ledger;
    exhausted.next[@intFromEnum(spec.Kind.functional_requirement)] = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidSpecification, identifiers.assign(a, content, exhausted));
}

fn Fields(comptime kind: spec.Kind, value: spec.BusinessValue) @FieldType(spec.Content(spec.BusinessValue), @tagName(kind)) {
    const T = @FieldType(spec.Content(spec.BusinessValue), @tagName(kind));
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| {
        @field(result, field.name) = if (comptime field.type == spec.BusinessValue) value else &.{};
    }
    return result;
}
const Fixture = struct {
    allocator: std.mem.Allocator,
    context: provenance.Context,
    passive: text.Prepared,
    extracted: @import("domain/reference_extraction.zig").Accounted,
    extracted_text: @import("domain/reference_extraction.zig").TextValidated,
    fn init(a: std.mem.Allocator, bytes: []const u8) !Fixture {
        return initClassified(a, bytes, .business_exact_string);
    }
    fn initClassified(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind) !Fixture {
        return initExtraction(a, bytes, kind, true);
    }
    fn initExtraction(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, has_claims: bool) !Fixture {
        return initContent(a, bytes, kind, has_claims, "An extracted business claim.", 1);
    }
    fn initContent(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, has_claims: bool, claim_text: []const u8, model_claim_count: usize) !Fixture {
        return initContentKinds(a, bytes, kind, has_claims, claim_text, model_claim_count, false);
    }
    fn initContentKinds(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, has_claims: bool, claim_text: []const u8, model_claim_count: usize, include_technical: bool) !Fixture {
        return initClaims(a, bytes, kind, .{ .repeated = .{ .has_claims = has_claims, .text = claim_text, .count = model_claim_count, .technical = include_technical } });
    }
    const Claims = union(enum) {
        repeated: struct { has_claims: bool, text: []const u8, count: usize, technical: bool },
        selected: []const @import("domain/reference_extraction.zig").Proposal,
    };
    fn initClaims(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, supplied: Claims) !Fixture {
        var ids: evidence.IdSource = .{};
        const inputs = try evidence.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "stories.md", bytes));
        const passive = try text.prepare(a, inputs);
        errdefer passive.deinit();
        const candidates = try tokens.candidates(a, inputs);
        const raw = try a.alloc(@import("domain/reference_extraction.zig").RawResult, inputs.chunks.entries.len);
        for (inputs.chunks.entries, raw) |chunk, *entry| {
            var choices: std.ArrayList(@import("domain/structured_tokens.zig").Classification) = .empty;
            for (candidates.entries) |candidate| if (candidate.fact.scope.chunk_id.eql(chunk.id)) try choices.append(a, if (kind) |selected| .{ .preserve = .{ .token_candidate_id = candidate.id, .kind = selected } } else .{ .irrelevant = candidate.id });
            const json = @import("domain/model_candidate_json.zig");
            const Response = @import("domain/reference_extraction_parser.zig").Response;
            const reply = switch (supplied) {
                .selected => |claims| selected: {
                    std.debug.assert(inputs.chunks.entries.len == 1);
                    break :selected try json.encode(Response, a, .{ .claims = .{ .claims = claims, .token_classifications = choices.items } });
                },
                .repeated => |options| repeated: {
                    const initial = try tokens.wire(a, if (options.has_claims) try extraction.reply(a, chunk, options.text) else extraction.no_claim, choices.items);
                    if (!options.has_claims or options.count == 1) break :repeated initial;
                    var response = try json.decode(Response, a, initial);
                    const claims = try a.alloc(@import("domain/reference_extraction.zig").Proposal, options.count);
                    @memset(claims, response.claims.claims[0]);
                    if (options.technical) claims[1].content = .{ .technical = .{ .nodes = &.{.{ .literal = .{ .value = options.text } }} } };
                    response.claims.claims = claims;
                    break :repeated try json.encode(Response, a, response);
                },
            };
            entry.* = .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = reply } };
        }
        const parsed = try @import("domain/reference_extraction_parser.zig").parse(a, .{ .entries = raw });
        const extracted_text = try passive.check(a, inputs, parsed);
        const extracted = try extraction.finishText(a, inputs, extracted_text);
        const context: references.Context = .{ .inputs = inputs, .registry = passive.registry, .current = text.safety.value(passive.owner) };
        const global = try references.summaries(a, try references.initialize(a, inputs, extracted, 2), context);
        const complete = (try references.finish(a, global, try references.global(a, global), context)).valid;
        return .{ .allocator = a, .extracted = extracted, .extracted_text = extracted_text, .context = .{ .inputs = inputs, .references = complete, .registry = passive.registry, .current = context.current }, .passive = passive };
    }
    fn deinit(self: *Fixture) void {
        self.passive.deinit();
    }
    fn proposal(self: *const Fixture, bytes: []const u8) !spec.Model.AttributedValue {
        const canonical = try self.value(bytes);
        return .{ .value = canonical.value, .source_group_ids = canonical.source_group_ids, .provenance = selection(canonical.provenance) };
    }
    fn proposalAllGroups(self: *const Fixture, bytes: []const u8) !spec.Model.AttributedValue {
        const binding = @import("domain/specification_source_binding.zig");
        const records = @import("domain/reference_support.zig").records(self.context.references);
        const catalogue = try binding.catalogue(self.allocator, records, .content);
        const ids = try self.allocator.alloc(references.r.SignalId, catalogue.len);
        for (catalogue, ids) |group, *id| id.* = group.signal_id;
        const resolved = try binding.resolveGroups(self.allocator, records, self.context.inputs, ids, .content);
        var proposed = try self.proposal(bytes);
        proposed.source_group_ids = resolved.source_group_ids;
        proposed.provenance = resolved.selection;
        return proposed;
    }
    fn value(self: *const Fixture, bytes: []const u8) !spec.AttributedValue {
        const claim = self.context.references.records.assignments.checked.prior.prior.input.items[0].claim;
        const segments = try self.allocator.dupe(@import("domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = bytes } }});
        const claims = try self.allocator.dupe(references.r.ClaimId, &.{claim.id});
        const group = self.context.references.records.signals[0].id;
        return .{ .value = .{ .segments = segments }, .source_group_ids = try self.allocator.dupe(references.r.SignalId, &.{group}), .provenance = .{ .claim_ids = claims, .citation_ids = claim.citation_ids, .clarification_response_ids = &.{} } };
    }
};

test "atomic specification repair preserves siblings and rejects stale or foreign replacements" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A visitor sees a greeting.", "A borrower renews a loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        const good = try fixture.proposal(source);
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection);
        try std.testing.expect(authorization.target.value.subject == .description);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization);
        defer packets.release(packet);
        try checkAuthoringPacket(a, packet.body());
        const replacement: repair.Replacement = .{ .value = good.value };
        const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
        const parsed = try repair.parse(a, authorization, packet, wire);
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, parsed, null);
        try std.testing.expectEqual(@as(u64, 2), merged.revision);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.title);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.primary_goal);
        try std.testing.expectEqualDeep(bad, candidate.response.content.brief.description);
        _ = (try g.validate(a, text.validator, fixture.context, .brief, merged.response)).valid;
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, merged, rejection));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, merged, authorization, parsed, null));
        var changed = candidate;
        changed.response.content.brief.description = good;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, changed, authorization, parsed, null));
        var foreign = current;
        foreign.feature.bytes = "another-feature";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), foreign, fixture.context, candidate, authorization, parsed, null));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, foreign, fixture.context, authorization));
        var wrong_id = authorization;
        wrong_id.id.bytes = "foreign-repair";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.parse(a, wrong_id, packet, try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement)));
        const with_target = try std.fmt.allocPrint(a, "{{\"target\":\"title\",{s}", .{wire[1..]});
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, with_target));
        const with_sibling = try std.fmt.allocPrint(a, "{{\"record\":{{}},{s}", .{wire[1..]});
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, with_sibling));
        const still_invalid = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = bad.value }, null);
        try std.testing.expectEqual(.typed_text, (try g.validate(a, text.validator, fixture.context, .brief, still_invalid.response)).invalid.rule);
    }
}

test "active scalar repairs present one selected task and retain their bound source selections" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const descriptions = @import("domain/required_authority_description.zig");
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    for ([_][]const u8{ "MOCK A visitor sees a startup greeting.", "MOCK A borrower receives a renewal receipt." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schema_owner = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
        const cases = [_]struct { index: usize, subject: candidates.Subject, slot: @import("domain/required_authority.zig").Slot, disposition: spec.Applicability = .not_applicable }{
            .{ .index = 0, .subject = .title, .slot = .display_name },
            .{ .index = 0, .subject = .description, .slot = .description },
            .{ .index = 0, .subject = .primary_goal, .slot = .primary_goal },
            .{ .index = 1, .subject = .story, .slot = .primary_user_story },
            .{ .index = 2, .subject = .entity_basis, .slot = .entities },
            .{ .index = 2, .subject = .entity_basis, .slot = .entities, .disposition = .required },
        };
        for (cases) |case| {
            var current = try completedFixture(&fixture, false);
            const good = try fixture.proposal(source);
            const original: g.Response = .{ .content = switch (case.index) {
                0 => .{ .brief = .{ .title = good, .description = good, .primary_goal = good } },
                1 => .{ .primary_user_story = good },
                2 => .{ .entities = .{ .disposition = case.disposition, .basis = good, .records = if (case.disposition == .required) &.{.{ .content = .{ .entity = .{ .name = good.value, .business_meaning = good.value, .relationships = &.{} } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance }} else &.{} } },
                else => return error.UnexpectedRecordAssignment,
            } };
            current.completed = case.index;
            for (current.units[case.index..]) |*unit_value| unit_value.* = null;
            const target: candidates.Target = .{ .value = .{ .subject = case.subject, .field = .value } };
            const candidate: repair.Candidate = .{ .response = try candidates.replace(a, original, target, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} } }) };
            const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
            try std.testing.expectEqualDeep(target, rejection.issue.field.target);
            const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection);
            const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization);
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            const input = body.get("input").?;
            try std.testing.expectEqualStrings(try descriptions.task(a, .{ .kind = if (case.slot == .entities) .entity_applicability else .feature_intent, .unit = .{ .feature = .singleton }, .slot = case.slot }), try selectedNativeRepairTask(input));
            const assigned = try json.decode(binding.Guidance, a, try std.json.Stringify.valueAlloc(a, input.object.get("source_assignment").?, .{}));
            switch (assigned) {
                .brief => {},
                .primary_user_story => {},
                .entities => {},
                .records => return error.UnexpectedRecordAssignment,
            }
            const initial = try sessions.packet(std.testing.allocator, current, fixture.context);
            defer packets.release(initial);
            const initial_body = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
            if (case.subject == .entity_basis) {
                // The same decision-and-basis purpose governs initial authoring
                // and repair of the selected explanation, for either disposition.
                const purpose = try descriptions.task(a, .{ .kind = .entity_applicability, .unit = .{ .feature = .singleton }, .slot = .entities });
                try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s}\n{s}", .{ purpose, try descriptions.record(a, .entity) }), initial_body.get("source_assignment").?.object.get("purpose").?.string);
                try std.testing.expectEqualStrings(purpose, try @import("domain/required_authority_description.zig").task(a, .{ .kind = .entity_applicability, .unit = .{ .feature = .singleton }, .slot = .entities }));
                try std.testing.expectEqualStrings(purpose, try selectedNativeRepairTask(input));
            }
            inline for (.{ "context_requirements", "preserved_tokens", "sources" }) |key| try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, initial_body.get(key).?, .{}), try std.json.Stringify.valueAlloc(a, input.object.get(key).?, .{}));
            const selected = try candidates.attributedValue(.model, original, case.subject, .value);
            const replacement: repair.Replacement = .{ .value = selected.value };
            try @import("test_fixtures/prepared_model_repair.zig").check(a, initial, schema_owner, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, original)), null);
            try @import("test_fixtures/prepared_model_repair.zig").check(a, packet, schema_owner, try json.encodeSelected(repair.Replacement, a, replacement), null);
            const decoded = try repair.parse(a, authorization, packet, try json.encodeSelected(repair.Replacement, a, replacement));
            const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, decoded, null);
            try std.testing.expectEqualDeep(original, merged.response);
            if (case.subject == .entity_basis) try std.testing.expectEqual(case.disposition, merged.response.content.entities.disposition);
            _ = (try validate_unit.execute(a, current, fixture.context, merged)).valid;
        }
    }
}

test "record repair removes only an evidence-equivalent duplicate and preserves siblings" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    var current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    const value = try fixture.proposal("Borrower requests renewal.");
    inline for (.{ spec.Kind.acceptance_criterion, spec.Kind.business_rule }) |kind| {
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        const record: spec.Model.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, value.value)), .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        const proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ record, record } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, proposed, rejection);
        try std.testing.expectEqual(@as(usize, 1), authorization.target.record);
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, proposed, authorization, null, null);
        try std.testing.expectEqual(@as(usize, 1), merged.response.content.records.len);
        try std.testing.expectEqualDeep(record, merged.response.content.records[0]);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
        _ = (try g.validate(a, text.validator, fixture.context, .records, merged.response)).valid;
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, proposed, authorization, .{ .provenance = value.provenance }, null));
        var bad_sibling = record;
        const bad_value: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        bad_sibling.content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, bad_value));
        const with_sibling: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ record, record, bad_sibling } } } };
        const value_field: @import("domain/specification_candidate.zig").ValueField = if (kind == .acceptance_criterion) .given else .text;
        const stable = try with_sibling.origins.stableTarget(.{ .value = .{ .subject = .{ .record = 2 }, .field = value_field } }, 3);
        const remove = try repair.authorize(a, current, fixture.context, with_sibling, (try validate_unit.execute(a, current, fixture.context, with_sibling)).invalid);
        const shifted = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, with_sibling, remove, null, null);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, shifted)).?.validated.result);
        const remaining = (try validate_unit.execute(a, current, fixture.context, shifted)).invalid;
        const next = try repair.authorize(a, current, fixture.context, shifted, remaining);
        try std.testing.expectEqualDeep(stable, try shifted.origins.stableTarget(next.target, 2));
        try std.testing.expectEqualDeep(remove.retry.?.key.scope, next.retry.?.key.scope);
        try std.testing.expectEqual(remove.retry.?.maximum_targets, next.retry.?.maximum_targets);
    }
}

test "claim coverage rejects omitted business claims and unfulfilled exact-copy obligations" {
    const coverage = @import("domain/specification_coverage.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `MOCK Hello, World!`.", "Display `MOCK Loan renewed!`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const value = try fixture.value("The requested message is displayed.");
        const brief: g.Brief = .{ .title = value, .description = value, .primary_goal = value };
        var content: spec.IdentifiedContent = .{ .display_name = value, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = &.{} };
        try std.testing.expectError(error.InvalidSpecificationCoverage, coverage.validate(a, fixture.context.references, brief, content));
        const all = try provenance.items(fixture.context);
        const item = all.entries[all.entries.len - 1];
        const record: spec.IdentifiedRecord = .{ .id = .{ .kind = .user_visible_outcome, .ordinal = 1 }, .proposal = .{ .content = .{ .user_visible_outcome = .{ .text = .{ .segments = &.{ .{ .literal = .{ .value = "The user sees " } }, .{ .exact_copy = .{ .claim_id = item.claim.id } } } } } }, .provenance = .{ .claim_ids = &.{item.claim.id}, .citation_ids = item.claim.citation_ids, .clarification_response_ids = &.{} } } };
        content.records = &.{record};
        const accepted = try coverage.validate(a, fixture.context.references, brief, content);
        try std.testing.expectEqual(all.entries.len, accepted.accounts.len);
        try std.testing.expectEqual(@as(usize, 1), accepted.obligations.len);
        var missing = value;
        missing.provenance.claim_ids = &.{};
        content.primary_user_story = missing;
        content.entities.basis = missing;
        try std.testing.expectError(error.InvalidSpecificationCoverage, coverage.validate(a, fixture.context.references, .{ .title = missing, .description = missing, .primary_goal = missing }, content));
    }
}

test "meaningful requirements and observable criteria preserve exact output through generation and rendering" {
    const sessions = @import("domain/specification_session.zig");
    const coverage = @import("domain/specification_coverage.zig");
    const projection = @import("domain/specification_projection.zig");
    const codec = @import("domain/specification_markdown.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Example = struct { source: []const u8, story: []const u8, given: []const u8, when: []const u8, output: []const u8, required: []const u8, recommended: []const u8 };
    for ([_]Example{
        .{
            .source = "On startup the application MUST display `MOCK Hello, World!` and SHOULD show the date and time in UTC.",
            .story = "As a user, I want to start the application and see a greeting and the date and time in UTC.",
            .given = "the application is not running",
            .when = "the user starts the application and reads its greeting",
            .output = "MOCK Hello, World!",
            .required = "On startup the application MUST display MOCK Hello, World!.",
            .recommended = "On startup the application SHOULD show the date and time in UTC.",
        },
        .{
            .source = "After a successful loan renewal the service MUST display `MOCK Loan renewed!` and SHOULD show the new due date.",
            .story = "As a borrower, I want confirmation of a successful renewal and its new due date.",
            .given = "a loan renewal has succeeded",
            .when = "the borrower reads the renewal confirmation",
            .output = "MOCK Loan renewed!",
            .required = "After a successful loan renewal the service MUST display MOCK Loan renewed!.",
            .recommended = "After a successful loan renewal the service SHOULD show the new due date.",
        },
    }) |example| {
        var fixture = try Fixture.initContent(a, example.source, .business_exact_string, true, example.source, 1);
        defer fixture.deinit();
        const items = try provenance.items(fixture.context);
        const token_claim = items.entries[items.entries.len - 1].claim;
        const story = try fixture.proposal(example.story);
        const required = try fixture.proposal(example.required);
        const recommended = try fixture.proposal(example.recommended);
        const criterion: spec.Model.RecordProposal = .{
            .content = .{ .acceptance_criterion = .{
                .given = (try fixture.proposal(example.given)).value,
                .when = (try fixture.proposal(example.when)).value,
                .then = .{ .segments = &.{ .{ .literal = .{ .value = "the user sees " } }, .{ .exact_copy = .{ .claim_id = token_claim.id } } } },
            } },
            .source_group_ids = story.source_group_ids,
            .provenance = story.provenance,
        };
        const requirements = [_]spec.Model.RecordProposal{
            .{ .content = .{ .functional_requirement = .{ .text = required.value } }, .source_group_ids = required.source_group_ids, .provenance = required.provenance },
            .{ .content = .{ .functional_requirement = .{ .text = recommended.value } }, .source_group_ids = recommended.source_group_ids, .provenance = recommended.provenance },
        };
        var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = story, .description = story, .primary_goal = story } },
                .primary_user_story => .{ .primary_user_story = story },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = story } },
                .records => .{ .records = try std.mem.concat(a, spec.Model.RecordProposal, &.{ &.{criterion}, &requirements }) },
            } };
            const decoded = try g.parse(a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)), try sessions.currentBinding(a, current, fixture.context));
            current = try appendMockResponse(a, current, fixture.context, decoded);
        }
        const content = (try sessions.assemble(a, text.validator, fixture.context, current)).content;
        const brief = current.units[0].?.response.content.brief;
        const accounted = try coverage.validate(a, fixture.context.references, brief, content);
        try std.testing.expectEqual(items.entries.len, accounted.accounts.len);
        try std.testing.expectEqual(@as(usize, 1), accounted.obligations.len);
        const document = try projection.project(a, fixture.context, content);
        try std.testing.expectEqual(@as(usize, 3), document.records.len);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "the user sees {s}", .{example.output}), document.records[0].content.acceptance_criterion.then.bytes);
        try std.testing.expectEqualStrings(example.required, document.records[1].content.functional_requirement.text.bytes);
        try std.testing.expectEqualStrings(example.recommended, document.records[2].content.functional_requirement.text.bytes);
        const rendered = try codec.render(a, document);
        try std.testing.expectEqualDeep(document, try codec.parse(a, rendered));

        // The handle supplies its claim without changing the explicit selection.
        var missing = criterion;
        missing.provenance = story.provenance;
        const derived = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{missing} } })).valid;
        try std.testing.expectEqualDeep(story.provenance.claim_ids, derived.response.content.records[0].provenance.claim_ids);
        try std.testing.expectEqual(@as(usize, 2), derived.response.content.records[0].provenance.citation_ids.len);
        // A complete exact value is recognized, but it cannot supply the
        // narrative required by an acceptance criterion on its own.
        missing.content.acceptance_criterion.then = (try fixture.proposal(example.output)).value;
        const exact_only = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{missing} } })).invalid;
        try std.testing.expectEqual(.reference_only, exact_only.text_issue.?.reason);
        var referenced_story = story;
        referenced_story.value = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "{s} The required output is {s}.", .{ example.story, example.output }) } }} };
        const linked_story = try provenance.checkAttributed(.model, a, text.validator, fixture.context, referenced_story, .spec_story);
        var incomplete = content;
        incomplete.primary_user_story = linked_story;
        try std.testing.expectEqualDeep(content.records[1..], incomplete.records[1..]);
        // Coverage is aggregate: one correctly referenced story can satisfy the
        // token obligation while raw-copy records remain unchanged. Passing this
        // gate does not prove every authored value followed the shared guidance.
        var referenced = incomplete;
        referenced.primary_user_story = linked_story;
        const restored = try coverage.validate(a, fixture.context.references, brief, referenced);
        try std.testing.expect(restored.obligations[0].exact_targets.len >= 1);
        try std.testing.expect(restored.obligations[0].exact_targets[0] == .primary_user_story);
        try std.testing.expectEqualDeep(incomplete.records, referenced.records);
    }
}

test "mandatory content gaps survive positive model review and scenario coverage has a shared gate" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const project = @import("domain/specification_authority.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "An application starts successfully.", "A librarian renews a loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const value = try fixture.value(source);
        for (0..5) |mode| {
            var records: std.ArrayList(spec.IdentifiedRecord) = .empty;
            if (mode & 1 != 0 or mode == 4) try records.append(a, .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } });
            if (mode & 2 != 0 or mode == 4) try records.append(a, .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .proposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } });
            const content: spec.IdentifiedContent = .{ .display_name = value, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = records.items };
            const inputs = try project.project(a, .{ .bytes = "chosen" }, fixture.context.references, content, .{ .title = value, .description = value, .primary_goal = value });
            const ledger = try authority.build(a, inputs);
            const findings = try a.alloc(support.Finding, ledger.requirements.len);
            for (ledger.requirements, findings, 0..) |requirement, *finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{
                .kind = if (mode == 4 and requirement.seed.id.slot == .scenario_coverage) .unsupported else .supported,
                .question = if (mode == 4 and requirement.seed.id.slot == .scenario_coverage) "What observable result establishes success for this scenario?" else null,
                .provenance = selection(value.provenance),
                .source_ids = &.{},
                .detail = "A required scenario is not established by the source.",
            } };
            const collected = try collectReview(support, a, inputs, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings }), null);
            if (inputs.forced_gaps.len != 0) {
                // Offered groups cannot establish support for an absent
                // collection. A positive model label is rejected at admission.
                try std.testing.expect(collected == .rejected);
                const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, ledger);
                const result = try authority.reconcile(a, ledger, observations);
                try std.testing.expectEqual(.blocked, result.continuation);
                var native_missing = false;
                for (result.entries) |entry| if (entry.candidate_defect) |defect| {
                    if (defect.reason == .missing_content) native_missing = true;
                };
                try std.testing.expect(native_missing);
                var bypass = inputs;
                bypass.forced_gaps = &.{};
                try std.testing.expectError(error.InvalidRequiredAuthority, authority.build(a, bypass));
                continue;
            }
            const reviewed = collected.accepted.inputs;
            const checked = try authority.build(a, reviewed);
            const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, checked);
            const result = try authority.reconcile(a, checked, observations);
            try std.testing.expectEqual(.all_resolved, result.continuation);
            try std.testing.expect(try authority.validate(a, reviewed, observations, result));
            for (result.entries) |entry| if (entry.outcome == .clarification_required) {
                try std.testing.expectEqual(.spec, entry.outcome.clarification_required.owner);
                try std.testing.expectEqual(@as(authority.GapReason, if (mode == 4) .unsupported else .missing), entry.outcome.clarification_required.reason);
            };
            if (inputs.forced_gaps.len != 0) {
                var bypass = reviewed;
                bypass.forced_gaps = &.{};
                try std.testing.expectError(error.InvalidRequiredAuthority, authority.build(a, bypass));
            }
        }
    }
}

test "retained specification rejection distinguishes source binding and preserves sibling origins" {
    const repair = @import("domain/specification_repair.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const sessions = @import("domain/specification_session.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const initial: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const correction: Origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    const good = try fixture.proposal("A renewal is confirmed.");
    var bad = good;
    bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    const candidate: candidates.Candidate = .{ .origins = .{ .initial = initial }, .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = bad } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectEqual(.typed_text, rejected.issue.rule);
    try std.testing.expectEqual(.InvalidTypedText, rejected.issue.native_error.?);
    try std.testing.expectEqualDeep(initial, rejected.origin.?);
    try std.testing.expectEqualDeep(bad.value, rejected.issue.observed.?.value);
    const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected);
    const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = good.value }, correction);
    const sibling = (try validate_unit.execute(a, current, fixture.context, merged)).invalid;
    try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
    const sibling_authorization = try repair.authorize(a, current, fixture.context, merged, sibling);
    try std.testing.expect(!std.meta.eql(authorization.retry.?.key, sibling_authorization.retry.?.key));
    try std.testing.expectEqualDeep(authorization.retry.?.key.scope, sibling_authorization.retry.?.key.scope);
    try std.testing.expectEqual(authorization.retry.?.maximum_targets, sibling_authorization.retry.?.maximum_targets);
    try std.testing.expect(sibling.issue.field.target.value.subject == .primary_goal);
    try std.testing.expectEqualDeep(initial, sibling.origin.?);
    try std.testing.expectEqualDeep(correction, merged.origins.at(.{ .target = .{ .value = .{ .subject = .description, .field = .value } } }).?);
    try std.testing.expectEqualDeep(initial, merged.origins.at(.{ .target = .{ .value = .{ .subject = .title, .field = .value } } }).?);
    const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = bad.value }, correction);
    const again = (try validate_unit.execute(a, current, fixture.context, unchanged)).invalid;
    try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, unchanged)).?.validated.result);
    const repeated = try repair.authorize(a, current, fixture.context, unchanged, again);
    try std.testing.expectEqualDeep(authorization.retry.?.key, repeated.retry.?.key);
    const changed_invalid = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "\x01" } }} } }, correction);
    try std.testing.expect(changed_invalid.last_repair.?.changed);
    try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, changed_invalid)).?.validated.result);
    try std.testing.expectEqualDeep(authorization.retry.?.key, (try repair.authorize(a, current, fixture.context, changed_invalid, (try validate_unit.execute(a, current, fixture.context, changed_invalid)).invalid)).retry.?.key);
    try std.testing.expectEqual(false, unchanged.last_repair.?.changed);
    try std.testing.expectEqual(true, merged.last_repair.?.changed);
    try std.testing.expectEqual(.typed_text, again.issue.rule);
    try std.testing.expectEqualDeep(correction, again.origin.?);
    for (0..5) |scenario| {
        var foreign = rejected;
        switch (scenario) {
            0 => foreign.owner.specification_unit.feature_id.bytes = "another-feature",
            1 => foreign.issue.unit = .primary_user_story,
            2 => foreign.revision += 1,
            3 => foreign.origin = correction,
            4 => foreign.issue.observed = .{ .value = good.value },
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, foreign));
    }
    var wrong = candidate;
    wrong.response = .{ .content = .{ .primary_user_story = good } };
    const wrong_unit = (try validate_unit.execute(a, current, fixture.context, wrong)).invalid;
    try std.testing.expectEqual(.unit_kind, wrong_unit.issue.rule);
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, wrong, wrong_unit));
    var stale = fixture.context;
    stale.references.records.assignments.checked.prior.prior.input.progress.plan.layout.items.state_id.bytes = "foreign-state";
    try std.testing.expectError(error.InvalidSpecification, validate_unit.execute(a, current, stale, candidate));
    // Even a candidate with no values cannot mask an inconsistent source corpus.
    try std.testing.expectError(error.InvalidSpecification, g.validate(a, text.validator, stale, .records, .{ .content = .{ .records = &.{} } }));
}

test "retained specification rejection and authorization release allocation failures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A visitor confirms a reservation.");
    defer fixture.deinit();
    const current = (try @import("domain/specification_session.zig").initialize(a, .{ .bytes = "chosen" }, fixture.context)).ready;
    const good = try fixture.proposal("Reservation confirmation is visible.");
    var bad = good;
    bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    const candidate: @import("domain/specification_candidate.zig").Candidate = .{ .response = .{ .content = .{ .primary_user_story = bad } } };
    var story = current;
    story.completed = 1;
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(rejectionAllocationCase, .{ fixture.context, story, candidate, good });
}
fn rejectionAllocationCase(allocator: std.mem.Allocator, context: provenance.Context, current: @import("domain/specification_session.zig").Session, candidate: @import("domain/specification_candidate.zig").Candidate, good: spec.Model.AttributedValue) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const repair = @import("domain/specification_repair.zig");
    const rejected = (try validate_unit.execute(a, current, context, candidate)).invalid;
    const diagnostic: @import("domain/candidate_validation_diagnostic.zig").Diagnostic = .{ .specification = rejected };
    _ = try diagnostic.copy(a);
    const authorization = try repair.authorize(a, current, context, candidate, rejected);
    const packet = try repair.packet(allocator, current, context, authorization);
    defer @import("domain/model_input_packet.zig").release(packet);
    const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), current, context, candidate, authorization, .{ .value = good.value }, null);
    try std.testing.expect((try validate_unit.execute(a, current, context, merged)) == .valid);
}

fn selection(value: spec.Provenance) spec.Selection {
    return .{ .claim_ids = value.claim_ids, .clarification_response_ids = value.clarification_response_ids };
}

test "model evidence selections construct canonical citations and canonical revalidation detects tampering" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Confirm a reservation.", "Show a renewal receipt." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const proposal = try fixture.proposal(source);
        const response: g.Response = .{ .content = .{ .primary_user_story = proposal } };
        const checked = (try g.validate(a, text.validator, fixture.context, .primary_user_story, response)).valid;
        const expected = (try fixture.value(source)).provenance;
        try std.testing.expectEqualDeep(expected, checked.response.content.primary_user_story.provenance);
        _ = (try g.revalidate(a, text.validator, fixture.context, .primary_user_story, checked.response)).valid;
        var corrupt = checked.response;
        corrupt.content.primary_user_story.provenance.citation_ids = &.{};
        const rejected = (try g.revalidate(a, text.validator, fixture.context, .primary_user_story, corrupt)).invalid;
        try std.testing.expectEqual(.provenance, rejected.rule);
        try std.testing.expectEqualDeep(@import("domain/specification_candidate.zig").Field{ .target = .{ .provenance = .story } }, rejected.field);
        for (0..4) |scenario| {
            var bad = response;
            const selected = &bad.content.primary_user_story.provenance;
            switch (scenario) {
                0 => selected.claim_ids = &.{},
                1 => selected.claim_ids = &.{.{ .ordinal = 999 }},
                2 => selected.claim_ids = &.{ proposal.provenance.claim_ids[0], proposal.provenance.claim_ids[0] },
                3 => selected.clarification_response_ids = &.{.{ .ordinal = 1 }},
                else => unreachable,
            }
            try std.testing.expectEqual(.provenance, (try g.validate(a, text.validator, fixture.context, .primary_user_story, bad)).invalid.rule);
        }
    }
}

test "specification provenance preserves selected claim order and rejects reordered canonical citations" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Show `Reservation accepted!`.");
    defer fixture.deinit();
    const items = try provenance.items(fixture.context);
    try std.testing.expectEqual(@as(usize, 2), items.entries.len);
    const forward = try provenance.select(a, fixture.context, .{ .claim_ids = &.{ items.entries[0].claim.id, items.entries[1].claim.id }, .clarification_response_ids = &.{} });
    const reverse = try provenance.select(a, fixture.context, .{ .claim_ids = &.{ items.entries[1].claim.id, items.entries[0].claim.id }, .clarification_response_ids = &.{} });
    try std.testing.expectEqual(@as(usize, 2), forward.citation_ids.len);
    try std.testing.expectEqualDeep(items.entries[0].claim.citation_ids[0], forward.citation_ids[0]);
    try std.testing.expectEqualDeep(items.entries[1].claim.citation_ids[0], reverse.citation_ids[0]);
    var corrupt = forward;
    corrupt.citation_ids = reverse.citation_ids;
    try std.testing.expectError(error.InvalidSpecification, provenance.scopes(a, fixture.context, corrupt));
}

test "record value repair preserves business fields and isolates subsequent text rejection" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const initial: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower receives a renewal receipt.");
    defer fixture.deinit();
    const good = try fixture.proposal("The receipt is visible.");
    const bad = try fixture.proposal("Invalid\x01text");
    inline for (.{spec.Kind.acceptance_criterion}) |kind| {
        var current = (try sessions.initialize(a, .{ .bytes = "chosen" }, fixture.context)).ready;
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = good } } })).valid;
        var record: spec.Model.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, good.value)), .source_group_ids = good.source_group_ids, .provenance = good.provenance };
        record.content.acceptance_criterion.given = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        record.content.acceptance_criterion.then = bad.value;
        const field: candidates.ValueField = .then;
        const proposed: repair.Candidate = .{ .origins = .{ .initial = initial }, .response = .{ .content = .{ .records = &.{record} } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        try std.testing.expectEqualDeep(candidates.Target{ .value = .{ .subject = .{ .record = 0 }, .field = .given } }, rejected.issue.field.target);
        const authorized = try repair.authorize(a, current, fixture.context, proposed, rejected);
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, proposed, authorized, .{ .value = good.value }, corrected);
        try std.testing.expectEqualDeep(record.content.acceptance_criterion.when, fixed.response.content.records[0].content.acceptance_criterion.when);
        try std.testing.expectEqualDeep(record.content.acceptance_criterion.then, fixed.response.content.records[0].content.acceptance_criterion.then);
        const text_failure = (try validate_unit.execute(a, current, fixture.context, fixed)).invalid;
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, fixed)).?.validated.result);
        try std.testing.expectEqualDeep(candidates.Target{ .value = .{ .subject = .{ .record = 0 }, .field = field } }, text_failure.issue.field.target);
        try std.testing.expectEqualDeep(initial, text_failure.origin.?);
        const text_authorized = try repair.authorize(a, current, fixture.context, fixed, text_failure);
        const complete = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, fixed, text_authorized, .{ .value = good.value }, corrected);
        _ = (try validate_unit.execute(a, current, fixture.context, complete)).valid;
        try std.testing.expectEqualDeep(good.provenance, complete.response.content.records[0].provenance);
        try std.testing.expectEqualDeep(good.value, complete.response.content.records[0].content.acceptance_criterion.given);
        try std.testing.expectEqualDeep(record.content.acceptance_criterion.when, complete.response.content.records[0].content.acceptance_criterion.when);
        // The selected response cannot carry valid business text as a side effect.
        const packet = try repair.packet(a, current, fixture.context, authorized);
        defer @import("domain/model_input_packet.zig").release(packet);
        const broad = try @import("domain/model_candidate_json.zig").encode(spec.Model.AttributedValue, a, good);
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorized, packet, broad));
        const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, fixed, text_authorized, .{ .value = bad.value }, corrected);
        try std.testing.expectEqualDeep(corrected, (try validate_unit.execute(a, current, fixture.context, unchanged)).invalid.origin.?);
    }
}

test "coverage rejects unsafe whole-field reconstruction without changing business values" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_coverage_repair.zig");
    const check = @import("actions/specification/validate_specification_coverage.zig").Action{ .validator = text.validator };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `MOCK Hello, World!`.", "Display `MOCK Loan renewed!`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const claim = all.entries[all.entries.len - 1].claim;
        const token = claim.content.preserved_token;
        const good = try fixture.proposal("The requested outcome is observable.");
        const raw = token.value.raw_value.bytes;
        const normalized: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = raw[0..3] } }, .{ .literal = .{ .value = raw[3..] } } } };
        const record: spec.Model.RecordProposal = .{ .content = .{ .user_visible_outcome = .{ .text = good.value } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance };
        var exact_only = record;
        exact_only.content.user_visible_outcome.text = normalized;
        var inspection: provenance.Inspection = .{};
        try std.testing.expectError(error.InvalidTypedText, provenance.inspectRecord(.model, a, text.validator, fixture.context, exact_only, &inspection));
        try std.testing.expectEqual(.reference_only, inspection.text_issue.?.reason);
        const title = try fixture.proposalAllGroups("The requested outcome is named.");
        var current = (try sessions.initialize(a, .{ .bytes = "chosen" }, fixture.context)).ready;
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = title, .description = good, .primary_goal = good } },
                .primary_user_story => .{ .primary_user_story = good },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
                .records => .{ .records = &.{record} },
            } };
            current = try appendMockResponse(a, current, fixture.context, response);
        }
        const identified = try sessions.assemble(a, text.validator, fixture.context, current);
        const rejection = (try check.execute(a, current, fixture.context, identified.content)).invalid;
        try std.testing.expect(rejection.issue == .missing_exact_copy);
        try std.testing.expectEqual(.candidate, (@import("domain/candidate_validation_diagnostic.zig").Diagnostic{ .coverage = rejection }).attribution());
        const denied = (try repair.authorize(a, current, fixture.context, identified.content, rejection)).blocked;
        try std.testing.expectEqual(.no_independent_supported_target, denied.blocked.?);
        // Complete raw values acquire native lineage without authoring handles;
        // the surrounding prose must still express the field's behavior.
        var embedded = current;
        var embedded_record = record;
        embedded_record.content.user_visible_outcome.text = .{ .segments = &.{
            .{ .literal = .{ .value = "MOCK The visitor sees " } },
            .{ .literal = .{ .value = raw } },
        } };
        embedded.units[sessions.records_index] = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{embedded_record} } })).valid;
        const embedded_content = try sessions.assemble(a, text.validator, fixture.context, embedded);
        _ = (try check.execute(a, embedded, fixture.context, embedded_content.content)).valid;
        const recognized = embedded.units[sessions.records_index].?.response.content.records[0].content.user_visible_outcome.text;
        try std.testing.expectEqualDeep(claim.id, recognized.segments[1].exact_copy.claim_id);
        var stale_context = fixture.context;
        const names = try a.dupe(@import("domain/path_token_grammar.zig").ReferenceName, stale_context.registry.grammar.reference_names);
        names[0].basename = "changed.md";
        stale_context.registry.grammar.reference_names = names;
        try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.authorize(a, current, stale_context, identified.content, rejection));
        stale_context = fixture.context;
        stale_context.references.records.assignments.checked.prior.prior.input.progress.latest = null;
        try std.testing.expectError(error.InvalidReferenceReconciliation, repair.authorize(a, current, stale_context, identified.content, rejection));
        const index = sessions.records_index;
        var unsupported = current;
        unsupported.units[index] = .{ .unit = .records, .response = .{ .content = .{ .records = &.{} } } };
        const omitted = try sessions.assemble(a, text.validator, fixture.context, unsupported);
        const gap = (try check.execute(a, unsupported, fixture.context, omitted.content)).invalid;
        const blocked = try repair.authorize(a, unsupported, fixture.context, omitted.content, gap);
        try std.testing.expect(blocked == .blocked);
        {
            const data = @import("domain/pipeline_data.zig");
            const values = @import("application/pipeline_values.zig");
            const owned = @import("application/specification_values.zig").storage;
            const native_spec = @import("application/specification_workflow.zig");
            const native_repair = @import("application/specification_coverage_repair_workflow.zig");
            const session_value = value: {
                const owner = try owned.create(std.testing.allocator, .{});
                errdefer owned.destroy(owner);
                owner.payload = .{ .session = unsupported };
                break :value try values.adopt(std.testing.allocator, native_spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
            };
            defer values.destroy(session_value);
            var inputs: data.View = .{};
            inputs.slots[@intFromEnum(native_spec.session_schema.key)] = session_value;
            const rejected_value = value: {
                const owner = try owned.create(std.testing.allocator, inputs);
                errdefer owned.destroy(owner);
                owner.payload = .{ .coverage_rejected = gap };
                break :value try values.adopt(std.testing.allocator, native_spec.coverage_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
            };
            defer values.destroy(rejected_value);
            inputs.slots[@intFromEnum(native_spec.coverage_schema.key)] = rejected_value;
            const result_value = value: {
                const owner = try owned.create(std.testing.allocator, inputs);
                errdefer owned.destroy(owner);
                owner.payload = .{ .coverage_repair = blocked };
                break :value try values.adopt(std.testing.allocator, native_repair.schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
            };
            defer values.destroy(result_value);
            var current_view = inputs;
            current_view.slots[@intFromEnum(native_repair.schema.key)] = result_value;
            try std.testing.expect(try native_repair.authorizationBlocked(&current_view));
            const foreign_session = value: {
                const owner = try owned.create(std.testing.allocator, .{});
                errdefer owned.destroy(owner);
                owner.payload = .{ .session = unsupported };
                break :value try values.adopt(std.testing.allocator, native_spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
            };
            defer values.destroy(foreign_session);
            current_view.slots[@intFromEnum(native_spec.session_schema.key)] = foreign_session;
            try std.testing.expectError(error.InvalidCandidatePayload, native_repair.authorizationBlocked(&current_view));
            current_view.slots[@intFromEnum(native_spec.session_schema.key)] = session_value;
            const stale_rejection = value: {
                const owner = try owned.create(std.testing.allocator, inputs);
                errdefer owned.destroy(owner);
                owner.payload = .{ .coverage_rejected = gap };
                break :value try values.adopt(std.testing.allocator, native_spec.coverage_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
            };
            defer values.destroy(stale_rejection);
            current_view.slots[@intFromEnum(native_spec.coverage_schema.key)] = stale_rejection;
            try std.testing.expectError(error.InvalidCandidatePayload, native_repair.authorizationBlocked(&current_view));
            current_view.slots[@intFromEnum(native_spec.coverage_schema.key)] = rejected_value;
            try std.testing.expect(try native_repair.authorizationBlocked(&current_view));
        }
        const copied = try (@import("domain/candidate_validation_diagnostic.zig").Diagnostic{ .coverage = gap }).copy(a);
        try std.testing.expectEqualDeep(gap, copied.coverage);
    }
}

test "specification repair packets expose unchanged dependent fields and native value alternatives" {
    const repair = @import("domain/specification_repair.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A visitor sees a greeting.", "A borrower sees a renewal receipt." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const good = try fixture.proposal(source);
        for ([_]bool{ false, true }) |record| {
            var current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
            var bad = good;
            bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
            if (record) {
                current.completed = sessions.records_index;
                current.record_cursor = 0;
                current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = good } } })).valid;
            }
            const candidate: candidates.Candidate = .{ .response = .{ .content = if (record) .{ .records = &.{.{ .content = .{ .acceptance_criterion = .{ .given = bad.value, .when = good.value, .then = good.value } }, .source_group_ids = bad.source_group_ids, .provenance = bad.provenance }} } else .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
            const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
            const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
            const packet = try repair.packet(a, current, fixture.context, auth);
            defer packets.release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const input = body.value.object.get("input").?.object;
            // These fixtures have no accepted brief to supply as a dependency.
            try std.testing.expect(!input.contains("brief"));
            if (!record) {
                try std.testing.expect(!input.contains("candidate"));
                const retained = try json.decode(spec.Selection, a, try std.json.Stringify.valueAlloc(a, input.get("provenance").?, .{}));
                try std.testing.expectEqualDeep(bad.provenance, retained);
            } else {
                const read = try json.decode(candidates.ReadContext, a, try std.json.Stringify.valueAlloc(a, input.get("candidate").?, .{}));
                const retained_selection = if (record) read.record.provenance else read.attributed.provenance;
                try std.testing.expectEqualDeep(bad.provenance, retained_selection);
                if (record) {
                    try std.testing.expectEqualDeep(good.value, read.record.content.acceptance_criterion.when);
                    try std.testing.expectEqualDeep(good.value, read.record.content.acceptance_criterion.then);
                    try std.testing.expectEqualDeep(bad.value, read.record.content.acceptance_criterion.given);
                } else try std.testing.expectEqualDeep(bad.value, read.attributed.value);
            }
            try std.testing.expect(body.value.object.get("repair").?.object.get("rule").?.object.get("value_choices") == null);
            try std.testing.expectEqual(@as(usize, 0), input.get("preserved_tokens").?.array.items.len);
            const replacement: repair.Replacement = .{ .value = good.value };
            const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, auth, try repair.parse(a, auth, packet, try json.encodeSelected(repair.Replacement, a, replacement)), null);
            _ = (try validate_unit.execute(a, current, fixture.context, merged)).valid;
            const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, auth, auth.operation.replace, null);
            try std.testing.expect((try validate_unit.execute(a, current, fixture.context, unchanged)) == .invalid);
        }
    }
    var fixture = try Fixture.init(a, "Display `Renewal accepted!`.");
    defer fixture.deinit();
    const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    const all = try provenance.items(fixture.context);
    const selected = all.entries[all.entries.len - 1].claim;
    var value = try fixture.proposal("Renewal is confirmed.");
    value.source_group_ids = try mockClaimGroup(a, fixture.context, selected.id);
    value.provenance.claim_ids = &.{selected.id};
    value.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    const good_title = try fixture.proposal("Renewal confirmation.");
    const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = good_title, .description = value, .primary_goal = value } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
    const choices = auth.rule.value_choices.?;
    try std.testing.expectEqualDeep(&[_]@import("domain/typed_text.zig").ExactCopy{.{ .claim_id = selected.id }}, choices.exact_copy);
    const packet = try repair.packet(a, current, fixture.context, auth);
    defer packets.release(packet);
    const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    try std.testing.expect(body.value.object.get("repair").?.object.get("rule").?.object.get("value_choices") == null);
    try std.testing.expectEqual(@as(usize, 1), body.value.object.get("input").?.object.get("preserved_tokens").?.array.items.len);
    const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, auth, .{ .value = .{ .segments = &.{ .{ .literal = .{ .value = "Show " } }, .{ .exact_copy = choices.exact_copy[0] } } } }, null);
    try std.testing.expectEqualDeep(value.provenance, merged.response.content.brief.description.provenance);
    try std.testing.expectEqualDeep(good_title, merged.response.content.brief.title);
    try std.testing.expectEqualDeep(value, merged.response.content.brief.primary_goal);
    // One corrected value is not acceptance of its still-invalid siblings.
    try std.testing.expectEqual(.typed_text, (try validate_unit.execute(a, current, fixture.context, merged)).invalid.issue.rule);
}

test "source-only extraction omissions remain candidate defects without clarification or invented claim authority" {
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    const gaps = @import("domain/required_authority_clarifications.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "On startup display `MOCK Hello, World!` and the current UTC date and time.", "After renewal display `MOCK Loan renewed!` and the new return deadline." }) |source| {
        var fixture = try Fixture.initExtraction(a, source, null, false);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const packet = try reviewPacketAt(support, a, inputs, fixture.context, 0);
        defer @import("domain/model_input_packet.zig").release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        const feature_id = (try @import("domain/required_authority.zig").build(a, inputs)).requirements[0].seed.id;
        try expectReviewAssessmentScope(.source, a, .{ .object = body }, feature_id);
        try std.testing.expect(feature_id.unit == .feature);
        try std.testing.expectEqualStrings("source_preservation", body.get("subject").?.object.get("kind").?.string);
        const feature_instruction = body.get("assessment_scope").?.object.get("instruction").?.string;
        try std.testing.expect(std.mem.indexOf(u8, feature_instruction, "assigned business purpose before authoring") != null);
        try std.testing.expect(std.mem.indexOf(u8, feature_instruction, "Sources need not supply prewritten specification fields") != null);
        try std.testing.expect(std.mem.indexOf(u8, feature_instruction, "complete assigned original source") == null);
        const preservation_inputs = try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs);
        const source_id = try support.nextSubject(a, preservation_inputs, null);
        try std.testing.expect(source_id.unit == .source);
        const source_packet = try support.packetFor(std.testing.allocator, preservation_inputs, fixture.context, .{ .finding = source_id });
        defer @import("domain/model_input_packet.zig").release(source_packet);
        const source_body = (try std.json.parseFromSlice(std.json.Value, a, source_packet.body(), .{})).value;
        try expectReviewAssessmentScope(.source, a, source_body, source_id);
        try std.testing.expectEqualStrings("reference", source_body.object.get("subject").?.object.get("kind").?.string);
        const selected_source = try json.decode(@import("domain/specification_review_subject.zig").Subject, a, try std.json.Stringify.valueAlloc(a, source_body.object.get("subject").?, .{}));
        try std.testing.expectEqualDeep(source_id.unit.source, selected_source.reference.source);
        const source_instruction = source_body.object.get("assessment_scope").?.object.get("instruction").?.string;
        try std.testing.expect(std.mem.indexOf(u8, source_instruction, "complete assigned original source") != null);
        try std.testing.expect(std.mem.indexOf(u8, source_instruction, "including meaning with no surviving claim") != null);
        try std.testing.expectEqualStrings(source, source_body.object.get("sources").?.array.items[0].object.get("text").?.string);
        try std.testing.expectEqual(@as(usize, 0), source_body.object.get("claims").?.array.items.len);
        try std.testing.expectEqualStrings(source, body.get("sources").?.array.items[0].object.get("text").?.string);
        try std.testing.expectEqual(@as(usize, 0), body.get("claims").?.array.items.len);
        const extracted = body.get("extraction").?.array.items[0].object;
        try std.testing.expectEqualStrings("no_feature_claim", extracted.get("outcome").?.object.get("kind").?.string);
        try std.testing.expectEqualStrings("irrelevant", extracted.get("token_classifications").?.array.items[0].object.get("decision").?.object.get("kind").?.string);
        const base = try reviewFor(a, inputs, fixture.context.inputs);
        const findings = try a.dupe(support.Finding, base.entries);
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 14 }, .attempt = .{ .value = 1 } };
        for (findings) |*finding| finding.value = .{ .kind = .candidate_omission, .missing_obligation = fixture.context.inputs.corpus.sources[0].bytes, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = "Extraction discarded the source-required behavior." };
        const admitted = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), origin)).accepted.inputs;
        const decision = try supportDecision(a, admitted);
        try std.testing.expectEqual(.invalid, decision.result.continuation);
        for (decision.result.entries) |entry| try std.testing.expect(entry.candidate_defect != null);
        try std.testing.expectError(error.InvalidRequiredAuthority, gaps.build(a, fixture.context.inputs, admitted, decision.observations, decision.result));
        try std.testing.expectEqualDeep(origin, admitted.review_origin.?);
        try std.testing.expectEqual(@as(usize, 0), admitted.candidates.len);
        // A source-only omission has no authored candidate to blame. It keeps
        // the original source repair path without manufacturing claim evidence.
        findings[0].value.loss = .{ .candidate = .{} };
        try std.testing.expect((try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), origin)) == .rejected);
        findings[0].value.loss = .{ .unlocalized = .{} };
        // A source ID cannot manufacture the claim provenance required by a
        // positive verdict. Genuine authority gaps still produce user forms.
        for (findings) |*finding| finding.value.kind = .supported;
        try std.testing.expect((try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), origin)) == .rejected);
        for (findings) |*finding| {
            finding.value.kind = .unsupported;
            finding.value.missing_obligation = null;
            finding.value.question = "Which deadline should apply? State the duration and starting event.";
            finding.value.source_ids = &.{};
            finding.value.detail = "The source does not establish this requirement.";
        }
        const missing = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), origin)).accepted.inputs;
        const unresolved = try supportDecision(a, missing);
        try std.testing.expectEqual(.needs_user, unresolved.result.continuation);
        try std.testing.expectEqual(findings.len, (try gaps.build(a, fixture.context.inputs, missing, unresolved.observations, unresolved.result)).entries.len);
    }
}

test "native specification dependencies reject changed grammar and broken history independently of presentation" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    const facts = @import("domain/specification_candidate_context.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Display `Receipt issued!`.");
    defer fixture.deinit();
    const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    const good = try fixture.proposal("The borrower sees a receipt.");
    var bad = good;
    bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = bad, .description = good, .primary_goal = good } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
    const original = try sessions.packet(a, current, fixture.context);
    defer packets.release(original);
    const stamp = try facts.snapshot(a, current, fixture.context, candidate);
    // Formatting a presentation has no input to the native dependency capture.
    const presented = try std.json.parseFromSlice(std.json.Value, a, original.body(), .{});
    const formatted = try packets.create(a, try std.json.Stringify.valueAlloc(a, presented.value, .{ .whitespace = .indent_2 }), original.unit(), original.purpose(), original.resultDefinition());
    defer packets.release(formatted);
    try std.testing.expect(!std.mem.eql(u8, original.body(), formatted.body()));
    try std.testing.expectEqualDeep(stamp, try facts.snapshot(a, current, fixture.context, candidate));
    var context = fixture.context;
    const names = try a.dupe(@import("domain/path_token_grammar.zig").ReferenceName, context.registry.grammar.reference_names);
    names[0].basename = "changed.md";
    context.registry.grammar.reference_names = names;
    const same_presentation = try sessions.packet(a, current, context);
    defer packets.release(same_presentation);
    try std.testing.expectEqualStrings(original.body(), same_presentation.body());
    try std.testing.expectError(error.InvalidPathTokenGrammar, validate_unit.execute(a, current, context, candidate));
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, context, candidate, rejected));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, current, context, auth));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), current, context, candidate, auth, .{ .value = good.value }, null));
    context = fixture.context;
    try std.testing.expect(context.references.records.assignments.checked.prior.prior.input.progress.summary_count > 0);
    context.references.records.assignments.checked.prior.prior.input.progress.latest = null;
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.authorize(a, current, context, candidate, rejected));
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.packet(a, current, context, auth));
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), current, context, candidate, auth, .{ .value = good.value }, null));
}

fn collectSupport(allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: @import("domain/specification_provenance.zig").Context, bytes: []const u8) !@import("domain/required_authority.zig").Inputs {
    return switch (try collectReview(@import("domain/specification_support.zig").Source, allocator, inputs, context, bytes, null)) {
        .accepted => |accepted| accepted.inputs,
        .pending, .rejected => error.InvalidRequiredAuthority,
    };
}

fn sourceReviewWire(allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: @import("domain/specification_provenance.zig").Context, id: @import("domain/required_authority.zig").Id, value: @import("domain/specification_support.zig").Source.Value) ![]const u8 {
    const rules = @import("domain/specification_support_evidence.zig");
    return @import("domain/specification_support_model.zig").encode(allocator, value, try rules.requirements(allocator, inputs, context.inputs, id));
}

/// A member-set packet's selected schema admits exactly one item per assigned
/// member; partial, repeated and foreign responses fail response admission.
fn expectExactMembers(a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, body: []const u8, collection: []const u8, key: []const u8) !void {
    const schema = @import("domain/model_result_schema.zig");
    const check = @import("domain/model_payload_schema.zig");
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const restricted = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    const complete = try std.json.parseFromSliceLeaky(std.json.Value, a, body, .{ .parse_numbers = false });
    try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&complete), restricted.selected().root()) == null);
    try std.testing.expect(complete.object.get(collection).?.array.items.len != 0);
    for ([_]check.Rejection{ .array_length, .duplicate_member, .enum_mismatch }) |rejection| {
        var altered = try std.json.parseFromSliceLeaky(std.json.Value, a, body, .{ .parse_numbers = false });
        const items = &altered.object.getPtr(collection).?.array;
        // A single member cannot repeat within its fixed count of one.
        const expected: check.Rejection = if (rejection == .duplicate_member and items.items.len == 1) .array_length else rejection;
        switch (rejection) {
            .array_length => _ = items.pop(),
            .duplicate_member => if (items.items.len == 1) try items.append(items.items[0]) else {
                items.items[items.items.len - 1].object.getPtr(key).?.* = items.items[0].object.get(key).?;
            },
            else => items.items[0].object.getPtr(key).?.* = .{ .number_string = "2048" },
        }
        try std.testing.expectEqual(expected, check.validateValue(@import("domain/model_envelope.zig").value(&altered), restricted.selected().root()).?.reason);
    }
}

fn assignmentWire(comptime Review: type, a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, id: @import("domain/required_authority.zig").Id, complete: Review.Review) ![]const u8 {
    const authority = @import("domain/required_authority.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const selected = try Review.assignmentSubjects(a, inputs, id);
    const native = try authority.build(a, inputs);
    const WireValue = if (Review == @import("domain/specification_support.zig").Source) @import("domain/specification_support_model.zig").Value else Review.Value;
    const WireFinding = struct { requirement_ordinal: u32, value: WireValue };
    const findings = try a.alloc(WireFinding, selected.len);
    for (selected, findings) |target, *entry| {
        const index = for (native.requirements, 0..) |required, position| {
            if (std.meta.eql(required.seed.id, target)) break position;
        } else return error.InvalidRequiredAuthority;
        const value = for (complete.entries) |finding| {
            if (finding.requirement_ordinal == index + 1) break finding.value;
        } else return error.InvalidRequiredAuthority;
        entry.* = .{ .requirement_ordinal = @intCast(index + 1), .value = if (Review == @import("domain/specification_support.zig").Source) try codec.decode(WireValue, a, try sourceReviewWire(a, inputs, context, target, value)) else value };
    }
    return codec.encode(struct { findings: []const WireFinding }, a, .{ .findings = findings });
}

test "R31 structurally corrected reviews still require complete findings and entity claim evidence" {
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited);
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, bytes);
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 3 } };
    for ([_][]const u8{ "Display `MOCK Hello, World!` and the current UTC date and time.", "Display `MOCK Loan renewed!` and label the deadline `Return by`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const ledger = try @import("domain/required_authority.zig").build(a, inputs);
        const entity = for (ledger.requirements, 0..) |requirement, index| {
            if (requirement.seed.id.kind == .entity_applicability) break index;
        } else return error.MissingEntityRequirement;
        const packet = try support.packetFor(a, inputs, fixture.context, .{ .finding = ledger.requirements[entity].seed.id });
        defer @import("domain/model_input_packet.zig").release(packet);
        const selected = schema.select(packet.resultDefinition().?).?;
        try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = try sourceReviewWire(a, inputs, fixture.context, ledger.requirements[entity].seed.id, good.entries[entity].value) });
        for (0..3) |scenario| {
            const findings = try a.dupe(support.Finding, if (scenario == 1) good.entries[0..1] else good.entries);
            if (scenario == 2) {
                findings[entity].value.kind = .supported;
                findings[entity].value.detail = "No business data entity is needed.";
                findings[entity].value.provenance.claim_ids = &.{};
            }
            const corrected = try json.encode(support.Review, a, .{ .entries = findings });
            if (scenario == 2) try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = try sourceReviewWire(a, inputs, fixture.context, ledger.requirements[entity].seed.id, findings[entity].value) });
            // Native admission independently retains the same rejection. Production
            // corrects the complete response before it reaches this collector.
            const result = try collectReview(support, a, inputs, fixture.context, corrected, origin);
            if (scenario == 0) {
                try std.testing.expectEqualDeep(good.entries, result.accepted.candidate.review.entries);
                for (result.accepted.candidate.origins) |retained| try std.testing.expectEqualDeep(origin, retained.?);
                try support.validateStored(a, result.accepted.inputs, fixture.context.inputs);
            } else if (scenario == 1) {
                try std.testing.expectEqual(good.entries.len - 1, result.rejected.rejection.diagnostics.len);
                for (result.rejected.rejection.diagnostics) |issue| try std.testing.expectEqual(.missing_finding, issue.issue);
                try std.testing.expectEqualDeep(good.entries[0..1], result.rejected.candidate.?.review.entries);
            } else {
                try std.testing.expectEqual(@as(usize, 1), result.rejected.rejection.diagnostics.len);
                try std.testing.expectEqual(.missing_claims, result.rejected.rejection.selected().?.evidence.?.issue);
                try std.testing.expectEqualDeep(good.entries[0..entity], result.rejected.candidate.?.review.entries[0..entity]);
                try std.testing.expectEqualDeep(good.entries[entity + 1 ..], result.rejected.candidate.?.review.entries[entity + 1 ..]);
            }
        }
    }
}

test "review decisions retain seven source-gap assessments as advice and reject forbidden applicability" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "On startup display `MOCK Hello, World!` and the current UTC date and time.", "After renewal display `MOCK Loan renewed!` and the new return deadline." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const current = try completedFixture(&fixture, false);
        const content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, current)).content;
        {
            const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, content, current.units[0].?.response.content.brief);
            const ledger = try authority.build(a, inputs);
            const good = try reviewFor(a, inputs, fixture.context.inputs);
            const findings = try a.dupe(support.Finding, good.entries);
            var gaps: usize = 0;
            for (ledger.requirements, findings) |requirement, *finding| {
                if (requirement.seed.id.kind != .feature_intent or requirement.seed.id.unit != .feature) continue;
                const bound = finding.value.provenance;
                finding.value = .{ .kind = .unsupported, .question = "What behavior is required? State the triggering event and expected result.", .provenance = bound, .source_ids = &.{}, .detail = "The source leaves this decision unspecified." };
                gaps += 1;
            }
            try std.testing.expectEqual(@as(usize, 7), gaps);
            const collected = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
            try std.testing.expectEqualDeep(findings, collected.candidate.review.entries);
            const resolved = try supportDecision(a, collected.inputs);
            try std.testing.expectEqual(.all_resolved, resolved.result.continuation);
            for (resolved.result.entries) |entry| try std.testing.expect(entry.outcome == .assessment_complete);
            try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, collected.inputs, resolved.observations, resolved.result));
            try support.validateStored(a, collected.inputs, fixture.context.inputs);
            for (ledger.requirements, 0..) |requirement, index| {
                if (requirement.seed.id.kind == .entity_applicability) continue;
                // Includes feature fields, records, signals and preserved tokens.
                const forbidden = try a.dupe(support.Finding, good.entries);
                forbidden[index].value.kind = .not_applicable;
                const rejected = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = forbidden }), null)).rejected;
                try std.testing.expectEqual(.invalid_decision, rejected.rejection.selected().?.issue);
                try std.testing.expectEqualDeep(requirement.seed.id, rejected.rejection.selected().?.requirement.?);
                try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, rejected));
            }
            const old = "{\"entries\":[{\"requirement_ordinal\":1,\"value\":{\"finding\":\"unsupported\",\"disposition\":\"not_applicable\",\"provenance\":{\"claim_ids\":[],\"clarification_response_ids\":[]},\"source_ids\":[],\"detail\":\"No explicit field.\"}}]}";
            try std.testing.expectError(error.InvalidJsonDocument, collectReview(support, a, inputs, fixture.context, old, null));
        }
    }
}

test "entity applicability shares native policy across initial inserted and persisted reviews" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower receives a renewal receipt.");
    defer fixture.deinit();
    const current = try completedFixture(&fixture, false);
    const content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, current)).content;
    for ([_]usize{ 2, 3 }) |mode| {
        var candidate = content;
        if (mode == 3) candidate.entities.disposition = .required;
        const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, candidate, current.units[0].?.response.content.brief);
        const ledger = try authority.build(a, inputs);
        const entity = for (ledger.requirements, 0..) |requirement, index| {
            if (requirement.seed.id.kind == .entity_applicability) break index;
        } else return error.MissingEntityRequirement;
        for (ledger.requirements, 0..) |_, index| {
            const packet = try reviewPacketAt(support, a, inputs, fixture.context, index);
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try std.testing.expectEqual(@as(usize, 1), body.get("requirements").?.array.items.len);
            const requirement = body.get("requirements").?.array.items[0];
            if (index == entity) {
                try std.testing.expectEqualStrings("finding", packet.resultDefinition().?.bytes);
                const task = requirement.object.get("task").?.string;
                try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, ledger.requirements[entity].seed.id), task);
                const subject = body.get("subject").?.object;
                try std.testing.expectEqualStrings("entity_applicability", subject.get("kind").?.string);
                try expectBusinessReviewPurpose(.source, a, inputs, fixture.context, packet, ledger.requirements[entity].seed.id);
            }
            const allowed = requirement.object.get("permitted_not_applicable");
            try std.testing.expect(allowed == null);
        }
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const findings = try a.dupe(support.Finding, good.entries);
        const accepted = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
        try std.testing.expectEqual(.supported, accepted.inputs.evidence[entity].finding);
        try std.testing.expectEqual(mode != 3, accepted.inputs.evidence[entity].resolution.assessment.not_applicable != null);
        try support.validateStored(a, accepted.inputs, fixture.context.inputs);
        var tampered = accepted.inputs;
        const proofs = try a.dupe(authority.Evidence, tampered.evidence);
        proofs[entity].resolution = if (mode == 3) .{ .not_applicable = .no_business_data } else .{ .supported_candidate = .{ .ordinal = @intCast(entity + 1), .revision = inputs.revision } };
        tampered.evidence = proofs;
        try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, tampered, fixture.context.inputs));
        // Missing mandatory and entity findings share insertion and full validation.
        for ([_]usize{ 0, entity }) |index| {
            var missing: std.ArrayList(support.Finding) = .empty;
            for (findings, 0..) |finding, ordinal| if (ordinal != index) try missing.append(a, finding);
            const rejected = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = missing.items }), null)).rejected;
            const authorization = try repair.authorize(a, inputs, fixture.context, rejected);
            const request = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, authorization);
            defer packets.release(request);
            try std.testing.expectEqualStrings("finding", request.resultDefinition().?.bytes);
            const request_body = (try std.json.parseFromSlice(std.json.Value, a, request.body(), .{})).value.object;
            const selected_task = request_body.get("input").?.object.get("requirements").?.array.items[0].object;
            const original_packet = try reviewPacketAt(support, a, inputs, fixture.context, index);
            defer packets.release(original_packet);
            const original_body = (try std.json.parseFromSlice(std.json.Value, a, original_packet.body(), .{})).value.object;
            try std.testing.expectEqualStrings(original_body.get("requirements").?.array.items[0].object.get("task").?.string, selected_task.get("task").?.string);
            const task_evidence = request_body.get("input").?.object.get("requirements").?.array.items[0].object.get("evidence").?.object;
            try std.testing.expect(task_evidence.get("eligible_claim_ids").?.array.items.len > 0);
            const replacement = try repair.parse(a, authorization, request, try sourceReviewWire(a, inputs, fixture.context, authorization.target.requirement, findings[index].value));
            var empty_evidence = replacement;
            empty_evidence.finding.provenance.claim_ids = &.{};
            const invalid_evidence = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, authorization, empty_evidence, null)).rejected;
            try std.testing.expectEqual(.missing_claims, invalid_evidence.rejection.selected().?.evidence.?.issue);
            try std.testing.expectEqualDeep(missing.items, invalid_evidence.candidate.?.review.entries[0..missing.items.len]);
            const merged = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, authorization, replacement, null)).accepted;
            try std.testing.expectEqualDeep(accepted.inputs.evidence, merged.inputs.evidence);
            try std.testing.expectEqualDeep(missing.items, merged.candidate.review.entries[0..missing.items.len]);
            try support.validateStored(a, merged.inputs, fixture.context.inputs);
            // The merge still rejects a forbidden decision, even after decoding.
            {
                var invalid = replacement;
                invalid.finding.kind = .not_applicable;
                const invalid_merge = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, authorization, invalid, null)).rejected;
                try std.testing.expectEqual(.invalid_decision, invalid_merge.rejection.selected().?.issue);
                try std.testing.expectEqualDeep(missing.items, invalid_merge.candidate.?.review.entries[0..missing.items.len]);
            }
            {
                var changed = inputs;
                changed.specification.?.entities.disposition = if (mode == 2) .required else .not_applicable;
                try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, changed, fixture.context, rejected.candidate.?, authorization));
                try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), changed, fixture.context, rejected.candidate.?, authorization, replacement, null));
            }
        }
        findings[entity].value.kind = .unsupported;
        findings[entity].value.question = "Which deadline should apply? State the duration and starting event.";
        findings[entity].value.detail = "The source does not establish the entity basis.";
        const negative = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
        try std.testing.expectEqual(.unsupported, negative.evidence[entity].finding);
        try std.testing.expectEqual(mode == 2, negative.evidence[entity].resolution.assessment.not_applicable != null);
        try std.testing.expectEqual(.all_resolved, (try supportDecision(a, negative)).result.continuation);
        try support.validateStored(a, negative, fixture.context.inputs);
        {
            findings[entity].value.kind = .not_applicable;
            try std.testing.expectEqual(.invalid_decision, (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected.rejection.selected().?.issue);
        }
    }
}

test "review evidence repairs expose both defects without changing semantic findings" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "On startup display `MOCK Hello, World!` and the current UTC date and time.", "After renewal display `MOCK Loan renewed!` and the new return deadline." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const ledger = try authority.build(a, inputs);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const findings = try a.dupe(support.Finding, good.entries);
        var entity: ?usize = null;
        var token: ?usize = null;
        var negatives: usize = 0;
        for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
            if (requirement.seed.id.kind == .entity_applicability) {
                entity = index;
                finding.value.kind = .supported;
                finding.value.provenance.claim_ids = &.{};
            } else if (requirement.seed.id.unit == .token) {
                token = index;
                finding.value.provenance = good.entries[0].value.provenance;
            } else {
                finding.value.kind = .unsupported;
                finding.value.question = "Which deadline should apply? State the duration and starting event.";
                const required = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, requirement.seed.id);
                finding.value.provenance.claim_ids = required.rule(.unsupported, .{ .unlocalized = .{} }).fixedClaims() orelse &.{};
                finding.value.detail = "The source does not settle this requirement.";
                negatives += 1;
            }
            finding.value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
        }
        const first = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
        try std.testing.expectEqual(.invalid_evidence, first.rejection.selected().?.issue);
        try std.testing.expectEqual(.missing_claims, first.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqual(entity.? + 1, first.rejection.selected().?.ordinal.?);
        try std.testing.expectEqual(.claim_required, first.rejection.selected().?.evidence.?.rule.minimum);
        try std.testing.expectEqual(@as(usize, 2), first.rejection.diagnostics.len);
        try std.testing.expectEqual(token.? + 1, first.rejection.diagnostics[1].ordinal.?);
        try std.testing.expectEqual(.ineligible_claim, first.rejection.diagnostics[1].evidence.?.issue);
        const authorization = try repair.authorize(a, inputs, fixture.context, first);
        const packet = try repair.packet(a, inputs, fixture.context, first.candidate.?, authorization);
        defer packets.release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        const rule = body.get("repair").?.object.get("rule").?.object;
        const scoped_input = body.get("input").?.object;
        try std.testing.expect(!scoped_input.contains("evidence_rules"));
        try std.testing.expect(!scoped_input.get("requirements").?.array.items[0].object.contains("evidence"));
        try std.testing.expectEqualStrings("missing_claims", rule.get("evidence_issue").?.string);
        try std.testing.expectEqualStrings("claim_required", rule.get("evidence_rule").?.object.get("minimum").?.string);
        // An unchanged replacement consumes a merge but cannot satisfy admission.
        const unchanged = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, first.candidate.?, authorization, authorization.operation.replace, corrected)).rejected;
        try std.testing.expectEqual(.missing_claims, unchanged.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqual(@as(usize, 2), unchanged.rejection.diagnostics.len);
        try std.testing.expect(!unchanged.candidate.?.last_repair.?.changed);
        try std.testing.expectEqual(@as(u64, 2), unchanged.candidate.?.revision);
        try std.testing.expectEqualDeep(findings, unchanged.candidate.?.review.entries);
        const entity_replacement: repair.Replacement = .{ .selection = .{ .provenance = good.entries[entity.?].value.provenance, .source_ids = findings[entity.?].value.source_ids } };
        const second = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, first.candidate.?, authorization, entity_replacement, corrected)).rejected;
        try std.testing.expectEqual(.ineligible_claim, second.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqual(@as(usize, 1), second.rejection.diagnostics.len);
        try std.testing.expectEqual(token.? + 1, second.rejection.selected().?.ordinal.?);
        try std.testing.expectEqualDeep(original, second.rejection.selected().?.origin.?);
        try std.testing.expectEqualDeep(corrected, second.candidate.?.origins[entity.?].?);
        try std.testing.expectEqual(.supported, second.candidate.?.review.entries[entity.?].value.kind);
        for (findings, second.candidate.?.review.entries, 0..) |before, after, index| if (index != entity.?) try std.testing.expectEqualDeep(before, after);
        const token_authorization = try repair.authorize(a, inputs, fixture.context, second);
        const token_rule = second.rejection.selected().?.evidence.?.rule;
        try std.testing.expect(token_rule.claims == .exact);
        try std.testing.expectEqualDeep(good.entries[token.?].value.provenance.claim_ids, token_rule.claims.exact);
        const token_replacement: repair.Replacement = .{ .selection = .{ .provenance = good.entries[token.?].value.provenance, .source_ids = findings[token.?].value.source_ids } };
        const completed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, second.candidate.?, token_authorization, token_replacement, corrected)).accepted;
        try std.testing.expectEqual(@as(u64, 3), completed.candidate.revision);
        for (findings, completed.candidate.review.entries, 0..) |before, after, index| if (index != entity.? and index != token.?) try std.testing.expectEqualDeep(before, after);
        const resolved = try supportDecision(a, completed.inputs);
        try std.testing.expectEqual(.all_resolved, resolved.result.continuation);
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, completed.inputs, resolved.observations, resolved.result));
        var retained_negatives: usize = 0;
        for (completed.inputs.evidence) |finding| if (finding.finding == .unsupported) {
            retained_negatives += 1;
        };
        try std.testing.expectEqual(negatives, retained_negatives);
        try support.validateStored(a, completed.inputs, fixture.context.inputs);
        for ([_]usize{ entity.?, token.? }) |index| {
            var corrupted = completed.inputs;
            const entries = try a.dupe(authority.Evidence, corrupted.evidence);
            entries[index].review.?.provenance.claim_ids = findings[index].value.provenance.claim_ids;
            corrupted.evidence = entries;
            try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, corrupted, fixture.context.inputs));
        }
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, completed.candidate, token_authorization, token_replacement, corrected));
    }
}

test "source review retains candidate-loss and gap judgments as advice without native semantic verdicts" {
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    const clarification = @import("domain/required_authority_clarifications.zig");
    const cases = [_]struct { complete: []const u8, incomplete: []const u8, partial: []const u8, question: []const u8 }{
        .{ .complete = "On startup display a greeting and the current UTC date and time.", .incomplete = "On startup display a greeting and time; its timezone is undecided.", .partial = "On startup display a greeting.", .question = "Which timezone should be shown?" },
        .{ .complete = "A borrower renews a loan for fourteen days and sees the new deadline.", .incomplete = "A borrower renews a loan; the renewal period is undecided.", .partial = "A borrower renews a loan.", .question = "How long is the renewal period?" },
    };
    const Mode = enum { supported, genuine_gap, lost_meaning, inconclusive, mistaken_gap };
    for (cases) |case| for (std.meta.tags(Mode)) |mode| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const source = if (mode == .genuine_gap) case.incomplete else case.complete;
        var fixture = try Fixture.initContent(a, source, .business_exact_string, true, if (mode == .lost_meaning) case.partial else source, 1);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const ledger = try @import("domain/required_authority.zig").build(a, inputs);
        const target = for (ledger.requirements, 0..) |requirement, index| {
            if (requirement.seed.id.slot == .acceptance_criteria) break index;
        } else return error.MissingRequirement;
        const signal = for (ledger.requirements, 0..) |requirement, index| {
            if (requirement.seed.id.unit == .signal) break index;
        } else return error.MissingRequirement;
        const packet = try reviewPacketAt(support, a, inputs, fixture.context, target);
        defer packets.release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        try std.testing.expectEqualStrings(source, body.get("sources").?.array.items[0].object.get("text").?.string);
        try std.testing.expectEqualStrings(@import("domain/required_authority_description.zig").recordFamily(.acceptance_criterion), body.get("requirements").?.array.items[0].object.get("task").?.string);
        const signal_packet = try reviewPacketAt(support, a, inputs, fixture.context, signal);
        defer packets.release(signal_packet);
        const signal_body = (try std.json.parseFromSlice(std.json.Value, a, signal_packet.body(), .{})).value.object;
        try std.testing.expectEqualStrings("Source meaning preserved by signal 1.", signal_body.get("requirements").?.array.items[0].object.get("task").?.string);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const findings = try a.dupe(support.Finding, good.entries);
        if (mode != .supported) findings[target].value = .{
            .kind = switch (mode) {
                .genuine_gap => .ambiguous,
                .lost_meaning => .candidate_omission,
                .inconclusive => .inconclusive,
                .mistaken_gap => .unsupported,
                .supported => unreachable,
            },
            .missing_obligation = if (mode == .lost_meaning) case.complete else null,
            .question = if (mode == .genuine_gap or mode == .mistaken_gap) case.question else null,
            .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} },
            .source_ids = &.{fixture.context.inputs.corpus.sources[0].id},
            .detail = switch (mode) {
                .genuine_gap, .mistaken_gap => "The source leaves the timing decision unresolved; it determines the observable result.",
                .lost_meaning => "The source supplies the timing requirement, but the extracted claim omits it.",
                .inconclusive => "The source supplies a timing requirement, but I could not interpret it; no missing user decision was established.",
                .supported => unreachable,
            },
        };
        try bindReviewClaims(a, inputs, fixture.context, findings);
        const collected = try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null);
        const admitted = try (@import("actions/specification/apply_specification_support.zig").Action{}).execute(collected);
        try support.validateStored(a, admitted, fixture.context.inputs);
        // Scripted responses exercise the real admission/gate path, not semantic truth.
        try std.testing.expectEqualDeep(findings, collected.accepted.candidate.review.entries);
        const decision = try supportDecision(a, admitted);
        try std.testing.expectEqual(.all_resolved, decision.result.continuation);
        try std.testing.expect(decision.result.entries[target].outcome == .assessment_complete);
        try std.testing.expect(decision.result.entries[target].candidate_defect == null);
        try std.testing.expectEqualDeep(findings[target].value.detail, admitted.evidence[target].review.?.detail);
        try std.testing.expectError(error.InvalidRequiredAuthority, clarification.build(a, fixture.context.inputs, admitted, decision.observations, decision.result));
        // Captured policy is not a completed principle assessment.
        const captured = try @import("test_fixtures/principles.zig").registry(a, "Keep business intent intact.\n");
        const progress = try @import("domain/specification_review.zig").advance(a, .{ .source = collected }, captured);
        try std.testing.expectEqual(.more, progress.outcome);
        try std.testing.expect(progress.progress.pending.source.inputs.principle_assessment == null);
    };
}

test "candidate review retains semantic roles and contradiction advice without user questions" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const clarification = @import("domain/required_authority_clarifications.zig");
    const Mode = enum { required, wrong_non_goal, wrong_prohibition, excluded, prohibited };
    const cases = [_]struct { required: []const u8, exclusion: []const u8 }{
        .{ .required = "The application must start successfully. When started it must display MOCK Hello, World! and should output date and time in UTC.", .exclusion = "Remote message delivery is outside scope." },
        .{ .required = "On startup display a greeting and the current UTC date and time.", .exclusion = "Sending telemetry is outside scope and must not occur." },
        .{ .required = "A borrower renews a loan and receives the new return deadline.", .exclusion = "Charging a renewal fee is outside scope and must not occur." },
    };
    for (cases, 0..) |case, case_index| for (std.meta.tags(Mode)) |mode| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const source = try std.fmt.allocPrint(a, "{s}\n{s}\n", .{ case.required, case.exclusion });
        var fixture = try Fixture.initContent(a, source, null, true, source, 1);
        defer fixture.deinit();
        const required = try fixture.value(case.required);
        const value = try fixture.value(if (mode == .excluded or mode == .prohibited) case.exclusion else case.required);
        const record: spec.RecordProposal = .{ .content = switch (mode) {
            .required => .{ .functional_requirement = .{ .text = value.value } },
            .wrong_non_goal, .excluded => .{ .non_goal = .{ .text = value.value } },
            .wrong_prohibition, .prohibited => .{ .prohibited_behavior = .{ .text = value.value } },
        }, .provenance = value.provenance };
        const content = (try identifiers.assign(a, .{
            .display_name = required,
            .primary_user_story = required,
            .records = &.{
                .{ .content = .{ .acceptance_criterion = .{ .given = required.value, .when = required.value, .then = required.value } }, .source_group_ids = required.source_group_ids, .provenance = required.provenance },
                .{ .content = .{ .functional_requirement = .{ .text = required.value } }, .source_group_ids = required.source_group_ids, .provenance = required.provenance },
                record,
            },
            .entities = .{ .disposition = .not_applicable, .basis = required },
        }, .{})).content;
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, content, .{ .title = required, .description = required, .primary_goal = required });
        const ledger = try authority.build(a, inputs);
        const selected = for (ledger.requirements, 0..) |requirement, index| {
            const unit = requirement.seed.id.unit;
            if (unit == .record and std.meta.eql(unit.record, content.records[2].id)) break index;
        } else return error.MissingRecordRequirement;
        const focused = try support.packetFor(a, inputs, fixture.context, .{ .finding = ledger.requirements[selected].seed.id });
        defer packets.release(focused);
        const body = (try std.json.parseFromSlice(std.json.Value, a, focused.body(), .{})).value.object;
        try std.testing.expectEqualStrings(source, body.get("sources").?.array.items[0].object.get("text").?.string);
        const subject = body.get("subject").?.object;
        try std.testing.expectEqualStrings("candidate_field", subject.get("kind").?.string);
        try std.testing.expectEqualStrings(if (mode == .excluded or mode == .prohibited) case.exclusion else case.required, subject.get("text").?.string);
        const carried = try json.decode(spec.IdentifiedRecord, a, try std.json.Stringify.valueAlloc(a, subject.get("record").?, .{}));
        try std.testing.expectEqualDeep(content.records[2], carried);
        try std.testing.expect(!subject.contains("candidate"));
        try std.testing.expectEqualStrings("finding", focused.resultDefinition().?.bytes);
        try std.testing.expectEqual(@as(usize, 1), body.get("requirements").?.array.items.len);
        // Diagnostic inputs only. No replay result is imported as workflow state.
        const path = try std.fmt.allocPrint(a, ".zig-cache/review-assignment-{d}-{s}.json", .{ case_index, @tagName(mode) });
        try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = focused.body() });
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const partial = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[selected .. selected + 1] }), null)).rejected;
        try std.testing.expectEqual(.missing_finding, partial.rejection.selected().?.issue);
        try std.testing.expectEqual(good.entries.len - 1, partial.rejection.diagnostics.len);
        const repair = @import("domain/specification_support_repair.zig").Source;
        const authorization = try repair.authorize(a, inputs, fixture.context, partial);
        const insertion = try repair.packet(a, inputs, fixture.context, partial.candidate.?, authorization);
        defer packets.release(insertion);
        const insertion_body = (try std.json.parseFromSlice(std.json.Value, a, insertion.body(), .{})).value.object;
        try std.testing.expectEqualStrings("missing_finding", insertion_body.get("repair").?.object.get("rule").?.object.get("issue").?.string);
        const assigned = try support.packetFor(a, inputs, fixture.context, .{ .finding = authorization.target.requirement });
        defer packets.release(assigned);
        const assigned_body = (try std.json.parseFromSlice(std.json.Value, a, assigned.body(), .{})).value.object;
        const insertion_input = insertion_body.get("input").?.object;
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, assigned_body.get("subject").?, .{}), try std.json.Stringify.valueAlloc(a, insertion_input.get("subject").?, .{}));
        try std.testing.expectEqual(authorization.target.ordinal, insertion_input.get("requirements").?.array.items[0].object.get("ordinal").?.integer);
        // The missing assessment can support content already in the candidate.
        // Insertion changes neither that content nor its previously reviewed sibling.
        const inserted = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, partial.candidate.?, authorization, .{ .finding = good.entries[authorization.target.ordinal - 1].value }, null)).rejected;
        try std.testing.expectEqual(good.entries.len - 2, inserted.rejection.diagnostics.len);
        try std.testing.expectEqualDeep(partial.candidate.?.review.entries[0], inserted.candidate.?.review.entries[0]);
        try std.testing.expectEqualDeep(partial.candidate.?.origins[0], inserted.candidate.?.origins[0]);
        // A structurally valid false positive is still admitted: this is not a
        // native semantic classifier or proof of live instruction effectiveness.
        const positive = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, good), null)).accepted;
        try std.testing.expectEqual(.all_resolved, (try supportDecision(a, positive.inputs)).result.continuation);
        try support.validateStored(a, positive.inputs, fixture.context.inputs);
        if (mode != .wrong_non_goal and mode != .wrong_prohibition) continue;
        for ([_]support.Decision{ .candidate_omission, .inconclusive }) |decision_kind| {
            const findings = try a.dupe(support.Finding, good.entries);
            findings[selected].value.kind = decision_kind;
            findings[selected].value.missing_obligation = if (decision_kind == .candidate_omission) fixture.context.inputs.corpus.sources[0].bytes else null;
            findings[selected].value.detail = "The candidate assigns source-required behavior to an exclusion or prohibition; no missing user decision is established.";
            findings[selected].value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
            const accepted = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
            try support.validateStored(a, accepted.inputs, fixture.context.inputs);
            const gate = try supportDecision(a, accepted.inputs);
            try std.testing.expectEqual(.all_resolved, gate.result.continuation);
            try std.testing.expect(gate.result.entries[selected].outcome == .assessment_complete);
            try std.testing.expect(gate.result.entries[selected].candidate_defect == null);
            try std.testing.expectError(error.InvalidRequiredAuthority, clarification.build(a, fixture.context.inputs, accepted.inputs, gate.observations, gate.result));
            try std.testing.expectEqualDeep(content, accepted.inputs.specification.?);
            for (good.entries, accepted.candidate.review.entries, 0..) |before, after, index| if (index != selected) try std.testing.expectEqualDeep(before, after);
            findings[selected].value.question = "Should the required behavior be excluded?";
            try std.testing.expectEqual(.forbidden_question, (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected.rejection.selected().?.issue);
        }
    };
}

test "source membership guidance remains distinct from claims through review repair and readback" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const admission = @import("domain/specification_support_evidence.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const SourceId = @import("domain/reference_identity.zig").SourceId;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const restrict = @import("domain/model_result_schema.zig").restrict;
    const check = @import("model_payload_schema_test.zig").checkDocument;
    for ([_][]const u8{ "On startup display `MOCK Hello, World!`.", "After renewal display `MOCK Loan renewed!` and label the deadline `Return by`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const allowed = try admission.sourceChoices(a, fixture.context.inputs);
        try std.testing.expectEqualDeep(&[_]SourceId{.{ .ordinal = 1 }}, allowed);
        try std.testing.expect(inputs.references.?.items.entries.len > allowed.len);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        // Claim 2 exists; source 2 does not. Their numerical overlap is not authority.
        const findings = try a.dupe(support.Finding, good.entries);
        try std.testing.expect(inputs.references.?.items.entries.len >= 2);
        findings[1].value.source_ids = &.{.{ .ordinal = 2 }};
        const rejected = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected;
        try std.testing.expectEqual(@as(usize, 1), rejected.rejection.diagnostics.len);
        const diagnostic = rejected.rejection.selected().?.evidence.?;
        try std.testing.expectEqual(.invalid_sources, diagnostic.issue);
        try std.testing.expectEqualDeep(allowed, diagnostic.rule.eligible_source_ids);
        // Reports copy the same rule; no observer reconstructs source membership.
        const report: @import("domain/candidate_validation_diagnostic.zig").Diagnostic = .{ .support = rejected.rejection };
        try std.testing.expectEqualDeep(report, try report.copy(a));
        const initial = try reviewPacketAt(support, a, inputs, fixture.context, 0);
        defer packets.release(initial);
        const missing = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[1..] }), null)).rejected;
        const insertion = try repair.packet(a, inputs, fixture.context, missing.candidate.?, try repair.authorize(a, inputs, fixture.context, missing));
        defer packets.release(insertion);
        for ([_]*const packets.Packet{ initial, insertion }) |packet| {
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            const input = if (packet == initial) body else body.get("input").?.object;
            const offered = input.get("evidence_rules").?.object.get("eligible_source_ids").?;
            try std.testing.expectEqualDeep(allowed, try json.decode([]const SourceId, a, try std.json.Stringify.valueAlloc(a, offered, .{})));
            for (input.get("requirements").?.array.items) |requirement| try std.testing.expect(!requirement.object.get("evidence").?.object.contains("eligible_source_ids"));
            const selected = try restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer selected.release();
            try check(selected.selected().modelBytes(), .{ .bytes = "{\"kind\":\"supported\",\"source_ids\":[1],\"detail\":\"MOCK source support\"}" });
            try check(selected.selected().modelBytes(), .{ .bytes = "{\"kind\":\"supported\",\"source_ids\":[2],\"detail\":\"MOCK foreign claim ID\"}", .rejection = .enum_mismatch, .path = "/source_ids/0" });
        }
        const authorization = try repair.authorize(a, inputs, fixture.context, rejected);
        const correction = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, authorization);
        defer packets.release(correction);
        const selected = try restrict(std.testing.allocator, schemas.select(correction.resultDefinition().?).?, correction.excludedVariants(), correction.integerChoices());
        defer selected.release();
        try check(selected.selected().modelBytes(), .{ .bytes = "{\"source_ids\":[1]}" });
        try check(selected.selected().modelBytes(), .{ .bytes = "{\"source_ids\":[]}" });
        try check(selected.selected().modelBytes(), .{ .bytes = "{\"source_ids\":[2]}", .rejection = .enum_mismatch, .path = "/source_ids/0" });
        const body = (try std.json.parseFromSlice(std.json.Value, a, correction.body(), .{})).value.object;
        const offered = body.get("repair").?.object.get("rule").?.object.get("evidence_rule").?.object.get("eligible_source_ids").?;
        try std.testing.expectEqualDeep(allowed, try json.decode([]const SourceId, a, try std.json.Stringify.valueAlloc(a, offered, .{})));
        try std.testing.expect(!body.get("input").?.object.contains("evidence_rules"));
        var stale = fixture.context;
        stale.inputs.corpus.state_id.bytes = "changed-corpus";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, inputs, stale, rejected.candidate.?, authorization));
        const unchanged = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, authorization, authorization.operation.replace, null)).rejected;
        try std.testing.expectEqualDeep(rejected.candidate.?.review, unchanged.candidate.?.review);
        try std.testing.expectEqual(.invalid_sources, unchanged.rejection.selected().?.evidence.?.issue);
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = findings[1].value.provenance, .source_ids = allowed } }, null)).accepted;
        for (findings, fixed.candidate.review.entries, 0..) |before, after, index| {
            if (index != 1) try std.testing.expectEqualDeep(before, after) else {
                try std.testing.expectEqualDeep(before.value.provenance, after.value.provenance);
                try std.testing.expectEqual(before.value.kind, after.value.kind);
            }
        }
        try support.validateStored(a, fixed.inputs, fixture.context.inputs);
        var corrupt = fixed.inputs;
        const proofs = try a.dupe(authority.Evidence, corrupt.evidence);
        proofs[1].review.?.source_ids = findings[1].value.source_ids;
        corrupt.evidence = proofs;
        try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, corrupt, fixture.context.inputs));
    }
}

test "readiness source-purpose positives select original sources through production wire without authored provenance" {
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const model = @import("domain/specification_support_model.zig");
    const authority = @import("domain/required_authority.zig");
    const packets = @import("domain/model_input_packet.zig");
    const codec = @import("domain/strict_json.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const positive = "{\"kind\":\"supported\",\"source_ids\":[1],\"detail\":\"The selected original source establishes this purpose before authoring.\"}";
    for ([_][]const u8{ "Display the current UTC time on startup.", "A borrower may renew an eligible loan and see the new deadline." }) |source| {
        for ([_]usize{ 0, 1, 3 }) |count| {
            var fixture = try Fixture.initContent(a, source, null, count != 0, source, @max(count, 1));
            defer fixture.deinit();
            const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
            const ledger = try authority.build(a, inputs);
            const id = ledger.requirements[0].seed.id;
            const required = try admission.requirements(a, inputs, fixture.context.inputs, id);
            try std.testing.expectEqual(.original_sources, required.positive_evidence);
            try std.testing.expectEqual(count, required.eligible_claim_ids.len);
            try std.testing.expect(!required.candidate_bound);
            const rule = required.rule(.supported, .{ .unlocalized = .{} });
            try std.testing.expectEqual(.source_required, rule.minimum);
            try std.testing.expect(rule.claims == .exact and rule.claims.exact.len == 0);
            const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, support.assignmentScope(inputs, id));
            defer packets.release(packet);
            const schema = schemas.select(packet.resultDefinition().?).?;
            try check(schema.modelBytes(), .{ .bytes = positive });
            const packet_body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try std.testing.expectEqualStrings("source_preservation", packet_body.get("subject").?.object.get("kind").?.string);
            try std.testing.expectEqualStrings("original_sources", packet_body.get("requirements").?.array.items[0].object.get("evidence").?.object.get("positive_evidence").?.string);
            try std.testing.expectEqualStrings("source_required", packet_body.get("evidence_rules").?.object.get("supported").?.string);
            const decoded = try model.decode(a, positive, required);
            try std.testing.expectEqual(@as(usize, 0), decoded.provenance.claim_ids.len);
            const original: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 701 }, .attempt = .{ .value = 1 } };
            const first = try support.collectFocused(a, inputs, fixture.context, null, packet, positive, original);
            try std.testing.expect(first == .pending);
            try std.testing.expectEqual(@as(usize, 0), first.pending.review.entries[0].value.provenance.claim_ids.len);
            const Bad = struct { wire: []const u8, issue: admission.Issue };
            for ([_]Bad{
                .{ .wire = "{\"kind\":\"supported\",\"source_ids\":[],\"detail\":\"\"}", .issue = .missing_evidence },
                .{ .wire = "{\"kind\":\"supported\",\"source_ids\":[999],\"detail\":\"\"}", .issue = .invalid_sources },
                .{ .wire = "{\"kind\":\"supported\",\"source_ids\":[1,1],\"detail\":\"\"}", .issue = .invalid_sources },
            }) |bad| {
                // Generic wire structure permits the list; native role and
                // source identity own nonempty/exact current membership.
                try check(schema.modelBytes(), .{ .bytes = bad.wire });
                const rejected = (try support.collectFocused(a, inputs, fixture.context, null, packet, bad.wire, original)).rejected;
                try std.testing.expectEqual(bad.issue, rejected.rejection.selected().?.evidence.?.issue);
            }
            const forged_wire = "{\"kind\":\"supported\",\"source_ids\":[1],\"detail\":\"\",\"provenance\":{\"claim_ids\":[1]}}";
            try check(schema.modelBytes(), .{ .bytes = forged_wire, .rejection = .unknown_property, .path = "/provenance" });
            try std.testing.expectError(error.InvalidJsonDocument, model.decode(a, forged_wire, required));
            var stale = inputs;
            // Before authoring the reference snapshot is the current owner;
            // an unrelated candidate revision counter supplies no authority.
            stale.references.?.items.state_id.bytes = "stale-reference-state";
            try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, stale, fixture.context, null, packet, positive, original));

            // Complete every required subject through the production packet,
            // selected schema, decoder and collector, without canonical fakes.
            const good = try reviewFor(a, inputs, fixture.context.inputs);
            var collected: ?support.Collection = null;
            for (ledger.requirements, good.entries, 0..) |requirement, finding, index| {
                const current_packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, support.assignmentScope(inputs, requirement.seed.id));
                defer packets.release(current_packet);
                const wire = try sourceReviewWire(a, inputs, fixture.context, requirement.seed.id, finding.value);
                try check(schemas.select(current_packet.resultDefinition().?).?.modelBytes(), .{ .bytes = wire });
                collected = try support.collectFocused(a, inputs, fixture.context, collected, current_packet, wire, .{ .request = .{ .value = @intCast(800 + index) }, .attempt = .{ .value = 1 } });
                if (index + 1 < ledger.requirements.len) try std.testing.expect(collected.? == .pending);
            }
            const accepted = collected.?.accepted;
            try support.validateStored(a, accepted.inputs, fixture.context.inputs);
            const decision = try supportDecision(a, accepted.inputs);
            try std.testing.expectEqual(.all_resolved, decision.result.continuation);
            try std.testing.expect(accepted.inputs.specification == null and accepted.inputs.brief == null);
            try std.testing.expectEqual(@as(usize, 0), accepted.inputs.candidates.len);
            for (accepted.inputs.evidence) |proof| if (proof.requirement.unit == .feature) {
                try std.testing.expectEqual(.model_assisted, proof.method);
                try std.testing.expect(proof.resolution == .existing_authority and proof.resolution.existing_authority == .reference);
                try std.testing.expect(proof.resolution.existing_authority.reference.eql(inputs.references.?.items.state_id));
                try std.testing.expectEqual(@as(usize, 0), proof.review.?.provenance.claim_ids.len);
                try std.testing.expectEqual(@as(usize, 0), proof.review.?.provenance.citation_ids.len);
                try std.testing.expectEqual(@as(usize, 0), proof.review.?.provenance.clarification_response_ids.len);
            };
            var restored = accepted.inputs;
            restored.evidence = try codec.decode([]const authority.Evidence, a, try std.json.Stringify.valueAlloc(a, accepted.inputs.evidence, .{}), .{ .maximum_depth = 128 });
            try support.validateStored(a, restored, fixture.context.inputs);
            const Forgery = enum { claims, citations, clarification_responses, missing_sources, foreign_sources, duplicate_sources, method, resolution, registry_version, candidate_registry };
            const StoredCase = struct { forgery: Forgery, rejection: admission.Error = error.InvalidRequiredAuthority };
            for ([_]StoredCase{
                .{ .forgery = .claims },
                .{ .forgery = .citations, .rejection = error.InvalidReferenceReconciliation },
                .{ .forgery = .clarification_responses },
                .{ .forgery = .missing_sources },
                .{ .forgery = .foreign_sources },
                .{ .forgery = .duplicate_sources },
                .{ .forgery = .method },
                .{ .forgery = .resolution },
                .{ .forgery = .registry_version },
                .{ .forgery = .candidate_registry },
            }) |case| {
                var bad = restored;
                const proofs = try a.dupe(authority.Evidence, bad.evidence);
                bad.evidence = proofs;
                switch (case.forgery) {
                    .claims => proofs[0].review.?.provenance.claim_ids = &.{.{ .ordinal = 1 }},
                    .citations => proofs[0].review.?.provenance.citation_ids = &.{.{ .ordinal = 1 }},
                    .clarification_responses => proofs[0].review.?.provenance.clarification_response_ids = &.{.{ .ordinal = 1 }},
                    .missing_sources => proofs[0].review.?.source_ids = &.{},
                    .foreign_sources => proofs[0].review.?.source_ids = &.{.{ .ordinal = 999 }},
                    .duplicate_sources => proofs[0].review.?.source_ids = &.{ .{ .ordinal = 1 }, .{ .ordinal = 1 } },
                    .method => proofs[0].method = .deterministic,
                    .resolution => proofs[0].resolution = .{ .supported_candidate = .{ .ordinal = 1, .revision = 1 } },
                    .registry_version => {
                        const seeds = try a.dupe(authority.Seed, bad.seeds);
                        seeds[0].id.contract_version = 999;
                        bad.seeds = seeds;
                    },
                    .candidate_registry => bad.candidates = &.{.{ .id = .{ .ordinal = 1, .revision = 1 }, .requirement = id }},
                }
                try std.testing.expectError(case.rejection, support.validateStored(a, bad, fixture.context.inputs));
            }
            var foreign_sources = fixture.context.inputs;
            foreign_sources.corpus.state_id.bytes = "foreign-state";
            try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, accepted.inputs, foreign_sources));

            const preserved = try @import("domain/source_preservation.zig").project(a, inputs.feature, inputs.references.?, fixture.context.inputs);
            const source_id = (try authority.build(a, preserved)).requirements[0].seed.id;
            const preserved_rule = try admission.requirements(a, preserved, fixture.context.inputs, source_id);
            try std.testing.expectEqual(.bound_claims, preserved_rule.positive_evidence);
            try std.testing.expectEqual(.exact_set, preserved_rule.positive_claims);
            try std.testing.expectEqualDeep(preserved_rule.eligible_claim_ids, (try model.decode(a, positive, preserved_rule)).provenance.claim_ids);
            if (count != 0) {
                const authored = try completedFixture(&fixture, false);
                const complete_inputs = try completedSupportInputs(&fixture);
                const bound = try admission.requirements(a, complete_inputs, fixture.context.inputs, id);
                try std.testing.expectEqual(.bound_claims, bound.positive_evidence);
                try std.testing.expectEqualDeep(bound.supported_provenance.?.claim_ids, (try model.decode(a, positive, bound)).provenance.claim_ids);
                try std.testing.expect((try admission.admit(a, complete_inputs, fixture.context.inputs, id, .supported, .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, &.{.{ .ordinal = 1 }}, "", null, .{ .unlocalized = .{} }, null, null)) == .rejected);
                var partial = inputs;
                partial.brief = authored.units[0].?.response.content.brief;
                try std.testing.expectEqual(.bound_claims, (try admission.requirements(a, partial, fixture.context.inputs, id)).positive_evidence);
                const absent_other_field: authority.Id = .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .primary_user_story };
                const other = try admission.requirements(a, partial, fixture.context.inputs, absent_other_field);
                try std.testing.expectEqual(.bound_claims, other.positive_evidence);
                try std.testing.expectError(error.InvalidJsonDocument, model.decode(a, positive, other));
                try std.testing.expectError(error.InvalidRequiredAuthority, authority.build(a, partial));
                var false_postgen = inputs;
                false_postgen.projection = .specification;
                const absent = try admission.requirements(a, false_postgen, fixture.context.inputs, id);
                try std.testing.expectEqual(.bound_claims, absent.positive_evidence);
                try std.testing.expectError(error.InvalidJsonDocument, model.decode(a, positive, absent));
                try std.testing.expectError(error.InvalidRequiredAuthority, authority.build(a, false_postgen));
            }
        }
    }
}

test "review evidence rules preserve minima exact sets and candidate provenance across subjects" {
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const authority = @import("domain/required_authority.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower receives `MOCK Loan renewed!`.");
    defer fixture.deinit();
    const current = try completedFixture(&fixture, false);
    const content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, current)).content;
    {
        const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, content, current.units[0].?.response.content.brief);
        const ledger = try authority.build(a, inputs);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const sources = &.{fixture.context.inputs.corpus.sources[0].id};
        const empty: spec.Selection = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} };
        for (ledger.requirements, good.entries) |requirement, finding| {
            const id = requirement.seed.id;
            const expected = try admission.requirements(a, inputs, fixture.context.inputs, id);
            try std.testing.expectEqualDeep(sources, expected.eligible_source_ids);
            try std.testing.expectEqualDeep(expected.rule(.supported, .{ .unlocalized = .{} }), (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, empty, sources, "", null, .{ .unlocalized = .{} }, null, null)).rejected.rule);
            try std.testing.expectEqual(.missing_claims, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, empty, sources, "", null, .{ .unlocalized = .{} }, null, null)).rejected.issue);
            try std.testing.expectEqual(.missing_evidence, (try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, empty, &.{}, "The source requirement was lost.", "MOCK After renewal display the new return deadline.", .{ .unlocalized = .{} }, null, null)).rejected.issue);
            const omission = try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, empty, sources, "The source requirement was lost.", "MOCK After renewal display the new return deadline.", .{ .unlocalized = .{} }, null, null);
            if (expected.positive_claims == .exact_set) try std.testing.expectEqual(.wrong_claim_set, omission.rejected.issue) else if (expected.candidate_bound) try std.testing.expectEqual(.wrong_candidate_provenance, omission.rejected.issue) else try std.testing.expect(omission == .accepted);
            const unsupported = try admission.admit(a, inputs, fixture.context.inputs, id, .unsupported, empty, &.{}, "The source does not settle this requirement.", null, .{ .unlocalized = .{} }, null, null);
            if (expected.positive_claims == .exact_set) try std.testing.expectEqual(.wrong_claim_set, unsupported.rejected.issue) else if (expected.candidate_bound) try std.testing.expectEqual(.wrong_candidate_provenance, unsupported.rejected.issue) else try std.testing.expect(unsupported == .accepted);
            try std.testing.expectEqual(.invalid_sources, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, finding.value.provenance, &.{.{ .ordinal = 999 }}, "", null, .{ .unlocalized = .{} }, null, null)).rejected.issue);
            try std.testing.expectEqual(.invalid_sources, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, finding.value.provenance, &.{ sources[0], sources[0] }, "", null, .{ .unlocalized = .{} }, null, null)).rejected.issue);
            var invalid = finding.value.provenance;
            invalid.claim_ids = try std.mem.concat(a, references.r.ClaimId, &.{ invalid.claim_ids, invalid.claim_ids });
            try std.testing.expectEqual(.invalid_selection, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, invalid, &.{}, "", null, .{ .unlocalized = .{} }, null, null)).rejected.issue);
            invalid = finding.value.provenance;
            invalid.clarification_response_ids = &.{.{ .ordinal = 1 }};
            try std.testing.expectEqual(.invalid_selection, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, invalid, &.{}, "", null, .{ .unlocalized = .{} }, null, null)).rejected.issue);
            if (expected.supported_provenance != null) {
                invalid = .{ .claim_ids = expected.eligible_claim_ids, .clarification_response_ids = &.{} };
                try std.testing.expectEqual(.wrong_candidate_provenance, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, invalid, &.{}, "", null, .{ .unlocalized = .{} }, null, null)).rejected.issue);
            }
        }
        const accepted = try collectSupport(a, inputs, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, good));
        try support.validateStored(a, accepted, fixture.context.inputs);
    }
}

test "multiple original sources retain complete evidence while source-specific schemas bind exact eligibility" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const schema = @import("domain/model_result_schema.zig");
    const json = @import("domain/model_candidate_json.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    for ([_][2][]const u8{
        .{ "MOCK Start the application.\n", "MOCK Show UTC time.\n" },
        .{ "MOCK Renew the loan.\n", "MOCK Show the return deadline.\n" },
    }) |sources| {
        const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &sources);
        defer fixture.deinit();
        const global = try references.summaries(a, try references.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        const accounted = (try references.finish(a, global, try references.global(a, global), fixture.context())).valid;
        const context: provenance.Context = .{ .inputs = fixture.inputs, .references = accounted, .registry = fixture.text.registry, .current = fixture.context().current };
        const inputs = try @import("domain/source_preservation.zig").project(a, fixture.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(accounted), fixture.inputs);
        for (inputs.seeds, 0..) |seed, index| {
            const packet = try support.packetFor(std.testing.allocator, inputs, context, .{ .finding = seed.id });
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try std.testing.expectEqual(@as(usize, 2), body.get("sources").?.array.items.len);
            const restricted = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer restricted.release();
            const good = try std.fmt.allocPrint(a, "{{\"kind\":\"supported\",\"source_ids\":[{d}],\"detail\":\"MOCK preserved source meaning\"}}", .{seed.id.unit.source.ordinal});
            const other = try std.fmt.allocPrint(a, "{{\"kind\":\"supported\",\"source_ids\":[{d}],\"detail\":\"MOCK wrong source scope\"}}", .{inputs.seeds[1 - index].id.unit.source.ordinal});
            try check(restricted.selected().modelBytes(), .{ .bytes = good });
            try check(restricted.selected().modelBytes(), .{ .bytes = other, .rejection = .enum_mismatch, .path = "/source_ids/0" });
        }
        const good = try reviewFor(a, inputs, fixture.inputs);
        const findings = try a.dupe(support.Finding, good.entries);
        findings[0].value.source_ids = &.{fixture.inputs.corpus.sources[1].id};
        const rejected = (try collectReview(support, a, inputs, context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected;
        const authorization = try repair.authorize(a, inputs, context, rejected);
        const packet = try repair.packet(a, inputs, context, rejected.candidate.?, authorization);
        defer packets.release(packet);
        const restricted = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer restricted.release();
        try check(restricted.selected().modelBytes(), .{ .bytes = "{\"source_ids\":[1]}" });
        try check(restricted.selected().modelBytes(), .{ .bytes = "{\"source_ids\":[2]}", .rejection = .enum_mismatch, .path = "/source_ids/0" });
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = good.entries[0].value.provenance, .source_ids = &.{fixture.inputs.corpus.sources[0].id} } }, null)).accepted;
        try std.testing.expectEqualDeep(good.entries[1], fixed.candidate.review.entries[1]);
        try support.validateStored(a, fixed.inputs, fixture.inputs);
    }
}

fn reviewFor(a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, sources: @import("domain/reference_evidence.zig").Inputs) !@import("domain/specification_support.zig").Source.Review {
    const support = @import("domain/specification_support.zig").Source;
    const ledger = try @import("domain/required_authority.zig").build(a, inputs);
    const findings = try a.alloc(support.Finding, ledger.requirements.len);
    for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
        const required = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, sources, requirement.seed.id);
        const choices = required.eligible_claim_ids;
        const bound = required.supported_provenance;
        const claims = required.rule(.supported, .{ .unlocalized = .{} }).fixedClaims() orelse choices[0..@min(choices.len, 1)];
        const unbound = required.positive_evidence == .bound_claims and requirement.seed.id.unit == .feature and inputs.references.?.signals.len != 0 and claims.len != 0 and bound == null;
        const conflict_gap = unbound and inputs.references.?.conflicts.len != 0;
        finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .kind = if (conflict_gap) .unsupported else if (unbound) .inconclusive else .supported, .provenance = .{ .claim_ids = if (unbound) &.{} else claims, .clarification_response_ids = &.{} }, .source_ids = if (requirement.seed.id.unit == .source or required.positive_evidence == .original_sources) required.eligible_source_ids else &.{}, .detail = if (conflict_gap) "The conflicting source requirements leave this behavior unsettled." else if (unbound) "No retained source group binds this required meaning." else "", .question = if (conflict_gap) "Which source requirement governs this behavior? Choose one and state the required behavior." else null } };
    }
    return .{ .entries = findings };
}

fn bindReviewClaims(allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, entries: []@import("domain/specification_support.zig").Source.Finding) !void {
    const ledger = try @import("domain/required_authority.zig").build(allocator, inputs);
    const rules = @import("domain/specification_support_evidence.zig");
    for (entries, ledger.requirements) |*entry, requirement| {
        const required = try rules.requirements(allocator, inputs, context.inputs, requirement.seed.id);
        if (required.rule(entry.value.kind.finding(), entry.value.loss).fixedClaims()) |claims| entry.value.provenance.claim_ids = claims;
    }
}
const AuthorityDecision = struct { inputs: @import("domain/required_authority.zig").Inputs, observations: @import("domain/required_authority.zig").Observations, result: @import("domain/required_authority.zig").Result };
fn supportDecision(a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs) !AuthorityDecision {
    const authority = @import("domain/required_authority.zig");
    const ledger = try authority.build(a, inputs);
    const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, ledger);
    return .{ .inputs = inputs, .observations = observations, .result = try authority.reconcile(a, ledger, observations) };
}

fn omissionSupport(fixture: *const Fixture, location: @import("domain/source_omission.zig").Location, obligation: []const u8) !@import("domain/source_omission.zig").Support {
    const support = @import("domain/specification_support.zig").Source;
    const a = fixture.allocator;
    const inputs = if (location == .reconciliation_signal or location == .reconciliation_conflict)
        try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null)
    else
        try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs);
    const review = try reviewFor(a, inputs, fixture.context.inputs);
    const findings = try a.dupe(support.Finding, review.entries);
    const ledger = try @import("domain/required_authority.zig").build(a, inputs);
    const selected_index = for (ledger.requirements, 0..) |requirement, index| {
        const selected = switch (location) {
            .reconciliation_signal => |id| requirement.seed.id.unit == .signal and std.meta.eql(requirement.seed.id.unit.signal, id),
            .reconciliation_conflict => |id| requirement.seed.id.unit == .conflict and std.meta.eql(requirement.seed.id.unit.conflict, id),
            else => requirement.seed.id.unit == .source and requirement.seed.id.unit.source.ordinal == fixture.context.inputs.corpus.sources[0].id.ordinal,
        };
        if (selected) break index;
    } else return error.InvalidOmissionFixture;
    findings[selected_index].value.kind = .candidate_omission;
    findings[selected_index].value.missing_obligation = obligation;
    findings[selected_index].value.detail = "MOCK Preserve the source-required obligation.";
    findings[selected_index].value.question = null;
    findings[selected_index].value.source_ids = try a.dupe(@import("domain/reference_identity.zig").SourceId, &.{fixture.context.inputs.corpus.sources[0].id});
    findings[selected_index].value.loss = location;
    findings[selected_index].value.preservation = try @import("test_fixtures/source_omission_evidence.zig").proof(a, inputs, fixture.context.inputs, findings[selected_index]);
    const required = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, ledger.requirements[selected_index].seed.id);
    findings[selected_index].value.provenance.claim_ids = required.rule(.candidate_omission, location).fixedClaims() orelse &.{};
    const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, findings.len);
    @memset(origins, .{ .request = .{ .value = 14 }, .attempt = .{ .value = 1 } });
    const candidate: support.Candidate = .{ .review = .{ .entries = findings }, .origin = origins[0], .origins = origins };
    const admitted = try support.validate(a, inputs, fixture.context.inputs, candidate);
    if (admitted != .accepted) return error.InvalidOmissionFixture;
    const decision = try supportDecision(a, admitted.accepted.inputs);
    return .{ .repair_phase = .pre_generation, .review = admitted.accepted.candidate, .inputs = decision.inputs, .observations = decision.observations, .result = decision.result };
}

test "source repair phase derives from typed optional generation facts" {
    const data = @import("domain/pipeline_data.zig");
    const values = @import("application/pipeline_values.zig");
    const owned = @import("application/specification_values.zig").storage;
    const native_spec = @import("application/specification_workflow.zig");
    const native_authority = @import("application/required_authority_workflow.zig");
    const authority_owned = @import("application/required_authority_values.zig");
    const generation_facts = @import("application/specification_generation_facts.zig");
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower may renew a loan.");
    defer fixture.deinit();
    var inputs: data.View = .{};
    try std.testing.expectEqual(.pre_generation, (try generation_facts.read(&inputs)).phase());
    const initialized = try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context);
    const current = switch (initialized) {
        .ready => |value| value,
        .blocked => return error.InvalidOmissionFixture,
    };
    try std.testing.expectEqual(@as(usize, 0), current.completed);
    const session_value = value: {
        const owner = try owned.create(std.testing.allocator, .{});
        errdefer owned.destroy(owner);
        owner.payload = .{ .session = current };
        break :value try values.adopt(std.testing.allocator, native_spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
    };
    defer values.destroy(session_value);
    inputs.slots[@intFromEnum(native_spec.session_schema.key)] = session_value;
    // Merely starting generation consumes source authority; no completed unit
    // or generated content is needed for the native repair prohibition.
    try std.testing.expectEqual(.generation_started, (try generation_facts.read(&inputs)).phase());
    inputs = .{};
    const completed = try completedFixture(&fixture, false);
    const content = (try sessions.assemble(a, text.validator, fixture.context, completed)).content;
    const content_value = value: {
        const owner = try authority_owned.create(std.testing.allocator, .{});
        errdefer authority_owned.destroy(owner);
        owner.payload = .{ .content = content };
        break :value try values.adopt(std.testing.allocator, native_authority.content_schema, authority_owned.Value, authority_owned.Owner, owner, authority_owned.view, authority_owned.destroy, null);
    };
    defer values.destroy(content_value);
    inputs.slots[@intFromEnum(native_authority.content_schema.key)] = content_value;
    try std.testing.expectEqual(.generation_started, (try generation_facts.read(&inputs)).phase());
    inputs.slots[@intFromEnum(native_spec.session_schema.key)] = session_value;
    try std.testing.expectEqual(.generation_started, (try generation_facts.read(&inputs)).phase());
    const rejected_session = value: {
        const owner = try owned.create(std.testing.allocator, .{});
        errdefer owned.destroy(owner);
        break :value try values.adopt(std.testing.allocator, native_spec.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
    };
    defer values.destroy(rejected_session);
    inputs = .{};
    inputs.slots[@intFromEnum(native_spec.session_schema.key)] = rejected_session;
    try std.testing.expectError(error.InvalidCandidatePayload, generation_facts.read(&inputs));
    const rejected_content = value: {
        const owner = try authority_owned.create(std.testing.allocator, .{});
        errdefer authority_owned.destroy(owner);
        break :value try values.adopt(std.testing.allocator, native_authority.content_schema, authority_owned.Value, authority_owned.Owner, owner, authority_owned.view, authority_owned.destroy, null);
    };
    defer values.destroy(rejected_content);
    inputs = .{};
    inputs.slots[@intFromEnum(native_authority.content_schema.key)] = rejected_content;
    try std.testing.expectError(error.InvalidRequiredAuthority, generation_facts.read(&inputs));
    const wrong_schema = values.schema(.specification_generation_session, u8, 1, 16);
    const wrong_value = try values.create(std.testing.allocator, wrong_schema, u8, 1);
    defer values.destroy(wrong_value);
    inputs = .{};
    inputs.slots[@intFromEnum(native_spec.session_schema.key)] = wrong_value;
    try std.testing.expectError(error.DataSchemaMismatch, generation_facts.read(&inputs));
}

test "registered authority projections cannot restore required semantic review after generation starts" {
    const data = @import("domain/pipeline_data.zig");
    const values = @import("application/pipeline_values.zig");
    const native = @import("application/required_authority_workflow.zig");
    const authority_owned = @import("application/required_authority_values.zig");
    const specification_owned = @import("application/specification_values.zig").storage;
    const reference_owned = @import("domain/reference_candidate_value.zig");
    const feature = @import("application/feature_directory_workflow.zig");
    const sources = @import("application/reference_evidence_workflow.zig");
    const accounted = @import("application/reference_reconciliation_workflow.zig").accounted_schema;
    const native_spec = @import("application/specification_workflow.zig");
    const publication = @import("application/specification_publication_workflow.zig");
    const passive_schema = @import("application/passive_literal_workflow.zig").registry_schema;
    const toolchain_schema = @import("application/toolchain_workflow_values.zig").valid;
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display the current UTC time.", "A borrower may renew an eligible loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        var transferred = false;
        defer if (!transferred) fixture.deinit();
        const toolchain = try values.adopt(std.testing.allocator, toolchain_schema, text.safety.ValidToolchain, text.safety.Owner, fixture.passive.owner, text.safety.value, text.safety.deinitOwner, text.safety.retainedBytes(fixture.passive.owner));
        transferred = true;
        defer values.destroy(toolchain);
        const passive = try values.create(std.testing.allocator, passive_schema, @import("domain/passive_literals.zig").Registry, fixture.context.registry);
        defer values.destroy(passive);
        const prior = value: {
            const owner = try specification_owned.create(std.testing.allocator, .{});
            errdefer specification_owned.destroy(owner);
            owner.payload = .{ .prior_state = .{ .captured = null } };
            break :value try values.adopt(std.testing.allocator, publication.prior_schema, specification_owned.Value, specification_owned.Owner, owner, specification_owned.view, specification_owned.destroy, null);
        };
        defer values.destroy(prior);
        const selector = try values.create(std.testing.allocator, feature.selector, @import("domain/feature_directory.zig").Selector, .{
            .feature_id = fixture.context.inputs.corpus.feature_id,
            .project_relative_path = "specs/features/test",
        });
        defer values.destroy(selector);
        const source_value = try values.create(std.testing.allocator, sources.inputs_schema, @import("domain/reference_evidence.zig").Inputs, fixture.context.inputs);
        defer values.destroy(source_value);
        const reference_value = value: {
            const owner = try reference_owned.create(std.testing.allocator, null);
            errdefer reference_owned.destroy(owner);
            owner.payload = .{ .reconciliation_accounted = fixture.context.references };
            break :value try values.adopt(std.testing.allocator, accounted, reference_owned.Value, reference_owned.Owner, owner, reference_owned.view, reference_owned.destroy, null);
        };
        defer values.destroy(reference_value);
        var base: data.View = .{};
        base.slots[@intFromEnum(feature.selector.key)] = selector;
        base.slots[@intFromEnum(sources.inputs_schema.key)] = source_value;
        base.slots[@intFromEnum(accounted.key)] = reference_value;
        base.slots[@intFromEnum(passive_schema.key)] = passive;
        base.slots[@intFromEnum(toolchain_schema.key)] = toolchain;
        base.slots[@intFromEnum(publication.prior_schema.key)] = prior;
        try checkNativeAuthorityProjection(native.ProjectSourcePreservation, base, .source_preservation);
        try checkNativeAuthorityProjection(native.ProjectSpecification, base, .source_readiness);
        try checkNativeGenerationStart(base, true, null);

        // This is an earlier, legitimate pre-generation projection. A custom
        // graph may retire it, but cannot retire the actual generation facts.
        const old_projection = value: {
            const owner = try authority_owned.create(std.testing.allocator, base);
            errdefer authority_owned.destroy(owner);
            owner.payload = .{ .inputs = try (native.ProjectSourcePreservation.Action{}).execute(owner.arena.allocator(), fixture.context.inputs.corpus.feature_id, fixture.context.references, fixture.context.inputs) };
            break :value try values.adopt(std.testing.allocator, native.inputs_schema, authority_owned.Value, authority_owned.Owner, owner, authority_owned.view, authority_owned.destroy, null);
        };
        defer values.destroy(old_projection);
        const old_inputs = try authority_owned.read(&.{ .slots = slots: {
            var slots = data.empty_slots;
            slots[@intFromEnum(native.inputs_schema.key)] = old_projection;
            break :slots slots;
        } }, native.inputs_schema, .inputs);
        const old_decision = try supportDecision(a, old_inputs);
        // Inputs, an unfinished review, and a precomputed result each prohibit
        // consuming source authority even when the other context is absent.
        const Lingering = struct { schema: data.Schema, payload: authority_owned.Payload };
        var review_context: data.View = .{};
        defer for (review_context.slots) |slot| {
            if (slot) |value| values.destroy(value);
        };
        for ([_]Lingering{
            .{ .schema = native.inputs_schema, .payload = .{ .inputs = old_inputs } },
            .{ .schema = @import("application/specification_support_workflow.zig").schema, .payload = .{ .support = .{ .pending = .{ .review = .{ .entries = &.{} }, .origin = null, .origins = &.{} } } } },
            .{ .schema = native.ledger_schema, .payload = .{ .ledger = try @import("domain/required_authority.zig").build(a, old_inputs) } },
            .{ .schema = native.observations_schema, .payload = .{ .observations = old_decision.observations } },
            .{ .schema = native.result_schema, .payload = .{ .result = old_decision.result } },
        }) |lingering| {
            const value = value: {
                const owner = try authority_owned.create(std.testing.allocator, base);
                errdefer authority_owned.destroy(owner);
                owner.payload = lingering.payload;
                break :value try values.adopt(std.testing.allocator, lingering.schema, authority_owned.Value, authority_owned.Owner, owner, authority_owned.view, authority_owned.destroy, null);
            };
            review_context.slots[@intFromEnum(lingering.schema.key)] = value;
            var unretired = base;
            unretired.slots[@intFromEnum(lingering.schema.key)] = value;
            try checkNativeGenerationStart(unretired, false, null);
        }
        review_context.slots[@intFromEnum(native.gate_schema.key)] = try values.create(std.testing.allocator, native.gate_schema, @import("domain/workflow_gate.zig").Decision, .rejected);
        var gate_only = base;
        gate_only.slots[@intFromEnum(native.gate_schema.key)] = review_context.slots[@intFromEnum(native.gate_schema.key)];
        try checkNativeGenerationStart(gate_only, false, null);
        var unretired = base;
        for (review_context.slots, 0..) |slot, index| if (slot) |value| {
            unretired.slots[index] = value;
        };
        try checkNativeGenerationStart(unretired, false, null);
        const retired = try retireNativeReviewProjection(unretired);
        // The runner exposes the active native permit even when a source
        // parent's dependent review is suspended behind another repair family.
        const active_child: @import("domain/workflow_retry.zig").Permit = .{
            .key = .{ .scope = @splat(1), .target = @splat(2), .family = @splat(3) },
            .authorization = @splat(4),
            .revision = 1,
            .maximum_targets = 1,
        };
        try checkNativeGenerationStart(retired, false, active_child);
        try checkNativeGenerationStart(retired, true, null);
        const initialized = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const complete = try completedFixture(&fixture, false);
        const partial = try sessions.append(initialized, complete.units[0].?);
        const content = (try sessions.assemble(a, text.validator, fixture.context, complete)).content;
        const content_value = value: {
            const owner = try authority_owned.create(std.testing.allocator, .{});
            errdefer authority_owned.destroy(owner);
            owner.payload = .{ .content = content };
            break :value try values.adopt(std.testing.allocator, native.content_schema, authority_owned.Value, authority_owned.Owner, owner, authority_owned.view, authority_owned.destroy, null);
        };
        defer values.destroy(content_value);
        const Case = struct { current: ?sessions.Session, assembled: bool, specification: ?@import("domain/required_authority.zig").Projection };
        for ([_]Case{
            .{ .current = initialized, .assembled = false, .specification = null },
            .{ .current = partial, .assembled = false, .specification = null },
            .{ .current = null, .assembled = true, .specification = null },
            .{ .current = complete, .assembled = true, .specification = .specification },
        }) |case| {
            const session_value: ?*data.Value = if (case.current) |current| value: {
                const owner = try specification_owned.create(std.testing.allocator, .{});
                errdefer specification_owned.destroy(owner);
                owner.payload = .{ .session = current };
                break :value try values.adopt(std.testing.allocator, native_spec.session_schema, specification_owned.Value, specification_owned.Owner, owner, specification_owned.view, specification_owned.destroy, null);
            } else null;
            defer if (session_value) |value| values.destroy(value);
            var current = base;
            for (review_context.slots, 0..) |slot, index| if (slot) |value| {
                current.slots[index] = value;
            };
            current.slots[@intFromEnum(native_spec.session_schema.key)] = session_value;
            if (case.assembled) current.slots[@intFromEnum(native.content_schema.key)] = content_value;
            // Apply the actual registered retirement action's native delta.
            current = try retireNativeReviewProjection(current);
            try std.testing.expect(!current.contains(native.inputs_schema.key));
            try std.testing.expectEqual(session_value, current.slots[@intFromEnum(native_spec.session_schema.key)]);
            try std.testing.expectEqual(if (case.assembled) content_value else null, current.slots[@intFromEnum(native.content_schema.key)]);
            try checkNativeAuthorityProjection(native.ProjectSourcePreservation, current, null);
            try checkNativeAuthorityProjection(native.ProjectSpecification, current, case.specification);
        }
    }
}

fn retireNativeReviewProjection(current: @import("domain/pipeline_data.zig").View) !@import("domain/pipeline_data.zig").View {
    const pipeline = @import("domain/pipeline.zig");
    const native = @import("application/required_authority_workflow.zig");
    var binding: native.Retire = .{};
    const result = try native.Retire.invoke(&binding, try projectionOperationInput(native.Retire, current));
    try std.testing.expectEqual(.ok, result.outcome);
    var shape = pipeline.DataShape.init(&.{});
    for (current.slots, 0..) |slot, index| shape.available[index] = slot != null;
    // Retirement is exact: all declared targets must really be present. The
    // transition test cannot simulate optional or missing-target invalidation.
    _ = try shape.applyDelta(native.Retire.Action.contract, &result.delta);
    var next = current;
    var retired = result.delta.data_invalidations.iterator();
    while (retired.next()) |key| next.slots[@intFromEnum(key)] = null;
    return next;
}

fn projectionOperationInput(comptime T: type, current: @import("domain/pipeline_data.zig").View) !@import("ports/workflow_operation_registry.zig").Input {
    const contract = T.Action.contract;
    const compiled = struct {
        const step: @import("domain/workflow_compilation.zig").CompiledStep = .{
            .id = .{ .bytes = "projection" },
            .operation_id = .{ .bytes = contract.id },
            .parameters = &.{},
            .requires = contract.requires,
            .optional = contract.optional,
            .produces = contract.produces,
            .replaces = contract.replaces,
            .invalidates = contract.invalidates,
            .outcomes = if (@hasDecl(T, "outcomes")) &T.outcomes else &.{.ok},
            .side_effect = .none,
            .gates = &.{},
            .capabilities = &.{},
            .retry_authority = null,
        };
    };
    // Match the runner's declared-input projection: an undeclared optional
    // key would disappear here and reopen the custom-graph bypass.
    var view: @import("domain/pipeline_data.zig").View = .{};
    for (contract.requires) |key| view.slots[@intFromEnum(key)] = current.slots[@intFromEnum(key)];
    for (contract.optional) |key| view.slots[@intFromEnum(key)] = current.slots[@intFromEnum(key)];
    var shape = @import("domain/pipeline.zig").DataShape.init(&.{});
    for (view.slots, 0..) |slot, index| shape.available[index] = slot != null;
    try shape.validateInvocation(contract);
    return .{ .step = .{ .data = view, .step = &compiled.step, .resources = &.{}, .model_binding = null, .log = .init(try @import("domain/telemetry.zig").WorkflowShortcode.parse("PHSE")) } };
}

fn checkNativeAuthorityProjection(comptime T: type, view: @import("domain/pipeline_data.zig").View, expected: ?@import("domain/required_authority.zig").Projection) !void {
    const values = @import("application/pipeline_values.zig");
    const native = @import("application/required_authority_workflow.zig");
    const owned = @import("application/required_authority_values.zig");
    var binding: T = .{ .allocator = std.testing.allocator };
    const result = try T.invoke(&binding, try projectionOperationInput(T, view));
    const value = result.delta.data_writes[@intFromEnum(native.inputs_schema.key)] orelse return error.ExpectedAuthorityProjection;
    defer values.destroy(value);
    if (expected) |projection| {
        try std.testing.expectEqual(.ok, result.outcome);
        try std.testing.expect(result.diagnostic == null);
        const input = try owned.read(&.{ .slots = result.delta.data_writes }, native.inputs_schema, .inputs);
        try std.testing.expectEqual(projection, input.projection);
        const policy: @import("domain/required_authority.zig").AssessmentPolicy = if (projection == .specification) .advisory else .required;
        try std.testing.expectEqual(policy, @import("domain/required_authority.zig").assessmentPolicy(input.projection));
    } else {
        try std.testing.expectEqual(.blocked, result.outcome);
        try std.testing.expectEqual(error.InvalidRequiredAuthority, result.diagnostic.?);
        try std.testing.expectError(error.InvalidRequiredAuthority, owned.read(&.{ .slots = result.delta.data_writes }, native.inputs_schema, .inputs));
    }
}

fn checkNativeGenerationStart(view: @import("domain/pipeline_data.zig").View, accepted: bool, permit: ?@import("domain/workflow_retry.zig").Permit) !void {
    const values = @import("application/pipeline_values.zig");
    const native = @import("application/specification_workflow.zig");
    var binding: native.Initialize = .{ .allocator = std.testing.allocator };
    var input = try projectionOperationInput(native.Initialize, view);
    input.step.repair_permit = permit;
    const result = try native.Initialize.invoke(&binding, input);
    const value = result.delta.data_writes[@intFromEnum(native.session_schema.key)] orelse return error.ExpectedGenerationInitialization;
    defer values.destroy(value);
    const output: @import("domain/pipeline_data.zig").View = .{ .slots = result.delta.data_writes };
    if (accepted) {
        try std.testing.expectEqual(.ok, result.outcome);
        try std.testing.expect(result.diagnostic == null);
        try std.testing.expectEqual(@as(usize, 0), (try native.readSession(&output)).completed);
    } else {
        try std.testing.expectEqual(.blocked, result.outcome);
        try std.testing.expectEqual(error.InvalidRequiredAuthority, result.diagnostic.?);
        try std.testing.expectError(error.InvalidCandidatePayload, native.readSession(&output));
    }
}

test "source omission repair preserves sibling claims and rebuilds canonical identities" {
    const repair = @import("domain/reference_extraction_repair.zig").Omission;
    const e = @import("domain/reference_extraction.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display the current UTC date and time.\n", "Show the loan's new return deadline.\n" }) |source| {
        var fixture = try Fixture.initClassified(a, source, null);
        defer fixture.deinit();
        const inputs = fixture.context.inputs;
        const chunk = inputs.chunks.entries[0];
        const facts: repair.Facts = .{ .extraction = .{ .inputs = inputs, .candidates = try tokens.candidates(a, inputs), .candidate = fixture.extracted_text }, .support = try omissionSupport(&fixture, .{ .extraction_claim = chunk.id }, source) };
        const auth = try repair.authorize(a, facts);
        try std.testing.expect(auth.operation == .insert and auth.target.claim == 1);
        var started = facts;
        started.support.repair_phase = .generation_started;
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.authorize(a, started));
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.packet(a, started, fixture.context.registry, auth));
        const packet = try repair.packet(std.testing.allocator, facts, fixture.context.registry, auth);
        defer packets.release(packet);
        try std.testing.expectEqualStrings("claim", packet.resultDefinition().?.bytes);
        const proposal: e.Proposal = .{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Show the required date and time." } }} } }, .citations = &.{extraction.wholeChunk(chunk)} };
        const wire = try @import("domain/model_candidate_json.zig").encode(e.Proposal, a, proposal);
        try checkPreparedExtractionOmission(a, packet, wire);
        const replacement = try repair.parse(a, auth, packet, wire);
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, started.extraction.inputs), text.validator, fixture.context.registry, fixture.context.current, started, auth, replacement, null));
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 15 }, .attempt = .{ .value = 1 } };
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (facts).extraction.inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, replacement, origin);
        try std.testing.expectEqualDeep(fixture.extracted_text.entries[1..], merged.entries[1..]);
        try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].outcome.claims[0], merged.entries[0].outcome.claims[0]);
        try std.testing.expectEqualDeep(origin, merged.entries[0].outcome.claims[1].origin.?);
        try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].token_classifications, merged.entries[0].token_classifications);
        const rebuilt = try extraction.finishText(a, inputs, merged);
        try std.testing.expectEqual(fixture.extracted.ledger.claims.len + 1, rebuilt.ledger.claims.len);
        try std.testing.expectEqual(@as(u32, 2), rebuilt.ledger.chunks[0].outcome.claims[1].ordinal);
        const renewed_context: references.Context = .{ .inputs = inputs, .registry = fixture.context.registry, .current = fixture.context.current };
        const renewed_global = try references.summaries(a, try references.initialize(a, inputs, rebuilt, 2), renewed_context);
        var rebuilt_context = fixture.context;
        rebuilt_context.references = (try references.finish(a, renewed_global, try references.global(a, renewed_global), renewed_context)).valid;
        try checkSourceOmissionProgress(a, merged.omission_retry.?, facts.support, rebuilt_context, &fixture);
        var stale = facts;
        stale.extraction.candidate = merged;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (stale).extraction.inputs), text.validator, fixture.context.registry, fixture.context.current, stale, auth, replacement, origin));
        stale = facts;
        stale.extraction.candidate.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, stale, fixture.context.registry, auth));
        var bad = replacement;
        bad.claim.citations = &.{.{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } }};
        const invalid = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (facts).extraction.inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, bad, origin);
        try std.testing.expectError(error.InvalidSourceCitation, extraction.finishText(a, inputs, invalid));
        var unlocalized = facts;
        unlocalized.support = try omissionSupport(&fixture, .{ .unlocalized = .{} }, source);
        try std.testing.expectError(error.UnlocalizedSourceOmission, repair.authorize(a, unlocalized));
    }
}

test "source omission reconciliation repair preserves evidence and rejects stale or foreign attribution" {
    const repair = @import("domain/reference_reconciliation_repair.zig").Omission;
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display the current UTC time.", "Display the new return deadline." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const global = fixture.context.references.records.assignments.checked.prior.prior;
        const parsed: r.Parsed = .{ .source = global.source, .input = global.input, .proposal = .{ .global = global.proposal } };
        const ctx: @import("domain/reference_reconciliation_validation.zig").TextContext = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
        const support = try omissionSupport(&fixture, .{ .reconciliation_signal = .{ .ordinal = 1 } }, source);
        const auth = try repair.authorize(a, parsed, ctx, support);
        try std.testing.expectEqual(@as(usize, 0), auth.target.unit.signal_content);
        var started = support;
        started.repair_phase = .generation_started;
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.authorize(a, parsed, ctx, started));
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.packet(a, parsed, ctx, started, auth));
        const packet = try repair.packet(std.testing.allocator, parsed, ctx, support, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("business_text", packet.resultDefinition().?.bytes);
        const proposed = try repair.parse(a, auth, packet, "{\"segments\":\"Preserve the required deadline.\"}");
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, ctx.inputs), parsed, ctx, started, auth, proposed, null));
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), parsed, ctx, support, auth, proposed, null);
        try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions, merged.proposal.global.claim_dispositions);
        try std.testing.expectEqualDeep(parsed.proposal.global.signals[1..], merged.proposal.global.signals[1..]);
        try std.testing.expectEqualDeep(parsed.proposal.global.conflicts, merged.proposal.global.conflicts);
        try std.testing.expectEqualDeep(parsed.proposal.global.signals[0].claim_ids, merged.proposal.global.signals[0].claim_ids);
        var rebuilt_context = fixture.context;
        // Reference repairs retain current conflict authority and proceed through
        // full native validation without a presentation-role reassessment.
        try std.testing.expectEqual(.complete, merged.phase);
        rebuilt_context.references = (try references.finish(a, merged.input, merged.proposal.global, ctx)).valid;
        const before = try @import("domain/reference_reconciliation_context.zig").snapshot(a, parsed, ctx);
        const after = try @import("domain/reference_reconciliation_context.zig").snapshot(a, merged, ctx);
        try std.testing.expect(!std.meta.eql(before, after));
        try checkSourceOmissionProgress(a, merged.source.omission_retry.?, support, rebuilt_context, &fixture);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), merged, ctx, support, auth, proposed, null));
        var changed = support;
        changed.review.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, ctx, changed, auth));
        const review = @import("domain/specification_support.zig").Source;
        const findings = try a.dupe(review.Finding, support.review.review.entries);
        const selected_index = for (findings, 0..) |finding, index| {
            if (finding.value.kind == .candidate_omission) break index;
        } else return error.InvalidOmissionFixture;
        findings[selected_index].value.loss = .{ .extraction_claim = .{ .bytes = "foreign-chunk" } };
        var candidate = support.review;
        candidate.review.entries = findings;
        var unreviewed = support.inputs;
        unreviewed.evidence = &.{};
        unreviewed.candidates = &.{};
        try std.testing.expect((try review.validate(a, unreviewed, ctx.inputs, candidate)) == .rejected);
        findings[selected_index].value.loss = support.review.review.entries[selected_index].value.loss;
        findings[selected_index].value.kind = .supported;
        try std.testing.expect((try review.validate(a, unreviewed, ctx.inputs, candidate)) == .rejected);
    }
}

test "semantic disposition repair reuses fixed-sibling choices and full validation" {
    const repair = @import("domain/reference_reconciliation_repair.zig").Omission;
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Retain the booking deadline.\n" ** 70);
    defer fixture.deinit();
    const original = fixture.context.references.records.assignments.checked.prior.prior;
    const values = try a.dupe(r.ClaimDispositionProposal, original.proposal.claim_dispositions);
    try std.testing.expect(values.len >= 2);
    values[0].disposition = .{ .duplicate = .{ .target_claim_id = values[1].claim_id } };
    var proposal = original.proposal;
    proposal.claim_dispositions = values;
    // The retired group remains diagnostic evidence; positive authoring
    // selections must use retained groups from the current native catalogue.
    const ctx: @import("domain/reference_reconciliation_validation.zig").TextContext = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
    fixture.context.references = (try references.finish(a, original.input, proposal, ctx)).valid;
    const global = fixture.context.references.records.assignments.checked.prior.prior;
    const parsed: r.Parsed = .{ .source = global.source, .input = global.input, .proposal = .{ .global = global.proposal } };
    const disposition_support = try omissionSupport(&fixture, .{ .reconciliation_disposition = parsed.proposal.global.claim_dispositions[0].claim_id }, "MOCK Retain the booking deadline.");
    const disposition_auth = try repair.authorize(a, parsed, ctx, disposition_support);
    try std.testing.expect(disposition_auth.rule.disposition_choices.?.retained);
    try std.testing.expectEqual(values.len - 1, disposition_auth.rule.disposition_choices.?.duplicate_targets.len);
    try std.testing.expectEqualDeep(values[1].claim_id, disposition_auth.rule.disposition_choices.?.duplicate_targets[0]);
    const disposition_packet = try repair.packet(a, parsed, ctx, disposition_support, disposition_auth);
    defer @import("domain/model_input_packet.zig").release(disposition_packet);
    try std.testing.expectEqualStrings("repair_disposition", disposition_packet.resultDefinition().?.bytes);
    const body = try std.json.parseFromSlice(std.json.Value, a, disposition_packet.body(), .{});
    try std.testing.expectEqual(@as(usize, 0), body.value.object.get("input").?.object.get("constraints").?.array.items.len);
    try std.testing.expect(body.value.object.get("repair").?.object.get("rule").?.object.get("disposition_choices").?.object.get("retained").?.bool);
    const replacement = try repair.parse(a, disposition_auth, disposition_packet, "{\"kind\":\"retained\"}");
    const repaired = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), parsed, ctx, disposition_support, disposition_auth, replacement, null);
    try std.testing.expectEqual(.dispositions, repaired.phase);
    try std.testing.expectEqualDeep(parsed.proposal.global.signals[1..], repaired.proposal.global.signals);
    try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions[1..], repaired.proposal.global.claim_dispositions[1..]);
    try std.testing.expect(repaired.proposal.global.claim_dispositions[0].disposition == .retained);
    try std.testing.expect((try references.validate_dispositions.execute(a, repaired)) == .valid);
    try std.testing.expectError(error.InvalidReferenceReconciliation, references.validate_signals.execute(a, (try references.validate_dispositions.execute(a, repaired)).valid, ctx));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, repaired, ctx, disposition_support, disposition_auth));
}

test "pre-generation localized disposition evidence replaces source review lineage" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const model = @import("domain/specification_support_model.zig");
    const loss = @import("domain/source_omission.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = @import("domain/model_result_schema.zig");
    const canonical = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    for ([_][]const u8{ "MOCK Display the greeting and current UTC date.", "MOCK Renew an eligible loan and retain its deadline on refusal." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        const original = fixture.context.references.records.assignments.checked.prior.prior;
        var proposal = original.proposal;
        const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
        const retained = dispositions[0].claim_id;
        const discarded = dispositions[1].claim_id;
        dispositions[1].disposition = .{ .duplicate = .{ .target_claim_id = retained } };
        proposal.claim_dispositions = dispositions;
        const ctx: @import("domain/reference_reconciliation_validation.zig").TextContext = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
        fixture.context.references = (try references.finish(a, original.input, proposal, ctx)).valid;
        const feature = fixture.context.inputs.corpus.feature_id;
        const views = [_]authority.Inputs{
            try (@import("actions/authority/build_source_preservation_requirements.zig").Action{}).execute(a, feature, fixture.context.references, fixture.context.inputs),
            try @import("domain/specification_authority.zig").project(a, feature, fixture.context.references, null, null),
        };
        for (views) |inputs| {
            const ledger = try authority.build(a, inputs);
            const index = if (inputs.projection == .source_preservation) 0 else for (ledger.requirements, 0..) |required, i| {
                if (required.seed.id.unit == .feature and required.seed.id.slot == .primary_user_story) break i;
            } else return error.MissingStoryRequirement;
            const id = ledger.requirements[index].seed.id;
            const required = try admission.requirements(a, inputs, fixture.context.inputs, id);
            if (inputs.specification != null) try std.testing.expectEqualDeep(&[_]r.ClaimId{retained}, required.supported_provenance.?.claim_ids);
            const entries = try a.dupe(support.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
            entries[index].value = try model.decode(a, try std.fmt.allocPrint(a, "{{\"kind\":\"candidate_omission\",\"source_ids\":[{d}],\"detail\":\"MOCK A discarded producer lost a requirement.\",\"missing_obligation\":\"MOCK Retain the booking deadline.\"}}", .{fixture.context.inputs.corpus.sources[0].id.ordinal}), required);
            const initial = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = entries }), null)).accepted;
            var pending = initial.candidate;
            pending.pending_localization = @intCast(index + 1);
            const packet = try support.packetForLoss(std.testing.allocator, inputs, fixture.context, pending);
            defer packets.release(packet);
            const narrowed = try schema.restrict(a, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer narrowed.release();
            const selected: loss.Location = .{ .reconciliation_disposition = discarded };
            const assigned = try support.comparisonAssignment(a, inputs, fixture.context, pending);
            const wire = try @import("test_fixtures/source_omission_evidence.zig").encode(a, assigned, selected);
            try @import("model_payload_schema_test.zig").checkDocument(narrowed.selected().modelBytes(), .{ .bytes = wire });
            try expectExactMembers(a, packet, wire, "assessments", "comparison_id");

            const collected = (try support.collectLoss(a, inputs, fixture.context, .{ .accepted = .{ .inputs = initial.inputs, .candidate = pending } }, packet, wire, null)).accepted;
            const located = collected.candidate.review.entries[index].value;
            try std.testing.expectEqualDeep(&[_]r.ClaimId{discarded}, located.provenance.claim_ids);
            try std.testing.expectEqual(initial.candidate.review.entries[index].value.kind, located.kind);
            try std.testing.expectEqualStrings(initial.candidate.review.entries[index].value.detail, located.detail);
            try std.testing.expectEqualDeep(initial.candidate.review.entries[index].value.source_ids, located.source_ids);
            for (initial.candidate.review.entries, collected.candidate.review.entries, 0..) |before, after, sibling| if (sibling != index) try std.testing.expectEqualDeep(before, after);
            try support.validateStored(a, collected.inputs, fixture.context.inputs);
            try std.testing.expectEqualDeep(&[_]r.ClaimId{discarded}, required.rule(.candidate_omission, selected).fixedClaims().?);
            for ([_][]const r.ClaimId{ &.{retained}, &.{} }) |wrong| {
                const rejected = try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, .{ .claim_ids = wrong, .clarification_response_ids = &.{} }, located.source_ids, located.detail, located.missing_obligation, selected, null, null);
                try std.testing.expect(rejected == .rejected);
            }
            const invalid_location = try model.bindLoss(required, initial.candidate.review.entries[index].value, .{ .reconciliation_disposition = retained }, located.preservation.?);
            const rejected = try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, invalid_location.provenance, invalid_location.source_ids, invalid_location.detail, invalid_location.missing_obligation, invalid_location.loss, null, null);
            try std.testing.expectEqual(.invalid_loss, rejected.rejected.issue);
            try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(lossPacketAllocationCase, .{ inputs, fixture.context, pending });
        }
    }
}

fn lossPacketAllocationCase(allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, candidate: @import("domain/specification_support.zig").Source.Candidate) !void {
    const packet = try @import("domain/specification_support.zig").Source.packetForLoss(allocator, inputs, context, candidate);
    defer @import("domain/model_input_packet.zig").release(packet);
}

test "loss comparison keeps multi-source producers visible without authorizing uncited sources" {
    const r = references.r;
    const authority = @import("domain/required_authority.zig");
    const loss = @import("domain/source_omission.zig");
    const projection = @import("domain/source_omission_context.zig");
    for ([_][2][]const u8{
        .{ "MOCK Renew eligible loans.\n", "MOCK Preserve the due date after refusal.\n" },
        .{ "MOCK Reserve available equipment.\n", "MOCK Confirm its return deadline.\n" },
    }) |sources| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &sources);
        defer fixture.deinit();
        const input = try references.summaries(a, try references.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
        var proposal = try references.global(a, input);
        const ids = [_]r.ClaimId{ proposal.signals[0].claim_ids[0], proposal.signals[1].claim_ids[0] };
        proposal.signals = &.{.{ .claim_ids = &ids, .content = proposal.signals[0].content }};
        const ready = (try references.finish(a, input, proposal, fixture.context())).valid;
        const context: provenance.Context = .{ .inputs = fixture.inputs, .references = ready, .registry = fixture.text.registry, .current = fixture.context().current };
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.inputs.corpus.feature_id, ready, null, null);
        const subject_id = (try authority.build(a, inputs)).requirements[0].seed.id;
        const source_ids = [_]r.extraction.identity.SourceId{ fixture.inputs.corpus.sources[0].id, fixture.inputs.corpus.sources[1].id };
        const upstream: loss.Location = .{ .reconciliation_signal = inputs.references.?.signals[0].id };
        var review: authority.ReviewEvidence = .{ .detail = "MOCK Compare the complete grouped obligation.", .source_ids = &source_ids, .provenance = .{ .claim_ids = &ids, .citation_ids = &.{}, .clarification_response_ids = &.{} } };
        try std.testing.expectError(error.InvalidRequiredAuthority, loss.validate(a, inputs, fixture.inputs, subject_id, .candidate_omission, review, upstream));
        const full = try projection.project(a, inputs.references.?, context);
        review.source_ids = source_ids[0..1];
        try std.testing.expectError(error.InvalidRequiredAuthority, loss.validate(a, inputs, fixture.inputs, subject_id, .candidate_omission, review, upstream));
        const limited = try projection.project(a, inputs.references.?, context);
        try std.testing.expectEqual(full.len, limited.len);
        var signal_count: usize = 0;
        for (full, limited) |eligible, supporting| {
            try std.testing.expectEqualDeep(eligible.output, supporting.output);
            if (supporting.output != .signal) continue;
            signal_count += 1;
            try std.testing.expectEqualDeep(&ids, supporting.output.signal.result.value.claim_ids);
            try std.testing.expectEqual(@as(usize, 2), supporting.output.signal.claims.claims.len);
            for (supporting.output.signal.claims.claims, source_ids) |claim, source_id| {
                try std.testing.expectEqualDeep(source_id, claim.source_id);
                try std.testing.expectEqualStrings("The user can confirm the request.", claim.meaning);
                try std.testing.expect(claim.citation_ids.len != 0);
            }
        }
        try std.testing.expectEqual(@as(usize, 1), signal_count);
    }
}

test "loss producer comparison resolves passive and source references while preserving exact evidence" {
    const r = references.r;
    const projection = @import("domain/source_omission_context.zig");
    for ([_][]const u8{
        "MOCK Display status from src/status.zig with `MOCK Ready!`.\n",
        "MOCK Confirm queued work from src/queue.zig with `MOCK Queued!`.\n",
    }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContentKinds(a, source, .business_exact_string, true, "MOCK Read the supplied source.", 2, true);
        defer fixture.deinit();
        var records = @import("domain/reference_support.zig").records(fixture.context.references);
        const items = try a.dupe(r.Item, records.items.entries);
        records.items.entries = items;
        const scope: r.evidence.Scope = .{ .state_id = fixture.context.inputs.corpus.state_id, .chunk_id = items[0].claim.chunk_id };
        const validation_context: r.text.Context = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current, .scope = scope, .field = .extraction_business };
        const literal = fixture.context.registry.records[0];
        items[0].claim.content = .{ .model = .{ .business = try text.validator.business(a, validation_context, .{ .segments = &.{
            .{ .literal = .{ .value = "MOCK Display " } },
            .{ .passive = .{ .passive_literal_id = literal.id } },
            .{ .literal = .{ .value = " when requested." } },
        } }) } };
        var technical_context = validation_context;
        technical_context.field = .extraction_technical;
        items[1].claim.content = .{ .model = .{ .technical = try text.validator.reference(a, technical_context, .{ .nodes = &.{
            .{ .literal = .{ .value = "MOCK Context in " } },
            .{ .source = .{ .source_id = items[1].source_id } },
        } }) } };
        const signals = try a.dupe(r.Signal, records.signals);
        records.signals = signals;
        for (signals) |*signal| {
            const claim = try r.item(records.items, signal.value.claim_ids[0]);
            signal.value.content = switch (claim.claim.content) {
                .model => |content| .{ .model = content },
                .preserved_token => |token| .{ .preserved_token = .{ .token_id = token.value.id } },
            };
        }
        const producers = try projection.project(a, records, fixture.context);
        const supporting = try projection.comparisonSupport(a, records, fixture.context, &.{items[0].source_id}, &.{ items[0].claim.id, items[1].claim.id, items[2].claim.id });
        try std.testing.expectEqual(producers.len, supporting.len);
        const business = try std.fmt.allocPrint(a, "MOCK Display {s} when requested.", .{literal.value});
        const technical = try std.fmt.allocPrint(a, "MOCK Context in {s}", .{fixture.context.inputs.corpus.sources[0].path.bytes});
        const exact = items[2].claim.content.preserved_token.value.raw_value.bytes;
        const original_evidence = try @import("domain/model_evidence.zig").project(a, items);
        for (producers, supporting) |canonical, presented| switch (canonical.output) {
            .extraction => |value| {
                const projected = presented.output.extraction;
                try std.testing.expectEqual(value.claims.claims.len, projected.outcome.claims.len);
                for (value.claims.claims, projected.outcome.claims) |claim, copy| {
                    try std.testing.expectEqualStrings(claim.meaning, copy.meaning);
                    try std.testing.expectEqualDeep(claim.source_id, copy.source_id);
                }
                for (value.result.token_classifications, projected.token_classifications) |decision, copy| {
                    try std.testing.expectEqualDeep(decision.decision, copy.decision);
                    try std.testing.expectEqualStrings(decision.candidate.verbatim.?, copy.verbatim.?);
                }
            },
            .signal => |value| {
                try std.testing.expectEqualDeep(value.result.value.content, presented.output.signal.content);
            },
            .disposition => |value| {
                try std.testing.expectEqual(value.result.disposition, presented.output.disposition.disposition);
                try std.testing.expectEqualStrings(value.claims.claims[0].meaning, presented.output.disposition.input.meaning);
            },
            .token_classification => |value| try std.testing.expectEqualStrings(value.candidate.verbatim.?, presented.output.token_classification.verbatim.?),
            else => return error.UnexpectedLossProducer,
        };
        var inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        inputs.references = records;
        var signal_subjects: usize = 0;
        var token_subjects: usize = 0;
        for ((try @import("domain/required_authority.zig").build(a, inputs)).requirements) |requirement| switch (requirement.seed.id.unit) {
            .signal => |id| {
                const subject = try @import("domain/specification_review_subject.zig").projectLoss(a, inputs, fixture.context, requirement.seed.id);
                try std.testing.expect(subject == .reference and subject.reference == .signal);
                for (producers) |producer| {
                    if (producer.output == .signal and std.meta.eql(producer.output.signal.result.id, id)) {
                        try std.testing.expectEqualDeep(producer.output.signal.result, subject.reference.signal);
                        break;
                    }
                } else return error.MissingSignalProducer;
                signal_subjects += 1;
            },
            .token => {
                const subject = try @import("domain/specification_review_subject.zig").projectLoss(a, inputs, fixture.context, requirement.seed.id);
                try std.testing.expect(subject == .reference and subject.reference == .token);
                try std.testing.expectEqualStrings(exact, subject.reference.token.value);
                try std.testing.expectEqualDeep(items[2].claim.citation_ids[0], subject.reference.token.citation_id);
                token_subjects += 1;
            },
            else => {},
        };
        try std.testing.expectEqual(signals.len, signal_subjects);
        try std.testing.expectEqual(@as(usize, 1), token_subjects);
        for (producers) |producer| switch (producer.output) {
            .extraction => |output| {
                try std.testing.expectEqual(@as(usize, 3), output.claims.claims.len);
                for (output.claims.claims, items, [_][]const u8{ business, technical, exact }) |claim, item, expected| {
                    try std.testing.expectEqualStrings(expected, claim.meaning);
                    try std.testing.expectEqualDeep(item.claim.id, claim.id);
                    try std.testing.expectEqualDeep(item.claim.citation_ids, claim.citation_ids);
                }
                try std.testing.expectEqualStrings(exact, output.claims.preserved_tokens[0].value);
                try std.testing.expectEqualDeep(original_evidence.citations, output.claims.citations);
                try std.testing.expectEqualDeep(original_evidence.preserved_tokens, output.claims.preserved_tokens);
            },
            .signal => |output| {
                try std.testing.expectEqualStrings(output.claims.claims[0].meaning, output.result.value.content.meaning);
                try std.testing.expectEqualDeep(output.result.value.claim_ids[0], output.claims.claims[0].id);
            },
            .disposition => |output| {
                try std.testing.expectEqualDeep(output.result.claim_id, output.claims.claims[0].id);
                const expected = ([_][]const u8{ business, technical, exact })[output.result.claim_id.ordinal - 1];
                try std.testing.expectEqualStrings(expected, output.claims.claims[0].meaning);
            },
            .token_classification => |classification| {
                try std.testing.expectEqualStrings(exact, classification.candidate.verbatim.?);
            },
            else => return error.UnexpectedLossProducer,
        };
    }
}

test "source omission repairs a false empty outcome and reclassifies its exact tokens" {
    const repair = @import("domain/reference_extraction_repair.zig").Omission;
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    {
        var fixture = try Fixture.initExtraction(a, "Display `MOCK Loan renewed!` and `Due today` with the new deadline.", null, false);
        defer fixture.deinit();
        const inputs = fixture.context.inputs;
        const candidates = try tokens.candidates(a, inputs);
        try std.testing.expectEqual(@as(usize, 2), candidates.entries.len);
        const entries = try a.dupe(@import("domain/reference_extraction.zig").TextValidatedResult, fixture.extracted_text.entries);
        const origins = try a.alloc(?Origin, entries[0].token_classifications.len);
        @memset(origins, original);
        entries[0].classification_origins = origins;
        entries[0].origin = original;
        fixture.extracted_text.entries = entries;
        const chunk = inputs.chunks.entries[0];
        const facts: repair.Facts = .{ .extraction = .{ .inputs = inputs, .candidates = candidates, .candidate = fixture.extracted_text }, .support = try omissionSupport(&fixture, .{ .extraction_claim = chunk.id }, "MOCK Display the new deadline.") };
        const auth = try repair.authorize(a, facts);
        try std.testing.expect(auth.operation == .replace);
        const replacement: repair.Replacement = .{ .outcome = .{ .claim = .{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Display the new deadline." } }} } }, .citations = &.{extraction.wholeChunk(chunk)} } } };
        try std.testing.expect(auth.target == .outcome and auth.operation.replace.outcome == .no_feature_claim);
        const atomic = @import("domain/atomic_repair.zig");
        const before = try atomic.snapshot(repair.Authorization, a, auth);
        const packet = try repair.packet(a, facts, fixture.context.registry, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("claim", packet.resultDefinition().?.bytes);
        const wire = try @import("domain/model_candidate_json.zig").encode(@import("domain/reference_extraction.zig").Proposal, a, replacement.outcome.claim);
        try checkPreparedExtractionOmission(a, packet, wire);
        try std.testing.expectEqualDeep(before, try atomic.snapshot(repair.Authorization, a, auth));
        const decoded = try repair.parse(a, auth, packet, wire);
        try std.testing.expectEqualDeep(replacement, decoded);
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (facts).extraction.inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, decoded, corrected);
        try std.testing.expectEqualDeep(original, merged.entries[0].origin.?);
        var classified = merged;
        {
            try std.testing.expectEqual(@as(usize, 0), merged.entries[0].token_classifications.len);
            try std.testing.expectEqual(@as(usize, 0), merged.entries[0].classification_origins.len);
            try std.testing.expect((try @import("domain/token_classification_validation.zig").validate(a, inputs, candidates, merged)) == .invalid);
            const revised = try a.dupe(@import("domain/reference_extraction.zig").TextValidatedResult, merged.entries);
            const choices = try a.alloc(@import("domain/structured_tokens.zig").Classification, candidates.entries.len);
            const origins_ = try a.alloc(?Origin, choices.len);
            @memset(origins_, corrected);
            for (choices, candidates.entries) |*choice, candidate| choice.* = .{ .preserve = .{ .token_candidate_id = candidate.id, .kind = .business_exact_string } };
            revised[0].token_classifications = choices;
            revised[0].classification_origins = origins_;
            classified.entries = revised;
        }
        const rebuilt = try extraction.finishText(a, inputs, classified);
        try std.testing.expectEqual(.complete, rebuilt.outcome);
        {
            try std.testing.expectEqual(@as(usize, 2), classified.entries[0].token_classifications.len);
            try std.testing.expectEqualDeep(corrected, merged.entries[0].outcome.claims[0].origin.?);
            try std.testing.expectEqualDeep(corrected, merged.entries[0].outcome.claims[0].citations_origin.?);
        }
    }
}
fn completedFixture(fixture: *const Fixture, omit_requirements: bool) !@import("domain/specification_session.zig").Session {
    return completedFixtureValue(fixture, omit_requirements, try fixture.proposal("A receipt is available."));
}
fn completedSupportInputs(fixture: *const Fixture) !@import("domain/required_authority.zig").Inputs {
    const current = try completedFixture(fixture, false);
    const content = (try @import("domain/specification_session.zig").assemble(fixture.allocator, text.validator, fixture.context, current)).content;
    return @import("domain/specification_authority.zig").project(fixture.allocator, current.feature, fixture.context.references, content, current.units[0].?.response.content.brief);
}
fn completedFixtureValue(fixture: *const Fixture, omit_requirements: bool, value: spec.Model.AttributedValue) !@import("domain/specification_session.zig").Session {
    const sessions = @import("domain/specification_session.zig");
    const a = fixture.allocator;
    const ac: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const fr: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
    while (current.completed < sessions.unit_count) {
        const unit = try sessions.unit(current.completed);
        const response: g.Response = .{ .content = switch (unit) {
            .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
            .primary_user_story => .{ .primary_user_story = value },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
            .records => .{ .records = if (omit_requirements) &.{ac} else &.{ fr, ac } },
        } };
        if (unit == .records) {
            // A finite native assignment is assessed even when it yields no
            // records. Only the first mock business group authors these records.
            const batch: @import("domain/specification_candidate.zig").Candidate = .{ .response = if (current.record_cursor == 0) response else .{ .content = .{ .records = &.{} } } };
            const checked = (try validate_unit.execute(a, current, fixture.context, batch)).valid;
            current = try sessions.appendBound(a, current, checked);
        } else current = try appendMockResponse(a, current, fixture.context, response);
    }
    return current;
}

// Test-only authoring folds explicit mock associations through each native
// assignment. Empty batches are admitted rather than skipped or fabricated.
fn appendMockResponse(a: std.mem.Allocator, current: @import("domain/specification_session.zig").Session, context: provenance.Context, response: g.Response) !@import("domain/specification_session.zig").Session {
    return appendMockChecked(a, current, context, (try g.validate(a, text.validator, context, try @import("domain/specification_session.zig").unit(current.completed), response)).valid);
}

fn appendMockChecked(a: std.mem.Allocator, current: @import("domain/specification_session.zig").Session, context: provenance.Context, checked: g.Checked) !@import("domain/specification_session.zig").Session {
    const sessions = @import("domain/specification_session.zig");
    const response = checked.response;
    if (response != .content or response.content != .records) return sessions.append(current, checked);
    var next = current;
    var dispatched: usize = 0;
    while (next.completed == sessions.records_index) {
        const bound = (try sessions.currentBinding(a, next, context)).records;
        var selected: std.ArrayList(spec.RecordProposal) = .empty;
        var origins: std.ArrayList(@import("domain/specification_candidate.zig").FieldOrigin) = .empty;
        for (response.content.records, 0..) |record, index| {
            if (record.source_group_ids.len != 1) return error.InvalidMockAssociation;
            if (std.meta.eql(record.source_group_ids[0], bound.signal)) {
                try origins.append(a, .{ .target = .{ .record = selected.items.len }, .origin = checked.origins.at(.{ .target = .{ .record = index } }) });
                try selected.append(a, record);
                dispatched += 1;
            }
        }
        var batch = checked;
        batch.response.content.records = selected.items;
        batch.origins = .{ .fields = origins.items };
        batch.record_assignment = null;
        const admitted = try sessions.admit(a, next, context, batch);
        try std.testing.expect((try sessions.checkConsistency(a, next, context, admitted)) == null);
        next = try sessions.appendBound(a, next, admitted);
    }
    if (dispatched != response.content.records.len) return error.InvalidMockAssociation;
    return next;
}

fn mockClaimGroup(a: std.mem.Allocator, context: provenance.Context, id: references.r.ClaimId) ![]const references.r.SignalId {
    const groups = try @import("domain/specification_source_binding.zig").catalogue(a, @import("domain/reference_support.zig").records(context.references), .content);
    for (groups) |group| if (group.claim_ids.len == 1 and std.meta.eql(group.claim_ids[0], id)) return a.dupe(references.r.SignalId, &.{group.signal_id});
    return error.MissingMockGroup;
}

test "scalar source assessments resolve their assigned field and preserve complete evidence across review repairs" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    const model_evidence = @import("domain/model_evidence.zig");
    const admission = @import("domain/specification_support_evidence.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][4][]const u8{
        .{ "# MOCK Hello World Application\nDisplay `MOCK Hello, World!` and export stories.md.\n", "MOCK Hello, World!", "Display the greeting and export its document.", "Let a visitor read the greeting." },
        .{ "# Loan renewal\nRenew the loan, display `MOCK Loan renewed!` and export stories.md.\n", "MOCK Loan renewed!", "Renew the loan and export its document.", "Let a borrower retain the renewal receipt." },
    }) |example| {
        var fixture = try Fixture.init(a, example[0]);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const token_claim = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token and std.mem.eql(u8, entry.claim.content.preserved_token.value.raw_value.bytes, example[1])) break entry.claim;
        } else return error.MissingExactToken;
        const title: spec.AttributedValue = .{
            .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = token_claim.id } }} },
            .source_group_ids = try mockClaimGroup(a, fixture.context, token_claim.id),
            .provenance = .{ .claim_ids = &.{token_claim.id}, .citation_ids = token_claim.citation_ids, .clarification_response_ids = &.{} },
        };
        const description = try fixture.value(example[2]);
        const goal = try fixture.value(example[3]);
        var story = try fixture.value("Read the document after the action.");
        const filename = fixture.context.registry.records[0];
        try std.testing.expectEqualStrings("stories.md", filename.value);
        story.value = .{ .segments = &.{
            .{ .literal = .{ .value = "Read " } },
            .{ .passive = .{ .passive_literal_id = filename.id } },
            .{ .literal = .{ .value = " after the action." } },
        } };
        const session = try completedFixture(&fixture, false);
        var content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, session)).content;
        content.display_name = title;
        content.primary_user_story = story;
        // The assembled name is selected even when the brief carries another title.
        const inputs = try @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references, content, .{ .title = description, .description = description, .primary_goal = goal });
        const ledger = try authority.build(a, inputs);
        const projected = try model_evidence.project(a, all.entries);
        for ([_]authority.Slot{ .display_name, .description, .primary_goal, .primary_user_story }, [_]spec.AttributedValue{ title, description, goal, story }, [_][]const u8{ example[1], example[2], example[3], "Read stories.md after the action." }) |slot, field, expected_text| {
            const id = for (ledger.requirements) |requirement| {
                if (requirement.seed.id.unit == .feature and requirement.seed.id.slot == slot) break requirement.seed.id;
            } else return error.MissingFeatureRequirement;
            const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = id });
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try expectReviewAssessmentScope(.source, a, .{ .object = body }, id);
            const subject = body.get("subject").?.object;
            try std.testing.expectEqualStrings("candidate_field", subject.get("kind").?.string);
            try std.testing.expectEqualStrings(@tagName(slot), subject.get("slot").?.string);
            try std.testing.expectEqualStrings(expected_text, subject.get("text").?.string);
            try std.testing.expectEqualDeep(field.provenance, try json.decode(spec.Provenance, a, try std.json.Stringify.valueAlloc(a, subject.get("provenance").?, .{})));
            var expected_evidence = field.provenance;
            expected_evidence.claim_ids = try provenance.effectiveClaims(a, field.provenance.claim_ids, &.{field.value});
            try std.testing.expectEqualDeep(expected_evidence, (try admission.expectedProvenance(a, inputs, fixture.context.inputs, id)).?);
            try std.testing.expect(!subject.contains("candidate") and !subject.contains("brief"));
            for ([_][]const u8{ "extraction", "dispositions", "signals", "conflicts" }) |key| try std.testing.expect(!body.contains(key));
            try std.testing.expectEqualStrings(example[0], body.get("sources").?.array.items[0].object.get("text").?.string);
            try std.testing.expectEqualStrings(try json.encode(@TypeOf(projected.claims), a, projected.claims), try std.json.Stringify.valueAlloc(a, body.get("claims").?, .{}));
            try std.testing.expectEqualStrings(try json.encode(@TypeOf(projected.citations), a, projected.citations), try std.json.Stringify.valueAlloc(a, body.get("citations").?, .{}));
            try std.testing.expectEqualStrings(try json.encode(@TypeOf(projected.preserved_tokens), a, projected.preserved_tokens), try std.json.Stringify.valueAlloc(a, body.get("preserved_tokens").?, .{}));
            const assigned = body.get("requirements").?.array.items;
            try std.testing.expectEqual(@as(usize, 1), assigned.len);
            try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, id), assigned[0].object.get("task").?.string);
            try std.testing.expectEqualStrings("finding", packet.resultDefinition().?.bytes);
            const correction = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .correction = id });
            defer packets.release(correction);
            const correction_body = (try std.json.parseFromSlice(std.json.Value, a, correction.body(), .{})).value.object;
            try expectSameReviewSubject(a, packet, correction);
            try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, body.get("subject").?, .{}), try std.json.Stringify.valueAlloc(a, correction_body.get("subject").?, .{}));
            for ([_][]const u8{ "extraction", "dispositions", "signals", "conflicts" }) |key| try std.testing.expect(!correction_body.contains(key));
            try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(scalarReviewPacketAllocationCase, .{ inputs, fixture.context, id });
        }
        // Readiness has no authored brief; generated review requires the pair.
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references, null, .{ .title = title, .description = description, .primary_goal = goal }));
        const findings = try a.dupe(support.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
        findings[0].value.kind = .candidate_omission;
        findings[0].value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
        findings[0].value.detail = "The source feature identity was replaced by its output token.";
        findings[0].value.missing_obligation = "MOCK Preserve the named feature identity.";
        try bindReviewClaims(a, inputs, fixture.context, findings);
        const verdict = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
        try std.testing.expect(verdict.candidate.pending_localization == null);
        try std.testing.expectEqualDeep(inputs.specification, verdict.inputs.specification);
        try std.testing.expectEqual(.candidate_omission, verdict.inputs.evidence[0].finding);
        try std.testing.expect(verdict.inputs.evidence[0].resolution == .assessment);
        try support.validateStored(a, verdict.inputs, fixture.context.inputs);
        try std.testing.expectError(error.InvalidRequiredAuthority, support.comparisonAssignment(a, inputs, fixture.context, verdict.candidate));
        try std.testing.expectError(error.InvalidRequiredAuthority, support.packetForLoss(a, inputs, fixture.context, verdict.candidate));
        const id = ledger.requirements[0].seed.id;
        var foreign = id;
        foreign.contract_version += 1;
        try std.testing.expectError(error.InvalidRequiredAuthority, support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = foreign }));
    }
}

fn scalarReviewPacketAllocationCase(allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, id: @import("domain/required_authority.zig").Id) !void {
    const packet = try @import("domain/specification_support.zig").Source.packetFor(allocator, inputs, context, .{ .finding = id });
    defer @import("domain/model_input_packet.zig").release(packet);
}

test "record and signal review assignments retain resolved targets without post-generation localization" {
    const authority = @import("domain/required_authority.zig");
    const projection = @import("domain/specification_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][4][]const u8{
        .{ "On startup display `MOCK Hello!` and UTC date/time.", "The application has launched.", "The application may launch.", "The application has been shut down." },
        .{ "After renewal display `MOCK Loan renewed!` and the new return deadline.", "The borrower has renewed the loan.", "The borrower may renew the loan.", "The borrower has returned the loan." },
    }) |example| {
        var fixture = try Fixture.init(a, example[0]);
        defer fixture.deinit();
        const session = try completedFixture(&fixture, false);
        const initial = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, session)).content;
        for (example[1..]) |wording| {
            var content = initial;
            const records = try a.dupe(spec.IdentifiedRecord, content.records);
            const chosen = for (records, 0..) |record, index| {
                if (record.id.kind == .acceptance_criterion) break index;
            } else return error.MissingAcceptanceCriterion;
            records[chosen].proposal.content.acceptance_criterion.given = (try fixture.value(wording)).value;
            content.records = records;
            const inputs = try projection.project(a, session.feature, fixture.context.references, content, session.units[0].?.response.content.brief);
            const ledger = try authority.build(a, inputs);
            const target_index = for (ledger.requirements, 0..) |requirement, index| {
                if (requirement.seed.id.unit == .record and std.meta.eql(requirement.seed.id.unit.record, records[chosen].id) and requirement.seed.id.slot == .given) break index;
            } else return error.MissingGivenRequirement;
            const id = ledger.requirements[target_index].seed.id;
            const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = id });
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try expectReviewAssessmentScope(.source, a, .{ .object = body }, id);
            const subject = body.get("subject").?.object;
            try std.testing.expectEqualStrings("candidate_field", subject.get("kind").?.string);
            // Different meaning stays visible for the semantic judge; native
            // projection neither endorses it nor normalizes it into equivalence.
            try std.testing.expectEqualStrings(wording, subject.get("text").?.string);
            try std.testing.expectEqualDeep(records[chosen], try json.decode(spec.IdentifiedRecord, a, try std.json.Stringify.valueAlloc(a, subject.get("record").?, .{})));
            try std.testing.expectEqualStrings(example[0], body.get("sources").?.array.items[0].object.get("text").?.string);
            try std.testing.expect(std.mem.indexOf(u8, body.get("requirements").?.array.items[0].object.get("task").?.string, "precondition") != null);
            try scalarReviewPacketAllocationCase(std.testing.allocator, inputs, fixture.context, id);
            const good = try reviewFor(a, inputs, fixture.context.inputs);
            const proposed = try a.dupe(support.Finding, good.entries);
            proposed[target_index].value = try @import("domain/specification_support_model.zig").decode(a, "{\"kind\":\"candidate_omission\",\"source_ids\":[1],\"detail\":\"MOCK missing meaning supplied by the judge\",\"missing_obligation\":\"MOCK After the requested operation display its confirmation.\"}", try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, id));
            const finding = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = proposed }), null)).accepted;
            try std.testing.expect(finding.candidate.pending_localization == null);
            try std.testing.expectError(error.InvalidRequiredAuthority, support.packetForLoss(a, inputs, fixture.context, finding.candidate));
            try std.testing.expectEqual(.candidate_omission, finding.candidate.review.entries[target_index].value.kind);
            try std.testing.expectEqual(.unlocalized, std.meta.activeTag(finding.candidate.review.entries[target_index].value.loss));
            const result = try supportDecision(a, finding.inputs);
            try std.testing.expectEqual(.all_resolved, result.result.continuation);
            try std.testing.expect(result.result.entries[target_index].candidate_defect == null);
        }
        const inputs = try projection.project(a, session.feature, fixture.context.references, initial, session.units[0].?.response.content.brief);
        const ledger = try authority.build(a, inputs);
        for (ledger.requirements) |requirement| if (requirement.seed.id.unit == .signal) {
            const id = requirement.seed.id;
            const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = id });
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            const subject = body.get("subject").?.object;
            try std.testing.expectEqualStrings("reference", subject.get("kind").?.string);
            try std.testing.expect(!subject.contains("candidate"));
            const expected = for (inputs.references.?.signals) |signal| {
                if (std.meta.eql(signal.id, id.unit.signal)) break signal;
            } else return error.MissingSignal;
            const projected = try @import("domain/source_omission_context.zig").projectSignal(a, inputs.references.?, fixture.context, expected);
            const selected = try json.decode(@import("domain/specification_review_subject.zig").Subject, a, try std.json.Stringify.valueAlloc(a, @as(std.json.Value, .{ .object = subject }), .{}));
            try std.testing.expectEqualDeep(projected, selected.reference.signal);
            if (expected.value.content == .preserved_token) try std.testing.expectEqualStrings((try @import("domain/reference_support.zig").exact(inputs.references.?.items, expected.value.claim_ids[0])).value.raw_value.bytes, selected.reference.signal.value.content.meaning);
        };
        try std.testing.expectError(error.InvalidRequiredAuthority, projection.valueField(.{ .kind = .feature_intent, .unit = .{ .record = initial.records[0].id }, .slot = .relationship, .member = 0 }));
    }
}

test "native reference reviews retain pre-generation attribution and generated advisory subjects" {
    const authority = @import("domain/required_authority.zig");
    const subjects = @import("domain/specification_review_subject.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    for ([_][2][]const u8{
        .{ "On startup display `MOCK Ready!` and the UTC date.\n", "MOCK Display the current UTC date after startup." },
        .{ "After delivery display `MOCK Delivered!` and retain the sender receipt.\n", "MOCK Retain the sender receipt after delivery." },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, example[0], .business_exact_string, true, example[1], 3);
        defer fixture.deinit();
        _ = try introduceConflict(&fixture);
        const records = @import("domain/reference_support.zig").records(fixture.context.references);
        const association = try binding.resolveGroups(a, records, fixture.context.inputs, &.{records.signals[0].id}, .content);
        const value: spec.AttributedValue = .{
            .value = .{ .segments = &.{.{ .literal = .{ .value = example[1] } }} },
            .source_group_ids = association.source_group_ids,
            .provenance = try provenance.select(a, fixture.context, association.selection),
        };
        // Read-only projections also inspect a candidate while source review
        // evaluates a conflict. Such references must not enter authoring.
        const brief: spec.Brief = .{ .title = value, .description = value, .primary_goal = value };
        const content: spec.IdentifiedContent = .{
            .display_name = value,
            .primary_user_story = value,
            .entities = .{ .disposition = .not_applicable, .basis = value },
            .records = &.{
                .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
                .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .proposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
            },
        };
        const source_inputs = try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, records, fixture.context.inputs);
        _ = try checkNativeReferenceReview(a, &fixture, source_inputs, source_inputs.seeds[0].id);
        // Native reference duties do not acquire authored feature duties as
        // unrelated brief fields and complete business records become available.
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, brief));
        for ([_]bool{ false, true }) |generated| {
            const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, if (generated) content else null, if (generated) brief else null);
            var counts: std.EnumArray(std.meta.Tag(authority.Unit), usize) = .initFill(0);
            for ((try authority.build(a, inputs)).requirements) |required| {
                const id = required.seed.id;
                switch (id.unit) {
                    .signal, .token, .conflict => {},
                    else => continue,
                }
                counts.set(std.meta.activeTag(id.unit), counts.get(std.meta.activeTag(id.unit)) + 1);
                const localized = try checkNativeReferenceReview(a, &fixture, inputs, id);
                if (id.unit == .token) {
                    const token_finding = localized.accepted.candidate.review.entries[localized.accepted.candidate.review.entries.len - 1].value;
                    try std.testing.expectEqual(.candidate_omission, token_finding.kind);
                    try std.testing.expectEqual(.unlocalized, std.meta.activeTag(token_finding.loss));
                }
            }
            try std.testing.expectEqual(records.signals.len, counts.get(.signal));
            try std.testing.expectEqual(@as(usize, 1), counts.get(.token));
            try std.testing.expectEqual(records.conflicts.len, counts.get(.conflict));
            for ([_]authority.Id{
                .{ .kind = .reference_meaning, .unit = .{ .source = .{ .ordinal = 999 } }, .slot = .disposition },
                .{ .kind = .reference_meaning, .unit = .{ .signal = .{ .ordinal = 999 } }, .slot = .disposition },
                .{ .kind = .reference_meaning, .unit = .{ .conflict = .{ .ordinal = 999 } }, .slot = .disposition },
                .{ .kind = .preservation, .unit = .{ .token = .{ .ordinal = 999 } }, .slot = .value },
                .{ .kind = .design_decision, .unit = .{ .decision = .{ .ordinal = 1 } }, .slot = .decision },
            }) |foreign| {
                try std.testing.expectError(error.InvalidRequiredAuthority, subjects.project(a, inputs, fixture.context, foreign));
                try std.testing.expectError(error.InvalidRequiredAuthority, subjects.projectLoss(a, inputs, fixture.context, foreign));
                try std.testing.expectError(error.InvalidRequiredAuthority, support.packetFor(a, inputs, fixture.context, .{ .finding = foreign }));
            }
        }
        // The obsolete broad reference assignment is not a second accepted
        // model-facing shape after the native-subject change.
        try std.testing.expectError(error.InvalidJsonDocument, json.decode(subjects.Subject, a, "{\"kind\":\"candidate_support\",\"candidate\":null,\"brief\":null}"));
    }
}

fn checkNativeReferenceReview(a: std.mem.Allocator, fixture: *const Fixture, inputs: @import("domain/required_authority.zig").Inputs, id: @import("domain/required_authority.zig").Id) !@import("domain/specification_support.zig").Source.Collection {
    const authority = @import("domain/required_authority.zig");
    const subjects = @import("domain/specification_review_subject.zig");
    const context = @import("domain/source_omission_context.zig");
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    const records = inputs.references.?;
    const original_evidence = try @import("domain/model_evidence.zig").project(a, records.items.entries);
    const expected: subjects.ReferenceSubject = switch (id.unit) {
        .source => |source| .{ .source = source },
        .signal => |selected| found: {
            for (records.signals) |signal| if (std.meta.eql(signal.id, selected)) break :found .{ .signal = try context.projectSignal(a, records, fixture.context, signal) };
            return error.MissingSignal;
        },
        .token => |selected| found: {
            for (original_evidence.preserved_tokens) |token| if (std.meta.eql(token.id, selected)) break :found .{ .token = token };
            return error.MissingToken;
        },
        .conflict => |selected| found: {
            for (records.conflicts) |conflict| if (std.meta.eql(conflict.id, selected)) break :found .{ .conflict = try context.projectConflict(a, records, fixture.context, conflict) };
            return error.MissingConflict;
        },
        else => return error.NotAReferenceRequirement,
    };
    const projected = try subjects.project(a, inputs, fixture.context, id);
    try std.testing.expect(projected == .reference);
    try std.testing.expectEqualDeep(expected, projected.reference);
    const loss_subject = try subjects.projectLoss(a, inputs, fixture.context, id);
    try std.testing.expect(loss_subject == .reference);
    try std.testing.expectEqualDeep(expected, loss_subject.reference);
    const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = id });
    defer packets.release(packet);
    const correction = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .correction = id });
    defer packets.release(correction);
    try expectSameReviewSubject(a, packet, correction);
    const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value;
    try expectReviewAssessmentScope(.source, a, body, id);
    const wire_subject = try json.decode(subjects.Subject, a, try std.json.Stringify.valueAlloc(a, body.object.get("subject").?, .{}));
    try std.testing.expectEqualDeep(projected, wire_subject);
    try std.testing.expectEqual(@as(usize, 1), body.object.get("sources").?.array.items.len);
    try std.testing.expectEqualStrings(fixture.context.inputs.corpus.sources[0].bytes, body.object.get("sources").?.array.items[0].object.get("text").?.string);
    try std.testing.expectEqual(original_evidence.claims.len, body.object.get("claims").?.array.items.len);
    try std.testing.expectEqual(original_evidence.citations.len, body.object.get("citations").?.array.items.len);
    try std.testing.expectEqual(original_evidence.preserved_tokens.len, body.object.get("preserved_tokens").?.array.items.len);
    const scope = body.object.get("assessment_scope").?.object.get("instruction").?.string;
    try std.testing.expect(std.mem.indexOf(u8, scope, "assigned business purpose") == null);
    try std.testing.expect(std.mem.indexOf(u8, scope, "surrounding candidate") == null);
    const required_scope_fragments: []const []const u8 = switch (expected) {
        .source => &.{ "complete assigned original source", "including meaning with no surviving claim", "Current candidate associations do not limit this assignment" },
        .signal => &.{ "own conditions and obligations", "source-required use and conditions", "does not assign other source duties", "Generated fields and collections have their own assessments" },
        .token => &.{ "source-required use and conditions", "does not require the token to express other source obligations or assess generated fields and collections", "Matching bytes or citations alone do not establish support" },
        .conflict => &.{ "original meanings are incompatible", "a candidate conflict label or explanation is not source truth", "without assessing unrelated generated fields or collections" },
    };
    for (required_scope_fragments) |fragment| try std.testing.expect(std.mem.indexOf(u8, scope, fragment) != null);
    const ledger = try authority.build(a, inputs);
    const index = for (ledger.requirements, 0..) |required, selected| {
        if (std.meta.eql(required.seed.id, id)) break selected;
    } else return error.MissingReferenceRequirement;
    const good = try reviewFor(a, inputs, fixture.context.inputs);
    const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, index);
    @memset(origins, null);
    const prior: ?support.Collection = if (index == 0) null else .{ .pending = .{ .review = .{ .entries = good.entries[0..index] }, .working = true, .origin = null, .origins = origins } };
    const omission = "MOCK supplied source obligation with its required condition.";
    const initial = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, id));
    defer packets.release(initial);
    const omission_value: @import("domain/specification_support_model.zig").Value = .{ .candidate_omission = .{ .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = "MOCK Reviewer supplied this omission; native focus supplies no semantic verdict.", .missing_obligation = omission } };
    const native_findings = try a.dupe(support.Finding, good.entries);
    native_findings[index].value = try @import("domain/specification_support_model.zig").canonical(omission_value, try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, id));
    const bytes = if (authority.assessmentPolicy(inputs.projection) == .advisory) try assignmentWire(support, a, inputs, fixture.context, id, .{ .entries = native_findings }) else try json.encode(@import("domain/specification_support_model.zig").Value, a, omission_value);
    const omitted = try support.collectFocused(a, inputs, fixture.context, prior, initial, bytes, null);
    const candidate = switch (omitted) {
        .accepted => |value| value.candidate,
        .pending => |value| value,
        .rejected => return error.InvalidNativeReferenceReview,
    };
    if (authority.assessmentPolicy(inputs.projection) == .advisory) {
        try std.testing.expect(candidate.pending_localization == null);
        try std.testing.expectError(error.InvalidRequiredAuthority, support.comparisonAssignment(a, inputs, fixture.context, candidate));
        try std.testing.expectError(error.InvalidRequiredAuthority, support.packetForLoss(a, inputs, fixture.context, candidate));
        return omitted;
    }
    const loss_packet = try support.packetForLoss(std.testing.allocator, inputs, fixture.context, candidate);
    defer packets.release(loss_packet);
    const loss_body = (try std.json.parseFromSlice(std.json.Value, a, loss_packet.body(), .{})).value.object;
    const supporting = loss_body.get("supporting_evidence").?.object;
    try std.testing.expectEqualDeep(context.fixedSubject(loss_subject), try json.decode(context.FixedSubject, a, try std.json.Stringify.valueAlloc(a, supporting.get("deficient_subject").?, .{})));
    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, id), supporting.get("target_purpose").?.string);
    try std.testing.expectEqualStrings(omission, loss_body.get("fixed_finding").?.object.get("missing_obligation").?.string);
    const assigned = try support.comparisonAssignment(a, inputs, fixture.context, candidate);
    try std.testing.expectEqualDeep(id, assigned.finding.subject);
    const response = try json.encode(preservation.Response, a, try preservationResponse(a, assigned, .preserved));
    var stale = inputs;
    stale.revision += 1;
    try std.testing.expectError(error.InvalidPreservationComparison, support.admitComparisons(a, stale, fixture.context, candidate, assigned, response));
    const foreign_packet = try packets.create(std.testing.allocator, loss_packet.body(), loss_packet.unit(), .{ .semantic_review = .{ .bytes = "foreign-reference-review" } }, loss_packet.resultDefinition());
    defer packets.release(foreign_packet);
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collectLoss(a, inputs, fixture.context, omitted, foreign_packet, response, null));
    return support.collectLoss(a, inputs, fixture.context, omitted, loss_packet, response, null);
}

test "review repair preserves negative verdicts and repairs only native findings with exact current dependencies" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 5 }, .attempt = .{ .value = 2 } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    const inputs = try completedSupportInputs(&fixture);
    const good = try reviewFor(a, inputs, fixture.context.inputs);
    const findings = try a.dupe(support.Finding, good.entries);
    findings[0].value.kind = .ambiguous;
    findings[0].value.question = "Which deadline should apply? State the duration and starting event.";
    findings[0].value.detail = "The source leaves the deadline ambiguous.";
    try bindReviewClaims(a, inputs, fixture.context, findings);
    try checkDetailRepair(.source, a, inputs, fixture.context, .{ .entries = findings });
    findings[0].value.detail = "";
    const rejected = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
    try std.testing.expectEqual(.invalid_detail, rejected.rejection.selected().?.issue);
    try std.testing.expectError(error.InvalidRequiredAuthority, (@import("actions/specification/apply_specification_support.zig").Action{}).execute(.{ .rejected = rejected }));
    const authorization = try repair.authorize(a, inputs, fixture.context, rejected);
    const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, authorization);
    defer @import("domain/model_input_packet.zig").release(packet);
    const request_body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    const repair_input = request_body.value.object.get("input").?.object;
    try std.testing.expectEqual(@as(usize, 1), repair_input.get("requirements").?.array.items.len);
    try std.testing.expectEqualStrings("A borrower renews a loan.", repair_input.get("sources").?.array.items[0].object.get("text").?.string);
    const replacement = try repair.parse(a, authorization, packet, "{\"detail\":\"Which renewal deadline applies?\",\"question\":\"Which renewal deadline applies? Supply a duration and starting event.\"}");
    const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, authorization, replacement, corrected)).accepted;
    try std.testing.expectEqual(.ambiguous, fixed.inputs.evidence[0].finding);
    try std.testing.expectEqualDeep(corrected, fixed.inputs.review_origins[0].?);
    try std.testing.expectEqualDeep(original, fixed.inputs.review_origins[1].?);
    try std.testing.expectEqualStrings("Which renewal deadline applies?", fixed.inputs.evidence[0].review.?.detail);
    try std.testing.expectEqual(.all_resolved, (try supportDecision(a, fixed.inputs)).result.continuation);
    for (findings[1..], fixed.candidate.review.entries[1..]) |before, after| try std.testing.expectEqualDeep(before, after);
    var stale = rejected.candidate.?;
    stale.revision += 1;
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, inputs, fixture.context, stale, authorization));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, stale, authorization, replacement, corrected));
    // No substantive negative result can enter malformed-review authorization.
    try std.testing.expectError(error.InvalidRequiredAuthority, repair.authorize(a, fixed.inputs, fixture.context, rejected));
    const missing = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[1..] }), original)).rejected;
    try std.testing.expectEqual(.missing_finding, missing.rejection.selected().?.issue);
    const insert = try repair.authorize(a, inputs, fixture.context, missing);
    try std.testing.expect(insert.operation == .insert);
    const complete = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, missing.candidate.?, insert, .{ .finding = good.entries[0].value }, corrected)).accepted;
    try std.testing.expectEqual(good.entries.len, complete.inputs.evidence.len);
    const duplicate = try a.alloc(support.Finding, good.entries.len + 1);
    @memcpy(duplicate[0..good.entries.len], good.entries);
    duplicate[good.entries.len] = good.entries[0];
    const extra = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = duplicate }), original)).rejected;
    const deletion = try repair.authorize(a, inputs, fixture.context, extra);
    try std.testing.expect(deletion.operation == .delete);
    const deduplicated = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, extra.candidate.?, deletion, null, null)).accepted;
    try std.testing.expectEqualDeep(good, deduplicated.candidate.review);
    duplicate[good.entries.len].value.kind = .conflicting;
    const competing = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = duplicate }), original)).rejected;
    try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, competing));
    findings[0].requirement_ordinal = 999;
    const foreign = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
    try std.testing.expectEqual(.unknown_requirement, foreign.rejection.selected().?.issue);
    try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, foreign));
}

test "review diagnostics retain mixed association and value defects in stable order" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "A borrower renews a loan.", "Display `MOCK Hello, World!` and `UTC` on startup." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        var findings = [_]support.Finding{ good.entries[0], good.entries[1], good.entries[1], good.entries[0] };
        findings[0].value.kind = .not_applicable;
        findings[0].value.detail = "\x00";
        findings[0].value.provenance.claim_ids = &.{.{ .ordinal = 999 }};
        findings[2].value.provenance.claim_ids = &.{.{ .ordinal = 999 }};
        findings[3].requirement_ordinal = 999;
        const bytes = try json.encode(support.Review, a, .{ .entries = &findings });
        const rejected = (try collectReview(support, a, inputs, fixture.context, bytes, null)).rejected;
        const issues = rejected.rejection.diagnostics;
        try std.testing.expectEqual(good.entries.len + 4, issues.len);
        try std.testing.expectEqualDeep(rejected.rejection, (try collectReview(support, a, inputs, fixture.context, bytes, null)).rejected.rejection);
        const expected = [_]support.Issue{ .duplicate_requirement, .unknown_requirement, .invalid_decision, .invalid_detail, .invalid_evidence, .invalid_evidence };
        for (expected, issues[0..expected.len]) |issue, actual| try std.testing.expectEqual(issue, actual.issue);
        try std.testing.expectEqual(@as(usize, 2), issues[0].entry_index.?);
        try std.testing.expectEqual(@as(usize, 3), issues[1].entry_index.?);
        for (issues[6..], 3..) |issue, ordinal| {
            try std.testing.expectEqual(.missing_finding, issue.issue);
            try std.testing.expectEqual(ordinal, issue.ordinal.?);
            try std.testing.expect(issue.entry_index == null);
        }
        try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, rejected));
        var tampered = rejected;
        tampered.rejection.diagnostics = issues[0..1];
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, inputs, fixture.context, tampered));
        tampered.rejection.diagnostics = &.{};
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, inputs, fixture.context, tampered));
        const empty = (try collectReview(support, a, inputs, fixture.context, "{\"entries\":[]}", null)).rejected;
        try std.testing.expectEqual(good.entries.len, empty.rejection.diagnostics.len);
        try std.testing.expectError(error.InvalidJsonDocument, collectReview(support, a, inputs, fixture.context, "{", null));
    }
}

test "partial reviews retain all omissions through foreign insertion unchanged correction and bounded recovery" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 24 }, .attempt = .{ .value = 1 } };
    const inserted: Origin = .{ .request = .{ .value = 25 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 26 }, .attempt = .{ .value = 1 } };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "On startup display `MOCK Hello, World!` and the current UTC date and time.", "After renewal display `MOCK Loan renewed!` and label the deadline `Return by`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const initial = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[0..2] }), original)).rejected;
        try std.testing.expectEqual(good.entries.len - 2, initial.rejection.diagnostics.len);
        for (initial.rejection.diagnostics, 3..) |issue, ordinal| {
            try std.testing.expectEqual(.missing_finding, issue.issue);
            try std.testing.expectEqual(ordinal, issue.ordinal.?);
        }
        const insert = try repair.authorize(a, inputs, fixture.context, initial);
        var bad = good.entries[2].value;
        bad.provenance.claim_ids = &.{.{ .ordinal = @intCast(inputs.references.?.items.entries.len + 1) }};
        const second = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, initial.candidate.?, insert, .{ .finding = bad }, inserted)).rejected;
        try std.testing.expectEqual(initial.rejection.diagnostics.len, second.rejection.diagnostics.len);
        try std.testing.expectEqual(.ineligible_claim, second.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(inserted, second.rejection.selected().?.origin.?);
        const correction = try repair.authorize(a, inputs, fixture.context, second);
        const packet = try repair.packet(a, inputs, fixture.context, second.candidate.?, correction);
        defer @import("domain/model_input_packet.zig").release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        try std.testing.expectEqual(@as(usize, 1), body.get("input").?.object.get("requirements").?.array.items.len);
        try std.testing.expect(!body.get("repair").?.object.get("rule").?.object.contains("diagnostics"));
        const unchanged = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, second.candidate.?, correction, correction.operation.replace, corrected)).rejected;
        try std.testing.expectEqual(@as(u64, 3), unchanged.candidate.?.revision);
        try std.testing.expect(!unchanged.candidate.?.last_repair.?.changed);
        try std.testing.expectEqualDeep(corrected, unchanged.rejection.selected().?.origin.?);
        for (unchanged.rejection.diagnostics[1..], 4..) |issue, ordinal| {
            try std.testing.expectEqual(.missing_finding, issue.issue);
            try std.testing.expectEqual(ordinal, issue.ordinal.?);
            try std.testing.expectEqualDeep(original, issue.origin.?);
        }
        try std.testing.expectEqualDeep(second.candidate.?.review, unchanged.candidate.?.review);
        try std.testing.expectEqualDeep(good.entries[0..2], unchanged.candidate.?.review.entries[0..2]);
        for (unchanged.candidate.?.origins[0..2]) |origin| try std.testing.expectEqualDeep(original, origin.?);
        // A valid selection still cannot admit a candidate with missing siblings.
        const remaining = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, second.candidate.?, correction, .{ .selection = .{ .provenance = good.entries[2].value.provenance, .source_ids = good.entries[2].value.source_ids } }, corrected)).rejected;
        try std.testing.expectEqual(good.entries.len - 3, remaining.rejection.diagnostics.len);
        try std.testing.expectEqual(@as(u32, 4), remaining.rejection.selected().?.ordinal.?);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, remaining.candidate.?, correction, correction.operation.replace, corrected));
        // Two independent omissions can recover through two existing atomic calls.
        const bounded = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[2..] }), original)).rejected;
        const one = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, bounded.candidate.?, try repair.authorize(a, inputs, fixture.context, bounded), .{ .finding = good.entries[0].value }, inserted)).rejected;
        try std.testing.expectEqual(@as(usize, 1), one.rejection.diagnostics.len);
        const complete = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, one.candidate.?, try repair.authorize(a, inputs, fixture.context, one), .{ .finding = good.entries[1].value }, corrected)).accepted;
        try std.testing.expectEqualDeep(good.entries[2..], complete.candidate.review.entries[0 .. good.entries.len - 2]);
        for (complete.candidate.origins[0 .. good.entries.len - 2]) |origin| try std.testing.expectEqualDeep(original, origin.?);
        try support.validateStored(a, complete.inputs, fixture.context.inputs);
    }
}

test "empty principle review can recover every assigned finding without losing earlier results" {
    const source_review = @import("domain/specification_support.zig").Source;
    const policy_review = @import("domain/specification_support.zig").Contract(.principles);
    const repair = @import("domain/specification_support_repair.zig").Contract(.principles);
    const authority = @import("domain/required_authority.zig");
    const progress = @import("domain/specification_review.zig");
    const sessions = @import("domain/specification_session.zig");
    const json = @import("domain/model_candidate_json.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    for ([_][2][]const u8{
        .{ "On startup display `MOCK Hello, World!` and the current UTC date and time.", "User-facing output must be readable.\n" },
        .{ "After renewal display `MOCK Loan renewed!` and label the deadline `Return by`.", "Loan notices must be concise.\n" },
    }) |example| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, example[0]);
        defer fixture.deinit();
        const current = try completedFixture(&fixture, false);
        const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
        var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
        inputs.revision = current.revision;
        const source = try collectReview(source_review, a, inputs, fixture.context, try json.encode(source_review.Review, a, try reviewFor(a, inputs, fixture.context.inputs)), null);
        const policies = try @import("test_fixtures/principles.zig").registry(a, example[1]);
        const advanced = try progress.advance(a, .{ .source = source }, policies);
        try std.testing.expectEqual(.more, advanced.outcome);
        const policy_inputs = advanced.progress.pending.inputs;
        const ledger = try authority.build(a, policy_inputs);
        try std.testing.expect(ledger.requirements.len > 2);
        const findings = try a.alloc(policy_review.Finding, ledger.requirements.len);
        for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = .compatible, .citations = &.{}, .detail = "" } };
        const original: Origin = .{ .request = .{ .value = 70 }, .attempt = .{ .value = 1 } };
        var result = try collectReview(policy_review, a, policy_inputs, fixture.context, "{\"entries\":[]}", original);
        for (findings, 0..) |finding, index| {
            try std.testing.expect(result == .rejected);
            try std.testing.expectEqual(findings.len - index, result.rejected.rejection.diagnostics.len);
            try std.testing.expectEqual(@as(u32, @intCast(index + 1)), result.rejected.rejection.selected().?.ordinal.?);
            const next_origin: Origin = .{ .request = .{ .value = @intCast(71 + index) }, .attempt = .{ .value = 1 } };
            const authorization = try repair.authorize(a, policy_inputs, fixture.context, result.rejected);
            result = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), policy_inputs, fixture.context, result.rejected.candidate.?, authorization, .{ .finding = finding.value }, next_origin);
            const candidate = if (result == .accepted) result.accepted.candidate else result.rejected.candidate.?;
            try std.testing.expectEqual(index + 1, candidate.review.entries.len);
            try std.testing.expectEqualDeep(findings[0 .. index + 1], candidate.review.entries);
            try std.testing.expectEqualDeep(original, candidate.origin.?);
            for (candidate.origins, 0..) |origin, prior| try std.testing.expectEqualDeep(Origin{ .request = .{ .value = @intCast(71 + prior) }, .attempt = .{ .value = 1 } }, origin.?);
        }
        try std.testing.expect(result == .accepted);
        try policy_review.validateStored(a, result.accepted.inputs, fixture.context.inputs);
        const complete = try progress.advance(a, .{ .principles = .{ .pending = advanced.progress.pending, .result = result } }, policies);
        try std.testing.expectEqual(.complete, complete.outcome);
        try std.testing.expect(complete.progress.source.accepted.inputs.principle_assessment != null);
        var focused: ?policy_review.Collection = null;
        var index: usize = 0;
        while (index < findings.len) {
            const selected = try policy_review.nextSubject(a, policy_inputs, focused);
            try std.testing.expectEqualDeep(ledger.requirements[index].seed.id, selected);
            const packet = try policy_review.packetFor(a, policy_inputs, fixture.context, policy_review.assignmentScope(policy_inputs, selected));
            defer @import("domain/model_input_packet.zig").release(packet);
            try std.testing.expectEqualStrings("principle_assignment_findings", packet.resultDefinition().?.bytes);
            const body = try assignmentWire(policy_review, a, policy_inputs, fixture.context, selected, .{ .entries = findings });
            if (index == 0) try rejectForeignReviewPackets(.principles, a, policy_inputs, fixture.context, packet, body);
            if (index == 0) try expectExactMembers(a, packet, body, "findings", "requirement_ordinal");
            focused = try policy_review.collectFocused(a, policy_inputs, fixture.context, focused, packet, body, .{ .request = .{ .value = @intCast(300 + index) }, .attempt = .{ .value = 1 } });
            index += (try policy_review.assignmentSubjects(a, policy_inputs, selected)).len;
            if (index < findings.len) try std.testing.expect(focused.? == .pending);
        }
        try std.testing.expect(focused.? == .accepted);
        try std.testing.expectEqualDeep(result.accepted.inputs.evidence, focused.?.accepted.inputs.evidence);
        try policy_review.validateStored(a, focused.?.accepted.inputs, fixture.context.inputs);
    }
}

test "focused source review repairs one finding and retains native assignment identity" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    for ([_][]const u8{
        "On startup display `MOCK Hello, World!` and the current UTC date and time.",
        "After renewal display `MOCK Loan renewed!` and label the deadline `Return by`.",
    }) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const ledger = try authority.build(a, inputs);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        var current: ?support.Collection = null;
        var first_slot: ?[]const u8 = null;
        var index: usize = 0;
        while (index < good.entries.len) {
            const selected = try support.nextSubject(a, inputs, current);
            try std.testing.expectEqualDeep(ledger.requirements[index].seed.id, selected);
            const members = try support.assignmentSubjects(a, inputs, selected);
            const packet = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, selected));
            defer packets.release(packet);
            const slot = packet.unit().semantic_review.review_slot_id.bytes;
            if (first_slot) |first| {
                try std.testing.expect(!std.mem.eql(u8, first, slot));
            } else first_slot = try a.dupe(u8, slot);
            const correction = try support.packetFor(a, inputs, fixture.context, .{ .correction = selected });
            defer packets.release(correction);
            try std.testing.expectEqualStrings(try @import("domain/specification_support.zig").reviewSlot(a, inputs, selected), correction.unit().semantic_review.review_slot_id.bytes);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            try std.testing.expectEqual(members.len, body.get("requirements").?.array.items.len);
            const original: Origin = .{ .request = .{ .value = @intCast(100 + index) }, .attempt = .{ .value = 1 } };
            const proposed = try a.dupe(support.Finding, good.entries);
            if (index == 0) proposed[1].value.source_ids = &.{.{ .ordinal = @intCast(fixture.context.inputs.corpus.sources.len + 1) }};
            const wire = try assignmentWire(support, a, inputs, fixture.context, selected, .{ .entries = proposed });
            if (index == 0) try rejectForeignReviewPackets(.source, a, inputs, fixture.context, packet, wire);
            current = try support.collectFocused(a, inputs, fixture.context, current, packet, wire, original);
            if (index == 0) {
                try std.testing.expect(current.? == .rejected);
                const authorization = try repair.authorize(a, inputs, fixture.context, current.?.rejected);
                const candidate = current.?.rejected.candidate.?;
                const repaired: Origin = .{ .request = .{ .value = 200 }, .attempt = .{ .value = 1 } };
                current = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), inputs, fixture.context, candidate, authorization, .{ .selection = .{ .provenance = good.entries[1].value.provenance, .source_ids = good.entries[1].value.source_ids } }, repaired);
                try std.testing.expect(current.? == .pending);
                try std.testing.expectEqualDeep(original, current.?.pending.origin.?);
                try std.testing.expectEqualDeep(repaired, current.?.pending.origins[1].?);
                try std.testing.expectEqualDeep(original, current.?.pending.origins[0].?);
                try std.testing.expectEqualDeep(original, current.?.pending.origins[2].?);
            }
            index += members.len;
            const candidate = if (current.? == .accepted) current.?.accepted.candidate else current.?.pending;
            try std.testing.expectEqualDeep(good.entries[0..index], candidate.review.entries);
            if (index < good.entries.len) try std.testing.expect(current.? == .pending);
        }
        try std.testing.expect(current.? == .accepted);
        try support.validateStored(a, current.?.accepted.inputs, fixture.context.inputs);
    }
}

fn rejectForeignReviewPackets(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, expected: *const @import("domain/model_input_packet.zig").Packet, response: []const u8) !void {
    const packets = @import("domain/model_input_packet.zig");
    const review = @import("domain/specification_support.zig").Contract(purpose);
    for (0..6) |mutation| {
        var body = expected.body();
        var unit = expected.unit();
        var binding = expected.purpose();
        var definition = expected.resultDefinition();
        switch (mutation) {
            0 => body = "{}",
            1 => unit = .workflow_step,
            2 => binding = .{ .semantic_review = .{ .bytes = "foreign-review" } },
            3 => binding = .initial_generation,
            4 => definition = .{ .bytes = "foreign-result" },
            5 => definition = null,
            else => unreachable,
        }
        const foreign = try packets.create(a, body, unit, binding, definition);
        defer packets.release(foreign);
        try std.testing.expectError(error.InvalidRequiredAuthority, review.collectFocused(a, inputs, context, null, foreign, response, null));
    }
}

test "conflict review exact evidence survives repair and rejects corrupt readback" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try @import("reference_reconciliation_test.zig").prepare(a, &.{ "Renew the loan.\n", "Reject the renewal.\n", "Issue a receipt.\n" });
    defer fixture.deinit();
    const global = try references.summaries(a, try references.initialize(a, fixture.inputs, fixture.extracted, 2), fixture.context());
    var proposal = try references.global(a, global);
    const dispositions = try a.dupe(references.r.ClaimDispositionProposal, proposal.claim_dispositions);
    dispositions[0].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[1].claim_id} } };
    dispositions[1].disposition = .{ .conflicting = .{ .related_claim_ids = &.{dispositions[0].claim_id} } };
    proposal.claim_dispositions = dispositions;
    proposal.signals = proposal.signals[2..];
    proposal.conflicts = &.{.{ .claim_ids = &.{ dispositions[0].claim_id, dispositions[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The outcomes disagree." } }} } }};
    const accounted = (try references.finish(a, global, proposal, fixture.context())).valid;
    const context: provenance.Context = .{ .inputs = fixture.inputs, .references = accounted, .registry = fixture.context().registry, .current = fixture.context().current };
    const inputs = try @import("domain/specification_authority.zig").project(a, fixture.inputs.corpus.feature_id, accounted, null, null);
    const allowed_sources = try @import("domain/specification_support_evidence.zig").sourceChoices(a, fixture.inputs);
    try std.testing.expectEqualDeep(&[_]@import("domain/reference_identity.zig").SourceId{ .{ .ordinal = 1 }, .{ .ordinal = 2 }, .{ .ordinal = 3 } }, allowed_sources);
    const ledger = try authority.build(a, inputs);
    const good = try reviewFor(a, inputs, fixture.inputs);
    const index = for (ledger.requirements, 0..) |requirement, i| {
        if (requirement.seed.id.unit == .conflict) break i;
    } else return error.TestExpectedEqual;
    const accepted = (try collectReview(support, a, inputs, context, try json.encode(support.Review, a, good), null)).accepted;
    try support.validateStored(a, accepted.inputs, fixture.inputs);
    try std.testing.expectEqual(.invalid, (try supportDecision(a, accepted.inputs)).result.continuation);
    const negative = try a.dupe(support.Finding, good.entries);
    negative[index].value.kind = .conflicting;
    negative[index].value.detail = "One source requires renewal; the other rejects it.";
    negative[index].value.question = "Should this loan be renewed or rejected? Choose the required outcome.";
    const genuine = (try collectReview(support, a, inputs, context, try json.encode(support.Review, a, .{ .entries = negative }), null)).accepted;
    try std.testing.expectEqual(.needs_user, (try supportDecision(a, genuine.inputs)).result.continuation);
    const claims = good.entries[index].value.provenance.claim_ids;
    const wrong = [_][]const references.r.ClaimId{ &.{}, claims[0..1], &.{dispositions[2].claim_id}, &.{ claims[0], claims[0] } };
    const issues = [_]@import("domain/specification_support_evidence.zig").Issue{ .missing_claims, .wrong_claim_set, .ineligible_claim, .invalid_selection };
    for (wrong, issues) |selection_ids, expected| {
        const findings = try a.dupe(support.Finding, good.entries);
        findings[index].value.provenance.claim_ids = selection_ids;
        const rejected = (try collectReview(support, a, inputs, context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected;
        try std.testing.expectEqual(@as(usize, 1), rejected.rejection.diagnostics.len);
        try std.testing.expectEqual(expected, rejected.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(allowed_sources, rejected.rejection.selected().?.evidence.?.rule.eligible_source_ids);
        const authorization = try repair.authorize(a, inputs, context, rejected);
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = good.entries[index].value.provenance, .source_ids = &.{} } }, null)).accepted;
        try std.testing.expectEqualDeep(good, fixed.candidate.review);
        try support.validateStored(a, fixed.inputs, fixture.inputs);
        var corrupt = accepted.inputs;
        const proofs = try a.dupe(authority.Evidence, corrupt.evidence);
        proofs[index].review.?.provenance.claim_ids = selection_ids;
        corrupt.evidence = proofs;
        try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, corrupt, fixture.inputs));
    }
}

test "record association preserves accepted multi-claim order and rejects unbound selections" {
    const binding = @import("domain/specification_source_binding.zig");
    const refs = @import("domain/reference_support.zig");
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Renew the loan and retain its deadline.", "Confirm the booking and retain its arrival date." }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, source, 2);
        defer fixture.deinit();
        const original = fixture.context.references.records.assignments.checked.prior.prior;
        var proposed = original.proposal;
        const claims = try a.alloc(r.ClaimId, 2);
        for (original.input.items, claims) |item, *id| id.* = item.claim.id;
        const signal = proposed.signals[0];
        proposed.signals = &.{.{ .claim_ids = claims, .content = signal.content }};
        const accepted = (try references.finish(a, original.input, proposed, .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current })).valid;
        const records = refs.records(accepted);
        try binding.validate(records, fixture.context.inputs);
        const bound = try binding.record(a, records, fixture.context.inputs, 0);
        try std.testing.expectEqualDeep(records.signals[0].id, bound.records.signal);
        try std.testing.expectEqualDeep(claims, bound.records.selection.claim_ids);
        try std.testing.expectError(error.InvalidSpecificationBinding, binding.record(a, records, fixture.context.inputs, 1));
        const chosen = try binding.resolveGroups(a, records, fixture.context.inputs, &.{records.signals[0].id}, .content);
        try std.testing.expectEqualDeep(claims, chosen.selection.claim_ids);
        const value = try fixture.proposal(source);
        var wrong = value;
        wrong.source_group_ids = chosen.source_group_ids;
        wrong.provenance.claim_ids = claims[0..1];
        try std.testing.expectError(error.InvalidSpecification, provenance.checkAttributed(.model, a, text.validator, .{ .inputs = fixture.context.inputs, .references = accepted, .registry = fixture.context.registry, .current = fixture.context.current }, wrong, .spec_story));
    }
}

test "support reviews retain original sources and discarded or misclassified token decisions" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `Renewal accepted!` and provide a return deadline.", "Display `MOCK Booking confirmed!` and provide the arrival date." }) |source| {
        for ([_]?@import("domain/structured_tokens.zig").Kind{ null, .visual_typography, .business_exact_string }) |kind| {
            var fixture = try Fixture.initClassified(a, source, kind);
            defer fixture.deinit();
            const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
            const packet = try reviewPacketAt(support, a, inputs, fixture.context, 0);
            defer @import("domain/model_input_packet.zig").release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            try std.testing.expectEqualStrings("source_preservation", body.value.object.get("subject").?.object.get("kind").?.string);
            try std.testing.expect(body.value.object.get("candidate_revision") == null);
            try std.testing.expect(body.value.object.get("candidate") == null);
            const row = body.value.object.get("requirements").?.array.items[0].object;
            try std.testing.expect(row.get("contract_version") == null and row.get("requirement") == null);
            try std.testing.expect(row.get("slot") == null and row.get("unit") == null and row.get("member") == null);
            try std.testing.expect(row.get("task") != null and row.get("evidence").?.object.get("eligible_claim_ids") != null);
            try std.testing.expectEqualStrings(source, body.value.object.get("sources").?.array.items[0].object.get("text").?.string);
            const classification = body.value.object.get("extraction").?.array.items[0].object.get("token_classifications").?.array.items[0];
            try std.testing.expectEqualStrings(if (kind == null) "irrelevant" else "preserve", classification.object.get("decision").?.object.get("kind").?.string);
            // Both correct and incorrect semantic choices remain inspectable;
            // allowed labels alone do not decide whether a review passes.
            const good = try reviewFor(a, inputs, fixture.context.inputs);
            _ = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, good), null)).accepted;
            const findings = try a.dupe(support.Finding, good.entries);
            findings[0].value = .{ .kind = .candidate_omission, .missing_obligation = fixture.context.inputs.corpus.sources[0].bytes, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = "The extraction omitted the source-required confirmation and follow-up date." };
            const omitted = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
            try std.testing.expectEqual(.invalid, (try supportDecision(a, omitted)).result.continuation);
            try std.testing.expectEqualStrings(findings[0].value.detail, omitted.evidence[0].review.?.detail);
            try std.testing.expectEqualDeep(findings[0].value.source_ids, omitted.evidence[0].review.?.source_ids);
            var foreign = fixture.context;
            foreign.inputs.corpus.state_id.bytes = "foreign-state";
            try std.testing.expect((try collectReview(support, a, inputs, foreign, try json.encode(support.Review, a, good), null)) == .rejected);
            const ledger = try authority.build(a, inputs);
            try std.testing.expect(ledger.requirements.len >= 8);
        }
    }
}

test "review-purpose eligibility retains native duplicate token evidence without widening business provenance" {
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const snapshot = @import("domain/reference_snapshot.zig");
    const r = references.r;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Hello, World!", "Renewal accepted!" }) |value| {
        var fixture = try Fixture.init(a, try std.fmt.allocPrint(a, "Display `{s}` on startup and repeat `{s}` after recovery.", .{ value, value }));
        defer fixture.deinit();
        const items = try provenance.items(fixture.context);
        var originals: std.ArrayList(r.extraction.Claim) = .empty;
        for (items.entries) |item| if (item.claim.content == .preserved_token) try originals.append(a, item.claim);
        try std.testing.expectEqual(@as(usize, 2), originals.items.len);
        const first = originals.items[0];
        const duplicate = originals.items[1];
        const dispositions = fixture.context.references.records.assignments.checked.prior.prior.dispositions;
        try std.testing.expectEqual(.retained, dispositions[first.id.ordinal - 1].disposition);
        try std.testing.expectEqual(.duplicate, dispositions[duplicate.id.ordinal - 1].disposition);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{first.id}, dispositions[duplicate.id.ordinal - 1].related_claim_ids);
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const accepted = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, good), null)).accepted.inputs;
        try std.testing.expectEqual(.all_resolved, (try supportDecision(a, accepted)).result.continuation);
        const token_requirement: authority.Id = .{ .kind = .preservation, .unit = .{ .token = duplicate.content.preserved_token.value.id }, .slot = .value };
        try std.testing.expect(admission.eligible(inputs.references.?, token_requirement, duplicate.id));
        const required = try admission.requirements(a, inputs, fixture.context.inputs, token_requirement);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{duplicate.id}, required.rule(.supported, .{ .unlocalized = .{} }).fixedClaims().?);
        const retained = for (accepted.evidence) |entry| {
            if (std.meta.eql(entry.requirement, token_requirement)) break entry;
        } else return error.MissingTokenPreservationEvidence;
        try std.testing.expectEqualDeep(&[_]r.ClaimId{duplicate.id}, retained.review.?.provenance.claim_ids);
        _ = try provenance.select(a, fixture.context, .{ .claim_ids = &.{first.id}, .clarification_response_ids = &.{} });
        try std.testing.expectError(error.InvalidSpecification, provenance.select(a, fixture.context, .{ .claim_ids = &.{duplicate.id}, .clarification_response_ids = &.{} }));

        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
        const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
        const saved = try snapshot.build(.{ .bytes = "references" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
        try snapshot.validate(a, saved);
        for ([_]r.Disposition{ .superseded, .conflicting }) |kind| {
            var forged = saved;
            const changed = try a.dupe(r.ClaimDisposition, saved.dispositions);
            changed[duplicate.id.ordinal - 1].disposition = kind;
            changed[duplicate.id.ordinal - 1].related_claim_ids = &.{first.id};
            forged.dispositions = changed;
            const rejected = (try @import("domain/reference_disposition_validation.zig").check(a, items, changed)).invalid;
            try std.testing.expectEqual(.native_token_disposition, rejected.issue.expected.constraint);
            try std.testing.expectError(error.InvalidReferenceSnapshot, snapshot.validate(a, forged));
        }
    }
}

test "published support validates without an execution ledger and rejects erased or foreign review authority" {
    const support = @import("domain/specification_support.zig").Source;
    const state = @import("domain/specification_state.zig");
    const sessions = @import("domain/specification_session.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower receives a renewal receipt.");
    defer fixture.deinit();
    const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
    const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
    const current = try completedFixture(&fixture, false);
    const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
    var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
    inputs.revision = current.revision;
    const reviewed = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, try reviewFor(a, inputs, fixture.context.inputs)), .{ .request = .{ .value = 500 }, .attempt = .{ .value = 1 } })).accepted.inputs;
    const decision = try supportDecision(a, reviewed);
    const value: state.State = .{
        .schema = state.schema,
        .principle_assessment = try @import("test_fixtures/principles.zig").emptyAssessment(a, reviewed),
        .feature = current.feature,
        .revision = 1,
        .stage = .specified,
        .reference = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "first" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract),
        .brief = inputs.brief.?,
        .content = assigned.content,
        .id_ledger = assigned.ledger,
        .coverage = try @import("domain/specification_coverage.zig").validate(a, fixture.context.references, inputs.brief.?, assigned.content),
        .clarification = .{ .state_ordinal = 1, .revision = 1 },
        .review = .{ .candidate_revision = inputs.revision, .seeds = reviewed.seeds, .evidence = reviewed.evidence, .candidates = reviewed.candidates, .observations = decision.observations, .result = decision.result, .advice_stop = reviewed.advice_stop },
    };
    // A later clarification pause replaces prior completion and preserves ID allocation.
    const cf = @import("test_fixtures/clarification_inputs.zig");
    const c = @import("domain/clarification_inputs.zig");
    var clarification_record = cf.record("S01");
    clarification_record.authority = &.{.{ .reference = value.reference.inputs.corpus.state_id }};
    var pending_questions = cf.state(&.{clarification_record});
    pending_questions.feature_id = current.feature.bytes;
    const pending = try @import("domain/incomplete_specification.zig").build(a, .{ .captured = try std.json.Stringify.valueAlloc(a, value, .{}), .value = .{ .specified = value } }, value.reference, try c.validate(.{ .value = pending_questions }, current.feature), contracts.port());
    try std.testing.expectEqual(value.revision + 1, pending.revision);
    try std.testing.expectEqualDeep(value.id_ledger, pending.id_ledger);
    const pending_prior = try state.parse(a, try std.json.Stringify.valueAlloc(a, pending, .{}), current.feature, contracts.port());
    try std.testing.expect(pending_prior.specified() == null);
    const restarted = (try (@import("actions/specification/initialize_specification_generation.zig").Action{}).execute(a, current.feature, fixture.context, pending_prior)).ready;
    try std.testing.expectEqual(@as(usize, 0), restarted.completed);
    try std.testing.expectEqualDeep(value.id_ledger, restarted.starting_ledger);
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    var fresh = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer fresh.deinit();
    const restored = (try state.parse(fresh.allocator(), bytes, current.feature, contracts.port())).specified().?;
    try std.testing.expectEqualStrings(bytes, try std.json.Stringify.valueAlloc(a, restored, .{}));
    const document = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    try std.testing.expect(document.value.object.get("review").?.object.get("origin") == null);
    try std.testing.expectError(error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE, state.parse(a, bytes, current.feature, null));
    for (0..10) |mode| {
        var broken = value;
        var binding = contract;
        const entries = try a.dupe(@import("domain/reference_extraction_contract.zig").Extraction, binding.extractions);
        binding.extractions = entries;
        switch (mode) {
            0 => broken.reference.extraction_contract = null,
            1 => binding.workflow_id = .{ .bytes = "foreign-workflow" },
            2 => binding.workflow_version += 1,
            3 => entries[0].node = .{ .bytes = "foreign-node" },
            4 => entries[0].assembly_node = .{ .bytes = "foreign-assembly" },
            5 => entries[0].result_schema.bytes = "{}",
            6 => entries[0].composition.bytes = "{}",
            7 => entries[0].parts = &.{},
            8 => {
                const parts = try a.dupe(@import("domain/reference_extraction_contract.zig").Part, entries[0].parts);
                parts[0].parameters = &.{};
                entries[0].parts = parts;
            },
            9 => binding.extractions = &.{},
            else => unreachable,
        }
        if (mode != 0) broken.reference.extraction_contract = binding;
        try std.testing.expectError(error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE, state.parse(a, try std.json.Stringify.valueAlloc(a, broken, .{}), current.feature, contracts.port()));
    }
    for (0..22) |mode| {
        var broken = value;
        if (mode == 0) {
            broken.review.seeds = &.{};
            broken.review.evidence = &.{};
            broken.review.candidates = &.{};
            broken.review.observations.entries = &.{};
            broken.review.result.entries = &.{};
        } else if (mode == 1) {
            const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, value.review.evidence);
            proofs[0].review.?.provenance.claim_ids = &.{.{ .ordinal = 999 }};
            broken.review.evidence = proofs;
        } else if (mode == 2) {
            broken.review.candidate_revision += 1;
        } else if (mode == 3) {
            const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, value.review.evidence);
            proofs[0].review = null;
            broken.review.evidence = proofs;
        } else if (mode == 4) {
            broken.coverage.accounts = &.{};
        } else if (mode == 5) {
            broken.brief.title.provenance.citation_ids = &.{};
        } else if (mode == 6) {
            broken.content.primary_user_story.provenance.claim_ids = &.{};
        } else if (mode == 7) {
            broken.content.primary_user_story.value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 999 } } }} };
        } else if (mode == 8) {
            const sources = try a.dupe(@TypeOf(value.reference.inputs.corpus.sources[0]), value.reference.inputs.corpus.sources);
            sources[0].bytes = try std.mem.concat(a, u8, &.{ sources[0].bytes, "Unaccounted requirement." });
            broken.reference.inputs.corpus.sources = sources;
        } else if (mode == 9 or mode == 10) {
            const dispositions = try a.dupe(@import("domain/reference_reconciliation.zig").ClaimDisposition, value.reference.dispositions);
            if (mode == 9) dispositions[0].related_claim_ids = &.{dispositions[0].claim_id} else dispositions[0].disposition = .duplicate;
            broken.reference.dispositions = dispositions;
        } else if (mode == 11) {
            const signals = try a.dupe(@import("domain/reference_reconciliation.zig").Signal, value.reference.signals);
            signals[0].value.citation_ids = &.{};
            broken.reference.signals = signals;
        } else if (mode == 12) {
            broken.reference.signals = &.{};
        } else if (mode == 13) {
            const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, value.review.evidence);
            proofs[0].review.?.detail = "\x00";
            broken.review.evidence = proofs;
        } else if (mode == 14 or mode == 21) {
            broken.schema = if (mode == 14) "specification-state/v15" else "specification-state/v16";
        } else if (mode == 15 or mode == 16 or mode == 18 or mode == 19) {
            const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, value.review.evidence);
            try std.testing.expect(proofs[0].resolution == .assessment);
            switch (mode) {
                15 => proofs[0].resolution.assessment.candidate.revision += 1,
                16 => {
                    const candidate = proofs[0].resolution.assessment.candidate;
                    proofs[0].resolution = .{ .supported_candidate = candidate };
                },
                18 => proofs[0].method = .deterministic,
                19 => proofs[0].resolution.assessment.not_applicable = .no_business_data,
                else => unreachable,
            }
            broken.review.evidence = proofs;
        } else {
            const authority = @import("domain/required_authority.zig");
            const entries = try a.dupe(authority.Entry, value.review.result.entries);
            try std.testing.expect(entries[0].outcome == .assessment_complete);
            if (mode == 17) {
                const candidate = entries[0].outcome.assessment_complete.candidate;
                entries[0].outcome = .{ .resolved_exactly_one = .{ .supported_candidate = candidate } };
            } else {
                entries[0].outcome.assessment_complete.candidate.ordinal += 1;
            }
            broken.review.result.entries = entries;
        }
        try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, broken, .{}), current.feature, contracts.port()));
    }
}

test "source review scopes distinguish field coverage and joint record conditions without granting packet authority" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    for ([_][5][]const u8{
        .{ "Display clinic opening hours. When an appointment is cancelled, notify the patient only after verifying contact details.", "Display clinic opening hours.", "Contact details have been verified.", "An appointment is cancelled.", "Notify the patient." },
        .{ "Issue a sender receipt after successful delivery. Do not dispatch a parcel when its label is unreadable; identify it manually before dispatch.", "Issue a sender receipt after successful delivery.", "The parcel label is unreadable.", "Dispatch is requested.", "Do not dispatch until manual identification completes." },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, example[0], null, true, example[1], 1);
        defer fixture.deinit();
        const local = try fixture.value(example[1]);
        const given = try fixture.value(example[2]);
        const when = try fixture.value(example[3]);
        const then = try fixture.value(example[4]);
        const records: []const spec.IdentifiedRecord = &.{
            .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = given.value, .when = when.value, .then = then.value } }, .source_group_ids = local.source_group_ids, .provenance = local.provenance } },
            .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .proposal = .{ .content = .{ .functional_requirement = .{ .text = local.value } }, .source_group_ids = local.source_group_ids, .provenance = local.provenance } },
        };
        const content: spec.IdentifiedContent = .{ .display_name = local, .primary_user_story = local, .entities = .{ .disposition = .not_applicable, .basis = local }, .records = records };
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, content, .{ .title = local, .description = local, .primary_goal = local });
        const ledger = try authority.build(a, inputs);
        const field_id = try support.nextSubject(a, inputs, null);
        try std.testing.expect(field_id.unit == .feature and field_id.slot == .display_name);
        const collection_id = for (ledger.requirements) |requirement| {
            if (requirement.seed.id.unit == .feature and requirement.seed.id.slot == .functional_requirements) break requirement.seed.id;
        } else return error.MissingCollectionRequirement;
        const field_packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = field_id });
        defer packets.release(field_packet);
        const collection_packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = collection_id });
        defer packets.release(collection_packet);
        const field_body = (try std.json.parseFromSlice(std.json.Value, a, field_packet.body(), .{})).value;
        const collection_body = (try std.json.parseFromSlice(std.json.Value, a, collection_packet.body(), .{})).value;
        for ([_]*packets.Packet{ field_packet, collection_packet }) |packet| {
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value;
            try expectReviewAssessmentScope(.source, a, body, if (packet == field_packet) field_id else collection_id);
            try std.testing.expectEqualStrings(example[0], body.object.get("sources").?.array.items[0].object.get("text").?.string);
            // The original source still contains duties omitted by this mock
            // extraction. Packet presentation supplies no semantic verdict.
            try std.testing.expectEqual(@as(usize, 1), body.object.get("claims").?.array.items.len);
            try std.testing.expect(std.mem.indexOf(u8, try std.json.Stringify.valueAlloc(a, body.object.get("claims").?, .{}), example[2]) == null);
            const correction = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .correction = if (packet == field_packet) field_id else collection_id });
            defer packets.release(correction);
            try expectSameReviewSubject(a, packet, correction);
        }
        const field_scope = field_body.object.get("assessment_scope").?.object;
        const collection_scope = collection_body.object.get("assessment_scope").?.object;
        try std.testing.expect(std.mem.indexOf(u8, field_scope.get("instruction").?.string, "qualifying triggers, conditions, negation and obligation strength") != null);
        try std.testing.expect(std.mem.indexOf(u8, field_scope.get("instruction").?.string, "Unrelated feature duties") != null);
        try std.testing.expect(std.mem.indexOf(u8, collection_scope.get("instruction").?.string, "complete source-required coverage") != null);
        try std.testing.expect(std.mem.indexOf(u8, collection_scope.get("instruction").?.string, "obligations absent from current claims or associations") != null);
        try std.testing.expect(std.mem.indexOf(u8, collection_scope.get("original_sources").?.string, "Candidate assertions cannot establish source requirements") != null);
        try std.testing.expect(std.mem.indexOf(u8, collection_scope.get("derived_evidence").?.string, "omissions or labels do not remove original obligations") != null);
        try std.testing.expectEqualStrings(example[1], field_body.object.get("subject").?.object.get("text").?.string);
        const members = collection_body.object.get("subject").?.object.get("records").?.array.items;
        try std.testing.expectEqual(@as(usize, 1), members.len);
        const member = try json.decode(spec.CapturedRecord, a, try std.json.Stringify.valueAlloc(a, members[0], .{}));
        try std.testing.expectEqualDeep(records[1].id, member.id.?);
        try std.testing.expect(member.content == .functional_requirement);
        try std.testing.expectEqualStrings(example[1], member.content.functional_requirement.text.bytes);
        for ([_]authority.Slot{ .given, .when, .then }, example[2..]) |slot, expected| {
            const id = for (ledger.requirements) |requirement| {
                if (requirement.seed.id.unit == .record and requirement.seed.id.unit.record.kind == .acceptance_criterion and requirement.seed.id.slot == slot) break requirement.seed.id;
            } else return error.MissingAcceptanceCriterionRequirement;
            const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = id });
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value;
            try expectReviewAssessmentScope(.source, a, body, id);
            try std.testing.expectEqualStrings(expected, body.object.get("subject").?.object.get("text").?.string);
            try std.testing.expectEqualDeep(records[0], try json.decode(spec.IdentifiedRecord, a, try std.json.Stringify.valueAlloc(a, body.object.get("subject").?.object.get("record").?, .{})));
            const instruction = body.object.get("assessment_scope").?.object.get("instruction").?.string;
            try std.testing.expect(std.mem.indexOf(u8, instruction, "Sibling fields may supply joint conditions and results") != null);
            try std.testing.expect(std.mem.indexOf(u8, instruction, "each field need not repeat the whole flow") != null);
            try expectRecordReviewPurpose(.source, a, packet, id);
            const correction = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .correction = id });
            defer packets.release(correction);
            try expectSameReviewSubject(a, packet, correction);
        }
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const response = try sourceReviewWire(a, inputs, fixture.context, field_id, good.entries[0].value);
        var changed_scope = (try std.json.parseFromSlice(std.json.Value, a, field_packet.body(), .{})).value;
        try changed_scope.object.put(a, "assessment_scope", collection_body.object.get("assessment_scope").?);
        for ([_][]const u8{ try std.json.Stringify.valueAlloc(a, changed_scope, .{}), collection_packet.body() }) |body| {
            const forged = try packets.create(std.testing.allocator, body, field_packet.unit(), field_packet.purpose(), field_packet.resultDefinition());
            defer packets.release(forged);
            try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, inputs, fixture.context, null, forged, response, null));
        }
        var changed = inputs;
        changed.specification.?.display_name = try fixture.value("MOCK A changed current display name.");
        changed.brief.?.title = changed.specification.?.display_name;
        try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, changed, fixture.context, null, field_packet, response, null));
        try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, inputs, fixture.context, null, field_packet, response, null));
        const assignment = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, field_id));
        defer packets.release(assignment);
        const admitted = try support.collectFocused(a, inputs, fixture.context, null, assignment, try assignmentWire(support, a, inputs, fixture.context, field_id, good), null);
        try std.testing.expect(admitted == .pending);
        try std.testing.expectEqualDeep(good.entries[0].value, admitted.pending.review.entries[0].value);
    }
}

test "source review offers not_applicable only where native applicability permits it" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const model = @import("domain/specification_support_model.zig");
    const codec = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const envelope = @import("domain/model_envelope.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const positive: @FieldType(model.Value, "supported") = .{ .source_ids = &.{.{ .ordinal = 1 }}, .detail = "MOCK structural schema probe; no semantic judgment." };
    for ([_][]const u8{ "On startup display `MOCK Hello, World!`.", "After renewal display `MOCK Loan renewed!` and label the deadline `Return by`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();

        // Before authoring, unresolved entity applicability alone permits the verdict.
        const readiness = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        var permitted: usize = 0;
        for ((try authority.build(a, readiness)).requirements) |requirement| {
            const id = requirement.seed.id;
            const permits = (try authority.applicability(readiness, id)) == .review;
            if (permits) {
                try std.testing.expectEqual(authority.Kind.entity_applicability, id.kind);
                permitted += 1;
            }
            const packet = try support.packetFor(a, readiness, fixture.context, support.assignmentScope(readiness, id));
            defer packets.release(packet);
            try std.testing.expectEqualStrings(if (permits) "applicability_finding" else "finding", packet.resultDefinition().?.bytes);
            const body = (try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{})).object;
            try std.testing.expectEqual(permits, body.get("evidence_rules").?.object.contains("not_applicable"));
            try std.testing.expectEqual(permits, body.get("requirements").?.array.items[0].object.contains("permitted_not_applicable"));
            if (permits) {
                // A one-member assignment keeps the permitted verdict in the shared batch schema.
                const assignment = try support.packetFor(a, readiness, fixture.context, .{ .assignment = id });
                defer packets.release(assignment);
                try std.testing.expectEqual(@as(usize, 0), assignment.excludedVariants().len);
                const restricted = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(assignment.resultDefinition().?).?, assignment.excludedVariants(), assignment.integerChoices());
                defer restricted.release();
                const ordinal: u32 = @intCast((try std.json.parseFromSliceLeaky(std.json.Value, a, assignment.body(), .{})).object.get("requirements").?.array.items[0].object.get("ordinal").?.integer);
                var document = try envelope.parseContent(a, try codec.encode(model.Batch, a, .{ .findings = &.{.{ .requirement_ordinal = ordinal, .value = .{ .not_applicable = positive } }} }), null);
                defer document.deinit();
                try std.testing.expect(@import("domain/model_payload_schema.zig").validateValue(envelope.value(&document.parsed.value), restricted.selected().root()) == null);
            }
        }
        try std.testing.expectEqual(@as(usize, 1), permitted);

        // After authoring, the candidate fixes applicability for every advisory assignment.
        const current = try completedFixture(&fixture, false);
        var content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, current)).content;
        for ([_]@TypeOf(content.entities.disposition){ .not_applicable, .required }) |disposition| {
            content.entities.disposition = disposition;
            const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, content, current.units[0].?.response.content.brief);
            const ledger = try authority.build(a, inputs);
            var kinds: std.EnumSet(authority.Kind) = .initEmpty();
            var position: usize = 0;
            while (position < ledger.requirements.len) {
                const id = ledger.requirements[position].seed.id;
                const assigned = try support.assignmentSubjects(a, inputs, id);
                try std.testing.expect(support.assignmentScope(inputs, id) == .assignment);
                const packet = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, id));
                defer packets.release(packet);
                try std.testing.expectEqualStrings("assignment_findings", packet.resultDefinition().?.bytes);
                var excluded = false;
                for (packet.excludedVariants()) |variant| excluded = excluded or std.mem.eql(u8, variant.kind, "not_applicable");
                try std.testing.expect(excluded);
                const body = (try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{})).object;
                for (body.get("requirements").?.array.items) |requirement| {
                    try std.testing.expect(!requirement.object.contains("permitted_not_applicable"));
                    try std.testing.expect(!requirement.object.get("evidence_rules").?.object.contains("not_applicable"));
                }
                const restricted = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
                defer restricted.release();
                for ([_]bool{ false, true }) |forbidden| {
                    const findings = try a.alloc(model.BatchFinding, assigned.len);
                    for (findings, 0..) |*finding, index| finding.* = .{
                        .requirement_ordinal = @intCast(position + index + 1),
                        .value = if (forbidden and index + 1 == assigned.len) .{ .not_applicable = positive } else .{ .supported = positive },
                    };
                    var document = try envelope.parseContent(a, try codec.encode(model.Batch, a, .{ .findings = findings }), null);
                    defer document.deinit();
                    const invalid = @import("domain/model_payload_schema.zig").validateValue(envelope.value(&document.parsed.value), restricted.selected().root());
                    try std.testing.expectEqual(forbidden, invalid != null);
                    if (invalid) |diagnostic| try std.testing.expectEqual(.unknown_variant, diagnostic.reason);
                }
                for (assigned) |member| kinds.insert(member.kind);
                position += assigned.len;
            }
            // Unrelated subject kinds share the one native restriction.
            for ([_]authority.Kind{ .feature_intent, .entity_applicability, .reference_meaning, .preservation }) |kind| try std.testing.expect(kinds.contains(kind));
        }
    }
}

test "record source review admits complete native membership with shared origins and independent evidence" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const model = @import("domain/specification_support_model.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][4][]const u8{
        .{ "MOCK Notify the patient only after verifying contact details when an appointment is cancelled.", "MOCK Contact details have been verified.", "MOCK An appointment is cancelled.", "MOCK Notify the patient." },
        .{ "MOCK Do not dispatch an unreadable parcel until manual identification completes.", "MOCK The parcel label is unreadable.", "MOCK Dispatch is requested.", "MOCK Do not dispatch until manual identification completes." },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, example[0], null, true, example[0], 1);
        defer fixture.deinit();
        const value = try fixture.value(example[0]);
        const records = [_]spec.IdentifiedRecord{
            .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = (try fixture.value(example[1])).value, .when = (try fixture.value(example[2])).value, .then = (try fixture.value(example[3])).value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
            .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 2 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
            .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .proposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
        };
        const content: spec.IdentifiedContent = .{ .display_name = value, .primary_user_story = value, .records = &records, .entities = .{ .disposition = .not_applicable, .basis = value } };
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, content, .{ .title = value, .description = value, .primary_goal = value });
        const ledger = try authority.build(a, inputs);
        const start = for (ledger.requirements, 0..) |required, index| {
            if (required.seed.id.unit == .record and required.seed.id.unit.record.kind == .acceptance_criterion) break index;
        } else return error.MissingRecordAssignment;
        const target = ledger.requirements[start].seed.id;
        const selected = try support.assignmentSubjects(a, inputs, target);
        // One acceptance-criterion family: every field of both criteria, in ledger order.
        try std.testing.expectEqual(@as(usize, 6), selected.len);
        for (selected, 0..) |id, index| {
            try std.testing.expectEqualDeep(records[index / 3].id, id.unit.record);
            try std.testing.expectEqual(([_]authority.Slot{ .given, .when, .then })[index % 3], id.slot);
        }
        try std.testing.expect(support.assignmentScope(inputs, ledger.requirements[start + 6].seed.id) == .assignment);
        // Neither a later member nor the second criterion starts its own assignment.
        try std.testing.expectError(error.InvalidRequiredAuthority, support.assignmentSubjects(a, inputs, selected[1]));
        try std.testing.expectError(error.InvalidRequiredAuthority, support.assignmentSubjects(a, inputs, ledger.requirements[start + 3].seed.id));
        // The functional requirement is a separate family.
        const requirement_family = try support.assignmentSubjects(a, inputs, ledger.requirements[start + 6].seed.id);
        try std.testing.expectEqual(@as(usize, 1), requirement_family.len);
        try std.testing.expectEqualDeep(records[2].id, requirement_family[0].unit.record);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        var prior: ?support.Collection = null;
        var position: usize = 0;
        while (position < start) {
            const id = ledger.requirements[position].seed.id;
            const preceding = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, id));
            defer packets.release(preceding);
            prior = try support.collectFocused(a, inputs, fixture.context, prior, preceding, try assignmentWire(support, a, inputs, fixture.context, id, good), .{ .request = .{ .value = @intCast(800 + position) }, .attempt = .{ .value = 1 } });
            try std.testing.expect(prior.? == .pending);
            position = prior.?.pending.review.entries.len;
        }
        const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, .{ .assignment = target });
        defer packets.release(packet);
        try std.testing.expectEqualStrings("assignment_findings", packet.resultDefinition().?.bytes);
        const body = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
        try std.testing.expect(body.object.get("subject") == null);
        const assigned = body.object.get("requirements").?.array.items;
        // A family has no single shared record; each member carries its own.
        try std.testing.expect(body.object.get("record") == null);
        var response: [6]model.BatchFinding = undefined;
        for (selected, assigned, &response, 0..) |id, item, *finding, index| {
            const single = try support.packetFor(a, inputs, fixture.context, .{ .finding = id });
            defer packets.release(single);
            const single_body = try std.json.parseFromSliceLeaky(std.json.Value, a, single.body(), .{});
            try std.testing.expectEqualStrings(if (index < 3) example[index + 1] else example[0], item.object.get("subject").?.object.get("text").?.string);
            const own_record = try std.json.Stringify.valueAlloc(a, item.object.get("subject").?.object.get("record").?, .{});
            try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, single_body.object.get("subject").?.object.get("record").?, .{}), own_record);
            try std.testing.expectEqualStrings(try json.encode(spec.IdentifiedRecord, a, records[index / 3]), own_record);
            for ([_][]const u8{ "sources", "claims", "citations", "preserved_tokens" }) |key| try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, single_body.object.get(key).?, .{}), try std.json.Stringify.valueAlloc(a, body.object.get(key).?, .{}));
            for ([_][]const u8{ "assessment_scope", "evidence_rules" }) |key| try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, single_body.object.get(key).?, .{}), try std.json.Stringify.valueAlloc(a, item.object.get(key).?, .{}));
            finding.* = .{ .requirement_ordinal = @intCast(start + index + 1), .value = try json.decode(model.Value, a, try sourceReviewWire(a, inputs, fixture.context, id, good.entries[start + index].value)) };
        }
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 900 }, .attempt = .{ .value = 2 } };
        const prompt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.prompt.md", a, .limited(1_048_576));
        try checkProtocolCorrectionPreservesPacket(a, packet, prompt, "{\"findings\":[],\"unexpected\":\"MOCK\"}");
        const bytes = try json.encode(model.Batch, a, .{ .findings = &response });
        const admitted = try support.collectFocused(a, inputs, fixture.context, prior, packet, bytes, origin);
        try std.testing.expect(admitted == .pending);
        try std.testing.expectEqual(start + 6, admitted.pending.review.entries.len);
        try std.testing.expectEqualDeep(prior.?.pending.origin, admitted.pending.origin);
        try std.testing.expectEqualDeep(prior.?.pending.review.entries, admitted.pending.review.entries[0..start]);
        for (admitted.pending.review.entries[start..], admitted.pending.origins[start..], 0..) |finding, retained_origin, index| {
            try std.testing.expectEqualDeep(good.entries[start + index], finding);
            try std.testing.expectEqualDeep(origin, retained_origin.?);
            _ = try admitted.pending.occurrences.at(start + index, admitted.pending.review.entries.len);
        }
        var reversed = response;
        std.mem.reverse(model.BatchFinding, &reversed);
        const reordered = try support.collectFocused(a, inputs, fixture.context, prior, packet, try json.encode(model.Batch, a, .{ .findings = &reversed }), origin);
        try std.testing.expectEqualDeep(admitted, reordered);
        for (0..5) |mutation| {
            var bad = response;
            const findings: []const model.BatchFinding = switch (mutation) {
                0 => bad[0..2],
                // One complete record is not the complete family.
                4 => bad[0..3],
                1 => blk: {
                    bad[1] = bad[0];
                    break :blk &bad;
                },
                2 => blk: {
                    bad[1].requirement_ordinal += 6;
                    break :blk &bad;
                },
                3 => &.{},
                else => unreachable,
            };
            const rejected = try support.collectFocused(a, inputs, fixture.context, prior, packet, try json.encode(model.Batch, a, .{ .findings = findings }), origin);
            try std.testing.expect(rejected == .rejected and rejected.rejected.candidate == null);
            try std.testing.expect(rejected.rejected.rejection.diagnostics.len != 0);
            try std.testing.expectEqual(start, prior.?.pending.review.entries.len);
        }
        var altered = response;
        altered[1].value = .{ .supported = .{ .source_ids = &.{.{ .ordinal = 999 }}, .detail = "MOCK Foreign source." } };
        const bad_evidence = try support.collectFocused(a, inputs, fixture.context, prior, packet, try json.encode(model.Batch, a, .{ .findings = &altered }), origin);
        try std.testing.expect(bad_evidence == .rejected and bad_evidence.rejected.candidate != null);
        try std.testing.expectEqualDeep(good.entries[start], bad_evidence.rejected.candidate.?.review.entries[start]);
        try std.testing.expectEqualDeep(good.entries[start + 2], bad_evidence.rejected.candidate.?.review.entries[start + 2]);
        try std.testing.expectEqual(selected[1].slot, bad_evidence.rejected.rejection.selected().?.requirement.?.slot);
        // The family stops atomically: an invalid finding in the second criterion
        // also discards the first criterion's otherwise valid findings.
        var late = response;
        late[4].value = .{ .supported = .{ .source_ids = &.{.{ .ordinal = 999 }}, .detail = "MOCK Foreign source." } };
        const late_rejected = try support.collectFocused(a, inputs, fixture.context, prior, packet, try json.encode(model.Batch, a, .{ .findings = &late }), origin);
        try std.testing.expect(late_rejected == .rejected and late_rejected.rejected.candidate != null);
        try std.testing.expectEqualDeep(selected[4], late_rejected.rejected.rejection.selected().?.requirement.?);
        const stopped = (try support.stop(a, inputs, fixture.context, late_rejected, .protocol_exhausted, origin)).accepted;
        try std.testing.expectEqual(start, stopped.candidate.review.entries.len);
        try std.testing.expectEqual(ledger.requirements.len - start, stopped.inputs.advice_stop.?.unassessed.len);
        try std.testing.expectEqualDeep(selected[0], stopped.inputs.advice_stop.?.unassessed[0]);
        try support.validateStored(a, stopped.inputs, fixture.context.inputs);
        // A stop forged at the record boundary inside the family is rejected:
        // the first criterion alone is not a complete assignment prefix.
        var partial = admitted.pending;
        partial.review.entries = admitted.pending.review.entries[0 .. start + 3];
        partial.origins = admitted.pending.origins[0 .. start + 3];
        var forged_stop = inputs;
        forged_stop.advice_stop = .{ .reason = .protocol_exhausted, .projection = inputs.projection, .candidate_revision = inputs.revision, .requirements = stopped.inputs.advice_stop.?.requirements, .unassessed = stopped.inputs.advice_stop.?.requirements[start + 3 ..], .authorities = inputs.authorities, .origin = origin };
        try std.testing.expectError(error.InvalidRequiredAuthority, support.validate(a, forged_stop, fixture.context.inputs, partial));
        // Control: the same construction at the family boundary is a valid stop.
        partial.review.entries = admitted.pending.review.entries[0..start];
        partial.origins = admitted.pending.origins[0..start];
        forged_stop.advice_stop.?.unassessed = stopped.inputs.advice_stop.?.requirements[start..];
        try std.testing.expect(try support.validate(a, forged_stop, fixture.context.inputs, partial) == .accepted);
        var changed = inputs;
        const changed_records = try a.dupe(spec.IdentifiedRecord, records[0..]);
        changed_records[0].proposal.content.acceptance_criterion.when = (try fixture.value("MOCK A changed trigger.")).value;
        changed.specification.?.records = changed_records;
        try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, changed, fixture.context, prior, packet, bytes, origin));
        const foreign = try support.packetFor(a, inputs, fixture.context, .{ .assignment = ledger.requirements[start + 6].seed.id });
        defer packets.release(foreign);
        try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, inputs, fixture.context, prior, foreign, bytes, origin));
        const malformed = try support.collectFocused(a, inputs, fixture.context, prior, packet, "{\"findings\":", origin);
        try std.testing.expect(malformed == .rejected and malformed.rejected.candidate == null);
        try std.testing.expectEqual(.invalid_json, malformed.rejected.rejection.selected().?.issue);
    }
}

fn familyFixtureInputs(a: std.mem.Allocator, fixture: *Fixture, source: []const u8, records: []const spec.IdentifiedRecord) !@import("domain/required_authority.zig").Inputs {
    const value = try fixture.value(source);
    const content: spec.IdentifiedContent = .{ .display_name = value, .primary_user_story = value, .records = records, .entities = .{ .disposition = .required, .basis = value } };
    return @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, content, .{ .title = value, .description = value, .primary_goal = value });
}

test "record families group every record of one kind for unrelated kinds and keep entity applicability separate" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "MOCK Register each borrower and record which loans each borrower holds.";
    var fixture = try Fixture.initContent(a, source, null, true, source, 1);
    defer fixture.deinit();
    const value = try fixture.value(source);
    const relationships = [_]spec.BusinessValue{ value.value, value.value };
    const entity: spec.Content(spec.BusinessValue) = .{ .entity = .{ .name = value.value, .business_meaning = value.value, .relationships = &relationships } };
    const requirement: spec.Content(spec.BusinessValue) = .{ .functional_requirement = .{ .text = value.value } };
    const records = [_]spec.IdentifiedRecord{
        .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .proposal = .{ .content = requirement, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
        .{ .id = .{ .kind = .functional_requirement, .ordinal = 2 }, .proposal = .{ .content = requirement, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
        .{ .id = .{ .kind = .entity, .ordinal = 1 }, .proposal = .{ .content = entity, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
        .{ .id = .{ .kind = .entity, .ordinal = 2 }, .proposal = .{ .content = entity, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
    };
    const inputs = try familyFixtureInputs(a, &fixture, source, &records);
    const ledger = try authority.build(a, inputs);
    // Two functional requirements give two members; two entities with a name, a
    // business meaning and two relationships each give eight.
    for ([_]struct { spec.Kind, usize }{ .{ .functional_requirement, 2 }, .{ .entity, 8 } }) |expected| {
        const start = for (ledger.requirements, 0..) |required, index| {
            if (required.seed.id.unit == .record and required.seed.id.unit.record.kind == expected[0]) break index;
        } else return error.MissingRecordFamily;
        const members = try support.assignmentSubjects(a, inputs, ledger.requirements[start].seed.id);
        try std.testing.expectEqual(expected[1], members.len);
        const packet = try support.packetFor(a, inputs, fixture.context, .{ .assignment = members[0] });
        defer packets.release(packet);
        const body = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
        try std.testing.expect(body.object.get("record") == null);
        for (members, body.object.get("requirements").?.array.items, 0..) |member, item, index| {
            try std.testing.expectEqual(expected[0], member.unit.record.kind);
            try std.testing.expectEqual(@as(u32, @intCast(index * 2 / members.len + 1)), member.unit.record.ordinal);
            const id = item.object.get("subject").?.object.get("record").?.object.get("id").?.object;
            try std.testing.expectEqualStrings(@tagName(expected[0]), id.get("kind").?.string);
            try std.testing.expectEqual(@as(i64, member.unit.record.ordinal), id.get("ordinal").?.integer);
        }
        // The family's second record cannot start its own assignment.
        try std.testing.expectError(error.InvalidRequiredAuthority, support.assignmentSubjects(a, inputs, members[members.len / 2]));
    }
    const applicability = for (ledger.requirements) |required| {
        if (required.seed.id.unit == .feature and required.seed.id.slot == .entities) break required.seed.id;
    } else return error.MissingEntityApplicability;
    const decided = try support.assignmentSubjects(a, inputs, applicability);
    try std.testing.expectEqual(@as(usize, 1), decided.len);
    try std.testing.expectEqual(.entities, try @import("domain/specification_review_subject.zig").assignmentUnit(a, inputs, applicability));
}

test "a record family above the member choice bound rejects before invocation without splitting" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const schema_owner = @import("domain/model_result_schema.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "MOCK Record every relationship of the borrower.";
    var fixture = try Fixture.initContent(a, source, null, true, source, 1);
    defer fixture.deinit();
    const value = try fixture.value(source);
    // A name, a business meaning and 1,023 relationships: 1,025 members.
    const relationships = try a.alloc(spec.BusinessValue, schema_owner.max_choices - 1);
    @memset(relationships, value.value);
    const records = [_]spec.IdentifiedRecord{.{ .id = .{ .kind = .entity, .ordinal = 1 }, .proposal = .{ .content = .{ .entity = .{ .name = value.value, .business_meaning = value.value, .relationships = relationships } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance } }};
    const inputs = try familyFixtureInputs(a, &fixture, source, &records);
    const ledger = try authority.build(a, inputs);
    const first = for (ledger.requirements) |required| {
        if (required.seed.id.unit == .record) break required.seed.id;
    } else return error.MissingRecordFamily;
    // The family is complete, never split, and its request is refused before any
    // member packet is built, so no provider call can follow.
    const members = try support.assignmentSubjects(a, inputs, first);
    try std.testing.expectEqual(@as(usize, schema_owner.max_choices + 1), members.len);
    try std.testing.expectError(error.ChoiceBoundExceeded, support.packetFor(a, inputs, fixture.context, .{ .assignment = first }));
    // The family check and schema restriction share one bound: the maximum is
    // allowed and one more is not.
    try std.testing.expect(schema_owner.withinChoiceBound(schema_owner.max_choices) and !schema_owner.withinChoiceBound(members.len));
    // Control: a small family of the same record kind builds its packet.
    var bounded = records;
    bounded[0].proposal.content.entity.relationships = relationships[0..2];
    const within = try familyFixtureInputs(a, &fixture, source, &bounded);
    const packet = try support.packetFor(a, within, fixture.context, .{ .assignment = first });
    defer packets.release(packet);
    try std.testing.expectEqual(@as(usize, 4), packet.integerChoices()[0].allowed.len);
}

fn expectWithheld(packet: *const @import("domain/model_input_packet.zig").Packet, kinds: []const []const u8) !void {
    try std.testing.expectEqual(kinds.len, packet.excludedVariants().len);
    for (kinds, packet.excludedVariants()) |kind, excluded| try std.testing.expectEqualStrings(kind, excluded.kind);
}

test "an assignment withholds positive verdicts no claim set can bind, so one in a response fails admission" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const model = @import("domain/specification_support_model.zig");
    const rules = @import("domain/specification_support_evidence.zig");
    const schema = @import("domain/model_result_schema.zig");
    const check = @import("domain/model_payload_schema.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    // Functional requirements alone leave the acceptance-criteria and scenario
    // collections without a backing record; acceptance criteria alone leave the
    // functional-requirement collection without one and back scenario coverage.
    const Shape = struct { source: []const u8, kind: spec.Kind, empty: []const authority.Slot, backed: []const authority.Slot };
    for ([_]Shape{
        .{ .source = "MOCK Record each borrower's renewal request.", .kind = .functional_requirement, .empty = &.{ .acceptance_criteria, .scenario_coverage }, .backed = &.{.functional_requirements} },
        .{ .source = "MOCK Display the greeting and the current date.", .kind = .acceptance_criterion, .empty = &.{.functional_requirements}, .backed = &.{ .acceptance_criteria, .scenario_coverage } },
    }) |shape| {
        const source = shape.source;
        var fixture = try Fixture.initContent(a, source, null, true, source, 1);
        defer fixture.deinit();
        const value = try fixture.value(source);
        const content: spec.Content(spec.BusinessValue) = if (shape.kind == .functional_requirement) .{ .functional_requirement = .{ .text = value.value } } else .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } };
        const records = [_]spec.IdentifiedRecord{
            .{ .id = .{ .kind = shape.kind, .ordinal = 1 }, .proposal = .{ .content = content, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
            .{ .id = .{ .kind = shape.kind, .ordinal = 2 }, .proposal = .{ .content = content, .source_group_ids = value.source_group_ids, .provenance = value.provenance } },
        };
        const inputs = try familyFixtureInputs(a, &fixture, source, &records);
        const ledger = try authority.build(a, inputs);
        for (shape.empty) |slot| {
            const coverage = for (ledger.requirements, 0..) |required, index| {
                if (required.seed.id.unit == .feature and required.seed.id.slot == slot) break index;
            } else return error.MissingCollectionSubject;
            const id = ledger.requirements[coverage].seed.id;
            // Neither positive verdict can be canonicalized for the empty
            // collection, while every negative verdict still can.
            const required = try rules.requirements(a, inputs, fixture.context.inputs, id);
            try std.testing.expect(!model.resolves(required, .supported) and !model.resolves(required, .not_applicable));
            for ([_]model.Decision{ .ambiguous, .conflicting, .unsupported, .candidate_omission, .candidate_invalid, .inconclusive }) |negative| try std.testing.expect(model.resolves(required, negative));
            const packet = try support.packetFor(a, inputs, fixture.context, .{ .assignment = id });
            defer packets.release(packet);
            try expectWithheld(packet, &.{ "supported", "not_applicable" });
            // Guidance offers no rule for a withheld verdict.
            const body = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
            const members = body.object.get("requirements").?.array.items;
            try std.testing.expectEqual(@as(usize, 1), members.len);
            const evidence_rules = members[0].object.get("evidence_rules").?.object;
            try std.testing.expect(evidence_rules.get("supported") == null and evidence_rules.get("not_applicable") == null and evidence_rules.get("negative") != null);
            try std.testing.expect(members[0].object.get("permitted_not_applicable") == null);
            // Response admission rejects a withheld verdict as a typed defect,
            // which takes the bounded protocol correction; a negative verdict is
            // admitted.
            const restricted = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer restricted.release();
            const sources = evidence_rules.get("eligible_source_ids").?.array.items;
            const Finding = struct { requirement_ordinal: u32, value: model.Value };
            const source_ids = [_]@import("domain/reference_identity.zig").SourceId{.{ .ordinal = @intCast(sources[0].integer) }};
            for ([_]struct { model.Value, ?check.Rejection }{
                .{ .{ .supported = .{ .source_ids = &source_ids, .detail = "MOCK The collection is covered." } }, .unknown_variant },
                .{ .{ .not_applicable = .{ .source_ids = &source_ids, .detail = "MOCK Not applicable." } }, .unknown_variant },
                .{ .{ .candidate_omission = .{ .source_ids = &source_ids, .detail = "MOCK The source states an outcome.", .missing_obligation = "MOCK State the outcome." } }, null },
            }) |case| {
                const wire = try @import("domain/model_candidate_json.zig").encode(struct { findings: []const Finding }, a, .{ .findings = &.{.{ .requirement_ordinal = @intCast(coverage + 1), .value = case[0] }} });
                const response = try std.json.parseFromSliceLeaky(std.json.Value, a, wire, .{ .parse_numbers = false });
                const rejected = check.validateValue(@import("domain/model_envelope.zig").value(&response), restricted.selected().root());
                if (case[1]) |reason| try std.testing.expectEqual(reason, rejected.?.reason) else try std.testing.expect(rejected == null);
            }
        }
        // Controls: each backed collection and the record family bind claims, so
        // each withholds only the `not_applicable` that native applicability
        // excludes.
        var controls: std.ArrayList(authority.Id) = .empty;
        var family = false;
        for (ledger.requirements) |entry| {
            const backed = entry.seed.id.unit == .feature and std.mem.indexOfScalar(authority.Slot, shape.backed, entry.seed.id.slot) != null;
            // A record family's assignment starts at its first member.
            const first_member = !family and entry.seed.id.unit == .record;
            family = family or first_member;
            if (backed or first_member) try controls.append(a, entry.seed.id);
        }
        try std.testing.expect(controls.items.len > shape.backed.len);
        for (controls.items) |id| {
            const required = try rules.requirements(a, inputs, fixture.context.inputs, id);
            try std.testing.expect(model.resolves(required, .supported));
            const packet = try support.packetFor(a, inputs, fixture.context, .{ .assignment = id });
            defer packets.release(packet);
            try expectWithheld(packet, &.{"not_applicable"});
        }
    }
}

test "source and policy collections expose selected members despite matching text elsewhere and retain them through repairs" {
    const authority = @import("domain/required_authority.zig");
    const collection = @import("domain/specification_authority.zig");
    const assessment = @import("domain/principle_assessment.zig");
    const source_review = @import("domain/specification_support.zig").Source;
    const policy_review = @import("domain/specification_support.zig").Contract(.principles);
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    for ([_]authority.Slot{ .acceptance_criteria, .functional_requirements, .scenario_coverage }) |slot| {
        inline for (comptime std.meta.tags(spec.Kind)) |kind| try std.testing.expectEqual(switch (slot) {
            .acceptance_criteria => kind == .acceptance_criterion,
            .functional_requirements => kind == .functional_requirement,
            .scenario_coverage => kind == .acceptance_criterion or kind == .edge_case or kind == .user_visible_outcome,
            else => unreachable,
        }, try collection.collectionContains(slot, kind));
    }
    try std.testing.expectError(error.InvalidRequiredAuthority, collection.collectionContains(.text, .functional_requirement));
    try std.testing.expectEqual(@as(?spec.Kind, null), collection.collectionFamily(.scenario_coverage));
    for ([_][]const u8{ "MOCK A visitor receives a startup greeting.", "MOCK A borrower receives a renewal receipt." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, null, true, source, 5);
        defer fixture.deinit();
        const value = try fixture.value(source);
        const all = try provenance.items(fixture.context);
        try std.testing.expectEqual(@as(usize, 5), all.entries.len);
        const claims = try a.alloc(@import("domain/reference_reconciliation.zig").ClaimId, all.entries.len);
        const associations = try a.alloc(spec.Provenance, all.entries.len);
        for (all.entries, claims, associations, 0..) |entry, *claim, *association, index| {
            claim.* = entry.claim.id;
            association.* = .{ .claim_ids = claims[index .. index + 1], .citation_ids = entry.claim.citation_ids, .clarification_response_ids = &.{} };
        }
        const policies = try @import("test_fixtures/principles.zig").registry(a, "MOCK User-facing results must be readable.\n");
        for (0..4) |mode| {
            var records: std.ArrayList(spec.IdentifiedRecord) = .empty;
            // The same source wording remains in the story and other families
            // when either selected mandatory collection is empty.
            if (mode & 1 == 0) try records.append(a, .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = try mockClaimGroup(a, fixture.context, claims[0]), .provenance = associations[0] } });
            try records.append(a, .{ .id = .{ .kind = .user_visible_outcome, .ordinal = 1 }, .proposal = .{ .content = .{ .user_visible_outcome = .{ .text = value.value } }, .source_group_ids = try mockClaimGroup(a, fixture.context, claims[1]), .provenance = associations[1] } });
            try records.append(a, .{ .id = .{ .kind = .edge_case, .ordinal = 1 }, .proposal = .{ .content = .{ .edge_case = .{ .condition = value.value, .expected_outcome = value.value } }, .source_group_ids = try mockClaimGroup(a, fixture.context, claims[2]), .provenance = associations[2] } });
            if (mode & 2 == 0) try records.append(a, .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .proposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = try mockClaimGroup(a, fixture.context, claims[3]), .provenance = associations[3] } });
            try records.append(a, .{ .id = .{ .kind = .business_rule, .ordinal = 1 }, .proposal = .{ .content = .{ .business_rule = .{ .text = value.value } }, .source_group_ids = try mockClaimGroup(a, fixture.context, claims[4]), .provenance = associations[4] } });
            const content: spec.IdentifiedContent = .{ .display_name = value, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = records.items };
            const business: assessment.Business = .{ .feature = fixture.context.inputs.corpus.feature_id, .revision = 9, .brief = .{ .title = value, .description = value, .primary_goal = value }, .content = content, .references = @import("domain/reference_support.zig").records(fixture.context.references) };
            const source_inputs = try @import("domain/specification_authority.zig").projectRecords(a, business.feature, business.references, content, business.brief);
            const source_ledger = try authority.build(a, source_inputs);
            const source_good = try reviewFor(a, source_inputs, fixture.context.inputs);
            const policy_inputs = try assessment.project(a, .{ .business = business, .registry = policies, .selection = try @import("domain/principle_registry.zig").select(a, policies, .{ .stage = .spec, .environment = null, .fileKind = null }) });
            const policy_subjects = try assessment.subjects(a, business);
            const policy_ledger = try authority.build(a, policy_inputs);
            const policy_good = try a.alloc(policy_review.Finding, policy_ledger.requirements.len);
            for (policy_good, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = .compatible, .citations = &.{}, .detail = "" } };
            for ([_]authority.Slot{ .acceptance_criteria, .functional_requirements, .scenario_coverage }) |slot| {
                const source_index = for (source_ledger.requirements, 0..) |requirement, index| {
                    if (requirement.seed.id.unit == .feature and requirement.seed.id.slot == slot) break index;
                } else return error.MissingCollectionRequirement;
                const business_id = source_ledger.requirements[source_index].seed.id;
                const policy_index = for (policy_subjects, 0..) |id, index| {
                    if (std.meta.eql(id, business_id)) break index;
                } else return error.MissingPolicyCollectionRequirement;
                const source_packet = try source_review.packetFor(std.testing.allocator, source_inputs, fixture.context, .{ .finding = business_id });
                defer packets.release(source_packet);
                const policy_packet = try policy_review.packetFor(std.testing.allocator, policy_inputs, fixture.context, .{ .finding = policy_ledger.requirements[policy_index].seed.id });
                defer packets.release(policy_packet);
                try expectBusinessReviewPurpose(.source, a, source_inputs, fixture.context, source_packet, business_id);
                try expectBusinessReviewPurpose(.principles, a, policy_inputs, fixture.context, policy_packet, business_id);
                const source_body = (try std.json.parseFromSlice(std.json.Value, a, source_packet.body(), .{})).value.object;
                const policy_body = (try std.json.parseFromSlice(std.json.Value, a, policy_packet.body(), .{})).value.object;
                const expected_claims: ?[]const @import("domain/reference_reconciliation.zig").ClaimId = switch (slot) {
                    .acceptance_criteria => if (mode & 1 == 0) claims[0..1] else null,
                    .functional_requirements => if (mode & 2 == 0) claims[3..4] else null,
                    .scenario_coverage => if (mode & 1 == 0) claims[0..3] else claims[1..3],
                    else => unreachable,
                };
                if (expected_claims) |selected_claims| {
                    const required = try @import("domain/specification_support_evidence.zig").requirements(a, source_inputs, fixture.context.inputs, business_id);
                    try std.testing.expectEqualDeep(selected_claims, required.supported_provenance.?.claim_ids);
                    const presented = source_body.get("requirements").?.array.items[0].object.get("evidence").?.object.get("supported_provenance").?.object.get("claim_ids").?;
                    try std.testing.expectEqualDeep(selected_claims, try json.decode([]const @import("domain/reference_reconciliation.zig").ClaimId, a, try std.json.Stringify.valueAlloc(a, presented, .{})));
                }
                try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, source_body.get("subject").?, .{}), try std.json.Stringify.valueAlloc(a, policy_body.get("subject").?, .{}));
                const members = source_body.get("subject").?.object.get("records").?.array.items;
                try std.testing.expectEqual(@as(usize, switch (slot) {
                    .acceptance_criteria => @intFromBool(mode & 1 == 0),
                    .functional_requirements => @intFromBool(mode & 2 == 0),
                    .scenario_coverage => 2 + @as(usize, @intFromBool(mode & 1 == 0)),
                    else => unreachable,
                }), members.len);
                // Exercise both populated and empty collections through native
                // malformed-data repair; this supplies no semantic verdict.
                if (mode == 0 or mode == 3) {
                    try checkReviewRepairPurposes(.source, a, source_inputs, fixture.context, source_good, source_index, business_id);
                    try checkReviewRepairPurposes(.principles, a, policy_inputs, fixture.context, .{ .entries = policy_good }, policy_index, business_id);
                }
            }
            const reviewed = (try collectReview(source_review, a, source_inputs, fixture.context, try json.encode(source_review.Review, a, source_good), null)).accepted;
            const decision = try supportDecision(a, reviewed.inputs);
            try std.testing.expectEqual(@as(@TypeOf(decision.result.continuation), if (mode == 0) .all_resolved else .invalid), decision.result.continuation);
        }
    }
}

test "principle packets resolve assigned business subjects without exposing native requirement tuples" {
    const assessment = @import("domain/principle_assessment.zig");
    const authority = @import("domain/required_authority.zig");
    const review = @import("domain/specification_support.zig").Contract(.principles);
    const projection = @import("domain/specification_projection.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][]const u8{
        "MOCK visitor reads stories.md and sees `MOCK Ready!`.",
        "MOCK borrower reads stories.md and sees `MOCK Renewed!`.",
    }, 0..) |source, source_index| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const token = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token) break entry.claim;
        } else return error.MissingExactToken;
        const exact: spec.AttributedValue = .{
            .value = .{ .segments = &.{ .{ .literal = .{ .value = "MOCK Display " } }, .{ .exact_copy = .{ .claim_id = token.id } } } },
            .source_group_ids = try mockClaimGroup(a, fixture.context, token.id),
            .provenance = .{ .claim_ids = &.{token.id}, .citation_ids = token.citation_ids, .clarification_response_ids = &.{} },
        };
        var passive = try fixture.value("MOCK read the source.");
        passive.value = .{ .segments = &.{
            .{ .literal = .{ .value = "MOCK read " } },
            .{ .passive = .{ .passive_literal_id = fixture.context.registry.records[0].id } },
        } };
        const literal = try fixture.value("MOCK singleton renewal");
        const records = try a.alloc(spec.IdentifiedRecord, std.meta.fields(spec.Kind).len);
        inline for (std.meta.fields(spec.Kind), 0..) |kind, index| records[index] = .{
            .id = .{ .kind = @field(spec.Kind, kind.name), .ordinal = 1 },
            .proposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), kind.name, Fields(@field(spec.Kind, kind.name), passive.value)), .source_group_ids = passive.source_group_ids, .provenance = passive.provenance },
        };
        records[0].proposal.content.acceptance_criterion.given = literal.value;
        records[0].proposal.content.acceptance_criterion.then = exact.value;
        records[0].proposal.provenance = (try provenance.lineageForRepair(a, fixture.context, selection(passive.provenance), try provenance.recordValues(a, records[0].proposal.content))).provenance;
        records[records.len - 1].proposal.content.entity.relationships = &.{passive.value};
        for ([_]spec.Applicability{ .required, .not_applicable }) |disposition| {
            const content: spec.IdentifiedContent = .{
                .display_name = literal,
                .primary_user_story = passive,
                .entities = .{ .disposition = disposition, .basis = passive },
                .records = if (disposition == .required) records else records[0 .. records.len - 1],
            };
            const business: assessment.Business = .{
                .feature = fixture.context.inputs.corpus.feature_id,
                .revision = 7,
                .brief = .{ .title = literal, .description = exact, .primary_goal = passive },
                .content = content,
                .references = @import("domain/reference_support.zig").records(fixture.context.references),
            };
            const policies = try @import("test_fixtures/principles.zig").registry(a, "MOCK user-facing output must be readable.\n");
            const inputs = try assessment.project(a, .{ .business = business, .registry = policies, .selection = try @import("domain/principle_registry.zig").select(a, policies, .{ .stage = .spec, .environment = null, .fileKind = null }) });
            const assigned = try assessment.subjects(a, business);
            const ledger = try authority.build(a, inputs);
            const policy_findings = try a.alloc(review.Finding, ledger.requirements.len);
            for (policy_findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = .compatible, .citations = &.{}, .detail = "" } };
            const source_inputs = try @import("domain/specification_authority.zig").projectRecords(a, business.feature, business.references, content, business.brief);
            const source_ledger = try authority.build(a, source_inputs);
            const source_findings = try reviewFor(a, source_inputs, fixture.context.inputs);
            const projected = try projection.project(a, fixture.context, content);
            for (ledger.requirements, assigned) |requirement, id| {
                const packet = try review.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = requirement.seed.id });
                defer packets.release(packet);
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                try std.testing.expect(body.get("subject").? == .object);
                const subject = body.get("subject").?.object;
                const related = subject.get("context").?.object;
                // Arbitrary policies may compare this field with other requirements.
                try std.testing.expectEqualDeep(projected, try json.decode(spec.CapturedDocument, a, try std.json.Stringify.valueAlloc(a, related.get("candidate").?, .{})));
                try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "MOCK Display {s}", .{token.content.preserved_token.value.raw_value.bytes}), related.get("brief").?.object.get("description").?.object.get("bytes").?.string);
                try std.testing.expectEqualStrings("MOCK read stories.md", related.get("entity_basis").?.object.get("bytes").?.string);
                try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, id), body.get("task").?.string);
                try std.testing.expect(std.mem.indexOf(u8, body.get("task").?.string, "Source support") == null);
                for ([_][]const u8{ "requirements", "brief", "candidate", "entity_basis" }) |key| try std.testing.expect(!body.contains(key));
                try std.testing.expect(std.mem.indexOf(u8, packet.body(), "\"singleton\"") == null);
                try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Assess the assigned requirement in the surrounding candidate") == null);
                try std.testing.expectEqual(policies.chunks.len, body.get("principles").?.array.items.len);
                if (id.unit == .record) {
                    try expectRecordReviewPurpose(.principles, a, packet, id);
                    try std.testing.expectEqualStrings("field", subject.get("kind").?.string);
                    try std.testing.expectEqualStrings(@tagName(id.slot), subject.get("slot").?.string);
                    const selected = (try @import("domain/specification_authority.zig").recordField(try @import("domain/specification_authority.zig").projectRecords(a, business.feature, business.references, content, business.brief), id)).?;
                    try std.testing.expectEqualStrings((try projection.recordScalar(a, fixture.context, selected.record.proposal, selected.field.value)).bytes, subject.get("text").?.string);
                    const expected = for (projected.records) |record| {
                        if (std.meta.eql(record.id.?, id.unit.record)) break record;
                    } else return error.MissingRecord;
                    try std.testing.expectEqualDeep(expected, try json.decode(spec.CapturedRecord, a, try std.json.Stringify.valueAlloc(a, subject.get("record").?, .{})));
                    if (id.unit.record.kind == .acceptance_criterion) {
                        try std.testing.expectEqualStrings("MOCK singleton renewal", expected.content.acceptance_criterion.given.bytes);
                        try std.testing.expectEqualStrings("MOCK read stories.md", expected.content.acceptance_criterion.when.bytes);
                        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "MOCK Display {s}", .{token.content.preserved_token.value.raw_value.bytes}), expected.content.acceptance_criterion.then.bytes);
                    }
                    if (id.slot == .relationship) try std.testing.expectEqualStrings("MOCK read stories.md", expected.content.entity.relationships[0].bytes);
                    if (disposition == .required) {
                        const policy_index = requirement.seed.id.unit.decision.ordinal - 1;
                        try checkReviewRepairPurposes(.principles, a, inputs, fixture.context, .{ .entries = policy_findings }, policy_index, id);
                        const source_index_of_id = for (source_ledger.requirements, 0..) |source_requirement, index| {
                            if (std.meta.eql(source_requirement.seed.id, id)) break index;
                        } else return error.MissingRecordRequirement;
                        try checkReviewRepairPurposes(.source, a, source_inputs, fixture.context, source_findings, source_index_of_id, id);
                    }
                } else switch (id.slot) {
                    .display_name, .description, .primary_goal, .primary_user_story => {
                        try std.testing.expectEqualStrings("field", subject.get("kind").?.string);
                        const expected = switch (id.slot) {
                            .display_name => literal.value.segments[0].literal.value,
                            .description => try std.fmt.allocPrint(a, "MOCK Display {s}", .{token.content.preserved_token.value.raw_value.bytes}),
                            else => "MOCK read stories.md",
                        };
                        try std.testing.expectEqualStrings(expected, subject.get("text").?.string);
                        try std.testing.expect(!subject.contains("candidate"));
                    },
                    .acceptance_criteria, .functional_requirements, .scenario_coverage, .entities => {
                        try std.testing.expectEqualStrings(if (id.slot == .entities) "entity_applicability" else "collection", subject.get("kind").?.string);
                        if (id.slot == .entities) {
                            try std.testing.expectEqualStrings(@tagName(disposition), subject.get("disposition").?.string);
                            try std.testing.expectEqualStrings("MOCK read stories.md", subject.get("basis").?.object.get("bytes").?.string);
                            const source_entity_index = for (source_ledger.requirements, 0..) |source_requirement, index| {
                                if (std.meta.eql(source_requirement.seed.id, id)) break index;
                            } else return error.MissingEntityRequirement;
                            if (source_index == 0 and disposition == .required)
                                try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(scalarReviewPacketAllocationCase, .{ source_inputs, fixture.context, id });
                            for ([_]struct { value: spec.AttributedValue, allowed: bool }{ .{ .value = literal, .allowed = true }, .{ .value = exact, .allowed = false }, .{ .value = passive, .allowed = true } }) |basis_case| {
                                const basis = basis_case.value;
                                var entity_source = source_inputs;
                                entity_source.specification.?.entities.basis = basis;
                                var entity_policy = inputs;
                                entity_policy.principle_context.?.business.content.entities.basis = basis;
                                if (!basis_case.allowed) {
                                    try std.testing.expectError(error.InvalidTypedText, review.packetFor(std.testing.allocator, entity_policy, fixture.context, .{ .finding = id }));
                                    continue;
                                }
                                const entity_findings = try reviewFor(a, entity_source, fixture.context.inputs);
                                try checkReviewRepairPurposes(.source, a, entity_source, fixture.context, entity_findings, source_entity_index, id);
                                try checkReviewRepairPurposes(.principles, a, entity_policy, fixture.context, .{ .entries = policy_findings }, requirement.seed.id.unit.decision.ordinal - 1, id);
                                const subjects = @import("domain/specification_review_subject.zig");
                                const localized = try subjects.projectLoss(a, entity_source, fixture.context, id);
                                try std.testing.expect(localized == .business);
                                try std.testing.expect(localized.business == .entity_applicability);
                                try std.testing.expectEqualDeep(try subjects.projectBusiness(a, entity_source, fixture.context, id), localized.business);
                            }
                            var invalid_entity = source_inputs;
                            invalid_entity.specification.?.entities.basis.provenance.claim_ids = &.{};
                            try std.testing.expectError(error.InvalidSpecification, @import("domain/specification_support.zig").Source.packetFor(std.testing.allocator, invalid_entity, fixture.context, .{ .finding = id }));
                        } else try std.testing.expectEqualStrings(@tagName(id.slot), subject.get("slot").?.string);
                    },
                    else => return error.UnexpectedPolicySubject,
                }
                const correction = try review.packetFor(std.testing.allocator, inputs, fixture.context, .{ .correction = requirement.seed.id });
                defer packets.release(correction);
                try expectSameReviewSubject(a, packet, correction);
                if (source_index == 0 and disposition == .required and (id.slot == .display_name or id.slot == .entities or id.slot == .functional_requirements or id.slot == .given)) {
                    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(policyReviewPacketAllocationCase, .{ inputs, fixture.context, requirement.seed.id });
                }
            }
            var foreign = ledger.requirements[0].seed.id;
            foreign.contract_version += 1;
            try std.testing.expectError(error.InvalidRequiredAuthority, review.packetFor(std.testing.allocator, inputs, fixture.context, .{ .finding = foreign }));
            var stale = inputs;
            stale.principle_context.?.business.content.display_name.provenance.claim_ids = &.{};
            try std.testing.expectError(error.InvalidSpecification, review.packetFor(std.testing.allocator, stale, fixture.context, .{ .finding = ledger.requirements[0].seed.id }));
            // A focused payload must not bypass complete business-view validation.
            var invalid = inputs;
            const reordered = try a.dupe(spec.IdentifiedRecord, content.records);
            std.mem.swap(spec.IdentifiedRecord, &reordered[0], &reordered[1]);
            invalid.principle_context.?.business.content.records = reordered;
            try std.testing.expectError(error.InvalidSpecification, review.packetFor(std.testing.allocator, invalid, fixture.context, .{ .finding = ledger.requirements[0].seed.id }));
            if (disposition == .required) {
                invalid = inputs;
                invalid.principle_context.?.business.content.entities.disposition = .not_applicable;
                try std.testing.expectError(error.InvalidSpecification, review.packetFor(std.testing.allocator, invalid, fixture.context, .{ .finding = ledger.requirements[0].seed.id }));
            }
        }
    }
}

fn policyReviewPacketAllocationCase(allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, id: @import("domain/required_authority.zig").Id) !void {
    const packet = try @import("domain/specification_support.zig").Contract(.principles).packetFor(allocator, inputs, context, .{ .finding = id });
    defer @import("domain/model_input_packet.zig").release(packet);
}

fn expectSameReviewSubject(a: std.mem.Allocator, expected: *@import("domain/model_input_packet.zig").Packet, actual: *@import("domain/model_input_packet.zig").Packet) !void {
    const expected_body = (try std.json.parseFromSlice(std.json.Value, a, expected.body(), .{})).value;
    const left = expected_body.object.get("input") orelse expected_body;
    const body = (try std.json.parseFromSlice(std.json.Value, a, actual.body(), .{})).value;
    const right = body.object.get("input") orelse body;
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, left.object.get("subject").?, .{}), try std.json.Stringify.valueAlloc(a, right.object.get("subject").?, .{}));
    const left_task = left.object.get("task") orelse left.object.get("requirements").?.array.items[0].object.get("task").?;
    const right_task = right.object.get("task") orelse right.object.get("requirements").?.array.items[0].object.get("task").?;
    try std.testing.expectEqualStrings(left_task.string, right_task.string);
    if (left.object.get("assessment_scope")) |scope| {
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, scope, .{}), try std.json.Stringify.valueAlloc(a, right.object.get("assessment_scope").?, .{}));
    } else try std.testing.expect(!right.object.contains("assessment_scope"));
}

fn expectReviewAssessmentScope(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, input: std.json.Value, id: @import("domain/required_authority.zig").Id) !void {
    if (purpose == .principles) return std.testing.expect(!input.object.contains("assessment_scope"));
    const scope = input.object.get("assessment_scope").?.object;
    try std.testing.expectEqual(@as(usize, 3), scope.count());
    const subject_value = input.object.get("subject").?;
    try std.testing.expect(@import("domain/required_authority.zig").policy(id) != null);
    const record = subject_value.object.get("record");
    // A native record input may contain engine-derived exact identities. It is
    // evidence, so do not feed it to the model-response decoder to assert the
    // presentation instruction. This independent expectation covers that role.
    const expected = if (std.mem.eql(u8, subject_value.object.get("kind").?.string, "candidate_field") and record != null and record.? != .null)
        @import("domain/required_authority_description.zig").SourceReviewScope{ .instruction = "Assess subject.text for its assigned field purpose within subject.record. Sibling fields may supply joint conditions and results; each field need not repeat the whole flow." }
    else
        @import("domain/required_authority_description.zig").sourceReviewScope(try @import("domain/model_candidate_json.zig").decode(@import("domain/specification_review_subject.zig").Subject, a, try std.json.Stringify.valueAlloc(a, subject_value, .{})));
    inline for (std.meta.fields(@TypeOf(expected))) |field| {
        const presented = scope.get(field.name).?.string;
        try std.testing.expect(presented.len != 0);
        try std.testing.expectEqualStrings(@field(expected, field.name), presented);
    }
}

fn selectedNativeRepairTask(input: std.json.Value) ![]const u8 {
    const assignment = input.object.get("source_assignment").?;
    if (assignment == .object) {
        try std.testing.expect(!assignment.object.contains("purpose"));
        if (std.mem.eql(u8, assignment.object.get("kind").?.string, "brief")) {
            inline for (.{ "title", "description", "primary_goal" }) |field| try std.testing.expect(!assignment.object.get(field).?.object.contains("purpose"));
        }
    }
    return input.object.get("task").?.string;
}

fn expectRecordReviewPurpose(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, id: @import("domain/required_authority.zig").Id) !void {
    const descriptions = @import("domain/required_authority_description.zig");
    const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value;
    const input = (body.object.get("input") orelse body).object;
    try expectReviewAssessmentScope(purpose, a, .{ .object = input }, id);
    const task = if (purpose == .principles) input.get("task").?.string else input.get("requirements").?.array.items[0].object.get("task").?.string;
    try std.testing.expectEqualStrings(try descriptions.recordTask(a, id.unit.record.kind, id.slot), task);
    try std.testing.expect(std.mem.indexOf(u8, task, descriptions.recordFamily(id.unit.record.kind)) != null);
    try std.testing.expect(std.mem.indexOf(u8, task, try descriptions.recordField(id.unit.record.kind, id.slot)) != null);
    const subject = input.get("subject").?.object;
    try std.testing.expectEqualStrings(@tagName(id.slot), subject.get("slot").?.string);
    const record = subject.get("record").?.object;
    try std.testing.expectEqualStrings(@tagName(id.unit.record.kind), record.get("id").?.object.get("kind").?.string);
    try std.testing.expectEqual(@as(i64, id.unit.record.ordinal), record.get("id").?.object.get("ordinal").?.integer);
    if (purpose == .principles) {
        try std.testing.expect(!input.contains("sources"));
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Assess the assigned requirement in the surrounding candidate") == null);
    } else try std.testing.expect(!input.contains("principles"));
}

fn expectBusinessReviewPurpose(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, packet: *const @import("domain/model_input_packet.zig").Packet, id: @import("domain/required_authority.zig").Id) !void {
    const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value;
    const input = (body.object.get("input") orelse body).object;
    try expectReviewAssessmentScope(purpose, a, .{ .object = input }, id);
    const task = if (purpose == .principles) input.get("task").?.string else input.get("requirements").?.array.items[0].object.get("task").?.string;
    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, id), task);
    const subject_value = input.get("subject").?;
    const subject = subject_value.object;
    const selected = try @import("domain/model_candidate_json.zig").decode(@import("domain/specification_review_subject.zig").Subject, a, try std.json.Stringify.valueAlloc(a, subject_value, .{}));
    const content = if (purpose == .source) inputs.specification.? else inputs.principle_context.?.business.content;
    const brief = if (purpose == .source) inputs.brief.? else inputs.principle_context.?.business.brief;
    const projection = @import("domain/specification_projection.zig");
    const resolved = try projection.project(a, context, content);
    const related = switch (selected) {
        .collection => |value| collection: {
            try std.testing.expectEqualStrings("collection", subject.get("kind").?.string);
            try std.testing.expectEqual(id.slot, value.slot);
            var count: usize = 0;
            for (resolved.records) |record| {
                const matches = switch (id.slot) {
                    .acceptance_criteria => record.content == .acceptance_criterion,
                    .functional_requirements => record.content == .functional_requirement,
                    .scenario_coverage => record.content == .acceptance_criterion or record.content == .edge_case or record.content == .user_visible_outcome,
                    else => return error.NotACollectionRequirement,
                };
                if (!matches) continue;
                try std.testing.expect(count < value.records.len);
                try std.testing.expectEqualDeep(record, value.records[count]);
                count += 1;
            }
            try std.testing.expectEqual(count, value.records.len);
            break :collection value.context;
        },
        .entity_applicability => |value| entity: {
            try std.testing.expectEqualStrings("entity_applicability", subject.get("kind").?.string);
            try std.testing.expectEqual(.entities, id.slot);
            try std.testing.expectEqual(content.entities.disposition, value.disposition);
            try std.testing.expectEqualDeep(try projection.scalar(a, context, content.entities.basis), value.basis);
            break :entity value.context;
        },
        else => return error.UnexpectedBusinessReviewSubject,
    };
    try std.testing.expectEqualDeep(resolved, related.candidate);
    try std.testing.expectEqualDeep(try projection.scalar(a, context, brief.title), related.brief.title);
    try std.testing.expectEqualDeep(try projection.scalar(a, context, brief.description), related.brief.description);
    try std.testing.expectEqualDeep(try projection.scalar(a, context, brief.primary_goal), related.brief.primary_goal);
    try std.testing.expectEqualDeep(try projection.scalar(a, context, content.entities.basis), related.entity_basis);
    try std.testing.expect(!subject.contains("instruction"));
    if (purpose == .principles) {
        try std.testing.expect(!input.contains("sources"));
    } else {
        try std.testing.expect(!input.contains("principles"));
        const model_evidence = @import("domain/model_evidence.zig");
        const all = try provenance.items(context);
        const projected = try model_evidence.project(a, all.entries);
        const records = inputs.references.?;
        const retained = .{
            .sources = try model_evidence.sources(a, context.inputs),
            .claims = projected.claims,
            .citations = projected.citations,
            .preserved_tokens = projected.preserved_tokens,
            .extraction = try model_evidence.extractionReview(a, context.inputs, all.extraction),
            .dispositions = records.dispositions,
            .signals = try model_evidence.signals(a, records.signals),
            .conflicts = try model_evidence.conflicts(a, records.conflicts),
        };
        inline for (std.meta.fields(@TypeOf(retained))) |field| {
            const actual = input.get(field.name) orelse return error.MissingSourceReconstructionEvidence;
            try std.testing.expect(actual == .array);
            try std.testing.expectEqualStrings(try @import("domain/model_candidate_json.zig").encode(field.type, a, @field(retained, field.name)), try std.json.Stringify.valueAlloc(a, actual, .{}));
        }
    }
}

fn expectReviewPurpose(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, packet: *const @import("domain/model_input_packet.zig").Packet, id: @import("domain/required_authority.zig").Id) !void {
    if (id.unit == .record) return expectRecordReviewPurpose(purpose, a, packet, id);
    return expectBusinessReviewPurpose(purpose, a, inputs, context, packet, id);
}

fn checkReviewRepairPurposes(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, good: @import("domain/specification_support.zig").Contract(purpose).Review, index: usize, business_id: @import("domain/required_authority.zig").Id) !void {
    const review = @import("domain/specification_support.zig").Contract(purpose);
    const repair = @import("domain/specification_support_repair.zig").Contract(purpose);
    const packets = @import("domain/model_input_packet.zig");
    const ledger = try @import("domain/required_authority.zig").build(a, inputs);
    const id = ledger.requirements[index].seed.id;
    const initial = try review.packetFor(std.testing.allocator, inputs, context, .{ .finding = id });
    defer packets.release(initial);
    const correction = try review.packetFor(std.testing.allocator, inputs, context, .{ .correction = id });
    defer packets.release(correction);
    for ([_]*const packets.Packet{ initial, correction }) |packet| try expectReviewPurpose(purpose, a, inputs, context, packet, business_id);
    try expectSameReviewSubject(a, initial, correction);
    const accepted = (try collectReview(review, a, inputs, context, try @import("domain/model_candidate_json.zig").encode(review.Review, a, good), null)).accepted;
    // These are native malformed-data repairs, not reconsideration of meaning.
    for (0..3) |mode| {
        var candidate = accepted.candidate;
        const rows = try a.dupe(review.Finding, good.entries);
        candidate.review.entries = rows;
        switch (mode) {
            0 => {
                const remaining = try a.alloc(review.Finding, rows.len - 1);
                @memcpy(remaining[0..index], rows[0..index]);
                @memcpy(remaining[index..], rows[index + 1 ..]);
                candidate.review.entries = remaining;
                const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, remaining.len);
                @memset(origins, null);
                candidate.origins = origins;
            },
            1 => rows[index].value.detail = "\x00",
            2 => if (purpose == .principles) {
                rows[index].value.citations = &.{.{ .chunk = .{ .ordinal = 999 }, .first_line = 1, .last_line = 1 }};
            } else {
                rows[index].value.provenance.claim_ids = &.{.{ .ordinal = 9999 }};
            },
            else => unreachable,
        }
        const rejected = (try review.validate(a, inputs, context.inputs, candidate)).rejected;
        try std.testing.expectEqualDeep(id, rejected.rejection.selected().?.requirement.?);
        try std.testing.expectEqual(@as(review.Issue, switch (mode) {
            0 => .missing_finding,
            1 => .invalid_detail,
            2 => .invalid_evidence,
            else => unreachable,
        }), rejected.rejection.selected().?.issue);
        const authorization = try repair.authorize(a, inputs, context, rejected);
        const packet = try repair.packet(std.testing.allocator, inputs, context, rejected.candidate.?, authorization);
        defer packets.release(packet);
        try expectReviewPurpose(purpose, a, inputs, context, packet, business_id);
        try expectSameReviewSubject(a, initial, packet);
        try std.testing.expectEqualDeep(id, authorization.target.requirement);
        const replacement: repair.Replacement = switch (mode) {
            0 => .{ .finding = good.entries[index].value },
            1 => .{ .detail = if (purpose == .source) .{ .detail = good.entries[index].value.detail, .question = good.entries[index].value.question } else .{ .detail = good.entries[index].value.detail } },
            2 => .{ .selection = if (purpose == .source) .{ .provenance = good.entries[index].value.provenance, .source_ids = good.entries[index].value.source_ids } else .{ .citations = good.entries[index].value.citations } },
            else => unreachable,
        };
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, rejected.candidate.?, authorization, replacement, null)).accepted;
        try review.validateStored(a, fixed.inputs, context.inputs);
        try std.testing.expectEqual(good.entries.len, fixed.candidate.review.entries.len);
        for (fixed.candidate.review.entries) |finding| try std.testing.expectEqualDeep(good.entries[finding.requirement_ordinal - 1], finding);
    }
}

test "principle review preserves business authority and retains cited advice through repair and readback" {
    const source_review = @import("domain/specification_support.zig").Source;
    const policy_review = @import("domain/specification_support.zig").Contract(.principles);
    const repair = @import("domain/specification_support_repair.zig").Contract(.principles);
    const assessment = @import("domain/principle_assessment.zig");
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const progress = @import("domain/specification_review.zig");
    const sessions = @import("domain/specification_session.zig");
    for ([_][2][]const u8{
        .{ "Show the current UTC date and time.", "Display dates in the visitor's local timezone.\n" },
        .{ "Retain loan receipts for seven years.", "Delete all loan receipts after thirty days.\n" },
    }) |example| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, example[0]);
        defer fixture.deinit();
        const current = try completedFixture(&fixture, false);
        const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
        var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
        inputs.revision = current.revision;
        const source = try collectReview(source_review, a, inputs, fixture.context, try json.encode(source_review.Review, a, try reviewFor(a, inputs, fixture.context.inputs)), null);
        const policies = try @import("test_fixtures/principles.zig").registry(a, example[1]);
        const advanced = try progress.advance(a, .{ .source = source }, policies);
        try std.testing.expectEqual(.more, advanced.outcome);
        const pending = advanced.progress.pending;
        const policy_inputs = pending.inputs;
        const ledger = try authority.build(a, policy_inputs);
        try std.testing.expect(ledger.requirements.len >= 7);
        const packet = try reviewPacketAt(policy_review, std.testing.allocator, policy_inputs, fixture.context, 0);
        defer @import("domain/model_input_packet.zig").release(packet);
        const initial_packet = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        try std.testing.expectEqualStrings("field", initial_packet.get("subject").?.object.get("kind").?.string);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "toolchain.yaml") == null);
        const source_packet = try reviewPacketAt(source_review, std.testing.allocator, inputs, fixture.context, 0);
        defer @import("domain/model_input_packet.zig").release(source_packet);
        try std.testing.expect(std.mem.indexOf(u8, source_packet.body(), example[1]) == null);
        const findings = try a.alloc(policy_review.Finding, ledger.requirements.len);
        for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = if (index == 0) .conflicting else .compatible, .citations = if (index == 0) &.{.{ .chunk = policies.chunks[0].id, .first_line = 1, .last_line = 1 }} else &.{}, .detail = if (index == 0) "The explicit business requirement conflicts with the selected policy; Plan must resolve the choice." else "" } };
        try checkDetailRepair(.principles, a, policy_inputs, fixture.context, .{ .entries = findings });
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
        const good = try collectReview(policy_review, a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = findings }), origin);
        try std.testing.expect(good == .accepted);
        const canonical = try assessment.canonical(a, good.accepted.inputs);
        try std.testing.expectEqual(.all_resolved, canonical.result.continuation);
        try std.testing.expect(canonical.result.entries[0].outcome == .assessment_complete);
        try std.testing.expectEqual(.conflicting, canonical.evidence[0].finding);
        try assessment.validateStored(a, source.accepted.inputs, fixture.context.inputs, canonical);
        try std.testing.expectError(error.InvalidRequiredAuthority, assessment.canonical(a, policy_inputs));
        const ready = try progress.advance(a, .{ .principles = .{ .pending = pending, .result = good } }, policies);
        try std.testing.expectEqual(.complete, ready.outcome);
        try std.testing.expectEqualDeep(source.accepted.inputs.specification, ready.progress.source.accepted.inputs.specification);
        try std.testing.expectEqualDeep(source.accepted.inputs.evidence, ready.progress.source.accepted.inputs.evidence);
        try std.testing.expect(ready.progress.source.accepted.inputs.principle_assessment != null);
        for (0..12) |mode| {
            var invalid = canonical;
            switch (mode) {
                0 => invalid.evidence = &.{},
                1 => invalid.requirements = invalid.requirements[1..],
                2 => invalid.selection.chunks = &.{},
                3 => invalid.candidate_revision += 1,
                4 => invalid.result.entries = &.{},
                5 => invalid.selection.registry.revision += 1,
                6 => {
                    const evidence_copy = try a.dupe(authority.Evidence, invalid.evidence);
                    evidence_copy[0].review.?.principle_citations = &.{.{ .chunk = .{ .ordinal = 999 }, .first_line = 1, .last_line = 1 }};
                    invalid.evidence = evidence_copy;
                },
                7 => invalid.result.continuation = .needs_user,
                8 => {
                    invalid.registry.id.root.file_id += 1;
                    invalid.registry.inventory.root.identity = invalid.registry.id.root;
                    invalid.selection.registry = invalid.registry.id;
                },
                9 => {
                    const candidates = try a.dupe(authority.Candidate, invalid.candidates);
                    candidates[0].id.revision += 1;
                    invalid.candidates = candidates;
                },
                10 => {
                    const evidence_copy = try a.dupe(authority.Evidence, invalid.evidence);
                    evidence_copy[0].resolution.assessment.candidate.ordinal += 1;
                    invalid.evidence = evidence_copy;
                },
                11 => {
                    const evidence_copy = try a.dupe(authority.Evidence, invalid.evidence);
                    evidence_copy[0].resolution = .{ .supported_candidate = canonical.candidates[0].id };
                    invalid.evidence = evidence_copy;
                },
                else => unreachable,
            }
            if (assessment.validateStored(a, source.accepted.inputs, fixture.context.inputs, invalid)) |_| return error.ExpectedInvalidPolicyEvidence else |err| try std.testing.expect(err != error.OutOfMemory);
        }
        // An invalid citation is repaired without changing the negative decision.
        const broken = try a.dupe(policy_review.Finding, findings);
        broken[0].value.citations = &.{.{ .chunk = .{ .ordinal = 999 }, .first_line = 1, .last_line = 1 }};
        const rejected = (try collectReview(policy_review, a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = broken }), origin)).rejected;
        const authorization = try repair.authorize(a, policy_inputs, fixture.context, rejected);
        const request = try repair.packet(std.testing.allocator, policy_inputs, fixture.context, rejected.candidate.?, authorization);
        defer @import("domain/model_input_packet.zig").release(request);
        try std.testing.expectEqualStrings("principle_selection", request.resultDefinition().?.bytes);
        const citation_diagnostic = rejected.rejection.selected().?.evidence.?.citation.?;
        try std.testing.expectEqual(@as(usize, 0), citation_diagnostic.index);
        try std.testing.expectEqualDeep(@import("domain/principle_registry.zig").CitationDiagnostic{ .field = .chunk, .rejected = 999 }, citation_diagnostic.diagnostic);
        const repair_packet = try std.json.parseFromSlice(std.json.Value, a, request.body(), .{});
        try expectSameReviewSubject(a, packet, request);
        const guidance_rule = repair_packet.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expectEqualStrings("chunk", guidance_rule.get("citation").?.object.get("diagnostic").?.object.get("field").?.string);
        try std.testing.expectEqual(@as(i64, 999), guidance_rule.get("citation").?.object.get("diagnostic").?.object.get("rejected").?.integer);
        try std.testing.expectEqual(policies.chunks.len, guidance_rule.get("evidence_rule").?.object.get("permitted_chunks").?.array.items.len);
        // A changed line error carries current bounds through the same repair path.
        const wrong_lines = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), policy_inputs, fixture.context, rejected.candidate.?, authorization, .{ .selection = .{ .citations = &.{.{ .chunk = policies.chunks[0].id, .first_line = 1, .last_line = 2 }} } }, origin);
        const line_rejection = wrong_lines.rejected.rejection.selected().?.evidence.?.citation.?.diagnostic;
        try std.testing.expectEqualDeep(@import("domain/principle_registry.zig").CitationDiagnostic{ .field = .last_line, .rejected = 2, .bounds = .{ .minimum = 1, .maximum = 1 } }, line_rejection);
        const line_authorization = try repair.authorize(a, policy_inputs, fixture.context, wrong_lines.rejected);
        const line_packet = try repair.packet(std.testing.allocator, policy_inputs, fixture.context, wrong_lines.rejected.candidate.?, line_authorization);
        defer @import("domain/model_input_packet.zig").release(line_packet);
        const line_guidance = try std.json.parseFromSlice(std.json.Value, a, line_packet.body(), .{});
        const bound = line_guidance.value.object.get("repair").?.object.get("rule").?.object.get("citation").?.object.get("diagnostic").?.object.get("bounds").?.object;
        try std.testing.expectEqual(@as(i64, 1), bound.get("maximum").?.integer);
        var stale_inputs = policy_inputs;
        stale_inputs.principle_context.?.selection.registry.revision += 1;
        try std.testing.expectError(error.InvalidPrincipleRegistry, assessment.admit(a, stale_inputs, ledger.requirements[0].seed.id, broken[0].value));
        try std.testing.expectError(error.InvalidRequiredAuthority, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), stale_inputs, fixture.context, rejected.candidate.?, authorization, .{ .selection = .{ .citations = findings[0].value.citations } }, origin));
        const replacement = try repair.parse(a, authorization, request, "{\"citations\":[{\"chunk\":1,\"first_line\":1,\"last_line\":1}]}");
        const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), policy_inputs, fixture.context, rejected.candidate.?, authorization, .{ .selection = .{ .citations = broken[0].value.citations } }, origin);
        try std.testing.expect(unchanged == .rejected);
        const recovered = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), policy_inputs, fixture.context, rejected.candidate.?, authorization, replacement, .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } })).accepted;
        try std.testing.expectEqual(.conflicting, recovered.candidate.review.entries[0].value.decision);
        try std.testing.expectEqualDeep(findings[1..], recovered.candidate.review.entries[1..]);
        try std.testing.expectEqual(@as(u64, 2), recovered.candidate.revision);
        try std.testing.expectEqualDeep(origin, recovered.candidate.origins[1].?);
        try assessment.validateStored(a, source.accepted.inputs, fixture.context.inputs, try assessment.canonical(a, recovered.inputs));
        const missing = (try collectReview(policy_review, a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = findings[1..] }), origin)).rejected;
        const insert = try repair.authorize(a, policy_inputs, fixture.context, missing);
        try std.testing.expect(insert.operation == .insert);
        const insert_packet = try repair.packet(std.testing.allocator, policy_inputs, fixture.context, missing.candidate.?, insert);
        defer @import("domain/model_input_packet.zig").release(insert_packet);
        try expectSameReviewSubject(a, packet, insert_packet);
        const inserted = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), policy_inputs, fixture.context, missing.candidate.?, insert, .{ .finding = findings[0].value }, origin)).accepted;
        try std.testing.expectEqualDeep(findings[1..], inserted.candidate.review.entries[0 .. findings.len - 1]);
        _ = try assessment.canonical(a, inserted.inputs);
        const duplicate = try std.mem.concat(a, policy_review.Finding, &.{ findings, findings[0..1] });
        duplicate[1].requirement_ordinal = 999;
        duplicate[0].value.citations = &.{};
        const multiple = (try collectReview(policy_review, a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = duplicate }), origin)).rejected;
        try std.testing.expect(multiple.rejection.diagnostics.len >= 4);
        var stale = policies;
        stale.id.revision += 1;
        try std.testing.expectError(error.InvalidRequiredAuthority, progress.advance(a, .{ .principles = .{ .pending = pending, .result = good } }, stale));
        // Policy evidence cannot satisfy the source-preservation contract.
        var borrowed = source.accepted.inputs;
        const source_evidence = try a.dupe(authority.Evidence, borrowed.evidence);
        source_evidence[0].review.?.principle_citations = findings[0].value.citations;
        borrowed.evidence = source_evidence;
        try std.testing.expectError(error.InvalidRequiredAuthority, source_review.validateStored(a, borrowed, fixture.context.inputs));
    }
}

test "specification repair occurrence keys survive preceding record deletion" {
    const candidates = @import("domain/specification_candidate.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original: candidates.Origins = .{};
    const target: candidates.Target = .{ .value = .{ .subject = .{ .record = 2 }, .field = .text } };
    const stable = try original.stableTarget(target, 3);
    const deleted = try original.deleting(a, 1, 3);
    try std.testing.expectEqualDeep(stable, try deleted.stableTarget(.{ .value = .{ .subject = .{ .record = 1 }, .field = .text } }, 2));
    try std.testing.expectEqualDeep(candidates.Target{ .value = .{ .subject = .{ .record = 1 }, .field = .text } }, (try deleted.currentTarget(stable, 2)).?);
    const removed = try original.stableTarget(.{ .record = 1 }, 3);
    try std.testing.expect((try deleted.currentTarget(removed, 2)) == null);
}

test "multiple missing exact obligations do not authorize invalid insertion-only reconstruction" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_coverage_repair.zig");
    const check = @import("actions/specification/validate_specification_coverage.zig").Action{ .validator = text.validator };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Display `Accepted!` and `Ready!`.");
    defer fixture.deinit();
    const all = try provenance.items(fixture.context);
    const good = try fixture.proposal("The requested outcome is observable.");
    var records: std.ArrayList(spec.Model.RecordProposal) = .empty;
    for (all.entries) |entry| if (entry.claim.content == .preserved_token) {
        const raw = entry.claim.content.preserved_token.value.raw_value.bytes;
        try records.append(a, .{ .content = .{ .user_visible_outcome = .{ .text = .{ .segments = try a.dupe(@import("domain/typed_text.zig").BusinessSegment, &.{ .{ .literal = .{ .value = raw[0..2] } }, .{ .literal = .{ .value = raw[2..] } }, .{ .literal = .{ .value = "suffix" } } }) } } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance });
    };
    try std.testing.expectEqual(@as(usize, 2), records.items.len);
    const title = try fixture.proposalAllGroups("The requested outcomes are named.");
    var current = (try sessions.initialize(a, .{ .bytes = "chosen" }, fixture.context)).ready;
    while (current.completed < sessions.unit_count) {
        const unit = try sessions.unit(current.completed);
        const response: g.Response = .{ .content = switch (unit) {
            .brief => .{ .brief = .{ .title = title, .description = good, .primary_goal = good } },
            .primary_user_story => .{ .primary_user_story = good },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
            .records => .{ .records = records.items },
        } };
        current = try appendMockResponse(a, current, fixture.context, response);
    }
    const initial = (try sessions.assemble(a, text.validator, fixture.context, current)).content;
    const before = try std.json.Stringify.valueAlloc(a, current, .{});
    const rejected = (try check.execute(a, current, fixture.context, initial)).invalid;
    try std.testing.expect(rejected.issue == .missing_exact_copy);
    const decision = try repair.authorize(a, current, fixture.context, initial, rejected);
    try std.testing.expectEqual(.no_independent_supported_target, decision.blocked.blocked.?);
    try std.testing.expectEqualStrings(before, try std.json.Stringify.valueAlloc(a, current, .{}));
}

fn checkSourceOmissionProgress(a: std.mem.Allocator, permit: @import("domain/workflow_retry.zig").Permit, negative: @import("domain/source_omission.zig").Support, context: provenance.Context, fixture: *const Fixture) !void {
    const loss = @import("domain/source_omission.zig");
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    try std.testing.expectEqual(negative.inputs.projection, (try loss.pendingReview(a, permit, context.inputs.corpus.feature_id, context.inputs.corpus.state_id)).?);
    try checkNativeSourceReviewGates(permit, negative.inputs.projection, context);
    var unreviewed = negative.inputs;
    unreviewed.evidence = &.{};
    unreviewed.candidates = &.{};
    const negative_admitted = (try support.validate(a, unreviewed, context.inputs, negative.review)).accepted;
    try std.testing.expectEqual(.recurring, (try loss.admittedValidation(a, permit, negative_admitted)).?.validated.result);
    const renewed_inputs = if (negative.inputs.projection == .source_preservation)
        try @import("domain/source_preservation.zig").project(a, context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(context.references), context.inputs)
    else
        try @import("domain/specification_authority.zig").project(a, context.inputs.corpus.feature_id, context.references, null, null);
    const reviewed = (try collectReview(support, a, renewed_inputs, context, try json.encode(support.Review, a, try reviewFor(a, renewed_inputs, context.inputs)), null)).accepted;
    try std.testing.expectEqual(.all_resolved, (try supportDecision(a, reviewed.inputs)).result.continuation);
    try std.testing.expectEqual(.resolved, (try loss.admittedValidation(a, permit, reviewed)).?.validated.result);
    const foreign_purpose = if (negative.inputs.projection == .source_preservation)
        try @import("domain/specification_authority.zig").project(a, context.inputs.corpus.feature_id, context.references, null, null)
    else
        try @import("domain/source_preservation.zig").project(a, context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(context.references), context.inputs);
    const wrong_review = (try collectReview(support, a, foreign_purpose, context, try json.encode(support.Review, a, try reviewFor(a, foreign_purpose, context.inputs)), null)).accepted;
    try std.testing.expectError(error.InvalidRequiredAuthority, loss.admittedValidation(a, permit, wrong_review));
    try checkNativeApplySourceRejection(permit, wrong_review);
    // Even a mechanically accepted, current generated assessment cannot close
    // the earlier required source repair's dependent semantic validation.
    var generated_fixture = fixture.*;
    generated_fixture.context = context;
    const generated_inputs = try completedSupportInputs(&generated_fixture);
    const advisory = (try collectReview(support, a, generated_inputs, context, try json.encode(support.Review, a, try reviewFor(a, generated_inputs, context.inputs)), null)).accepted;
    try support.validateStored(a, advisory.inputs, context.inputs);
    try std.testing.expectEqual(.advisory, @import("domain/required_authority.zig").assessmentPolicy(advisory.inputs.projection));
    try std.testing.expectError(error.InvalidRequiredAuthority, loss.admittedValidation(a, permit, advisory));
    try checkNativeApplySourceRejection(permit, advisory);
    for (0..4) |scenario| {
        var altered = permit;
        switch (scenario) {
            0 => altered.key.scope[0] ^= 1,
            1 => altered.key.target[0] ^= 1,
            2 => altered.revision = std.math.maxInt(u64),
            3 => altered.key.family[0] ^= 1,
            else => unreachable,
        }
        if (scenario == 3) {
            try std.testing.expect((try loss.admittedValidation(a, altered, reviewed)) == null);
            try std.testing.expect((try loss.pendingReview(a, altered, context.inputs.corpus.feature_id, context.inputs.corpus.state_id)) == null);
        } else {
            // All source-purpose duties now have explicit admitted source
            // evidence. A removed/changed target cannot borrow that progress.
            if (scenario == 1) {
                try std.testing.expect(!std.meta.eql(permit.key.target, altered.key.target));
                try std.testing.expectEqual(negative.inputs.projection, (try loss.pendingReview(a, altered, context.inputs.corpus.feature_id, context.inputs.corpus.state_id)).?);
            }
            try std.testing.expectError(error.InvalidRequiredAuthority, loss.admittedValidation(a, altered, reviewed));
        }
    }
    for ([_]bool{ false, true }) |source| {
        var foreign = reviewed;
        if (source) foreign.inputs.references.?.items.state_id.bytes = "foreign-state" else foreign.inputs.feature.bytes = "foreign-feature";
        try std.testing.expectError(error.InvalidRequiredAuthority, loss.admittedValidation(a, permit, foreign));
        try std.testing.expectError(error.InvalidRequiredAuthority, loss.pendingReview(a, permit, foreign.inputs.feature, foreign.inputs.references.?.items.state_id));
    }
    var foreign_evidence = reviewed.inputs;
    const entries = try a.dupe(@import("domain/required_authority.zig").Evidence, reviewed.inputs.evidence);
    entries[0].review.?.source_ids = &.{.{ .ordinal = 999 }};
    foreign_evidence.evidence = entries;
    try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, foreign_evidence, context.inputs));
}

fn checkNativeApplySourceRejection(permit: @import("domain/workflow_retry.zig").Permit, reviewed: @FieldType(@import("domain/specification_support.zig").Source.Collection, "accepted")) !void {
    const values = @import("application/pipeline_values.zig");
    const owned = @import("application/required_authority_values.zig");
    const native = @import("application/specification_support_workflow.zig");
    const authority = @import("application/required_authority_workflow.zig");
    const data = @import("domain/pipeline_data.zig");
    const retry = @import("domain/workflow_retry.zig");
    const source_value = value: {
        const owner = try owned.create(std.testing.allocator, .{});
        errdefer owned.destroy(owner);
        owner.payload = .{ .inputs = reviewed.inputs };
        break :value try values.adopt(std.testing.allocator, authority.inputs_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
    };
    defer values.destroy(source_value);
    var view: data.View = .{};
    view.slots[@intFromEnum(authority.inputs_schema.key)] = source_value;
    const review_value = value: {
        const owner = try owned.create(std.testing.allocator, view);
        errdefer owned.destroy(owner);
        owner.payload = .{ .support = .{ .accepted = reviewed } };
        break :value try values.adopt(std.testing.allocator, native.schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
    };
    defer values.destroy(review_value);
    view.slots[@intFromEnum(native.schema.key)] = review_value;
    var state = retry.State.init(std.testing.allocator);
    defer state.deinit();
    try state.commit(try state.prepare(.{ .authorized = permit }));
    try state.commit(try state.prepare(.{ .merged = .{ .permit = permit, .revision_after = permit.revision + 1, .changed = true, .validation = .dependent_review } }));
    const revision = state.revision;
    var input = try projectionOperationInput(native.Apply, view);
    input.step.repair_permit = state.currentPermit();
    var apply: native.Apply = .{ .allocator = std.testing.allocator };
    const result = try native.Apply.invoke(&apply, input);
    const rejected = result.delta.data_replacements[@intFromEnum(authority.inputs_schema.key)] orelse return error.ExpectedRejectedAuthority;
    defer values.destroy(rejected);
    try std.testing.expectEqual(.invalid, result.outcome);
    try std.testing.expectEqual(error.InvalidRequiredAuthority, result.diagnostic.?);
    try std.testing.expect(result.delta.repair_transition == null);
    for (result.delta.data_writes) |slot| try std.testing.expect(slot == null);
    const shape = @import("domain/pipeline.zig").DataShape.init(native.Apply.Action.contract.requires);
    _ = try shape.applyDelta(native.Apply.Action.contract, &result.delta);
    const rejected_view: data.View = .{ .slots = result.delta.data_replacements };
    try std.testing.expectError(error.InvalidRequiredAuthority, owned.read(&rejected_view, authority.inputs_schema, .inputs));
    try std.testing.expectEqual(error.InvalidRequiredAuthority, owned.rejection(try values.read(&rejected_view, authority.inputs_schema, owned.Value)).?);
    try std.testing.expectEqualDeep(reviewed.inputs, try owned.read(&view, authority.inputs_schema, .inputs));
    try std.testing.expectEqualDeep(reviewed.candidate, (try owned.read(&view, native.schema, .support)).accepted.candidate);
    try std.testing.expectEqualDeep(permit, state.currentPermit().?);
    try std.testing.expectEqual(revision, state.revision);
}

fn checkNativeSourceReviewGates(permit: @import("domain/workflow_retry.zig").Permit, projection: @import("domain/required_authority.zig").Projection, context: provenance.Context) !void {
    const values = @import("application/pipeline_values.zig");
    const data = @import("domain/pipeline_data.zig");
    const sources = @import("application/reference_evidence_workflow.zig").inputs_schema;
    const accounted = @import("application/reference_reconciliation_workflow.zig").accounted_schema;
    const owned = @import("domain/reference_candidate_value.zig");
    const readiness = @import("application/specification_workflow.zig").SourceReadiness;
    const preservation_gate = @import("application/required_authority_workflow.zig").SourcePreservationPolicy;
    const source_value = try values.create(std.testing.allocator, sources, @import("domain/reference_evidence.zig").Inputs, context.inputs);
    defer values.destroy(source_value);
    const reference_value = value: {
        const owner = try owned.create(std.testing.allocator, null);
        errdefer owned.destroy(owner);
        owner.payload = .{ .reconciliation_accounted = context.references };
        break :value try values.adopt(std.testing.allocator, accounted, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
    };
    defer values.destroy(reference_value);
    var view: data.View = .{};
    view.slots[@intFromEnum(sources.key)] = source_value;
    view.slots[@intFromEnum(accounted.key)] = reference_value;
    var ready: readiness = .{ .allocator = std.testing.allocator };
    const disabled: @import("domain/config.zig").ValidationConfig = .{ .sourcePreservationCheck = false };
    var preserve: preservation_gate = .{ .allocator = std.testing.allocator, .policy = &disabled };
    try std.testing.expect(provenance.generationReady(context.references));
    for ([_]?@import("domain/workflow_retry.zig").Permit{ null, permit }) |active| {
        var readiness_input = try projectionOperationInput(readiness, view);
        readiness_input.step.repair_permit = active;
        const ready_result = try readiness.invoke(&ready, readiness_input);
        const ready_outcome: @import("domain/workflow.zig").OutcomeTag = if (active != null and projection == .source_readiness) .blocked else .ok;
        try std.testing.expectEqual(ready_outcome, ready_result.outcome);
        var preservation_input = try projectionOperationInput(preservation_gate, view);
        preservation_input.step.repair_permit = active;
        const preserved = try preservation_gate.invoke(&preserve, preservation_input);
        const preserve_outcome: @import("domain/workflow.zig").OutcomeTag = if (active != null and projection == .source_preservation) .ok else .more;
        try std.testing.expectEqual(preserve_outcome, preserved.outcome);
    }
    var foreign = permit;
    foreign.key.scope[0] ^= 1;
    var readiness_input = try projectionOperationInput(readiness, view);
    readiness_input.step.repair_permit = foreign;
    const invalid_readiness = try readiness.invoke(&ready, readiness_input);
    try std.testing.expectEqual(.invalid, invalid_readiness.outcome);
    try std.testing.expectEqual(error.InvalidRequiredAuthority, invalid_readiness.diagnostic.?);
    var preservation_input = try projectionOperationInput(preservation_gate, view);
    preservation_input.step.repair_permit = foreign;
    const invalid_preservation = try preservation_gate.invoke(&preserve, preservation_input);
    try std.testing.expectEqual(.invalid, invalid_preservation.outcome);
    try std.testing.expectEqual(error.InvalidRequiredAuthority, invalid_preservation.diagnostic.?);
}

fn checkDetailRepair(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, good: @import("domain/specification_support.zig").Contract(purpose).Review) !void {
    const review = @import("domain/specification_support.zig").Contract(purpose);
    const repair = @import("domain/specification_support_repair.zig").Contract(purpose);
    const detail_owner = @import("domain/specification_support_evidence.zig");
    const original: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: @TypeOf(original) = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const collected = try collectReview(review, a, inputs, context, try @import("domain/model_candidate_json.zig").encode(review.Review, a, good), original);
    const admitted = collected.accepted;
    try review.validateStored(a, admitted.inputs, context.inputs);
    const oversized = try std.mem.concat(a, u8, &.{ "é" ** 1000, "x" });
    for ([_][]const u8{ "", " \t\n", "\x00", oversized }) |invalid| {
        const rows = try a.dupe(review.Finding, good.entries);
        rows[0].value.detail = invalid;
        var candidate = admitted.candidate;
        candidate.review.entries = rows;
        const rejected = (try review.validate(a, inputs, context.inputs, candidate)).rejected;
        try std.testing.expectEqual(.invalid_detail, rejected.rejection.selected().?.issue);
        const authorization = try repair.authorize(a, inputs, context, rejected);
        const packet = try repair.packet(a, inputs, context, candidate, authorization);
        defer @import("domain/model_input_packet.zig").release(packet);
        if (purpose == .principles) {
            const initial = try review.packetFor(a, inputs, context, .{ .finding = authorization.target.requirement });
            defer @import("domain/model_input_packet.zig").release(initial);
            try expectSameReviewSubject(a, initial, packet);
        }
        var schema_parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schemas = try schema_parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
        const selected = schemas.select(packet.resultDefinition().?).?;
        const codec = @import("domain/model_candidate_json.zig");
        var expected = authorization.operation.replace;
        expected.detail.detail = good.entries[0].value.detail;
        if (purpose == .source) expected.detail.question = good.entries[0].value.question;
        try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = try codec.encodeSelected(repair.Replacement, a, expected) });
        if (purpose == .principles) try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = "{\"detail\":\"Known facts.\",\"question\":\"Which rule applies?\"}", .rejection = .unknown_property, .path = "/question" });
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const repair_rule = body.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expect(!repair_rule.contains("finding"));
        try std.testing.expectEqualStrings(@tagName(review.decisionOf(good.entries[0].value)), repair_rule.get("decision").?.string);
        const rule = repair_rule.get("detail_rule").?.object;
        try std.testing.expect(!rule.get("allow_empty").?.bool);
        try std.testing.expectEqual(@as(i64, @import("domain/clarification_inputs.zig").max_text_bytes), rule.get("maximum_utf8_bytes").?.integer);
        try std.testing.expect(std.mem.indexOf(u8, rule.get("instruction").?.string, "retained finding") != null);
        try std.testing.expect(std.mem.indexOf(u8, rule.get("instruction").?.string, "known facts/preconditions") != null);
        if (purpose == .source) {
            const question_rule = repair_rule.get("question_rule").?.string;
            try std.testing.expect(std.mem.indexOf(u8, question_rule, "affects required behavior") != null);
            try std.testing.expect(std.mem.indexOf(u8, question_rule, "answer format that resolves it") != null);
        }
        const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, candidate, authorization, .{ .detail = .{ .detail = invalid } }, corrected);
        try std.testing.expect(unchanged == .rejected);
        var corrected_detail = authorization.operation.replace;
        corrected_detail.detail.detail = good.entries[0].value.detail;
        if (purpose == .source) corrected_detail.detail.question = good.entries[0].value.question;
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, candidate, authorization, corrected_detail, corrected)).accepted;
        try std.testing.expectEqualDeep(good, fixed.candidate.review);
        try std.testing.expectEqualDeep(corrected, fixed.candidate.origins[0].?);
        try std.testing.expectEqualDeep(original, fixed.candidate.origins[1].?);
        try review.validateStored(a, fixed.inputs, context.inputs);
        const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, fixed.inputs.evidence);
        proofs[0].review.?.detail = invalid;
        var corrupt = fixed.inputs;
        corrupt.evidence = proofs;
        try std.testing.expectError(error.InvalidRequiredAuthority, review.validateStored(a, corrupt, context.inputs));
        // Missing-finding insertion uses the same full admission, including detail.
        var absent = admitted.candidate;
        absent.review.entries = good.entries[1..];
        absent.origins = absent.origins[1..];
        absent.occurrences = .{};
        const missing = (try review.validate(a, inputs, context.inputs, absent)).rejected;
        const insert = try repair.authorize(a, inputs, context, missing);
        try std.testing.expect((try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, missing.candidate.?, insert, .{ .finding = rows[0].value }, corrected)) == .rejected);
    }
    try std.testing.expect(!detail_owner.detailRule(.supported).accepts("\xc0"));
    try std.testing.expect(detail_owner.detailRule(.supported).accepts(""));
    try std.testing.expect(!detail_owner.detailRule(.unsupported).accepts(""));
}

// Metadata outlives neither its original graph nor execution arena. Only the
// serialized comparison evidence crosses to the new invocation.
test "persisted extraction binding resolves fresh compiled authority after original owners are released" {
    const contract = @import("domain/reference_extraction_contract.zig");
    const fixture_type = @import("test_fixtures/extraction_contract.zig").Fixture;
    const bytes = capture: {
        var execution_arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer execution_arena.deinit();
        const a = execution_arena.allocator();
        const original = try fixture_type.init(a);
        const binding = try contract.capture(a, original.authority, .source_blocks_v1);
        break :capture try std.json.Stringify.valueAlloc(std.testing.allocator, binding, .{});
    };
    defer std.testing.allocator.free(bytes);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stored = try @import("domain/strict_json.zig").decode(contract.Binding, a, bytes, .{ .maximum_bytes = 10000, .maximum_depth = 32 });
    var current = try fixture_type.init(a);
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(contract.validate, .{ stored, &current.authority, .source_blocks_v1 });
    current.authority.workflow_version += 1;
    try std.testing.expectError(error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE, contract.validate(a, stored, &current.authority, .source_blocks_v1));
    current.authority.workflow_version -= 1;
    // Same resource IDs and workflow version, changed schema bytes.
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const changed_schema = try parser.compiler().compile(a, try std.mem.replaceOwned(u8, a, stored.extractions[0].result_schema.bytes, "100", "99"));
    const changed_plan = try parser.compiler().compileComposition(a, stored.extractions[0].composition.bytes, changed_schema);
    const resources = try a.dupe(@import("domain/workflow_compilation.zig").CompiledResource, current.authority.resources);
    resources[0].content = .{ .result_schema = changed_schema };
    resources[1].content = .{ .json_composition = changed_plan };
    current.authority.resources = resources;
    try std.testing.expectError(error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE, contract.validate(a, stored, &current.authority, .source_blocks_v1));
}

test "incomplete specifications publish supported business evidence and bound questions without completion authority" {
    const draft = @import("domain/incomplete_specification.zig");
    const codec = @import("domain/incomplete_specification_markdown.zig");
    const state = @import("domain/specification_state.zig");
    const c = @import("domain/clarification_inputs.zig");
    const cf = @import("test_fixtures/clarification_inputs.zig");
    const json = @import("domain/canonical_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "When started, display MOCK Hello, World! and the UTC date and time.", "The borrower receives a renewal receipt." }) |source| {
        var fixture = try Fixture.initContent(a, source, .business_exact_string, true, source, 1);
        defer fixture.deinit();
        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
        const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
        const snapshot = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "first" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
        var record = cf.record("S01");
        record.authority = &.{.{ .reference = snapshot.inputs.corpus.state_id }};
        var clarification = cf.state(&.{record});
        clarification.feature_id = snapshot.inputs.corpus.feature_id.bytes;
        const validated = try c.validate(.{ .value = clarification }, snapshot.inputs.corpus.feature_id);
        const prior: state.Prior = .{ .captured = null };
        const value = try draft.build(a, prior, snapshot, validated, contracts.port());
        const rendered = try codec.render(a, value, validated);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "Status: Incomplete") != null);
        // Exact business text is escaped by the canonical Markdown owner.
        var escaped: std.Io.Writer.Allocating = .init(a);
        try @import("domain/specification_markdown.zig").literal(&escaped.writer, source);
        try std.testing.expect(std.mem.indexOf(u8, rendered, escaped.written()) != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "[S01](clarify/S01.md)") != null);
        // The pending projection shares reference classification, not keyword rules.
        var technical = value;
        const technical_claims = try a.dupe(@import("domain/reference_extraction.zig").Claim, value.reference.extraction.claims);
        const technical_signals = try a.dupe(@import("domain/reference_reconciliation.zig").Signal, value.reference.signals);
        try std.testing.expectEqual(@as(usize, 1), technical_claims.len);
        try std.testing.expectEqual(@as(usize, 1), technical_signals.len);
        technical_claims[0].content = .{ .model = .{ .technical = .{ .value = .{ .nodes = &.{.{ .literal = .{ .value = source } }} } } } };
        technical_signals[0].value.content = .{ .model = technical_claims[0].content.model };
        technical.reference.extraction.claims = technical_claims;
        technical.reference.signals = technical_signals;
        try draft.validate(a, technical, value.feature, contracts.port());
        const without_technical = try codec.render(a, technical, validated);
        try std.testing.expect(std.mem.indexOf(u8, without_technical, escaped.written()) == null);
        try std.testing.expect(std.mem.indexOf(u8, try @import("domain/reference_context.zig").render(a, technical.reference, null, null), escaped.written()) != null);

        try std.testing.expectError(error.InvalidSpecification, @import("domain/specification_markdown.zig").parse(a, rendered));
        const bytes = try json.encode(draft.State, a, value);
        const unknown = try std.mem.concat(a, u8, &.{ "{\"unknown\":true,", bytes[1..] });
        try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, unknown, value.feature, contracts.port()));
        const restored = try state.parse(a, bytes, value.feature, contracts.port());
        try std.testing.expect(restored.value == .pending and restored.specified() == null);
        try std.testing.expectEqualStrings(rendered, try codec.render(a, restored.value.pending, validated));
        try std.testing.expectEqual(@as(u64, 2), try state.nextRevision(restored));
        var successor = restored;
        successor.value.pending.id_ledger.next[0] = 42;
        const next = try draft.build(a, successor, snapshot, validated, contracts.port());
        try std.testing.expectEqual(@as(u32, 42), next.id_ledger.next[0]);
        try std.testing.expectEqual(@as(u64, 2), next.revision);
        try std.testing.expectError(error.REFERENCE_EXTRACTION_CONTRACT_UNAVAILABLE, state.parse(a, bytes, value.feature, null));
        for (0..9) |mode| {
            var bad = value;
            switch (mode) {
                0 => bad.open_clarifications = &.{},
                1 => bad.open_clarifications = &.{ .{ .stage = .spec, .ordinal = 1 }, .{ .stage = .spec, .ordinal = 1 } },
                2 => bad.open_clarifications = &.{.{ .stage = .plan, .ordinal = 1 }},
                3 => bad.open_clarifications = &.{.{ .stage = .spec, .ordinal = 0 }},
                4 => bad.feature = .{ .bytes = "foreign" },
                5 => bad.clarification.revision = 0,
                6 => bad.schema = "specification-state/v15",
                7 => bad.id_ledger.next[0] = 0,
                8 => bad.schema = "specification-state/v16",
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try json.encode(draft.State, a, bad), value.feature, contracts.port()));
        }
        const forged = try std.mem.replaceOwned(u8, a, bytes, "spec_clarification_pending", "specified");
        try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, forged, value.feature, contracts.port()));
        var stale = value;
        stale.clarification.revision += 1;
        try std.testing.expectError(error.InvalidIncompleteSpecification, codec.render(a, stale, validated));
        stale = value;
        stale.open_clarifications = &.{.{ .stage = .spec, .ordinal = 2 }};
        try std.testing.expectError(error.InvalidIncompleteSpecification, codec.render(a, stale, validated));
        const closed_records = try a.dupe(c.Record, clarification.records);
        closed_records[0].status = .resolved_by_authority;
        closed_records[0].authority_resolution = "Resolved from current sources.";
        var closed = clarification;
        closed.records = closed_records;
        try std.testing.expectError(error.InvalidIncompleteSpecification, draft.build(a, prior, snapshot, try c.validate(.{ .value = closed }, value.feature), contracts.port()));
        const selected = try @import("domain/feature_directory.zig").validate(a, .{ .bytes = value.feature.bytes }, .{ .specs = "requirements", .archive = "archive" });
        const paths = try @import("domain/workflow_artifact_registry.zig").resolveFeaturePaths(a, .{ .specs = "requirements", .archive = "archive", .workflows = "engine" }, selected);
        const directory: @import("domain/feature_directory.zig").Directory = .{ .selector = selected, .root_observation = .absent, .observation = .absent };
        const inputs: c.Inputs = .{ .state = .{ .value = null }, .submissions = &.{}, .protected_forms = &.{} };
        const original_sources = try a.alloc(@import("domain/model_text_wire.zig").SourceText, snapshot.inputs.corpus.sources.len);
        for (snapshot.inputs.corpus.sources, original_sources) |captured_source, *witness| witness.* = .{ .source_id = captured_source.id, .bytes = captured_source.bytes };
        const ready: @import("domain/clarification_refresh.zig").Ready = .{ .state = validated, .original_sources = original_sources };
        const forms = try @import("domain/clarification_views.zig").render(a, ready, &.{});
        const prepare: @import("actions/specification/prepare_incomplete_specification_output.zig").Action = .{ .contracts = contracts.port() };
        const prepared = try prepare.execute(a, directory, paths, .{ .state = null, .forms = &.{} }, inputs, .{ .ready = ready }, forms, prior, value, rendered);
        try std.testing.expectEqual(.needs_user, prepared.terminal_outcome);
        try std.testing.expectEqual(@as(usize, 5), prepared.files.len);
        try std.testing.expectEqual(.specification, prepared.files[0].target.artifact);
        try std.testing.expectEqual(.workflow_state, prepared.files[prepared.files.len - 1].target.artifact);
        try std.testing.expectError(error.InvalidWorkflowOutput, prepare.execute(a, directory, paths, .{ .state = null, .forms = &.{} }, inputs, .{ .ready = ready }, forms, prior, value, "forged spec"));
    }
}

test "clarification preparation preserves source evidence once and uses full-view references within form bounds" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prepare = @import("domain/clarification_preparation.zig").prepare;
    const limits = @import("domain/clarification_inputs.zig");
    for ([_]usize{ 40, 2400 }) |length| {
        const source = try a.alloc(u8, length);
        @memset(source, 'a');
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const items = (try @import("domain/specification_provenance.zig").items(fixture.context)).entries;
        const repeated = try std.mem.concat(a, @TypeOf(items[0]), &.{ items, items });
        const question = "Which retention period applies? State the duration.";
        const reason = "The source leaves the period undecided.";
        const prepared = try prepare(a, question, reason, repeated, .{ .source_ids = &.{items[0].source_id} });
        try std.testing.expectEqualStrings(reason, prepared.why_required);
        try std.testing.expect(std.mem.startsWith(u8, prepared.question, question));
        try std.testing.expect(prepared.question.len <= limits.max_text_bytes);
        if (length == 40) {
            try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, prepared.question, source));
        } else {
            try std.testing.expect(std.mem.indexOf(u8, prepared.question, "reference-context.md") != null);
            try std.testing.expect(std.mem.indexOf(u8, prepared.question, source[0..10]) == null);
        }
        const full_question = try a.alloc(u8, limits.max_text_bytes);
        @memset(full_question, 'q');
        const full = try prepare(a, full_question, reason, repeated, .{ .source_ids = &.{items[0].source_id} });
        try std.testing.expectEqualStrings(full_question, full.question);
        try std.testing.expect(std.mem.indexOf(u8, full.why_required, "reference-context.md") != null);
    }
}

test "clarification excerpts follow evidence selections and collapse exact contained ranges only" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const preparation = @import("domain/clarification_preparation.zig");
    for ([_][]const u8{ "Startup greeting and UTC date.", "Library renewal and return deadline." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const original = (try provenance.items(fixture.context)).entries[0];
        const outer = original.citations[0];
        var inner = outer;
        inner.id.ordinal = 100;
        inner.value.location.start.byte += 8;
        inner.value.location.start.column += 8;
        inner.value.verbatim = outer.value.verbatim.?[8..];
        var separate = outer;
        separate.id.ordinal = 101;
        separate.value.block_id.ordinal += 1;
        var item = original;
        item.citations = &.{ inner, separate, outer };
        const before = try std.json.Stringify.valueAlloc(a, item, .{});
        const question = "Which reporting interval is required? Give its duration.";
        const reason = "The source establishes the output but gives no interval.";
        const scoped = try preparation.prepare(a, question, reason, &.{item}, .{ .citation_ids = &.{ outer.id, inner.id }, .source_ids = &.{item.source_id} });
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, scoped.question, "Source 1, lines"));
        try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, scoped.question, source));
        const source_only = try preparation.prepare(a, question, reason, &.{item}, .{ .source_ids = &.{item.source_id} });
        try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, source_only.question, source));
        const absent = try preparation.prepare(a, question, reason, &.{item}, .{});
        try std.testing.expect(std.mem.indexOf(u8, absent.question, "reference-context.md") != null);
        try std.testing.expect(std.mem.indexOf(u8, absent.question, source) == null);
        const no_sources = try preparation.prepare(a, question, reason, &.{}, .{});
        try std.testing.expectEqualStrings(question, no_sources.question);
        // Source-only evidence cannot broaden a precise citation selection.
        const narrow = try preparation.prepare(a, question, reason, &.{item}, .{ .citation_ids = &.{inner.id} });
        try std.testing.expect(std.mem.indexOf(u8, narrow.question, source) == null);
        try std.testing.expect(std.mem.indexOf(u8, narrow.question, inner.value.verbatim.?) != null);
        try std.testing.expectEqualStrings(before, try std.json.Stringify.valueAlloc(a, item, .{}));
    }
}

test "advisory question metadata survives correction and readback without clarification authority" {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    const inputs = try completedSupportInputs(&fixture);
    const good = try reviewFor(a, inputs, fixture.context.inputs);
    const entries = try a.dupe(review.Finding, good.entries);
    entries[0].value.kind = .ambiguous;
    entries[0].value.detail = "Renewal is supported, but the source gives no duration.";
    try bindReviewClaims(a, inputs, fixture.context, entries);
    const question = "How long should renewal last? Supply a duration and its starting event.";
    for ([_]?[]const u8{ null, "", " \n", "\x00", "Which value follows {\"kind\":\"exact_copy\",\"claim_id\":1}?" }) |bad| {
        entries[0].value.question = bad;
        const rejected = (try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).rejected;
        try std.testing.expectEqual(@as(review.Issue, if (bad == null) .missing_question else .invalid_question), rejected.rejection.selected().?.issue);
        if (bad) |value| if (std.mem.eql(u8, value, " \n") or std.mem.indexOf(u8, value, "exact_copy") != null) {
            try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, rejected));
            continue;
        };
        const auth = try repair.authorize(a, inputs, fixture.context, rejected);
        const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("gap_detail", packet.resultDefinition().?.bytes);
        var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schema_owner = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
        const admitted_question = try json.encode(struct { detail: []const u8, question: []const u8 }, a, .{ .detail = entries[0].value.detail, .question = question });
        try @import("test_fixtures/prepared_model_repair.zig").check(a, packet, schema_owner, admitted_question, null);
        const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, auth, auth.operation.replace, null);
        try std.testing.expectEqual(.recurring, repair.progress(auth, unchanged));
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, auth, .{ .detail = .{ .detail = entries[0].value.detail, .question = question } }, null);
        try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
        try std.testing.expectEqual(.ambiguous, fixed.accepted.inputs.evidence[0].finding);
        try std.testing.expectEqualDeep(entries[0].value.provenance, fixed.accepted.candidate.review.entries[0].value.provenance);
        try std.testing.expectEqualDeep(good.entries[1..], fixed.accepted.candidate.review.entries[1..]);
        try review.validateStored(a, fixed.accepted.inputs, fixture.context.inputs);
        const decision = try supportDecision(a, fixed.accepted.inputs);
        try std.testing.expectEqual(.all_resolved, decision.result.continuation);
        try std.testing.expectEqualStrings(question, fixed.accepted.inputs.evidence[0].review.?.question.?);
        try std.testing.expect(decision.result.entries[0].outcome == .assessment_complete);
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, decision.inputs, decision.observations, decision.result));
        var corrupt = fixed.accepted.inputs;
        const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, corrupt.evidence);
        proofs[0].review.?.question = bad;
        corrupt.evidence = proofs;
        try std.testing.expectError(error.InvalidRequiredAuthority, review.validateStored(a, corrupt, fixture.context.inputs));
        const missing = (try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = good.entries[1..] }), null)).rejected;
        const insertion = try repair.authorize(a, inputs, fixture.context, missing);
        try std.testing.expect((try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, missing.candidate.?, insertion, .{ .finding = entries[0].value }, null)) == .rejected);
    }
    entries[0] = good.entries[0];
    entries[0].value.question = question;
    try std.testing.expect((try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)) == .rejected);
}

fn introduceConflict(fixture: *Fixture) ![]const references.r.ClaimId {
    const a = fixture.allocator;
    const r = references.r;
    const original = fixture.context.references.records.assignments.checked.prior.prior;
    var proposal = original.proposal;
    const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
    var business: std.ArrayList(r.ClaimId) = .empty;
    for (original.input.progress.plan.layout.items.entries) |item| if (item.claim.content == .model) {
        try business.append(a, item.claim.id);
    };
    try std.testing.expect(business.items.len >= 2);
    const claims = business.items[0..2];
    for (dispositions) |*value| {
        if (std.meta.eql(value.claim_id, claims[0])) value.disposition = .{ .conflicting = .{ .related_claim_ids = try a.dupe(r.ClaimId, &.{claims[1]}) } };
        if (std.meta.eql(value.claim_id, claims[1])) value.disposition = .{ .conflicting = .{ .related_claim_ids = try a.dupe(r.ClaimId, &.{claims[0]}) } };
    }
    proposal.claim_dispositions = dispositions;
    var signals: std.ArrayList(r.SignalProposal) = .empty;
    for (proposal.signals) |signal| {
        var affected = false;
        for (claims) |id| if (r.contains(r.ClaimId, signal.claim_ids, id)) {
            affected = true;
        };
        if (!affected) try signals.append(a, signal);
    }
    proposal.signals = try signals.toOwnedSlice(a);
    proposal.conflicts = try a.dupe(r.ConflictProposal, &.{.{ .claim_ids = claims, .kind = .mutually_exclusive, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The compatible requirements were incorrectly grouped as conflicting." } }} } }});
    const ctx: @import("domain/reference_reconciliation_validation.zig").TextContext = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
    fixture.context.references = (try references.finish(a, original.input, proposal, ctx)).valid;
    return business.toOwnedSlice(a);
}

test "source omission cannot reopen a native duplicate token disposition" {
    const authority = @import("domain/required_authority.zig");
    const loss = @import("domain/source_omission.zig");
    const r = references.r;
    for ([_][]const u8{ "Hello, World!", "Renewal accepted!" }) |value| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, try std.fmt.allocPrint(a, "Display `{s}` initially and repeat `{s}` after recovery.", .{ value, value }));
        defer fixture.deinit();
        const records = @import("domain/reference_support.zig").records(fixture.context.references);
        var original_tokens: std.ArrayList(r.Item) = .empty;
        for (records.items.entries) |item| if (item.claim.content == .preserved_token) try original_tokens.append(a, item);
        try std.testing.expectEqual(@as(usize, 2), original_tokens.items.len);
        const first = original_tokens.items[0];
        const duplicate = original_tokens.items[1];
        try std.testing.expect(first.claim.id.ordinal < duplicate.claim.id.ordinal);
        try std.testing.expectEqualStrings(first.claim.content.preserved_token.value.raw_value.bytes, duplicate.claim.content.preserved_token.value.raw_value.bytes);
        const disposition = records.dispositions[duplicate.claim.id.ordinal - 1];
        try std.testing.expectEqual(.duplicate, disposition.disposition);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{first.claim.id}, disposition.related_claim_ids);
        const inputs = try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, records, fixture.context.inputs);
        const ledger = try authority.build(a, inputs);
        const selected = for (ledger.requirements, 0..) |requirement, index| {
            if (requirement.seed.id.unit == .source) break index;
        } else return error.MissingSourcePreservationRequirement;
        const id = ledger.requirements[selected].seed.id;
        const location: loss.Location = .{ .reconciliation_disposition = duplicate.claim.id };
        var review: authority.ReviewEvidence = .{
            .loss = location,
            .detail = "MOCK The later token occurrence was suppressed.",
            .missing_obligation = value,
            .provenance = .{ .claim_ids = &.{duplicate.claim.id}, .citation_ids = duplicate.claim.citation_ids, .clarification_response_ids = &.{} },
            .source_ids = &.{duplicate.source_id},
        };
        const assignment = try @import("domain/source_omission_binding.zig").build(a, inputs, fixture.context.inputs, id, @intCast(selected + 1), 1, review);
        review.preservation = .{ .assignment = assignment, .response = try @import("test_fixtures/source_omission_evidence.zig").response(a, assignment, location) };
        // The supplied comparison is current and really identifies this native
        // duplicate. Its semantic verdict still cannot reopen native identity.
        const attributed = try loss.comparisons.validate(a, inputs, fixture.context.inputs, id, review, review.preservation.?);
        try std.testing.expect(loss.comparisons.location(attributed).eql(location));
        try std.testing.expectError(error.InvalidRequiredAuthority, loss.validate(a, inputs, fixture.context.inputs, id, .candidate_omission, review, location));
    }
}
test "false conflicts repair a closed relation group with exact preconditions and preserved siblings" {
    const repair = @import("domain/reference_reconciliation_repair.zig").Omission;
    const review = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const r = references.r;
    for ([_][]const u8{ "On startup show the greeting and UTC date. Display `MOCK Hello, World!`.\n", "Renew the loan and show the new return date. Display `MOCK Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, .business_exact_string, true, "Retain the supported behavior and its date information.", 3);
        defer fixture.deinit();
        const token = for ((try provenance.items(fixture.context)).entries) |item| {
            if (item.claim.content == .preserved_token) break item.claim.id;
        } else return error.MissingTestToken;
        // Native token accounting cannot become an admitted semantic omission
        // location, so there is no source-repair authorization to mint for it.
        try std.testing.expectError(error.InvalidOmissionFixture, omissionSupport(&fixture, .{ .reconciliation_disposition = token }, "Preserve the original literal."));
        const business = try introduceConflict(&fixture);
        const claims = business[0..2];
        const ctx: @import("domain/reference_reconciliation_validation.zig").TextContext = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
        const global = fixture.context.references.records.assignments.checked.prior.prior;
        const parsed: r.Parsed = .{ .source = global.source, .input = global.input, .proposal = .{ .global = global.proposal } };
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const entries = try a.dupe(review.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
        const ledger = try authority.build(a, inputs);
        var conflict_index: usize = 0;
        for (ledger.requirements, entries, 0..) |requirement, *finding, index| if (requirement.seed.id.unit == .conflict) {
            conflict_index = index;
            finding.value.kind = .candidate_omission;
            finding.value.missing_obligation = fixture.context.inputs.corpus.sources[0].bytes;
            finding.value.detail = "The original requirements are compatible; restore their separate supported meanings.";
            finding.value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
            finding.value.loss = .{ .reconciliation_conflict = requirement.seed.id.unit.conflict };
            finding.value.preservation = try @import("test_fixtures/source_omission_evidence.zig").proof(a, inputs, fixture.context.inputs, finding.*);
        };
        const admitted = (try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).accepted;
        const decision = try supportDecision(a, admitted.inputs);
        try std.testing.expectEqual(.invalid, decision.result.continuation);
        const support: @import("domain/source_omission.zig").Support = .{ .repair_phase = .pre_generation, .review = admitted.candidate, .inputs = decision.inputs, .observations = decision.observations, .result = decision.result };
        const auth = try repair.authorize(a, parsed, ctx, support);
        try std.testing.expectEqualDeep(claims, auth.target.conflict_group);
        const packet = try repair.packet(a, parsed, ctx, support, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("repair_conflict_group", packet.resultDefinition().?.bytes);
        const changed = try a.dupe(r.ClaimDispositionProposal, auth.operation.replace.conflict_group.claim_dispositions);
        for (changed) |*value| value.disposition = .{ .retained = .{} };
        const replacement = try repair.parse(a, auth, packet, try json.encode(@import("domain/reference_reconciliation_repair.zig").ConflictGroup, a, .{ .claim_dispositions = changed, .conflicts = &.{} }));
        var foreign_group = replacement;
        foreign_group.conflict_group.conflict_groups = &.{.{ .claim_ids = &.{ claims[0], .{ .ordinal = 999 } } }};
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), parsed, ctx, support, auth, foreign_group, null));
        // A valid semantic relation repair cannot acquire a native token as a
        // member or relation target, even through a coupled replacement.
        var token_group = replacement;
        token_group.conflict_group.conflict_groups = &.{.{ .claim_ids = &.{ claims[0], token } }};
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, ctx.inputs), parsed, ctx, support, auth, token_group, null));
        const token_members = try a.dupe(r.ClaimDispositionProposal, changed);
        token_members[0].claim_id = token;
        token_group = .{ .conflict_group = .{ .claim_dispositions = token_members, .conflicts = &.{} } };
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, ctx.inputs), parsed, ctx, support, auth, token_group, null));
        token_members[0] = changed[0];
        token_members[0].disposition = .{ .duplicate = .{ .target_claim_id = token } };
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, ctx.inputs), parsed, ctx, support, auth, token_group, null));
        var forged_scope = auth;
        forged_scope.target.conflict_group = &.{ claims[0], token };
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, ctx.inputs), parsed, ctx, support, forged_scope, replacement, null));
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), parsed, ctx, support, auth, replacement, .{ .request = .{ .value = 101 }, .attempt = .{ .value = 1 } });
        try std.testing.expectEqualDeep(parsed.proposal.global.signals, fixed.proposal.global.signals);
        for (parsed.proposal.global.claim_dispositions, fixed.proposal.global.claim_dispositions, 0..) |before, after, index| if (!r.contains(r.ClaimId, claims, before.claim_id)) {
            try std.testing.expectEqualDeep(before, after);
            try std.testing.expectEqualDeep(parsed.source.at(.{ .disposition = index }, .record), fixed.source.at(.{ .disposition = index }, .record));
        };
        try std.testing.expectEqual(@as(usize, 0), fixed.proposal.global.conflicts.len);
        // Group repair cannot itself invent replacement signals; full validation
        // must require their rebuilding by the existing coverage-repair owner.
        try std.testing.expect((try references.finish(a, fixed.input, fixed.proposal.global, ctx)) == .invalid);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), fixed, ctx, support, auth, replacement, null));
        changed[0].claim_id = business[2];
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), parsed, ctx, support, auth, .{ .conflict_group = .{ .claim_dispositions = changed, .conflicts = &.{} } }, null));
        changed[0].claim_id = auth.operation.replace.conflict_group.claim_dispositions[0].claim_id;
        changed[0].disposition = .{ .duplicate = .{ .target_claim_id = business[2] } };
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), parsed, ctx, support, auth, .{ .conflict_group = .{ .claim_dispositions = changed, .conflicts = &.{} } }, null));
        var stale_context = ctx;
        stale_context.inputs.corpus.state_id.bytes = "stale-source-state";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, stale_context, support, auth));
        // Member order does not create a fresh retry target.
        var reordered = support;
        const reordered_conflicts = try a.dupe(r.Conflict, support.inputs.references.?.conflicts);
        reordered_conflicts[0].value.claim_ids = &.{ claims[1], claims[0] };
        reordered.inputs.references.?.conflicts = reordered_conflicts;
        const again = try @import("domain/source_omission.zig").retryPermit(a, .reconciliation, auth.owner, auth.id, auth.revision, reordered, ledger.requirements[conflict_index].seed.id, auth.retry);
        try std.testing.expectEqualDeep(auth.retry.?.key, again.key);
        // A genuine conflict remains a user decision, never repair permission.
        entries[conflict_index].value.kind = .conflicting;
        entries[conflict_index].value.missing_obligation = null;
        entries[conflict_index].value.loss = .{ .unlocalized = .{} };
        entries[conflict_index].value.preservation = null;
        entries[conflict_index].value.question = "Which requirement should take precedence? Identify the required behavior.";
        const negative = (try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).accepted;
        const gap = try supportDecision(a, negative.inputs);
        try std.testing.expectEqual(.needs_user, gap.result.continuation);
        try std.testing.expectError(error.InvalidRequiredAuthority, repair.authorize(a, parsed, ctx, .{ .repair_phase = .pre_generation, .review = negative.candidate, .inputs = gap.inputs, .observations = gap.observations, .result = gap.result }));
    }
}

test "R42 selected question schemas match retained decisions and text defects share one retry identity" {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    for ([_][]const u8{ "Display a greeting and the UTC time on startup.", "A borrower renews a loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        for (std.meta.tags(review.Decision)) |decision| {
            // The actual entity disposition already fixes applicability.
            // Models cannot reclassify it with the retired pre-authoring branch.
            if (decision == .not_applicable) continue;
            const entries = try a.dupe(review.Finding, good.entries);
            const index = if (decision == .not_applicable) blk: {
                const ledger = try @import("domain/required_authority.zig").build(a, inputs);
                for (ledger.requirements, 0..) |req, i| if (req.seed.id.kind == .entity_applicability) break :blk i;
                return error.MissingEntityRequirement;
            } else 0;
            const negative = @import("domain/specification_support_evidence.zig").questionRequired(decision.finding());
            entries[index].value.kind = decision;
            entries[index].value.detail = "The source establishes the action; its duration is unspecified.";
            entries[index].value.question = if (negative) null else "Unexpected question.";
            entries[index].value.missing_obligation = if (decision == .candidate_omission) fixture.context.inputs.corpus.sources[0].bytes else null;
            if (decision == .candidate_omission or decision == .candidate_invalid) entries[index].value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
            try bindReviewClaims(a, inputs, fixture.context, entries);
            const rejected = (try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).rejected;
            try std.testing.expectEqual(@as(review.Issue, if (negative) .missing_question else .forbidden_question), rejected.rejection.selected().?.issue);
            const auth = try repair.authorize(a, inputs, fixture.context, rejected);
            const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, auth);
            defer @import("domain/model_input_packet.zig").release(packet);
            const restricted = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer restricted.release();
            const selected = restricted.selected();
            const only_detail = "{\"detail\":\"The source establishes the action; its duration is unspecified.\"}";
            const pair = "{\"detail\":\"The source establishes the action; its duration is unspecified.\",\"question\":\"What duration applies? State the duration and starting event.\"}";
            const omission_detail = try json.encodeSelected(repair.Replacement, a, .{ .detail = .{ .detail = entries[index].value.detail, .missing_obligation = entries[index].value.missing_obligation } });
            const invalid_detail = "{\"detail\":\"MOCK The candidate adds an unsupported duty.\",\"authority_gap\":null}";
            const accepted_detail = if (negative) pair else if (decision == .candidate_omission) omission_detail else if (decision == .candidate_invalid) invalid_detail else only_detail;
            try check(selected.modelBytes(), .{ .bytes = accepted_detail });
            try check(selected.modelBytes(), .{ .bytes = if (negative) only_detail else pair, .rejection = if (negative) .missing_required_property else .unknown_property, .path = "/question" });
            const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, auth, try repair.parse(a, auth, packet, accepted_detail), null);
            try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
            try std.testing.expectEqual(decision, fixed.accepted.candidate.review.entries[index].value.kind);
            try std.testing.expectEqualDeep(entries[index].value.provenance, fixed.accepted.candidate.review.entries[index].value.provenance);
            for (entries, fixed.accepted.candidate.review.entries, 0..) |before, after, i| if (i != index) try std.testing.expectEqualDeep(before, after);
            try review.validateStored(a, fixed.accepted.inputs, fixture.context.inputs);
            if (!negative) continue;
            // Presence is schema-checked; whitespace remains a native text
            // defect and retains the original pair's retry key.
            try check(selected.modelBytes(), .{ .bytes = "{\"detail\":\"\",\"question\":\"What duration applies? State its starting event.\"}", .rejection = .string_length, .path = "/detail" });
            const blank_detail = "{\"detail\":\" \",\"question\":\"What duration applies? State its starting event.\"}";
            try check(selected.modelBytes(), .{ .bytes = blank_detail });
            const recurring = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, auth, try repair.parse(a, auth, packet, blank_detail), null);
            try std.testing.expectEqual(.invalid_detail, recurring.rejected.rejection.selected().?.issue);
            try std.testing.expectEqual(.recurring, repair.progress(auth, recurring));
            const again = try repair.authorize(a, inputs, fixture.context, recurring.rejected);
            try std.testing.expectEqualDeep(auth.retry.?.key, again.retry.?.key);
            const blank_question = "{\"detail\":\"Known facts and missing duration.\",\"question\":\" \"}";
            try check(selected.modelBytes(), .{ .bytes = blank_question });
            const next_packet = try repair.packet(a, inputs, fixture.context, recurring.rejected.candidate.?, again);
            defer @import("domain/model_input_packet.zig").release(next_packet);
            const still_bad = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, recurring.rejected.candidate.?, again, try repair.parse(a, again, next_packet, blank_question), null);
            try std.testing.expectEqual(.invalid_question, still_bad.rejected.rejection.selected().?.issue);
            try std.testing.expectEqual(.recurring, repair.progress(again, still_bad));
            try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, still_bad.rejected));
            var both = rejected.candidate.?;
            const malformed = try a.dupe(review.Finding, both.review.entries);
            malformed[index].value.detail = "";
            both.review.entries = malformed;
            const all = (try review.validate(a, inputs, fixture.context.inputs, both)).rejected.rejection.diagnostics;
            try std.testing.expectEqual(@as(usize, 2), all.len);
            try std.testing.expectEqual(.invalid_detail, all[0].issue);
            try std.testing.expectEqual(.missing_question, all[1].issue);
        }
    }
}

test "selected evidence repair schemas preserve native minima across findings and candidate stages" {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const json = @import("domain/model_candidate_json.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    for ([_][]const u8{ "Display a greeting and the UTC time on startup.", "A borrower renews a loan." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const session = try completedFixture(&fixture, false);
        const content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, session)).content;
        for (0..2) |stage| {
            const inputs = if (stage == 0)
                try @import("domain/source_preservation.zig").project(a, session.feature, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs)
            else
                try @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references, content, session.units[0].?.response.content.brief);
            const good = try reviewFor(a, inputs, fixture.context.inputs);
            const ledger = try @import("domain/required_authority.zig").build(a, inputs);
            for (std.meta.tags(review.Decision)) |decision| {
                // The pre-authoring boundary reviews source preservation, not
                // absent feature fields or a retired role-classifier selection.
                if (stage == 0 and !@import("domain/source_preservation.zig").permits(decision.finding())) continue;
                if (decision == .not_applicable) continue;
                const index = if (decision == .not_applicable) blk: {
                    for (ledger.requirements, 0..) |req, i| if (req.seed.id.kind == .entity_applicability) break :blk i;
                    return error.MissingEntityRequirement;
                } else 0;
                const entries = try a.dupe(review.Finding, good.entries);
                entries[index].value.kind = decision;
                entries[index].value.missing_obligation = if (decision == .candidate_omission) source else null;
                entries[index].value.detail = "The source establishes the action; its duration is unspecified.";
                entries[index].value.question = if (admission.questionRequired(decision.finding())) "What duration applies? Supply a duration and starting event." else null;
                try bindReviewClaims(a, inputs, fixture.context, entries);
                entries[index].value.source_ids = &.{.{ .ordinal = 999 }};
                const rejected = (try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).rejected;
                try std.testing.expectEqual(.invalid_sources, rejected.rejection.selected().?.evidence.?.issue);
                const auth = try repair.authorize(a, inputs, fixture.context, rejected);
                const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, auth);
                defer @import("domain/model_input_packet.zig").release(packet);
                const restricted = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
                defer restricted.release();
                const selected = restricted.selected();
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                const rule = body.get("repair").?.object.get("rule").?.object.get("evidence_rule").?.object;
                try std.testing.expectEqualStrings(admission.selection_instruction, rule.get("instruction").?.string);
                const model = @import("domain/specification_support_model.zig");
                const source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
                const bytes = if (decision == .candidate_invalid)
                    try json.encode(model.InvalidSelection, a, .{ .source_ids = source_ids, .authority_gap_source_ids = null })
                else
                    try json.encode(model.Selection, a, .{ .source_ids = source_ids });
                try std.testing.expectEqualStrings(if (decision == .candidate_invalid) "invalid_selection" else "selection", packet.resultDefinition().?.bytes);
                try check(selected.modelBytes(), .{ .bytes = "{\"source_ids\":[1],\"provenance\":{\"claim_ids\":[1]}}", .rejection = .unknown_property, .path = "/provenance" });
                try check(selected.modelBytes(), .{ .bytes = bytes });
                const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, auth, try repair.parse(a, auth, packet, bytes), null);
                try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
                try std.testing.expectEqual(decision, fixed.accepted.candidate.review.entries[index].value.kind);
                for (entries, fixed.accepted.candidate.review.entries, 0..) |before, after, i| if (i != index) try std.testing.expectEqualDeep(before, after);
                try review.validateStored(a, fixed.accepted.inputs, fixture.context.inputs);
                // Model responses cannot alter the bound claim set during repair.
                try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, auth, packet, "{\"provenance\":{\"claim_ids\":[999]},\"source_ids\":[1]}"));
                const initial = try review.packetFor(a, inputs, fixture.context, .{ .finding = ledger.requirements[index].seed.id });
                defer @import("domain/model_input_packet.zig").release(initial);
                const input = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
                try std.testing.expectEqualStrings(admission.selection_instruction, input.get("evidence_rules").?.object.get("instruction").?.string);
            }
        }
    }
}

test "FIX002 false cross-kind conflict and nine question repairs cannot publish a clarification" {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const needs = @import("domain/required_authority_clarifications.zig");
    for ([_][]const u8{ "On startup display `MOCK Hello, World!` and the UTC date.", "Renew the loan, show the return date and display `MOCK Loan renewed!`." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContentKinds(a, source, .business_exact_string, true, "Preserve the action, message and date.", 2, true);
        defer fixture.deinit();
        _ = try introduceConflict(&fixture);
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const entries = try a.dupe(review.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
        const ledger = try authority.build(a, inputs);
        var negative_count: usize = 0;
        for (ledger.requirements, entries) |required, *entry| {
            if (required.seed.id.unit == .signal or required.seed.id.unit == .token) continue;
            entry.value.kind = .unsupported;
            entry.value.detail = "The source supplies the action and date, but the derived conflict leaves this interpretation unsupported.";
            entry.value.question = null;
            negative_count += 1;
        }
        try bindReviewClaims(a, inputs, fixture.context, entries);
        try std.testing.expectEqual(@as(usize, 9), negative_count);
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 1 } };
        var collected = try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), origin);
        try std.testing.expectEqual(negative_count, collected.rejected.rejection.diagnostics.len);
        for (0..negative_count) |index| {
            const rejected = collected.rejected;
            const auth = try repair.authorize(a, inputs, fixture.context, rejected);
            try std.testing.expectEqual(.missing_question, auth.rule.rejection.issue);
            const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, auth);
            defer @import("domain/model_input_packet.zig").release(packet);
            try std.testing.expectEqualStrings("gap_detail", packet.resultDefinition().?.bytes);
            collected = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, auth, .{ .detail = .{ .detail = entries[auth.target.index].value.detail, .question = "Which behavior is intended? State the action and date to display." } }, .{ .request = .{ .value = @intCast(9 + index) }, .attempt = .{ .value = 1 } });
            try std.testing.expectEqual(.resolved, repair.progress(auth, collected));
            const current = if (collected == .accepted) collected.accepted.candidate else collected.rejected.candidate.?;
            for (rejected.candidate.?.review.entries, current.review.entries, 0..) |before, after, sibling| {
                try std.testing.expectEqual(before.value.kind, after.value.kind);
                try std.testing.expectEqualDeep(before.value.provenance, after.value.provenance);
                if (sibling != auth.target.index) {
                    try std.testing.expectEqualDeep(before, after);
                    try std.testing.expectEqualDeep(rejected.candidate.?.origins[sibling], current.origins[sibling]);
                }
            }
        }
        try std.testing.expect(collected == .accepted);
        try review.validateStored(a, collected.accepted.inputs, fixture.context.inputs);
        const gate = try supportDecision(a, collected.accepted.inputs);
        try std.testing.expectEqual(.invalid, gate.result.continuation);
        try std.testing.expectError(error.InvalidRequiredAuthority, needs.build(a, fixture.context.inputs, gate.inputs, gate.observations, gate.result));
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/source_omission.zig").select(a, fixture.context.inputs, .{ .repair_phase = .generation_started, .review = collected.accepted.candidate, .inputs = gate.inputs, .observations = gate.observations, .result = gate.result }));
    }
}

test "FIX002 generation inconclusive stays terminal while source advice cannot invent questions" {
    const review = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    const inputs = try completedSupportInputs(&fixture);
    const entries = try a.dupe(review.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
    entries[0].value.kind = .inconclusive;
    entries[0].value.detail = "I could not reconcile the current interpretations; no missing user choice was established.";
    try bindReviewClaims(a, inputs, fixture.context, entries);
    const inconclusive_result = try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null);
    const accepted = inconclusive_result.accepted;
    try review.validateStored(a, accepted.inputs, fixture.context.inputs);
    const gate = try supportDecision(a, accepted.inputs);
    try std.testing.expectEqual(.all_resolved, gate.result.continuation);
    try std.testing.expect(gate.result.entries[0].outcome == .assessment_complete);
    try std.testing.expect(gate.result.entries[0].candidate_defect == null);
    try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, gate.inputs, gate.observations, gate.result));
    entries[0].value.question = "Repeat the requirement?";
    try std.testing.expect((try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)) == .rejected);
    const sessions = @import("domain/specification_session.zig");
    const response = try g.parse(a, "{\"kind\":\"inconclusive\",\"detail\":\"Cannot establish the interpretation.\"}", try sessions.currentBinding(a, (try sessions.initialize(a, inputs.feature, fixture.context)).ready, fixture.context));
    const failed = try g.validate(a, text.validator, fixture.context, .brief, response);
    try std.testing.expectEqual(.inconclusive_review, failed.invalid.blocked.?);
    try std.testing.expectEqualStrings(response.inconclusive.detail, failed.invalid.detail.?);
    try std.testing.expectError(error.InvalidSpecification, (@import("actions/clarification/build_specification_clarification_need.zig").Action{}).execute(a, inputs.feature, fixture.context, .{ .unit = .brief, .response = .{ .inconclusive = response.inconclusive } }));
}

test "identical exact originals share native recognition without rewriting selected support or dropping duties" {
    const upstream = @import("reference_reconciliation_test.zig");
    const r = references.r;
    const native = @import("domain/reference_token_disposition.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const fixture = try upstream.prepare(a, &.{ "Show `Done!` on startup.\n", "Show `Done!` after renewal.\n" });
    defer fixture.deinit();
    const selected = fixture.context();
    const progress = try references.summaries(a, try references.initialize(a, fixture.inputs, fixture.extracted, 2), selected);
    const accounted = (try references.finish(a, progress, try references.global(a, progress), selected)).valid;
    const context: provenance.Context = .{ .inputs = fixture.inputs, .references = accounted, .registry = selected.registry, .current = selected.current };
    const items = try provenance.items(context);
    var handles: [2]struct { claim: r.ClaimId, handle: @import("domain/typed_text.zig").ExactCopy, bytes: []const u8, citations: []const r.CitationId } = undefined;
    var count: usize = 0;
    for (items.entries) |item| {
        if (item.claim.content != .preserved_token) continue;
        try std.testing.expect(count < handles.len);
        const token = item.claim.content.preserved_token;
        handles[count] = .{ .claim = item.claim.id, .handle = .{ .claim_id = item.claim.id }, .bytes = token.value.raw_value.bytes, .citations = item.claim.citation_ids };
        count += 1;
    }
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings(handles[0].bytes, handles[1].bytes);
    try std.testing.expect(!std.meta.eql(handles[0].claim, handles[1].claim));
    try std.testing.expect(!std.meta.eql(handles[0].handle, handles[1].handle));
    try std.testing.expect(handles[0].citations[0].ordinal != handles[1].citations[0].ordinal);
    try std.testing.expectEqualDeep(&[_]r.ClaimId{ handles[0].claim, handles[1].claim }, try native.originals(a, items, handles[1].claim));
    try std.testing.expectEqualDeep(handles[0].claim, try native.representative(items, handles[1].claim));
    var checked_values: [2]spec.AttributedValue = undefined;
    var records: [2]spec.RecordProposal = undefined;
    for (handles, 0..) |handle, index| {
        const semantic = for (items.entries) |item| {
            if (item.claim.content == .model and item.source_id.ordinal == index + 1) break item.claim.id;
        } else return error.MissingSemanticClaim;
        const group = for (accounted.records.signals) |signal| {
            if (r.contains(r.ClaimId, signal.value.claim_ids, semantic)) break signal.id;
        } else return error.MissingSemanticGroup;
        const candidate: spec.Model.AttributedValue = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "Display {s}", .{handle.bytes}) } }} }, .source_group_ids = try a.dupe(r.SignalId, &.{group}), .provenance = .{ .claim_ids = try a.dupe(r.ClaimId, &.{semantic}), .clarification_response_ids = &.{} } };
        checked_values[index] = try provenance.checkAttributed(.model, a, text.validator, context, candidate, .spec_story);
        const accepted = checked_values[index];
        try std.testing.expectEqualDeep(candidate.source_group_ids, accepted.source_group_ids);
        try std.testing.expectEqualDeep(candidate.provenance.claim_ids, accepted.provenance.claim_ids);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{ semantic, handles[0].claim }, try provenance.effectiveClaims(a, accepted.provenance.claim_ids, &.{accepted.value}));
        _ = try provenance.checkAttributed(.canonical, a, text.validator, context, accepted, .spec_story);
        var exact_count: usize = 0;
        for (accepted.value.segments) |segment| if (segment == .exact_copy) {
            exact_count += 1;
            try std.testing.expectEqualDeep(handles[0].handle, segment.exact_copy);
        };
        try std.testing.expectEqual(@as(usize, 1), exact_count);
        records[index] = try provenance.checkRecord(.model, a, text.validator, context, .{ .content = .{ .functional_requirement = .{ .text = candidate.value } }, .source_group_ids = candidate.source_group_ids, .provenance = candidate.provenance });

        // Native duplicate identity is diagnostic evidence, never an alternate
        // exact handle chosen by selecting a different business source.
        var inspection: provenance.Inspection = .{};
        var wrong = candidate;
        wrong.value = .{ .segments = &.{ .{ .literal = .{ .value = "Display " } }, .{ .exact_copy = handles[1].handle } } };
        try std.testing.expectError(error.InvalidTypedText, provenance.inspectAttributed(.model, a, text.validator, context, wrong, .spec_story, &inspection));
        try std.testing.expectEqual(.unknown_exact, inspection.text_issue.?.reason);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{semantic}, candidate.provenance.claim_ids);
    }
    var title = checked_values[0];
    title.value = .{ .segments = &.{.{ .literal = .{ .value = "Operation outcome" } }} };
    title = try provenance.checkAttributed(.model, a, text.validator, context, .{ .value = title.value, .source_group_ids = title.source_group_ids, .provenance = selection(title.provenance) }, .spec_title);
    const brief: g.Brief = .{ .title = title, .description = title, .primary_goal = title };
    const content = (try identifiers.assign(a, .{ .display_name = title, .primary_user_story = checked_values[0], .entities = .{ .disposition = .not_applicable, .basis = title }, .records = &records }, .{})).content;
    const coverage = try @import("domain/specification_coverage.zig").validate(a, accounted, brief, content);
    try std.testing.expectEqual(@as(usize, 2), coverage.obligations.len);
    for (coverage.obligations, handles) |obligation, original| {
        try std.testing.expectEqualDeep(original.claim, obligation.claim_id);
        try std.testing.expect(obligation.exact_targets.len > 0);
        try std.testing.expectEqualDeep(original.citations, (try r.item(items, original.claim)).claim.citation_ids);
    }
    const forged = try a.dupe(r.ClaimDisposition, accounted.records.assignments.checked.prior.prior.dispositions);
    forged[handles[1].claim.ordinal - 1].related_claim_ids = &.{items.entries[0].claim.id};
    const rejected = (try @import("domain/reference_disposition_validation.zig").check(a, items, forged)).invalid;
    try std.testing.expectEqual(.native_token_disposition, rejected.issue.expected.constraint);
}

test "empty display choices reject invented and misbound references and permit bounded prose recovery" {
    const repair = @import("domain/specification_repair.zig");
    const candidates = @import("domain/specification_candidate.zig");
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    const schema = @import("domain/model_result_schema.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const compiler = @import("adapters/parsers/model_result_schemas.zig");
    var adapter: compiler.Adapter = .{};
    const canonical = try adapter.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
    for ([_][]const u8{ "The visitor sees `MOCK Hello, World!`.", "The borrower sees `MOCK Renewal complete!`." }) |source| for ([_]bool{ false, true }) |exact| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        const good = try fixture.proposal(source);
        var bad = good;
        const handle: @import("domain/typed_text.zig").ExactCopy = .{ .claim_id = .{ .ordinal = 999 } };
        bad.value = .{ .segments = &.{if (exact) .{ .exact_copy = handle } else .{ .passive = .{ .passive_literal_id = .{ .ordinal = 1 } } }} };
        const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = bad, .description = good, .primary_goal = good } } } };
        const initial = try sessions.packet(std.testing.allocator, current, fixture.context);
        defer packets.release(initial);
        const generation_schema = try schema.restrict(std.testing.allocator, canonical.select(initial.resultDefinition().?).?, initial.excludedVariants(), initial.integerChoices());
        defer generation_schema.release();
        var invalid_body = try std.json.parseFromSlice(std.json.Value, a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, .{ .content = .{ .brief = .{ .title = good, .description = good, .primary_goal = good } } })), .{ .parse_numbers = false });
        invalid_body.value.object.getPtr("title").?.object.getPtr("value").?.* = try std.json.parseFromSliceLeaky(std.json.Value, a, if (exact) "{\"fragments\":[{\"kind\":\"exact_copy\",\"claim_id\":999}]}" else "{\"fragments\":[{\"kind\":\"passive\",\"passive_literal_id\":1}]}", .{});
        try std.testing.expect(@import("domain/model_payload_schema.zig").validateValue(@import("domain/model_envelope.zig").value(&invalid_body.value), generation_schema.selected().root()) != null);
        try std.testing.expect(std.mem.indexOf(u8, generation_schema.selected().modelBytes(), "exact_copy") == null);
        if (exact) try std.testing.expectError(error.InvalidJsonDocument, json.decode(g.ModelResponse, a, try std.json.Stringify.valueAlloc(a, invalid_body.value, .{})));
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(@as(@FieldType(@import("domain/typed_text.zig").Issue, "reason"), if (exact) .unknown_exact else .unknown_passive), rejected.issue.text_issue.?.reason);
        if (exact) try std.testing.expectEqualDeep(handle, rejected.issue.text_issue.?.rejected_exact.?) else try std.testing.expectEqual(@as(u32, 1), rejected.issue.text_issue.?.rejected_passive.?.ordinal);
        // A model-authored exact handle has no current wire producer. Its
        // schema/codec rejection precedes candidate value-repair authority.
        if (exact) continue;
        const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, auth);
        defer packets.release(packet);
        const selected = try schema.restrict(std.testing.allocator, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer selected.release();
        {
            try std.testing.expectEqual(.value, std.meta.activeTag(auth.target));
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "passive reference ID 1") != null);
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "Return source-backed prose without reference handles.") != null);
            try std.testing.expect(std.mem.indexOf(u8, selected.selected().modelBytes(), "exact_copy") == null);
        }
        try std.testing.expect(std.mem.indexOf(u8, selected.selected().modelBytes(), "passive_literal_id") == null);
        const replacement: repair.Replacement = .{ .value = good.value };
        const bytes = try json.encodeSelected(repair.Replacement, a, replacement);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{ .parse_numbers = false });
        try std.testing.expect(@import("domain/model_payload_schema.zig").validateValue(@import("domain/model_envelope.zig").value(&parsed.value), selected.selected().root()) == null);
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, auth, try repair.parse(a, auth, packet, bytes), null);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.description);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.primary_goal);
        try std.testing.expectEqualDeep(bad.provenance, merged.response.content.brief.title.provenance);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, merged)) == .valid);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
    };
}

test "exact claim handles derive field and shared-record lineage without rewriting explicit selection" {
    const r = references.r;
    const projection = @import("domain/specification_projection.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Display `MOCK Renewed!` after loan renewal." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const explicit = all.entries[0].claim.id;
        const exact = all.entries[all.entries.len - 1].claim.id;
        const value: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = "Display " } }, .{ .exact_copy = .{ .claim_id = exact } }, .{ .literal = .{ .value = " and again " } }, .{ .exact_copy = .{ .claim_id = exact } } } };
        const proposed: spec.Model.AttributedValue = .{ .value = value, .source_group_ids = &.{fixture.context.references.records.signals[0].id}, .provenance = .{ .claim_ids = &.{explicit}, .clarification_response_ids = &.{} } };
        const checked = try provenance.checkAttributed(.model, a, text.validator, fixture.context, proposed, .spec_story);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{explicit}, checked.provenance.claim_ids);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{ explicit, exact }, try provenance.effectiveClaims(a, checked.provenance.claim_ids, &.{checked.value}));
        try std.testing.expectEqual(@as(usize, 2), checked.provenance.citation_ids.len);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "Display {s} and again {s}", .{ all.entries[all.entries.len - 1].claim.content.preserved_token.value.raw_value.bytes, all.entries[all.entries.len - 1].claim.content.preserved_token.value.raw_value.bytes }), (try projection.scalar(a, fixture.context, checked)).bytes);
        const exact_only: spec.Model.AttributedValue = .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = exact } }} }, .source_group_ids = &.{}, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} } };
        const supported = try provenance.checkAttributed(.model, a, text.validator, fixture.context, exact_only, .entity_name);
        try std.testing.expectEqual(@as(usize, 0), supported.provenance.claim_ids.len);
        try std.testing.expectEqualDeep(all.entries[all.entries.len - 1].claim.citation_ids, supported.provenance.citation_ids);
        const record: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = (try fixture.proposal("The application starts.")).value, .when = value, .then = value } }, .source_group_ids = proposed.source_group_ids, .provenance = proposed.provenance };
        const shared = try provenance.checkRecord(.model, a, text.validator, fixture.context, record);
        try std.testing.expectEqualDeep(&[_]r.ClaimId{explicit}, shared.provenance.claim_ids);
        try std.testing.expectEqual(@as(usize, 2), shared.provenance.citation_ids.len);
        const plain = try provenance.checkAttributed(.model, a, text.validator, fixture.context, try fixture.proposal("A user sees the result."), .spec_story);
        const entity = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
            .content = .{ .entity = .{ .name = value, .business_meaning = plain.value, .relationships = &.{plain.value} } },
            .source_group_ids = proposed.source_group_ids,
            .provenance = proposed.provenance,
        });
        const content = (try identifiers.assign(a, .{
            .display_name = plain,
            .primary_user_story = plain,
            .records = &.{ shared, entity },
            .entities = .{ .disposition = .required, .basis = plain },
        }, .{})).content;
        const document = try projection.project(a, fixture.context, content);
        const exact_bytes = try std.fmt.allocPrint(a, "Display {s} and again {s}", .{ all.entries[all.entries.len - 1].claim.content.preserved_token.value.raw_value.bytes, all.entries[all.entries.len - 1].claim.content.preserved_token.value.raw_value.bytes });
        for (document.records) |projected| switch (projected.content) {
            .acceptance_criterion => |criterion| {
                try std.testing.expectEqualStrings("The application starts.", criterion.given.bytes);
                try std.testing.expectEqualStrings(exact_bytes, criterion.when.bytes);
            },
            .entity => |model| {
                try std.testing.expectEqualStrings(exact_bytes, model.name.bytes);
                try std.testing.expectEqualStrings("A user sees the result.", model.relationships[0].bytes);
            },
            else => return error.UnexpectedRecordKind,
        };
        const markdown = try @import("domain/specification_markdown.zig").render(a, document);
        try std.testing.expectEqualDeep(document, try @import("domain/specification_markdown.zig").parse(a, markdown));
    }
}

test "completed requirement links keep separate source sets and many-to-many lineage" {
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "Display `Done!` after the operation.", .business_exact_string, true, "The operation has an observable result.", 2);
    defer fixture.deinit();
    const all = try provenance.items(fixture.context);
    try std.testing.expectEqual(@as(usize, 3), all.entries.len);
    const one = all.entries[0].claim.id;
    const two = all.entries[1].claim.id;
    const exact = all.entries[2].claim.id;
    // A complete combined group is an independent native occurrence; records
    // never reconstruct that occurrence from equal claim sets.
    const input = fixture.context.references.records.assignments.checked.prior.prior.input;
    var proposed = try references.global(a, input);
    proposed.signals = try std.mem.concat(a, r.SignalProposal, &.{ proposed.signals, &.{.{
        .claim_ids = &.{ one, two },
        .content = .{ .model = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "The operation and result are visible together." } }} } } },
    }} });
    fixture.context.references = (try references.finish(a, input, proposed, .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current })).valid;
    const groups = fixture.context.references.records.signals;
    const first = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
        .content = .{ .functional_requirement = .{ .text = .{ .segments = &.{ .{ .literal = .{ .value = "Display " } }, .{ .exact_copy = .{ .claim_id = exact } } } } } },
        .source_group_ids = &.{groups[0].id},
        .provenance = .{ .claim_ids = &.{one}, .clarification_response_ids = &.{} },
    });
    const second = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
        .content = .{ .functional_requirement = .{ .text = .{ .segments = &.{.{ .literal = .{ .value = "The result is visible." } }} } } },
        .source_group_ids = &.{groups[1].id},
        .provenance = .{ .claim_ids = &.{two}, .clarification_response_ids = &.{} },
    });
    const third = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
        .content = .{ .functional_requirement = .{ .text = .{ .segments = &.{.{ .literal = .{ .value = "The operation and result are visible together." } }} } } },
        .source_group_ids = &.{groups[3].id},
        .provenance = .{ .claim_ids = &.{ one, two }, .clarification_response_ids = &.{} },
    });
    const basis = try fixture.value("The operation is visible.");
    const content = (try identifiers.assign(a, .{ .display_name = basis, .primary_user_story = basis, .entities = .{ .disposition = .not_applicable, .basis = basis }, .records = &.{ first, second, third } }, .{})).content;
    const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
    const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
    const snapshot = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "references" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
    const traces = try @import("domain/specification_projection.zig").traceRequirements(a, snapshot, content);
    try std.testing.expectEqual(@as(usize, 3), traces.len);
    for (traces, &[_][]const r.ClaimId{ &.{ one, exact }, &.{two}, &.{ one, two } }) |trace, expected| {
        try std.testing.expectEqual(expected.len, trace.occurrences.len);
        for (expected, trace.occurrences) |claim, occurrence| try std.testing.expectEqualDeep(claim, occurrence.claim_id);
    }
    const linked = try @import("domain/reference_context.zig").render(a, snapshot, null, traces);
    for ([_]struct { id: []const u8, present: []const u8, absent: ?[]const u8 }{
        .{ .id = "FR-001", .present = "claim 3", .absent = "claim 2" },
        .{ .id = "FR-002", .present = "claim 2", .absent = "claim 1" },
        .{ .id = "FR-003", .present = "claim 1", .absent = "claim 3" },
    }) |check| {
        const marker = try std.fmt.allocPrint(a, "- **{s}**:", .{check.id});
        const start = std.mem.indexOf(u8, linked, marker) orelse return error.MissingRequirementLink;
        const rest = linked[start..];
        const line = rest[0 .. std.mem.indexOfScalar(u8, rest, '\n') orelse return error.MissingRequirementLink];
        try std.testing.expect(std.mem.indexOf(u8, line, check.present) != null);
        try std.testing.expect(std.mem.indexOf(u8, line, check.absent.?) == null);
    }
}

test "mixed record lineage survives completed readback and rejects a missing derived citation" {
    const sessions = @import("domain/specification_session.zig");
    const state = @import("domain/specification_state.zig");
    const support = @import("domain/specification_support.zig").Source;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Display `MOCK Renewed!` after renewal." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const exact = all.entries[all.entries.len - 1].claim.id;
        var current = try completedFixture(&fixture, false);
        try std.testing.expectEqual(@as(usize, 1), current.record_group_count);
        const records = try a.dupe(spec.RecordProposal, current.units[sessions.records_index].?.response.content.records);
        const prose = (try fixture.proposal("The application starts.")).value;
        records[1] = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
            .content = .{ .acceptance_criterion = .{
                .given = prose,
                .when = prose,
                .then = .{ .segments = &.{ .{ .literal = .{ .value = "The application displays " } }, .{ .exact_copy = .{ .claim_id = exact } } } },
            } },
            .source_group_ids = &.{fixture.context.references.records.signals[0].id},
            .provenance = .{ .claim_ids = &.{all.entries[0].claim.id}, .clarification_response_ids = &.{} },
        });
        current.units[sessions.records_index].?.response.content.records = records;
        const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
        var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
        inputs.revision = current.revision;
        const positive = try reviewFor(a, inputs, fixture.context.inputs);
        const findings = try a.dupe(support.Finding, positive.entries);
        const ledger = try @import("domain/required_authority.zig").build(a, inputs);
        for (ledger.requirements, findings) |requirement, *finding| if (requirement.seed.id.unit == .record) {
            const rule = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, requirement.seed.id);
            finding.value.provenance.claim_ids = rule.supported_provenance.?.claim_ids;
        };
        const reviewed = (try collectReview(support, a, inputs, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
        const decision = try supportDecision(a, reviewed);
        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
        const binding = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
        const snapshot: state.State = .{
            .schema = state.schema,
            .principle_assessment = try @import("test_fixtures/principles.zig").emptyAssessment(a, reviewed),
            .feature = current.feature,
            .revision = 1,
            .stage = .specified,
            .reference = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "first" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, binding),
            .brief = inputs.brief.?,
            .content = assigned.content,
            .id_ledger = assigned.ledger,
            .coverage = try @import("domain/specification_coverage.zig").validate(a, fixture.context.references, inputs.brief.?, assigned.content),
            .clarification = .{ .state_ordinal = 1, .revision = 1 },
            .review = .{ .candidate_revision = inputs.revision, .seeds = reviewed.seeds, .evidence = reviewed.evidence, .candidates = reviewed.candidates, .observations = decision.observations, .result = decision.result, .advice_stop = reviewed.advice_stop },
        };
        const bytes = try std.json.Stringify.valueAlloc(a, snapshot, .{});
        const restored = (try state.parse(a, bytes, current.feature, contracts.port())).specified().?;
        const traces = try @import("domain/specification_projection.zig").traceRequirements(a, restored.reference, restored.content);
        try std.testing.expectEqual(restored.content.records.len, traces.len);
        for (restored.content.records, traces) |record, trace| try std.testing.expectEqualDeep(record.id, trace.id);
        const linked = try @import("domain/reference_context.zig").render(a, restored.reference, restored.principle_assessment, traces);
        try std.testing.expect(std.mem.indexOf(u8, linked, "## Generated Requirement Sources") != null);
        try std.testing.expect(std.mem.indexOf(u8, linked, "(#cit-") != null);
        const projected = try @import("domain/specification_projection.zig").project(a, fixture.context, restored.content);
        const criterion_index = for (projected.records, 0..) |record, index| {
            if (record.content == .acceptance_criterion) break index;
        } else return error.MissingCriterion;
        try std.testing.expect(std.mem.indexOf(u8, projected.records[criterion_index].content.acceptance_criterion.then.bytes, all.entries[all.entries.len - 1].claim.content.preserved_token.value.raw_value.bytes) != null);
        const markdown = try @import("domain/specification_markdown.zig").render(a, projected);
        try std.testing.expectEqualDeep(projected, try @import("domain/specification_markdown.zig").parse(a, markdown));
        var tampered = snapshot;
        const altered = try a.dupe(spec.IdentifiedRecord, snapshot.content.records);
        altered[criterion_index].proposal.provenance.citation_ids = all.entries[0].claim.citation_ids;
        tampered.content.records = altered;
        try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, tampered, .{}), current.feature, contracts.port()));

        // Skipping a token-only record task does not erase its aggregate exact
        // obligation. Even a legitimate incidental mapping cannot satisfy it.
        var missing_exact = snapshot;
        missing_exact.brief.title = try provenance.checkAttributed(.model, a, text.validator, fixture.context, .{
            .value = .{ .segments = &.{.{ .literal = .{ .value = "The requested behavior is named." } }} },
            .source_group_ids = &.{ fixture.context.references.records.signals[0].id, fixture.context.references.records.signals[1].id },
            .provenance = .{ .claim_ids = &.{ all.entries[0].claim.id, exact }, .clarification_response_ids = &.{} },
        }, .spec_title);
        const without_exact = try a.dupe(spec.IdentifiedRecord, snapshot.content.records);
        const original_record = without_exact[criterion_index].proposal;
        var raw_content = try provenance.modelRecord(a, @import("domain/reference_support.zig").records(fixture.context.references), original_record.content);
        raw_content.acceptance_criterion.then = prose;
        without_exact[criterion_index].proposal = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{ .content = raw_content, .source_group_ids = original_record.source_group_ids, .provenance = selection(original_record.provenance) });
        missing_exact.content.records = without_exact;
        const checked = try @import("domain/specification_coverage.zig").check(a, fixture.context.references, missing_exact.brief, missing_exact.content);
        try std.testing.expect(checked == .invalid);
        try std.testing.expectEqualDeep(exact, checked.invalid.claim_id);
        try std.testing.expect(checked.invalid.issue == .missing_exact_copy);
        try std.testing.expectEqual(@as(usize, 0), (try @import("domain/specification_coverage.zig").exactTargets(a, missing_exact.brief, missing_exact.content, exact)).len);
        // The stored provenance remains valid; current coverage is what fails.
        try provenance.validateStored(a, fixture.context.inputs, .{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences }, @import("domain/reference_support.zig").records(fixture.context.references), missing_exact.brief, missing_exact.content);
        try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, missing_exact, .{}), current.feature, contracts.port()));
    }
}

test "value repair pins the original effective evidence through recurring invalid prose" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Display `MOCK Renewed!` after loan renewal." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const exact = all.entries[all.entries.len - 1].claim.id;
        const good = try fixture.proposal("The application displays the required result.");
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        var candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
        const first = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, first);
        try std.testing.expectEqual(.value, std.meta.activeTag(authorization.target));
        try std.testing.expectEqualDeep(good.provenance.claim_ids, authorization.rule.value_bound.?.effective);
        const packet = try repair.packet(a, current, fixture.context, authorization);
        defer @import("domain/model_input_packet.zig").release(packet);
        for (packet.exactScope().?.occurrences) |occurrence| try std.testing.expect(occurrence.claim_id.ordinal != exact.ordinal);
        const token = try @import("domain/reference_support.zig").exact(all, exact);
        const expanded: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "The user sees {s}.", .{token.value.raw_value.bytes}) } }} };
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, candidate, authorization, .{ .value = expanded }, null));
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = exact } }} } }, null));
        candidate = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Another invalid scalar\x02" } }} } }, null);
        try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, candidate)).?.validated.result);
        const second = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const again = try repair.authorize(a, current, fixture.context, candidate, second);
        try std.testing.expectEqualDeep(authorization.rule.value_bound.?, again.rule.value_bound.?);
        try std.testing.expectEqualDeep(authorization.retry.?.key, again.retry.?.key);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, again, .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = exact } }} } }, null));
        const recovered = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, again, .{ .value = good.value }, null);
        try std.testing.expectEqualDeep(good, recovered.response.content.brief.title);
        try std.testing.expectEqualDeep(good, recovered.response.content.brief.primary_goal);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, recovered)).?.validated.result);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, recovered)) == .valid);
    }
}

test "record repair validates its selected field with shared exact evidence and preserves retry progress" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Show `MOCK Renewed!` after renewal." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const exact = all.entries[all.entries.len - 1].claim.id;
        const plain = try fixture.proposal("The user starts the application.");
        const basis = try provenance.checkAttributed(.model, a, text.validator, fixture.context, plain, .spec_story);
        var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        current.completed = sessions.records_index;
        try std.testing.expectEqual(@as(usize, 1), current.record_group_count);
        current.units[2] = .{ .unit = .entities, .response = .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = basis } } } };
        const copy: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = "The user sees " } }, .{ .exact_copy = .{ .claim_id = exact } } } };
        const record: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{
            .given = .{ .segments = &.{} },
            .when = plain.value,
            .then = copy,
        } }, .source_group_ids = plain.source_group_ids, .provenance = plain.provenance };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{record} } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected);
        try std.testing.expectEqualDeep(plain.provenance.claim_ids, authorization.rule.value_bound.?.explicit);
        try std.testing.expectEqualDeep(&[_]references.r.ClaimId{ all.entries[0].claim.id, exact }, authorization.rule.value_bound.?.effective);
        const repaired = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = plain.value }, null);
        try std.testing.expectEqualDeep(copy, repaired.response.content.records[0].content.acceptance_criterion.then);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, repaired)).?.validated.result);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, repaired)) == .valid);
        const invalid = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} } }, null);
        try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, invalid)).?.validated.result);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, invalid)) == .invalid);
        var invalid_sibling = record;
        invalid_sibling.content.acceptance_criterion.when = .{ .segments = &.{} };
        const with_sibling: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{invalid_sibling} } } };
        const first = (try validate_unit.execute(a, current, fixture.context, with_sibling)).invalid;
        const first_authorization = try repair.authorize(a, current, fixture.context, with_sibling, first);
        const first_repair = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, with_sibling, first_authorization, .{ .value = plain.value }, null);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, first_repair)).?.validated.result);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, first_repair)) == .invalid);
    }
}

test "provenance-only repair is denied even when exact content could supply support" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Display `MOCK Hello, World!` on startup.");
    defer fixture.deinit();
    const all = try provenance.items(fixture.context);
    const exact = all.entries[all.entries.len - 1].claim.id;
    const plain = try fixture.proposal("The application starts.");
    const broken: spec.Model.AttributedValue = .{
        .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = exact } }} },
        .source_group_ids = plain.source_group_ids,
        .provenance = .{ .claim_ids = &.{.{ .ordinal = 999 }}, .clarification_response_ids = &.{} },
    };
    const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
    const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = broken, .description = plain, .primary_goal = plain } } } };
    const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectEqual(.provenance, rejection.issue.rule);
    try std.testing.expectError(error.UnsafeSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejection));
    var exact_only = broken;
    exact_only.source_group_ids = &.{};
    exact_only.provenance.claim_ids = &.{};
    const resolved = try provenance.checkAttributed(.model, a, text.validator, fixture.context, exact_only, .entity_name);
    try std.testing.expectEqual(@as(usize, 0), resolved.provenance.claim_ids.len);
    try std.testing.expectEqualDeep(all.entries[all.entries.len - 1].claim.citation_ids, resolved.provenance.citation_ids);
}

test "fixed repair packet offers only passive choices from its bound claims" {
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{
        "Export stories.md with the specification.",
        "Read stories.md while planning the release.",
    }) |source| {
        var fixture = try Fixture.initContent(a, source, null, true, "The application handles the named file.", 1);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const initial = try sessions.packetFor(a, current, fixture.context, 0);
        defer packets.release(initial);
        const bound = try sessions.packetForOptions(a, current, fixture.context, 0, .{ .exact_claims = &.{} });
        defer packets.release(bound);
        const initial_body = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
        const bound_body = (try std.json.parseFromSlice(std.json.Value, a, bound.body(), .{})).value.object;
        try std.testing.expect(initial_body.get("passive_literals").?.array.items.len > 0);
        try std.testing.expectEqual(initial_body.get("sources").?.array.items.len, bound_body.get("sources").?.array.items.len);
        try std.testing.expectEqual(@as(usize, 0), bound_body.get("passive_literals").?.array.items.len);
    }
}

test "fixed Spec choices narrow the visible token catalogue with the selected schema" {
    const sessions = @import("domain/specification_session.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{
        "Display `MOCK Hello, World!` on startup.",
        "Export `report.csv` when requested.",
    }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const initial = try sessions.packetFor(a, current, fixture.context, 0);
        defer packets.release(initial);
        const before = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value;
        try std.testing.expect(before.object.get("preserved_tokens").?.array.items.len > 0);
        const business = fixture.context.references.records.assignments.checked.prior.prior.input.items[0].claim.id;
        const narrowed = try sessions.withSelectionChoices(a, initial, fixture.context, .{ .claim_ids = &.{business}, .clarification_response_ids = &.{} });
        defer packets.release(narrowed);
        const after = (try std.json.parseFromSlice(std.json.Value, a, narrowed.body(), .{})).value;
        try std.testing.expectEqual(@as(usize, 0), after.object.get("preserved_tokens").?.array.items.len);
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, before.object.get("source_assignment").?, .{}), try std.json.Stringify.valueAlloc(a, after.object.get("source_assignment").?, .{}));
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, before.object.get("context_requirements").?, .{}), try std.json.Stringify.valueAlloc(a, after.object.get("context_requirements").?, .{}));
        for (narrowed.integerChoices()) |choice| if (choice.target == .tagged) try std.testing.expect(!std.mem.eql(u8, choice.target.tagged.kind, "exact_copy"));
    }
}

const preservation = @import("domain/source_omission.zig").comparisons;
const PreservationTest = struct {
    inputs: @import("domain/required_authority.zig").Inputs,
    pending: @import("domain/specification_support.zig").Source.Candidate,
};
const PreservationOwner = enum { source_readiness, source_preservation };
fn preservationTest(a: std.mem.Allocator, fixture: *const Fixture, owner: PreservationOwner, obligation: []const u8) !PreservationTest {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const inputs = switch (owner) {
        .source_readiness => try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null),
        .source_preservation => try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs),
    };
    const ledger = try authority.build(a, inputs);
    const entries = try a.dupe(support.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
    var selected: u32 = 0;
    for (ledger.requirements, entries, 1..) |requirement, *entry, index| {
        const omitted = if (owner == .source_readiness) requirement.seed.id.slot == .description else index == 1;
        entry.requirement_ordinal = @intCast(index);
        if (omitted) {
            entry.value.kind = .candidate_omission;
            entry.value.missing_obligation = obligation;
            entry.value.detail = "MOCK Required behavior is missing.";
            entry.value.source_ids = &.{.{ .ordinal = 1 }};
        }
        if (omitted) selected = @intCast(index);
    }
    const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, entries.len);
    @memset(origins, null);
    return .{ .inputs = inputs, .pending = .{ .review = .{ .entries = entries }, .pending_localization = selected, .origin = null, .origins = origins } };
}
fn preservationResponse(a: std.mem.Allocator, assigned: preservation.Assignment, verdict: preservation.Verdict) !preservation.Response {
    const entries = try a.alloc(preservation.Assessment, assigned.comparisons.len);
    for (assigned.comparisons, entries) |view, *entry| {
        const spans = try a.dupe(preservation.Span, &.{.{ .chunk_id = assigned.sources[0].chunk_id, .lines = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } } }});
        entry.* = .{ .comparison_id = view.id, .result = verdict, .sources = spans, .explanation = "MOCK Comparison evidence." };
    }
    return .{ .assessments = entries };
}

test "bound preservation rejects missing duplicate foreign evidence and empty preserved collections" {
    const support = @import("domain/specification_support.zig").Source;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "MOCK Required behavior.", null, true, "MOCK Required behavior.", 2);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Required behavior.");
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, state.pending);
    const good = try preservationResponse(a, assigned, .preserved);
    try std.testing.expectEqual(@as(usize, 2), assigned.comparisons[0].members.len);
    try std.testing.expect(assigned.comparisons[0].members[0].claim_id.ordinal != assigned.comparisons[0].members[1].claim_id.ordinal);
    try std.testing.expectError(error.InvalidPreservationComparison, preservation.admit(a, assigned, assigned, fixture.context.inputs, .{ .assessments = &.{} }));
    for (0..5) |variant| {
        var response = try preservationResponse(a, assigned, .preserved);
        const entries = try a.dupe(preservation.Assessment, response.assessments);
        response.assessments = entries;
        switch (variant) {
            0 => entries[0].comparison_id.ordinal = 999,
            1 => entries[0].sources = &.{},
            2 => entries[0].sources = &.{.{ .chunk_id = assigned.sources[0].chunk_id, .lines = .{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } } }},
            3 => entries[0].explanation = " ",
            4 => response.assessments = try a.dupe(preservation.Assessment, &.{ entries[0], entries[0] }),
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidPreservationComparison, preservation.admit(a, assigned, assigned, fixture.context.inputs, response));
    }
    var empty = assigned;
    empty.comparisons = &.{};
    empty.boundaries = &.{};
    try std.testing.expectEqual(preservation.Attribution.unresolved, try preservation.admit(a, empty, empty, fixture.context.inputs, .{ .assessments = &.{} }));
    var malformed = assigned;
    malformed.boundaries = &.{.{ .input = .deficient_subject, .output = .source_premise, .owner = null }};
    try std.testing.expectError(error.InvalidPreservationComparison, preservation.admit(a, malformed, malformed, fixture.context.inputs, good));
}

test "reported lost obligations admit against complete nonempty native collections without model member selection" {
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    // Supplied verdicts exercise admission only; native code does not prove that
    // these mocked source and collection meanings justify the judgment.
    for ([_][3][]const u8{
        .{ "MOCK Shut down the pump after an alarm and keep it off until recovery.", "MOCK Record pump temperature.", "MOCK Pump monitoring does not state alarm shutdown or recovery." },
        .{ "MOCK Enable backup cooling and sound an alarm when temperature is unsafe.", "MOCK Display temperature.", "MOCK Temperature display does not state cooling or alarm behavior." },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, example[0], null, true, example[1], 2);
        defer fixture.deinit();
        const state = try preservationTest(a, &fixture, .source_preservation, example[0]);
        const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, state.pending);
        try std.testing.expectEqual(@as(usize, 2), assigned.comparisons[0].members.len);
        var response = try preservationResponse(a, assigned, .lost);
        const assessments = try a.dupe(preservation.Assessment, response.assessments);
        for (assessments) |*assessment| assessment.explanation = example[2];
        response.assessments = assessments;
        const bytes = try json.encode(preservation.Response, a, response);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
        for (parsed.value.object.get("assessments").?.array.items) |entry| try std.testing.expect(!entry.object.contains("members"));
        const attribution = try support.admitComparisons(a, state.inputs, fixture.context, state.pending, assigned, bytes);
        try std.testing.expect(attribution == .established and attribution.established == .existing and attribution.established.existing == .extraction_claim);
        const packet = try support.packetForLoss(a, state.inputs, fixture.context, state.pending);
        defer @import("domain/model_input_packet.zig").release(packet);
        const accepted = (try support.collectLoss(a, state.inputs, fixture.context, .{ .pending = state.pending }, packet, bytes, null)).accepted;
        const retained = accepted.candidate.review.entries[state.pending.pending_localization.? - 1].value.preservation.?;
        try std.testing.expectEqualDeep(assigned, retained.assignment);
        try std.testing.expectEqualDeep(response, retained.response);
        for (0..4) |variant| {
            var changed = assigned;
            const views = try a.dupe(preservation.View, assigned.comparisons);
            changed.comparisons = views;
            switch (variant) {
                0 => views[0].members = views[0].members[0..1],
                1 => {
                    const members = try a.dupe(preservation.Member, views[0].members);
                    members[1].claim_id.ordinal = members[0].claim_id.ordinal;
                    views[0].members = members;
                },
                2 => views[0].purpose = "MOCK Different collection purpose.",
                3 => changed.finding.missing_obligation = "MOCK Different obligation.",
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidPreservationComparison, preservation.admit(a, assigned, changed, fixture.context.inputs, response));
        }
    }
}

test "native preservation collection retains equal literal occurrences under different triggers" {
    const support = @import("domain/specification_support.zig").Source;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "MOCK On startup display `MOCK Ready`.\nMOCK After recovery display `MOCK Ready`.\n";
    var claims: [2]@import("domain/reference_extraction.zig").Proposal = undefined;
    for (&claims, [_][]const u8{ "MOCK On startup display `MOCK Ready`.", "MOCK After recovery display `MOCK Ready`." }, 1..) |*claim, value, line| claim.* = .{
        .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = value } }} } },
        .citations = try a.dupe(@import("domain/source_selections.zig").Selection, &.{.{ .first = .{ .ordinal = @intCast(line) }, .last = .{ .ordinal = @intCast(line) } }}),
    };
    var fixture = try Fixture.initClaims(a, source, .business_exact_string, .{ .selected = &claims });
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_preservation, source);
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, state.pending);
    try std.testing.expectEqual(@as(usize, 4), assigned.comparisons[0].members.len);
    const items = assigned.facts.records.items;
    const first = try references.r.item(items, assigned.comparisons[0].members[2].claim_id);
    const second = try references.r.item(items, assigned.comparisons[0].members[3].claim_id);
    try std.testing.expect(first.claim.content == .preserved_token and second.claim.content == .preserved_token);
    try std.testing.expectEqualStrings(first.claim.content.preserved_token.value.raw_value.bytes, second.claim.content.preserved_token.value.raw_value.bytes);
    try std.testing.expect(first.claim.id.ordinal != second.claim.id.ordinal);
    try std.testing.expect(!std.meta.eql(first.citations[0].value.location, second.citations[0].value.location));
    const response = try preservationResponse(a, assigned, .preserved);
    try std.testing.expectEqual(preservation.Attribution.unresolved, try preservation.admit(a, assigned, assigned, fixture.context.inputs, response));
    const encoded = try @import("domain/strict_json.zig").decode(preservation.Evidence, a, try std.json.Stringify.valueAlloc(a, preservation.Evidence{ .assignment = assigned, .response = response }, .{}), .{ .maximum_depth = 128 });
    try std.testing.expectEqualDeep(assigned.comparisons, encoded.assignment.comparisons);
    try std.testing.expectEqualDeep(response, encoded.response);
}

test "bound preservation traces source-only loss without inventing a positive claim" {
    const support = @import("domain/specification_support.zig").Source;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initExtraction(a, "MOCK Retain the required obligation.", null, false);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_preservation, "MOCK Retain the required obligation.");
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, state.pending);
    try std.testing.expectEqual(@as(usize, 0), assigned.comparisons[0].members.len);
    const absent = try preservationResponse(a, assigned, .lost);
    const result = try preservation.admit(a, assigned, assigned, fixture.context.inputs, absent);
    try std.testing.expect(result == .established and result.established.existing == .extraction_claim);
    try std.testing.expectError(error.InvalidPreservationComparison, preservation.admit(a, assigned, assigned, fixture.context.inputs, try preservationResponse(a, assigned, .preserved)));
    try std.testing.expectEqual(preservation.Attribution.unresolved, try preservation.admit(a, assigned, assigned, fixture.context.inputs, try preservationResponse(a, assigned, .uncertain)));
}

test "bound preservation packet owns evidence after preparation arena teardown" {
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const packet = blk: {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, "MOCK Keep an audit record.", null, true, "MOCK Keep an audit record.", 1);
        defer fixture.deinit();
        const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Keep an audit record.");
        break :blk try support.packetForLoss(std.testing.allocator, state.inputs, fixture.context, state.pending);
    };
    defer packets.release(packet);
    try std.testing.expectEqualStrings("preservation_comparisons", packet.resultDefinition().?.bytes);
    try std.testing.expect(std.mem.indexOf(u8, packet.body(), "MOCK Keep an audit record.") != null);
    const owned = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, packet.body(), .{});
    defer owned.deinit();
    try std.testing.expectEqualStrings("MOCK Keep an audit record.", owned.value.object.get("fixed_finding").?.object.get("missing_obligation").?.string);
    try std.testing.expect(std.mem.indexOf(u8, packet.body(), "\"comparisons\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, packet.body(), "\"boundaries\"") == null);
}

test "bound preservation shared schema and codec exclude culprit and verdict reassessment" {
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "MOCK Close the valve on alarm.", null, true, "MOCK Close the valve on alarm.", 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Close the valve on alarm.");
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, state.pending);
    const response = try preservationResponse(a, assigned, .preserved);
    const bytes = try json.encode(preservation.Response, a, response);
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, state.pending);
    defer @import("domain/model_input_packet.zig").release(packet);
    const selected = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer selected.release();
    try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = bytes });
    try std.testing.expectEqualDeep(response, try json.decode(preservation.Response, a, bytes));
    const forbidden = "{\"assessments\":[],\"location\":{\"kind\":\"candidate\"}}";
    try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = forbidden, .rejection = .unknown_property, .path = "/location" });
    try std.testing.expectError(error.InvalidJsonDocument, json.decode(preservation.Response, a, forbidden));
    try std.testing.expectError(error.InvalidJsonDocument, json.decode(preservation.Response, a, "{\"assessments\":[],\"finding\":\"supported\"}"));
    const foreign = try a.dupe(preservation.Assessment, response.assessments);
    foreign[0].comparison_id.ordinal = 999;
    try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = try json.encode(preservation.Response, a, .{ .assessments = foreign }), .rejection = .enum_mismatch, .path = "/assessments/0/comparison_id" });
    for ([_][]const u8{ "[]", "[1]" }) |members| {
        // Every assigned comparison stays present, so only the retired field differs.
        var retired = try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{});
        try retired.object.getPtr("assessments").?.array.items[0].object.put(a, "members", try std.json.parseFromSliceLeaky(std.json.Value, a, members, .{}));
        const obsolete = try std.json.Stringify.valueAlloc(a, retired, .{});
        try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = obsolete, .rejection = .unknown_property, .path = "/assessments/0/members" });
        try std.testing.expectError(error.InvalidJsonDocument, json.decode(preservation.Response, a, obsolete));
    }
    const unknown = try std.mem.replaceOwned(u8, a, bytes, "\"preserved\"", "\"approved\"");
    try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = unknown, .rejection = .enum_mismatch, .path = "/assessments/0/result" });
    try std.testing.expectError(error.InvalidJsonDocument, json.decode(preservation.Response, a, unknown));
}

fn preservationAllocationCheck(a: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    var fixture = try Fixture.initContent(arena.allocator(), "MOCK Retain a receipt.", null, true, "MOCK Retain a receipt.", 1);
    defer fixture.deinit();
    const state = try preservationTest(arena.allocator(), &fixture, .source_readiness, "MOCK Retain a receipt.");
    const packet = try @import("domain/specification_support.zig").Source.packetForLoss(a, state.inputs, fixture.context, state.pending);
    defer @import("domain/model_input_packet.zig").release(packet);
}

test "bound preservation preparation cleans up allocation failures" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(preservationAllocationCheck, .{});
}

test "bound preservation does not attribute composite classification loss to claim insertion" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initExtraction(a, "MOCK Display `MOCK Ready` after approval.", null, true);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_preservation, "MOCK Display `MOCK Ready` after approval.");
    const assigned = try @import("domain/specification_support.zig").Source.comparisonAssignment(a, state.inputs, fixture.context, state.pending);
    try std.testing.expect(assigned.boundaries[0].owner == null);
    const response = try preservationResponse(a, assigned, .lost);
    try std.testing.expectEqual(preservation.Attribution.unresolved, try preservation.admit(a, assigned, assigned, fixture.context.inputs, response));
    const foreign = try a.dupe(preservation.Assessment, response.assessments);
    foreign[0].sources = &.{.{ .chunk_id = .{ .bytes = "MOCK foreign chunk" }, .lines = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } } }};
    try std.testing.expectError(error.InvalidPreservationComparison, preservation.admit(a, assigned, assigned, fixture.context.inputs, .{ .assessments = foreign }));
}

fn collectedPreservation(a: std.mem.Allocator, fixture: *const Fixture, state: PreservationTest, location: @import("domain/source_omission.zig").Location, origin: ?@import("domain/model_candidate_origin.zig").Origin) !@import("domain/specification_support.zig").Source.Collection {
    const support = @import("domain/specification_support.zig").Source;
    var pending = state.pending;
    const good = try reviewFor(a, state.inputs, fixture.context.inputs);
    const entries = try a.dupe(support.Finding, good.entries);
    const index = pending.pending_localization.? - 1;
    entries[index].value.kind = .candidate_omission;
    entries[index].value.missing_obligation = pending.review.entries[index].value.missing_obligation;
    entries[index].value.detail = pending.review.entries[index].value.detail;
    entries[index].value.source_ids = pending.review.entries[index].value.source_ids;
    pending.review.entries = entries;
    const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, entries.len);
    @memset(origins, .{ .request = .{ .value = 31 }, .attempt = .{ .value = 1 } });
    pending.origins = origins;
    pending.origin = origins[0];
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, pending);
    defer @import("domain/model_input_packet.zig").release(packet);
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, pending);
    return support.collectLoss(a, state.inputs, fixture.context, .{ .pending = pending }, packet, try @import("test_fixtures/source_omission_evidence.zig").encode(a, assigned, location), origin);
}

test "preservation lifecycle retains distinct origins and rederives attribution without request logs" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const codec = @import("domain/strict_json.zig");
    for ([_][]const u8{ "MOCK Display date after approval.", "MOCK Renew only an eligible loan." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, null, true, source, 1);
        defer fixture.deinit();
        var state = try preservationTest(a, &fixture, .source_readiness, source);
        const native = try authority.build(a, state.inputs);
        const selected = for (native.requirements, 0..) |required, position| {
            if (required.seed.id.unit == .signal) break position;
        } else return error.MissingSignalRequirement;
        const baseline = try reviewFor(a, state.inputs, fixture.context.inputs);
        const findings = try a.dupe(support.Finding, baseline.entries);
        const target = native.requirements[selected].seed.id;
        findings[selected].value = try @import("domain/specification_support_model.zig").canonical(.{ .candidate_omission = .{
            .source_ids = &.{fixture.context.inputs.corpus.sources[0].id},
            .detail = "MOCK The selected signal loses its original obligation.",
            .missing_obligation = source,
        } }, try @import("domain/specification_support_evidence.zig").requirements(a, state.inputs, fixture.context.inputs, target));
        state.pending.review.entries = findings;
        state.pending.pending_localization = @intCast(selected + 1);
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 32 }, .attempt = .{ .value = 2 } };
        const accepted = (try collectedPreservation(a, &fixture, state, .{ .reconciliation_signal = fixture.context.references.records.signals[0].id }, origin)).accepted;
        const index = state.pending.pending_localization.? - 1;
        try std.testing.expectEqualDeep(@import("domain/source_omission.zig").Location{ .reconciliation_signal = target.unit.signal }, accepted.inputs.evidence[index].review.?.loss.?);
        try std.testing.expectEqual(@as(u32, 31), accepted.candidate.origins[index].?.request.value);
        const retained = accepted.inputs.evidence[index].review.?.preservation.?;
        try std.testing.expectEqualDeep(origin, retained.origin.?);
        const bytes = try std.json.Stringify.valueAlloc(a, accepted.inputs.evidence, .{});
        var restored = accepted.inputs;
        restored.evidence = try codec.decode([]const authority.Evidence, a, bytes, .{ .maximum_depth = 128 });
        restored.review_origins = &.{};
        restored.review_origin = null;
        try support.validateStored(a, restored, fixture.context.inputs);
        try std.testing.expectEqualStrings(source, restored.evidence[index].review.?.missing_obligation.?);
        try std.testing.expectEqualStrings(source, retained.assignment.finding.missing_obligation);
        for (0..9) |variant| {
            var changed = restored;
            const proofs = try a.dupe(authority.Evidence, changed.evidence);
            changed.evidence = proofs;
            const proof = &proofs[index].review.?.preservation.?;
            switch (variant) {
                0 => proof.assignment.finding.detail = "MOCK A different omission.",
                1 => proof.assignment.facts.revision += 1,
                2 => proof.assignment.boundaries = &.{},
                3 => proof.response.assessments = &.{},
                4 => {
                    const foreign: @import("domain/source_omission.zig").Location = .{ .reconciliation_signal = .{ .ordinal = 999 } };
                    try std.testing.expect(!proofs[index].review.?.loss.?.eql(foreign));
                    proofs[index].review.?.loss = foreign;
                },
                5 => proofs[index].review.?.preservation = null,
                6 => proof.assignment.finding.missing_obligation = "MOCK Require a different action.",
                7 => proofs[index].review.?.missing_obligation = "MOCK Require a different action.",
                8 => proofs[index].review.?.missing_obligation = null,
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, changed, fixture.context.inputs));
        }
        var stale = state.inputs;
        stale.revision += 1;
        const rejection = (try support.validate(a, stale, fixture.context.inputs, accepted.candidate)).rejected;
        try std.testing.expectEqual(.invalid_loss, rejection.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(origin, rejection.rejection.selected().?.origin.?);
        try std.testing.expectError(error.UnsafeSupportRepair, @import("domain/specification_support_repair.zig").Source.authorize(a, stale, fixture.context, rejection));
    }
}

test "invalid preservation response reports comparison call and cannot enter semantic repair" {
    const support = @import("domain/specification_support.zig").Source;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "MOCK Preserve receipt.", null, true, "MOCK Preserve receipt.", 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Preserve receipt.");
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, state.pending);
    defer @import("domain/model_input_packet.zig").release(packet);
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 44 }, .attempt = .{ .value = 3 } };
    const result = (try support.collectLoss(a, state.inputs, fixture.context, .{ .pending = state.pending }, packet, "{\"assessments\":[]}", origin)).rejected;
    try std.testing.expectEqualDeep(origin, result.rejection.selected().?.origin.?);
    try std.testing.expectEqual(state.pending.review.entries[state.pending.pending_localization.? - 1].value.kind, result.candidate.?.review.entries[state.pending.pending_localization.? - 1].value.kind);
    try std.testing.expectEqual(.invalid_loss, result.rejection.selected().?.evidence.?.issue);
    try std.testing.expectError(error.UnsafeSupportRepair, @import("domain/specification_support_repair.zig").Source.authorize(a, state.inputs, fixture.context, result));
    try std.testing.expectError(error.InvalidJsonDocument, support.collectLoss(a, state.inputs, fixture.context, .{ .pending = state.pending }, packet, "{\"kind\":\"candidate\"}", origin));
}

test "multi-chunk and separately classified loss cannot fabricate a unique upstream repair owner" {
    for ([_][2][]const u8{ .{ "MOCK Preserve all conditions.\n" ** 70, "MOCK Preserve all conditions." }, .{ "MOCK Display `MOCK Approved` after confirmation.", "MOCK Display `MOCK Approved` after confirmation." } }) |example| {
        const source = example[0];
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, null, true, "MOCK Partial meaning.", 1);
        defer fixture.deinit();
        const state = try preservationTest(a, &fixture, .source_preservation, example[1]);
        const accepted = (try collectedPreservation(a, &fixture, state, .{ .unlocalized = .{} }, null)).accepted;
        try @import("domain/specification_support.zig").Source.validateStored(a, accepted.inputs, fixture.context.inputs);
        const assignment = accepted.inputs.evidence[0].review.?.preservation.?.assignment;
        try std.testing.expect(assignment.boundaries[0].owner == null);
        const response = try preservationResponse(a, assignment, .lost);
        try std.testing.expectEqual(preservation.Attribution.unresolved, try preservation.admit(a, assignment, assignment, fixture.context.inputs, response));
    }
}

test "collecting a second comparison preserves independent admitted evidence" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "MOCK Keep both receipt and deadline.", null, true, "MOCK Keep both receipt and deadline.", 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Keep both receipt and deadline.");
    const first = (try collectedPreservation(a, &fixture, state, .{ .reconciliation_signal = fixture.context.references.records.signals[0].id }, null)).accepted;
    const ledger = try authority.build(a, state.inputs);
    const index = for (ledger.requirements, 0..) |required, at| {
        if (required.seed.id.unit == .feature and required.seed.id.slot == .primary_goal) break at;
    } else return error.InvalidFixture;
    var pending = first.candidate;
    const entries = try a.dupe(support.Finding, pending.review.entries);
    entries[index].value.kind = .candidate_omission;
    entries[index].value.missing_obligation = fixture.context.inputs.corpus.sources[0].bytes;
    entries[index].value.source_ids = &.{.{ .ordinal = 1 }};
    entries[index].value.detail = "MOCK The goal loses the required purpose.";
    pending.review.entries = entries;
    pending.pending_localization = @intCast(index + 1);
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, pending);
    defer @import("domain/model_input_packet.zig").release(packet);
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, pending);
    const second = (try support.collectLoss(a, state.inputs, fixture.context, .{ .pending = pending }, packet, try @import("test_fixtures/source_omission_evidence.zig").encode(a, assigned, .{ .reconciliation_signal = fixture.context.references.records.signals[0].id }), null)).accepted;
    const original = state.pending.pending_localization.? - 1;
    try std.testing.expectEqualDeep(first.candidate.review.entries[original], second.candidate.review.entries[original]);
    try support.validateStored(a, second.inputs, fixture.context.inputs);
    const unsupported = second.candidate.review.entries[index];
    const rules = try @import("domain/specification_support_evidence.zig").requirements(a, state.inputs, fixture.context.inputs, ledger.requirements[index].seed.id);
    var forged = unsupported.value;
    forged.kind = .supported;
    try std.testing.expectError(error.InvalidJsonDocument, @import("domain/specification_support_model.zig").bindLoss(rules, forged, .{ .reconciliation_signal = fixture.context.references.records.signals[0].id }, unsupported.value.preservation.?));
}

test "omission admission requires its source premise before preparing comparisons" {
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "MOCK Retain the delivery deadline.", null, true, "MOCK Retain the delivery deadline.", 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Retain the delivery deadline.");
    var missing = state.pending;
    const entries = try a.dupe(support.Finding, missing.review.entries);
    const index = missing.pending_localization.? - 1;
    try std.testing.expectEqual(@as(usize, 0), entries[index].value.provenance.claim_ids.len);
    entries[index].value.source_ids = &.{};
    missing.review.entries = entries;
    const rejected = (try support.validate(a, state.inputs, fixture.context.inputs, missing)).rejected;
    try std.testing.expectEqual(admission.Issue.missing_evidence, rejected.rejection.selected().?.evidence.?.issue);
    try std.testing.expectEqual(.source_required, rejected.rejection.selected().?.evidence.?.rule.minimum);
    try std.testing.expect((try support.validate(a, state.inputs, fixture.context.inputs, state.pending)) == .accepted);
}

test "bound preservation calibration separates current admission from unavailable historical candidate subjects" {
    try @import("test_fixtures/source_loss_calibration.zig").run();
}

test "source review scope calibration validates current native requests without semantic evidence or dispatch" {
    try @import("test_fixtures/source_review_scope_calibration.zig").run();
}

test "source review handoff retains generated advice and pre-generation comparison controls" {
    try @import("test_fixtures/source_review_handoff_calibration.zig").run();
}

// Most permission tests assert the outcome; reporting tests retain this trace.
test "source reviewer supplies one obligation and loss review carries it without interpreting diagnostic prose" {
    const support = @import("domain/specification_support.zig").Source;
    const model = @import("domain/specification_support_model.zig");
    const admission = @import("domain/specification_support_evidence.zig");
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][]const u8{
        "MOCK At startup display Hello, World! and the current UTC date and time.",
        "MOCK Renew only eligible loans; do not change the deadline when renewal is refused.",
        "MOCK After cancellation the service must notify the patient.",
        "MOCK After approval retain the receipt for thirty days.",
    }) |obligation| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, obligation, null, true, obligation, 1);
        defer fixture.deinit();
        const state = try preservationTest(a, &fixture, .source_preservation, obligation);
        const id = state.inputs.seeds[0].id;
        const required = try admission.requirements(a, state.inputs, fixture.context.inputs, id);
        const initial = try support.packetFor(a, state.inputs, fixture.context, .{ .finding = id });
        defer packets.release(initial);
        const review_origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 701 }, .attempt = .{ .value = 2 } };
        const loss_origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 702 }, .attempt = .{ .value = 1 } };
        const source_ids: []const @import("domain/reference_identity.zig").SourceId = &.{fixture.context.inputs.corpus.sources[0].id};
        const response = try json.encode(model.Value, a, .{ .candidate_omission = .{
            .source_ids = source_ids,
            .detail = "MOCK The captured producer discarded this requirement.",
            .missing_obligation = obligation,
        } });
        const collected = (try support.collectFocused(a, state.inputs, fixture.context, null, initial, response, review_origin)).accepted;
        const finding = collected.candidate.review.entries[0].value;
        try std.testing.expectEqualStrings(obligation, finding.missing_obligation.?);
        try std.testing.expectEqualStrings(obligation, collected.inputs.evidence[0].review.?.missing_obligation.?);
        try std.testing.expectEqualDeep(source_ids, finding.source_ids);
        try std.testing.expectEqualDeep(source_ids, collected.inputs.evidence[0].review.?.source_ids);
        try std.testing.expectEqualDeep(review_origin, collected.inputs.review_origins[0].?);
        const packet = try support.packetForLoss(a, state.inputs, fixture.context, collected.candidate);
        defer packets.release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        const fixed = body.get("fixed_finding").?.object;
        try std.testing.expectEqual(@as(usize, 1), fixed.count());
        try std.testing.expectEqualStrings(obligation, fixed.get("missing_obligation").?.string);
        try std.testing.expectEqualStrings(finding.detail, body.get("supporting_evidence").?.object.get("diagnostic_detail").?.string);
        const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, collected.candidate);
        try std.testing.expectEqualStrings(obligation, assigned.finding.missing_obligation);
        try std.testing.expectEqualDeep(source_ids, assigned.finding.source_ids);
        try std.testing.expectEqual(@as(usize, assigned.sources.len), body.get("sources").?.array.items.len);
        for (assigned.sources, body.get("sources").?.array.items) |source, visible| {
            try std.testing.expectEqual(@as(i64, source.source_id.ordinal), visible.object.get("source_id").?.integer);
            try std.testing.expectEqualStrings(source.chunk_id.bytes, visible.object.get("chunk_id").?.object.get("bytes").?.string);
            try std.testing.expectEqual(source.lines.len, visible.object.get("lines").?.array.items.len);
        }
        const assessed = try preservationResponse(a, assigned, .lost);
        const assessed_bytes = try json.encode(preservation.Response, a, assessed);
        var stale = assigned;
        stale.finding.missing_obligation = "MOCK A different obligation must be satisfied.";
        try std.testing.expectError(error.InvalidPreservationComparison, preservation.admit(a, assigned, stale, fixture.context.inputs, assessed));
        var changed = collected.candidate;
        const changed_entries = try a.dupe(support.Finding, changed.review.entries);
        changed_entries[0].value.missing_obligation = stale.finding.missing_obligation;
        changed.review.entries = changed_entries;
        try std.testing.expectError(error.InvalidPreservationComparison, support.admitComparisons(a, state.inputs, fixture.context, changed, assigned, assessed_bytes));
        try std.testing.expectError(error.InvalidRequiredAuthority, support.collectLoss(a, state.inputs, fixture.context, .{ .pending = changed }, packet, assessed_bytes, loss_origin));
        const localized = (try support.collectLoss(a, state.inputs, fixture.context, .{ .accepted = collected }, packet, assessed_bytes, loss_origin)).accepted;
        try std.testing.expectEqualStrings(obligation, localized.candidate.review.entries[0].value.missing_obligation.?);
        const retained = localized.inputs.evidence[0].review.?.preservation.?;
        try std.testing.expectEqualDeep(assigned, retained.assignment);
        try std.testing.expectEqualDeep(review_origin, localized.inputs.review_origins[0].?);
        try std.testing.expectEqualDeep(loss_origin, retained.origin.?);
        try support.validateStored(a, localized.inputs, fixture.context.inputs);

        const foreign_source = try json.encode(model.Value, a, .{ .candidate_omission = .{
            .source_ids = &.{.{ .ordinal = 999 }},
            .detail = finding.detail,
            .missing_obligation = obligation,
        } });
        const rejected = (try support.collectFocused(a, state.inputs, fixture.context, null, initial, foreign_source, review_origin)).rejected;
        try std.testing.expectEqual(.invalid_sources, rejected.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(review_origin, rejected.rejection.selected().?.origin.?);
        var foreign_response = assessed;
        const foreign_entries = try a.dupe(preservation.Assessment, assessed.assessments);
        foreign_entries[0].sources = &.{.{ .chunk_id = .{ .bytes = "MOCK unassigned source" }, .lines = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } } }};
        foreign_response.assessments = foreign_entries;
        const loss_rejected = (try support.collectLoss(a, state.inputs, fixture.context, .{ .accepted = collected }, packet, try json.encode(preservation.Response, a, foreign_response), loss_origin)).rejected;
        try std.testing.expectEqual(.invalid_loss, loss_rejected.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(loss_origin, loss_rejected.rejection.selected().?.origin.?);

        // The obsolete overloaded wire shape cannot silently reconstruct a target.
        for ([_][]const u8{
            "{\"kind\":\"candidate_omission\",\"source_ids\":[1],\"detail\":\"MOCK The producer omitted notification.\"}",
            "{\"kind\":\"candidate_omission\",\"source_ids\":[1],\"detail\":\"MOCK Missing.\",\"missing_obligation\":null}",
            "{\"kind\":\"candidate_omission\",\"source_ids\":[1],\"detail\":\"MOCK Missing.\",\"missing_obligation\":\"MOCK Notify the patient.\",\"fallback\":true}",
            "{\"kind\":\"supported\",\"source_ids\":[1],\"detail\":\"MOCK Supported.\",\"missing_obligation\":\"MOCK Notify the patient.\"}",
        }) |invalid| try std.testing.expectError(error.InvalidJsonDocument, model.decode(a, invalid, required));
    }
}

fn checkProtocolCorrectionPreservesPacket(a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, prompt: []const u8, rejected_bytes: []const u8) !void {
    const schemas = @import("domain/model_result_schema.zig");
    const build_request = @import("actions/model/build_model_request.zig");
    const correction_prompt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/protocol.prompt.md", a, .limited(1_048_576));
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .limited(1_048_576)));
    const selected = schema.select(packet.resultDefinition().?).?;
    const restricted = try schemas.restrict(std.testing.allocator, selected, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    var provider_fixture: @import("provider_invocation_test_fixture.zig").Fixture = undefined;
    try provider_fixture.initWithCompiledSchema(selected);
    defer provider_fixture.deinit();
    var request_source = try provider_fixture.requestSource();
    request_source.restriction = restricted;
    const prepared = try (build_request.Action{}).execute(std.testing.allocator, request_source, &.{ .{ .guidance = prompt }, .{ .user = packet.body() } });
    provider_fixture.prepared.deinit();
    provider_fixture.prepared = prepared;
    provider_fixture.base.request = prepared.request.*;
    provider_fixture.call.request = prepared.request;
    request_source = try provider_fixture.requestSource();
    request_source.restriction = restricted;
    provider_fixture.fake.invocation_plan.complete.content = rejected_bytes;
    var response = try provider_fixture.response();
    defer response.deinit();
    var captured = try (@import("actions/model/validate_provider_invocation_observation.zig").Action{}).execute(std.testing.allocator, provider_fixture.call, &response);
    defer captured.deinit();
    var decoded = try (@import("actions/model/decode_model_envelope.zig").Action{}).execute(std.testing.allocator, captured.evidence.result().complete, null);
    defer decoded.deinit();
    const validation = @import("domain/model_payload_schema.zig");
    const diagnostic = validation.validate(decoded.candidate).invalid;
    try std.testing.expectEqual(validation.Rejection.unknown_property, diagnostic.reason);
    var retry = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, request_source, prepared.request.content, captured.evidence, .{ .schema = diagnostic }, .unconfirmed, correction_prompt);
    defer retry.deinit();
    try std.testing.expectEqualDeep(prepared.request.content, retry.request.content[0..prepared.request.content.len]);
    try std.testing.expectEqualDeep(prepared.request.model_request_id, retry.request.model_request_id);
    try std.testing.expect(retry.request.response_schema == restricted.selected());
    for ([_]*const @import("domain/llm_provider_operation.zig").IdentifiedProviderNeutralModelRequest{ prepared.request, retry.request }) |request| {
        var guidance_count: usize = 0;
        var packet_count: usize = 0;
        for (request.content) |part| switch (part) {
            .guidance => |bytes| guidance_count += @intFromBool(std.mem.eql(u8, prompt, bytes)),
            .user => |bytes| packet_count += @intFromBool(std.mem.eql(u8, packet.body(), bytes)),
            .system, .evidence => {},
        };
        try std.testing.expectEqual(@as(usize, 1), guidance_count);
        try std.testing.expectEqual(@as(usize, 1), packet_count);
    }
}

test "loss request correction preserves canonical citation guidance and the complete native collection" {
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obligation = "MOCK After refusal do not change the deadline; retain the receipt for thirty days.";
    var source_fixture = try Fixture.initContent(a, obligation, null, true, obligation, 2);
    defer source_fixture.deinit();
    const state = try preservationTest(a, &source_fixture, .source_preservation, obligation);
    const assigned = try support.comparisonAssignment(a, state.inputs, source_fixture.context, state.pending);
    try std.testing.expectEqual(@as(usize, 2), assigned.comparisons[0].members.len);
    const packet = try support.packetForLoss(a, state.inputs, source_fixture.context, state.pending);
    defer packets.release(packet);
    const prompt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support-loss.prompt.md", a, .limited(1_048_576));
    try checkProtocolCorrectionPreservesPacket(a, packet, prompt, "{\"assessments\":[],\"members\":[]}");
    // Protocol correction preserves inputs and scope; it supplies no semantic
    // verdict and cannot replace or select the collection being assessed.
    try std.testing.expectEqualDeep(assigned, try support.comparisonAssignment(a, state.inputs, source_fixture.context, state.pending));
}

test "supported and source-gap findings never create loss or upstream repair authority" {
    const support = @import("domain/specification_support.zig").Source;
    const model = @import("domain/specification_support_model.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_]model.Value{
        .{ .supported = .{ .source_ids = &.{.{ .ordinal = 1 }}, .detail = "MOCK The source requirement survives in the current collection." } },
        .{ .ambiguous = .{ .source_ids = &.{.{ .ordinal = 1 }}, .detail = "MOCK The source does not select a delivery channel.", .question = "MOCK Which delivery channel is required?" } },
    }) |response| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const requirement = "MOCK After approval notify the patient.";
        var fixture = try Fixture.initContent(a, requirement, null, true, requirement, 1);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const ledger = try @import("domain/required_authority.zig").build(a, inputs);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        var collection: ?support.Collection = null;
        // These mock judgments exercise admission, not semantic truth.
        const findings = try a.dupe(support.Finding, good.entries);
        for (ledger.requirements, findings) |required, *finding| if (required.seed.id.slot == .description) {
            finding.value = try model.canonical(response, try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, required.seed.id));
        };
        var position: usize = 0;
        while (position < ledger.requirements.len) {
            const id = ledger.requirements[position].seed.id;
            const packet = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, id));
            defer packets.release(packet);
            collection = try support.collectFocused(a, inputs, fixture.context, collection, packet, try assignmentWire(support, a, inputs, fixture.context, id, .{ .entries = findings }), .{ .request = .{ .value = @intCast(703 + position) }, .attempt = .{ .value = 1 } });
            try std.testing.expect(collection.? != .rejected);
            position += (try support.assignmentSubjects(a, inputs, id)).len;
        }
        try std.testing.expect(collection.? == .accepted);
        const collected = collection.?.accepted;
        try std.testing.expect(collected.candidate.pending_localization == null);
        try std.testing.expect(collected.inputs.evidence[0].review.?.missing_obligation == null);
        try std.testing.expect(collected.inputs.evidence[0].review.?.preservation == null);
        try std.testing.expectError(error.InvalidRequiredAuthority, support.packetForLoss(a, inputs, fixture.context, collected.candidate));
        const decision = try supportDecision(a, collected.inputs);
        try std.testing.expectEqual(.all_resolved, decision.result.continuation);
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/source_omission.zig").select(a, fixture.context.inputs, .{ .repair_phase = .generation_started, .review = collected.candidate, .inputs = decision.inputs, .observations = decision.observations, .result = decision.result }));
    }
}

test "invalid advisory finding metadata requires bounded native correction and cannot authorize clarification" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const model = @import("domain/specification_support_model.zig");
    const repair = @import("domain/specification_support_repair.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    const packets = @import("domain/model_input_packet.zig");
    const Failure = enum { defect_sources, gap_question, gap_sources };
    for ([_][]const u8{
        "MOCK After approval notify the patient; the delivery channel is undecided.",
        "MOCK After renewal retain the deadline; the notification channel is undecided.",
    }) |source| for (std.meta.tags(Failure)) |failure| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const mixed = failure != .defect_sources;
        var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
        var fixture = try Fixture.initContent(a, source, null, true, source, 1);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const ledger = try authority.build(a, inputs);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const gap: ?authority.AuthorityGap = if (mixed) .{
            .kind = .unsupported,
            .source_ids = &.{.{ .ordinal = 1 }},
            .detail = "MOCK The source leaves the delivery channel undecided.",
            .question = "MOCK Which delivery channel is required?",
        } else null;
        const proposed: model.Value = .{ .candidate_invalid = .{
            .source_ids = &.{.{ .ordinal = 1 }},
            .detail = "MOCK The candidate invents a mandatory monthly maintenance duty.",
            .authority_gap = gap,
        } };
        const index = for (ledger.requirements, 0..) |required, position| {
            if (required.seed.id.slot == .description) break position;
        } else return error.InvalidFixture;
        var initial = proposed;
        switch (failure) {
            .defect_sources => initial.candidate_invalid.source_ids = &.{.{ .ordinal = 999 }},
            .gap_question => initial.candidate_invalid.authority_gap.?.question = "Invalid scalar\x01",
            .gap_sources => initial.candidate_invalid.authority_gap.?.source_ids = &.{.{ .ordinal = 999 }},
        }
        // Exercise the canonical admission and selected native correction owners.
        // Initial model transport separately requires complete native assignments.
        const findings = try a.dupe(support.Finding, good.entries);
        const required = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, ledger.requirements[index].seed.id);
        findings[index].value = try model.canonical(initial, required);
        const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, findings.len);
        @memset(origins, null);
        var collection = try support.validate(a, inputs, fixture.context.inputs, .{ .review = .{ .entries = findings }, .origin = null, .origins = origins });
        const rejected = collection.rejected;
        const authorization = try repair.authorize(a, inputs, fixture.context, rejected);
        const correction = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, authorization);
        defer packets.release(correction);
        try std.testing.expectEqualStrings(if (failure == .gap_question) "invalid_detail" else "invalid_selection", correction.resultDefinition().?.bytes);
        const restricted_schema = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(correction.resultDefinition().?).?, correction.excludedVariants(), correction.integerChoices());
        defer restricted_schema.release();
        const selected_schema = restricted_schema.selected();
        const replacement = if (failure == .gap_question) blk: {
            var changed = gap.?;
            changed.kind = .ambiguous;
            const Detail = struct { detail: []const u8, authority_gap: ?authority.AuthorityGap };
            try std.testing.expectError(error.UnsafeSupportRepair, repair.parse(a, authorization, correction, try json.encode(Detail, a, .{ .detail = proposed.candidate_invalid.detail, .authority_gap = changed })));
            changed = gap.?;
            changed.source_ids = &.{.{ .ordinal = 999 }};
            try std.testing.expectError(error.UnsafeSupportRepair, repair.parse(a, authorization, correction, try json.encode(Detail, a, .{ .detail = proposed.candidate_invalid.detail, .authority_gap = changed })));
            try std.testing.expectError(error.UnsafeSupportRepair, repair.parse(a, authorization, correction, try json.encode(Detail, a, .{ .detail = proposed.candidate_invalid.detail, .authority_gap = null })));
            const bytes = try json.encode(Detail, a, .{ .detail = proposed.candidate_invalid.detail, .authority_gap = gap });
            try @import("test_fixtures/prepared_model_repair.zig").check(a, correction, schemas, bytes, null);
            try @import("model_payload_schema_test.zig").checkDocument(selected_schema.modelBytes(), .{ .bytes = bytes });
            break :blk try repair.parse(a, authorization, correction, bytes);
        } else blk: {
            try std.testing.expectError(error.UnsafeSupportRepair, repair.parse(a, authorization, correction, try json.encode(model.InvalidSelection, a, .{ .source_ids = proposed.candidate_invalid.source_ids, .authority_gap_source_ids = if (mixed) null else &.{} })));
            const bytes = try json.encode(model.InvalidSelection, a, .{ .source_ids = proposed.candidate_invalid.source_ids, .authority_gap_source_ids = if (gap) |retained| retained.source_ids else null });
            try @import("model_payload_schema_test.zig").checkDocument(selected_schema.modelBytes(), .{ .bytes = bytes });
            break :blk try repair.parse(a, authorization, correction, bytes);
        };
        collection = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.candidate.?, authorization, replacement, .{ .request = .{ .value = @intCast(950 + index) }, .attempt = .{ .value = 1 } });
        const admitted = collection.accepted;
        try std.testing.expect(admitted.candidate.pending_localization == null);
        try std.testing.expectError(error.InvalidRequiredAuthority, support.packetForLoss(a, inputs, fixture.context, admitted.candidate));
        const decoded = try @import("domain/strict_json.zig").decode(authority.Inputs, a, try std.json.Stringify.valueAlloc(a, admitted.inputs, .{}), .{ .maximum_depth = 128 });
        try support.validateStored(a, decoded, fixture.context.inputs);
        const decision = try supportDecision(a, decoded);
        try std.testing.expectEqual(.all_resolved, decision.result.continuation);
        const entry = for (decision.result.entries) |item| {
            if (item.requirement.slot == .description) break item;
        } else return error.InvalidFixture;
        try std.testing.expect(entry.outcome == .assessment_complete);
        try std.testing.expect(entry.candidate_defect == null);
        const reviewed_evidence = for (decoded.evidence) |item| {
            if (item.finding == .candidate_invalid) break item;
        } else return error.InvalidFixture;
        try std.testing.expectEqualDeep(gap, reviewed_evidence.review.?.authority_gap);
        try std.testing.expect(reviewed_evidence.review.?.missing_obligation == null and reviewed_evidence.review.?.preservation == null);
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, decision.inputs, decision.observations, decision.result));
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/source_omission.zig").select(a, fixture.context.inputs, .{ .repair_phase = .generation_started, .review = admitted.candidate, .inputs = decision.inputs, .observations = decision.observations, .result = decision.result }));
    };
}

test "omission obligation correction is closed atomic and retained through admission" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obligation = "MOCK After cancellation the service must notify the patient.";
    var fixture = try Fixture.initContent(a, obligation, null, true, obligation, 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_preservation, obligation);
    for ([_]?[]const u8{ null, "", " \t\n", "\x00" }) |invalid| {
        var candidate = state.pending;
        const entries = try a.dupe(support.Finding, candidate.review.entries);
        entries[0].value.missing_obligation = invalid;
        candidate.review.entries = entries;
        const rejected = (try support.validate(a, state.inputs, fixture.context.inputs, candidate)).rejected;
        try std.testing.expectEqual(.invalid_obligation, rejected.rejection.selected().?.issue);
        const authorization = try repair.authorize(a, state.inputs, fixture.context, rejected);
        const packet = try repair.packet(a, state.inputs, fixture.context, candidate, authorization);
        defer packets.release(packet);
        try std.testing.expectEqualStrings("omission_detail", packet.resultDefinition().?.bytes);
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, "{\"detail\":\"MOCK Omitted notification.\"}"));
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, "{\"detail\":\"MOCK Omitted notification.\",\"missing_obligation\":\"MOCK Notify the patient.\",\"kind\":\"supported\"}"));
        const replacement = try repair.parse(a, authorization, packet, "{\"detail\":\"MOCK Omitted notification.\",\"missing_obligation\":\"MOCK After cancellation the service must notify the patient.\"}");
        const corrected = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), state.inputs, fixture.context, candidate, authorization, replacement, null)).accepted;
        try std.testing.expectEqual(.candidate_omission, corrected.candidate.review.entries[0].value.kind);
        try std.testing.expectEqualDeep(entries[0].value.source_ids, corrected.candidate.review.entries[0].value.source_ids);
        try std.testing.expectEqualDeep(entries[0].value.provenance, corrected.candidate.review.entries[0].value.provenance);
        try std.testing.expectEqualStrings(obligation, corrected.inputs.evidence[0].review.?.missing_obligation.?);
        var stale = candidate;
        stale.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), state.inputs, fixture.context, stale, authorization, replacement, null));
    }
    const entries = try a.dupe(support.Finding, state.pending.review.entries);
    entries[0].value.kind = .supported;
    entries[0].value.detail = "";
    var candidate = state.pending;
    candidate.pending_localization = null;
    candidate.review.entries = entries;
    const rejected = (try support.validate(a, state.inputs, fixture.context.inputs, candidate)).rejected;
    try std.testing.expectEqual(.invalid_obligation, rejected.rejection.selected().?.issue);
}

const RetentionCall = struct {
    base: @import("provider_authorization_test_fixture.zig").Fixture,
    selection: @import("domain/model_request_handoff.zig").Selection,
    request: *@import("domain/model_request_handoff.zig").Request,
    response: @import("domain/llm_provider_operation.zig").ProviderInvocationObservation,
    validated: @import("domain/provider_invocation_validation.zig").Owned,
    decoded: @import("domain/model_envelope.zig").Owned,
    proof: *const @import("domain/model_payload_schema.zig").Evidence,

    fn init(self: *RetentionCall, a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, response_bytes: []const u8) !void {
        const handoff = @import("domain/model_request_handoff.zig");
        try self.base.init(std.testing.allocator);
        errdefer self.base.deinit();
        var schemas: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const compiled = try schemas.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .limited(1_048_576)));
        self.selection = .{ .binding = self.base.provider_binding, .prompt = .{ .id = .{ .bytes = "source-review-prompt" }, .content = .{ .prompt = "Review only the assigned source purpose." } }, .protocol_prompt = null, .result = .{ .id = .{ .bytes = "support-schema" }, .content = .{ .result_schema = compiled } }, .input = .{ .packet = packet }, .result_selection = .input };
        const id = try self.base.requests.assign(self.base.requests.ledger().?.revision(), packet.unit(), self.base.provider_binding.operation_id, packet.purpose());
        const assigned = try handoff.assign(std.testing.allocator, self.base.requests.current_owner.?, id, self.selection);
        defer handoff.destroy(assigned);
        const binding = try self.base.requests.validate(self.base.requests.ledger().?.revision(), id, packet.unit(), self.base.provider_binding.operation_id, packet.purpose());
        const checked = try handoff.validated(assigned, binding);
        defer handoff.destroy(checked);
        var input_id: [32]u8 = undefined;
        var parts: handoff.ContentBuffer = undefined;
        var owned = try @import("domain/model_request_preparation.zig").build(std.testing.allocator, try checked.buildSource(&input_id), checked.content(&parts));
        self.request = handoff.prepared(checked, owned, null) catch |err| {
            owned.deinit();
            return err;
        };
        errdefer handoff.destroy(self.request);
        self.base.model_request_id = id;
        self.base.request = self.request.prepared().?.*;
        _ = try self.base.attempts.reserve(self.base.attempts.current().revision(), self.base.requests.ledger().?, self.base.ledger(), self.base.requests.ledger().?.revision(), id, .initial);
        const invoked = try self.base.startInference();
        var fake: @import("adapters/provider/fake_llm_provider.zig").FakeLLMProvider = .{ .allocator = std.testing.allocator, .authorization_leases = self.base.leasePort(), .invocation_plan = .{ .complete = .{ .content = response_bytes, .input_tokens = 10, .output_tokens = 10 } } };
        self.response = try (@import("actions/model/invoke_model.zig").Action{ .provider = fake.interface() }).execute(&self.base.provider_binding, self.request.prepared().?, invoked.reference, invoked.invoked);
        errdefer self.response.deinit();
        self.validated = try @import("domain/provider_invocation_validation.zig").validate(std.testing.allocator, .{ .request = self.request.prepared().?, .provider_binding = &self.base.provider_binding, .operations = self.base.ledger(), .operation_id = invoked.invoked.id }, &self.response);
        errdefer self.validated.deinit();
        self.decoded = try @import("domain/model_envelope.zig").decode(std.testing.allocator, self.validated.evidence.result().complete, null);
        errdefer self.decoded.deinit();
        self.proof = switch (@import("domain/model_payload_schema.zig").validate(self.decoded.candidate)) {
            .valid => |proof| proof,
            .invalid => return error.InvalidRetentionTestResponse,
        };
        try self.base.change(.inference, .{ .terminate = .completed });
        try self.base.requests.advance(self.base.requests.ledger().?.revision(), id, .invoked, .{ .terminal = .accepted });
    }
    fn deinit(self: *RetentionCall) void {
        self.decoded.deinit();
        self.validated.deinit();
        self.response.deinit();
        @import("domain/model_request_handoff.zig").destroy(self.request);
        self.base.deinit();
    }
};

test "execution-local retention reuses unchanged source assignments through native admission and keeps recurrence identity" {
    const support = @import("domain/specification_support.zig").Source;
    const retention = @import("domain/specification_review_retention.zig");
    const packets = @import("domain/model_input_packet.zig");
    for ([_][]const u8{ "MOCK Display the greeting and current UTC time.", "MOCK Renew eligible loans and display the new deadline." }) |source_text| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source_text);
        defer fixture.deinit();
        const session = try completedFixtureValue(&fixture, false, try fixture.proposal("MOCK A receipt is available."));
        const assembled = try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, session);
        const inputs = try @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references, assembled.content, session.units[0].?.response.content.brief);
        const first = try support.nextSubject(a, inputs, null);
        const packet = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, first));
        defer packets.release(packet);
        const complete = try reviewFor(a, inputs, fixture.context.inputs);
        const wire = try assignmentWire(support, a, inputs, fixture.context, first, complete);
        var call: RetentionCall = undefined;
        try call.init(a, packet, wire);
        defer call.deinit();
        const ledger = call.base.requests.ledger().?;
        const origin = @import("domain/model_candidate_origin.zig").Origin.fromAccepted(ledger, call.proof).?;
        const original = try support.collectFocused(a, inputs, fixture.context, null, packet, wire, origin);
        const history = try retention.record(a, .{}, inputs, fixture.context, original, call.request, call.proof, ledger);
        try std.testing.expectEqual(@as(usize, 1), history.receipts.len);
        var forged = original.pending;
        const foreign_findings = try a.dupe(support.Finding, forged.review.entries);
        foreign_findings[0].value.detail = "MOCK A different native finding cannot borrow this call's origin.";
        forged.review.entries = foreign_findings;
        try std.testing.expectError(error.InvalidRequiredAuthority, retention.record(a, .{}, inputs, fixture.context, .{ .pending = forged }, call.request, call.proof, ledger));
        var changed = inputs;
        changed.revision += 1;
        changed.specification.?.primary_user_story = try fixture.value("MOCK The visitor receives the result.");
        const pending = (try retention.restart(a, history, changed, ledger)).?;
        try std.testing.expect(pending == .pending and pending.pending.review.entries.len == 0);
        const current_packet = try support.packetFor(a, changed, fixture.context, support.assignmentScope(changed, first));
        defer packets.release(current_packet);
        var selected = call.selection;
        selected.input = .{ .packet = current_packet };
        const before = ledger.recordCount();
        const reused = (try retention.reuse(a, history, changed, fixture.context, pending, selected, ledger)).?;
        try std.testing.expectEqual(before, ledger.recordCount());
        try std.testing.expect(reused == .pending);
        try std.testing.expectEqualDeep(original.pending.review.entries, reused.pending.review.entries);
        try std.testing.expectEqualDeep(origin, reused.pending.origin.?);
        try std.testing.expectEqualDeep(origin, reused.pending.origins[0].?);
        try std.testing.expectEqual(try original.pending.occurrences.at(0, 3), try reused.pending.occurrences.at(0, 3));
        const observed = try retention.observe(a, history, changed, fixture.context, reused, ledger);
        const again = (try retention.restart(a, observed, changed, ledger)).?;
        const repeated = (try retention.reuse(a, observed, changed, fixture.context, again, selected, ledger)).?;
        try std.testing.expectEqual(try reused.pending.occurrences.at(0, 3), try repeated.pending.occurrences.at(0, 3));
        var edited = changed;
        edited.specification.?.display_name = try fixture.value("MOCK Different feature identity.");
        const edited_packet = try support.packetFor(a, edited, fixture.context, support.assignmentScope(edited, first));
        defer packets.release(edited_packet);
        selected.input = .{ .packet = edited_packet };
        try std.testing.expect(try retention.reuse(a, history, edited, fixture.context, pending, selected, ledger) == null);
        const fresh_owner = try @import("domain/model_request_identity.zig").createInitial(a, @import("domain/model_request_identity.zig").RequestPurposeRegistry.all());
        defer @import("domain/model_request_identity.zig").deinitOwner(fresh_owner);
        try std.testing.expect(try retention.restart(a, history, changed, @import("domain/model_request_identity.zig").ledger(fresh_owner)) == null);
        var stale = inputs;
        stale.revision = 0;
        try std.testing.expectError(error.InvalidRequiredAuthority, retention.restart(a, history, stale, ledger));
        var repaired = original.pending;
        const corrected = try a.dupe(support.Finding, repaired.review.entries);
        corrected[0].value.detail = "MOCK The original source supports this exact requirement.";
        repaired.review.entries = corrected;
        const retired = try retention.observe(a, history, inputs, fixture.context, .{ .pending = repaired }, ledger);
        try std.testing.expectEqual(@as(usize, 0), retired.receipts.len);
        var regenerated = changed;
        var current_records = regenerated.references.?;
        current_records.signals = try a.dupe(@import("domain/reference_reconciliation.zig").Signal, current_records.signals);
        regenerated.references = current_records;
        try std.testing.expect(try retention.restart(a, history, regenerated, ledger) == null);
        // A fresh native observation cannot overwrite the dependency witness of
        // old receipts when source metadata changes outside packet text.
        var metadata = fixture.context;
        const sources = try a.dupe(@import("domain/reference_evidence.zig").Source, metadata.inputs.corpus.sources);
        sources[0].path = .{ .bytes = "changed-source.txt" };
        metadata.inputs.corpus.sources = sources;
        const renewed = try retention.observe(a, history, inputs, metadata, original, ledger);
        try std.testing.expectEqual(@as(usize, 0), renewed.receipts.len);
        try std.testing.expect(renewed.scope.?.origin_request == null);
        const renewed_packet = try support.packetFor(a, inputs, metadata, support.assignmentScope(inputs, first));
        defer packets.release(renewed_packet);
        selected.input = .{ .packet = renewed_packet };
        try std.testing.expect(try retention.reuse(a, renewed, inputs, metadata, .{ .pending = pending.pending }, selected, ledger) == null);
    }
}

test "rejected first source assignment authenticates scope without a reusable receipt and native repair keeps recurrence" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Contract(.source);
    const retention = @import("domain/specification_review_retention.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "MOCK Deliver a parcel and display its confirmed delivery date.");
    defer fixture.deinit();
    const session = try completedFixtureValue(&fixture, false, try fixture.proposal("MOCK A receipt is available."));
    const assembled = try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, session);
    const inputs = try @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references, assembled.content, session.units[0].?.response.content.brief);
    const first = try support.nextSubject(a, inputs, null);
    const packet = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, first));
    defer packets.release(packet);
    const complete = try reviewFor(a, inputs, fixture.context.inputs);
    const good = complete.entries[0];
    var invalid = good.value;
    invalid.source_ids = &.{ fixture.context.inputs.corpus.sources[0].id, fixture.context.inputs.corpus.sources[0].id };
    const broken = try a.dupe(support.Finding, complete.entries);
    broken[0].value = invalid;
    const wire = try assignmentWire(support, a, inputs, fixture.context, first, .{ .entries = broken });
    var call: RetentionCall = undefined;
    try call.init(a, packet, wire);
    defer call.deinit();
    const ledger = call.base.requests.ledger().?;
    const origin = @import("domain/model_candidate_origin.zig").Origin.fromAccepted(ledger, call.proof).?;
    const rejected = try support.collectFocused(a, inputs, fixture.context, null, packet, wire, origin);
    try std.testing.expect(rejected == .rejected);
    try std.testing.expectEqual(.invalid_evidence, rejected.rejected.rejection.selected().?.issue);
    const history = try retention.record(a, .{}, inputs, fixture.context, rejected, call.request, call.proof, ledger);
    try std.testing.expectEqual(@as(usize, 0), history.receipts.len);
    try std.testing.expect(history.scope.?.origin_request.? == call.request.id());
    const occurrence = try rejected.rejected.candidate.?.occurrences.at(0, 3);
    try std.testing.expectEqual(occurrence, history.scope.?.occurrences[0].occurrence);
    var forged = rejected.rejected;
    forged.rejection = .{ .diagnostics = &.{} };
    try std.testing.expectError(error.InvalidRequiredAuthority, retention.record(a, .{}, inputs, fixture.context, .{ .rejected = forged }, call.request, call.proof, ledger));
    const authorization = try repair.authorize(a, inputs, fixture.context, rejected.rejected);
    const corrected = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, rejected.rejected.candidate.?, authorization, .{ .selection = .{ .provenance = good.value.provenance, .source_ids = good.value.source_ids } }, origin);
    try std.testing.expect(corrected == .pending);
    const observed = try retention.observe(a, history, inputs, fixture.context, corrected, ledger);
    try std.testing.expectEqual(@as(usize, 0), observed.receipts.len);
    try std.testing.expectEqual(corrected.pending.revision, observed.scope.?.candidate.revision);
    try std.testing.expectEqualDeep(corrected.pending.last_repair, observed.scope.?.candidate.last_repair);
    const restarted = (try retention.restart(a, observed, inputs, ledger)).?;
    try std.testing.expectEqualDeep(origin, restarted.pending.origin.?);
    try std.testing.expectEqualDeep(corrected.pending.last_repair, restarted.pending.last_repair);
    try std.testing.expect(try retention.reuse(a, observed, inputs, fixture.context, restarted, call.selection, ledger) == null);
    const recollected = try support.appendAdmitted(a, inputs, fixture.context, restarted, packet, complete.entries[0..3], origin);
    try std.testing.expectEqual(occurrence, try recollected.pending.occurrences.at(0, 3));
    const recurring = try a.dupe(support.Finding, recollected.pending.review.entries);
    recurring[0].value.source_ids = invalid.source_ids;
    var current = recollected.pending;
    current.review.entries = recurring;
    const recurrence = (try support.validateWorking(a, inputs, fixture.context.inputs, current)).rejected;
    const again = try repair.authorize(a, inputs, fixture.context, recurrence);
    try std.testing.expectEqualSlices(u8, &authorization.retry.?.key.scope, &again.retry.?.key.scope);
    try std.testing.expectEqualSlices(u8, &authorization.retry.?.key.target, &again.retry.?.key.target);
}

test "native retained append rejects partial and foreign record membership and still validates every finding" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "MOCK Eligible borrowers can renew a loan and receive the new deadline.");
    defer fixture.deinit();
    const session = try completedFixtureValue(&fixture, false, try fixture.proposal("MOCK A receipt is available."));
    const assembled = try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, session);
    const inputs = try @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references, assembled.content, session.units[0].?.response.content.brief);
    const good = try reviewFor(a, inputs, fixture.context.inputs);
    const native = try authority.build(a, inputs);
    var prior: ?support.Collection = null;
    var position: usize = 0;
    while (position < native.requirements.len) {
        const id = native.requirements[position].seed.id;
        if (id.unit == .record and id.unit.record.kind == .acceptance_criterion) break;
        const assigned = try support.assignmentSubjects(a, inputs, id);
        const packet = try support.packetFor(a, inputs, fixture.context, support.assignmentScope(inputs, id));
        defer @import("domain/model_input_packet.zig").release(packet);
        prior = try support.appendAdmitted(a, inputs, fixture.context, prior, packet, good.entries[position .. position + assigned.len], null);
        position += assigned.len;
    }
    const start = prior.?.pending.review.entries.len;
    const target = try support.nextSubject(a, inputs, prior);
    const packet = try support.packetFor(a, inputs, fixture.context, .{ .assignment = target });
    defer @import("domain/model_input_packet.zig").release(packet);
    const members = good.entries[start .. start + 3];
    try std.testing.expectError(error.InvalidRequiredAuthority, support.appendAdmitted(a, inputs, fixture.context, prior, packet, members[0..2], null));
    var foreign = try a.dupe(support.Finding, members);
    foreign[1].requirement_ordinal = foreign[0].requirement_ordinal;
    try std.testing.expectError(error.InvalidRequiredAuthority, support.appendAdmitted(a, inputs, fixture.context, prior, packet, foreign, null));
    foreign = try a.dupe(support.Finding, members);
    foreign[2].value.source_ids = &.{.{ .ordinal = 999 }};
    const rejected = try support.appendAdmitted(a, inputs, fixture.context, prior, packet, foreign, null);
    try std.testing.expect(rejected == .rejected);
    try std.testing.expectEqual(.invalid_evidence, rejected.rejected.rejection.selected().?.issue);
    foreign = try a.dupe(support.Finding, members);
    foreign[2].value.kind = .not_applicable;
    const forbidden = try support.appendAdmitted(a, inputs, fixture.context, prior, packet, foreign, null);
    try std.testing.expect(forbidden == .rejected);
    try std.testing.expectEqual(.invalid_decision, forbidden.rejected.rejection.selected().?.issue);
    const appended = try support.appendAdmitted(a, inputs, fixture.context, prior, packet, members, null);
    try std.testing.expectEqualDeep(members, appended.pending.review.entries[start..]);
    var changed = inputs;
    const records = try a.dupe(spec.IdentifiedRecord, changed.specification.?.records);
    for (records) |*record| if (std.meta.eql(record.id, target.unit.record)) {
        record.proposal.content.acceptance_criterion.when = (try fixture.value("MOCK The renewal is refused.")).value;
    };
    changed.specification.?.records = records;
    try std.testing.expectError(error.InvalidRequiredAuthority, support.appendAdmitted(a, changed, fixture.context, prior, packet, members, null));
}

test "value repair retains raw native occurrence evidence from an unchanged sibling" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A user sees status `ACTIVE` and exports `report.csv`.");
    defer fixture.deinit();
    const plain = try fixture.proposal("The user starts the requested operation.");
    const all = try provenance.items(fixture.context);
    const active = for (all.entries) |entry| {
        if (entry.claim.content == .preserved_token and std.mem.eql(u8, entry.claim.content.preserved_token.value.raw_value.bytes, "ACTIVE")) break entry.claim.id;
    } else return error.MissingTestToken;
    var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
    current.completed = sessions.records_index;
    current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = plain } } })).valid;
    const raw_then: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "The user sees ACTIVE." } }} };
    const record: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{
        .given = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = .{ .ordinal = 999 } } }} },
        .when = plain.value,
        .then = raw_then,
    } }, .source_group_ids = plain.source_group_ids, .provenance = plain.provenance };
    const candidate: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{record} } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectEqual(.unknown_passive, rejected.issue.text_issue.?.reason);
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
    const bound = auth.rule.value_bound.?;
    try std.testing.expectEqualDeep(plain.provenance.claim_ids, bound.explicit);
    try std.testing.expectEqual(plain.provenance.claim_ids.len + 1, bound.effective.len);
    try std.testing.expect(@import("domain/reference_reconciliation.zig").contains(references.r.ClaimId, bound.effective, active));
    const packet = try repair.packet(a, current, fixture.context, auth);
    defer @import("domain/model_input_packet.zig").release(packet);
    try std.testing.expectEqual(@as(usize, 1), packet.exactScope().?.occurrences.len);
    try std.testing.expectEqualDeep(active, packet.exactScope().?.occurrences[0].claim_id);
    const wider_ids = try a.alloc(references.r.ClaimId, all.entries.len);
    for (all.entries, wider_ids) |entry, *id| id.* = entry.claim.id;
    try std.testing.expectError(error.InvalidModelInputPacket, sessions.withSelectionChoices(a, packet, fixture.context, .{ .claim_ids = wider_ids, .clarification_response_ids = &.{} }));
    const canonical = try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs);
    const merged = try repair.merge(a, canonical, current, fixture.context, candidate, auth, .{ .value = plain.value }, null);
    try std.testing.expectEqualDeep(raw_then, merged.response.content.records[0].content.acceptance_criterion.then);
    _ = (try validate_unit.execute(a, current, fixture.context, merged)).valid;
    try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
    const wider: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "The user exports report.csv." } }} };
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, canonical, current, fixture.context, candidate, auth, .{ .value = wider }, null));
}

test "feature entity insertion pins native occurrence scope independently of authored support" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A user sees status `ACTIVE` and exports `report.csv`.");
    defer fixture.deinit();
    const plain = try fixture.proposal("The user observes the operation status.");
    var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
    current.completed = sessions.entities_index;
    const candidate: repair.Candidate = .{ .response = .{ .content = .{ .entities = .{ .disposition = .required, .basis = plain } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectEqual(.entity_membership, rejected.issue.rule);
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
    try std.testing.expectEqualDeep(plain.provenance, auth.rule.group.?.membership.fixed_provenance);
    const record: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = .{ .segments = &.{.{ .literal = .{ .value = "ACTIVE" } }} }, .business_meaning = plain.value, .relationships = &.{} } }, .source_group_ids = plain.source_group_ids, .provenance = plain.provenance };
    const canonical = try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs);
    const inserted = try repair.merge(a, canonical, current, fixture.context, candidate, auth, .{ .record = record }, null);
    _ = (try validate_unit.execute(a, current, fixture.context, inserted)).valid;
    const bound = inserted.group_repair.?.policy.membership.evidence_bound.?;
    try std.testing.expectEqual(plain.provenance.claim_ids.len + 1, bound.effective.len);
    var broken = inserted;
    const records = try a.dupe(spec.Model.RecordProposal, inserted.response.content.entities.records);
    records[0].content.entity.business_meaning = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    broken.response.content.entities.records = records;
    const next_rejection = (try validate_unit.execute(a, current, fixture.context, broken)).invalid;
    const correction = try repair.authorize(a, current, fixture.context, broken, next_rejection);
    const packet = try repair.packet(a, current, fixture.context, correction);
    defer @import("domain/model_input_packet.zig").release(packet);
    try std.testing.expectEqual(@as(usize, 1), packet.exactScope().?.occurrences.len);
    try std.testing.expectEqualStrings("ACTIVE", packet.exactScope().?.occurrences[0].bytes);
    const fixed = try repair.merge(a, canonical, current, fixture.context, broken, correction, .{ .record = record }, null);
    _ = (try validate_unit.execute(a, current, fixture.context, fixed)).valid;
    try std.testing.expectEqualDeep(bound, fixed.group_repair.?.policy.membership.evidence_bound.?);
    var wider = record;
    wider.content.entity.name = .{ .segments = &.{.{ .literal = .{ .value = "ACTIVE and report.csv" } }} };
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, canonical, current, fixture.context, broken, correction, .{ .record = wider }, null));
    var forged = fixed;
    const forged_records = try a.dupe(spec.Model.RecordProposal, fixed.response.content.entities.records);
    forged_records[0] = wider;
    forged.response.content.entities.records = forged_records;
    try std.testing.expectError(error.InvalidSpecificationUnit, g.validateCandidate(a, text.validator, fixture.context, .entities, forged));
    var complete = try completedFixture(&fixture, false);
    complete.units[sessions.entities_index] = (try g.validate(a, text.validator, fixture.context, .entities, inserted.response)).valid;
    // Satisfy the sibling token's business mapping so coverage reaches the
    // entity name's deliberately non-behavioral ACTIVE witness.
    const completed_records = try a.dupe(spec.RecordProposal, complete.units[sessions.records_index].?.response.content.records);
    for (completed_records) |*completed_record| if (completed_record.content == .functional_requirement) {
        completed_record.* = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{ .content = .{ .functional_requirement = .{ .text = .{ .segments = &.{.{ .literal = .{ .value = "The user exports report.csv." } }} } } }, .source_group_ids = plain.source_group_ids, .provenance = plain.provenance });
    };
    complete.units[sessions.records_index].?.response.content.records = completed_records;
    const assembled = try sessions.assemble(a, text.validator, fixture.context, complete);
    const coverage = try @import("domain/specification_coverage.zig").check(a, fixture.context.references, complete.units[0].?.response.content.brief, assembled.content);
    try std.testing.expect(coverage == .invalid);
    try std.testing.expect(coverage.invalid.issue == .missing_exact_copy);
    try std.testing.expectEqualStrings("ACTIVE", coverage.invalid.issue.missing_exact_copy.value.raw_value.bytes);
}

test "native generation rejects composition without granting unit repair and retains identity exceptions" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const Segment = @import("domain/typed_text.zig").BusinessSegment;
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Display `MOCK Renewal accepted!` after renewal." }) |source| for ([_]bool{ false, true }) |descriptive| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const token = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token) break entry.claim.id;
        } else return error.MissingTestToken;
        var good = try fixture.proposal("The user observes the supported result.");
        // Explicitly retain the supported exact-value lineage even when the
        // selected descriptive field must remove the prohibited insertion.
        good.provenance.claim_ids = try std.mem.concat(a, references.r.ClaimId, &.{ good.provenance.claim_ids, &.{token} });
        good.source_group_ids = try std.mem.concat(a, references.r.SignalId, &.{ good.source_group_ids, try mockClaimGroup(a, fixture.context, token) });
        var bad = good;
        const exact: Segment = .{ .exact_copy = .{ .claim_id = token } };
        bad.value = .{ .segments = &.{ exact, .{ .literal = .{ .value = " " } }, exact } };
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = if (descriptive) bad else good, .description = if (descriptive) good else bad, .primary_goal = good } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(.typed_text, rejection.issue.rule);
        try std.testing.expectEqual(@as(@FieldType(@import("domain/typed_text.zig").Issue, "reason"), if (descriptive) .prohibited_exact else .reference_only), rejection.issue.text_issue.?.reason);
        try std.testing.expectEqual(@as(@import("domain/text_field_policy.zig").Field, if (descriptive) .spec_title else .spec_description), rejection.issue.text_issue.?.field.?);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejection));
        const in_sentence: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = "The user sees " } }, exact } };
        var fixed = candidate;
        if (descriptive) fixed.response.content.brief.title.value = good.value else fixed.response.content.brief.description.value = in_sentence;
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, fixed)) == .valid);
        var identity_candidate = bad;
        identity_candidate.value = .{ .segments = &.{exact} };
        const identity = try provenance.checkAttributed(.model, a, text.validator, fixture.context, identity_candidate, .entity_name);
        try std.testing.expectEqualDeep(identity_candidate.value, identity.value);
        try std.testing.expectEqualDeep(bad.value, (try provenance.checkAttributed(.model, a, text.validator, fixture.context, bad, .entity_name)).value);
        try std.testing.expectError(error.InvalidTypedText, provenance.checkAttributed(.model, a, text.validator, fixture.context, bad, .spec_story));
        const captured = try @import("domain/reference_support.zig").exact(all, token);
        var raw_identity = identity_candidate;
        raw_identity.value = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "{s} {s}", .{ captured.value.raw_value.bytes, captured.value.raw_value.bytes }) } }} };
        try std.testing.expectEqualDeep(bad.value, (try provenance.checkAttributed(.model, a, text.validator, fixture.context, raw_identity, .entity_name)).value);
        try std.testing.expectError(error.InvalidTypedText, provenance.checkAttributed(.model, a, text.validator, fixture.context, raw_identity, .spec_story));
    };
}

test "persisted reference and specification readers enforce composition and original-source wire evidence" {
    const snapshots = @import("domain/reference_snapshot.zig");
    const passive = @import("domain/passive_literals.zig");
    const sessions = @import("domain/specification_session.zig");
    const encoded = "Which value follows {\"kind\":\"exact_copy\",\"claim_id\":1}?";
    for ([_][]const u8{ "MOCK The receipt includes UTC time. Export stories.md.", "MOCK The renewal receipt includes its due date. Export stories.md." }) |source| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
        const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
        const snapshot = try snapshots.build(.{ .bytes = "references" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
        try snapshots.validate(a, snapshot);
        for ([_]bool{ false, true }) |wire| {
            const rejected: spec.BusinessValue = .{ .segments = if (wire)
                &.{.{ .literal = .{ .value = encoded } }}
            else
                &.{.{ .passive = .{ .passive_literal_id = fixture.context.registry.records[0].id } }} };
            var broken = snapshot;
            const claims = try a.dupe(@import("domain/reference_extraction.zig").Claim, snapshot.extraction.claims);
            claims[0].content.model.business.value.segments = rejected.segments;
            broken.extraction.claims = claims;
            try std.testing.expectError(error.InvalidReferenceSnapshot, snapshots.validate(a, broken));
            broken = snapshot;
            const signals = try a.dupe(references.r.Signal, snapshot.signals);
            signals[0].value.content.model.business.value.segments = rejected.segments;
            broken.signals = signals;
            try std.testing.expectError(error.InvalidReferenceSnapshot, snapshots.validate(a, broken));
            const current = try completedFixture(&fixture, false);
            const assembled = try sessions.assemble(a, text.validator, fixture.context, current);
            const brief = current.units[0].?.response.content.brief;
            const captured: passive.Captured = .{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences };
            const records = @import("domain/reference_support.zig").records(fixture.context.references);
            try provenance.validateStored(a, fixture.context.inputs, captured, records, brief, assembled.content);
            var invalid = assembled.content;
            invalid.primary_user_story.value = rejected;
            try std.testing.expectError(error.InvalidTypedText, provenance.validateStored(a, fixture.context.inputs, captured, records, brief, invalid));
        }
    }
}

test "native embedded insertion syntax never grants specification unit repair authority" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const atomic = @import("domain/atomic_repair.zig");
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Display `MOCK Renewal accepted!` after renewal." }) |source| for ([_]bool{ false, true }) |title| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const good = try fixture.proposal("The user observes the supported result.");
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Display {\"kind\":\"exact_copy\"}." } }} };
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = if (title) bad else good, .description = if (title) good else bad, .primary_goal = good } } } };
        const before = try atomic.snapshot(repair.Candidate, a, candidate);
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(.embedded_insertion_syntax, rejection.issue.text_issue.?.reason);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejection));
        try std.testing.expectEqualDeep(before, try atomic.snapshot(repair.Candidate, a, candidate));
    };
}

test "prepared native assignments retain exact evidence by native field role without model exact alternatives" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const packets = @import("domain/model_input_packet.zig");
    const binding = @import("domain/specification_source_binding.zig");
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Display `MOCK Renewal accepted!` after renewal." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const token_group = for (fixture.context.references.records.signals) |group| {
            if (try binding.tokenOnly(@import("domain/reference_support.zig").records(fixture.context.references), group.id)) break group.id;
        } else return error.MissingTokenOnlyGroup;
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const initial = try sessions.packet(a, current, fixture.context);
        defer packets.release(initial);
        try checkPreparedNativeProjection(a, initial, true, true, token_group);
        const all = try provenance.items(fixture.context);
        const token = for (all.entries) |entry| {
            if (entry.claim.content == .preserved_token) break entry.claim.id;
        } else return error.MissingTestToken;
        var good = try fixture.proposal("The user observes the supported result.");
        good.provenance.claim_ids = try std.mem.concat(a, references.r.ClaimId, &.{ good.provenance.claim_ids, &.{token} });
        good.source_group_ids = try std.mem.concat(a, references.r.SignalId, &.{ good.source_group_ids, try mockClaimGroup(a, fixture.context, token) });
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        for ([_]enum { title, description, goal }{ .title, .description, .goal }) |selected| {
            const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = if (selected == .title) bad else good, .description = if (selected == .description) bad else good, .primary_goal = if (selected == .goal) bad else good } } } };
            const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
            const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection);
            const packet = try repair.packet(a, current, fixture.context, authorization);
            defer packets.release(packet);
            try checkPreparedNativeProjection(a, packet, selected == .description, false, token_group);
        }
    }
}

fn checkPreparedNativeProjection(a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, exact: bool, question: bool, token_group: references.r.SignalId) !void {
    const handoff = @import("domain/model_request_handoff.zig");
    const preparation = @import("domain/model_request_preparation.zig");
    const original_bytes = try a.dupe(u8, packet.body());
    var base: @import("provider_authorization_test_fixture.zig").Fixture = undefined;
    try base.init(std.testing.allocator);
    defer base.deinit();
    var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .limited(1_048_576)));
    const selected: handoff.Selection = .{ .binding = base.provider_binding, .prompt = .{ .id = .{ .bytes = "generation" }, .content = .{ .prompt = "Generate the assigned source-backed value." } }, .protocol_prompt = .{ .id = .{ .bytes = "protocol" }, .content = .{ .prompt = "Correct the protocol defect." } }, .result = .{ .id = .{ .bytes = "generation-result" }, .content = .{ .result_schema = schema } }, .input = .{ .packet = packet }, .result_selection = .input };
    const id = try base.requests.assign(base.requests.ledger().?.revision(), packet.unit(), base.provider_binding.operation_id, packet.purpose());
    const assigned = try handoff.assign(std.testing.allocator, base.requests.current_owner.?, id, selected);
    defer handoff.destroy(assigned);
    const request_binding = try base.requests.validate(base.requests.ledger().?.revision(), id, packet.unit(), base.provider_binding.operation_id, packet.purpose());
    const checked = try handoff.validated(assigned, request_binding);
    defer handoff.destroy(checked);
    var input_id: [32]u8 = undefined;
    var parts: handoff.ContentBuffer = undefined;
    const request_source = try checked.buildSource(&input_id);
    var owned = try preparation.build(std.testing.allocator, request_source, checked.content(&parts));
    const request = handoff.prepared(checked, owned, null) catch |err| {
        owned.deinit();
        return err;
    };
    defer handoff.destroy(request);
    const actual = request.prepared().?;
    const input = (try std.json.parseFromSlice(std.json.Value, a, request.input().?, .{})).value.object;
    const native = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
    const projected = if (packet.purpose() == .atomic_repair) input.get("input").?.object else input;
    const original = if (packet.purpose() == .atomic_repair) native.get("input").?.object else native;
    try std.testing.expect(original.get("preserved_tokens").?.array.items.len > 0);
    try std.testing.expectEqual(exact, projected.contains("preserved_tokens"));
    var token_groups: usize = 0;
    for (projected.get("source_groups").?.array.items) |group| if (group.object.get("signal_id").?.integer == token_group.ordinal) {
        token_groups += 1;
    };
    try std.testing.expectEqual(@as(usize, @intFromBool(exact)), token_groups);
    try std.testing.expectEqual(original.get("source_groups").?.array.items.len - @intFromBool(!exact), projected.get("source_groups").?.array.items.len);
    try std.testing.expect(std.mem.indexOf(u8, actual.response_schema.modelBytes(), "exact_copy") == null);
    const rules = input.get("field_rules").?.array.items;
    var question_rules: usize = 0;
    for (rules) |rule| {
        const path = rule.object.get("field").?.string;
        if (std.mem.indexOf(u8, path, "question") != null) question_rules += 1;
    }
    try std.testing.expectEqual(question, question_rules > 0);
    try std.testing.expect(!input.get("insertion_fields").?.object.contains("exact_copy"));
    try std.testing.expect(@import("domain/model_exact_values.zig").same(packet.exactScope(), actual.exact_scope));
    try std.testing.expectEqualDeep(packet.originalSources(), actual.original_sources);
    try std.testing.expectEqualDeep(packet.fieldPolicies(), actual.field_policies);
    base.model_request_id = id;
    base.request = actual.*;
    _ = try base.attempts.reserve(base.attempts.current().revision(), base.requests.ledger().?, base.ledger(), base.requests.ledger().?.revision(), id, .initial);
    const invoked = try base.startInference();
    var fake: @import("adapters/provider/fake_llm_provider.zig").FakeLLMProvider = .{ .allocator = std.testing.allocator, .authorization_leases = base.leasePort(), .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 2 } } };
    var response = try (@import("actions/model/invoke_model.zig").Action{ .provider = fake.interface() }).execute(&base.provider_binding, actual, invoked.reference, invoked.invoked);
    defer response.deinit();
    var validated = try @import("domain/provider_invocation_validation.zig").validate(std.testing.allocator, .{ .request = actual, .provider_binding = &base.provider_binding, .operations = base.ledger(), .operation_id = invoked.invoked.id }, &response);
    defer validated.deinit();
    var decoded = try @import("domain/model_envelope.zig").decode(std.testing.allocator, validated.evidence.result().complete, null);
    defer decoded.deinit();
    const diagnostic = @import("domain/model_payload_schema.zig").validate(decoded.candidate).invalid;
    var retry = try (@import("actions/model/build_model_protocol_retry.zig").Action{}).execute(std.testing.allocator, request_source, checked.content(&parts), validated.evidence, .{ .schema = diagnostic }, .unconfirmed, "Correct the protocol defect.");
    const correction = handoff.prepared(checked, retry, .{ .previous = request, .rejected = validated.evidence, .diagnostic = .{ .schema = diagnostic } }) catch |err| {
        retry.deinit();
        return err;
    };
    defer handoff.destroy(correction);
    try std.testing.expectEqualStrings(request.input().?, correction.input().?);
    try std.testing.expectEqualDeep(actual.content, correction.prepared().?.content[0..actual.content.len]);
    try std.testing.expect(correction.prepared().?.response_schema == actual.response_schema);
    try std.testing.expectEqualStrings(packet.body(), (request.packet() orelse return error.MissingNativePacket).body());
    try std.testing.expectEqualDeep(packet.presentationOmissions(), (request.packet() orelse return error.MissingNativePacket).presentationOmissions());
    // The native producer packet is immutable; protocol correction keeps the
    // already-projected bytes instead of applying original array indices again.
    try std.testing.expectEqualStrings(original_bytes, packet.body());
}

test "record projection retains shared sibling lineage while composition cannot authorize unit repair" {
    const projection = @import("domain/specification_projection.zig");
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    const passive_literals = @import("domain/passive_literals.zig");
    for ([_][]const u8{ "MOCK Record the startup outcome.", "MOCK Renew the eligible loan." }) |obligation| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        // The production Markdown reader creates a block every 64 lines;
        // headings alone intentionally do not create evidence boundaries.
        var fixture = try Fixture.init(a, try std.fmt.allocPrint(a, "{s}{s}Display `MOCK Done!` in stories.md.\n", .{ obligation, "\n" ** 64 }));
        defer fixture.deinit();
        const items = try provenance.items(fixture.context);
        const first = items.entries[0].claim;
        const exact = for (items.entries) |entry| {
            if (entry.claim.content == .preserved_token and !entry.claim.chunk_id.eql(first.chunk_id) and std.mem.eql(u8, entry.claim.content.preserved_token.value.raw_value.bytes, "MOCK Done!")) break entry.claim.id;
        } else return error.MissingSiblingExactClaim;
        const passive = for (fixture.context.registry.records) |entry| {
            if (std.mem.eql(u8, entry.value, "stories.md")) break entry;
        } else return error.MissingSiblingPassiveReference;
        const only_reference: spec.BusinessValue = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = passive.id } }} };
        const good = try fixture.proposal("The source-backed condition applies.");
        const record: spec.Model.RecordProposal = .{
            .source_group_ids = good.source_group_ids,
            .provenance = good.provenance,
            .content = .{ .acceptance_criterion = .{
                .given = only_reference,
                .when = good.value,
                .then = .{ .segments = &.{ .{ .literal = .{ .value = "Display " } }, .{ .exact_copy = .{ .claim_id = exact } } } },
            } },
        };
        // The selected field alone cannot resolve this reference. Its sibling's
        // legitimate exact insertion contributes the second native source scope.
        try std.testing.expectError(error.InvalidPassiveLiteral, projection.modelValue(a, fixture.context, .{ .value = only_reference, .source_group_ids = record.source_group_ids, .provenance = record.provenance }));
        try std.testing.expectEqualStrings(passive.value, (try projection.modelRecord(a, fixture.context, record)).acceptance_criterion.given.bytes);
        const first_scope: @import("domain/reference_evidence.zig").Scope = .{ .state_id = fixture.context.inputs.corpus.state_id, .chunk_id = first.chunk_id };
        try std.testing.expectError(error.InvalidPassiveLiteral, passive_literals.resolveIn(fixture.context.registry, fixture.context.inputs, &.{first_scope}, passive.id));
        var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        current.completed = sessions.records_index;
        current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = good } } })).valid;
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{record} } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(.reference_only, rejected.issue.text_issue.?.reason);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejected));
    }
}

test "native source question syntax bypass cannot grant support unit repair" {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const codec = @import("domain/model_candidate_json.zig");
    const wire_question = "Which channel applies? {\"kind\":\"passive\",\"passive_literal_id\":1}";
    for ([_][]const u8{ "MOCK Notify the patient; the delivery channel is undecided.", "MOCK Confirm the renewal; the delivery channel is undecided." }) |source| for ([_]bool{ false, true }) |nested| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, null, true, source, 1);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const entries = try a.dupe(review.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
        const source_ids: []const @import("domain/reference_identity.zig").SourceId = &.{fixture.context.inputs.corpus.sources[0].id};
        entries[0].value.kind = if (nested) .candidate_invalid else .unsupported;
        entries[0].value.source_ids = source_ids;
        entries[0].value.detail = "MOCK The candidate selects a delivery channel that the source leaves undecided.";
        entries[0].value.question = if (nested) null else wire_question;
        entries[0].value.authority_gap = if (nested) .{ .kind = .unsupported, .source_ids = source_ids, .detail = "MOCK The source leaves the delivery channel undecided.", .question = wire_question } else null;
        try bindReviewClaims(a, inputs, fixture.context, entries);
        const rejected = (try collectReview(review, a, inputs, fixture.context, try codec.encode(review.Review, a, .{ .entries = entries }), null)).rejected;
        try std.testing.expectEqual(.invalid_question, rejected.rejection.selected().?.issue);
        try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, rejected));
    };
}

fn checkPreparedExtractionOmission(a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, wire: []const u8) !void {
    const codec = @import("domain/model_candidate_json.zig");
    const bindings = try codec.fieldBindings(@import("domain/reference_extraction.zig").Proposal, a, .{ .reference_phase = .extraction });
    try std.testing.expect(@import("domain/model_text_field.zig").same(bindings, packet.fieldPolicies()));
    try std.testing.expectEqual(@as(usize, 7), bindings.len);
    var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/extraction.schema.json", a, .limited(1_048_576)));
    // The old no-feature outcome is an exact native CAS witness, never an
    // alternative answer for the selected claim-repair response contract.
    try @import("test_fixtures/prepared_model_repair.zig").check(a, packet, schema, wire, extraction.no_claim);
}

test "post-generation semantic judgments remain admitted advice without content repair or clarification authority" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    const sessions = @import("domain/specification_session.zig");
    var capture_arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer capture_arena.deinit();
    const capture_a = capture_arena.allocator();
    const captured_bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "test/calibration/source-review-advice/loan-borrower-relationship.capture.json", capture_a, .limited(1_048_576));
    const captured = try std.json.parseFromSliceLeaky(std.json.Value, capture_a, captured_bytes, .{});
    const captured_subject = captured.object.get("byte_facts").?.object.get("subject_text").?.string;
    try std.testing.expectEqualStrings(captured_subject, captured.object.get("observed_finding").?.object.get("missing_obligation").?.string);
    const examples = [_][2][]const u8{
        .{ "Display the current UTC time after startup.", "Display the current UTC time after startup." },
        .{ captured.object.get("original_source").?.object.get("text").?.string, captured_subject },
        .{ "Display the greeting without storing business data.", "Display the greeting without storing business data." },
    };
    for (examples, 0..) |example, example_index| {
        const source = example[0];
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const authored = if (example_index != 1) example[1] else try std.fmt.allocPrint(a, "{s} Loan renewed! Renewal refused.", .{example[1]});
        const current = try completedFixtureValue(&fixture, false, try fixture.proposal(authored));
        var assigned = try sessions.assemble(a, text.validator, fixture.context, current);
        if (example_index == 1) {
            const relationship = try fixture.value(captured_subject);
            const name = try fixture.value("Loan");
            const meaning = try fixture.value("A library loan tracks renewal and its borrower.");
            const records = try a.alloc(spec.IdentifiedRecord, assigned.content.records.len + 1);
            @memcpy(records[0..assigned.content.records.len], assigned.content.records);
            records[assigned.content.records.len] = .{ .id = .{ .kind = .entity, .ordinal = 1 }, .proposal = .{ .content = .{ .entity = .{ .name = name.value, .business_meaning = meaning.value, .relationships = &.{relationship.value} } }, .source_group_ids = relationship.source_group_ids, .provenance = relationship.provenance } };
            assigned.content.records = records;
            assigned.content.entities = .{ .disposition = .required, .basis = meaning };
        }
        var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
        inputs.revision = current.revision;
        const missing = try supportDecision(a, inputs);
        try std.testing.expectEqual(.blocked, missing.result.continuation);
        try std.testing.expectEqual(authority.BlockReason.incomplete_assessment, missing.result.entries[0].outcome.administrative_block);
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, inputs, missing.observations, missing.result));
        const baseline = try reviewFor(a, inputs, fixture.context.inputs);
        const ledger = try authority.build(a, inputs);
        const target: usize = if (example_index == 0) 0 else for (ledger.requirements, 0..) |required, index| {
            if (example_index == 2 and required.seed.id.kind == .entity_applicability) break index;
            if (example_index == 1 and required.seed.id.unit == .record and required.seed.id.unit.record.kind == .entity and required.seed.id.slot == .relationship) break index;
        } else return error.MissingRelationshipRequirement;
        try provenance.validateStored(a, fixture.context.inputs, .{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences }, @import("domain/reference_support.zig").records(fixture.context.references), inputs.brief.?, inputs.specification.?);
        try std.testing.expect((try @import("domain/specification_coverage.zig").checkRecords(a, inputs.references.?, inputs.brief.?, inputs.specification.?)) == .valid);
        for ([_]support.Decision{ .supported, .candidate_omission, .candidate_invalid, .inconclusive, .unsupported, .ambiguous, .conflicting }) |decision| {
            const findings = try a.dupe(support.Finding, baseline.entries);
            findings[target].value.kind = decision;
            findings[target].value.detail = if (decision == .supported) "" else if (example_index == 1 and decision == .candidate_omission) captured.object.get("observed_finding").?.object.get("detail").?.string else "Captured semantic judgment remains advice; its native binding does not prove its truth.";
            findings[target].value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
            findings[target].value.missing_obligation = if (decision == .candidate_omission) example[1] else null;
            findings[target].value.question = if (decision == .unsupported or decision == .ambiguous or decision == .conflicting) "Which original business choice is intended? State the required choice." else null;
            const checked = try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null);
            try std.testing.expect(checked == .accepted);
            const accepted = checked.accepted.inputs;
            try std.testing.expectEqual(decision.finding(), accepted.evidence[target].finding);
            try std.testing.expect(accepted.evidence[target].resolution == .assessment);
            if (example_index == 2) {
                try std.testing.expectEqual(spec.Applicability.not_applicable, accepted.specification.?.entities.disposition);
                try std.testing.expectEqual(@as(?authority.Rule, .no_business_data), accepted.evidence[target].resolution.assessment.not_applicable);
            }
            const result = try supportDecision(a, accepted);
            try std.testing.expectEqual(.all_resolved, result.result.continuation);
            try std.testing.expect(result.result.entries[target].outcome == .assessment_complete);
            try std.testing.expect(result.result.entries[target].candidate_defect == null);
            try std.testing.expect((try authority.supportedOmission(a, accepted, result.observations, result.result, accepted.evidence[target].requirement)) == null);
            try std.testing.expect(support.pendingLocalization(accepted, checked.accepted.candidate.review.entries) == null);
            try support.validateStored(a, accepted, fixture.context.inputs);
            try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, accepted, result.observations, result.result));
            try std.testing.expectEqualDeep(inputs.specification, accepted.specification);
            // Advisory tags do not permit stale or foreign candidate bindings.
            for (0..4) |mutation| {
                var forged = accepted;
                const evidence_copy = try a.dupe(authority.Evidence, accepted.evidence);
                forged.evidence = evidence_copy;
                switch (mutation) {
                    0 => evidence_copy[target].resolution.assessment.candidate.revision += 1,
                    1 => evidence_copy[target].resolution = .{ .supported_candidate = accepted.candidates[target].id },
                    2 => evidence_copy[target].method = .deterministic,
                    3 => evidence_copy[target].resolution.assessment.not_applicable = if (evidence_copy[target].resolution.assessment.not_applicable == null) .no_business_data else null,
                    else => unreachable,
                }
                try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, forged, fixture.context.inputs));
                if (mutation == 3) {
                    const forged_ledger = try authority.build(a, forged);
                    try std.testing.expectError(error.InvalidRequiredAuthority, authority.reconcile(a, forged_ledger, try authority.buildObservations(a, forged_ledger)));
                }
            }
        }
    }
}

test "native literal obligations survive code-sample classification and token-only scheduling" {
    const sessions = @import("domain/specification_session.zig");
    const coverage = @import("domain/specification_coverage.zig");
    const exact_policy = @import("domain/specification_exact_tokens.zig");
    const r = references.r;
    for ([_][3][]const u8{
        .{ "Display `Hello, World!` on startup.", "Display Hello, World! on startup.", "The application displays Hello, World! on startup." },
        .{ "Display `Loan renewed!` or `Renewal refused.` after renewal.", "Display Loan renewed! or Renewal refused. after renewal.", "The result is Loan renewed! or Renewal refused. after renewal." },
        .{ "Pass `--color=always` when requesting color.", "Pass --color=always when requesting color.", "The application passes --color=always when requesting color." },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, example[0], .code_sample, true, example[1], 1);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const current = try completedFixtureValue(&fixture, false, try fixture.proposal(example[2]));
        try std.testing.expectEqual(@as(usize, 1), current.record_group_count);
        const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
        const brief = current.units[0].?.response.content.brief;
        const checked = try coverage.validate(a, fixture.context.references, brief, assigned.content);
        try std.testing.expectEqual(all.entries.len - 1, checked.obligations.len);
        for (checked.obligations) |obligation| {
            const claim = (try r.item(all, obligation.claim_id)).claim;
            try std.testing.expectEqual(.code_sample, claim.content.preserved_token.value.kind);
            try std.testing.expect((try exact_policy.policy(all, claim.id)).mandatory);
            try std.testing.expect(try exact_policy.permits(all, claim.id));
            try std.testing.expect(obligation.exact_targets.len != 0);
        }
        // Recognition contributes E and L while authored support S remains
        // exactly the original business group selected by the model.
        for (assigned.content.records) |record| {
            try std.testing.expectEqualSlices(r.ClaimId, &.{all.entries[0].claim.id}, record.proposal.provenance.claim_ids);
            const lineage = try provenance.storedRecordLineage(a, fixture.context.inputs, @import("domain/reference_support.zig").records(fixture.context.references), record.proposal);
            try std.testing.expectEqual(all.entries.len, lineage.effective_claim_ids.len);
        }
        // Maintain an ordinary native support mapping but remove every exact
        // witness. A code_sample classification cannot turn the duty optional.
        const plain = try fixture.proposal("The requested behavior is described.");
        const omitted_session = try completedFixtureValue(&fixture, false, plain);
        const omitted = try sessions.assemble(a, text.validator, fixture.context, omitted_session);
        var mapped_brief = omitted_session.units[0].?.response.content.brief;
        const catalogue = try @import("domain/specification_source_binding.zig").catalogue(a, @import("domain/reference_support.zig").records(fixture.context.references), .content);
        const groups = try a.alloc(r.SignalId, catalogue.len);
        const claims = try a.alloc(r.ClaimId, all.entries.len);
        for (catalogue, groups) |group, *id| id.* = group.signal_id;
        for (all.entries, claims) |item, *id| id.* = item.claim.id;
        mapped_brief.title = try provenance.checkAttributed(.model, a, text.validator, fixture.context, .{ .value = plain.value, .source_group_ids = groups, .provenance = .{ .claim_ids = claims, .clarification_response_ids = &.{} } }, .spec_title);
        const rejected = (try coverage.check(a, fixture.context.references, mapped_brief, omitted.content)).invalid;
        try std.testing.expect(rejected.issue == .missing_exact_copy);
    }
}

test "equal-byte originals retain mixed-kind exact duties through one representative without expanding support" {
    const sessions = @import("domain/specification_session.zig");
    const exact_policy = @import("domain/specification_exact_tokens.zig");
    const native = @import("domain/reference_token_disposition.zig");
    const ex = @import("domain/reference_extraction.zig");
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "Display `ACTIVE` beside `ACTIVE` and `ACTIVE`.", .code_sample, true, "The application displays its status.", 1);
    defer fixture.deinit();
    var changed = fixture.extracted_text;
    const entries = try a.dupe(ex.TextValidatedResult, changed.entries);
    changed.entries = entries;
    const choices = try a.dupe(@import("domain/structured_tokens.zig").Classification, entries[0].token_classifications);
    try std.testing.expectEqual(@as(usize, 3), choices.len);
    choices[1].preserve.kind = .business_exact_string;
    choices[2].preserve.kind = .exact_identifier;
    entries[0].token_classifications = choices;
    fixture.extracted_text = changed;
    fixture.extracted = try extraction.finishText(a, fixture.context.inputs, changed);
    const context: references.Context = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
    const global = try references.summaries(a, try references.initialize(a, context.inputs, fixture.extracted, 2), context);
    fixture.context.references = (try references.finish(a, global, try references.global(a, global), context)).valid;
    const all = try provenance.items(fixture.context);
    const representative = all.entries[1].claim.id;
    try std.testing.expectEqual(.code_sample, all.entries[1].claim.content.preserved_token.value.kind);
    for (all.entries[1..]) |entry| {
        const policy = try exact_policy.policy(all, entry.claim.id);
        try std.testing.expect(policy.mandatory);
        try std.testing.expectEqualDeep(representative, policy.representative);
        try std.testing.expectEqual(entry.claim.id.ordinal == representative.ordinal, try exact_policy.permits(all, entry.claim.id));
    }
    const current = try completedFixtureValue(&fixture, false, try fixture.proposal("The application displays ACTIVE beside its status."));
    try std.testing.expectEqual(@as(usize, 1), current.record_group_count);
    const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
    const covered = try @import("domain/specification_coverage.zig").validate(a, fixture.context.references, current.units[0].?.response.content.brief, assigned.content);
    try std.testing.expectEqual(@as(usize, 3), covered.obligations.len);
    for (covered.obligations, all.entries[1..]) |obligation, entry| {
        try std.testing.expectEqualDeep(entry.claim.id, obligation.claim_id);
        try std.testing.expectEqualDeep(covered.obligations[0].exact_targets, obligation.exact_targets);
        try std.testing.expect(obligation.exact_targets.len != 0);
    }
    for (assigned.content.records) |record| {
        try std.testing.expectEqualSlices(r.ClaimId, &.{all.entries[0].claim.id}, record.proposal.provenance.claim_ids);
        const lineage = try provenance.storedRecordLineage(a, fixture.context.inputs, @import("domain/reference_support.zig").records(fixture.context.references), record.proposal);
        try std.testing.expectEqualSlices(r.ClaimId, &.{ all.entries[0].claim.id, representative }, lineage.effective_claim_ids);
    }
    // Original Kind, occurrence and native edge survive snapshot validation.
    const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
    const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
    const snapshot = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "mixed-kinds" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
    try @import("domain/reference_snapshot.zig").validate(a, snapshot);
    for (snapshot.dispositions) |disposition| if ((try r.item(all, disposition.claim_id)).claim.content == .preserved_token) try std.testing.expect(try native.matches(all, disposition));
    const support = @import("domain/specification_support.zig").Source;
    const state = @import("domain/specification_state.zig");
    var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
    inputs.revision = current.revision;
    const positive = try reviewFor(a, inputs, fixture.context.inputs);
    const findings = try a.dupe(support.Finding, positive.entries);
    const ledger = try @import("domain/required_authority.zig").build(a, inputs);
    for (ledger.requirements, findings) |requirement, *finding| if (requirement.seed.id.unit == .record) {
        const rule = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, fixture.context.inputs, requirement.seed.id);
        finding.value.provenance.claim_ids = rule.supported_provenance.?.claim_ids;
    };
    const reviewed = (try collectReview(support, a, inputs, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
    const decision = try supportDecision(a, reviewed);
    const stored: state.State = .{
        .schema = state.schema,
        .principle_assessment = try @import("test_fixtures/principles.zig").emptyAssessment(a, reviewed),
        .feature = current.feature,
        .revision = 1,
        .stage = .specified,
        .reference = snapshot,
        .brief = inputs.brief.?,
        .content = assigned.content,
        .id_ledger = assigned.ledger,
        .coverage = covered,
        .clarification = .{ .state_ordinal = 1, .revision = 1 },
        .review = .{ .candidate_revision = inputs.revision, .seeds = reviewed.seeds, .evidence = reviewed.evidence, .candidates = reviewed.candidates, .observations = decision.observations, .result = decision.result, .advice_stop = reviewed.advice_stop },
    };
    const restored = (try state.parse(a, try std.json.Stringify.valueAlloc(a, stored, .{}), current.feature, contracts.port())).specified().?;
    try std.testing.expectEqualDeep(stored.coverage, restored.coverage);
    try std.testing.expectEqualDeep(stored.reference.extraction, restored.reference.extraction);
    // Every original duplicate duty participates in readback equality even
    // though the representative supplies the single exact byte witness.
    var omitted = stored;
    omitted.coverage.obligations = covered.obligations[0..2];
    try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, omitted, .{}), current.feature, contracts.port()));
    var forged = stored;
    const dispositions = try a.dupe(r.ClaimDisposition, snapshot.dispositions);
    dispositions[all.entries[3].claim.id.ordinal - 1].related_claim_ids = &.{all.entries[2].claim.id};
    forged.reference.dispositions = dispositions;
    try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, forged, .{}), current.feature, contracts.port()));
}

test "source units and complete principle sets preserve every record family and relationship member" {
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Describe the complete business operation and its data relationships.");
    defer fixture.deinit();
    const attributed = try fixture.value("A complete business statement relates the participating records.");
    const records = try a.alloc(spec.IdentifiedRecord, std.meta.tags(spec.Kind).len + 1);
    inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| {
        var fields: @FieldType(spec.Content(spec.BusinessValue), @tagName(kind)) = undefined;
        inline for (@typeInfo(@TypeOf(fields)).@"struct".fields) |field| {
            @field(fields, field.name) = if (field.type == spec.BusinessValue) attributed.value else &.{ attributed.value, attributed.value };
        }
        records[index] = .{ .id = .{ .kind = kind, .ordinal = 1 }, .proposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), fields), .source_group_ids = attributed.source_group_ids, .provenance = attributed.provenance } };
    }
    var second_criterion = records[0];
    second_criterion.id.ordinal = 2;
    std.mem.copyBackwards(spec.IdentifiedRecord, records[2..], records[1 .. records.len - 1]);
    records[1] = second_criterion;
    const content: spec.IdentifiedContent = .{ .display_name = attributed, .primary_user_story = attributed, .entities = .{ .disposition = .required, .basis = attributed }, .records = records };
    const source_inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, content, .{ .title = attributed, .description = attributed, .primary_goal = attributed });
    const registry = try @import("test_fixtures/principles.zig").registry(a, "Keep the business operation understandable.\n");
    const policy_selection = try @import("domain/principle_registry.zig").select(a, registry, .{ .stage = .spec, .environment = null, .fileKind = null });
    inline for ([_]support.Purpose{ .source, .principles }) |purpose| {
        const Review = support.Contract(purpose);
        const inputs = if (purpose == .source) source_inputs else try @import("domain/principle_assessment.zig").project(a, .{ .business = .{ .feature = source_inputs.feature, .revision = source_inputs.revision, .brief = source_inputs.brief.?, .content = content, .references = source_inputs.references.? }, .registry = registry, .selection = policy_selection });
        const ledger = try authority.build(a, inputs);
        const findings = if (purpose == .source) (try reviewFor(a, inputs, fixture.context.inputs)).entries else blk: {
            const values = try a.alloc(Review.Finding, ledger.requirements.len);
            for (values, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = .compatible, .citations = &.{}, .detail = "" } };
            break :blk values;
        };
        var current: ?Review.Collection = null;
        var position: usize = 0;
        var largest: usize = 0;
        var assignments: usize = 0;
        while (position < ledger.requirements.len) {
            assignments += 1;
            const target = ledger.requirements[position].seed.id;
            const members = try Review.assignmentSubjects(a, inputs, target);
            largest = @max(largest, members.len);
            const unit = try @import("domain/specification_review_subject.zig").assignmentUnit(a, inputs, target);
            for (members) |member| try std.testing.expectEqualDeep(unit, try @import("domain/specification_review_subject.zig").assignmentUnit(a, inputs, member));
            const packet = try Review.packetFor(a, inputs, fixture.context, Review.assignmentScope(inputs, target));
            defer packets.release(packet);
            try std.testing.expect(try Review.matchesAdvicePacket(a, inputs, fixture.context, current, packet));
            const body = try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{});
            try std.testing.expectEqual(members.len, body.object.get("requirements").?.array.items.len);
            if (unit == .record_family) {
                // One call reviews every record of the kind; each member keeps the
                // record it belongs to instead of one shared assignment record.
                try std.testing.expect(!body.object.contains("record"));
                var distinct: usize = 0;
                for (members, body.object.get("requirements").?.array.items, 0..) |member, requirement, index| {
                    try std.testing.expectEqual(unit.record_family, member.unit.record.kind);
                    const id = requirement.object.get("subject").?.object.get("record").?.object.get("id").?.object;
                    try std.testing.expectEqualStrings(@tagName(member.unit.record.kind), id.get("kind").?.string);
                    try std.testing.expectEqual(@as(i64, member.unit.record.ordinal), id.get("ordinal").?.integer);
                    if (index == 0 or !std.meta.eql(members[index - 1].unit.record, member.unit.record)) distinct += 1;
                }
                // The fixture authors two acceptance criteria and one record of every other kind.
                try std.testing.expectEqual(@as(usize, if (unit.record_family == .acceptance_criterion) 2 else 1), distinct);
                if (unit.record_family == .entity) try std.testing.expectEqual(@as(usize, 4), members.len);
                // Only the first family member can start the assignment.
                if (members.len > 1) try std.testing.expectError(error.InvalidRequiredAuthority, Review.assignmentSubjects(a, inputs, members[members.len - 1]));
            }
            if (purpose == .principles) {
                try std.testing.expect(unit == .principle_set);
                try std.testing.expectEqual(ledger.requirements.len, members.len);
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, packet.body(), "\"principles\":"));
                try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, packet.body(), "\"business_context\":"));
                try std.testing.expect(!body.object.contains("record"));
                try std.testing.expectEqual(registry.chunks.len, body.object.get("principles").?.array.items.len);
                const assigned = try @import("domain/principle_assessment.zig").subjects(a, inputs.principle_context.?.business);
                for (assigned, body.object.get("requirements").?.array.items) |subject_id, requirement| {
                    const subject = requirement.object.get("subject").?.object;
                    try std.testing.expect(!subject.contains("context"));
                    if (subject_id.unit == .record) {
                        const retained_record = try @import("domain/model_candidate_json.zig").decode(spec.CapturedRecord, a, try std.json.Stringify.valueAlloc(a, subject.get("record").?, .{}));
                        try std.testing.expectEqualDeep(subject_id.unit.record, retained_record.id.?);
                    }
                }
                try std.testing.expectError(error.InvalidRequiredAuthority, Review.assignmentSubjects(a, inputs, members[1]));
                const source_ledger = try authority.build(a, source_inputs);
                const source_packet = try support.Source.packetFor(a, source_inputs, fixture.context, support.Source.assignmentScope(source_inputs, source_ledger.requirements[0].seed.id));
                defer packets.release(source_packet);
                try std.testing.expect(!try Review.matchesAdvicePacket(a, inputs, fixture.context, null, source_packet));
                var changed = inputs;
                changed.principle_context.?.business.brief.description.value = .{ .segments = &.{.{ .literal = .{ .value = "A different current business description." } }} };
                try std.testing.expect(!try Review.matchesAdvicePacket(a, changed, fixture.context, null, packet));
            }
            const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = @intCast(position + 1) }, .attempt = .{ .value = 1 } };
            const wire = try assignmentWire(Review, a, inputs, fixture.context, target, .{ .entries = findings });
            var missing_member = try std.json.parseFromSliceLeaky(std.json.Value, a, wire, .{});
            missing_member.object.getPtr("findings").?.array.items.len -= 1;
            const rejected = try Review.collectFocused(a, inputs, fixture.context, current, packet, try std.json.Stringify.valueAlloc(a, missing_member, .{}), origin);
            try std.testing.expect(rejected == .rejected and rejected.rejected.candidate == null);
            try std.testing.expectEqual(.missing_finding, rejected.rejected.rejection.selected().?.issue);
            if (purpose == .principles) {
                for ([_]bool{ false, true }) |foreign| {
                    var invalid_member = try std.json.parseFromSliceLeaky(std.json.Value, a, wire, .{});
                    const ordinal = invalid_member.object.getPtr("findings").?.array.items[1].object.getPtr("requirement_ordinal").?;
                    ordinal.* = .{ .integer = if (foreign) @intCast(ledger.requirements.len + 1) else 1 };
                    const invalid = try Review.collectFocused(a, inputs, fixture.context, null, packet, try std.json.Stringify.valueAlloc(a, invalid_member, .{}), origin);
                    try std.testing.expect(invalid == .rejected and invalid.rejected.candidate == null);
                    try std.testing.expectEqual(if (foreign) Review.Issue.unknown_requirement else Review.Issue.duplicate_requirement, invalid.rejected.rejection.selected().?.issue);
                }
                const invalid_findings = try a.dupe(Review.Finding, findings);
                const correction_index = invalid_findings.len / 2;
                invalid_findings[correction_index].value.detail = " \t";
                const invalid = (try Review.collectFocused(a, inputs, fixture.context, null, packet, try assignmentWire(Review, a, inputs, fixture.context, target, .{ .entries = invalid_findings }), origin)).rejected;
                try std.testing.expectEqual(.invalid_detail, invalid.rejection.selected().?.issue);
                const Repair = @import("domain/specification_support_repair.zig").Contract(.principles);
                const authorization = try Repair.authorize(a, inputs, fixture.context, invalid);
                const correction_packet = try Repair.packet(a, inputs, fixture.context, invalid.candidate.?, authorization);
                defer packets.release(correction_packet);
                try std.testing.expect(correction_packet.advisoryAssessment() != null);
                try std.testing.expect(try Review.matchesAdvicePacket(a, inputs, fixture.context, .{ .rejected = invalid }, correction_packet));
                try std.testing.expect(!try Review.matchesAdvicePacket(a, inputs, fixture.context, null, correction_packet));
                const corrected_origin: @TypeOf(origin) = .{ .request = .{ .value = 100 }, .attempt = .{ .value = 1 } };
                const corrected = (try Repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), inputs, fixture.context, invalid.candidate.?, authorization, .{ .detail = .{ .detail = "" } }, corrected_origin)).accepted;
                try std.testing.expectEqualDeep(findings, corrected.candidate.review.entries);
                for (corrected.candidate.origins, 0..) |retained_origin, index| try std.testing.expectEqualDeep(if (index == correction_index) corrected_origin else origin, retained_origin.?);
                try Review.validateStored(a, corrected.inputs, fixture.context.inputs);
            }
            if (current) |prior| try std.testing.expectEqual(position, prior.pending.review.entries.len);
            current = try Review.collectFocused(a, inputs, fixture.context, current, packet, wire, origin);
            const candidate = if (current.? == .pending) current.?.pending else current.?.accepted.candidate;
            for (candidate.origins[position..]) |retained| try std.testing.expectEqualDeep(origin, retained.?);
            position += members.len;
            try std.testing.expectEqual(position, candidate.review.entries.len);
        }
        try std.testing.expect(largest > 3);
        if (purpose == .principles) try std.testing.expectEqual(@as(usize, 1), assignments) else try std.testing.expect(assignments > 3);
        try std.testing.expect(current.? == .accepted);
        const reviewed = current.?.accepted.inputs;
        const result = try supportDecision(a, reviewed);
        try std.testing.expectEqual(.all_resolved, result.result.continuation);
        for (result.result.entries) |entry| try std.testing.expect(entry.outcome == .assessment_complete);
        try Review.validateStored(a, reviewed, fixture.context.inputs);
    }
}

test "native advice stops retain admitted assignments and never resolve missing native content" {
    const authority = @import("domain/required_authority.zig");
    const Review = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    for ([_][]const u8{ "Start successfully and show the current UTC time.", "Renew the eligible loan and show the resulting deadline." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try completedSupportInputs(&fixture);
        const ledger = try authority.build(a, inputs);
        var good = try reviewFor(a, inputs, fixture.context.inputs);
        const advisory_findings = try a.dupe(Review.Finding, good.entries);
        advisory_findings[0].value.kind = .inconclusive;
        advisory_findings[0].value.detail = "The reviewer could not assess this business statement.";
        good.entries = advisory_findings;
        const origin: Origin = .{ .request = .{ .value = 200 }, .attempt = .{ .value = 1 } };
        const stopped_origin: Origin = .{ .request = .{ .value = 201 }, .attempt = .{ .value = 1 } };
        var prior: ?Review.Collection = null;
        var retained: usize = 0;
        while (ledger.requirements[retained].seed.id.unit != .record) {
            const id = ledger.requirements[retained].seed.id;
            const packet = try Review.packetFor(a, inputs, fixture.context, Review.assignmentScope(inputs, id));
            defer packets.release(packet);
            prior = try Review.collectFocused(a, inputs, fixture.context, prior, packet, try assignmentWire(Review, a, inputs, fixture.context, id, good), origin);
            try std.testing.expect(prior.? == .pending);
            retained += (try Review.assignmentSubjects(a, inputs, id)).len;
        }
        const id = ledger.requirements[retained].seed.id;
        const members = try Review.assignmentSubjects(a, inputs, id);
        try std.testing.expect(members.len > 1);
        const invalid_findings = try a.dupe(Review.Finding, good.entries);
        invalid_findings[retained].value.detail = " \t";
        const packet = try Review.packetFor(a, inputs, fixture.context, Review.assignmentScope(inputs, id));
        defer packets.release(packet);
        const rejected = try Review.collectFocused(a, inputs, fixture.context, prior, packet, try assignmentWire(Review, a, inputs, fixture.context, id, .{ .entries = invalid_findings }), stopped_origin);
        try std.testing.expect(rejected == .rejected and rejected.rejected.candidate != null);
        const stopped = (try Review.stop(a, inputs, fixture.context, rejected, .protocol_exhausted, stopped_origin)).accepted;
        try std.testing.expectEqual(retained, stopped.inputs.evidence.len);
        try std.testing.expectEqual(.inconclusive, stopped.inputs.evidence[0].finding);
        try std.testing.expectEqualDeep(good.entries[0..retained], stopped.candidate.review.entries);
        for (stopped.candidate.origins) |retained_origin| try std.testing.expectEqualDeep(origin, retained_origin.?);
        try std.testing.expectEqual(ledger.requirements.len - retained, stopped.inputs.advice_stop.?.unassessed.len);
        try std.testing.expectEqualDeep(stopped_origin, stopped.inputs.advice_stop.?.origin.?);
        try Review.validateStored(a, stopped.inputs, fixture.context.inputs);
        const decision = try supportDecision(a, stopped.inputs);
        try std.testing.expectEqual(.all_resolved, decision.result.continuation);
        for (decision.result.entries, 0..) |entry, index| try std.testing.expect(if (index < retained) entry.outcome == .assessment_complete else entry.outcome == .assessment_incomplete);
        for (0..6) |mutation| {
            var forged = stopped.inputs;
            switch (mutation) {
                0 => forged.advice_stop = null,
                1 => forged.advice_stop.?.candidate_revision += 1,
                2 => forged.advice_stop.?.projection = .source_readiness,
                3 => forged.advice_stop.?.requirements = forged.advice_stop.?.requirements[1..],
                4 => forged.advice_stop.?.unassessed = forged.advice_stop.?.unassessed[1..],
                5 => {
                    forged.evidence = forged.evidence[0..1];
                    forged.candidates = forged.candidates[0..1];
                    forged.advice_stop.?.unassessed = forged.advice_stop.?.requirements[1..];
                },
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidRequiredAuthority, Review.validateStored(a, forged, fixture.context.inputs));
        }
        const readiness = try @import("domain/specification_authority.zig").project(a, inputs.feature, fixture.context.references, null, null);
        try std.testing.expectError(error.InvalidRequiredAuthority, Review.stop(a, readiness, fixture.context, null, .usage_unavailable, origin));
        var missing = inputs.specification.?;
        missing.records = &.{};
        const invalid = try @import("domain/specification_authority.zig").project(a, inputs.feature, fixture.context.references, missing, inputs.brief);
        const native_failure = (try Review.stop(a, invalid, fixture.context, null, .provider_failure, origin)).accepted.inputs;
        try std.testing.expectEqual(.invalid, (try supportDecision(a, native_failure)).result.continuation);
        inline for (std.meta.tags(authority.AdviceStop.Reason)) |reason| {
            const stop_origin: ?@import("domain/model_candidate_origin.zig").Origin = origin;
            const empty = (try Review.stop(a, inputs, fixture.context, null, reason, stop_origin)).accepted.inputs;
            var invalid_origin = empty;
            invalid_origin.advice_stop.?.origin = if (stop_origin == null) origin else null;
            try std.testing.expectError(error.InvalidRequiredAuthority, Review.validateStored(a, invalid_origin, fixture.context.inputs));
            if (stop_origin != null) {
                inline for (0..2) |invalid_field| {
                    var forged_origin = empty;
                    switch (invalid_field) {
                        0 => forged_origin.advice_stop.?.origin.?.request.value = 0,
                        1 => forged_origin.advice_stop.?.origin.?.attempt.value = 0,
                        else => unreachable,
                    }
                    try std.testing.expectError(error.InvalidRequiredAuthority, Review.validateStored(a, forged_origin, fixture.context.inputs));
                }
            }
            try std.testing.expectEqual(@as(usize, 0), empty.evidence.len);
            try std.testing.expectEqual(@as(usize, 0), empty.candidates.len);
            try std.testing.expectEqual(reason, empty.advice_stop.?.reason);
            try Review.validateStored(a, empty, fixture.context.inputs);
        }
    }
}

test "incomplete source and principle advice survive publication readback without invented findings" {
    const authority = @import("domain/required_authority.zig");
    const Review = @import("domain/specification_review.zig");
    const state = @import("domain/specification_state.zig");
    const sessions = @import("domain/specification_session.zig");
    for ([_][]const u8{ "Start the application and show the current UTC date and time.", "Renew an eligible loan and show its new deadline." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const current = try completedFixture(&fixture, false);
        const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
        var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
        inputs.revision = current.revision;
        const source_origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 77 }, .attempt = .{ .value = 1 } };
        const stopped = try Review.Source.stop(a, inputs, fixture.context, null, .provider_output_limit, source_origin);
        const policies = try @import("test_fixtures/principles.zig").registry(a, "Keep user-visible behavior clear.\n");
        const pending = (try Review.advance(a, .{ .source = stopped }, policies)).progress.pending;
        const policy_origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 78 }, .attempt = .{ .value = 1 } };
        const stopped_policy = try Review.Policy.stop(a, pending.inputs, fixture.context, null, .protocol_exhausted, policy_origin);
        const advanced = try Review.advance(a, .{ .principles = .{ .pending = pending, .result = stopped_policy } }, policies);
        try std.testing.expectEqual(.complete, advanced.outcome);
        const reviewed = advanced.progress.source.accepted.inputs;
        try std.testing.expectEqualDeep(inputs.specification, reviewed.specification);
        const principle = reviewed.principle_assessment.?;
        try std.testing.expect(principle.advice_stop != null);
        try std.testing.expectEqual(@as(usize, 0), principle.evidence.len);
        try std.testing.expectEqual(@as(usize, 0), principle.candidates.len);
        for (principle.result.entries) |entry| try std.testing.expect(entry.outcome == .assessment_incomplete);
        try @import("domain/principle_assessment.zig").validateStored(a, reviewed, fixture.context.inputs, principle);
        const decision = try supportDecision(a, reviewed);
        try std.testing.expectEqual(.all_resolved, decision.result.continuation);
        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
        const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
        const snapshot = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "references" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
        const stored: state.State = .{
            .schema = state.schema,
            .principle_assessment = principle,
            .feature = current.feature,
            .revision = 1,
            .stage = .specified,
            .reference = snapshot,
            .brief = inputs.brief.?,
            .content = assigned.content,
            .id_ledger = assigned.ledger,
            .coverage = try @import("domain/specification_coverage.zig").validate(a, fixture.context.references, inputs.brief.?, assigned.content),
            .clarification = .{ .state_ordinal = 1, .revision = 1 },
            .review = .{ .candidate_revision = inputs.revision, .seeds = reviewed.seeds, .evidence = reviewed.evidence, .candidates = reviewed.candidates, .observations = decision.observations, .result = decision.result, .advice_stop = reviewed.advice_stop },
        };
        const bytes = try std.json.Stringify.valueAlloc(a, stored, .{});
        const restored = (try state.parse(a, bytes, current.feature, contracts.port())).specified().?;
        try std.testing.expectEqualStrings(bytes, try std.json.Stringify.valueAlloc(a, restored, .{}));
        const view = try @import("domain/reference_context.zig").render(a, snapshot, restored.principle_assessment, null);
        try std.testing.expect(std.mem.indexOf(u8, view, "Assessment incomplete (protocol_exhausted)") != null);
        try std.testing.expect(std.mem.indexOf(u8, view, "Missing advice is not a compatible finding") != null);
        for (0..6) |mutation| {
            var forged = stored;
            switch (mutation) {
                0 => forged.schema = "specification-state/v18",
                1 => forged.review.advice_stop = null,
                2 => forged.review.advice_stop.?.candidate_revision += 1,
                3 => forged.principle_assessment.advice_stop = null,
                4 => forged.principle_assessment.advice_stop.?.candidate_revision += 1,
                5 => {
                    const entries = try a.dupe(authority.Entry, forged.review.result.entries);
                    entries[0].outcome = .{ .assessment_complete = .{ .candidate = .{ .ordinal = 1, .revision = inputs.revision } } };
                    forged.review.result.entries = entries;
                },
                else => unreachable,
            }
            try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, forged, .{}), current.feature, contracts.port()));
        }
    }
}
