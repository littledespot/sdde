const std = @import("std");
const packet_guidance = @import("test_fixtures/packet_guidance.zig");
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
/// The selected reference directory fixture sources are shown in (§23 source lines).
const test_directory: @import("domain/reference_ingestion.zig").RelativePath = .{ .bytes = "references/feature" };

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
    return Review.packetFor(allocator, inputs, context, &packet_guidance.marked, .{ .finding = ledger.requirements[index].seed.id });
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
        var fixture = try Fixture.initContent(a, example[0], null, true, 1);
        defer fixture.deinit();
        const inputs = try projector.execute(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, fixture.context.inputs);
        try std.testing.expect((try (@import("actions/specification/initialize_specification_review.zig").Action{}).execute(inputs)) == .initial);
        var foreign = inputs;
        foreign.projection = .registered_obligations;
        try std.testing.expectError(error.InvalidRequiredAuthority, (@import("actions/specification/initialize_specification_review.zig").Action{}).execute(foreign));
        const ledger = try authority.build(a, inputs);
        try std.testing.expectEqual(fixture.context.inputs.corpus.sources.len, ledger.requirements.len);
        const id = ledger.requirements[0].seed.id;
        try std.testing.expect(id.unit == .source);
        const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, .{ .finding = id });
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
        const missing_authority = try review_repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, missing.rejected);
        const replacement_packet = try review_repair.packet(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, missing.rejected.candidate.?, missing_authority);
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

        // Rejected evidence keeps the preserved omission in its support repair
        // rule, which presents each comparison with its guidance purpose.
        var ineligible = finding;
        ineligible.value.provenance = .{ .claim_ids = &.{.{ .ordinal = 999 }}, .clarification_response_ids = &.{} };
        const rejected = try support.validate(a, inputs, fixture.context.inputs, .{ .review = .{ .entries = &.{ineligible} }, .origin = null, .origins = &.{null} });
        try std.testing.expect(rejected == .rejected);
        try std.testing.expect(rejected.rejected.rejection.selected().?.evidence.?.issue != .invalid_loss);
        const selection_authority = try review_repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected.rejected);
        const selection_packet = try review_repair.packet(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, rejected.rejected.candidate.?, selection_authority);
        defer @import("domain/model_input_packet.zig").release(selection_packet);
        try expectPresentedComparisons(a, selection_packet, finding.value.preservation.?);
        var unregistered = finding.value;
        unregistered.preservation.?.assignment.finding.subject = .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .text };
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/model_presentation.zig").present(@TypeOf(unregistered), a, &packet_guidance.marked, unregistered));
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
            try std.testing.expectError(error.UnsafeSupportRepair, review_repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, forbidden.rejected));
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
    const finding_packet = try support.packetFor(a, inputs, fixture.context, &packet_guidance.marked, .{ .finding = id });
    defer @import("domain/model_input_packet.zig").release(finding_packet);
    const omitted = try support.collectFocused(a, inputs, fixture.context, &packet_guidance.marked, null, finding_packet, "{\"kind\":\"candidate_omission\",\"source_ids\":[1],\"detail\":\"The supplied identity was discarded.\",\"missing_obligation\":\"MOCK The feature is named Known feature.\"}", null);
    try std.testing.expect(omitted == .accepted);
    try std.testing.expect(omitted.accepted.candidate.pending_localization != null);
    const packet = try support.packetForLoss(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, omitted.accepted.candidate);
    defer @import("domain/model_input_packet.zig").release(packet);
    const foreign = try @import("domain/model_input_packet.zig").create(a, packet.body(), packet.unit(), .{ .semantic_review = .{ .bytes = "foreign-review" } }, packet.resultDefinition());
    defer @import("domain/model_input_packet.zig").release(foreign);
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collectLoss(a, inputs, fixture.context, &packet_guidance.marked, omitted, foreign, "{}", null));
    const localized = try support.collectLoss(a, inputs, fixture.context, &packet_guidance.marked, omitted, packet, try @import("test_fixtures/source_omission_evidence.zig").encode(a, try support.comparisonAssignment(a, inputs, fixture.context, omitted.accepted.candidate), .{ .extraction_claim = fixture.extracted.ledger.chunks[0].scope.chunk_id }), null);
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
        var fixture = try Fixture.initContent(a, example[0], null, true, 1);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        const original = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
        defer packets.release(original);
        const good = try fixture.proposal(example[1]);
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = good } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked);
        const correction = try repair.packet(std.testing.allocator, current, fixture.context, authorization, &packet_guidance.marked);
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
                try std.testing.expectEqualStrings(packet_guidance.marked.feature_purposes.get(.description), assignment.get("description").?.object.get("purpose").?.string);
                try std.testing.expect(!input.object.contains("task"));
            } else {
                try std.testing.expect(!assignment.get("description").?.object.contains("purpose"));
                try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .description }), try selectedNativeRepairTask(input));
            }
            const groups = try @import("domain/model_candidate_json.zig").decode([]const @import("domain/specification_source_binding.zig").GroupGuidance, a, try std.json.Stringify.valueAlloc(a, input.object.get("source_groups").?, .{}));
            try expectAssignedRequirements(good.provenance.claim_ids, groups[0].requirements);
        }
        // Added source context does not widen valid provenance or authorize lost content.
        try std.testing.expectError(error.InvalidReferenceReconciliation, provenance.select(a, fixture.context, .{ .claim_ids = &.{.{ .ordinal = 999 }}, .clarification_response_ids = &.{} }));
        const recovered = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = good.value }, null);
        const validated = (try validate_unit.execute(a, current, fixture.context, recovered)).valid;
        try std.testing.expectEqualDeep(good.provenance.claim_ids, validated.response.content.brief.description.provenance.claim_ids);
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
    // Retained call 9's source, an unrelated business domain, a legitimate
    // exact name, and an undecided source. These are packet/shape regressions;
    // the exported requests permit separate live semantic comparison.
    // Each claim cites its whole chunk and quotes it (ADR 0036). Hello's list splits
    // into the headings and one claim per item (ADR 0038). `authored` is the
    // generated value.
    const cases = [_]struct { name: []const u8, source: []const u8, quoted: []const []const u8, authored: []const u8 }{
        .{ .name = "hello", .source = "# MOCK Hello World Application\n\n## Requirements\n\n- The application must start successfully.\n- When started, the application must display `MOCK Hello, World!`.\n- Must also output date and time in UTC\n", .quoted = &.{ "# MOCK Hello World Application\n\n## Requirements", "- The application must start successfully.", "- When started, the application must display `MOCK Hello, World!`.", "- Must also output date and time in UTC" }, .authored = "The application must start successfully.When started, the application must display `MOCK Hello, World!`.The application must also output date and time in UTC." },
        .{ .name = "renewal", .source = "# Library Loan Renewal\nA borrower may renew an eligible loan for fourteen days and sees `Loan renewed` and the new due date. Refused renewals retain the old due date.\n", .quoted = &.{"# Library Loan Renewal\nA borrower may renew an eligible loan for fourteen days and sees `Loan renewed` and the new due date. Refused renewals retain the old due date."}, .authored = "Borrowers renew eligible loans for fourteen days and see confirmation and the new due date. Refused renewals retain the old due date." },
        .{ .name = "exact-name", .source = "# Readiness confirmation\nThe feature must be named `Ready!`. It lets an operator confirm readiness and displays that same exact message after confirmation.\n", .quoted = &.{"# Readiness confirmation\nThe feature must be named `Ready!`. It lets an operator confirm readiness and displays that same exact message after confirmation."}, .authored = "The feature is named Ready! and lets an operator confirm readiness, then displays the required readiness message." },
        .{ .name = "missing-choice", .source = "# Renewal Policy\nBorrowers can renew eligible loans and see the new due date. The renewal duration is undecided and must be supplied by the owner.\n", .quoted = &.{"# Renewal Policy\nBorrowers can renew eligible loans and see the new due date. The renewal duration is undecided and must be supplied by the owner."}, .authored = "Borrowers renew eligible loans and see the new due date; the owner has not decided the renewal duration." },
    };
    try std.Io.Dir.cwd().createDirPath(std.testing.io, ".zig-cache/authoring-comparison");
    for (cases) |example| {
        var fixture = try Fixture.initContent(a, example.source, .business_exact_string, true, 1);
        defer fixture.deinit();
        const claims = fixture.extracted_text.entries[0].outcome.claims;
        try std.testing.expectEqual(example.quoted.len, claims.len);
        for (example.quoted, claims) |quoted, claim| try std.testing.expectEqualStrings(quoted, claim.content.business.value.segments[0].literal.value);
        var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const good = try fixture.proposal(example.authored);
        for (0..sessions.unit_count) |index| {
            current.completed = index;
            if (index != 0) current.units[0] = (try g.validate(a, text.validator, fixture.context, .brief, .{ .content = .{ .brief = .{ .description = good, .primary_goal = good } } })).valid;
            if (index == sessions.records_index) current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = good } } })).valid;
            // ADR 0047: the engine composes the story; no authoring request carries it.
            if (index == sessions.story_index) {
                try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked));
                continue;
            }
            const bound = try sessions.currentBinding(a, current, fixture.context);
            const before = try codec.encode(binding.Bound, a, bound);
            const packet = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            // Only the entities request receives an earlier draft, the brief.
            try std.testing.expectEqual(index == sessions.entities_index, body.contains("brief"));
            try std.testing.expect(!body.contains("entities"));
            if (body.get("brief")) |brief| {
                try std.testing.expectEqual(@as(usize, 2), brief.object.count());
                for ([_][]const u8{ "description", "primary_goal" }) |field| try std.testing.expectEqualStrings(example.authored, brief.object.get(field).?.string);
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
            try std.testing.expectEqualStrings(example.quoted[0], selected_requirements[0].meaning);
            for (body.get("context_requirements").?.array.items) |requirement| try std.testing.expect(!binding.assigns(assigned, .{ .ordinal = @intCast(requirement.object.get("claim_id").?.integer) }));
            switch (assigned) {
                .brief => |brief| {
                    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .description }), brief.description.purpose.?);
                    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .primary_goal }), brief.primary_goal.purpose.?);
                    const selected = try schema.restrict(a, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
                    defer selected.release();
                    if (body.get("exact_texts").?.array.items.len != 0) {
                        const id = body.get("exact_texts").?.array.items[0].object.get("claim_id").?.integer;
                        const segment = if (body.get("exact_texts").?.array.items.len == 1) "{\"kind\":\"exact_copy\"}" else try std.fmt.allocPrint(a, "{{\"kind\":\"exact_copy\",\"claim_id\":{d}}}", .{id});
                        const wire = try std.fmt.allocPrint(a, "{{\"kind\":\"brief\",\"description\":{{\"signal_ids\":[1],\"value\":{{\"fragments\":[{s}]}}}},\"primary_goal\":{{\"signal_ids\":[1],\"value\":{{\"fragments\":[{s}]}}}}}}", .{ segment, segment });
                        // Occurrence handles are native facts, never accepted
                        // model-text variants, even when their ID is known.
                        try @import("model_payload_schema_test.zig").checkDocument(selected.selected().modelBytes(), .{ .bytes = wire, .rejection = .type_mismatch });
                        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, try codec.constructBound(a, wire, packet.integerChoices()), bound));
                    }
                    const export_value = .{ .input = std.json.Value{ .object = body }, .prior_assignment = (try std.json.parseFromSlice(std.json.Value, a, before, .{})).value, .schema = selected.selected().modelBytes() };
                    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = try std.fmt.allocPrint(a, ".zig-cache/authoring-comparison/{s}.json", .{example.name}), .data = try std.json.Stringify.valueAlloc(a, export_value, .{}) });
                },
                .entities => |entities| {
                    try std.testing.expect(std.mem.indexOf(u8, entities.purpose.?, try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, .{ .kind = .entity_applicability, .unit = .{ .feature = .singleton }, .slot = .entities })) != null);
                    try std.testing.expect(std.mem.indexOf(u8, entities.purpose.?, try @import("domain/required_authority_description.zig").record(a, &packet_guidance.marked, .entity)) != null);
                },
                .records => |records| {
                    try expectAssignedRequirements(bound.records.selection.claim_ids, records.requirements);
                    try std.testing.expectEqualDeep(bound.records.signal, records.signal);
                    const descriptions = @import("domain/required_authority_description.zig");
                    inline for (comptime std.meta.tags(spec.Kind)) |kind| try std.testing.expectEqual(kind != .entity, std.mem.indexOf(u8, records.purpose.?, descriptions.recordFamily(&packet_guidance.marked, kind)) != null);
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
        current.units[0].?.response.content.brief = .{ .description = accepted, .primary_goal = accepted };
        var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const canonical = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
        // The entities request receives the resolved brief and no entity decision.
        {
            const packet = try sessions.packetForOptions(std.testing.allocator, current, fixture.context, sessions.entities_index, .{ .presentation = .{ .authoring = &packet_guidance.marked } });
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            const brief = body.get("brief").?.object;
            try std.testing.expectEqual(@as(usize, 2), brief.count());
            for ([_][]const u8{ "description", "primary_goal" }) |field| try std.testing.expectEqualStrings(expected, brief.get(field).?.string);
            try std.testing.expect(!body.contains("entities"));
        }
        // Records requests and their repair packets receive neither draft, so the
        // entity decision changes no byte of them.
        var first_bodies: [2]?[]const u8 = .{ null, null };
        // The drafts' resolved wording, which no source line contains.
        const accepted_marker = try std.mem.concat(a, u8, &.{ " from ", filename.value });
        try std.testing.expect(std.mem.indexOf(u8, source, accepted_marker) == null);
        for (std.meta.tags(spec.Applicability)) |disposition| {
            current.units[2].?.response.content.entities = .{ .disposition = disposition, .basis = accepted };
            const before = try json.encode(@TypeOf(current.units), a, current.units);
            for ([_]?[]const u8{ null, try descriptions.recordTask(a, &packet_guidance.marked, .functional_requirement, .text) }, &first_bodies) |task, *first_body| {
                const packet = try sessions.packetForOptions(std.testing.allocator, current, fixture.context, sessions.records_index, .{ .presentation = if (task) |value| .{ .task = value } else .{ .authoring = &packet_guidance.marked } });
                defer packets.release(packet);
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                try std.testing.expect(!body.contains("brief"));
                try std.testing.expect(!body.contains("entities"));
                try std.testing.expect(std.mem.indexOf(u8, packet.body(), accepted_marker) == null);
                if (first_body.*) |bytes| try std.testing.expectEqualStrings(bytes, packet.body()) else first_body.* = try a.dupe(u8, packet.body());
                try std.testing.expectEqualStrings(fixture.context.inputs.corpus.sources[0].bytes, body.get("sources").?.array.items[0].object.get("text").?.string);
                try std.testing.expectEqualStrings(token.content.preserved_token.value.raw_value.bytes, body.get("exact_texts").?.array.items[0].object.get("value").?.string);
                // ADR 0043: the model sees only the exact-text names.
                try std.testing.expect(std.mem.indexOf(u8, packet.body(), "preserved_token") == null);
                const selected = try schema.restrict(a, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
                defer selected.release();
                const selected_bytes = selected.selected().modelBytes();
                inline for (comptime std.meta.tags(spec.Kind)) |kind| {
                    const permitted = kind != .entity;
                    try std.testing.expectEqual(permitted, std.mem.indexOf(u8, selected_bytes, "\"const\":\"" ++ @tagName(kind) ++ "\"") != null);
                    if (task == null) try std.testing.expectEqual(permitted, std.mem.indexOf(u8, body.get("source_assignment").?.object.get("purpose").?.string, descriptions.recordFamily(&packet_guidance.marked, kind)) != null);
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
    for (body.get("exact_texts").?.array.items) |token| {
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
    const packet = try @import("domain/specification_session.zig").packet(allocator, current, context, &packet_guidance.marked);
    defer @import("domain/model_input_packet.zig").release(packet);
}

/// A session whose brief is admitted, so the story is the next unit.
fn sessionAtStory(a: std.mem.Allocator, fixture: *const Fixture) !@import("domain/specification_session.zig").Session {
    const sessions = @import("domain/specification_session.zig");
    const short = try fixture.proposal("Short brief text");
    const current = try appendMockResponse(a, (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready, fixture.context, .{ .content = .{ .brief = .{ .description = short, .primary_goal = short } } });
    try std.testing.expectEqual(sessions.story_index, current.completed);
    return current;
}

/// The value's text with each exact copy in code delimiters, as its source wrote it.
fn quotedText(a: std.mem.Allocator, context: provenance.Context, value: spec.BusinessValue) !struct { text: []const u8, exact: usize } {
    var bytes: std.ArrayList(u8) = .empty;
    var exact: usize = 0;
    for (value.segments) |segment| switch (segment) {
        .literal => |literal| try bytes.appendSlice(a, literal.value),
        .exact_copy => |copy| {
            exact += 1;
            const token = try @import("domain/reference_support.zig").exact(@import("domain/reference_support.zig").records(context.references).items, copy.claim_id);
            try bytes.print(a, "`{s}`", .{token.value.raw_value.bytes});
        },
        .passive => return error.UnexpectedPassiveSegment,
    };
    return .{ .text = bytes.items, .exact = exact };
}

const compose_story: @import("actions/specification/compose_specification_story.zig").Action = .{ .validator = text.validator };

test "the engine composes the story from its catalogue's business claims in source order" {
    const story = @import("domain/specification_story.zig");
    const sessions = @import("domain/specification_session.zig");
    const r = @import("domain/reference_reconciliation.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Both development cases' sources and an unrelated domain. Headings are skipped,
    // list markers (`- `, `1) `, `+ `) removed and quotes joined by one space.
    const cases = [_]struct { source: []const u8, story: []const u8, exact: usize, groups: usize }{
        .{
            .source = "# Library Loan Renewal\n\n## Requirements\n\n- A borrower must be able to renew an active loan that has not previously been renewed.\n- Successful renewal must extend the existing due date by fourteen calendar days.\n- After successful renewal, display `Loan renewed!` and the new due date to the borrower.\n- A loan may be renewed only once.\n- Refuse renewal if the loan is inactive or has previously been renewed; leave its due date unchanged and display `Renewal refused.`.\n",
            .story = "A borrower must be able to renew an active loan that has not previously been renewed. Successful renewal must extend the existing due date by fourteen calendar days. After successful renewal, display `Loan renewed!` and the new due date to the borrower. A loan may be renewed only once. Refuse renewal if the loan is inactive or has previously been renewed; leave its due date unchanged and display `Renewal refused.`.",
            .exact = 2,
            .groups = 5,
        },
        .{
            .source = "# Hello World Application\n\n## Requirements\n\n- The application must start successfully.\n- When started, the application must display `Hello, World!`.\n- Must also output date and time in UTC\n",
            .story = "The application must start successfully. When started, the application must display `Hello, World!`. Must also output date and time in UTC",
            .exact = 1,
            .groups = 3,
        },
        .{
            .source = "# Greenhouse Irrigation\n\n1) The controller must open valve `V-12` when soil moisture falls below thirty percent.\n2) Operators must be able to pause irrigation.\n\n+ Pausing must not close an open valve.\n",
            .story = "The controller must open valve `V-12` when soil moisture falls below thirty percent. Operators must be able to pause irrigation. Pausing must not close an open valve.",
            .exact = 1,
            .groups = 3,
        },
    };
    for (cases) |case| {
        var fixture = try Fixture.init(a, case.source);
        defer fixture.deinit();
        const current = try sessionAtStory(a, &fixture);
        const composed = (try story.compose(a, current, fixture.context)).story;
        // The story selects only the groups whose business claims it quotes: one
        // group per list item here, and none for the heading or an exact value.
        const records = @import("domain/reference_support.zig").records(fixture.context.references);
        try std.testing.expectEqual(case.groups, composed.source_group_ids.len);
        for (composed.source_group_ids) |id| for (records.signals) |signal| if (signal.id.ordinal == id.ordinal) for (signal.value.claim_ids) |claim| {
            const content = (try r.item(records.items, claim)).claim.content;
            try std.testing.expect(content == .model and content.model == .business);
            try std.testing.expect(!std.mem.startsWith(u8, content.model.business.value.segments[0].literal.value, "#"));
        };
        const next = (try compose_story.execute(a, current, fixture.context)).composed;
        try std.testing.expectEqual(sessions.entities_index, next.completed);
        const admitted = next.units[sessions.story_index].?.response.content.primary_user_story;
        const flattened = try quotedText(a, fixture.context, admitted.value);
        try std.testing.expectEqualStrings(case.story, flattened.text);
        try std.testing.expectEqual(case.exact, flattened.exact);
        // The admitted value holds the same groups the composer selected.
        try std.testing.expectEqualDeep(composed.source_group_ids, admitted.source_group_ids);
    }
}

test "the composed story skips heading and technical claims and blocks without a business claim" {
    const story = @import("domain/specification_story.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A business claim and a technical claim cite the same lines, so both stay claims;
    // each quotes the heading and every list item as separate claims (ADR 0038).
    {
        var fixture = try Fixture.initContentKinds(a, "# Kiosk Greeting\n\n- The kiosk must greet each visitor.\n- The kiosk must show the time.\n", null, true, 2, true);
        defer fixture.deinit();
        const current = try sessionAtStory(a, &fixture);
        const next = (try compose_story.execute(a, current, fixture.context)).composed;
        const admitted = next.units[@import("domain/specification_session.zig").story_index].?.response.content.primary_user_story;
        try std.testing.expectEqualStrings("The kiosk must greet each visitor. The kiosk must show the time.", (try quotedText(a, fixture.context, admitted.value)).text);
        // Only the list items' business groups are selected.
        try std.testing.expectEqual(@as(usize, 2), admitted.source_group_ids.len);
    }
    // A technical claim, or a business claim that is only a heading, gives the
    // story nothing to quote: the unit blocks with its typed rejection.
    for ([_]struct { source: []const u8, category: @import("domain/reference_extraction.zig").Kind }{
        .{ .source = "Store loans in a relational database.\n", .category = .technical },
        .{ .source = "# Loan Renewal\n", .category = .business },
    }) |case| {
        var fixture = try Fixture.initClaims(a, case.source, null, .{ .selected = &.{.{ .category = case.category, .citations = &.{.{ .ordinal = 1 }} }} });
        defer fixture.deinit();
        const current = try sessionAtStory(a, &fixture);
        const rejection = (try story.compose(a, current, fixture.context)).blocked;
        try std.testing.expectEqual(.no_story_requirements, rejection.reason);
        try std.testing.expectEqualDeep(try @import("domain/specification_source_binding.zig").catalogue(a, @import("domain/reference_support.zig").records(fixture.context.references), .content), rejection.eligible_signals);
        try std.testing.expectEqual(.no_story_requirements, (try compose_story.execute(a, current, fixture.context)).blocked.reason);
    }
    // Each quote is one paragraph: a heading quoted with content, a wrapped list
    // item and lines cited apart keep their words, without headings or line breaks.
    for ([_]struct { source: []const u8, citations: []const []const u32, story: []const u8 }{
        .{
            .source = "## Renewal\nA borrower must be able to renew an active loan.\n- Refuse renewal if the loan is inactive;\n  leave its due date unchanged.\n",
            .citations = &.{ &.{ 1, 2 }, &.{ 3, 4 } },
            .story = "A borrower must be able to renew an active loan. Refuse renewal if the loan is inactive; leave its due date unchanged.",
        },
        .{
            .source = "- A loan may be renewed once.\nA note.\n- Show the new due date.\n",
            .citations = &.{&.{ 1, 3 }},
            .story = "A loan may be renewed once. Show the new due date.",
        },
        // A wrapped number is wording, not a list item, so the story keeps every word:
        // in an item, an indented continuation and a plain paragraph.
        .{
            .source = "- The fee is waived for loans opened in\n2024. Other loans pay the fee.\n",
            .citations = &.{&.{ 1, 2 }},
            .story = "The fee is waived for loans opened in 2024. Other loans pay the fee.",
        },
        .{
            .source = "- Renew loans opened in\n  2024. Others wait.\n",
            .citations = &.{&.{ 1, 2 }},
            .story = "Renew loans opened in 2024. Others wait.",
        },
        .{
            .source = "Renew the loan within\n3) days of the notice.\n",
            .citations = &.{&.{ 1, 2 }},
            .story = "Renew the loan within 3) days of the notice.",
        },
        // A comment line is not a list item, so its marker stays wording.
        .{
            .source = "<!--\n- Renewals stay open.\n-->\n",
            .citations = &.{&.{2}},
            .story = "- Renewals stay open.",
        },
        // Lines cited apart in one paragraph keep the quote's ellipsis between them.
        .{
            .source = "Renew active loans.\nA note.\nShow the new due date.\n",
            .citations = &.{&.{ 1, 3 }},
            .story = "Renew active loans. … Show the new due date.",
        },
    }) |case| {
        var proposals: std.ArrayList(@import("domain/reference_extraction.zig").Proposal) = .empty;
        for (case.citations) |lines| {
            var ids: std.ArrayList(@import("domain/source_selections.zig").Id) = .empty;
            for (lines) |line| try ids.append(a, .{ .ordinal = line });
            try proposals.append(a, .{ .category = .business, .citations = ids.items });
        }
        var fixture = try Fixture.initClaims(a, case.source, null, .{ .selected = proposals.items });
        defer fixture.deinit();
        const current = try sessionAtStory(a, &fixture);
        const next = (try compose_story.execute(a, current, fixture.context)).composed;
        const admitted = next.units[@import("domain/specification_session.zig").story_index].?.response.content.primary_user_story;
        try std.testing.expectEqualStrings(case.story, (try quotedText(a, fixture.context, admitted.value)).text);
    }
    // The source reader's line structure decides headings, not the quoted bytes: a
    // fenced line that starts with `#` is code, so its words stay as text.
    {
        var fixture = try Fixture.initClaims(a, "```\n# set the flag\n```\n", .code_sample, .{ .selected = &.{.{ .category = .business, .citations = &.{.{ .ordinal = 2 }} }} });
        defer fixture.deinit();
        const composed = (try story.compose(a, try sessionAtStory(a, &fixture), fixture.context)).story;
        try std.testing.expectEqualStrings("# set the flag", (try quotedText(a, fixture.context, composed.value)).text);
    }
    // The story is composed only as the session's current unit.
    {
        var fixture = try Fixture.init(a, "The kiosk must greet each visitor.\n");
        defer fixture.deinit();
        const current = (try @import("domain/specification_session.zig").initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        try std.testing.expectError(error.InvalidSpecificationUnit, story.compose(a, current, fixture.context));
    }
}

test "the registered story composition advances the session or replaces it with its typed rejection" {
    const values = @import("application/pipeline_values.zig");
    const native = @import("application/specification_workflow.zig");
    const owned = @import("application/specification_values.zig").storage;
    const reference_owned = @import("domain/reference_candidate_value.zig");
    const sources = @import("application/reference_evidence_workflow.zig");
    const accounted = @import("application/reference_reconciliation_workflow.zig").accounted_schema;
    const passive_schema = @import("application/passive_literal_workflow.zig").registry_schema;
    const toolchain_schema = @import("application/toolchain_workflow_values.zig").valid;
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { source: []const u8, category: @import("domain/reference_extraction.zig").Kind }{
        .{ .source = "The kiosk must greet each visitor.\n", .category = .business },
        .{ .source = "Store loans in a relational database.\n", .category = .technical },
    }) |case| {
        var fixture = try Fixture.initClaims(a, case.source, null, .{ .selected = &.{.{ .category = case.category, .citations = &.{.{ .ordinal = 1 }} }} });
        var transferred = false;
        defer if (!transferred) fixture.deinit();
        const current = try sessionAtStory(a, &fixture);
        const toolchain = try values.adopt(std.testing.allocator, toolchain_schema, text.safety.ValidToolchain, text.safety.Owner, fixture.passive.owner, text.safety.value, text.safety.deinitOwner, text.safety.retainedBytes(fixture.passive.owner));
        transferred = true;
        defer values.destroy(toolchain);
        const passive = try values.create(std.testing.allocator, passive_schema, @import("domain/passive_literals.zig").Registry, fixture.context.registry);
        defer values.destroy(passive);
        const source_value = try values.create(std.testing.allocator, sources.inputs_schema, @import("domain/reference_evidence.zig").Inputs, fixture.context.inputs);
        defer values.destroy(source_value);
        const reference_value = value: {
            const owner = try reference_owned.create(std.testing.allocator, null);
            errdefer reference_owned.destroy(owner);
            owner.payload = .{ .reconciliation_accounted = fixture.context.references };
            break :value try values.adopt(std.testing.allocator, accounted, reference_owned.Value, reference_owned.Owner, owner, reference_owned.view, reference_owned.destroy, null);
        };
        defer values.destroy(reference_value);
        const session_value = value: {
            const owner = try owned.create(std.testing.allocator, .{});
            errdefer owned.destroy(owner);
            owner.payload = .{ .session = current };
            break :value try values.adopt(std.testing.allocator, native.session_schema, owned.Value, owned.Owner, owner, owned.view, owned.destroy, null);
        };
        defer values.destroy(session_value);
        var view: @import("domain/pipeline_data.zig").View = .{};
        view.slots[@intFromEnum(sources.inputs_schema.key)] = source_value;
        view.slots[@intFromEnum(accounted.key)] = reference_value;
        view.slots[@intFromEnum(passive_schema.key)] = passive;
        view.slots[@intFromEnum(toolchain_schema.key)] = toolchain;
        view.slots[@intFromEnum(native.session_schema.key)] = session_value;
        var binding: native.ComposeStory = .{ .allocator = std.testing.allocator, .action = compose_story };
        const result = try native.ComposeStory.invoke(&binding, try projectionOperationInput(native.ComposeStory, view));
        const replaced = result.delta.data_replacements[@intFromEnum(native.session_schema.key)] orelse return error.ExpectedSessionReplacement;
        defer values.destroy(replaced);
        var output: @import("domain/pipeline_data.zig").View = .{};
        output.slots[@intFromEnum(native.session_schema.key)] = replaced;
        if (case.category == .business) {
            try std.testing.expectEqual(.ok, result.outcome);
            const next = try native.readSession(&output);
            try std.testing.expectEqual(sessions.entities_index, next.completed);
            const before = try sessions.iterationProgress(current);
            try std.testing.expectEqualDeep(@as(?@import("domain/workflow_iteration.zig").Transition, .{ .limit = before.limit, .before = before.position, .after = before.position + 1 }), result.iteration);
        } else {
            try std.testing.expectEqual(.blocked, result.outcome);
            try std.testing.expect(result.iteration == null);
            const diagnostic = (try @import("application/candidate_validation_diagnostics.zig").read(&output)) orelse return error.ExpectedStoryRejection;
            try std.testing.expectEqual(.no_story_requirements, diagnostic.source_catalogue.reason);
        }
    }
}

test "a source's title heading is its first level-1 heading with text, outside code, HTML and containers" {
    const markdown = @import("domain/markdown_code_spans.zig");
    for ([_]struct { source: []const u8, title: ?[]const u8 }{
        .{ .source = "# Loan renewal\n", .title = "Loan renewal" },
        .{ .source = "   # Indented heading\n", .title = "Indented heading" },
        .{ .source = "#\tTabbed\n", .title = "Tabbed" },
        .{ .source = "# Room booking ##  \n", .title = "Room booking" },
        // A closing `#` with no space or tab before it is text, as an escaped one is.
        .{ .source = "# C#\n", .title = "C#" },
        .{ .source = "# Notes \\#\n", .title = "Notes \\#" },
        .{ .source = "# Loan renewal\r\nRenew the loan.\r\n", .title = "Loan renewal" },
        // A heading with no text and a level-2 heading are passed over.
        .{ .source = "# #\n# Parking\n", .title = "Parking" },
        .{ .source = "## Overview\n# Parking\n", .title = "Parking" },
        // Setext: a paragraph underlined with `=` that opens at a top-level boundary.
        .{ .source = "Loan renewal\n===\n", .title = "Loan renewal" },
        .{ .source = "Loan\n  renewal  \n=\n", .title = "Loan\nrenewal" },
        .{ .source = "Overview\n---\nLoan renewal\n===\n", .title = "Loan renewal" },
        .{ .source = "```\ncode\n```\nLoan renewal\n===\n", .title = "Loan renewal" },
        .{ .source = "<!-- note -->\nLoan renewal\n===\n", .title = "Loan renewal" },
        .{ .source = "- note\n\nLoan renewal\n===\n", .title = "Loan renewal" },
        .{ .source = "  <div>\n\nLoan renewal\n===\n", .title = "Loan renewal" },
        // A byte-order mark is no part of the first line.
        .{ .source = "\xef\xbb\xbf# Loan renewal\n", .title = "Loan renewal" },
        // Rejected: no heading, code, HTML, a list item, a quote or a bare marker.
        .{ .source = "Renew the loan.\n", .title = null },
        .{ .source = "#5 bolt\n", .title = null },
        .{ .source = "    # Indented code\n", .title = null },
        .{ .source = "```\n# Not a title\n```\n", .title = null },
        .{ .source = "<!--\n# Not a title\n-->\n", .title = null },
        .{ .source = "<div>\nLoan renewal\n===\n</div>\n", .title = null },
        .{ .source = "  <div>\nLoan renewal\n===\n", .title = null },
        .{ .source = "- # Item heading\n", .title = null },
        .{ .source = "> # Quoted heading\n", .title = null },
        .{ .source = "- Renew the loan.\nLoan renewal\n===\n", .title = null },
        .{ .source = "> Renew the loan.\nLoan renewal\n===\n", .title = null },
        .{ .source = "    Indented code\n===\n", .title = null },
        .{ .source = "===\n", .title = null },
    }) |case| {
        const found = try markdown.levelOneHeading(std.testing.allocator, case.source);
        defer if (found) |bytes| std.testing.allocator.free(bytes);
        if (case.title) |expected| try std.testing.expectEqualStrings(expected, found orelse return error.MissingTitleHeading) else try std.testing.expect(found == null);
    }
}

test "the session takes its title from the sources' level-1 heading, or blocks before generation" {
    const sessions = @import("domain/specification_session.zig");
    const title = @import("domain/specification_title.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Both development cases' titles are their sources' headings as written.
    for ([_]struct { path: []const u8, title: []const u8 }{
        .{ .path = "test/e2e/wf-001-hello-world/reference/stories.md", .title = "Hello World Application" },
        .{ .path = "test/e2e/wf-002-loan-renewal/stories.md", .title = "Library Loan Renewal" },
    }) |case| {
        const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, case.path, a, .limited(1024 * 1024));
        var ids: evidence.IdSource = .{};
        const inputs = try evidence.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "stories.md", bytes));
        try std.testing.expectEqualDeep(title.Derivation{ .title = .{ .bytes = case.title } }, try title.derive(a, inputs));
    }
    // Accepted: an ATX or Setext heading, and an unrelated domain.
    for ([_]struct { source: []const u8, title: []const u8 }{
        .{ .source = "# Kiosk Greeting\n\nThe kiosk must greet each visitor.\n", .title = "Kiosk Greeting" },
        .{ .source = "Greenhouse watering\n===================\n\nWater each bed at dawn.\n", .title = "Greenhouse watering" },
    }) |case| {
        var fixture = try Fixture.initAsWritten(a, case.source);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
        try std.testing.expectEqualStrings(case.title, current.title.bytes);
    }
    // Rejected: no level-1 heading, only an empty one, a level-2 heading or a fenced `#`
    // line. The engine read the sources, so the block has no origin, issue or group.
    for ([_][]const u8{
        "The kiosk must greet each visitor.\n",
        "#\n\nThe kiosk must greet each visitor.\n",
        "## Greeting\n\nThe kiosk must greet each visitor.\n",
        "```\n# greet\n```\n\nThe kiosk must greet each visitor.\n",
    }) |source| {
        var fixture = try Fixture.initAsWritten(a, source);
        defer fixture.deinit();
        const rejection = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).blocked;
        try std.testing.expectEqual(.no_title_heading, rejection.reason);
        try std.testing.expect(rejection.origin == null and rejection.issue == null and rejection.eligible_signals.len == 0);
        // The retained diagnostic keeps the block, and decoding refuses an unpaired one.
        const Diagnostic = @import("domain/candidate_validation_diagnostic.zig").Diagnostic;
        try std.testing.expectEqual(.candidate, (Diagnostic{ .source_catalogue = rejection }).attribution());
        try std.testing.expectEqualDeep(Diagnostic{ .source_catalogue = rejection }, try (Diagnostic{ .source_catalogue = rejection }).copy(a));
        var attributed = rejection;
        attributed.origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
        var grouped = rejection;
        grouped.eligible_signals = try @import("domain/specification_source_binding.zig").catalogue(a, @import("domain/reference_support.zig").records(fixture.context.references), .content);
        for ([_]@import("domain/specification_source_binding.zig").Rejection{ attributed, grouped }) |bad| {
            try std.testing.expect(!bad.valid());
            try std.testing.expectError(error.InvalidJsonDocument, (Diagnostic{ .source_catalogue = bad }).copy(a));
        }
    }
}

test "peer sources agree on one title heading or the corpus blocks" {
    const title = @import("domain/specification_title.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { sources: []const []const u8, derived: title.Derivation }{
        // One source has a level-1 heading and another has none.
        .{ .sources = &.{ "Issue a receipt.\n", "# Loan renewal\nRenew the loan.\n" }, .derived = .{ .title = .{ .bytes = "Loan renewal" } } },
        // Two sources with the same heading text, written ATX and Setext.
        .{ .sources = &.{ "# Loan renewal\nRenew the loan.\n", "Loan renewal\n============\nIssue a receipt.\n" }, .derived = .{ .title = .{ .bytes = "Loan renewal" } } },
        // Different headings block in either order; only each source's first counts.
        .{ .sources = &.{ "# Loan renewal\nRenew the loan.\n", "# Receipts\nIssue a receipt.\n" }, .derived = .{ .gap = .conflicting_title_headings } },
        .{ .sources = &.{ "# Receipts\nIssue a receipt.\n", "# Loan renewal\nRenew the loan.\n" }, .derived = .{ .gap = .conflicting_title_headings } },
        .{ .sources = &.{ "# Loan renewal\n", "# Receipts\n\n# Loan renewal\n" }, .derived = .{ .gap = .conflicting_title_headings } },
        // The engine doesn't judge wording: a different case is a different heading.
        .{ .sources = &.{ "# Loan renewal\n", "# Loan Renewal\n" }, .derived = .{ .gap = .conflicting_title_headings } },
        .{ .sources = &.{ "Issue a receipt.\n", "## Renewal\nRenew the loan.\n" }, .derived = .{ .gap = .no_title_heading } },
    }) |case| {
        var ids: evidence.IdSource = .{};
        const inputs = try evidence.prepare(a, &ids, try @import("reference_ingestion_test.zig").readSources(std.testing.io, a, case.sources));
        try std.testing.expectEqualDeep(case.derived, try title.derive(a, inputs));
        // Readback admits only the title the captured sources yield.
        switch (case.derived) {
            .title => |value| {
                try title.validateStored(a, inputs, value);
                try std.testing.expectError(error.InvalidSpecification, title.validateStored(a, inputs, .{ .bytes = "Loan Renewal" }));
            },
            .gap => try std.testing.expectError(error.InvalidSpecification, title.validateStored(a, inputs, .{ .bytes = "Loan renewal" })),
        }
    }
}

test "a heading claim that only the title once selected leaves its group unmapped" {
    const repair = @import("domain/specification_coverage_repair.zig");
    const check = @import("actions/specification/validate_specification_coverage.zig").Action{ .validator = text.validator };
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // ADR 0048: the title selects no group. The heading's claim is the second group's only
    // claim; no narrative field selects that group and no record names it (ADR 0038).
    const claims = [_]@import("domain/reference_extraction.zig").Proposal{
        .{ .category = .business, .citations = &.{.{ .ordinal = 1 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 2 }} },
    };
    var fixture = try Fixture.initClaims(a, "A borrower renews a loan.\n# Loan renewal\n", null, .{ .selected = &claims });
    defer fixture.deinit();
    const renewed = try fixture.proposalGroup("The loan is renewed.", 0);
    const batch = [_]spec.Model.RecordProposal{
        authoredRecord(.{ .functional_requirement = .{ .text = renewed.value } }, renewed),
        authoredRecord(.{ .acceptance_criterion = .{ .given = renewed.value, .when = renewed.value, .then = renewed.value } }, renewed),
    };
    const current = try sessionWithBatches(a, &fixture, &.{ &batch, &.{} });
    try std.testing.expectEqualStrings("Loan renewal", current.title.bytes);
    const content = (try sessions.assemble(a, text.validator, fixture.context, current, &.{})).content;
    try std.testing.expectEqualDeep(current.title, content.display_name);
    const rejection = (try check.execute(a, current, fixture.context, content)).invalid;
    try std.testing.expect(rejection.issue == .missing_business_mapping);
    try std.testing.expectEqualDeep(fixture.context.references.records.signals[1].value.claim_ids[0], rejection.claim_id);
    try std.testing.expectEqual(.no_independent_supported_target, (try repair.authorize(a, current, fixture.context, content, rejection)).blocked.blocked.?);
}

test "a composed story that fails unit validation blocks with its issue and is never repaired" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The only business claim quotes a code span alone: the story has no prose.
    // Distinct overlapping exact values leave a bare quote ambiguous.
    for ([_]struct { source: []const u8, reason: @FieldType(@import("domain/typed_text.zig").Issue, "reason") }{
        .{ .source = "`Ready.`\n", .reason = .reference_only },
        .{ .source = "Display `ACTIVE` or the distinct value `ACTIVE VALUE`.\n\nThe panel shows ACTIVE VALUE.\n", .reason = .ambiguous_exact },
    }) |case| {
        var fixture = try Fixture.init(a, case.source);
        defer fixture.deinit();
        const current = try sessionAtStory(a, &fixture);
        const rejection = (try compose_story.execute(a, current, fixture.context)).blocked;
        try std.testing.expectEqual(.story_not_admissible, rejection.reason);
        const issue = rejection.issue orelse return error.MissingStoryIssue;
        try std.testing.expectEqual(g.Unit.primary_user_story, issue.unit);
        try std.testing.expectEqual(case.reason, issue.text_issue.?.reason);
        try std.testing.expectEqualDeep(try @import("domain/specification_source_binding.zig").catalogue(a, @import("domain/reference_support.zig").records(fixture.context.references), .content), rejection.eligible_signals);
        // The engine produced the story, so the block is the candidate's, not a
        // model response's, and survives the retained diagnostic's readback.
        const Diagnostic = @import("domain/candidate_validation_diagnostic.zig").Diagnostic;
        try std.testing.expect(rejection.origin == null);
        const diagnostic: Diagnostic = .{ .source_catalogue = rejection };
        try std.testing.expectEqual(.candidate, diagnostic.attribution());
        try std.testing.expectEqualDeep(diagnostic, try diagnostic.copy(a));
        // Readback rejects an unpaired reason and issue, or a story block with an origin.
        var missing = rejection;
        missing.issue = null;
        var foreign = rejection;
        foreign.reason = .no_record_authoring_groups;
        var attributed = rejection;
        attributed.origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
        var unadmitted = rejection;
        unadmitted.reason = .no_story_requirements;
        for ([_]@import("domain/specification_source_binding.zig").Rejection{ missing, foreign, attributed, unadmitted }) |bad| {
            try std.testing.expect(!bad.valid());
            try std.testing.expectError(error.InvalidJsonDocument, (Diagnostic{ .source_catalogue = bad }).copy(a));
        }
        unadmitted.issue = null;
        try std.testing.expectEqualDeep(Diagnostic{ .source_catalogue = unadmitted }, try (Diagnostic{ .source_catalogue = unadmitted }).copy(a));
        // An operational failure stays an error, never a blocked story.
        try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(storyAllocationCase, .{ current, fixture.context });
    }
}
fn storyAllocationCase(allocator: std.mem.Allocator, current: @import("domain/specification_session.zig").Session, context: provenance.Context) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const outcome = try compose_story.execute(arena.allocator(), current, context);
    try std.testing.expectEqual(.story_not_admissible, outcome.blocked.reason);
}

test "no repair targets the engine-composed story" {
    const repair = @import("domain/specification_repair.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "The kiosk must greet each visitor.\n");
    defer fixture.deinit();
    const current = try sessionAtStory(a, &fixture);
    var bad = try fixture.proposal("The kiosk greets each visitor.");
    bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    const candidate: repair.Candidate = .{ .response = .{ .content = .{ .primary_user_story = bad } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked));
}

test "the only record naming a claim is kept when it equals the composed story" {
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "The kiosk must greet each visitor.\n");
    defer fixture.deinit();
    var current = (try compose_story.execute(a, try sessionAtStory(a, &fixture), fixture.context)).composed;
    current = try appendMockResponse(a, current, fixture.context, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = try fixture.proposal("No entities.") } } });
    const story = current.units[sessions.story_index].?.response.content.primary_user_story;
    const bound = (try sessions.currentBinding(a, current, fixture.context)).records;
    const restated: spec.Model.RecordProposal = .{ .content = .{ .assumption = .{ .text = story.value } }, .source_group_ids = &.{bound.signal}, .provenance = bound.selection };
    // The batch's only record equals the story; deleting it would leave its claim
    // without a record, so ADR 0035 keeps it (ADR 0047).
    const kept = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &.{restated} } } })).valid;
    try std.testing.expectEqual(@as(usize, 1), kept.response.content.records.len);
    // When another record names the same claim, the restatement is still deleted.
    const requirement: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = (try fixture.proposal("The kiosk greets each visitor.")).value } }, .source_group_ids = &.{bound.signal}, .provenance = bound.selection };
    const rejection = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &.{ requirement, restated } } } })).invalid;
    try std.testing.expectEqual(.restatement, rejection.issue.rule);
    try std.testing.expectEqualDeep(@as(@import("domain/specification_candidate.zig").Target, .{ .record = 1 }), rejection.issue.field.target);
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
        const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = value, .records = &.{}, .entities = .{ .disposition = .not_applicable, .basis = value } }, .{}, &.{})).content;
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
                const packet = try sessions.packet(std.testing.allocator, current, context, &packet_guidance.marked);
                defer packets.release(packet);
                const repair = @import("domain/specification_repair.zig");
                var bad = proposal;
                bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
                const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = proposal } } } };
                const rejection = (try validate_unit.execute(a, current, context, candidate)).invalid;
                const authorization = try repair.authorize(a, current, context, candidate, rejection, &packet_guidance.marked);
                const repair_packet = try repair.packet(std.testing.allocator, current, context, authorization, &packet_guidance.marked);
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
                try std.testing.expectError(error.InvalidSpecificationBinding, sessions.packet(std.testing.allocator, current, context, &packet_guidance.marked));
            } else {
                // A question can still select retained source groups when no
                // group is eligible to establish business content.
                const packet = try sessions.packet(std.testing.allocator, current, context, &packet_guidance.marked);
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
            const accounted = try coverage.validate(a, context.references, .{ .description = value, .primary_goal = value }, content);
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
        var fixture = try Fixture.initContent(a, source, null, true, 2);
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
            .{ .category = .business, .citations = &.{.{ .ordinal = 1 }} },
            .{ .category = .open_question, .citations = &.{.{ .ordinal = 2 }} },
        };
        var fixture = try Fixture.initClaims(a, try std.fmt.allocPrint(a, "{s}\n{s}\n", .{ case.behavior, case.question }), null, .{ .selected = &claims });
        defer fixture.deinit();
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const packet = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
        defer @import("domain/model_input_packet.zig").release(packet);
        const selected = try schema.restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer selected.release();
        const good = try fixture.proposal(case.behavior);
        const response: g.Response = .{ .content = .{ .brief = .{ .description = good, .primary_goal = good } } };
        try checkDocument(selected.selected().modelBytes(), .{ .bytes = try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)) });
        var wrong = response;
        wrong.content.brief.description.source_group_ids = &.{fixture.context.references.records.signals[1].id};
        wrong.content.brief.description.provenance.claim_ids = &.{.{ .ordinal = 2 }};
        const wrong_wire = try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, wrong));
        try checkDocument(selected.selected().modelBytes(), .{ .bytes = wrong_wire, .rejection = .enum_mismatch, .path = "/description/signal_ids/0" });
        const bound = try sessions.currentBinding(a, current, fixture.context);
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, wrong_wire, bound));
        try std.testing.expectEqual(.provenance, (try g.validate(a, text.validator, fixture.context, .brief, wrong)).invalid.rule);
        var question = good;
        question.value = .{ .segments = &.{.{ .literal = .{ .value = case.question } }} };
        question.source_group_ids = wrong.content.brief.description.source_group_ids;
        question.provenance.claim_ids = wrong.content.brief.description.provenance.claim_ids;
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
        var fixture = try Fixture.initContent(a, case.source, .business_exact_string, true, 3);
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
        var fixture = try Fixture.initClaims(a, prose, null, .{ .selected = &.{.{ .category = kind, .citations = &.{.{ .ordinal = 1 }} }} });
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
        // A record catalogue gap stays attributed to the reconciliation signals response.
        try std.testing.expectEqualDeep(token_only.records.assignments.checked.prior.prior.source.at(.signals, .record), rejected.origin);
        try std.testing.expect(rejected.valid() and rejected.issue == null);
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
    const compose_action: @import("actions/specification/compose_specification_story.zig").Action = .{ .validator = text.validator };
    var begin: native.Initialize = .{ .allocator = a };
    var advance: native.Advance = .{ .allocator = a };
    var compose: native.ComposeStory = .{ .allocator = a, .action = compose_action };
    const begin_entry = @import("composition/native_workflow_operations.zig").entry(native.Initialize, &begin);
    const advance_entry = @import("composition/native_workflow_operations.zig").entry(native.Advance, &advance);
    const compose_entry = @import("composition/native_workflow_operations.zig").entry(native.ComposeStory, &compose);
    try std.testing.expect(iteration.validContract(begin_entry.contract, begin_entry.binding.capabilities()));
    try std.testing.expect(iteration.validContract(advance_entry.contract, advance_entry.binding.capabilities()));
    try std.testing.expect(iteration.validContract(compose_entry.contract, compose_entry.binding.capabilities()));
    try std.testing.expectEqualDeep(native.Initialize.iteration, begin_entry.contract.iteration.?);
    try std.testing.expectEqualDeep(native.Advance.iteration, advance_entry.contract.iteration.?);
    try std.testing.expectEqualDeep(native.ComposeStory.iteration, compose_entry.contract.iteration.?);
    for ([_]usize{ 1, 37 }) |groups| {
        var fixture = try Fixture.initContent(a, "MOCK Display the current status.", null, true, groups);
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
            const before = try sessions.iterationProgress(current);
            // ADR 0047: the engine composes the story; models author the other units.
            const next = if (unit == .primary_user_story) (try compose_action.execute(a, current, fixture.context)).composed else model: {
                const response: g.Response = .{ .content = switch (unit) {
                    .brief => .{ .brief = .{ .description = good, .primary_goal = good } },
                    .primary_user_story => unreachable,
                    .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
                    .records => .{ .records = &.{} },
                } };
                const checked = try sessions.admit(a, current, fixture.context, (try g.validate(a, text.validator, fixture.context, unit, response)).valid);
                break :model try advance_action.execute(a, current, checked);
            };
            const after = try sessions.iterationProgress(next);
            try std.testing.expectEqual(before.position + 1, after.position);
            const transition: iteration.Transition = .{ .limit = after.limit, .before = before.position, .after = after.position };
            const accepted = try state.prepare(if (unit == .primary_user_story) native.ComposeStory.iteration else native.Advance.iteration, transition, 1, generation);
            generation += 1;
            try state.commit(accepted, generation);
            try std.testing.expectError(error.InvalidNativeIteration, state.prepare(native.Advance.iteration, transition, 1, generation));
            current = next;
        }
        try std.testing.expectEqual(initial.limit, (try sessions.iterationProgress(current)).position);
        try std.testing.expectEqual(groups, current.record_batches.len);
        // Generation is complete only with every mandatory record family. These
        // batches authored none, so the completed candidate is invalid.
        const progress: @import("actions/specification/check_specification_generation_progress.zig").Action = .{};
        try std.testing.expect(sessions.missingRequiredFamily(current));
        try std.testing.expectEqual(.invalid, progress.execute(current));
        var unfinished = current;
        unfinished.completed -= 1;
        try std.testing.expectEqual(.more, progress.execute(unfinished));
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
        const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = good } } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const issue = rejected.issue.text_issue.?;
        try std.testing.expectEqual(.invalid_scalar, issue.reason);
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization, &packet_guidance.marked);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const rule = body.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expectEqualStrings(issue.description(), rule.get("requirement").?.string);
        try std.testing.expectEqualDeep(issue, try json.decode(@import("domain/typed_text.zig").Issue, a, try std.json.Stringify.valueAlloc(a, rule.get("text_issue").?, .{})));
        const replacement: repair.Replacement = .{ .value = good.value };
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, try repair.parse(a, authorization, packet, try json.encodeSelected(repair.Replacement, a, replacement)), null);
        try std.testing.expectEqualDeep(bad.provenance, merged.response.content.brief.description.provenance);
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
            .source_group_ids = value.source_group_ids,
            .provenance = value.provenance,
        });
        // The edge case prints the Then of the criterion of its batch that shares its claims.
        const outcomes = [_]identifiers.Outcome{.{ .edge_case = @intFromEnum(spec.Kind.edge_case), .criterion = @intFromEnum(spec.Kind.acceptance_criterion) }};
        const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = value, .records = records.items, .entities = .{ .disposition = .required, .basis = value } }, .{}, &outcomes)).content;
        const document = try projection.project(a, fixture.context, test_directory, content);
        const bytes = try codec.render(a, document);
        try validate.execute(a, document, bytes);
        try std.testing.expectEqualDeep(document, try codec.parse(a, bytes));
        try std.testing.expectError(error.InvalidSpecification, validate.execute(a, document, try std.mem.concat(a, u8, &.{ bytes, "\n" })));
        var stale = fixture.context;
        stale.inputs.corpus.state_id.bytes = "foreign";
        try std.testing.expectError(error.InvalidSpecification, projection.project(a, stale, test_directory, content));
    }
}

