const std = @import("std");
const build = @import("actions/model/build_model_request.zig");
const preparation = @import("domain/model_request_preparation.zig");
const provider = @import("domain/llm_provider_operation.zig");
const compilation = @import("domain/workflow_compilation.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const Fixture = @import("provider_authorization_test_fixture.zig").Fixture;

test "current exact-capable fields require an explicit native scope even with no occurrences" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = try compiler.compiler().compile(fixture.schema_arena.allocator(), "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"string\",\"maxLength\":256}},\"required\":[\"value\"],\"additionalProperties\":false}");
    const resource: compilation.CompiledResource = .{ .id = .{ .bytes = "value-result" }, .content = .{ .result_schema = compiled } };
    var selected = try source(&fixture, &resource);
    selected.field_policies = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }};
    const content: []const provider.ModelVisibleContent = &.{.{ .user = "Describe the assigned value." }};
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, preparation.build(std.testing.allocator, selected, content));
    selected.exact_scope = .{ .reference_state = .{ .bytes = "TEST-empty-reference" }, .occurrences = &.{} };
    var owned = try preparation.build(std.testing.allocator, selected, content);
    defer owned.deinit();
    try preparation.validateRequest(selected, owned.request);
    try std.testing.expectEqual(@as(usize, 0), owned.request.exact_scope.?.occurrences.len);
    var missing = owned.request.*;
    missing.exact_scope = null;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, missing.validate());
    const Description = @import("domain/model_request_description.zig").Description;
    var described = Description.from(owned.request, &fixture.provider_binding, .inference);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    _ = try Description.decode(a, try std.json.Stringify.valueAlloc(a, described, .{}));
    described.exact_scope = null;
    try std.testing.expectError(error.InvalidJsonDocument, Description.decode(a, try std.json.Stringify.valueAlloc(a, described, .{})));
    selected.exact_scope = null;
    selected.field_policies = &.{};
    selected.prose_fields = &.{.{ .field = .ac_then, .path = &.{.{ .property = "value" }} }};
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, preparation.build(std.testing.allocator, selected, content));
    selected.prose_fields = &.{};
    for ([_]@import("domain/text_field_policy.zig").Field{ .spec_goal, .extraction_business, .reconciliation_business }) |field| {
        selected.exact_scope = null;
        selected.field_policies = &.{ .{ .field = field, .path = &.{.{ .property = "value" }} }, .{ .field = .ac_then, .path = &.{.{ .property = "absent" }} } };
        var prohibited = try preparation.build(std.testing.allocator, selected, content);
        defer prohibited.deinit();
        try std.testing.expect(prohibited.request.exact_scope == null);
    }
}

test "native raw prose selectors are deep owned schema bound and absent from provider content" {
    const wire = @import("domain/model_text_wire.zig");
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var compiler: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const compiled = try compiler.compiler().compile(fixture.schema_arena.allocator(), "{\"type\":\"object\",\"properties\":{\"question\":{\"type\":\"string\",\"maxLength\":256}},\"required\":[\"question\"],\"additionalProperties\":false}");
    const resource: compilation.CompiledResource = .{ .id = .{ .bytes = "question-result" }, .content = .{ .result_schema = compiled } };
    var selected_source = try source(&fixture, &resource);
    var name = "question".*;
    var path = [_]@import("domain/model_result_schema.zig").ChoiceStep{.{ .property = &name }};
    var fields = [_]wire.ProseField{.{ .field = .clarification_question, .path = &path }};
    selected_source.prose_fields = &fields;
    const content = [_]provider.ModelVisibleContent{.{ .user = "Ask the unresolved question." }};
    var owned = try preparation.build(std.testing.allocator, selected_source, &content);
    defer owned.deinit();
    try preparation.validateRequest(selected_source, owned.request);
    try std.testing.expect(owned.request.prose_fields.ptr != fields[0..].ptr);
    try std.testing.expect(owned.request.prose_fields[0].path.ptr != path[0..].ptr);
    try std.testing.expect(owned.request.prose_fields[0].path[0].property.ptr != name[0..].ptr);
    try std.testing.expectEqualDeep(@as([]const provider.ModelVisibleContent, &content), owned.request.content);
    name[0] = 'X';
    try std.testing.expectEqualStrings("question", owned.request.prose_fields[0].path[0].property);
    try std.testing.expectError(error.InvalidModelRequestSource, preparation.validateRequest(selected_source, owned.request));
    name[0] = 'q';
    fields[0].field = .spec_goal;
    try std.testing.expectError(error.ModelRequestAssociationInvalid, preparation.validateRequest(selected_source, owned.request));
    fields[0].field = .clarification_question;
    const described = @import("domain/model_request_description.zig").Description.from(owned.request, &fixture.provider_binding, .inference);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const encoded = try std.json.Stringify.valueAlloc(a, described, .{});
    const restored = try @import("domain/model_request_description.zig").Description.decode(a, encoded);
    try std.testing.expectEqualDeep(owned.request.prose_fields, restored.prose_fields);
    const malformed = try std.mem.replaceOwned(u8, a, encoded, "clarification_question", "unknown_prose_policy");
    try std.testing.expectError(error.InvalidJsonDocument, @import("domain/model_request_description.zig").Description.decode(a, malformed));
    path[0] = .items;
    try std.testing.expectError(error.InvalidModelRequestSource, preparation.build(std.testing.allocator, selected_source, &content));
}

