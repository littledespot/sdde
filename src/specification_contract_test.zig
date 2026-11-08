const std = @import("std");
const spec = @import("domain/specification.zig");
const json = @import("domain/strict_json.zig");
const markdown = @import("domain/specification_markdown.zig");
const testing = std.testing;

test "specification record identity is closed and grows beyond three digits" {
    inline for (comptime std.meta.tags(spec.Kind)) |kind| {
        const id = spec.Id.parse((comptime kind.prefix()) ++ "-001").?;
        try testing.expectEqual(kind, id.kind);
        try testing.expectEqual(@as(u32, 1), id.ordinal);
    }
    try testing.expectEqual(@as(u32, 1000), spec.Id.parse("EN-1000").?.ordinal);
    for ([_][]const u8{ "AC-000", "FR-01", "UO-0001", "OQ-001", "EN-+001", "AC-4294967296", "ac-001", "AC-01x", "AC-001 " }) |bytes| {
        try testing.expect(spec.Id.parse(bytes) == null);
    }
    try testing.expect(std.meta.stringToEnum(spec.Kind, "open_question") == null);
}

test "closed specification proposal has one content authority and no IDs modality or questions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const proposed = proposal();
    const bytes = try std.json.Stringify.valueAlloc(allocator, proposed, .{});
    const decoded = try decodeProposal(allocator, bytes);
    try testing.expectEqual(@as(usize, 0), decoded.records.len);
    try testing.expectEqual(.not_applicable, decoded.entities.disposition);
    try testing.expect(!@hasField(spec.RecordProposal, "id"));
    try testing.expect(!@hasField(@FieldType(spec.Content(spec.BusinessValue), "functional_requirement"), "modality"));
    for ([_][]const u8{ "id", "modality", "open_questions", "path", "completed" }) |foreign| {
        const changed = try std.fmt.allocPrint(allocator, "{{\"{s}\":true,{s}", .{ foreign, bytes[1..] });
        try testing.expectError(error.InvalidJsonDocument, decodeProposal(allocator, changed));
    }
}

test "schema parsing rejects malformed nested union and scalar coercions across unrelated contracts" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const Shape = struct { choice: union(enum) { count: u32, absent: struct {} }, label: []const u8 };
    const valid = try json.decode(Shape, allocator, "{\"choice\":{\"count\":3},\"label\":\"sample\"}", .{ .maximum_depth = 8 });
    try testing.expectEqual(@as(u32, 3), valid.choice.count);
    _ = try json.decode(Shape, allocator, "{\"choice\":{\"absent\":{}},\"label\":\"sample\"}", .{ .maximum_depth = 8 });
    for ([_][]const u8{
        "{\"choice\":{\"count\":\"3\"},\"label\":\"sample\"}",
        "{\"choice\":{\"count\":3,\"absent\":null},\"label\":\"sample\"}",
        "{\"choice\":{\"count\":3,\"count\":4},\"label\":\"sample\"}",
        "{\"choice\":{\"foreign\":3},\"label\":\"sample\"}",
        "{\"choice\":{\"absent\":false},\"label\":\"sample\"}",
        "{\"choice\":{\"absent\":null},\"label\":\"sample\"}",
        "{\"choice\":{\"count\":3},\"label\":[65]}",
        "{\"choice\":{\"count\":3}}",
    }) |bytes| try testing.expectError(error.InvalidJsonDocument, json.decode(Shape, allocator, bytes, .{ .maximum_depth = 8 }));
    try testing.expectError(error.InvalidJsonDocument, decodeProposal(allocator, "{}"));
}

test "optional collections may be empty and presence cannot prove entity applicability" {
    var document: spec.CapturedDocument = .{
        .display_name = .{ .bytes = "A small application" },
        .primary_user_story = .{ .bytes = "A person starts the application." },
        .records = &.{},
        .entity_section = .omitted,
    };
    try spec.validateDocument(document, true);
    document.entity_section = .present;
    try spec.validateDocument(document, true);
    document.display_name.bytes = " \n";
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
}