test "record assignment resolves edge-case links to the IDs it allocates and refuses any other link" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "A guest books a meeting room for one hour.";
    var fixture = try Fixture.init(a, source);
    defer fixture.deinit();
    const value = try fixture.value(source);
    const Group = @typeInfo(@TypeOf(value.source_group_ids)).pointer.child;
    const first_batch = value.source_group_ids[0].ordinal;
    const second_batch = [_]Group{.{ .ordinal = first_batch + 1 }};
    const Record = struct {
        fn of(comptime kind: spec.Kind, attributed: spec.AttributedValue, groups: []const Group) spec.RecordProposal {
            return .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, attributed.value)), .source_group_ids = groups, .provenance = attributed.provenance };
        }
    };
    // Two batches, each with one criterion and one edge case sharing its claim.
    const records = [_]spec.RecordProposal{
        Record.of(.acceptance_criterion, value, value.source_group_ids),
        Record.of(.acceptance_criterion, value, &second_batch),
        Record.of(.edge_case, value, value.source_group_ids),
        Record.of(.edge_case, value, &second_batch),
    };
    // A prior ledger already past AC-004 and EC-002: the IDs come from allocation, not position.
    var prior: identifiers.Ledger = .{};
    prior.next[@intFromEnum(spec.Kind.acceptance_criterion)] = 5;
    prior.next[@intFromEnum(spec.Kind.edge_case)] = 3;
    const proposal: spec.ContentProposal = .{ .display_name = fixture_display_name, .primary_user_story = value, .records = &records, .entities = .{ .disposition = .required, .basis = value } };
    const assigned = try identifiers.assign(a, proposal, prior, &.{ .{ .edge_case = 3, .criterion = 1 }, .{ .edge_case = 2, .criterion = 0 } });
    const ids = [_]spec.Id{
        .{ .kind = .acceptance_criterion, .ordinal = 5 },
        .{ .kind = .acceptance_criterion, .ordinal = 6 },
        .{ .kind = .edge_case, .ordinal = 3 },
        .{ .kind = .edge_case, .ordinal = 4 },
    };
    for (assigned.content.records, ids) |record, id| try std.testing.expectEqualDeep(id, record.id);
    try std.testing.expect(assigned.content.records[0].outcome_of == null);
    try std.testing.expectEqualDeep(ids[0], assigned.content.records[2].outcome_of.?);
    try std.testing.expectEqualDeep(ids[1], assigned.content.records[3].outcome_of.?);
    for (assigned.content.records, 0..) |_, index| try std.testing.expect(@import("domain/scenario_link.zig").validStored(assigned.content.records, index));
    for ([_][]const identifiers.Outcome{
        // An edge case without a link.
        &.{.{ .edge_case = 2, .criterion = 0 }},
        // One edge case linked twice, the other not at all.
        &.{ .{ .edge_case = 2, .criterion = 0 }, .{ .edge_case = 2, .criterion = 0 } },
        // An index past the records.
        &.{ .{ .edge_case = 2, .criterion = 9 }, .{ .edge_case = 3, .criterion = 1 } },
        // A link from a record that is not an edge case.
        &.{ .{ .edge_case = 0, .criterion = 1 }, .{ .edge_case = 3, .criterion = 1 } },
        // Criteria of the other batch are not candidates.
        &.{ .{ .edge_case = 2, .criterion = 1 }, .{ .edge_case = 3, .criterion = 0 } },
    }) |outcomes| try std.testing.expectError(error.InvalidSpecification, identifiers.assign(a, proposal, prior, outcomes));
}

test "specification display resolves exact values without normalization and passive values as code" {
    const projection = @import("domain/specification_projection.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Show `Cafe\u{301}` and consult stories.md.");
    defer fixture.deinit();
    const packet = try @import("domain/specification_session.zig").packet(std.testing.allocator, (try @import("domain/specification_session.zig").initialize(a, .{ .bytes = "selected" }, fixture.context)).ready, fixture.context, &packet_guidance.marked);
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
        // A passive value keeps its code span inside quotes. An exact copy touching it
        // shares its span; quoted apart from it, the exact copy alone loses its span.
        const exact = for (items.entries) |item| {
            if (item.claim.content == .preserved_token) break item.claim.id;
        } else return error.MissingTestToken;
        value.provenance = try provenance.select(a, fixture.context, .{ .claim_ids = &.{ value.provenance.claim_ids[0], exact }, .clarification_response_ids = &.{} });
        const Expected = struct { segments: []const @import("domain/typed_text.zig").BusinessSegment, bytes: []const u8, spans: []const spec.CodeSpan };
        for ([_]Expected{
            .{ .segments = &.{ .{ .literal = .{ .value = "Consult \"" } }, .{ .passive = .{ .passive_literal_id = record.id } }, .{ .literal = .{ .value = "\" now." } } }, .bytes = "Consult \"stories.md\" now.", .spans = &.{.{ .start = 9, .end = 19 }} },
            .{ .segments = &.{ .{ .literal = .{ .value = "Show \"" } }, .{ .exact_copy = .{ .claim_id = exact } }, .{ .passive = .{ .passive_literal_id = record.id } }, .{ .literal = .{ .value = "\" now." } } }, .bytes = "Show \"Cafe\u{301}stories.md\" now.", .spans = &.{.{ .start = 6, .end = 22 }} },
            .{ .segments = &.{ .{ .literal = .{ .value = "Show \"" } }, .{ .exact_copy = .{ .claim_id = exact } }, .{ .literal = .{ .value = "\" and " } }, .{ .passive = .{ .passive_literal_id = record.id } }, .{ .literal = .{ .value = "." } } }, .bytes = "Show \"Cafe\u{301}\" and stories.md.", .spans = &.{.{ .start = 18, .end = 28 }} },
        }) |expected| {
            value.value = .{ .segments = expected.segments };
            const mixed = try projection.scalar(a, fixture.context, value);
            try std.testing.expectEqualStrings(expected.bytes, mixed.bytes);
            try std.testing.expectEqualSlices(spec.CodeSpan, expected.spans, mixed.code_spans);
        }
    }
    try std.testing.expectEqual(@as(usize, 1), passive_count);
}

test "an exact copy takes no delimiting pair from a neighbouring exact copy's bytes" {
    const projection = @import("domain/specification_projection.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Say `Hello ` then `\" x` now.");
    defer fixture.deinit();
    const items = try provenance.items(fixture.context);
    var hello: ?@import("domain/reference_reconciliation.zig").ClaimId = null;
    var quoted: ?@import("domain/reference_reconciliation.zig").ClaimId = null;
    for (items.entries) |item| {
        if (item.claim.content != .preserved_token) continue;
        const raw = item.claim.content.preserved_token.value.raw_value.bytes;
        if (std.mem.eql(u8, raw, "Hello ")) hello = item.claim.id;
        if (std.mem.eql(u8, raw, "\" x")) quoted = item.claim.id;
    }
    // The quote after `Hello ` is the second copy's first byte, not literal text, so
    // the first copy keeps its span and both share it.
    const value: spec.AttributedValue = .{
        .value = .{ .segments = &.{ .{ .literal = .{ .value = "say \"" } }, .{ .exact_copy = .{ .claim_id = hello.? } }, .{ .exact_copy = .{ .claim_id = quoted.? } }, .{ .literal = .{ .value = " now" } } } },
        .provenance = try provenance.select(a, fixture.context, .{ .claim_ids = &.{ hello.?, quoted.? }, .clarification_response_ids = &.{} }),
    };
    const projected = try projection.scalar(a, fixture.context, value);
    try std.testing.expectEqualStrings("say \"Hello \" x now", projected.bytes);
    try std.testing.expectEqualSlices(spec.CodeSpan, &.{.{ .start = 5, .end = 14 }}, projected.code_spans);
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
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, current, &.{}));
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            // The engine composes the story without a request (ADR 0047).
            if (unit == .primary_user_story) {
                try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked));
                current = (try compose_story.execute(a, current, fixture.context)).composed;
                continue;
            }
            const packet = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
            defer @import("domain/model_input_packet.zig").release(packet);
            try checkAuthoringPacket(a, packet.body());
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "principles") == null);
            const response: g.Response = .{
                .content = switch (unit) {
                    .brief => .{ .brief = .{ .description = value, .primary_goal = value } },
                    .primary_user_story => unreachable,
                    .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
                    .records => result: {
                        // ADR 0038: the requirement's claims need a scenario of the same batch.
                        const records = try a.dupe(spec.Model.RecordProposal, &.{
                            .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance },
                            .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance },
                        });
                        break :result .{ .records = records };
                    },
                },
            };
            current = try appendMockResponse(a, current, fixture.context, response);
        }
        const identified = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
        // ADR 0048: the display name is the session's title, taken from the sources.
        try std.testing.expectEqualDeep(current.title, identified.content.display_name);
        try std.testing.expectEqual(@as(usize, 2), identified.content.records.len);
        for (identified.content.records) |record| try std.testing.expect(std.meta.eql(record.id, spec.Id{ .kind = .functional_requirement, .ordinal = 1 }) or std.meta.eql(record.id, spec.Id{ .kind = .acceptance_criterion, .ordinal = 1 }));
        try std.testing.expectEqual(@as(usize, 0), first.completed);
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.append(current, current.units[0].?));
        var stale = fixture.context;
        stale.inputs.corpus.state_id.bytes = "changed";
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, stale, current, &.{}));
    }
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
    const brief: g.Response = .{ .content = .{ .brief = .{ .description = value, .primary_goal = value } } };
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
        // Six source lines, one claim each, in one group: each statement family states
        // its own claim (one statement record per claim), and scenarios cover the
        // behaviour statements' claims.
        const lines = try std.fmt.allocPrint(a, "{s} One.\n{s} Two.\n{s} Three.\n{s} Four.\n{s} Five.\n{s} Six.\n", .{ source, source, source, source, source, source });
        var fixture = try Fixture.initClaimsGrouped(a, lines, null, .{ .selected = &.{
            .{ .category = .business, .citations = &.{.{ .ordinal = 1 }} }, .{ .category = .business, .citations = &.{.{ .ordinal = 2 }} },
            .{ .category = .business, .citations = &.{.{ .ordinal = 3 }} }, .{ .category = .business, .citations = &.{.{ .ordinal = 4 }} },
            .{ .category = .business, .citations = &.{.{ .ordinal = 5 }} }, .{ .category = .business, .citations = &.{.{ .ordinal = 6 }} },
        } }, &.{&.{ 0, 1, 2, 3, 4, 5 }});
        defer fixture.deinit();
        const value = try fixture.proposalAllGroups(source);
        var claims: [6]@import("domain/reference_identity.zig").ClaimId = undefined;
        var found: usize = 0;
        for ((try provenance.items(fixture.context)).entries) |entry| if (entry.claim.content != .preserved_token) {
            claims[found] = entry.claim.id;
            found += 1;
        };
        try std.testing.expectEqual(@as(usize, 6), found);
        const records = try a.alloc(spec.Model.RecordProposal, std.meta.fields(spec.Kind).len);
        // Functional requirements, acceptance criteria, edge cases and entities share
        // the story's wording. ADR 0035 removes any other statement record that equals
        // the story, so each of those states its own text.
        inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| {
            const own = switch (kind) {
                .acceptance_criterion, .edge_case, .functional_requirement, .entity => value,
                else => try fixture.proposalAllGroups(try std.fmt.allocPrint(a, "{s} {s}", .{ source, @tagName(kind) })),
            };
            const named: []const @import("domain/reference_identity.zig").ClaimId = switch (kind) {
                .functional_requirement => claims[0..1],
                .business_rule => claims[1..2],
                .user_visible_outcome => claims[2..3],
                .assumption => claims[3..4],
                .non_goal => claims[4..5],
                .prohibited_behavior => claims[5..6],
                .acceptance_criterion => &.{ claims[0], claims[1], claims[2], claims[5] },
                .edge_case => claims[0..1],
                .entity => value.provenance.claim_ids,
            };
            records[index] = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, own.value)), .source_group_ids = own.source_group_ids, .provenance = .{ .claim_ids = named, .clarification_response_ids = &.{} } };
        }
        var current = try completedFixtureValue(&fixture, false, value);
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .required, .basis = value, .records = records[records.len - 1 ..] } } })).valid;
        const initial = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
        defer packets.release(initial);
        const initial_body = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
        const initial_purpose = initial_body.get("source_assignment").?.object.get("purpose").?.string;
        try std.testing.expectEqualStrings(try descriptions.recordsFor(a, &packet_guidance.marked, std.meta.tags(spec.Kind)[0 .. std.meta.tags(spec.Kind).len - 1]), initial_purpose);
        inline for (comptime std.meta.tags(spec.Kind)) |kind| try std.testing.expectEqual(kind != .entity, std.mem.indexOf(u8, initial_purpose, descriptions.recordFamily(&packet_guidance.marked, kind)) != null);
        const response: g.Response = .{ .content = .{ .records = records[0 .. records.len - 1] } };
        var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schema_owner = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
        try @import("test_fixtures/prepared_model_repair.zig").check(a, initial, schema_owner, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)), null);
        const valid = (try validate_unit.execute(a, current, fixture.context, .{ .response = response, .origins = .{ .initial = origin } })).valid;
        try std.testing.expectEqual(records.len - 1, valid.response.content.records.len);
        for (records[0 .. records.len - 1], valid.response.content.records) |proposed, accepted| try std.testing.expectEqualDeep(proposed.content, accepted.content);
        // Equal wording in a functional requirement, acceptance criterion, edge case
        // and entity remains distinct candidate data; purpose guidance creates no
        // deduplication rule beyond ADR 0035's restatements.
        const complete = try appendMockChecked(a, current, fixture.context, valid);
        const identified = (try sessions.assemble(a, text.validator, fixture.context, complete, try resolvedLinks(a, complete))).content;
        try std.testing.expectEqual(records.len, identified.records.len);
        inline for (comptime std.meta.tags(spec.Kind)) |kind| try std.testing.expectEqual(spec.Id{ .kind = kind, .ordinal = 1 }, for (identified.records) |record| {
            if (record.id.kind == kind) break record.id;
        } else return error.MissingRecordFamily);

        inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| {
            inline for (std.meta.fields(@FieldType(spec.Content(spec.BusinessValue), @tagName(kind)))) |field| {
                const slot: @import("domain/required_authority.zig").Slot = @field(@import("domain/required_authority.zig").Slot, field.name);
                const selected: candidates.ValueField = @unionInit(candidates.ValueField, @tagName(slot), {});
                var selected_current = current;
                const owned_response: g.Response = if (kind == .entity) .{ .content = .{ .entities = .{ .disposition = .required, .basis = value, .records = records[records.len - 1 ..] } } } else response;
                if (kind == .entity) {
                    selected_current.completed = sessions.entities_index;
                    selected_current.units[sessions.entities_index] = null;
                }
                const local_index = if (kind == .entity) 0 else index;
                const target: candidates.Target = .{ .value = .{ .subject = .{ .record = local_index }, .field = selected } };
                const original = (try candidates.select(owned_response, target)).value;
                const candidate: repair.Candidate = .{
                    .response = try candidates.replace(a, owned_response, target, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} } }),
                    .origins = .{ .initial = origin },
                };
                const rejected = (try validate_unit.execute(a, selected_current, fixture.context, candidate)).invalid;
                try std.testing.expectEqualDeep(target, rejected.issue.field.target);
                const authorization = try repair.authorize(a, selected_current, fixture.context, candidate, rejected, &packet_guidance.marked);
                const packet = try repair.packet(std.testing.allocator, selected_current, fixture.context, authorization, &packet_guidance.marked);
                defer packets.release(packet);
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                const input = body.get("input").?.object;
                try std.testing.expect(!input.contains("record_requirements"));
                // A record repair carries no unpublished draft; an entity repair keeps
                // the brief its unit receives.
                try std.testing.expectEqual(kind == .entity, input.contains("brief"));
                try std.testing.expect(!input.contains("entities"));
                try std.testing.expectEqualStrings(try descriptions.recordTask(a, &packet_guidance.marked, kind, slot), try selectedNativeRepairTask(body.get("input").?));
                const selected_record = try json.decode(candidates.ReadContext, a, try std.json.Stringify.valueAlloc(a, input.get("candidate").?, .{}));
                try std.testing.expectEqualDeep(g.recordCollection(.model, candidate.response.content).?[local_index], selected_record.record);
                try std.testing.expectEqualDeep(origin, authorization.dependencies.candidate.origins.initial.?);
                try @import("test_fixtures/prepared_model_repair.zig").check(a, packet, schema_owner, try json.encodeSelected(repair.Replacement, a, .{ .value = original }), null);
                const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), selected_current, fixture.context, candidate, authorization, .{ .value = original }, null);
                try std.testing.expectEqualDeep(owned_response, fixed.response);
                _ = (try validate_unit.execute(a, selected_current, fixture.context, fixed)).valid;
            }
        }
        // Missing optional families remain allowed under the existing native
        // applicability decision; guidance does not demand nine populated sections.
        current.units[2].?.response.content.entities.disposition = .not_applicable;
        current.units[2].?.response.content.entities.records = &.{};
        const minimum = [_]spec.Model.RecordProposal{ records[0], records[@intFromEnum(spec.Kind.functional_requirement)] };
        const sparse = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &minimum } } })).valid;
        const sparse_complete = try appendMockChecked(a, current, fixture.context, sparse);
        const sparse_content = (try sessions.assemble(a, text.validator, fixture.context, sparse_complete, &.{})).content;
        try std.testing.expectEqual(@as(usize, 2), sparse_content.records.len);
        try std.testing.expectEqual(.not_applicable, sparse_content.entities.disposition);
    }
}

test "record requirements apply across bound groups while native assembled family gaps remain enforced" {
    const sessions = @import("domain/specification_session.zig");
    const binding = @import("domain/specification_source_binding.zig");
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    for ([_][]const u8{ "MOCK A visitor receives a startup greeting.", "MOCK A borrower receives a renewal receipt." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, null, true, 2);
        defer fixture.deinit();
        const value = try fixture.proposal(source);
        const fr: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        const ac: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        for (0..3) |mode| {
            var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
            while (current.completed < sessions.records_index) {
                const unit = try sessions.unit(current.completed);
                if (unit == .primary_user_story) {
                    current = (try compose_story.execute(a, current, fixture.context)).composed;
                    continue;
                }
                const packet = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
                defer packets.release(packet);
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                try std.testing.expect(!body.contains("record_requirements"));
                const response: g.Response = .{ .content = switch (unit) {
                    .brief => .{ .brief = .{ .description = value, .primary_goal = value } },
                    .primary_user_story => unreachable,
                    .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
                    .records => unreachable,
                } };
                const parsed = try g.parse(a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)), try sessions.currentBinding(a, current, fixture.context));
                current = try sessions.append(current, (try validate_unit.execute(a, current, fixture.context, .{ .response = parsed })).valid);
            }
            try std.testing.expectEqual(@as(usize, 2), current.record_group_count);
            var previous_signal: ?i64 = null;
            for (0..2) |group| {
                const packet = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
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
                // Each group emits only its selected families; no group receives
                // a per-group floor or optional filler requirement. A record names
                // claims from its own batch's group, and a requirement's claims need a
                // scenario of that batch (ADR 0038), so only a batch of scope statements
                // leaves both families out.
                const selected = try sessions.currentBinding(a, current, fixture.context);
                var requirement = fr;
                requirement.provenance = selected.records.selection;
                var criterion = ac;
                criterion.provenance = selected.records.selection;
                var scope = fr;
                scope.content = .{ .non_goal = .{ .text = value.value } };
                scope.provenance = selected.records.selection;
                const records: []const spec.Model.RecordProposal = switch (mode) {
                    0 => if (group == 0) try a.dupe(spec.Model.RecordProposal, &.{ requirement, criterion }) else &.{},
                    1 => if (group == 0) try a.dupe(spec.Model.RecordProposal, &.{scope}) else &.{},
                    else => if (group == 0) try a.dupe(spec.Model.RecordProposal, &.{criterion}) else &.{},
                };
                const raw: g.Response = .{ .content = .{ .records = records } };
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
            const content = (try sessions.assemble(a, text.validator, fixture.context, current, &.{})).content;
            try std.testing.expectEqual(@as(usize, if (mode == 0) 2 else 1), content.records.len);
            for (content.records) |record| try std.testing.expect(record.id.kind == .acceptance_criterion or record.id.kind == .functional_requirement or record.id.kind == .non_goal);
            // The assembled family floor is a native structural fact; no model
            // review can stand in for a missing mandatory family.
            for (spec.required_record_families) |kind| {
                const missing = switch (mode) {
                    0 => false,
                    1 => true,
                    else => kind == .functional_requirement,
                };
                try std.testing.expectEqual(!missing, spec.hasRecords(content, kind));
            }
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
        var fixture = try Fixture.initContent(a, source, null, true, 2);
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
        const auth = try repair.authorize(a, current, fixture.context, proposed, rejection, &packet_guidance.marked);
        try std.testing.expect(auth.operation == .insert);
        try std.testing.expectEqualDeep(association.selection, auth.rule.group.?.membership.fixed_provenance);
        try std.testing.expectEqualDeep(association.source_group_ids, auth.rule.group.?.membership.fixed_source_group_ids);
        const packet = try repair.packet(a, current, fixture.context, auth, &packet_guidance.marked);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("repair_record_entity", packet.resultDefinition().?.bytes);
        const record: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = basis.value } }, .source_group_ids = association.source_group_ids, .provenance = association.selection };
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
        broken.content.entity.name = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const invalid = try repair.merge(a, canonical, current, fixture.context, proposed, auth, .{ .record = broken }, corrected);
        const invalid_rejection = (try validate_unit.execute(a, current, fixture.context, invalid)).invalid;
        const next_auth = try repair.authorize(a, current, fixture.context, invalid, invalid_rejection, &packet_guidance.marked);
        try std.testing.expectEqualDeep(auth.retry.?.key, next_auth.retry.?.key);
        try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, invalid)).?.validated.result);
        const recovered = try repair.merge(a, canonical, current, fixture.context, invalid, next_auth, .{ .record = record }, corrected);
        _ = (try validate_unit.execute(a, current, fixture.context, recovered)).valid;
        // A not-applicable feature removes only its contradictory entity. It
        // cannot move the record into another business-content family.
        var contradictory = proposed;
        contradictory.response.content.entities = .{ .disposition = .not_applicable, .basis = basis, .records = &.{record} };
        const contradiction = (try validate_unit.execute(a, current, fixture.context, contradictory)).invalid;
        const deletion = try repair.authorize(a, current, fixture.context, contradictory, contradiction, &packet_guidance.marked);
        try std.testing.expect(deletion.operation == .delete);
        const removed = try repair.merge(a, canonical, current, fixture.context, contradictory, deletion, null, null);
        try std.testing.expectEqual(@as(usize, 0), removed.response.content.entities.records.len);
        try std.testing.expectEqualDeep(basis, removed.response.content.entities.basis);
        _ = (try validate_unit.execute(a, current, fixture.context, removed)).valid;
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, removed)).?.validated.result);
        const title_target: candidate_type.Target = .{ .value = .{ .subject = .{ .record = 0 }, .field = .name } };
        const named = try candidate_type.replace(a, merged.response, title_target, .{ .value = (try fixture.proposal("MOCK A supported identity")).value });
        try std.testing.expectEqualDeep(record.provenance, named.content.entities.records[0].provenance);
    }
}

