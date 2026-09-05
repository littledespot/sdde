const std = @import("std");
const parse = @import("actions/workflow/parse_workflow_definitions.zig");
const validate_schema = @import("actions/workflow/validate_workflow_definition_schema.zig");
const resolve_resources = @import("actions/workflow/resolve_workflow_resources.zig");
const compile = @import("actions/workflow/compile_workflow_graphs.zig");
const validate_graphs = @import("actions/workflow/validate_compiled_workflow_graphs.zig");
const parser_adapter = @import("adapters/parsers/workflow_definitions.zig");
const execution = @import("domain/workflow_execution.zig");
const workflow = @import("domain/workflow.zig");
const inventory = @import("domain/workflow_inventory.zig");
const filesystem_identity = @import("domain/filesystem_identity.zig");
const operation_registry = @import("ports/workflow_operation_registry.zig");
const operation_bindings = @import("application/workflow_operation_binding.zig");
const binding_fixture = @import("workflow_binding_test_fixture.zig");
const values = @import("application/pipeline_values.zig");
const gate_module = @import("domain/workflow_gate.zig");

test "concise resources and native parameters compile into immutable operation authority" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var yaml_parser: parser_adapter.Adapter = .{};
    const captures = [_]inventory.Capture{.{ .ordinal = 1, .bytes = resource_workflow }};
    const raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(arena.allocator(), &captures);
    const definitions = try (validate_schema.Action{}).execute(arena.allocator(), raw);
    const inventory_value = testInventory();
    const manifest = try (resolve_resources.Action{}).execute(arena.allocator(), inventory_value, definitions);
    const resource_captures = [_]inventory.Capture{
        .{ .ordinal = 3, .bytes = "Generate one result." },
        .{ .ordinal = 5, .bytes = "{\"type\":\"object\"}" },
    };
    const graphs = try (compile.Action{ .registry = &operations }).execute(
        arena.allocator(),
        definitions,
        inventory_value,
        manifest,
        &resource_captures,
    );
    _ = try (validate_graphs.Action{}).execute(arena.allocator(), graphs);
    const graph = graphs[0];
    try std.testing.expectEqualStrings("custom-generation", graph.authority.workflow_id.bytes);
    try std.testing.expectEqual(@as(usize, 2), graph.authority.resources.len);
    try std.testing.expectEqualStrings("Generate one result.", graph.authority.resources[0].bytes);
    try std.testing.expectEqual(@as(u32, 2), graph.authority.steps[0].retry_authority.?.limit.value);
    try std.testing.expectEqual(@as(u64, 1000), graph.authority.total_model_token_budget.value);
    try std.testing.expectEqual(@as(usize, 6), graph.authority.maximum_step_executions);
    var slots: usize = 0;
    var resource_parameters: usize = 0;
    for (graph.authority.steps[0].parameters) |parameter| switch (parameter.value) {
        .model_slot => |slot| {
            slots += 1;
            try std.testing.expectEqualStrings("spec-generation", slot.bytes);
        },
        .resource => resource_parameters += 1,
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 1), slots);
    try std.testing.expectEqual(@as(usize, 2), resource_parameters);
    try std.testing.expectEqual(@as(u64, 200), graph.authority.steps[0].model.?.capacity.canonical.maximum_output_tokens);
    try std.testing.expectEqualStrings("model-ready@1", graph.authority.steps[0].gates[0].id.bytes);
    try std.testing.expectEqualStrings("model-provider", graph.authority.steps[0].capabilities[0]);
}

test "unknown operations and unguarded cycles reject the complete graph" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var yaml_parser: parser_adapter.Adapter = .{};

    const unknown_capture = [_]inventory.Capture{.{ .ordinal = 1, .bytes = unknown_operation_workflow }};
    const unknown_raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(arena.allocator(), &unknown_capture);
    const unknown = try (validate_schema.Action{}).execute(arena.allocator(), unknown_raw);
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (compile.Action{ .registry = &operations }).execute(
            arena.allocator(),
            unknown,
            emptyInventory(),
            .{ .bindings = &.{}, .resource_ordinals = &.{} },
            &.{},
        ),
    );

    const cycle_capture = [_]inventory.Capture{.{ .ordinal = 1, .bytes = unguarded_cycle_workflow }};
    const cycle_raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(arena.allocator(), &cycle_capture);
    const cycle = try (validate_schema.Action{}).execute(arena.allocator(), cycle_raw);
    const graphs = try (compile.Action{ .registry = &operations }).execute(
        arena.allocator(),
        cycle,
        emptyInventory(),
        .{ .bindings = &.{}, .resource_ordinals = &.{} },
        &.{},
    );
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (validate_graphs.Action{}).execute(arena.allocator(), graphs),
    );
}

