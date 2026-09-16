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
    const support = @import("domain/specification_support.zig");
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
    const bytes = try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{});
    const reviewed = try collectSupport(a, initial, fixture.context, bytes);
    for (reviewed.evidence) |proof| try std.testing.expectEqual(.model_assisted, proof.method);
    const current = try authority.build(a, reviewed);
    const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, current);
    const result = try authority.reconcile(a, current, observations);
    try std.testing.expect(try authority.validate(a, reviewed, observations, result));
    findings[0].value.decision = .ambiguous;
    const gap = try collectSupport(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{}));
    const gap_ledger = try authority.build(a, gap);
    const gap_observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, gap_ledger);
    try std.testing.expectEqual(.needs_user, (try authority.reconcile(a, gap_ledger, gap_observations)).continuation);
    findings[0].value.provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} };
    const absent = try collectSupport(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{}));
    try std.testing.expectEqual(.ambiguous, absent.evidence[0].finding);
    findings[0].value.provenance.clarification_response_ids = &.{.{ .ordinal = 1 }};
    try std.testing.expectError(error.InvalidRequiredAuthority, collectSupport(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{})));
    findings[0].value.provenance = selection(value.provenance);
    findings[0].requirement_ordinal = 999;
    try std.testing.expectError(error.InvalidRequiredAuthority, collectSupport(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{})));
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
    fn init(a: std.mem.Allocator, bytes: []const u8) !Fixture {
        return initClassified(a, bytes, .business_exact_string);
    }
    fn initClassified(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind) !Fixture {
        return initExtraction(a, bytes, kind, true);
    }
    fn initExtraction(a: std.mem.Allocator, bytes: []const u8, kind: ?@import("domain/structured_tokens.zig").Kind, has_claims: bool) !Fixture {
        var ids: evidence.IdSource = .{};
        const inputs = try evidence.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "stories.md", bytes));
        const passive = try text.prepare(a, inputs);
        errdefer passive.deinit();
        const chunk = inputs.chunks.entries[0];
        const candidates = try tokens.candidates(a, inputs);
        const choices = try a.alloc(@import("domain/structured_tokens.zig").Classification, candidates.entries.len);
        for (candidates.entries, choices) |candidate, *choice| choice.* = if (kind) |selected| .{ .preserve = .{ .token_candidate_id = candidate.id, .kind = selected } } else .{ .irrelevant = candidate.id };
        const reply = try tokens.wire(a, if (has_claims) try extraction.reply(a, chunk, "An extracted business claim.") else extraction.no_claim, choices);
        const extracted = try extraction.finish(a, inputs, &.{.{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = reply } }});
        const context: references.Context = .{ .inputs = inputs, .registry = passive.registry, .current = text.safety.value(passive.owner) };
        const global = try references.summaries(a, try references.initialize(a, inputs, extracted, 2), context);
        const complete = (try references.finish(a, global, try references.global(a, global), context)).valid;
        return .{ .allocator = a, .extracted = extracted, .context = .{ .inputs = inputs, .references = complete, .registry = passive.registry, .current = context.current }, .passive = passive };
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
        _ = (try g.validate(a, text.validator, fixture.context, .{ .records = kind }, merged.response)).valid;
        try std.testing.expectError(error.InvalidAtomicRepair, repair.merge(a, current, fixture.context, proposed, authorization, .{ .provenance = value.provenance }, null));
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
    const support = @import("domain/specification_support.zig");
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
                .provenance = selection(value.provenance),
                .source_ids = &.{},
                .detail = "A required scenario is not established by the source.",
            } };
            const reviewed = try collectSupport(a, inputs, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{}));
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
    try std.testing.expect(sibling.issue.field.target.provenance == .primary_goal);
    try std.testing.expectEqualDeep(initial, sibling.origin.?);
    try std.testing.expectEqualDeep(correction, merged.origins.at(.{ .target = .{ .provenance = .description } }).?);
    try std.testing.expectEqualDeep(initial, merged.origins.at(.{ .target = .{ .provenance = .title } }).?);
    const unchanged = try repair.merge(a, current, fixture.context, candidate, authorization, .{ .provenance = bad.provenance }, correction);
    const again = (try validate_unit.execute(a, current, fixture.context, unchanged)).invalid;
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
    const support = @import("domain/specification_support.zig");
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
    return switch (try @import("domain/specification_support.zig").collect(allocator, inputs, context, bytes, null)) {
        .accepted => |accepted| accepted.inputs,
        .rejected => error.InvalidRequiredAuthority,
    };
}