test "identical entities of one group are a deletable duplicate and of different groups block" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A name is all an entity holds, so equal names are equal content (ADR 0038 Decision 6).
    const name: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Loan" } }} };
    const first: spec.RecordProposal = .{
        .content = .{ .entity = .{ .name = name } },
        .source_group_ids = &.{.{ .ordinal = 1 }},
        .provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .citation_ids = &.{.{ .ordinal = 1 }}, .clarification_response_ids = &.{} },
    };
    var elsewhere = first;
    elsewhere.source_group_ids = &.{.{ .ordinal = 2 }};
    elsewhere.provenance = .{ .claim_ids = &.{.{ .ordinal = 2 }}, .citation_ids = &.{.{ .ordinal = 2 }}, .clarification_response_ids = &.{} };
    try std.testing.expect((try g.duplicateRecordIssue(a, first, first, 1, null)).?.blocked == null);
    try std.testing.expectEqual(.competing_records, (try g.duplicateRecordIssue(a, first, elsewhere, 1, null)).?.blocked.?);
    var other_name = first;
    other_name.content = .{ .entity = .{ .name = .{ .segments = &.{.{ .literal = .{ .value = "Borrower" } }} } } };
    try std.testing.expect((try g.duplicateRecordIssue(a, first, other_name, 1, null)) == null);
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
        var fixture = try Fixture.initContent(a, source, null, true, 2);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        const basis = try fixture.proposal("MOCK Business data is required.");
        const second = try binding.resolveGroups(a, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs, &.{fixture.context.references.records.signals[1].id}, .content);
        const entity: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = basis.value } }, .source_group_ids = second.source_group_ids, .provenance = second.selection };
        current.completed = sessions.entities_index;
        current.units[sessions.entities_index] = null;
        current.units[sessions.records_index] = null;
        current.record_cursor = 0;
        current.record_batches = &.{};
        const response: g.Response = .{ .content = .{ .entities = .{ .disposition = .required, .basis = basis, .records = &.{entity} } } };
        const packet = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
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
        const batch = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
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
        const assembled = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
        var count: usize = 0;
        for (assembled.content.records) |record| if (record.id.kind == .entity) {
            count += 1;
            try std.testing.expectEqualDeep(second.selection.claim_ids, record.proposal.provenance.claim_ids);
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
        var fixture = try Fixture.initContent(a, source, null, true, 3);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, false);
        current.completed = sessions.records_index;
        current.units[sessions.records_index] = null;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[2].?.response.content.entities.disposition = .required;
        const first = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
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
        const later = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
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
        const repair_packet = try sessions.packetForOptions(std.testing.allocator, current, fixture.context, sessions.records_index, .{ .presentation = .{ .task = "MOCK Repair one authorized field." } });
        defer packets.release(repair_packet);
        try std.testing.expect(!(try std.json.parseFromSlice(std.json.Value, a, repair_packet.body(), .{})).value.object.contains("record_requirements"));
        const empty: g.Response = .{ .content = .{ .records = &.{} } };
        current = try sessions.appendBound(a, current, (try validate_unit.execute(a, current, fixture.context, .{ .response = empty })).valid);
        const after_empty = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
        defer packets.release(after_empty);
        const empty_requirements = (try std.json.parseFromSlice(std.json.Value, a, after_empty.body(), .{})).value.object.get("record_requirements").?;
        try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, body.get("record_requirements").?, .{}), try std.json.Stringify.valueAlloc(a, empty_requirements, .{}));
        var stale = current;
        const batches = try a.dupe(g.Checked, current.record_batches);
        stale.record_batches = batches;
        batches[1].record_assignment = null;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, stale, fixture.context, &packet_guidance.marked));
        batches[1].record_assignment = current.record_batches[1].record_assignment;
        batches[1].record_assignment.?.references.bytes[0] ^= 1;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, stale, fixture.context, &packet_guidance.marked));
        var incomplete = current;
        incomplete.record_batches = incomplete.record_batches[0..1];
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, incomplete, fixture.context, &packet_guidance.marked));
        var mismatched = fixture.context;
        const signals = try a.dupe(references.r.Signal, fixture.context.references.records.signals);
        signals[0].value.content.model.business.value.segments = &.{.{ .literal = .{ .value = "MOCK Changed requirement under the same source group." } }};
        mismatched.references.records.signals = signals;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, current, mismatched, &packet_guidance.marked));
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
        var fixture = try Fixture.initContent(a, source, null, true, 2);
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
    var fixture = try Fixture.initContent(a, "Renew a loan and display `MOCK Loan renewed!` with its new deadline.", .business_exact_string, true, 2);
    defer fixture.deinit();
    var current = try completedFixture(&fixture, false);
    current.completed = sessions.records_index;
    current.units[sessions.records_index] = null;
    current.record_cursor = 0;
    current.record_batches = &.{};
    const value = try fixture.proposal("The requested action completes successfully.");
    const ordinary: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const entity: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const ordinary_wire = try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, .{ .content = .{ .records = &.{ordinary} } }));
    const entity_wire = try codec.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, .{ .content = .{ .records = &.{entity} } }));
    for ([_]bool{ false, true }) |required| {
        current.units[2].?.response.content.entities.disposition = if (required) .required else .not_applicable;
        const initial = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
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
    try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packet(a, current, fixture.context, &packet_guidance.marked));
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
        var fixture = try Fixture.initContent(a, source, null, true, 2);
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
        const authorization = try repair.authorize(a, current, fixture.context, initial, invalid, &packet_guidance.marked);
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, initial, authorization, .{ .value = good.value }, corrected);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, fixed)).?.validated.result);
        const first_checked = (try validate_unit.execute(a, current, fixture.context, fixed)).valid;
        current = try sessions.appendBound(a, current, first_checked);
        try std.testing.expectEqual(sessions.records_index, current.completed);
        const second_group = try sessions.currentBinding(a, current, fixture.context);
        // A scope statement, which needs no scenario of its batch (ADR 0038 Decision 2).
        const next_response: g.Response = .{ .content = .{ .records = &.{.{
            .content = .{ .assumption = .{ .text = good.value } },
            .source_group_ids = good.source_group_ids,
            .provenance = second_group.records.selection,
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
        _ = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
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
    try std.testing.expectError(error.InvalidSpecificationRepair, (candidates.Origins{ .fields = &.{.{ .target = .{ .value = .{ .subject = .description, .field = .value } }, .origin = corrected }} }).appendingRecords(a, 0, right, 1));
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
        // The first group holds claims 1, 3 and 4 and the second claim 2, so each sibling
        // statement names its own claim (ADR 0038 Decision 5).
        var fixture = try Fixture.initClaimsGrouped(a, source, null, .{ .repeated = .{ .has_claims = true, .count = 4, .technical = false } }, &.{ &.{ 0, 2, 3 }, &.{1} });
        defer fixture.deinit();
        var current = try completedFixtureValue(&fixture, false, try fixture.proposalGroup("A receipt is available.", 0));
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        current.record_batches = &.{};
        current.units[sessions.records_index] = null;
        const good = try fixture.proposalGroup("The requested outcome is observable.", 0);
        const requirement = try fixture.proposalNaming("The requested outcome is observable.", 0);
        const assumption = try fixture.proposalNaming("An existing account is available.", 2);
        const exclusion = try fixture.proposalNaming("Purchases are outside this feature.", 3);
        const bad: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
        const records = [_]spec.Model.RecordProposal{
            .{ .content = .{ .functional_requirement = .{ .text = requirement.value } }, .source_group_ids = requirement.source_group_ids, .provenance = requirement.provenance },
            .{ .content = .{ .assumption = .{ .text = bad } }, .source_group_ids = assumption.source_group_ids, .provenance = assumption.provenance },
            .{ .content = .{ .acceptance_criterion = .{ .given = requirement.value, .when = requirement.value, .then = requirement.value } }, .source_group_ids = requirement.source_group_ids, .provenance = requirement.provenance },
            .{ .content = .{ .non_goal = .{ .text = exclusion.value } }, .source_group_ids = exclusion.source_group_ids, .provenance = exclusion.provenance },
        };
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .records = &records } }, .origins = .{ .initial = original } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqualDeep(@as(@import("domain/specification_candidate.zig").Target, .{ .value = .{ .subject = .{ .record = 1 }, .field = .text } }), rejected.issue.field.target);
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = assumption.value }, correction);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, fixed)).?.validated.result);
        for ([_]usize{ 0, 2, 3 }) |index| {
            try std.testing.expectEqualDeep(records[index], fixed.response.content.records[index]);
            try std.testing.expectEqualDeep(original, fixed.origins.at(.{ .target = .{ .provenance = .{ .record = index } } }).?);
        }
        const checked = (try validate_unit.execute(a, current, fixture.context, fixed)).valid;
        current = try appendMockChecked(a, current, fixture.context, checked);
        current.starting_ledger.next[@intFromEnum(spec.Kind.functional_requirement)] = 7;
        const assembled = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
        try std.testing.expectEqual(.acceptance_criterion, assembled.content.records[0].id.kind);
        var required_entities = current;
        required_entities.units[2].?.response.content.entities.disposition = .required;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, required_entities, &.{}));
        required_entities.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .required, .basis = good, .records = &.{.{ .content = .{ .entity = .{ .name = good.value } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance }} } } })).valid;
        _ = try sessions.assemble(a, text.validator, fixture.context, required_entities, &.{});
        required_entities.units[2].?.response.content.entities.disposition = .not_applicable;
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, required_entities, &.{}));
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
        try std.testing.expectError(error.UnsafeSpecificationRepair, repair.authorize(a, current, fixture.context, duplicate, failure, &packet_guidance.marked));
    }
}

test "completed repair packets retire authoring assignments while pending record groups remain bound" {
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display the startup time in UTC.", "Renew a loan and issue a receipt." }, 1..) |source, group_count| {
        var fixture = try Fixture.initContent(a, source, null, true, group_count);
        defer fixture.deinit();
        var current = try completedFixture(&fixture, true);
        try std.testing.expectEqual(group_count, current.record_group_count);
        current.record_cursor = group_count;
        const completed = try sessions.packetFor(a, current, fixture.context, sessions.records_index, &packet_guidance.marked);
        defer @import("domain/model_input_packet.zig").release(completed);
        const complete_json = try std.json.parseFromSlice(std.json.Value, a, completed.body(), .{});
        try std.testing.expect(complete_json.value.object.get("source_assignment").? == .null);
        for (0..sessions.unit_count) |index| {
            // No model request, repair included, carries the engine's story (ADR 0047).
            if (index == sessions.story_index) {
                try std.testing.expectError(error.InvalidSpecificationUnit, sessions.packetForOptions(a, current, fixture.context, index, .{ .presentation = .{ .task = "MOCK selected completed replacement." } }));
                continue;
            }
            const selected = try sessions.packetForOptions(a, current, fixture.context, index, .{ .presentation = .{ .task = "MOCK selected completed replacement." } });
            defer @import("domain/model_input_packet.zig").release(selected);
            const input = (try std.json.parseFromSlice(std.json.Value, a, selected.body(), .{})).value;
            try std.testing.expect(input.object.get("source_assignment").? == .null);
            try std.testing.expectEqualStrings("MOCK selected completed replacement.", try selectedNativeRepairTask(input));
        }
        var pending = current;
        pending.completed = sessions.records_index;
        pending.units[sessions.records_index] = null;
        try std.testing.expectError(error.InvalidSpecificationBinding, sessions.packetFor(a, pending, fixture.context, sessions.records_index, &packet_guidance.marked));
        pending.record_cursor -= 1;
        pending.record_batches = pending.record_batches[0..pending.record_cursor];
        const assigned = try sessions.packetFor(a, pending, fixture.context, sessions.records_index, &packet_guidance.marked);
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
    var fixture = try Fixture.initContent(a, source, null, true, 2);
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
    const same = (try sessions.checkConsistency(a, current, fixture.context, repeated, null)).?;
    try std.testing.expectEqual(.duplicate_record, same.rule);
    try std.testing.expect(same.blocked == null);
    var competing = first;
    competing.provenance.claim_ids = &.{.{ .ordinal = 2 }};
    competing.source_group_ids = &.{fixture.context.references.records.signals[1].id};
    const checked = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{competing} } })).valid;
    const issue = (try sessions.checkConsistency(a, current, fixture.context, checked, null)).?;
    try std.testing.expectEqual(.duplicate_record, issue.rule);
    try std.testing.expectEqual(.competing_records, issue.blocked.?);
    var distinct = first;
    distinct.content.functional_requirement.text = (try fixture.proposal("The clock result is visible.")).value;
    // Its claims need a scenario of its batch (ADR 0038 Decision 2).
    var tested = distinct;
    tested.content = .{ .acceptance_criterion = .{ .given = distinct.content.functional_requirement.text, .when = distinct.content.functional_requirement.text, .then = distinct.content.functional_requirement.text } };
    const different = (try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{ distinct, tested } } })).valid;
    try std.testing.expect((try sessions.checkConsistency(a, current, fixture.context, different, null)) == null);
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
        const prohibited = try provenance.checkAttributed(.model, a, text.validator, fixture.context, original, .spec_goal);
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

    // ADR 0036: a repair bound to ACTIVE alone still keeps delimiters whose removal
    // would join ACTIVE VALUE, so the full re-check admits what the repair admitted.
    const active = for ((try provenance.items(ambiguous.context)).entries) |item| {
        if (item.claim.content == .preserved_token and std.mem.eql(u8, item.claim.content.preserved_token.value.raw_value.bytes, "ACTIVE")) break item.claim.id;
    } else return error.MissingTestToken;
    const wrapped: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Display `ACTIVE` VALUE." } }} };
    const repaired = try provenance.checkValueInUnit(a, text.validator, ambiguous.context, .{ .claim_ids = &.{active}, .clarification_response_ids = &.{} }, &.{}, wrapped, .functional_requirement);
    try std.testing.expectEqual(@as(usize, 3), repaired.segments.len);
    try std.testing.expectEqualStrings("Display `", repaired.segments[0].literal.value);
    try std.testing.expectEqualDeep(active, repaired.segments[1].exact_copy.claim_id);
    try std.testing.expectEqualStrings("` VALUE.", repaired.segments[2].literal.value);
    try std.testing.expectEqualDeep(repaired, try provenance.recognizeValue(a, @import("domain/reference_support.zig").records(ambiguous.context.references), repaired, .functional_requirement, null));
    // The kept backticks are a table pair, so the engine adds no second delimiter and
    // the model's backticks render as written text.
    const projection = @import("domain/specification_projection.zig");
    const markdown = @import("domain/specification_markdown.zig");
    const kept = try projection.scalar(a, ambiguous.context, .{ .value = repaired, .provenance = try provenance.select(a, ambiguous.context, .{ .claim_ids = &.{active}, .clarification_response_ids = &.{} }) });
    try std.testing.expectEqualStrings("Display `ACTIVE` VALUE.", kept.bytes);
    try std.testing.expectEqual(@as(usize, 0), kept.code_spans.len);
    const document: spec.CapturedDocument = .{ .display_name = .{ .bytes = "Kept delimiters" }, .primary_user_story = kept, .records = &.{}, .entity_section = .omitted };
    const rendered = try markdown.render(a, document);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "Display \\`ACTIVE\\` VALUE.") != null);
    try std.testing.expectEqualDeep(document, try markdown.parse(a, rendered));

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
        const target: candidates.Target = .{ .value = .{ .subject = .description, .field = .value } };
        const plain = try fixture.proposal("The visitor sees the result.");
        var proposed: candidates.Candidate = .{
            .response = .{ .content = .{ .brief = .{ .description = raw, .primary_goal = plain } } },
            .value_bound = .{
                .target = try origins.stableTarget(target, 0),
                .explicit = selected.claim_ids,
                .effective = selected.claim_ids,
                .citations = selected.citation_ids,
            },
        };
        try std.testing.expectError(error.InvalidSpecificationUnit, g.validateCandidate(a, text.validator, fixture.context, .brief, proposed));
        const accepted = try provenance.checkAttributed(.model, a, text.validator, fixture.context, raw, .spec_description);
        const retained = try provenance.lineageForRepair(a, fixture.context, raw.provenance, &.{accepted.value});
        proposed.value_bound.?.effective = retained.effective_claim_ids;
        proposed.value_bound.?.citations = retained.provenance.citation_ids;
        try std.testing.expect((try g.validateCandidate(a, text.validator, fixture.context, .brief, proposed)) == .valid);
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
    const descriptive = try provenance.checkAttributed(.model, a, text.validator, fixture.context, base, .spec_goal);
    const story = try provenance.checkAttributed(.model, a, text.validator, fixture.context, base, .spec_story);
    const record = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
        .content = .{ .functional_requirement = .{ .text = .{ .segments = &.{.{ .literal = .{ .value = "The user sees ACTIVE and exports report.csv." } }} } } },
        .source_group_ids = base.source_group_ids,
        .provenance = base.provenance,
    });
    const brief: g.Brief = .{ .description = descriptive, .primary_goal = descriptive };
    const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = story, .records = &.{record}, .entities = .{ .disposition = .not_applicable, .basis = descriptive } }, .{}, &.{})).content;
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

test "an exact copy its own prose wraps in a balanced pair is projected without the engine's code span" {
    const projection = @import("domain/specification_projection.zig");
    const markdown = @import("domain/specification_markdown.zig");
    const Segment = @import("domain/typed_text.zig").BusinessSegment;
    const Case = struct { source: []const u8, prefix: []const u8, suffix: []const u8, spans: usize };
    for ([_]Case{
        // The prose delimits a value that ends without punctuation, in any table pair.
        .{ .source = "Export `report.csv` nightly.", .prefix = "Export \"", .suffix = "\" nightly.", .spans = 0 },
        .{ .source = "Export `report.csv` nightly.", .prefix = "Export (", .suffix = "), nightly.", .spans = 0 },
        .{ .source = "Export `report.csv` nightly.", .prefix = "Export \u{201c}", .suffix = "\u{201d} nightly.", .spans = 0 },
        .{ .source = "Display `Hello, World` when started.", .prefix = "Display the exact text \"", .suffix = "\" when started.", .spans = 0 },
        // Both development-case shapes end in their own punctuation, which inside the
        // pair reads as the prose's, so the engine still delimits them.
        .{ .source = "Display `Hello, World!` when started.", .prefix = "Display the exact text \"", .suffix = "\" when started.", .spans = 1 },
        .{ .source = "Refuse and display `Renewal refused.`.", .prefix = "The system refuses and displays \"", .suffix = "\"", .spans = 1 },
        // No pair, or punctuation inside the pair: the engine delimits the value.
        .{ .source = "Export `report.csv` nightly.", .prefix = "Export ", .suffix = " nightly.", .spans = 1 },
        .{ .source = "Export `report.csv` nightly.", .prefix = "Export \"", .suffix = ".\" nightly.", .spans = 1 },
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
        const raw = token_claim.content.preserved_token.value.raw_value.bytes;
        const fixed = try provenance.select(a, fixture.context, .{ .claim_ids = &.{ all.entries[0].claim.id, token_claim.id }, .clarification_response_ids = &.{} });
        const segments: []const Segment = &.{ .{ .literal = .{ .value = case.prefix } }, .{ .exact_copy = .{ .claim_id = token_claim.id } }, .{ .literal = .{ .value = case.suffix } } };
        const model: spec.Model.AttributedValue = .{ .value = .{ .segments = segments }, .source_group_ids = &.{ fixture.context.references.records.signals[0].id, fixture.context.references.records.signals[1].id }, .provenance = selection(fixed) };
        const value = try provenance.checkAttributed(.model, a, text.validator, fixture.context, model, .spec_story);
        const displayed = try projection.scalar(a, fixture.context, value);
        try std.testing.expectEqualStrings(try std.mem.concat(a, u8, &.{ case.prefix, raw, case.suffix }), displayed.bytes);
        try std.testing.expectEqual(case.spans, displayed.code_spans.len);
        if (case.spans == 1) try std.testing.expectEqual(spec.CodeSpan{ .start = case.prefix.len, .end = case.prefix.len + raw.len }, displayed.code_spans[0]);
        const record = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = &.{fixture.context.references.records.signals[0].id}, .provenance = .{ .claim_ids = &.{all.entries[0].claim.id}, .clarification_response_ids = &.{} } });
        const descriptive = try provenance.checkAttributed(.model, a, text.validator, fixture.context, try fixture.proposal("The user receives the requested output."), .spec_goal);
        const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = value, .records = &.{record}, .entities = .{ .disposition = .not_applicable, .basis = descriptive } }, .{}, &.{})).content;
        const document = try projection.project(a, fixture.context, test_directory, content);
        try std.testing.expectEqual(case.spans, document.primary_user_story.code_spans.len);
        try std.testing.expectEqual(case.spans, document.records[0].content.functional_requirement.text.code_spans.len);
        const rendered = try markdown.render(a, document);
        // Field lines carry a backtick only for the engine's span; source lines always do.
        var fields_have_code = false;
        var lines = std.mem.splitScalar(u8, rendered, '\n');
        while (lines.next()) |rendered_line| {
            if (std.mem.startsWith(u8, rendered_line, "  - Source: ")) continue;
            if (std.mem.indexOfScalar(u8, rendered_line, '`') != null) fields_have_code = true;
        }
        try std.testing.expectEqual(case.spans != 0, fields_have_code);
        try std.testing.expectEqualDeep(document, try markdown.parse(a, rendered));
    }
}

test "cited lines merge where they overlap, nest or touch, and stay apart across a gap" {
    const projection = @import("domain/specification_projection.zig");
    const Case = struct { input: []const spec.LineRange, merged: []const spec.LineRange };
    for ([_]Case{
        .{ .input = &.{}, .merged = &.{} },
        .{ .input = &.{ .{ .first = 9, .last = 9 }, .{ .first = 3, .last = 4 } }, .merged = &.{ .{ .first = 3, .last = 4 }, .{ .first = 9, .last = 9 } } },
        .{ .input = &.{ .{ .first = 5, .last = 6 }, .{ .first = 7, .last = 7 } }, .merged = &.{.{ .first = 5, .last = 7 }} },
        .{ .input = &.{ .{ .first = 5, .last = 8 }, .{ .first = 6, .last = 9 } }, .merged = &.{.{ .first = 5, .last = 9 }} },
        .{ .input = &.{ .{ .first = 2, .last = 10 }, .{ .first = 4, .last = 5 }, .{ .first = 2, .last = 3 } }, .merged = &.{.{ .first = 2, .last = 10 }} },
        .{ .input = &.{ .{ .first = 6, .last = 6 }, .{ .first = 6, .last = 6 } }, .merged = &.{.{ .first = 6, .last = 6 }} },
    }) |case| {
        var buffer: [8]spec.LineRange = undefined;
        @memcpy(buffer[0..case.input.len], case.input);
        try std.testing.expectEqualSlices(spec.LineRange, case.merged, projection.mergeLines(buffer[0..case.input.len]));
    }
}

test "a record shows its claims' cited source lines, merged per file" {
    const projection = @import("domain/specification_projection.zig");
    const markdown = @import("domain/specification_markdown.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The first claim cites line 4 and the second lines 1-2, in one group. Each line
    // span ends at the next line's column 1, which closes the line before it; the
    // shown ranges are sorted, whatever the claim order.
    var fixture = try Fixture.initClaimsGrouped(a, "Show the greeting.\nKeep it short.\n\nLog the time.\n", null, .{ .selected = &.{
        .{ .category = .business, .citations = &.{.{ .ordinal = 4 }} },
        .{ .category = .business, .citations = &.{ .{ .ordinal = 1 }, .{ .ordinal = 2 } } },
    } }, &.{&.{ 0, 1 }});
    defer fixture.deinit();
    const all = try provenance.items(fixture.context);
    var prose: std.ArrayList(@import("domain/reference_reconciliation.zig").ClaimId) = .empty;
    for (all.entries) |item| if (item.claim.content != .preserved_token) try prose.append(a, item.claim.id);
    try std.testing.expectEqual(@as(usize, 2), prose.items.len);
    const Expected = struct { claims: []const @import("domain/reference_reconciliation.zig").ClaimId, line: []const u8 };
    const cases = [_]Expected{
        .{ .claims = &.{prose.items[0]}, .line = "  - Source: `references/feature/stories.md` line 4\n" },
        .{ .claims = &.{prose.items[1]}, .line = "  - Source: `references/feature/stories.md` lines 1–2\n" },
        .{ .claims = &.{ prose.items[0], prose.items[1] }, .line = "  - Source: `references/feature/stories.md` lines 1–2, 4\n" },
    };
    var records: [cases.len]spec.RecordProposal = undefined;
    for (cases, &records) |case, *record| record.* = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
        .content = .{ .functional_requirement = .{ .text = (try fixture.proposal("The visitor sees a short greeting.")).value } },
        .source_group_ids = &.{fixture.context.references.records.signals[0].id},
        .provenance = .{ .claim_ids = case.claims, .clarification_response_ids = &.{} },
    });
    const descriptive = try provenance.checkAttributed(.model, a, text.validator, fixture.context, try fixture.proposalAllGroups("The visitor sees a short greeting."), .spec_goal);
    const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = descriptive, .records = &records, .entities = .{ .disposition = .not_applicable, .basis = descriptive } }, .{}, &.{})).content;
    const document = try projection.project(a, fixture.context, test_directory, content);
    const rendered = try markdown.render(a, document);
    for (cases, document.records) |case, record| {
        try std.testing.expectEqual(@as(usize, 1), record.sources.len);
        try std.testing.expect(std.mem.indexOf(u8, rendered, case.line) != null);
    }
    try std.testing.expectEqualDeep(document, try markdown.parse(a, rendered));
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
        const descriptive = try provenance.checkAttributed(.model, a, text.validator, fixture.context, try fixture.proposal("The user receives the requested output."), .spec_goal);
        const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = value, .records = &.{record}, .entities = .{ .disposition = .not_applicable, .basis = descriptive } }, .{}, &.{})).content;
        const brief: g.Brief = .{ .description = value, .primary_goal = descriptive };
        _ = try coverage.validate(a, fixture.context.references, brief, content);
        const document = try projection.project(a, fixture.context, test_directory, content);
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
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = repair_wrong, .primary_goal = plain_model } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(.typed_text, rejection.issue.rule);
        const authorized = try repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked);
        const packet = try repair.packet(a, current, fixture.context, authorized, &packet_guidance.marked);
        defer @import("domain/model_input_packet.zig").release(packet);
        const replacement: repair.Replacement = .{ .value = model.value };
        const plain = try provenance.modelValue(a, @import("domain/reference_support.zig").records(fixture.context.references), model.value);
        const wire = try @import("domain/model_candidate_json.zig").encode(struct { value: spec.BusinessValue }, a, .{ .value = plain });
        const decoded = try repair.parse(a, authorized, packet, wire);
        try std.testing.expectEqualDeep(repair.Replacement{ .value = plain }, decoded);
        try std.testing.expectError(error.InvalidJsonDocument, @import("domain/model_candidate_json.zig").encode(repair.Replacement, a, replacement));
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorized, decoded, null);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, merged)) == .valid);
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
    const proposed: g.Response = .{ .content = .{ .brief = .{ .description = exact_only, .primary_goal = good } } };
    const rejected = (try g.validate(a, text.validator, fixture.context, .brief, proposed)).invalid;
    try std.testing.expectEqual(.provenance, rejected.rule);
    const question: g.Response = .{ .clarification = .{ .reason = .missing, .question = exact_only } };
    try std.testing.expectEqual(.clarification_question, (try g.validate(a, text.validator, fixture.context, .brief, question)).invalid.blocked.?);
    const canonical = try fixture.value("MOCK The user sees the completed state.");
    const content: spec.IdentifiedContent = .{ .display_name = fixture_display_name, .primary_user_story = canonical, .entities = .{ .disposition = .not_applicable, .basis = canonical }, .records = &.{} };
    const brief: spec.Brief = .{ .description = inspected, .primary_goal = canonical };
    try std.testing.expectEqual(.provenance, (try g.revalidate(a, text.validator, fixture.context, .brief, .{ .content = .{ .brief = brief } })).invalid.rule);
    try std.testing.expectError(error.InvalidSpecification, provenance.validateStored(a, fixture.context.inputs, .{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences }, @import("domain/reference_support.zig").records(fixture.context.references), brief, content));
}

test "code samples remain reference evidence and cannot be copied into business specification fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const raw = "print(\"sample\")\n``` inside the example\n";
    // The business claim quotes only line 1; quoting the code would make it an exact obligation (ADR 0024).
    var fixture = try Fixture.initClaims(a, "Example:\n~~~~text\n" ++ raw ++ "~~~~\n", .code_sample, .{ .selected = &.{.{ .category = .business, .citations = &.{.{ .ordinal = 1 }} }} });
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
    const bytes = try @import("domain/reference_context.zig").render(a, snapshot, null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "````\n" ++ raw ++ "````\n") != null);
}

test "unit parsing rejects model authority and ID ledger allocation remains engine owned" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Users view a greeting.");
    defer fixture.deinit();
    const value = try fixture.value("Users view a greeting.");
    const proposed = try fixture.proposal("Users view a greeting.");
    const response: g.Response = .{ .content = .{ .brief = .{ .description = proposed, .primary_goal = proposed } } };
    const bytes = try @import("domain/model_candidate_json.zig").encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response));
    const records = @import("domain/reference_support.zig").records(fixture.context.references);
    const bound = try @import("domain/specification_source_binding.zig").forUnit(a, records, fixture.context.inputs, .brief, 0);
    _ = try g.parse(a, bytes, bound);
    // The engine composes the story: it has no wire form and no response parses for it (ADR 0047).
    try std.testing.expect(!@hasField(g.ModelResponse, "primary_user_story"));
    try std.testing.expectError(error.InvalidSpecificationUnit, g.ModelResponse.from(a, fixture.context, .{ .content = .{ .primary_user_story = proposed } }));
    const story_bound = try @import("domain/specification_source_binding.zig").forUnit(a, records, fixture.context.inputs, .primary_user_story, 0);
    try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, bytes, story_bound));
    // The engine takes the title (ADR 0048), so a brief that carries one is rejected.
    for ([_][]const u8{ "id", "completed", "path", "approved", "open_questions", "title" }) |key| {
        const forged = try std.fmt.allocPrint(a, "{{\"{s}\":true,{s}", .{ key, bytes[1..] });
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, forged, bound));
    }
    const record: spec.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
    const content: spec.ContentProposal = .{ .display_name = fixture_display_name, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = &.{record} };
    const first = try identifiers.assign(a, content, .{}, &.{});
    try std.testing.expectEqual(@as(u32, 1), first.content.records[0].id.ordinal);
    const next = try identifiers.assign(a, content, first.ledger, &.{});
    try std.testing.expectEqual(@as(u32, 2), next.content.records[0].id.ordinal);
    var exhausted = first.ledger;
    exhausted.next[@intFromEnum(spec.Kind.functional_requirement)] = std.math.maxInt(u32);
    try std.testing.expectError(error.InvalidSpecification, identifiers.assign(a, content, exhausted, &.{}));
}

