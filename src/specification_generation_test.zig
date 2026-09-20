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
            const current = try sessions.initialize(.{ .bytes = "selected" }, context);
            const packet = try sessions.packet(std.testing.allocator, current, context);
            defer packets.release(packet);
            const repair = @import("domain/specification_repair.zig");
            var bad = proposal;
            bad.provenance.claim_ids = &.{.{ .ordinal = 999 }};
            const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = bad, .description = proposal, .primary_goal = proposal } } } };
            const rejection = (try validate_unit.execute(a, current, context, candidate)).invalid;
            const authorization = try repair.authorize(a, current, context, candidate, rejection);
            const repair_packet = try repair.packet(std.testing.allocator, current, context, authorization);
            defer packets.release(repair_packet);
            for ([_]*const packets.Packet{ packet, repair_packet }) |request| {
                const body = try std.json.parseFromSlice(std.json.Value, a, request.body(), .{});
                const input = if (request.purpose() == .atomic_repair) body.value.object.get("input").? else body.value;
                var offered = false;
                for (input.object.get("claims").?.array.items) |claim| {
                    const ordinal = claim.object.get("id").?.object.get("ordinal").?.integer;
                    if (ordinal == id.ordinal) offered = true;
                    try std.testing.expect(ordinal != 999);
                }
                try std.testing.expectEqual(eligible, offered);
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
            try std.testing.expect(!provenance.eligibleClaim(null));
            try std.testing.expectError(error.InvalidReferenceReconciliation, provenance.select(a, context, .{ .claim_ids = &.{missing}, .clarification_response_ids = &.{} }));
        }
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
        const current = try @import("domain/specification_session.zig").initialize(.{ .bytes = "selected" }, fixture.context);
        const good = try fixture.proposal(source);
        var bad = good;
        bad.value = .{ .normalized = .{ .segments = &.{.{ .literal = .{ .value = "Display \\\"a result\\\"." } }} } };
        const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const issue = rejected.issue.text_issue.?;
        try std.testing.expectEqual(.unbound_path, issue.reason);
        try std.testing.expectEqualStrings("\\", issue.path_match.?.lexeme);
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization);
        defer packets.release(packet);
        const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
        const rule = body.value.object.get("repair").?.object.get("rule").?.object;
        try std.testing.expectEqualStrings(issue.description(), rule.get("requirement").?.string);
        try std.testing.expectEqualDeep(issue, try json.decode(@import("domain/typed_text.zig").Issue, a, try std.json.Stringify.valueAlloc(a, rule.get("text_issue").?, .{})));
        const replacement: repair.Replacement = .{ .value = good.value };
        const merged = try repair.merge(a, current, fixture.context, candidate, authorization, try repair.parse(a, authorization, packet, try json.encodeSelected(repair.Replacement, a, replacement)), null);
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
    const items = try provenance.items(fixture.context);
    var exact_count: usize = 0;
    for (items.entries) |item| {
        if (item.claim.content != .preserved_token) continue;
        exact_count += 1;
        const token = item.claim.content.preserved_token;
        const value: spec.AttributedValue = .{ .value = .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } }, .provenance = .{ .claim_ids = &.{item.claim.id}, .citation_ids = item.claim.citation_ids, .clarification_response_ids = &.{} } };
        try std.testing.expectEqualStrings("Cafe\u{301}", (try projection.scalar(a, fixture.context, value)).bytes);
        var invalid = value;
        invalid.value.exact_copy.citation_id.ordinal = 999;
        try std.testing.expectError(error.InvalidSpecification, projection.scalar(a, fixture.context, invalid));
    }
    try std.testing.expectEqual(@as(usize, 1), exact_count);
    var passive_count: usize = 0;
    for (fixture.context.registry.records) |record| {
        if (!std.mem.eql(u8, record.value, "stories.md")) continue;
        passive_count += 1;
        var value = try fixture.value("unused");
        value.value = .{ .normalized = .{ .segments = &.{.{ .passive = .{ .passive_literal_id = record.id } }} } };
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
        var current = try sessions.initialize(.{ .bytes = "requested-feature" }, fixture.context);
        const first = current;
        const value = try fixture.proposal(source);
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, current));
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const packet = try sessions.packet(std.testing.allocator, current, fixture.context);
            defer @import("domain/model_input_packet.zig").release(packet);
            try @import("reference_model_input_test.zig").checkProjectedPacket(a, packet.body());
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "principles") == null);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
                .primary_user_story => .{ .primary_user_story = value },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
                .records => |kind| result: {
                    if (kind != .functional_requirement) break :result .{ .records = &.{} };
                    const records = try a.dupe(spec.Model.RecordProposal, &.{.{ .content = .{ .functional_requirement = .{ .text = value.value } }, .provenance = value.provenance }});
                    break :result .{ .records = records };
                },
            } };
            const checked = (try g.validate(a, text.validator, fixture.context, unit, response)).valid;
            current = try sessions.append(current, checked);
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

test "specification semantic support contributes scoped evidence to the shared gate" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A visitor sees a greeting.");
    defer fixture.deinit();
    const initial = try @import("domain/specification_authority.zig").project(a, .{ .bytes = "chosen" }, fixture.context.references, null, null);
    const ledger = try authority.build(a, initial);
    const findings = try a.alloc(support.Finding, ledger.requirements.len);
    const value = try fixture.value("A greeting is visible.");
    for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = .supported, .provenance = selection(value.provenance), .source_ids = &.{}, .detail = "The source leaves the required decision ambiguous." } };
    const bytes = try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings });
    const reviewed = try collectSupport(a, initial, fixture.context, bytes);
    for (reviewed.evidence) |proof| try std.testing.expectEqual(.model_assisted, proof.method);
    const current = try authority.build(a, reviewed);
    const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, current);
    const result = try authority.reconcile(a, current, observations);
    try std.testing.expect(try authority.validate(a, reviewed, observations, result));
    findings[0].value.decision = .ambiguous;
    findings[0].value.question = "Which deadline should apply? State the duration and starting event.";
    const gap = try collectSupport(a, initial, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings }));
    const gap_ledger = try authority.build(a, gap);
    const gap_observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, gap_ledger);
    try std.testing.expectEqual(.needs_user, (try authority.reconcile(a, gap_ledger, gap_observations)).continuation);
    findings[0].value.provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} };
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
        const record: spec.Model.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), fields), .provenance = value.provenance };
        const result = (try g.validate(a, text.validator, fixture.context, .{ .records = kind }, .{ .content = .{ .records = &.{record} } })).valid;
        try std.testing.expectEqual(kind, std.meta.activeTag(result.response.content.records[0].content));
        const wire = try @import("domain/model_candidate_json.zig").encode(g.ModelResponse, a, g.ModelResponse.from(.{ .content = .{ .records = &.{record} } }));
        try std.testing.expectEqualDeep(result.response, (try g.validate(a, text.validator, fixture.context, .{ .records = kind }, try g.parse(a, wire))).valid.response);
        _ = (try g.validate(a, text.validator, fixture.context, .{ .records = kind }, .{ .content = .{ .records = &.{} } })).valid;
        try std.testing.expectEqual(.duplicate_record, (try g.validate(a, text.validator, fixture.context, .{ .records = kind }, .{ .content = .{ .records = &.{ record, record } } })).invalid.rule);
    }
    const brief: g.Response = .{ .content = .{ .brief = .{ .title = value, .description = value, .primary_goal = value } } };
    _ = (try g.validate(a, text.validator, fixture.context, .brief, brief)).valid;
    try std.testing.expectEqual(.unit_kind, (try g.validate(a, text.validator, fixture.context, .primary_user_story, brief)).invalid.rule);
    const question = (try g.validate(a, text.validator, fixture.context, .primary_user_story, .{ .clarification = .{ .reason = .ambiguous, .question = try fixture.proposal("Which renewal limit applies?") } })).valid;
    try std.testing.expectEqual(.clarification, std.meta.activeTag(question.response));
}

test "specification provenance rejects foreign missing duplicate stale and unaccepted support" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A customer books a visit.");
    defer fixture.deinit();
    const good = try fixture.value("A customer books a visit.");
    _ = try provenance.checkAttributed(.canonical, a, text.validator, fixture.context, good);
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
        if (provenance.checkAttributed(.canonical, a, text.validator, fixture.context, changed)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.InvalidSpecification, error.InvalidReferenceReconciliation => {},
            else => return err,
        }
    }
    var stale = fixture.context;
    stale.inputs.corpus.state_id.bytes = "different-reference-state";
    try std.testing.expectError(error.InvalidSpecification, provenance.checkAttributed(.canonical, a, text.validator, stale, good));
    try std.testing.expectError(error.UnboundPathReference, provenance.checkAttributed(.canonical, a, text.validator, fixture.context, try fixture.value("Write src/main.zig.")));
}

test "exact specification values retain token references and never accept replacement display bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Show `Hello, World!`.", "Show `Booking confirmed!`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        for (all.entries) |item| if (item.claim.content == .preserved_token) {
            const token = item.claim.content.preserved_token;
            const ids = try a.dupe(references.r.ClaimId, &.{item.claim.id});
            const proposed: spec.AttributedValue = .{ .value = .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } }, .provenance = .{ .claim_ids = ids, .citation_ids = item.claim.citation_ids, .clarification_response_ids = &.{} } };
            const accepted = try provenance.checkAttributed(.canonical, a, text.validator, fixture.context, proposed);
            try std.testing.expectEqualDeep(proposed, accepted);
            const model: spec.Model.AttributedValue = .{ .value = proposed.value, .provenance = selection(proposed.provenance) };
            try std.testing.expectEqualDeep(accepted, try provenance.checkAttributed(.model, a, text.validator, fixture.context, model));
            var wrong_model = model;
            wrong_model.value.exact_copy.citation_id.ordinal = 999;
            try std.testing.expectError(error.InvalidSpecification, provenance.checkAttributed(.model, a, text.validator, fixture.context, wrong_model));
            var wrong = proposed;
            wrong.value.exact_copy.token_id.ordinal = 999;
            try std.testing.expectError(error.InvalidSpecification, provenance.checkAttributed(.canonical, a, text.validator, fixture.context, wrong));
        };
    }
}