test "native packet prose selectors survive clones and release all failed allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, prosePacketAllocation, .{});
}

fn prosePacketAllocation(a: std.mem.Allocator) !void {
    const packets = @import("domain/model_input_packet.zig");
    const wire = @import("domain/model_text_wire.zig");
    const packet = try packets.create(a, "{\"input\":\"original\"}", .workflow_step, .initial_generation, null);
    defer packets.release(packet);
    var name = "question".*;
    const fields = [_]wire.ProseField{.{ .field = .clarification_question, .path = &.{.{ .property = &name }} }};
    const declared = try packets.withProseFields(a, packet, &fields);
    defer packets.release(declared);
    const witnessed = try packets.withOriginalSourceTexts(a, declared, &.{.{ .source_id = .{ .ordinal = 1 }, .bytes = "Original question." }});
    defer packets.release(witnessed);
    const policies = [_]@import("domain/model_text_field.zig").Binding{.{ .field = .clarification_question, .path = &.{.{ .property = &name }} }};
    const bound = try packets.withFieldPolicies(a, witnessed, &policies);
    defer packets.release(bound);
    var catalogue = "catalogue".*;
    const omissions = [_]@import("domain/model_field_presentation.zig").Omission{.{ .requires = .exact_copy, .path = &.{ .{ .property = &catalogue }, .{ .index = 2 } } }};
    const presented = try packets.withPresentationOmissions(a, bound, &omissions);
    defer packets.release(presented);
    const cloned = try packets.withRestrictions(a, presented, &.{}, &.{});
    defer packets.release(cloned);
    name[0] = 'X';
    catalogue[0] = 'X';
    try std.testing.expectEqualStrings("question", cloned.proseFields()[0].path[0].property);
    try std.testing.expectEqualStrings("question", cloned.fieldPolicies()[0].path[0].property);
    try std.testing.expectEqualStrings("catalogue", cloned.presentationOmissions()[0].path[0].property);
    try std.testing.expectEqual(@as(u32, 2), cloned.presentationOmissions()[0].path[1].index);
    try std.testing.expectEqual(@import("domain/text_field_policy.zig").Insertion.exact_copy, cloned.presentationOmissions()[0].requires);
    try std.testing.expect(cloned.fieldPolicies().ptr != bound.fieldPolicies().ptr);
    try std.testing.expect(cloned.fieldPolicies()[0].path.ptr != bound.fieldPolicies()[0].path.ptr);
    try std.testing.expect(cloned.fieldPolicies()[0].path[0].property.ptr != bound.fieldPolicies()[0].path[0].property.ptr);
    try std.testing.expect(cloned.presentationOmissions().ptr != presented.presentationOmissions().ptr);
    try std.testing.expect(cloned.presentationOmissions()[0].path.ptr != presented.presentationOmissions()[0].path.ptr);
    try std.testing.expect(cloned.presentationOmissions()[0].path[0].property.ptr != presented.presentationOmissions()[0].path[0].property.ptr);
    try std.testing.expectEqualStrings("Original question.", cloned.originalSources()[0].bytes);
    try std.testing.expectEqualStrings(packet.body(), cloned.body());
    try std.testing.expectEqual(@as(usize, 0), packet.proseFields().len);
    try std.testing.expectEqual(@as(usize, 0), packet.fieldPolicies().len);
    try std.testing.expectEqual(@as(usize, 0), packet.presentationOmissions().len);
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withProseFields(a, packet, &.{ .{ .field = .clarification_question, .path = &.{.{ .property = "question" }} }, .{ .field = .spec_goal, .path = &.{.{ .property = "question" }} } }));
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withFieldPolicies(a, packet, &.{ .{ .field = .clarification_question, .path = &.{.{ .property = "question" }} }, .{ .field = .spec_goal, .path = &.{.{ .property = "question" }} } }));
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withPresentationOmissions(a, packet, &.{ .{ .requires = .exact_copy, .path = &.{.{ .property = "catalogue" }} }, .{ .requires = .passive, .path = &.{.{ .property = "catalogue" }} } }));
}

