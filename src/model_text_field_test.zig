const std = @import("std");
const fields = @import("domain/model_text_field.zig");
const policy = @import("domain/text_field_policy.zig");
const codec = @import("domain/model_candidate_json.zig");
const schema = @import("domain/model_result_schema.zig");
const payload = @import("domain/model_payload_schema.zig");

const all_insertions =
    \\{"type":"object","properties":{"value":{"oneOf":[{"type":"string","minLength":1,"maxLength":4096},{"type":"object","properties":{"fragments":{"type":"array","minItems":1,"maxItems":32,"items":{"oneOf":[{"type":"string","minLength":1,"maxLength":4096},{"type":"object","properties":{"kind":{"const":"exact_copy"},"claim_id":{"type":"integer","minimum":1,"maximum":100}},"required":["kind","claim_id"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"passive"},"passive_literal_id":{"type":"integer","minimum":1,"maximum":100}},"required":["kind","passive_literal_id"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"source"},"source_id":{"type":"integer","minimum":1,"maximum":100}},"required":["kind","source_id"],"additionalProperties":false}]}}},"required":["fragments"],"additionalProperties":false}]}},"required":["value"],"additionalProperties":false}
;
fn compile(a: std.mem.Allocator, bytes: []const u8) !*const schema.Schema {
    var adapter: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    return adapter.compiler().compile(a, bytes);
}
fn accepted(a: std.mem.Allocator, selected: *const schema.Schema, bytes: []const u8) !bool {
    const value = try @import("domain/strict_json.zig").parse(a, bytes, .{ .maximum_depth = schema.max_json_depth }, false, null);
    return payload.validateValue(@import("domain/model_envelope.zig").value(&value.value), selected.root()) == null;
}

test "every declared field schema offers exactly its permitted insertion alternatives" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const canonical = try compile(a, all_insertions);
    for (std.meta.tags(policy.Field)) |field| {
        const binding: []const fields.Binding = &.{.{ .field = field, .path = &.{.{ .property = "value" }} }};
        const selected = try schema.restrictFieldPolicies(a, canonical, &.{}, &.{}, binding);
        defer selected.release();
        const inspected = fields.inspectSchema(selected.selected().root(), binding, &.{});
        try std.testing.expect(inspected.valid);
        try std.testing.expectEqual(policy.permits(field, .exact_copy), inspected.requires_exact_scope);
        try std.testing.expect(try accepted(a, selected.selected(), "{\"value\":\"Observe the requested behavior.\"}"));
        for (std.meta.tags(policy.Insertion)) |kind| {
            const id = switch (kind) {
                .exact_copy => "claim_id",
                .passive => "passive_literal_id",
                .source => "source_id",
            };
            const bytes = try std.fmt.allocPrint(a, "{{\"value\":{{\"fragments\":[\"Observe \",{{\"kind\":\"{s}\",\"{s}\":1}}]}}}}", .{ @tagName(kind), id });
            try std.testing.expectEqual(policy.permitsModel(field, kind), try accepted(a, selected.selected(), bytes));
        }
        // Both provider grammar views serialize the already restricted owner.
        const bedrock = try @import("domain/model_schema_projection.zig").render(a, selected.selected(), .bedrock);
        const full = try @import("domain/model_schema_projection.zig").render(a, selected.selected(), .complete);
        for (std.meta.tags(policy.Insertion)) |kind| {
            const marker = try std.fmt.allocPrint(a, "\"const\":\"{s}\"", .{@tagName(kind)});
            try std.testing.expectEqual(policy.permitsModel(field, kind), std.mem.indexOf(u8, full, marker) != null);
            try std.testing.expectEqual(policy.permitsModel(field, kind), std.mem.indexOf(u8, bedrock, marker) != null);
        }
    }
    try std.testing.expect(!fields.validSchema(canonical.root(), &.{}));
    try std.testing.expectError(error.InvalidModelResultSchema, fields.project(a, canonical.root(), &.{.{ .field = .spec_title, .path = &.{.{ .property = "foreign" }} }}, true));
}