test "YAML model bounds reject omissions invalid scalars unknown modes and policy authority" {
    const substitutions = [_][2][]const u8{
        .{ "input-bytes: 4096, ", "" },
        .{ "output-bytes: 1024, ", "" },
        .{ "input-tokens: 1000, ", "" },
        .{ "output-tokens: 200, ", "" },
        .{ ", response-mode: prompt-only", "" },
        .{ "input-bytes: 4096", "input-bytes: 0" },
        .{ "output-tokens: 200", "output-tokens: -1" },
        .{ "input-bytes: 4096", "input-bytes: 4294967296" },
        .{ "input-tokens: 1000", "input-tokens: many" },
        .{ "response-mode: prompt-only", "response-mode: automatic" },
        .{ "response-mode: prompt-only", "response-mode: prompt-only, temperature: 1001" },
    };
    for (substitutions) |replacement| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const yaml = try std.mem.replaceOwned(u8, arena.allocator(), resource_workflow, replacement[0], replacement[1]);
        try std.testing.expect(!std.mem.eql(u8, yaml, resource_workflow));
        var yaml_parser: parser_adapter.Adapter = .{};
        const raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(arena.allocator(), &.{.{ .ordinal = 1, .bytes = yaml }});
        const definitions = try (validate_schema.Action{}).execute(arena.allocator(), raw);
        const manifest = try (resolve_resources.Action{}).execute(arena.allocator(), testInventory(), definitions);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (compile.Action{ .registry = &operations }).execute(
            arena.allocator(),
            definitions,
            testInventory(),
            manifest,
            &.{
                .{ .ordinal = 3, .bytes = "Generate one result." },
                .{ .ordinal = 5, .bytes = "{\"type\":\"object\"}" },
            },
        ));
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var yaml_parser: parser_adapter.Adapter = .{};
    const yaml = try std.mem.replaceOwned(u8, arena.allocator(), resource_workflow, "policy: test.model-policy@1", "policy: { id: test.model-policy@1, input-tokens: 1000 }");
    const raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(arena.allocator(), &.{.{ .ordinal = 1, .bytes = yaml }});
    try std.testing.expectError(error.WorkflowDefinitionSchemaInvalid, (validate_schema.Action{}).execute(arena.allocator(), raw));
}