test "review decisions preserve seven source gaps and reject forbidden applicability across requirement kinds" {
    const support = @import("domain/specification_support.zig");
    const repair = @import("domain/specification_support_repair.zig");
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
                finding.value = .{ .decision = .unsupported, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{}, .detail = "The source leaves this decision unspecified." };
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
                try std.testing.expectEqual(.invalid_decision, rejected.rejection.issue);
                try std.testing.expectEqualDeep(requirement.seed.id, rejected.rejection.requirement.?);
                try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, rejected));
            }
            const old = "{\"entries\":[{\"requirement_ordinal\":1,\"value\":{\"finding\":\"unsupported\",\"disposition\":\"not_applicable\",\"provenance\":{\"claim_ids\":[],\"clarification_response_ids\":[]},\"source_ids\":[],\"detail\":\"No explicit field.\"}}]}";
            try std.testing.expectEqual(.invalid_json, (try support.collect(a, inputs, fixture.context, old, null)).rejected.rejection.issue);
        }
    }
}

test "entity applicability shares native policy across initial inserted and persisted reviews" {
    const support = @import("domain/specification_support.zig");
    const repair = @import("domain/specification_support_repair.zig");
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
            try std.testing.expectEqual(.missing_claims, invalid_evidence.rejection.evidence.?.issue);
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
                try std.testing.expectEqual(.invalid_decision, invalid_merge.rejection.issue);
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
        findings[entity].value.detail = "The source does not establish the entity basis.";
        const negative = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
        try std.testing.expectEqual(.unsupported, negative.evidence[entity].finding);
        try std.testing.expectEqual(mode == 2, negative.evidence[entity].resolution == .not_applicable);
        try std.testing.expectEqual(.needs_user, (try supportDecision(a, negative)).result.continuation);
        try support.validateStored(a, negative, fixture.context.inputs);
        if (mode >= 2) {
            findings[entity].value.decision = .not_applicable;
            try std.testing.expectEqual(.invalid_decision, (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).rejected.rejection.issue);
        }
    }
}