fn Fields(comptime kind: spec.Kind, value: spec.BusinessValue) @FieldType(spec.Content(spec.BusinessValue), @tagName(kind)) {
    const T = @FieldType(spec.Content(spec.BusinessValue), @tagName(kind));
    var result: T = undefined;
    inline for (@typeInfo(T).@"struct".fields) |field| @field(result, field.name) = value;
    return result;
}
/// The title heading `Fixture` gives a source written without one (ADR 0048).
const fixture_title = "MOCK Specification title";
const fixture_display_name: spec.DisplayName = .{ .bytes = fixture_title };
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
        return initContent(a, bytes, kind, has_claims, 1);
    }
    /// The first model claim quotes every line of `bytes` (ADR 0036). Each further claim
    /// quotes its own appended line, so several claims are distinct evidence: identical
    /// claims are one.
    fn initContent(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, has_claims: bool, model_claim_count: usize) !Fixture {
        return initContentKinds(a, bytes, kind, has_claims, model_claim_count, false);
    }
    fn initContentKinds(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, has_claims: bool, model_claim_count: usize, include_technical: bool) !Fixture {
        return initClaims(a, bytes, kind, .{ .repeated = .{ .has_claims = has_claims, .count = model_claim_count, .technical = include_technical } });
    }
    const Claims = union(enum) {
        repeated: struct { has_claims: bool, count: usize, technical: bool },
        selected: []const @import("domain/reference_extraction.zig").Proposal,
    };
    fn initClaims(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, supplied: Claims) !Fixture {
        return initClaimsGrouped(a, bytes, kind, supplied, &.{});
    }
    /// `groups` partitions prose claims (by position) into reconciled groups, as live
    /// reconciliation often merges them; none keeps one group per claim. Tokens keep
    /// their own groups.
    fn initClaimsGrouped(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, supplied: Claims, groups: []const []const usize) !Fixture {
        return build(a, bytes, kind, supplied, groups, true);
    }
    /// The source exactly as written, with no title heading added (ADR 0048).
    fn initAsWritten(a: std.mem.Allocator, bytes: []const u8) !Fixture {
        return build(a, bytes, .business_exact_string, .{ .repeated = .{ .has_claims = true, .count = 1, .technical = false } }, &.{}, false);
    }
    fn build(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, supplied: Claims, groups: []const []const usize, titled: bool) !Fixture {
        var ids: evidence.IdSource = .{};
        const copies: usize = switch (supplied) {
            .repeated => |options| if (options.has_claims) @max(options.count, 1) else 1,
            .selected => 1,
        };
        // A technical claim needs no line of its own: another category on the same lines is
        // already distinct evidence.
        const appended: usize = switch (supplied) {
            .repeated => |options| copies - 1 - @intFromBool(options.technical and copies > 1),
            .selected => 0,
        };
        const source = if (appended == 0) bytes else extended: {
            var all: std.ArrayList(u8) = .empty;
            try all.appendSlice(a, bytes);
            if (!std.mem.endsWith(u8, bytes, "\n")) try all.append(a, '\n');
            // A blank line keeps the appended lines out of the source's last list item.
            try all.append(a, '\n');
            for (0..appended) |index| try all.print(a, "MOCK Further requirement {d}.\n", .{index + 2});
            break :extended all.items;
        };
        // ADR 0048: a session takes its title from a level-1 heading. A source written
        // without one gets `fixture_title` after its text, which no scripted claim quotes,
        // as no live extraction quoted a title heading.
        const appended_title = titled and (try @import("domain/markdown_code_spans.zig").levelOneHeading(a, source)) == null;
        const document = if (!appended_title) source else try std.mem.concat(a, u8, &.{ source, if (std.mem.endsWith(u8, source, "\n")) "\n" else "\n\n", "# ", fixture_title, "\n" });
        const inputs = try evidence.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "stories.md", document));
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
                    // One business claim quotes every citable line but an appended title.
                    const lines = try extraction.citableLines(a, inputs, chunk);
                    const last = chunk.id.eql(inputs.chunks.entries[inputs.chunks.entries.len - 1].id);
                    const quoted = if (appended_title and last) lines[0 .. lines.len - 1] else lines;
                    const claimed = try json.encode(Response, a, .{ .claims = .{ .claims = &.{.{ .category = .business, .citations = quoted }}, .token_classifications = &.{} } });
                    const initial = try tokens.wire(a, if (options.has_claims) claimed else extraction.no_claim, choices.items);
                    if (!options.has_claims or options.count == 1) break :repeated initial;
                    var response = try json.decode(Response, a, initial);
                    const claims = try a.alloc(@import("domain/reference_extraction.zig").Proposal, options.count);
                    // The reply cites every citable line: the first claim cites the supplied
                    // lines, a technical claim the same lines, and each further claim its own
                    // appended line.
                    const every = response.claims.claims[0].citations;
                    if (inputs.chunks.entries.len != 1 or every.len <= appended) return error.InvalidFixture;
                    const supplied_lines = every.len - appended;
                    var next_line = supplied_lines;
                    for (claims, 0..) |*claim, index| {
                        const technical = options.technical and index == 1;
                        claim.* = .{ .category = if (technical) .technical else response.claims.claims[0].category, .citations = if (index == 0 or technical) every[0..supplied_lines] else every[next_line..][0..1] };
                        if (index != 0 and !technical) next_line += 1;
                    }
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
        var reconciled = try references.global(a, global);
        if (groups.len != 0) {
            var prose: std.ArrayList(@TypeOf(reconciled.signals[0])) = .empty;
            var signals: std.ArrayList(@TypeOf(reconciled.signals[0])) = .empty;
            for (global.items, reconciled.signals) |item, signal| {
                if (item.claim.content == .preserved_token) try signals.append(a, signal) else try prose.append(a, signal);
            }
            for (groups, 0..) |members, index| {
                const grouped = try a.alloc(@import("domain/reference_identity.zig").ClaimId, members.len);
                for (members, grouped) |position, *id| id.* = prose.items[position].claim_ids[0];
                try signals.insert(a, index, .{ .claim_ids = grouped, .content = prose.items[members[0]].content });
            }
            reconciled.signals = signals.items;
        }
        const complete = (try references.finish(a, global, reconciled, context)).valid;
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
    /// A proposal bound to group `index` alone, with all of its claims.
    fn proposalGroup(self: *const Fixture, bytes: []const u8, index: usize) !spec.Model.AttributedValue {
        const binding = @import("domain/specification_source_binding.zig");
        const records = @import("domain/reference_support.zig").records(self.context.references);
        const resolved = try binding.resolveGroups(self.allocator, records, self.context.inputs, &.{self.context.references.records.signals[index].id}, .content);
        var proposed = try self.proposal(bytes);
        proposed.source_group_ids = resolved.source_group_ids;
        proposed.provenance = resolved.selection;
        return proposed;
    }
    /// A proposal naming only claim `index`, bound to the group that holds it.
    fn proposalNaming(self: *const Fixture, bytes: []const u8, index: usize) !spec.Model.AttributedValue {
        var proposed = try self.proposal(bytes);
        const claim = self.context.references.records.assignments.checked.prior.prior.input.items[index].claim;
        const group = for (self.context.references.records.signals) |signal| {
            if (@import("domain/reference_reconciliation.zig").contains(references.r.ClaimId, signal.value.claim_ids, claim.id)) break signal.id;
        } else return error.InvalidFixture;
        proposed.source_group_ids = try self.allocator.dupe(references.r.SignalId, &.{group});
        proposed.provenance = .{ .claim_ids = try self.allocator.dupe(references.r.ClaimId, &.{claim.id}), .clarification_response_ids = &.{} };
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
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = good } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked);
        try std.testing.expect(authorization.target.value.subject == .description);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization, &packet_guidance.marked);
        defer packets.release(packet);
        try checkAuthoringPacket(a, packet.body());
        const replacement: repair.Replacement = .{ .value = good.value };
        const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
        const parsed = try repair.parse(a, authorization, packet, wire);
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, parsed, null);
        try std.testing.expectEqual(@as(u64, 2), merged.revision);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.primary_goal);
        try std.testing.expectEqualDeep(bad, candidate.response.content.brief.description);
        _ = (try g.validate(a, text.validator, fixture.context, .brief, merged.response)).valid;
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, merged, rejection, &packet_guidance.marked));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, merged, authorization, parsed, null));
        var changed = candidate;
        changed.response.content.brief.description = good;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, changed, authorization, parsed, null));
        var foreign = current;
        foreign.feature.bytes = "another-feature";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), foreign, fixture.context, candidate, authorization, parsed, null));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, foreign, fixture.context, authorization, &packet_guidance.marked));
        var wrong_id = authorization;
        wrong_id.id.bytes = "foreign-repair";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.parse(a, wrong_id, packet, try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement)));
        const with_target = try std.fmt.allocPrint(a, "{{\"target\":\"primary_goal\",{s}", .{wire[1..]});
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
            .{ .index = 0, .subject = .description, .slot = .description },
            .{ .index = 0, .subject = .primary_goal, .slot = .primary_goal },
            .{ .index = 2, .subject = .entity_basis, .slot = .entities },
            .{ .index = 2, .subject = .entity_basis, .slot = .entities, .disposition = .required },
        };
        for (cases) |case| {
            var current = try completedFixture(&fixture, false);
            const good = try fixture.proposal(source);
            const original: g.Response = .{ .content = switch (case.index) {
                0 => .{ .brief = .{ .description = good, .primary_goal = good } },
                2 => .{ .entities = .{ .disposition = case.disposition, .basis = good, .records = if (case.disposition == .required) &.{.{ .content = .{ .entity = .{ .name = good.value } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance }} else &.{} } },
                else => return error.UnexpectedRecordAssignment,
            } };
            current.completed = case.index;
            for (current.units[case.index..]) |*unit_value| unit_value.* = null;
            const target: candidates.Target = .{ .value = .{ .subject = case.subject, .field = .value } };
            const candidate: repair.Candidate = .{ .response = try candidates.replace(a, original, target, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} } }) };
            const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
            try std.testing.expectEqualDeep(target, rejection.issue.field.target);
            const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked);
            const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization, &packet_guidance.marked);
            defer packets.release(packet);
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            const input = body.get("input").?;
            try std.testing.expectEqualStrings(try descriptions.task(a, &packet_guidance.marked, .{ .kind = if (case.slot == .entities) .entity_applicability else .feature_intent, .unit = .{ .feature = .singleton }, .slot = case.slot }), try selectedNativeRepairTask(input));
            const assigned = try json.decode(binding.Guidance, a, try std.json.Stringify.valueAlloc(a, input.object.get("source_assignment").?, .{}));
            switch (assigned) {
                .brief => {},
                .entities => {},
                .records => return error.UnexpectedRecordAssignment,
            }
            const initial = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
            defer packets.release(initial);
            const initial_body = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
            if (case.subject == .entity_basis) {
                // The same decision-and-basis purpose governs initial authoring
                // and repair of the selected explanation, for either disposition.
                const purpose = try descriptions.task(a, &packet_guidance.marked, .{ .kind = .entity_applicability, .unit = .{ .feature = .singleton }, .slot = .entities });
                try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s}\n{s}", .{ purpose, try descriptions.record(a, &packet_guidance.marked, .entity) }), initial_body.get("source_assignment").?.object.get("purpose").?.string);
                try std.testing.expectEqualStrings(purpose, try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, .{ .kind = .entity_applicability, .unit = .{ .feature = .singleton }, .slot = .entities }));
                try std.testing.expectEqualStrings(purpose, try selectedNativeRepairTask(input));
            }
            inline for (.{ "context_requirements", "exact_texts", "sources" }) |key| try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, initial_body.get(key).?, .{}), try std.json.Stringify.valueAlloc(a, input.object.get(key).?, .{}));
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

// ADR 0035's same-kind delete runs before ADR 0038 Decision 5's repeated statements.
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
    inline for (.{ spec.Kind.acceptance_criterion, spec.Kind.edge_case, spec.Kind.business_rule }) |kind| {
        current.completed = sessions.records_index;
        current.record_cursor = 0;
        const record: spec.Model.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, value.value)), .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        const proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ record, record } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, proposed, rejection, &packet_guidance.marked);
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
        const value_field: @import("domain/specification_candidate.zig").ValueField = switch (kind) {
            .acceptance_criterion => .given,
            .edge_case => .condition,
            else => .text,
        };
        const stable = try with_sibling.origins.stableTarget(.{ .value = .{ .subject = .{ .record = 2 }, .field = value_field } }, 3);
        const remove = try repair.authorize(a, current, fixture.context, with_sibling, (try validate_unit.execute(a, current, fixture.context, with_sibling)).invalid, &packet_guidance.marked);
        const shifted = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, with_sibling, remove, null, null);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, shifted)).?.validated.result);
        const remaining = (try validate_unit.execute(a, current, fixture.context, shifted)).invalid;
        const next = try repair.authorize(a, current, fixture.context, shifted, remaining, &packet_guidance.marked);
        try std.testing.expectEqualDeep(stable, try shifted.origins.stableTarget(next.target, 2));
        try std.testing.expectEqualDeep(remove.retry.?.key.scope, next.retry.?.key.scope);
        try std.testing.expectEqual(remove.retry.?.maximum_targets, next.retry.?.maximum_targets);
    }
}

test "a repeated statement holding the batch's only copy of an exact value is kept" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "After a successful loan renewal the service MUST display `MOCK Loan renewed!`.", .business_exact_string, true, 1);
    defer fixture.deinit();
    const items = try provenance.items(fixture.context);
    const token = items.entries[items.entries.len - 1].claim;
    var current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    current.completed = sessions.records_index;
    current.record_cursor = 0;
    const claim = try fixture.proposal("The service confirms the renewal.");
    const plain = claim.value;
    const copied: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = "The service displays " } }, .{ .exact_copy = .{ .claim_id = token.id } } } };
    const record = struct {
        fn of(content: spec.Content(spec.BusinessValue), from: spec.Model.AttributedValue) spec.Model.RecordProposal {
            return .{ .content = content, .source_group_ids = from.source_group_ids, .provenance = from.provenance };
        }
    }.of;
    const requirement_plain = record(.{ .functional_requirement = .{ .text = plain } }, claim);
    const requirement_copied = record(.{ .functional_requirement = .{ .text = copied } }, claim);
    const outcome = record(.{ .user_visible_outcome = .{ .text = copied } }, claim);
    const rule = record(.{ .business_rule = .{ .text = copied } }, claim);
    // The scenario the claim needs (ADR 0038 Decision 2). It holds no exact value, so it
    // changes no delete.
    const criterion = record(.{ .acceptance_criterion = .{ .given = plain, .when = plain, .then = plain } }, claim);
    for ([_]struct { records: []const spec.Model.RecordProposal, deleted: []const usize, kept: []const spec.Model.RecordProposal }{
        // ADR 0038 Decision 5: the outcome is the only record holding the exact value, so
        // deleting it would lose the value; it stays.
        .{ .records = &.{ requirement_plain, outcome, criterion }, .deleted = &.{}, .kept = &.{ requirement_plain, outcome, criterion } },
        // The requirement holds the value too, so the outcome is deleted.
        .{ .records = &.{ requirement_copied, outcome, criterion }, .deleted = &.{1}, .kept = &.{ requirement_copied, criterion } },
        // Each delete is decided on the batch it leaves: the first of two holders goes, and
        // the last holder of the value stays.
        .{ .records = &.{ requirement_plain, outcome, rule, criterion }, .deleted = &.{1}, .kept = &.{ requirement_plain, rule, criterion } },
    }) |case| {
        var proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = case.records } } };
        for (case.deleted) |deleted| {
            const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
            try std.testing.expectEqual(@import("domain/specification_candidate.zig").Rule.repeated_statement, rejection.issue.rule);
            const authorization = try repair.authorize(a, current, fixture.context, proposed, rejection, &packet_guidance.marked);
            try std.testing.expectEqual(deleted, authorization.target.record);
            proposed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, proposed, authorization, null, null);
        }
        _ = (try validate_unit.execute(a, current, fixture.context, proposed)).valid;
        try std.testing.expectEqualDeep(case.kept, proposed.response.content.records);
    }
}

test "a wholly taken statement whose text breaks its field's policy is deleted, never repaired" {
    // ADR 0038 Decision 5: the owner deletes a repeated statement before its own text is
    // judged. A requirement, or a statement that is the batch's only holder of an exact
    // value, is still held to its field's policy.
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    const candidate_rule = @import("domain/specification_candidate.zig").Rule;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "After a successful loan renewal the service MUST display `MOCK Loan renewed!`.", .business_exact_string, true, 1);
    defer fixture.deinit();
    const items = try provenance.items(fixture.context);
    const token = items.entries[items.entries.len - 1].claim;
    var current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    current.completed = sessions.records_index;
    current.record_cursor = 0;
    const claim = try fixture.proposal("The service confirms the renewal.");
    const copied: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = "The service displays " } }, .{ .exact_copy = .{ .claim_id = token.id } } } };
    // Recognition makes this exactly the exact value, so a prose-required field rejects it.
    const bare: spec.BusinessValue = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = token.id } }} };
    // The model writes the value as plain text; native recognition makes it the same value.
    const plain_value: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = token.content.preserved_token.value.raw_value.bytes } }} };
    const record = struct {
        fn of(content: spec.Content(spec.BusinessValue), from: spec.Model.AttributedValue) spec.Model.RecordProposal {
            return .{ .content = content, .source_group_ids = from.source_group_ids, .provenance = from.provenance };
        }
    }.of;
    const requirement_plain = record(.{ .functional_requirement = .{ .text = claim.value } }, claim);
    const requirement_copied = record(.{ .functional_requirement = .{ .text = copied } }, claim);
    const requirement_bare = record(.{ .functional_requirement = .{ .text = bare } }, claim);
    const outcome_bare = record(.{ .user_visible_outcome = .{ .text = bare } }, claim);
    const rule_bare = record(.{ .business_rule = .{ .text = bare } }, claim);
    const outcome_plain = record(.{ .user_visible_outcome = .{ .text = plain_value } }, claim);
    // The scenario the claim needs (ADR 0038 Decision 2); it holds no exact value.
    const criterion = record(.{ .acceptance_criterion = .{ .given = claim.value, .when = claim.value, .then = claim.value } }, claim);

    // Accepted: the requirement holds the value, so the defective statement is deleted.
    for ([_][]const spec.Model.RecordProposal{
        &.{ requirement_copied, outcome_bare, criterion },
        &.{ requirement_copied, rule_bare, criterion },
        &.{ requirement_copied, outcome_bare, rule_bare, criterion },
        &.{ requirement_copied, outcome_plain, criterion },
    }) |records| {
        var proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = records } } };
        for (records[1 .. records.len - 1]) |_| {
            const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
            try std.testing.expectEqual(candidate_rule.repeated_statement, rejection.issue.rule);
            try std.testing.expect(rejection.issue.text_issue == null);
            const authorization = try repair.authorize(a, current, fixture.context, proposed, rejection, &packet_guidance.marked);
            proposed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, proposed, authorization, null, null);
        }
        try std.testing.expectEqualDeep(&[_]spec.Model.RecordProposal{ requirement_copied, criterion }, proposed.response.content.records);
        _ = (try validate_unit.execute(a, current, fixture.context, proposed)).valid;
    }

    // Rejected: the statement is the only holder of the exact value, so deleting it would
    // lose the value; it keeps its text defect, which no unit repair can fix.
    const only_holder: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ requirement_plain, outcome_bare } } } };
    const kept = (try validate_unit.execute(a, current, fixture.context, only_holder)).invalid;
    try std.testing.expectEqual(candidate_rule.typed_text, kept.issue.rule);
    try std.testing.expectEqual(.reference_only, kept.issue.text_issue.?.reason);
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, only_holder, kept, &packet_guidance.marked));
    const only_plain: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ requirement_plain, outcome_plain } } } };
    const kept_plain = (try validate_unit.execute(a, current, fixture.context, only_plain)).invalid;
    try std.testing.expectEqual(candidate_rule.typed_text, kept_plain.issue.rule);
    try std.testing.expectEqual(.reference_only, kept_plain.issue.text_issue.?.reason);

    // Rejected: a requirement is never deleted, whatever else holds the value.
    const requirement_first: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ requirement_bare, requirement_copied } } } };
    const requirement = (try validate_unit.execute(a, current, fixture.context, requirement_first)).invalid;
    try std.testing.expectEqual(candidate_rule.typed_text, requirement.issue.rule);
    try std.testing.expectEqual(.reference_only, requirement.issue.text_issue.?.reason);

    // Rejected: with nothing taking its claims, a lone defective statement keeps its defect.
    const lone: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{outcome_bare} } } };
    const untaken = (try validate_unit.execute(a, current, fixture.context, lone)).invalid;
    try std.testing.expectEqual(candidate_rule.typed_text, untaken.issue.rule);

    // Accepted: another record's exact value can't be identified (here a copy of a claim that
    // holds none). That record is kept and holds nothing for the others, but it doesn't stop the delete.
    const unrecognizable = record(.{ .business_rule = .{ .text = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = .{ .ordinal = 9999 } } }} } } }, claim);
    const mixed: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ requirement_copied, outcome_bare, unrecognizable } } } };
    const deleted = (try validate_unit.execute(a, current, fixture.context, mixed)).invalid;
    try std.testing.expectEqual(candidate_rule.repeated_statement, deleted.issue.rule);
    try std.testing.expectEqual(@as(usize, 1), deleted.issue.field.target.record);
}

/// The records of `records` that the records validator deletes natively as repeated statements,
/// in the original numbering, applying its deletes one at a time as the repair route does.
fn deletedByValidator(a: std.mem.Allocator, current: @import("domain/specification_session.zig").Session, context: provenance.Context, records: []const spec.Model.RecordProposal) ![]const usize {
    const repair = @import("domain/specification_repair.zig");
    var live: std.ArrayList(usize) = .empty;
    for (0..records.len) |index| try live.append(a, index);
    var deleted: std.ArrayList(usize) = .empty;
    while (true) {
        const batch = try a.alloc(spec.Model.RecordProposal, live.items.len);
        for (live.items, batch) |original, *slot| slot.* = records[original];
        const proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = batch } } };
        const result = try validate_unit.execute(a, current, context, proposed);
        if (result != .invalid or result.invalid.issue.rule != .repeated_statement) break;
        const at = result.invalid.issue.field.target.record;
        try deleted.append(a, live.items[at]);
        _ = live.orderedRemove(at);
    }
    std.mem.sort(usize, deleted.items, {}, std.sort.asc(usize));
    return deleted.items;
}

/// The records whose text defects response admission reports for `records`, as the wire
/// carries them, with and without ADR 0038 Decision 5's exemption.
fn admissionReports(a: std.mem.Allocator, context: provenance.Context, records: []const spec.Model.RecordProposal, exempting: bool) ![]const usize {
    const composition = @import("domain/model_text_composition.zig");
    const json = @import("domain/model_candidate_json.zig");
    const wire = try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, context, .{ .content = .{ .records = records } }));
    const document = try @import("domain/strict_json.zig").parse(a, wire, .{ .maximum_depth = @import("domain/model_result_schema.zig").max_json_depth }, false, null);
    const scope: @import("domain/model_exact_values.zig").Scope = .{
        .reference_state = (try provenance.items(context)).state_id,
        .occurrences = try provenance.exactOccurrences(a, @import("domain/reference_support.zig").records(context.references), null),
    };
    const statements: composition.Statements = .{ .path = &.{ .{ .property = "records" }, .items, .{ .property = "claim_ids" } }, .rule = @import("domain/specification_session.zig").statement_rule };
    const diagnostic = (try composition.check(a, document.value, try json.fieldBindings(g.ModelResponse, a, .{}), &.{}, &.{}, .{ .exact_scope = scope, .statements = if (exempting) statements else null })) orelse return &.{};
    var reported: std.ArrayList(usize) = .empty;
    for (diagnostic.fields) |field| {
        const prefix = "/records/";
        try std.testing.expect(std.mem.startsWith(u8, field.path, prefix));
        const end = std.mem.indexOfScalarPos(u8, field.path, prefix.len, '/') orelse return error.TestUnexpectedResult;
        const index = try std.fmt.parseInt(usize, field.path[prefix.len..end], 10);
        if (std.mem.indexOfScalar(usize, reported.items, index) == null) try reported.append(a, index);
    }
    std.mem.sort(usize, reported.items, {}, std.sort.asc(usize));
    return reported.items;
}

test "response admission exempts only statements the records validator deletes" {
    // ADR 0038 Decision 5: admission reads the wire and unit validation reads typed records, so
    // the two must reach the same delete. Over each batch, the records admission stops reporting
    // are a subset of those the validator deletes, and a record holding an exact value no other
    // record holds is deleted by neither.
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "After a successful loan renewal the service MUST display `MOCK Loan renewed!`.", .business_exact_string, true, 1);
    defer fixture.deinit();
    const items = try provenance.items(fixture.context);
    const token = items.entries[items.entries.len - 1].claim;
    const raw = token.content.preserved_token.value.raw_value.bytes;
    var current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    current.completed = sessions.records_index;
    current.record_cursor = 0;
    const claim = try fixture.proposal("The service confirms the renewal.");
    const value = struct {
        fn of(segments: []const @import("domain/typed_text.zig").BusinessSegment) spec.BusinessValue {
            return .{ .segments = segments };
        }
    }.of;
    const bare = value(&.{.{ .exact_copy = .{ .claim_id = token.id } }});
    const copied = value(&.{ .{ .literal = .{ .value = "The service displays " } }, .{ .exact_copy = .{ .claim_id = token.id } } });
    const unscalar = value(&.{.{ .literal = .{ .value = try std.mem.concat(a, u8, &.{ raw, " \x01" }) } }});
    const record = struct {
        fn of(content: spec.Content(spec.BusinessValue), from: spec.Model.AttributedValue) spec.Model.RecordProposal {
            return .{ .content = content, .source_group_ids = from.source_group_ids, .provenance = from.provenance };
        }
    }.of;
    const requirement_plain = record(.{ .functional_requirement = .{ .text = claim.value } }, claim);
    const requirement_copied = record(.{ .functional_requirement = .{ .text = copied } }, claim);
    const outcome_bare = record(.{ .user_visible_outcome = .{ .text = bare } }, claim);
    const outcome_plain = record(.{ .user_visible_outcome = .{ .text = value(&.{.{ .literal = .{ .value = raw } }}) } }, claim);
    const outcome_unscalar = record(.{ .user_visible_outcome = .{ .text = unscalar } }, claim);
    const rule_bare = record(.{ .business_rule = .{ .text = bare } }, claim);
    // Insertion syntax in prose is a composition defect whose control character the wire ignores.
    const assumption_unscalar = record(.{ .assumption = .{ .text = value(&.{.{ .literal = .{ .value = "Assume {\"kind\":\"exact_copy\"} \x01" } }}) } }, claim);
    const rule_copied = record(.{ .business_rule = .{ .text = copied } }, claim);
    // An assumption forbids exact copies, so its value is plain text and has no defect to exempt.
    const assumption_plain = record(.{ .assumption = .{ .text = value(&.{.{ .literal = .{ .value = raw } }}) } }, claim);
    const non_goal_bare = record(.{ .non_goal = .{ .text = bare } }, claim);
    const prohibition_bare = record(.{ .prohibited_behavior = .{ .text = bare } }, claim);
    const criterion_unscalar = record(.{ .acceptance_criterion = .{ .given = claim.value, .when = claim.value, .then = unscalar } }, claim);
    const Row = struct { records: []const spec.Model.RecordProposal, exempt: []const usize, deleted: []const usize };
    const rows = [_]Row{
        // A requirement holds the value the statements repeat, whatever their kind or spelling.
        .{ .records = &.{ requirement_copied, outcome_bare }, .exempt = &.{1}, .deleted = &.{1} },
        .{ .records = &.{ requirement_copied, outcome_plain }, .exempt = &.{1}, .deleted = &.{1} },
        .{ .records = &.{ requirement_copied, assumption_plain, non_goal_bare, prohibition_bare }, .exempt = &.{ 2, 3 }, .deleted = &.{ 1, 2, 3 } },
        // The only holder of the value is kept, as is the last of two.
        .{ .records = &.{ requirement_plain, outcome_bare }, .exempt = &.{}, .deleted = &.{} },
        .{ .records = &.{ requirement_plain, outcome_bare, rule_bare }, .exempt = &.{1}, .deleted = &.{1} },
        // A value in text that is not a valid scalar can't be identified, so its record is kept
        // and holds nothing for the others.
        .{ .records = &.{ requirement_plain, outcome_unscalar }, .exempt = &.{}, .deleted = &.{} },
        .{ .records = &.{ requirement_plain, outcome_bare, criterion_unscalar }, .exempt = &.{}, .deleted = &.{} },
        // An assumption forbids exact copies, so text that is not a valid scalar hides no exact
        // value there: its record is judged like any other, by both layers.
        .{ .records = &.{ requirement_plain, assumption_unscalar }, .exempt = &.{1}, .deleted = &.{1} },
        // An earlier statement takes its claims for a later one, never the reverse: here the
        // earlier statement is the defective one and nothing takes it, so it keeps its defect.
        .{ .records = &.{ outcome_bare, rule_copied }, .exempt = &.{}, .deleted = &.{} },
        .{ .records = &.{ rule_copied, outcome_bare }, .exempt = &.{1}, .deleted = &.{1} },
    };
    for (rows, 0..) |row, row_index| {
        errdefer std.debug.print("statement parity row {d} failed\n", .{row_index});
        const exempt = try admissionReports(a, fixture.context, row.records, false);
        const kept = try admissionReports(a, fixture.context, row.records, true);
        var exempted: std.ArrayList(usize) = .empty;
        for (exempt) |index| if (std.mem.indexOfScalar(usize, kept, index) == null) try exempted.append(a, index);
        const deleted = try deletedByValidator(a, current, fixture.context, row.records);
        try std.testing.expectEqualSlices(usize, row.exempt, exempted.items);
        try std.testing.expectEqualSlices(usize, row.deleted, deleted);
        for (exempted.items) |index| try std.testing.expect(std.mem.indexOfScalar(usize, deleted, index) != null);
    }
}

test "a record's part in the repeated-statement rule is the part the request's coverage gives its kind" {
    // The wire reads a kind's part from the recorded coverage kinds, the validator and the
    // session from the kind itself. Both must agree for every kind.
    const rule = @import("domain/specification_session.zig").statement_rule;
    const ownership = @import("domain/statement_ownership.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const listed = struct {
        fn in(kinds: []const []const u8, name: []const u8) bool {
            for (kinds) |kind| if (std.mem.eql(u8, kind, name)) return true;
            return false;
        }
    }.in;
    inline for (comptime std.meta.tags(spec.Kind)) |kind| {
        const content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, .{ .segments = &.{} }));
        const expected: ownership.Role = if (listed(rule.owning, @tagName(kind))) .owning else if (listed(rule.exclusive, @tagName(kind))) .exclusive else .other;
        try std.testing.expectEqual(expected, (try g.statementRecord(a, content, &.{})).role);
    }
}

test "ADR 0035 story restatement keeps functional requirements and needs covered evidence" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "Display a startup greeting. Show the current UTC date and time.";
    var fixture = try Fixture.initContent(a, source, null, true, 2);
    defer fixture.deinit();
    const story = try fixture.value("The visitor sees a greeting.");
    const other = try fixture.value("The visitor sees the time.");
    const record = struct {
        fn of(comptime kind: spec.Kind, value: spec.AttributedValue) spec.RecordProposal {
            return .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, value.value)), .source_group_ids = value.source_group_ids, .provenance = value.provenance };
        }
    }.of;
    // Every single-statement kind except a functional requirement restates the story.
    inline for (.{ spec.Kind.business_rule, spec.Kind.assumption, spec.Kind.non_goal, spec.Kind.prohibited_behavior, spec.Kind.user_visible_outcome }) |kind| {
        try std.testing.expect(try g.restatesStory(a, story, record(kind, story)));
    }
    try std.testing.expect(!try g.restatesStory(a, story, record(.functional_requirement, story)));
    // Multi-field kinds and different wording never restate it.
    try std.testing.expect(!try g.restatesStory(a, story, record(.acceptance_criterion, story)));
    try std.testing.expect(!try g.restatesStory(a, story, record(.edge_case, story)));
    try std.testing.expect(!try g.restatesStory(a, story, record(.business_rule, other)));
    // Identical wording whose evidence the story doesn't cover stays in place.
    var uncovered = record(.business_rule, story);
    uncovered.source_group_ids = &.{fixture.context.references.records.signals[1].id};
    uncovered.provenance.claim_ids = &.{.{ .ordinal = 2 }};
    try std.testing.expect(!try g.restatesStory(a, story, uncovered));
}

test "a business rule that restates the story is deleted natively and coverage holds" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    const story = try fixture.proposal("A borrower can renew an active loan.");
    const requirement = try fixture.proposal("The system renews an eligible loan.");
    var current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    while (current.completed < sessions.records_index) {
        const response: g.Response = .{ .content = switch (try sessions.unit(current.completed)) {
            .brief => .{ .brief = .{ .description = story, .primary_goal = story } },
            .primary_user_story => .{ .primary_user_story = story },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = story } },
            .records => unreachable,
        } };
        current = try appendMockResponse(a, current, fixture.context, response);
    }
    const fr: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = requirement.value } }, .source_group_ids = requirement.source_group_ids, .provenance = requirement.provenance };
    const ac: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = requirement.value, .when = requirement.value, .then = requirement.value } }, .source_group_ids = requirement.source_group_ids, .provenance = requirement.provenance };
    const rule: spec.Model.RecordProposal = .{ .content = .{ .business_rule = .{ .text = story.value } }, .source_group_ids = story.source_group_ids, .provenance = story.provenance };
    const proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ fr, rule, ac } } } };
    const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
    try std.testing.expectEqual(.restatement, rejection.issue.rule);
    try std.testing.expect(rejection.issue.blocked == null);
    // The session rule binds the observed model record for the old-value precondition.
    try std.testing.expectEqualDeep(@as(@import("domain/specification_candidate.zig").Replacement, .{ .record = rule }), rejection.issue.observed.?);
    const authorization = try repair.authorize(a, current, fixture.context, proposed, rejection, &packet_guidance.marked);
    try std.testing.expectEqual(@as(usize, 1), authorization.target.record);
    const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, proposed, authorization, null, null);
    try std.testing.expectEqual(@as(usize, 2), merged.response.content.records.len);
    try std.testing.expectEqualDeep(fr, merged.response.content.records[0]);
    try std.testing.expectEqualDeep(ac, merged.response.content.records[1]);
    try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
    const checked = (try validate_unit.execute(a, current, fixture.context, merged)).valid;
    // The remaining specification still assembles with complete claim coverage.
    _ = try sessions.assemble(a, text.validator, fixture.context, try sessions.appendBound(a, current, checked), &.{});
    // A functional requirement with the story's wording is kept.
    const story_requirement: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = story.value } }, .source_group_ids = story.source_group_ids, .provenance = story.provenance };
    _ = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &.{ story_requirement, ac } } } })).valid;
}

fn sessionAtRecords(a: std.mem.Allocator, fixture: *const Fixture, story: spec.Model.AttributedValue) !@import("domain/specification_session.zig").Session {
    const sessions = @import("domain/specification_session.zig");
    var current = (try sessions.initialize(a, .{ .bytes = "selected" }, fixture.context)).ready;
    while (current.completed < sessions.records_index) {
        const response: g.Response = .{ .content = switch (try sessions.unit(current.completed)) {
            .brief => .{ .brief = .{ .description = story, .primary_goal = story } },
            .primary_user_story => .{ .primary_user_story = story },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = story } },
            .records => unreachable,
        } };
        current = try appendMockResponse(a, current, fixture.context, response);
    }
    return current;
}

