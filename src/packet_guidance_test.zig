const std = @import("std");
const guidance = @import("domain/packet_guidance.zig");
const fixture = @import("test_fixtures/packet_guidance.zig");
const flow = @import("application/packet_guidance_workflow.zig");
const authority = @import("domain/required_authority.zig");
const spec = @import("domain/specification.zig");
const pipeline = @import("domain/pipeline.zig");
const compilation = @import("domain/workflow_compilation.zig");
const inventory = @import("domain/workflow_inventory.zig");
const values = @import("application/pipeline_values.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const bindings = @import("application/workflow_operation_binding.zig");

test "shipped packet guidance compiles with one valid text per registered key" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const compiled = try fixture.shipped(a);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, fixture.shipped_path, a, .limited(guidance.max_bytes));
    try std.testing.expectEqualStrings(bytes, compiled.bytes());
    try expectTexts(guidance.Guidance, compiled.guidance);
}

test "marked guidance places each wire entry under its registered key" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const marked = fixture.marked;
    // Every leaf, reached by field name or registered key, holds its own wire path.
    try expectMarks(a, guidance.Guidance, marked, "");
    // The compiled resource path yields the same guidance as the direct wire.
    const compiled = try guidance.compile(a, try fixture.markedJson(a));
    try std.testing.expectEqualDeep(marked, compiled.guidance);
}

test "packet guidance rejects missing extra mistyped empty versioned duplicate non-object and trailing documents" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const valid = try fixture.markedJson(a);
    _ = try guidance.compile(a, valid);
    const Change = struct { object: []const []const u8, key: []const u8, value: ?std.json.Value };
    const text: std.json.Value = .{ .string = "MOCK replacement" };
    for ([_]Change{
        // Missing registered entries.
        .{ .object = &.{"feature_purposes"}, .key = "scenario_coverage", .value = null },
        .{ .object = &.{"review_scope"}, .key = "collection", .value = null },
        .{ .object = &.{ "review_scope", "candidate_field" }, .key = "in_record", .value = null },
        .{ .object = &.{"support_evidence"}, .key = "selection", .value = null },
        .{ .object = &.{ "support_evidence", "question" }, .key = "required", .value = null },
        .{ .object = &.{ "reference_tasks", "token" }, .key = "after", .value = null },
        .{ .object = &.{}, .key = "summary_purpose", .value = null },
        .{ .object = &.{}, .key = "schema", .value = null },
        // Extra entries, including a feature slot owned by a record family.
        .{ .object = &.{"feature_purposes"}, .key = "acceptance_criteria", .value = text },
        .{ .object = &.{"record_fields"}, .key = "text", .value = text },
        .{ .object = &.{"review_scope"}, .key = "instruction", .value = text },
        .{ .object = &.{}, .key = "notes", .value = text },
        // Wrong wire kinds.
        .{ .object = &.{}, .key = "summary_purpose", .value = .{ .integer = 1 } },
        .{ .object = &.{"record_families"}, .key = "entity", .value = .{ .null = {} } },
        .{ .object = &.{"reference_tasks"}, .key = "signal", .value = text },
        .{ .object = &.{"review_scope"}, .key = "candidate_field", .value = text },
        .{ .object = &.{ "review_scope", "reference" }, .key = "signal", .value = .{ .integer = 2 } },
        .{ .object = &.{"support_evidence"}, .key = "question", .value = text },
        // Empty, blank and control-character texts.
        .{ .object = &.{}, .key = "summary_purpose", .value = .{ .string = "" } },
        .{ .object = &.{"repair_tails"}, .key = "value_choices", .value = .{ .string = "   " } },
        .{ .object = &.{ "reference_tasks", "conflict" }, .key = "before", .value = .{ .string = "" } },
        .{ .object = &.{"support_evidence"}, .key = "detail", .value = .{ .string = "MOCK\ndetail" } },
        .{ .object = &.{ "support_evidence", "question" }, .key = "omitted", .value = .{ .string = "MOCK\u{85}omitted" } },
        // Unsupported version.
        .{ .object = &.{}, .key = "schema", .value = .{ .string = "packet-guidance/v2" } },
    }) |change| {
        var document = try std.json.parseFromSliceLeaky(std.json.Value, a, valid, .{});
        var target = &document;
        for (change.object) |name| target = target.object.getPtr(name).?;
        if (change.value) |value| try target.object.put(a, change.key, value) else try std.testing.expect(target.object.orderedRemove(change.key));
        const changed = try std.json.Stringify.valueAlloc(a, document, .{});
        try std.testing.expectError(error.InvalidPacketGuidance, guidance.compile(a, changed));
    }
    const duplicate = try std.mem.replaceOwned(u8, a, valid, "{\"schema\":\"packet-guidance/v1\",", "{\"schema\":\"packet-guidance/v1\",\"schema\":\"packet-guidance/v1\",");
    try std.testing.expect(!std.mem.eql(u8, duplicate, valid));
    for ([_][]const u8{
        duplicate,
        "",
        "[]",
        "null",
        "\"packet-guidance/v1\"",
        try std.mem.concat(a, u8, &[_][]const u8{ "[", valid, "]" }),
        try std.mem.concat(a, u8, &[_][]const u8{ valid, "{}" }),
        try std.mem.concat(a, u8, &[_][]const u8{ valid, "x" }),
    }) |bytes| try std.testing.expectError(error.InvalidPacketGuidance, guidance.compile(a, bytes));
}