test "shape validation checks all record families without asserting their meaning" {
    const value: spec.Scalar = .{ .bytes = "Business content" };
    var records = [_]spec.CapturedRecord{
        .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = value, .when = value, .then = value } } },
        .{ .id = .{ .kind = .user_visible_outcome, .ordinal = 1 }, .content = .{ .user_visible_outcome = .{ .text = value } } },
        .{ .id = .{ .kind = .edge_case, .ordinal = 1 }, .content = .{ .edge_case = .{ .condition = value } }, .outcome = value },
        .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .content = .{ .functional_requirement = .{ .text = value } } },
        .{ .id = .{ .kind = .business_rule, .ordinal = 1 }, .content = .{ .business_rule = .{ .text = value } } },
        .{ .id = .{ .kind = .assumption, .ordinal = 1 }, .content = .{ .assumption = .{ .text = value } } },
        .{ .id = .{ .kind = .non_goal, .ordinal = 1 }, .content = .{ .non_goal = .{ .text = value } } },
        .{ .id = .{ .kind = .prohibited_behavior, .ordinal = 1 }, .content = .{ .prohibited_behavior = .{ .text = value } } },
        .{ .id = .{ .kind = .entity, .ordinal = 1 }, .content = .{ .entity = .{ .name = value } } },
    };
    var document: spec.CapturedDocument = .{ .display_name = value, .primary_user_story = value, .records = &records, .entity_section = .present };
    try spec.validateDocument(document, true);
    document.entity_section = .omitted;
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
    document.entity_section = .present;
    records[0].content.acceptance_criterion.then.bytes = "";
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
    records[0].content.acceptance_criterion.then = value;
    records[0].id = null;
    try spec.validateDocument(document, false);
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
    records[0].id = .{ .kind = .functional_requirement, .ordinal = 1 };
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
}

test "closed specification parsing cleans up every allocation failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(parseAllocated, .{});
}

test "editable specification round-trips every family and exact spans with allocation cleanup" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(roundTrip, .{});
}

fn roundTrip(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain: spec.Scalar = .{ .bytes = "A user sees *literal* [text](not-a-link).\nNext line." };
    const exact: spec.Scalar = .{ .bytes = "Display `a`\n b", .code_spans = &.{.{ .start = 8, .end = 14 }} };
    // Exercise every closed family; the same codec is not tied to Hello World.
    var records: [9]spec.CapturedRecord = undefined;
    inline for (comptime std.meta.tags(spec.Kind), 0..) |kind, index| {
        const Body = @FieldType(spec.Content(spec.Scalar), @tagName(kind));
        var body: Body = undefined;
        inline for (@typeInfo(Body).@"struct".fields) |f| @field(body, f.name) = plain;
        records[index] = .{ .id = .{ .kind = kind, .ordinal = 1001 }, .content = @unionInit(spec.Content(spec.Scalar), @tagName(kind), body), .outcome = if (kind.showsOutcome()) plain else null };
    }
    records[3].content.functional_requirement.text = exact;
    records[8].related = &.{ .{ .kind = .user_visible_outcome, .ordinal = 1001 }, .{ .kind = .functional_requirement, .ordinal = 1001 }, .{ .kind = .prohibited_behavior, .ordinal = 1001 } };
    const document: spec.CapturedDocument = .{ .display_name = .{ .bytes = "A café" }, .primary_user_story = plain, .records = &records, .entity_section = .present };
    const rendered = try markdown.render(a, document);
    try testing.expect(std.mem.indexOf(u8, rendered, "## User Scenarios & Testing _(mandatory)_\n") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "\n### Acceptance Criteria\n") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "**EN-1001**\n- **NAME** A user sees \\*literal\\* \\[text\\](not-a-link).&#10;Next line.\n- **RELATED STATEMENTS** UO-1001, FR-1001, PB-1001\n") != null);
    try testing.expect(std.mem.endsWith(u8, rendered, "\n") and !std.mem.endsWith(u8, rendered, "\n\n"));
    const parsed = try markdown.parse(a, rendered);
    try testing.expectEqualDeep(document, parsed);
    try testing.expectEqualStrings(rendered, try markdown.render(a, parsed));
}