test "review evidence repairs expose both defects without changing semantic findings" {
    const support = @import("domain/specification_support.zig");
    const repair = @import("domain/specification_support_repair.zig");
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
                finding.value.provenance.claim_ids = &.{};
                finding.value.detail = "The source does not settle this requirement.";
                negatives += 1;
            }
            finding.value.source_ids = &.{fixture.context.inputs.corpus.sources[0].id};
        }
        try std.testing.expectEqual(@as(usize, 9), negatives);
        const first = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
        try std.testing.expectEqual(.invalid_evidence, first.rejection.issue);
        try std.testing.expectEqual(.missing_claims, first.rejection.evidence.?.issue);
        try std.testing.expectEqual(entity.? + 1, first.rejection.ordinal.?);
        try std.testing.expectEqual(.claim_required, first.rejection.evidence.?.rule.minimum);
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
        try std.testing.expectEqual(.missing_claims, unchanged.rejection.evidence.?.issue);
        try std.testing.expect(!unchanged.candidate.?.last_repair.?.changed);
        try std.testing.expectEqual(@as(u64, 2), unchanged.candidate.?.revision);
        try std.testing.expectEqualDeep(findings, unchanged.candidate.?.review.entries);
        const entity_replacement: repair.Replacement = .{ .selection = .{ .provenance = good.entries[entity.?].value.provenance, .source_ids = findings[entity.?].value.source_ids } };
        const second = (try repair.merge(a, inputs, fixture.context, first.candidate.?, authorization, entity_replacement, corrected)).rejected;
        try std.testing.expectEqual(.ineligible_claim, second.rejection.evidence.?.issue);
        try std.testing.expectEqual(token.? + 1, second.rejection.ordinal.?);
        try std.testing.expectEqualDeep(original, second.rejection.origin.?);
        try std.testing.expectEqualDeep(corrected, second.candidate.?.origins[entity.?].?);
        try std.testing.expectEqual(.not_applicable, second.candidate.?.review.entries[entity.?].value.decision);
        for (findings, second.candidate.?.review.entries, 0..) |before, after, index| if (index != entity.?) try std.testing.expectEqualDeep(before, after);
        const token_authorization = try repair.authorize(a, inputs, fixture.context, second);
        const token_rule = second.rejection.evidence.?.rule;
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
    const support = @import("domain/specification_support.zig");
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
        if (case.gap) |detail| findings[4].value = .{ .decision = .ambiguous, .provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} }, .source_ids = &.{fixture.context.inputs.corpus.sources[0].id}, .detail = detail };
        const accepted = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted;
        // Scripted decisions test admission/routing; prose is never classified natively.
        try std.testing.expectEqualDeep(findings, accepted.candidate.review.entries);
        try std.testing.expectEqual(@as(@FieldType(@import("domain/required_authority.zig").Result, "continuation"), if (case.gap != null) .needs_user else .all_resolved), (try supportDecision(a, accepted.inputs)).result.continuation);
    }
}

test "review evidence rules preserve minima exact sets and candidate provenance across subjects" {
    const support = @import("domain/specification_support.zig");
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
            const expected = try admission.requirements(a, inputs, id);
            try std.testing.expectEqualDeep(expected.rule(.supported), (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, empty, sources, "")).rejected.rule);
            try std.testing.expectEqual(.missing_claims, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, empty, sources, "")).rejected.issue);
            try std.testing.expectEqual(.missing_evidence, (try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, empty, &.{}, "The source requirement was lost.")).rejected.issue);
            const omission = try admission.admit(a, inputs, fixture.context.inputs, id, .candidate_omission, empty, sources, "The source requirement was lost.");
            if (expected.positive_claims == .exact_set) try std.testing.expectEqual(.wrong_claim_set, omission.rejected.issue) else try std.testing.expect(omission == .accepted);
            try std.testing.expect((try admission.admit(a, inputs, fixture.context.inputs, id, .unsupported, empty, &.{}, "The source does not settle this requirement.")) == .accepted);
            try std.testing.expectEqual(.invalid_sources, (try admission.admit(a, inputs, fixture.context.inputs, id, .supported, finding.value.provenance, &.{.{ .ordinal = 999 }}, "")).rejected.issue);
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