test "registered keys follow the native registries and consumers declare their guidance" {
    for (std.enums.values(authority.Slot)) |slot| {
        var feature = false;
        for (std.enums.values(authority.Kind)) |kind| feature = feature or authority.policy(.{ .kind = kind, .unit = .{ .feature = .singleton }, .slot = slot }) != null;
        try std.testing.expectEqual(feature and @import("domain/specification_authority.zig").collectionFamily(slot) == null, std.meta.stringToEnum(guidance.FeaturePurpose, @tagName(slot)) != null);
        if (@import("domain/specification_authority.zig").collectionFamily(slot) != null) try std.testing.expect(feature);
        var record = false;
        for (std.enums.values(spec.Kind)) |kind| record = record or authority.recordField(kind, slot);
        try std.testing.expectEqual(record and slot != .text, std.meta.stringToEnum(guidance.RecordField, @tagName(slot)) != null);
    }
    const Subject = std.meta.Tag(@import("domain/specification_review_subject.zig").Subject);
    const scope = std.meta.fieldNames(@FieldType(guidance.Wire, "review_scope"));
    try std.testing.expectEqual(std.meta.tags(Subject).len + guidance.shared_scope.len, scope.len);
    for (scope) |name| {
        const shared = for (guidance.shared_scope) |entry| {
            if (std.mem.eql(u8, entry, name)) break true;
        } else false;
        try std.testing.expect(shared != (std.meta.stringToEnum(Subject, name) != null));
    }
    try std.testing.expectEqualDeep(std.meta.fieldNames(@import("domain/specification_review_subject.zig").ReferenceSubject), std.meta.fieldNames(guidance.ReferenceUnit));
    for (std.meta.fieldNames(guidance.ReferenceUnit)) |name| try std.testing.expect(std.meta.stringToEnum(std.meta.Tag(authority.Unit), name) != null);

    try std.testing.expectEqualSlices(pipeline.DataKey, &.{.packet_guidance}, flow.Capture.Action.contract.produces);
    try std.testing.expectEqual(@as(usize, 1), flow.Capture.parameters.len);
    try std.testing.expectEqual(.packet_guidance, flow.Capture.parameters[0].resource_kind.?);
    try std.testing.expect(flow.Capture.parameters[0].required);
    try std.testing.expectEqual(bindings.Inspection{}, comptime bindings.inspect(flow.Capture, &.{}));
    inline for (.{
        @import("actions/reference/build_reference_reconciliation_model_input.zig").Action,
        @import("actions/reference/build_reference_reconciliation_repair_input.zig").Action,
        @import("actions/specification/build_specification_model_input.zig").Action,
        @import("actions/specification/build_specification_repair_input.zig").Action,
        @import("actions/specification/reuse_specification_review.zig").Action,
        @import("actions/specification/build_specification_support_input.zig").Action,
        @import("actions/specification/collect_specification_support.zig").Action,
        @import("actions/specification/build_specification_support_loss_input.zig").Action,
        @import("actions/specification/collect_specification_support_loss.zig").Action,
        @import("actions/specification/authorize_specification_support_repair.zig").Action,
        @import("actions/specification/build_specification_support_repair_input.zig").Action,
        @import("actions/specification/merge_specification_support_repair.zig").Action,
        @import("actions/clarification/build_required_authority_clarification_needs.zig").Action,
        @import("actions/reference/build_source_omission_repair_input.zig").Action,
        @import("actions/specification/authorize_specification_repair.zig").Action,
    }) |Action| try std.testing.expect(std.mem.indexOfScalar(pipeline.DataKey, Action.contract.requires, .packet_guidance) != null);
    // Source-omission repair presents guidance only while building its request.
    inline for (.{
        @import("actions/reference/authorize_source_omission_repair.zig").Action,
        @import("actions/reference/parse_source_omission_repair.zig").Action,
        @import("actions/reference/merge_source_extraction_repair.zig").Action,
        @import("actions/reference/merge_source_reconciliation_repair.zig").Action,
        // Coverage repair places no repair tail.
        @import("actions/specification/authorize_specification_coverage_repair.zig").Action,
    }) |Action| try std.testing.expect(std.mem.indexOfScalar(pipeline.DataKey, Action.contract.requires, .packet_guidance) == null);
    // Every advice stop revalidates its stopped packet against the run guidance.
    inline for (comptime std.enums.values(@import("domain/specification_advice_stop.zig").Scope)) |transport| {
        const stop = comptime @import("domain/specification_advice_stop.zig").contract(transport);
        try std.testing.expect(std.mem.indexOfScalar(pipeline.DataKey, stop.requires, .packet_guidance) != null);
    }
}