test "compiler rejects parameter outcome gate and capability violations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var yaml_parser: parser_adapter.Adapter = .{};
    const inventory_value = testInventory();
    const resource_captures = [_]inventory.Capture{
        .{ .ordinal = 3, .bytes = "Generate one result." },
        .{ .ordinal = 5, .bytes = "{\"type\":\"object\"}" },
    };

    inline for (.{
        wrong_parameter_workflow,
        missing_retry_limit_workflow,
        negative_retry_limit_workflow,
        excessive_retry_limit_workflow,
        missing_outcome_workflow,
    }) |yaml| {
        const raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(
            arena.allocator(),
            &.{.{ .ordinal = 1, .bytes = yaml }},
        );
        const definitions = try (validate_schema.Action{}).execute(arena.allocator(), raw);
        const manifest = try (resolve_resources.Action{}).execute(arena.allocator(), inventory_value, definitions);
        try std.testing.expectError(
            error.WorkflowGraphCompileInvalid,
            (compile.Action{ .registry = &operations }).execute(
                arena.allocator(),
                definitions,
                inventory_value,
                manifest,
                &resource_captures,
            ),
        );
    }

    const accepted_raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(
        arena.allocator(),
        &.{.{ .ordinal = 1, .bytes = resource_workflow }},
    );
    const accepted = try (validate_schema.Action{}).execute(arena.allocator(), accepted_raw);
    const accepted_manifest = try (resolve_resources.Action{}).execute(arena.allocator(), inventory_value, accepted);
    const restrictive: operation_registry.Registry = .{
        .model_capacity = @import("model_contract_test_fixture.zig").capacity,
        .operations = &operation_entries,
        .policies = &.{.{
            .id = "test.model-policy@1",
            .allowed_capabilities = &.{},
            .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled },
            .total_model_token_budget = .{ .value = 1000 },
        }},
        .gates = operations.gates,
        .data_schemas = operations.data_schemas,
    };
    try std.testing.expect(restrictive.validate());
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (compile.Action{ .registry = &restrictive }).execute(
            arena.allocator(),
            accepted,
            inventory_value,
            accepted_manifest,
            &resource_captures,
        ),
    );
    var missing_gate = operations;
    missing_gate.gates = &.{};
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (compile.Action{ .registry = &missing_gate }).execute(
            arena.allocator(),
            accepted,
            inventory_value,
            accepted_manifest,
            &resource_captures,
        ),
    );

    const hidden_raw = try (parse.Action{ .parser = yaml_parser.parser() }).execute(
        arena.allocator(),
        &.{.{ .ordinal = 1, .bytes = hidden_retry_limit_workflow }},
    );
    const hidden = try (validate_schema.Action{}).execute(arena.allocator(), hidden_raw);
    try std.testing.expectError(
        error.WorkflowGraphCompileInvalid,
        (compile.Action{ .registry = &operations }).execute(
            arena.allocator(),
            hidden,
            emptyInventory(),
            .{ .bindings = &.{}, .resource_ordinals = &.{} },
            &.{},
        ),
    );
}

const resource_workflow =
    \\schema: workflow/v1
    \\id: custom-generation
    \\version: 1
    \\shortcode: CSTM
    \\invoke: test.empty@1
    \\policy: test.model-policy@1
    \\start: validate
    \\resources:
    \\  prompt: prompts/generate.md
    \\  result-schema: schemas/result.json
    \\steps:
    \\  generate:
    \\    use: model.generate@1
    \\    with: { slot: spec-generation, prompt: prompt, result-schema: result-schema, retry-limit: 2, input-bytes: 4096, output-bytes: 1024, input-tokens: 1000, output-tokens: 200, response-mode: prompt-only }
    \\    on: { ok: end.ok, invalid: generate, failed: end.failed, cancelled: end.cancelled }
    \\  validate: { use: test.validate@1, on: { ok: generate } }
;

const unknown_operation_workflow =
    \\schema: workflow/v1
    \\id: unknown-operation
    \\version: 1
    \\shortcode: UNKN
    \\invoke: test.empty@1
    \\policy: test.safe@1
    \\start: run
    \\steps:
    \\  run:
    \\    use: source.only@1
    \\    on: { ok: end.ok }
;

const wrong_parameter_workflow =
    \\schema: workflow/v1
    \\id: custom-generation
    \\version: 1
    \\shortcode: CSTM
    \\invoke: test.empty@1
    \\policy: test.model-policy@1
    \\start: generate
    \\resources: { prompt: prompts/generate.md, result-schema: schemas/result.json }
    \\steps:
    \\  generate:
    \\    use: model.generate@1
    \\    with: { slot: spec-generation, prompt: prompt, result-schema: result-schema, retry-limit: two, input-bytes: 4096, output-bytes: 1024, input-tokens: 1000, output-tokens: 200, response-mode: prompt-only }
    \\    on: { ok: end.ok, invalid: generate, failed: end.failed, cancelled: end.cancelled }
;

const missing_retry_limit_workflow =
    \\schema: workflow/v1
    \\id: custom-generation
    \\version: 1
    \\shortcode: CSTM
    \\invoke: test.empty@1
    \\policy: test.model-policy@1
    \\start: generate
    \\resources: { prompt: prompts/generate.md, result-schema: schemas/result.json }
    \\steps:
    \\  generate:
    \\    use: model.generate@1
    \\    with: { slot: spec-generation, prompt: prompt, result-schema: result-schema, input-bytes: 4096, output-bytes: 1024, input-tokens: 1000, output-tokens: 200, response-mode: prompt-only }
    \\    on: { ok: end.ok, invalid: generate, failed: end.failed, cancelled: end.cancelled }