test "native model declarations distinguish shared text types and narrowed replacement context" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = @import("domain/specification_generation.zig");
    const bound = try codec.fieldBindings(g.ModelResponse, a, .{});
    try std.testing.expect(fields.valid(bound));
    const resource = try compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/generation.schema.json", a, .unlimited));
    for ([_][]const u8{ "brief", "primary_user_story", "entities", "records" }) |name| {
        const selected = try schema.restrictFieldPolicies(a, resource.select(.{ .bytes = name }).?, &.{}, &.{}, bound);
        defer selected.release();
        const active = try fields.activeBindings(a, selected.selected().root(), bound);
        try std.testing.expect(active.len != 0);
        try std.testing.expect(fields.validSchema(selected.selected().root(), bound));
    }
    const replacement = @import("domain/specification_candidate.zig").Replacement;
    const narrowed = try codec.selectedFieldBindings(replacement, a, .value, .{ .inherited = .spec_goal });
    try std.testing.expectEqual(@as(usize, 1), narrowed.len);
    try std.testing.expectEqual(policy.Field.spec_goal, narrowed[0].field);
    try std.testing.expect(fields.samePath(&.{.{ .property = "value" }}, narrowed[0].path));
    try std.testing.expectError(error.InvalidModelTextBinding, codec.fieldBindings(g.spec.BusinessValue, a, .{}));
    const reference = try codec.fieldBindings(@import("domain/reference_extraction_parser.zig").Response, a, .{ .reference_phase = .extraction });
    try std.testing.expect(reference.len != 0 and fields.valid(reference));
    const questions = try codec.fieldBindings(@import("domain/specification_support.zig").Source.Value, a, .{});
    for (questions) |question| try std.testing.expectEqual(policy.Field.clarification_question, question.field);
    try std.testing.expect(questions.len != 0);
    const wire_questions = try codec.fieldBindings(@import("domain/specification_support_model.zig").Value, a, .{});
    try std.testing.expect(fields.same(questions, wire_questions));
}

test "descriptive insertions reject identically in native composition and stored readback" {
    const text = @import("domain/typed_text.zig");
    const reference = @import("reference_evidence_test.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ids: reference.IdSource = .{};
    const inputs = try reference.prepare(a, &ids, try @import("reference_ingestion_test.zig").read(a, "source.md", "An unrelated source-backed meaning.\n"));
    const value: []const text.BusinessSegment = &.{ .{ .literal = .{ .value = "A supported meaning with " } }, .{ .exact_copy = .{ .claim_id = .{ .ordinal = 1 } } } };
    var context: text.StoredContext = .{ .inputs = inputs, .passive = .{ .records = &.{}, .occurrences = &.{} }, .scopes = &.{.{ .state_id = inputs.corpus.state_id, .chunk_id = inputs.chunks.entries[0].id }}, .field = .spec_title, .exact_copies = &.{value[1].exact_copy} };
    for ([_]policy.Field{ .spec_title, .spec_goal, .spec_entity_basis, .entity_meaning, .entity_relationship, .assumption, .clarification_question }) |field| {
        try std.testing.expectEqual(.prohibited_exact, text.composition(text.BusinessSegment, field, value).?.reason);
        context.field = field;
        try std.testing.expectError(error.InvalidTypedText, text.stored(text.BusinessSegment, a, context, value));
    }
    try std.testing.expect(text.composition(text.BusinessSegment, .entity_name, &.{value[1]}) == null);
    try std.testing.expect(text.composition(text.BusinessSegment, .functional_requirement, value) == null);
    context.field = .entity_name;
    try text.stored(text.BusinessSegment, a, context, &.{value[1]});
    context.field = .functional_requirement;
    try text.stored(text.BusinessSegment, a, context, value);
}

test "captured field-policy descriptions round trip selected schema numeric bounds" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const binding: []const fields.Binding = &.{.{ .field = .functional_requirement, .path = &.{.{ .property = "value" }} }};
    const canonical = try compile(a, all_insertions);
    const selected = try schema.restrictFieldPolicies(a, canonical, &.{}, &.{}, binding);
    defer selected.release();
    var fixture: @import("provider_invocation_test_fixture.zig").Fixture = undefined;
    try fixture.initWithFieldPolicies(selected.selected().modelBytes(), &.{}, &.{}, binding);
    defer fixture.deinit();
    const description = @import("domain/model_request_description.zig").Description;
    const captured = description.from(fixture.prepared.request, &fixture.base.provider_binding, .inference);
    const restored = try description.decode(a, try std.json.Stringify.valueAlloc(a, captured, .{}));
    try std.testing.expectEqualStrings(captured.schema, restored.schema);
    try std.testing.expect(fields.same(binding, restored.field_policies));
}