test "model input presents stored values with run guidance and keeps every other field" {
    const presentation = @import("domain/model_presentation.zig");
    const Proof = struct {
        label: []const u8,
        pub const model_presentation_required = "test purpose";
        pub const Presented = struct { label: []const u8, purpose: []const u8 };
        pub fn present(self: @This(), _: std.mem.Allocator, g: *const guidance.Guidance) presentation.Error!Presented {
            if (self.label.len == 0) return error.InvalidRequiredAuthority;
            return .{ .label = self.label, .purpose = g.summary_purpose };
        }
    };
    const Stored = struct { id: u32, proof: ?Proof = null, proofs: []const Proof, note: ?[]const u8 = null };
    const Plain = struct { id: u32, note: ?[]const u8 = null };
    try std.testing.expect(comptime presentation.required(Stored));
    try std.testing.expect(comptime !presentation.required(Plain));
    try std.testing.expect(presentation.Presentation(Plain) == Plain);
    const Presented = presentation.Presentation(Stored);
    try std.testing.expect(@FieldType(Presented, "proof") == ?Proof.Presented);
    try std.testing.expect(@FieldType(Presented, "proofs") == []const Proof.Presented);
    try std.testing.expect(@FieldType(Presented, "note") == ?[]const u8);
    inline for (@typeInfo(Stored).@"struct".fields, @typeInfo(Presented).@"struct".fields) |stored, presented| {
        try std.testing.expectEqualStrings(stored.name, presented.name);
        try std.testing.expectEqual(stored.default_value_ptr == null, presented.default_value_ptr == null);
    }
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const marked = &fixture.marked;
    const shown = try presentation.present(Stored, a, marked, .{ .id = 3, .proof = .{ .label = "MOCK first" }, .proofs = &.{ .{ .label = "MOCK second" }, .{ .label = "MOCK third" } } });
    try std.testing.expectEqual(@as(u32, 3), shown.id);
    try std.testing.expectEqualStrings("MOCK first", shown.proof.?.label);
    try std.testing.expectEqualStrings(marked.summary_purpose, shown.proof.?.purpose);
    for (shown.proofs, [_][]const u8{ "MOCK second", "MOCK third" }) |proof, label| {
        try std.testing.expectEqualStrings(label, proof.label);
        try std.testing.expectEqualStrings(marked.summary_purpose, proof.purpose);
    }
    try std.testing.expect(shown.note == null);
    try std.testing.expect((try presentation.present(Stored, a, marked, .{ .id = 4, .proofs = &.{} })).proof == null);
    // A stored value whose own presentation rejects stops the whole presentation.
    try std.testing.expectError(error.InvalidRequiredAuthority, presentation.present(Stored, a, marked, .{ .id = 5, .proofs = &.{.{ .label = "" }} }));
}