test "source lines follow criteria requirements and entities and accept only the renderer's grammar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const scalar: spec.Scalar = .{ .bytes = "Business content" };
    // A multiline exact span continues its field on two-space lines; the source line
    // after the blank line is never read as that continuation.
    const exact: spec.Scalar = .{ .bytes = "Display `a`\n b", .code_spans = &.{.{ .start = 8, .end = 14 }} };
    const records = [_]spec.CapturedRecord{
        .{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = scalar, .when = scalar, .then = scalar } }, .sources = &.{.{ .path = "references/a.md", .ranges = &.{.{ .first = 5, .last = 7 }} }} },
        .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .content = .{ .functional_requirement = .{ .text = exact } }, .sources = &.{
            .{ .path = "references/a.md", .ranges = &.{ .{ .first = 3, .last = 4 }, .{ .first = 9, .last = 9 } } },
            .{ .path = "references/odd`name.md", .ranges = &.{.{ .first = 9, .last = 9 }} },
        } },
        .{ .id = .{ .kind = .business_rule, .ordinal = 1 }, .content = .{ .business_rule = .{ .text = scalar } } },
        .{ .id = .{ .kind = .entity, .ordinal = 1 }, .content = .{ .entity = .{ .name = scalar } }, .sources = &.{.{ .path = "references/a.md", .ranges = &.{.{ .first = 2, .last = 2 }} }}, .related = &.{ .{ .kind = .functional_requirement, .ordinal = 1 }, .{ .kind = .business_rule, .ordinal = 1 } } },
    };
    const document: spec.CapturedDocument = .{ .display_name = scalar, .primary_user_story = scalar, .records = &records, .entity_section = .present };
    const rendered = try markdown.render(a, document);
    for ([_][]const u8{
        "**Then** Business content\n\n  - Source: `references/a.md` lines 5–7\n\n",
        "- **FR-001**: Display `` `a`\n   b ``\n\n  - Source: `references/a.md` lines 3–4, 9; ``references/odd`name.md`` line 9\n\n",
        "- **BR-001**: Business content\n\n### Key",
        "- **NAME** Business content\n- **RELATED STATEMENTS** FR-001, BR-001\n- Source: `references/a.md` line 2\n",
    }) |expected| try testing.expect(std.mem.indexOf(u8, rendered, expected) != null);
    try testing.expectEqualDeep(document, try markdown.parse(a, rendered));
    try testing.expectEqualStrings(rendered, try markdown.render(a, try markdown.parse(a, rendered)));

    // One rejected drift per clause of the source-line grammar: range punctuation, range
    // order, path form, label, file joiner, line against lines, ranges that touch, and a line
    // on a record that shows none.
    inline for (.{
        .{ "lines 5–7", "lines 5-7" },
        .{ "lines 5–7", "lines 7–5" },
        .{ "`references/a.md` lines 5–7", "references/a.md lines 5–7" },
        .{ "  - Source: `references/a.md` lines 5–7", "  - Sources: `references/a.md` lines 5–7" },
        .{ "9; ``references/odd`name.md``", "9, ``references/odd`name.md``" },
        .{ "lines 3–4, 9;", "lines 3–4, 5;" },
        .{ "`references/a.md` line 2", "`references/a.md` lines 2" },
        .{ "- **BR-001**: Business content\n", "- **BR-001**: Business content\n\n  - Source: `references/a.md` line 1\n" },
    }) |mutation| {
        const changed = try std.mem.replaceOwned(u8, a, rendered, mutation[0], mutation[1]);
        try testing.expect(!std.mem.eql(u8, changed, rendered));
        try testing.expectError(error.InvalidSpecification, markdown.parse(a, changed));
    }
    // Directly under its field, a two-space line is that field's continuation, so a
    // source line written there doesn't round-trip.
    inline for (.{
        .{ "Business content\n\n  - Source: `references/a.md` lines 5–7", "Business content\n  - Source: `references/a.md` lines 5–7" },
        .{ "- Source: `references/a.md` line 2", "  - Source: `references/a.md` line 2" },
    }) |mutation| {
        const tight = try std.mem.replaceOwned(u8, a, rendered, mutation[0], mutation[1]);
        try testing.expect(!std.mem.eql(u8, tight, rendered));
        if (markdown.parse(a, tight)) |parsed| {
            try testing.expect(!std.mem.eql(u8, tight, try markdown.render(a, parsed)));
        } else |err| try testing.expectEqual(error.InvalidSpecification, err);
    }
    // Only criterion, requirement and entity records carry source lines.
    var foreign = records;
    foreign[2].sources = records[0].sources;
    try testing.expectError(error.InvalidSpecification, markdown.render(a, .{ .display_name = scalar, .primary_user_story = scalar, .records = &foreign, .entity_section = .present }));
    // A file appears once and its ranges ascend without touching, so one lineage has one display.
    inline for (.{
        &[_]spec.SourceLines{.{ .path = "references/a.md", .ranges = &.{ .{ .first = 3, .last = 4 }, .{ .first = 5, .last = 6 } } }},
        &[_]spec.SourceLines{ .{ .path = "references/a.md", .ranges = &.{.{ .first = 3, .last = 4 }} }, .{ .path = "references/a.md", .ranges = &.{.{ .first = 9, .last = 9 }} } },
    }) |files| {
        var drifted = records;
        drifted[1].sources = files;
        try testing.expectError(error.InvalidSpecification, markdown.render(a, .{ .display_name = scalar, .primary_user_story = scalar, .records = &drifted, .entity_section = .present }));
    }
}

