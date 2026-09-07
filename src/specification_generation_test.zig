const std = @import("std");
const g = @import("domain/specification_generation.zig");
const spec = g.spec;
const provenance = @import("domain/specification_provenance.zig");
const identifiers = @import("domain/specification_identity.zig");
const references = @import("test_fixtures/reference_reconciliation.zig");
const evidence = @import("reference_evidence_test.zig");
const extraction = @import("reference_extraction_test.zig");
const text = @import("test_fixtures/reference_text.zig");
const tokens = @import("test_fixtures/reference_tokens.zig");

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
        const value = try fixture.value(source);
        try std.testing.expectError(error.InvalidSpecificationUnit, sessions.assemble(a, text.validator, fixture.context, current));
        while (current.completed < sessions.unit_count) {
            const unit = try sessions.unit(current.completed);
            const packet = try sessions.packet(std.testing.allocator, current, fixture.context);
            defer @import("domain/model_input_packet.zig").release(packet);
            try std.testing.expect(std.mem.indexOf(u8, packet.body(), "principles") == null);
            const response: g.Response = .{ .content = switch (unit) {
                .brief => .{ .brief = .{ .title = value, .description = value, .primary_goal = value } },
                .primary_user_story => .{ .primary_user_story = value },
                .entities => .{ .entities = .{ .disposition = .not_applicable, .basis = value } },
                .records => |kind| result: {
                    if (kind != .functional_requirement) break :result .{ .records = &.{} };
                    const records = try a.dupe(spec.RecordProposal, &.{.{ .content = .{ .functional_requirement = .{ .text = value.value } }, .provenance = value.provenance }});
                    break :result .{ .records = records };
                },
            } };
            const checked = try g.validate(a, text.validator, fixture.context, unit, response);
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
    for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .finding = .supported, .disposition = .supported, .provenance = value.provenance };
    const bytes = try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{});
    const reviewed = try support.collect(a, initial, fixture.context, bytes);
    for (reviewed.evidence) |proof| try std.testing.expectEqual(.model_assisted, proof.method);
    const current = try authority.build(a, reviewed);
    const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, current);
    const result = try authority.reconcile(a, current, observations);
    try std.testing.expect(try authority.validate(a, reviewed, observations, result));
    findings[0].finding = .ambiguous;
    const gap = try support.collect(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{}));
    const gap_ledger = try authority.build(a, gap);
    const gap_observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, gap_ledger);
    try std.testing.expectEqual(.needs_user, (try authority.reconcile(a, gap_ledger, gap_observations)).continuation);
    findings[0].requirement_ordinal = 999;
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collect(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{})));
}

test "specification units validate every section family without creating IDs or filler" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A librarian renews a loan.");
    defer fixture.deinit();
    const value = try fixture.value("A librarian renews a loan.");
    inline for (comptime std.meta.tags(spec.Kind)) |kind| {
        const fields = Fields(kind, value.value);
        const record: spec.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), fields), .provenance = value.provenance };
        const result = try g.validate(a, text.validator, fixture.context, .{ .records = kind }, .{ .content = .{ .records = &.{record} } });
        try std.testing.expectEqual(kind, std.meta.activeTag(result.response.content.records[0].content));
        const wire = try @import("domain/model_candidate_json.zig").encode(g.ModelResponse, a, g.ModelResponse.from(result.response));
        try std.testing.expectEqualDeep(result.response, try g.parse(a, wire));
        _ = try g.validate(a, text.validator, fixture.context, .{ .records = kind }, .{ .content = .{ .records = &.{} } });
        try std.testing.expectError(error.InvalidSpecificationUnit, g.validate(a, text.validator, fixture.context, .{ .records = kind }, .{ .content = .{ .records = &.{ record, record } } }));
    }
    const brief: g.Response = .{ .content = .{ .brief = .{ .title = value, .description = value, .primary_goal = value } } };
    _ = try g.validate(a, text.validator, fixture.context, .brief, brief);
    try std.testing.expectError(error.InvalidSpecificationUnit, g.validate(a, text.validator, fixture.context, .primary_user_story, brief));
    const question = try g.validate(a, text.validator, fixture.context, .primary_user_story, .{ .clarification = .{ .reason = .ambiguous, .question = try fixture.value("Which renewal limit applies?") } });
    try std.testing.expectEqual(.clarification, std.meta.activeTag(question.response));
}