test "a value-choice correction ends with its workflow repair tail" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Issue = @import("domain/typed_text.zig").Issue;
    const choices: @import("domain/specification_provenance.zig").ValueChoices = .{ .exact_copy = &.{} };
    const rejected: Issue = .{ .reason = .unknown_passive, .first_node = 0, .last_node = 0, .rejected_passive = .{ .ordinal = 3 } };
    try std.testing.expectEqualStrings("Validation failed: passive reference ID 3 is unavailable for this field's authorized evidence. Return source-backed prose without reference handles. MOCK repair_tails.value_choices", try choices.correction(a, &fixture.marked, rejected));
    const exact: Issue = .{ .reason = .unknown_exact, .first_node = 0, .last_node = 0, .rejected_exact = .{ .claim_id = .{ .ordinal = 7 } } };
    try std.testing.expectEqualStrings("Validation failed: exact-copy claim 7 is unavailable for this field's authorized evidence. Return source-backed prose without reference handles. MOCK repair_tails.value_choices", try choices.correction(a, &fixture.marked, exact));
    // Without a rejected handle the native description stands alone, with no tail.
    const unnamed: Issue = .{ .reason = .unknown_passive, .first_node = 0, .last_node = 0 };
    try std.testing.expectEqualStrings(unnamed.description(), try choices.correction(a, &fixture.marked, unnamed));
}

test "review scopes and evidence instructions place their workflow entries" {
    const descriptions = @import("domain/required_authority_description.zig");
    const evidence = @import("domain/specification_support_evidence.zig");
    const presentation = @import("domain/model_presentation.zig");
    const marked = &fixture.marked;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const preservation = descriptions.sourceReviewScope(marked, .{ .source_preservation = .{} });
    try std.testing.expectEqualStrings(marked.review_scope.original_sources, preservation.original_sources);
    try std.testing.expectEqualStrings(marked.review_scope.derived_evidence, preservation.derived_evidence);
    try std.testing.expectEqualStrings(marked.review_scope.source_preservation, preservation.instruction);
    try std.testing.expectEqualStrings(marked.review_scope.reference.get(.source), descriptions.sourceReviewScope(marked, .{ .reference = .{ .source = .{ .ordinal = 1 } } }).instruction);
    // Each native evidence rule names one entry; model input presents its text.
    const entries = [_]struct { entry: evidence.Instruction.Entry, text: []const u8 }{
        .{ .entry = .selection, .text = marked.support_evidence.selection },
        .{ .entry = .detail, .text = marked.support_evidence.detail },
        .{ .entry = .obligation, .text = marked.support_evidence.obligation },
        .{ .entry = .authority_gap, .text = marked.support_evidence.authority_gap },
        .{ .entry = .{ .question = .retained_gap }, .text = marked.support_evidence.question.get(.retained_gap) },
        .{ .entry = .{ .question = .required }, .text = marked.support_evidence.question.get(.required) },
        .{ .entry = .{ .question = .omitted }, .text = marked.support_evidence.question.get(.omitted) },
    };
    for (entries) |entry| try std.testing.expectEqualStrings(entry.text, try presentation.present(evidence.Instruction, a, marked, .{ .entry = entry.entry }));
    try std.testing.expect(comptime presentation.required(evidence.Rule.Guidance));
    try std.testing.expect(@FieldType(presentation.Presentation(evidence.Rule.Guidance), "instruction") == []const u8);
    try std.testing.expect(@FieldType(presentation.Presentation(evidence.DetailRule.Guidance), "instruction") == []const u8);
    // The native rule chooses the question entry from the retained finding.
    const rules = std.enums.EnumArray(authority.Finding, guidance.QuestionRule).init(.{
        .supported = .omitted,
        .ambiguous = .required,
        .conflicting = .required,
        .unsupported = .required,
        .candidate_omission = .omitted,
        .candidate_invalid = .retained_gap,
        .inconclusive = .omitted,
    });
    for (std.enums.values(authority.Finding)) |finding| try std.testing.expectEqual(rules.get(finding), evidence.questionRule(finding));
}