test "ADR 0035 restatements use production evidence shapes and keep uncovered wording" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = "Display a startup greeting. Show the current UTC date and time.";
    const wording = "The visitor sees a greeting with the time.";
    var fixture = try Fixture.initContent(a, source, null, true, 2);
    defer fixture.deinit();
    const other = try fixture.proposal("The visitor sees the time.");
    const fr: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = other.value } }, .source_group_ids = other.source_group_ids, .provenance = other.provenance };
    const ac: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = other.value, .when = other.value, .then = other.value } }, .source_group_ids = other.source_group_ids, .provenance = other.provenance };
    // The story cites every group; a batch record cites only its own group.
    {
        const story = try fixture.proposalAllGroups(wording);
        const bound = try fixture.proposal(wording);
        const rule: spec.Model.RecordProposal = .{ .content = .{ .business_rule = .{ .text = bound.value } }, .source_group_ids = bound.source_group_ids, .provenance = bound.provenance };
        const current = try sessionAtRecords(a, &fixture, story);
        const proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ fr, ac, rule } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        try std.testing.expectEqual(.restatement, rejection.issue.rule);
        try std.testing.expectEqual(@as(usize, 2), (try repair.authorize(a, current, fixture.context, proposed, rejection, &packet_guidance.marked)).target.record);
    }
    // A competing same-kind pair across batches is decided before any restatement.
    {
        const story = try fixture.proposal("The visitor sees a greeting.");
        var current = try sessionAtRecords(a, &fixture, story);
        const earlier: spec.Model.RecordProposal = .{ .content = .{ .non_goal = .{ .text = other.value } }, .source_group_ids = other.source_group_ids, .provenance = other.provenance };
        const first = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &.{ ac, earlier } } } })).valid;
        current = try sessions.appendBound(a, current, first);
        var second_requirement = fr;
        second_requirement.source_group_ids = &.{fixture.context.references.records.signals[1].id};
        second_requirement.provenance.claim_ids = &.{.{ .ordinal = 2 }};
        var second_non_goal = earlier;
        second_non_goal.source_group_ids = second_requirement.source_group_ids;
        second_non_goal.provenance = second_requirement.provenance;
        const rejection = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &.{ second_requirement, second_non_goal } } } })).invalid;
        try std.testing.expectEqual(.duplicate_record, rejection.issue.rule);
        try std.testing.expectEqual(.competing_records, rejection.issue.blocked.?);
    }
    // A second-batch record with the story's wording but evidence the story
    // doesn't cite is admitted unchanged.
    {
        const story = try fixture.proposal(wording);
        var current = try sessionAtRecords(a, &fixture, story);
        const first = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &.{ fr, ac } } } })).valid;
        current = try sessions.appendBound(a, current, first);
        var uncovered: spec.Model.RecordProposal = .{ .content = .{ .business_rule = .{ .text = story.value } }, .source_group_ids = &.{fixture.context.references.records.signals[1].id}, .provenance = story.provenance };
        uncovered.provenance.claim_ids = &.{.{ .ordinal = 2 }};
        // Its claim needs a scenario of the batch (ADR 0038 Decision 2).
        var criterion = ac;
        criterion.content = .{ .acceptance_criterion = .{ .given = story.value, .when = story.value, .then = story.value } };
        criterion.source_group_ids = uncovered.source_group_ids;
        criterion.provenance = uncovered.provenance;
        const checked = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &.{ uncovered, criterion } } } })).valid;
        try std.testing.expect(checked.response.content.records[0].content == .business_rule);
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
        const brief: g.Brief = .{ .description = value, .primary_goal = value };
        var content: spec.IdentifiedContent = .{ .display_name = fixture_display_name, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = &.{} };
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
        try std.testing.expectError(error.InvalidSpecificationCoverage, coverage.validate(a, fixture.context.references, .{ .description = missing, .primary_goal = missing }, content));
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
        var fixture = try Fixture.initContent(a, example.source, .business_exact_string, true, 1);
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
                .brief => .{ .brief = .{ .description = story, .primary_goal = story } },
                .primary_user_story => .{ .primary_user_story = story },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = story } },
                .records => .{ .records = try std.mem.concat(a, spec.Model.RecordProposal, &.{ &.{criterion}, &requirements }) },
            } };
            // The story has no model wire form (ADR 0047).
            const decoded = if (unit == .primary_user_story) response else try g.parse(a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, response)), try sessions.currentBinding(a, current, fixture.context));
            current = try appendMockResponse(a, current, fixture.context, decoded);
        }
        const content = (try sessions.assemble(a, text.validator, fixture.context, current, &.{})).content;
        const brief = current.units[0].?.response.content.brief;
        const accounted = try coverage.validate(a, fixture.context.references, brief, content);
        try std.testing.expectEqual(items.entries.len, accounted.accounts.len);
        try std.testing.expectEqual(@as(usize, 1), accounted.obligations.len);
        const document = try projection.project(a, fixture.context, test_directory, content);
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
        // ADR 0047: the story's exact value is recognised, but it discharges no
        // exact-copy duty; the criterion's copy alone satisfies the obligation.
        var exact_segments: usize = 0;
        for (linked_story.value.segments) |segment| exact_segments += @intFromBool(segment == .exact_copy);
        try std.testing.expectEqual(@as(usize, 1), exact_segments);
        var referenced = content;
        referenced.primary_user_story = linked_story;
        const restored = try coverage.validate(a, fixture.context.references, brief, referenced);
        for (restored.obligations[0].exact_targets) |target| try std.testing.expect(target != .primary_user_story);
        // Only the recommended requirement, which holds no copy, stays beside the story.
        var story_only = referenced;
        story_only.records = content.records[2..3];
        try std.testing.expectError(error.InvalidSpecificationCoverage, coverage.validate(a, fixture.context.references, brief, story_only));
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
    const candidate: candidates.Candidate = .{ .origins = .{ .initial = initial }, .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = bad } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectEqual(.typed_text, rejected.issue.rule);
    try std.testing.expectEqual(.InvalidTypedText, rejected.issue.native_error.?);
    try std.testing.expectEqualDeep(initial, rejected.origin.?);
    try std.testing.expectEqualDeep(bad.value, rejected.issue.observed.?.value);
    const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
    const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = good.value }, correction);
    const sibling = (try validate_unit.execute(a, current, fixture.context, merged)).invalid;
    try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
    const sibling_authorization = try repair.authorize(a, current, fixture.context, merged, sibling, &packet_guidance.marked);
    try std.testing.expect(!std.meta.eql(authorization.retry.?.key, sibling_authorization.retry.?.key));
    try std.testing.expectEqualDeep(authorization.retry.?.key.scope, sibling_authorization.retry.?.key.scope);
    try std.testing.expectEqual(authorization.retry.?.maximum_targets, sibling_authorization.retry.?.maximum_targets);
    try std.testing.expect(sibling.issue.field.target.value.subject == .primary_goal);
    try std.testing.expectEqualDeep(initial, sibling.origin.?);
    try std.testing.expectEqualDeep(correction, merged.origins.at(.{ .target = .{ .value = .{ .subject = .description, .field = .value } } }).?);
    try std.testing.expectEqualDeep(initial, merged.origins.at(.{ .target = .{ .value = .{ .subject = .primary_goal, .field = .value } } }).?);
    const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = bad.value }, correction);
    const again = (try validate_unit.execute(a, current, fixture.context, unchanged)).invalid;
    try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, unchanged)).?.validated.result);
    const repeated = try repair.authorize(a, current, fixture.context, unchanged, again, &packet_guidance.marked);
    try std.testing.expectEqualDeep(authorization.retry.?.key, repeated.retry.?.key);
    const changed_invalid = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "\x01" } }} } }, correction);
    try std.testing.expect(changed_invalid.last_repair.?.changed);
    try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, changed_invalid)).?.validated.result);
    try std.testing.expectEqualDeep(authorization.retry.?.key, (try repair.authorize(a, current, fixture.context, changed_invalid, (try validate_unit.execute(a, current, fixture.context, changed_invalid)).invalid, &packet_guidance.marked)).retry.?.key);
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
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, foreign, &packet_guidance.marked));
    }
    var wrong = candidate;
    wrong.response = .{ .content = .{ .primary_user_story = good } };
    const wrong_unit = (try validate_unit.execute(a, current, fixture.context, wrong)).invalid;
    try std.testing.expectEqual(.unit_kind, wrong_unit.issue.rule);
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, wrong, wrong_unit, &packet_guidance.marked));
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
    const candidate: @import("domain/specification_candidate.zig").Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = good } } } };
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(rejectionAllocationCase, .{ fixture.context, current, candidate, good });
}
fn rejectionAllocationCase(allocator: std.mem.Allocator, context: provenance.Context, current: @import("domain/specification_session.zig").Session, candidate: @import("domain/specification_candidate.zig").Candidate, good: spec.Model.AttributedValue) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const repair = @import("domain/specification_repair.zig");
    const rejected = (try validate_unit.execute(a, current, context, candidate)).invalid;
    const diagnostic: @import("domain/candidate_validation_diagnostic.zig").Diagnostic = .{ .specification = rejected };
    _ = try diagnostic.copy(a);
    const authorization = try repair.authorize(a, current, context, candidate, rejected, &packet_guidance.marked);
    const packet = try repair.packet(allocator, current, context, authorization, &packet_guidance.marked);
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
        const authorized = try repair.authorize(a, current, fixture.context, proposed, rejected, &packet_guidance.marked);
        const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, proposed, authorized, .{ .value = good.value }, corrected);
        try std.testing.expectEqualDeep(record.content.acceptance_criterion.when, fixed.response.content.records[0].content.acceptance_criterion.when);
        try std.testing.expectEqualDeep(record.content.acceptance_criterion.then, fixed.response.content.records[0].content.acceptance_criterion.then);
        const text_failure = (try validate_unit.execute(a, current, fixture.context, fixed)).invalid;
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, fixed)).?.validated.result);
        try std.testing.expectEqualDeep(candidates.Target{ .value = .{ .subject = .{ .record = 0 }, .field = field } }, text_failure.issue.field.target);
        try std.testing.expectEqualDeep(initial, text_failure.origin.?);
        const text_authorized = try repair.authorize(a, current, fixture.context, fixed, text_failure, &packet_guidance.marked);
        const complete = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, fixed, text_authorized, .{ .value = good.value }, corrected);
        _ = (try validate_unit.execute(a, current, fixture.context, complete)).valid;
        try std.testing.expectEqualDeep(good.provenance, complete.response.content.records[0].provenance);
        try std.testing.expectEqualDeep(good.value, complete.response.content.records[0].content.acceptance_criterion.given);
        try std.testing.expectEqualDeep(record.content.acceptance_criterion.when, complete.response.content.records[0].content.acceptance_criterion.when);
        // The selected response cannot carry valid business text as a side effect.
        const packet = try repair.packet(a, current, fixture.context, authorized, &packet_guidance.marked);
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
        // Distinct from the story, so ADR 0035's restatement rule leaves it in place.
        const visible = try fixture.proposal("The requested outcome is visible.");
        const record: spec.Model.RecordProposal = .{ .content = .{ .user_visible_outcome = .{ .text = visible.value } }, .source_group_ids = visible.source_group_ids, .provenance = visible.provenance };
        var exact_only = record;
        exact_only.content.user_visible_outcome.text = normalized;
        var inspection: provenance.Inspection = .{};
        try std.testing.expectError(error.InvalidTypedText, provenance.inspectRecord(.model, a, text.validator, fixture.context, exact_only, &inspection));
        try std.testing.expectEqual(.reference_only, inspection.text_issue.?.reason);
        const named = try fixture.proposalAllGroups("The requested outcome is named.");
        var current = (try sessions.initialize(a, .{ .bytes = "chosen" }, fixture.context)).ready;
        // The outcome's claims need a scenario of its batch (ADR 0038 Decision 2); its
        // fields copy no exact value, so the exact-copy gap stays.
        const criterion: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = good.value, .when = good.value, .then = good.value } }, .source_group_ids = visible.source_group_ids, .provenance = visible.provenance };
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .description = named, .primary_goal = good } },
                .primary_user_story => .{ .primary_user_story = good },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
                .records => .{ .records = &.{ record, criterion } },
            } };
            current = try appendMockResponse(a, current, fixture.context, response);
        }
        const identified = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
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
        const embedded_content = try sessions.assemble(a, text.validator, fixture.context, embedded, &.{});
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
        const omitted = try sessions.assemble(a, text.validator, fixture.context, unsupported, &.{});
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
            const candidate: candidates.Candidate = .{ .response = .{ .content = if (record) .{ .records = &.{.{ .content = .{ .acceptance_criterion = .{ .given = bad.value, .when = good.value, .then = good.value } }, .source_group_ids = bad.source_group_ids, .provenance = bad.provenance }} } else .{ .brief = .{ .description = bad, .primary_goal = good } } } };
            const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
            const auth = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
            const packet = try repair.packet(a, current, fixture.context, auth, &packet_guidance.marked);
            defer packets.release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const input = body.value.object.get("input").?.object;
            // These fixtures have no accepted brief to supply as a dependency, and a
            // repair never receives the entity decision.
            try std.testing.expect(!input.contains("brief"));
            try std.testing.expect(!input.contains("entities"));
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
            try std.testing.expectEqual(@as(usize, 0), input.get("exact_texts").?.array.items.len);
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
    const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = value, .primary_goal = value } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
    const choices = auth.rule.value_choices.?;
    try std.testing.expectEqualDeep(&[_]@import("domain/typed_text.zig").ExactCopy{.{ .claim_id = selected.id }}, choices.exact_copy);
    const packet = try repair.packet(a, current, fixture.context, auth, &packet_guidance.marked);
    defer packets.release(packet);
    const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    try std.testing.expect(body.value.object.get("repair").?.object.get("rule").?.object.get("value_choices") == null);
    try std.testing.expectEqual(@as(usize, 1), body.value.object.get("input").?.object.get("exact_texts").?.array.items.len);
    const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, auth, .{ .value = .{ .segments = &.{ .{ .literal = .{ .value = "Show " } }, .{ .exact_copy = choices.exact_copy[0] } } } }, null);
    try std.testing.expectEqualDeep(value.provenance, merged.response.content.brief.description.provenance);
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
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
        const packet = try reviewPacketAt(support, a, inputs, fixture.context, 0);
        defer @import("domain/model_input_packet.zig").release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        const feature_id = (try @import("domain/required_authority.zig").build(a, inputs)).requirements[0].seed.id;
        try expectReviewAssessmentScope(a, .{ .object = body }, feature_id);
        try std.testing.expect(feature_id.unit == .feature);
        try std.testing.expectEqualStrings("source_preservation", body.get("subject").?.object.get("kind").?.string);
        try std.testing.expectEqualStrings(packet_guidance.marked.review_scope.source_preservation, body.get("assessment_scope").?.object.get("instruction").?.string);
        const preservation_inputs = try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs);
        const source_id = try support.nextSubject(a, preservation_inputs, null);
        try std.testing.expect(source_id.unit == .source);
        const source_packet = try support.packetFor(std.testing.allocator, preservation_inputs, fixture.context, &packet_guidance.marked, .{ .finding = source_id });
        defer @import("domain/model_input_packet.zig").release(source_packet);
        const source_body = (try std.json.parseFromSlice(std.json.Value, a, source_packet.body(), .{})).value;
        try expectReviewAssessmentScope(a, source_body, source_id);
        try std.testing.expectEqualStrings("reference", source_body.object.get("subject").?.object.get("kind").?.string);
        const selected_source = try json.decode(@import("domain/specification_review_subject.zig").Subject, a, try std.json.Stringify.valueAlloc(a, source_body.object.get("subject").?, .{}));
        try std.testing.expectEqualDeep(source_id.unit.source, selected_source.reference.source);
        try std.testing.expectEqualStrings(packet_guidance.marked.review_scope.reference.get(.source), source_body.object.get("assessment_scope").?.object.get("instruction").?.string);
        try std.testing.expectEqualStrings(fixture.context.inputs.corpus.sources[0].bytes, source_body.object.get("sources").?.array.items[0].object.get("text").?.string);
        try std.testing.expectEqual(@as(usize, 0), source_body.object.get("claims").?.array.items.len);
        try std.testing.expectEqualStrings(fixture.context.inputs.corpus.sources[0].bytes, body.get("sources").?.array.items[0].object.get("text").?.string);
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
        try std.testing.expectError(error.InvalidRequiredAuthority, gaps.build(a, fixture.context.inputs, admitted, decision.observations, decision.result, &packet_guidance.marked));
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
        try std.testing.expectEqual(findings.len, (try gaps.build(a, fixture.context.inputs, missing, unresolved.observations, unresolved.result, &packet_guidance.marked)).entries.len);
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
    const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = good } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
    const original = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
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
    const same_presentation = try sessions.packet(a, current, context, &packet_guidance.marked);
    defer packets.release(same_presentation);
    try std.testing.expectEqualStrings(original.body(), same_presentation.body());
    try std.testing.expectError(error.InvalidPathTokenGrammar, validate_unit.execute(a, current, context, candidate));
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, context, candidate, rejected, &packet_guidance.marked));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, current, context, auth, &packet_guidance.marked));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), current, context, candidate, auth, .{ .value = good.value }, null));
    context = fixture.context;
    try std.testing.expect(context.references.records.assignments.checked.prior.prior.input.progress.summary_count > 0);
    context.references.records.assignments.checked.prior.prior.input.progress.latest = null;
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.authorize(a, current, context, candidate, rejected, &packet_guidance.marked));
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.packet(a, current, context, auth, &packet_guidance.marked));
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), current, context, candidate, auth, .{ .value = good.value }, null));
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

test "source membership guidance remains distinct from claims through review repair and readback" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
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
        const inputs = try readinessSupportInputs(&fixture);
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
        const insertion = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, missing.candidate.?, try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, missing));
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
        const authorization = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected);
        const correction = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, authorization);
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
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, inputs, stale, &packet_guidance.marked, rejected.candidate.?, authorization));
        const unchanged = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, authorization, authorization.operation.replace, null)).rejected;
        try std.testing.expectEqualDeep(rejected.candidate.?.review, unchanged.candidate.?.review);
        try std.testing.expectEqual(.invalid_sources, unchanged.rejection.selected().?.evidence.?.issue);
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = findings[1].value.provenance, .source_ids = allowed } }, null)).accepted;
        for (findings, fixed.candidate.review.entries, 0..) |before, after, index| {
            if (index != 1) try std.testing.expectEqualDeep(before, after) else {
                try std.testing.expectEqualDeep(before.value.provenance, after.value.provenance);
                try std.testing.expectEqual(before.value.kind, after.value.kind);
            }
        }
    }
}

test "readiness source-purpose positives select original sources through production wire without authored provenance" {
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const model = @import("domain/specification_support_model.zig");
    const authority = @import("domain/required_authority.zig");
    const packets = @import("domain/model_input_packet.zig");
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const positive = "{\"kind\":\"supported\",\"source_ids\":[1],\"detail\":\"The selected original source establishes this purpose before authoring.\"}";
    for ([_][]const u8{ "Display the current UTC time on startup.", "A borrower may renew an eligible loan and see the new deadline." }) |source| {
        for ([_]usize{ 0, 1, 3 }) |count| {
            var fixture = try Fixture.initContent(a, source, null, count != 0, @max(count, 1));
            defer fixture.deinit();
            const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
            const ledger = try authority.build(a, inputs);
            const id = ledger.requirements[0].seed.id;
            const required = try admission.requirements(a, inputs, fixture.context.inputs, id);
            try std.testing.expectEqual(.original_sources, required.positive_evidence);
            try std.testing.expectEqual(count, required.eligible_claim_ids.len);
            const rule = required.rule(.supported, .{ .unlocalized = .{} });
            try std.testing.expectEqual(.source_required, rule.minimum);
            try std.testing.expect(rule.claims == .exact and rule.claims.exact.len == 0);
            const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, .{ .finding = id });
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
            const first = try support.collectFocused(a, inputs, fixture.context, &packet_guidance.marked, null, packet, positive, original);
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
                const rejected = (try support.collectFocused(a, inputs, fixture.context, &packet_guidance.marked, null, packet, bad.wire, original)).rejected;
                try std.testing.expectEqual(bad.issue, rejected.rejection.selected().?.evidence.?.issue);
            }
            const forged_wire = "{\"kind\":\"supported\",\"source_ids\":[1],\"detail\":\"\",\"provenance\":{\"claim_ids\":[1]}}";
            try check(schema.modelBytes(), .{ .bytes = forged_wire, .rejection = .unknown_property, .path = "/provenance" });
            try std.testing.expectError(error.InvalidJsonDocument, model.decode(a, forged_wire, required));
            var stale = inputs;
            // Before authoring the reference snapshot is the current owner;
            // an unrelated candidate revision counter supplies no authority.
            stale.references.?.items.state_id.bytes = "stale-reference-state";
            try std.testing.expectError(error.InvalidRequiredAuthority, support.collectFocused(a, stale, fixture.context, &packet_guidance.marked, null, packet, positive, original));

            // Complete every required subject through the production packet,
            // selected schema, decoder and collector, without canonical fakes.
            const good = try reviewFor(a, inputs, fixture.context.inputs);
            var collected: ?support.Collection = null;
            for (ledger.requirements, good.entries, 0..) |requirement, finding, index| {
                const current_packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, .{ .finding = requirement.seed.id });
                defer packets.release(current_packet);
                const wire = try sourceReviewWire(a, inputs, fixture.context, requirement.seed.id, finding.value);
                try check(schemas.select(current_packet.resultDefinition().?).?.modelBytes(), .{ .bytes = wire });
                collected = try support.collectFocused(a, inputs, fixture.context, &packet_guidance.marked, collected, current_packet, wire, .{ .request = .{ .value = @intCast(800 + index) }, .attempt = .{ .value = 1 } });
                if (index + 1 < ledger.requirements.len) try std.testing.expect(collected.? == .pending);
            }
            const accepted = collected.?.accepted;
            const decision = try supportDecision(a, accepted.inputs);
            try std.testing.expectEqual(.all_resolved, decision.result.continuation);
            try std.testing.expectEqual(@as(usize, 0), accepted.inputs.candidates.len);
            for (accepted.inputs.evidence) |proof| if (proof.requirement.unit == .feature) {
                try std.testing.expectEqual(.model_assisted, proof.method);
                try std.testing.expect(proof.resolution == .existing_authority and proof.resolution.existing_authority == .reference);
                try std.testing.expect(proof.resolution.existing_authority.reference.eql(inputs.references.?.items.state_id));
                try std.testing.expectEqual(@as(usize, 0), proof.review.?.provenance.claim_ids.len);
                try std.testing.expectEqual(@as(usize, 0), proof.review.?.provenance.citation_ids.len);
                try std.testing.expectEqual(@as(usize, 0), proof.review.?.provenance.clarification_response_ids.len);
            };

            const preserved = try @import("domain/source_preservation.zig").project(a, inputs.feature, inputs.references.?, fixture.context.inputs);
            const source_id = (try authority.build(a, preserved)).requirements[0].seed.id;
            const preserved_rule = try admission.requirements(a, preserved, fixture.context.inputs, source_id);
            try std.testing.expectEqual(.bound_claims, preserved_rule.positive_evidence);
            try std.testing.expectEqual(.exact_set, preserved_rule.positive_claims);
            try std.testing.expectEqualDeep(preserved_rule.eligible_claim_ids, (try model.decode(a, positive, preserved_rule)).provenance.claim_ids);
        }
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
            const packet = try support.packetFor(std.testing.allocator, inputs, context, &packet_guidance.marked, .{ .finding = seed.id });
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
        const authorization = try repair.authorize(a, inputs, context, &packet_guidance.marked, rejected);
        const packet = try repair.packet(a, inputs, context, &packet_guidance.marked, rejected.candidate.?, authorization);
        defer packets.release(packet);
        const restricted = try schema.restrict(std.testing.allocator, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer restricted.release();
        try check(restricted.selected().modelBytes(), .{ .bytes = "{\"source_ids\":[1]}" });
        try check(restricted.selected().modelBytes(), .{ .bytes = "{\"source_ids\":[2]}", .rejection = .enum_mismatch, .path = "/source_ids/0" });
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, &packet_guidance.marked, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = good.entries[0].value.provenance, .source_ids = &.{fixture.inputs.corpus.sources[0].id} } }, null)).accepted;
        try std.testing.expectEqualDeep(good.entries[1], fixed.candidate.review.entries[1]);
    }
}

fn reviewFor(a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, sources: @import("domain/reference_evidence.zig").Inputs) !@import("domain/specification_support.zig").Source.Review {
    const support = @import("domain/specification_support.zig").Source;
    const ledger = try @import("domain/required_authority.zig").build(a, inputs);
    const findings = try a.alloc(support.Finding, ledger.requirements.len);
    for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
        const required = try @import("domain/specification_support_evidence.zig").requirements(a, inputs, sources, requirement.seed.id);
        const choices = required.eligible_claim_ids;
        const claims = required.rule(.supported, .{ .unlocalized = .{} }).fixedClaims() orelse choices[0..@min(choices.len, 1)];
        const unbound = required.positive_evidence == .bound_claims and requirement.seed.id.unit == .feature and inputs.references.?.signals.len != 0 and claims.len != 0;
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
        try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references)
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
    const content = (try sessions.assemble(a, text.validator, fixture.context, completed, &.{})).content;
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
        const content = (try sessions.assemble(a, text.validator, fixture.context, complete, &.{})).content;
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
            // Complete generated content projects no post-generation review either.
            .{ .current = complete, .assembled = true, .specification = null },
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

test "source omission repair inserts every new claim a list-spanning proposal quotes" {
    const repair = @import("domain/reference_extraction_repair.zig").Omission;
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]struct { source: []const u8, items: [2]u32, quotes: [2][]const u8 }{
        .{ .source = "Renewal rules:\n\n- Renew a loan.\n- Refuse overdue loans.\n", .items = .{ 3, 4 }, .quotes = .{ "- Renew a loan.", "- Refuse overdue loans." } },
        .{ .source = "Startup:\n1. Show the greeting.\n2. Show the UTC time.\n", .items = .{ 2, 3 }, .quotes = .{ "1. Show the greeting.", "2. Show the UTC time." } },
    }) |case| {
        var fixture = try Fixture.initClaims(a, case.source, null, .{ .selected = &.{.{ .category = .business, .citations = &.{.{ .ordinal = 1 }} }} });
        defer fixture.deinit();
        const inputs = fixture.context.inputs;
        const chunk = inputs.chunks.entries[0];
        const facts: repair.Facts = .{ .extraction = .{ .inputs = inputs, .candidates = try tokens.candidates(a, inputs), .candidate = fixture.extracted_text }, .support = try omissionSupport(&fixture, .{ .extraction_claim = chunk.id }, case.source) };
        const auth = try repair.authorize(a, facts);
        try std.testing.expect(auth.operation == .insert and auth.target.claim == 1);
        const proposal: @import("domain/reference_extraction.zig").Proposal = .{ .category = .business, .citations = &.{ .{ .ordinal = case.items[0] }, .{ .ordinal = case.items[1] } } };
        const packet = try repair.packet(std.testing.allocator, facts, fixture.context.registry, auth, &packet_guidance.marked);
        defer packets.release(packet);
        try checkPreparedExtractionOmission(a, packet, try @import("domain/model_candidate_json.zig").encode(@import("domain/reference_extraction.zig").Proposal, a, proposal));
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, .{ .claim = proposal }, null);
        // ADR 0036, ADR 0038: the proposal spans two list items, so both quoted claims are inserted.
        const claims = merged.entries[0].outcome.claims;
        try std.testing.expectEqual(@as(usize, 3), claims.len);
        try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].outcome.claims[0], claims[0]);
        for (claims[1..], case.items, case.quotes) |claim, line, quote| {
            try std.testing.expectEqualDeep(&[_]@import("domain/source_selections.zig").Selection{.{ .first = .{ .ordinal = line }, .last = .{ .ordinal = line } }}, claim.citations);
            try std.testing.expectEqualStrings(quote, claim.content.business.value.segments[0].literal.value);
        }
        try std.testing.expectEqual(@as(usize, 3), (try extraction.finishText(a, inputs, merged)).ledger.claims.len);
        try std.testing.expect(merged.last_repair.?.changed);
        // An inserted claim already present adds nothing. An insertion that adds
        // no claim is an unchanged merge, which the shared retry state ends as
        // `unchanged_repair` (§22.4); the same lines in another category are new evidence.
        const existing = fixture.extracted_text.entries[0].outcome.claims;
        const duplicate: @import("domain/reference_extraction.zig").Proposal = .{ .category = .business, .citations = &.{.{ .ordinal = 1 }} };
        const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, .{ .claim = duplicate }, null);
        try std.testing.expectEqualDeep(existing, unchanged.entries[0].outcome.claims);
        try std.testing.expect(!unchanged.last_repair.?.changed);
        const other: @import("domain/reference_extraction.zig").Proposal = .{ .category = .validation, .citations = &.{.{ .ordinal = 1 }} };
        const added = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, .{ .claim = other }, null);
        try std.testing.expectEqual(existing.len + 1, added.entries[0].outcome.claims.len);
        try std.testing.expectEqual(.validation, std.meta.activeTag(added.entries[0].outcome.claims[existing.len].content));
        try std.testing.expect(added.last_repair.?.changed);
    }
    // A list-spanning insertion whose first item is already held adds only its new item; the
    // held claim keeps its own origin and the new one takes the repair's.
    for ([_]struct { source: []const u8, items: [2]u32 }{
        .{ .source = "Renewal rules:\n\n- Renew a loan.\n- Refuse overdue loans.\n", .items = .{ 3, 4 } },
        .{ .source = "Startup:\n1. Show the greeting.\n2. Show the UTC time.\n", .items = .{ 2, 3 } },
    }) |case| {
        var fixture = try Fixture.initClaims(a, case.source, null, .{ .selected = &.{.{ .category = .business, .citations = &.{.{ .ordinal = case.items[0] }} }} });
        defer fixture.deinit();
        const inputs = fixture.context.inputs;
        const chunk = inputs.chunks.entries[0];
        const facts: repair.Facts = .{ .extraction = .{ .inputs = inputs, .candidates = try tokens.candidates(a, inputs), .candidate = fixture.extracted_text }, .support = try omissionSupport(&fixture, .{ .extraction_claim = chunk.id }, case.source) };
        const auth = try repair.authorize(a, facts);
        const proposal: @import("domain/reference_extraction.zig").Proposal = .{ .category = .business, .citations = &.{ .{ .ordinal = case.items[0] }, .{ .ordinal = case.items[1] } } };
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 21 }, .attempt = .{ .value = 1 } };
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, .{ .claim = proposal }, origin);
        const held = fixture.extracted_text.entries[0].outcome.claims[0];
        const claims = merged.entries[0].outcome.claims;
        try std.testing.expectEqual(@as(usize, 2), claims.len);
        try std.testing.expectEqualDeep(held, claims[0]);
        try std.testing.expect(!std.meta.eql(held.origin, @as(?@import("domain/model_candidate_origin.zig").Origin, origin)));
        try std.testing.expectEqualDeep(&[_]@import("domain/source_selections.zig").Selection{.{ .first = .{ .ordinal = case.items[1] }, .last = .{ .ordinal = case.items[1] } }}, claims[1].citations);
        try std.testing.expectEqualDeep(origin, claims[1].origin.?);
        try std.testing.expect(merged.last_repair.?.changed);
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
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.packet(a, started, fixture.context.registry, auth, &packet_guidance.marked));
        const packet = try repair.packet(std.testing.allocator, facts, fixture.context.registry, auth, &packet_guidance.marked);
        defer packets.release(packet);
        try std.testing.expectEqualStrings("claim", packet.resultDefinition().?.bytes);
        try expectPresentedComparisons(a, packet, auth.rule.preservation.?);
        try expectPresentationAddsOnlyPurposes(a, @TypeOf(auth.rule), auth.rule, auth.rule);
        // A comparison subject without a workflow purpose cannot be presented.
        var unregistered = auth.rule.preservation.?;
        unregistered.assignment.finding.subject = .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .text };
        try std.testing.expectError(error.InvalidRequiredAuthority, unregistered.present(a, &packet_guidance.marked));
        var unpresentable = auth.rule;
        unpresentable.preservation = unregistered;
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/model_presentation.zig").present(@TypeOf(auth.rule), a, &packet_guidance.marked, unpresentable));
        // The chunk already holds a business claim on these lines, so the inserted claim
        // is new evidence only in another category.
        const proposal: e.Proposal = .{ .category = .validation, .citations = try extraction.citableLines(a, inputs, chunk) };
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
        try checkSourceOmissionProgress(a, merged.omission_retry.?, facts.support, rebuilt_context);
        var stale = facts;
        stale.extraction.candidate = merged;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (stale).extraction.inputs), text.validator, fixture.context.registry, fixture.context.current, stale, auth, replacement, origin));
        stale = facts;
        stale.extraction.candidate.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, stale, fixture.context.registry, auth, &packet_guidance.marked));
        var bad = replacement;
        // Admission restricts citations to supplied lines; an unknown one is a defect.
        bad.claim.citations = &.{.{ .ordinal = 999 }};
        try std.testing.expectError(error.InvalidReferenceExtraction, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (facts).extraction.inputs), text.validator, fixture.context.registry, fixture.context.current, facts, auth, bad, origin));
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
        try std.testing.expectError(error.PostGenerationSourceRepairForbidden, repair.packet(a, parsed, ctx, started, auth, &packet_guidance.marked));
        const packet = try repair.packet(std.testing.allocator, parsed, ctx, support, auth, &packet_guidance.marked);
        defer @import("domain/model_input_packet.zig").release(packet);
        try expectPresentedComparisons(a, packet, auth.rule.finding.preservation.?);
        try expectPresentationAddsOnlyPurposes(a, @TypeOf(auth.rule), auth.rule, auth.rule.finding);
        var unpresentable = auth.rule;
        unpresentable.finding.preservation.?.assignment.finding.subject = .{ .kind = .feature_intent, .unit = .{ .feature = .singleton }, .slot = .text };
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/model_presentation.zig").present(@TypeOf(auth.rule), a, &packet_guidance.marked, unpresentable));
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
        try checkSourceOmissionProgress(a, merged.source.omission_retry.?, support, rebuilt_context);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (ctx).inputs), merged, ctx, support, auth, proposed, null));
        var changed = support;
        changed.review.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, ctx, changed, auth, &packet_guidance.marked));
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
    const disposition_packet = try repair.packet(a, parsed, ctx, disposition_support, disposition_auth, &packet_guidance.marked);
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
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, repaired, ctx, disposition_support, disposition_auth, &packet_guidance.marked));
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
        var fixture = try Fixture.initContent(a, source, null, true, 2);
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
            try @import("domain/specification_authority.zig").project(a, feature, fixture.context.references),
        };
        for (views) |inputs| {
            const ledger = try authority.build(a, inputs);
            const index = if (inputs.projection == .source_preservation) 0 else for (ledger.requirements, 0..) |required, i| {
                if (required.seed.id.unit == .feature and required.seed.id.slot == .description) break i;
            } else return error.MissingDescriptionRequirement;
            const id = ledger.requirements[index].seed.id;
            const required = try admission.requirements(a, inputs, fixture.context.inputs, id);
            const entries = try a.dupe(support.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
            entries[index].value = try model.decode(a, try std.fmt.allocPrint(a, "{{\"kind\":\"candidate_omission\",\"source_ids\":[{d}],\"detail\":\"MOCK A discarded producer lost a requirement.\",\"missing_obligation\":\"MOCK Retain the booking deadline.\"}}", .{fixture.context.inputs.corpus.sources[0].id.ordinal}), required);
            const initial = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = entries }), null)).accepted;
            var pending = initial.candidate;
            pending.pending_localization = @intCast(index + 1);
            const packet = try support.packetForLoss(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, pending);
            defer packets.release(packet);
            const narrowed = try schema.restrict(a, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer narrowed.release();
            const selected: loss.Location = .{ .reconciliation_disposition = discarded };
            const assigned = try support.comparisonAssignment(a, inputs, fixture.context, pending);
            const wire = try @import("test_fixtures/source_omission_evidence.zig").encode(a, assigned, selected);
            try @import("model_payload_schema_test.zig").checkDocument(narrowed.selected().modelBytes(), .{ .bytes = wire });
            try expectExactMembers(a, packet, wire, "assessments", "comparison_id");

            const collected = (try support.collectLoss(a, inputs, fixture.context, &packet_guidance.marked, .{ .accepted = .{ .inputs = initial.inputs, .candidate = pending } }, packet, wire, null)).accepted;
            const located = collected.candidate.review.entries[index].value;
            try std.testing.expectEqualDeep(&[_]r.ClaimId{discarded}, located.provenance.claim_ids);
            try std.testing.expectEqual(initial.candidate.review.entries[index].value.kind, located.kind);
            try std.testing.expectEqualStrings(initial.candidate.review.entries[index].value.detail, located.detail);
            try std.testing.expectEqualDeep(initial.candidate.review.entries[index].value.source_ids, located.source_ids);
            for (initial.candidate.review.entries, collected.candidate.review.entries, 0..) |before, after, sibling| if (sibling != index) try std.testing.expectEqualDeep(before, after);
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
    const packet = try @import("domain/specification_support.zig").Source.packetForLoss(allocator, inputs, context, &packet_guidance.marked, candidate);
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
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.inputs.corpus.feature_id, ready);
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
            for (supporting.output.signal.claims.claims, source_ids, sources) |claim, source_id, bytes| {
                try std.testing.expectEqualDeep(source_id, claim.source_id);
                // Each claim quotes its own source line (ADR 0036).
                try std.testing.expectEqualStrings(std.mem.trimEnd(u8, bytes, "\n"), claim.meaning);
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
        var fixture = try Fixture.initContentKinds(a, source, .business_exact_string, true, 2, true);
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
        var inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
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
                try std.testing.expectEqualStrings(exact, output.claims.exact_texts[0].value);
                try std.testing.expectEqualDeep(original_evidence.citations, output.claims.citations);
                try std.testing.expectEqualDeep(original_evidence.exact_texts, output.claims.exact_texts);
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
        const replacement: repair.Replacement = .{ .outcome = .{ .claim = .{ .category = .business, .citations = try extraction.citableLines(a, inputs, chunk) } } };
        try std.testing.expect(auth.target == .outcome and auth.operation.replace.outcome == .no_feature_claim);
        const atomic = @import("domain/atomic_repair.zig");
        const before = try atomic.snapshot(repair.Authorization, a, auth);
        const packet = try repair.packet(a, facts, fixture.context.registry, auth, &packet_guidance.marked);
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
        }
    }
}
fn completedFixture(fixture: *const Fixture, omit_requirements: bool) !@import("domain/specification_session.zig").Session {
    return completedFixtureValue(fixture, omit_requirements, try fixture.proposal("A receipt is available."));
}
fn readinessSupportInputs(fixture: *const Fixture) !@import("domain/required_authority.zig").Inputs {
    return @import("domain/specification_authority.zig").project(fixture.allocator, fixture.context.inputs.corpus.feature_id, fixture.context.references);
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
            .brief => .{ .brief = .{ .description = value, .primary_goal = value } },
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

/// The links of a completed session none of whose edge cases needs a model choice.
fn resolvedLinks(a: std.mem.Allocator, current: @import("domain/specification_session.zig").Session) ![]const @import("domain/scenario_link.zig").Link {
    return @import("domain/scenario_link.zig").resolve(a, try @import("domain/scenario_link_request.zig").planFor(a, current), &.{});
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
        try std.testing.expect((try sessions.checkConsistency(a, next, context, admitted, null)) == null);
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

test "native reference reviews retain pre-generation attribution" {
    const authority = @import("domain/required_authority.zig");
    const subjects = @import("domain/specification_review_subject.zig");
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    for ([_][]const u8{
        "On startup display `MOCK Ready!` and the UTC date.\n",
        "After delivery display `MOCK Delivered!` and retain the sender receipt.\n",
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, example, .business_exact_string, true, 3);
        defer fixture.deinit();
        _ = try introduceConflict(&fixture);
        const records = @import("domain/reference_support.zig").records(fixture.context.references);
        const source_inputs = try @import("domain/source_preservation.zig").project(a, fixture.context.inputs.corpus.feature_id, records, fixture.context.inputs);
        _ = try checkNativeReferenceReview(a, &fixture, source_inputs, source_inputs.seeds[0].id);
        {
            const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
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
                try std.testing.expectError(error.InvalidRequiredAuthority, support.packetFor(a, inputs, fixture.context, &packet_guidance.marked, .{ .finding = foreign }));
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
            for (original_evidence.exact_texts) |token| if (std.meta.eql(token.id, selected)) break :found .{ .token = token };
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
    const packet = try support.packetFor(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, .{ .finding = id });
    defer packets.release(packet);
    const correction = try support.packetFor(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, .{ .correction = id });
    defer packets.release(correction);
    try expectSameReviewSubject(a, packet, correction);
    const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value;
    try expectReviewAssessmentScope(a, body, id);
    const wire_subject = try json.decode(subjects.Subject, a, try std.json.Stringify.valueAlloc(a, body.object.get("subject").?, .{}));
    try std.testing.expectEqualDeep(projected, wire_subject);
    try std.testing.expectEqual(@as(usize, 1), body.object.get("sources").?.array.items.len);
    try std.testing.expectEqualStrings(fixture.context.inputs.corpus.sources[0].bytes, body.object.get("sources").?.array.items[0].object.get("text").?.string);
    try std.testing.expectEqual(original_evidence.claims.len, body.object.get("claims").?.array.items.len);
    try std.testing.expectEqual(original_evidence.citations.len, body.object.get("citations").?.array.items.len);
    try std.testing.expectEqual(original_evidence.exact_texts.len, body.object.get("exact_texts").?.array.items.len);
    try std.testing.expectEqualStrings(packet_guidance.marked.review_scope.reference.get(std.meta.activeTag(expected)), body.object.get("assessment_scope").?.object.get("instruction").?.string);
    const ledger = try authority.build(a, inputs);
    const index = for (ledger.requirements, 0..) |required, selected| {
        if (std.meta.eql(required.seed.id, id)) break selected;
    } else return error.MissingReferenceRequirement;
    const good = try reviewFor(a, inputs, fixture.context.inputs);
    const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, index);
    @memset(origins, null);
    const prior: ?support.Collection = if (index == 0) null else .{ .pending = .{ .review = .{ .entries = good.entries[0..index] }, .working = true, .origin = null, .origins = origins } };
    const omission = "MOCK supplied source obligation with its required condition.";
    const initial = try support.packetFor(a, inputs, fixture.context, &packet_guidance.marked, .{ .finding = id });
    defer packets.release(initial);
    const omission_value: @import("domain/specification_support_model.zig").Value = .{ .candidate_omission = .{ .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = "MOCK Reviewer supplied this omission; native focus supplies no semantic verdict.", .missing_obligation = omission } };
    const bytes = try json.encode(@import("domain/specification_support_model.zig").Value, a, omission_value);
    const omitted = try support.collectFocused(a, inputs, fixture.context, &packet_guidance.marked, prior, initial, bytes, null);
    const candidate = switch (omitted) {
        .accepted => |value| value.candidate,
        .pending => |value| value,
        .rejected => return error.InvalidNativeReferenceReview,
    };
    const loss_packet = try support.packetForLoss(std.testing.allocator, inputs, fixture.context, &packet_guidance.marked, candidate);
    defer packets.release(loss_packet);
    const loss_body = (try std.json.parseFromSlice(std.json.Value, a, loss_packet.body(), .{})).value.object;
    const supporting = loss_body.get("supporting_evidence").?.object;
    try std.testing.expectEqualDeep(context.fixedSubject(loss_subject), try json.decode(context.FixedSubject, a, try std.json.Stringify.valueAlloc(a, supporting.get("deficient_subject").?, .{})));
    try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, id), supporting.get("target_purpose").?.string);
    try std.testing.expectEqualStrings(omission, loss_body.get("fixed_finding").?.object.get("missing_obligation").?.string);
    const assigned = try support.comparisonAssignment(a, inputs, fixture.context, candidate);
    try std.testing.expectEqualDeep(id, assigned.finding.subject);
    const response = try json.encode(preservation.Response, a, try preservationResponse(a, assigned, .preserved));
    var stale = inputs;
    stale.revision += 1;
    try std.testing.expectError(error.InvalidPreservationComparison, support.admitComparisons(a, stale, fixture.context, candidate, assigned, response));
    const foreign_packet = try packets.create(std.testing.allocator, loss_packet.body(), loss_packet.unit(), .{ .semantic_review = .{ .bytes = "foreign-reference-review" } }, loss_packet.resultDefinition());
    defer packets.release(foreign_packet);
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collectLoss(a, inputs, fixture.context, &packet_guidance.marked, omitted, foreign_packet, response, null));
    return support.collectLoss(a, inputs, fixture.context, &packet_guidance.marked, omitted, loss_packet, response, null);
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
    const inputs = try readinessSupportInputs(&fixture);
    const good = try reviewFor(a, inputs, fixture.context.inputs);
    const findings = try a.dupe(support.Finding, good.entries);
    findings[0].value.kind = .ambiguous;
    findings[0].value.question = "Which deadline should apply? State the duration and starting event.";
    findings[0].value.detail = "The source leaves the deadline ambiguous.";
    try bindReviewClaims(a, inputs, fixture.context, findings);
    try checkDetailRepair(a, inputs, fixture.context, .{ .entries = findings });
    findings[0].value.detail = "";
    const rejected = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
    try std.testing.expectEqual(.invalid_detail, rejected.rejection.selected().?.issue);
    try std.testing.expectError(error.InvalidRequiredAuthority, (@import("actions/specification/apply_specification_support.zig").Action{}).execute(.{ .rejected = rejected }));
    const authorization = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected);
    const packet = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, authorization);
    defer @import("domain/model_input_packet.zig").release(packet);
    const request_body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    const repair_input = request_body.value.object.get("input").?.object;
    try std.testing.expectEqual(@as(usize, 1), repair_input.get("requirements").?.array.items.len);
    try std.testing.expectEqualStrings(fixture.context.inputs.corpus.sources[0].bytes, repair_input.get("sources").?.array.items[0].object.get("text").?.string);
    const replacement = try repair.parse(a, authorization, packet, "{\"detail\":\"Which renewal deadline applies?\",\"question\":\"Which renewal deadline applies? Supply a duration and starting event.\"}");
    const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, authorization, replacement, corrected)).accepted;
    try std.testing.expectEqual(.ambiguous, fixed.inputs.evidence[0].finding);
    try std.testing.expectEqualDeep(corrected, fixed.inputs.review_origins[0].?);
    try std.testing.expectEqualDeep(original, fixed.inputs.review_origins[1].?);
    try std.testing.expectEqualStrings("Which renewal deadline applies?", fixed.inputs.evidence[0].review.?.detail);
    // Required review keeps the preserved source gap: the gate asks the user.
    try std.testing.expectEqual(.needs_user, (try supportDecision(a, fixed.inputs)).result.continuation);
    for (findings[1..], fixed.candidate.review.entries[1..]) |before, after| try std.testing.expectEqualDeep(before, after);
    var stale = rejected.candidate.?;
    stale.revision += 1;
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, inputs, fixture.context, &packet_guidance.marked, stale, authorization));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, stale, authorization, replacement, corrected));
    // No substantive negative result can enter malformed-review authorization.
    try std.testing.expectError(error.InvalidRequiredAuthority, repair.authorize(a, fixed.inputs, fixture.context, &packet_guidance.marked, rejected));
    const missing = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[1..] }), original)).rejected;
    try std.testing.expectEqual(.missing_finding, missing.rejection.selected().?.issue);
    const insert = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, missing);
    try std.testing.expect(insert.operation == .insert);
    const complete = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, missing.candidate.?, insert, .{ .finding = good.entries[0].value }, corrected)).accepted;
    try std.testing.expectEqual(good.entries.len, complete.inputs.evidence.len);
    const duplicate = try a.alloc(support.Finding, good.entries.len + 1);
    @memcpy(duplicate[0..good.entries.len], good.entries);
    duplicate[good.entries.len] = good.entries[0];
    const extra = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = duplicate }), original)).rejected;
    const deletion = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, extra);
    try std.testing.expect(deletion.operation == .delete);
    const deduplicated = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, extra.candidate.?, deletion, null, null)).accepted;
    try std.testing.expectEqualDeep(good, deduplicated.candidate.review);
    duplicate[good.entries.len].value.kind = .conflicting;
    const competing = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = duplicate }), original)).rejected;
    try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, competing));
    findings[0].requirement_ordinal = 999;
    const foreign = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
    try std.testing.expectEqual(.unknown_requirement, foreign.rejection.selected().?.issue);
    try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, foreign));
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
        const inputs = try readinessSupportInputs(&fixture);
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
        try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected));
        var tampered = rejected;
        tampered.rejection.diagnostics = issues[0..1];
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, tampered));
        tampered.rejection.diagnostics = &.{};
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, tampered));
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
        const inputs = try readinessSupportInputs(&fixture);
        const good = try reviewFor(a, inputs, fixture.context.inputs);
        const initial = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[0..2] }), original)).rejected;
        try std.testing.expectEqual(good.entries.len - 2, initial.rejection.diagnostics.len);
        for (initial.rejection.diagnostics, 3..) |issue, ordinal| {
            try std.testing.expectEqual(.missing_finding, issue.issue);
            try std.testing.expectEqual(ordinal, issue.ordinal.?);
        }
        const insert = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, initial);
        var bad = good.entries[2].value;
        bad.provenance.claim_ids = &.{.{ .ordinal = @intCast(inputs.references.?.items.entries.len + 1) }};
        const second = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, initial.candidate.?, insert, .{ .finding = bad }, inserted)).rejected;
        try std.testing.expectEqual(initial.rejection.diagnostics.len, second.rejection.diagnostics.len);
        try std.testing.expectEqual(.ineligible_claim, second.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(inserted, second.rejection.selected().?.origin.?);
        const correction = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, second);
        const packet = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, second.candidate.?, correction);
        defer @import("domain/model_input_packet.zig").release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        try std.testing.expectEqual(@as(usize, 1), body.get("input").?.object.get("requirements").?.array.items.len);
        try std.testing.expect(!body.get("repair").?.object.get("rule").?.object.contains("diagnostics"));
        const unchanged = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, second.candidate.?, correction, correction.operation.replace, corrected)).rejected;
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
        const remaining = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, second.candidate.?, correction, .{ .selection = .{ .provenance = good.entries[2].value.provenance, .source_ids = good.entries[2].value.source_ids } }, corrected)).rejected;
        try std.testing.expectEqual(good.entries.len - 3, remaining.rejection.diagnostics.len);
        try std.testing.expectEqual(@as(u32, 4), remaining.rejection.selected().?.ordinal.?);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, remaining.candidate.?, correction, correction.operation.replace, corrected));
        // Two independent omissions can recover through two existing atomic calls.
        const bounded = (try collectReview(support, a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[2..] }), original)).rejected;
        const one = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, bounded.candidate.?, try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, bounded), .{ .finding = good.entries[0].value }, inserted)).rejected;
        try std.testing.expectEqual(@as(usize, 1), one.rejection.diagnostics.len);
        const complete = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, one.candidate.?, try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, one), .{ .finding = good.entries[1].value }, corrected)).accepted;
        try std.testing.expectEqualDeep(good.entries[2..], complete.candidate.review.entries[0 .. good.entries.len - 2]);
        for (complete.candidate.origins[0 .. good.entries.len - 2]) |origin| try std.testing.expectEqualDeep(original, origin.?);
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
    const inputs = try @import("domain/specification_authority.zig").project(a, fixture.inputs.corpus.feature_id, accounted);
    const allowed_sources = try @import("domain/specification_support_evidence.zig").sourceChoices(a, fixture.inputs);
    try std.testing.expectEqualDeep(&[_]@import("domain/reference_identity.zig").SourceId{ .{ .ordinal = 1 }, .{ .ordinal = 2 }, .{ .ordinal = 3 } }, allowed_sources);
    const ledger = try authority.build(a, inputs);
    const good = try reviewFor(a, inputs, fixture.inputs);
    const index = for (ledger.requirements, 0..) |requirement, i| {
        if (requirement.seed.id.unit == .conflict) break i;
    } else return error.TestExpectedEqual;
    const accepted = (try collectReview(support, a, inputs, context, try json.encode(support.Review, a, good), null)).accepted;
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
        const authorization = try repair.authorize(a, inputs, context, &packet_guidance.marked, rejected);
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, &packet_guidance.marked, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = good.entries[index].value.provenance, .source_ids = &.{} } }, null)).accepted;
        try std.testing.expectEqualDeep(good, fixed.candidate.review);
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
        var fixture = try Fixture.initContent(a, source, null, true, 2);
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
    // The claim quotes line 2 only (ADR 0036), so line 1's token may be discarded.
    for ([_][]const u8{ "Display `Renewal accepted!`.\nProvide a return deadline.\n", "Display `MOCK Booking confirmed!`.\nProvide the arrival date.\n" }) |source| {
        for ([_]?@import("domain/structured_tokens.zig").Kind{ null, .visual_typography, .business_exact_string }) |kind| {
            var fixture = try Fixture.initClaims(a, source, kind, .{ .selected = &.{.{ .category = .business, .citations = &.{.{ .ordinal = 2 }} }} });
            defer fixture.deinit();
            const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
            const packet = try reviewPacketAt(support, a, inputs, fixture.context, 0);
            defer @import("domain/model_input_packet.zig").release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            try std.testing.expectEqualStrings("source_preservation", body.value.object.get("subject").?.object.get("kind").?.string);
            try std.testing.expect(body.value.object.get("candidate_revision") == null);
            try std.testing.expect(body.value.object.get("candidate") == null);
            const row = body.value.object.get("requirements").?.array.items[0].object;
            try std.testing.expect(row.get("contract_version") == null and row.get("requirement") == null);
            try std.testing.expect(row.get("slot") == null and row.get("unit") == null);
            try std.testing.expect(row.get("task") != null and row.get("evidence").?.object.get("eligible_claim_ids") != null);
            try std.testing.expectEqualStrings(fixture.context.inputs.corpus.sources[0].bytes, body.value.object.get("sources").?.array.items[0].object.get("text").?.string);
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
            // Six feature subjects (ADRs 0047 and 0048) and at least one reference obligation.
            const ledger = try authority.build(a, inputs);
            try std.testing.expect(ledger.requirements.len >= 7);
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
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
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
        const readiness = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
        var permitted: usize = 0;
        for ((try authority.build(a, readiness)).requirements) |requirement| {
            const id = requirement.seed.id;
            const permits = (try authority.applicability(id)) == .review;
            if (permits) {
                try std.testing.expectEqual(authority.Kind.entity_applicability, id.kind);
                permitted += 1;
            }
            const packet = try support.packetFor(a, readiness, fixture.context, &packet_guidance.marked, .{ .finding = id });
            defer packets.release(packet);
            try std.testing.expectEqualStrings(if (permits) "applicability_finding" else "finding", packet.resultDefinition().?.bytes);
            const body = (try std.json.parseFromSliceLeaky(std.json.Value, a, packet.body(), .{})).object;
            try std.testing.expectEqual(permits, body.get("evidence_rules").?.object.contains("not_applicable"));
            try std.testing.expectEqual(permits, body.get("requirements").?.array.items[0].object.contains("permitted_not_applicable"));
            // The selected single-finding schema offers not_applicable only where permitted.
            const restricted = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer restricted.release();
            var document = try envelope.parseContent(a, try codec.encode(model.Value, a, .{ .not_applicable = positive }), null);
            defer document.deinit();
            const invalid = @import("domain/model_payload_schema.zig").validateValue(envelope.value(&document.parsed.value), restricted.selected().root());
            try std.testing.expectEqual(!permits, invalid != null);
        }
        try std.testing.expectEqual(@as(usize, 1), permitted);
    }
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

fn expectReviewAssessmentScope(a: std.mem.Allocator, input: std.json.Value, id: @import("domain/required_authority.zig").Id) !void {
    const scope = input.object.get("assessment_scope").?.object;
    try std.testing.expectEqual(@as(usize, 3), scope.count());
    const subject_value = input.object.get("subject").?;
    try std.testing.expect(@import("domain/required_authority.zig").policy(id) != null);
    const record = subject_value.object.get("record");
    // Each presented scope text is its marked workflow entry, named from the
    // subject's kind independently of the native scope selection.
    const kind = subject_value.object.get("kind").?.string;
    try std.testing.expect(record == null);
    const entry = if (std.mem.eql(u8, kind, "reference"))
        try std.fmt.allocPrint(a, "reference.{s}", .{@tagName(id.unit)})
    else
        kind;
    try std.testing.expectEqualStrings("MOCK review_scope.original_sources", scope.get("original_sources").?.string);
    try std.testing.expectEqualStrings("MOCK review_scope.derived_evidence", scope.get("derived_evidence").?.string);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "MOCK review_scope.{s}", .{entry}), scope.get("instruction").?.string);
}