test "native original-source witness is owned bound and absent from provider content" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    var selected = try source(&fixture, &resource);
    var bytes = "Original {\"kind\":\"exact_copy\"} source".*;
    var sources = [_]@import("domain/model_text_wire.zig").SourceText{.{ .source_id = .{ .ordinal = 1 }, .bytes = &bytes }};
    selected.original_sources = &sources;
    const content = [_]provider.ModelVisibleContent{.{ .user = "One assigned business value." }};
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer owned.deinit();
    try preparation.validateRequest(selected, owned.request);
    try std.testing.expectEqualDeep(@as([]const provider.ModelVisibleContent, &content), owned.request.content);
    try std.testing.expect(owned.request.original_sources.ptr != sources[0..].ptr);
    try std.testing.expect(owned.request.original_sources[0].bytes.ptr != bytes[0..].ptr);
    const original = owned.request.original_sources[0].bytes;
    bytes[0] = 'X';
    try std.testing.expectEqual(@as(u8, 'O'), original[0]);
    try std.testing.expectError(error.ModelRequestAssociationInvalid, preparation.validateRequest(selected, owned.request));
    sources[0].bytes = original;
    sources[0].source_id.ordinal = 2;
    try std.testing.expectError(error.ModelRequestAssociationInvalid, preparation.validateRequest(selected, owned.request));
    sources[0].source_id.ordinal = 0;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(std.testing.allocator, selected, &content));
}

test "request construction is deterministic minimal and preserves immutable authorities" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    const content = [_]provider.ModelVisibleContent{
        .{ .system = "Return one object." },
        .{ .guidance = "Keep the declared fields." },
        .{ .user = "Describe this item." },
        .{ .evidence = "A café opens at eight.\n" },
    };
    const ledger = fixture.requests.ledger().?;
    const attempts = fixture.attempts.current();
    var first = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer first.deinit();
    var second = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer second.deinit();
    try preparation.validateRequest(selected, first.request);
    try std.testing.expect(first.request != second.request);
    try std.testing.expectEqualDeep(first.request.*, second.request.*);
    try std.testing.expect(first.request.model_request_id == fixture.model_request_id);
    try std.testing.expect(first.request.response_schema == resource.content.result_schema);
    try std.testing.expectEqualStrings(resource.id.bytes, first.request.result_schema_id.bytes);
    try std.testing.expectEqualDeep(@as([]const provider.ModelVisibleContent, &content), first.request.content);
    for (first.request.content) |part| {
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), "epoch-1") == null);
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), "input-1") == null);
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), "request.test/v1") == null);
        try std.testing.expect(std.mem.indexOf(u8, part.bytes(), resource.content.result_schema.bytes()) == null);
    }
    try std.testing.expect(fixture.requests.ledger().? == ledger);
    try std.testing.expect(fixture.attempts.current() == attempts);
    try std.testing.expectEqual(@as(u64, 0), fixture.ledger().revision().value);
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
}