test "capture publishes its bound compiled guidance as owned run data and rejects other bindings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const compiled = try fixture.shipped(a);
    const resources = [_]compilation.CompiledResource{
        .{ .id = .{ .bytes = "packet-guidance" }, .content = .{ .packet_guidance = compiled } },
        .{ .id = .{ .bytes = "prompt" }, .content = .{ .prompt = "Generate one result." } },
    };
    const contract = flow.Capture.Action.contract;
    var step: compilation.CompiledStep = .{ .id = .{ .bytes = "guidance" }, .operation_id = .{ .bytes = contract.id }, .parameters = &.{.{ .id = .{ .bytes = "guidance" }, .value = .{ .resource = .{ .bytes = "packet-guidance" } } }}, .requires = contract.requires, .produces = contract.produces, .replaces = contract.replaces, .invalidates = contract.invalidates, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
    var node: flow.Capture = .{ .allocator = std.testing.allocator };
    const log: pipeline.WorkflowLog = .init(try @import("domain/telemetry.zig").WorkflowShortcode.parse("GUID"));
    const captured = try flow.Capture.invoke(&node, .{ .step = .{ .data = .{}, .step = &step, .resources = &resources, .model_binding = null, .log = log } });
    try std.testing.expectEqual(.ok, captured.outcome);
    const value = captured.delta.data_writes[@intFromEnum(flow.schema.key)].?;
    defer values.destroy(value);
    const published = try flow.read(&.{ .slots = captured.delta.data_writes });
    try std.testing.expectEqualDeep(compiled.guidance, published.*);
    try std.testing.expect(published.summary_purpose.ptr != compiled.guidance.summary_purpose.ptr);
    step.parameters = &.{.{ .id = .{ .bytes = "guidance" }, .value = .{ .resource = .{ .bytes = "prompt" } } }};
    try std.testing.expectError(error.OperationExecutionFailed, flow.Capture.invoke(&node, .{ .step = .{ .data = .{}, .step = &step, .resources = &resources, .model_binding = null, .log = log } }));
    step.parameters = &.{};
    try std.testing.expectError(error.OperationExecutionFailed, flow.Capture.invoke(&node, .{ .step = .{ .data = .{}, .step = &step, .resources = &resources, .model_binding = null, .log = log } }));
}