test "unit parsing rejects model authority and ID ledger allocation remains engine owned" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Users view a greeting.");
    defer fixture.deinit();
    const value = try fixture.value("Users view a greeting.");
    const response: g.Response = .{ .content = .{ .primary_user_story = try fixture.proposal("Users view a greeting.") } };
    const bytes = try @import("domain/model_candidate_json.zig").encode(g.ModelResponse, a, g.ModelResponse.from(response));
    _ = try g.parse(a, bytes);
    for ([_][]const u8{ "id", "completed", "path", "approved", "open_questions" }) |key| {
        const forged = try std.fmt.allocPrint(a, "{{\"{s}\":true,{s}", .{ key, bytes[1..] });
        try std.testing.expectError(error.InvalidSpecificationUnit, g.parse(a, forged));
    }
    const record: spec.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .provenance = value.provenance };
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
        var ids: evidence.IdSource = .{};
        const inputs = try evidence.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "stories.md", bytes));
        const passive = try text.prepare(a, inputs);
        errdefer passive.deinit();
        const candidates = try tokens.candidates(a, inputs);
        const raw = try a.alloc(@import("domain/reference_extraction.zig").RawResult, inputs.chunks.entries.len);
        for (inputs.chunks.entries, raw) |chunk, *entry| {
            var choices: std.ArrayList(@import("domain/structured_tokens.zig").Classification) = .empty;
            for (candidates.entries) |candidate| if (candidate.fact.scope.chunk_id.eql(chunk.id)) try choices.append(a, if (kind) |selected| .{ .preserve = .{ .token_candidate_id = candidate.id, .kind = selected } } else .{ .irrelevant = candidate.id });
            var reply = try tokens.wire(a, if (has_claims) try extraction.reply(a, chunk, claim_text) else extraction.no_claim, choices.items);
            if (has_claims and model_claim_count != 1) {
                const Response = @import("domain/reference_extraction_parser.zig").Response;
                const json = @import("domain/model_candidate_json.zig");
                var response = try json.decode(Response, a, reply);
                const claims = try a.alloc(@import("domain/reference_extraction.zig").Proposal, model_claim_count);
                @memset(claims, response.claims.claims[0]);
                response.claims.claims = claims;
                reply = try json.encode(Response, a, response);
            }
            entry.* = .{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = reply } };
        }
        const parsed = try @import("domain/reference_extraction_parser.zig").parse(a, .{ .entries = raw });
        const extracted_text = try text.check(a, inputs, parsed);
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
        return .{ .value = canonical.value, .provenance = selection(canonical.provenance) };
    }
    fn value(self: *const Fixture, bytes: []const u8) !spec.AttributedValue {
        const claim = self.context.references.records.assignments.checked.prior.prior.input.items[0].claim;
        const segments = try self.allocator.dupe(@import("domain/typed_text.zig").BusinessSegment, &.{.{ .literal = .{ .value = bytes } }});
        const claims = try self.allocator.dupe(references.r.ClaimId, &.{claim.id});
        return .{ .value = .{ .normalized = .{ .segments = segments } }, .provenance = .{ .claim_ids = claims, .citation_ids = claim.citation_ids, .clarification_response_ids = &.{} } };
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
        const current = try sessions.initialize(.{ .bytes = "selected" }, fixture.context);
        const good = try fixture.proposal(source);
        var bad = good;
        bad.provenance.claim_ids = &.{.{ .ordinal = 999 }};
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, candidate, rejection);
        try std.testing.expect(authorization.target.provenance == .description);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization);
        defer packets.release(packet);
        try @import("reference_model_input_test.zig").checkProjectedPacket(a, packet.body());
        const replacement: repair.Replacement = .{ .provenance = good.provenance };
        const wire = try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement);
        const parsed = try repair.parse(a, authorization, packet, wire);
        const merged = try repair.merge(a, current, fixture.context, candidate, authorization, parsed, null);
        try std.testing.expectEqual(@as(u64, 2), merged.revision);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.title);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.primary_goal);
        try std.testing.expectEqualDeep(bad, candidate.response.content.brief.description);
        _ = (try g.validate(a, text.validator, fixture.context, .brief, merged.response)).valid;
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, current, fixture.context, merged, rejection));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, current, fixture.context, merged, authorization, parsed, null));
        var changed = candidate;
        changed.response.content.brief.description = good;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, current, fixture.context, changed, authorization, parsed, null));
        var foreign = current;
        foreign.feature.bytes = "another-feature";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, foreign, fixture.context, candidate, authorization, parsed, null));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, foreign, fixture.context, authorization));
        var wrong_id = authorization;
        wrong_id.id.bytes = "foreign-repair";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.parse(a, wrong_id, packet, try @import("domain/model_candidate_json.zig").encodeSelected(repair.Replacement, a, replacement)));
        const with_target = try std.fmt.allocPrint(a, "{{\"target\":\"title\",{s}", .{wire[1..]});
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, with_target));
        const with_sibling = try std.fmt.allocPrint(a, "{{\"record\":{{}},{s}", .{wire[1..]});
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorization, packet, with_sibling));
        const still_invalid = try repair.merge(a, current, fixture.context, candidate, authorization, .{ .provenance = bad.provenance }, null);
        try std.testing.expectEqual(.provenance, (try g.validate(a, text.validator, fixture.context, .brief, still_invalid.response)).invalid.rule);
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
    var current = try sessions.initialize(.{ .bytes = "selected" }, fixture.context);
    const value = try fixture.proposal("Borrower requests renewal.");
    inline for (.{ spec.Kind.acceptance_criterion, spec.Kind.business_rule }) |kind| {
        current.completed = 3 + @intFromEnum(kind);
        const record: spec.Model.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, value.value)), .provenance = value.provenance };
        const proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ record, record } } } };
        const rejection = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        const authorization = try repair.authorize(a, current, fixture.context, proposed, rejection);
        try std.testing.expectEqual(@as(usize, 1), authorization.target.record);
        const merged = try repair.merge(a, current, fixture.context, proposed, authorization, null, null);
        try std.testing.expectEqual(@as(usize, 1), merged.response.content.records.len);
        try std.testing.expectEqualDeep(record, merged.response.content.records[0]);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
        _ = (try g.validate(a, text.validator, fixture.context, .{ .records = kind }, merged.response)).valid;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, current, fixture.context, proposed, authorization, .{ .provenance = value.provenance }, null));
        var bad_sibling = record;
        bad_sibling.provenance.claim_ids = &.{.{ .ordinal = 900 }};
        const with_sibling: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ record, record, bad_sibling } } } };
        const stable = try with_sibling.origins.stableTarget(.{ .provenance = .{ .record = 2 } }, 3);
        const remove = try repair.authorize(a, current, fixture.context, with_sibling, (try validate_unit.execute(a, current, fixture.context, with_sibling)).invalid);
        const shifted = try repair.merge(a, current, fixture.context, with_sibling, remove, null, null);
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
    for ([_][]const u8{ "Display `Hello, World!`.", "Display `Loan renewed!`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const value = try fixture.value("The requested message is displayed.");
        const brief: g.Brief = .{ .title = value, .description = value, .primary_goal = value };
        var content: spec.IdentifiedContent = .{ .display_name = value, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = &.{} };
        try std.testing.expectError(error.InvalidSpecificationCoverage, coverage.validate(a, fixture.context.references, brief, content));
        const all = try provenance.items(fixture.context);
        const item = all.entries[all.entries.len - 1];
        const token = item.claim.content.preserved_token;
        const record: spec.IdentifiedRecord = .{ .id = .{ .kind = .user_visible_outcome, .ordinal = 1 }, .proposal = .{ .content = .{ .user_visible_outcome = .{ .text = .{ .exact_copy = .{ .token_id = token.value.id, .citation_id = token.citation_id } } } }, .provenance = .{ .claim_ids = &.{item.claim.id}, .citation_ids = item.claim.citation_ids, .clarification_response_ids = &.{} } } };
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
            if (mode & 1 != 0 or mode == 4) try records.append(a, .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .proposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .provenance = value.provenance } });
            if (mode & 2 != 0 or mode == 4) try records.append(a, .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .proposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .provenance = value.provenance } });
            const content: spec.IdentifiedContent = .{ .display_name = value, .primary_user_story = value, .entities = .{ .disposition = .not_applicable, .basis = value }, .records = records.items };
            const inputs = try project.project(a, .{ .bytes = "chosen" }, fixture.context.references, content, .{ .title = value, .description = value, .primary_goal = value });
            const ledger = try authority.build(a, inputs);
            const findings = try a.alloc(support.Finding, ledger.requirements.len);
            for (ledger.requirements, findings, 0..) |requirement, *finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{
                .decision = if (mode == 4 and requirement.seed.id.slot == .scenario_coverage) .unsupported else .supported,
                .question = if (mode == 4 and requirement.seed.id.slot == .scenario_coverage) "What observable result establishes success for this scenario?" else null,
                .provenance = selection(value.provenance),
                .source_ids = &.{},
                .detail = "A required scenario is not established by the source.",
            } };
            const reviewed = try collectSupport(a, inputs, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, .{ .entries = findings }));
            const checked = try authority.build(a, reviewed);
            const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, checked);
            const result = try authority.reconcile(a, checked, observations);
            try std.testing.expectEqual(@as(@TypeOf(result.continuation), if (mode == 3) .all_resolved else if (mode == 4) .needs_user else .invalid), result.continuation);
            try std.testing.expectEqual(mode == 3, try authority.validate(a, reviewed, observations, result));
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
    const current = try sessions.initialize(.{ .bytes = "selected" }, fixture.context);
    const good = try fixture.proposal("A renewal is confirmed.");
    var bad = good;
    bad.provenance.claim_ids = &.{.{ .ordinal = 999 }};
    const candidate: candidates.Candidate = .{ .origins = .{ .initial = initial }, .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = bad } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    try std.testing.expectEqual(.provenance, rejected.issue.rule);
    try std.testing.expectEqual(.InvalidReferenceReconciliation, rejected.issue.native_error.?);
    try std.testing.expectEqualDeep(initial, rejected.origin.?);
    try std.testing.expectEqualDeep(bad.provenance, rejected.issue.observed.?.provenance);
    const authorization = try repair.authorize(a, current, fixture.context, candidate, rejected);
    const merged = try repair.merge(a, current, fixture.context, candidate, authorization, .{ .provenance = good.provenance }, correction);
    const sibling = (try validate_unit.execute(a, current, fixture.context, merged)).invalid;
    try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, merged)).?.validated.result);
    const sibling_authorization = try repair.authorize(a, current, fixture.context, merged, sibling);
    try std.testing.expect(!std.meta.eql(authorization.retry.?.key, sibling_authorization.retry.?.key));
    try std.testing.expectEqualDeep(authorization.retry.?.key.scope, sibling_authorization.retry.?.key.scope);
    try std.testing.expectEqual(authorization.retry.?.maximum_targets, sibling_authorization.retry.?.maximum_targets);
    try std.testing.expect(sibling.issue.field.target.provenance == .primary_goal);
    try std.testing.expectEqualDeep(initial, sibling.origin.?);
    try std.testing.expectEqualDeep(correction, merged.origins.at(.{ .target = .{ .provenance = .description } }).?);
    try std.testing.expectEqualDeep(initial, merged.origins.at(.{ .target = .{ .provenance = .title } }).?);
    const unchanged = try repair.merge(a, current, fixture.context, candidate, authorization, .{ .provenance = bad.provenance }, correction);
    const again = (try validate_unit.execute(a, current, fixture.context, unchanged)).invalid;
    try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, unchanged)).?.validated.result);
    const repeated = try repair.authorize(a, current, fixture.context, unchanged, again);
    try std.testing.expectEqualDeep(authorization.retry.?.key, repeated.retry.?.key);
    const changed_invalid = try repair.merge(a, current, fixture.context, candidate, authorization, .{ .provenance = .{ .claim_ids = &.{.{ .ordinal = 998 }}, .clarification_response_ids = &.{} } }, correction);
    try std.testing.expect(changed_invalid.last_repair.?.changed);
    try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, changed_invalid)).?.validated.result);
    try std.testing.expectEqualDeep(authorization.retry.?.key, (try repair.authorize(a, current, fixture.context, changed_invalid, (try validate_unit.execute(a, current, fixture.context, changed_invalid)).invalid)).retry.?.key);
    try std.testing.expectEqual(false, unchanged.last_repair.?.changed);
    try std.testing.expectEqual(true, merged.last_repair.?.changed);
    try std.testing.expectEqual(.provenance, again.issue.rule);
    try std.testing.expectEqualDeep(correction, again.origin.?);
    for (0..5) |scenario| {
        var foreign = rejected;
        switch (scenario) {
            0 => foreign.owner.specification_unit.feature_id.bytes = "another-feature",
            1 => foreign.issue.unit = .primary_user_story,
            2 => foreign.revision += 1,
            3 => foreign.origin = correction,
            4 => foreign.issue.observed = .{ .provenance = good.provenance },
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
    try std.testing.expectError(error.InvalidSpecification, g.validate(a, text.validator, stale, .{ .records = .business_rule }, .{ .content = .{ .records = &.{} } }));
}

test "retained specification rejection and authorization release allocation failures" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A visitor confirms a reservation.");
    defer fixture.deinit();
    const current = try @import("domain/specification_session.zig").initialize(.{ .bytes = "chosen" }, fixture.context);
    const good = try fixture.proposal("Reservation confirmation is visible.");
    var bad = good;
    bad.provenance.claim_ids = &.{};
    const candidate: @import("domain/specification_candidate.zig").Candidate = .{ .response = .{ .content = .{ .primary_user_story = bad } } };
    var story = current;
    story.completed = 1;
    try std.testing.checkAllAllocationFailures(std.testing.allocator, rejectionAllocationCase, .{ fixture.context, story, candidate, good });
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
    const merged = try repair.merge(a, current, context, candidate, authorization, .{ .provenance = good.provenance }, null);
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
        try std.testing.expectEqual(.provenance, (try g.revalidate(a, text.validator, fixture.context, .primary_user_story, corrupt)).invalid.rule);
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

test "record evidence repair preserves business fields and isolates subsequent text rejection" {
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
    const bad = try fixture.proposal("unbound/receipt.txt");
    inline for (.{ spec.Kind.acceptance_criterion, spec.Kind.business_rule }) |kind| {
        var current = try sessions.initialize(.{ .bytes = "chosen" }, fixture.context);
        current.completed = 3 + @intFromEnum(kind);
        var record: spec.Model.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, good.value)), .provenance = .{ .claim_ids = &.{.{ .ordinal = 900 }}, .clarification_response_ids = &.{} } };
        const field: candidates.ValueField = if (kind == .acceptance_criterion) .then else .text;
        if (kind == .acceptance_criterion) record.content.acceptance_criterion.then = bad.value else record.content.business_rule.text = bad.value;
        const proposed: repair.Candidate = .{ .origins = .{ .initial = initial }, .response = .{ .content = .{ .records = &.{record} } } };
        const rejected = (try validate_unit.execute(a, current, fixture.context, proposed)).invalid;
        try std.testing.expectEqualDeep(candidates.Target{ .provenance = .{ .record = 0 } }, rejected.issue.field.target);
        const authorized = try repair.authorize(a, current, fixture.context, proposed, rejected);
        const fixed = try repair.merge(a, current, fixture.context, proposed, authorized, .{ .provenance = good.provenance }, corrected);
        try std.testing.expectEqualDeep(record.content, fixed.response.content.records[0].content);
        const text_failure = (try validate_unit.execute(a, current, fixture.context, fixed)).invalid;
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, fixed)).?.validated.result);
        try std.testing.expectEqualDeep(candidates.Target{ .value = .{ .subject = .{ .record = 0 }, .field = field } }, text_failure.issue.field.target);
        try std.testing.expectEqualDeep(initial, text_failure.origin.?);
        const text_authorized = try repair.authorize(a, current, fixture.context, fixed, text_failure);
        const complete = try repair.merge(a, current, fixture.context, fixed, text_authorized, .{ .value = good.value }, corrected);
        _ = (try validate_unit.execute(a, current, fixture.context, complete)).valid;
        try std.testing.expectEqualDeep(good.provenance, complete.response.content.records[0].provenance);
        if (kind == .acceptance_criterion) {
            try std.testing.expectEqualDeep(record.content.acceptance_criterion.given, complete.response.content.records[0].content.acceptance_criterion.given);
            try std.testing.expectEqualDeep(record.content.acceptance_criterion.when, complete.response.content.records[0].content.acceptance_criterion.when);
        }
        // The selected response cannot carry valid business text as a side effect.
        const packet = try repair.packet(a, current, fixture.context, authorized);
        defer @import("domain/model_input_packet.zig").release(packet);
        const broad = try @import("domain/model_candidate_json.zig").encode(spec.Model.AttributedValue, a, good);
        try std.testing.expectError(error.InvalidJsonDocument, repair.parse(a, authorized, packet, broad));
        const unchanged = try repair.merge(a, current, fixture.context, fixed, text_authorized, .{ .value = bad.value }, corrected);
        try std.testing.expectEqualDeep(corrected, (try validate_unit.execute(a, current, fixture.context, unchanged)).invalid.origin.?);
        var wrong_kind = proposed;
        wrong_kind.response.content.records = &.{.{ .content = .{ .entity = .{ .name = good.value, .business_meaning = good.value, .relationships = &.{} } }, .provenance = good.provenance }};
        const kind_rejection = (try validate_unit.execute(a, current, fixture.context, wrong_kind)).invalid;
        try std.testing.expectEqual(.record_kind, kind_rejection.issue.rule);
        const kind_authorization = try repair.authorize(a, current, fixture.context, wrong_kind, kind_rejection);
        try std.testing.expect(kind_authorization.target == .record);
        var correct_record = record;
        correct_record.provenance = good.provenance;
        correct_record.content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, good.value));
        const corrected_kind = try repair.merge(a, current, fixture.context, wrong_kind, kind_authorization, .{ .record = correct_record }, corrected);
        _ = (try validate_unit.execute(a, current, fixture.context, corrected_kind)).valid;
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, corrected_kind)).?.validated.result);
        var changed_record = record;
        changed_record.provenance = good.provenance;
        const incomplete_kind = try repair.merge(a, current, fixture.context, wrong_kind, kind_authorization, .{ .record = changed_record }, corrected);
        const incomplete_rejection = (try validate_unit.execute(a, current, fixture.context, incomplete_kind)).invalid;
        try std.testing.expectEqual(.recurring, (try repair.retryValidation(a, text.validator, current, fixture.context, incomplete_kind)).?.validated.result);
        const repeat_kind = try repair.authorize(a, current, fixture.context, incomplete_kind, incomplete_rejection);
        try std.testing.expectEqualDeep(kind_authorization.retry.?.key, repeat_kind.retry.?.key);
        try std.testing.expectEqual(kind_authorization.retry.?.maximum_targets, repeat_kind.retry.?.maximum_targets);
        try std.testing.expectEqual(.record, std.meta.activeTag(repeat_kind.target));
        // Entity's two initial fields do not grow the target budget when the
        // required acceptance criterion has three fields. It remains one record.
        const final_kind = try repair.merge(a, current, fixture.context, incomplete_kind, repeat_kind, .{ .record = correct_record }, corrected);
        try std.testing.expect((try validate_unit.execute(a, current, fixture.context, final_kind)) == .valid);
        try std.testing.expectEqual(.resolved, (try repair.retryValidation(a, text.validator, current, fixture.context, final_kind)).?.validated.result);
    }
}

test "coverage repair restores exact references without changing business bytes or sibling units" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_coverage_repair.zig");
    const check = @import("actions/specification/validate_specification_coverage.zig").Action{ .validator = text.validator };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `Hello, World!`.", "Display `Loan renewed!`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const all = try provenance.items(fixture.context);
        const claim = all.entries[all.entries.len - 1].claim;
        const token = claim.content.preserved_token;
        const good = try fixture.proposal("The requested outcome is observable.");
        const raw = token.value.raw_value.bytes;
        const normalized: spec.BusinessValue = .{ .normalized = .{ .segments = &.{ .{ .literal = .{ .value = raw[0..3] } }, .{ .literal = .{ .value = raw[3..] } } } } };
        const record: spec.Model.RecordProposal = .{ .content = .{ .user_visible_outcome = .{ .text = normalized } }, .provenance = .{ .claim_ids = &.{claim.id}, .clarification_response_ids = &.{} } };
        var current = try sessions.initialize(.{ .bytes = "chosen" }, fixture.context);
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = good, .description = good, .primary_goal = good } },
                .primary_user_story => .{ .primary_user_story = good },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
                .records => |kind| .{ .records = if (kind == .user_visible_outcome) &.{record} else &.{} },
            } };
            current = try sessions.append(current, (try g.validate(a, text.validator, fixture.context, unit, response)).valid);
        }
        const identified = try sessions.assemble(a, text.validator, fixture.context, current);
        const rejection = (try check.execute(a, current, fixture.context, identified.content)).invalid;
        try std.testing.expect(rejection.issue == .missing_exact_copy);
        const authorization = (try repair.authorize(a, current, fixture.context, identified.content, rejection)).authorized;
        var stale_context = fixture.context;
        const names = try a.dupe(@import("domain/path_token_grammar.zig").ReferenceName, stale_context.registry.grammar.reference_names);
        names[0].basename = "changed.md";
        stale_context.registry.grammar.reference_names = names;
        try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.authorize(a, current, stale_context, identified.content, rejection));
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, text.validator, current, stale_context, identified.content, authorization));
        stale_context = fixture.context;
        try std.testing.expect(stale_context.references.records.assignments.checked.prior.prior.input.progress.summary_count > 0);
        stale_context.references.records.assignments.checked.prior.prior.input.progress.latest = null;
        try std.testing.expectError(error.InvalidReferenceReconciliation, repair.authorize(a, current, stale_context, identified.content, rejection));
        try std.testing.expectError(error.InvalidReferenceReconciliation, repair.merge(a, text.validator, current, stale_context, identified.content, authorization));
        const fixed = try repair.merge(a, text.validator, current, fixture.context, identified.content, authorization);
        for (current.units, fixed.units, 0..) |before, after, index| if (index != authorization.target.unit) try std.testing.expectEqualDeep(before, after);
        const rebuilt = try sessions.assemble(a, text.validator, fixture.context, fixed);
        _ = (try check.execute(a, fixed, fixture.context, rebuilt.content)).valid;
        try std.testing.expectEqual(.resolved, (try repair.coverageValidation(a, fixed, fixture.context, rebuilt.content)).?.validated.result);
        try std.testing.expectEqualDeep(token.value.id, fixed.pending_coverage_repair.?.target.token_id);
        try std.testing.expectEqualDeep(token.citation_id, fixed.pending_coverage_repair.?.target.citation_id);
        try std.testing.expectEqualDeep(identified.ledger, rebuilt.ledger);
        const before = try @import("domain/specification_projection.zig").scalar(a, fixture.context, .{ .value = identified.content.records[0].proposal.content.user_visible_outcome.text, .provenance = identified.content.records[0].proposal.provenance });
        const after = try @import("domain/specification_projection.zig").scalar(a, fixture.context, .{ .value = rebuilt.content.records[0].proposal.content.user_visible_outcome.text, .provenance = rebuilt.content.records[0].proposal.provenance });
        try std.testing.expectEqualStrings(before.bytes, after.bytes);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, text.validator, fixed, fixture.context, rebuilt.content, authorization));
        try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.authorize(a, fixed, fixture.context, rebuilt.content, rejection));
        const index = 3 + @intFromEnum(spec.Kind.user_visible_outcome);
        var unsupported = current;
        unsupported.units[index] = .{ .unit = .{ .records = .user_visible_outcome }, .response = .{ .content = .{ .records = &.{} } } };
        const omitted = try sessions.assemble(a, text.validator, fixture.context, unsupported);
        const gap = (try check.execute(a, unsupported, fixture.context, omitted.content)).invalid;
        try std.testing.expect((try repair.authorize(a, unsupported, fixture.context, omitted.content, gap)) == .blocked);
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
        for ([_]bool{ false, true }) |record| for ([_]bool{ false, true }) |value_repair| {
            var current = try sessions.initialize(.{ .bytes = "selected" }, fixture.context);
            var bad = good;
            if (value_repair) bad.value = .{ .exact_copy = .{ .token_id = .{ .ordinal = 999 }, .citation_id = .{ .ordinal = 999 } } } else bad.provenance.claim_ids = &.{};
            if (record) current.completed = 3 + @intFromEnum(spec.Kind.acceptance_criterion);
            const candidate: candidates.Candidate = .{ .response = .{ .content = if (record) .{ .records = &.{.{ .content = .{ .acceptance_criterion = .{ .given = bad.value, .when = good.value, .then = good.value } }, .provenance = bad.provenance }} } else .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
            const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
            const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
            const packet = try repair.packet(a, current, fixture.context, auth);
            defer packets.release(packet);
            const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
            const input = body.value.object.get("input").?.object;
            // Initial brief has no accepted brief to substitute for the rejected text.
            try std.testing.expect(input.get("brief").? == .null);
            const read = try json.decode(candidates.ReadContext, a, try std.json.Stringify.valueAlloc(a, input.get("candidate").?, .{}));
            const retained_selection = if (record) read.record.provenance else read.attributed.provenance;
            try std.testing.expectEqualDeep(bad.provenance, retained_selection);
            if (record) {
                try std.testing.expectEqualDeep(good.value, read.record.content.acceptance_criterion.when);
                try std.testing.expectEqualDeep(good.value, read.record.content.acceptance_criterion.then);
                try std.testing.expectEqualDeep(bad.value, read.record.content.acceptance_criterion.given);
            } else try std.testing.expectEqualDeep(bad.value, read.attributed.value);
            if (value_repair) {
                const choices = body.value.object.get("repair").?.object.get("rule").?.object.get("value_choices").?.object;
                try std.testing.expect(choices.get("normalized").?.bool);
                try std.testing.expectEqual(@as(usize, 0), choices.get("exact_copy").?.array.items.len);
            }
            const replacement: repair.Replacement = if (value_repair) .{ .value = good.value } else .{ .provenance = good.provenance };
            const merged = try repair.merge(a, current, fixture.context, candidate, auth, try repair.parse(a, auth, packet, try json.encodeSelected(repair.Replacement, a, replacement)), null);
            _ = (try validate_unit.execute(a, current, fixture.context, merged)).valid;
            const unchanged = try repair.merge(a, current, fixture.context, candidate, auth, auth.operation.replace, null);
            try std.testing.expect((try validate_unit.execute(a, current, fixture.context, unchanged)) == .invalid);
        };
    }
    var fixture = try Fixture.init(a, "Display `Renewal accepted!`.");
    defer fixture.deinit();
    const current = try sessions.initialize(.{ .bytes = "selected" }, fixture.context);
    const all = try provenance.items(fixture.context);
    const selected = all.entries[all.entries.len - 1].claim;
    var value = try fixture.proposal("Renewal is confirmed.");
    value.provenance.claim_ids = &.{selected.id};
    value.value = .{ .exact_copy = .{ .token_id = .{ .ordinal = 999 }, .citation_id = .{ .ordinal = 999 } } };
    const candidate: candidates.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = value, .description = value, .primary_goal = value } } } };
    const rejected = (try validate_unit.execute(a, current, fixture.context, candidate)).invalid;
    const auth = try repair.authorize(a, current, fixture.context, candidate, rejected);
    const choices = auth.rule.value_choices.?;
    try std.testing.expect(choices.normalized);
    try std.testing.expectEqualDeep(&[_]@FieldType(spec.BusinessValue, "exact_copy"){.{ .token_id = selected.content.preserved_token.value.id, .citation_id = selected.content.preserved_token.citation_id }}, choices.exact_copy);
    const packet = try repair.packet(a, current, fixture.context, auth);
    defer packets.release(packet);
    const body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    try std.testing.expectEqual(@as(usize, 1), body.value.object.get("repair").?.object.get("rule").?.object.get("value_choices").?.object.get("exact_copy").?.array.items.len);
    const merged = try repair.merge(a, current, fixture.context, candidate, auth, .{ .value = .{ .exact_copy = choices.exact_copy[0] } }, null);
    try std.testing.expectEqualDeep(value.provenance, merged.response.content.brief.title.provenance);
    try std.testing.expectEqualDeep(value, merged.response.content.brief.description);
    // One corrected value is not acceptance of its still-invalid siblings.
    try std.testing.expectEqual(.exact_copy, (try validate_unit.execute(a, current, fixture.context, merged)).invalid.issue.rule);
}