// The derivation is the logic worth testing: the rendered line is always the projection's
// own output, so only a wrong derivation could publish a wrong line.
test "an entity lists the statements that share one of its source groups, in document order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Signal = @import("domain/reference_reconciliation.zig").SignalId;
    const first: []const Signal = &.{.{ .ordinal = 1 }};
    const second: []const Signal = &.{.{ .ordinal = 2 }};
    const records = [_]spec.IdentifiedRecord{
        statementRecord(.acceptance_criterion, 1, first),
        statementRecord(.user_visible_outcome, 1, second),
        statementRecord(.functional_requirement, 1, first),
        statementRecord(.functional_requirement, 2, second),
        statementRecord(.business_rule, 1, first),
        statementRecord(.assumption, 1, first),
        statementRecord(.entity, 1, first),
        statementRecord(.entity, 2, second),
    };
    const projection = @import("domain/specification_projection.zig");
    const id = struct {
        fn of(kind: spec.Kind, ordinal: u32) spec.Id {
            return .{ .kind = kind, .ordinal = ordinal };
        }
    }.of;
    // One group: its statements only. A scenario, a scope statement and an entity of the
    // same group are not statements, and a statement of another group is not related.
    try testing.expectEqualDeep(&[_]spec.Id{ id(.functional_requirement, 1), id(.business_rule, 1) }, try projection.relatedStatements(a, &records, records[6].proposal));
    try testing.expectEqualDeep(&[_]spec.Id{ id(.user_visible_outcome, 1), id(.functional_requirement, 2) }, try projection.relatedStatements(a, &records, records[7].proposal));
    // Several groups: every statement of each, once, in document order.
    var both = records[6].proposal;
    both.source_group_ids = &.{ .{ .ordinal = 2 }, .{ .ordinal = 1 } };
    try testing.expectEqualDeep(&[_]spec.Id{ id(.user_visible_outcome, 1), id(.functional_requirement, 1), id(.functional_requirement, 2), id(.business_rule, 1) }, try projection.relatedStatements(a, &records, both));
    // No shared group: no line.
    var alone = records[6].proposal;
    alone.source_group_ids = &.{.{ .ordinal = 3 }};
    try testing.expectEqual(@as(usize, 0), (try projection.relatedStatements(a, &records, alone)).len);
}

fn statementRecord(comptime kind: spec.Kind, ordinal: u32, groups: []const @import("domain/reference_reconciliation.zig").SignalId) spec.IdentifiedRecord {
    const value: spec.BusinessValue = .{ .segments = &.{.{ .literal = .{ .value = "Business content" } }} };
    var body: @FieldType(spec.Content(spec.BusinessValue), @tagName(kind)) = undefined;
    inline for (@typeInfo(@TypeOf(body)).@"struct".fields) |field| @field(body, field.name) = value;
    return .{ .id = .{ .kind = kind, .ordinal = ordinal }, .proposal = .{
        .content = @unionInit(spec.Content(spec.BusinessValue), @tagName(kind), body),
        .source_group_ids = groups,
        .provenance = .{ .claim_ids = &.{}, .citation_ids = &.{}, .clarification_response_ids = &.{} },
    } };
}

test "editable grammar rejects structural drift but permits an unnumbered new record" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const scalar: spec.Scalar = .{ .bytes = "Business content" };
    const document: spec.CapturedDocument = .{
        .display_name = scalar,
        .primary_user_story = scalar,
        .records = &.{.{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = scalar, .when = scalar, .then = scalar } } }},
        .entity_section = .omitted,
    };
    const rendered = try markdown.render(a, document);
    inline for (.{
        .{ "### Acceptance Criteria", "## Acceptance Criteria" },
        .{ "**Given**", "**GIVEN**" },
        .{ "**AC-001**", "**AC-000**" },
        .{ "**AC-001**", "**OQ-001**" },
    }) |mutation| {
        const changed = try std.mem.replaceOwned(u8, a, rendered, mutation[0], mutation[1]);
        try testing.expectError(error.InvalidSpecification, markdown.parse(a, changed));
    }
    const extra = try std.mem.concat(a, u8, &.{ rendered, "\n### Open Questions\n\nA question\n" });
    try testing.expectError(error.InvalidSpecification, markdown.parse(a, extra));
    const added = try std.mem.replaceOwned(u8, a, rendered, "**AC-001**", "**AC**");
    const captured = try markdown.parse(a, added);
    try testing.expect(captured.records[0].id == null);
    try testing.expectError(error.InvalidSpecification, markdown.render(a, captured));
}