test "prepared request owns transient content and IDs without cloning graph or ledger authority" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    var selected = try source(&fixture, &resource);
    var input = [_]u8{ 'i', 'n', 'p', 'u', 't' };
    var schema_id = [_]u8{ 'r', 'e', 'q' };
    var text = [_]u8{ 'd', 'a', 't', 'a' };
    var content = [_]provider.ModelVisibleContent{.{ .evidence = &text }};
    selected.request_schema_id.bytes = &schema_id;
    selected.model_visible_input_id.bytes = &input;
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer owned.deinit();
    try preparation.validateRequest(selected, owned.request);
    @memset(&input, 'x');
    @memset(&schema_id, 'x');
    @memset(&text, 'x');
    content[0] = .{ .user = "replaced" };
    try std.testing.expectEqualStrings("input", owned.request.model_visible_input_id.bytes);
    try std.testing.expectEqualStrings("req", owned.request.request_schema_id.bytes);
    try std.testing.expectEqualStrings("data", owned.request.content[0].evidence);
    try std.testing.expect(owned.request.response_schema == resource.content.result_schema);
    try owned.request.validate();
}

test "builder rejects malformed content and identities before allocating content" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    const invalid_utf8 = [_]u8{0xff};
    const cases = [_][]const provider.ModelVisibleContent{
        &.{},
        &.{.{ .user = "" }},
        &.{.{ .guidance = &invalid_utf8 }},
    };
    for (cases) |content| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(failing.allocator(), selected, content));
    }
    inline for (.{ false, true }) |input_identity| {
        var invalid = selected;
        if (input_identity) invalid.model_visible_input_id.bytes = "" else invalid.request_schema_id.bytes = "";
        try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(std.testing.allocator, invalid, fixture.request.content));
    }
}

test "request construction preserves all content beyond former input ceilings" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    const large = try std.testing.allocator.alloc(u8, 16_384);
    defer std.testing.allocator.free(large);
    @memset(large, 'x');
    const content = [_]provider.ModelVisibleContent{ .{ .system = "a" }, .{ .guidance = "b" }, .{ .user = "é" }, .{ .evidence = large } };
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, &content);
    defer owned.deinit();
    try preparation.validateRequest(selected, owned.request);
    try std.testing.expectEqualDeep(@as([]const provider.ModelVisibleContent, &content), owned.request.content);
    try std.testing.expect(owned.request.response_schema == resource.content.result_schema);
}

test "only a compiled result-schema resource can supply the request schema" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer owned.deinit();
    inline for (.{ .prompt, .example, .data }) |kind| {
        resource.content = @unionInit(@FieldType(compilation.CompiledResource, "content"), @tagName(kind), "{}");
        try std.testing.expectError(error.InvalidModelRequestSource, (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content));
        try std.testing.expectError(error.InvalidModelRequestSource, preparation.validateRequest(selected, owned.request));
    }
    resource = resultResource(&fixture);
    resource.id.bytes = "";
    try std.testing.expectError(error.InvalidModelRequestSource, (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content));
}

test "request validation rejects foreign request input and schema associations" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var other: Fixture = undefined;
    try other.init(std.testing.allocator);
    defer other.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer owned.deinit();
    inline for (0..5) |variant| {
        var wrong = owned.request.*;
        switch (variant) {
            0 => wrong.model_request_id = other.model_request_id,
            1 => wrong.request_schema_id.bytes = "another-request/v1",
            2 => wrong.result_schema_id.bytes = "another-result",
            3 => wrong.response_schema = other.request.response_schema,
            4 => wrong.model_visible_input_id.bytes = "another-input",
            else => unreachable,
        }
        try std.testing.expectError(error.ModelRequestAssociationInvalid, preparation.validateRequest(selected, &wrong));
    }
    var wrong_binding = fixture.provider_binding;
    wrong_binding.operation_id.workflow_version += 1;
    var invalid = selected;
    invalid.provider_binding = &wrong_binding;
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, (build.Action{}).execute(std.testing.allocator, invalid, fixture.request.content));
}