test "the compiler binds packet guidance only through its capture step and checked resource" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try fixture.markedJson(a);
    const guidance_file: Resource = .{ .path = "packet-guidance.json", .bytes = bytes };
    const prompt_file: Resource = .{ .path = "prompt.md", .bytes = "Generate one result." };
    const graph = try compileGuided(a, guided_workflow, &.{ guidance_file, prompt_file });
    const resource = for (graph.authority.resources) |item| {
        if (std.mem.eql(u8, item.id.bytes, "packet-guidance")) break item;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqual(.packet_guidance, resource.kind());
    try std.testing.expectEqualStrings(bytes, resource.bytes());
    try std.testing.expectEqualDeep(fixture.marked, resource.content.packet_guidance.guidance);
    // The registry copy reparses the same resource.
    const copy = try resource.clone(a, null);
    try std.testing.expectEqualDeep(resource.content.packet_guidance.guidance, copy.content.packet_guidance.guidance);

    // A registered entry is missing from the resource.
    var document = try std.json.parseFromSliceLeaky(std.json.Value, a, bytes, .{});
    try std.testing.expect(document.object.getPtr("record_fields").?.object.orderedRemove("relationship"));
    const missing: Resource = .{ .path = guidance_file.path, .bytes = try std.json.Stringify.valueAlloc(a, document, .{}) };
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileGuided(a, guided_workflow, &.{ missing, prompt_file }));
    // The guidance alias is also bound as a prompt.
    const as_prompt = try replace(a, try replace(a, guided_workflow, "with: {prompt: prompt}", "with: {prompt: packet-guidance}"), "  prompt: prompt.md\n", "");
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileGuided(a, as_prompt, &.{guidance_file}));
    // A prompt alias is bound as guidance.
    const as_guidance = try replace(a, try replace(a, guided_workflow, "with: {guidance: packet-guidance}", "with: {guidance: prompt}"), "  packet-guidance: packet-guidance.json\n", "");
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileGuided(a, as_guidance, &.{prompt_file}));
    // The capture step omits its resource parameter.
    const unbound = try replace(a, try replace(a, guided_workflow, "    with: {guidance: packet-guidance}\n", ""), "  packet-guidance: packet-guidance.json\n", "");
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileGuided(a, unbound, &.{prompt_file}));
    // A consumer has no upstream capture.
    const uncaptured = try replace(a, try replace(a, try replace(a, guided_workflow, guided_capture_step, ""), "start: guidance", "start: consume"), "  packet-guidance: packet-guidance.json\n", "");
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, compileGuided(a, uncaptured, &.{prompt_file}));
}

const guided_capture_step =
    \\  guidance:
    \\    use: capture-packet-guidance
    \\    with: {guidance: packet-guidance}
    \\    on: {ok: consume, failed: end.failed}
    \\
;
const guided_workflow =
    \\schema: workflow/v1
    \\id: guided-check
    \\version: 1
    \\shortcode: GUID
    \\invoke: test.empty
    \\policy: test.guided@1
    \\start: guidance
    \\resources:
    \\  packet-guidance: packet-guidance.json
    \\  prompt: prompt.md
    \\steps:
    \\
++ guided_capture_step ++
    \\  consume:
    \\    use: test.consume
    \\    with: {prompt: prompt}
    \\    on: {ok: end.ok}
    \\
;

const Resource = struct { path: []const u8, bytes: []const u8 };

var capture_node: flow.Capture = .{ .allocator = std.testing.allocator };
const guided_registry: operations.Registry = .{
    .operations = &.{
        .{ .contract = .{ .id = "test.empty", .kind = .invocation, .produces = &.{.workflow_invocation}, .outcomes = &.{.ok}, .side_effect = .none }, .binding = bindings.bind(void, null, unusedOperation) },
        @import("composition/native_workflow_operations.zig").entry(flow.Capture, &capture_node),
        .{ .contract = .{
            .id = "test.consume",
            .kind = .step,
            .parameters = &.{.{ .id = "prompt", .kind = .resource, .required = true, .workflow_definition_safe = true, .resource_kind = .prompt }},
            .requires = &.{.packet_guidance},
            .outcomes = &.{.ok},
            .side_effect = .none,
        }, .binding = bindings.bind(void, null, unusedOperation) },
    },
    .policies = &.{.{ .id = "test.guided@1", .allowed_capabilities = &.{}, .allowed_terminal_outcomes = &.{ .ok, .failed } }},
    .gates = &.{},
    .data_schemas = &.{ values.schema(.workflow_invocation, u32, 1, 32), flow.schema },
};