test "editable grammar has no review status line after post-generation review removal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const scalar: spec.Scalar = .{ .bytes = "Business content" };
    const document: spec.CapturedDocument = .{
        .display_name = scalar,
        .primary_user_story = scalar,
        .records = &.{.{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = scalar, .when = scalar, .then = scalar } } }},
        .entity_section = .omitted,
    };
    const rendered = try markdown.render(a, document);
    try testing.expect(std.mem.indexOf(u8, rendered, "Review status") == null);
    try testing.expectEqualDeep(document, try markdown.parse(a, rendered));
    // The retired engine status line is not editable grammar: a document that
    // still carries it under the title is rejected rather than silently dropped.
    const retired = try std.mem.replaceOwned(u8, a, rendered, "\n\n## User Scenarios", "\n\n**Review status: Incomplete — 3 of 12 review subjects were not assessed.** See reference-context.md for what was not assessed and why.\n\n## User Scenarios");
    try testing.expect(!std.mem.eql(u8, retired, rendered));
    try testing.expectError(error.InvalidSpecification, markdown.parse(a, retired));
}

test "display escaping preserves whitespace Unicode delimiters and inert path spelling" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "`", "a``b", " two ", "  ", "part\nnext", "e\xcc\x81", "https://example.invalid/a", "src/sample.zig" }) |copy| {
        const bytes = try std.mem.concat(a, u8, &.{ "Copy ", copy, "." });
        const scalar: spec.Scalar = .{ .bytes = bytes, .code_spans = &.{.{ .start = 5, .end = 5 + copy.len }} };
        const document: spec.CapturedDocument = .{
            .display_name = .{ .bytes = "Small feature" },
            .primary_user_story = scalar,
            .records = &.{},
            .entity_section = .omitted,
        };
        try testing.expectEqualDeep(document, try markdown.parse(a, try markdown.render(a, document)));
    }
}

test "duplicate identities and invalid display spans cannot render" {
    const scalar: spec.Scalar = .{ .bytes = "Business text" };
    const record: spec.CapturedRecord = .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .content = .{ .functional_requirement = .{ .text = scalar } } };
    var document: spec.CapturedDocument = .{ .display_name = scalar, .primary_user_story = scalar, .records = &.{ record, record }, .entity_section = .omitted };
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
    document.records = &.{};
    document.display_name.code_spans = &.{.{ .start = 2, .end = 99 }};
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
    document.display_name = .{ .bytes = "ab", .code_spans = &.{ .{ .start = 0, .end = 1 }, .{ .start = 1, .end = 2 } } };
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
    document.display_name = .{ .bytes = "bad\x00value" };
    try testing.expectError(error.InvalidSpecification, spec.validateDocument(document, true));
}

test "every optional-section combination round trips without empty headings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value: spec.Scalar = .{ .bytes = "Supported business behavior" };
    const optional = [_]spec.Kind{ .user_visible_outcome, .edge_case, .business_rule, .assumption, .non_goal, .prohibited_behavior, .entity };
    for (0..1 << optional.len) |mask| {
        var records: std.ArrayList(spec.CapturedRecord) = .empty;
        inline for (comptime std.meta.tags(spec.Kind)) |kind| {
            const include = spec.requiresRecords(kind) or mask & (@as(usize, 1) << @intCast(std.mem.indexOfScalar(spec.Kind, &optional, kind).?)) != 0;
            if (include) {
                var body: @FieldType(spec.Content(spec.Scalar), @tagName(kind)) = undefined;
                inline for (@typeInfo(@TypeOf(body)).@"struct".fields) |field| @field(body, field.name) = value;
                try records.append(a, .{ .id = .{ .kind = kind, .ordinal = 1 }, .content = @unionInit(spec.Content(spec.Scalar), @tagName(kind), body), .outcome = if (kind.showsOutcome()) value else null });
            }
        }
        const document: spec.CapturedDocument = .{ .display_name = value, .primary_user_story = value, .records = records.items, .entity_section = if (mask & 64 != 0) .present else .omitted };
        const bytes = try markdown.render(a, document);
        try testing.expect(std.mem.startsWith(u8, bytes, "# Feature Specification: "));
        try testing.expectEqualDeep(document, try markdown.parse(a, bytes));
        for (optional, 0..) |kind, bit| try testing.expectEqual(mask & (@as(usize, 1) << @intCast(bit)) != 0, std.mem.indexOf(u8, bytes, kind.heading()) != null);
        try testing.expectEqual(mask & (8 | 16 | 32) != 0, std.mem.indexOf(u8, bytes, "### Assumptions & Scope Boundaries") != null);
    }
}