fn selectedNativeRepairTask(input: std.json.Value) ![]const u8 {
    const assignment = input.object.get("source_assignment").?;
    if (assignment == .object) {
        try std.testing.expect(!assignment.object.contains("purpose"));
        if (std.mem.eql(u8, assignment.object.get("kind").?.string, "brief")) {
            inline for (.{ "description", "primary_goal" }) |field| try std.testing.expect(!assignment.object.get(field).?.object.contains("purpose"));
        }
    }
    return input.object.get("task").?.string;
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
        // Requirements may share a claim (ADR 0038 Decision 5), so both records stay.
        try records.append(a, .{ .content = .{ .functional_requirement = .{ .text = .{ .segments = try a.dupe(@import("domain/typed_text.zig").BusinessSegment, &.{ .{ .literal = .{ .value = raw[0..2] } }, .{ .literal = .{ .value = raw[2..] } }, .{ .literal = .{ .value = "suffix" } } }) } } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance });
    };
    try std.testing.expectEqual(@as(usize, 2), records.items.len);
    // The requirements' claims need a scenario of the batch (ADR 0038 Decision 2); its
    // fields copy no exact value, so the exact-copy gaps stay.
    try records.append(a, .{ .content = .{ .acceptance_criterion = .{ .given = good.value, .when = good.value, .then = good.value } }, .source_group_ids = good.source_group_ids, .provenance = good.provenance });
    const named = try fixture.proposalAllGroups("The requested outcomes are named.");
    var current = (try sessions.initialize(a, .{ .bytes = "chosen" }, fixture.context)).ready;
    while (current.completed < sessions.unit_count) {
        const unit = try sessions.unit(current.completed);
        const response: g.Response = .{ .content = switch (unit) {
            .brief => .{ .brief = .{ .description = named, .primary_goal = good } },
            .primary_user_story => .{ .primary_user_story = good },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
            .records => .{ .records = records.items },
        } };
        current = try appendMockResponse(a, current, fixture.context, response);
    }
    const initial = (try sessions.assemble(a, text.validator, fixture.context, current, &.{})).content;
    const before = try std.json.Stringify.valueAlloc(a, current, .{});
    const rejected = (try check.execute(a, current, fixture.context, initial)).invalid;
    try std.testing.expect(rejected.issue == .missing_exact_copy);
    const decision = try repair.authorize(a, current, fixture.context, initial, rejected);
    try std.testing.expectEqual(.no_independent_supported_target, decision.blocked.blocked.?);
    try std.testing.expectEqualStrings(before, try std.json.Stringify.valueAlloc(a, current, .{}));
}

fn checkSourceOmissionProgress(a: std.mem.Allocator, permit: @import("domain/workflow_retry.zig").Permit, negative: @import("domain/source_omission.zig").Support, context: provenance.Context) !void {
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
        try @import("domain/specification_authority.zig").project(a, context.inputs.corpus.feature_id, context.references);
    const reviewed = (try collectReview(support, a, renewed_inputs, context, try json.encode(support.Review, a, try reviewFor(a, renewed_inputs, context.inputs)), null)).accepted;
    try std.testing.expectEqual(.all_resolved, (try supportDecision(a, reviewed.inputs)).result.continuation);
    try std.testing.expectEqual(.resolved, (try loss.admittedValidation(a, permit, reviewed)).?.validated.result);
    const foreign_purpose = if (negative.inputs.projection == .source_preservation)
        try @import("domain/specification_authority.zig").project(a, context.inputs.corpus.feature_id, context.references)
    else
        try @import("domain/source_preservation.zig").project(a, context.inputs.corpus.feature_id, @import("domain/reference_support.zig").records(context.references), context.inputs);
    const wrong_review = (try collectReview(support, a, foreign_purpose, context, try json.encode(support.Review, a, try reviewFor(a, foreign_purpose, context.inputs)), null)).accepted;
    try std.testing.expectError(error.InvalidRequiredAuthority, loss.admittedValidation(a, permit, wrong_review));
    try checkNativeApplySourceRejection(permit, wrong_review);
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

fn checkDetailRepair(a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, good: @import("domain/specification_support.zig").Source.Review) !void {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const detail_owner = @import("domain/specification_support_evidence.zig");
    const original: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: @TypeOf(original) = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const collected = try collectReview(review, a, inputs, context, try @import("domain/model_candidate_json.zig").encode(review.Review, a, good), original);
    const admitted = collected.accepted;
    const oversized = try std.mem.concat(a, u8, &.{ "é" ** 1000, "x" });
    for ([_][]const u8{ "", " \t\n", "\x00", oversized }) |invalid| {
        const rows = try a.dupe(review.Finding, good.entries);
        rows[0].value.detail = invalid;
        var candidate = admitted.candidate;
        candidate.review.entries = rows;
        const rejected = (try review.validate(a, inputs, context.inputs, candidate)).rejected;
        try std.testing.expectEqual(.invalid_detail, rejected.rejection.selected().?.issue);
        const authorization = try repair.authorize(a, inputs, context, &packet_guidance.marked, rejected);
        const packet = try repair.packet(a, inputs, context, &packet_guidance.marked, candidate, authorization);
        defer @import("domain/model_input_packet.zig").release(packet);
        var schema_parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const schemas = try schema_parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
        const selected = schemas.select(packet.resultDefinition().?).?;
        const codec = @import("domain/model_candidate_json.zig");
        var expected = authorization.operation.replace;
        expected.detail.detail = good.entries[0].value.detail;
        expected.detail.question = good.entries[0].value.question;
        try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = try codec.encodeSelected(repair.Replacement, a, expected) });
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const repair_rule = body.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expect(!repair_rule.contains("finding"));
        try std.testing.expectEqualStrings(@tagName(review.decisionOf(good.entries[0].value)), repair_rule.get("decision").?.string);
        const rule = repair_rule.get("detail_rule").?.object;
        try std.testing.expect(!rule.get("allow_empty").?.bool);
        try std.testing.expectEqual(@as(i64, @import("domain/clarification_inputs.zig").max_text_bytes), rule.get("maximum_utf8_bytes").?.integer);
        try std.testing.expectEqualStrings(packet_guidance.marked.support_evidence.detail, rule.get("instruction").?.string);
        {
            // This fixture's retained finding needs a user question.
            try std.testing.expectEqualStrings(packet_guidance.marked.support_evidence.question.get(.required), repair_rule.get("question_rule").?.string);
            try std.testing.expectEqualStrings(packet_guidance.marked.support_evidence.obligation, repair_rule.get("obligation_rule").?.string);
            try std.testing.expect(!repair_rule.contains("authority_gap_rule"));
        }
        const unchanged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, &packet_guidance.marked, candidate, authorization, .{ .detail = .{ .detail = invalid } }, corrected);
        try std.testing.expect(unchanged == .rejected);
        var corrected_detail = authorization.operation.replace;
        corrected_detail.detail.detail = good.entries[0].value.detail;
        corrected_detail.detail.question = good.entries[0].value.question;
        const fixed = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, &packet_guidance.marked, candidate, authorization, corrected_detail, corrected)).accepted;
        try std.testing.expectEqualDeep(good, fixed.candidate.review);
        try std.testing.expectEqualDeep(corrected, fixed.candidate.origins[0].?);
        try std.testing.expectEqualDeep(original, fixed.candidate.origins[1].?);
        // Missing-finding insertion uses the same full admission, including detail.
        var absent = admitted.candidate;
        absent.review.entries = good.entries[1..];
        absent.origins = absent.origins[1..];
        absent.occurrences = .{};
        const missing = (try review.validate(a, inputs, context.inputs, absent)).rejected;
        const insert = try repair.authorize(a, inputs, context, &packet_guidance.marked, missing);
        try std.testing.expect((try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (context).inputs), inputs, context, &packet_guidance.marked, missing.candidate.?, insert, .{ .finding = rows[0].value }, corrected)) == .rejected);
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
        var fixture = try Fixture.initContent(a, source, .business_exact_string, true, 1);
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
        try @import("domain/specification_markdown.zig").literal(&escaped.writer, source, .block_start);
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
        try std.testing.expect(std.mem.indexOf(u8, try @import("domain/reference_context.zig").render(a, technical.reference, null), escaped.written()) != null);
        // A claim's text opens its list item's line, so a byte that opens a block there is escaped.
        var leading = value;
        const leading_claims = try a.dupe(@import("domain/reference_extraction.zig").Claim, value.reference.extraction.claims);
        leading_claims[0].content = .{ .model = .{ .business = .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "- item" } }} } } } };
        leading.reference.extraction.claims = leading_claims;
        try std.testing.expect(std.mem.indexOf(u8, try codec.render(a, leading, validated), "\n- \\- item\n") != null);

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
        for (0..10) |mode| {
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
                9 => bad.schema = "specification-state/v21",
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
        var fixture = try Fixture.initContent(a, source, .business_exact_string, true, 3);
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
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
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
        const packet = try repair.packet(a, parsed, ctx, support, auth, &packet_guidance.marked);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("repair_conflict_group", packet.resultDefinition().?.bytes);
        // ADR 0046: the group's answer binds each group claim once at admission, natively.
        var members: ?@import("domain/model_result_schema.zig").IntegerChoice = null;
        for (packet.integerChoices()) |choice| if (choice.collection == .exact_members) {
            members = choice;
        };
        try std.testing.expectEqual(.native, members.?.member_count);
        try std.testing.expectEqualStrings("claim_dispositions", members.?.target.path[0].property);
        try std.testing.expectEqual(claims.len, members.?.allowed.len);
        for (claims, members.?.allowed) |id, allowed| try std.testing.expectEqual(@as(i64, id.ordinal), allowed);
        {
            // An answer omitting a group claim is rejected at admission, for the
            // repair's own correction, before merge could fail it.
            const schema = @import("domain/model_result_schema.zig");
            var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
            const resource = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/reconciliation.schema.json", a, .unlimited));
            const restricted = try schema.restrict(a, resource.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
            defer restricted.release();
            const one = try std.fmt.allocPrint(a, "{{\"claim_dispositions\":[{{\"claim_id\":{d},\"disposition\":{{\"kind\":\"retained\"}}}}],\"conflict_groups\":[],\"conflicts\":[]}}", .{claims[0].ordinal});
            const answer = try std.json.parseFromSlice(std.json.Value, a, one, .{ .parse_numbers = false });
            const rejected = @import("domain/model_payload_schema.zig").validateValue(@import("domain/model_envelope.zig").value(&answer.value), restricted.selected().root()).?;
            try std.testing.expectEqual(.missing_member, rejected.reason);
            try std.testing.expectEqual(@as(i64, claims[1].ordinal), rejected.member.?);
        }
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
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, stale_context, support, auth, &packet_guidance.marked));
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
        const inputs = try readinessSupportInputs(&fixture);
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
            const auth = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected);
            const packet = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, auth);
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
            const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, auth, try repair.parse(a, auth, packet, accepted_detail), null);
            try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
            try std.testing.expectEqual(decision, fixed.accepted.candidate.review.entries[index].value.kind);
            try std.testing.expectEqualDeep(entries[index].value.provenance, fixed.accepted.candidate.review.entries[index].value.provenance);
            for (entries, fixed.accepted.candidate.review.entries, 0..) |before, after, i| if (i != index) try std.testing.expectEqualDeep(before, after);
            if (!negative) continue;
            // Presence is schema-checked; whitespace remains a native text
            // defect and retains the original pair's retry key.
            try check(selected.modelBytes(), .{ .bytes = "{\"detail\":\"\",\"question\":\"What duration applies? State its starting event.\"}", .rejection = .string_length, .path = "/detail" });
            const blank_detail = "{\"detail\":\" \",\"question\":\"What duration applies? State its starting event.\"}";
            try check(selected.modelBytes(), .{ .bytes = blank_detail });
            const recurring = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, auth, try repair.parse(a, auth, packet, blank_detail), null);
            try std.testing.expectEqual(.invalid_detail, recurring.rejected.rejection.selected().?.issue);
            try std.testing.expectEqual(.recurring, repair.progress(auth, recurring));
            const again = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, recurring.rejected);
            try std.testing.expectEqualDeep(auth.retry.?.key, again.retry.?.key);
            const blank_question = "{\"detail\":\"Known facts and missing duration.\",\"question\":\" \"}";
            try check(selected.modelBytes(), .{ .bytes = blank_question });
            const next_packet = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, recurring.rejected.candidate.?, again);
            defer @import("domain/model_input_packet.zig").release(next_packet);
            const still_bad = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, recurring.rejected.candidate.?, again, try repair.parse(a, again, next_packet, blank_question), null);
            try std.testing.expectEqual(.invalid_question, still_bad.rejected.rejection.selected().?.issue);
            try std.testing.expectEqual(.recurring, repair.progress(again, still_bad));
            try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, still_bad.rejected));
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
        for (0..2) |stage| {
            const inputs = if (stage == 0)
                try @import("domain/source_preservation.zig").project(a, session.feature, @import("domain/reference_support.zig").records(fixture.context.references), fixture.context.inputs)
            else
                try @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references);
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
                const auth = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected);
                const packet = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, auth);
                defer @import("domain/model_input_packet.zig").release(packet);
                const restricted = try @import("domain/model_result_schema.zig").restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
                defer restricted.release();
                const selected = restricted.selected();
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                const repair_rule = body.get("repair").?.object.get("rule").?.object;
                const rule = repair_rule.get("evidence_rule").?.object;
                try std.testing.expectEqualStrings(packet_guidance.marked.support_evidence.selection, rule.get("instruction").?.string);
                // Only a retained invalid candidate carries the authority-gap rule.
                if (decision == .candidate_invalid)
                    try std.testing.expectEqualStrings(packet_guidance.marked.support_evidence.authority_gap, repair_rule.get("authority_gap_rule").?.string)
                else
                    try std.testing.expect(!repair_rule.contains("authority_gap_rule"));
                const model = @import("domain/specification_support_model.zig");
                const source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
                const bytes = if (decision == .candidate_invalid)
                    try json.encode(model.InvalidSelection, a, .{ .source_ids = source_ids, .authority_gap_source_ids = null })
                else
                    try json.encode(model.Selection, a, .{ .source_ids = source_ids });
                try std.testing.expectEqualStrings(if (decision == .candidate_invalid) "invalid_selection" else "selection", packet.resultDefinition().?.bytes);
                try check(selected.modelBytes(), .{ .bytes = "{\"source_ids\":[1],\"provenance\":{\"claim_ids\":[1]}}", .rejection = .unknown_property, .path = "/provenance" });
                try check(selected.modelBytes(), .{ .bytes = bytes });
                const fixed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, auth, try repair.parse(a, auth, packet, bytes), null);
                try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
                try std.testing.expectEqual(decision, fixed.accepted.candidate.review.entries[index].value.kind);
                for (entries, fixed.accepted.candidate.review.entries, 0..) |before, after, i| if (i != index) try std.testing.expectEqualDeep(before, after);
                // Model responses cannot alter the bound claim set during repair.
                try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, auth, packet, "{\"provenance\":{\"claim_ids\":[999]},\"source_ids\":[1]}"));
                const initial = try review.packetFor(a, inputs, fixture.context, &packet_guidance.marked, .{ .finding = ledger.requirements[index].seed.id });
                defer @import("domain/model_input_packet.zig").release(initial);
                const input = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
                try std.testing.expectEqualStrings(packet_guidance.marked.support_evidence.selection, input.get("evidence_rules").?.object.get("instruction").?.string);
            }
        }
    }
}

test "false cross-kind conflict and seven question repairs cannot publish a clarification" {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const needs = @import("domain/required_authority_clarifications.zig");
    for ([_][]const u8{ "On startup display `MOCK Hello, World!` and the UTC date.", "Renew the loan, show the return date and display `MOCK Loan renewed!`." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContentKinds(a, source, .business_exact_string, true, 2, true);
        defer fixture.deinit();
        _ = try introduceConflict(&fixture);
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references);
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
        // Six feature subjects (the engine-derived story and title are none, ADRs 0047 and
        // 0048) and one conflict.
        try std.testing.expectEqual(@as(usize, 7), negative_count);
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 8 }, .attempt = .{ .value = 1 } };
        var collected = try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), origin);
        try std.testing.expectEqual(negative_count, collected.rejected.rejection.diagnostics.len);
        for (0..negative_count) |index| {
            const rejected = collected.rejected;
            const auth = try repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected);
            try std.testing.expectEqual(.missing_question, auth.rule.rejection.issue);
            const packet = try repair.packet(a, inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, auth);
            defer @import("domain/model_input_packet.zig").release(packet);
            try std.testing.expectEqualStrings("gap_detail", packet.resultDefinition().?.bytes);
            collected = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), inputs, fixture.context, &packet_guidance.marked, rejected.candidate.?, auth, .{ .detail = .{ .detail = entries[auth.target.index].value.detail, .question = "Which behavior is intended? State the action and date to display." } }, .{ .request = .{ .value = @intCast(9 + index) }, .attempt = .{ .value = 1 } });
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
        const gate = try supportDecision(a, collected.accepted.inputs);
        try std.testing.expectEqual(.invalid, gate.result.continuation);
        try std.testing.expectError(error.InvalidRequiredAuthority, needs.build(a, fixture.context.inputs, gate.inputs, gate.observations, gate.result, &packet_guidance.marked));
        try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/source_omission.zig").select(a, fixture.context.inputs, .{ .repair_phase = .generation_started, .review = collected.accepted.candidate, .inputs = gate.inputs, .observations = gate.observations, .result = gate.result }));
    }
}

test "generation inconclusive stays terminal and an inconclusive source finding invents no question" {
    const review = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    const inputs = try readinessSupportInputs(&fixture);
    const entries = try a.dupe(review.Finding, (try reviewFor(a, inputs, fixture.context.inputs)).entries);
    entries[0].value.kind = .inconclusive;
    entries[0].value.detail = "I could not reconcile the current interpretations; no missing user choice was established.";
    try bindReviewClaims(a, inputs, fixture.context, entries);
    const inconclusive_result = try collectReview(review, a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null);
    const accepted = inconclusive_result.accepted;
    const gate = try supportDecision(a, accepted.inputs);
    // Required review: an inconclusive finding is a candidate defect, never a user question.
    try std.testing.expectEqual(.invalid, gate.result.continuation);
    try std.testing.expectEqual(.inconclusive_review, gate.result.entries[0].candidate_defect.?.reason);
    try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/required_authority_clarifications.zig").build(a, fixture.context.inputs, gate.inputs, gate.observations, gate.result, &packet_guidance.marked));
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
    var outcome = checked_values[0];
    outcome.value = .{ .segments = &.{.{ .literal = .{ .value = "Operation outcome" } }} };
    outcome = try provenance.checkAttributed(.model, a, text.validator, context, .{ .value = outcome.value, .source_group_ids = outcome.source_group_ids, .provenance = selection(outcome.provenance) }, .spec_goal);
    const brief: g.Brief = .{ .description = outcome, .primary_goal = outcome };
    const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = checked_values[0], .entities = .{ .disposition = .not_applicable, .basis = outcome }, .records = &records }, .{}, &.{})).content;
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

test "admitted prose loses the code delimiters around a recognised exact value" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "MOCK Display `MOCK Hello, World!` on start.", "MOCK Show `MOCK Renewed!` after renewal." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const records = @import("domain/reference_support.zig").records(fixture.context.references);
        const token = for ((try provenance.items(fixture.context)).entries) |item| {
            if (item.claim.content == .preserved_token) break item.claim;
        } else return error.MissingTestToken;
        const bytes = token.content.preserved_token.value.raw_value.bytes;
        const wrapped: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "It must display `{s}` and stop.", .{bytes}) } }} };
        // ADR 0036: an obligation field holds the value once, as an exact copy.
        const recognized = try provenance.recognizeValue(a, records, wrapped, .functional_requirement, null);
        try std.testing.expectEqual(@as(usize, 3), recognized.segments.len);
        try std.testing.expectEqualStrings("It must display ", recognized.segments[0].literal.value);
        try std.testing.expectEqualDeep(token.id, recognized.segments[1].exact_copy.claim_id);
        try std.testing.expectEqualStrings(" and stop.", recognized.segments[2].literal.value);
        try std.testing.expectEqualDeep(recognized, try provenance.recognizeValue(a, records, recognized, .functional_requirement, null));
        // A field that can't hold exact copies keeps the value as text.
        const kept = try provenance.recognizeValue(a, records, wrapped, .assumption, null);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "It must display {s} and stop.", .{bytes}), kept.segments[0].literal.value);
        try std.testing.expectEqualDeep(kept, try provenance.recognizeValue(a, records, kept, .assumption, null));
        // A code-wrapped value alone becomes the exact copy alone.
        const alone: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "`{s}`", .{bytes}) } }} };
        try std.testing.expectEqualDeep(&[_]@import("domain/typed_text.zig").BusinessSegment{.{ .exact_copy = .{ .claim_id = token.id } }}, (try provenance.recognizeValue(a, records, alone, .functional_requirement, null)).segments);
        // Unequal backtick runs are not a code span; the text stays as written.
        const uneven: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "It must display ``{s}` and stop.", .{bytes}) } }} };
        try std.testing.expectEqualDeep(uneven, try provenance.recognizeValue(a, records, uneven, .functional_requirement, null));
    }
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
        const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = good, .primary_goal = bad } } } };
        const initial = try sessions.packet(std.testing.allocator, current, fixture.context, &packet_guidance.marked);
        defer packets.release(initial);
        const generation_schema = try schema.restrict(std.testing.allocator, canonical.select(initial.resultDefinition().?).?, initial.excludedVariants(), initial.integerChoices());
        defer generation_schema.release();
        var invalid_body = try std.json.parseFromSlice(std.json.Value, a, try json.encode(g.ModelResponse, a, try g.ModelResponse.from(a, fixture.context, .{ .content = .{ .brief = .{ .description = good, .primary_goal = good } } })), .{ .parse_numbers = false });
        invalid_body.value.object.getPtr("primary_goal").?.object.getPtr("value").?.* = try std.json.parseFromSliceLeaky(std.json.Value, a, if (exact) "{\"fragments\":[{\"kind\":\"exact_copy\",\"claim_id\":999}]}" else "{\"fragments\":[{\"kind\":\"passive\",\"passive_literal_id\":1}]}", .{});
        try std.testing.expect(@import("domain/model_payload_schema.zig").validateValue(@import("domain/model_envelope.zig").value(&invalid_body.value), generation_schema.selected().root()) != null);
        try std.testing.expect(std.mem.indexOf(u8, generation_schema.selected().modelBytes(), "exact_copy") == null);
        if (exact) try std.testing.expectError(error.InvalidJsonDocument, json.decode(g.ModelResponse, a, try std.json.Stringify.valueAlloc(a, invalid_body.value, .{})));
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(@as(@FieldType(@import("domain/typed_text.zig").Issue, "reason"), if (exact) .unknown_exact else .unknown_passive), rejected.issue.text_issue.?.reason);
        if (exact) try std.testing.expectEqualDeep(handle, rejected.issue.text_issue.?.rejected_exact.?) else try std.testing.expectEqual(@as(u32, 1), rejected.issue.text_issue.?.rejected_passive.?.ordinal);
        // A model-authored exact handle has no current wire producer. Its
        // schema/codec rejection precedes candidate value-repair authority.
        if (exact) continue;
        const auth = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, auth, &packet_guidance.marked);
        defer packets.release(packet);
        const selected = try schema.restrict(std.testing.allocator, canonical.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
        defer selected.release();
        {
            try std.testing.expectEqual(.value, std.meta.activeTag(auth.target));
            // The authorizer composes the native correction with the workflow's tail.
            const tailed = "Validation failed: passive reference ID 1 is unavailable for this field's authorized evidence. Return source-backed prose without reference handles. MOCK repair_tails.value_choices";
            try std.testing.expectEqualStrings(tailed, auth.rule.requirement);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            try std.testing.expectEqualStrings(tailed, body.value.object.get("repair").?.object.get("rule").?.object.get("requirement").?.string);
            try std.testing.expect(std.mem.indexOf(u8, selected.selected().modelBytes(), "exact_copy") == null);
        }
        try std.testing.expect(std.mem.indexOf(u8, selected.selected().modelBytes(), "passive_literal_id") == null);
        const replacement: repair.Replacement = .{ .value = good.value };
        const bytes = try json.encodeSelected(repair.Replacement, a, replacement);
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{ .parse_numbers = false });
        try std.testing.expect(@import("domain/model_payload_schema.zig").validateValue(@import("domain/model_envelope.zig").value(&parsed.value), selected.selected().root()) == null);
        const merged = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, auth, try repair.parse(a, auth, packet, bytes), null);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.description);
        try std.testing.expectEqualDeep(bad.provenance, merged.response.content.brief.primary_goal.provenance);
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
        const requirement = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
            .content = .{ .functional_requirement = .{ .text = value } },
            .source_group_ids = proposed.source_group_ids,
            .provenance = proposed.provenance,
        });
        const entity = try provenance.checkRecord(.model, a, text.validator, fixture.context, .{
            .content = .{ .entity = .{ .name = value } },
            .source_group_ids = proposed.source_group_ids,
            .provenance = proposed.provenance,
        });
        const content = (try identifiers.assign(a, .{
            .display_name = fixture_display_name,
            .primary_user_story = plain,
            .records = &.{ shared, requirement, entity },
            .entities = .{ .disposition = .required, .basis = plain },
        }, .{}, &.{})).content;
        const document = try projection.project(a, fixture.context, test_directory, content);
        const exact_bytes = try std.fmt.allocPrint(a, "Display {s} and again {s}", .{ all.entries[all.entries.len - 1].claim.content.preserved_token.value.raw_value.bytes, all.entries[all.entries.len - 1].claim.content.preserved_token.value.raw_value.bytes });
        for (document.records) |projected| switch (projected.content) {
            .acceptance_criterion => |criterion| {
                try std.testing.expectEqualStrings("The application starts.", criterion.given.bytes);
                try std.testing.expectEqualStrings(exact_bytes, criterion.when.bytes);
            },
            .functional_requirement => {},
            .entity => |model| {
                try std.testing.expectEqualStrings(exact_bytes, model.name.bytes);
                // The requirement of its group is related; the criterion, a scenario, is not.
                try std.testing.expectEqualDeep(&[_]spec.Id{.{ .kind = .functional_requirement, .ordinal = 1 }}, projected.related);
            },
            else => return error.UnexpectedRecordKind,
        };
        const markdown = try @import("domain/specification_markdown.zig").render(a, document);
        try std.testing.expect(std.mem.indexOf(u8, markdown, "- **RELATED STATEMENTS** FR-001\n") != null);
        try std.testing.expectEqualDeep(document, try @import("domain/specification_markdown.zig").parse(a, markdown));
    }
}

