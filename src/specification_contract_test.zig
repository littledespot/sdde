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
    const decoded = try spec.parseProposal(allocator, bytes);
    try testing.expectEqual(@as(usize, 0), decoded.records.len);
    try testing.expectEqual(.not_applicable, decoded.entities.disposition);
    try testing.expect(!@hasField(spec.RecordProposal, "id"));
    try testing.expect(!@hasField(@FieldType(spec.Content(spec.BusinessValue), "functional_requirement"), "modality"));
    for ([_][]const u8{ "id", "modality", "open_questions", "path", "completed" }) |foreign| {
        const changed = try std.fmt.allocPrint(allocator, "{{\"{s}\":true,{s}", .{ foreign, bytes[1..] });
        try testing.expectError(error.InvalidSpecification, spec.parseProposal(allocator, changed));
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
    try testing.expectError(error.InvalidSpecification, spec.parseProposal(allocator, "{}"));
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
        .{ .id = .{ .kind = .edge_case, .ordinal = 1 }, .content = .{ .edge_case = .{ .condition = value, .expected_outcome = value } } },
        .{ .id = .{ .kind = .functional_requirement, .ordinal = 1 }, .content = .{ .functional_requirement = .{ .text = value } } },
        .{ .id = .{ .kind = .business_rule, .ordinal = 1 }, .content = .{ .business_rule = .{ .text = value } } },
        .{ .id = .{ .kind = .assumption, .ordinal = 1 }, .content = .{ .assumption = .{ .text = value } } },
        .{ .id = .{ .kind = .non_goal, .ordinal = 1 }, .content = .{ .non_goal = .{ .text = value } } },
        .{ .id = .{ .kind = .prohibited_behavior, .ordinal = 1 }, .content = .{ .prohibited_behavior = .{ .text = value } } },
        .{ .id = .{ .kind = .entity, .ordinal = 1 }, .content = .{ .entity = .{ .name = value, .business_meaning = value, .relationships = &.{} } } },
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
    try testing.checkAllAllocationFailures(testing.allocator, parseAllocated, .{});
}

test "editable specification round-trips every record family and exact code spans" {
    try roundTrip(testing.allocator);
}

test "specification codec cleans up every allocation failure" {
    try testing.checkAllAllocationFailures(testing.allocator, roundTrip, .{});
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
        inline for (@typeInfo(Body).@"struct".fields) |f| {
            if (comptime f.type == spec.Scalar) @field(body, f.name) = plain else @field(body, f.name) = &.{plain};
        }
        records[index] = .{ .id = .{ .kind = kind, .ordinal = 1001 }, .content = @unionInit(spec.Content(spec.Scalar), @tagName(kind), body) };
    }
    records[3].content.functional_requirement.text = exact;
    const document: spec.CapturedDocument = .{ .display_name = .{ .bytes = "A café" }, .primary_user_story = plain, .records = &records, .entity_section = .present };
    const rendered = try markdown.render(a, document);
    try testing.expect(std.mem.indexOf(u8, rendered, "## User Scenarios & Testing _(mandatory)_\n") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "\n### Acceptance Criteria\n") != null);
    try testing.expect(std.mem.indexOf(u8, rendered, "**EN-1001**") != null);
    try testing.expect(std.mem.endsWith(u8, rendered, "\n") and !std.mem.endsWith(u8, rendered, "\n\n"));
    const parsed = try markdown.parse(a, rendered);
    try testing.expectEqualDeep(document, parsed);
    try testing.expectEqualStrings(rendered, try markdown.render(a, parsed));
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
        .{ "**When**", "**Given**" },
        .{ "**Then**", "**FOREIGN**" },
        .{ "**AC-001**", "**AC-000**" },
        .{ "**AC-001**", "**AC-01**" },
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
                inline for (@typeInfo(@TypeOf(body)).@"struct".fields) |field| @field(body, field.name) = if (field.type == spec.Scalar) value else &.{value};
                try records.append(a, .{ .id = .{ .kind = kind, .ordinal = 1 }, .content = @unionInit(spec.Content(spec.Scalar), @tagName(kind), body) });
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
        "**AC-001**\n- **GIVEN** state\n- **WHEN** action\n- **THEN** result",
    }) |record| try testing.expectError(error.InvalidSpecification, markdown.parse(a, try std.mem.concat(a, u8, &.{ start, record, end })));
    const valid = try std.mem.concat(a, u8, &.{ start, "- **AC-001**: **Given** state, **When** action, **Then** result", end });
    for ([_][]const u8{ "## User Scenarios & Testing _(mandatory)_\n", "### Acceptance Criteria\n", "## Requirements _(mandatory)_\n", "### Functional Requirements\n" }) |required| try testing.expectError(error.InvalidSpecification, markdown.parse(a, try std.mem.replaceOwned(u8, a, valid, required, "")));
    for ([_][]const u8{ "\n### Business Rules\n", "\n### Assumptions & Scope Boundaries\n", "\n#### Explicit Non-Goals\n\n- **NG-001**: An excluded behavior.\n" }) |extra| try testing.expectError(error.InvalidSpecification, markdown.parse(a, try std.mem.concat(a, u8, &.{ valid, extra })));
}

fn parseAllocated(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const bytes = try std.json.Stringify.valueAlloc(arena.allocator(), proposal(), .{});
    _ = try spec.parseProposal(arena.allocator(), bytes);
}

fn proposal() spec.ContentProposal {
    const value: spec.AttributedValue = .{
        .value = .{ .normalized = .{ .segments = &.{.{ .literal = .{ .value = "Reference-grounded content" } }} } },
        .provenance = .{ .claim_ids = &.{.{ .ordinal = 1 }}, .citation_ids = &.{.{ .ordinal = 1 }}, .clarification_response_ids = &.{} },
    };
    return .{ .display_name = value, .primary_user_story = value, .records = &.{}, .entities = .{ .disposition = .not_applicable, .basis = value } };
}