test "compact acceptance criteria preserve exact label text and reject malformed triplets" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const copy = "literal, **When** token\nwith **Then** and `quotes`";
    const value: spec.Scalar = .{ .bytes = copy, .code_spans = &.{.{ .start = 0, .end = copy.len }} };
    const plain: spec.Scalar = .{ .bytes = "an action occurs" };
    const document: spec.CapturedDocument = .{ .display_name = plain, .primary_user_story = plain, .entity_section = .omitted, .records = &.{.{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = value, .when = plain, .then = value } } }} };
    try testing.expectEqualDeep(document, try markdown.parse(a, try markdown.render(a, document)));
    const start = "# Feature Specification: Example\n\n## User Scenarios & Testing _(mandatory)_\n\n### Primary User Story\n\nA person acts.\n\n### Acceptance Criteria\n\n";
    const end = "\n\n## Requirements _(mandatory)_\n\n### Functional Requirements\n";
    for ([_][]const u8{
        "- **AC-001**: **Given** state, **When** action, **Then** result, **Given** extra",
        "- **AC-001**: **Given** state, **When** action **When** extra, **Then** result",
        "- **AC-001**: **Given** state, **Then** result, **When** action",
        "- **AC-001**: **Given** , **When** action, **Then** result",
        "- **AC-001**: **Given** state, **When** action, **Then** ",
        "- **AC-001**: **Given** state, **When** action",
        "**AC-001**\n- **GIVEN** state\n- **WHEN** action\n- **THEN** result",
    }) |record| try testing.expectError(error.InvalidSpecification, markdown.parse(a, try std.mem.concat(a, u8, &.{ start, record, end })));
    const valid = try std.mem.concat(a, u8, &.{ start, "- **AC-001**: **Given** state, **When** action, **Then** result", end });
    for ([_][]const u8{ "## User Scenarios & Testing _(mandatory)_\n", "### Acceptance Criteria\n", "## Requirements _(mandatory)_\n", "### Functional Requirements\n" }) |required| try testing.expectError(error.InvalidSpecification, markdown.parse(a, try std.mem.replaceOwned(u8, a, valid, required, "")));
    for ([_][]const u8{ "\n### Business Rules\n", "\n### Assumptions & Scope Boundaries\n", "\n#### Explicit Non-Goals\n\n- **NG-001**: An excluded behavior.\n" }) |extra| try testing.expectError(error.InvalidSpecification, markdown.parse(a, try std.mem.concat(a, u8, &.{ valid, extra })));
}