test "composition source preserves exact part schema execution unit and purpose association" {
    const packets = @import("domain/model_input_packet.zig");
    const runtime = @import("domain/json_composition_runtime.zig");
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const canonical = try parser.compiler().compile(a,
        \\{"type":"object","properties":{"left":{"type":"string","maxLength":10},"right":{"type":"string","maxLength":10}},"required":["left","right"],"additionalProperties":false}
    );
    const plan = try parser.compiler().compileComposition(a,
        \\{"schema":"json-composition/v1","result":"result","parts":{"left":{"paths":["/left"]},"right":{"paths":["/right"]}}}
    , canonical);
    const id = fixture.model_request_id;
    const packet = try packets.create(std.testing.allocator, "{}", id.immutable_unit_owner_id, id.purpose, null);
    defer packets.release(packet);
    const state = try runtime.State.init(a, plan, packet, id.stage_run_epoch_id);
    const part = try state.select(a, 0);
    const resource: compilation.CompiledResource = .{ .id = plan.resultAlias(), .content = .{ .result_schema = canonical } };
    var selected = try source(&fixture, &resource);
    selected.composition = part;
    var prepared = try preparation.build(std.testing.allocator, selected, fixture.request.content);
    defer prepared.deinit();
    try std.testing.expect(prepared.request.response_schema == part.schema);
    var native_entry = fixture.registry_entry;
    native_entry.capabilities.structured_response = .native_json_schema;
    native_entry.json = true;
    var native_binding = fixture.provider_binding;
    native_binding.registry_entry = &native_entry;
    var native_source = selected;
    native_source.provider_binding = &native_binding;
    var native_request = try preparation.build(std.testing.allocator, native_source, fixture.request.content);
    defer native_request.deinit();
    try std.testing.expect(native_request.request.response_schema == part.schema);
    const native_projection = try @import("domain/model_schema_projection.zig").render(a, native_request.request.response_schema, .native);
    try std.testing.expect(std.mem.indexOf(u8, native_projection, "\"left\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, native_projection, "\"right\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, part.schema.modelBytes(), "\"maxLength\":10") != null);
    const other_epoch = try @import("domain/execution_reference.zig").create(std.testing.allocator);
    defer other_epoch.release();
    const other_unit = try packets.create(std.testing.allocator, "{}", .{ .plan_unit = .{ .plan_input_authority_state_id = .{ .bytes = "other" }, .unit_slot_id = .{ .bytes = "other" } } }, .initial_generation, null);
    defer packets.release(other_unit);
    const other_purpose = try packets.create(std.testing.allocator, "{}", id.immutable_unit_owner_id, .{ .atomic_repair = .{ .bytes = "foreign-repair" } }, null);
    defer packets.release(other_purpose);
    for (0..4) |index| {
        var wrong = selected;
        switch (index) {
            0 => wrong.composition.?.epoch = .{ .reference = other_epoch },
            1 => wrong.composition.?.base = other_unit,
            2 => wrong.composition.?.base = other_purpose,
            3 => wrong.composition.?.part = 1,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidModelRequestSource, preparation.build(std.testing.allocator, wrong, fixture.request.content));
        try std.testing.expectError(error.InvalidModelRequestSource, preparation.validateRequest(wrong, prepared.request));
    }
}