test "source-only extraction omissions remain candidate defects without clarification or invented claim authority" {
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    const gaps = @import("domain/required_authority_clarifications.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "On startup display `Hello, World!` and the current UTC date and time.", "After renewal display `Loan renewed!` and the new return deadline." }) |source| {
        var fixture = try Fixture.initExtraction(a, source, null, false);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const packet = try support.packet(a, inputs, fixture.context);
        defer @import("domain/model_input_packet.zig").release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        try std.testing.expectEqualStrings(source, body.get("sources").?.array.items[0].object.get("text").?.string);
        try std.testing.expectEqual(@as(usize, 0), body.get("claims").?.array.items.len);
        const extracted = body.get("extraction").?.array.items[0].object;
        try std.testing.expectEqualStrings("no_feature_claim", extracted.get("outcome").?.object.get("kind").?.string);
        try std.testing.expectEqualStrings("irrelevant", extracted.get("token_classifications").?.array.items[0].object.get("decision").?.object.get("kind").?.string);
        const base = try reviewFor(a, inputs);
        const findings = try a.dupe(support.Finding, base.entries);
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 14 }, .attempt = .{ .value = 1 } };
        for (findings) |*finding| finding.value = .{ .decision = .candidate_omission, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = "Extraction discarded the source-required behavior." };
        const admitted = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), origin)).accepted.inputs;
        const decision = try supportDecision(a, admitted);
        try std.testing.expectEqual(.invalid, decision.result.continuation);
        for (decision.result.entries) |entry| try std.testing.expect(entry.candidate_defect != null);
        try std.testing.expectError(error.InvalidRequiredAuthority, gaps.build(a, admitted, decision.observations, decision.result));
        try std.testing.expectEqualDeep(origin, admitted.review_origin.?);
        try std.testing.expectEqual(@as(usize, 0), admitted.candidates.len);
        // A source ID cannot manufacture the claim provenance required by a
        // positive verdict. Genuine authority gaps still produce user forms.
        for (findings) |*finding| finding.value.decision = .supported;
        try std.testing.expect((try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), origin)) == .rejected);
        for (findings) |*finding| {
            finding.value.decision = .unsupported;
            finding.value.question = "Which deadline should apply? State the duration and starting event.";
            finding.value.source_ids = &.{};
            finding.value.detail = "The source does not establish this requirement.";
        }
        const missing = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), origin)).accepted.inputs;
        const unresolved = try supportDecision(a, missing);
        try std.testing.expectEqual(.needs_user, unresolved.result.continuation);
        try std.testing.expectEqual(findings.len, (try gaps.build(a, missing, unresolved.observations, unresolved.result)).entries.len);
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
    const current = try sessions.initialize(.{ .bytes = "selected" }, fixture.context);
    const good = try fixture.proposal("The borrower sees a receipt.");
    var bad = good;
    bad.provenance.claim_ids = &.{};
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
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, current, context, candidate, auth, .{ .provenance = good.provenance }, null));
    context = fixture.context;
    try std.testing.expect(context.references.records.assignments.checked.prior.prior.input.progress.summary_count > 0);
    context.references.records.assignments.checked.prior.prior.input.progress.latest = null;
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.authorize(a, current, context, candidate, rejected));
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.packet(a, current, context, auth));
    try std.testing.expectError(error.InvalidReferenceReconciliation, repair.merge(a, current, context, candidate, auth, .{ .provenance = good.provenance }, null));
}

fn collectSupport(allocator: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: @import("domain/specification_provenance.zig").Context, bytes: []const u8) !@import("domain/required_authority.zig").Inputs {
    return switch (try @import("domain/specification_support.zig").Source.collect(allocator, inputs, context, bytes, null)) {
        .accepted => |accepted| accepted.inputs,
        .rejected => error.InvalidRequiredAuthority,
    };
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
    for ([_][]const u8{ "Display `Hello, World!` and the current UTC date and time.", "Display `Loan renewed!` and label the deadline `Return by`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const packet = try support.packet(a, inputs, fixture.context);
        defer @import("domain/model_input_packet.zig").release(packet);
        const selected = schema.select(packet.resultDefinition().?).?;
        const good = try reviewFor(a, inputs);
        const ledger = try @import("domain/required_authority.zig").build(a, inputs);
        const entity = for (ledger.requirements, 0..) |requirement, index| {
            if (requirement.seed.id.kind == .entity_applicability) break index;
        } else return error.MissingEntityRequirement;
        for (0..3) |scenario| {
            const findings = try a.dupe(support.Finding, if (scenario == 1) good.entries[0..1] else good.entries);
            if (scenario == 2) {
                findings[entity].value.decision = .not_applicable;
                findings[entity].value.detail = "No business data entity is needed.";
                findings[entity].value.provenance.claim_ids = &.{};
            }
            const corrected = try json.encode(support.Review, a, .{ .entries = findings });
            try @import("model_payload_schema_test.zig").checkDocument(selected.modelBytes(), .{ .bytes = corrected });
            const result = try support.collect(a, inputs, fixture.context, corrected, origin);
            if (scenario == 0) {
                try std.testing.expectEqualDeep(good.entries, result.accepted.candidate.review.entries);
                for (result.accepted.candidate.origins) |retained| try std.testing.expectEqualDeep(origin, retained.?);
                try support.validateStored(a, result.accepted.inputs, fixture.context.inputs);
            } else if (scenario == 1) {
                try std.testing.expectEqual(good.entries.len - 1, result.rejected.rejection.diagnostics.len);
                for (result.rejected.rejection.diagnostics) |issue| try std.testing.expectEqual(.missing_requirement, issue.issue);
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

test "review decisions preserve seven source gaps and reject forbidden applicability across requirement kinds" {
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "On startup display `Hello, World!` and the current UTC date and time.", "After renewal display `Loan renewed!` and the new return deadline." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const current = try completedFixture(&fixture, false);
        const content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, current)).content;
        for ([_]bool{ false, true }) |with_candidate| {
            const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, if (with_candidate) content else null, if (with_candidate) current.units[0].?.response.content.brief else null);
            const ledger = try authority.build(a, inputs);
            const good = try reviewFor(a, inputs);
            const findings = try a.dupe(support.Finding, good.entries);
            var gaps: usize = 0;
            for (ledger.requirements, findings) |requirement, *finding| {
                if (requirement.seed.id.kind != .feature_intent or requirement.seed.id.unit != .feature) continue;
                finding.value = .{ .decision = .unsupported, .question = "What behavior is required? State the triggering event and expected result.", .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "The source leaves this decision unspecified." };
                gaps += 1;
            }
            try std.testing.expectEqual(@as(usize, 7), gaps);
            const collected = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
            try std.testing.expectEqualDeep(findings, collected.candidate.review.entries);
            const resolved = try supportDecision(a, collected.inputs);
            try std.testing.expectEqual(.needs_user, resolved.result.continuation);
            const forms = try @import("domain/required_authority_clarifications.zig").build(a, collected.inputs, resolved.observations, resolved.result);
            try std.testing.expectEqual(gaps, forms.entries.len);
            try support.validateStored(a, collected.inputs, fixture.context.inputs);
            for (ledger.requirements, 0..) |requirement, index| {
                if (requirement.seed.id.kind == .entity_applicability) continue;
                // Includes feature fields, records, signals and preserved tokens.
                const forbidden = try a.dupe(support.Finding, good.entries);
                forbidden[index].value.decision = .not_applicable;
                const rejected = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = forbidden }), null)).rejected;
                try std.testing.expectEqual(.invalid_decision, rejected.rejection.selected().?.issue);
                try std.testing.expectEqualDeep(requirement.seed.id, rejected.rejection.selected().?.requirement.?);
                try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, rejected));
            }
            const old = "{\"entries\":[{\"requirement_ordinal\":1,\"value\":{\"finding\":\"unsupported\",\"disposition\":\"not_applicable\",\"provenance\":{\"claim_ids\":[],\"clarification_response_ids\":[]},\"source_ids\":[],\"detail\":\"No explicit field.\"}}]}";
            try std.testing.expectEqual(.invalid_json, (try support.collect(a, inputs, fixture.context, old, null)).rejected.rejection.selected().?.issue);
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
    for (0..4) |mode| {
        var candidate = content;
        if (mode == 3) candidate.entities.disposition = .required;
        const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, if (mode >= 2) candidate else null, if (mode >= 1) current.units[0].?.response.content.brief else null);
        const ledger = try authority.build(a, inputs);
        const entity = for (ledger.requirements, 0..) |requirement, index| {
            if (requirement.seed.id.kind == .entity_applicability) break index;
        } else return error.MissingEntityRequirement;
        const packet = try support.packet(a, inputs, fixture.context);
        defer packets.release(packet);
        try std.testing.expectEqualStrings(if (mode < 2) "review_applicability" else "review", packet.resultDefinition().?.bytes);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        for (body.get("requirements").?.array.items, 0..) |requirement, index| {
            const allowed = requirement.object.get("permitted_not_applicable");
            if (mode < 2 and index == entity) try std.testing.expectEqualStrings("no_business_data", allowed.?.string) else try std.testing.expect(allowed == null);
        }
        const good = try reviewFor(a, inputs);
        const findings = try a.dupe(support.Finding, good.entries);
        if (mode < 2) findings[entity].value.decision = .not_applicable;
        const accepted = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
        try std.testing.expectEqual(.supported, accepted.inputs.evidence[entity].finding);
        try std.testing.expectEqual(mode != 3, accepted.inputs.evidence[entity].resolution == .not_applicable);
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
            const rejected = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = missing.items }), null)).rejected;
            const authorization = try repair.authorize(a, inputs, fixture.context, rejected);
            const request = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, authorization);
            defer packets.release(request);
            try std.testing.expectEqualStrings(if (mode < 2 and index == entity) "applicability_finding" else "finding", request.resultDefinition().?.bytes);
            const request_body = (try std.json.parseFromSlice(std.json.Value, a, request.body(), .{})).value.object;
            const task_evidence = request_body.get("input").?.object.get("requirements").?.array.items[0].object.get("evidence").?.object;
            try std.testing.expect(task_evidence.get("eligible_claim_ids").?.array.items.len > 0);
            const replacement = try repair.parse(a, authorization, request, try json.encode(support.Value, a, findings[index].value));
            var empty_evidence = replacement;
            empty_evidence.finding.provenance.claim_ids = &.{};
            const invalid_evidence = (try repair.merge(a, inputs, fixture.context, rejected.candidate.?, authorization, empty_evidence, null)).rejected;
            try std.testing.expectEqual(.missing_claims, invalid_evidence.rejection.selected().?.evidence.?.issue);
            try std.testing.expectEqualDeep(missing.items, invalid_evidence.candidate.?.review.entries[0..missing.items.len]);
            const merged = (try repair.merge(a, inputs, fixture.context, rejected.candidate.?, authorization, replacement, null)).accepted;
            try std.testing.expectEqualDeep(accepted.inputs.evidence, merged.inputs.evidence);
            try std.testing.expectEqualDeep(missing.items, merged.candidate.review.entries[0..missing.items.len]);
            try support.validateStored(a, merged.inputs, fixture.context.inputs);
            // The merge still rejects a forbidden decision, even after decoding.
            if (mode >= 2 or index != entity) {
                var invalid = replacement;
                invalid.finding.decision = .not_applicable;
                const invalid_merge = (try repair.merge(a, inputs, fixture.context, rejected.candidate.?, authorization, invalid, null)).rejected;
                try std.testing.expectEqual(.invalid_decision, invalid_merge.rejection.selected().?.issue);
                try std.testing.expectEqualDeep(missing.items, invalid_merge.candidate.?.review.entries[0..missing.items.len]);
            }
            if (mode >= 2) {
                var changed = inputs;
                changed.specification.?.entities.disposition = if (mode == 2) .required else .not_applicable;
                try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, changed, fixture.context, rejected.candidate.?, authorization));
                try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, changed, fixture.context, rejected.candidate.?, authorization, replacement, null));
            }
        }
        findings[entity].value.decision = .unsupported;
        findings[entity].value.question = "Which deadline should apply? State the duration and starting event.";
        findings[entity].value.detail = "The source does not establish the entity basis.";
        const negative = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
        try std.testing.expectEqual(.unsupported, negative.evidence[entity].finding);
        try std.testing.expectEqual(mode == 2, negative.evidence[entity].resolution == .not_applicable);
        try std.testing.expectEqual(.needs_user, (try supportDecision(a, negative)).result.continuation);
        try support.validateStored(a, negative, fixture.context.inputs);
        if (mode >= 2) {
            findings[entity].value.decision = .not_applicable;
            try std.testing.expectEqual(.invalid_decision, (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected.rejection.selected().?.issue);
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
    for ([_][]const u8{ "On startup display `Hello, World!` and the current UTC date and time.", "After renewal display `Loan renewed!` and the new return deadline." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const ledger = try authority.build(a, inputs);
        const good = try reviewFor(a, inputs);
        const findings = try a.dupe(support.Finding, good.entries);
        var entity: ?usize = null;
        var token: ?usize = null;
        var negatives: usize = 0;
        for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
            if (requirement.seed.id.kind == .entity_applicability) {
                entity = index;
                finding.value.decision = .not_applicable;
                finding.value.provenance.claim_ids = &.{};
            } else if (requirement.seed.id.unit == .token) {
                token = index;
                finding.value.provenance = good.entries[0].value.provenance;
            } else {
                finding.value.decision = .unsupported;
                finding.value.question = "Which deadline should apply? State the duration and starting event.";
                finding.value.provenance.claim_ids = &.{};
                finding.value.detail = "The source does not settle this requirement.";
                negatives += 1;
            }
            finding.value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
        }
        try std.testing.expectEqual(@as(usize, 9), negatives);
        const first = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
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
        const unchanged = (try repair.merge(a, inputs, fixture.context, first.candidate.?, authorization, authorization.operation.replace, corrected)).rejected;
        try std.testing.expectEqual(.missing_claims, unchanged.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqual(@as(usize, 2), unchanged.rejection.diagnostics.len);
        try std.testing.expect(!unchanged.candidate.?.last_repair.?.changed);
        try std.testing.expectEqual(@as(u64, 2), unchanged.candidate.?.revision);
        try std.testing.expectEqualDeep(findings, unchanged.candidate.?.review.entries);
        const entity_replacement: repair.Replacement = .{ .selection = .{ .provenance = good.entries[entity.?].value.provenance, .source_ids = findings[entity.?].value.source_ids } };
        const second = (try repair.merge(a, inputs, fixture.context, first.candidate.?, authorization, entity_replacement, corrected)).rejected;
        try std.testing.expectEqual(.ineligible_claim, second.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqual(@as(usize, 1), second.rejection.diagnostics.len);
        try std.testing.expectEqual(token.? + 1, second.rejection.selected().?.ordinal.?);
        try std.testing.expectEqualDeep(original, second.rejection.selected().?.origin.?);
        try std.testing.expectEqualDeep(corrected, second.candidate.?.origins[entity.?].?);
        try std.testing.expectEqual(.not_applicable, second.candidate.?.review.entries[entity.?].value.decision);
        for (findings, second.candidate.?.review.entries, 0..) |before, after, index| if (index != entity.?) try std.testing.expectEqualDeep(before, after);
        const token_authorization = try repair.authorize(a, inputs, fixture.context, second);
        const token_rule = second.rejection.selected().?.evidence.?.rule;
        try std.testing.expect(token_rule.claims == .exact);
        try std.testing.expectEqualDeep(good.entries[token.?].value.provenance.claim_ids, token_rule.claims.exact);
        const token_replacement: repair.Replacement = .{ .selection = .{ .provenance = good.entries[token.?].value.provenance, .source_ids = findings[token.?].value.source_ids } };
        const completed = (try repair.merge(a, inputs, fixture.context, second.candidate.?, token_authorization, token_replacement, corrected)).accepted;
        try std.testing.expectEqual(@as(u64, 3), completed.candidate.revision);
        for (findings, completed.candidate.review.entries, 0..) |before, after, index| if (index != entity.? and index != token.?) try std.testing.expectEqualDeep(before, after);
        const resolved = try supportDecision(a, completed.inputs);
        try std.testing.expectEqual(.needs_user, resolved.result.continuation);
        const forms = try @import("domain/required_authority_clarifications.zig").build(a, completed.inputs, resolved.observations, resolved.result);
        try std.testing.expectEqual(negatives, forms.entries.len);
        try support.validateStored(a, completed.inputs, fixture.context.inputs);
        for ([_]usize{ entity.?, token.? }) |index| {
            var corrupted = completed.inputs;
            const entries = try a.dupe(authority.Evidence, corrupted.evidence);
            entries[index].review.?.provenance.claim_ids = findings[index].value.provenance.claim_ids;
            corrupted.evidence = entries;
            try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, corrupted, fixture.context.inputs));
        }
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, inputs, fixture.context, completed.candidate, token_authorization, token_replacement, corrected));
    }
}