test "acceptance clauses that end a sentence join without a comma and keep their bytes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const prose = "The system displays ";
    const exact = "Renewal refused.";
    const refused: spec.Scalar = .{ .bytes = prose ++ exact, .code_spans = &.{.{ .start = prose.len, .end = prose.len + exact.len }} };
    const plain: spec.Scalar = .{ .bytes = "the loan is active" };
    const cases = [_]struct { given: spec.Scalar, when: spec.Scalar, joins: []const []const u8 }{
        .{ .given = .{ .bytes = "The loan is active." }, .when = plain, .joins = &.{ "active. **When** ", "active, **Then** " } },
        .{ .given = plain, .when = .{ .bytes = "The borrower asks!" }, .joins = &.{ "active, **When** ", "asks! **Then** " } },
        .{ .given = plain, .when = .{ .bytes = "Is the loan due?" }, .joins = &.{ "active, **When** ", "due? **Then** " } },
        .{ .given = refused, .when = plain, .joins = &.{ "`Renewal refused.` **When** ", "active, **Then** " } },
        // The shared terminal policy covers non-ASCII sentence ends and a closing comma.
        .{ .given = .{ .bytes = "The loan is active\u{2026}" }, .when = plain, .joins = &.{ "active\u{2026} **When** ", "active, **Then** " } },
        .{ .given = plain, .when = .{ .bytes = "\u{8cb8}\u{51fa}\u{4e2d}\u{3002}" }, .joins = &.{ "active, **When** ", "\u{3002} **Then** " } },
        .{ .given = .{ .bytes = "the loan is active," }, .when = plain, .joins = &.{ "active\\, **When** ", "active, **Then** " } },
        // A clause ending in a literal backslash keeps the real ", " separator on readback.
        .{ .given = .{ .bytes = "the path ends in \\" }, .when = plain, .joins = &.{ "in \\\\, **When** ", "active, **Then** " } },
        // A literal backslash then a comma ends in an escaped comma: an odd run, one space.
        .{ .given = .{ .bytes = "the path ends in \\," }, .when = plain, .joins = &.{ "in \\\\\\, **When** ", "active, **Then** " } },
    };
    for (cases) |case| {
        const document: spec.CapturedDocument = .{ .display_name = plain, .primary_user_story = plain, .entity_section = .omitted, .records = &.{.{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = case.given, .when = case.when, .then = refused } } }} };
        const rendered = try markdown.render(a, document);
        for (case.joins) |join| try testing.expect(std.mem.indexOf(u8, rendered, join) != null);
        for ([_][]const u8{ "., **", "!, **", "?, **", ".`, **", "\\,, **", "\u{2026}, **", "\u{3002}, **" }) |doubled| try testing.expect(std.mem.indexOf(u8, rendered, doubled) == null);
        const parsed = try markdown.parse(a, rendered);
        try testing.expectEqualDeep(document, parsed);
        try testing.expectEqualStrings(rendered, try markdown.render(a, parsed));
        try testing.expectEqualStrings(rendered, try markdown.render(a, document));
        try testing.expectEqualStrings(prose ++ exact, parsed.records[0].content.acceptance_criterion.then.bytes);
    }
    const document: spec.CapturedDocument = .{ .display_name = plain, .primary_user_story = plain, .entity_section = .omitted, .records = &.{.{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = .{ .bytes = "The loan is active." }, .when = plain, .then = refused } } }} };
    const rendered = try markdown.render(a, document);
    inline for (.{
        .{ "active. **When** ", "active., **When** " },
        .{ "active, **Then** ", "active **Then** " },
        .{ "**Given** The loan is active. **When** ", "**Given** **When** " },
    }) |mutation| {
        const changed = try std.mem.replaceOwned(u8, a, rendered, mutation[0], mutation[1]);
        try testing.expect(!std.mem.eql(u8, changed, rendered));
        try testing.expectError(error.InvalidSpecification, markdown.parse(a, changed));
    }
    // Renderings from before the shared terminal policy doubled a clause's own comma,
    // semicolon, colon or ellipsis; readback now rejects that separator.
    for ([_][2][]const u8{ .{ "the loan is active,", "active\\," }, .{ "the loan is active;", "active;" }, .{ "the loan is active:", "active:" }, .{ "the loan is active\u{2026}", "active\u{2026}" } }) |ending| {
        const ended: spec.CapturedDocument = .{ .display_name = plain, .primary_user_story = plain, .entity_section = .omitted, .records = &.{.{ .id = .{ .kind = .acceptance_criterion, .ordinal = 1 }, .content = .{ .acceptance_criterion = .{ .given = .{ .bytes = ending[0] }, .when = plain, .then = refused } } }} };
        const current = try markdown.render(a, ended);
        const changed = try std.mem.replaceOwned(u8, a, current, try std.mem.concat(a, u8, &.{ ending[1], " **When** " }), try std.mem.concat(a, u8, &.{ ending[1], ", **When** " }));
        try testing.expect(!std.mem.eql(u8, changed, current));
        try testing.expectError(error.InvalidSpecification, markdown.parse(a, changed));
    }
}