;

const negative_retry_limit_workflow =
    \\schema: workflow/v1
    \\id: custom-generation
    \\version: 1
    \\shortcode: CSTM
    \\invoke: test.empty@1
    \\policy: test.model-policy@1
    \\start: generate
    \\resources: { prompt: prompts/generate.md, result-schema: schemas/result.json }
    \\steps:
    \\  generate:
    \\    use: model.generate@1
    \\    with: { slot: spec-generation, prompt: prompt, result-schema: result-schema, retry-limit: -1, input-bytes: 4096, output-bytes: 1024, input-tokens: 1000, output-tokens: 200, response-mode: prompt-only }
    \\    on: { ok: end.ok, invalid: generate, failed: end.failed, cancelled: end.cancelled }
;

const excessive_retry_limit_workflow =
    \\schema: workflow/v1
    \\id: custom-generation
    \\version: 1
    \\shortcode: CSTM
    \\invoke: test.empty@1
    \\policy: test.model-policy@1
    \\start: generate
    \\resources: { prompt: prompts/generate.md, result-schema: schemas/result.json }
    \\steps:
    \\  generate:
    \\    use: model.generate@1
    \\    with: { slot: spec-generation, prompt: prompt, result-schema: result-schema, retry-limit: 4, input-bytes: 4096, output-bytes: 1024, input-tokens: 1000, output-tokens: 200, response-mode: prompt-only }
    \\    on: { ok: end.ok, invalid: generate, failed: end.failed, cancelled: end.cancelled }
;

const missing_outcome_workflow =
    \\schema: workflow/v1
    \\id: custom-generation
    \\version: 1
    \\shortcode: CSTM
    \\invoke: test.empty@1
    \\policy: test.model-policy@1
    \\start: generate
    \\resources: { prompt: prompts/generate.md, result-schema: schemas/result.json }
    \\steps:
    \\  generate:
    \\    use: model.generate@1
    \\    with: { slot: spec-generation, prompt: prompt, result-schema: result-schema, retry-limit: 2, input-bytes: 4096, output-bytes: 1024, input-tokens: 1000, output-tokens: 200, response-mode: prompt-only }
    \\    on: { ok: end.ok, invalid: generate, failed: end.failed }
;

const unguarded_cycle_workflow =
    \\schema: workflow/v1
    \\id: unguarded-cycle
    \\version: 1
    \\shortcode: CYCL
    \\invoke: test.empty@1
    \\policy: test.safe@1
    \\start: run
    \\steps:
    \\  run:
    \\    use: test.retry@1
    \\    on: { ok: end.ok, invalid: run }
;

const hidden_retry_limit_workflow =
    \\schema: workflow/v1
    \\id: hidden-retry
    \\version: 1
    \\shortcode: HIDN
    \\invoke: test.empty@1
    \\policy: test.safe@1
    \\start: run
    \\steps:
    \\  run:
    \\    use: test.retry@1
    \\    with: { retry-limit: 1 }
    \\    on: { ok: end.ok, invalid: run }
;

const descriptors = [_]inventory.InventoryDescriptor{
    .{ .path = "custom.workflow.yaml", .kind = .file, .identity = filesystem_identity.FileIdentity{ .filesystem_id = 1, .file_id = 1 }, .size = resource_workflow.len },
    .{ .path = "prompts", .kind = .directory, .identity = filesystem_identity.FileIdentity{ .filesystem_id = 1, .file_id = 2 } },
    .{ .path = "prompts/generate.md", .kind = .file, .identity = filesystem_identity.FileIdentity{ .filesystem_id = 1, .file_id = 3 }, .size = 20 },
    .{ .path = "schemas", .kind = .directory, .identity = filesystem_identity.FileIdentity{ .filesystem_id = 1, .file_id = 4 } },
    .{ .path = "schemas/result.json", .kind = .file, .identity = filesystem_identity.FileIdentity{ .filesystem_id = 1, .file_id = 5 }, .size = 17 },
};
const accounts = [_]inventory.InventoryAccount{
    .{ .ordinal = 1, .path = descriptors[0].path, .disposition = .definition },
    .{ .ordinal = 2, .path = descriptors[1].path, .disposition = .directory },
    .{ .ordinal = 3, .path = descriptors[2].path, .disposition = .resource },
    .{ .ordinal = 4, .path = descriptors[3].path, .disposition = .directory },
    .{ .ordinal = 5, .path = descriptors[4].path, .disposition = .resource },
};