test "request validation rejects divergent binding controls and modes" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content);
    defer owned.deinit();
    inline for (0..4) |variant| {
        var wrong = owned.request.*;
        switch (variant) {
            0 => wrong.binding_id.registry_entry_id.ordinal += 1,
            1 => wrong.binding_id.slot_id.bytes = "another-slot",
            2 => {
                wrong.controls.temperature = null;
                wrong.binding_id.controls = wrong.controls;
            },
            3 => wrong.response_guidance_mode = .native_schema,
            else => unreachable,
        }
        try std.testing.expectError(error.ModelRequestBindingInvalid, preparation.validateRequest(selected, &wrong));
    }
    fixture.registry_entry.capabilities.temperature = false;
    try std.testing.expectError(error.ModelRequestBindingInvalid, preparation.validateRequest(selected, owned.request));
    fixture.registry_entry.capabilities.temperature = true;
    fixture.registry_entry.json = true;
    try std.testing.expectError(error.ModelRequestBindingInvalid, (build.Action{}).execute(std.testing.allocator, selected, fixture.request.content));
}

test "prepared request reaches fake inference without preparation side effects" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    const large = try std.testing.allocator.alloc(u8, 16_384);
    defer std.testing.allocator.free(large);
    @memset(large, 'x');
    var owned = try (build.Action{}).execute(std.testing.allocator, selected, &.{.{ .evidence = large }});
    defer owned.deinit();
    try preparation.validateRequest(selected, owned.request);
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .authorization_leases = fixture.leasePort(),
        .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 1_000_000, .output_tokens = 500_000 } },
    };
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    fixture.request = owned.request.*;
    const inference = try fixture.startInference();
    var response = try fake.interface().invoke(&fixture.provider_binding, owned.request, inference.reference, inference.invoked);
    defer response.deinit();
    try std.testing.expectEqualStrings("{}", response.completed.raw_result.complete.content.bytes);
    try std.testing.expectEqual(@as(u64, 1_500_000), response.completed.raw_result.complete.usage.total_tokens);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
    try std.testing.expectEqualStrings(large, owned.request.content[0].evidence);
}

test "request construction releases every partial allocation without changing source authority" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    const selected = try source(&fixture, &resource);
    var owned = try (build.Action{}).execute(allocator, selected, fixture.request.content);
    defer owned.deinit();
    try preparation.validateRequest(selected, owned.request);
    try std.testing.expectEqual(@as(u64, 0), fixture.ledger().revision().value);
    try std.testing.expectEqual(@as(usize, 0), fixture.preloader.prepared_count);
}

fn resultResource(fixture: *const Fixture) compilation.CompiledResource {
    return .{ .id = .{ .bytes = "result" }, .content = .{ .result_schema = fixture.request.response_schema } };
}

fn source(fixture: *Fixture, resource: *const compilation.CompiledResource) !preparation.Source {
    const request_id = fixture.model_request_id;
    return .{
        .request_binding = try fixture.requests.validate(fixture.requests.ledger().?.revision(), request_id, request_id.immutable_unit_owner_id, request_id.model_operation_id, request_id.purpose),
        .provider_binding = &fixture.provider_binding,
        .request_schema_id = fixture.request.request_schema_id,
        .model_visible_input_id = fixture.request.model_visible_input_id,
        .result_resource = resource,
    };
}

test "request mode cannot override catalogue JSON selection" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    fixture.registry_entry.capabilities.structured_response = .native_json_schema;
    // Both wire modes are supported; only the captured catalogue choice is allowed.
    for ([_]bool{ false, true }) |json| {
        fixture.registry_entry.json = json;
        fixture.request.response_guidance_mode = fixture.registry_entry.responseMode();
        try std.testing.expect(fixture.request.matchesBinding(fixture.provider_binding));
        fixture.request.response_guidance_mode = if (json) .prompt_only else .native_schema;
        try std.testing.expect(!fixture.request.matchesBinding(fixture.provider_binding));
    }
}

