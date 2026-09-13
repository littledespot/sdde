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
    for (findings, 0..) |*finding, index| finding.* = .{ .requirement_ordinal = @intCast(index + 1), .finding = .supported, .disposition = .supported, .provenance = selection(value.provenance) };
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
    findings[0].provenance = .{ .claim_ids = &.{}, .clarification_response_ids = &.{} };
    const absent = try support.collect(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{}));
    try std.testing.expectEqual(.ambiguous, absent.evidence[0].finding);
    findings[0].provenance.clarification_response_ids = &.{.{ .ordinal = 1 }};
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collect(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{})));
    findings[0].provenance = selection(value.provenance);
    findings[0].requirement_ordinal = 999;
    try std.testing.expectError(error.InvalidRequiredAuthority, support.collect(a, initial, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{})));
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
        const complete = (try references.finish(a, global, try references.global(a, global), context)).valid;
        return .{ .allocator = a, .context = .{ .inputs = inputs, .references = complete, .registry = passive.registry, .current = context.current }, .passive = passive };
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
            for (ledger.requirements, findings, 0..) |requirement, *finding, index| finding.* = .{
                .requirement_ordinal = @intCast(index + 1),
                .finding = if (mode == 4 and requirement.seed.id.slot == .scenario_coverage) .unsupported else .supported,
                .disposition = if (requirement.seed.id.kind == .entity_applicability) .not_applicable else .supported,
                .provenance = selection(value.provenance),
            };
            const reviewed = try support.collect(a, inputs, fixture.context, try std.json.Stringify.valueAlloc(a, support.Review{ .entries = findings }, .{}));
            const checked = try authority.build(a, reviewed);
            const observations = try (@import("actions/authority/build_required_authority_observations.zig").Action{}).execute(a, checked);
            const result = try authority.reconcile(a, checked, observations);
            try std.testing.expectEqual(@as(@TypeOf(result.continuation), if (mode == 3) .all_resolved else .needs_user), result.continuation);
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