test "review tasks preserve sufficient and incomplete source meaning without native verdicts" {
    const support = @import("domain/specification_support.zig").Source;
    const packets = @import("domain/model_input_packet.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cases = [_]struct { source: []const u8, gap: ?[]const u8 }{
        .{ .source = "On startup display a greeting and the current UTC date and time.", .gap = null },
        .{ .source = "On startup display a greeting and time; its timezone is undecided.", .gap = "Which timezone should be shown?" },
        .{ .source = "A borrower renews a loan for fourteen days and sees the new deadline.", .gap = null },
        .{ .source = "A borrower renews a loan; the renewal period is undecided.", .gap = "How long is the renewal period?" },
    };
    for (cases) |case| {
        var fixture = try Fixture.init(a, case.source);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const packet = try support.packet(a, inputs, fixture.context);
        defer packets.release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        try std.testing.expectEqualStrings(case.source, body.get("sources").?.array.items[0].object.get("text").?.string);
        const tasks = body.get("requirements").?.array.items;
        try std.testing.expectEqualStrings("Observable pass/fail outcomes.", tasks[4].object.get("task").?.string);
        try std.testing.expectEqualStrings("Source meaning preserved by signal 1.", tasks[7].object.get("task").?.string);
        const good = try reviewFor(a, inputs);
        const findings = try a.dupe(support.Finding, good.entries);
        if (case.gap) |detail| findings[4].value = .{ .decision = .ambiguous, .question = detail, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = detail };
        const accepted = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
        // Scripted decisions test admission/routing; prose is never classified natively.
        try std.testing.expectEqualDeep(findings, accepted.candidate.review.entries);
        try std.testing.expectEqual(@as(@FieldType(@import("domain/required_authority.zig").Result, "continuation"), if (case.gap != null) .needs_user else .all_resolved), (try supportDecision(a, accepted.inputs)).result.continuation);
        const decision = try supportDecision(a, accepted.inputs);
        const clarification = @import("domain/required_authority_clarifications.zig");
        if (case.gap) |detail| {
            const needs = try clarification.build(a, accepted.inputs, decision.observations, decision.result);
            try std.testing.expectEqual(@as(usize, 1), needs.entries.len);
            try std.testing.expect(std.mem.indexOf(u8, needs.entries[0].question, case.source) != null);
            try std.testing.expect(std.mem.startsWith(u8, needs.entries[0].question, case.gap.?));
            try std.testing.expectEqualStrings(detail, needs.entries[0].why_required);
        } else try std.testing.expectError(error.InvalidRequiredAuthority, clarification.build(a, accepted.inputs, decision.observations, decision.result));
        // Capturing applicable principles cannot manufacture a completed assessment.
        const captured = try @import("test_fixtures/principles.zig").registry(a, "Keep business intent intact.\n");
        const progress = try @import("domain/specification_review.zig").advance(a, .{ .source = .{ .accepted = accepted } }, captured);
        try std.testing.expectEqual(.complete, progress.outcome);
        try std.testing.expect(progress.progress.source.accepted.inputs.principle_assessment == null);
    }
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
    for ([_][]const u8{ "On startup display `Hello, World!`.", "After renewal display `Loan renewed!` and label the deadline `Return by`." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const allowed = try admission.sourceChoices(a, fixture.context.inputs);
        try std.testing.expectEqualDeep(&[_]SourceId{.{ .ordinal = 1 }}, allowed);
        try std.testing.expect(inputs.references.?.items.entries.len > allowed.len);
        const good = try reviewFor(a, inputs);
        // Claim 2 exists; source 2 does not. Their numerical overlap is not authority.
        const findings = try a.dupe(support.Finding, good.entries);
        findings[1].value.provenance.claim_ids = &.{.{ .ordinal = 2 }};
        findings[1].value.source_ids = &.{.{ .ordinal = 2 }};
        const rejected = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected;
        try std.testing.expectEqual(@as(usize, 1), rejected.rejection.diagnostics.len);
        const diagnostic = rejected.rejection.selected().?.evidence.?;
        try std.testing.expectEqual(.invalid_sources, diagnostic.issue);
        try std.testing.expectEqualDeep(allowed, diagnostic.rule.eligible_source_ids);
        // Reports copy the same rule; no observer reconstructs source membership.
        const report: @import("domain/candidate_validation_diagnostic.zig").Diagnostic = .{ .support = rejected.rejection };
        try std.testing.expectEqualDeep(report, try report.copy(a));
        const initial = try support.packet(a, inputs, fixture.context);
        defer packets.release(initial);
        const missing = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[1..] }), null)).rejected;
        const insertion = try repair.packet(a, inputs, fixture.context, missing.candidate.?, try repair.authorize(a, inputs, fixture.context, missing));
        defer packets.release(insertion);
        for ([_]*const packets.Packet{ initial, insertion }) |packet| {
            const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
            const input = if (packet == initial) body else body.get("input").?.object;
            const offered = input.get("evidence_rules").?.object.get("eligible_source_ids").?;
            try std.testing.expectEqualDeep(allowed, try json.decode([]const SourceId, a, try std.json.Stringify.valueAlloc(a, offered, .{})));
            for (input.get("requirements").?.array.items) |requirement| try std.testing.expect(!requirement.object.get("evidence").?.object.contains("eligible_source_ids"));
        }
        const authorization = try repair.authorize(a, inputs, fixture.context, rejected);
        const correction = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, authorization);
        defer packets.release(correction);
        const body = (try std.json.parseFromSlice(std.json.Value, a, correction.body(), .{})).value.object;
        const offered = body.get("repair").?.object.get("rule").?.object.get("evidence_rule").?.object.get("eligible_source_ids").?;
        try std.testing.expectEqualDeep(allowed, try json.decode([]const SourceId, a, try std.json.Stringify.valueAlloc(a, offered, .{})));
        try std.testing.expect(!body.get("input").?.object.contains("evidence_rules"));
        var stale = fixture.context;
        stale.inputs.corpus.state_id.bytes = "changed-corpus";
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, inputs, stale, rejected.candidate.?, authorization));
        const unchanged = (try repair.merge(a, inputs, fixture.context, rejected.candidate.?, authorization, authorization.operation.replace, null)).rejected;
        try std.testing.expectEqualDeep(rejected.candidate.?.review, unchanged.candidate.?.review);
        try std.testing.expectEqual(.invalid_sources, unchanged.rejection.selected().?.evidence.?.issue);
        const fixed = (try repair.merge(a, inputs, fixture.context, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = findings[1].value.provenance, .source_ids = allowed } }, null)).accepted;
        for (findings, fixed.candidate.review.entries, 0..) |before, after, index| {
            if (index != 1) try std.testing.expectEqualDeep(before, after) else {
                try std.testing.expectEqualDeep(before.value.provenance, after.value.provenance);
                try std.testing.expectEqual(before.value.decision, after.value.decision);
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

test "review evidence rules preserve minima exact sets and candidate provenance across subjects" {
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const authority = @import("domain/required_authority.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower receives `Loan renewed!`.");
    defer fixture.deinit();
    const current = try completedFixture(&fixture, false);
    const content = (try @import("domain/specification_session.zig").assemble(a, text.validator, fixture.context, current)).content;
    for (0..3) |mode| {
        const inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, if (mode == 2) content else null, if (mode > 0) current.units[0].?.response.content.brief else null);
        const ledger = try authority.build(a, inputs);
        const good = try reviewFor(a, inputs);
        const sources = &.{fixture.context.inputs.corpus.sources[0].id};
        const empty: spec.Selection = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} };
        for (ledger.requirements, good.entries) |requirement, finding| {
            const id = requirement.seed.id;
            const expected = try admission.requirements(a, inputs, fixture.context.inputs, id);
            try std.testing.expectEqualDeep(sources, expected.eligible_source_ids);
            try std.testing.expectEqualDeep(expected.rule(.supported), (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, empty, sources, "")).rejected.rule);
            try std.testing.expectEqual(.missing_claims, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, empty, sources, "")).rejected.issue);
            try std.testing.expectEqual(.missing_evidence, (try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, empty, &.{}, "The source requirement was lost.")).rejected.issue);
            const omission = try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, empty, sources, "The source requirement was lost.");
            if (expected.positive_claims == .exact_set) try std.testing.expectEqual(.wrong_claim_set, omission.rejected.issue) else try std.testing.expect(omission == .accepted);
            try std.testing.expect((try admission.admit(a, inputs, fixture.context.inputs, id, .unsupported, empty, &.{}, "The source does not settle this requirement.")) == .accepted);
            try std.testing.expectEqual(.invalid_sources, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, finding.value.provenance, &.{.{ .ordinal = 999 }}, "")).rejected.issue);
            try std.testing.expectEqual(.invalid_sources, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, finding.value.provenance, &.{ sources[0], sources[0] }, "")).rejected.issue);
            var invalid = finding.value.provenance;
            invalid.claim_ids = try std.mem.concat(a, references.r.ClaimId, &.{ invalid.claim_ids, invalid.claim_ids });
            try std.testing.expectEqual(.invalid_selection, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, invalid, &.{}, "")).rejected.issue);
            if (expected.supported_provenance != null) {
                invalid = .{ .claim_ids = expected.eligible_claim_ids, .clarification_response_ids = &.{} };
                try std.testing.expectEqual(.wrong_candidate_provenance, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, invalid, &.{}, "")).rejected.issue);
            }
        }
        const accepted = try collectSupport(a, inputs, fixture.context, try @import("domain/model_candidate_json.zig").encode(support.Review, a, good));
        try support.validateStored(a, accepted, fixture.context.inputs);
    }
}

fn reviewFor(a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs) !@import("domain/specification_support.zig").Source.Review {
    const support = @import("domain/specification_support.zig").Source;
    const ledger = try @import("domain/required_authority.zig").build(a, inputs);
    const findings = try a.alloc(support.Finding, ledger.requirements.len);
    for (ledger.requirements, findings, 0..) |requirement, *finding, index| {
        const choices = try @import("domain/specification_support_evidence.zig").choices(a, inputs.references.?, requirement.seed.id);
        const claims = switch (requirement.seed.id.unit) {
            .signal, .conflict, .token => choices,
            else => choices[0..@min(choices.len, 1)],
        };
        finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = .supported, .provenance = .{ .claim_ids = claims, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "" } };
    }
    return .{ .entries = findings };
}
fn supportDecision(a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs) !@import("domain/specification_coverage_repair.zig").Support {
    const authority = @import("domain/required_authority.zig");
    const ledger = try authority.build(a, inputs);
    const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, ledger);
    return .{ .inputs = inputs, .observations = observations, .result = try authority.reconcile(a, ledger, observations) };
}

fn omissionSupport(fixture: *const Fixture, location: @import("domain/source_omission.zig").Location) !@import("domain/source_omission.zig").Support {
    const support = @import("domain/specification_support.zig").Source;
    const a = fixture.allocator;
    const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
    const review = try reviewFor(a, inputs);
    const findings = try a.dupe(support.Finding, review.entries);
    for (findings) |*finding| {
        finding.value.decision = .candidate_omission;
        finding.value.detail = "Preserve the source-required deadline.";
        finding.value.source_ids = try a.dupe(@import("domain/reference_identity.zig").SourceId, &.{fixture.context.inputs.corpus.sources[0].id});
    }
    findings[0].value.loss = location;
    findings[0].value.provenance.claim_ids = switch (location) {
        .reconciliation_signal => |id| fixture.context.references.records.signals[id.ordinal - 1].value.claim_ids,
        // A discarded claim is a repair location, not eligible feature content.
        // The original source supplies the evidence for this omission finding.
        .reconciliation_disposition => &.{},
        else => &.{},
    };
    const origins = try a.alloc(?@import("domain/model_candidate_origin.zig").Origin, findings.len);
    @memset(origins, .{ .request = .{ .value = 14 }, .attempt = .{ .value = 1 } });
    const candidate: support.Candidate = .{ .review = .{ .entries = findings }, .origin = origins[0], .origins = origins };
    const admitted = try support.validate(a, inputs, fixture.context.inputs, candidate);
    if (admitted != .accepted) return error.InvalidOmissionFixture;
    const decision = try supportDecision(a, admitted.accepted.inputs);
    return .{ .review = admitted.accepted.candidate, .inputs = decision.inputs, .observations = decision.observations, .result = decision.result };
}