test "specification provenance rejects foreign missing duplicate stale and unaccepted support" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A customer books a visit.");
    defer fixture.deinit();
    const good = try fixture.value("A customer books a visit.");
    _ = try provenance.attributed(a, text.validator, fixture.context, good);
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
        if (provenance.attributed(a, text.validator, fixture.context, changed)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.InvalidSpecification, error.InvalidReferenceReconciliation => {},
            else => return err,
        }
    }
    var stale = fixture.context;
    stale.inputs.corpus.state_id.bytes = "different-reference-state";
    try std.testing.expectError(error.InvalidSpecification, provenance.attributed(a, text.validator, stale, good));
    try std.testing.expectError(error.UnboundPathReference, provenance.attributed(a, text.validator, fixture.context, try fixture.value("Write src/main.zig.")));
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
            const accepted = try provenance.attributed(a, text.validator, fixture.context, proposed);
            try std.testing.expectEqualDeep(proposed, accepted);
            var wrong = proposed;
            wrong.value.exact_copy.token_id.ordinal = 999;
            try std.testing.expectError(error.InvalidSpecification, provenance.attributed(a, text.validator, fixture.context, wrong));
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
    const response: g.Response = .{ .content = .{ .primary_user_story = value } };
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
    fn init(a: std.mem.Allocator, bytes: []const u8) !Fixture {
        var ids: evidence.IdSource = .{};
        const inputs = try evidence.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "stories.md", bytes));
        const passive = try text.prepare(a, inputs);
        errdefer passive.deinit();
        const chunk = inputs.chunks.entries[0];
        const candidates = try tokens.candidates(a, inputs);
        const reply = try tokens.wire(a, try extraction.reply(a, chunk, "An extracted business claim."), try tokens.classifications(a, candidates, chunk));
        const extracted = try extraction.finish(a, inputs, &.{.{ .scope = .{ .state_id = inputs.corpus.state_id, .chunk_id = chunk.id }, .result = .{ .response = reply } }});
        const context: references.Context = .{ .inputs = inputs, .registry = passive.registry, .current = text.safety.value(passive.owner) };
        const global = try references.summaries(a, try references.initialize(a, inputs, extracted, 2), context);
        const complete = try references.finish(a, global, try references.global(a, global), context);
        return .{ .allocator = a, .context = .{ .inputs = inputs, .references = complete, .registry = passive.registry, .current = context.current }, .passive = passive };
    }
    fn deinit(self: *Fixture) void {
        self.passive.deinit();
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
        const good = try fixture.value(source);
        var bad = good;
        bad.provenance.claim_ids = &.{.{ .ordinal = 999 }};
        const candidate: repair.Candidate = .{ .response = .{ .content = .{ .brief = .{ .title = good, .description = bad, .primary_goal = good } } } };
        const authorization = try repair.authorize(a, text.validator, fixture.context, current, candidate);
        try std.testing.expect(authorization.target == .description);
        const packet = try repair.packet(std.testing.allocator, current, fixture.context, authorization);
        defer packets.release(packet);
        const replacement: repair.Replacement = .{ .attributed = good };
        const wire = try @import("domain/model_candidate_json.zig").encode(repair.Replacement, a, replacement);
        const parsed = try repair.parse(a, authorization, packet, wire);
        const merged = try repair.merge(a, current, candidate, authorization, parsed);
        try std.testing.expectEqual(@as(u64, 2), merged.revision);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.title);
        try std.testing.expectEqualDeep(good, merged.response.content.brief.primary_goal);
        try std.testing.expectEqualDeep(bad, candidate.response.content.brief.description);
        _ = try g.validate(a, text.validator, fixture.context, .brief, merged.response);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.authorize(a, text.validator, fixture.context, current, merged));
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, current, merged, authorization, parsed));
        var changed = candidate;
        changed.response.content.brief.description = good;
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, current, changed, authorization, parsed));
        var foreign = current;
        foreign.feature.bytes = "another-feature";
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, foreign, candidate, authorization, parsed));
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.packet(a, foreign, fixture.context, authorization));
        var wrong_id = authorization;
        wrong_id.id.bytes = "foreign-repair";
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.parse(a, wrong_id, packet, try @import("domain/model_candidate_json.zig").encode(repair.Replacement, a, replacement)));
        const with_target = try std.fmt.allocPrint(a, "{{\"target\":\"title\",{s}", .{wire[1..]});
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.parse(a, authorization, packet, with_target));
        const with_sibling = try std.fmt.allocPrint(a, "{{\"record\":{{}},{s}", .{wire[1..]});
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.parse(a, authorization, packet, with_sibling));
        const still_invalid = try repair.merge(a, current, candidate, authorization, .{ .attributed = bad });
        try std.testing.expectError(error.InvalidReferenceReconciliation, g.validate(a, text.validator, fixture.context, .brief, still_invalid.response));
    }
}

test "record repair selects one duplicate without changing IDs or valid sibling content" {
    const repair = @import("domain/specification_repair.zig");
    const sessions = @import("domain/specification_session.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try Fixture.init(a, "A borrower renews a loan.");
    defer fixture.deinit();
    var current = try sessions.initialize(.{ .bytes = "selected" }, fixture.context);
    const value = try fixture.value("Borrower requests renewal.");
    inline for (.{ spec.Kind.acceptance_criterion, spec.Kind.business_rule }) |kind| {
        current.completed = 3 + @intFromEnum(kind);
        const record: spec.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, value.value)), .provenance = value.provenance };
        const replacement_value = try fixture.value("Renewal confirmation is visible.");
        const replacement: spec.RecordProposal = .{ .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), Fields(kind, replacement_value.value)), .provenance = replacement_value.provenance };
        const proposed: repair.Candidate = .{ .response = .{ .content = .{ .records = &.{ record, record } } } };
        const authorization = try repair.authorize(a, text.validator, fixture.context, current, proposed);
        try std.testing.expectEqual(@as(usize, 1), authorization.target.record);
        const merged = try repair.merge(a, current, proposed, authorization, .{ .record = replacement });
        try std.testing.expectEqualDeep(record, merged.response.content.records[0]);
        _ = try g.validate(a, text.validator, fixture.context, .{ .records = kind }, merged.response);
        try std.testing.expectError(error.InvalidSpecificationRepair, repair.merge(a, current, proposed, authorization, .{ .attributed = value }));
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