test "selected field presentation intersects policy with raw prose and excluded wire insertions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const presentation = @import("domain/model_field_presentation.zig");
    const body = "{\"exact_catalogue\":[1],\"passive_catalogue\":[2],\"source_catalogue\":[3],\"evidence\":\"Keep original source evidence.\"}";
    const omissions: []const presentation.Omission = &.{
        .{ .requires = .exact_copy, .path = &.{.{ .property = "exact_catalogue" }} },
        .{ .requires = .passive, .path = &.{.{ .property = "passive_catalogue" }} },
        .{ .requires = .source, .path = &.{.{ .property = "source_catalogue" }} },
    };
    const raw = try compile(a, "{\"type\":\"object\",\"properties\":{\"question\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128}},\"required\":[\"question\"],\"additionalProperties\":false}");
    const question: []const fields.Binding = &.{.{ .field = .clarification_question, .path = &.{.{ .property = "question" }} }};
    const active_question = try fields.activeBindings(a, raw.root(), question);
    try std.testing.expectEqual(@as(usize, 1), active_question.len);
    try std.testing.expectEqual(@as(usize, 0), active_question[0].insertions.count());
    const question_body = (try @import("domain/strict_json.zig").parse(a, try presentation.project(a, body, raw.root(), question, omissions), .{ .maximum_depth = schema.max_json_depth }, false, null)).value.object;
    inline for (.{ "exact_catalogue", "passive_catalogue", "source_catalogue" }) |name| try std.testing.expect(!question_body.contains(name));
    try std.testing.expect(!question_body.get("insertion_fields").?.object.contains("exact_copy"));
    inline for (.{ "passive", "source" }) |kind| try std.testing.expectEqual(@as(usize, 0), question_body.get("insertion_fields").?.object.get(kind).?.array.items.len);
    try std.testing.expectEqualStrings(policy.selectedGuidance(.clarification_question, .initEmpty()).instruction, question_body.get("field_rules").?.array.items[0].object.get("instruction").?.string);
    try std.testing.expectEqualStrings("Keep original source evidence.", question_body.get("evidence").?.string);

    const canonical = try compile(a, all_insertions);
    const binding: []const fields.Binding = &.{.{ .field = .functional_requirement, .path = &.{.{ .property = "value" }} }};
    {
        const selected = try schema.restrictFieldPolicies(a, canonical, &.{}, &.{}, binding);
        defer selected.release();
        try std.testing.expect(fields.validSchema(selected.selected().root(), binding));
        const active = try fields.activeBindings(a, selected.selected().root(), binding);
        try std.testing.expectEqual(@as(usize, 1), active.len);
        try std.testing.expect(!active[0].insertions.contains(.exact_copy));
        try std.testing.expect(active[0].insertions.contains(.passive));
        try std.testing.expect(!active[0].insertions.contains(.source));
        const projected = (try @import("domain/strict_json.zig").parse(a, try presentation.project(a, body, selected.selected().root(), binding, omissions), .{ .maximum_depth = schema.max_json_depth }, false, null)).value.object;
        try std.testing.expect(projected.contains("exact_catalogue"));
        try std.testing.expect(projected.contains("passive_catalogue"));
        try std.testing.expect(!projected.contains("source_catalogue"));
        try std.testing.expect(!projected.get("insertion_fields").?.object.contains("exact_copy"));
        const instruction = projected.get("field_rules").?.array.items[0].object.get("instruction").?.string;
        try std.testing.expect(std.mem.indexOf(u8, instruction, "Type required exact values verbatim") != null);
        try std.testing.expectEqualStrings(policy.selectedGuidance(.functional_requirement, active[0].insertions).instruction, instruction);
    }
    const identity = try schema.restrictFieldPolicies(a, canonical, &.{ .{ .kind = "passive" }, .{ .kind = "source" } }, &.{}, &.{.{ .field = .entity_name, .path = &.{.{ .property = "value" }} }});
    defer identity.release();
    const active_identity = try fields.activeBindings(a, identity.selected().root(), &.{.{ .field = .entity_name, .path = &.{.{ .property = "value" }} }});
    try std.testing.expectEqual(@as(usize, 0), active_identity[0].insertions.count());
    try std.testing.expect(fields.inspectSchema(identity.selected().root(), &.{.{ .field = .entity_name, .path = &.{.{ .property = "value" }} }}, &.{}).requires_exact_scope);
    try std.testing.expectEqualStrings("Write the identity label as plain text.", policy.selectedGuidance(.entity_name, active_identity[0].insertions).instruction);
    // Guidance emitted before schema selection cannot promise an insertion
    // that a later native exclusion removes.
    try std.testing.expect(std.mem.indexOf(u8, policy.guidance(.functional_requirement).instruction, "Exact copies may carry") == null);
}