test "source omission repair preserves raw siblings and rebuilds canonical identities across chunks" {
    const repair = @import("domain/reference_extraction_repair.zig").Omission;
    const e = @import("domain/reference_extraction.zig");
    const packets = @import("domain/model_input_packet.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display the current UTC date and time.\n" ** 70, "Show the loan's new return deadline.\n" ** 70 }) |source| {
        var fixture = try Fixture.initClassified(a, source, null);
        defer fixture.deinit();
        const inputs = fixture.context.inputs;
        const chunk = inputs.chunks.entries[0];
        const facts: repair.Facts = .{ .extraction = .{ .inputs = inputs, .candidates = try tokens.candidates(a, inputs), .candidate = fixture.extracted_text }, .support = try omissionSupport(&fixture, .{ .extraction_claim = chunk.id }) };
        const auth = try repair.authorize(a, facts);
        try std.testing.expect(auth.operation == .insert and auth.target.claim == 1);
        const packet = try repair.packet(std.testing.allocator, facts, fixture.context.registry, auth);
        defer packets.release(packet);
        try std.testing.expectEqualStrings("claim", packet.resultDefinition().?.bytes);
        const proposal: e.Proposal = .{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Show the required date and time." } }} } }, .citations = &.{extraction.wholeChunk(chunk)} };
        const replacement = try repair.parse(a, auth, packet, try @import("domain/model_candidate_json.zig").encode(e.Proposal, a, proposal));
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 15 }, .attempt = .{ .value = 1 } };
        const merged = try repair.merge(a, text.validator, fixture.context.registry, fixture.context.current, facts, auth, replacement, origin);
        try std.testing.expectEqualDeep(fixture.extracted_text.entries[1..], merged.entries[1..]);
        try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].outcome.claims[0], merged.entries[0].outcome.claims[0]);
        try std.testing.expectEqualDeep(origin, merged.entries[0].outcome.claims[1].origin.?);
        try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].token_classifications, merged.entries[0].token_classifications);
        const rebuilt = try extraction.finishText(a, inputs, merged);
        try std.testing.expectEqual(fixture.extracted.ledger.claims.len + 1, rebuilt.ledger.claims.len);
        try std.testing.expectEqual(fixture.extracted.ledger.chunks[1].outcome.claims[0].ordinal + 1, rebuilt.ledger.chunks[1].outcome.claims[0].ordinal);
        const renewed_context: references.Context = .{ .inputs = inputs, .registry = fixture.context.registry, .current = fixture.context.current };
        const renewed_global = try references.summaries(a, try references.initialize(a, inputs, rebuilt, 2), renewed_context);
        var rebuilt_context = fixture.context;
        rebuilt_context.references = (try references.finish(a, renewed_global, try references.global(a, renewed_global), renewed_context)).valid;
        try checkSourceOmissionProgress(a, merged.omission_retry.?, facts.support, rebuilt_context);
        var stale = facts;
        stale.extraction.candidate = merged;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, text.validator, fixture.context.registry, fixture.context.current, stale, auth, replacement, origin));
        stale = facts;
        stale.extraction.candidate.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, stale, fixture.context.registry, auth));
        var bad = replacement;
        bad.claim.citations = &.{.{ .first = .{ .ordinal = 999 }, .last = .{ .ordinal = 999 } }};
        const invalid = try repair.merge(a, text.validator, fixture.context.registry, fixture.context.current, facts, auth, bad, origin);
        try std.testing.expectError(error.InvalidSourceCitation, extraction.finishText(a, inputs, invalid));
        var unlocalized = facts;
        unlocalized.support = try omissionSupport(&fixture, .{ .unlocalized = .{} });
        try std.testing.expectError(error.InvalidRequiredAuthority, repair.authorize(a, unlocalized));
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
        const support = try omissionSupport(&fixture, .{ .reconciliation_signal = .{ .ordinal = 1 } });
        const auth = try repair.authorize(a, parsed, ctx, support);
        try std.testing.expectEqual(@as(usize, 0), auth.target.unit.signal_content);
        const packet = try repair.packet(std.testing.allocator, parsed, ctx, support, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("business_text", packet.resultDefinition().?.bytes);
        const proposed = try repair.parse(a, auth, packet, "{\"segments\":[{\"kind\":\"literal\",\"value\":\"Preserve the required deadline.\"}]}");
        const merged = try repair.merge(a, parsed, ctx, support, auth, proposed, null);
        try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions, merged.proposal.global.claim_dispositions);
        try std.testing.expectEqualDeep(parsed.proposal.global.signals[1..], merged.proposal.global.signals[1..]);
        try std.testing.expectEqualDeep(parsed.proposal.global.conflicts, merged.proposal.global.conflicts);
        try std.testing.expectEqualDeep(parsed.proposal.global.signals[0].claim_ids, merged.proposal.global.signals[0].claim_ids);
        var rebuilt_context = fixture.context;
        rebuilt_context.references = (try references.finish(a, merged.input, merged.proposal.global, .{ .inputs = ctx.inputs, .registry = ctx.registry, .current = ctx.current })).valid;
        try checkSourceOmissionProgress(a, merged.source.omission_retry.?, support, rebuilt_context);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, merged, ctx, support, auth, proposed, null));
        var changed = support;
        changed.review.revision += 1;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, parsed, ctx, changed, auth));
        const review = @import("domain/specification_support.zig").Source;
        const findings = try a.dupe(review.Finding, support.review.review.entries);
        findings[0].value.loss = .{ .extraction_claim = .{ .bytes = "foreign-chunk" } };
        var candidate = support.review;
        candidate.review.entries = findings;
        var unreviewed = support.inputs;
        unreviewed.evidence = &.{};
        unreviewed.candidates = &.{};
        try std.testing.expect((try review.validate(a, unreviewed, ctx.inputs, candidate)) == .rejected);
        findings[0].value.loss = support.review.review.entries[0].value.loss;
        findings[0].value.decision = .supported;
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
    const ctx: @import("domain/reference_reconciliation_validation.zig").TextContext = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
    fixture.context.references = (try references.finish(a, original.input, proposal, ctx)).valid;
    const global = fixture.context.references.records.assignments.checked.prior.prior;
    const parsed: r.Parsed = .{ .source = global.source, .input = global.input, .proposal = .{ .global = global.proposal } };
    const disposition_support = try omissionSupport(&fixture, .{ .reconciliation_disposition = parsed.proposal.global.claim_dispositions[0].claim_id });
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
    const repaired = try repair.merge(a, parsed, ctx, disposition_support, disposition_auth, replacement, null);
    try std.testing.expectEqualDeep(parsed.proposal.global.signals, repaired.proposal.global.signals);
    try std.testing.expectEqualDeep(parsed.proposal.global.claim_dispositions[1..], repaired.proposal.global.claim_dispositions[1..]);
    try std.testing.expect(repaired.proposal.global.claim_dispositions[0].disposition == .retained);
    _ = (try references.finish(a, repaired.input, repaired.proposal.global, .{ .inputs = ctx.inputs, .registry = ctx.registry, .current = ctx.current })).valid;
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, repaired, ctx, disposition_support, disposition_auth));
}