fn testInventory() inventory.Inventory {
    return .{
        .capability = undefined,
        .descriptors = &descriptors,
        .accounts = &accounts,
        .definition_ordinals = &.{1},
        .resource_ordinals = &.{ 3, 5 },
    };
}
fn emptyInventory() inventory.Inventory {
    return .{
        .capability = undefined,
        .descriptors = &.{},
        .accounts = &.{},
        .definition_ordinals = &.{},
        .resource_ordinals = &.{},
    };
}

const operation_entries = [_]operation_registry.Entry{
    .{
        .contract = .{ .id = "test.empty@1", .kind = .invocation, .produces = &.{.workflow_invocation}, .outcomes = &.{.ok}, .side_effect = .none },
        .binding = operation_bindings.bind(void, null, unusedOperation),
    },
    .{
        .contract = .{
            .id = "model.generate@1",
            .kind = .step,
            .model_capacity = @import("model_contract_test_fixture.zig").capacity,
            .parameters = &([_]@import("domain/workflow_operation.zig").ParameterDescriptor{
                .{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
                .{ .id = "prompt", .kind = .resource, .required = true, .workflow_definition_safe = true, .resource_kind = .prompt },
                .{ .id = "result-schema", .kind = .resource, .required = true, .workflow_definition_safe = true, .resource_kind = .result_schema },
                .{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = 3 },
            } ++ @import("domain/workflow_model.zig").parameters),
            .outcomes = &.{ .ok, .invalid, .failed, .cancelled },
            .side_effect = .none,
            .gates = &.{"model-ready@1"},
            .retry_limit = .{ .maximum = 3 },
        },
        .binding = operation_bindings.bind(binding_fixture.ModelContext, &binding_fixture.model_context, binding_fixture.unusedModel),
    },
    .{
        .contract = .{ .id = "test.retry@1", .kind = .step, .outcomes = &.{ .ok, .invalid }, .side_effect = .none },
        .binding = operation_bindings.bind(void, null, unusedOperation),
    },
    .{
        .contract = .{ .id = "test.validate@1", .kind = .step, .requires = &.{.workflow_invocation}, .produces = &.{.workflow_operation_registry_evidence}, .outcomes = &.{.ok}, .side_effect = .none },
        .binding = operation_bindings.bind(void, null, unusedOperation),
    },
};

const operations: operation_registry.Registry = .{
    .model_capacity = @import("model_contract_test_fixture.zig").capacity,
    .operations = &operation_entries,
    .policies = &.{
        .{ .id = "test.safe@1", .allowed_capabilities = &.{}, .allowed_terminal_outcomes = &.{.ok}, .total_model_token_budget = .{ .value = 1000 } },
        .{ .id = "test.model-policy@1", .allowed_capabilities = &.{"model-provider"}, .allowed_terminal_outcomes = &.{ .ok, .failed, .cancelled }, .total_model_token_budget = .{ .value = 1000 } },
    },
    .gates = &.{.{ .id = .{ .bytes = "model-ready@1" }, .issuer = .{ .bytes = "test.validate@1" }, .evidence = .workflow_operation_registry_evidence, .authority = &.{.workflow_invocation} }},
    .data_schemas = &.{ values.schema(.workflow_invocation, u32, 1, 32), values.schema(.workflow_operation_registry_evidence, gate_module.Decision, 1, 32) },
};

fn unusedOperation(_: ?*void, _: operation_registry.Input) operation_registry.Error!execution.Candidate {
    return error.OperationExecutionFailed;
}