test "native exact occurrence scope is deep owned and bound across request descriptions" {
    const exact = @import("domain/model_exact_values.zig");
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const resource = resultResource(&fixture);
    var selected = try source(&fixture, &resource);
    var bytes = "ACTIVE".*;
    var occurrences = [_]@import("domain/exact_value_recognition.zig").Occurrence{.{ .claim_id = .{ .ordinal = 7 }, .bytes = &bytes }};
    selected.exact_scope = .{ .reference_state = .{ .bytes = "REF-1" }, .occurrences = &occurrences };
    const content = [_]provider.ModelVisibleContent{.{ .user = "Describe the assigned behavior." }};
    var owned = try preparation.build(std.testing.allocator, selected, &content);
    defer owned.deinit();
    const scope = owned.request.exact_scope.?;
    try std.testing.expect(exact.same(selected.exact_scope, scope));
    try std.testing.expect(scope.occurrences.ptr != occurrences[0..].ptr);
    try std.testing.expect(scope.occurrences[0].bytes.ptr != bytes[0..].ptr);
    try std.testing.expectEqualDeep(@as([]const provider.ModelVisibleContent, &content), owned.request.content);
    var bound_id = owned.request.model_request_id.*;
    bound_id.immutable_unit_owner_id = .{ .reference_global = .{ .reference_state_id = scope.reference_state, .unit_slot_id = .{ .bytes = "native-unit" } } };
    var bound_request = owned.request.*;
    bound_request.model_request_id = &bound_id;
    try bound_request.validate();
    bound_id.immutable_unit_owner_id.reference_global.reference_state_id.bytes = "FOREIGN";
    try std.testing.expectError(error.InvalidProviderNeutralModelRequest, bound_request.validate());
    bytes[0] = 'X';
    try std.testing.expectEqualStrings("ACTIVE", scope.occurrences[0].bytes);
    try std.testing.expectError(error.ModelRequestAssociationInvalid, preparation.validateRequest(selected, owned.request));
    bytes[0] = 'A';
    occurrences[0].claim_id.ordinal = 8;
    try std.testing.expectError(error.ModelRequestAssociationInvalid, preparation.validateRequest(selected, owned.request));
    occurrences[0].claim_id.ordinal = 7;
    selected.exact_scope.?.reference_state.bytes = "REF-2";
    try std.testing.expectError(error.ModelRequestAssociationInvalid, preparation.validateRequest(selected, owned.request));
    selected.exact_scope = scope;
    try preparation.validateRequest(selected, owned.request);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const description = @import("domain/model_request_description.zig").Description;
    const encoded = try std.json.Stringify.valueAlloc(a, description.from(owned.request, &fixture.provider_binding, .inference), .{});
    const restored = try description.decode(a, encoded);
    try std.testing.expect(exact.same(scope, restored.exact_scope));
    const old = try std.mem.replaceOwned(u8, a, encoded, @import("domain/model_request_description.zig").current_version, "model-request-debug/v5");
    try std.testing.expectError(error.InvalidJsonDocument, description.decode(a, old));
}

test "native exact packet scope narrows without widening and cleans every failed allocation" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exactPacketAllocation, .{});
}

fn exactPacketAllocation(a: std.mem.Allocator) !void {
    const packets = @import("domain/model_input_packet.zig");
    const exact = @import("domain/model_exact_values.zig");
    const base = try packets.create(a, "{\"input\":\"original\"}", .workflow_step, .initial_generation, null);
    defer packets.release(base);
    const scope: exact.Scope = .{ .reference_state = .{ .bytes = "REF-1" }, .occurrences = &.{ .{ .claim_id = .{ .ordinal = 7 }, .bytes = "ACTIVE" }, .{ .claim_id = .{ .ordinal = 9 }, .bytes = "READY" } } };
    const scoped = try packets.withExactScope(a, base, scope);
    defer packets.release(scoped);
    const narrow = try packets.withExactScope(a, scoped, .{ .reference_state = scope.reference_state, .occurrences = scope.occurrences[1..] });
    defer packets.release(narrow);
    const clone = try packets.withBody(a, narrow, "{\"input\":\"projected\"}");
    defer packets.release(clone);
    try std.testing.expect(base.exactScope() == null);
    try std.testing.expect(exact.same(narrow.exactScope(), clone.exactScope()));
    try std.testing.expect(clone.exactScope().?.occurrences.ptr != narrow.exactScope().?.occurrences.ptr);
    try std.testing.expectEqualStrings("{\"input\":\"projected\"}", clone.body());
    try std.testing.expectEqualStrings("{\"input\":\"original\"}", base.body());
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withExactScope(a, clone, scope));
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withExactScope(a, scoped, .{ .reference_state = .{ .bytes = "REF-2" }, .occurrences = scope.occurrences }));
    try std.testing.expectError(error.InvalidModelInputPacket, packets.withExactScope(a, scoped, .{ .reference_state = scope.reference_state, .occurrences = &.{.{ .claim_id = .{ .ordinal = 7 }, .bytes = "CHANGED" }} }));
}