test "source omission repairs target the false empty outcome and individual irrelevant classification" {
    const repair = @import("domain/reference_extraction_repair.zig").Omission;
    const Origin = @import("domain/model_candidate_origin.zig").Origin;
    const original: Origin = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const corrected: Origin = .{ .request = .{ .value = 7 }, .attempt = .{ .value = 2 } };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    inline for (.{ false, true }) |has_claims| {
        var fixture = try Fixture.initExtraction(a, "Display `Loan renewed!` and `Due today` with the new deadline.", null, has_claims);
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
        const facts: repair.Facts = .{ .extraction = .{ .inputs = inputs, .candidates = candidates, .candidate = fixture.extracted_text }, .support = try omissionSupport(&fixture, if (has_claims) .{ .token_classification = candidates.entries[0].id } else .{ .extraction_claim = chunk.id }) };
        const auth = try repair.authorize(a, facts);
        try std.testing.expect(auth.operation == .replace);
        const replacement: repair.Replacement = if (has_claims) .{ .classification = .{ .preserve = .{ .token_candidate_id = candidates.entries[0].id, .kind = .business_exact_string } } } else .{ .outcome = .{ .claim = .{ .content = .{ .business = .{ .segments = &.{.{ .literal = .{ .value = "Display the new deadline." } }} } }, .citations = &.{extraction.wholeChunk(chunk)} } } };
        const merged = try repair.merge(a, text.validator, fixture.context.registry, fixture.context.current, facts, auth, replacement, corrected);
        try std.testing.expectEqualDeep(original, merged.entries[0].origin.?);
        const rebuilt = try extraction.finishText(a, inputs, merged);
        try std.testing.expectEqual(.complete, rebuilt.outcome);
        if (has_claims) {
            try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].outcome, merged.entries[0].outcome);
            try std.testing.expectEqualDeep(corrected, merged.entries[0].classification_origins[0].?);
            try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].classification_origins[1..], merged.entries[0].classification_origins[1..]);
            try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].token_classifications[1..], merged.entries[0].token_classifications[1..]);
            const damaged_entries = try a.dupe(@import("domain/reference_extraction.zig").TextValidatedResult, merged.entries);
            const damaged_values = try a.dupe(@import("domain/structured_tokens.zig").Classification, damaged_entries[0].token_classifications);
            damaged_values[1].irrelevant.ordinal = 999;
            damaged_entries[0].token_classifications = damaged_values;
            var damaged = merged;
            damaged.entries = damaged_entries;
            const diagnostic = (try @import("domain/token_classification_validation.zig").validate(a, inputs, candidates, damaged)).invalid;
            try std.testing.expectEqualDeep(original, diagnostic.origin.?);
            try std.testing.expectEqual(@as(usize, 2), rebuilt.ledger.claims.len);
            var foreign = replacement;
            foreign.classification.preserve.token_candidate_id.ordinal += 1;
            try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, text.validator, fixture.context.registry, fixture.context.current, facts, auth, foreign, null));
        } else {
            try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].token_classifications, merged.entries[0].token_classifications);
            try std.testing.expectEqualDeep(fixture.extracted_text.entries[0].classification_origins, merged.entries[0].classification_origins);
            try std.testing.expectEqualDeep(corrected, merged.entries[0].outcome.claims[0].origin.?);
            try std.testing.expectEqualDeep(corrected, merged.entries[0].outcome.claims[0].citations_origin.?);
        }
    }
}
fn completedFixture(fixture: *const Fixture, omit_requirements: bool) !@import("domain/specification_session.zig").Session {
    const sessions = @import("domain/specification_session.zig");
    const a = fixture.allocator;
    const value = try fixture.proposal("A receipt is available.");
    const ac: spec.Model.RecordProposal = .{ .content = .{ .acceptance_criterion = .{ .given = value.value, .when = value.value, .then = value.value } }, .provenance = value.provenance };
    const fr: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .provenance = value.provenance };
    var current = try sessions.initialize(fixture.context.inputs.corpus.feature_id, fixture.context);
    while (current.completed < sessions.unit_count) {
        const unit = try sessions.unit(current.completed);
        const response: g.Response = .{ .content = switch (unit) {
            .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
            .primary_user_story => .{ .primary_user_story = value },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
            .records => |kind| .{ .records = if (kind == .acceptance_criterion) &.{ac} else if (kind == .functional_requirement and !omit_requirements) &.{fr} else &.{} },
        } };
        current = try sessions.append(current, (try g.validate(a, text.validator, fixture.context, unit, response)).valid);
    }
    return current;
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
    const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
    const good = try reviewFor(a, inputs);
    const findings = try a.dupe(support.Finding, good.entries);
    findings[0].value.decision = .ambiguous;
    findings[0].value.question = "Which deadline should apply? State the duration and starting event.";
    findings[0].value.detail = "The source leaves the deadline ambiguous.";
    try checkDetailRepair(.source, a, inputs, fixture.context, .{ .entries = findings });
    findings[0].value.detail = "";
    const rejected = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
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
    const fixed = (try repair.merge(a, inputs, fixture.context, rejected.candidate.?, authorization, replacement, corrected)).accepted;
    try std.testing.expectEqual(.ambiguous, fixed.inputs.evidence[0].finding);
    try std.testing.expectEqualDeep(corrected, fixed.inputs.review_origins[0].?);
    try std.testing.expectEqualDeep(original, fixed.inputs.review_origins[1].?);
    try std.testing.expectEqualStrings("Which renewal deadline applies?", fixed.inputs.evidence[0].review.?.detail);
    try std.testing.expectEqual(.needs_user, (try supportDecision(a, fixed.inputs)).result.continuation);
    for (findings[1..], fixed.candidate.review.entries[1..]) |before, after| try std.testing.expectEqualDeep(before, after);
    var stale = rejected.candidate.?;
    stale.revision += 1;
    try std.testing.expectError(error.InvalidAtomicRepair, repair.packet(a, inputs, fixture.context, stale, authorization));
    try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, inputs, fixture.context, stale, authorization, replacement, corrected));
    // No substantive negative result can enter malformed-review authorization.
    try std.testing.expectError(error.InvalidRequiredAuthority, repair.authorize(a, fixed.inputs, fixture.context, rejected));
    const missing = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[1..] }), original)).rejected;
    try std.testing.expectEqual(.missing_requirement, missing.rejection.selected().?.issue);
    const insert = try repair.authorize(a, inputs, fixture.context, missing);
    try std.testing.expect(insert.operation == .insert);
    const complete = (try repair.merge(a, inputs, fixture.context, missing.candidate.?, insert, .{ .finding = good.entries[0].value }, corrected)).accepted;
    try std.testing.expectEqual(good.entries.len, complete.inputs.evidence.len);
    const duplicate = try a.alloc(support.Finding, good.entries.len + 1);
    @memcpy(duplicate[0..good.entries.len], good.entries);
    duplicate[good.entries.len] = good.entries[0];
    const extra = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = duplicate }), original)).rejected;
    const deletion = try repair.authorize(a, inputs, fixture.context, extra);
    try std.testing.expect(deletion.operation == .delete);
    const deduplicated = (try repair.merge(a, inputs, fixture.context, extra.candidate.?, deletion, null, null)).accepted;
    try std.testing.expectEqualDeep(good, deduplicated.candidate.review);
    duplicate[good.entries.len].value.decision = .conflicting;
    const competing = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = duplicate }), original)).rejected;
    try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, competing));
    findings[0].requirement_ordinal = 999;
    const foreign = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
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
    for ([_][]const u8{ "A borrower renews a loan.", "Display `Hello, World!` and `UTC` on startup." }) |source| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const good = try reviewFor(a, inputs);
        var findings = [_]support.Finding{ good.entries[0], good.entries[1], good.entries[1], good.entries[0] };
        findings[0].value.decision = .not_applicable;
        findings[0].value.detail = "\x00";
        findings[0].value.provenance.claim_ids = &.{.{ .ordinal = 999 }};
        findings[2].value.provenance.claim_ids = &.{.{ .ordinal = 999 }};
        findings[3].requirement_ordinal = 999;
        const bytes = try json.encode(support.Review, a, .{ .entries = &findings });
        const rejected = (try support.collect(a, inputs, fixture.context, bytes, null)).rejected;
        const issues = rejected.rejection.diagnostics;
        try std.testing.expectEqual(good.entries.len + 4, issues.len);
        try std.testing.expectEqualDeep(rejected.rejection, (try support.collect(a, inputs, fixture.context, bytes, null)).rejected.rejection);
        const expected = [_]support.Issue{ .duplicate_requirement, .unknown_requirement, .invalid_decision, .invalid_detail, .invalid_evidence, .invalid_evidence };
        for (expected, issues[0..expected.len]) |issue, actual| try std.testing.expectEqual(issue, actual.issue);
        try std.testing.expectEqual(@as(usize, 2), issues[0].entry_index.?);
        try std.testing.expectEqual(@as(usize, 3), issues[1].entry_index.?);
        for (issues[6..], 3..) |issue, ordinal| {
            try std.testing.expectEqual(.missing_requirement, issue.issue);
            try std.testing.expectEqual(ordinal, issue.ordinal.?);
            try std.testing.expect(issue.entry_index == null);
        }
        try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, rejected));
        var tampered = rejected;
        tampered.rejection.diagnostics = issues[0..1];
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, inputs, fixture.context, tampered));
        tampered.rejection.diagnostics = &.{};
        try std.testing.expectError(error.InvalidAtomicRepair, repair.authorize(a, inputs, fixture.context, tampered));
        const empty = (try support.collect(a, inputs, fixture.context, "{\"entries\":[]}", null)).rejected;
        try std.testing.expectEqual(good.entries.len, empty.rejection.diagnostics.len);
        const malformed = (try support.collect(a, inputs, fixture.context, "{", null)).rejected;
        try std.testing.expect(malformed.candidate == null);
        try std.testing.expectEqual(@as(usize, 1), malformed.rejection.diagnostics.len);
        try std.testing.expectEqual(.invalid_json, malformed.rejection.selected().?.issue);
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
    for ([_][]const u8{ "On startup display `Hello, World!` and the current UTC date and time.", "After renewal display `Loan renewed!` and label the deadline `Return by`." }, 0..) |source, scenario| {
        var fixture = try Fixture.init(a, source);
        defer fixture.deinit();
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const good = try reviewFor(a, inputs);
        try std.testing.expectEqual(@as(usize, if (scenario == 0) 11 else 13), good.entries.len);
        const initial = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[0..2] }), original)).rejected;
        try std.testing.expectEqual(good.entries.len - 2, initial.rejection.diagnostics.len);
        for (initial.rejection.diagnostics, 3..) |issue, ordinal| {
            try std.testing.expectEqual(.missing_requirement, issue.issue);
            try std.testing.expectEqual(ordinal, issue.ordinal.?);
        }
        const insert = try repair.authorize(a, inputs, fixture.context, initial);
        var bad = good.entries[2].value;
        bad.provenance.claim_ids = &.{.{ .ordinal = @intCast(inputs.references.?.items.entries.len + 1) }};
        const second = (try repair.merge(a, inputs, fixture.context, initial.candidate.?, insert, .{ .finding = bad }, inserted)).rejected;
        try std.testing.expectEqual(initial.rejection.diagnostics.len, second.rejection.diagnostics.len);
        try std.testing.expectEqual(.ineligible_claim, second.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(inserted, second.rejection.selected().?.origin.?);
        const correction = try repair.authorize(a, inputs, fixture.context, second);
        const packet = try repair.packet(a, inputs, fixture.context, second.candidate.?, correction);
        defer @import("domain/model_input_packet.zig").release(packet);
        const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
        try std.testing.expectEqual(@as(usize, 1), body.get("input").?.object.get("requirements").?.array.items.len);
        try std.testing.expect(!body.get("repair").?.object.get("rule").?.object.contains("diagnostics"));
        const unchanged = (try repair.merge(a, inputs, fixture.context, second.candidate.?, correction, correction.operation.replace, corrected)).rejected;
        try std.testing.expectEqual(@as(u64, 3), unchanged.candidate.?.revision);
        try std.testing.expect(!unchanged.candidate.?.last_repair.?.changed);
        try std.testing.expectEqualDeep(corrected, unchanged.rejection.selected().?.origin.?);
        for (unchanged.rejection.diagnostics[1..], 4..) |issue, ordinal| {
            try std.testing.expectEqual(.missing_requirement, issue.issue);
            try std.testing.expectEqual(ordinal, issue.ordinal.?);
            try std.testing.expectEqualDeep(original, issue.origin.?);
        }
        try std.testing.expectEqualDeep(second.candidate.?.review, unchanged.candidate.?.review);
        try std.testing.expectEqualDeep(good.entries[0..2], unchanged.candidate.?.review.entries[0..2]);
        for (unchanged.candidate.?.origins[0..2]) |origin| try std.testing.expectEqualDeep(original, origin.?);
        // A valid selection still cannot admit a candidate with missing siblings.
        const remaining = (try repair.merge(a, inputs, fixture.context, second.candidate.?, correction, .{ .selection = .{ .provenance = good.entries[2].value.provenance, .source_ids = good.entries[2].value.source_ids } }, corrected)).rejected;
        try std.testing.expectEqual(good.entries.len - 3, remaining.rejection.diagnostics.len);
        try std.testing.expectEqual(@as(u32, 4), remaining.rejection.selected().?.ordinal.?);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, inputs, fixture.context, remaining.candidate.?, correction, correction.operation.replace, corrected));
        // Two independent omissions can recover through two existing atomic calls.
        const bounded = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = good.entries[2..] }), original)).rejected;
        const one = (try repair.merge(a, inputs, fixture.context, bounded.candidate.?, try repair.authorize(a, inputs, fixture.context, bounded), .{ .finding = good.entries[0].value }, inserted)).rejected;
        try std.testing.expectEqual(@as(usize, 1), one.rejection.diagnostics.len);
        const complete = (try repair.merge(a, inputs, fixture.context, one.candidate.?, try repair.authorize(a, inputs, fixture.context, one), .{ .finding = good.entries[1].value }, corrected)).accepted;
        try std.testing.expectEqualDeep(good.entries[2..], complete.candidate.review.entries[0 .. good.entries.len - 2]);
        for (complete.candidate.origins[0 .. good.entries.len - 2]) |origin| try std.testing.expectEqualDeep(original, origin.?);
        try support.validateStored(a, complete.inputs, fixture.context.inputs);
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
    proposal.conflicts = &.{.{ .claim_ids = &.{ dispositions[0].claim_id, dispositions[1].claim_id }, .kind = .value_mismatch, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The outcomes disagree." } }} }, .resolution = .unresolved }};
    const accounted = (try references.finish(a, global, proposal, fixture.context())).valid;
    const context: provenance.Context = .{ .inputs = fixture.inputs, .references = accounted, .registry = fixture.context().registry, .current = fixture.context().current };
    const inputs = try @import("domain/specification_authority.zig").project(a, fixture.inputs.corpus.feature_id, accounted, null, null);
    const allowed_sources = try @import("domain/specification_support_evidence.zig").sourceChoices(a, fixture.inputs);
    try std.testing.expectEqualDeep(&[_]@import("domain/reference_identity.zig").SourceId{ .{ .ordinal = 1 }, .{ .ordinal = 2 }, .{ .ordinal = 3 } }, allowed_sources);
    const ledger = try authority.build(a, inputs);
    const good = try reviewFor(a, inputs);
    const index = for (ledger.requirements, 0..) |requirement, i| {
        if (requirement.seed.id.unit == .conflict) break i;
    } else return error.TestExpectedEqual;
    const accepted = (try support.collect(a, inputs, context, try json.encode(support.Review, a, good), null)).accepted;
    try support.validateStored(a, accepted.inputs, fixture.inputs);
    try std.testing.expectEqual(.invalid, (try supportDecision(a, accepted.inputs)).result.continuation);
    const negative = try a.dupe(support.Finding, good.entries);
    negative[index].value.decision = .conflicting;
    negative[index].value.detail = "One source requires renewal; the other rejects it.";
    negative[index].value.question = "Should this loan be renewed or rejected? Choose the required outcome.";
    const genuine = (try support.collect(a, inputs, context, try json.encode(support.Review, a, .{ .entries = negative }), null)).accepted;
    try std.testing.expectEqual(.needs_user, (try supportDecision(a, genuine.inputs)).result.continuation);
    const claims = good.entries[index].value.provenance.claim_ids;
    const wrong = [_][]const references.r.ClaimId{ &.{}, claims[0..1], &.{dispositions[2].claim_id}, &.{ claims[0], claims[0] } };
    const issues = [_]@import("domain/specification_support_evidence.zig").Issue{ .missing_claims, .wrong_claim_set, .ineligible_claim, .invalid_selection };
    for (wrong, issues) |selection_ids, expected| {
        const findings = try a.dupe(support.Finding, good.entries);
        findings[index].value.provenance.claim_ids = selection_ids;
        const rejected = (try support.collect(a, inputs, context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected;
        try std.testing.expectEqual(@as(usize, 1), rejected.rejection.diagnostics.len);
        try std.testing.expectEqual(expected, rejected.rejection.selected().?.evidence.?.issue);
        try std.testing.expectEqualDeep(allowed_sources, rejected.rejection.selected().?.evidence.?.rule.eligible_source_ids);
        const authorization = try repair.authorize(a, inputs, context, rejected);
        const fixed = (try repair.merge(a, inputs, context, rejected.candidate.?, authorization, .{ .selection = .{ .provenance = good.entries[index].value.provenance, .source_ids = &.{} } }, null)).accepted;
        try std.testing.expectEqualDeep(good, fixed.candidate.review);
        try support.validateStored(a, fixed.inputs, fixture.inputs);
        var corrupt = accepted.inputs;
        const proofs = try a.dupe(authority.Evidence, corrupt.evidence);
        proofs[index].review.?.provenance.claim_ids = selection_ids;
        corrupt.evidence = proofs;
        try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, corrupt, fixture.inputs));
    }
}

test "established UTC and renewal omissions repair one field or record while actual source gaps cannot repair" {
    const sessions = @import("domain/specification_session.zig");
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_coverage_repair.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "The receipt includes a UTC timestamp.", "The renewal receipt includes the return deadline." }) |source| {
        for ([_]bool{ true, false }) |omit| {
            var fixture = try Fixture.init(a, source);
            defer fixture.deinit();
            const current = try completedFixture(&fixture, omit);
            const content = (try sessions.assemble(a, text.validator, fixture.context, current)).content;
            var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, content, current.units[0].?.response.content.brief);
            inputs.revision = current.revision;
            const review_packet = try support.packet(a, inputs, fixture.context);
            defer @import("domain/model_input_packet.zig").release(review_packet);
            const review_body = (try std.json.parseFromSlice(std.json.Value, a, review_packet.body(), .{})).value.object;
            const subject = review_body.get("subject").?.object;
            try std.testing.expectEqualStrings("candidate_support", subject.get("kind").?.string);
            const projected_content = try json.decode(spec.IdentifiedContent, a, try std.json.Stringify.valueAlloc(a, subject.get("candidate").?, .{}));
            try std.testing.expectEqualDeep(content, projected_content);
            const projected_brief = try json.decode(spec.Brief, a, try std.json.Stringify.valueAlloc(a, subject.get("brief").?, .{}));
            try std.testing.expectEqualDeep(inputs.brief.?, projected_brief);
            // A low-level review may supply a brief before the complete spec.
            const brief_inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, null, inputs.brief);
            const brief_packet = try support.packet(a, brief_inputs, fixture.context);
            defer @import("domain/model_input_packet.zig").release(brief_packet);
            const brief_subject = (try std.json.parseFromSlice(std.json.Value, a, brief_packet.body(), .{})).value.object.get("subject").?.object;
            try std.testing.expectEqualStrings("candidate_support", brief_subject.get("kind").?.string);
            try std.testing.expect(brief_subject.get("candidate").? == .null);
            try std.testing.expectEqualDeep(inputs.brief.?, try json.decode(spec.Brief, a, try std.json.Stringify.valueAlloc(a, brief_subject.get("brief").?, .{})));
            const good = try reviewFor(a, inputs);
            const findings = try a.dupe(support.Finding, good.entries);
            const ledger = try authority.build(a, inputs);
            const index = for (ledger.requirements, 0..) |requirement, at| {
                if ((omit and requirement.seed.id.slot == .functional_requirements) or (!omit and requirement.seed.id.unit == .record and requirement.seed.id.unit.record.kind == .functional_requirement and requirement.seed.id.slot == .text)) break at;
            } else unreachable;
            findings[index].value.decision = .candidate_omission;
            findings[index].value.detail = source;
            const admitted_review = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
            const reviewed = admitted_review.inputs;
            const decision = try supportDecision(a, reviewed);
            try std.testing.expectEqual(.invalid, decision.result.continuation);
            const authorization = try repair.authorizeOmission(a, text.validator, current, fixture.context, content, decision);
            try std.testing.expectEqual(omit, authorization.operation == .insert);
            if (omit) try std.testing.checkAllAllocationFailures(std.testing.allocator, omissionPacketAllocationCase, .{ current, fixture.context, content, decision, authorization });
            const packet = try repair.omissionPacket(a, current, fixture.context, content, decision, authorization);
            defer @import("domain/model_input_packet.zig").release(packet);
            const value = try fixture.proposal(source);
            const record: spec.Model.RecordProposal = .{ .content = .{ .functional_requirement = .{ .text = value.value } }, .provenance = value.provenance };
            const replacement = try repair.parseOmission(a, authorization, packet, if (omit) try json.encode(spec.Model.RecordProposal, a, record) else try json.encode(spec.BusinessValue, a, value.value));
            const fixed = try repair.mergeOmission(a, text.validator, current, fixture.context, content, decision, authorization, replacement, null);
            for (current.units, fixed.units, 0..) |before, after, at| if (at != authorization.target.unit) try std.testing.expectEqualDeep(before, after);
            const rebuilt = try sessions.assemble(a, text.validator, fixture.context, fixed);
            try std.testing.expect(spec.hasRecords(rebuilt.content, .functional_requirement));
            try std.testing.expectEqual(content.records.len + @intFromBool(omit), rebuilt.content.records.len);
            try std.testing.expectEqual(authorization.retry.?.maximum_targets, fixed.omission_target_bound.?);
            try std.testing.expect((try repair.coverageValidation(a, fixed, fixture.context, rebuilt.content)) == null);
            try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.admittedOmissionValidation(a, authorization.retry.?, admitted_review));
            var renewed_inputs = try @import("domain/specification_authority.zig").project(a, fixed.feature, fixture.context.references, rebuilt.content, fixed.units[0].?.response.content.brief);
            renewed_inputs.revision = fixed.revision;
            const renewed_review = try reviewFor(a, renewed_inputs);
            const positive_renewed = (try support.collect(a, renewed_inputs, fixture.context, try json.encode(support.Review, a, renewed_review), null)).accepted;
            try std.testing.expectEqual(.resolved, (try repair.admittedOmissionValidation(a, authorization.retry.?, positive_renewed)).?.validated.result);
            for (0..4) |scenario| {
                var altered = authorization.retry.?;
                switch (scenario) {
                    0 => altered.key.scope[0] ^= 1,
                    1 => altered.key.target[0] ^= 1,
                    2 => altered.revision = positive_renewed.inputs.revision,
                    3 => altered.key.family[0] ^= 1,
                    else => unreachable,
                }
                if (scenario == 3) {
                    try std.testing.expect((try repair.admittedOmissionValidation(a, altered, positive_renewed)) == null);
                } else try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.admittedOmissionValidation(a, altered, positive_renewed));
            }
            var stale_brief = positive_renewed.inputs;
            stale_brief.brief.?.primary_goal = try fixture.value("A different goal.");
            try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.authorizeOmission(a, text.validator, fixed, fixture.context, rebuilt.content, try supportDecision(a, stale_brief)));
            const negative_findings = try a.dupe(support.Finding, renewed_review.entries);
            const renewed_ledger = try authority.build(a, renewed_inputs);
            for (renewed_ledger.requirements, negative_findings) |requirement, *finding| if (std.meta.eql(requirement.seed.id, authorization.rule.omission.requirement)) {
                finding.value.decision = .candidate_omission;
                finding.value.detail = source;
            };
            const still_missing = (try support.collect(a, renewed_inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = negative_findings }), null)).accepted;
            try std.testing.expectEqual(.recurring, (try repair.admittedOmissionValidation(a, authorization.retry.?, still_missing)).?.validated.result);
            const repeated_authorization = try repair.authorizeOmission(a, text.validator, fixed, fixture.context, rebuilt.content, try supportDecision(a, still_missing.inputs));
            try std.testing.expectEqualDeep(authorization.retry.?.key, repeated_authorization.retry.?.key);
            try std.testing.expectEqual(authorization.retry.?.maximum_targets, repeated_authorization.retry.?.maximum_targets);
            try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.mergeOmission(a, text.validator, fixed, fixture.context, rebuilt.content, decision, authorization, replacement, null));
            findings[index].value.decision = .unsupported;
            findings[index].value.question = "Which deadline should apply? State the duration and starting event.";
            findings[index].value.provenance.claim_ids = &.{};
            const absent = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
            const gap = try supportDecision(a, absent);
            try std.testing.expectEqual(.needs_user, gap.result.continuation);
            try std.testing.expectError(error.UnsafeSpecificationOmissionRepair, repair.authorizeOmission(a, text.validator, current, fixture.context, content, gap));
            const positive = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, good), null)).accepted.inputs;
            try std.testing.expectError(error.UnsafeSpecificationOmissionRepair, repair.authorizeOmission(a, text.validator, current, fixture.context, content, try supportDecision(a, positive)));
        }
    }
}

fn omissionPacketAllocationCase(allocator: std.mem.Allocator, current: @import("domain/specification_session.zig").Session, context: provenance.Context, content: spec.IdentifiedContent, support: @import("domain/specification_coverage_repair.zig").Support, authorization: @import("domain/specification_coverage_repair.zig").Authorization) !void {
    const packet = try @import("domain/specification_coverage_repair.zig").omissionPacket(allocator, current, context, content, support, authorization);
    defer @import("domain/model_input_packet.zig").release(packet);
}

test "support reviews retain original sources and discarded or misclassified token decisions" {
    const support = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Display `Renewal accepted!` and provide a return deadline.", "Display `Booking confirmed!` and provide the arrival date." }) |source| {
        for ([_]?@import("domain/structured_tokens.zig").Kind{ null, .visual_typography, .business_exact_string }) |kind| {
            var fixture = try Fixture.initClassified(a, source, kind);
            defer fixture.deinit();
            const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
            const packet = try support.packet(a, inputs, fixture.context);
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
            const good = try reviewFor(a, inputs);
            _ = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, good), null)).accepted;
            const findings = try a.dupe(support.Finding, good.entries);
            findings[0].value = .{ .decision = .candidate_omission, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = "The extraction omitted the source-required confirmation and follow-up date." };
            const omitted = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
            try std.testing.expectEqual(.invalid, (try supportDecision(a, omitted)).result.continuation);
            try std.testing.expectEqualStrings(findings[0].value.detail, omitted.evidence[0].review.?.detail);
            try std.testing.expectEqualDeep(findings[0].value.source_ids, omitted.evidence[0].review.?.source_ids);
            var foreign = fixture.context;
            foreign.inputs.corpus.state_id.bytes = "foreign-state";
            try std.testing.expect((try support.collect(a, inputs, foreign, try json.encode(support.Review, a, good), null)) == .rejected);
            const ledger = try authority.build(a, inputs);
            try std.testing.expect(ledger.requirements.len >= 8);
        }
    }
}