fn reviewFor(a: std.mem.Allocator, inputs: @import("domain/required_authority.zig").Inputs) !@import("domain/specification_support.zig").Review {
    const support = @import("domain/specification_support.zig");
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
    const support = @import("domain/specification_support.zig");
    const repair = @import("domain/specification_support_repair.zig");
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
    const rejected = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), original)).rejected;
    try std.testing.expectEqual(.invalid_detail, rejected.rejection.issue);
    try std.testing.expectError(error.InvalidRequiredAuthority, (@import("actions/specification/apply_specification_support.zig").Action{}).execute(.{ .rejected = rejected }));
    const authorization = try repair.authorize(a, inputs, fixture.context, rejected);
    const packet = try repair.packet(a, inputs, fixture.context, rejected.candidate.?, authorization);
    defer @import("domain/model_input_packet.zig").release(packet);
    const request_body = try std.json.parseFromSlice(std.json.Value, a, packet.body(), .{});
    const repair_input = request_body.value.object.get("input").?.object;
    try std.testing.expectEqual(@as(usize, 1), repair_input.get("requirements").?.array.items.len);
    try std.testing.expectEqualStrings("A borrower renews a loan.", repair_input.get("sources").?.array.items[0].object.get("text").?.string);
    const replacement = try repair.parse(a, authorization, packet, "{\"detail\":\"Which renewal deadline applies?\"}");
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
    try std.testing.expectEqual(.missing_requirement, missing.rejection.issue);
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
    try std.testing.expectEqual(.unknown_requirement, foreign.rejection.issue);
    try std.testing.expectError(error.UnsafeSupportRepair, repair.authorize(a, inputs, fixture.context, foreign));
}

test "established UTC and renewal omissions repair one field or record while actual source gaps cannot repair" {
    const sessions = @import("domain/specification_session.zig");
    const authority = @import("domain/required_authority.zig");
    const support = @import("domain/specification_support.zig");
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
            const reviewed = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, .{ .entries = findings }), null)).accepted.inputs;
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
            try std.testing.expectError(error.InvalidSpecificationCoverageRepair, repair.mergeOmission(a, text.validator, fixed, fixture.context, rebuilt.content, decision, authorization, replacement, null));
            findings[index].value.decision = .unsupported;
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
    const support = @import("domain/specification_support.zig");
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
    const support = @import("domain/specification_support.zig");
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
    const support = @import("domain/specification_support.zig");
    const state = @import("domain/specification_state.zig");
    const sessions = @import("domain/specification_session.zig");
    const json = @import("domain/model_candidate_json.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower receives a renewal receipt.");
    defer fixture.deinit();
    const current = try completedFixture(&fixture, false);
    const assigned = try sessions.assemble(a, text.validator, fixture.context, current);
    var inputs = try @import("domain/specification_authority.zig").project(a, current.feature, fixture.context.references, assigned.content, current.units[0].?.response.content.brief);
    inputs.revision = current.revision;
    const reviewed = (try support.collect(a, inputs, fixture.context, try json.encode(support.Review, a, try reviewFor(a, inputs)), .{ .request = .{ .value = 500 }, .attempt = .{ .value = 1 } })).accepted.inputs;
    const decision = try supportDecision(a, reviewed);
    const value: state.State = .{
        .schema = state.schema,
        .feature = current.feature,
        .revision = 1,
        .stage = .specified,
        .reference = try @import("domain/reference_snapshot.zig").build(.{ .bytes = "first" }, fixture.context.inputs, fixture.extracted, fixture.context.references, fixture.context.registry),
        .brief = inputs.brief.?,
        .content = assigned.content,
        .id_ledger = assigned.ledger,
        .coverage = try @import("domain/specification_coverage.zig").validate(a, fixture.context.references, inputs.brief.?, assigned.content),
        .clarification = .{ .state_ordinal = 1, .revision = 1 },
        .review = .{ .candidate_revision = inputs.revision, .seeds = reviewed.seeds, .evidence = reviewed.evidence, .candidates = reviewed.candidates, .observations = decision.observations, .result = decision.result },
    };
    const bytes = try std.json.Stringify.valueAlloc(a, value, .{});
    var fresh = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer fresh.deinit();
    const restored = (try state.parse(fresh.allocator(), bytes, current.feature)).state.?;
    try std.testing.expectEqualStrings(bytes, try std.json.Stringify.valueAlloc(a, restored, .{}));
    const document = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    try std.testing.expect(document.value.object.get("review").?.object.get("origin") == null);
    for (0..13) |mode| {
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
        } else {
            broken.reference.signals = &.{};
        }
        try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, try std.json.Stringify.valueAlloc(a, broken, .{}), current.feature));
    }
}