test "completed requirement links keep separate source sets and many-to-many lineage" {
    const r = references.r;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "Display `Done!` after the operation.", .business_exact_string, true, 2);
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
    const content = (try identifiers.assign(a, .{ .display_name = fixture_display_name, .primary_user_story = basis, .entities = .{ .disposition = .not_applicable, .basis = basis }, .records = &.{ first, second, third } }, .{}, &.{})).content;
    const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
    const contract = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
    const snapshot = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "references" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, contract);
    const traces = try @import("domain/specification_projection.zig").traceSnapshot(a, snapshot, content);
    try std.testing.expectEqual(@as(usize, 3), traces.len);
    for (traces, &[_][]const r.ClaimId{ &.{ one, exact }, &.{two}, &.{ one, two } }) |trace, expected| {
        try std.testing.expectEqual(expected.len, trace.occurrences.len);
        for (expected, trace.occurrences) |claim, occurrence| try std.testing.expectEqualDeep(claim, occurrence.claim_id);
    }
    const linked = try @import("domain/reference_context.zig").render(a, snapshot, traces);
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
        const assigned = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
        const brief = current.units[0].?.response.content.brief;
        const contracts = try @import("test_fixtures/extraction_contract.zig").Fixture.init(a);
        const binding = try @import("domain/reference_extraction_contract.zig").capture(a, contracts.authority, fixture.context.inputs.chunks.partition);
        const snapshot: state.State = .{
            .schema = state.schema,
            .principle_registry = try @import("test_fixtures/principles.zig").registry(a, null),
            .feature = current.feature,
            .revision = 1,
            .stage = .specified,
            .reference = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "first" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry, binding),
            .brief = brief,
            .content = assigned.content,
            .id_ledger = assigned.ledger,
            .coverage = try @import("domain/specification_coverage.zig").validate(a, fixture.context.references, brief, assigned.content),
            .clarification = .{ .state_ordinal = 1, .revision = 1 },
        };
        const bytes = try std.json.Stringify.valueAlloc(a, snapshot, .{});
        const restored = (try state.parse(a, bytes, current.feature, contracts.port())).specified().?;
        const traces = try @import("domain/specification_projection.zig").traceSnapshot(a, restored.reference, restored.content);
        try std.testing.expectEqual(restored.content.records.len, traces.len);
        for (restored.content.records, traces) |record, trace| try std.testing.expectEqualDeep(record.id, trace.id);
        const linked = try @import("domain/reference_context.zig").render(a, restored.reference, traces);
        try std.testing.expect(std.mem.indexOf(u8, linked, "## Generated Requirement Sources") != null);
        try std.testing.expect(std.mem.indexOf(u8, linked, "(#cit-") != null);
        const projected = try @import("domain/specification_projection.zig").project(a, fixture.context, restored.reference.directory, restored.content);
        const criterion_index = for (projected.records, 0..) |record, index| {
            if (record.content == .acceptance_criterion) break index;
        } else return error.MissingCriterion;
        // The live projection shows exactly the lines the persisted snapshot's trace
        // gives, including the exact token's mid-line citation.
        const shown = @import("domain/specification_projection.zig");
        for (projected.records, traces) |record, trace| {
            const family: spec.Kind = record.content;
            if (!family.showsSources()) {
                try std.testing.expectEqual(@as(usize, 0), record.sources.len);
                continue;
            }
            try std.testing.expectEqual(@as(usize, 1), record.sources.len);
            try std.testing.expectEqualDeep(try shown.sourceLines(a, restored.reference.directory, restored.reference.inputs, trace.occurrences), record.sources);
        }
        // An occurrence whose source isn't in the corpus has no line to show.
        const foreign = try a.dupe(@import("domain/reference_support.zig").Occurrence, traces[0].occurrences);
        foreign[0].citation.value.source_id.ordinal = 99;
        try std.testing.expectError(error.InvalidSpecification, shown.sourceLines(a, restored.reference.directory, restored.reference.inputs, foreign));
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
        missing_exact.brief.primary_goal = try provenance.checkAttributed(.model, a, text.validator, fixture.context, .{
            .value = .{ .segments = &.{.{ .literal = .{ .value = "The requested behavior is named." } }} },
            .source_group_ids = &.{ fixture.context.references.records.signals[0].id, fixture.context.references.records.signals[1].id },
            .provenance = .{ .claim_ids = &.{ all.entries[0].claim.id, exact }, .clarification_response_ids = &.{} },
        }, .spec_goal);
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
        var candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = bad, .primary_goal = good } } } };
        const first = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, first, &packet_guidance.marked);
        try std.testing.expectEqual(.value, std.meta.activeTag(authorization.target));
        try std.testing.expectEqualDeep(good.provenance.claim_ids, authorization.rule.value_bound.?.effective);
        const packet = try repair.packet(a, current, fixture.context, authorization, &packet_guidance.marked);
        defer @import("domain/model_input_packet.zig").release(packet);
        for (packet.exactScope().?.occurrences) |occurrence| try std.testing.expect(occurrence.claim_id.ordinal != exact.ordinal);
        const token = try @import("domain/reference_support.zig").exact(all, exact);
        const expanded: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = try std.fmt.allocPrint(a, "The user sees {s}.", .{token.value.raw_value.bytes}) } }} };
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, candidate, authorization, .{ .value = expanded }, null));
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = exact } }} } }, null));
        candidate = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, authorization, .{ .value = .{ .segments = &.{.{ .literal = .{ .value = "Another invalid scalar\x02" } }} } }, null);
        try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, candidate)).?.validated.result);
        const second = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const again = try repair.authorize(a, current, fixture.context, candidate, second, &packet_guidance.marked);
        try std.testing.expectEqualDeep(authorization.rule.value_bound.?, again.rule.value_bound.?);
        try std.testing.expectEqualDeep(authorization.retry.?.key, again.retry.?.key);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, again, .{ .value = .{ .segments = &.{.{ .exact_copy = .{ .claim_id = exact } }} } }, null));
        const recovered = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), current, fixture.context, candidate, again, .{ .value = good.value }, null);
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
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
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
        const first_authorization = try repair.authorize(a, current, fixture.context, with_sibling, first, &packet_guidance.marked);
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
    const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = broken, .primary_goal = plain } } } };
    const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectEqual(.provenance, rejection.issue.rule);
    try std.testing.expectError(error.UnsafeSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked));
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
        var fixture = try Fixture.initContent(a, source, null, true, 1);
        defer fixture.deinit();
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const initial = try sessions.packetFor(a, current, fixture.context, 0, &packet_guidance.marked);
        defer packets.release(initial);
        const bound = try sessions.packetForOptions(a, current, fixture.context, 0, .{ .exact_claims = &.{}, .presentation = .{ .authoring = &packet_guidance.marked } });
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
        const initial = try sessions.packetFor(a, current, fixture.context, 0, &packet_guidance.marked);
        defer packets.release(initial);
        const before = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value;
        try std.testing.expect(before.object.get("exact_texts").?.array.items.len > 0);
        const business = fixture.context.references.records.assignments.checked.prior.prior.input.items[0].claim.id;
        const narrowed = try sessions.withSelectionChoices(a, initial, fixture.context, .{ .claim_ids = &.{business}, .clarification_response_ids = &.{} });
        defer packets.release(narrowed);
        const after = (try std.json.parseFromSlice(std.json.Value, a, narrowed.body(), .{})).value;
        try std.testing.expectEqual(@as(usize, 0), after.object.get("exact_texts").?.array.items.len);
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
        .source_readiness => try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references),
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
    var fixture = try Fixture.initContent(a, "MOCK Required behavior.", null, true, 2);
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
        var fixture = try Fixture.initContent(a, example[0], null, true, 2);
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
        const packet = try support.packetForLoss(a, state.inputs, fixture.context, &packet_guidance.marked, state.pending);
        defer @import("domain/model_input_packet.zig").release(packet);
        const accepted = (try support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .pending = state.pending }, packet, bytes, null)).accepted;
        const retained = accepted.candidate.review.entries[state.pending.pending_localization.? - 1].value.preservation.?;
        try std.testing.expectEqualDeep(assigned, retained.assignment);
        try std.testing.expectEqualDeep(response, retained.response);
        for (0..3) |variant| {
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
                2 => changed.finding.missing_obligation = "MOCK Different obligation.",
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
    for (&claims, 1..) |*claim, line| claim.* = .{
        .category = .business,
        .citations = try a.dupe(@import("domain/source_selections.zig").Id, &.{.{ .ordinal = @intCast(line) }}),
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
        var fixture = try Fixture.initContent(a, "MOCK Keep an audit record.", null, true, 1);
        defer fixture.deinit();
        const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Keep an audit record.");
        break :blk try support.packetForLoss(std.testing.allocator, state.inputs, fixture.context, &packet_guidance.marked, state.pending);
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
    var fixture = try Fixture.initContent(a, "MOCK Close the valve on alarm.", null, true, 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Close the valve on alarm.");
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, state.pending);
    const response = try preservationResponse(a, assigned, .preserved);
    const bytes = try json.encode(preservation.Response, a, response);
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, &packet_guidance.marked, state.pending);
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
    var fixture = try Fixture.initContent(arena.allocator(), "MOCK Retain a receipt.", null, true, 1);
    defer fixture.deinit();
    const state = try preservationTest(arena.allocator(), &fixture, .source_readiness, "MOCK Retain a receipt.");
    const packet = try @import("domain/specification_support.zig").Source.packetForLoss(a, state.inputs, fixture.context, &packet_guidance.marked, state.pending);
    defer @import("domain/model_input_packet.zig").release(packet);
}

test "bound preservation preparation cleans up allocation failures" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(preservationAllocationCheck, .{});
}

test "bound preservation does not attribute composite classification loss to claim insertion" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The claim quotes line 2 only (ADR 0036), so line 1's token is discarded separately.
    var fixture = try Fixture.initClaims(a, "MOCK Display `MOCK Ready` after approval.\nMOCK Approval comes first.\n", null, .{ .selected = &.{.{ .category = .business, .citations = &.{.{ .ordinal = 2 }} }} });
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
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, &packet_guidance.marked, pending);
    defer @import("domain/model_input_packet.zig").release(packet);
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, pending);
    return support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .pending = pending }, packet, try @import("test_fixtures/source_omission_evidence.zig").encode(a, assigned, location), origin);
}

test "preservation lifecycle retains distinct origins and rederives attribution without request logs" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const codec = @import("domain/strict_json.zig");
    for ([_][]const u8{ "MOCK Display date after approval.", "MOCK Renew only an eligible loan." }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, null, true, 1);
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
            try std.testing.expectError(error.InvalidRequiredAuthority, @import("domain/specification_support_evidence.zig").validate(a, changed, fixture.context.inputs, changed.evidence[index]));
        }
        var stale = state.inputs;
        stale.revision += 1;
        const rejection = (try support.validate(a, stale, fixture.context.inputs, accepted.candidate)).rejected;
        try std.testing.expectEqual(.invalid_loss, rejection.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(origin, rejection.rejection.selected().?.origin.?);
        try std.testing.expectError(error.UnsafeSupportRepair, @import("domain/specification_support_repair.zig").Source.authorize(a, stale, fixture.context, &packet_guidance.marked, rejection));
    }
}

test "invalid preservation response reports comparison call and cannot enter semantic repair" {
    const support = @import("domain/specification_support.zig").Source;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "MOCK Preserve receipt.", null, true, 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_readiness, "MOCK Preserve receipt.");
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, &packet_guidance.marked, state.pending);
    defer @import("domain/model_input_packet.zig").release(packet);
    const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 44 }, .attempt = .{ .value = 3 } };
    const result = (try support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .pending = state.pending }, packet, "{\"assessments\":[]}", origin)).rejected;
    try std.testing.expectEqualDeep(origin, result.rejection.selected().?.origin.?);
    try std.testing.expectEqual(state.pending.review.entries[state.pending.pending_localization.? - 1].value.kind, result.candidate.?.review.entries[state.pending.pending_localization.? - 1].value.kind);
    try std.testing.expectEqual(.invalid_loss, result.rejection.selected().?.evidence.?.issue);
    try std.testing.expectError(error.UnsafeSupportRepair, @import("domain/specification_support_repair.zig").Source.authorize(a, state.inputs, fixture.context, &packet_guidance.marked, result));
    try std.testing.expectError(error.InvalidJsonDocument, support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .pending = state.pending }, packet, "{\"kind\":\"candidate\"}", origin));
}

test "multi-chunk and separately classified loss cannot fabricate a unique upstream repair owner" {
    for ([_]struct { source: []const u8, obligation: []const u8, cited: ?u32 }{
        .{ .source = "MOCK Preserve all conditions.\n" ** 70, .obligation = "MOCK Preserve all conditions.", .cited = null },
        // The claim quotes line 2 only (ADR 0036), so line 1's token is discarded separately.
        .{ .source = "MOCK Display `MOCK Approved` after confirmation.\nMOCK Confirmation comes first.\n", .obligation = "MOCK Display `MOCK Approved` after confirmation.", .cited = 2 },
    }) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = if (example.cited) |line| try Fixture.initClaims(a, example.source, null, .{ .selected = &.{.{ .category = .business, .citations = &.{.{ .ordinal = line }} }} }) else try Fixture.initContent(a, example.source, null, true, 1);
        defer fixture.deinit();
        const state = try preservationTest(a, &fixture, .source_preservation, example.obligation);
        const accepted = (try collectedPreservation(a, &fixture, state, .{ .unlocalized = .{} }, null)).accepted;
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
    var fixture = try Fixture.initContent(a, "MOCK Keep both receipt and deadline.", null, true, 1);
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
    const packet = try support.packetForLoss(a, state.inputs, fixture.context, &packet_guidance.marked, pending);
    defer @import("domain/model_input_packet.zig").release(packet);
    const assigned = try support.comparisonAssignment(a, state.inputs, fixture.context, pending);
    const second = (try support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .pending = pending }, packet, try @import("test_fixtures/source_omission_evidence.zig").encode(a, assigned, .{ .reconciliation_signal = fixture.context.references.records.signals[0].id }), null)).accepted;
    const original = state.pending.pending_localization.? - 1;
    try std.testing.expectEqualDeep(first.candidate.review.entries[original], second.candidate.review.entries[original]);
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
    var fixture = try Fixture.initContent(a, "MOCK Retain the delivery deadline.", null, true, 1);
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
        var fixture = try Fixture.initContent(a, obligation, null, true, 1);
        defer fixture.deinit();
        const state = try preservationTest(a, &fixture, .source_preservation, obligation);
        const id = state.inputs.seeds[0].id;
        const required = try admission.requirements(a, state.inputs, fixture.context.inputs, id);
        const initial = try support.packetFor(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .finding = id });
        defer packets.release(initial);
        const review_origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 701 }, .attempt = .{ .value = 2 } };
        const loss_origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 702 }, .attempt = .{ .value = 1 } };
        const source_ids: []const @import("domain/reference_identity.zig").SourceId = &.{fixture.context.inputs.corpus.sources[0].id};
        const response = try json.encode(model.Value, a, .{ .candidate_omission = .{
            .source_ids = source_ids,
            .detail = "MOCK The captured producer discarded this requirement.",
            .missing_obligation = obligation,
        } });
        const collected = (try support.collectFocused(a, state.inputs, fixture.context, &packet_guidance.marked, null, initial, response, review_origin)).accepted;
        const finding = collected.candidate.review.entries[0].value;
        try std.testing.expectEqualStrings(obligation, finding.missing_obligation.?);
        try std.testing.expectEqualStrings(obligation, collected.inputs.evidence[0].review.?.missing_obligation.?);
        try std.testing.expectEqualDeep(source_ids, finding.source_ids);
        try std.testing.expectEqualDeep(source_ids, collected.inputs.evidence[0].review.?.source_ids);
        try std.testing.expectEqualDeep(review_origin, collected.inputs.review_origins[0].?);
        const packet = try support.packetForLoss(a, state.inputs, fixture.context, &packet_guidance.marked, collected.candidate);
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
        try std.testing.expectError(error.InvalidRequiredAuthority, support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .pending = changed }, packet, assessed_bytes, loss_origin));
        const localized = (try support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .accepted = collected }, packet, assessed_bytes, loss_origin)).accepted;
        try std.testing.expectEqualStrings(obligation, localized.candidate.review.entries[0].value.missing_obligation.?);
        const retained = localized.inputs.evidence[0].review.?.preservation.?;
        try std.testing.expectEqualDeep(assigned, retained.assignment);
        try std.testing.expectEqualDeep(review_origin, localized.inputs.review_origins[0].?);
        try std.testing.expectEqualDeep(loss_origin, retained.origin.?);

        const foreign_source = try json.encode(model.Value, a, .{ .candidate_omission = .{
            .source_ids = &.{.{ .ordinal = 999 }},
            .detail = finding.detail,
            .missing_obligation = obligation,
        } });
        const rejected = (try support.collectFocused(a, state.inputs, fixture.context, &packet_guidance.marked, null, initial, foreign_source, review_origin)).rejected;
        try std.testing.expectEqual(.invalid_sources, rejected.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(review_origin, rejected.rejection.selected().?.origin.?);
        var foreign_response = assessed;
        const foreign_entries = try a.dupe(preservation.Assessment, assessed.assessments);
        foreign_entries[0].sources = &.{.{ .chunk_id = .{ .bytes = "MOCK unassigned source" }, .lines = .{ .first = .{ .ordinal = 1 }, .last = .{ .ordinal = 1 } } }};
        foreign_response.assessments = foreign_entries;
        const loss_rejected = (try support.collectLoss(a, state.inputs, fixture.context, &packet_guidance.marked, .{ .accepted = collected }, packet, try json.encode(preservation.Response, a, foreign_response), loss_origin)).rejected;
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
    var source_fixture = try Fixture.initContent(a, obligation, null, true, 2);
    defer source_fixture.deinit();
    const state = try preservationTest(a, &source_fixture, .source_preservation, obligation);
    const assigned = try support.comparisonAssignment(a, state.inputs, source_fixture.context, state.pending);
    try std.testing.expectEqual(@as(usize, 2), assigned.comparisons[0].members.len);
    const packet = try support.packetForLoss(a, state.inputs, source_fixture.context, &packet_guidance.marked, state.pending);
    defer packets.release(packet);
    const prompt = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support-loss.prompt.md", a, .limited(1_048_576));
    try checkProtocolCorrectionPreservesPacket(a, packet, prompt, "{\"assessments\":[],\"members\":[]}");
    // Protocol correction preserves inputs and scope; it supplies no semantic
    // verdict and cannot replace or select the collection being assessed.
    try std.testing.expectEqualDeep(assigned, try support.comparisonAssignment(a, state.inputs, source_fixture.context, state.pending));
}

test "omission obligation correction is closed atomic and retained through admission" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const obligation = "MOCK After cancellation the service must notify the patient.";
    var fixture = try Fixture.initContent(a, obligation, null, true, 1);
    defer fixture.deinit();
    const state = try preservationTest(a, &fixture, .source_preservation, obligation);
    for ([_]?[]const u8{ null, "", " \t\n", "\x00" }) |invalid| {
        var candidate = state.pending;
        const entries = try a.dupe(support.Finding, candidate.review.entries);
        entries[0].value.missing_obligation = invalid;
        candidate.review.entries = entries;
        const rejected = (try support.validate(a, state.inputs, fixture.context.inputs, candidate)).rejected;
        try std.testing.expectEqual(.invalid_obligation, rejected.rejection.selected().?.issue);
        const authorization = try repair.authorize(a, state.inputs, fixture.context, &packet_guidance.marked, rejected);
        const packet = try repair.packet(a, state.inputs, fixture.context, &packet_guidance.marked, candidate, authorization);
        defer packets.release(packet);
        try std.testing.expectEqualStrings("omission_detail", packet.resultDefinition().?.bytes);
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, "{\"detail\":\"MOCK Omitted notification.\"}"));
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, "{\"detail\":\"MOCK Omitted notification.\",\"missing_obligation\":\"MOCK Notify the patient.\",\"kind\":\"supported\"}"));
        const replacement = try repair.parse(a, authorization, packet, "{\"detail\":\"MOCK Omitted notification.\",\"missing_obligation\":\"MOCK After cancellation the service must notify the patient.\"}");
        const corrected = (try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), state.inputs, fixture.context, &packet_guidance.marked, candidate, authorization, replacement, null)).accepted;
        try std.testing.expectEqual(.candidate_omission, corrected.candidate.review.entries[0].value.kind);
        try std.testing.expectEqualDeep(entries[0].value.source_ids, corrected.candidate.review.entries[0].value.source_ids);
        try std.testing.expectEqualDeep(entries[0].value.provenance, corrected.candidate.review.entries[0].value.provenance);
        try std.testing.expectEqualStrings(obligation, corrected.inputs.evidence[0].review.?.missing_obligation.?);
        var stale = candidate;
        stale.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, (fixture.context).inputs), state.inputs, fixture.context, &packet_guidance.marked, stale, authorization, replacement, null));
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
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
    const bound = auth.rule.value_bound.?;
    try std.testing.expectEqualDeep(plain.provenance.claim_ids, bound.explicit);
    try std.testing.expectEqual(plain.provenance.claim_ids.len + 1, bound.effective.len);
    try std.testing.expect(@import("domain/reference_reconciliation.zig").contains(references.r.ClaimId, bound.effective, active));
    const packet = try repair.packet(a, current, fixture.context, auth, &packet_guidance.marked);
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
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked);
    try std.testing.expectEqualDeep(plain.provenance, auth.rule.group.?.membership.fixed_provenance);
    // Insertion and record correction each keep their own native requirement.
    try std.testing.expectEqualStrings("Insert one source-backed entity required by the fixed applicability decision. Preserve all existing records.", auth.rule.requirement);
    const record: spec.Model.RecordProposal = .{ .content = .{ .entity = .{ .name = .{ .segments = &.{.{ .literal = .{ .value = "ACTIVE" } }} } } }, .source_group_ids = plain.source_group_ids, .provenance = plain.provenance };
    const canonical = try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs);
    const inserted = try repair.merge(a, canonical, current, fixture.context, candidate, auth, .{ .record = record }, null);
    _ = (try validate_unit.execute(a, current, fixture.context, inserted)).valid;
    const bound = inserted.group_repair.?.policy.membership.evidence_bound.?;
    try std.testing.expectEqual(plain.provenance.claim_ids.len + 1, bound.effective.len);
    var broken = inserted;
    const records = try a.dupe(spec.Model.RecordProposal, inserted.response.content.entities.records);
    records[0].content.entity.name = .{ .segments = &.{.{ .literal = .{ .value = "Invalid scalar\x01" } }} };
    broken.response.content.entities.records = records;
    const next_rejection = (try validate_unit.execute(a, current, fixture.context, broken)).invalid;
    const correction = try repair.authorize(a, current, fixture.context, broken, next_rejection, &packet_guidance.marked);
    // A record correction keeps its native requirement.
    try std.testing.expectEqualStrings("Return the complete corrected entity record and all siblings.", correction.rule.requirement);
    const packet = try repair.packet(a, current, fixture.context, correction, &packet_guidance.marked);
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
    const assembled = try sessions.assemble(a, text.validator, fixture.context, complete, &.{});
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
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = if (descriptive) good else bad, .primary_goal = if (descriptive) bad else good } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(.typed_text, rejection.issue.rule);
        try std.testing.expectEqual(@as(@FieldType(@import("domain/typed_text.zig").Issue, "reason"), if (descriptive) .prohibited_exact else .reference_only), rejection.issue.text_issue.?.reason);
        try std.testing.expectEqual(@as(@import("domain/text_field_policy.zig").Field, if (descriptive) .spec_goal else .spec_description), rejection.issue.text_issue.?.field.?);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked));
        const in_sentence: spec.BusinessValue = .{ .segments = &.{ .{ .literal = .{ .value = "The user sees " } }, exact } };
        var fixed = candidate;
        if (descriptive) fixed.response.content.brief.primary_goal.value = good.value else fixed.response.content.brief.description.value = in_sentence;
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
            const assembled = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
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
    for ([_][]const u8{ "Display `MOCK Hello, World!` on startup.", "Display `MOCK Renewal accepted!` after renewal." }) |source| for ([_]bool{ false, true }) |goal| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const good = try fixture.proposal("The user observes the supported result.");
        var bad = good;
        bad.value = .{ .segments = &.{.{ .literal = .{ .value = "Display {\"kind\":\"exact_copy\"}." } }} };
        const current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = if (goal) good else bad, .primary_goal = if (goal) bad else good } } } };
        const before = try atomic.snapshot(repair.Candidate, a, candidate);
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        try std.testing.expectEqual(.embedded_insertion_syntax, rejection.issue.text_issue.?.reason);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked));
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
        const initial = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
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
        for ([_]enum { description, goal }{ .description, .goal }) |selected| {
            const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .description = if (selected == .description) bad else good, .primary_goal = if (selected == .goal) bad else good } } } };
            const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
            const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection, &packet_guidance.marked);
            const packet = try repair.packet(a, current, fixture.context, authorization, &packet_guidance.marked);
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
    try std.testing.expect(original.get("exact_texts").?.array.items.len > 0);
    try std.testing.expectEqual(exact, projected.contains("exact_texts"));
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
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, candidate, rejected, &packet_guidance.marked));
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
        var fixture = try Fixture.initContent(a, source, null, true, 1);
        defer fixture.deinit();
        const inputs = try readinessSupportInputs(&fixture);
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
        try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, &packet_guidance.marked, rejected));
    };
}

/// ADR 0016 packet-guidance amendment: an omission repair rule presents each
/// stored comparison with its subject's workflow purpose at its request position.
fn expectPresentedComparisons(a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, proof: @import("domain/source_omission.zig").comparisons.Evidence) !void {
    const purpose = try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, proof.assignment.finding.subject);
    const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value;
    var rule = body.object.get("repair").?.object.get("rule").?;
    if (rule.object.get("finding")) |nested| rule = nested;
    const views = rule.object.get("preservation").?.object.get("assignment").?.object.get("comparisons").?.array.items;
    try std.testing.expectEqual(proof.assignment.comparisons.len, views.len);
    try std.testing.expect(views.len != 0);
    for (proof.assignment.comparisons, views) |stored, presented| {
        const keys = presented.object.keys();
        try std.testing.expectEqual(@as(usize, 3), keys.len);
        for ([_][]const u8{ "id", "purpose", "members" }, keys) |expected, key| try std.testing.expectEqualStrings(expected, key);
        try std.testing.expectEqual(@as(i64, stored.id.ordinal), presented.object.get("id").?.integer);
        try std.testing.expectEqualStrings(purpose, presented.object.get("purpose").?.string);
        try std.testing.expectEqual(stored.members.len, presented.object.get("members").?.array.items.len);
    }
}

/// The stored rule and its presentation have the same native shape once the
/// presented purposes are removed: names, order and every value are unchanged.
fn expectPresentationAddsOnlyPurposes(a: std.mem.Allocator, comptime Rule: type, rule: Rule, finding: @import("domain/required_authority.zig").ReviewEvidence) !void {
    const presentation = @import("domain/model_presentation.zig");
    var presented = try std.json.parseFromSliceLeaky(std.json.Value, a, try std.json.Stringify.valueAlloc(a, try presentation.present(Rule, a, &packet_guidance.marked, rule), .{}), .{});
    var presented_finding = &presented;
    if (Rule != @TypeOf(finding)) presented_finding = presented_finding.object.getPtr("finding").?;
    const views = presented_finding.object.getPtr("preservation").?.object.getPtr("assignment").?.object.getPtr("comparisons").?.array.items;
    try std.testing.expectEqual(finding.preservation.?.assignment.comparisons.len, views.len);
    for (views) |*view| {
        try std.testing.expectEqualStrings(try @import("domain/required_authority_description.zig").task(a, &packet_guidance.marked, finding.preservation.?.assignment.finding.subject), view.object.get("purpose").?.string);
        try std.testing.expect(view.object.orderedRemove("purpose"));
    }
    try std.testing.expectEqualStrings(try std.json.Stringify.valueAlloc(a, rule, .{}), try std.json.Stringify.valueAlloc(a, presented, .{}));
}