test "only bytes Markdown reads as markup are escaped, and every punctuation byte reads back" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const markup = "\\`*_~[]<>&";
    for (0..128) |code| {
        const byte: u8 = @intCast(code);
        if (!std.ascii.isPunctuation(byte)) continue;
        const bytes = try std.fmt.allocPrint(a, "a{c}b", .{byte});
        var out: std.Io.Writer.Allocating = .init(a);
        try markdown.literal(&out.writer, bytes, .inline_text);
        const expected = if (std.mem.indexOfScalar(u8, markup, byte) != null) try std.fmt.allocPrint(a, "a\\{c}b", .{byte}) else bytes;
        try testing.expectEqualStrings(expected, out.written());
        const value: spec.Scalar = .{ .bytes = bytes };
        const document: spec.CapturedDocument = .{ .display_name = value, .primary_user_story = value, .records = &.{}, .entity_section = .omitted };
        try testing.expectEqualDeep(document, try markdown.parse(a, try markdown.render(a, document)));
    }
    // As the first text of a block line only, a byte that opens a heading or a list is escaped.
    for ([_][2][]const u8{
        .{ "# Heading", "\\# Heading" },
        .{ "- item", "\\- item" },
        .{ "+ item", "\\+ item" },
        .{ "12. item", "12\\. item" },
        .{ "3) item", "3\\) item" },
        .{ "Item 3. next - a # b", "Item 3. next - a # b" },
    }) |case| {
        var out: std.Io.Writer.Allocating = .init(a);
        try markdown.literal(&out.writer, case[0], .block_start);
        try testing.expectEqualStrings(case[1], out.written());
        var inline_out: std.Io.Writer.Allocating = .init(a);
        try markdown.literal(&inline_out.writer, case[0], .inline_text);
        try testing.expectEqualStrings(case[0], inline_out.written());
        // The rendered story is the block-start text, not the inline one.
        const story: spec.Scalar = .{ .bytes = case[0] };
        const document: spec.CapturedDocument = .{ .display_name = .{ .bytes = "A" }, .primary_user_story = story, .records = &.{}, .entity_section = .omitted };
        const rendered = try markdown.render(a, document);
        try testing.expect(std.mem.indexOf(u8, rendered, try std.mem.concat(a, u8, &.{ "\n\n", case[1], "\n\n" })) != null);
        try testing.expectEqualDeep(document, try markdown.parse(a, rendered));
    }
    // A heading ends at a closing run of `#` that follows a space and is followed by spaces
    // only, so only that run is escaped; a run after an exact span has no space before it.
    const spanned: spec.Scalar = .{ .bytes = "x#", .code_spans = &.{.{ .start = 0, .end = 1 }} };
    for ([_]struct { title: spec.Scalar, expected: []const u8 }{
        .{ .title = .{ .bytes = "Sprint #" }, .expected = "Sprint \\#" },
        .{ .title = .{ .bytes = "Sprint ##" }, .expected = "Sprint \\#\\#" },
        .{ .title = .{ .bytes = "Sprint # " }, .expected = "Sprint \\# " },
        .{ .title = .{ .bytes = "#" }, .expected = "\\#" },
        .{ .title = .{ .bytes = "Sprint # 2" }, .expected = "Sprint # 2" },
        .{ .title = .{ .bytes = "C#" }, .expected = "C#" },
        .{ .title = spanned, .expected = "`x`#" },
    }) |case| {
        const document: spec.CapturedDocument = .{ .display_name = case.title, .primary_user_story = .{ .bytes = "A" }, .records = &.{}, .entity_section = .omitted };
        const rendered = try markdown.render(a, document);
        try testing.expect(std.mem.startsWith(u8, rendered, try std.mem.concat(a, u8, &.{ "# Feature Specification: ", case.expected, "\n\n" })));
        try testing.expectEqualDeep(document, try markdown.parse(a, rendered));
    }
    // The reader accepts a backslash before any ASCII punctuation, so text that escapes a byte
    // the renderer does not reads back to the same value and re-renders differently, which
    // publication's byte comparison rejects.
    const plain: spec.Scalar = .{ .bytes = "The loan is renewed." };
    const prose: spec.CapturedDocument = .{ .display_name = .{ .bytes = "A" }, .primary_user_story = plain, .records = &.{}, .entity_section = .omitted };
    const canonical = try markdown.render(a, prose);
    const over_escaped = try std.mem.replaceOwned(u8, a, canonical, "renewed.", "renewed\\.");
    try testing.expect(!std.mem.eql(u8, over_escaped, canonical));
    const read = try markdown.parse(a, over_escaped);
    try testing.expectEqualDeep(prose, read);
    try testing.expect(!std.mem.eql(u8, over_escaped, try markdown.render(a, read)));
}

fn parseAllocated(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), proposal(), .{});
    _ = try decodeProposal(arena.allocator(), bytes);
}

/// The closed content proposal decoded strictly at the model-result depth limit.
fn decodeProposal(allocator: std.mem.Allocator, bytes: []const u8) !spec.ContentProposal {
    return json.decode(spec.ContentProposal, allocator, bytes, .{ .maximum_depth = @import("domain/model_result_schema.zig").max_json_depth });
}

fn proposal() spec.ContentProposal {
    const value: spec.AttributedValue = .{
        .value = .{ .segments = &.{.{ .literal = .{ .value = "Reference-grounded content" } }} },
        .source_group_ids = &.{.{ .ordinal = 1 }},
        .provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .citation_ids = &.{.{ .ordinal = 1 }}, .clarification_response_ids = &.{} },
    };
    return .{ .display_name = value, .primary_user_story = value, .records = &.{}, .entities = .{ .disposition = .not_applicable, .basis = value } };
}
