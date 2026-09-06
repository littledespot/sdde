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
    const bytes = try std.json.Stringify.valueAlloc(a, response, .{});
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