test "native exact packet scopes must match reference-backed owner snapshots" {
    const packets = @import("domain/model_input_packet.zig");
    const ids = @import("domain/model_request_identity.zig");
    const scope: @import("domain/model_exact_values.zig").Scope = .{ .reference_state = .{ .bytes = "REF-1" }, .occurrences = &.{} };
    for ([_]ids.ImmutableUnitOwnerId{
        .{ .reference_chunk = .{ .reference_state_id = scope.reference_state, .chunk_id = .{ .bytes = "chunk-1" } } },
        .{ .reference_global = .{ .reference_state_id = scope.reference_state, .unit_slot_id = .{ .bytes = "unit" } } },
        .{ .specification_unit = .{ .reference_state_id = scope.reference_state, .feature_id = .{ .bytes = "feature" }, .unit_slot_id = .{ .bytes = "unit" } } },
        .{ .semantic_review = .{ .parent_unit_owner_id = .{ .reference_global = .{ .reference_state_id = scope.reference_state, .unit_slot_id = .{ .bytes = "unit" } } }, .review_slot_id = .{ .bytes = "review" } } },
    }) |owner| {
        const base = try packets.create(std.testing.allocator, "{}", owner, if (owner == .semantic_review) .{ .semantic_review = .{ .bytes = "review" } } else .initial_generation, null);
        defer packets.release(base);
        const bound = try packets.withExactScope(std.testing.allocator, base, scope);
        defer packets.release(bound);
        try std.testing.expectError(error.InvalidModelInputPacket, packets.withExactScope(std.testing.allocator, base, .{ .reference_state = .{ .bytes = "FOREIGN" }, .occurrences = &.{} }));
    }
}

test "replay authority matches a description only to its exact current binding and catalogue maximum" {
    const Description = @import("domain/model_request_description.zig").Description;
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    fixture.registry_entry.config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16384 } } };
    const described = Description.from(&fixture.request, &fixture.provider_binding, .inference);
    try std.testing.expect(described.matchesBinding(&fixture.provider_binding));

    // A catalogue whose maximum or region moved no longer authorizes the capture.
    for ([_]@import("domain/llm_provider_contracts.zig").ValidatedProviderConfig{
        .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 4096 } } },
        .{ .aws_bedrock = .{ .region = .@"us-west-2", .family = .@"gpt-oss", .max_output_tokens = .{ .tokens = 16384 } } },
        .empty_object,
    }) |drifted| {
        fixture.registry_entry.config = drifted;
        try std.testing.expect(!described.matchesBinding(&fixture.provider_binding));
    }
    fixture.registry_entry.config = described.provider_config;
    try std.testing.expect(described.matchesBinding(&fixture.provider_binding));

    // Every other bound identity is compared too.
    var other = described;
    other.model_slot = "repair";
    try std.testing.expect(!other.matchesBinding(&fixture.provider_binding));
    other = described;
    other.provider = "openai";
    try std.testing.expect(!other.matchesBinding(&fixture.provider_binding));
    other = described;
    other.model = "other-model";
    try std.testing.expect(!other.matchesBinding(&fixture.provider_binding));
    other = described;
    other.reasoning_effort = null;
    try std.testing.expect(!other.matchesBinding(&fixture.provider_binding));
    other = described;
    other.controls.temperature = if (described.controls.temperature == null) .fixed else null;
    try std.testing.expect(!other.matchesBinding(&fixture.provider_binding));
    other = described;
    other.response_mode = if (described.response_mode == .native_schema) .prompt_only else .native_schema;
    try std.testing.expect(!other.matchesBinding(&fixture.provider_binding));
}