fn checkPreparedExtractionOmission(a: std.mem.Allocator, packet: *const @import("domain/model_input_packet.zig").Packet, wire: []const u8) !void {
    const codec = @import("domain/model_candidate_json.zig");
    const bindings = try codec.fieldBindings(@import("domain/reference_extraction.zig").Proposal, a, .{ .reference_phase = .extraction });
    try std.testing.expect(@import("domain/model_text_field.zig").same(bindings, packet.fieldPolicies()));
    // ADR 0036: a claim proposal carries no model wording, only its category and lines.
    try std.testing.expectEqual(@as(usize, 0), bindings.len);
    var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schema = try compiler.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/extraction.schema.json", a, .limited(1_048_576)));
    // The old no-feature outcome is an exact native CAS witness, never an
    // alternative answer for the selected claim-repair response contract.
    try @import("test_fixtures/prepared_model_repair.zig").checkWithoutText(a, packet, schema, wire, extraction.no_claim);
    // The repaired claim cites only supplied, nonblank lines, no more of them than exist.
    const restricted = try @import("domain/model_result_schema.zig").restrict(a, schema.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    const contract = restricted.selected().modelBytes();
    const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    const check = @import("model_payload_schema_test.zig").checkDocument;
    var supplied: usize = 0;
    for (body.value.object.get("input").?.object.get("source_lines").?.array.items) |line| {
        if (@import("domain/source_selections.zig").citable(line.object.get("text").?.string)) {
            supplied += 1;
        } else try check(contract, .{ .bytes = try std.fmt.allocPrint(a, "{{\"category\":\"business\",\"citations\":[{d}]}}", .{line.object.get("id").?.integer}), .rejection = .enum_mismatch, .path = "/citations/0" });
    }
    try check(contract, .{ .bytes = "{\"category\":\"business\",\"citations\":[999]}", .rejection = .enum_mismatch, .path = "/citations/0" });
    var excess: std.ArrayList(u8) = .empty;
    try excess.appendSlice(a, "{\"category\":\"business\",\"citations\":[1");
    for (0..supplied) |_| try excess.appendSlice(a, ",1");
    try excess.appendSlice(a, "]}");
    try check(contract, .{ .bytes = excess.items, .rejection = .array_length, .path = "/citations" });
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
        var fixture = try Fixture.initContent(a, example[0], .code_sample, true, 1);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const current = try completedFixtureValue(&fixture, false, try fixture.proposal(example[2]));
        try std.testing.expectEqual(@as(usize, 1), current.record_group_count);
        const assigned = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
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
        const omitted = try sessions.assemble(a, text.validator, fixture.context, omitted_session, &.{});
        var mapped_brief = omitted_session.units[0].?.response.content.brief;
        const catalogue = try @import("domain/specification_source_binding.zig").catalogue(a, @import("domain/reference_support.zig").records(fixture.context.references), .content);
        const groups = try a.alloc(r.SignalId, catalogue.len);
        const claims = try a.alloc(r.ClaimId, all.entries.len);
        for (catalogue, groups) |group, *id| id.* = group.signal_id;
        for (all.entries, claims) |item, *id| id.* = item.claim.id;
        mapped_brief.primary_goal = try provenance.checkAttributed(.model, a, text.validator, fixture.context, .{ .value = plain.value, .source_group_ids = groups, .provenance = .{ .claim_ids = claims, .clarification_response_ids = &.{} } }, .spec_goal);
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
    var fixture = try Fixture.initContent(a, "Display `ACTIVE` beside `ACTIVE` and `ACTIVE`.", .code_sample, true, 1);
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
    const assigned = try sessions.assemble(a, text.validator, fixture.context, current, &.{});
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
    const state = @import("domain/specification_state.zig");
    const brief = current.units[0].?.response.content.brief;
    const stored: state.State = .{
        .schema = state.schema,
        .principle_registry = try @import("test_fixtures/principles.zig").registry(a, null),
        .feature = current.feature,
        .revision = 1,
        .stage = .specified,
        .reference = snapshot,
        .brief = brief,
        .content = assigned.content,
        .id_ledger = assigned.ledger,
        .coverage = covered,
        .clarification = .{ .state_ordinal = 1, .revision = 1 },
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

test "records name the claims they support from their group, requirements own their claims, and an uncovered behaviour claim gets an engine-bound criterion" {
    const schema = @import("domain/model_result_schema.zig");
    const check = @import("domain/model_payload_schema.zig");
    const sessions = @import("domain/specification_session.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const schemas = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
    const claims = [_]@import("domain/reference_extraction.zig").Proposal{
        .{ .category = .business, .citations = &.{.{ .ordinal = 1 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 2 }} },
    };
    var fixture = try Fixture.initClaimsGrouped(a, "MOCK Renew an active loan.\nMOCK Refuse renewal of an overdue loan.\n", null, .{ .selected = &claims }, &.{&.{ 0, 1 }});
    defer fixture.deinit();
    var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
    const good = try fixture.proposalAllGroups("MOCK Renew an active loan.");
    current.completed = sessions.records_index;
    current.units[0] = (try g.validate(a, text.validator, fixture.context, .brief, .{ .content = .{ .brief = .{ .description = good, .primary_goal = good } } })).valid;
    current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = good } } })).valid;
    const bound = try sessions.currentBinding(a, current, fixture.context);
    const group = bound.records.selection.claim_ids;
    try std.testing.expectEqual(@as(usize, 2), group.len);
    const renew = good.value;
    const refuse = (try fixture.proposalAllGroups("MOCK Refuse renewal of an overdue loan.")).value;
    const fr: spec.Content(spec.BusinessValue) = .{ .functional_requirement = .{ .text = renew } };
    const ec: spec.Content(spec.BusinessValue) = .{ .edge_case = .{ .condition = refuse } };
    const ac: spec.Content(spec.BusinessValue) = .{ .acceptance_criterion = .{ .given = refuse, .when = refuse, .then = refuse } };
    // Parsing keeps the named subset in the group's order, never the model's.
    const wire = try json.encode(g.ModelResponse, a, .{ .records = .{ .records = &.{ .{ .content = fr, .claim_ids = &.{ group[1], group[0] } }, .{ .content = ac, .claim_ids = &.{group[1]} } } } });
    const parsed = try g.parse(a, wire, bound);
    try std.testing.expectEqualDeep(group, parsed.content.records[0].provenance.claim_ids);
    try std.testing.expectEqualDeep(&[_]@import("domain/reference_identity.zig").ClaimId{group[1]}, parsed.content.records[1].provenance.claim_ids);
    // Each record's evidence is its own subset; a sibling's claims don't leak in.
    const checked = (try g.validate(a, text.validator, fixture.context, .records, parsed)).valid;
    try std.testing.expectEqual(@as(usize, 1), checked.response.content.records[1].provenance.claim_ids.len);
    // Stored readback admits a canonical subset record and rejects one out of group order.
    const brief = current.units[0].?.response.content.brief;
    const stored = (try @import("domain/specification_identity.zig").assign(a, .{ .display_name = current.title, .primary_user_story = brief.description, .entities = current.units[2].?.response.content.entities.decision(), .records = &.{ checked.response.content.records[1], checked.response.content.records[0] } }, .{}, &.{})).content;
    const passive: @import("domain/passive_literals.zig").Captured = .{ .records = fixture.context.registry.records, .occurrences = fixture.context.registry.occurrences };
    const supported = @import("domain/reference_support.zig").records(fixture.context.references);
    try provenance.validateStored(a, fixture.context.inputs, passive, supported, brief, stored);
    var reordered = stored;
    const swapped = try a.dupe(spec.IdentifiedRecord, stored.records);
    swapped[1].proposal.provenance.claim_ids = &.{ group[1], group[0] };
    reordered.records = swapped;
    try std.testing.expectError(error.InvalidSpecification, provenance.validateStored(a, fixture.context.inputs, passive, supported, brief, reordered));
    // Identical records naming different claims are not evidence-equivalent, so the
    // native duplicate rule blocks them as competing instead of deleting one.
    const twins = try json.encode(g.ModelResponse, a, .{ .records = .{ .records = &.{ .{ .content = fr, .claim_ids = group }, .{ .content = ec, .claim_ids = &.{group[0]} }, .{ .content = ec, .claim_ids = &.{group[1]} } } } });
    const competing = (try g.validate(a, text.validator, fixture.context, .records, try g.parse(a, twins, bound))).invalid;
    try std.testing.expectEqual(@import("domain/specification_candidate.zig").Rule.duplicate_record, competing.rule);
    try std.testing.expect(competing.blocked != null);
    // An empty, repeated or foreign selection is not a subset of the group.
    for ([_][]const @import("domain/reference_identity.zig").ClaimId{ &.{}, &.{ group[0], group[0] }, &.{.{ .ordinal = 999 }} }) |named| {
        const bad = try json.encode(g.ModelResponse, a, .{ .records = .{ .records = &.{.{ .content = fr, .claim_ids = named }} } });
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, bad, bound));
    }
    // Stored evidence keeps the rule: out of group order or outside the group is invalid.
    for ([_][]const @import("domain/reference_identity.zig").ClaimId{ &.{ group[1], group[0] }, &.{.{ .ordinal = 999 }}, &.{} }) |named| {
        const record: spec.Model.RecordProposal = .{ .content = fr, .source_group_ids = &.{bound.records.signal}, .provenance = .{ .claim_ids = named, .clarification_response_ids = &.{} } };
        try std.testing.expect(try g.validate(a, text.validator, fixture.context, .records, .{ .content = .{ .records = &.{record} } }) == .invalid);
    }
    // ADR 0038: the records request names the group's claims, and admission sends back a
    // non-requirement statement naming both claims a requirement or an earlier such
    // statement names and claims none does. A behaviour statement's claim no acceptance
    // criterion or edge case names is admitted: the session repairs it (Decision 3).
    // Requirements may share a claim.
    const packet = try sessions.packet(a, current, fixture.context, &packet_guidance.marked);
    defer @import("domain/model_input_packet.zig").release(packet);
    const restricted = try schema.restrict(a, schemas.select(packet.resultDefinition().?).?, packet.excludedVariants(), packet.integerChoices());
    defer restricted.release();
    try std.testing.expectEqual(@as(usize, 1), restricted.selected().coverageChoices().len);
    const item = "{{\"content\":{{\"kind\":\"{s}\",\"text\":\"MOCK x\"}},\"claim_ids\":{s}}}";
    const scenario = "{{\"content\":{{\"kind\":\"edge_case\",\"condition\":\"MOCK c\"}},\"claim_ids\":{s}}}";
    const one = try std.fmt.allocPrint(a, "[{d}]", .{group[0].ordinal});
    const both = try std.fmt.allocPrint(a, "[{d},{d}]", .{ group[0].ordinal, group[1].ordinal });
    const second = try std.fmt.allocPrint(a, "[{d}]", .{group[1].ordinal});
    const criterion = "{{\"content\":{{\"kind\":\"acceptance_criterion\",\"given\":\"MOCK g\",\"when\":\"MOCK w\",\"then\":\"MOCK t\"}},\"claim_ids\":{s}}}";
    for ([_]struct { bytes: []const u8, rejection: ?check.Rejection, path: []const u8 = "" }{
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", both, both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ scenario ++ "]}}", .{ "functional_requirement", both, both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ scenario ++ "]}}", .{ "functional_requirement", both, one }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "business_rule", both, both }), .rejection = .shared_member, .path = "/records/1" },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "assumption", both, both }), .rejection = .shared_member, .path = "/records/1" },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "]}}", .{ "business_rule", both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ criterion ++ "]}}", .{ "business_rule", both, both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "non_goal", second, one }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "]}}", .{ "assumption", both }), .rejection = null },
        // No behaviour kind's uncovered claim is an admission defect. Every
        // non-requirement statement kind is corrected when partly taken, by a requirement
        // before or after it or by an earlier such statement.
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "]}}", .{ "user_visible_outcome", both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "]}}", .{ "prohibited_behavior", both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "]}}", .{ "non_goal", both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "user_visible_outcome", both, both }), .rejection = .shared_member, .path = "/records/1" },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "non_goal", both, both }), .rejection = .shared_member, .path = "/records/1" },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "business_rule", second, "prohibited_behavior", both, both }), .rejection = .shared_member, .path = "/records/1" },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "user_visible_outcome", both, "functional_requirement", one, both }), .rejection = .shared_member, .path = "/records/0" },
        // A statement whose every claim a requirement or an earlier statement names is
        // admitted for its native delete, wherever the requirement is; requirements may
        // share a claim.
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "assumption", one, one }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "user_visible_outcome", one, "functional_requirement", one, one }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "prohibited_behavior", both, "business_rule", second, both }), .rejection = null },
        .{ .bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "functional_requirement", both, both }), .rejection = null },
        .{ .bytes = "{\"kind\":\"records\",\"records\":[{\"content\":{\"kind\":\"business_rule\",\"text\":\"MOCK x\"},\"claim_ids\":[999]}]}", .rejection = .enum_mismatch },
    }) |case| {
        const document = try std.json.parseFromSlice(std.json.Value, a, case.bytes, .{ .parse_numbers = false });
        const result = check.validateValue(@import("domain/model_envelope.zig").value(&document.value), restricted.selected().root());
        if (case.rejection) |expected| {
            try std.testing.expectEqual(expected, result.?.reason);
            if (case.path.len != 0) try std.testing.expectEqualStrings(case.path, (try result.?.describe(a)).path);
        } else try std.testing.expect(result == null);
    }
    // The partly taken correction resolves against the real records schema, as the
    // protocol correction does: the record node is located and outlined, the rule is the
    // compiled one, and the taken naming is the one listed.
    {
        const projection = @import("domain/model_schema_projection.zig");
        const bytes = try std.fmt.allocPrint(a, "{{\"kind\":\"records\",\"records\":[" ++ item ++ "," ++ item ++ "," ++ criterion ++ "]}}", .{ "functional_requirement", one, "business_rule", both, both });
        const document = try std.json.parseFromSlice(std.json.Value, a, bytes, .{ .parse_numbers = false });
        const response = @import("domain/model_envelope.zig").value(&document.value);
        const rejected = check.validateValue(response, restricted.selected().root()).?;
        try std.testing.expectEqual(check.Rejection.shared_member, rejected.reason);
        try std.testing.expectEqualStrings("/records/1", (try rejected.describeExpected(a)).path);
        try std.testing.expect((try projection.locate(a, restricted.selected(), rejected.expected)) != null);
        try std.testing.expect((try projection.outline(a, rejected.expected)) == .object);
        try std.testing.expectEqualDeep(sessions.statement_rule, rejected.coverage.?.rule);
        const records = response.object.get("records").?.array;
        try std.testing.expectEqualDeep(@as(?check.SharedNaming, .{ .item = 1, .position = 0 }), check.nextSharedNaming(records, rejected.coverage.?, .{ .item = 0, .position = 0 }));
        try std.testing.expect(check.nextSharedNaming(records, rejected.coverage.?, .{ .item = 1, .position = 1 }) == null);
    }
    // ADR 0038 Decision 5: the session deletes such a statement natively, one at a time,
    // with no model call, and keeps requirements, scenarios and requirements sharing a
    // claim. The batch has a live loan-renewal shape: an outcome restating each
    // requirement, before or after it, and a second requirement for one prose claim.
    const repair = @import("domain/specification_repair.zig");
    const signals: []const @TypeOf(bound.records.signal) = &.{bound.records.signal};
    const batch = [_]spec.Model.RecordProposal{
        .{ .content = .{ .user_visible_outcome = .{ .text = renew } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group[0..1], .clarification_response_ids = &.{} } },
        .{ .content = fr, .source_group_ids = signals, .provenance = .{ .claim_ids = group[0..1], .clarification_response_ids = &.{} } },
        .{ .content = .{ .functional_requirement = .{ .text = refuse } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group[1..2], .clarification_response_ids = &.{} } },
        .{ .content = .{ .acceptance_criterion = .{ .given = renew, .when = renew, .then = renew } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group, .clarification_response_ids = &.{} } },
        .{ .content = ec, .source_group_ids = signals, .provenance = .{ .claim_ids = group[1..2], .clarification_response_ids = &.{} } },
        .{ .content = .{ .user_visible_outcome = .{ .text = refuse } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group[1..2], .clarification_response_ids = &.{} } },
        .{ .content = .{ .functional_requirement = .{ .text = .{ .segments = &.{.{ .literal = .{ .value = "MOCK Show the refusal." } }} } } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group[1..2], .clarification_response_ids = &.{} } },
    };
    var proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = &batch } } };
    for ([_]usize{ 0, 4 }) |deleted| {
        const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        try std.testing.expectEqual(@import("domain/specification_candidate.zig").Rule.repeated_statement, rejection.issue.rule);
        const authorization = try repair.authorize(a, current, fixture.context, proposed, rejection, &packet_guidance.marked);
        try std.testing.expectEqual(deleted, authorization.target.record);
        try std.testing.expect(authorization.operation == .delete);
        // A native delete takes no model value.
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, proposed, authorization, .{ .provenance = proposed.response.content.records[deleted].provenance }, null));
        proposed = try repair.merge(a, try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs), current, fixture.context, proposed, authorization, null, null);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, proposed)).?.validated.result);
    }
    _ = (try validate_unit.execute(a, current, fixture.context, proposed)).valid;
    try std.testing.expectEqualDeep(@as([]const spec.Model.RecordProposal, &.{ batch[1], batch[2], batch[3], batch[4], batch[6] }), proposed.response.content.records);

    // ADR 0038 Decision 3: a behaviour statement's claim that no scenario of its batch
    // names is decided on the batch the native deletes leave, and repaired by one
    // acceptance-criterion insert whose claim and group the engine fixes; the model
    // writes only its content. A statement the engine deletes needs no scenario, and an
    // assumption or non-goal needs none at all.
    const canonical = try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs);
    const scope_only = [_]spec.Model.RecordProposal{
        .{ .content = fr, .source_group_ids = signals, .provenance = .{ .claim_ids = group[0..1], .clarification_response_ids = &.{} } },
        .{ .content = ac, .source_group_ids = signals, .provenance = .{ .claim_ids = group[0..1], .clarification_response_ids = &.{} } },
        .{ .content = .{ .assumption = .{ .text = refuse } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group[1..2], .clarification_response_ids = &.{} } },
    };
    _ = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = &scope_only } } })).valid;
    const uncovered_batch = [_]spec.Model.RecordProposal{
        .{ .content = fr, .source_group_ids = signals, .provenance = .{ .claim_ids = group, .clarification_response_ids = &.{} } },
        .{ .content = ec, .source_group_ids = signals, .provenance = .{ .claim_ids = group[0..1], .clarification_response_ids = &.{} } },
        // Every claim of this outcome the requirement names, so the engine deletes it first.
        .{ .content = .{ .user_visible_outcome = .{ .text = refuse } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group[1..2], .clarification_response_ids = &.{} } },
    };
    var uncovered: repair.Candidate = .{ .response = .{ .content = .{ .records = &uncovered_batch } } };
    const repeat = (try validate_unit.execute(a, current, fixture.context, uncovered)).invalid;
    try std.testing.expectEqual(@import("domain/specification_candidate.zig").Rule.repeated_statement, repeat.issue.rule);
    uncovered = try repair.merge(a, canonical, current, fixture.context, uncovered, try repair.authorize(a, current, fixture.context, uncovered, repeat, &packet_guidance.marked), null, null);
    const gap = (try validate_unit.execute(a, current, fixture.context, uncovered)).invalid;
    try std.testing.expectEqual(@import("domain/specification_candidate.zig").Rule.scenario_coverage, gap.issue.rule);
    try std.testing.expectEqual(group[1].ordinal, gap.issue.uncovered_claim.?.ordinal);
    const insert = try repair.authorize(a, current, fixture.context, uncovered, gap, &packet_guidance.marked);
    try std.testing.expect(insert.operation == .insert);
    try std.testing.expectEqual(@as(usize, 2), insert.target.record);
    const policy = insert.rule.group.?;
    try std.testing.expect(policy == .scenario);
    try std.testing.expectEqualDeep(&[_]@import("domain/reference_identity.zig").ClaimId{group[1]}, policy.scenario.fixed_provenance.claim_ids);
    try std.testing.expectEqualDeep(signals, policy.scenario.fixed_source_group_ids);
    // The request selects the content-only criterion definition and names the fixed claim.
    const insert_packet = try repair.packet(a, current, fixture.context, insert, &packet_guidance.marked);
    defer @import("domain/model_input_packet.zig").release(insert_packet);
    try std.testing.expectEqualStrings("repair_record_acceptance_criterion", insert_packet.resultDefinition().?.bytes);
    try std.testing.expect(std.mem.indexOf(u8, insert_packet.body(), "\"provenance\"") != null);
    // Rejected: another record kind, or any claims but the fixed one.
    const tested: spec.Model.RecordProposal = .{ .content = ac, .source_group_ids = signals, .provenance = .{ .claim_ids = group[1..2], .clarification_response_ids = &.{} } };
    var edge = tested;
    edge.content = ec;
    var widened = tested;
    widened.provenance.claim_ids = group;
    for ([_]spec.Model.RecordProposal{ edge, widened }) |wrong| {
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, canonical, current, fixture.context, uncovered, insert, .{ .record = wrong }, null));
    }
    const repaired = try repair.merge(a, canonical, current, fixture.context, uncovered, insert, .{ .record = tested }, null);
    try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, repaired)).?.validated.result);
    _ = (try validate_unit.execute(a, current, fixture.context, repaired)).valid;
    try std.testing.expectEqualDeep(@as([]const spec.Model.RecordProposal, &.{ uncovered_batch[0], uncovered_batch[1], tested }), repaired.response.content.records);
    // The rejection binds the revision it was found at: after the insert it is stale.
    try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, repaired, gap, &packet_guidance.marked));
}

test "every uncovered claim of a batch takes its own criterion insert within the frozen repair bound" {
    // ADR 0038 Decision 3 in an unrelated domain: one requirement names six list-item claims
    // and no scenario names any, so six inserts follow one another under the bound frozen at
    // the first authorization, more than the batch's one record alone allows.
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_repair.zig");
    const ClaimId = @import("domain/reference_identity.zig").ClaimId;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const claims = [_]@import("domain/reference_extraction.zig").Proposal{
        .{ .category = .business, .citations = &.{.{ .ordinal = 1 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 2 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 3 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 4 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 5 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 6 }} },
    };
    var fixture = try Fixture.initClaimsGrouped(a, "MOCK Book a meeting room.\nMOCK Show free rooms.\nMOCK Hold a room for ten minutes.\nMOCK Release an unconfirmed hold.\nMOCK Refuse a double booking.\nMOCK Email the organiser.\n", null, .{ .selected = &claims }, &.{&.{ 0, 1, 2, 3, 4, 5 }});
    defer fixture.deinit();
    var current = (try sessions.initialize(a, fixture.context.inputs.corpus.feature_id, fixture.context)).ready;
    const good = try fixture.proposalAllGroups("MOCK Book a meeting room.");
    current.completed = sessions.records_index;
    current.units[0] = (try g.validate(a, text.validator, fixture.context, .brief, .{ .content = .{ .brief = .{ .description = good, .primary_goal = good } } })).valid;
    current.units[2] = (try g.validate(a, text.validator, fixture.context, .entities, .{ .content = .{ .entities = .{ .disposition = .not_applicable, .basis = good } } })).valid;
    const bound = try sessions.currentBinding(a, current, fixture.context);
    const group = bound.records.selection.claim_ids;
    try std.testing.expectEqual(@as(usize, 6), group.len);
    const signals = try a.dupe(@TypeOf(bound.records.signal), &.{bound.records.signal});
    const requirement: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = good.value } }, .source_group_ids = signals, .provenance = .{ .claim_ids = group, .clarification_response_ids = &.{} } };
    const canonical = try @import("domain/typed_text.zig").CanonicalText.fromInputs(a, text.normalizer, fixture.context.inputs);
    var candidate: repair.Candidate = .{ .response = .{ .content = .{ .records = try a.dupe(spec.Model.RecordProposal, &.{requirement}) } } };
    var inserts: usize = 0;
    var frozen: ?u32 = null;
    while (true) {
        const result = try validate_unit.execute(a, current, fixture.context, candidate);
        if (result == .valid) break;
        const gap = result.invalid;
        try std.testing.expectEqual(@import("domain/specification_candidate.zig").Rule.scenario_coverage, gap.issue.rule);
        try std.testing.expectEqual(group[inserts].ordinal, gap.issue.uncovered_claim.?.ordinal);
        const insert = try repair.authorize(a, current, fixture.context, candidate, gap, &packet_guidance.marked);
        // The retry state admits a new target only while its scope's frozen bound has room
        // (`workflow_retry.zig`), so the bound fixed at the first insert must hold them all.
        const permit = insert.retry.?;
        if (frozen) |bound_targets| try std.testing.expectEqual(bound_targets, permit.maximum_targets) else frozen = permit.maximum_targets;
        try std.testing.expect(inserts < permit.maximum_targets);
        const wording = try std.fmt.allocPrint(a, "MOCK Case {d} is observed.", .{inserts + 1});
        const tested: spec.BusinessValue = .{ .segments = try a.dupe(@import("domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = wording } }}) };
        const criterion: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = tested, .when = tested, .then = tested } }, .source_group_ids = signals, .provenance = .{ .claim_ids = try a.dupe(ClaimId, &.{group[inserts]}), .clarification_response_ids = &.{} } };
        // Rejected: the same criterion in a group other than the batch's.
        var elsewhere = criterion;
        elsewhere.source_group_ids = &.{};
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, canonical, current, fixture.context, candidate, insert, .{ .record = elsewhere }, null));
        candidate = try repair.merge(a, canonical, current, fixture.context, candidate, insert, .{ .record = criterion }, null);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, candidate)).?.validated.result);
        inserts += 1;
    }
    try std.testing.expectEqual(@as(usize, 6), inserts);
    try std.testing.expectEqual(@as(usize, 7), candidate.response.content.records.len);
    // The one requirement alone would bound the scope at 5 targets, fewer than its six claims.
    try std.testing.expect(frozen.? > 6);
}

test "coverage counts only the claims each record names" {
    const coverage = @import("domain/specification_coverage.zig");
    const ClaimId = @import("domain/reference_identity.zig").ClaimId;
    const SignalId = @import("domain/reference_reconciliation.zig").SignalId;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const claims = [_]@import("domain/reference_extraction.zig").Proposal{
        .{ .category = .business, .citations = &.{.{ .ordinal = 1 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 2 }} },
        .{ .category = .business, .citations = &.{.{ .ordinal = 3 }} },
    };
    // Group one holds the purpose claim; group two holds two behaviours.
    var fixture = try Fixture.initClaimsGrouped(a, "MOCK Renew loans.\nMOCK Extend the due date by fourteen days.\nMOCK Refuse renewal of an overdue loan.\n", null, .{ .selected = &claims }, &.{ &.{0}, &.{ 1, 2 } });
    defer fixture.deinit();
    const records = @import("domain/reference_support.zig").records(fixture.context.references);
    const purpose = records.signals[0];
    const behaviours = records.signals[1];
    try std.testing.expectEqual(@as(usize, 2), behaviours.value.claim_ids.len);
    const extend = behaviours.value.claim_ids[0];
    const refuse = behaviours.value.claim_ids[1];
    const attributed = struct {
        fn of(allocator: std.mem.Allocator, group: SignalId, named: []const ClaimId) !spec.AttributedValue {
            return .{ .value = .{ .segments = try allocator.dupe(@import("domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = "MOCK value" } }}) }, .source_group_ids = try allocator.dupe(SignalId, &.{group}), .provenance = .{ .claim_ids = named, .citation_ids = &.{}, .clarification_response_ids = &.{} } };
        }
    }.of;
    const narrative = try attributed(a, purpose.id, purpose.value.claim_ids);
    const brief: spec.Brief = .{ .description = narrative, .primary_goal = narrative };
    const record = struct {
        fn of(kind: spec.Kind, ordinal: u32, content: spec.Content(spec.BusinessValue), value: spec.AttributedValue) spec.IdentifiedRecord {
            return .{ .id = .{ .kind = kind, .ordinal = ordinal }, .proposal = .{ .content = content, .source_group_ids = value.source_group_ids, .provenance = value.provenance } };
        }
    }.of;
    const text_value = narrative.value;
    const requirement = record(.functional_requirement, 1, .{ .functional_requirement = .{ .text = text_value } }, try attributed(a, behaviours.id, &.{extend}));
    const scenario = record(.edge_case, 1, .{ .edge_case = .{ .condition = text_value } }, try attributed(a, behaviours.id, &.{extend}));
    const refusal = record(.edge_case, 2, .{ .edge_case = .{ .condition = text_value } }, try attributed(a, behaviours.id, &.{refuse}));
    const content = struct {
        fn of(story: spec.AttributedValue, value: spec.AttributedValue, authored: []const spec.IdentifiedRecord) spec.IdentifiedContent {
            return .{ .display_name = fixture_display_name, .primary_user_story = story, .records = authored, .entities = .{ .disposition = .not_applicable, .basis = value } };
        }
    }.of;
    // A claim no record names, in a group no narrative field selects, is unmapped
    // and blocks; before ADR 0038 every record of the batch carried it.
    const unnamed = try coverage.checkRecords(a, records, brief, content(narrative, narrative, &.{ requirement, scenario }));
    try std.testing.expect(unnamed == .invalid);
    try std.testing.expectEqual(refuse, unnamed.invalid.claim_id);
    try std.testing.expect(unnamed.invalid.issue == .missing_business_mapping);
    // Naming it maps it.
    try std.testing.expect(try coverage.checkRecords(a, records, brief, content(narrative, narrative, &.{ requirement, scenario, refusal })) == .valid);
    // A narrative field that selects the group still maps every claim in it, named or
    // not (an ADR 0038 limit).
    const story = try attributed(a, behaviours.id, behaviours.value.claim_ids);
    try std.testing.expect(try coverage.checkRecords(a, records, brief, content(story, narrative, &.{ requirement, scenario })) == .valid);
}

fn authoredRecord(content: spec.Content(spec.BusinessValue), value: spec.Model.AttributedValue) spec.Model.RecordProposal {
    return .{ .content = content, .source_group_ids = value.source_group_ids, .provenance = value.provenance };
}

/// A session whose records unit holds `batches`, one per source group, in order.
fn sessionWithBatches(a: std.mem.Allocator, fixture: *const Fixture, batches: []const []const spec.Model.RecordProposal) !@import("domain/specification_session.zig").Session {
    const sessions = @import("domain/specification_session.zig");
    var current = try sessionAtRecords(a, fixture, try fixture.proposal("A loan can be renewed."));
    for (batches) |batch| {
        const checked = (try validate_unit.execute(a, current, fixture.context, .{ .response = .{ .content = .{ .records = batch } } })).valid;
        current = try sessions.appendBound(a, current, checked);
    }
    try std.testing.expectEqual(sessions.unit_count, current.completed);
    return current;
}

test "ADR 0038 Decision 7 an edge case's link is native, one closed choice among its batch's criteria, or a block" {
    const sessions = @import("domain/specification_session.zig");
    const links = @import("domain/scenario_link.zig");
    const request = @import("domain/scenario_link_request.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Two source groups: the first batch holds an edge case beside two criteria that name its
    // claim, the second an edge case beside one.
    var fixture = try Fixture.initContent(a, "Renew eligible loans.", null, true, 2);
    defer fixture.deinit();
    const renewed = try fixture.proposalGroup("The loan is renewed.", 0);
    const kept = try fixture.proposalGroup("The loan keeps its due date.", 0);
    const refused = try fixture.proposalGroup("The renewal is refused.", 1);
    // Two requirements precede the criteria, so a criterion's position in the unit is never its
    // offered id.
    const first_batch = [_]spec.Model.RecordProposal{
        authoredRecord(.{ .functional_requirement = .{ .text = renewed.value } }, renewed),
        authoredRecord(.{ .functional_requirement = .{ .text = kept.value } }, renewed),
        authoredRecord(.{ .acceptance_criterion = .{ .given = renewed.value, .when = renewed.value, .then = renewed.value } }, renewed),
        authoredRecord(.{ .acceptance_criterion = .{ .given = renewed.value, .when = renewed.value, .then = kept.value } }, renewed),
        authoredRecord(.{ .edge_case = .{ .condition = renewed.value } }, renewed),
    };
    const second_batch = [_]spec.Model.RecordProposal{
        authoredRecord(.{ .functional_requirement = .{ .text = refused.value } }, refused),
        authoredRecord(.{ .acceptance_criterion = .{ .given = refused.value, .when = refused.value, .then = refused.value } }, refused),
        authoredRecord(.{ .edge_case = .{ .condition = refused.value } }, refused),
    };
    const current = try sessionWithBatches(a, &fixture, &.{ &first_batch, &second_batch });
    const plan = try request.planFor(a, current);
    // Positions index the unit in authoring order. The second batch's edge case has its only
    // criterion; the first batch's two make one pending choice, and no criterion crosses batches.
    try std.testing.expectEqual(@as(?u32, null), plan.unlinkable);
    try std.testing.expectEqualDeep(&[_]links.Link{.{ .edge_case = 7, .criterion = 6 }}, plan.native);
    try std.testing.expectEqual(@as(usize, 1), plan.pending.len);
    try std.testing.expectEqual(@as(u32, 4), plan.pending[0].edge_case);
    try std.testing.expectEqualDeep(&[_]u32{ 2, 3 }, plan.pending[0].candidates);
    try std.testing.expectEqual(@as(usize, 1), (try request.begin(a, current, fixture.context)).ready);
    try std.testing.expectEqual(@as(usize, 1), try request.limit(a, current));

    // The request offers that batch's criteria, numbered from one, and nothing of the other batch.
    const offered = try request.packet(a, current, fixture.context, 0);
    defer packets.release(offered);
    const body = (try std.json.parseFromSlice(std.json.Value, a, offered.body(), .{})).value;
    try std.testing.expectEqualStrings("The loan is renewed.", body.object.get("edge_case").?.string);
    const criteria = body.object.get("acceptance_criteria").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), criteria.len);
    try std.testing.expectEqual(@as(i64, 1), criteria[0].object.get("id").?.integer);
    try std.testing.expectEqual(@as(i64, 2), criteria[1].object.get("id").?.integer);
    try std.testing.expectEqualStrings("The loan is renewed.", criteria[0].object.get("then").?.string);
    try std.testing.expectEqualStrings("The loan keeps its due date.", criteria[1].object.get("then").?.string);
    try std.testing.expect(std.mem.indexOf(u8, offered.body(), "The renewal is refused.") == null);
    try std.testing.expectEqualStrings(request.definition, offered.resultDefinition().?.bytes);
    try std.testing.expectEqualStrings("specification-links-1", offered.unit().specification_unit.unit_slot_id.bytes);
    try std.testing.expectEqual(@as(usize, 1), offered.integerChoices().len);
    try std.testing.expectEqualSlices(i64, &.{ 1, 2 }, offered.integerChoices()[0].allowed);

    // The request's response schema admits only an offered id and nothing else.
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = try parser.compiler().compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/links.schema.json", a, .unlimited));
    const restricted = try @import("domain/model_result_schema.zig").restrict(a, canonical.select(.{ .bytes = request.definition }).?, offered.excludedVariants(), offered.integerChoices());
    defer restricted.release();
    const payload = @import("model_payload_schema_test.zig");
    try payload.checkCompiled(restricted.selected(), .{ .bytes = "{\"criterion\":1}" });
    try payload.checkCompiled(restricted.selected(), .{ .bytes = "{\"criterion\":2}" });
    try payload.checkCompiled(restricted.selected(), .{ .bytes = "{\"criterion\":3}", .rejection = .enum_mismatch, .path = "/criterion" });
    try payload.checkCompiled(restricted.selected(), .{ .bytes = "{\"criterion\":2,\"outcome\":\"The renewal is refused.\"}", .rejection = .unknown_property, .path = "/outcome" });
    try payload.checkCompiled(restricted.selected(), .{ .bytes = "{}", .rejection = .missing_required_property, .path = "/criterion" });

    // The answer makes the link of the pending edge case to the criterion it names: the offered id
    // is a place among the candidates, not a position in the unit.
    const choice = try request.admit(a, current, fixture.context, 0, offered, "{\"criterion\":2}");
    try std.testing.expectEqualDeep(links.Link{ .edge_case = 4, .criterion = 3 }, choice);
    try std.testing.expectEqualDeep(links.Link{ .edge_case = 4, .criterion = 2 }, try request.admit(a, current, fixture.context, 0, offered, "{\"criterion\":1}"));
    try std.testing.expectError(error.InvalidScenarioLink, request.admit(a, current, fixture.context, 0, offered, "{\"criterion\":3}"));
    for ([_][]const u8{ "{\"criterion\":0}", "{\"criterion\":1,\"outcome\":\"x\"}", "{}", "{\"criterion\":\"1\"}", "{\"criterion\":1.5}" }) |bad| {
        try std.testing.expect(std.meta.isError(request.admit(a, current, fixture.context, 0, offered, bad)));
    }
    // A request that is not the one native code builds now admits nothing, and no choice
    // exists beyond the plan's pending edge cases.
    const stale = try packets.withBody(a, offered, "{\"edge_case\":\"The loan is renewed.\",\"acceptance_criteria\":[]}");
    defer packets.release(stale);
    try std.testing.expectError(error.InvalidScenarioLink, request.admit(a, current, fixture.context, 0, stale, "{\"criterion\":1}"));
    try std.testing.expectError(error.InvalidScenarioLink, request.admit(a, current, fixture.context, 1, offered, "{\"criterion\":1}"));

    // The registered actions wrap these owners: the plan counts the pending choices, the check
    // compares the choices so far with them, the input is the request for the next one, and the
    // admission appends the answer to the choices so far.
    const planning = @import("actions/specification/plan_scenario_links.zig").Action{};
    try std.testing.expectEqual(@as(usize, 1), (try planning.execute(a, current, fixture.context)).ready);
    const check = @import("actions/specification/check_scenario_link_progress.zig").Action{};
    try std.testing.expectEqual(.more, try check.execute(a, current, &.{}));
    try std.testing.expectEqual(.ok, try check.execute(a, current, &.{choice}));
    try std.testing.expectError(error.InvalidScenarioLink, check.execute(a, current, &.{ choice, choice }));
    const building = @import("actions/specification/build_scenario_link_input.zig").Action{};
    const built = try building.execute(a, current, fixture.context, &.{});
    defer packets.release(built);
    try std.testing.expectEqualStrings(offered.body(), built.body());
    try std.testing.expectError(error.InvalidScenarioLink, building.execute(a, current, fixture.context, &.{choice}));
    const admission = @import("actions/specification/admit_scenario_link_choice.zig").Action{};
    try std.testing.expectEqualDeep(&[_]links.Link{choice}, try admission.execute(a, current, fixture.context, &.{}, offered, "{\"criterion\":2}"));
    try std.testing.expectError(error.InvalidScenarioLink, admission.execute(a, current, fixture.context, &.{choice}, offered, "{\"criterion\":2}"));

    // Every edge case resolves once the pending one has its choice; ids follow authoring order.
    const resolved = try links.resolve(a, plan, &.{choice});
    try std.testing.expectEqualDeep(&[_]links.Link{ .{ .edge_case = 4, .criterion = 3 }, .{ .edge_case = 7, .criterion = 6 } }, resolved);
    try std.testing.expectError(error.InvalidScenarioLink, links.resolve(a, plan, &.{}));
    const assigned = try sessions.assemble(a, text.validator, fixture.context, current, resolved);
    // Links name records-unit positions: one past the unit, or the other batch's criterion, is refused.
    try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, current, &.{ .{ .edge_case = 4, .criterion = 99 }, resolved[1] }));
    try std.testing.expectError(error.InvalidSpecification, sessions.assemble(a, text.validator, fixture.context, current, &.{ .{ .edge_case = 4, .criterion = 6 }, resolved[1] }));
    var edge_cases: usize = 0;
    for (assigned.content.records) |record| {
        if (record.proposal.content != .edge_case) {
            try std.testing.expect(record.outcome_of == null);
            continue;
        }
        edge_cases += 1;
        // Criteria are AC-001 and AC-002 in the first batch and AC-003 in the second.
        const target: spec.Id = .{ .kind = .acceptance_criterion, .ordinal = if (record.id.ordinal == 1) 2 else 3 };
        try std.testing.expectEqualDeep(target, record.outcome_of.?);
    }
    try std.testing.expectEqual(@as(usize, 2), edge_cases);

    // The printed outcome is the linked criterion's Then, a derived display. A rendering whose
    // outcome line was edited still parses, yet it is not the render of the content's projection,
    // which is what publication compares.
    const projection = @import("domain/specification_projection.zig");
    const codec = @import("domain/specification_markdown.zig");
    const document = try projection.project(a, fixture.context, test_directory, assigned.content);
    const rendered = try codec.render(a, document);
    const printed = "- **EXPECTED OUTCOME** The loan keeps its due date.";
    try std.testing.expect(std.mem.indexOf(u8, rendered, printed) != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "- **EXPECTED OUTCOME** The renewal is refused.") != null);
    const forged = try std.mem.replaceOwned(u8, a, rendered, printed, "- **EXPECTED OUTCOME** The loan is renewed.");
    try std.testing.expect(!std.mem.eql(u8, forged, rendered));
    try std.testing.expectEqualStrings(forged, try codec.render(a, try codec.parse(a, forged)));
    try std.testing.expectEqualStrings(rendered, try codec.render(a, try projection.project(a, fixture.context, test_directory, assigned.content)));
    // An operational failure at any allocation is an error, never a partial request or a leak.
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(linkAllocationCase, .{ current, fixture.context });
}

fn linkAllocationCase(allocator: std.mem.Allocator, current: @import("domain/specification_session.zig").Session, context: provenance.Context) !void {
    const request = @import("domain/scenario_link_request.zig");
    var scratch: std.heap.ArenaAllocator = .init(allocator);
    defer scratch.deinit();
    try std.testing.expectEqual(@as(usize, 1), (try request.begin(scratch.allocator(), current, context)).ready);
    const offered = try request.packet(allocator, current, context, 0);
    defer @import("domain/model_input_packet.zig").release(offered);
    const choice = try request.admit(allocator, current, context, 0, offered, "{\"criterion\":2}");
    try std.testing.expectEqual(@as(u32, 3), choice.criterion);
}

test "an edge case no criterion of its batch can serve blocks with a typed gap and no request" {
    const request = @import("domain/scenario_link_request.zig");
    const links = @import("domain/scenario_link.zig");
    const Diagnostic = @import("domain/candidate_validation_diagnostic.zig").Diagnostic;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.initContent(a, "Renew eligible loans.", null, true, 2);
    defer fixture.deinit();
    const renewed = try fixture.proposalGroup("The loan is renewed.", 0);
    const refused = try fixture.proposalGroup("The renewal is refused.", 1);
    // The second batch's edge case covers its claim, which is valid, yet only a criterion of
    // that batch may serve it; the first batch's criterion cannot.
    const first_batch = [_]spec.Model.RecordProposal{
        authoredRecord(.{ .functional_requirement = .{ .text = renewed.value } }, renewed),
        authoredRecord(.{ .acceptance_criterion = .{ .given = renewed.value, .when = renewed.value, .then = renewed.value } }, renewed),
    };
    const second_batch = [_]spec.Model.RecordProposal{
        authoredRecord(.{ .functional_requirement = .{ .text = refused.value } }, refused),
        authoredRecord(.{ .edge_case = .{ .condition = refused.value } }, refused),
    };
    const current = try sessionWithBatches(a, &fixture, &.{ &first_batch, &second_batch });
    const plan = try request.planFor(a, current);
    try std.testing.expectEqual(@as(?u32, 3), plan.unlinkable);
    const gap = (try request.begin(a, current, fixture.context)).blocked;
    try std.testing.expectEqual(.edge_case_without_criterion, gap.reason);
    try std.testing.expect(gap.valid() and gap.origin == null and gap.issue == null);
    // The gap names the edge case's own group and the claims it names.
    try std.testing.expectEqual(@as(usize, 1), gap.eligible_signals.len);
    try std.testing.expectEqual(fixture.context.references.records.signals[1].id.ordinal, gap.eligible_signals[0].signal_id.ordinal);
    try std.testing.expectEqualDeep(refused.provenance.claim_ids, gap.eligible_signals[0].claim_ids);
    try std.testing.expectError(error.InvalidScenarioLink, request.packet(a, current, fixture.context, 0));
    try std.testing.expectError(error.InvalidScenarioLink, links.resolve(a, plan, &.{}));
    // The retained diagnostic survives readback as the candidate's, and a gap that does not
    // pair its reason with exactly one signal, or that claims a model origin, does not.
    const diagnostic: Diagnostic = .{ .source_catalogue = gap };
    try std.testing.expectEqual(.candidate, diagnostic.attribution());
    try std.testing.expectEqualDeep(diagnostic, try diagnostic.copy(a));
    var none = gap;
    none.eligible_signals = &.{};
    var attributed = gap;
    attributed.origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    for ([_]@import("domain/specification_source_binding.zig").Rejection{ none, attributed }) |bad| {
        try std.testing.expect(!bad.valid());
        try std.testing.expectError(error.InvalidJsonDocument, (Diagnostic{ .source_catalogue = bad }).copy(a));
    }
}

test "an edge case among three criteria of an unrelated domain prints the Then of the one the model names" {
    const sessions = @import("domain/specification_session.zig");
    const links = @import("domain/scenario_link.zig");
    const request = @import("domain/scenario_link_request.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Book a room for a guest.");
    defer fixture.deinit();
    const booked = try fixture.proposal("The room is booked.");
    const waitlisted = try fixture.proposal("The guest joins the waiting list.");
    const refused = try fixture.proposal("The booking is declined.");
    const batch = [_]spec.Model.RecordProposal{
        authoredRecord(.{ .functional_requirement = .{ .text = booked.value } }, booked),
        authoredRecord(.{ .functional_requirement = .{ .text = waitlisted.value } }, booked),
        authoredRecord(.{ .acceptance_criterion = .{ .given = booked.value, .when = booked.value, .then = booked.value } }, booked),
        authoredRecord(.{ .acceptance_criterion = .{ .given = booked.value, .when = booked.value, .then = waitlisted.value } }, booked),
        authoredRecord(.{ .acceptance_criterion = .{ .given = booked.value, .when = booked.value, .then = refused.value } }, booked),
        authoredRecord(.{ .edge_case = .{ .condition = booked.value } }, booked),
    };
    const current = try sessionWithBatches(a, &fixture, &.{&batch});
    const plan = try request.planFor(a, current);
    try std.testing.expectEqualDeep(&[_]u32{ 2, 3, 4 }, plan.pending[0].candidates);
    const offered = try request.packet(a, current, fixture.context, 0);
    defer packets.release(offered);
    try std.testing.expectEqualSlices(i64, &.{ 1, 2, 3 }, offered.integerChoices()[0].allowed);
    // Any offered id names its own criterion: the id is a place among the candidates.
    for ([_]struct { answer: []const u8, criterion: u32 }{
        .{ .answer = "{\"criterion\":1}", .criterion = 2 },
        .{ .answer = "{\"criterion\":2}", .criterion = 3 },
        .{ .answer = "{\"criterion\":3}", .criterion = 4 },
    }) |case| try std.testing.expectEqualDeep(links.Link{ .edge_case = 5, .criterion = case.criterion }, try request.admit(a, current, fixture.context, 0, offered, case.answer));
    const choice = try request.admit(a, current, fixture.context, 0, offered, "{\"criterion\":3}");
    const assigned = try sessions.assemble(a, text.validator, fixture.context, current, try links.resolve(a, plan, &.{choice}));
    const projection = @import("domain/specification_projection.zig");
    const rendered = try @import("domain/specification_markdown.zig").render(a, try projection.project(a, fixture.context, test_directory, assigned.content));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "- **EXPECTED OUTCOME** The booking is declined.") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "- **EXPECTED OUTCOME** The guest joins the waiting list.") == null);
}