test "review-purpose eligibility admits nonconflicting superseded tokens without widening business provenance" {
    const support = @import("domain/specification_support.zig").Source;
    const admission = @import("domain/specification_support_evidence.zig");
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Replace `Old greeting` with `Renewal accepted!`.");
    defer fixture.deinit();
    const dispositions = try a.dupe(references.r.ClaimDisposition, fixture.context.references.records.assignments.checked.prior.prior.dispositions);
    const token_claim = (try provenance.items(fixture.context)).entries[1].claim;
    dispositions[1].disposition = .superseded;
    dispositions[1].related_claim_ids = &.{dispositions[2].claim_id};
    fixture.context.references.records.assignments.checked.prior.prior.dispositions = dispositions;
    const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
    const good = try reviewFor(a, inputs);
    const accepted = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, good), null)).accepted.inputs;
    try std.testing.expectEqual(.all_resolved, (try supportDecision(a, accepted)).result.continuation);
    const token_requirement: authority.Id = .{ .kind = .preservation, .unit = .{ .token = token_claim.content.preserved_token.value.id }, .slot = .value };
    try std.testing.expect(admission.eligible(inputs.references.?, token_requirement, token_claim.id));
    try std.testing.expectError(error.InvalidSpecification, provenance.select(a, fixture.context, .{ .claim_ids = &.{token_claim.id}, .clarification_response_ids = &.{} }));
    dispositions[1].disposition = .conflicting;
    const conflicted = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
    try std.testing.expect(!admission.eligible(conflicted.references.?, token_requirement, token_claim.id));
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
    const reviewed = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, try reviewFor(a, inputs)), .{ .request = .{ .value = 500 }, .attempt = .{ .value = 1 } })).accepted.inputs;
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
        .review = .{ .candidate_revision = inputs.revision, .seeds = reviewed.seeds, .evidence = reviewed.evidence, .candidates = reviewed.candidates, .observations = decision.observations, .result = decision.result },
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
    const restarted = try (@import("actions/specification/initialize_specification_generation.zig").Action{}).execute(current.feature, fixture.context, pending_prior);
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
    for (0..14) |mode| {
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
            broken.content.primary_user_story.value = .{ .exact_copy = .{ .token_id = .{ .ordinal = 999 }, .citation_id = .{ .ordinal = 1 } } };
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
        } else {
            const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, value.review.evidence);
            proofs[0].review.?.detail = "\x00";
            broken.review.evidence = proofs;
        }
        try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, broken, .{}), current.feature, contracts.port()));
    }
}

test "principle review preserves business authority and retains cited Plan obligations through repair and readback" {
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
        const source = try source_review.collect(a, inputs, fixture.context, try json.encode(source_review.Review, a, try reviewFor(a, inputs)), null);
        const policies = try @import("test_fixtures/principles.zig").registry(a, example[1]);
        const advanced = try progress.advance(a, .{ .source = source }, policies);
        try std.testing.expectEqual(.more, advanced.outcome);
        const pending = advanced.progress.pending;
        const policy_inputs = pending.inputs;
        const ledger = try authority.build(a, policy_inputs);
        try std.testing.expect(ledger.requirements.len >= 7);
        const packet = try policy_review.packet(std.testing.allocator, policy_inputs, fixture.context);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "principle_consistency") != null);
        try std.testing.expect(std.mem.indexOf(u8, packet.body(), "toolchain.yaml") == null);
        const source_packet = try source_review.packet(std.testing.allocator, inputs, fixture.context);
        defer @import("domain/model_input_packet.zig").release(source_packet);
        try std.testing.expect(std.mem.indexOf(u8, source_packet.body(), example[1]) == null);
        const findings = try a.alloc(policy_review.Finding, ledger.requirements.len);
        for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .value = .{ .decision = if (index == 0) .conflicting else .compatible, .citations = if (index == 0) &.{.{ .chunk = policies.chunks[0].id, .first_line = 1, .last_line = 1 }} else &.{}, .detail = if (index == 0) "The explicit business requirement conflicts with the selected policy; Plan must resolve the choice." else "" } };
        try checkDetailRepair(.principles, a, policy_inputs, fixture.context, .{ .entries = findings });
        const origin: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
        const good = try policy_review.collect(a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = findings }), origin);
        try std.testing.expect(good == .accepted);
        const canonical = try assessment.canonical(a, good.accepted.inputs);
        try std.testing.expectEqual(.needs_user, canonical.result.continuation);
        try std.testing.expectEqual(.plan, canonical.result.entries[0].outcome.clarification_required.owner);
        try assessment.validateStored(a, source.accepted.inputs, fixture.context.inputs, canonical);
        try std.testing.expectError(error.InvalidRequiredAuthority, assessment.canonical(a, policy_inputs));
        const ready = try progress.advance(a, .{ .principles = .{ .pending = pending, .result = good } }, policies);
        try std.testing.expectEqual(.complete, ready.outcome);
        try std.testing.expectEqualDeep(source.accepted.inputs.specification, ready.progress.source.accepted.inputs.specification);
        try std.testing.expectEqualDeep(source.accepted.inputs.evidence, ready.progress.source.accepted.inputs.evidence);
        try std.testing.expect(ready.progress.source.accepted.inputs.principle_assessment != null);
        for (0..9) |mode| {
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
                7 => invalid.result.continuation = .all_resolved,
                8 => {
                    invalid.registry.id.root.file_id += 1;
                    invalid.registry.inventory.root.identity = invalid.registry.id.root;
                    invalid.selection.registry = invalid.registry.id;
                },
                else => unreachable,
            }
            if (assessment.validateStored(a, source.accepted.inputs, fixture.context.inputs, invalid)) |_| return error.ExpectedInvalidPolicyEvidence else |err| try std.testing.expect(err != error.OutOfMemory);
        }
        // An invalid citation is repaired without changing the negative decision.
        const broken = try a.dupe(policy_review.Finding, findings);
        broken[0].value.citations = &.{.{ .chunk = .{ .ordinal = 999 }, .first_line = 1, .last_line = 1 }};
        const rejected = (try policy_review.collect(a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = broken }), origin)).rejected;
        const authorization = try repair.authorize(a, policy_inputs, fixture.context, rejected);
        const request = try repair.packet(std.testing.allocator, policy_inputs, fixture.context, rejected.candidate.?, authorization);
        defer @import("domain/model_input_packet.zig").release(request);
        try std.testing.expectEqualStrings("principle_selection", request.resultDefinition().?.bytes);
        const replacement = try repair.parse(a, authorization, request, "{\"citations\":[{\"chunk\":{\"ordinal\":1},\"first_line\":1,\"last_line\":1}]}");
        const unchanged = try repair.merge(a, policy_inputs, fixture.context, rejected.candidate.?, authorization, .{ .selection = .{ .citations = broken[0].value.citations } }, origin);
        try std.testing.expect(unchanged == .rejected);
        const recovered = (try repair.merge(a, policy_inputs, fixture.context, rejected.candidate.?, authorization, replacement, .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } })).accepted;
        try std.testing.expectEqual(.conflicting, recovered.candidate.review.entries[0].value.decision);
        try std.testing.expectEqualDeep(findings[1..], recovered.candidate.review.entries[1..]);
        try std.testing.expectEqual(@as(u64, 2), recovered.candidate.revision);
        try std.testing.expectEqualDeep(origin, recovered.candidate.origins[1].?);
        _ = try assessment.canonical(a, recovered.inputs);
        const missing = (try policy_review.collect(a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = findings[1..] }), origin)).rejected;
        const insert = try repair.authorize(a, policy_inputs, fixture.context, missing);
        try std.testing.expect(insert.operation == .insert);
        const inserted = (try repair.merge(a, policy_inputs, fixture.context, missing.candidate.?, insert, .{ .finding = findings[0].value }, origin)).accepted;
        try std.testing.expectEqualDeep(findings[1..], inserted.candidate.review.entries[0 .. findings.len - 1]);
        _ = try assessment.canonical(a, inserted.inputs);
        const duplicate = try std.mem.concat(a, policy_review.Finding, &.{ findings, findings[0..1] });
        duplicate[1].requirement_ordinal = 999;
        duplicate[0].value.citations = &.{};
        const multiple = (try policy_review.collect(a, policy_inputs, fixture.context, try json.encode(policy_review.Review, a, .{ .entries = duplicate }), origin)).rejected;
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

test "coverage progress resolves the selected token while another obligation remains" {
    const sessions = @import("domain/specification_session.zig");
    const repair = @import("domain/specification_coverage_repair.zig");
    const check = @import("actions/specification/validate_specification_coverage.zig").Action{ .validator = text.validator };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "Display `Accepted!` and `Ready!`.");
    defer fixture.deinit();
    const all = try provenance.items(fixture.context);
    var records: std.ArrayList(spec.Model.RecordProposal) = .empty;
    for (all.entries) |entry| if (entry.claim.content == .preserved_token) {
        const raw = entry.claim.content.preserved_token.value.raw_value.bytes;
        try records.append(a, .{ .content = .{ .user_visible_outcome = .{ .text = .{ .normalized = .{ .segments = try a.dupe(@import("domain/typed_text.zig").BusinessSegment, &.{ .{ .literal = .{ .value = raw[0..2] } }, .{ .literal = .{ .value = raw[2..] } } }) } } } }, .provenance = .{ .claim_ids = try a.dupe(references.r.ClaimId, &.{entry.claim.id}), .clarification_response_ids = &.{} } });
    };
    try std.testing.expectEqual(@as(usize, 2), records.items.len);
    const good = try fixture.proposal("The requested outcome is observable.");
    var current = try sessions.initialize(.{ .bytes = "chosen" }, fixture.context);
    while (current.completed < sessions.unit_count) {
        const unit = try sessions.unit(current.completed);
        const response: g.Response = .{ .content = switch (unit) {
            .brief => .{ .brief = .{ .title = good, .description = good, .primary_goal = good } },
            .primary_user_story => .{ .primary_user_story = good },
            .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = good } },
            .records => |kind| .{ .records = if (kind == .user_visible_outcome) records.items else &.{} },
        } };
        current = try sessions.append(current, (try g.validate(a, text.validator, fixture.context, unit, response)).valid);
    }
    const initial = (try sessions.assemble(a, text.validator, fixture.context, current)).content;
    const first = (try repair.authorize(a, current, fixture.context, initial, (try check.execute(a, current, fixture.context, initial)).invalid)).authorized;
    const partial = try repair.merge(a, text.validator, current, fixture.context, initial, first);
    const intermediate = (try sessions.assemble(a, text.validator, fixture.context, partial)).content;
    const next_rejection = (try check.execute(a, partial, fixture.context, intermediate)).invalid;
    try std.testing.expectEqual(.resolved, (try repair.coverageValidation(a, partial, fixture.context, intermediate)).?.validated.result);
    const second = (try repair.authorize(a, partial, fixture.context, intermediate, next_rejection)).authorized;
    try std.testing.expectEqualDeep(first.retry.?.key.scope, second.retry.?.key.scope);
    try std.testing.expect(!std.meta.eql(first.retry.?.key.target, second.retry.?.key.target));
    try std.testing.expectEqual(first.retry.?.maximum_targets, second.retry.?.maximum_targets);
    const completed = try repair.merge(a, text.validator, partial, fixture.context, intermediate, second);
    const final = (try sessions.assemble(a, text.validator, fixture.context, completed)).content;
    try std.testing.expectEqual(.resolved, (try repair.coverageValidation(a, completed, fixture.context, final)).?.validated.result);
    try std.testing.expect((try check.execute(a, completed, fixture.context, final)) == .valid);
    try std.testing.expectEqualDeep(intermediate.records[0], final.records[0]);
}

fn checkSourceOmissionProgress(a: std.mem.Allocator, permit: @import("domain/workflow_retry.zig").Permit, negative: @import("domain/source_omission.zig").Support, context: provenance.Context) !void {
    const loss = @import("domain/source_omission.zig");
    const support = @import("domain/specification_support.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var unreviewed = negative.inputs;
    unreviewed.evidence = &.{};
    unreviewed.candidates = &.{};
    const negative_admitted = (try support.validate(a, unreviewed, context.inputs, negative.review)).accepted;
    try std.testing.expectEqual(.recurring, (try loss.admittedValidation(a, permit, negative_admitted)).?.validated.result);
    const renewed_inputs = try @import("domain/specification_authority.zig").project(a, context.inputs.corpus.feature_id, context.references, null, null);
    const reviewed = (try support.collect(a, renewed_inputs, context, try json.encode(support.Review, a, try reviewFor(a, renewed_inputs)), null)).accepted;
    try std.testing.expectEqual(.resolved, (try loss.admittedValidation(a, permit, reviewed)).?.validated.result);
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
        } else try std.testing.expectError(error.InvalidRequiredAuthority, loss.admittedValidation(a, altered, reviewed));
    }
    for ([_]bool{ false, true }) |source| {
        var foreign = reviewed;
        if (source) foreign.inputs.references.?.items.state_id.bytes = "foreign-state" else foreign.inputs.feature.bytes = "foreign-feature";
        try std.testing.expectError(error.InvalidRequiredAuthority, loss.admittedValidation(a, permit, foreign));
    }
    var foreign_evidence = reviewed.inputs;
    const entries = try a.dupe(@import("domain/required_authority.zig").Evidence, reviewed.inputs.evidence);
    entries[0].review.?.source_ids = &.{.{ .ordinal = 999 }};
    foreign_evidence.evidence = entries;
    try std.testing.expectError(error.InvalidRequiredAuthority, support.validateStored(a, foreign_evidence, context.inputs));
}