fn compileGuided(a: std.mem.Allocator, yaml: []const u8, resources: []const Resource) !compilation.CompiledWorkflow {
    var parser: @import("adapters/parsers/workflow_definitions.zig").Adapter = .{};
    const raw = try (@import("actions/workflow/parse_workflow_definitions.zig").Action{ .parser = parser.parser() }).execute(a, &.{.{ .ordinal = 1, .bytes = yaml }});
    const definitions = try (@import("actions/workflow/validate_workflow_definition_schema.zig").Action{}).execute(a, raw);
    const descriptors = try a.alloc(inventory.InventoryDescriptor, resources.len + 1);
    const accounts = try a.alloc(inventory.InventoryAccount, resources.len + 1);
    const resource_ordinals = try a.alloc(u16, resources.len);
    const captures = try a.alloc(inventory.Capture, resources.len);
    descriptors[0] = .{ .path = "guided.workflow.yaml", .kind = .file, .identity = .{ .filesystem_id = 1, .file_id = 1 }, .size = yaml.len };
    accounts[0] = .{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition };
    for (resources, 0..) |resource, index| {
        const ordinal: u16 = @intCast(index + 2);
        descriptors[index + 1] = .{ .path = resource.path, .kind = .file, .identity = .{ .filesystem_id = 1, .file_id = ordinal }, .size = resource.bytes.len };
        accounts[index + 1] = .{ .ordinal = ordinal, .path = resource.path, .disposition = .resource };
        resource_ordinals[index] = ordinal;
        captures[index] = .{ .ordinal = ordinal, .bytes = resource.bytes };
    }
    const source: inventory.Inventory = .{ .capability = undefined, .descriptors = descriptors, .accounts = accounts, .definition_ordinals = &.{1}, .resource_ordinals = resource_ordinals };
    const manifest = try (@import("actions/workflow/resolve_workflow_resources.zig").Action{}).execute(a, source, definitions);
    var schemas: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
    const graphs = try (@import("actions/workflow/compile_workflow_graphs.zig").Action{ .registry = &guided_registry, .result_schema_compiler = schemas.compiler() }).execute(a, definitions, source, manifest, captures);
    _ = try (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(a, graphs);
    return graphs[0];
}

fn replace(a: std.mem.Allocator, source: []const u8, needle: []const u8, replacement: []const u8) ![]const u8 {
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, source, needle));
    return std.mem.replaceOwned(u8, a, source, needle, replacement);
}

fn unusedOperation(_: ?*void, _: operations.Input) operations.Error!@import("domain/workflow_execution.zig").Candidate {
    return error.OperationExecutionFailed;
}

fn expectMarks(a: std.mem.Allocator, comptime T: type, value: T, path: []const u8) !void {
    if (T == []const u8) return std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "MOCK {s}", .{path}), value);
    if (@hasDecl(T, "Indexer")) {
        for (std.enums.values(T.Key)) |key| try expectMarks(a, T.Value, value.get(key), try std.fmt.allocPrint(a, "{s}.{s}", .{ path, @tagName(key) }));
    } else inline for (@typeInfo(T).@"struct".fields) |field| {
        try expectMarks(a, field.type, @field(value, field.name), if (path.len == 0) field.name else try std.fmt.allocPrint(a, "{s}.{s}", .{ path, field.name }));
    }
}

fn expectTexts(comptime T: type, value: T) !void {
    if (T == []const u8) return std.testing.expect(guidance.validText(value));
    const info = @typeInfo(T).@"struct";
    if (@hasDecl(T, "Indexer")) {
        for (value.values) |entry| try expectTexts(@TypeOf(entry), entry);
    } else inline for (info.fields) |field| try expectTexts(field.type, @field(value, field.name));
}