fn checkDetailRepair(comptime purpose: @import("domain/specification_support.zig").Purpose, a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs, context: provenance.Context, good: @import("domain/specification_support.zig").Contract(purpose).Review) !void {
    const review = @import("domain/specification_support.zig").Contract(purpose);
    const repair = @import("domain/specification_support_repair.zig").Contract(purpose);
    const detail_owner = @import("domain/specification_support_evidence.zig");
    const original: @import("domain/model_candidate_origin.zig").Origin = .{ .request = .{ .value = 1 }, .attempt = .{ .value = 1 } };
    const corrected: @TypeOf(original) = .{ .request = .{ .value = 2 }, .attempt = .{ .value = 1 } };
    const admitted = (try review.collect(a, inputs, context, try @import("domain/model_candidate_json.zig").encode(review.Review, a, good), original)).accepted;
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
        try std.testing.expectEqualStrings(@tagName(good.entries[0].value.decision), repair_rule.get("decision").?.string);
        const rule = repair_rule.get("detail_rule").?.object;
        try std.testing.expect(!rule.get("allow_empty").?.bool);
        try std.testing.expectEqual(@as(i64, @import("domain/clarification_inputs.zig").max_text_bytes), rule.get("maximum_utf8_bytes").?.integer);
        try std.testing.expect(std.mem.indexOf(u8, rule.get("instruction").?.string, "retained finding") != null);
        const unchanged = try repair.merge(a, inputs, context, candidate, authorization, .{ .detail = .{ .detail = invalid } }, corrected);
        try std.testing.expect(unchanged == .rejected);
        var corrected_detail = authorization.operation.replace;
        corrected_detail.detail.detail = good.entries[0].value.detail;
        if (purpose == .source) corrected_detail.detail.question = good.entries[0].value.question;
        const fixed = (try repair.merge(a, inputs, context, candidate, authorization, corrected_detail, corrected)).accepted;
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
        try std.testing.expect((try repair.merge(a, inputs, context, missing.candidate.?, insert, .{ .finding = rows[0].value }, corrected)) == .rejected);
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
    try contract.validate(std.testing.allocator, stored, &current.authority, .source_blocks_v1);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, contract.validate, .{ stored, &current.authority, .source_blocks_v1 });
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
    for ([_][]const u8{ "When started, display Hello, World! and the UTC date and time.", "The borrower receives a renewal receipt." }) |source| {
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
        try std.testing.expect(std.mem.indexOf(u8, try @import("domain/reference_context.zig").render(a, technical.reference, null), escaped.written()) != null);

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
        for (0..8) |mode| {
            var bad = value;
            switch (mode) {
                0 => bad.open_clarifications = &.{},
                1 => bad.open_clarifications = &.{ .{ .stage = .spec, .ordinal = 1 }, .{ .stage = .spec, .ordinal = 1 } },
                2 => bad.open_clarifications = &.{.{ .stage = .plan, .ordinal = 1 }},
                3 => bad.open_clarifications = &.{.{ .stage = .spec, .ordinal = 0 }},
                4 => bad.feature = .{ .bytes = "foreign" },
                5 => bad.clarification.revision = 0,
                6 => bad.schema = "specification-state/v2",
                7 => bad.id_ledger.next[0] = 0,
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
        const forms = try @import("domain/clarification_views.zig").render(a, validated, &.{});
        const prepare: @import("actions/specification/prepare_incomplete_specification_output.zig").Action = .{ .contracts = contracts.port() };
        const prepared = try prepare.execute(a, directory, paths, .{ .state = null, .forms = &.{} }, inputs, .{ .ready = validated }, forms, prior, value, rendered);
        try std.testing.expectEqual(.needs_user, prepared.terminal_outcome);
        try std.testing.expectEqual(@as(usize, 5), prepared.files.len);
        try std.testing.expectEqual(.specification, prepared.files[0].target.artifact);
        try std.testing.expectEqual(.workflow_state, prepared.files[prepared.files.len - 1].target.artifact);
        try std.testing.expectError(error.InvalidWorkflowOutput, prepare.execute(a, directory, paths, .{ .state = null, .forms = &.{} }, inputs, .{ .ready = validated }, forms, prior, value, "forged spec"));
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

test "source gap questions survive detail repair insertion and persisted validation without changing verdicts" {
    const review = @import("domain/specification_support.zig").Source;
    const repair = @import("domain/specification_support_repair.zig").Source;
    const json = @import("domain/model_candidate_json.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
    const good = try reviewFor(a, inputs);
    const entries = try a.dupe(review.Finding, good.entries);
    entries[0].value.decision = .ambiguous;
    entries[0].value.detail = "Renewal is supported, but the source gives no duration.";
    const question = "How long should renewal last? Supply a duration and its starting event.";
    for ([_]?[]const u8{ null, "", " \n", "\x00" }) |bad| {
        entries[0].value.question = bad;
        const rejected = (try review.collect(a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).rejected;
        try std.testing.expectEqual(@as(review.Issue, if (bad == null) .missing_question else .invalid_question), rejected.rejection.selected().?.issue);
        const auth = try repair.authorize(a, inputs, fixture.context, rejected);
        const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("gap_detail", packet.resultDefinition().?.bytes);
        const unchanged = try repair.merge(a, inputs, fixture.context, rejected.candidate.?, auth, auth.operation.replace, null);
        try std.testing.expectEqual(.recurring, repair.progress(auth, unchanged));
        const fixed = try repair.merge(a, inputs, fixture.context, rejected.candidate.?, auth, .{ .detail = .{ .detail = entries[0].value.detail, .question = question } }, null);
        try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
        try std.testing.expectEqual(.ambiguous, fixed.accepted.inputs.evidence[0].finding);
        try std.testing.expectEqualDeep(entries[0].value.provenance, fixed.accepted.candidate.review.entries[0].value.provenance);
        try std.testing.expectEqualDeep(good.entries[1..], fixed.accepted.candidate.review.entries[1..]);
        try review.validateStored(a, fixed.accepted.inputs, fixture.context.inputs);
        const decision = try supportDecision(a, fixed.accepted.inputs);
        const needs = try @import("domain/required_authority_clarifications.zig").build(a, decision.inputs, decision.observations, decision.result);
        try std.testing.expect(std.mem.startsWith(u8, needs.entries[0].question, question));
        var corrupt = fixed.accepted.inputs;
        const proofs = try a.dupe(@import("domain/required_authority.zig").Evidence, corrupt.evidence);
        proofs[0].review.?.question = bad;
        corrupt.evidence = proofs;
        try std.testing.expectError(error.InvalidRequiredAuthority, review.validateStored(a, corrupt, fixture.context.inputs));
        const missing = (try review.collect(a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = good.entries[1..] }), null)).rejected;
        const insertion = try repair.authorize(a, inputs, fixture.context, missing);
        try std.testing.expect((try repair.merge(a, inputs, fixture.context, missing.candidate.?, insertion, .{ .finding = entries[0].value }, null)) == .rejected);
    }
    entries[0] = good.entries[0];
    entries[0].value.question = question;
    try std.testing.expect((try review.collect(a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)) == .rejected);
}

test "false conflicts repair a closed relation group with exact preconditions and preserved siblings" {
    const repair = @import("domain/reference_reconciliation_repair.zig").Omission;
    const review = @import("domain/specification_support.zig").Source;
    const authority = @import("domain/required_authority.zig");
    const json = @import("domain/model_candidate_json.zig");
    const r = references.r;
    for ([_][]const u8{ "On startup show the greeting and UTC date. Display `Hello, World!`.\n", "Renew the loan and show the new return date. Display `Loan renewed!`.\n" }) |source| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var fixture = try Fixture.initContent(a, source, .business_exact_string, true, "Retain the supported behavior and its date information.", 3);
        defer fixture.deinit();
        const original = fixture.context.references.records.assignments.checked.prior.prior;
        var proposal = original.proposal;
        const dispositions = try a.dupe(r.ClaimDispositionProposal, proposal.claim_dispositions);
        var business: std.ArrayList(r.ClaimId) = .empty;
        for (original.input.progress.plan.layout.items.entries) |item| if (item.claim.content == .model) {
            try business.append(a, item.claim.id);
        };
        try std.testing.expect(business.items.len >= 3);
        const claims = business.items[0..2];
        for (dispositions) |*value| {
            if (std.meta.eql(value.claim_id, claims[0])) value.disposition = .{ .conflicting = .{ .related_claim_ids = &.{claims[1]} } };
            if (std.meta.eql(value.claim_id, claims[1])) value.disposition = .{ .conflicting = .{ .related_claim_ids = &.{claims[0]} } };
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
        proposal.conflicts = &.{.{ .claim_ids = claims, .kind = .mutually_exclusive, .summary = .{ .nodes = &.{.{ .literal = .{ .value = "The compatible requirements were incorrectly grouped as conflicting." } }} }, .resolution = .unresolved }};
        const ctx: @import("domain/reference_reconciliation_validation.zig").TextContext = .{ .inputs = fixture.context.inputs, .registry = fixture.context.registry, .current = fixture.context.current };
        fixture.context.references = (try references.finish(a, original.input, proposal, ctx)).valid;
        const global = fixture.context.references.records.assignments.checked.prior.prior;
        const parsed: r.Parsed = .{ .source = global.source, .input = global.input, .proposal = .{ .global = global.proposal } };
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const entries = try a.dupe(review.Finding, (try reviewFor(a, inputs)).entries);
        const ledger = try authority.build(a, inputs);
        var conflict_index: usize = 0;
        for (ledger.requirements, entries, 0..) |requirement, *finding, index| if (requirement.seed.id.unit == .conflict) {
            conflict_index = index;
            finding.value.decision = .candidate_omission;
            finding.value.detail = "The original requirements are compatible; restore their separate supported meanings.";
            finding.value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
            finding.value.loss = .{ .reconciliation_conflict = requirement.seed.id.unit.conflict };
        };
        const admitted = (try review.collect(a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).accepted;
        const decision = try supportDecision(a, admitted.inputs);
        try std.testing.expectEqual(.invalid, decision.result.continuation);
        const support: @import("domain/source_omission.zig").Support = .{ .review = admitted.candidate, .inputs = decision.inputs, .observations = decision.observations, .result = decision.result };
        const auth = try repair.authorize(a, parsed, ctx, support);
        try std.testing.expectEqualDeep(claims, auth.target.conflict_group);
        const packet = try repair.packet(a, parsed, ctx, support, auth);
        defer @import("domain/model_input_packet.zig").release(packet);
        try std.testing.expectEqualStrings("repair_conflict_group", packet.resultDefinition().?.bytes);
        const changed = try a.dupe(r.ClaimDispositionProposal, auth.operation.replace.conflict_group.claim_dispositions);
        for (changed) |*value| value.disposition = .{ .retained = .{} };
        const replacement = try repair.parse(a, auth, packet, try json.encode(@import("domain/reference_reconciliation_repair.zig").ConflictGroup, a, .{ .claim_dispositions = changed, .conflicts = &.{} }));
        const fixed = try repair.merge(a, parsed, ctx, support, auth, replacement, .{ .request = .{ .value = 101 }, .attempt = .{ .value = 1 } });
        try std.testing.expectEqualDeep(parsed.proposal.global.signals, fixed.proposal.global.signals);
        for (parsed.proposal.global.claim_dispositions, fixed.proposal.global.claim_dispositions, 0..) |before, after, index| if (!r.contains(r.ClaimId, claims, before.claim_id)) {
            try std.testing.expectEqualDeep(before, after);
            try std.testing.expectEqualDeep(parsed.source.at(.{ .disposition = index }, .record), fixed.source.at(.{ .disposition = index }, .record));
        };
        try std.testing.expectEqual(@as(usize, 0), fixed.proposal.global.conflicts.len);
        // Group repair cannot itself invent replacement signals; full validation
        // must require their rebuilding by the existing coverage-repair owner.
        try std.testing.expect((try references.finish(a, fixed.input, fixed.proposal.global, ctx)) == .invalid);
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, fixed, ctx, support, auth, replacement, null));
        changed[0].claim_id = business.items[2];
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, parsed, ctx, support, auth, .{ .conflict_group = .{ .claim_dispositions = changed, .conflicts = &.{} } }, null));
        changed[0].claim_id = auth.operation.replace.conflict_group.claim_dispositions[0].claim_id;
        changed[0].disposition = .{ .duplicate = .{ .target_claim_id = business.items[2] } };
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, parsed, ctx, support, auth, .{ .conflict_group = .{ .claim_dispositions = changed, .conflicts = &.{} } }, null));
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
        entries[conflict_index].value.decision = .conflicting;
        entries[conflict_index].value.loss = .{ .unlocalized = .{} };
        entries[conflict_index].value.question = "Which requirement should take precedence? Identify the required behavior.";
        const negative = (try review.collect(a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).accepted;
        const gap = try supportDecision(a, negative.inputs);
        try std.testing.expectEqual(.needs_user, gap.result.continuation);
        try std.testing.expectError(error.InvalidRequiredAuthority, repair.authorize(a, parsed, ctx, .{ .review = negative.candidate, .inputs = gap.inputs, .observations = gap.observations, .result = gap.result }));
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
        const inputs = try @import("domain/specification_authority.zig").project(a, fixture.context.inputs.corpus.feature_id, fixture.context.references, null, null);
        const good = try reviewFor(a, inputs);
        for (std.meta.tags(review.Decision)) |decision| {
            const entries = try a.dupe(review.Finding, good.entries);
            const index = if (decision == .not_applicable) blk: {
                const ledger = try @import("domain/required_authority.zig").build(a, inputs);
                for (ledger.requirements, 0..) |req, i| if (req.seed.id.kind == .entity_applicability) break :blk i;
                return error.MissingEntityRequirement;
            } else 0;
            const negative = @import("domain/specification_support_evidence.zig").questionRequired(decision.finding());
            entries[index].value.decision = decision;
            entries[index].value.detail = "The source establishes the action; its duration is unspecified.";
            entries[index].value.question = if (negative) null else "Unexpected question.";
            const rejected = (try review.collect(a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).rejected;
            try std.testing.expectEqual(@as(review.Issue, if (negative) .missing_question else .forbidden_question), rejected.rejection.selected().?.issue);
            const auth = try repair.authorize(a, inputs, fixture.context, rejected);
            const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, auth);
            defer @import("domain/model_input_packet.zig").release(packet);
            const selected = schemas.select(packet.resultDefinition().?).?;
            const only_detail = "{\"detail\":\"The source establishes the action; its duration is unspecified.\"}";
            const pair = "{\"detail\":\"The source establishes the action; its duration is unspecified.\",\"question\":\"What duration applies? State the duration and starting event.\"}";
            try check(selected.modelBytes(), .{ .bytes = if (negative) pair else only_detail });
            try check(selected.modelBytes(), .{ .bytes = if (negative) only_detail else pair, .rejection = if (negative) .missing_required_property else .unknown_property, .path = "/question" });
            const fixed = try repair.merge(a, inputs, fixture.context, rejected.candidate.?, auth, try repair.parse(a, auth, packet, if (negative) pair else only_detail), null);
            try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
            try std.testing.expectEqual(decision, fixed.accepted.candidate.review.entries[index].value.decision);
            try std.testing.expectEqualDeep(entries[index].value.provenance, fixed.accepted.candidate.review.entries[index].value.provenance);
            for (entries, fixed.accepted.candidate.review.entries, 0..) |before, after, i| if (i != index) try std.testing.expectEqualDeep(before, after);
            try review.validateStored(a, fixed.accepted.inputs, fixture.context.inputs);
            if (!negative) continue;
            // A schema-valid repair may introduce a native text defect. It must
            // retain the original pair's key, even when the failing field changes.
            const blank_detail = "{\"detail\":\"\",\"question\":\"What duration applies? State its starting event.\"}";
            try check(selected.modelBytes(), .{ .bytes = blank_detail });
            const recurring = try repair.merge(a, inputs, fixture.context, rejected.candidate.?, auth, try repair.parse(a, auth, packet, blank_detail), null);
            try std.testing.expectEqual(.invalid_detail, recurring.rejected.rejection.selected().?.issue);
            try std.testing.expectEqual(.recurring, repair.progress(auth, recurring));
            const again = try repair.authorize(a, inputs, fixture.context, recurring.rejected);
            try std.testing.expectEqualDeep(auth.retry.?.key, again.retry.?.key);
            const blank_question = "{\"detail\":\"Known facts and missing duration.\",\"question\":\" \"}";
            try check(selected.modelBytes(), .{ .bytes = blank_question });
            const next_packet = try repair.packet(a, inputs, fixture.context, recurring.rejected.candidate.?, again);
            defer @import("domain/model_input_packet.zig").release(next_packet);
            const still_bad = try repair.merge(a, inputs, fixture.context, recurring.rejected.candidate.?, again, try repair.parse(a, again, next_packet, blank_question), null);
            try std.testing.expectEqual(.invalid_question, still_bad.rejected.rejection.selected().?.issue);
            try std.testing.expectEqual(.recurring, repair.progress(again, still_bad));
            try std.testing.expectEqualDeep(auth.retry.?.key, (try repair.authorize(a, inputs, fixture.context, still_bad.rejected)).retry.?.key);
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
        for (0..3) |stage| {
            const inputs = try @import("domain/specification_authority.zig").project(a, session.feature, fixture.context.references, if (stage == 2) content else null, if (stage > 0) session.units[0].?.response.content.brief else null);
            const good = try reviewFor(a, inputs);
            const ledger = try @import("domain/required_authority.zig").build(a, inputs);
            for (std.meta.tags(review.Decision)) |decision| {
                // After generation native applicability already fixes the outcome;
                // the schema still follows its supported finding's evidence rule.
                if (decision == .not_applicable and stage == 2) continue;
                const index = if (decision == .not_applicable) blk: {
                    for (ledger.requirements, 0..) |req, i| if (req.seed.id.kind == .entity_applicability) break :blk i;
                    return error.MissingEntityRequirement;
                } else 0;
                const entries = try a.dupe(review.Finding, good.entries);
                entries[index].value.decision = decision;
                entries[index].value.detail = "The source establishes the action; its duration is unspecified.";
                entries[index].value.question = if (admission.questionRequired(decision.finding())) "What duration applies? Supply a duration and starting event." else null;
                entries[index].value.source_ids = &.{.{ .ordinal = 999 }};
                const rejected = (try review.collect(a, inputs, fixture.context, try json.encode(review.Review, a, .{ .entries = entries }), null)).rejected;
                try std.testing.expectEqual(.invalid_sources, rejected.rejection.selected().?.evidence.?.issue);
                const auth = try repair.authorize(a, inputs, fixture.context, rejected);
                const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, auth);
                defer @import("domain/model_input_packet.zig").release(packet);
                const selected = schemas.select(packet.resultDefinition().?).?;
                const body = (try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{})).value.object;
                const rule = body.get("repair").?.object.get("rule").?.object.get("evidence_rule").?.object;
                try std.testing.expectEqualStrings(admission.selection_instruction, rule.get("instruction").?.string);
                const required = admission.minimum(decision.finding()) == .claim_required;
                const empty: repair.Replacement = .{ .selection = .{ .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{fixture.context.inputs.corpus.sources[0].id} } };
                const empty_bytes = try json.encodeSelected(repair.Replacement, a, empty);
                if (required) try check(selected.modelBytes(), .{ .bytes = empty_bytes, .rejection = .array_length, .path = "/provenance/claim_ids" }) else try check(selected.modelBytes(), .{ .bytes = empty_bytes });
                var replacement = empty;
                if (required) replacement.selection.provenance = good.entries[index].value.provenance;
                const bytes = try json.encodeSelected(repair.Replacement, a, replacement);
                try check(selected.modelBytes(), .{ .bytes = bytes });
                const fixed = try repair.merge(a, inputs, fixture.context, rejected.candidate.?, auth, try repair.parse(a, auth, packet, bytes), null);
                try std.testing.expectEqual(.resolved, repair.progress(auth, fixed));
                try std.testing.expectEqual(decision, fixed.accepted.candidate.review.entries[index].value.decision);
                for (entries, fixed.accepted.candidate.review.entries, 0..) |before, after, i| if (i != index) try std.testing.expectEqualDeep(before, after);
                try review.validateStored(a, fixed.accepted.inputs, fixture.context.inputs);
                // Cardinality admission never certifies membership or semantic support.
                replacement.selection.provenance.claim_ids = &.{.{ .ordinal = 999 }};
                const foreign = try json.encodeSelected(repair.Replacement, a, replacement);
                try check(selected.modelBytes(), .{ .bytes = foreign });
                const invalid = try repair.merge(a, inputs, fixture.context, rejected.candidate.?, auth, try repair.parse(a, auth, packet, foreign), null);
                try std.testing.expectEqual(.ineligible_claim, invalid.rejected.rejection.selected().?.evidence.?.issue);
                try std.testing.expectEqual(.recurring, repair.progress(auth, invalid));
                try std.testing.expectEqualDeep(auth.retry.?.key, (try repair.authorize(a, inputs, fixture.context, invalid.rejected)).retry.?.key);
                for ([_]review.Scope{ .all, .{ .finding = ledger.requirements[index].seed.id } }) |scope| {
                    const initial = try review.packetFor(a, inputs, fixture.context, scope);
                    defer @import("domain/model_input_packet.zig").release(initial);
                    const input = (try std.json.parseFromSlice(std.json.Value, a, initial.body(), .{})).value.object;
                    try std.testing.expectEqualStrings(admission.selection_instruction, input.get("evidence_rules").?.object.get("instruction").?.string);
                }
            }
        }
    }
}
