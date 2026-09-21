const std = @import("std");
const requests = @import("application/model_request_workflow.zig");
const native = @import("composition/model_request_operations.zig");
const core = @import("composition/core_workflow_operations.zig");
const bindings = @import("application/workflow_operation_binding.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const runner_module = @import("application/workflow_pipeline_runner.zig");
const engine = @import("application/workflow_engine_orchestrator.zig");
const children = @import("application/workflow_engine_child_bindings.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const inventory = @import("domain/workflow_inventory.zig");
const pipeline = @import("domain/pipeline.zig");
const execution = @import("domain/workflow_execution.zig");
const values = @import("application/pipeline_values.zig");
const handoff = @import("domain/model_request_handoff.zig");
const identity = @import("domain/model_request_identity.zig");
const registry = @import("domain/llm_provider_registry.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const roots = @import("domain/bootstrap_root_registry.zig");
const attempt_accounting = @import("domain/model_attempt_accounting.zig");
const attempt_values = @import("application/workflow_model_accounting.zig");
const lifecycle = @import("domain/provider_operation_lifecycle.zig");
const provider = @import("domain/llm_provider_operation.zig");
const authorization_workflow = @import("application/provider_authorization_workflow.zig");
const authorization_result = @import("domain/provider_authorization_result.zig");
const authorization_port = @import("ports/provider_operation_authorization.zig");
const request_lifecycle_workflow = @import("application/model_request_lifecycle_workflow.zig");
const operation_lifecycle_workflow = @import("application/provider_operation_lifecycle_workflow.zig");
const completion_workflow = @import("application/provider_operation_completion_workflow.zig");
const termination_workflow = @import("application/provider_operation_termination_workflow.zig");
const request_completion = @import("application/model_request_completion_workflow.zig");
const request_termination = @import("application/model_request_termination_workflow.zig");
const model_invocation = @import("application/model_invocation_workflow.zig");
const invocation_result = @import("domain/model_invocation_result.zig").For(.inference);
const observation_workflow = @import("application/provider_observation_workflow.zig");
const envelope_workflow = @import("application/model_envelope_workflow.zig");
const payload_workflow = @import("application/model_payload_schema_workflow.zig");
const payload_validation = @import("domain/model_payload_schema.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const lease_port = @import("ports/provider_authorization_lease.zig");
const count_observation = @import("application/model_token_count_observation_workflow.zig");
const count_result = @import("domain/model_invocation_result.zig").For(.input_token_count);

const yaml =
    \\schema: workflow/v1
    \\id: arbitrary-request
    \\version: 1
    \\shortcode: PREP
    \\invoke: core.empty-invocation
    \\policy: core.capability-free@1
    \\start: initialize
    \\resources: { prompt: prompt.md, result: result.json, input: input.txt }
    \\steps:
    \\  initialize: { use: build-initial-model-request-identity-ledger, on: { ok: origin, failed: end.failed } }
    \\  origin:
    \\    use: assign-model-request-id
    \\    with: { slot: selected, prompt: prompt, result-schema: result, input: input }
    \\    on: { ok: validate, failed: end.failed }
    \\  validate: { use: validate-model-request-binding, on: { ok: build, failed: end.failed } }
    \\  build: { use: build-model-request, on: { ok: observe, failed: end.failed } }
    \\  observe: { use: test.observe-request, on: { ok: end.ok } }
;
const prompt_bytes = "Return the requested object.";
const schema_bytes = "{\"type\":\"object\",\"properties\":{\"answer\":{\"type\":\"string\",\"maxLength\":20000}},\"required\":[\"answer\"],\"additionalProperties\":false}";
const input_bytes = "x" ** 16_384;

fn consolidatedPreparation(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const assigned = try std.mem.replaceOwned(u8, allocator, source, "use: assign-model-request-id", "use: prepare-model-request");
    defer allocator.free(assigned);
    return std.mem.replaceOwned(u8, allocator, assigned,
        \\    on: { ok: validate, failed: end.failed }
        \\  validate: { use: validate-model-request-binding, on: { ok: build, failed: end.failed } }
        \\  build: { use: build-model-request, on: { ok: observe, failed: end.failed } }
    ,
        \\    on: { ok: observe, failed: end.failed }
    );
}

test "consolidated preparation publishes the same request and selected schema in one delta" {
    const packets = @import("domain/model_input_packet.zig");
    const selected_schema = "{\"$defs\":{\"answer\":" ++ schema_bytes ++ ",\"replacement\":{\"type\":\"object\",\"properties\":{\"approved\":{\"type\":\"boolean\"}},\"required\":[\"approved\"],\"additionalProperties\":false}},\"$ref\":\"#/$defs/answer\"}";
    for ([_]bool{ false, true }) |packet_input| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const a = fixture.arena.allocator();
        const detailed = if (packet_input) try std.mem.replaceOwned(u8, a, yaml, "input: input }", "result-selection: input }") else yaml;
        const source = if (packet_input) try std.mem.replaceOwned(u8, a, detailed, ", input: input.txt", "") else detailed;
        const graph = try fixture.compileWithAssets(source, if (packet_input) selected_schema else schema_bytes, !packet_input);
        const combined = try fixture.compileWithAssets(try consolidatedPreparation(a, source), if (packet_input) selected_schema else schema_bytes, !packet_input);
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(combined, std.testing.allocator);
        defer second.deinit();
        if (packet_input) for ([_]*runner_module.Runner{ &first, &second }) |runner| {
            const packet = try packets.create(std.testing.allocator, "{\"selected\":\"loan\"}", .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = "reference" }, .chunk_id = .{ .bytes = "chunk" } } }, .initial_generation, .{ .bytes = "replacement" });
            runner.envelope.slots[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, packet);
        };
        var one: Harness = .{ .runner = &first };
        try std.testing.expectEqual(.ok, one.run());
        try std.testing.expectEqual(.ok, second.bindings().invokeInvocation().outcome);
        try std.testing.expectEqual(.ok, second.bindings().invokeStep(.{ .bytes = "initialize" }).outcome);
        const initial_revision = (try requestLedger(&second)).revision().value;
        try std.testing.expectEqual(.ok, second.bindings().invokeStep(.{ .bytes = "origin" }).outcome);
        const retained = try currentRequest(&second);
        const left = (try currentRequest(&first)).prepared().?;
        const right = retained.prepared().?;
        try std.testing.expectEqual(initial_revision + 1, (try requestLedger(&second)).revision().value);
        for ([_]@import("domain/pipeline_data.zig").Schema{ requests.assigned_schema, requests.validated_schema, requests.prepared_schema }) |schema| {
            const value = try requests.readCurrent(&.{ .slots = second.envelope.slots }, schema);
            try std.testing.expect(value.id() == retained.id());
            try std.testing.expect(value.ledger() == try requestLedger(&second));
        }
        try std.testing.expect(identity.unitOwnerEql(left.model_request_id.immutable_unit_owner_id, right.model_request_id.immutable_unit_owner_id));
        try std.testing.expectEqualDeep(left.model_operation_id, right.model_operation_id);
        try std.testing.expectEqualDeep(left.content, right.content);
        try std.testing.expectEqualDeep(left.controls, right.controls);
        try std.testing.expectEqual(left.response_guidance_mode, right.response_guidance_mode);
        try std.testing.expectEqualStrings(left.response_schema.bytes(), right.response_schema.bytes());
        try std.testing.expectEqualStrings(left.response_schema.modelBytes(), right.response_schema.modelBytes());
        if (packet_input) try std.testing.expectEqualStrings("approved", right.response_schema.root().object[0].name);
        try std.testing.expectEqualStrings(left.model_visible_input_id.bytes, right.model_visible_input_id.bytes);
        try std.testing.expectEqual(.ok, second.bindings().invokeStep(.{ .bytes = "observe" }).outcome);
        try std.testing.expectEqual(@as(u128, 0), second.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, 0), second.tokenLedger().accounted_operations.items.len);
    }
}

test "runner rejects foreign consolidated children without accepting the successor" {
    const data = @import("domain/pipeline_data.zig");
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try consolidatedPreparation(fixture.arena.allocator(), yaml));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var one: Harness = .{ .runner = &first };
    try std.testing.expectEqual(.ok, one.run());
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    try std.testing.expectEqual(.ok, second.bindings().invokeInvocation().outcome);
    try std.testing.expectEqual(.ok, second.bindings().invokeStep(.{ .bytes = "initialize" }).outcome);
    const ledger_key = @intFromEnum(requests.ledger_schema.key);
    const initial = try values.retain(second.envelope.slots[ledger_key].?);
    defer values.destroy(initial);
    var input: data.View = .{ .slots = @splat(null) };
    input.slots[ledger_key] = initial;
    try std.testing.expectEqual(.ok, second.bindings().invokeStep(.{ .bytes = "origin" }).outcome);
    // Borrow the applied delta's values to test the existing runner validator.
    // Each substituted value is itself sealed and valid in another execution.
    var delta: pipeline.NodeDelta = .{ .data_writes = second.envelope.slots };
    delta.data_replacements[ledger_key] = second.envelope.slots[ledger_key];
    const validate = @import("application/workflow_model_request_lifecycle.zig").validateReplacement;
    _ = try validate(&input, requests.Prepare.Action.contract, &delta, .ok, null);
    for ([_]pipeline.DataKey{ .assigned_model_request, .validated_model_request, .prepared_model_request }) |key| {
        const index = @intFromEnum(key);
        delta.data_writes[index] = first.envelope.slots[index];
        try std.testing.expectError(error.ModelRequestBindingInvalid, validate(&input, requests.Prepare.Action.contract, &delta, .ok, null));
        delta.data_writes[index] = second.envelope.slots[index];
    }
    try std.testing.expectEqual(@as(u128, 0), second.tokenLedger().committed());
}

test "failed consolidated selection publishes neither a ledger successor nor partial preparation" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const source = try std.mem.replaceOwned(u8, a, try consolidatedPreparation(a, yaml), "result-schema: result", "result-schema: result, result-selection: input");
    const graph = try fixture.compile(source);
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    try std.testing.expectEqual(.ok, runner.bindings().invokeInvocation().outcome);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "initialize" }).outcome);
    const initial = try requestLedger(&runner);
    const revision = initial.revision();
    const result = runner.bindings().invokeStep(.{ .bytes = "origin" });
    try std.testing.expectEqualDeep(execution.Rejection{ .operation_failed = error.OperationExecutionFailed }, result.rejected);
    try std.testing.expect(initial == try requestLedger(&runner));
    try std.testing.expectEqual(revision, initial.revision());
    for ([_]pipeline.DataKey{ .assigned_model_request, .validated_model_request, .prepared_model_request }) |key| try std.testing.expect(runner.envelope.slots[@intFromEnum(key)] == null);
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
}

test "native domain packets traverse generic fake provider execution without resource or request substitution" {
    const packets = @import("domain/model_input_packet.zig");
    const candidate_handoff = @import("application/model_candidate_handoff.zig");
    for ([_][]const u8{ "{\"answer\":\"Hello, World!\"}", "{\"answer\":\"Loan renewed.\"}", "{\"{\"answer\":\"Orchard inspected.\"}", "{}" }) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const definition = try std.mem.replaceOwned(u8, fixture.arena.allocator(), try requestCompletionYaml(&fixture), ", input: input }", " }");
        const no_static_resource = try std.mem.replaceOwned(u8, fixture.arena.allocator(), definition, ", input: input.txt", "");
        const graph = try fixture.compileWithAssets(no_static_resource, schema_bytes, false);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        const unit: identity.ImmutableUnitOwnerId = .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = "current-reference" }, .chunk_id = .{ .bytes = "selected-chunk" } } };
        const packet = try packets.create(std.testing.allocator, "{\"text\":\"Only the selected chunk.\"}", unit, .initial_generation, null);
        runner.envelope.slots[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, packet);
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = body;
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        const expected: workflow.OutcomeTag = if (std.mem.eql(u8, body, "{}")) .invalid else .ok;
        try prepareRequestClosure(&runner, expected);
        const request = try currentRequest(&runner);
        try std.testing.expect(identity.unitOwnerEql(unit, request.id().immutable_unit_owner_id));
        try std.testing.expectEqualStrings(packet.body(), request.prepared().?.content[1].user);
        const view: @import("domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
        if (expected == .ok) {
            const expected_body = if (std.mem.startsWith(u8, body, "{\"{")) body[2..] else body;
            try std.testing.expectEqualStrings(expected_body, (try candidate_handoff.read(&view)).body);
            try std.testing.expectEqualStrings(body, (try envelopeResult(&runner)).outcome().decoded.association().result().complete.content());
        } else {
            try std.testing.expectError(error.OperationExecutionFailed, candidate_handoff.read(&view));
        }
        // Equal bytes do not authorize substituting another packet identity.
        const foreign = try packets.create(std.testing.allocator, packet.body(), unit, .initial_generation, null);
        const foreign_value = try requests.adoptPacket(std.testing.allocator, foreign);
        defer values.destroy(foreign_value);
        var changed = view;
        changed.slots[@intFromEnum(requests.packet_schema.key)] = foreign_value;
        try std.testing.expectError(error.OperationExecutionFailed, candidate_handoff.read(&changed));
        try std.testing.expectEqual(expected, runner.bindings().invokeStep(.{ .bytes = "close-request" }).outcome);
        const transport = @import("domain/model_transport.zig");
        const ledger = try requestLedger(&runner);
        const current = try currentRequest(&runner);
        const status: workflow.OutcomeTag = if (std.mem.eql(u8, body, "{}")) .invalid else .ok;
        const combined = try (@import("actions/model/retire_model_transport.zig").Action{}).execute(ledger, current.id(), status);
        const input_only = try transport.retire(.input, ledger, current.id(), status);
        const request_only = try transport.retire(.request, ledger, current.id(), status);
        try std.testing.expectEqualDeep(input_only.data_invalidations.unionWith(request_only.data_invalidations), combined.data_invalidations);
        const accounting = runner.tokenLedger().committed();
        for (transport.keys(.request_and_input)) |key| try std.testing.expect(combined.data_invalidations.contains(key));
        try std.testing.expectEqual(accounting, runner.tokenLedger().committed());
    }
}

test "native YAML preparation retains one generic request across distinct steps" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(yaml);
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
    const retained = try currentRequest(&runner);
    try std.testing.expectError(error.InvalidTransportRetirement, (@import("actions/model/retire_model_transport.zig").Action{}).execute(try requestLedger(&runner), retained.id(), .ok));
    const prepared = retained.prepared().?;
    try std.testing.expectEqual(.workflow_step, std.meta.activeTag(prepared.model_request_id.immutable_unit_owner_id));
    try std.testing.expectEqualStrings("origin", prepared.model_operation_id.workflow_step_id.bytes);
    try std.testing.expect(prepared.model_request_id == retained.id());
    try std.testing.expect(prepared.matchesBinding(retained.binding().*));
    try std.testing.expectEqualStrings(prompt_bytes, prepared.content[0].guidance);
    try std.testing.expectEqualStrings(input_bytes, prepared.content[1].user);
    try std.testing.expectEqualStrings(schema_bytes, prepared.response_schema.bytes());
    try std.testing.expectEqualStrings("model-request/v1", prepared.request_schema_id.bytes);
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    for (graph.authority.steps) |step| try std.testing.expectEqual(@as(usize, 0), step.capabilities.len);
    // No consumer repeats a slot, prompt, schema or control parameter.
    for (graph.authority.steps) |step| if (step.model == null) {
        try std.testing.expectEqual(@as(usize, 0), step.parameters.len);
    };
}

test "compiler rejects missing preparation dependencies and consumer rebinding" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const changes = [_][2][]const u8{
        .{ "slot: selected, ", "" },
        .{ "prompt: prompt, ", "" },
        .{ "result-schema: result, ", "" },
        .{ "slot: selected", "slot: 7" },
        .{ "slot: selected", "slot: selected, response-mode: native-schema" },
        .{ "prompt: prompt, result-schema: result", "prompt: result, result-schema: result" },
        .{ "result-schema: result", "result-schema: absent" },
        .{ "use: build-model-request,", "use: build-model-request, with: {slot: selected}," },
        .{ "use: build-model-request,", "use: build-model-request, with: {prompt: prompt}," },
        .{ "use: validate-model-request-binding, on: { ok: build, failed: end.failed }", "use: core.noop, on: { ok: build }" },
        .{ "use: build-initial-model-request-identity-ledger, on: { ok: origin, failed: end.failed }", "use: core.noop, on: { ok: origin }" },
        .{ "use: build-model-request", "use: hidden-model-route" },
    };
    for (changes) |change| {
        const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), yaml, change[0], change[1]);
        if (fixture.compile(invalid)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.WorkflowGraphCompileInvalid, error.WorkflowDefinitionSchemaInvalid => {},
            else => return err,
        }
    }
}

test "one unauthorized slot fails preparation without invoking a consumer" {
    for ([_]bool{ false, true }) |consolidated| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), if (consolidated) try consolidatedPreparation(fixture.arena.allocator(), yaml) else yaml, "slot: selected", "slot: unauthorized");
        const graph = try fixture.compile(invalid);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.prepared_model_request)] == null);
    }
}

test "each execution has fresh identities and rejects a foreign retained request" {
    for ([_]bool{ false, true }) |consolidated| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(if (consolidated) try consolidatedPreparation(fixture.arena.allocator(), yaml) else yaml);
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        var one: Harness = .{ .runner = &first };
        var two: Harness = .{ .runner = &second };
        try std.testing.expectEqual(.ok, one.run());
        const left = try currentRequest(&first);
        try std.testing.expectEqual(.ok, two.run());
        const right = try currentRequest(&second);
        try std.testing.expect(left.id() != right.id());
        try std.testing.expect(!left.id().stage_run_epoch_id.eql(right.id().stage_run_epoch_id));
        try std.testing.expectEqual(@as(u32, 1), right.id().request_ordinal.value);
        const key = @intFromEnum(pipeline.DataKey.prepared_model_request);
        std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
        defer std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
        const denied = second.bindings().invokeStep(.{ .bytes = "observe" });
        try std.testing.expectEqual(.authority, denied.rejected);
        try std.testing.expectEqual(@as(usize, 2), fixture.observer.calls);
    }
}

test "cancellation at every preparation boundary stops the compiled workflow" {
    for ([_]bool{ false, true }) |consolidated| {
        for (0..@as(usize, if (consolidated) 3 else 5)) |boundary| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(if (consolidated) try consolidatedPreparation(fixture.arena.allocator(), yaml) else yaml);
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
            runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
            try std.testing.expectEqual(.cancelled, harness.run());
            try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
            try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        }
    }
}

test "native preparation releases partial allocations and unapplied deltas" {
    for ([_]bool{ false, true }) |consolidated| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(if (consolidated) try consolidatedPreparation(fixture.arena.allocator(), yaml) else yaml);
        try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ &fixture, graph });
    }
}

test "retained request consumers still require policy permission and available workflow tokens" {
    const Consumer = struct {
        provider: @import("ports/llm_provider_interface.zig").LLMProviderInterface = @import("workflow_binding_test_fixture.zig").port(),
        calls: usize = 0,
        fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
            if (input.step.model_binding != request.binding()) return error.OperationExecutionFailed;
            context.?.calls += 1;
            return .{ .outcome = .ok, .delta = .{} };
        }
    };
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var consumer: Consumer = .{};
    fixture.entries[fixture.entries.len - 1].binding = bindings.bind(Consumer, &consumer, Consumer.invoke);
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(yaml));
    var profile = core.profiles[0];
    profile.allowed_capabilities = &.{"model-provider"};
    fixture.registry.policies = &.{profile};
    const graph = try fixture.compile(yaml);
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const request = try currentRequest(&runner);
    try runner.token_accounting.reconcile(.initial, .{ .model_request_id = request.id(), .model_attempt_ordinal = .{ .value = 1 }, .kind = .inference }, .{ .exact_usage = @import("domain/llm_provider_operation.zig").ProviderUsage.init(100_000, 0, 100_000).? });
    const rejected = runner.bindings().invokeStep(.{ .bytes = "observe" });
    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, rejected.rejected.token_budget);
    try std.testing.expectEqual(@as(usize, 1), consumer.calls);
}

test "consumer contracts cannot replace retained resources controls or retired size policy" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const original = fixture.entries[fixture.entries.len - 1];
    const descriptors = [_]@import("domain/workflow_operation.zig").ParameterDescriptor{
        .{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
        .{ .id = "prompt", .kind = .resource, .resource_kind = .prompt, .required = true, .workflow_definition_safe = true },
        .{ .id = "response-mode", .kind = .enumeration, .allowed_values = &.{"native-schema"}, .required = true, .workflow_definition_safe = true },
        .{ .id = "temperature", .kind = .integer, .required = false, .workflow_definition_safe = true },
        .{ .id = "input-bytes", .kind = .integer, .required = false, .workflow_definition_safe = true },
        .{ .id = "output-bytes", .kind = .integer, .required = false, .workflow_definition_safe = true },
        .{ .id = "input-tokens", .kind = .integer, .required = false, .workflow_definition_safe = true },
        .{ .id = "output-tokens", .kind = .integer, .required = false, .workflow_definition_safe = true },
    };
    for (descriptors) |descriptor| {
        var entry = original;
        entry.contract.parameters = &.{descriptor};
        fixture.entries[fixture.entries.len - 1] = entry;
        try std.testing.expect(!fixture.registry.validate());
    }
}

fn allocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    if (outcome == .failed) {
        if (runner.model_accounting) |state| {
            try std.testing.expectEqual(state.current_operations.revision().value != 0, runner.envelope.slots[@intFromEnum(pipeline.DataKey.assigned_provider_operation)] != null or
                runner.envelope.slots[@intFromEnum(pipeline.DataKey.invoked_provider_operation)] != null);
            if (runner.envelope.slots[@intFromEnum(pipeline.DataKey.provider_authorization_result)] != null) {
                const authorization = (try authorizationResult(&runner)).outcome();
                try std.testing.expect(authorization.* == .prepared);
                _ = try runner.model_accounting.?.authorization_leases.canonicalReference(authorization.prepared);
            }
        }
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(.ok, outcome);
}

test "YAML accounting publishes applied attempt evidence without rebinding or provider work" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try accountingYaml(&fixture, 0, false));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const evidence = try values.read(&.{ .slots = runner.envelope.slots }, attempt_values.schema, attempt_accounting.AccountedAttempt);
    const request = try currentRequest(&runner);
    try std.testing.expect(evidence.requestId() == request.id());
    try std.testing.expectEqual(@as(u32, 1), evidence.ordinal().value);
    try std.testing.expectEqualStrings("origin", request.id().model_operation_id.workflow_step_id.bytes);
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 0), runner.model_accounting.?.current_operations.revision().value);
    for (graph.authority.steps) |step| if (step.runner_accounting == .increment_model_attempt) {
        try std.testing.expectEqualStrings("account", step.retry_authority.?.operation_instance_id.bytes);
        try std.testing.expectEqual(@as(usize, 0), step.capabilities.len);
    };
}

test "YAML accounting permits only the declared retries after the initial execution" {
    for ([_]u32{ 0, 1, 3 }) |limit| for ([_]bool{ false, true }) |exhaust| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try accountingYaml(&fixture, limit, true));
        fixture.observer.retry_until = limit + 1 + @intFromBool(exhaust);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (exhaust) .failed else .ok), harness.run());
        try std.testing.expectEqual(@as(usize, limit + 1), fixture.observer.calls);
        try std.testing.expectEqual(limit + 1, fixture.observer.last_attempt);
        const request = try currentRequest(&runner);
        try std.testing.expectEqual(limit + 1, attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(request.id()));
    };
}

test "accounting schema rejects missing invalid excessive hidden and policy retry parameters" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try accountingYaml(&fixture, 0, false);
    for ([_][2][]const u8{
        .{ "with: {retry-limit: 0}, ", "" },
        .{ "retry-limit: 0", "retry-limit: -1" },
        .{ "retry-limit: 0", "retry-limit: 4294967296" },
        .{ "retry-limit: 0", "retry-limit: true" },
        .{ "retry-limit: 0", "attempts: 1" },
        .{ "retry-limit: 0", "retry-limit: 0, slot: selected" },
        .{ "policy: core.capability-free@1", "policy: {use: core.capability-free@1, retry-limit: 1}" },
        .{ "use: build-model-request", "use: core.noop" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        if (fixture.compile(invalid)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.WorkflowGraphCompileInvalid, error.WorkflowDefinitionSchemaInvalid => {},
            else => return err,
        }
    }
}

test "accounted attempts are isolated and foreign evidence cannot reach a consumer" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try accountingYaml(&fixture, 0, false));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var one: Harness = .{ .runner = &first };
    var two: Harness = .{ .runner = &second };
    try std.testing.expectEqual(.ok, one.run());
    try std.testing.expectEqual(.ok, two.run());
    const key = @intFromEnum(pipeline.DataKey.accounted_model_attempt);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    defer std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    const result = second.bindings().invokeStep(.{ .bytes = "observe" });
    try std.testing.expectEqual(.authority, result.rejected);
    try std.testing.expectEqual(@as(usize, 2), fixture.observer.calls);
    try std.testing.expectEqual(@as(u32, 1), fixture.observer.last_attempt);
}

test "accounting cancellation and allocation failures retain no partial evidence" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try accountingYaml(&fixture, 0, false));
    for (0..6) |boundary| {
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
        runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
        try std.testing.expectEqual(.cancelled, harness.run());
        if (boundary <= 4) try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.accounted_model_attempt)] == null);
    }
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ &fixture, graph });
}

fn accountingYaml(fixture: *Fixture, limit: u32, cycle: bool) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const consumer = &fixture.entries[fixture.entries.len - 1];
    consumer.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt };
    consumer.contract.outcomes = if (cycle) &.{ .ok, .invalid } else &.{.ok};
    consumer.contract.invalidates = if (cycle) &.{.accounted_model_attempt} else &.{};
    fixture.observer.consume_attempt = cycle;
    var source = try std.mem.replaceOwned(u8, allocator, yaml, "ok: observe", "ok: account");
    if (cycle) source = try std.mem.replaceOwned(u8, allocator, source, "on: { ok: end.ok }", "on: { ok: end.ok, invalid: account }");
    return std.fmt.allocPrint(allocator, "{s}\n  account: {{ use: advance-model-attempt-accounting, with: {{retry-limit: {d}}}, on: {{ok: observe, failed: end.failed}} }}\n", .{ source, limit });
}

test "new logical requests get initial attempts without resetting the YAML operation bound" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try accountingYaml(&fixture, 1, false));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    try std.testing.expectEqual(.ok, runner.bindings().invokeInvocation().outcome);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "initialize" }).outcome);
    for (0..3) |index| {
        for ([_][]const u8{ "origin", "validate", "build" }) |step| try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        const applied = runner.bindings().invokeStep(.{ .bytes = "account" });
        if (index == 2) {
            try std.testing.expectEqualStrings("account", applied.rejected.retry_limit.operation().bytes);
            try std.testing.expectEqual(@as(u32, 1), applied.rejected.retry_limit.limit.value);
            try std.testing.expectEqual(@as(u64, 2), applied.rejected.retry_limit.completed_executions);
            break;
        }
        try std.testing.expectEqual(.ok, applied.outcome);
        const request = try currentRequest(&runner);
        try std.testing.expectEqual(@as(u32, 1), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(request.id()));
        // Isolate the accounting boundary: no provider operation was assigned.
        // Retire test transport values through the same envelope delta owner.
        const keys = [_]pipeline.DataKey{ .assigned_model_request, .validated_model_request, .prepared_model_request, .accounted_model_attempt };
        var delta: pipeline.NodeDelta = .{};
        for (keys) |key| delta.data_invalidations.insert(key);
        try runner.envelope.apply(.{ .id = "test.retire-uninvoked-request-values", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &keys, .side_effect = .none }, &delta, .ok);
    }
}

test "forged accounting transitions and rejected deltas cannot publish attempts" {
    for ([_]FaultyAdvance.Fault{ .missing_transition, .wrong_ordinal, .stale_revision, .undeclared_write, .cancel_after_action }) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try accountingYaml(&fixture, 1, false));
        var faulty: FaultyAdvance = .{ .fault = fault };
        for (&fixture.entries) |*entry| if (entry.contract.runner_accounting == .increment_model_attempt) {
            entry.binding = bindings.bind(FaultyAdvance, &faulty, FaultyAdvance.invoke);
        };
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        runner.runtime = .{ .context = &faulty, .status_fn = FaultyAdvance.status };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (fault == .cancel_after_action) .cancelled else .failed), harness.run());
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        const request = try currentRequest(&runner);
        try std.testing.expectEqual(@as(u32, 0), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(request.id()));
        try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.accounted_model_attempt)] == null);
    }
}

test "runner rejects tampered accounting permissions and registry rejects hidden accounting" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try accountingYaml(&fixture, 0, false));
    var tampered = graph.*;
    const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
    for (steps) |*step| if (step.runner_accounting == .increment_model_attempt) {
        step.runner_accounting = .none;
    };
    tampered.authority.steps = steps;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
    var runner = fixture.runner(&tampered, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.failed, harness.run());
    try std.testing.expect(runner.model_accounting == null);

    for (&fixture.entries) |*entry| if (entry.contract.runner_accounting == .increment_model_attempt) {
        entry.contract.runner_accounting = .none;
    };
    try std.testing.expect(!fixture.registry.validate());
}

test "runner binds retry authority to the accounting step not the request origin" {
    for ([_]FaultyAdvance.Fault{ .foreign_retry, .forged_retry_count }) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try accountingYaml(&fixture, 2, true));
        fixture.observer.retry_until = 3;
        var faulty: FaultyAdvance = .{ .fault = fault };
        for (&fixture.entries) |*entry| if (entry.contract.runner_accounting == .increment_model_attempt) {
            entry.binding = bindings.bind(FaultyAdvance, &faulty, FaultyAdvance.invoke);
        };
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
        try std.testing.expectEqual(@as(u64, 1), attempt_accounting.accounting(runner.model_accounting.?.attempts).revision().value);
    }
}

const FaultyAdvance = struct {
    const Fault = enum { missing_transition, wrong_ordinal, stale_revision, undeclared_write, cancel_after_action, foreign_retry, forged_retry_count };
    action: @import("actions/model/advance_model_attempt_accounting.zig").Action = .{},
    fault: Fault,
    cancelled: bool = false,

    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const facts = input.step.model_attempt.?;
        var delta = self.action.execute(facts.accounting, facts.accounting.revision(), ledger, facts.operations, ledger.revision(), request.id(), facts.attempt) catch return error.OperationExecutionFailed;
        switch (self.fault) {
            .missing_transition => delta.runner_accounting_transition = null,
            .wrong_ordinal => delta.runner_accounting_transition.?.increment_model_attempt.next_request_value += 1,
            .stale_revision => delta.runner_accounting_transition.?.increment_model_attempt.expected_revision.value += 1,
            .undeclared_write => delta.data_writes[@intFromEnum(pipeline.DataKey.raw_engine_config)] = values.create(std.testing.allocator, values.schema(.raw_engine_config, bool, 1, 1), bool, true) catch return error.OperationExecutionFailed,
            .cancel_after_action => self.cancelled = true,
            .foreign_retry => if (facts.attempt == .retry) {
                delta.runner_accounting_transition.?.increment_model_attempt.attempt.retry.authority.operation_instance_id = .{ .bytes = "origin" };
            },
            .forged_retry_count => if (facts.attempt == .retry) {
                delta.runner_accounting_transition.?.increment_model_attempt.attempt.retry.completed_retries += 1;
            },
        }
        return .{ .outcome = .ok, .delta = delta };
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const FaultyAdvance = @ptrCast(@alignCast(context.?));
        return if (self.cancelled) .cancelled else .active;
    }
};

test "YAML assigns either provider operation to the existing attempt without external effects" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try assignmentYaml(&fixture, kind, false));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.ok, harness.run());
        try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
        const evidence = try assignedOperation(&runner);
        const record = evidence.record();
        try std.testing.expectEqual(@as(provider.ProviderOperationKind, if (std.mem.eql(u8, kind, "inference")) .inference else .input_token_count), record.id.kind);
        try std.testing.expectEqual(@as(u32, 1), record.id.model_attempt_ordinal.value);
        try std.testing.expectEqual(@as(u64, 1), runner.model_accounting.?.current_operations.revision().value);
        try std.testing.expect(evidence == try runner.model_accounting.?.current_operations.requireAssigned(record.id));
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        for (graph.authority.steps) |step| try std.testing.expectEqual(@as(usize, 0), step.capabilities.len);
    }
}

test "assignment rejects missing dependencies and hidden or invalid kind parameters" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try assignmentYaml(&fixture, "inference", false);
    for ([_][2][]const u8{
        .{ "with: {kind: inference}, ", "" },
        .{ "kind: inference", "kind: true" },
        .{ "kind: inference", "kind: automatic" },
        .{ "kind: inference", "kind: inference, retry-limit: 1" },
        .{ "kind: inference", "kind: inference, slot: selected" },
        .{ "kind: inference", "kind: inference, prompt: prompt" },
        .{ "use: advance-model-attempt-accounting, with: {retry-limit: 0}, on: {ok: assign-operation, failed: end.failed}", "use: core.noop, on: {ok: assign-operation}" },
        .{ "use: build-model-request", "use: core.noop" },
        .{ "assign-provider-operation", "hidden-provider-operation" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, source, invalid));
        if (fixture.compile(invalid)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.WorkflowGraphCompileInvalid, error.WorkflowDefinitionSchemaInvalid => {},
            else => return err,
        }
    }
}

test "an assigned operation blocks a YAML retry even after its pipeline evidence is consumed" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try assignmentYaml(&fixture, "inference", true));
    fixture.observer.retry_until = 2;
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.failed, harness.run());
    try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
    try std.testing.expectEqual(@as(u64, 1), attempt_accounting.accounting(runner.model_accounting.?.attempts).revision().value);
    try std.testing.expectEqual(@as(u64, 1), runner.model_accounting.?.current_operations.revision().value);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.assigned_provider_operation)] == null);
}

test "foreign attempt and assignment evidence never reach an assignment or consumer" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try assignmentYaml(&fixture, "input-token-count", false));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var one: Harness = .{ .runner = &first };
    var two: Harness = .{ .runner = &second };
    try std.testing.expectEqual(.ok, one.run());
    try std.testing.expectEqual(.ok, two.run());
    for ([_]pipeline.DataKey{ .accounted_model_attempt, .assigned_provider_operation }) |key| {
        const index = @intFromEnum(key);
        std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
        defer std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
        try std.testing.expectEqual(.authority, second.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
        if (key == .accounted_model_attempt) try std.testing.expectEqual(.authority, second.bindings().invokeStep(.{ .bytes = "assign-operation" }).rejected);
    }
    try std.testing.expectEqual(@as(usize, 2), fixture.observer.calls);
    // Consuming an envelope value cannot authorize assigning the same operation again.
    const key = @intFromEnum(pipeline.DataKey.assigned_provider_operation);
    const saved = second.envelope.slots[key].?;
    second.envelope.slots[key] = null;
    defer second.envelope.slots[key] = saved;
    try std.testing.expectEqualDeep(execution.Rejection{ .operation_failed = error.OperationExecutionFailed }, second.bindings().invokeStep(.{ .bytes = "assign-operation" }).rejected);
    try std.testing.expectEqual(@as(u64, 1), second.model_accounting.?.current_operations.revision().value);
}

test "assignment cancellation and allocation failures publish no partial ledger or evidence" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try assignmentYaml(&fixture, "inference", false));
    for (0..7) |boundary| {
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
        runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
        try std.testing.expectEqual(.cancelled, harness.run());
        if (boundary <= 5) {
            try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.assigned_provider_operation)] == null);
            if (runner.model_accounting) |state| try std.testing.expectEqual(@as(u64, 0), state.current_operations.revision().value);
        }
    }
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ &fixture, graph });
}

test "assignment registration and compiled graphs reject hidden authority" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try assignmentYaml(&fixture, "inference", false));
    const entry = for (&fixture.entries) |*entry| {
        if (entry.contract.runner_accounting == .advance_provider_operation) break entry;
    } else return error.MissingAssignment;
    const original = entry.*;
    entry.contract.parameters = &.{};
    try std.testing.expect(!fixture.registry.validate());
    entry.* = original;
    entry.contract.runner_accounting = .none;
    try std.testing.expect(!fixture.registry.validate());
    entry.* = original;
    entry.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request };
    try std.testing.expect(!fixture.registry.validate());
    entry.* = original;
    entry.contract.produces = &.{};
    entry.contract.replaces = &.{.assigned_provider_operation};
    try std.testing.expect(!fixture.registry.validate());
    entry.* = original;

    for ([_]bool{ false, true }) |remove_permission| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (step.runner_accounting == .advance_provider_operation) {
            if (remove_permission) step.runner_accounting = .none else step.parameters = &.{};
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        try std.testing.expectEqual(@as(u64, 0), runner.model_accounting.?.current_operations.revision().value);
    }
}

test "a terminal operation makes retained assignment evidence stale" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try assignmentYaml(&fixture, "input-token-count", false));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const evidence = try assignedOperation(&runner);
    const request = try currentRequest(&runner);
    const state = &runner.model_accounting.?;
    const authority = state.operationAuthority(request.ledger());
    const delta = try (@import("actions/model/advance_provider_operation_lifecycle.zig").Action{}).execute(state.current_operations, authority, state.current_operations.revision(), evidence.record().id, evidence.record().revision, .{ .terminate = .{ .cancelled = .not_sent } });
    state.current_operations = try lifecycle.apply(state.current_operations, authority, delta.runner_accounting_transition.?.advance_provider_operation);
    try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
    try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
}

test "forged assignment proposals and rejected deltas cannot publish an operation" {
    for (std.enums.values(FaultyAssignment.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try assignmentYaml(&fixture, "inference", false));
        var faulty: FaultyAssignment = .{ .fault = fault };
        for (&fixture.entries) |*entry| if (entry.contract.runner_accounting == .advance_provider_operation) {
            entry.binding = bindings.bind(FaultyAssignment, &faulty, FaultyAssignment.invoke);
        };
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        runner.runtime = .{ .context = &faulty, .status_fn = FaultyAssignment.status };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (fault == .cancel_after_action) .cancelled else .failed), harness.run());
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expectEqual(@as(u64, 0), runner.model_accounting.?.current_operations.revision().value);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.assigned_provider_operation)] == null);
    }
}

test "assigned evidence retains its canonical record and request until destroyed" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try assignmentYaml(&fixture, "inference", false));
    var runner = fixture.runner(graph, std.testing.allocator);
    var alive = true;
    defer if (alive) runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const evidence = try assignedOperation(&runner);
    const key = @intFromEnum(pipeline.DataKey.assigned_provider_operation);
    const retained = runner.envelope.slots[key].?;
    runner.envelope.slots[key] = null;
    defer values.destroy(retained);
    runner.deinit();
    alive = false;
    try std.testing.expectEqualStrings("origin", evidence.record().id.model_request_id.model_operation_id.workflow_step_id.bytes);
    try std.testing.expectEqualStrings("selected", evidence.record().binding_id.slot_id.bytes);
    try std.testing.expectEqual(.assigned, evidence.record().state);
}

fn assignmentYaml(fixture: *Fixture, kind: []const u8, cycle: bool) ![]const u8 {
    const source = try accountingYaml(fixture, if (cycle) 1 else 0, cycle);
    const consumer = &fixture.entries[fixture.entries.len - 1];
    consumer.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .assigned_provider_operation };
    if (cycle) consumer.contract.invalidates = &.{ .accounted_model_attempt, .assigned_provider_operation };
    fixture.observer.consume_operation = cycle;
    const replaced = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, "ok: observe", "ok: assign-operation");
    return std.fmt.allocPrint(fixture.arena.allocator(), "{s}\n  assign-operation: {{ use: assign-provider-operation, with: {{kind: {s}}}, on: {{ok: observe, failed: end.failed}} }}\n", .{ replaced, kind });
}

fn assignedOperation(runner: *const runner_module.Runner) !*const lifecycle.AssignedOperation {
    return values.read(&.{ .slots = runner.envelope.slots }, attempt_values.operation_schema, lifecycle.AssignedOperation);
}

const FaultyAssignment = struct {
    const Fault = enum { missing_transition, wrong_ordinal, wrong_kind, wrong_binding, wrong_input, stale_revision, unassigned_invoke, undeclared_write, forged_evidence, cancel_after_action };
    action: @import("actions/model/advance_provider_operation_lifecycle.zig").Action = .{},
    fault: Fault,
    cancelled: bool = false,

    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        const prepared = request.prepared().?;
        const evidence = values.read(&input.step.data, attempt_values.schema, attempt_accounting.AccountedAttempt) catch return error.OperationExecutionFailed;
        const facts = input.step.provider_operation.?;
        var delta = self.action.execute(facts.ledger, facts.authority, facts.ledger.revision(), .{ .model_request_id = request.id(), .model_attempt_ordinal = evidence.ordinal(), .kind = .inference }, null, .{ .assign_inference = .{ .binding_id = prepared.binding_id, .model_visible_input_id = prepared.model_visible_input_id } }) catch return error.OperationExecutionFailed;
        const transition = &delta.runner_accounting_transition.?.advance_provider_operation;
        switch (self.fault) {
            .missing_transition => delta.runner_accounting_transition = null,
            .wrong_ordinal => transition.operation_id.model_attempt_ordinal.value += 1,
            .wrong_kind => {
                const assigned = transition.command.assign_inference;
                transition.operation_id.kind = .input_token_count;
                transition.command = .{ .assign_count = assigned };
            },
            .wrong_binding => transition.command.assign_inference.binding_id.slot_id.bytes = "other-slot",
            .wrong_input => transition.command.assign_inference.model_visible_input_id.bytes = "other-input",
            .stale_revision => transition.expected_revision.value += 1,
            .unassigned_invoke => transition.command = .{ .invoke = .{ .deadline_monotonic_ms = 100 } },
            .undeclared_write, .forged_evidence => {
                const key: pipeline.DataKey = if (self.fault == .undeclared_write) .raw_engine_config else .assigned_provider_operation;
                delta.data_writes[@intFromEnum(key)] = values.create(std.testing.allocator, values.schema(.raw_engine_config, bool, 1, 1), bool, true) catch return error.OperationExecutionFailed;
            },
            .cancel_after_action => self.cancelled = true,
        }
        return .{ .outcome = .ok, .delta = delta };
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const FaultyAssignment = @ptrCast(@alignCast(context.?));
        return if (self.cancelled) .cancelled else .active;
    }
};

test "YAML authorization prepares one private lease for either assigned operation and cleans up" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try authorizationYaml(&fixture, kind));
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var harness: Harness = .{ .runner = &runner };
            try std.testing.expectEqual(.ok, harness.run());
            const result = try authorizationResult(&runner);
            try std.testing.expect(result.outcome().* == .prepared);
            _ = try runner.model_accounting.?.authorization_leases.canonicalReference(result.outcome().prepared);
            try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepare_count);
            try std.testing.expectEqual(@as(usize, 0), fixture.authorization.destroyed_count);
            try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
            try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
            try std.testing.expectEqual(.assigned, (try assignedOperation(&runner)).record().state);
            for (graph.authority.steps) |step| for (step.capabilities) |capability| {
                try std.testing.expectEqualStrings("provider-authorization", capability);
            };
        }
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    }
}

test "authorization failure facts and cancellation stay distinct and follow declared outcomes" {
    for ([_]@import("adapters/provider/fake_provider_authorization.zig").Plan{ .{ .failed = .authentication_failed }, .{ .failed = .authorization_denied }, .cancelled }) |plan| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = plan;
        const graph = try fixture.compile(try authorizationYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (plan == .cancelled) .cancelled else .failed), harness.run());
        const result = (try authorizationResult(&runner)).outcome();
        if (plan == .failed) {
            try std.testing.expectEqual(@as(provider.ProviderFailureCause, if (plan.failed == .authentication_failed) .authentication_failed else .authorization_denied), result.failed.cause);
            try std.testing.expectEqual(.not_sent, result.failed.delivery);
            try std.testing.expect(result.failed.operation_id.eql((try assignedOperation(&runner)).record().id));
            try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls); // Explicit failed -> observe -> end.failed.
        } else try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    }
}

test "authorization rejects missing timeout invalid timeout dependencies and capability permission" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try authorizationYaml(&fixture, "inference");
    for ([_][2][]const u8{
        .{ "with: {timeout-ms: 1000}, ", "" },
        .{ "timeout-ms: 1000", "timeout-ms: 0" },
        .{ "timeout-ms: 1000", "timeout-ms: -1" },
        .{ "timeout-ms: 1000", "timeout-ms: true" },
        .{ "timeout-ms: 1000", "timeout-ms: 9223372036854775808" },
        .{ "timeout-ms: 1000", "timeout-ms: 1000, retry-limit: 1" },
        .{ "timeout-ms: 1000", "timeout-ms: 1000, slot: selected" },
        .{ "timeout-ms: 1000", "timeout-ms: 1000, kind: inference" },
        .{ "timeout-ms: 1000", "timeout-ms: 1000, api-key: forbidden" },
        .{ "policy: core.model-authorization@1", "policy: core.capability-free@1" },
        .{ "use: assign-provider-operation, with: {kind: inference}, on: {ok: authorize, failed: end.failed}", "use: core.noop, on: {ok: authorize}" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, invalid, source));
        if (fixture.compile(invalid)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.WorkflowGraphCompileInvalid, error.WorkflowDefinitionSchemaInvalid, error.WorkflowDefinitionParseError => {},
            else => return err,
        }
    }
}

test "duplicate preparation and foreign lease results cannot authorize another operation" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try authorizationYaml(&fixture, "inference"));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var one: Harness = .{ .runner = &first };
    var two: Harness = .{ .runner = &second };
    try std.testing.expectEqual(.ok, one.run());
    try std.testing.expectEqual(.ok, two.run());
    const key = @intFromEnum(authorization_workflow.schema.key);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    try std.testing.expectEqual(.authority, second.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    const saved = second.envelope.slots[key];
    second.envelope.slots[key] = null;
    defer second.envelope.slots[key] = saved;
    try std.testing.expectEqual(.authority, second.bindings().invokeStep(.{ .bytes = "authorize" }).rejected);
    try std.testing.expectEqual(@as(usize, 2), fixture.authorization.prepare_count);
    try std.testing.expectEqual(@as(usize, 2), fixture.observer.calls);
}

test "authorization guards expiration overflow unavailable clocks and absent adapters" {
    for (0..5) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try authorizationYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        switch (variant) {
            0 => fixture.clock.now_ms = std.math.maxInt(u64),
            1 => fixture.clock.unavailable = true,
            2 => runner.provider_clock = null,
            3 => fixture.native.prepare_authorization.action = null,
            4 => {},
            else => unreachable,
        }
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (variant == 4) .ok else .failed), harness.run());
        if (variant == 4) {
            fixture.clock.now_ms = 1001;
            try std.testing.expectEqual(.deadline_exhausted, runner.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
            try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        } else try std.testing.expectEqual(@as(usize, 0), fixture.authorization.prepare_count);
    }
}

test "authorization cancellation and allocation faults release all unpublished capabilities" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try authorizationYaml(&fixture, "inference"));
    for (0..8) |boundary| {
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
            runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
            try std.testing.expectEqual(.cancelled, harness.run());
            if (boundary <= 6) try std.testing.expect(runner.envelope.slots[@intFromEnum(authorization_workflow.schema.key)] == null);
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ &fixture, graph });
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
}

test "authorization validates deposited facts and releases backing after mid-preparation cancellation or expiry" {
    for (std.enums.values(AuthorizationSpy.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try authorizationYaml(&fixture, "inference"));
        var spy: AuthorizationSpy = .{ .fixture = &fixture, .fault = fault };
        fixture.native.prepare_authorization.action = .{ .authorization = spy.port() };
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        runner.runtime = .{ .context = &spy, .status_fn = AuthorizationSpy.status };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (fault == .cancel) .cancelled else .failed), harness.run());
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepared_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        if (fault == .cancel or fault == .expire) {
            try std.testing.expect(runner.envelope.slots[@intFromEnum(authorization_workflow.schema.key)] == null);
            try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        } else try std.testing.expectEqual(.authorization_denied, (try authorizationResult(&runner)).outcome().failed.cause);
    }
}

test "forged authorization results and rejected deltas publish no lease and destroy backing" {
    for (std.enums.values(FaultyAuthorization.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try authorizationYaml(&fixture, "inference"));
        var faulty: FaultyAuthorization = .{ .prepare = fixture.native.prepare_authorization, .fault = fault };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, authorization_workflow.Prepare.contract.id)) {
            entry.binding = bindings.bind(FaultyAuthorization, &faulty, FaultyAuthorization.invoke);
        };
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        const actual = harness.run();
        try std.testing.expectEqual(.failed, actual);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(authorization_workflow.schema.key)] == null);
    }
}

test "authorization compiler and registry reject hidden producers and tampered timeout authority" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try authorizationYaml(&fixture, "inference"));
    for (0..3) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, authorization_workflow.Prepare.contract.id)) {
            switch (variant) {
                0 => step.capabilities = &.{},
                1 => step.parameters = &.{},
                2 => step.produces = &.{ .provider_authorization_result, .raw_engine_config },
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        try std.testing.expectEqual(@as(usize, 0), fixture.authorization.prepare_count);
    }
    for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, authorization_workflow.Prepare.contract.id)) {
        const original = entry.*;
        entry.contract.parameters = &.{};
        try std.testing.expect(!fixture.registry.validate());
        entry.* = original;
        entry.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request };
        try std.testing.expect(!fixture.registry.validate());
        entry.* = original;
        entry.contract.produces = &.{};
        try std.testing.expect(!fixture.registry.validate());
        entry.* = original;
        entry.binding = bindings.bind(void, null, UnauthorizedProducer.invoke);
        try std.testing.expect(!fixture.registry.validate());
        entry.* = original;
    };
    const consumer = &fixture.entries[fixture.entries.len - 1];
    consumer.contract.requires = &.{.provider_authorization_result};
    try std.testing.expect(!fixture.registry.validate());
}

const UnauthorizedProducer = struct {
    fn invoke(_: ?*void, _: operations.Input) operations.Error!execution.Candidate {
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const AuthorizationSpy = struct {
    const Fault = enum { binding, input, operation, deadline, cancel, expire };
    fixture: *Fixture,
    fault: Fault,
    cancelled: bool = false,
    fn port(self: *AuthorizationSpy) authorization_port.Port {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare };
    }
    fn prepare(context: *authorization_port.Context, facts: authorization_port.Facts, slot: authorization_port.Slot) authorization_port.Error!authorization_port.Observation {
        const self: *AuthorizationSpy = @ptrCast(@alignCast(context));
        var changed = facts;
        var binding = facts.provider_binding.*;
        var request = facts.request.*;
        switch (self.fault) {
            .binding => {
                binding.slot_id.bytes = "different-slot";
                changed.provider_binding = &binding;
            },
            .input => {
                request.model_visible_input_id.bytes = "different-input";
                changed.request = &request;
            },
            .operation => changed.operation_id.kind = .input_token_count,
            .deadline => changed.deadline_monotonic_ms += 1,
            .cancel, .expire => {},
        }
        const result = try self.fixture.authorization.port().prepare(changed, slot);
        if (self.fault == .cancel) self.cancelled = true;
        if (self.fault == .expire) self.fixture.clock.now_ms = facts.deadline_monotonic_ms;
        return result;
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const AuthorizationSpy = @ptrCast(@alignCast(context.?));
        return if (self.cancelled) .cancelled else .active;
    }
};

const FaultyAuthorization = struct {
    const Fault = enum { missing_result, undeclared_write, forged_reference, failure_as_success, foreign_failure, foreign_cancellation };
    prepare: authorization_workflow.Prepare,
    fault: Fault,
    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var candidate = try authorization_workflow.Prepare.invoke(&self.prepare, input);
        const key = @intFromEnum(authorization_workflow.schema.key);
        if (self.fault == .undeclared_write) {
            candidate.delta.data_writes[@intFromEnum(pipeline.DataKey.raw_engine_config)] = values.create(std.testing.allocator, values.schema(.raw_engine_config, bool, 1, 1), bool, true) catch return error.OperationExecutionFailed;
            return candidate;
        }
        values.destroy(candidate.delta.data_writes[key].?);
        candidate.delta.data_writes[key] = null;
        if (self.fault == .missing_result) return candidate;
        var id = input.step.provider_authorization.?.facts.operation_id;
        if (self.fault == .foreign_failure or self.fault == .foreign_cancellation) id.kind = .input_token_count;
        const reference = @import("domain/execution_reference.zig").create(std.testing.allocator) catch return error.OperationExecutionFailed;
        defer reference.release();
        const payload: authorization_result.Outcome = switch (self.fault) {
            .forged_reference => .{ .prepared = .{ .identity = reference } },
            .failure_as_success, .foreign_failure => .{ .failed = .{ .operation_id = id, .cause = .authorization_denied, .retry_class = .never, .delivery = .not_sent } },
            .foreign_cancellation => .{ .cancelled = id },
            else => unreachable,
        };
        const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
        const owner = authorization_result.create(std.testing.allocator, ledger, payload) catch return error.OperationExecutionFailed;
        errdefer authorization_result.destroy(owner);
        candidate.delta.data_writes[key] = values.adopt(std.testing.allocator, authorization_workflow.schema, authorization_result.Result, authorization_result.Result, owner, get, authorization_result.destroy, null) catch return error.OperationExecutionFailed;
        if (self.fault == .foreign_failure) candidate.outcome = .failed;
        if (self.fault == .foreign_cancellation) candidate.outcome = .cancelled;
        return candidate;
    }
    fn get(value: *const authorization_result.Result) *const authorization_result.Result {
        return value;
    }
};

fn authorizationYaml(fixture: *Fixture, kind: []const u8) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try assignmentYaml(fixture, kind, false);
    const consumer = &fixture.entries[fixture.entries.len - 1];
    consumer.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .assigned_provider_operation, .provider_authorization_result };
    consumer.contract.outcomes = &.{ .ok, .failed, .cancelled };
    var replaced = try std.mem.replaceOwned(u8, allocator, source, "ok: observe", "ok: authorize");
    replaced = try std.mem.replaceOwned(u8, allocator, replaced, "policy: core.capability-free@1", "policy: core.model-authorization@1");
    replaced = try std.mem.replaceOwned(u8, allocator, replaced, "on: { ok: end.ok }", "on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled }");
    return std.fmt.allocPrint(allocator, "{s}\n  authorize: {{ use: prepare-provider-operation-authorization, with: {{timeout-ms: 1000}}, on: {{ok: observe, failed: observe, cancelled: end.cancelled}} }}\n", .{replaced});
}

fn authorizationResult(runner: *const runner_module.Runner) !*const authorization_result.Result {
    return values.read(&.{ .slots = runner.envelope.slots }, authorization_workflow.schema, authorization_result.Result);
}

fn terminationYaml(fixture: *Fixture, kind: []const u8) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try authorizationYaml(fixture, kind);
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .provider_authorization_result };
    fixture.observer.expected_request_status = .assigned;
    const routed = try std.mem.replaceOwned(u8, allocator, source, "on: {ok: observe, failed: observe, cancelled: end.cancelled}", "on: {ok: end.ok, failed: terminate, cancelled: terminate}");
    return std.fmt.allocPrint(allocator, "{s}\n  terminate: {{ use: terminate-provider-operation, on: {{failed: observe, cancelled: observe}} }}\n", .{routed});
}

fn prepareTermination(runner: *runner_module.Runner, outcome: workflow.OutcomeTag) !void {
    try std.testing.expectEqual(.ok, runner.bindings().invokeInvocation().outcome);
    for ([_][]const u8{ "initialize", "origin", "validate", "build", "account", "assign-operation" }) |step|
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    try std.testing.expectEqual(outcome, runner.bindings().invokeStep(.{ .bytes = "authorize" }).outcome);
}

fn requestTerminationYaml(fixture: *Fixture, kind: []const u8) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try terminationYaml(fixture, kind);
    fixture.observer.expected_request_status = .terminal;
    const routed = try std.mem.replaceOwned(u8, allocator, source, "use: terminate-provider-operation, on: {failed: observe, cancelled: observe}", "use: terminate-provider-operation, on: {failed: close-request, cancelled: close-request}");
    return std.fmt.allocPrint(allocator, "{s}\n  close-request: {{ use: terminate-model-request, on: {{failed: observe, cancelled: observe}} }}\n", .{routed});
}

fn prepareRequestTermination(runner: *runner_module.Runner, cancelled: bool, invoked: bool) !void {
    const outcome: workflow.OutcomeTag = if (cancelled) .cancelled else .failed;
    try prepareTermination(runner, outcome);
    if (invoked) {
        // Seed a previously invoked request through the canonical lifecycle action.
        // No test helper supplies terminal evidence or request-closure authority.
        const current = try requestLedger(runner);
        const owner = try (@import("actions/model/advance_model_request_lifecycle.zig").Action{}).execute(current, runner.model_accounting.?.current_operations, current.revision(), (try currentRequest(runner)).id(), .assigned, .invoked);
        const value = requests.adoptLedger(std.testing.allocator, owner) catch |err| {
            identity.deinitOwner(owner);
            return err;
        };
        const key = @intFromEnum(requests.ledger_schema.key);
        values.destroy(runner.envelope.slots[key].?);
        runner.envelope.slots[key] = value;
        runner.model_accounting.?.replaceRequests(try identity.retainLedger(identity.ledger(owner)));
    }
    try std.testing.expectEqual(outcome, runner.bindings().invokeStep(.{ .bytes = "terminate" }).outcome);
}

test "YAML pre-call request closure preserves failure and cancellation without provider calls" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        for ([_]@import("adapters/provider/fake_provider_authorization.zig").Plan{ .{ .failed = .authentication_failed }, .{ .failed = .authorization_denied }, .cancelled }) |plan| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            fixture.authorization.plan = plan;
            const graph = try fixture.compile(try requestTerminationYaml(&fixture, kind));
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            var harness: Harness = .{ .runner = &runner };
            const expected: workflow.OutcomeTag = if (plan == .cancelled) .cancelled else .failed;
            try std.testing.expectEqual(expected, harness.run());
            const ledger = try requestLedger(&runner);
            const record = ledger.record((try currentRequest(&runner)).id()).?;
            try std.testing.expectEqual(.terminal, record.status);
            try std.testing.expectEqual(@as(identity.TerminalReason, if (plan == .cancelled) .cancelled else .not_invoked_authorization_failure), record.terminal_reason.?);
            try std.testing.expect(ledger == identity.ledger(runner.model_accounting.?.requests));
            try runner.model_accounting.?.current_operations.validateRequestClosure((try currentRequest(&runner)).id());
            try std.testing.expectEqual(expected, runner.envelope.origins[@intFromEnum(requests.ledger_schema.key)].?.outcome);
            try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
            try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepare_count);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null);
            try expectNoProviderEffects(&runner, &fake);
        }
    }
}

test "pre-call request closure maps both request states and retains immutable owners after cleanup" {
    for ([_]bool{ false, true }) |invoked| {
        for ([_]bool{ false, true }) |cancelled| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            var spy: RejectedDeposit = .{ .fixture = &fixture, .cancelled = cancelled };
            fixture.native.prepare_authorization.action = .{ .authorization = spy.port() };
            const graph = try fixture.compile(try requestTerminationYaml(&fixture, "inference"));
            var runner = fixture.runner(graph, std.testing.allocator);
            var active = true;
            defer if (active) runner.deinit();
            try prepareRequestTermination(&runner, cancelled, invoked);
            const old_value = try values.retain(runner.envelope.slots[@intFromEnum(requests.ledger_schema.key)].?);
            defer values.destroy(old_value);
            const old = try requestLedger(&runner);
            const original_operations = runner.model_accounting.?.current_operations;
            const auth = try authorizationResult(&runner);
            const terminal = try completedOperation(&runner);
            runner.provider_clock = null;
            fixture.clock.now_ms = 1001;
            try std.testing.expectEqual(@as(workflow.OutcomeTag, if (cancelled) .cancelled else .failed), runner.bindings().invokeStep(.{ .bytes = "close-request" }).outcome);
            try std.testing.expect(original_operations == runner.model_accounting.?.current_operations);
            try std.testing.expect(auth == try authorizationResult(&runner));
            try std.testing.expect(terminal == try completedOperation(&runner));
            const retained_ledger = try values.retain(runner.envelope.slots[@intFromEnum(requests.ledger_schema.key)].?);
            defer values.destroy(retained_ledger);
            const retained_auth = try values.retain(runner.envelope.slots[@intFromEnum(authorization_workflow.schema.key)].?);
            defer values.destroy(retained_auth);
            const retained_terminal = try values.retain(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)].?);
            defer values.destroy(retained_terminal);
            const ledger = try requestLedger(&runner);
            const id = (try currentRequest(&runner)).id();
            try std.testing.expectEqual(@as(u64, old.revision().value + 1), ledger.revision().value);
            runner.deinit();
            active = false;
            try std.testing.expectEqual(@as(identity.TerminalReason, if (cancelled) .cancelled else if (invoked) .failed else .not_invoked_authorization_failure), ledger.record(id).?.terminal_reason.?);
            try std.testing.expectEqual(@as(identity.RequestStatus, if (invoked) .invoked else .assigned), old.record(id).?.status);
            try std.testing.expectEqual(@as(workflow.OutcomeTag, if (cancelled) .cancelled else .failed), try @import("application/workflow_provider_authorization.zig").validateTerminal(auth, terminal.record()));
            try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepared_count);
            try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        }
    }
}

test "YAML pre-call request closure after inference preserves its response and single token charge" {
    for ([_]bool{ false, true }) |cancelled| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const allocator = fixture.arena.allocator();
        const source = try completionYaml(&fixture);
        fixture.observer.expected_request_status = .invoked;
        fixture.observer.release_terminal = true;
        fixture.entries[fixture.entries.len - 1].contract.invalidates = &.{ .terminal_provider_operation, .provider_authorization_result };
        const routed = try std.mem.replaceOwned(u8, allocator, source, "ok: end.ok", "ok: assign-next");
        const bytes = try std.fmt.allocPrint(
            allocator,
            "{s}\n" ++
                "  assign-next: {{ use: assign-provider-operation, with: {{kind: input-token-count}}, on: {{ok: authorize-next, failed: end.failed}} }}\n" ++
                "  authorize-next: {{ use: prepare-provider-operation-authorization, with: {{timeout-ms: 1000}}, on: {{ok: end.ok, failed: terminate-next, cancelled: terminate-next}} }}\n" ++
                "  terminate-next: {{ use: terminate-provider-operation, on: {{failed: close-request, cancelled: close-request}} }}\n" ++
                "  close-request: {{ use: terminate-model-request, on: {{failed: end.failed, cancelled: end.cancelled}} }}\n",
            .{routed},
        );
        var sequence: AuthorizationAfterInference = .{ .fixture = &fixture, .cancelled = cancelled };
        fixture.native.prepare_authorization.action = .{ .authorization = sequence.port() };
        const graph = try fixture.compile(bytes);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = "{\"answer\":\"retained\"}";
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (cancelled) .cancelled else .failed), harness.run());
        const request = try currentRequest(&runner);
        try std.testing.expectEqual(@as(identity.TerminalReason, if (cancelled) .cancelled else .failed), (try requestLedger(&runner)).record(request.id()).?.terminal_reason.?);
        try runner.model_accounting.?.current_operations.validateRequestClosure(request.id());
        try std.testing.expectEqual(.input_token_count, (try completedOperation(&runner)).record().id.kind);
        try std.testing.expectEqualStrings("retained", (try payloadResult(&runner)).outcome().valid.candidate().root().get("answer").?.string);
        try std.testing.expectEqual(@as(usize, 2), fixture.authorization.prepare_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        try expectResponseAccounting(&runner, &fake, 7);
    }
}

const AuthorizationAfterInference = struct {
    fixture: *Fixture,
    cancelled: bool,
    fn port(self: *@This()) authorization_port.Port {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare };
    }
    fn prepare(context: *authorization_port.Context, facts: authorization_port.Facts, slot: authorization_port.Slot) authorization_port.Error!authorization_port.Observation {
        const self: *@This() = @ptrCast(@alignCast(context));
        self.fixture.authorization.plan = if (facts.operation_id.kind == .inference) .prepared else if (self.cancelled) .cancelled else .{ .failed = .authorization_denied };
        return self.fixture.authorization.port().prepare(facts, slot);
    }
};

test "runtime cancellation before pre-call request closure leaves no hidden ledger transition" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    fixture.authorization.plan = .{ .failed = .authentication_failed };
    const graph = try fixture.compile(try requestTerminationYaml(&fixture, "inference"));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner, .cancel_at = 8 };
    runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
    try std.testing.expectEqual(.cancelled, harness.run());
    const request = try currentRequest(&runner);
    try std.testing.expectEqual(.assigned, (try requestLedger(&runner)).record(request.id()).?.status);
    try std.testing.expectEqual(.preparation_failed, std.meta.activeTag((try completedOperation(&runner)).record().state.terminal));
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

test "pre-call request closure rejects missing foreign stale duplicate and prepared evidence" {
    for ([_]bool{ false, true }) |cancelled| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = if (cancelled) .cancelled else .{ .failed = .authentication_failed };
        const graph = try fixture.compile(try requestTerminationYaml(&fixture, "inference"));
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        try prepareRequestTermination(&first, cancelled, false);
        try prepareRequestTermination(&second, cancelled, false);
        const original = try values.retain(first.envelope.slots[@intFromEnum(requests.ledger_schema.key)].?);
        defer values.destroy(original);
        for (request_termination.Terminate.contract.requires) |key| {
            const index = @intFromEnum(key);
            const saved = first.envelope.slots[index];
            first.envelope.slots[index] = null;
            const missing = first.bindings().invokeStep(.{ .bytes = "close-request" });
            first.envelope.slots[index] = saved;
            try std.testing.expectEqual(.authority, missing.rejected);
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            const foreign = first.bindings().invokeStep(.{ .bytes = "close-request" });
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            try std.testing.expectEqual(.authority, foreign.rejected);
            try std.testing.expect(first.envelope.slots[@intFromEnum(requests.ledger_schema.key)] == original);
        }
        for (0..7) |variant| {
            var id = (try completedOperation(&first)).record().id;
            if (variant == 0) id.kind = .input_token_count;
            if (variant == 1) id.model_attempt_ordinal.value += 1;
            const reference = try @import("domain/execution_reference.zig").create(std.testing.allocator);
            defer reference.release();
            const outcome: authorization_result.Outcome = switch (variant) {
                5 => if (cancelled) .{ .failed = .{ .operation_id = id, .cause = .authentication_failed, .retry_class = .never, .delivery = .not_sent } } else .{ .cancelled = id },
                6 => .{ .prepared = .{ .identity = reference } },
                else => if (cancelled and variant < 2) .{ .cancelled = id } else .{ .failed = .{
                    .operation_id = id,
                    .cause = if (variant == 4) .authorization_denied else .authentication_failed,
                    .retry_class = if (variant == 2) .policy_eligible else .never,
                    .delivery = if (variant == 3) .response_received else .not_sent,
                } },
            };
            const owner = try authorization_result.create(std.testing.allocator, try requestLedger(&first), outcome);
            const value = try values.adopt(std.testing.allocator, authorization_workflow.schema, authorization_result.Result, authorization_result.Result, owner, authorization_result_view, authorization_result.destroy, null);
            defer values.destroy(value);
            const index = @intFromEnum(authorization_workflow.schema.key);
            const saved = first.envelope.slots[index];
            first.envelope.slots[index] = value;
            const rejected = first.bindings().invokeStep(.{ .bytes = "close-request" });
            first.envelope.slots[index] = saved;
            try std.testing.expectEqual(.authority, rejected.rejected);
            try std.testing.expect(first.envelope.slots[@intFromEnum(requests.ledger_schema.key)] == original);
        }
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (cancelled) .cancelled else .failed), first.bindings().invokeStep(.{ .bytes = "close-request" }).outcome);
        const closed = try requestLedger(&first);
        try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "close-request" }).rejected);
        const index = @intFromEnum(requests.ledger_schema.key);
        const saved = first.envelope.slots[index];
        first.envelope.slots[index] = original;
        const stale = first.bindings().invokeStep(.{ .bytes = "close-request" });
        first.envelope.slots[index] = saved;
        try std.testing.expectEqual(.authority, stale.rejected);
        try std.testing.expect(closed == try requestLedger(&first));
    }
}

test "pre-call request closure requires every operation terminal" {
    for ([_]bool{ false, true }) |invoke| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = .{ .failed = .authentication_failed };
        const graph = try fixture.compile(try requestTerminationYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareRequestTermination(&runner, false, invoke);
        const ledger = try requestLedger(&runner);
        const state = &runner.model_accounting.?;
        const prepared = (try currentRequest(&runner)).prepared().?;
        var id = (try completedOperation(&runner)).record().id;
        id.kind = .input_token_count;
        const authority = state.operationAuthority(ledger);
        const assigned = try lifecycle.propose(state.current_operations, authority, state.current_operations.revision(), id, null, .{ .assign_count = .{ .binding_id = prepared.binding_id, .model_visible_input_id = prepared.model_visible_input_id } });
        state.current_operations = try lifecycle.apply(state.current_operations, authority, assigned);
        if (invoke) {
            const invoked = try lifecycle.propose(state.current_operations, authority, state.current_operations.revision(), id, state.current_operations.record(id).?.revision, .{ .invoke = .{ .deadline_monotonic_ms = 1000 } });
            state.current_operations = try lifecycle.apply(state.current_operations, authority, invoked);
        }
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "close-request" }).rejected);
        try std.testing.expectError(error.ProviderOperationStillOpen, fixture.native.terminate_request.action.execute(ledger, state.current_operations, ledger.revision(), prepared.model_request_id, if (invoke) .invoked else .assigned, .{ .terminal = if (invoke) .failed else .not_invoked_authorization_failure }));
        try std.testing.expect(ledger == try requestLedger(&runner));
    }
}

fn expectNoProviderEffects(runner: *const runner_module.Runner, fake: *const fake_provider.FakeLLMProvider) !void {
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 0), runner.tokenLedger().revision().value);
}

test "pre-call request closure rejects forged successors and cancellation before publication" {
    const Spy = RequestClosureSpy(request_termination.Terminate);
    for (std.enums.values(Spy.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = .{ .failed = .authentication_failed };
        const graph = try fixture.compile(try requestTerminationYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareRequestTermination(&runner, false, true);
        var spy: Spy = .{ .inner = &fixture.native.terminate_request, .fault = fault };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, request_termination.Terminate.contract.id)) {
            entry.binding = bindings.bind(Spy, &spy, Spy.invoke);
        };
        runner.runtime = .{ .context = &spy, .status_fn = Spy.status };
        const ledger = try requestLedger(&runner);
        const original_operations = runner.model_accounting.?.current_operations;
        const original_authorization = try authorizationResult(&runner);
        const result = runner.bindings().invokeStep(.{ .bytes = "close-request" });
        switch (fault) {
            .cancelled => try std.testing.expectEqual(.cancelled, result.rejected),
            else => try std.testing.expectEqual(.authority, result.rejected),
        }
        try std.testing.expect(ledger == try requestLedger(&runner));
        try std.testing.expect(ledger == identity.ledger(runner.model_accounting.?.requests));
        try std.testing.expect(original_operations == runner.model_accounting.?.current_operations);
        try std.testing.expect(original_authorization == try authorizationResult(&runner));
    }
}

test "pre-call request closure allocation failures release every owner and deposited capability" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        for ([_]bool{ false, true }) |cancelled| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(try requestTerminationYaml(&fixture, kind));
            try std.testing.checkAllAllocationFailures(std.testing.allocator, requestTerminationAllocationCase, .{ &fixture, graph, cancelled });
            try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
        }
    }
}

fn requestTerminationAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, cancelled: bool) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    var spy: RejectedDeposit = .{ .fixture = fixture, .cancelled = cancelled };
    fixture.native.prepare_authorization.action = .{ .authorization = spy.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const actual = harness.run();
    try expectNoProviderEffects(&runner, &fake);
    const record = if (requestLedger(&runner)) |ledger| ledger.latestRecord() else |_| null;
    if (record == null or record.?.status != .terminal) {
        try std.testing.expectEqual(.failed, actual);
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(@as(workflow.OutcomeTag, if (cancelled) .cancelled else .failed), actual);
    try std.testing.expectEqual(@as(identity.TerminalReason, if (cancelled) .cancelled else .not_invoked_authorization_failure), record.?.terminal_reason.?);
    try runner.model_accounting.?.current_operations.validateRequestClosure((try currentRequest(&runner)).id());
}

test "pre-call request closure rejects YAML assertions missing prerequisites and forged projections" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try requestTerminationYaml(&fixture, "inference");
    for ([_][2][]const u8{
        .{ "use: terminate-model-request,", "use: hidden-request-termination," },
        .{ "use: terminate-model-request,", "use: terminate-model-request, with: {reason: failed}," },
        .{ "use: terminate-model-request,", "use: terminate-model-request, with: {transition: terminal}," },
        .{ "use: terminate-model-request,", "use: terminate-model-request, with: {retry-limit: 1}," },
        .{ "use: terminate-model-request,", "use: terminate-model-request, with: {timeout-ms: 100}," },
        .{ "use: terminate-model-request,", "use: terminate-model-request, with: {slot: selected}," },
        .{ "use: terminate-provider-operation, on: {failed: close-request, cancelled: close-request}", "use: core.noop, on: {ok: close-request}" },
        .{ "use: prepare-provider-operation-authorization, with: {timeout-ms: 1000}, on: {ok: end.ok, failed: terminate, cancelled: terminate}", "use: core.noop, on: {ok: terminate}" },
        .{ "failed: end.failed", "failed: end.ok" },
        .{ "cancelled: end.cancelled", "cancelled: end.ok" },
        .{ "use: terminate-model-request, on: {failed: observe, cancelled: observe}", "use: terminate-model-request, on: {failed: observe}" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, changed, source));
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
    const graph = try fixture.compile(source);
    for (0..7) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, request_termination.Terminate.contract.id)) {
            switch (variant) {
                0 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation },
                1 => step.capabilities = &.{"provider-authorization"},
                2 => step.replaces = &.{ .model_request_identity_ledger, .prepared_model_request },
                3 => step.outcomes = &.{ .ok, .failed, .cancelled },
                4 => step.optional = &.{.model_payload_schema_result},
                5 => step.invalidates = &.{.provider_authorization_result},
                6 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result },
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "close-request" }).rejected);
    }
}

test "YAML pre-call termination preserves authorization failure and cancellation for both operation kinds" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        for ([_]@import("adapters/provider/fake_provider_authorization.zig").Plan{ .{ .failed = .authentication_failed }, .{ .failed = .authorization_denied }, .cancelled }) |plan| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            fixture.authorization.plan = plan;
            const graph = try fixture.compile(try terminationYaml(&fixture, kind));
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            var harness: Harness = .{ .runner = &runner };
            const expected: workflow.OutcomeTag = if (plan == .cancelled) .cancelled else .failed;
            try std.testing.expectEqual(expected, harness.run());
            const terminal = try completedOperation(&runner);
            const record = terminal.record();
            const current = runner.model_accounting.?.current_operations;
            try std.testing.expect(terminal == try current.requireTerminal(record.id));
            try std.testing.expectEqual(@as(u64, 2), current.revision().value);
            try std.testing.expectEqual(@as(u64, 2), record.revision.value);
            const original = (try authorizationResult(&runner)).outcome();
            if (plan == .cancelled) {
                try std.testing.expectEqual(.not_sent, record.state.terminal.cancelled);
                try std.testing.expect(original.cancelled.eql(record.id));
            } else {
                try std.testing.expectEqual(original.failed.cause, record.state.terminal.preparation_failed.cause);
                try std.testing.expectEqual(original.failed.retry_class, record.state.terminal.preparation_failed.retry_class);
                try std.testing.expectEqual(.not_sent, record.state.terminal.preparation_failed.delivery);
                try std.testing.expect(original.failed.operation_id.eql(record.id));
            }
            try current.validateRequestClosure(record.id.model_request_id);
            try std.testing.expectEqual(.assigned, (try requestLedger(&runner)).record(record.id.model_request_id).?.status);
            const attempt_evidence = try values.read(&.{ .slots = runner.envelope.slots }, attempt_values.schema, attempt_accounting.AccountedAttempt);
            try std.testing.expectEqual(@as(u32, 1), attempt_evidence.ordinal().value);
            try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
            try std.testing.expectEqual(expected, runner.envelope.origins[@intFromEnum(attempt_values.terminal_schema.key)].?.outcome);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.operation_schema.key)] == null);
            try expectNoProviderEffects(&runner, &fake);
        }
    }
}

test "pre-call termination rejects prepared missing duplicate and stale evidence without mutation" {
    for ([_]bool{ false, true }) |prepared| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = if (prepared) .prepared else .{ .failed = .authorization_denied };
        const graph = try fixture.compile(try terminationYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareTermination(&runner, if (prepared) .ok else .failed);
        const original = runner.model_accounting.?.current_operations;
        const saved = try values.retain(runner.envelope.slots[@intFromEnum(attempt_values.operation_schema.key)].?);
        defer values.destroy(saved);
        if (prepared) {
            try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "terminate" }).rejected);
            try std.testing.expect(original == runner.model_accounting.?.current_operations);
            _ = try runner.model_accounting.?.authorization_leases.canonicalReference((try authorizationResult(&runner)).outcome().prepared);
            try std.testing.expectEqual(@as(usize, 0), fixture.authorization.destroyed_count);
            continue;
        }
        for (termination_workflow.Terminate.contract.requires) |key| {
            const index = @intFromEnum(key);
            const value = runner.envelope.slots[index];
            runner.envelope.slots[index] = null;
            const rejected = runner.bindings().invokeStep(.{ .bytes = "terminate" });
            runner.envelope.slots[index] = value;
            try std.testing.expectEqual(.authority, rejected.rejected);
            try std.testing.expect(original == runner.model_accounting.?.current_operations);
        }
        try std.testing.expectEqual(.failed, runner.bindings().invokeStep(.{ .bytes = "terminate" }).outcome);
        const terminal = runner.model_accounting.?.current_operations;
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "terminate" }).rejected);
        const index = @intFromEnum(attempt_values.operation_schema.key);
        runner.envelope.slots[index] = saved;
        const stale = runner.bindings().invokeStep(.{ .bytes = "terminate" });
        runner.envelope.slots[index] = null;
        try std.testing.expectEqual(.authority, stale.rejected);
        try std.testing.expect(terminal == runner.model_accounting.?.current_operations);
        try std.testing.expectEqual(.assigned, original.record((try completedOperation(&runner)).record().id).?.state);
    }
}

test "pre-call termination rejects foreign inputs and invalid authorization facts" {
    for ([_]bool{ false, true }) |cancelled| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = if (cancelled) .cancelled else .{ .failed = .authentication_failed };
        const graph = try fixture.compile(try terminationYaml(&fixture, "inference"));
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        try prepareTermination(&first, if (cancelled) .cancelled else .failed);
        try prepareTermination(&second, if (cancelled) .cancelled else .failed);
        const original = first.model_accounting.?.current_operations;
        for (termination_workflow.Terminate.contract.requires) |key| {
            const index = @intFromEnum(key);
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            const rejected = first.bindings().invokeStep(.{ .bytes = "terminate" });
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            try std.testing.expectEqual(.authority, rejected.rejected);
            try std.testing.expect(original == first.model_accounting.?.current_operations);
        }
        for (0..4) |variant| {
            var id = (try assignedOperation(&first)).record().id;
            if (variant == 0) id.kind = .input_token_count;
            if (variant == 1) id.model_attempt_ordinal.value += 1;
            const outcome: authorization_result.Outcome = if (cancelled and variant < 2) .{ .cancelled = id } else .{ .failed = .{
                .operation_id = id,
                .cause = .authentication_failed,
                .retry_class = if (variant == 2) .policy_eligible else .never,
                .delivery = if (variant == 3) .response_received else .not_sent,
            } };
            const owner = try authorization_result.create(std.testing.allocator, try requestLedger(&first), outcome);
            const value = try values.adopt(std.testing.allocator, authorization_workflow.schema, authorization_result.Result, authorization_result.Result, owner, authorization_result_view, authorization_result.destroy, null);
            defer values.destroy(value);
            const index = @intFromEnum(authorization_workflow.schema.key);
            const saved = first.envelope.slots[index];
            first.envelope.slots[index] = value;
            const rejected = first.bindings().invokeStep(.{ .bytes = "terminate" });
            first.envelope.slots[index] = saved;
            try std.testing.expectEqual(.authority, rejected.rejected);
            try std.testing.expect(original == first.model_accounting.?.current_operations);
        }
    }
}

test "pre-call termination and terminal-result consumers require no clock or provider deadline" {
    for ([_]bool{ false, true }) |cancelled| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = if (cancelled) .cancelled else .{ .failed = .authorization_denied };
        const graph = try fixture.compile(try terminationYaml(&fixture, "input-token-count"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        const expected: workflow.OutcomeTag = if (cancelled) .cancelled else .failed;
        try prepareTermination(&runner, expected);
        const original_request = try requestLedger(&runner);
        const original_result = try authorizationResult(&runner);
        fixture.clock.now_ms = 1001;
        fixture.clock.unavailable = true;
        runner.provider_clock = null;
        try std.testing.expectEqual(expected, runner.bindings().invokeStep(.{ .bytes = "terminate" }).outcome);
        try std.testing.expectEqual(expected, runner.bindings().invokeStep(.{ .bytes = "observe" }).outcome);
        try std.testing.expect(original_request == try requestLedger(&runner));
        try std.testing.expect(original_result == try authorizationResult(&runner));
        try expectNoProviderEffects(&runner, &fake);
    }
}

test "authorization result consumers require exactly one current lifecycle phase and prepared leases still need a clock" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try terminationYaml(&fixture, "inference"));
    const consumer = &fixture.entries[fixture.entries.len - 1];
    const original = consumer.contract.requires;
    defer consumer.contract.requires = original;
    const common = [_]pipeline.DataKey{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .provider_authorization_result };
    for ([_]pipeline.DataKey{ .assigned_provider_operation, .invoked_provider_operation, .terminal_provider_operation }) |phase| {
        const one = common ++ [_]pipeline.DataKey{phase};
        consumer.contract.requires = &one;
        try std.testing.expect(fixture.registry.validate());
    }
    consumer.contract.requires = &common;
    try std.testing.expect(!fixture.registry.validate());
    for ([_]pipeline.DataKey{ .assigned_provider_operation, .invoked_provider_operation }) |phase| {
        const mixed = common ++ [_]pipeline.DataKey{ phase, .terminal_provider_operation };
        consumer.contract.requires = &mixed;
        try std.testing.expect(!fixture.registry.validate());
    }
    consumer.contract.requires = original;
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    try prepareTermination(&runner, .ok);
    const ledger = runner.model_accounting.?.current_operations;
    runner.provider_clock = null;
    try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "terminate" }).rejected);
    try std.testing.expect(ledger == runner.model_accounting.?.current_operations);
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
}

test "pre-call termination releases deposited backing once and retains evidence after runner cleanup" {
    for ([_]bool{ false, true }) |cancelled| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var spy: RejectedDeposit = .{ .fixture = &fixture, .cancelled = cancelled };
        fixture.native.prepare_authorization.action = .{ .authorization = spy.port() };
        const graph = try fixture.compile(try terminationYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        var active = true;
        defer if (active) runner.deinit();
        const expected: workflow.OutcomeTag = if (cancelled) .cancelled else .failed;
        try prepareTermination(&runner, expected);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepared_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        try std.testing.expectEqual(expected, runner.bindings().invokeStep(.{ .bytes = "terminate" }).outcome);
        const terminal = try completedOperation(&runner);
        const result = try authorizationResult(&runner);
        const terminal_owner = try values.retain(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)].?);
        defer values.destroy(terminal_owner);
        const result_owner = try values.retain(runner.envelope.slots[@intFromEnum(authorization_workflow.schema.key)].?);
        defer values.destroy(result_owner);
        runner.deinit();
        active = false;
        const id = terminal.record().id;
        if (cancelled) {
            try std.testing.expectEqual(.not_sent, terminal.record().state.terminal.cancelled);
            try std.testing.expect(result.outcome().cancelled.eql(id));
        } else {
            try std.testing.expectEqual(.authentication_failed, terminal.record().state.terminal.preparation_failed.cause);
            try std.testing.expect(result.outcome().failed.operation_id.eql(id));
        }
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    }
}

const RejectedDeposit = struct {
    fixture: *Fixture,
    cancelled: bool,

    fn port(self: *@This()) authorization_port.Port {
        return .{ .context = @ptrCast(self), .prepare_fn = prepare };
    }

    fn prepare(context: *authorization_port.Context, facts: authorization_port.Facts, slot: authorization_port.Slot) authorization_port.Error!authorization_port.Observation {
        const self: *@This() = @ptrCast(@alignCast(context));
        _ = try self.fixture.authorization.port().prepare(facts, slot);
        return if (self.cancelled) error.Cancelled else .{ .failed = .authentication_failed };
    }
};

test "runtime cancellation abandons authorization without hidden pre-call termination" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var spy: AuthorizationSpy = .{ .fixture = &fixture, .fault = .cancel };
    fixture.native.prepare_authorization.action = .{ .authorization = spy.port() };
    const graph = try fixture.compile(try terminationYaml(&fixture, "inference"));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    runner.runtime = .{ .context = &spy, .status_fn = AuthorizationSpy.status };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.cancelled, harness.run());
    try std.testing.expectEqual(.assigned, (try assignedOperation(&runner)).record().state);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(authorization_workflow.schema.key)] == null);
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepared_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

test "pre-call termination rejects forged deltas and cancellation before publication" {
    const Spy = TerminalDeltaSpy(termination_workflow.Terminate);
    for (std.enums.values(Spy.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        fixture.authorization.plan = .{ .failed = .authorization_denied };
        const graph = try fixture.compile(try terminationYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareTermination(&runner, .failed);
        var spy: Spy = .{ .inner = &fixture.native.terminate_operation, .fault = fault };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, termination_workflow.Terminate.contract.id)) {
            entry.binding = bindings.bind(Spy, &spy, Spy.invoke);
        };
        runner.runtime = .{ .context = &spy, .status_fn = Spy.status };
        const ledger = runner.model_accounting.?.current_operations;
        const original = try authorizationResult(&runner);
        const rejected = runner.bindings().invokeStep(.{ .bytes = "terminate" });
        if (fault == .cancelled) try std.testing.expectEqual(.cancelled, rejected.rejected) else try std.testing.expectEqual(.authority, rejected.rejected);
        try std.testing.expect(ledger == runner.model_accounting.?.current_operations);
        try std.testing.expect(original == try authorizationResult(&runner));
        try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
        try std.testing.expectEqual(.assigned, (try assignedOperation(&runner)).record().state);
    }
}

test "pre-call termination allocation failures release every owner without calls or token usage" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        for ([_]bool{ false, true }) |cancelled| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(try terminationYaml(&fixture, kind));
            try std.testing.checkAllAllocationFailures(std.testing.allocator, terminationAllocationCase, .{ &fixture, graph, cancelled });
            try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
        }
    }
}

fn terminationAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, cancelled: bool) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    var spy: RejectedDeposit = .{ .fixture = fixture, .cancelled = cancelled };
    fixture.native.prepare_authorization.action = .{ .authorization = spy.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const actual = harness.run();
    try expectNoProviderEffects(&runner, &fake);
    if (runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null) {
        try std.testing.expectEqual(.failed, actual);
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(@as(workflow.OutcomeTag, if (cancelled) .cancelled else .failed), actual);
    const record = (try completedOperation(&runner)).record();
    try runner.model_accounting.?.current_operations.validateRequestClosure(record.id.model_request_id);
    try std.testing.expectEqual(.assigned, (try requestLedger(&runner)).record(record.id.model_request_id).?.status);
}

test "pre-call termination rejects YAML assertions missing prerequisites and forged compiled contracts" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try terminationYaml(&fixture, "inference");
    for ([_][2][]const u8{
        .{ "use: terminate-provider-operation,", "use: hidden-provider-termination," },
        .{ "use: terminate-provider-operation,", "use: terminate-provider-operation, with: {outcome: preparation_failed}," },
        .{ "use: terminate-provider-operation,", "use: terminate-provider-operation, with: {delivery: not_sent}," },
        .{ "use: terminate-provider-operation,", "use: terminate-provider-operation, with: {timeout-ms: 100}," },
        .{ "use: terminate-provider-operation,", "use: terminate-provider-operation, with: {retry-limit: 1}," },
        .{ "use: terminate-provider-operation,", "use: terminate-provider-operation, with: {slot: selected}," },
        .{ "on: {failed: observe, cancelled: observe}", "on: {failed: end.ok, cancelled: end.cancelled}" },
        .{ "on: {failed: observe, cancelled: observe}", "on: {failed: end.failed}" },
        .{ "use: prepare-provider-operation-authorization, with: {timeout-ms: 1000}, on: {ok: end.ok, failed: terminate, cancelled: terminate}", "use: core.noop, on: {ok: terminate}" },
        .{ "use: assign-provider-operation, with: {kind: inference}, on: {ok: authorize, failed: end.failed}", "use: core.noop, on: {ok: authorize}" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, changed, source));
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
    const graph = try fixture.compile(source);
    for (0..6) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, termination_workflow.Terminate.contract.id)) {
            switch (variant) {
                0 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .assigned_provider_operation },
                1 => step.capabilities = &.{"provider-authorization"},
                2 => step.invalidates = &.{.invoked_provider_operation},
                3 => step.runner_accounting = .none,
                4 => step.optional = &.{.provider_invocation_validation_result},
                5 => step.outcomes = &.{ .ok, .failed, .cancelled },
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "terminate" }).rejected);
    }
}

test "YAML advances the logical request once while preserving its request attempt operation and lease" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try requestLifecycleYaml(&fixture, kind));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareAuthorized(&runner);
        const before = runner.envelope.slots;
        const current = try requestLedger(&runner);
        const id = (try currentRequest(&runner)).id();
        try std.testing.expectEqual(.assigned, current.record(id).?.status);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).outcome);
        const next = try requestLedger(&runner);
        try std.testing.expect(next != current);
        try std.testing.expectEqual(current.revision().value + 1, next.revision().value);
        try std.testing.expectEqual(current.recordCount(), next.recordCount());
        try std.testing.expect(next.canonicalRequestId(id) == id);
        try std.testing.expectEqual(.assigned, current.record(id).?.status);
        try std.testing.expectEqual(.invoked, next.record(id).?.status);
        try std.testing.expect(next == identity.ledger(runner.model_accounting.?.requests));
        for (before, runner.envelope.slots, 0..) |old, new, index| {
            if (index != @intFromEnum(requests.ledger_schema.key)) try std.testing.expect(old == new);
        }
        try std.testing.expectEqual(.assigned, (try assignedOperation(&runner)).record().state);
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepare_count);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "observe" }).outcome);
        try std.testing.expectEqualDeep(execution.Rejection{ .operation_failed = error.OperationExecutionFailed }, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).rejected);
        try std.testing.expect(try requestLedger(&runner) == next);
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        var harness: Harness = .{ .runner = &second };
        try std.testing.expectEqual(.ok, harness.run());
        try std.testing.expect(!(try requestLedger(&second)).stageRunEpochId().eql(next.stageRunEpochId()));
    }
}

test "request lifecycle YAML rejects hidden transitions retry rebinding and absent authorization" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try requestLifecycleYaml(&fixture, "inference");
    for ([_][2][]const u8{
        .{ "with: {transition: invoked}, ", "" },
        .{ "transition: invoked", "transition: assigned" },
        .{ "transition: invoked", "transition: terminal" },
        .{ "transition: invoked", "transition: true" },
        .{ "transition: invoked", "transition: 1" },
        .{ "transition: invoked", "transition: invoked, retry-limit: 1" },
        .{ "transition: invoked", "transition: invoked, timeout-ms: 1000" },
        .{ "transition: invoked", "transition: invoked, slot: selected" },
        .{ "transition: invoked", "transition: invoked, input: data" },
        .{ "use: prepare-provider-operation-authorization, with: {timeout-ms: 1000}, on: {ok: advance-request, failed: end.failed, cancelled: end.cancelled}", "use: core.noop, on: {ok: advance-request}" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, source, invalid));
        if (fixture.compile(invalid)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.WorkflowGraphCompileInvalid, error.WorkflowDefinitionSchemaInvalid, error.WorkflowDefinitionParseError => {},
            else => return err,
        }
    }
}

test "failed cancelled expired and foreign authorization cannot advance a logical request" {
    for (0..5) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const source = try requestLifecycleYaml(&fixture, "inference");
        const graph = try fixture.compile(source);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareAuthorized(&runner);
        const original = try requestLedger(&runner);
        const id = (try assignedOperation(&runner)).record().id;
        switch (variant) {
            0, 1 => {
                const owner = try authorization_result.create(std.testing.allocator, original, if (variant == 0)
                    .{ .failed = .{ .operation_id = id, .cause = .authentication_failed, .retry_class = .never, .delivery = .not_sent } }
                else
                    .{ .cancelled = id });
                const value = try values.adopt(std.testing.allocator, authorization_workflow.schema, authorization_result.Result, authorization_result.Result, owner, authorization_result_view, authorization_result.destroy, null);
                const key = @intFromEnum(authorization_workflow.schema.key);
                values.destroy(runner.envelope.slots[key].?);
                runner.envelope.slots[key] = value;
            },
            2 => fixture.clock.now_ms = 1001,
            3 => runner.runtime = .{ .status_fn = alwaysCancelled },
            4 => {
                var foreign = fixture.runner(graph, std.testing.allocator);
                defer foreign.deinit();
                try prepareAuthorized(&foreign);
                const key = @intFromEnum(authorization_workflow.schema.key);
                std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &runner.envelope.slots[key], &foreign.envelope.slots[key]);
                try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).rejected);
                try std.testing.expect(try requestLedger(&runner) == original);
                continue;
            },
            else => unreachable,
        }
        const applied = runner.bindings().invokeStep(.{ .bytes = "advance-request" });
        try std.testing.expectEqual(@as(execution.Rejection, switch (variant) {
            0 => .authority,
            1, 3 => .cancelled,
            2 => .deadline_exhausted,
            else => unreachable,
        }), applied.rejected);
        try std.testing.expect(try requestLedger(&runner) == original);
        try std.testing.expectEqual(.assigned, original.record(id.model_request_id).?.status);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    }
}

test "stale request-ledger snapshots cannot reset invocation or reach later consumers" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try requestLifecycleYaml(&fixture, "input-token-count"));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    try prepareAuthorized(&runner);
    const old_owner = try identity.retainLedger(try requestLedger(&runner));
    const stale = try requests.adoptLedger(std.testing.allocator, old_owner);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).outcome);
    const key = @intFromEnum(requests.ledger_schema.key);
    const current = runner.envelope.slots[key].?;
    runner.envelope.slots[key] = stale;
    defer {
        runner.envelope.slots[key] = current;
        values.destroy(stale);
    }
    for ([_][]const u8{ "advance-request", "observe", "authorize" }) |step| {
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = step }).rejected);
    }
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepare_count);
}

test "forged lifecycle successors and rejected deltas never publish request invocation" {
    for (std.enums.values(FaultyRequestLifecycle.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try requestLifecycleYaml(&fixture, "inference"));
        var faulty: FaultyRequestLifecycle = .{ .advance = fixture.native.advance_request, .fault = fault, .clock = &fixture.clock };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, request_lifecycle_workflow.Advance.contract.id)) {
            entry.binding = bindings.bind(FaultyRequestLifecycle, &faulty, FaultyRequestLifecycle.invoke);
        };
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            runner.runtime = .{ .context = &faulty, .status_fn = FaultyRequestLifecycle.status };
            try prepareAuthorized(&runner);
            const original = try requestLedger(&runner);
            const applied = runner.bindings().invokeStep(.{ .bytes = "advance-request" });
            try std.testing.expectEqual(@as(execution.Rejection, switch (fault) {
                .cancel => .cancelled,
                .expire => .deadline_exhausted,
                else => .authority,
            }), applied.rejected);
            try std.testing.expect(try requestLedger(&runner) == original);
            try std.testing.expect(identity.ledger(runner.model_accounting.?.requests) == original);
            try std.testing.expectEqual(.assigned, original.record((try currentRequest(&runner)).id()).?.status);
            try std.testing.expectEqual(@as(usize, 1), faulty.calls);
            try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

test "request lifecycle cancellation allocation faults and compiler tampering fail closed" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try requestLifecycleYaml(&fixture, "inference"));
    for (0..9) |boundary| {
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
            runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
            try std.testing.expectEqual(.cancelled, harness.run());
            if (boundary == 7) try std.testing.expectEqual(.assigned, (try requestLedger(&runner)).record((try currentRequest(&runner)).id()).?.status);
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ &fixture, graph });
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    fixture.native.init(std.testing.allocator);
    fixture.authorization.allocator = std.testing.allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, request_lifecycle_workflow.Advance.contract.id)) {
        const original = entry.*;
        entry.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request };
        try std.testing.expect(!fixture.registry.validate());
        entry.* = original;
        entry.contract.parameters = &.{};
        try std.testing.expect(!fixture.registry.validate());
        entry.* = original;
    };
    var tampered = graph.*;
    const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
    for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, request_lifecycle_workflow.Advance.contract.id)) {
        step.parameters = &.{};
    };
    tampered.authority.steps = steps;
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
}

const FaultyRequestLifecycle = struct {
    const Fault = enum { missing, undeclared_write, old_snapshot, assignment, terminal, skipped_revision, failed_outcome, cancel, expire };
    advance: request_lifecycle_workflow.Advance,
    fault: Fault,
    clock: *@import("provider_authorization_test_fixture.zig").TestClock,
    cancelled: bool = false,
    calls: usize = 0,
    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        self.calls += 1;
        var candidate = try request_lifecycle_workflow.Advance.invoke(&self.advance, input);
        const key = @intFromEnum(requests.ledger_schema.key);
        switch (self.fault) {
            .failed_outcome => candidate.outcome = .failed,
            .cancel => self.cancelled = true,
            .expire => self.clock.now_ms = 1001,
            .undeclared_write => candidate.delta.data_writes[@intFromEnum(pipeline.DataKey.raw_engine_config)] = values.create(std.testing.allocator, values.schema(.raw_engine_config, bool, 1, 1), bool, true) catch return error.OperationExecutionFailed,
            else => {
                const current = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
                const id = (try requests.readCurrent(&input.step.data, requests.prepared_schema)).id();
                const successor = values.read(&.{ .slots = candidate.delta.data_replacements }, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
                const owner: ?*identity.Owner = switch (self.fault) {
                    .missing => null,
                    .old_snapshot => identity.retainLedger(current) catch return error.OperationExecutionFailed,
                    .assignment => (identity.createSuccessor(current, current.revision(), id.immutable_unit_owner_id, id.model_operation_id, id.purpose) catch return error.OperationExecutionFailed).owner,
                    .terminal => identity.createLifecycleSuccessor(current, current.revision(), id, .assigned, .{ .terminal = .cancelled }) catch return error.OperationExecutionFailed,
                    .skipped_revision => identity.createLifecycleSuccessor(successor, successor.revision(), id, .invoked, .{ .terminal = .accepted }) catch return error.OperationExecutionFailed,
                    else => unreachable,
                };
                values.destroy(candidate.delta.data_replacements[key].?);
                candidate.delta.data_replacements[key] = if (owner) |value| requests.adoptLedger(std.testing.allocator, value) catch return error.OperationExecutionFailed else null;
            },
        }
        return candidate;
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const @This() = @ptrCast(@alignCast(context.?));
        return if (self.cancelled) .cancelled else .active;
    }
};

fn requestLifecycleYaml(fixture: *Fixture, kind: []const u8) ![]const u8 {
    const source = try authorizationYaml(fixture, kind);
    fixture.observer.expected_request_status = .invoked;
    const replaced = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, "ok: observe, failed: observe", "ok: advance-request, failed: end.failed");
    return std.fmt.allocPrint(fixture.arena.allocator(), "{s}\n  advance-request: {{ use: advance-model-request-lifecycle, with: {{transition: invoked}}, on: {{ok: observe, failed: end.failed}} }}\n", .{replaced});
}

fn prepareAuthorized(runner: *runner_module.Runner) !void {
    try std.testing.expectEqual(.ok, runner.bindings().invokeInvocation().outcome);
    for ([_][]const u8{ "initialize", "origin", "validate", "build", "account", "assign-operation", "authorize" }) |step| {
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    }
}

fn requestLedger(runner: *const runner_module.Runner) !*const identity.ModelRequestIdentityLedger {
    return values.read(&.{ .slots = runner.envelope.slots }, requests.ledger_schema, identity.ModelRequestIdentityLedger);
}

fn authorization_result_view(value: *const authorization_result.Result) *const authorization_result.Result {
    return value;
}

fn alwaysCancelled(_: ?*anyopaque) pipeline.RuntimeStatus {
    return .cancelled;
}

test "YAML provider invocation publishes canonical evidence with the original lease deadline for both kinds" {
    for ([_][]const u8{ "inference", "input-token-count" }) |kind| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try operationLifecycleYaml(&fixture, kind));
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            try prepareInvocable(&runner);
            const before = runner.envelope.slots;
            const assigned = (try assignedOperation(&runner)).record().*;
            const previous = runner.model_accounting.?.current_operations;
            fixture.clock.now_ms = 250;
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
            const invoked = (try invokedOperation(&runner)).operation();
            const current = runner.model_accounting.?.current_operations;
            try std.testing.expect(invoked == try current.requireInvoked(assigned.id));
            try std.testing.expectEqual(@as(u64, 1001), invoked.deadline_monotonic_ms);
            try std.testing.expectEqual(previous.revision().value + 1, current.revision().value);
            try std.testing.expectEqual(assigned.revision.value + 1, current.record(assigned.id).?.revision.value);
            try std.testing.expectEqual(.assigned, std.meta.activeTag(previous.record(assigned.id).?.state));
            try std.testing.expect(runner.model_accounting.?.authorization_leases.operations == current);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.assigned_provider_operation)] == null);
            for (before, runner.envelope.slots, 0..) |old, new, index| {
                if (index != @intFromEnum(pipeline.DataKey.assigned_provider_operation) and index != @intFromEnum(pipeline.DataKey.invoked_provider_operation)) try std.testing.expect(old == new);
            }
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "observe" }).outcome);
            try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).rejected);
            try std.testing.expect(current == runner.model_accounting.?.current_operations);
            try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
            try std.testing.expectEqual(@as(usize, 1), fixture.authorization.prepare_count);
            try std.testing.expectEqual(@as(usize, 0), fixture.authorization.destroyed_count);

            // Invocation-state advancement did not consume the capability. The
            // existing adapter port can consume this exact canonical proof once.
            const request = try currentRequest(&runner);
            const reference = &(try authorizationResult(&runner)).outcome().prepared;
            const port = runner.model_accounting.?.authorization_leases.port(fixture.clock.port(), .{});
            var capability = try port.consume(reference, request.binding(), request.prepared().?, invoked);
            defer capability.deinit();
            try std.testing.expectError(error.AuthorizationDenied, port.consume(reference, request.binding(), request.prepared().?, invoked));
            try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
        fixture.clock.now_ms = 1;
        var fresh = fixture.runner(graph, std.testing.allocator);
        defer fresh.deinit();
        var harness: Harness = .{ .runner = &fresh };
        try std.testing.expectEqual(.ok, harness.run());
        try std.testing.expectEqual(@as(u128, 0), fresh.tokenLedger().committed());
    }
}

test "provider invocation YAML rejects missing unknown hidden and replacement parameters" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try operationLifecycleYaml(&fixture, "inference");
    const valid = "use: advance-provider-operation-lifecycle, with: {transition: invoked}";
    const invalid = [_][]const u8{
        "use: advance-provider-operation-lifecycle",
        "use: advance-provider-operation-lifecycle, with: {transition: terminal}",
        "use: advance-provider-operation-lifecycle, with: {transition: assigned}",
        "use: advance-provider-operation-lifecycle, with: {transition: 1}",
        "use: advance-provider-operation-lifecycle, with: {transition: invoked, timeout-ms: 2000}",
        "use: advance-provider-operation-lifecycle, with: {transition: invoked, retry-limit: 1}",
        "use: advance-provider-operation-lifecycle, with: {transition: invoked, kind: input-token-count}",
        "use: advance-provider-operation-lifecycle, with: {transition: invoked, slot: selected}",
        "use: advance-provider-operation-lifecycle, with: {transition: invoked, prompt: prompt}",
        "use: hidden-provider-invocation, with: {transition: invoked}",
    };
    for (invalid) |replacement| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, valid, replacement);
        if (fixture.compile(changed)) |_| return error.ExpectedRejection else |err| switch (err) {
            error.WorkflowGraphCompileInvalid, error.WorkflowDefinitionSchemaInvalid => {},
            else => return err,
        }
    }
    const missing = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, "use: prepare-provider-operation-authorization, with: {timeout-ms: 1000}", "use: core.noop");
    try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(missing));
}

test "provider invocation requires an invoked request and rejects failed cancelled expired and foreign leases" {
    for (0..7) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try operationLifecycleYaml(&fixture, "inference"));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareAuthorized(&runner);
        if (variant != 0) try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).outcome);
        const original = runner.model_accounting.?.current_operations;
        const id = (try assignedOperation(&runner)).record().id;
        switch (variant) {
            0 => {},
            1, 2 => {
                const owner = try authorization_result.create(std.testing.allocator, try requestLedger(&runner), if (variant == 1)
                    .{ .failed = .{ .operation_id = id, .cause = .authentication_failed, .retry_class = .never, .delivery = .not_sent } }
                else
                    .{ .cancelled = id });
                const value = try values.adopt(std.testing.allocator, authorization_workflow.schema, authorization_result.Result, authorization_result.Result, owner, authorization_result_view, authorization_result.destroy, null);
                const key = @intFromEnum(authorization_workflow.schema.key);
                values.destroy(runner.envelope.slots[key].?);
                runner.envelope.slots[key] = value;
            },
            3 => fixture.clock.now_ms = 1001,
            4 => runner.runtime = .{ .status_fn = alwaysCancelled },
            5 => {
                var foreign = fixture.runner(graph, std.testing.allocator);
                defer foreign.deinit();
                try prepareInvocable(&foreign);
                const key = @intFromEnum(authorization_workflow.schema.key);
                std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &runner.envelope.slots[key], &foreign.envelope.slots[key]);
                try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).rejected);
                try std.testing.expect(original == runner.model_accounting.?.current_operations);
                continue;
            },
            6 => runner.provider_clock = null,
            else => unreachable,
        }
        const applied = runner.bindings().invokeStep(.{ .bytes = "advance-operation" });
        try std.testing.expectEqual(@as(execution.Rejection, switch (variant) {
            0 => .{ .operation_failed = error.OperationExecutionFailed },
            1, 6 => .authority,
            2, 4 => .cancelled,
            3 => .deadline_exhausted,
            else => unreachable,
        }), applied.rejected);
        try std.testing.expect(original == runner.model_accounting.?.current_operations);
        try std.testing.expectEqual(.assigned, std.meta.activeTag(original.record(id).?.state));
        try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.invoked_provider_operation)] == null);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    }
}

test "provider invocation rejects forged transitions and deltas without publishing state or evidence" {
    for (std.enums.values(FaultyOperationLifecycle.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try operationLifecycleYaml(&fixture, "inference"));
        var faulty: FaultyOperationLifecycle = .{ .advance = fixture.native.advance_operation, .fault = fault, .clock = &fixture.clock };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, operation_lifecycle_workflow.Advance.contract.id)) {
            entry.binding = bindings.bind(FaultyOperationLifecycle, &faulty, FaultyOperationLifecycle.invoke);
        };
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            runner.runtime = .{ .context = &faulty, .status_fn = FaultyOperationLifecycle.status };
            try prepareInvocable(&runner);
            const original = runner.model_accounting.?.current_operations;
            const before = runner.envelope.slots;
            const applied = runner.bindings().invokeStep(.{ .bytes = "advance-operation" });
            try std.testing.expectEqual(@as(execution.Rejection, switch (fault) {
                .cancel => .cancelled,
                .expire => .deadline_exhausted,
                else => .authority,
            }), applied.rejected);
            try std.testing.expect(original == runner.model_accounting.?.current_operations);
            try std.testing.expectEqualSlices(?*@import("domain/pipeline_data.zig").Value, &before, &runner.envelope.slots);
            try std.testing.expectEqual(@as(usize, 1), faulty.calls);
            try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
            try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

test "invoked evidence cannot cross executions or outlive its canonical status" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try operationLifecycleYaml(&fixture, "input-token-count"));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    for ([_]*runner_module.Runner{ &first, &second }) |runner| {
        try prepareInvocable(runner);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
    }
    const key = @intFromEnum(pipeline.DataKey.invoked_provider_operation);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    const state = &first.model_accounting.?;
    const invoked = (try invokedOperation(&first)).operation();
    const authority = state.operationAuthority(try requestLedger(&first));
    const current = state.current_operations;
    const terminal = try lifecycle.propose(current, authority, current.revision(), invoked.id, current.record(invoked.id).?.revision, .{ .terminate = .{ .cancelled = .not_sent } });
    state.current_operations = try lifecycle.apply(current, authority, terminal);
    state.authorization_leases.update(state.current_operations);
    try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

test "provider invocation cancellation allocation failures and retained evidence clean up exactly once" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try operationLifecycleYaml(&fixture, "inference"));
    for (0..10) |boundary| {
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
            runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
            try std.testing.expectEqual(.cancelled, harness.run());
            if (boundary == 8) try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.invoked_provider_operation)] == null);
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ &fixture, graph });
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    fixture.native.init(std.testing.allocator);
    fixture.authorization.allocator = std.testing.allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, std.testing.allocator);
    try prepareInvocable(&runner);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
    const evidence = try invokedOperation(&runner);
    const key = @intFromEnum(pipeline.DataKey.invoked_provider_operation);
    const retained = runner.envelope.slots[key].?;
    runner.envelope.slots[key] = null;
    defer values.destroy(retained);
    runner.deinit();
    try std.testing.expectEqualStrings("origin", evidence.operation().id.model_request_id.model_operation_id.workflow_step_id.bytes);
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
}

test "provider invocation accounting permission and exact compiled profile cannot be hidden or weakened" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try operationLifecycleYaml(&fixture, "inference"));
    for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, operation_lifecycle_workflow.Advance.contract.id)) {
        const original = entry.*;
        for (0..6) |variant| {
            switch (variant) {
                0 => entry.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt },
                1 => entry.contract.runner_accounting = .none,
                2 => entry.contract.parameters = &.{},
                3 => entry.contract.invalidates = &.{},
                4 => entry.contract.produces = &.{ .invoked_provider_operation, .assigned_provider_operation },
                5 => entry.contract.replaces = &.{.provider_authorization_result},
                else => unreachable,
            }
            try std.testing.expect(!fixture.registry.validate());
            entry.* = original;
        }
    };
    for (0..5) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, operation_lifecycle_workflow.Advance.contract.id)) {
            switch (variant) {
                0 => step.parameters = &.{},
                1 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt },
                2 => step.runner_accounting = .none,
                3 => step.invalidates = &.{},
                4 => step.capabilities = &.{"model-provider"},
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        try prepareInvocable(&runner);
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).rejected);
    }
}

test "provider invocation rechecks cancellation and lease deadline after allocating candidate evidence" {
    for (std.enums.values(PublicationGuard.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try operationLifecycleYaml(&fixture, "inference"));
        var counted = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        {
            var runner = fixture.runner(graph, counted.allocator());
            defer runner.deinit();
            try prepareInvocable(&runner);
            const before = runner.envelope.slots;
            const current = runner.model_accounting.?.current_operations;
            var guard: PublicationGuard = .{ .allocations = &counted, .before = counted.allocated_bytes, .fault = fault };
            runner.provider_clock = .{ .context = @ptrCast(&guard), .now_fn = PublicationGuard.now };
            runner.runtime = .{ .context = &guard, .status_fn = PublicationGuard.status };
            const result = runner.bindings().invokeStep(.{ .bytes = "advance-operation" });
            try std.testing.expectEqual(@as(execution.Rejection, switch (fault) {
                .expire, .deadline => .deadline_exhausted,
                .cancel => .cancelled,
                .clock => .authority,
            }), result.rejected);
            try std.testing.expect(guard.checked_after_allocation);
            try std.testing.expect(current == runner.model_accounting.?.current_operations);
            try std.testing.expectEqualSlices(?*@import("domain/pipeline_data.zig").Value, &before, &runner.envelope.slots);
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

const PublicationGuard = struct {
    const Fault = enum { expire, cancel, deadline, clock };
    allocations: *std.testing.FailingAllocator,
    before: usize,
    fault: Fault,
    checked_after_allocation: bool = false,
    fn now(context: *@import("ports/provider_authorization_lease.zig").Context) error{ClockUnavailable}!u64 {
        const self: *@This() = @ptrCast(@alignCast(context));
        if (self.allocations.allocated_bytes > self.before) {
            self.checked_after_allocation = true;
            if (self.fault == .expire) return 1001;
            if (self.fault == .clock) return error.ClockUnavailable;
        }
        return 1;
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const @This() = @ptrCast(@alignCast(context.?));
        if (!self.checked_after_allocation) return .active;
        return switch (self.fault) {
            .cancel => .cancelled,
            .deadline => .deadline_exhausted,
            .expire, .clock => .active,
        };
    }
};

const FaultyOperationLifecycle = struct {
    const Fault = enum { missing, undeclared_write, injected_evidence, no_invalidation, deadline, operation, ordinal, revision, ledger_revision, stale_ledger, assignment, terminal, failed_outcome, cancel, expire };
    advance: operation_lifecycle_workflow.Advance,
    fault: Fault,
    clock: *@import("provider_authorization_test_fixture.zig").TestClock,
    cancelled: bool = false,
    calls: usize = 0,
    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        self.calls += 1;
        var candidate = try operation_lifecycle_workflow.Advance.invoke(&self.advance, input);
        const transition = &candidate.delta.runner_accounting_transition.?.advance_provider_operation;
        switch (self.fault) {
            .missing => candidate.delta.runner_accounting_transition = null,
            .no_invalidation => candidate.delta.data_invalidations = .initEmpty(),
            .deadline => transition.command.invoke.deadline_monotonic_ms += 1,
            .operation => transition.operation_id.kind = .input_token_count,
            .ordinal => transition.operation_id.model_attempt_ordinal.value += 1,
            .revision => transition.expected_operation_revision.?.value += 1,
            .ledger_revision => transition.expected_revision.value += 1,
            .stale_ledger => transition.expected_ledger = lifecycle.apply(input.step.provider_operation.?.ledger, input.step.provider_operation.?.authority, transition.*) catch return error.OperationExecutionFailed,
            .assignment => {
                const request = (try requests.readCurrent(&input.step.data, requests.prepared_schema)).prepared().?;
                transition.command = .{ .assign_inference = .{ .binding_id = request.binding_id, .model_visible_input_id = request.model_visible_input_id } };
            },
            .terminal => transition.command = .{ .terminate = .{ .cancelled = .not_sent } },
            .failed_outcome => candidate.outcome = .failed,
            .cancel => self.cancelled = true,
            .expire => self.clock.now_ms = 1001,
            .undeclared_write, .injected_evidence => {
                const key: pipeline.DataKey = if (self.fault == .undeclared_write) .raw_engine_config else .invoked_provider_operation;
                const descriptor = if (self.fault == .undeclared_write) values.schema(.raw_engine_config, bool, 1, 1) else values.schema(.invoked_provider_operation, bool, 1, 1);
                candidate.delta.data_writes[@intFromEnum(key)] = values.create(std.testing.allocator, descriptor, bool, true) catch return error.OperationExecutionFailed;
            },
        }
        return candidate;
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const @This() = @ptrCast(@alignCast(context.?));
        return if (self.cancelled) .cancelled else .active;
    }
};

fn operationLifecycleYaml(fixture: *Fixture, kind: []const u8) ![]const u8 {
    const source = try requestLifecycleYaml(fixture, kind);
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .invoked_provider_operation, .provider_authorization_result };
    const replaced = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, "{ok: observe, failed: end.failed}", "{ok: advance-operation, failed: end.failed}");
    return std.fmt.allocPrint(fixture.arena.allocator(), "{s}\n  advance-operation: {{ use: advance-provider-operation-lifecycle, with: {{transition: invoked}}, on: {{ok: observe, failed: end.failed}} }}\n", .{replaced});
}

fn prepareInvocable(runner: *runner_module.Runner) !void {
    try prepareAuthorized(runner);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).outcome);
}

fn invokedOperation(runner: *const runner_module.Runner) !*const lifecycle.InvokedOperation {
    return values.read(&.{ .slots = runner.envelope.slots }, attempt_values.invoked_schema, lifecycle.InvokedOperation);
}

test "native YAML invokes one model call and retains unparsed output and actual usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try invocationYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    const observed = try invocationResult(&runner);
    try std.testing.expect(observed.operationId().eql((try invokedOperation(&runner)).operation().id));
    const output = observed.outcome().?.observation.completed.raw_result.complete;
    try std.testing.expectEqualStrings("not JSON; still untrusted", output.content.bytes);
    const request = try currentRequest(&runner);
    try std.testing.expect(request.id() == output.request_id);
    try std.testing.expect(request.prepared().?.binding_id.eql(output.binding_id));
    try std.testing.expectEqualStrings("origin", output.request_id.model_operation_id.workflow_step_id.bytes);
    try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    try std.testing.expectEqual(.invoked, (try requestLedger(&runner)).record(request.id()).?.status);
    try std.testing.expectEqual(.invoked, std.meta.activeTag(runner.model_accounting.?.current_operations.record(observed.operationId()).?.state));
    // Even removing the result cannot resurrect the consumed authorization.
    values.destroy(runner.envelope.slots[@intFromEnum(model_invocation.schema.key)].?);
    runner.envelope.slots[@intFromEnum(model_invocation.schema.key)] = null;
    try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
}

test "YAML invocation preserves every stopped outcome and charges its actual usage" {
    inline for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try invocationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .stopped = .{ .reason = reason, .input_tokens = 8, .output_tokens = 3 } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        try std.testing.expectEqual(reason, (try invocationResult(&runner)).outcome().?.observation.completed.raw_result.stopped.reason);
        try std.testing.expectEqual(@as(u128, 11), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    }
}

test "YAML invocation preserves failures and blocks further calls when usage is unavailable" {
    inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try invocationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .failed = .{ .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        const failure = (try invocationResult(&runner)).outcome().?.observation.failed;
        try std.testing.expectEqualDeep(provider.ProviderFailure{ .operation_id = (try invokedOperation(&runner)).operation().id, .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery }, failure);
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
        if (delivery == .not_sent) {
            try std.testing.expectEqual(.available, runner.tokenLedger().status());
        } else {
            try std.testing.expectEqual(.usage_unavailable, runner.tokenLedger().status());
            try std.testing.expectEqual(error.ProviderTokenUsageUnavailable, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected.token_budget);
        }
        try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
        try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
    }
}

test "YAML invocation accounts exact budget exhaustion and overshoot before blocking subsequent calls" {
    for ([_]u64{ 0, 1 }) |overshoot| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try invocationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try prepareInvocable(&runner);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = graph.authority.total_model_token_budget.value - 2, .output_tokens = 2 + overshoot } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        const first = runner.bindings().invokeStep(.{ .bytes = "call" });
        if (overshoot == 0) {
            try std.testing.expectEqual(.ok, first.outcome);
            try std.testing.expectEqual(.exhausted, runner.tokenLedger().status());
        } else {
            try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, first.rejected.token_budget);
            try std.testing.expectEqual(.exceeded, runner.tokenLedger().status());
            try std.testing.expect(runner.envelope.slots[@intFromEnum(model_invocation.schema.key)] == null);
        }
        try std.testing.expectEqual(@as(u128, graph.authority.total_model_token_budget.value) + overshoot, runner.tokenLedger().committed());
        try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected.token_budget);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    }
}

test "YAML invocation cancellation stays distinct without fabricated usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try invocationYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = .cancelled;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.cancelled, harness.run());
    try std.testing.expectEqual(.cancelled, std.meta.activeTag((try invocationResult(&runner)).outcome().?.*));
    try std.testing.expectEqual(.usage_unavailable, runner.tokenLedger().status());
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

test "YAML call rejects missing dependencies controls and policy permission" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try invocationYaml(&fixture);
    for ([_][2][]const u8{
        .{ "ok: advance-operation", "ok: call" },
        .{ "use: build-model-request", "use: core.noop" },
        .{ "use: invoke-model, on:", "use: invoke-model, with: {slot: selected}, on:" },
        .{ "use: invoke-model, on:", "use: invoke-model, with: {timeout-ms: 1000}, on:" },
        .{ "use: invoke-model, on:", "use: invoke-model, with: {retry-limit: 1}, on:" },
        .{ "use: invoke-model, on:", "use: invoke-model, with: {input-bytes: 1000}, on:" },
        .{ "use: invoke-model, on:", "use: invoke-model, with: {response-mode: prompt-only}, on:" },
        .{ "policy: core.model-inference@1", "policy: core.model-authorization@1" },
        .{ "use: invoke-model", "use: hidden-invoke-model" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, source, invalid));
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(invalid));
    }
}

fn invocationYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try operationLifecycleYaml(fixture, "inference");
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .provider_invocation_result };
    var replaced = try std.mem.replaceOwned(u8, allocator, source, "core.model-authorization@1", "core.model-inference@1");
    replaced = try std.mem.replaceOwned(u8, allocator, replaced, "ok: observe", "ok: call");
    return std.fmt.allocPrint(allocator, "{s}\n  call: {{ use: invoke-model, on: {{ok: observe, failed: end.failed, cancelled: end.cancelled}} }}\n", .{replaced});
}

test "workflow result retains the exact budget rejection and does not follow a YAML failure edge" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try invocationYaml(&fixture);
    const yaml_bytes = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, "ok: observe, failed: end.failed, cancelled: end.cancelled", "ok: observe, failed: observe, cancelled: end.cancelled");
    const graph = try fixture.compile(yaml_bytes);
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = graph.authority.total_model_token_budget.value, .output_tokens = 1 } };
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.result();
    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, outcome.execution_rejected.token_budget);
    try std.testing.expectEqualStrings("WorkflowTokenBudgetExceeded", outcome.execution_rejected.diagnostic());
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    try std.testing.expectEqual(@as(u128, graph.authority.total_model_token_budget.value) + 1, runner.tokenLedger().committed());
}

test "YAML call guards cancellation expiry wrong kinds and absent adapters before effects" {
    for (0..5) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        var source = try invocationYaml(&fixture);
        if (fault == 3) source = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, "kind: inference", "kind: input-token-count");
        const graph = try fixture.compile(source);
        {
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            try prepareInvocable(&runner);
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
            var fake = invocationProvider(&runner, std.testing.allocator);
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            switch (fault) {
                0 => fixture.clock.now_ms = 1001,
                1 => runner.runtime = .{ .status_fn = alwaysCancelled },
                2 => fixture.clock.unavailable = true,
                3 => {},
                4 => fixture.native.invoke_model.action = null,
                else => unreachable,
            }
            const outcome = runner.bindings().invokeStep(.{ .bytes = "call" });
            switch (fault) {
                0 => try std.testing.expectEqual(.deadline_exhausted, outcome.rejected),
                1 => try std.testing.expectEqual(.cancelled, outcome.rejected),
                2, 3 => try std.testing.expectEqual(.authority, outcome.rejected),
                4 => {
                    try std.testing.expectEqual(.failed, outcome.outcome);
                    try std.testing.expectEqual(.authorization_denied, (try invocationResult(&runner)).outcome().?.observation.failed.cause);
                },
                else => unreachable,
            }
            try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
            try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
            try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        }
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

test "post-call cancellation deadlines malformed associations and usage fail without replay" {
    inline for ([_]InvocationSpy.Fault{ .cancelled, .expired, .operation, .binding, .usage }) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try invocationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        var spy: InvocationSpy = .{ .fake = &fake, .clock = &fixture.clock, .fault = fault };
        runner.runtime = .{ .context = &spy, .status_fn = InvocationSpy.status };
        fake.authorization_leases.runtime = runner.runtime;
        fixture.native.invoke_model.action = .{ .provider = spy.port() };
        var harness: Harness = .{ .runner = &runner };
        const outcome = harness.result();
        switch (fault) {
            .cancelled => try std.testing.expectEqual(.cancelled, outcome.execution_rejected),
            .expired => try std.testing.expectEqual(.deadline_exhausted, outcome.execution_rejected),
            .operation, .binding, .usage => try std.testing.expectEqual(.authority, outcome.execution_rejected),
            .utf8, .cancel_before_lease => unreachable, // Covered by response-validation and completion tests.
        }
        try std.testing.expectEqual(@as(u128, if (fault == .cancelled or fault == .expired) 7 else 0), runner.tokenLedger().committed());
        if (fault == .operation or fault == .binding or fault == .usage) try std.testing.expectEqual(.usage_unavailable, runner.tokenLedger().status());
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(model_invocation.schema.key)] == null);
    }
}

test "rejected invocation deltas retain actual usage without publishing candidate data" {
    for ([_]bool{ true, false }) |wrong_outcome| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try invocationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var spy: InvocationDeltaSpy = .{ .inner = &fixture.native.invoke_model, .wrong_outcome = wrong_outcome };
        for (&fixture.entries) |*entry| if (entry.contract.side_effect == .model_call) {
            entry.binding = bindings.bind(InvocationDeltaSpy, &spy, InvocationDeltaSpy.invoke);
        };
        try prepareInvocable(&runner);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
        const outcome = runner.bindings().invokeStep(.{ .bytes = "call" });
        try std.testing.expectEqual(.authority, outcome.rejected);
        try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(model_invocation.schema.key)] == null);
    }
}

test "YAML invocation owners and token usage are isolated between executions" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try invocationYaml(&fixture));
    var first = fixture.runner(graph, std.testing.allocator);
    var first_live = true;
    defer if (first_live) first.deinit();
    var fake_first = invocationProvider(&first, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake_first.interface() };
    var one: Harness = .{ .runner = &first };
    try std.testing.expectEqual(.ok, one.run());
    const first_result = try invocationResult(&first);
    const retained = first.envelope.slots[@intFromEnum(model_invocation.schema.key)].?;
    first.envelope.slots[@intFromEnum(model_invocation.schema.key)] = null;
    defer values.destroy(retained);
    const first_id = first_result.operationId();
    first.deinit();
    first_live = false;
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    try std.testing.expectEqual(@as(u128, 0), second.tokenLedger().committed());
    var fake_second = invocationProvider(&second, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake_second.interface() };
    var two: Harness = .{ .runner = &second };
    try std.testing.expectEqual(.ok, two.run());
    const second_id = (try invocationResult(&second)).operationId();
    try std.testing.expect(!first_id.eql(second_id));
    try std.testing.expect(!first_id.model_request_id.stage_run_epoch_id.eql(second_id.model_request_id.stage_run_epoch_id));
    try std.testing.expectEqualStrings("not JSON; still untrusted", first_result.outcome().?.observation.completed.raw_result.complete.content.bytes);
    try std.testing.expectEqual(@as(u128, 7), second.tokenLedger().committed());
}

test "YAML invocation allocation failures release pending responses and consumed or unused leases" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try invocationYaml(&fixture));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, invocationAllocationCase, .{ &fixture, graph });
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
}

fn invocationAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    try std.testing.expect(fake.effect_count <= 1);
    if (outcome == .failed) return error.OutOfMemory;
    try std.testing.expectEqual(.ok, outcome);
    try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
}

const InvocationSpy = struct {
    const Fault = enum { cancelled, expired, operation, binding, usage, utf8, cancel_before_lease };
    fake: *fake_provider.FakeLLMProvider,
    clock: *@import("provider_authorization_test_fixture.zig").TestClock,
    fault: Fault,
    cancelled: bool = false,
    calls: usize = 0,
    fn port(self: *InvocationSpy) @import("ports/llm_provider_interface.zig").LLMProviderInterface {
        return .{ .context = @ptrCast(self), .vtable = &.{ .invoke = invoke, .count_input_tokens = count } };
    }
    fn invoke(context: *@import("ports/llm_provider_interface.zig").Context, selected: *const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding, request: *const provider.IdentifiedProviderNeutralModelRequest, reference: *const provider.ValidatedProviderAuthorizationLeaseRef, invoked: *const provider.InvokedProviderOperation) @import("ports/llm_provider_interface.zig").Error!provider.ProviderInvocationObservation {
        const self: *InvocationSpy = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.fault == .cancel_before_lease) return error.Cancelled;
        var response = try self.fake.interface().invoke(selected, request, reference, invoked);
        errdefer response.deinit();
        switch (self.fault) {
            .cancel_before_lease => unreachable,
            .cancelled => self.cancelled = true,
            .expired => self.clock.now_ms = invoked.deadline_monotonic_ms,
            .operation => response.completed.operation_id.kind = .input_token_count,
            .binding => response.completed.raw_result.complete.binding_id.operation_id.workflow_version += 1,
            .usage => response.completed.raw_result.complete.usage.total_tokens += 1,
            .utf8 => {
                const bytes = try self.fake.allocator.dupe(u8, "\xff");
                response.completed.raw_result.complete.content.deinit();
                response.completed.raw_result.complete.content = .{ .allocator = self.fake.allocator, .bytes = bytes };
            },
        }
        return response;
    }
    fn count(context: *@import("ports/llm_provider_interface.zig").Context, selected: *const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding, request: *const provider.IdentifiedProviderNeutralModelRequest, reference: *const provider.ValidatedProviderAuthorizationLeaseRef, invoked: *const provider.InvokedProviderOperation) @import("ports/llm_provider_interface.zig").Error!provider.ProviderTokenCountObservation {
        const self: *InvocationSpy = @ptrCast(@alignCast(context));
        return self.fake.interface().countInputTokens(selected, request, reference, invoked);
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *InvocationSpy = @ptrCast(@alignCast(context.?));
        return if (self.cancelled) .cancelled else .active;
    }
};

const InvocationDeltaSpy = struct {
    inner: *model_invocation.Invoke,
    wrong_outcome: bool,
    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var candidate = try model_invocation.Invoke.invoke(self.inner, input);
        if (self.wrong_outcome) candidate.outcome = .failed else candidate.delta.data_invalidations.insert(.prepared_model_request);
        return candidate;
    }
};

fn invocationResult(runner: *const runner_module.Runner) !*const invocation_result.Result {
    return values.read(&.{ .slots = runner.envelope.slots }, model_invocation.schema, invocation_result.Result);
}

fn observationYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try invocationYaml(fixture);
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .provider_invocation_validation_result };
    const routed = try std.mem.replaceOwned(u8, allocator, source, "use: invoke-model, on: {ok: observe, failed: end.failed, cancelled: end.cancelled}", "use: invoke-model, on: {ok: validate-response, failed: validate-response, cancelled: validate-response}");
    return std.fmt.allocPrint(allocator, "{s}\n  validate-response: {{ use: validate-provider-invocation-observation, on: {{ok: observe, failed: end.failed, cancelled: end.cancelled}} }}\n", .{routed});
}

fn observationResult(runner: *const runner_module.Runner) !*const observation_workflow.Result {
    return values.read(&.{ .slots = runner.envelope.slots }, observation_workflow.schema, observation_workflow.Result);
}

fn envelopeYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try observationYaml(fixture);
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .model_envelope_result };
    const routed = try std.mem.replaceOwned(u8, allocator, source, "use: validate-provider-invocation-observation, on: {ok: observe, failed: end.failed, cancelled: end.cancelled}", "use: validate-provider-invocation-observation, on: {ok: decode, failed: decode, cancelled: decode}");
    return std.fmt.allocPrint(allocator, "{s}\n  decode: {{ use: decode-model-envelope, on: {{ok: observe, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled}} }}\n", .{routed});
}

fn envelopeResult(runner: *const runner_module.Runner) !*const envelope_workflow.Result {
    return values.read(&.{ .slots = runner.envelope.slots }, envelope_workflow.schema, envelope_workflow.Result);
}

fn payloadYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try envelopeYaml(fixture);
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .model_payload_schema_result };
    const routed = try std.mem.replaceOwned(u8, allocator, source, "use: decode-model-envelope, on: {ok: observe, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled}", "use: decode-model-envelope, on: {ok: validate-payload, invalid: validate-payload, failed: validate-payload, cancelled: validate-payload}");
    return std.fmt.allocPrint(allocator, "{s}\n  validate-payload: {{ use: validate-model-payload-schema, on: {{ok: observe, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled}} }}\n", .{routed});
}

fn responseAdmissionYaml(fixture: *Fixture, source: []const u8, consolidated: bool) ![]const u8 {
    if (!consolidated) return source;
    const allocator = fixture.arena.allocator();
    const removed = try std.mem.replaceOwned(u8, allocator, source, "  decode: { use: decode-model-envelope, on: {ok: validate-payload, invalid: validate-payload, failed: validate-payload, cancelled: validate-payload} }\n", "");
    try std.testing.expect(removed.len < source.len);
    const routed = try std.mem.replaceOwned(u8, allocator, removed, ": decode", ": validate-payload");
    return std.mem.replaceOwned(u8, allocator, routed, "use: validate-model-payload-schema,", "use: admit-model-response,");
}

test "response admission preserves selected requests captured authority and serialized request sizes" {
    const packet = @import("domain/model_input_packet.zig");
    const selected_schema = "{\"$defs\":{\"answer\":" ++ schema_bytes ++ ",\"replacement\":{\"type\":\"object\",\"properties\":{\"approved\":{\"type\":\"boolean\"}},\"required\":[\"approved\"],\"additionalProperties\":false}},\"$ref\":\"#/$defs/answer\"}";
    for ([_]bool{ false, true }) |selected| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const allocator = fixture.arena.allocator();
        const base = try payloadYaml(&fixture);
        const selection = if (selected) try std.mem.replaceOwned(u8, allocator, base, "input: input }", "result-selection: input }") else base;
        const source = if (selected) try std.mem.replaceOwned(u8, allocator, selection, ", input: input.txt", "") else selection;
        const detailed = try fixture.compileWithAssets(source, if (selected) selected_schema else schema_bytes, !selected);
        const combined = try fixture.compileWithAssets(try responseAdmissionYaml(&fixture, source, true), if (selected) selected_schema else schema_bytes, !selected);
        try std.testing.expectEqual(detailed.authority.steps.len - 1, combined.authority.steps.len);
        var first = fixture.runner(detailed, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(combined, std.testing.allocator);
        defer second.deinit();
        for ([_]*runner_module.Runner{ &first, &second }) |runner| {
            if (selected) {
                const input = try packet.create(std.testing.allocator, "{\"selected\":\"loan\"}", .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = "reference" }, .chunk_id = .{ .bytes = "chunk" } } }, .initial_generation, .{ .bytes = "replacement" });
                runner.envelope.slots[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, input);
            }
            var fake = invocationProvider(runner, std.testing.allocator);
            fake.invocation_plan.complete.content = if (selected) "{\"approved\":true}" else "{\"answer\":\"valid\"}";
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            var harness: Harness = .{ .runner = runner };
            try std.testing.expectEqual(.ok, harness.run());
            try expectResponseAccounting(runner, &fake, 7);
            const payload = try payloadResult(runner);
            try std.testing.expect(payload.source() == try envelopeResult(runner));
            try std.testing.expect(payload.outcome().valid.candidate() == payload.source().outcome().decoded);
        }
        const first_origin = first.envelope.origins[@intFromEnum(payload_workflow.schema.key)].?;
        const second_origin = second.envelope.origins[@intFromEnum(payload_workflow.schema.key)].?;
        try std.testing.expectEqualDeep(first_origin.lineage, second_origin.lineage);
        try std.testing.expect(first_origin.lineage_conflicts.count() == 0 and second_origin.lineage_conflicts.count() == 0);
        try std.testing.expectEqual(second_origin.generation, second.envelope.origins[@intFromEnum(envelope_workflow.schema.key)].?.generation);
        const before = (try currentRequest(&first)).prepared().?;
        const after = (try currentRequest(&second)).prepared().?;
        try std.testing.expectEqualDeep(before.content, after.content);
        try std.testing.expectEqualStrings(before.response_schema.modelBytes(), after.response_schema.modelBytes());
        try std.testing.expectEqualDeep(before.model_operation_id, after.model_operation_id);
        const encode = @import("adapters/provider/bedrock_request.zig").encode;
        const before_wire = try encode(allocator, before, .inference);
        const after_wire = try encode(allocator, after, .inference);
        try std.testing.expectEqualStrings(before_wire, after_wire);
        for ([_][]const u8{ before_wire, after_wire }, [_][]const u8{ "before", "after" }) |wire, label| {
            const path = try std.fmt.allocPrint(allocator, ".zig-cache/chunk13-admission-{s}-{s}.json", .{ if (selected) "selected" else "root", label });
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = wire });
        }
    }
}

test "response admission permits only the exact pure output pair" {
    const contract = @import("domain/workflow_model_invocation.zig");
    try std.testing.expect(contract.validContract(payload_workflow.Admit.contract, &.{}));
    for (0..8) |variant| {
        var invalid = payload_workflow.Admit.contract;
        switch (variant) {
            0 => invalid.produces = &.{ .model_envelope_result, .provider_invocation_validation_result },
            1 => invalid.produces = &.{ .model_envelope_result, .model_payload_schema_result, .provider_invocation_result },
            2 => invalid.requires = &.{ .model_request_identity_ledger, .prepared_model_request },
            3 => invalid.optional = &.{.model_input_packet},
            4 => invalid.replaces = &.{.model_envelope_result},
            5 => invalid.runner_accounting = .increment_model_attempt,
            6 => invalid.parameters = requests.Assign.contract.parameters,
            7 => invalid.retry_limit = @import("application/model_attempt_workflow.zig").Advance.contract.retry_limit,
            else => unreachable,
        }
        try std.testing.expect(!contract.validContract(invalid, &.{}));
    }
    try std.testing.expect(!contract.validContract(payload_workflow.Admit.contract, &.{"model-provider"}));
}

test "response admission rejects missing and foreign observation authority without partial publication" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), true));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    for ([_]*runner_module.Runner{ &first, &second }) |runner| {
        var fake = invocationProvider(runner, std.testing.allocator);
        fake.invocation_plan.complete.content = "{\"answer\":\"valid\"}";
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try prepareInvocable(runner);
        for ([_][]const u8{ "advance-operation", "call", "validate-response" }) |step|
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    }
    const key = @intFromEnum(observation_workflow.schema.key);
    const original = first.envelope.slots[key];
    first.envelope.slots[key] = null;
    try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "validate-payload" }).rejected);
    first.envelope.slots[key] = second.envelope.slots[key];
    try std.testing.expectEqualDeep(execution.Rejection{ .operation_failed = error.OperationExecutionFailed }, first.bindings().invokeStep(.{ .bytes = "validate-payload" }).rejected);
    first.envelope.slots[key] = original;
    for (payload_workflow.Admit.contract.produces) |produced|
        try std.testing.expect(first.envelope.slots[@intFromEnum(produced)] == null);
    try std.testing.expectEqual(@as(u128, 7), first.tokenLedger().committed());
    try std.testing.expectEqual(.ok, first.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
}

fn payloadResult(runner: *const runner_module.Runner) !*const payload_workflow.Result {
    return values.read(&.{ .slots = runner.envelope.slots }, payload_workflow.schema, payload_workflow.Result);
}

fn completionYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try payloadYaml(fixture);
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .model_payload_schema_result };
    const routed = try std.mem.replaceOwned(u8, allocator, source, "use: validate-provider-invocation-observation, on: {ok: decode, failed: decode, cancelled: decode}", "use: validate-provider-invocation-observation, on: {ok: complete-operation, failed: complete-operation, cancelled: complete-operation}");
    return std.fmt.allocPrint(allocator, "{s}\n  complete-operation: {{ use: complete-provider-operation, on: {{ok: decode, failed: decode, cancelled: decode}} }}\n", .{routed});
}

fn completedOperation(runner: *const runner_module.Runner) !*const lifecycle.TerminalOperation {
    return values.read(&.{ .slots = runner.envelope.slots }, attempt_values.terminal_schema, lifecycle.TerminalOperation);
}

fn prepareCompletable(runner: *runner_module.Runner) !void {
    try prepareInvocable(runner);
    for ([_][]const u8{ "advance-operation", "call", "validate-response" }) |step| {
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    }
}

fn requestCompletionYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    const source = try completionYaml(fixture);
    fixture.observer.expected_request_status = .terminal;
    const routed = try std.mem.replaceOwned(u8, allocator, source, "use: validate-model-payload-schema, on: {ok: observe, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled}", "use: validate-model-payload-schema, on: {ok: close-request, invalid: close-request, failed: close-request, cancelled: close-request}");
    return std.fmt.allocPrint(allocator, "{s}\n  close-request: {{ use: complete-model-request, on: {{ok: observe, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled}} }}\n", .{routed});
}

fn prepareRequestClosure(runner: *runner_module.Runner, outcome: workflow.OutcomeTag) !void {
    try prepareInvocable(runner);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
    const provider_outcome: workflow.OutcomeTag = if (outcome == .invalid) .ok else outcome;
    for ([_][]const u8{ "call", "validate-response", "complete-operation" }) |step|
        try std.testing.expectEqual(provider_outcome, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    _ = runner.bindings().invokeStep(.{ .bytes = "decode" });
    try std.testing.expectEqual(outcome, runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
}

const malformed_protocol_items = "{\"items\":[{\"name\":\"first\",\"text\":\"one\"},{\"name\":\"second\",\"text\":\"two\",\"name\":\"third\",\"text\":\"three\"}]}";
const malformed_protocol_record = "{\"result\":{\"settings\":{\"state\":\"open\",\"state\":\"closed\"}}}";

test "bounded protocol assignments continue many valid units and stop repeated or alternating failures" {
    const cases = [_]struct { schema: []const u8, valid: []const u8, invalid: []const u8, duplicate: []const u8 }{
        .{ .schema = schema_bytes, .valid = "{\"answer\":\"Preserve all meaning\"}", .invalid = "{\"answer\":42}", .duplicate = "{\"answer\":\"one\",\"answer\":\"two\"}" },
        .{
            .schema = "{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"segments\"],\"properties\":{\"segments\":{\"type\":\"array\",\"maxItems\":8,\"items\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"kind\",\"text\"],\"properties\":{\"kind\":{\"enum\":[\"literal\"]},\"text\":{\"type\":\"string\",\"maxLength\":2000}}}}}}",
            .valid = "{\"segments\":[{\"kind\":\"literal\",\"text\":\"Retain the return deadline\"}]}",
            .invalid = "{\"segments\":[{\"kind\":\"preserved_token\",\"text\":\"Retain the return deadline\"}]}",
            .duplicate = "{\"segments\":[],\"segments\":[]}",
        },
    };
    for (cases) |example| for ([_]bool{ false, true }) |recover| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const a = fixture.arena.allocator();
        var source = try protocolRetryYaml(&fixture);
        for ([_][2][]const u8{
            .{ "ok: origin, failed: end.failed", "ok: select, failed: end.failed" },
            .{ ", input: input.txt", "" },
            .{ ", input: input }", " }" },
            .{ "use: test.observe-request, on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled }", "use: test.observe-request, on: { ok: retire, failed: end.failed, cancelled: end.cancelled }" },
        }) |change| source = try std.mem.replaceOwned(u8, a, source, change[0], change[1]);
        source = try std.fmt.allocPrint(a,
            \\{s}
            \\  select: {{ use: test.select-unit, with: {{retry-limit: 128}}, on: {{ok: origin, failed: end.failed}} }}
            \\  retire: {{ use: retire-model-transport, on: {{ok: select, failed: end.failed}} }}
            \\
        , .{source});
        var owner: ProtocolUnits = .{};
        var entries = fixture.entries ++ [_]operations.Entry{.{
            .contract = .{ .id = "test.select-unit", .kind = .step, .produces = &.{.model_input_packet}, .outcomes = &.{ .ok, .failed }, .side_effect = .none, .parameters = &.{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = 128 }}, .retry_limit = .{ .maximum = 128 } },
            .binding = bindings.bind(ProtocolUnits, &owner, ProtocolUnits.select),
        }};
        fixture.registry.operations = &entries;
        var profiles = core.profiles;
        for (&profiles) |*profile| profile.total_model_token_budget.value = 10000;
        fixture.registry.policies = &profiles;
        const graph = try fixture.compileWithAssets(source, example.schema, false);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try std.testing.expectEqual(.ok, runner.bindings().invokeInvocation().outcome);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "initialize" }).outcome);
        // The collection's capacity is 128; correction is bounded independently
        // after many successful requests through the same compiled call site.
        const successful_units: usize = 16;
        for (0..successful_units + 1) |unit| {
            for ([_][]const u8{ "select", "origin", "validate", "build" }) |step|
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            const request = (try currentRequest(&runner)).id();
            const count: usize = if (unit == successful_units) 3 else 1;
            for (0..count) |attempt_index| {
                if (attempt_index > 0) try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
                const success = unit < successful_units or (recover and attempt_index == 2);
                fake.invocation_plan.complete.content = if (success) example.valid else if (attempt_index == 1) example.invalid else example.duplicate;
                for ([_][]const u8{ "account", "assign-operation", "authorize", "phase" }) |step|
                    try std.testing.expectEqual(@as(workflow.OutcomeTag, if (std.mem.eql(u8, step, "phase") and attempt_index > 0) .more else .ok), runner.bindings().invokeStep(.{ .bytes = step }).outcome);
                if (attempt_index == 0) try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).outcome);
                for ([_][]const u8{ "advance-operation", "call", "validate-response", "complete-operation" }) |step|
                    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
                try std.testing.expectEqual(@as(workflow.OutcomeTag, if (success or attempt_index == 1) .ok else .invalid), runner.bindings().invokeStep(.{ .bytes = "decode" }).outcome);
                try std.testing.expectEqual(@as(workflow.OutcomeTag, if (success) .ok else .invalid), runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
                try std.testing.expect((try currentRequest(&runner)).id() == request);
                if (success) for ([_][]const u8{ "close-request", "observe", "retire" }) |step|
                    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            }
        }
        if (recover) {
            for ([_][]const u8{ "select", "origin", "validate", "build", "account" }) |step|
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        } else {
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
            const exhausted = runner.bindings().invokeStep(.{ .bytes = "account" }).rejected.retry_limit;
            try std.testing.expectEqual(@as(u32, 2), exhausted.limit.value);
            try std.testing.expectEqual(@as(u64, 3), exhausted.completed_executions);
        }
        const observations = try runner.retryObservations(a);
        const account = for (observations) |row| {
            if (std.mem.eql(u8, row.step, "account")) break row;
        } else return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(u64, 0), account.operation_executions);
        try std.testing.expectEqual(@as(usize, successful_units + 1 + @intFromBool(recover)), account.assignments.len);
        for (account.assignments[0..successful_units], 1..) |row, index| {
            try std.testing.expectEqual(index, row.request.value);
            try std.testing.expectEqual(@as(u64, 1), row.completed_executions);
        }
        try std.testing.expectEqual(@as(u64, 3), account.assignments[successful_units].completed_executions);
        try std.testing.expectEqual(@as(usize, successful_units + 3), fake.effect_count);
        try std.testing.expectEqual(@as(u128, (successful_units + 3) * 7), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, successful_units + @intFromBool(recover)), fixture.observer.calls);
    };
}

const ProtocolUnits = struct {
    next: u32 = 0,
    fn select(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        self.next += 1;
        var name: [32]u8 = undefined;
        const unit: identity.ImmutableUnitOwnerId = .{ .reference_global = .{ .reference_state_id = .{ .bytes = "source" }, .unit_slot_id = .{ .bytes = std.fmt.bufPrint(&name, "partition-{d}", .{self.next}) catch return error.OperationExecutionFailed } } };
        const packet = @import("domain/model_input_packet.zig").create(std.testing.allocator, "{}", unit, .initial_generation, null) catch return error.OperationExecutionFailed;
        return requests.publishPacket(std.testing.allocator, packet);
    }
};

fn protocolRetryYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    var source = try requestCompletionYaml(fixture);
    for ([_][2][]const u8{
        .{ "prompt: prompt, result-schema:", "prompt: prompt, protocol-prompt: prompt, result-schema:" },
        .{ "retry-limit: 0", "retry-limit: 2" },
        .{ "ok: close-request, invalid: close-request", "ok: close-request, invalid: retry" },
        .{ "ok: advance-request, failed: end.failed", "ok: phase, failed: end.failed" },
    }) |change| source = try std.mem.replaceOwned(u8, allocator, source, change[0], change[1]);
    return std.fmt.allocPrint(allocator,
        \\{s}
        \\  phase: {{ use: check-model-request-phase, on: {{ok: advance-request, more: advance-operation, failed: end.failed}} }}
        \\  retry: {{ use: build-model-protocol-retry, on: {{ok: account, failed: end.failed}} }}
        \\
    , .{source});
}

fn prepareProtocolAttempt(runner: *runner_module.Runner, retry: bool) !void {
    if (!retry) {
        try std.testing.expectEqual(.ok, runner.bindings().invokeInvocation().outcome);
        for ([_][]const u8{ "initialize", "origin", "validate", "build" }) |step|
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    }
    for ([_][]const u8{ "account", "assign-operation", "authorize" }) |step|
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    try std.testing.expectEqual(@as(workflow.OutcomeTag, if (retry) .more else .ok), runner.bindings().invokeStep(.{ .bytes = "phase" }).outcome);
    if (!retry) try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).outcome);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
}

fn rejectProtocolResponse(runner: *runner_module.Runner, consolidated: bool) !void {
    for ([_][]const u8{ "call", "validate-response", "complete-operation" }) |step|
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    if (!consolidated) try std.testing.expectEqual(.invalid, runner.bindings().invokeStep(.{ .bytes = "decode" }).outcome);
    try std.testing.expectEqual(.invalid, runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
}

test "native repair progress permits independent requests while retaining the global token budget" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    var source = try requestCompletionYaml(&fixture);
    for ([_][2][]const u8{
        .{ "ok: origin, failed: end.failed", "ok: select, failed: end.failed" },
        .{ ", input: input.txt", "" },
        .{ ", input: input }", " }" },
        .{ "use: test.observe-request, on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled }", "use: test.observe-request, with: {retry-limit: 0}, on: { ok: retire, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled }" },
    }) |change| source = try std.mem.replaceOwned(u8, a, source, change[0], change[1]);
    source = try std.fmt.allocPrint(a,
        \\{s}
        \\  select: {{ use: test.authorize-repair, on: {{ok: origin, invalid: end.invalid}} }}
        \\  retire: {{ use: retire-model-transport, on: {{ok: select, failed: end.failed}} }}
        \\
    , .{source});
    var owner: RepairSequence = .{};
    const merger = &fixture.entries[fixture.entries.len - 1];
    merger.contract.outcomes = &.{ .ok, .invalid, .failed, .cancelled };
    merger.contract.parameters = &.{.{ .id = "retry-limit", .kind = .integer, .required = true, .workflow_definition_safe = true, .integer_min = 0, .integer_max = 1 }};
    merger.contract.retry_limit = .{ .maximum = 1, .scope = .repair };
    merger.contract.repair_role = .merge_validate;
    merger.contract.requires = &@import("application/model_candidate_handoff.zig").requires;
    merger.binding = bindings.bind(RepairSequence, &owner, RepairSequence.merge);
    var entries = fixture.entries ++ [_]operations.Entry{.{
        .contract = .{ .id = "test.authorize-repair", .kind = .step, .produces = &.{.model_input_packet}, .outcomes = &.{ .ok, .invalid }, .side_effect = .none, .repair_role = .authorize },
        .binding = bindings.bind(RepairSequence, &owner, RepairSequence.authorize),
    }};
    fixture.registry.operations = &entries;
    var profiles = core.profiles;
    for (&profiles) |*profile| profile.total_model_token_budget.value = 21;
    fixture.registry.policies = &profiles;
    const graph = try fixture.compileWithAssets(source, schema_bytes, false);
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan.complete.content = "{\"answer\":\"repaired\"}";
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    try std.testing.expectEqual(.ok, runner.bindings().invokeInvocation().outcome);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "initialize" }).outcome);
    for (0..3) |index| {
        for ([_][]const u8{ "select", "origin", "validate", "build", "account", "assign-operation", "authorize", "advance-request", "advance-operation", "call", "validate-response", "complete-operation", "decode", "validate-payload", "close-request", "observe" }) |step| {
            const result = runner.bindings().invokeStep(.{ .bytes = step });
            if (result == .rejected) std.debug.print("repair {d} step {s}: {any}\n", .{ index, step, result.rejected });
            try std.testing.expect(result == .outcome);
            try std.testing.expectEqual(.ok, result.outcome);
        }
        const request = try currentRequest(&runner);
        const permit = request.packet().?.repairPermit().?;
        try std.testing.expectEqual(@as(u64, 1), runner.repair_retry.completedAttempts(.{ .bytes = "account" }, permit.key));
        try std.testing.expectEqual(@as(u64, 1), runner.repair_retry.completedAttempts(.{ .bytes = "observe" }, permit.key));
        try std.testing.expectEqual(@as(u32, 1), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(request.id()));
        try std.testing.expectEqual(@as(u128, (index + 1) * 7), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, index + 1), runner.tokenLedger().accounted_operations.items.len);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retire" }).outcome);
    }
    var stopped = false;
    for ([_][]const u8{ "select", "origin", "validate", "build", "account", "assign-operation", "authorize", "advance-request", "advance-operation", "call" }) |step| {
        const result = runner.bindings().invokeStep(.{ .bytes = step });
        if (result == .rejected) {
            try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, result.rejected.token_budget);
            stopped = true;
            break;
        }
        try std.testing.expectEqual(.ok, result.outcome);
    }
    try std.testing.expect(stopped);
    try std.testing.expectEqual(@as(usize, 3), owner.merges);
    try std.testing.expectEqual(@as(usize, 3), fake.effect_count);
    try std.testing.expectEqual(@as(u128, 21), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 3), runner.tokenLedger().revision().value);
}

const RepairSequence = struct {
    selected: u8 = 0,
    merges: usize = 0,

    fn authorize(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        self.selected += 1;
        const authorization: [64]u8 = @splat('a' + self.selected);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(&authorization, &digest, .{});
        const permit: @import("domain/workflow_retry.zig").Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(self.selected), .family = @splat(2) }, .authorization = digest, .revision = self.selected, .maximum_targets = 4 };
        const unit: identity.ImmutableUnitOwnerId = .{ .reference_chunk = .{ .reference_state_id = .{ .bytes = "repair-state" }, .chunk_id = .{ .bytes = "repair-chunk" } } };
        const packet = @import("domain/model_input_packet.zig").createRepair(std.testing.allocator, "{}", unit, .{ .atomic_repair = .{ .bytes = &authorization } }, null, permit, null) catch return error.OperationExecutionFailed;
        var result = try requests.publishPacket(std.testing.allocator, packet);
        result.delta.repair_transition = .{ .authorized = permit };
        return result;
    }

    fn merge(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        _ = try @import("application/model_candidate_handoff.zig").read(&input.step.data);
        const permit = input.step.repair_permit orelse return error.OperationExecutionFailed;
        context.?.merges += 1;
        return .{ .outcome = .ok, .delta = .{ .repair_transition = .{ .merged_validated = .{ .permit = permit, .revision_after = permit.revision + 1, .result = .resolved } } } };
    }
};

test "dependent reviews retain parent allowances through initial protocol correction and global accounting" {
    for ([_]bool{ false, true }) |recurring| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const a = fixture.arena.allocator();
        var source = try protocolRetryYaml(&fixture);
        source = try std.mem.replaceOwned(u8, a, source, "retry-limit: 2", "retry-limit: 1");
        source = try std.mem.replaceOwned(u8, a, source, "use: test.observe-request, on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled }", "use: test.observe-request, on: { ok: retire, failed: end.failed, cancelled: end.cancelled }");
        source = try std.fmt.allocPrint(a,
            \\{s}
            \\  retire: {{ use: retire-model-request, on: {{ok: select, failed: end.failed}} }}
            \\  select: {{ use: test.authorize-dependent, on: {{ok: merge}} }}
            \\  merge: {{ use: test.merge-dependent, on: {{ok: origin}} }}
            \\
        , .{source});
        var owner: DependentReviewSequence = .{};
        const observer = &fixture.entries[fixture.entries.len - 1];
        observer.contract.repair_role = .validate;
        observer.binding = bindings.bind(DependentReviewSequence, &owner, DependentReviewSequence.observe);
        var entries = fixture.entries ++ [_]operations.Entry{
            .{ .contract = .{ .id = "test.authorize-dependent", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none, .repair_role = .authorize }, .binding = bindings.bind(DependentReviewSequence, &owner, DependentReviewSequence.authorize) },
            .{ .contract = .{ .id = "test.merge-dependent", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none, .repair_role = .merge }, .binding = bindings.bind(DependentReviewSequence, &owner, DependentReviewSequence.merge) },
        };
        fixture.registry.operations = &entries;
        var profiles = core.profiles;
        for (&profiles) |*profile| profile.total_model_token_budget.value = if (recurring) 1000 else 28;
        fixture.registry.policies = &profiles;
        const graph = try fixture.compile(source);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        fake.invocation_plan.complete.content = "{";
        try prepareProtocolAttempt(&runner, false);
        const initial_id = (try currentRequest(&runner)).id();
        try rejectProtocolResponse(&runner, false);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
        try prepareProtocolAttempt(&runner, true);
        try std.testing.expect((try currentRequest(&runner)).id() == initial_id);
        fake.invocation_plan.complete.content = "{\"answer\":\"valid\"}";
        for ([_][]const u8{ "call", "validate-response", "complete-operation", "decode", "validate-payload", "close-request", "observe", "retire" }) |step|
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        try std.testing.expectEqual(@as(u128, 14), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, 0), owner.resolved);
        if (recurring) {
            for ([_][]const u8{ "select", "merge", "origin", "validate", "build" }) |step|
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            const parent = runner.repair_retry.currentDependentPermit().?;
            const request = (try currentRequest(&runner)).id();
            fake.invocation_plan.complete.content = "{";
            for (0..2) |index| {
                if (index == 0) {
                    for ([_][]const u8{ "account", "assign-operation", "authorize", "phase", "advance-request", "advance-operation" }) |step|
                        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
                } else try prepareProtocolAttempt(&runner, true);
                try std.testing.expect((try currentRequest(&runner)).id() == request);
                try rejectProtocolResponse(&runner, false);
                try std.testing.expectEqual(@as(u64, index + 1), runner.repair_retry.completedAssignmentAttempts(.{ .bytes = "account" }, .{ .request = request, .record = (try requestLedger(&runner)).indexOf(request).?, .parent = parent.key }));
                try std.testing.expectEqual(@as(u32, @intCast(index + 1)), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(request));
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
            }
            const exhausted = runner.bindings().invokeStep(.{ .bytes = "account" });
            try std.testing.expectEqual(@as(u64, 2), exhausted.rejected.retry_limit.completed_executions);
            try std.testing.expectEqualDeep(parent, runner.repair_retry.currentDependentPermit().?);
            try std.testing.expectEqual(@as(usize, 0), owner.resolved);
        } else {
            for (0..2) |index| {
                for ([_][]const u8{ "select", "merge", "origin", "validate", "build", "account", "assign-operation", "authorize", "phase", "advance-request", "advance-operation", "call", "validate-response", "complete-operation", "decode", "validate-payload", "close-request" }) |step|
                    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
                const parent = runner.repair_retry.currentDependentPermit().?;
                const request = (try currentRequest(&runner)).id();
                try std.testing.expect(request.purpose != .atomic_repair);
                try std.testing.expectEqual(@as(u64, 1), runner.repair_retry.completedAssignmentAttempts(.{ .bytes = "account" }, .{ .request = request, .record = (try requestLedger(&runner)).indexOf(request).?, .parent = parent.key }));
                try std.testing.expectEqual(@as(u32, 1), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(request));
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "observe" }).outcome);
                try std.testing.expect(runner.repair_retry.currentPermit() == null);
                try std.testing.expectEqual(@as(usize, index + 1), owner.resolved);
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retire" }).outcome);
            }
            var stopped = false;
            for ([_][]const u8{ "select", "merge", "origin", "validate", "build", "account", "assign-operation", "authorize", "phase", "advance-request", "advance-operation", "call" }) |step| {
                const result = runner.bindings().invokeStep(.{ .bytes = step });
                if (result == .rejected) {
                    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, result.rejected.token_budget);
                    stopped = true;
                    break;
                }
                try std.testing.expectEqual(.ok, result.outcome);
            }
            try std.testing.expect(stopped);
            try std.testing.expectEqual(@as(usize, 2), owner.resolved);
        }
        try std.testing.expectEqual(@as(usize, 4), fake.effect_count);
        try std.testing.expectEqual(@as(u128, 28), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 4), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 4), runner.tokenLedger().accounted_operations.items.len);
    }
}

const DependentReviewSequence = struct {
    selected: u8 = 0,
    resolved: usize = 0,

    fn authorize(context: ?*@This(), _: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        self.selected += 1;
        const permit: @import("domain/workflow_retry.zig").Permit = .{ .key = .{ .scope = @splat(1), .target = @splat(self.selected), .family = @splat(2) }, .authorization = @splat(self.selected), .revision = self.selected, .maximum_targets = 3 };
        return .{ .outcome = .ok, .delta = .{ .repair_transition = .{ .authorized = permit } } };
    }

    fn merge(_: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const permit = input.step.repair_permit orelse return error.OperationExecutionFailed;
        return .{ .outcome = .ok, .delta = .{ .repair_transition = .{ .merged = .{ .permit = permit, .revision_after = permit.revision + 1, .validation = .dependent_review } } } };
    }

    fn observe(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        if ((try payload_workflow.readCurrent(&input.step.data)).outcome() != .valid) return error.OperationExecutionFailed;
        const permit = input.step.repair_permit orelse return .{ .outcome = .ok, .delta = .{} };
        context.?.resolved += 1;
        return .{ .outcome = .ok, .delta = .{ .repair_transition = .{ .validated = .{ .permit = permit, .revision = permit.revision + 1, .result = .resolved } } } };
    }
};

test "protocol retries retain only latest repeated or alternating decoder rejection until local exhaustion" {
    for ([_]bool{ false, true }) |consolidated| {
        const sequences = [_][3][]const u8{
            .{ malformed_protocol_items, malformed_protocol_items, malformed_protocol_items },
            .{ malformed_protocol_items, "{", malformed_protocol_record },
        };
        for (sequences) |responses| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try protocolRetryYaml(&fixture), consolidated));
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            var original_id: ?*const identity.ModelRequestId = null;
            for (responses, 0..) |body, index| {
                fake.invocation_plan.complete.content = body;
                try prepareProtocolAttempt(&runner, index != 0);
                const request = try currentRequest(&runner);
                if (index == 0) original_id = request.id();
                try std.testing.expect(request.id() == original_id.?);
                try std.testing.expectEqualStrings(schema_bytes, request.prepared().?.response_schema.bytes());
                try std.testing.expectEqual(@as(u32, @intCast(index + 1)), (try invokedOperation(&runner)).operation().id.model_attempt_ordinal.value);
                try rejectProtocolResponse(&runner, consolidated);
                const diagnostic = (try envelopeResult(&runner)).outcome().protocol_rejected.diagnostic;
                if (body.len > 1) {
                    try std.testing.expectEqual(.DuplicateField, diagnostic.reason);
                    try std.testing.expectEqualStrings(if (std.mem.eql(u8, body, malformed_protocol_items)) "/items/1" else "/result/settings", diagnostic.context.?.path);
                    try std.testing.expect(diagnostic.context.?.first_occurrence.?.byte_offset < diagnostic.context.?.repeated_occurrence.?.byte_offset);
                }
                const retained_diagnostic = try std.json.Stringify.valueAlloc(fixture.arena.allocator(), diagnostic, .{});
                try std.testing.expectEqualStrings(body, (try observationResult(&runner)).outcome().validated.result().complete.content());
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
                const correction = (try currentRequest(&runner)).prepared().?;
                try std.testing.expect(correction.model_request_id == original_id.?);
                try std.testing.expectEqualStrings(schema_bytes, correction.response_schema.bytes());
                // The immutable inputs plus one prompt/diagnostic/response survive;
                // an earlier correction can never become the next assignment.
                try std.testing.expectEqual(@as(usize, 5), correction.content.len);
                try std.testing.expectEqualStrings(prompt_bytes, correction.content[0].guidance);
                try std.testing.expectEqualStrings(input_bytes, correction.content[1].user);
                const repeated = index > 0 and std.mem.eql(u8, responses[index - 1], body);
                const expected_prompt = if (repeated) prompt_bytes ++ "\nThe previous correction still failed this validation." else prompt_bytes;
                try std.testing.expectEqualStrings(expected_prompt, correction.content[2].guidance);
                var guidance = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, correction.content[3].guidance, .{});
                defer guidance.deinit();
                const decoder = guidance.value.object.get("diagnostic").?.object.get("decoder").?;
                try std.testing.expectEqualStrings(retained_diagnostic, try std.json.Stringify.valueAlloc(fixture.arena.allocator(), decoder, .{}));
                var evidence = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, correction.content[4].evidence, .{});
                defer evidence.deinit();
                try std.testing.expectEqual(@as(usize, 1), evidence.value.object.count());
                try std.testing.expectEqualStrings(body, evidence.value.object.get("rejected_response").?.string);
                try std.testing.expectEqual(@as(u128, (index + 1) * 7), runner.tokenLedger().committed());
                try std.testing.expectEqual(@as(u64, @intCast(index + 1)), runner.tokenLedger().revision().value);
            }
            const exhausted = runner.bindings().invokeStep(.{ .bytes = "account" });
            try std.testing.expectEqualStrings("account", exhausted.rejected.retry_limit.operation().bytes);
            try std.testing.expectEqual(@as(u32, 2), exhausted.rejected.retry_limit.limit.value);
            try std.testing.expectEqual(@as(u64, 3), exhausted.rejected.retry_limit.completed_executions);
            try std.testing.expectEqual(@as(u32, 3), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(original_id.?));
            try std.testing.expectEqual(@as(usize, 3), fake.effect_count);
            try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
            try std.testing.expectEqual(@as(u128, 21), runner.tokenLedger().committed());
            try std.testing.expectEqual(.invoked, (try requestLedger(&runner)).record(original_id.?).?.status);
        }
    }
}

test "R31 syntax nesting and sibling loss retain correction scope through recovery or exhaustion" {
    for ([_]bool{ false, true }) |consolidated| {
        for ([_]bool{ false, true }) |recover| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const a = fixture.arena.allocator();
            const support_schema = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited);
            const misplaced = try protocolReview(a, 11, true);
            const cases = [_]struct { schema: []const u8, invalid: []const u8, dropped: []const u8, corrected: []const u8, path: []const u8, reason: payload_validation.Rejection }{
                .{ .schema = support_schema, .invalid = misplaced, .dropped = try protocolReview(a, 1, true), .corrected = try protocolReview(a, 11, false), .path = "/entries/0/source_ids", .reason = .unknown_property },
                .{
                    .schema = "{\"type\":\"object\",\"properties\":{\"groups\":{\"type\":\"array\",\"maxItems\":3,\"items\":{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"maxItems\":3,\"items\":{\"oneOf\":[{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":\"text\"},\"value\":{\"type\":\"string\",\"maxLength\":40}},\"required\":[\"kind\",\"value\"],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":\"flag\"},\"value\":{\"type\":\"boolean\"}},\"required\":[\"kind\",\"value\"],\"additionalProperties\":false}]}}},\"required\":[\"items\"],\"additionalProperties\":false}}},\"required\":[\"groups\"],\"additionalProperties\":false}",
                    .invalid = "{\"groups\":[{\"items\":[{\"value\":\"Keep this text.\"},{\"kind\":\"flag\",\"value\":true}]}]}",
                    .dropped = "{\"groups\":[{\"items\":[{\"value\":\"Keep this text.\"}]}]}",
                    .corrected = "{\"groups\":[{\"items\":[{\"kind\":\"text\",\"value\":\"Keep this text.\"},{\"kind\":\"flag\",\"value\":true}]}]}",
                    .path = "/groups/0/items/0/kind",
                    .reason = .missing_required_property,
                },
            };
            for (cases) |case| {
                const graph = try fixture.compileWithSchema(try responseAdmissionYaml(&fixture, try protocolRetryYaml(&fixture), consolidated), case.schema);
                var runner = fixture.runner(graph, std.testing.allocator);
                defer runner.deinit();
                var fake = invocationProvider(&runner, std.testing.allocator);
                fixture.native.invoke_model.action = .{ .provider = fake.interface() };
                const responses = [_][]const u8{ try std.mem.concat(a, u8, &.{ case.invalid, "}" }), case.invalid, if (recover) case.corrected else case.dropped };
                var original: ?*const identity.ModelRequestId = null;
                for (responses, 0..) |body, index| {
                    fake.invocation_plan.complete.content = body;
                    try prepareProtocolAttempt(&runner, index != 0);
                    const request = try currentRequest(&runner);
                    if (index == 0) original = request.id();
                    try std.testing.expect(request.id() == original.?);
                    try std.testing.expectEqualStrings(case.schema, request.prepared().?.response_schema.bytes());
                    try std.testing.expectEqual(@as(u32, @intCast(index + 1)), (try invokedOperation(&runner)).operation().id.model_attempt_ordinal.value);
                    for ([_][]const u8{ "call", "validate-response", "complete-operation" }) |step|
                        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
                    if (!consolidated) try std.testing.expectEqual(@as(workflow.OutcomeTag, if (index == 0) .invalid else .ok), runner.bindings().invokeStep(.{ .bytes = "decode" }).outcome);
                    const accepted = recover and index == 2;
                    try std.testing.expectEqual(@as(workflow.OutcomeTag, if (accepted) .ok else .invalid), runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
                    if (accepted) {
                        const candidate = (try payloadResult(&runner)).outcome().valid.candidate();
                        try std.testing.expectEqualStrings(case.corrected, candidate.association().result().complete.content());
                        try std.testing.expect(candidate.association().request() == request.prepared().?);
                        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "close-request" }).outcome);
                        try std.testing.expectEqual(.accepted, (try requestLedger(&runner)).record(original.?).?.terminal_reason.?);
                    } else {
                        if (index > 0) {
                            const reason = (try payloadResult(&runner)).outcome().schema_rejected;
                            try std.testing.expectEqual(case.reason, reason.reason);
                            try std.testing.expectEqualStrings(case.path, (try reason.describe(a)).path);
                        } else try std.testing.expect((try envelopeResult(&runner)).outcome() == .protocol_rejected);
                        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
                        const correction = (try currentRequest(&runner)).prepared().?;
                        try std.testing.expect(correction.model_request_id == original.?);
                        try std.testing.expect(correction.response_schema == request.prepared().?.response_schema);
                        try std.testing.expectEqual(@as(usize, 5), correction.content.len);
                        try std.testing.expectEqualStrings(prompt_bytes, correction.content[0].guidance);
                        try std.testing.expectEqualStrings(input_bytes, correction.content[1].user);
                        try std.testing.expectEqual(@as(usize, if (index == 2) 1 else 0), std.mem.count(u8, correction.content[2].guidance, "The previous correction still failed this validation."));
                        const latest = try std.json.parseFromSlice(std.json.Value, a, correction.content[4].evidence, .{});
                        try std.testing.expectEqualStrings(body, latest.value.object.get("rejected_response").?.string);
                    }
                    try std.testing.expectEqual(@as(u128, (index + 1) * 7), runner.tokenLedger().committed());
                    try std.testing.expectEqual(@as(u64, @intCast(index + 1)), runner.tokenLedger().revision().value);
                }
                if (!recover) {
                    const exhausted = runner.bindings().invokeStep(.{ .bytes = "account" }).rejected.retry_limit;
                    try std.testing.expectEqualStrings("account", exhausted.operation().bytes);
                    try std.testing.expectEqual(@as(u32, 2), exhausted.limit.value);
                    try std.testing.expectEqual(@as(u64, 3), exhausted.completed_executions);
                    try std.testing.expectEqual(.invoked, (try requestLedger(&runner)).record(original.?).?.status);
                }
                try std.testing.expectEqual(@as(usize, 3), fake.effect_count);
                try std.testing.expectEqual(@as(usize, 3), runner.tokenLedger().accounted_operations.items.len);
                try std.testing.expectEqual(@as(u32, 3), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(original.?));
                try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
            }
        }
    }
}

test "protocol repetition requires the current correction association and same typed rejection" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try protocolRetryYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var original: ?*const handoff.Request = null;
    var prior: ?*const @import("domain/provider_invocation_validation.zig").Evidence = null;
    // Changed bytes can retain the same defect; moving that defect changes its identity.
    for ([_][]const u8{ "{\"foreign\":true}", "{\"foreign\":false}", "{\"another\":false}" }, 0..) |body, index| {
        fake.invocation_plan.complete.content = body;
        try prepareProtocolAttempt(&runner, index != 0);
        const request = try currentRequest(&runner);
        if (index == 0) original = request;
        for ([_][]const u8{ "call", "validate-response", "complete-operation", "decode" }) |step|
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        try std.testing.expectEqual(.invalid, runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
        const evidence = (try observationResult(&runner)).outcome().validated;
        const diagnostic: @import("domain/model_protocol_retry.zig").Diagnostic = .{ .schema = (try payloadResult(&runner)).outcome().schema_rejected };
        try std.testing.expectEqual(@as(@import("domain/model_protocol_retry.zig").Repetition, if (index == 1) .confirmed else .unconfirmed), try request.protocolRepetition(evidence, diagnostic));
        if (prior) |previous| {
            try std.testing.expectError(error.ModelRequestAssociationInvalid, request.protocolRepetition(previous, diagnostic));
            try std.testing.expectError(error.ModelRequestAssociationInvalid, original.?.protocolRepetition(evidence, diagnostic));
        }
        prior = evidence;
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
        const correction = try currentRequest(&runner);
        const wire = try @import("adapters/provider/bedrock_request.zig").encode(std.testing.allocator, correction.prepared().?, .inference);
        defer std.testing.allocator.free(wire);
        try std.testing.expectEqual(@as(usize, if (index == 1) 1 else 0), std.mem.count(u8, wire, "The previous correction still failed this validation."));
        try std.testing.expect(std.mem.indexOf(u8, wire, "identical response") == null);
        try std.testing.expect(std.mem.indexOf(u8, wire, "Schema validation failed: this property is not allowed") != null);
        try std.testing.expectEqual(@as(u128, (index + 1) * 7), runner.tokenLedger().committed());
    }
    try std.testing.expectEqual(@as(u64, 3), runner.bindings().invokeStep(.{ .bytes = "account" }).rejected.retry_limit.completed_executions);
    // A new execution with the same compiled schema cannot inherit the old fact.
    var fresh = fixture.runner(graph, std.testing.allocator);
    defer fresh.deinit();
    try prepareProtocolAttempt(&fresh, false);
    const current = try currentRequest(&fresh);
    try std.testing.expect(current.id() != original.?.id());
    try std.testing.expectError(error.ModelRequestAssociationInvalid, current.protocolRepetition(prior.?, .missing_final_text));
    try std.testing.expectEqual(@as(u128, 0), fresh.tokenLedger().committed());
    try std.testing.expectEqual(@as(usize, 3), fake.effect_count);
}

test "correction handoff releases copied rejection context at every allocation failure" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const nested = "{\"type\":\"object\",\"properties\":{\"result\":" ++ schema_bytes ++ "},\"required\":[\"result\"],\"additionalProperties\":false}";
    const graph = try fixture.compileWithSchema(try protocolRetryYaml(&fixture), nested);
    for ([_][]const u8{ "{\"result\":{\"foreign\":true}}", malformed_protocol_record }) |body|
        try std.testing.checkAllAllocationFailures(std.testing.allocator, correctionAllocation, .{ &fixture, graph, body });
}

fn correctionAllocation(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, body: []const u8) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fake.invocation_plan.complete.content = body;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    const invocation = runner.bindings().invokeInvocation();
    if (invocation != .outcome or invocation.outcome != .ok) return error.OutOfMemory;
    for ([_][]const u8{
        "initialize", "origin",           "validate",  "build", "account",           "assign-operation", "authorize",         "phase",              "advance-request", "advance-operation", "call",  "validate-response", "complete-operation", "decode", "validate-payload", "retry",
        "account",    "assign-operation", "authorize", "phase", "advance-operation", "call",             "validate-response", "complete-operation", "decode",          "validate-payload",  "retry",
    }, 0..) |step, index| {
        const result = runner.bindings().invokeStep(.{ .bytes = step });
        if (result != .outcome or result.outcome == .failed) return error.OutOfMemory;
        const expected: workflow.OutcomeTag = if (std.mem.eql(u8, step, "validate-payload") or (std.mem.eql(u8, step, "decode") and std.mem.eql(u8, body, malformed_protocol_record))) .invalid else if (index == 19) .more else .ok;
        try std.testing.expectEqual(expected, result.outcome);
    }
    const request = (try currentRequest(&runner)).prepared().?;
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, request.content[2].guidance, "The previous correction still failed this validation."));
    try std.testing.expectEqual(@as(u128, 14), runner.tokenLedger().committed());
}

// Independently authored wire data: preserve all eleven distinct findings while
// moving only the fields that R31 incorrectly placed beside `value`.
fn protocolReview(a: std.mem.Allocator, count: usize, misplaced: bool) ![]const u8 {
    const rows = try a.alloc([]const u8, count);
    for (rows, 1..) |*row, ordinal| {
        const provenance = .{ .claim_ids = .{.{ .ordinal = @as(u32, 1) }}, .clarification_response_ids = [0]u32{} };
        const sources = .{.{ .ordinal = @as(u32, 1) }};
        const detail = try std.fmt.allocPrint(a, "Evidence for requirement {d}.", .{ordinal});
        const loss = .{ .kind = "unlocalized" };
        row.* = if (misplaced)
            try std.json.Stringify.valueAlloc(a, .{ .requirement_ordinal = ordinal, .value = .{ .decision = "supported", .provenance = provenance }, .source_ids = sources, .detail = detail, .loss = loss }, .{})
        else
            try std.json.Stringify.valueAlloc(a, .{ .requirement_ordinal = ordinal, .value = .{ .decision = "supported", .provenance = provenance, .source_ids = sources, .detail = detail, .loss = loss } }, .{});
    }
    return std.mem.concat(a, u8, &.{ "{\"entries\":[", try std.mem.join(a, ",", rows), "]}" });
}

test "metadata and diagnostic echoes exhaust protocol retries without acceptance or extra accounting" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try protocolRetryYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    for ([_][]const u8{ "{\"index\":1,\"unit\":\"signals\"}", "{\"kind\":\"count\",\"count\":2}", "{\"index\":1,\"unit\":\"signals\"}" }, 0..) |body, index| {
        fake.invocation_plan.complete.content = body;
        try prepareProtocolAttempt(&runner, index != 0);
        for ([_][]const u8{ "call", "validate-response", "complete-operation", "decode" }) |step|
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        try std.testing.expectEqual(.invalid, runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
        const correction = (try currentRequest(&runner)).prepared().?;
        try std.testing.expectEqual(@as(usize, 5), correction.content.len);
        const latest = try std.json.parseFromSlice(std.json.Value, fixture.arena.allocator(), correction.content[4].evidence, .{});
        try std.testing.expectEqualStrings(body, latest.value.object.get("rejected_response").?.string);
        try std.testing.expectEqual(@as(u128, (index + 1) * 7), runner.tokenLedger().committed());
    }
    try std.testing.expectEqual(@as(u64, 3), runner.bindings().invokeStep(.{ .bytes = "account" }).rejected.retry_limit.completed_executions);
    try std.testing.expectEqual(@as(usize, 3), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

test "protocol retry budget overshoot charges the response before decoding and blocks another call" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try protocolRetryYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan.complete.content = malformed_protocol_items;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    try prepareProtocolAttempt(&runner, false);
    try rejectProtocolResponse(&runner, false);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
    try prepareProtocolAttempt(&runner, true);
    fake.invocation_plan.complete = .{ .content = malformed_protocol_record, .input_tokens = graph.authority.total_model_token_budget.value - 7, .output_tokens = 1 };
    const rejected = runner.bindings().invokeStep(.{ .bytes = "call" });
    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, rejected.rejected.token_budget);
    try std.testing.expectEqual(@as(u128, graph.authority.total_model_token_budget.value) + 1, runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 2), runner.tokenLedger().revision().value);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(model_invocation.schema.key)] == null);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(envelope_workflow.schema.key)] == null);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null);
    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected.token_budget);
    try std.testing.expectEqual(@as(usize, 2), fake.effect_count);
    try std.testing.expectEqual(@as(u32, 2), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved((try currentRequest(&runner)).id()));
}

test "corrected protocol responses pass schema validation before request closure" {
    for ([_]bool{ false, true }) |consolidated| for ([_]bool{ false, true }) |normalize| {
        const result_schema = "{\"type\":\"object\",\"properties\":{\"items\":{\"type\":\"array\",\"maxItems\":3,\"items\":{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"maxLength\":40},\"text\":{\"type\":\"string\",\"maxLength\":40}},\"required\":[\"name\",\"text\"],\"additionalProperties\":false}}},\"required\":[\"items\"],\"additionalProperties\":false}";
        const corrected = "{\"items\":[{\"name\":\"first\",\"text\":\"one\"},{\"text\":\"two\",\"name\":\"second\"},{\"name\":\"third\",\"text\":\"three\"}]}";
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compileWithSchema(try responseAdmissionYaml(&fixture, try protocolRetryYaml(&fixture), consolidated), result_schema);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = malformed_protocol_items;
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try prepareProtocolAttempt(&runner, false);
        try rejectProtocolResponse(&runner, consolidated);
        for ([_][]const u8{ "{}", corrected }, 0..) |body, index| {
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
            try prepareProtocolAttempt(&runner, true);
            fake.invocation_plan.complete.content = if (normalize and index != 0) try std.fmt.allocPrint(fixture.arena.allocator(), "{{\"{s}", .{body}) else body;
            for ([_][]const u8{ "call", "validate-response", "complete-operation" }) |step|
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            if (!consolidated) try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "decode" }).outcome);
            const validated = runner.bindings().invokeStep(.{ .bytes = "validate-payload" });
            if (index == 0) {
                try std.testing.expectEqual(.invalid, validated.outcome);
                try std.testing.expectEqual(.missing_required_property, (try payloadResult(&runner)).outcome().schema_rejected.reason);
                try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
            } else {
                try std.testing.expectEqual(.ok, validated.outcome);
                const accepted = (try payloadResult(&runner)).outcome().valid.candidate();
                try std.testing.expectEqualStrings(fake.invocation_plan.complete.content, accepted.association().result().complete.content());
                try std.testing.expectEqual(@as(@TypeOf(accepted.normalization()), if (normalize) .removed_leading_brace_quote else .none), accepted.normalization());
                try std.testing.expect(accepted.association().request() == (try currentRequest(&runner)).prepared().?);
                for ([_][]const u8{ "close-request", "observe" }) |step|
                    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            }
        }
        try std.testing.expectEqual(@as(usize, 3), fake.effect_count);
        try std.testing.expectEqual(@as(u128, 21), runner.tokenLedger().committed());
        try std.testing.expectEqual(.accepted, (try requestLedger(&runner)).record((try currentRequest(&runner)).id()).?.terminal_reason.?);
    };
}

test "YAML request closure accepts only the schema-valid candidate and preserves content rejection" {
    for ([_]bool{ false, true }) |consolidated| {
        for ([_][]const u8{ "{\"answer\":\"candidate, not workflow success\"}", "{}", "{", "{\"answer\":1,\"answer\":2}", "{} trailing" }) |body| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try requestCompletionYaml(&fixture), consolidated));
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fake.invocation_plan.complete.content = body;
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            const expected: workflow.OutcomeTag = if (std.mem.indexOf(u8, body, "candidate") != null) .ok else .invalid;
            var harness: Harness = .{ .runner = &runner };
            try std.testing.expectEqual(expected, harness.run());
            const ledger = try requestLedger(&runner);
            const record = ledger.record((try currentRequest(&runner)).id()).?;
            try std.testing.expectEqual(.terminal, record.status);
            try std.testing.expectEqual(@as(identity.TerminalReason, if (expected == .ok) .accepted else .failed), record.terminal_reason.?);
            try std.testing.expectEqual(@as(u64, 3), ledger.revision().value);
            try std.testing.expect(ledger == identity.ledger(runner.model_accounting.?.requests));
            try std.testing.expectEqual(expected, payload_workflow.status(try payloadResult(&runner)));
            try std.testing.expectEqual(expected, runner.envelope.origins[@intFromEnum(requests.ledger_schema.key)].?.outcome);
            try std.testing.expectEqual(.completed, (try completedOperation(&runner)).record().state.terminal);
            try expectResponseAccounting(&runner, &fake, 7);
        }
    }
}

test "YAML request closure preserves provider stops failures cancellation and invalid UTF8" {
    for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason|
        try checkRequestClosureOutcome(.{ .stopped = .{ .reason = reason, .input_tokens = 5, .output_tokens = 2 } }, false);
    for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery|
        try checkRequestClosureOutcome(.{ .failed = .{ .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery } }, false);
    try checkRequestClosureOutcome(.cancelled, false);
    try checkRequestClosureOutcome(.{ .complete = .{ .content = "{}", .input_tokens = 5, .output_tokens = 2 } }, true);
}

fn checkRequestClosureOutcome(plan: fake_provider.InvocationPlan, invalid_utf8: bool) !void {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try requestCompletionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = plan;
    var spy: InvocationSpy = .{ .fake = &fake, .clock = &fixture.clock, .fault = .utf8 };
    fixture.native.invoke_model.action = .{ .provider = if (invalid_utf8) spy.port() else fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const expected: workflow.OutcomeTag = if (plan == .cancelled) .cancelled else .failed;
    try std.testing.expectEqual(expected, harness.run());
    const record = (try requestLedger(&runner)).record((try currentRequest(&runner)).id()).?;
    try std.testing.expectEqual(.terminal, record.status);
    try std.testing.expectEqual(@as(identity.TerminalReason, if (plan == .cancelled) .cancelled else .failed), record.terminal_reason.?);
    const terminal = (try completedOperation(&runner)).record().state.terminal;
    switch (plan) {
        .stopped => |value| try std.testing.expectEqual(value.reason, terminal.stopped),
        .failed => |value| {
            try std.testing.expectEqual(value.cause, terminal.failed.cause);
            try std.testing.expectEqual(value.delivery, terminal.failed.delivery);
            try std.testing.expectEqual(value.retry_class, terminal.failed.retry_class);
        },
        .cancelled => try std.testing.expectEqual(.accepted_or_unknown, terminal.cancelled),
        .complete => try std.testing.expectEqual(.response_invalid, terminal.failed.cause),
    }
    try std.testing.expectEqual(expected, payload_workflow.status(try payloadResult(&runner)));
    try expectResponseAccounting(&runner, &fake, if (plan == .complete or plan == .stopped) 7 else 0);
}

test "request closure rejects every missing input stale ledger and duplicate closure without mutation" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try requestCompletionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan.complete.content = "{\"answer\":\"value\"}";
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    try prepareRequestClosure(&runner, .ok);
    const original = try values.retain(runner.envelope.slots[@intFromEnum(requests.ledger_schema.key)].?);
    defer values.destroy(original);
    for (request_completion.Complete.contract.requires) |key| {
        const ordinal = @intFromEnum(key);
        const stored = runner.envelope.slots[ordinal];
        runner.envelope.slots[ordinal] = null;
        const result = runner.bindings().invokeStep(.{ .bytes = "close-request" });
        runner.envelope.slots[ordinal] = stored;
        try std.testing.expectEqual(.authority, result.rejected);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(requests.ledger_schema.key)] == original);
    }
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "close-request" }).outcome);
    const closed = try requestLedger(&runner);
    try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "close-request" }).rejected);
    const key = @intFromEnum(requests.ledger_schema.key);
    const saved = runner.envelope.slots[key];
    runner.envelope.slots[key] = original;
    const stale = runner.bindings().invokeStep(.{ .bytes = "close-request" });
    runner.envelope.slots[key] = saved;
    try std.testing.expectEqual(.authority, stale.rejected);
    try std.testing.expect(closed == try requestLedger(&runner));
    try expectResponseAccounting(&runner, &fake, 7);
}

test "request closure rejects foreign payload terminal attempt and request evidence" {
    for ([_][]const u8{ "{\"answer\":\"value\"}", "{" }) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try requestCompletionYaml(&fixture));
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        var fake_first = invocationProvider(&first, std.testing.allocator);
        var fake_second = invocationProvider(&second, std.testing.allocator);
        for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
            fake.invocation_plan.complete.content = body;
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            try prepareRequestClosure(runner, if (body.len == 1) .invalid else .ok);
        }
        for (request_completion.Complete.contract.requires) |key| {
            const index = @intFromEnum(key);
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            const rejected = first.bindings().invokeStep(.{ .bytes = "close-request" });
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            try std.testing.expectEqual(.authority, rejected.rejected);
            try std.testing.expectEqual(.invoked, (try requestLedger(&first)).record((try currentRequest(&first)).id()).?.status);
        }
    }
}

test "request closure refuses an additional assigned or invoked operation despite terminal evidence" {
    for ([_]bool{ false, true }) |invoke| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try requestCompletionYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = "{\"answer\":\"value\"}";
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try prepareRequestClosure(&runner, .ok);
        const state = &runner.model_accounting.?;
        const ledger = try requestLedger(&runner);
        const prepared = (try currentRequest(&runner)).prepared().?;
        var id = (try completedOperation(&runner)).record().id;
        id.kind = .input_token_count;
        const authority = state.operationAuthority(ledger);
        const assigned = try lifecycle.propose(state.current_operations, authority, state.current_operations.revision(), id, null, .{ .assign_count = .{ .binding_id = prepared.binding_id, .model_visible_input_id = prepared.model_visible_input_id } });
        state.current_operations = try lifecycle.apply(state.current_operations, authority, assigned);
        if (invoke) {
            const invoked = try lifecycle.propose(state.current_operations, authority, state.current_operations.revision(), id, state.current_operations.record(id).?.revision, .{ .invoke = .{ .deadline_monotonic_ms = 1000 } });
            state.current_operations = try lifecycle.apply(state.current_operations, authority, invoked);
        }
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "close-request" }).rejected);
        try std.testing.expectError(error.ProviderOperationStillOpen, fixture.native.complete_request.action.execute(ledger, state.current_operations, ledger.revision(), prepared.model_request_id, .invoked, .{ .terminal = .accepted }));
        try std.testing.expect(ledger == try requestLedger(&runner));
    }
}

test "request closure needs no live lease deadline or remaining token budget and retains ownership" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try requestCompletionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    var active = true;
    defer if (active) runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan.complete.content = "{\"answer\":\"value\"}";
    fake.invocation_plan.complete.input_tokens = graph.authority.total_model_token_budget.value - 2;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    try prepareRequestClosure(&runner, .ok);
    const result = try payloadResult(&runner);
    const previous = try requestLedger(&runner);
    const original_operations = runner.model_accounting.?.current_operations;
    const original_requests = try values.retain(runner.envelope.slots[@intFromEnum(requests.ledger_schema.key)].?);
    defer values.destroy(original_requests);
    fixture.clock.now_ms = 1001;
    runner.provider_clock = null;
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "close-request" }).outcome);
    try std.testing.expect(original_operations == runner.model_accounting.?.current_operations);
    try std.testing.expect(result == try payloadResult(&runner));
    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected.token_budget);
    try expectResponseAccounting(&runner, &fake, graph.authority.total_model_token_budget.value);
    const retained_payload = try values.retain(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)].?);
    defer values.destroy(retained_payload);
    const retained_ledger = try values.retain(runner.envelope.slots[@intFromEnum(requests.ledger_schema.key)].?);
    defer values.destroy(retained_ledger);
    const ledger = try requestLedger(&runner);
    const id = (try currentRequest(&runner)).id();
    runner.deinit();
    active = false;
    try std.testing.expectEqual(.accepted, ledger.record(id).?.terminal_reason.?);
    try std.testing.expectEqual(.invoked, previous.record(id).?.status);
    try std.testing.expect(result.outcome().valid.candidate().association().request().model_request_id == id);
    try std.testing.expectEqualStrings(schema_bytes, result.outcome().valid.candidate().association().request().response_schema.bytes());
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
}

test "request closure rejects forged successors suppressed outcomes and cancelled publication" {
    const Spy = RequestClosureSpy(request_completion.Complete);
    for (std.enums.values(Spy.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try requestCompletionYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .stopped = .{ .reason = .output_limit, .input_tokens = 5, .output_tokens = 2 } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try prepareRequestClosure(&runner, .failed);
        var spy: Spy = .{ .inner = &fixture.native.complete_request, .fault = fault };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, request_completion.Complete.contract.id)) {
            entry.binding = bindings.bind(Spy, &spy, Spy.invoke);
        };
        runner.runtime = .{ .context = &spy, .status_fn = Spy.status };
        const original = try requestLedger(&runner);
        const original_operations = runner.model_accounting.?.current_operations;
        const result = runner.bindings().invokeStep(.{ .bytes = "close-request" });
        switch (fault) {
            .cancelled => try std.testing.expectEqual(.cancelled, result.rejected),
            else => try std.testing.expectEqual(.authority, result.rejected),
        }
        try std.testing.expect(original == try requestLedger(&runner));
        try std.testing.expect(original == identity.ledger(runner.model_accounting.?.requests));
        try std.testing.expect(original_operations == runner.model_accounting.?.current_operations);
        try std.testing.expectEqual(.failed, payload_workflow.status(try payloadResult(&runner)));
        try std.testing.expectEqual(.invoked, original.record((try currentRequest(&runner)).id()).?.status);
        try expectResponseAccounting(&runner, &fake, 7);
    }
}

fn RequestClosureSpy(comptime Native: type) type {
    return struct {
        const Fault = enum { missing, old_snapshot, accepted, needs_user, invalid_exhausted, cancelled_reason, assignment, skipped_revision, suppressed_outcome, cancelled, undeclared_invalidation };
        inner: *Native,
        fault: Fault,
        invoked: bool = false,

        fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            var candidate = try Native.invoke(self.inner, input);
            switch (self.fault) {
                .suppressed_outcome => candidate.outcome = .ok,
                .cancelled => {},
                .undeclared_invalidation => candidate.delta.data_invalidations.insert(.model_payload_schema_result),
                else => {
                    const current = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
                    const id = (try requests.readCurrent(&input.step.data, requests.prepared_schema)).id();
                    const owner: ?*identity.Owner = switch (self.fault) {
                        .missing => null,
                        .old_snapshot => identity.retainLedger(current) catch return error.OperationExecutionFailed,
                        .accepted, .needs_user, .invalid_exhausted, .cancelled_reason => identity.createLifecycleSuccessor(current, current.revision(), id, .invoked, .{ .terminal = switch (self.fault) {
                            .accepted => .accepted,
                            .needs_user => .needs_user,
                            .invalid_exhausted => .invalid_exhausted,
                            .cancelled_reason => .cancelled,
                            else => unreachable,
                        } }) catch return error.OperationExecutionFailed,
                        .assignment, .skipped_revision => assigned: {
                            const assigned = identity.createSuccessor(current, current.revision(), id.immutable_unit_owner_id, id.model_operation_id, id.purpose) catch return error.OperationExecutionFailed;
                            if (self.fault == .assignment) break :assigned assigned.owner;
                            defer identity.deinitOwner(assigned.owner);
                            const next = identity.ledger(assigned.owner);
                            break :assigned identity.createLifecycleSuccessor(next, next.revision(), id, .invoked, .{ .terminal = .failed }) catch return error.OperationExecutionFailed;
                        },
                        else => unreachable,
                    };
                    const key = @intFromEnum(requests.ledger_schema.key);
                    values.destroy(candidate.delta.data_replacements[key].?);
                    candidate.delta.data_replacements[key] = if (owner) |value| requests.adoptLedger(std.testing.allocator, value) catch return error.OperationExecutionFailed else null;
                },
            }
            self.invoked = true;
            return candidate;
        }

        fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
            const self: *const @This() = @ptrCast(@alignCast(context.?));
            return if (self.invoked and self.fault == .cancelled) .cancelled else .active;
        }
    };
}

test "request closure releases owned ledgers and responses on allocation failure for every outcome" {
    for ([_]fake_provider.InvocationPlan{
        .{ .complete = .{ .content = "{\"answer\":\"value\"}", .input_tokens = 5, .output_tokens = 2 } },
        .{ .complete = .{ .content = "{}", .input_tokens = 5, .output_tokens = 2 } },
        .{ .complete = .{ .content = "{", .input_tokens = 5, .output_tokens = 2 } },
        .{ .stopped = .{ .reason = .output_limit, .input_tokens = 5, .output_tokens = 2 } },
        .{ .failed = .{ .cause = .request_rejected, .retry_class = .never, .delivery = .not_sent } },
        .cancelled,
    }) |plan| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try requestCompletionYaml(&fixture));
        try std.testing.checkAllAllocationFailures(std.testing.allocator, requestClosureAllocationCase, .{ &fixture, graph, plan });
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

fn requestClosureAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, plan: fake_provider.InvocationPlan) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fake.invocation_plan = plan;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    try std.testing.expect(fake.effect_count <= 1);
    const record = if (requestLedger(&runner)) |ledger| ledger.latestRecord() else |_| null;
    if (record == null or record.?.status != .terminal) {
        try std.testing.expectEqual(.failed, outcome);
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(payload_workflow.status(try payloadResult(&runner)), outcome);
    try std.testing.expectEqual(@as(identity.TerminalReason, switch (outcome) {
        .ok => .accepted,
        .invalid, .failed => .failed,
        .cancelled => .cancelled,
        else => unreachable,
    }), record.?.terminal_reason.?);
    try expectResponseAccounting(&runner, &fake, if (plan == .complete or plan == .stopped) 7 else 0);
}

test "request closure YAML rejects missing evidence hidden reasons and forged compiled contracts" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try requestCompletionYaml(&fixture);
    for ([_][2][]const u8{
        .{ "use: complete-model-request,", "use: hidden-request-closure," },
        .{ "use: complete-model-request,", "use: complete-model-request, with: {reason: accepted}," },
        .{ "use: complete-model-request,", "use: complete-model-request, with: {transition: terminal}," },
        .{ "use: complete-model-request,", "use: complete-model-request, with: {retry-limit: 1}," },
        .{ "use: complete-model-request,", "use: complete-model-request, with: {slot: selected}," },
        .{ "use: complete-model-request,", "use: complete-model-request, with: {timeout-ms: 1}," },
        .{ "use: complete-provider-operation, on: {ok: decode, failed: decode, cancelled: decode}", "use: core.noop, on: {ok: decode}" },
        .{ "use: validate-model-payload-schema, on: {ok: close-request, invalid: close-request, failed: close-request, cancelled: close-request}", "use: core.noop, on: {ok: close-request}" },
        .{ "invalid: end.invalid", "invalid: end.ok" },
        .{ "failed: end.failed", "failed: end.ok" },
        .{ "cancelled: end.cancelled", "cancelled: end.ok" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
    const graph = try fixture.compile(source);
    for (0..5) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, request_completion.Complete.contract.id)) {
            switch (variant) {
                0 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request },
                1 => step.capabilities = &.{"model-provider"},
                2 => step.replaces = &.{ .model_request_identity_ledger, .prepared_model_request },
                3 => step.outcomes = &.{.ok},
                4 => step.optional = &.{.provider_authorization_result},
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "close-request" }).rejected);
    }
}

test "YAML provider completion closes only the operation independently of payload validity" {
    const Case = struct { body: []const u8, outcome: workflow.OutcomeTag };
    for ([_]Case{
        .{ .body = "{\"answer\":\"value\"}", .outcome = .ok },
        .{ .body = "{", .outcome = .invalid },
        .{ .body = "{}", .outcome = .invalid },
    }) |case| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try completionYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = case.body;
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(case.outcome, harness.run());
        const terminal = try completedOperation(&runner);
        const record = terminal.record();
        const current = runner.model_accounting.?.current_operations;
        try std.testing.expect(terminal == try current.requireTerminal(record.id));
        try std.testing.expectEqual(.completed, record.state.terminal);
        try std.testing.expectEqual(@as(u64, 3), record.revision.value);
        try std.testing.expectEqual(@as(u64, 3), current.revision().value);
        try current.validateRequestClosure(record.id.model_request_id);
        const request_ledger = identity.ledger(runner.model_accounting.?.requests);
        try std.testing.expectEqual(.invoked, request_ledger.record(record.id.model_request_id).?.status);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.invoked_provider_operation)] == null);
        try std.testing.expect((try observationResult(&runner)).operationId().eql(record.id));
        try std.testing.expectEqualStrings(case.body, (try observationResult(&runner)).outcome().validated.result().complete.content());
        try std.testing.expectEqual(.ok, runner.envelope.origins[@intFromEnum(attempt_values.terminal_schema.key)].?.outcome);
        try expectResponseAccounting(&runner, &fake, 7);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    }
}

test "YAML provider completion preserves stopped failed cancelled and unsafe response facts" {
    for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason| {
        try checkCompletionOutcome(.{ .stopped = .{ .reason = reason, .input_tokens = 5, .output_tokens = 2 } }, false);
    }
    for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        try checkCompletionOutcome(.{ .failed = .{ .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery } }, false);
    }
    try checkCompletionOutcome(.cancelled, false);
    try checkCompletionOutcome(.{ .complete = .{ .content = "{}", .input_tokens = 5, .output_tokens = 2 } }, true);
}

fn checkCompletionOutcome(plan: fake_provider.InvocationPlan, invalid_utf8: bool) !void {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try completionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = plan;
    var spy: InvocationSpy = .{ .fake = &fake, .clock = &fixture.clock, .fault = .utf8 };
    fixture.native.invoke_model.action = .{ .provider = if (invalid_utf8) spy.port() else fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const expected: workflow.OutcomeTag = if (plan == .cancelled) .cancelled else .failed;
    try std.testing.expectEqual(expected, harness.run());
    const terminal = (try completedOperation(&runner)).record().state.terminal;
    switch (plan) {
        .complete => {
            try std.testing.expectEqual(.response_invalid, terminal.failed.cause);
            try std.testing.expectEqual(.response_received, terminal.failed.delivery);
        },
        .stopped => |stop| try std.testing.expectEqual(stop.reason, terminal.stopped),
        .failed => |failure| {
            try std.testing.expectEqual(failure.cause, terminal.failed.cause);
            try std.testing.expectEqual(failure.retry_class, terminal.failed.retry_class);
            try std.testing.expectEqual(failure.delivery, terminal.failed.delivery);
        },
        .cancelled => try std.testing.expectEqual(.accepted_or_unknown, terminal.cancelled),
    }
    try std.testing.expectEqual(expected, runner.envelope.origins[@intFromEnum(attempt_values.terminal_schema.key)].?.outcome);
    try std.testing.expect((try envelopeResult(&runner)).outcome().not_decoded == try observationResult(&runner));
    try std.testing.expect((try payloadResult(&runner)).outcome().not_validated == try envelopeResult(&runner));
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    try expectResponseAccounting(&runner, &fake, if (plan == .stopped or invalid_utf8) 7 else 0);
}

test "YAML completion needs no live lease and works at exact token exhaustion" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try completionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = .{ .complete = .{ .content = "{\"answer\":\"value\"}", .input_tokens = graph.authority.total_model_token_budget.value - 2, .output_tokens = 2 } };
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    try prepareCompletable(&runner);
    fixture.clock.now_ms = std.math.maxInt(u64);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).outcome);
    try std.testing.expectEqual(.completed, (try completedOperation(&runner)).record().state.terminal);
    try std.testing.expectEqual(.exhausted, runner.tokenLedger().status());
    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected.token_budget);
    try expectResponseAccounting(&runner, &fake, graph.authority.total_model_token_budget.value);
}

test "YAML completion releases unused authorization after provider-side cancellation exactly once" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try completionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    var active = true;
    defer if (active) runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    // Cancel before entering the lease port, whose own rejection already cleans up.
    var spy: InvocationSpy = .{ .fake = &fake, .clock = &fixture.clock, .fault = .cancel_before_lease };
    fixture.native.invoke_model.action = .{ .provider = spy.port() };
    try prepareInvocable(&runner);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
    for ([_][]const u8{ "call", "validate-response" }) |step| try std.testing.expectEqual(.cancelled, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    try std.testing.expectEqual(@as(usize, 0), fixture.authorization.destroyed_count);
    try std.testing.expectEqual(.cancelled, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).outcome);
    try std.testing.expectEqual(.accepted_or_unknown, (try completedOperation(&runner)).record().state.terminal.cancelled);
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
    try std.testing.expectEqual(@as(usize, 1), spy.calls);
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 0), fake.effect_count);
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    runner.deinit();
    active = false;
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
}

test "YAML completion rejects duplicate stale and missing evidence without altering the ledger" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try completionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    try prepareCompletable(&runner);
    const state = &runner.model_accounting.?;
    const original = state.current_operations;
    const observation_key = @intFromEnum(observation_workflow.schema.key);
    const source = runner.envelope.slots[observation_key];
    runner.envelope.slots[observation_key] = null;
    try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).rejected);
    runner.envelope.slots[observation_key] = source;
    try std.testing.expect(original == state.current_operations);
    const invoked_key = @intFromEnum(attempt_values.invoked_schema.key);
    const retained = try values.retain(runner.envelope.slots[invoked_key].?);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).outcome);
    const current = state.current_operations;
    try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).rejected);
    runner.envelope.slots[invoked_key] = retained; // transferred to runner cleanup
    try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).rejected);
    try std.testing.expect(current == state.current_operations);
    const completed = try completedOperation(&runner);
    try std.testing.expectError(error.ProviderOperationStillOpen, original.validateRequestClosure(completed.record().id.model_request_id));
    try current.validateRequestClosure(completed.record().id.model_request_id);
    try expectResponseAccounting(&runner, &fake, 7);
}

test "YAML completion rejects foreign observation and invocation evidence" {
    for ([_]pipeline.DataKey{ .provider_invocation_validation_result, .invoked_provider_operation }) |key| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try completionYaml(&fixture));
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        var fake_first = invocationProvider(&first, std.testing.allocator);
        var fake_second = invocationProvider(&second, std.testing.allocator);
        for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            try prepareCompletable(runner);
        }
        std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[@intFromEnum(key)], &second.envelope.slots[@intFromEnum(key)]);
        for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
            const original = runner.model_accounting.?.current_operations;
            try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).rejected);
            try std.testing.expect(original == runner.model_accounting.?.current_operations);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
            try expectResponseAccounting(runner, fake, 7);
        }
    }
}

test "terminal evidence cannot authorize a consumer in another execution" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try completionYaml(&fixture));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var fake_first = invocationProvider(&first, std.testing.allocator);
    var fake_second = invocationProvider(&second, std.testing.allocator);
    for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
        fake.invocation_plan.complete.content = "{\"answer\":\"value\"}";
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = runner };
        try std.testing.expectEqual(.ok, harness.run());
    }
    const key = @intFromEnum(attempt_values.terminal_schema.key);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    for ([_]*runner_module.Runner{ &first, &second }) |runner| try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "observe" }).rejected);
    try std.testing.expectEqual(@as(usize, 2), fixture.observer.calls);
}

test "YAML completion evidence and response owners survive runner cleanup" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try completionYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    var active = true;
    defer if (active) runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan.complete.content = "{\"answer\":\"retained\"}";
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const retained_terminal = try values.retain(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)].?);
    defer values.destroy(retained_terminal);
    const retained_payload = try values.retain(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)].?);
    defer values.destroy(retained_payload);
    const terminal = try completedOperation(&runner);
    const candidate = (try payloadResult(&runner)).outcome().valid.candidate();
    runner.deinit();
    active = false;
    try std.testing.expect(terminal.record().id.eql(candidate.association().operationId()));
    try std.testing.expectEqual(.completed, terminal.record().state.terminal);
    try std.testing.expectEqualStrings("retained", candidate.root().get("answer").?.string);
    try std.testing.expectEqualStrings(schema_bytes, candidate.association().request().response_schema.bytes());
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
}

test "YAML completion rejects unvalidated response associations without inventing a terminal result" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try completionYaml(&fixture));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var fake_first = invocationProvider(&first, std.testing.allocator);
    var fake_second = invocationProvider(&second, std.testing.allocator);
    for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try prepareInvocable(runner);
        for ([_][]const u8{ "advance-operation", "call" }) |step| try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    }
    const key = @intFromEnum(model_invocation.schema.key);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
        const original = runner.model_accounting.?.current_operations;
        try std.testing.expectEqual(.failed, runner.bindings().invokeStep(.{ .bytes = "validate-response" }).outcome);
        try std.testing.expectEqual(error.ProviderInvocationAssociationInvalid, (try observationResult(runner)).outcome().rejected);
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).rejected);
        try std.testing.expect(original == runner.model_accounting.?.current_operations);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
        try expectResponseAccounting(runner, fake, 7);
    }
}

test "YAML completion rejects fabricated terminal facts suppressed failures and cancelled publication" {
    for (std.enums.values(CompletionDeltaSpy.Fault)) |fault| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try completionYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .stopped = .{ .reason = .output_limit, .input_tokens = 5, .output_tokens = 2 } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var spy: CompletionDeltaSpy = .{ .inner = &fixture.native.complete_operation, .fault = fault };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, completion_workflow.Complete.contract.id)) {
            entry.binding = bindings.bind(CompletionDeltaSpy, &spy, CompletionDeltaSpy.invoke);
        };
        try prepareInvocable(&runner);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
        for ([_][]const u8{ "call", "validate-response" }) |step| try std.testing.expectEqual(.failed, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        const original = runner.model_accounting.?.current_operations;
        const response = try observationResult(&runner);
        runner.runtime = .{ .context = &spy, .status_fn = CompletionDeltaSpy.status };
        const outcome = runner.bindings().invokeStep(.{ .bytes = "complete-operation" });
        if (fault == .cancelled) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.authority, outcome.rejected);
        try std.testing.expect(original == runner.model_accounting.?.current_operations);
        try std.testing.expect(try observationResult(&runner) == response);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.invoked_schema.key)] != null);
        try expectResponseAccounting(&runner, &fake, 7);
    }
}

const CompletionDeltaSpy = TerminalDeltaSpy(completion_workflow.Complete);

fn TerminalDeltaSpy(comptime Native: type) type {
    return struct {
        const Fault = enum { command, identity, revision, ledger, outcome, missing_invalidation, extra_invalidation, fabricated_evidence, cancelled };
        inner: *Native,
        fault: Fault,
        invoked: bool = false,

        fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
            const self = context.?;
            var candidate = try Native.invoke(self.inner, input);
            const transition = &candidate.delta.runner_accounting_transition.?.advance_provider_operation;
            switch (self.fault) {
                .command => transition.command = .{ .terminate = .completed },
                .identity => transition.operation_id.kind = .input_token_count,
                .revision => transition.expected_operation_revision.?.value += 1,
                .ledger => transition.expected_revision.value += 1,
                .outcome => candidate.outcome = .ok,
                .missing_invalidation => candidate.delta.data_invalidations.remove(Native.contract.invalidates[0]),
                .extra_invalidation => candidate.delta.data_invalidations.insert(.prepared_model_request),
                .fabricated_evidence => candidate.delta.data_writes[@intFromEnum(attempt_values.terminal_schema.key)] = values.create(std.testing.allocator, values.schema(.terminal_provider_operation, bool, 1, 1), bool, true) catch return error.OperationExecutionFailed,
                .cancelled => {},
            }
            self.invoked = true;
            return candidate;
        }

        fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
            const self: *const @This() = @ptrCast(@alignCast(context.?));
            return if (self.invoked and self.fault == .cancelled) .cancelled else .active;
        }
    };
}

test "YAML completion releases all retained owners on every allocation failure and terminal branch" {
    for ([_]fake_provider.InvocationPlan{
        .{ .complete = .{ .content = "{\"answer\":\"value\"}", .input_tokens = 5, .output_tokens = 2 } },
        .{ .stopped = .{ .reason = .output_limit, .input_tokens = 5, .output_tokens = 2 } },
        .{ .failed = .{ .cause = .request_rejected, .retry_class = .never, .delivery = .not_sent } },
        .cancelled,
    }) |plan| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try completionYaml(&fixture));
        try std.testing.checkAllAllocationFailures(std.testing.allocator, completionAllocationCase, .{ &fixture, graph, plan });
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

fn completionAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, plan: fake_provider.InvocationPlan) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fake.invocation_plan = plan;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    try std.testing.expect(fake.effect_count <= 1);
    if (runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null) {
        try std.testing.expectEqual(.failed, outcome);
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(@as(workflow.OutcomeTag, switch (plan) {
        .complete => .ok,
        .stopped, .failed => .failed,
        .cancelled => .cancelled,
    }), outcome);
    const terminal = try completedOperation(&runner);
    try runner.model_accounting.?.current_operations.validateRequestClosure(terminal.record().id.model_request_id);
    try expectResponseAccounting(&runner, &fake, if (plan == .complete or plan == .stopped) 7 else 0);
}

test "completion YAML rejects missing observations and outcome delivery or selection overrides" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try completionYaml(&fixture);
    for ([_][2][]const u8{
        .{ "use: complete-provider-operation,", "use: hidden-provider-completion," },
        .{ "use: complete-provider-operation,", "use: complete-provider-operation, with: {outcome: completed}," },
        .{ "use: complete-provider-operation,", "use: complete-provider-operation, with: {delivery: not_sent}," },
        .{ "use: complete-provider-operation,", "use: complete-provider-operation, with: {slot: selected}," },
        .{ "use: complete-provider-operation,", "use: complete-provider-operation, with: {retry-limit: 1}," },
        .{ "use: complete-provider-operation,", "use: complete-provider-operation, with: {timeout-ms: 1}," },
        .{ "use: validate-provider-invocation-observation, on: {ok: complete-operation, failed: complete-operation, cancelled: complete-operation}", "use: core.noop, on: {ok: complete-operation}" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
    const graph = try fixture.compile(source);
    for (0..5) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, completion_workflow.Complete.contract.id)) {
            switch (variant) {
                0 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .invoked_provider_operation },
                1 => step.capabilities = &.{"model-provider"},
                2 => step.invalidates = &.{},
                3 => step.runner_accounting = .none,
                4 => step.optional = &.{.provider_authorization_result},
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).rejected);
    }
}

test "runner logs normalization once with call provenance and stops on log failure" {
    const telemetry = @import("domain/telemetry.zig");
    const Spy = struct {
        count: usize = 0,
        fail: bool,
        invalid: bool = false,
        fn process(context: *anyopaque, fact: telemetry.WorkflowTelemetryFact) @import("domain/feature_log_stream.zig").Outcome {
            const self: *@This() = @ptrCast(@alignCast(context));
            _ = @import("domain/log_event_registry.zig").validateFact(fact.fact) catch {
                self.invalid = true;
                return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
            };
            if (fact.fact.event_type == .model_response_normalized) {
                self.count += 1;
                if (fact.fact.correlation_id == null or fact.fact.attempt != 1 or
                    !std.mem.eql(u8, fact.fact.fields.diagnostic_code.?.bytes, "REMOVED_LEADING_BRACE_QUOTE")) self.invalid = true;
                if (self.fail) return .{ .blocked = .LOG_FLUSH_FAILURE };
            }
            return .dropped;
        }
    };
    for ([_]bool{ false, true }) |consolidated| for ([_]bool{ false, true }) |fail| for ([_][]const u8{ "{\"{\"answer\":\"valid\"}", "{\"{\"answer\":42}" }) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        // Supply the already activated feature fact; no filesystem side effects.
        const directory_schema = @import("application/feature_logging_workflow.zig").directory;
        runner.envelope.slots[@intFromEnum(directory_schema.key)] = try @import("application/pipeline_values.zig").create(std.testing.allocator, directory_schema, @import("domain/feature_directory.zig").Directory, .{
            .selector = .{ .feature_id = .{ .bytes = "selected" }, .project_relative_path = "specs/selected" },
            .root_observation = .absent,
            .observation = .absent,
        });
        var spy: Spy = .{ .fail = fail };
        runner.barrier = .{ .context = &spy, .process_fn = Spy.process };
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = body;
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        const result = harness.result();
        if (fail) {
            try std.testing.expectEqual(.LOG_FLUSH_FAILURE, result.execution_rejected.logging);
            try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        } else try std.testing.expectEqual(@as(workflow.OutcomeTag, if (std.mem.indexOf(u8, body, "42") != null) .invalid else .ok), result.execution);
        try std.testing.expect(!spy.invalid);
        try std.testing.expectEqual(@as(usize, 1), spy.count);
        try std.testing.expectEqualStrings(body, (try envelopeResult(&runner)).outcome().decoded.association().result().complete.content());
        try expectResponseAccounting(&runner, &fake, 7);
    };
}

test "normalization never bypasses schema rejection or the protocol retry allowance" {
    for ([_]bool{ false, true }) |consolidated| for ([_][]const u8{
        "{\"{ \"answer\":42}",
        "{\"{ \"answer\":\"invalid remainder\",}",
    }) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try protocolRetryYaml(&fixture), consolidated));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = body;
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        const exhausted = harness.result().execution_rejected.retry_limit;
        try std.testing.expectEqual(@as(u32, 2), exhausted.limit.value);
        try std.testing.expectEqual(@as(u64, 3), exhausted.completed_executions);
        try std.testing.expectEqual(@as(usize, 3), fake.effect_count);
        try std.testing.expectEqual(@as(u128, 21), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        // Preparing the last correction retires admission evidence; its retained
        // original response remains available through the existing request owner.
        const correction = (try currentRequest(&runner)).prepared().?;
        var evidence = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, correction.content[4].evidence, .{});
        defer evidence.deinit();
        try std.testing.expectEqualStrings(body, evidence.value.object.get("rejected_response").?.string);
    };
}

test "YAML payload validation uses each exact compiled schema and retains the same candidate" {
    for ([_]bool{ false, true }) |consolidated| {
        const variants =
            \\{"oneOf":[{"type":"object","properties":{"kind":{"const":"content"},"values":{"type":"array","minItems":1,"maxItems":2,"items":{"type":"integer","minimum":1,"maximum":2}},"marker":{"const":true}},"required":["kind","values","marker"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"question"},"subject":{"enum":["alpha","beta"]}},"required":["kind","subject"],"additionalProperties":false}]}
        ;
        const Case = struct { schema: []const u8 = schema_bytes, body: []const u8, rejection: ?payload_validation.Rejection = null };
        for ([_]Case{
            .{ .body = "{\"answer\":\"é😀\"}" },
            .{ .body = "{\"{\"answer\":\"é😀\"}" },
            .{ .body = "{\"{\"answer\":42}", .rejection = .type_mismatch },
            .{ .body = "{\"{\"answer\":\"ok\",\"approved\":true}", .rejection = .unknown_property },
            .{ .body = "{\"answer\":\"" ++ "x" ** 20_000 ++ "\"}" },
            .{ .body = "{}", .rejection = .missing_required_property },
            .{ .body = "{\"answer\":42}", .rejection = .type_mismatch },
            .{ .body = "{\"answer\":\"ok\",\"approved\":true}", .rejection = .unknown_property },
            .{ .body = "{\"answer\":\"" ++ "x" ** 20_001 ++ "\"}", .rejection = .string_length },
            .{ .schema = variants, .body = "{\"kind\":\"content\",\"values\":[1.0,2e0],\"marker\":true}" },
            .{ .schema = variants, .body = "{\"kind\":\"question\",\"subject\":\"alpha\"}" },
            .{ .schema = variants, .body = "{\"kind\":\"other\"}", .rejection = .unknown_variant },
            .{ .schema = variants, .body = "{\"kind\":\"content\",\"values\":[1,3],\"marker\":true}", .rejection = .integer_range },
            .{ .schema = variants, .body = "{\"kind\":\"content\",\"values\":[],\"marker\":true}", .rejection = .array_length },
            .{ .schema = variants, .body = "{\"kind\":\"content\",\"values\":[1],\"marker\":false}", .rejection = .constant_mismatch },
            .{ .schema = variants, .body = "{\"kind\":\"question\",\"subject\":\"other\"}", .rejection = .enum_mismatch },
        }) |case| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compileWithSchema(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated), case.schema);
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fake.invocation_plan.complete.content = case.body;
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            var harness: Harness = .{ .runner = &runner };
            try std.testing.expectEqual(@as(workflow.OutcomeTag, if (case.rejection != null) .invalid else .ok), harness.run());
            const result = try payloadResult(&runner);
            const decoded = try envelopeResult(&runner);
            try std.testing.expect(result.source() == decoded);
            if (case.rejection) |reason| {
                try std.testing.expectEqual(reason, result.outcome().schema_rejected.reason);
                try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
            } else {
                try std.testing.expect(result.outcome().valid.candidate() == decoded.outcome().decoded);
                try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
            }
            const candidate = decoded.outcome().decoded;
            try std.testing.expect(candidate.association().request() == (try currentRequest(&runner)).prepared().?);
            try std.testing.expectEqualStrings(case.schema, candidate.association().request().response_schema.bytes());
            try std.testing.expectEqualStrings(case.body, candidate.association().result().complete.content());
            try expectResponseAccounting(&runner, &fake, 7);
            try std.testing.expectEqual(.invoked, std.meta.activeTag(runner.model_accounting.?.current_operations.record(candidate.association().operationId()).?.state));
        }
    }
}

test "YAML payload validation preserves protocol provider cancellation and observation rejection" {
    for ([_]bool{ false, true }) |consolidated| {
        for ([_][]const u8{ "{", "[]", "{\"answer\":1,\"answer\":2}", "{\"{\"answer\":1,\"answer\":2}", "{\"{\"answer\":1} trailing", "{} trailing" }) |body| {
            try checkUnvalidatedPayload(.{ .complete = .{ .content = body, .input_tokens = 5, .output_tokens = 2 } }, false, consolidated);
        }
        for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason| {
            try checkUnvalidatedPayload(.{ .stopped = .{ .reason = reason, .input_tokens = 5, .output_tokens = 2 } }, false, consolidated);
        }
        for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
            try checkUnvalidatedPayload(.{ .failed = .{ .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery } }, false, consolidated);
        }
        try checkUnvalidatedPayload(.cancelled, false, consolidated);
        try checkUnvalidatedPayload(.{ .complete = .{ .content = "{}", .input_tokens = 5, .output_tokens = 2 } }, true, consolidated);
    }
}

fn checkUnvalidatedPayload(plan: fake_provider.InvocationPlan, invalid_utf8: bool, consolidated: bool) !void {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = plan;
    var spy: InvocationSpy = .{ .fake = &fake, .clock = &fixture.clock, .fault = .utf8 };
    fixture.native.invoke_model.action = .{ .provider = if (invalid_utf8) spy.port() else fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const expected: workflow.OutcomeTag = if (plan == .cancelled) .cancelled else if (plan == .complete and !invalid_utf8) .invalid else .failed;
    try std.testing.expectEqual(expected, harness.run());
    const decoded = try envelopeResult(&runner);
    const result = try payloadResult(&runner);
    try std.testing.expect(result.source() == decoded);
    try std.testing.expect(result.outcome().not_validated == decoded);
    try std.testing.expectEqual(expected, runner.envelope.origins[@intFromEnum(payload_workflow.schema.key)].?.outcome);
    if (expected == .invalid) try std.testing.expectEqual(error.InvalidModelEnvelope, decoded.outcome().protocol_rejected.reason) else try std.testing.expect(decoded.outcome().not_decoded == try observationResult(&runner));
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    try expectResponseAccounting(&runner, &fake, if (plan == .complete or plan == .stopped) 7 else 0);
}

fn expectResponseAccounting(runner: *const runner_module.Runner, fake: *const fake_provider.FakeLLMProvider, tokens: u128) !void {
    try std.testing.expectEqual(tokens, runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
}

test "YAML schema evidence retains the tree request and response after all upstream cleanup" {
    for ([_]bool{ false, true }) |consolidated| {
        for ([_][]const u8{ "{\"answer\":\"retained\"}", "{}", "{" }) |body| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated));
            var runner = fixture.runner(graph, std.testing.allocator);
            var active = true;
            defer if (active) runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fake.invocation_plan.complete.content = body;
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            var harness: Harness = .{ .runner = &runner };
            try std.testing.expectEqual(@as(workflow.OutcomeTag, if (body.len > 2) .ok else .invalid), harness.run());
            const retained = try values.retain(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)].?);
            defer values.destroy(retained);
            const result = try payloadResult(&runner);
            const original = try envelopeResult(&runner);
            const request = (try currentRequest(&runner)).prepared().?;
            runner.deinit();
            active = false;
            try std.testing.expect(result.source() == original);
            try std.testing.expect(original.source().outcome().validated.request() == request);
            try std.testing.expectEqualStrings(body, original.source().outcome().validated.result().complete.content());
            try std.testing.expectEqualStrings(schema_bytes, request.response_schema.bytes());
            switch (result.outcome()) {
                .valid => |evidence| try std.testing.expectEqualStrings("retained", evidence.candidate().root().get("answer").?.string),
                .schema_rejected => |reason| try std.testing.expectEqual(.missing_required_property, reason.reason),
                .not_validated => |source| try std.testing.expectEqual(error.InvalidModelEnvelope, source.outcome().protocol_rejected.reason),
            }
            try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        }
    }
}

test "YAML payload validation rejects missing evidence and hidden schema or retry overrides" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try payloadYaml(&fixture);
    for ([_][2][]const u8{
        .{ "use: validate-model-payload-schema,", "use: hidden-payload-validator," },
        .{ "use: validate-model-payload-schema,", "use: validate-model-payload-schema, with: {slot: selected}," },
        .{ "use: validate-model-payload-schema,", "use: validate-model-payload-schema, with: {result-schema: result}," },
        .{ "use: validate-model-payload-schema,", "use: validate-model-payload-schema, with: {retry-limit: 1}," },
        .{ "use: validate-model-payload-schema,", "use: validate-model-payload-schema, with: {output-bytes: 100}," },
        .{ "invalid: end.invalid, ", "" },
        .{ "invalid: end.invalid", "invalid: end.ok" },
        .{ "use: decode-model-envelope, on: {ok: validate-payload, invalid: validate-payload, failed: validate-payload, cancelled: validate-payload}", "use: core.noop, on: {ok: validate-payload}" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
}

test "YAML payload validation rejects foreign decoded and nondecoded evidence without rebinding" {
    for ([_][]const u8{ "{\"answer\":\"value\"}", "{" }) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try payloadYaml(&fixture));
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        var fake_first = invocationProvider(&first, std.testing.allocator);
        var fake_second = invocationProvider(&second, std.testing.allocator);
        for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
            fake.invocation_plan.complete.content = body;
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            try prepareInvocable(runner);
            for ([_][]const u8{ "advance-operation", "call", "validate-response", "decode" }) |step| {
                try std.testing.expectEqual(@as(workflow.OutcomeTag, if (body.len == 1 and std.mem.eql(u8, step, "decode")) .invalid else .ok), runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            }
        }
        const key = @intFromEnum(envelope_workflow.schema.key);
        std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
        for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
            try std.testing.expectEqualDeep(execution.Rejection{ .operation_failed = error.OperationExecutionFailed }, runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).rejected);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null);
            try expectResponseAccounting(runner, fake, 7);
        }
    }
}

test "YAML payload validation allocation failures release retained candidates on every outcome" {
    for ([_]bool{ false, true }) |consolidated| {
        for ([_][]const u8{ "{\"answer\":\"value\"}", "{}", "{" }) |body| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated));
            try std.testing.checkAllAllocationFailures(std.testing.allocator, payloadAllocationCase, .{ &fixture, graph, body });
            try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
        }
    }
}

fn payloadAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, body: []const u8) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fake.invocation_plan.complete.content = body;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    try std.testing.expect(fake.effect_count <= 1);
    if (runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null) {
        try std.testing.expectEqual(.failed, outcome);
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(@as(workflow.OutcomeTag, if (body.len > 2) .ok else .invalid), outcome);
    const result = try payloadResult(&runner);
    if (body.len > 2) try std.testing.expect(result.outcome() == .valid) else if (body.len == 2) try std.testing.expectEqual(.missing_required_property, result.outcome().schema_rejected.reason) else try std.testing.expectEqual(error.InvalidModelEnvelope, result.outcome().not_validated.outcome().protocol_rejected.reason);
    try expectResponseAccounting(&runner, &fake, 7);
}

test "YAML payload validation remains available at the token budget without another charge" {
    for ([_]bool{ false, true }) |consolidated| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .complete = .{ .content = "{\"answer\":\"value\"}", .input_tokens = graph.authority.total_model_token_budget.value - 2, .output_tokens = 2 } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.ok, harness.run());
        try std.testing.expectEqual(.exhausted, runner.tokenLedger().status());
        try std.testing.expect((try payloadResult(&runner)).outcome() == .valid);
        try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected.token_budget);
        try expectResponseAccounting(&runner, &fake, graph.authority.total_model_token_budget.value);
    }
}

test "YAML payload publication rejection and cancellation release evidence without consuming the candidate" {
    for ([_]bool{ false, true }) |consolidated| {
        for ([_]bool{ false, true }) |cancel| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated));
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fake.invocation_plan.complete.content = "{\"answer\":\"value\"}";
            fixture.native.invoke_model.action = .{ .provider = fake.interface() };
            var spy: PayloadDeltaSpy = .{ .inner = if (consolidated) .{ .admit = &fixture.native.admit_response } else .{ .validate = &fixture.native.validate_payload }, .cancel = cancel };
            for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, if (consolidated) payload_workflow.Admit.contract.id else payload_workflow.Validate.contract.id)) {
                entry.binding = bindings.bind(PayloadDeltaSpy, &spy, PayloadDeltaSpy.invoke);
            };
            try prepareInvocable(&runner);
            for ([_][]const u8{ "advance-operation", "call", "validate-response" }) |step| {
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            }
            if (!consolidated) try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "decode" }).outcome);
            runner.runtime = .{ .context = &spy, .status_fn = PayloadDeltaSpy.status };
            const original = if (consolidated) null else try envelopeResult(&runner);
            const outcome = runner.bindings().invokeStep(.{ .bytes = "validate-payload" });
            if (cancel) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.authority, outcome.rejected);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null);
            if (original) |retained| {
                try std.testing.expect(try envelopeResult(&runner) == retained);
                try std.testing.expectEqualStrings("value", retained.outcome().decoded.root().get("answer").?.string);
            } else try std.testing.expect(runner.envelope.slots[@intFromEnum(envelope_workflow.schema.key)] == null);
            try expectResponseAccounting(&runner, &fake, 7);
        }
    }
}

const PayloadDeltaSpy = struct {
    inner: union(enum) { validate: *payload_workflow.Validate, admit: *payload_workflow.Admit },
    cancel: bool,
    invoked: bool = false,

    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var candidate = try switch (self.inner) {
            .validate => |inner| payload_workflow.Validate.invoke(inner, input),
            .admit => |inner| payload_workflow.Admit.invoke(inner, input),
        };
        self.invoked = true;
        if (!self.cancel) candidate.delta.data_invalidations.insert(.model_envelope_result);
        return candidate;
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const @This() = @ptrCast(@alignCast(context.?));
        return if (self.invoked and self.cancel) .cancelled else .active;
    }
};

test "compiled payload validation cannot bypass its candidate or add effects" {
    for ([_]bool{ false, true }) |consolidated| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try responseAdmissionYaml(&fixture, try payloadYaml(&fixture), consolidated));
        for (0..3) |variant| {
            var tampered = graph.*;
            const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
            for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, if (consolidated) payload_workflow.Admit.contract.id else payload_workflow.Validate.contract.id)) {
                switch (variant) {
                    0 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request },
                    1 => step.capabilities = &.{"model-provider"},
                    2 => step.invalidates = &.{.model_envelope_result},
                    else => unreachable,
                }
            };
            tampered.authority.steps = steps;
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
            var runner = fixture.runner(&tampered, std.testing.allocator);
            defer runner.deinit();
            try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).rejected);
        }
    }
}

test "YAML decodes complete JSON objects and retains syntax-only evidence and exact numbers" {
    for ([_][]const u8{
        "{}",
        " \t\n{\"answer\":\"value\"}\r\n",
        "{\"values\":[null,true,false,{\"unicode\":\"\\u00e9\"}]}",
        "{\"kind\":\"unrecognized\",\"requestId\":\"not-authority\",\"n\":1e9999}",
        "{\"answer\":\"" ++ "x" ** 65_537 ++ "\"}",
    }) |bytes| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try envelopeYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = bytes;
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.ok, harness.run());
        const decoded = try envelopeResult(&runner);
        const candidate = decoded.outcome().decoded;
        const observation = try observationResult(&runner);
        try std.testing.expect(decoded.source() == observation);
        try std.testing.expect(candidate.association() == observation.outcome().validated);
        try std.testing.expect(candidate.association().request() == (try currentRequest(&runner)).prepared().?);
        try std.testing.expectEqualStrings(bytes, candidate.association().result().complete.content());
        if (candidate.root().get("n")) |number| try std.testing.expectEqualStrings("1e9999", number.number);
        try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
        try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
        try std.testing.expectEqual(.invoked, std.meta.activeTag(runner.model_accounting.?.current_operations.record(observation.operationId()).?.state));
    }
}

test "YAML decoding returns protocol invalid for malformed duplicate non-object and trailing JSON" {
    for ([_][]const u8{
        "",         " ",                 "{",                       "[]",                              "null",  "true",        "17",     "\"text\"",
        "{\"x\":}", "{\"x\":1,\"x\":2}", "{\"x\":1,\"\\u0078\":2}", "{\"items\":[{\"x\":1,\"x\":2}]}", "{} {}", "{} trailing", "{}\x00", "```json\n{}\n```",
    }) |bytes| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try envelopeYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = bytes;
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.invalid, harness.run());
        try std.testing.expectEqual(error.InvalidModelEnvelope, (try envelopeResult(&runner)).outcome().protocol_rejected.reason);
        try std.testing.expectEqual(.invalid, runner.envelope.origins[@intFromEnum(envelope_workflow.schema.key)].?.outcome);
        try std.testing.expectEqualStrings(bytes, (try observationResult(&runner)).outcome().validated.result().complete.content());
        try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    }
}

test "YAML decoder never converts stopped failed cancelled or rejected observations into protocol invalid" {
    for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason| {
        try checkUndecoded(.{ .stopped = .{ .reason = reason, .input_tokens = 5, .output_tokens = 2 } }, false);
    }
    for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        try checkUndecoded(.{ .failed = .{ .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery } }, false);
    }
    try checkUndecoded(.cancelled, false);
    try checkUndecoded(.{ .complete = .{ .content = "{}", .input_tokens = 5, .output_tokens = 2 } }, true);
}

fn checkUndecoded(plan: fake_provider.InvocationPlan, invalid_utf8: bool) !void {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try envelopeYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = plan;
    var spy: InvocationSpy = .{ .fake = &fake, .clock = &fixture.clock, .fault = .utf8 };
    fixture.native.invoke_model.action = .{ .provider = if (invalid_utf8) spy.port() else fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(@as(workflow.OutcomeTag, if (plan == .cancelled) .cancelled else .failed), harness.run());
    const observation = try observationResult(&runner);
    const decoded = try envelopeResult(&runner);
    try std.testing.expect(decoded.source() == observation);
    try std.testing.expect(decoded.outcome().not_decoded == observation);
    try std.testing.expectEqual(observation_workflow.status(observation), runner.envelope.origins[@intFromEnum(envelope_workflow.schema.key)].?.outcome);
    try std.testing.expectEqual(@as(u128, if (plan == .stopped or invalid_utf8) 7 else 0), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

test "decoded YAML candidate keeps its tree and original evidence after all source-value cleanup" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try envelopeYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    var active = true;
    defer if (active) runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan.complete.content = "{\"answer\":\"retained\"}";
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const retained = try values.retain(runner.envelope.slots[@intFromEnum(envelope_workflow.schema.key)].?);
    defer values.destroy(retained);
    const decoded = try envelopeResult(&runner);
    const observation = try observationResult(&runner);
    const request = (try currentRequest(&runner)).prepared().?;
    runner.deinit();
    active = false;
    const candidate = decoded.outcome().decoded;
    try std.testing.expectEqualStrings("retained", candidate.root().get("answer").?.string);
    try std.testing.expect(decoded.source() == observation);
    try std.testing.expect(candidate.association() == observation.outcome().validated);
    try std.testing.expect(candidate.association().request() == request);
    try std.testing.expectEqualStrings(schema_bytes, candidate.association().request().response_schema.bytes());
    try std.testing.expectEqualStrings("origin", candidate.association().operationId().model_request_id.model_operation_id.workflow_step_id.bytes);
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
}

test "YAML decoding rejects absent evidence and parameter or outcome overrides before execution" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try envelopeYaml(&fixture);
    for ([_][2][]const u8{
        .{ "use: decode-model-envelope,", "use: hidden-envelope-decoder," },
        .{ "use: decode-model-envelope,", "use: decode-model-envelope, with: {slot: selected}," },
        .{ "use: decode-model-envelope,", "use: decode-model-envelope, with: {result-schema: result}," },
        .{ "use: decode-model-envelope,", "use: decode-model-envelope, with: {retry-limit: 1}," },
        .{ "use: decode-model-envelope,", "use: decode-model-envelope, with: {output-bytes: 100}," },
        .{ "invalid: end.invalid, ", "" },
        .{ "invalid: end.invalid", "invalid: end.failed" },
        .{ "invalid: end.invalid", "invalid: end.ok" },
        .{ "use: validate-provider-invocation-observation, on: {ok: decode, failed: decode, cancelled: decode}", "use: core.noop, on: {ok: decode}" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
}

test "YAML decoder rejects foreign sealed observations without rebinding or a new provider call" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try envelopeYaml(&fixture));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var fake_first = invocationProvider(&first, std.testing.allocator);
    var fake_second = invocationProvider(&second, std.testing.allocator);
    for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
        fake.invocation_plan.complete.content = "{}";
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try prepareInvocable(runner);
        for ([_][]const u8{ "advance-operation", "call", "validate-response" }) |step| {
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        }
    }
    const key = @intFromEnum(observation_workflow.schema.key);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    for ([_]*runner_module.Runner{ &first, &second }) |runner| {
        try std.testing.expectEqualDeep(execution.Rejection{ .operation_failed = error.OperationExecutionFailed }, runner.bindings().invokeStep(.{ .bytes = "decode" }).rejected);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(envelope_workflow.schema.key)] == null);
        try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
    }
    try std.testing.expectEqual(@as(usize, 1), fake_first.effect_count);
    try std.testing.expectEqual(@as(usize, 1), fake_second.effect_count);
}

test "YAML decoder releases parse trees and retained evidence on every allocation failure" {
    for ([_][]const u8{ "{\"answer\":\"value\",\"list\":[true,null,{}]}", "{\"x\":1,\"x\":2}", "{} trailing" }, 0..) |body, index| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try envelopeYaml(&fixture));
        try std.testing.checkAllAllocationFailures(std.testing.allocator, envelopeAllocationCase, .{ &fixture, graph, body, index == 0 });
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

fn envelopeAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, body: []const u8, accepted: bool) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fake.invocation_plan.complete.content = body;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    try std.testing.expect(fake.effect_count <= 1);
    if (runner.envelope.slots[@intFromEnum(envelope_workflow.schema.key)] == null) {
        try std.testing.expectEqual(.failed, outcome);
        return error.OutOfMemory;
    }
    const decoded = try envelopeResult(&runner);
    if (accepted) {
        try std.testing.expectEqual(.ok, outcome);
        try std.testing.expectEqualStrings("value", decoded.outcome().decoded.root().get("answer").?.string);
    } else {
        try std.testing.expectEqual(.invalid, outcome);
        try std.testing.expectEqual(error.InvalidModelEnvelope, decoded.outcome().protocol_rejected.reason);
    }
    try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
}

test "YAML decoding releases rejected deltas and cancelled trees without consuming its evidence" {
    for ([_]bool{ false, true }) |cancel| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try envelopeYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = "{\"answer\":\"value\"}";
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var spy: DecodeDeltaSpy = .{ .inner = &fixture.native.decode_envelope, .cancel = cancel };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, envelope_workflow.Decode.contract.id)) {
            entry.binding = bindings.bind(DecodeDeltaSpy, &spy, DecodeDeltaSpy.invoke);
        };
        try prepareInvocable(&runner);
        for ([_][]const u8{ "advance-operation", "call", "validate-response" }) |step| {
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        }
        runner.runtime = .{ .context = &spy, .status_fn = DecodeDeltaSpy.status };
        const original = try observationResult(&runner);
        const outcome = runner.bindings().invokeStep(.{ .bytes = "decode" });
        if (cancel) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.authority, outcome.rejected);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(envelope_workflow.schema.key)] == null);
        try std.testing.expect(try observationResult(&runner) == original);
        try std.testing.expectEqualStrings("{\"answer\":\"value\"}", original.outcome().validated.result().complete.content());
        try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    }
}

const DecodeDeltaSpy = struct {
    inner: *envelope_workflow.Decode,
    cancel: bool,
    invoked: bool = false,

    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var candidate = try envelope_workflow.Decode.invoke(self.inner, input);
        self.invoked = true;
        if (!self.cancel) candidate.delta.data_invalidations.insert(.provider_invocation_validation_result);
        return candidate;
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const @This() = @ptrCast(@alignCast(context.?));
        return if (self.invoked and self.cancel) .cancelled else .active;
    }
};

test "compiled decoding contracts cannot bypass evidence or add a provider capability" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try envelopeYaml(&fixture));
    for (0..3) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, envelope_workflow.Decode.contract.id)) {
            switch (variant) {
                0 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request },
                1 => step.capabilities = &.{"model-provider"},
                2 => step.invalidates = &.{.provider_invocation_validation_result},
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "decode" }).rejected);
    }
}

test "YAML validates a complete observation without decoding or charging tokens twice" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try observationYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const result = try observationResult(&runner);
    const evidence = result.outcome().validated;
    const raw = (try invocationResult(&runner)).outcome().?.observation.completed.raw_result.complete;
    try std.testing.expect(evidence.request() == (try currentRequest(&runner)).prepared().?);
    try std.testing.expect(result.operationId().eql(evidence.operationId()));
    try std.testing.expectEqualStrings("not JSON; still untrusted", evidence.result().complete.content());
    try std.testing.expect(evidence.result().complete.content().ptr == raw.content.bytes.ptr);
    try std.testing.expectEqualDeep(raw.usage, evidence.usage().?);
    try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.observer.calls);
    try std.testing.expectEqual(.invoked, std.meta.activeTag(runner.model_accounting.?.current_operations.record(result.operationId()).?.state));
}

test "YAML observation validation preserves every stop and provider failure without another charge" {
    inline for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try observationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .stopped = .{ .reason = reason, .input_tokens = 8, .output_tokens = 3 } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        try std.testing.expectEqual(reason, (try observationResult(&runner)).outcome().validated.result().stopped);
        try std.testing.expectEqual(@as(u128, 11), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    }
    inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try observationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan = .{ .failed = .{ .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery } };
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.failed, harness.run());
        const evidence = (try observationResult(&runner)).outcome().validated;
        try std.testing.expectEqualDeep((try invocationResult(&runner)).outcome().?.observation.failed, evidence.result().failed);
        try std.testing.expect(evidence.usage() == null);
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    }
}

test "YAML observation validation retains provider cancellation without fabricating evidence" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try observationYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = .cancelled;
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.cancelled, harness.run());
    try std.testing.expectEqual(.cancelled, (try observationResult(&runner)).outcome());
    try std.testing.expectEqual(.usage_unavailable, runner.tokenLedger().status());
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

test "YAML observation validation rejects unsafe UTF-8 after accounting its reported usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try observationYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    var spy: InvocationSpy = .{ .fake = &fake, .clock = &fixture.clock, .fault = .utf8 };
    fixture.native.invoke_model.action = .{ .provider = spy.port() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.failed, harness.run());
    const evidence = (try observationResult(&runner)).outcome().validated;
    try std.testing.expectEqual(.response_invalid, evidence.result().failed.cause);
    try std.testing.expectEqual(.response_received, evidence.delivery());
    try std.testing.expectEqual(.never, evidence.result().failed.retry_class);
    try std.testing.expectEqual(@as(u64, 7), evidence.usage().?.total_tokens);
    try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
}

test "YAML observation consumers reject cross-execution results and stale invoked evidence" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try envelopeYaml(&fixture));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var fake_first = invocationProvider(&first, std.testing.allocator);
    var fake_second = invocationProvider(&second, std.testing.allocator);
    for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &fake_first, &fake_second }) |runner, fake| {
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        try prepareInvocable(runner);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "call" }).outcome);
    }
    const raw_key = @intFromEnum(model_invocation.schema.key);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[raw_key], &second.envelope.slots[raw_key]);
    try std.testing.expectEqual(.failed, second.bindings().invokeStep(.{ .bytes = "validate-response" }).outcome);
    try std.testing.expectEqual(error.ProviderInvocationAssociationInvalid, (try observationResult(&second)).outcome().rejected);
    try std.testing.expectEqual(.failed, second.bindings().invokeStep(.{ .bytes = "decode" }).outcome);
    try std.testing.expect((try envelopeResult(&second)).outcome().not_decoded == try observationResult(&second));
    const invoked_key = @intFromEnum(attempt_values.invoked_schema.key);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[invoked_key], &second.envelope.slots[invoked_key]);
    try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "validate-response" }).rejected);
    try std.testing.expect(first.envelope.slots[@intFromEnum(observation_workflow.schema.key)] == null);
    try std.testing.expectEqual(@as(u128, 7), first.tokenLedger().committed());
    try std.testing.expectEqual(@as(u128, 7), second.tokenLedger().committed());
    try std.testing.expectEqual(@as(usize, 1), fake_first.effect_count);
    try std.testing.expectEqual(@as(usize, 1), fake_second.effect_count);
}

test "validated observation owns its request and response after source values and runner cleanup" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try observationYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    var active = true;
    defer if (active) runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    const retained = try values.retain(runner.envelope.slots[@intFromEnum(observation_workflow.schema.key)].?);
    defer values.destroy(retained);
    const result = try observationResult(&runner);
    const original_request = (try currentRequest(&runner)).prepared().?;
    const original_bytes = result.outcome().validated.result().complete.content();
    runner.deinit();
    active = false;
    try std.testing.expectEqualStrings("not JSON; still untrusted", result.outcome().validated.result().complete.content());
    try std.testing.expect(result.outcome().validated.request() == original_request);
    try std.testing.expect(result.outcome().validated.result().complete.content().ptr == original_bytes.ptr);
    try std.testing.expectEqualStrings(schema_bytes, result.outcome().validated.request().response_schema.bytes());
    try std.testing.expectEqualStrings("origin", result.operationId().model_request_id.model_operation_id.workflow_step_id.bytes);
    try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
}

test "observation validation remains available after exact workflow token exhaustion" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try observationYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = graph.authority.total_model_token_budget.value, .output_tokens = 0 } };
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    try std.testing.expectEqual(.exhausted, runner.tokenLedger().status());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    try std.testing.expectEqualStrings("{}", (try observationResult(&runner)).outcome().validated.result().complete.content());
    try std.testing.expectEqual(error.WorkflowTokenBudgetExceeded, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected.token_budget);
    try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
}

test "observation YAML rejects missing inputs hidden operations and parameter overrides" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try observationYaml(&fixture);
    for ([_][2][]const u8{
        .{ "use: validate-provider-invocation-observation,", "use: hidden-provider-validator," },
        .{ "use: validate-provider-invocation-observation,", "use: validate-provider-invocation-observation, with: {slot: selected}," },
        .{ "use: validate-provider-invocation-observation,", "use: validate-provider-invocation-observation, with: {retry-limit: 1}," },
        .{ "use: validate-provider-invocation-observation,", "use: validate-provider-invocation-observation, with: {timeout-ms: 2}," },
        .{ "use: validate-provider-invocation-observation,", "use: validate-provider-invocation-observation, with: {result-schema: result}," },
        .{ "use: invoke-model, on: {ok: validate-response, failed: validate-response, cancelled: validate-response}", "use: core.noop, on: {ok: validate-response}" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
}

test "observation validation releases all references on every allocation failure" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try observationYaml(&fixture));
    try std.testing.checkAllAllocationFailures(std.testing.allocator, invocationAllocationCase, .{ &fixture, graph });
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
}

test "rejected validation deltas and runtime cancellation release evidence without changing usage" {
    for ([_]bool{ false, true }) |cancel| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try observationYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var spy: ObservationDeltaSpy = .{ .inner = &fixture.native.validate_observation, .cancel = cancel };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, observation_workflow.Validate.contract.id)) {
            entry.binding = bindings.bind(ObservationDeltaSpy, &spy, ObservationDeltaSpy.invoke);
        };
        try prepareInvocable(&runner);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "call" }).outcome);
        runner.runtime = .{ .context = &spy, .status_fn = ObservationDeltaSpy.status };
        const original_request = try currentRequest(&runner);
        const original_response = try invocationResult(&runner);
        const outcome = runner.bindings().invokeStep(.{ .bytes = "validate-response" });
        if (cancel) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.authority, outcome.rejected);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(observation_workflow.schema.key)] == null);
        try std.testing.expect(try currentRequest(&runner) == original_request);
        try std.testing.expect(try invocationResult(&runner) == original_response);
        try std.testing.expectEqualStrings("not JSON; still untrusted", original_response.outcome().?.observation.completed.raw_result.complete.content.bytes);
        try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
    }
}

const ObservationDeltaSpy = struct {
    inner: *observation_workflow.Validate,
    cancel: bool,
    invoked: bool = false,

    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var candidate = try observation_workflow.Validate.invoke(self.inner, input);
        self.invoked = true;
        if (!self.cancel) candidate.delta.data_invalidations.insert(.prepared_model_request);
        return candidate;
    }

    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *const @This() = @ptrCast(@alignCast(context.?));
        return if (self.invoked and self.cancel) .cancelled else .active;
    }
};

test "compiled observation validation cannot hide its dependencies or add a capability" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try observationYaml(&fixture));
    for (0..3) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, observation_workflow.Validate.contract.id)) {
            switch (variant) {
                0 => step.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .provider_invocation_result },
                1 => step.capabilities = &.{"model-provider"},
                2 => step.invalidates = &.{.provider_invocation_result},
                else => unreachable,
            }
        };
        tampered.authority.steps = steps;
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(fixture.arena.allocator(), &.{tampered}));
        var runner = fixture.runner(&tampered, std.testing.allocator);
        defer runner.deinit();
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "validate-response" }).rejected);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(observation_workflow.schema.key)] == null);
    }
}

pub fn invocationProvider(runner: *runner_module.Runner, allocator: std.mem.Allocator) fake_provider.FakeLLMProvider {
    return .{
        .allocator = allocator,
        .authorization_leases = .{ .context = @ptrCast(runner), .clock = runner.provider_clock.?, .runtime = runner.runtime, .consume_fn = consumeInvocationLease },
        .count_plan = .{ .counted = 0 },
        .invocation_plan = .{ .complete = .{ .content = "not JSON; still untrusted", .input_tokens = 5, .output_tokens = 2 } },
    };
}

fn consumeInvocationLease(context: *lease_port.Context, reference: *const provider.ValidatedProviderAuthorizationLeaseRef, selected: *const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding, request: *const provider.IdentifiedProviderNeutralModelRequest, invoked: *const provider.InvokedProviderOperation, now: lease_port.Error!u64) lease_port.Error!lease_port.Capability {
    const runner: *runner_module.Runner = @ptrCast(@alignCast(context));
    const state = if (runner.model_accounting) |*value| value else return error.AuthorizationDenied;
    const port = state.authorization_leases.port(runner.provider_clock.?, runner.runtime);
    return port.consume_fn(port.context, reference, selected, request, invoked, now);
}

fn countYaml(fixture: *Fixture, close_request: bool) ![]const u8 {
    const allocator = fixture.arena.allocator();
    var source = try invocationYaml(fixture);
    source = try std.mem.replaceOwned(u8, allocator, source, "kind: inference", "kind: input-token-count");
    source = try std.mem.replaceOwned(u8, allocator, source, "use: invoke-model, on: {ok: observe, failed: end.failed, cancelled: end.cancelled}", "use: count-model-input-tokens, on: {ok: validate-count, failed: validate-count, cancelled: validate-count}");
    fixture.entries[fixture.entries.len - 1].contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .provider_token_count_validation_result };
    source = try std.fmt.allocPrint(allocator, "{s}\n  validate-count: {{ use: validate-model-token-count-observation, on: {{ok: complete-count, failed: complete-count, cancelled: complete-count}} }}\n  complete-count: {{ use: complete-count-operation, on: {{ok: observe, failed: {s}, cancelled: {s}}} }}\n", .{ source, if (close_request) "close-count" else "end.failed", if (close_request) "close-count" else "end.cancelled" });
    return if (close_request) std.fmt.allocPrint(allocator, "{s}\n  close-count: {{ use: complete-count-request, on: {{failed: end.failed, cancelled: end.cancelled}} }}\n", .{source}) else source;
}

fn countObservation(runner: *const runner_module.Runner) !*const count_observation.Result {
    return values.read(&.{ .slots = runner.envelope.slots }, count_observation.schema, count_observation.Result);
}

fn prepareCountCompletion(runner: *runner_module.Runner, outcome: workflow.OutcomeTag) !void {
    try prepareInvocable(runner);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
    for ([_][]const u8{ "call", "validate-count" }) |step|
        try std.testing.expectEqual(outcome, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
}

const count_plans = [_]fake_provider.CountPlan{
    .{ .counted = 0 },
    .{ .counted = std.math.maxInt(u64) },
    .{ .failed = .{ .cause = .request_rejected, .retry_class = .never, .delivery = .not_sent } },
    .{ .failed = .{ .cause = .transport_failed, .retry_class = .policy_eligible, .delivery = .accepted_or_unknown } },
    .cancelled,
};

test "YAML count path preserves exact counts failures and cancellation without charging or accepting requests" {
    for (count_plans) |plan| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try countYaml(&fixture, true));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.count_plan = plan;
        fixture.native.count_model_input.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        const expected: workflow.OutcomeTag = switch (plan) {
            .counted => .ok,
            .failed => .failed,
            .cancelled => .cancelled,
        };
        try std.testing.expectEqual(expected, harness.run());
        try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
        try std.testing.expectEqual(@as(usize, 1), fake.effect_count);
        try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
        const source = try countObservation(&runner);
        const request = try currentRequest(&runner);
        const terminal = (try completedOperation(&runner)).record();
        try std.testing.expect(terminal.id.eql(source.operationId()));
        try runner.model_accounting.?.current_operations.validateRequestClosure(request.id());
        const record = (try requestLedger(&runner)).record(request.id()).?;
        switch (plan) {
            .counted => |count| {
                const evidence = source.outcome().validated.counted;
                try std.testing.expect(evidence.count_operation_id.eql(terminal.id));
                try std.testing.expect(evidence.binding_id.eql(request.prepared().?.binding_id));
                try std.testing.expect(evidence.model_visible_input_id.eql(request.prepared().?.model_visible_input_id));
                try std.testing.expectEqual(count, terminal.state.terminal.counted);
                try std.testing.expectEqual(count, evidence.input_tokens);
                try std.testing.expectEqual(.invoked, record.status);
            },
            .failed => |failure| {
                try std.testing.expectEqualDeep(failure.cause, source.outcome().validated.failed.cause);
                try std.testing.expectEqualDeep(failure.cause, terminal.state.terminal.failed.cause);
                try std.testing.expectEqual(failure.delivery, terminal.state.terminal.failed.delivery);
                try std.testing.expectEqual(.failed, record.terminal_reason.?);
            },
            .cancelled => {
                try std.testing.expectEqual(.cancelled, source.outcome());
                try std.testing.expectEqual(.accepted_or_unknown, terminal.state.terminal.cancelled);
                try std.testing.expectEqual(.cancelled, record.terminal_reason.?);
            },
        }
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
        try std.testing.expectEqual(@as(u64, 0), runner.token_accounting.current().revision().value);
    }
}

test "YAML count completion rejects missing foreign stale and duplicate evidence" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try countYaml(&fixture, true));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var first_fake = invocationProvider(&first, std.testing.allocator);
    var second_fake = invocationProvider(&second, std.testing.allocator);
    for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &first_fake, &second_fake }) |runner, fake| {
        fixture.native.count_model_input.action = .{ .provider = fake.interface() };
        try prepareCountCompletion(runner, .ok);
    }
    const original = first.model_accounting.?.current_operations;
    for (completion_workflow.CompleteCount.contract.requires) |key| {
        const index = @intFromEnum(key);
        const saved = first.envelope.slots[index];
        first.envelope.slots[index] = null;
        const missing = first.bindings().invokeStep(.{ .bytes = "complete-count" });
        first.envelope.slots[index] = saved;
        try std.testing.expectEqual(.authority, missing.rejected);
        std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
        const foreign = first.bindings().invokeStep(.{ .bytes = "complete-count" });
        std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
        try std.testing.expectEqual(.authority, foreign.rejected);
        try std.testing.expect(original == first.model_accounting.?.current_operations);
    }
    const invoked_key = @intFromEnum(attempt_values.invoked_schema.key);
    const old_invoked = try values.retain(first.envelope.slots[invoked_key].?);
    try std.testing.expectEqual(.ok, first.bindings().invokeStep(.{ .bytes = "complete-count" }).outcome);
    const completed = first.model_accounting.?.current_operations;
    try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "complete-count" }).rejected);
    first.envelope.slots[invoked_key] = old_invoked;
    try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "complete-count" }).rejected);
    try std.testing.expect(completed == first.model_accounting.?.current_operations);
    // An exact successful count still cannot accept the logical request.
    try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "close-count" }).rejected);
    try std.testing.expectEqual(.invoked, (try requestLedger(&first)).record((try currentRequest(&first)).id()).?.status);
}

test "YAML count request closure rejects missing foreign stale and duplicate evidence" {
    for ([_]bool{ false, true }) |cancelled| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try countYaml(&fixture, true));
        var first = fixture.runner(graph, std.testing.allocator);
        defer first.deinit();
        var second = fixture.runner(graph, std.testing.allocator);
        defer second.deinit();
        var first_fake = invocationProvider(&first, std.testing.allocator);
        var second_fake = invocationProvider(&second, std.testing.allocator);
        const outcome: workflow.OutcomeTag = if (cancelled) .cancelled else .failed;
        for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &first_fake, &second_fake }) |runner, fake| {
            fake.count_plan = if (cancelled) .cancelled else count_plans[2];
            fixture.native.count_model_input.action = .{ .provider = fake.interface() };
            try prepareCountCompletion(runner, outcome);
            try std.testing.expectEqual(outcome, runner.bindings().invokeStep(.{ .bytes = "complete-count" }).outcome);
        }
        const original = try values.retain(first.envelope.slots[@intFromEnum(requests.ledger_schema.key)].?);
        defer values.destroy(original);
        for (request_completion.CompleteCount.contract.requires) |key| {
            const index = @intFromEnum(key);
            const saved = first.envelope.slots[index];
            first.envelope.slots[index] = null;
            const missing = first.bindings().invokeStep(.{ .bytes = "close-count" });
            first.envelope.slots[index] = saved;
            try std.testing.expectEqual(.authority, missing.rejected);
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            const foreign = first.bindings().invokeStep(.{ .bytes = "close-count" });
            std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[index], &second.envelope.slots[index]);
            try std.testing.expectEqual(.authority, foreign.rejected);
            try std.testing.expect(first.envelope.slots[@intFromEnum(requests.ledger_schema.key)] == original);
        }
        try std.testing.expectEqual(outcome, first.bindings().invokeStep(.{ .bytes = "close-count" }).outcome);
        try std.testing.expectEqual(.authority, first.bindings().invokeStep(.{ .bytes = "close-count" }).rejected);
        const closed = first.envelope.slots[@intFromEnum(requests.ledger_schema.key)];
        first.envelope.slots[@intFromEnum(requests.ledger_schema.key)] = original;
        const stale = first.bindings().invokeStep(.{ .bytes = "close-count" });
        first.envelope.slots[@intFromEnum(requests.ledger_schema.key)] = closed;
        try std.testing.expectEqual(.authority, stale.rejected);
    }
}

test "YAML count validation rejects foreign raw results without fabricating completion" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try countYaml(&fixture, true));
    var first = fixture.runner(graph, std.testing.allocator);
    defer first.deinit();
    var second = fixture.runner(graph, std.testing.allocator);
    defer second.deinit();
    var first_fake = invocationProvider(&first, std.testing.allocator);
    var second_fake = invocationProvider(&second, std.testing.allocator);
    for ([_]*runner_module.Runner{ &first, &second }, [_]*fake_provider.FakeLLMProvider{ &first_fake, &second_fake }) |runner, fake| {
        fixture.native.count_model_input.action = .{ .provider = fake.interface() };
        try prepareInvocable(runner);
        for ([_][]const u8{ "advance-operation", "call" }) |step| try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
    }
    const key = @intFromEnum(model_invocation.count_schema.key);
    std.mem.swap(?*@import("domain/pipeline_data.zig").Value, &first.envelope.slots[key], &second.envelope.slots[key]);
    for ([_]*runner_module.Runner{ &first, &second }) |runner| {
        try std.testing.expectEqual(.failed, runner.bindings().invokeStep(.{ .bytes = "validate-count" }).outcome);
        try std.testing.expectEqual(error.ModelTokenCountAssociationInvalid, (try countObservation(runner)).outcome().rejected);
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-count" }).rejected);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    }
}

test "YAML count validation reuses exact operation binding and input checks" {
    for (0..5) |variant| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try countYaml(&fixture, true));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.count_model_input.action = .{ .provider = fake.interface() };
        try prepareInvocable(&runner);
        for ([_][]const u8{ "advance-operation", "call" }) |step| try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        const raw = try values.read(&.{ .slots = runner.envelope.slots }, model_invocation.count_schema, count_result.Result);
        var faulty = raw.outcome().?.observation;
        switch (variant) {
            0 => faulty.counted.operation_id.kind = .inference,
            1 => faulty.counted.operation_id.model_attempt_ordinal.value += 1,
            2 => faulty.counted.binding_id.slot_id.bytes = "foreign",
            3 => faulty.counted.model_visible_input_id.bytes = "foreign",
            4 => {
                faulty = .{ .failed = .{ .operation_id = raw.operationId(), .cause = .request_rejected, .retry_class = .never, .delivery = .not_sent } };
                faulty.failed.operation_id.model_attempt_ordinal.value += 1;
            },
            else => unreachable,
        }
        const owner = try count_result.Owner.init(std.testing.allocator, try requestLedger(&runner), raw.operationId());
        owner.finish(.{ .observation = faulty });
        const value = values.adopt(std.testing.allocator, model_invocation.count_schema, count_result.Result, count_result.Owner, owner, count_result.Owner.view, count_result.Owner.destroy, null) catch |err| {
            owner.destroy();
            return err;
        };
        const key = @intFromEnum(model_invocation.count_schema.key);
        values.destroy(runner.envelope.slots[key].?);
        runner.envelope.slots[key] = value;
        try std.testing.expectEqual(.failed, runner.bindings().invokeStep(.{ .bytes = "validate-count" }).outcome);
        try std.testing.expectEqual(error.ModelTokenCountAssociationInvalid, (try countObservation(&runner)).outcome().rejected);
        try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "complete-count" }).rejected);
        try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
        try std.testing.expectEqual(@as(u64, 0), runner.tokenLedger().revision().value);
    }
}

test "count YAML rejects undeclared inputs overrides hidden operations and false acceptance" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const source = try countYaml(&fixture, true);
    for ([_][]const u8{ "count-model-input-tokens", "validate-model-token-count-observation", "complete-count-operation", "complete-count-request" }) |id| {
        const needle = try std.fmt.allocPrint(fixture.arena.allocator(), "use: {s},", .{id});
        for ([_][]const u8{ "count: 1", "outcome: counted", "slot: selected", "timeout-ms: 1", "retry-limit: 1" }) |parameter| {
            const replacement = try std.fmt.allocPrint(fixture.arena.allocator(), "use: {s}, with: {{{s}}},", .{ id, parameter });
            const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, needle, replacement);
            try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
        }
        const hidden = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, needle, "use: test.hidden-count,");
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(hidden));
    }
    for ([_][2][]const u8{
        .{ "use: count-model-input-tokens, on: {ok: validate-count, failed: validate-count, cancelled: validate-count}", "use: core.noop, on: {ok: validate-count}" },
        .{ "use: validate-model-token-count-observation, on: {ok: complete-count, failed: complete-count, cancelled: complete-count}", "use: core.noop, on: {ok: complete-count}" },
        .{ "use: complete-count-request, on: {failed: end.failed, cancelled: end.cancelled}", "use: complete-count-request, on: {ok: end.ok, failed: end.failed, cancelled: end.cancelled}" },
    }) |change| {
        const changed = try std.mem.replaceOwned(u8, fixture.arena.allocator(), source, change[0], change[1]);
        try std.testing.expectError(error.WorkflowGraphCompileInvalid, fixture.compile(changed));
    }
}

test "YAML count raw result and validation independently retain their original request owners" {
    for ([_]pipeline.DataKey{ .provider_token_count_result, .provider_token_count_validation_result }) |key| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try countYaml(&fixture, true));
        var runner = fixture.runner(graph, std.testing.allocator);
        var active = true;
        defer if (active) runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.count_plan = .{ .counted = 47 };
        fixture.native.count_model_input.action = .{ .provider = fake.interface() };
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.ok, harness.run());
        const retained = try values.retain(runner.envelope.slots[@intFromEnum(key)].?);
        defer values.destroy(retained);
        const request = try currentRequest(&runner);
        const raw = try values.read(&.{ .slots = runner.envelope.slots }, model_invocation.count_schema, count_result.Result);
        const validated = try countObservation(&runner);
        runner.deinit();
        active = false;
        const operation_id = if (key == .provider_token_count_result) raw.operationId() else validated.operationId();
        try std.testing.expect(operation_id.model_request_id == request.id());
        const count = if (key == .provider_token_count_result) raw.outcome().?.observation.counted.input_tokens else validated.outcome().validated.counted.input_tokens;
        try std.testing.expectEqual(@as(u64, 47), count);
        try std.testing.expectEqualStrings(schema_bytes, request.prepared().?.response_schema.bytes());
        try std.testing.expectEqualStrings("selected", request.binding().bindingId().slot_id.bytes);
    }
}

test "YAML count and validation release ownership at every allocation failure" {
    for (count_plans) |plan| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try countYaml(&fixture, true));
        try std.testing.checkAllAllocationFailures(std.testing.allocator, countAllocationCase, .{ &fixture, graph, plan });
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
    }
}

fn countAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, plan: fake_provider.CountPlan) !void {
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, allocator);
    fake.count_plan = plan;
    fixture.native.count_model_input.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    try std.testing.expect(fake.effect_count <= 1);
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    const terminal = runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)];
    if (terminal == null) {
        try std.testing.expectEqual(.failed, outcome);
        return error.OutOfMemory;
    }
    const request_closed = (try requestLedger(&runner)).record((try currentRequest(&runner)).id()).?.status == .terminal;
    if (plan != .counted and !request_closed) {
        try std.testing.expectEqual(.failed, outcome);
        return error.OutOfMemory;
    }
    try std.testing.expectEqual(@as(workflow.OutcomeTag, switch (plan) {
        .counted => .ok,
        .failed => .failed,
        .cancelled => .cancelled,
    }), outcome);
}

test "YAML count cannot reuse authorization and never marks missing inference usage" {
    for ([_]bool{ false, true }) |expired| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try countYaml(&fixture, false));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.count_model_input.action = .{ .provider = fake.interface() };
        try prepareInvocable(&runner);
        try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
        if (expired) {
            fixture.clock.now_ms = (try invokedOperation(&runner)).operation().deadline_monotonic_ms;
            try std.testing.expectEqual(.deadline_exhausted, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected);
        } else {
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "call" }).outcome);
            try std.testing.expectEqual(.authority, runner.bindings().invokeStep(.{ .bytes = "call" }).rejected);
        }
        try std.testing.expectEqual(@as(usize, if (expired) 0 else 1), fake.count_call_count);
        try std.testing.expectEqual(.available, runner.tokenLedger().status());
        try std.testing.expectEqual(@as(u64, 0), runner.tokenLedger().revision().value);
    }
}

test "YAML count cancellation at every boundary releases owners without hidden completion" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try countYaml(&fixture, true));
    for (0..13) |boundary| {
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
        runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
        var fake = invocationProvider(&runner, std.testing.allocator);
        fixture.native.count_model_input.action = .{ .provider = fake.interface() };
        try std.testing.expectEqual(.cancelled, harness.run());
        try std.testing.expectEqual(@as(u64, 0), runner.tokenLedger().revision().value);
        if (boundary <= 11) try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
    }
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
}

test "YAML counts then independently authorizes inference on the same attempt and charges only usage" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try countInferenceYaml(&fixture));
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var fake = invocationProvider(&runner, std.testing.allocator);
    fake.count_plan = .{ .counted = std.math.maxInt(u64) };
    fake.invocation_plan.complete.content = "{\"answer\":\"same request\"}";
    fixture.native.invoke_model.action = .{ .provider = fake.interface() };
    fixture.native.count_model_input.action = .{ .provider = fake.interface() };
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 2), fixture.authorization.prepared_count);
    try std.testing.expectEqual(@as(usize, 2), fixture.authorization.destroyed_count);
    try std.testing.expectEqual(@as(u128, 7), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
    const counted = (try countObservation(&runner)).outcome().validated.counted;
    const inferred = (try completedOperation(&runner)).record().id;
    try std.testing.expect(counted.count_operation_id.model_request_id == inferred.model_request_id);
    try std.testing.expectEqual(counted.count_operation_id.model_attempt_ordinal.value, inferred.model_attempt_ordinal.value);
    try std.testing.expectEqual(.accepted, (try requestLedger(&runner)).record(inferred.model_request_id).?.terminal_reason.?);
    try runner.model_accounting.?.current_operations.validateRequestClosure(inferred.model_request_id);
}

fn countInferenceYaml(fixture: *Fixture) ![]const u8 {
    const allocator = fixture.arena.allocator();
    var source = try countYaml(fixture, false);
    source = try std.mem.replaceOwned(u8, allocator, source, "on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled }", "on: { ok: assign-inference, failed: end.failed, cancelled: end.cancelled }");
    source = try std.fmt.allocPrint(allocator, "{s}\n  assign-inference: {{ use: assign-provider-operation, with: {{kind: inference}}, on: {{ok: authorize-inference, failed: end.failed}} }}\n" ++
        "  authorize-inference: {{ use: prepare-provider-operation-authorization, with: {{timeout-ms: 100}}, on: {{ok: advance-inference, failed: end.failed, cancelled: end.cancelled}} }}\n" ++
        "  advance-inference: {{ use: advance-provider-operation-lifecycle, with: {{transition: invoked}}, on: {{ok: infer, failed: end.failed}} }}\n" ++
        "  infer: {{ use: invoke-model, on: {{ok: validate-response, failed: validate-response, cancelled: validate-response}} }}\n" ++
        "  validate-response: {{ use: validate-provider-invocation-observation, on: {{ok: complete-inference, failed: complete-inference, cancelled: complete-inference}} }}\n" ++
        "  complete-inference: {{ use: complete-provider-operation, on: {{ok: decode, failed: decode, cancelled: decode}} }}\n" ++
        "  decode: {{ use: decode-model-envelope, on: {{ok: validate-payload, invalid: validate-payload, failed: validate-payload, cancelled: validate-payload}} }}\n" ++
        "  validate-payload: {{ use: validate-model-payload-schema, on: {{ok: close-request, invalid: close-request, failed: close-request, cancelled: close-request}} }}\n" ++
        "  close-request: {{ use: complete-model-request, on: {{ok: end.ok, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled}} }}\n", .{source});
    fixture.entries[fixture.entries.len - 1].contract.invalidates = &.{ .terminal_provider_operation, .provider_authorization_result };
    fixture.observer.release_terminal = true;
    return source;
}

test "YAML count retries follow explicit edges and operation-local limits" {
    for ([_]bool{ false, true }) |failed| {
        for ([_]bool{ false, true }) |exhaust| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            const allocator = fixture.arena.allocator();
            var source = try countYaml(&fixture, false);
            source = try std.mem.replaceOwned(u8, allocator, source, "retry-limit: 0", "retry-limit: 1");
            source = try std.mem.replaceOwned(u8, allocator, source, "ok: advance-request", "ok: route-request");
            source = try std.mem.replaceOwned(u8, allocator, source, "on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled }", "on: { ok: end.ok, invalid: account, failed: end.failed, cancelled: end.cancelled }");
            source = try std.mem.replaceOwned(u8, allocator, source, "use: complete-count-operation, on: {ok: observe, failed: end.failed, cancelled: end.cancelled}", "use: complete-count-operation, on: {ok: observe, failed: observe, cancelled: observe}");
            source = try std.fmt.allocPrint(allocator, "{s}\n  route-request: {{ use: test.route-request, on: {{ok: advance-request, invalid: advance-operation}} }}\n", .{source});
            var controller: CountRetry = .{ .retry_until = if (exhaust) 3 else 2 };
            const observer = &fixture.entries[fixture.entries.len - 1];
            observer.contract.requires = &.{ .model_request_identity_ledger, .prepared_model_request, .accounted_model_attempt, .terminal_provider_operation, .provider_token_count_validation_result };
            observer.contract.outcomes = &.{ .ok, .invalid, .failed, .cancelled };
            observer.contract.invalidates = &CountRetry.released;
            observer.binding = bindings.bind(CountRetry, &controller, CountRetry.invoke);
            var entries = fixture.entries ++ [_]operations.Entry{.{
                .contract = .{ .id = "test.route-request", .kind = .step, .requires = &.{ .model_request_identity_ledger, .prepared_model_request }, .outcomes = &.{ .ok, .invalid }, .side_effect = .none },
                .binding = bindings.bind(void, null, routeInvokedRequest),
            }};
            fixture.registry.operations = &entries;
            const graph = try fixture.compile(source);
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var fake = invocationProvider(&runner, std.testing.allocator);
            fake.count_plan = if (failed) count_plans[3] else .{ .counted = 100 };
            fixture.native.count_model_input.action = .{ .provider = fake.interface() };
            var harness: Harness = .{ .runner = &runner };
            try std.testing.expectEqual(@as(workflow.OutcomeTag, if (failed or exhaust) .failed else .ok), harness.run());
            try std.testing.expectEqual(@as(usize, 2), fake.count_call_count);
            try std.testing.expectEqual(@as(usize, 2), fixture.authorization.prepared_count);
            try std.testing.expectEqual(@as(usize, 2), fixture.authorization.destroyed_count);
            const request = try currentRequest(&runner);
            try std.testing.expectEqual(@as(u32, 2), attempt_accounting.accounting(runner.model_accounting.?.attempts).attemptsReserved(request.id()));
            try runner.model_accounting.?.current_operations.validateRequestClosure(request.id());
            try std.testing.expectEqual(@as(u64, 0), runner.tokenLedger().revision().value);
        }
    }
}

const CountRetry = struct {
    const released = [_]pipeline.DataKey{ .accounted_model_attempt, .terminal_provider_operation, .provider_authorization_result, .provider_token_count_result, .provider_token_count_validation_result };
    retry_until: u32,
    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const counted = try count_observation.readCurrent(&input.step.data);
        const attempt = values.read(&input.step.data, attempt_values.schema, attempt_accounting.AccountedAttempt) catch return error.OperationExecutionFailed;
        var delta: pipeline.NodeDelta = .{};
        for (released) |key| delta.data_invalidations.insert(key);
        return .{ .outcome = if (attempt.ordinal().value < self.retry_until) .invalid else count_observation.status(counted), .delta = delta };
    }
};

fn routeInvokedRequest(_: ?*void, input: operations.Input) operations.Error!execution.Candidate {
    const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
    const ledger = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
    return .{ .outcome = if (ledger.record(request.id()).?.status == .assigned) .ok else .invalid, .delta = .{} };
}

const Observer = struct {
    calls: usize = 0,
    last_attempt: u32 = 0,
    retry_until: u32 = 1,
    consume_attempt: bool = false,
    consume_operation: bool = false,
    release_terminal: bool = false,
    expected_request_status: ?identity.RequestStatus = null,
    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        if (request.prepared() == null or input.step.model_binding != request.binding()) return error.OperationExecutionFailed;
        if (self.expected_request_status) |expected| {
            const current = values.read(&input.step.data, requests.ledger_schema, identity.ModelRequestIdentityLedger) catch return error.OperationExecutionFailed;
            if (current.record(request.id()).?.status != expected) return error.OperationExecutionFailed;
        }
        self.calls += 1;
        if (input.step.data.contains(observation_workflow.schema.key)) {
            const result = values.read(&input.step.data, observation_workflow.schema, observation_workflow.Result) catch return error.OperationExecutionFailed;
            const evidence = switch (result.outcome()) {
                .validated => |evidence| evidence,
                .rejected, .cancelled => return error.OperationExecutionFailed,
            };
            if (evidence.result() != .complete or evidence.request() != request.prepared().?) return error.OperationExecutionFailed;
        }
        if (input.step.data.contains(envelope_workflow.schema.key)) {
            const result = values.read(&input.step.data, envelope_workflow.schema, envelope_workflow.Result) catch return error.OperationExecutionFailed;
            const decoded = switch (result.outcome()) {
                .decoded => |candidate| candidate,
                .protocol_rejected, .not_decoded => return error.OperationExecutionFailed,
            };
            if (decoded.association().request() != request.prepared().?) return error.OperationExecutionFailed;
        }
        if (input.step.data.contains(payload_workflow.schema.key)) {
            const result = values.read(&input.step.data, payload_workflow.schema, payload_workflow.Result) catch return error.OperationExecutionFailed;
            const evidence = switch (result.outcome()) {
                .valid => |evidence| evidence,
                .schema_rejected, .not_validated => return error.OperationExecutionFailed,
            };
            if (evidence.candidate().association().request() != request.prepared().?) return error.OperationExecutionFailed;
        }
        var delta: pipeline.NodeDelta = .{};
        if (self.release_terminal) {
            delta.data_invalidations.insert(.terminal_provider_operation);
            delta.data_invalidations.insert(.provider_authorization_result);
        }
        if (input.step.data.slots[@intFromEnum(pipeline.DataKey.accounted_model_attempt)] != null) {
            const evidence = values.read(&input.step.data, attempt_values.schema, attempt_accounting.AccountedAttempt) catch return error.OperationExecutionFailed;
            if (evidence.requestId() != request.id()) return error.OperationExecutionFailed;
            self.last_attempt = evidence.ordinal().value;
            if (self.consume_attempt) delta.data_invalidations.insert(.accounted_model_attempt);
        }
        if (input.step.data.contains(.assigned_provider_operation)) {
            const evidence = values.read(&input.step.data, attempt_values.operation_schema, lifecycle.AssignedOperation) catch return error.OperationExecutionFailed;
            const record = evidence.record();
            if (record.id.model_request_id != request.id() or record.id.model_attempt_ordinal.value != self.last_attempt or
                !record.binding_id.eql(request.prepared().?.binding_id) or !record.model_visible_input_id.eql(request.prepared().?.model_visible_input_id) or record.state != .assigned) return error.OperationExecutionFailed;
            if (self.consume_operation) delta.data_invalidations.insert(.assigned_provider_operation);
        }
        if (input.step.data.contains(.invoked_provider_operation)) {
            const evidence = (values.read(&input.step.data, attempt_values.invoked_schema, lifecycle.InvokedOperation) catch return error.OperationExecutionFailed).operation();
            if (evidence.id.model_request_id != request.id() or evidence.id.model_attempt_ordinal.value != self.last_attempt) return error.OperationExecutionFailed;
        }
        if (input.step.data.contains(.provider_authorization_result)) {
            const result = values.read(&input.step.data, authorization_workflow.schema, authorization_result.Result) catch return error.OperationExecutionFailed;
            switch (result.outcome().*) {
                .prepared => {},
                .failed => return .{ .outcome = .failed, .delta = delta },
                .cancelled => return .{ .outcome = .cancelled, .delta = delta },
            }
        }
        return .{ .outcome = if (self.last_attempt != 0 and self.last_attempt < self.retry_until) .invalid else .ok, .delta = delta };
    }
};

const composition_yaml =
    \\schema: workflow/v1
    \\id: compose-address
    \\version: 1
    \\shortcode: PART
    \\invoke: core.empty-invocation
    \\policy: core.model-inference@1
    \\start: initialize
    \\resources: {prompt: prompt.md, result: result.json, composition: composition.json}
    \\steps:
    \\  initialize: {use: build-initial-model-request-identity-ledger, on: {ok: input, failed: end.failed}}
    \\  input: {use: test.select-unit, on: {ok: begin, failed: end.failed}}
    \\  begin: {use: initialize-json-composition, with: {composition: composition}, on: {ok: street, failed: end.failed}}
    \\  street: {call: part, with: {part: street}, on: {ok: flags, failed: end.failed, invalid: end.invalid, cancelled: end.cancelled}}
    \\  flags: {call: part, with: {part: flags}, on: {ok: zip, failed: end.failed, invalid: end.invalid, cancelled: end.cancelled}}
    \\  zip: {call: part, with: {part: zip}, on: {ok: assemble, failed: end.failed, invalid: end.invalid, cancelled: end.cancelled}}
    \\  assemble: {use: assemble-json, on: {ok: validate, failed: end.failed}}
    \\  validate: {use: validate-assembled-json, on: {ok: observe, failed: end.failed}}
    \\  observe: {use: test.observe-request, on: {ok: end.ok}}
    \\subgraphs:
    \\  part:
    \\    start: prepare
    \\    steps:
    \\      prepare: {use: prepare-model-request, with: {slot: selected, prompt: prompt, protocol-prompt: prompt, composition-part: {param: part}}, on: {ok: account, failed: end.failed}}
    \\      account: {use: advance-model-attempt-accounting, with: {retry-limit: 2}, on: {ok: operation, failed: end.failed}}
    \\      operation: {use: assign-provider-operation, with: {kind: inference}, on: {ok: authorize, failed: end.failed}}
    \\      authorize: {use: prepare-provider-operation-authorization, with: {timeout-ms: 1000}, on: {ok: phase, failed: end.failed, cancelled: end.cancelled}}
    \\      phase: {use: check-model-request-phase, on: {ok: advance-request, more: advance-operation, failed: end.failed}}
    \\      advance-request: {use: advance-model-request-lifecycle, with: {transition: invoked}, on: {ok: advance-operation, failed: end.failed}}
    \\      advance-operation: {use: advance-provider-operation-lifecycle, with: {transition: invoked}, on: {ok: call, failed: end.failed}}
    \\      call: {use: invoke-model, on: {ok: observation, failed: observation, cancelled: observation}}
    \\      observation: {use: validate-provider-invocation-observation, on: {ok: complete, failed: complete, cancelled: complete}}
    \\      complete: {use: complete-provider-operation, on: {ok: admit, failed: admit, cancelled: admit}}
    \\      admit: {use: admit-model-response, on: {ok: close, invalid: retry, failed: close, cancelled: close}}
    \\      retry: {use: build-model-protocol-retry, on: {ok: account, failed: end.failed}}
    \\      close: {use: complete-model-request, on: {ok: retain, invalid: end.invalid, failed: end.failed, cancelled: end.cancelled}}
    \\      retain: {use: retain-json-part, on: {ok: retire, failed: end.failed}}
    \\      retire: {use: retire-model-request, on: {ok: end.ok, failed: end.failed}}
;
const address_schema =
    \\{"type":"object","properties":{"address":{"type":"object","properties":{"street":{"type":"string","maxLength":100},"zip":{"type":"string","maxLength":20}},"required":["street","zip"],"additionalProperties":false},"flags":{"type":"array","maxItems":3,"items":{"type":"boolean"}}},"required":["address","flags"],"additionalProperties":false}
;
const address_composition =
    \\{"schema":"json-composition/v1","result":"result","parts":{"street":{"paths":["/address/street"]},"zip":{"paths":["/address/zip"],"requires":["street"]},"flags":{"paths":["/flags"]}}}
;

test "configured parts keep admitted siblings through protocol recovery and exhaustion with exact accounting" {
    for ([_]bool{ false, true }) |missing_answer| {
        for ([_]bool{ false, true }) |recover| {
            var fixture: Fixture = undefined;
            try fixture.init(std.testing.allocator);
            defer fixture.deinit();
            var input: ProtocolUnits = .{};
            fixture.entries[fixture.entries.len - 1] = .{
                .contract = .{ .id = "test.observe-request", .kind = .step, .requires = &.{ .assembled_json, .validated_assembled_json }, .outcomes = &.{.ok}, .side_effect = .none },
                .binding = bindings.bind(void, null, CompositionCalls.observe),
            };
            var entries = fixture.entries ++ [_]operations.Entry{.{
                .contract = .{ .id = "test.select-unit", .kind = .step, .produces = &.{.model_input_packet}, .outcomes = &.{ .ok, .failed }, .side_effect = .none },
                .binding = bindings.bind(ProtocolUnits, &input, ProtocolUnits.select),
            }};
            fixture.registry.operations = &entries;
            const source_yaml = composition_yaml ++ "\n# source-secret\n";
            var source_graph = (try fixture.compileResources(source_yaml, address_schema, false, address_composition)).*;
            source_graph.source = .{ .path = "request.workflow.yaml", .content = source_yaml };
            const graph = &source_graph;
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            var snapshots: std.ArrayList(@import("domain/request_source_snapshot.zig").Snapshot) = .empty;
            var calls: CompositionCalls = .{
                .fake = invocationProvider(&runner, std.testing.allocator),
                .recover = recover,
                .missing_answer = missing_answer,
                .source_observer = .{ .runner = &runner, .allocator = fixture.arena.allocator(), .snapshots = &snapshots },
            };
            fixture.native.invoke_model.action = .{ .provider = calls.interface() };
            var harness: Harness = .{ .runner = &runner };
            try std.testing.expectEqual(@as(workflow.OutcomeTag, if (recover) .ok else .failed), harness.run());
            try std.testing.expectEqual(@as(usize, 5), calls.fake.effect_count);
            try std.testing.expect(calls.consistent);
            try std.testing.expectEqual(calls.fake.effect_count, snapshots.items.len);
            for (snapshots.items) |snapshot| {
                try snapshot.validate();
                try std.testing.expect(snapshot.document.redacted);
                try std.testing.expect(std.mem.indexOf(u8, snapshot.document.content, "source-secret") == null);
                try std.testing.expectEqualStrings(snapshot.selection.part.?, snapshot.caller.chain[0].id);
                try std.testing.expectEqualStrings("part", snapshot.caller.chain[1].subgraph.?);
                try std.testing.expectEqualStrings("call", snapshot.caller.chain[1].id);
                try std.testing.expectEqualStrings("prepare", snapshot.preparation.chain[1].id);
                try std.testing.expectEqual(@as(usize, 4), snapshot.resources.len);
                try std.testing.expectEqualStrings("prompt", snapshot.resources[0].alias);
                try std.testing.expectEqualStrings("prompt", snapshot.resources[1].alias);
                try std.testing.expectEqualStrings("result.json", snapshot.resources[2].document.path);
                try std.testing.expectEqualStrings(address_schema, snapshot.resources[2].document.content);
                try std.testing.expectEqualStrings("composition.json", snapshot.resources[3].document.path);
                try std.testing.expectEqualStrings(address_composition, snapshot.resources[3].document.content);
                try std.testing.expectEqual(@as(usize, 1), snapshot.selection.paths.len);
                try std.testing.expectEqualStrings(snapshot.selection.part.?, snapshot.selection.paths[0][snapshot.selection.paths[0].len - 1]);
            }
            try std.testing.expectEqual(@as(u128, 35), runner.tokenLedger().committed());
            try std.testing.expectEqual(@as(usize, 5), runner.tokenLedger().accounted_operations.items.len);
            try std.testing.expectEqual(@as(usize, 3), (try requestLedger(&runner)).recordCount());
            const observations = try runner.retryObservations(fixture.arena.allocator());
            var seen: usize = 0;
            for (observations) |row| for (row.assignments) |assignment| {
                seen += 1;
                try std.testing.expectEqual(@as(u64, if (assignment.request.value == 3) 3 else 1), assignment.completed_executions);
            };
            try std.testing.expectEqual(@as(usize, 3), seen);
            const composition_workflow = @import("application/json_composition_workflow.zig");
            const view: @import("domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
            if (recover) {
                try std.testing.expect(!view.contains(.json_composition));
                const assembled = try composition_workflow.readValidated(&view);
                try std.testing.expectEqualStrings("{\"address\":{\"street\":\"Main St\",\"zip\":\"3050\"},\"flags\":[true,false]}", assembled.body);
                try std.testing.expectEqual(@as(usize, 1), assembled.origin.request.value);
                try std.testing.expectEqual(@as(usize, 3), assembled.producer(&.{ "address", "zip" }).?.request.value);
                try std.testing.expectEqual(@as(u32, 3), assembled.producer(&.{ "address", "zip" }).?.attempt.value);
                try std.testing.expectEqual(@as(usize, 2), assembled.producer(&.{"flags"}).?.request.value);
            } else {
                const state = try composition_workflow.readState(&view);
                try std.testing.expect(state.getEntry(0) != null and state.getEntry(2) != null and state.getEntry(1) == null);
                try std.testing.expect(!view.contains(.assembled_json));
            }
        }
    }
}

const CompositionCalls = struct {
    fake: fake_provider.FakeLLMProvider,
    recover: bool,
    missing_answer: bool = false,
    zip_request: ?*const identity.ModelRequestId = null,
    consistent: bool = true,
    source_observer: ?struct {
        runner: *runner_module.Runner,
        allocator: std.mem.Allocator,
        snapshots: *std.ArrayList(@import("domain/request_source_snapshot.zig").Snapshot),
    } = null,
    fn interface(self: *@This()) @import("ports/llm_provider_interface.zig").LLMProviderInterface {
        return .{ .context = @ptrCast(self), .vtable = &.{ .invoke = invoke, .count_input_tokens = count } };
    }
    fn invoke(context: *@import("ports/llm_provider_interface.zig").Context, selected: *const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding, request: *const provider.IdentifiedProviderNeutralModelRequest, reference: *const provider.ValidatedProviderAuthorizationLeaseRef, invoked: *const provider.InvokedProviderOperation) @import("ports/llm_provider_interface.zig").Error!provider.ProviderInvocationObservation {
        const self: *@This() = @ptrCast(@alignCast(context));
        if (self.source_observer) |observer| {
            const metadata = observer.runner.model_capture.current orelse return error.ModelLoggingBlocked;
            const snapshot = @import("application/request_source_capture.zig").snapshot(observer.allocator, metadata.source_context.?, metadata.node.bytes, &.{"source-secret"}) catch return error.ModelLoggingBlocked;
            observer.snapshots.append(observer.allocator, snapshot.?) catch return error.OutOfMemory;
        }
        const shape = request.response_schema.modelBytes();
        if (std.mem.indexOf(u8, shape, "\"street\"") != null) {
            self.fake.invocation_plan.complete.content = "{\"address\":{\"street\":\"Main St\"}}";
        } else if (std.mem.indexOf(u8, shape, "\"flags\"") != null) {
            self.fake.invocation_plan.complete.content = "{\"flags\":[true,false]}";
        } else {
            if (self.zip_request) |id| {
                self.consistent = self.consistent and id == request.model_request_id;
            } else self.zip_request = request.model_request_id;
            self.consistent = self.consistent and std.mem.indexOf(u8, request.content[1].user, "\"street\":\"Main St\"") != null and
                std.mem.indexOf(u8, request.content[1].user, "\"flags\"") == null;
            self.fake.invocation_plan.complete.content = switch (invoked.id.model_attempt_ordinal.value) {
                1 => "{broken",
                2 => "{\"address\":{\"zip\":7}}",
                else => if (self.recover) "{\"address\":{\"zip\":\"3050\"}}" else "{broken",
            };
        }
        var response = try self.fake.interface().invoke(selected, request, reference, invoked);
        if (self.missing_answer and invoked.id.model_attempt_ordinal.value == 2) {
            const prior = response.completed.raw_result.complete;
            response.deinit();
            return .{ .completed = .{ .operation_id = invoked.id, .raw_result = .{ .rejected = .{
                .request_id = request.model_request_id,
                .binding_id = request.binding_id,
                .usage = prior.usage,
                .provider_latency_ms = prior.provider_latency_ms,
                .reason = .missing_final_text,
            } } } };
        }
        return response;
    }
    fn count(context: *@import("ports/llm_provider_interface.zig").Context, selected: *const @import("domain/llm_provider_binding.zig").ValidatedProviderModelBinding, request: *const provider.IdentifiedProviderNeutralModelRequest, reference: *const provider.ValidatedProviderAuthorizationLeaseRef, invoked: *const provider.InvokedProviderOperation) @import("ports/llm_provider_interface.zig").Error!provider.ProviderTokenCountObservation {
        const self: *@This() = @ptrCast(@alignCast(context));
        return self.fake.interface().countInputTokens(selected, request, reference, invoked);
    }
    fn observe(_: ?*void, input: operations.Input) operations.Error!execution.Candidate {
        _ = try @import("application/json_composition_workflow.zig").readValidated(&input.step.data);
        return .{ .outcome = .ok, .delta = .{} };
    }
};

test "composition application handoffs release retained parts and requests at every allocation failure" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var input: ProtocolUnits = .{};
    fixture.entries[fixture.entries.len - 1] = .{
        .contract = .{ .id = "test.observe-request", .kind = .step, .requires = &.{ .assembled_json, .validated_assembled_json }, .outcomes = &.{.ok}, .side_effect = .none },
        .binding = bindings.bind(void, null, CompositionCalls.observe),
    };
    var entries = fixture.entries ++ [_]operations.Entry{.{
        .contract = .{ .id = "test.select-unit", .kind = .step, .produces = &.{.model_input_packet}, .outcomes = &.{ .ok, .failed }, .side_effect = .none },
        .binding = bindings.bind(ProtocolUnits, &input, ProtocolUnits.select),
    }};
    fixture.registry.operations = &entries;
    const graph = try fixture.compileResources(composition_yaml, address_schema, false, address_composition);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, compositionAllocationCase, .{ &fixture, graph, &entries, &input });
    try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
}

fn compositionAllocationCase(allocator: std.mem.Allocator, fixture: *Fixture, graph: *const compilation.CompiledWorkflow, entries: []operations.Entry, input: *ProtocolUnits) !void {
    input.* = .{};
    fixture.native.init(allocator);
    fixture.authorization.allocator = allocator;
    fixture.native.prepare_authorization.action = .{ .authorization = fixture.authorization.port() };
    @memcpy(entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var calls: CompositionCalls = .{ .fake = invocationProvider(&runner, allocator), .recover = true, .missing_answer = true };
    fixture.native.invoke_model.action = .{ .provider = calls.interface() };
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    if (outcome == .failed) return error.OutOfMemory;
    try std.testing.expectEqual(.ok, outcome);
    try std.testing.expectEqual(@as(usize, 5), calls.fake.effect_count);
    try std.testing.expect(calls.consistent);
    try std.testing.expectEqual(@as(u128, 35), runner.tokenLedger().committed());
    const view: @import("domain/pipeline_data.zig").View = .{ .slots = runner.envelope.slots };
    const candidate = try @import("application/json_composition_workflow.zig").readValidated(&view);
    try std.testing.expectEqualStrings("{\"address\":{\"street\":\"Main St\",\"zip\":\"3050\"},\"flags\":[true,false]}", candidate.body);
    try std.testing.expect(!view.contains(.json_composition));
}

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    services: @import("application/model_provider_bootstrap_services.zig").ModelProviderBootstrapServices,
    roots_owner: *roots.Owner,
    native: native.Assembly,
    observer: Observer,
    authorization: @import("adapters/provider/fake_provider_authorization.zig").FakeProviderAuthorization,
    clock: @import("provider_authorization_test_fixture.zig").TestClock,
    entries: [core.entries.len + native.count + 1]operations.Entry,
    registry: operations.Registry,

    fn init(self: *Fixture, allocator: std.mem.Allocator) !void {
        return self.initWithProvider(allocator, null, false);
    }

    fn initWithProvider(self: *Fixture, allocator: std.mem.Allocator, production: ?usize, json: bool) !void {
        self.arena = .init(allocator);
        errdefer self.arena.deinit();
        self.services = try providerServices(allocator, production, "selected", json);
        errdefer self.services.deinit();
        self.roots_owner = try rootOwner(allocator);
        self.native.init(allocator);
        self.authorization = .{ .allocator = allocator };
        self.clock = .{};
        self.native.prepare_authorization.action = .{ .authorization = self.authorization.port() };
        self.observer = .{};
        self.entries = core.entries ++ self.native.entries ++ [_]operations.Entry{.{
            .contract = .{ .id = "test.observe-request", .kind = .step, .requires = &.{ .model_request_identity_ledger, .prepared_model_request }, .outcomes = &.{.ok}, .side_effect = .none },
            .binding = bindings.bind(Observer, &self.observer, Observer.invoke),
        }};
        self.registry = .{ .operations = &self.entries, .data_schemas = &native.schemas, .policies = &core.profiles, .gates = &.{} };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.services.deinit();
        roots.deinitOwner(self.roots_owner);
    }

    fn compile(self: *Fixture, bytes: []const u8) !*const compilation.CompiledWorkflow {
        return self.compileWithSchema(bytes, schema_bytes);
    }

    fn compileWithSchema(self: *Fixture, bytes: []const u8, result_schema: []const u8) !*const compilation.CompiledWorkflow {
        return self.compileWithAssets(bytes, result_schema, true);
    }

    fn compileWithAssets(self: *Fixture, bytes: []const u8, result_schema: []const u8, include_static_input: bool) !*const compilation.CompiledWorkflow {
        return self.compileResources(bytes, result_schema, include_static_input, null);
    }

    fn compileResources(self: *Fixture, bytes: []const u8, result_schema: []const u8, include_static_input: bool, composition_bytes: ?[]const u8) !*const compilation.CompiledWorkflow {
        const allocator = self.arena.allocator();
        var parser: @import("adapters/parsers/workflow_definitions.zig").Adapter = .{};
        var schema_parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const raw = try (@import("actions/workflow/parse_workflow_definitions.zig").Action{ .parser = parser.parser() }).execute(allocator, &.{.{ .ordinal = 1, .bytes = bytes }});
        const definitions = try (@import("actions/workflow/validate_workflow_definition_schema.zig").Action{}).execute(allocator, raw);
        const paths = [_][]const u8{ "request.workflow.yaml", "prompt.md", "result.json", if (composition_bytes != null) "composition.json" else "input.txt" };
        const bodies = [_][]const u8{ bytes, prompt_bytes, result_schema, composition_bytes orelse input_bytes };
        var descriptors: [4]inventory.InventoryDescriptor = undefined;
        var accounts: [4]inventory.InventoryAccount = undefined;
        for (paths, bodies, 0..) |path, body, index| {
            descriptors[index] = .{ .path = path, .kind = .file, .identity = .{ .filesystem_id = 1, .file_id = index + 1 }, .size = body.len };
            accounts[index] = .{ .ordinal = @intCast(index + 1), .path = path, .disposition = if (index == 0) .definition else .resource };
        }
        const count: usize = if (include_static_input or composition_bytes != null) 4 else 3;
        const inv: inventory.Inventory = .{ .capability = roots.registry(self.roots_owner).workflowAuthority(), .descriptors = descriptors[0..count], .accounts = accounts[0..count], .definition_ordinals = &.{1}, .resource_ordinals = if (count == 4) &.{ 2, 3, 4 } else &.{ 2, 3 } };
        const manifest = try (@import("actions/workflow/resolve_workflow_resources.zig").Action{}).execute(allocator, inv, definitions);
        const captures = [_]inventory.Capture{ .{ .ordinal = 2, .bytes = prompt_bytes }, .{ .ordinal = 3, .bytes = result_schema }, .{ .ordinal = 4, .bytes = composition_bytes orelse input_bytes } };
        const graphs = try (@import("actions/workflow/compile_workflow_graphs.zig").Action{ .registry = &self.registry, .result_schema_compiler = schema_parser.compiler() }).execute(allocator, definitions, inv, manifest, captures[0 .. count - 1]);
        _ = try (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(allocator, graphs);
        return &graphs[0];
    }

    fn runner(self: *Fixture, graph: *const compilation.CompiledWorkflow, allocator: std.mem.Allocator) runner_module.Runner {
        var result = runner_module.Runner.init(allocator, .{ .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} }, .graph = graph }, &self.registry, .{ .context = self, .process_fn = noTelemetry }, .{}, &self.services);
        result.provider_clock = self.clock.port();
        return result;
    }
};

pub fn providerServices(allocator: std.mem.Allocator, production: ?usize, slot: []const u8, json: bool) !@import("application/model_provider_bootstrap_services.zig").ModelProviderBootstrapServices {
    const selected: contracts.ProviderModelContract = if (production) |index| @import("composition/provider_model_contracts.zig").registry.entries[index] else .{ .provider = .{ .bytes = "test-provider" }, .model = .{ .bytes = "test-model" }, .implementation_id = .{ .ordinal = 1 }, .config_schema = .empty_object, .capabilities = @import("model_contract_test_fixture.zig").capabilities, .supported_reasoning_efforts = &.{} };
    const registered: contracts.Registry = .{ .entries = &.{selected} };
    var candidate = try registry.Candidate.init(allocator, 1);
    defer candidate.deinit();
    const contract = registered.entries[0];
    candidate.entries[0] = .{ .provider = contract.provider, .model = contract.model, .implementation_id = contract.implementation_id, .json = json, .config = if (production != null) .{ .aws_bedrock = .{ .region = contract.bedrock_regions[0] } } else .empty_object, .capabilities = contract.capabilities, .supported_reasoning_efforts = contract.supported_reasoning_efforts };
    const owner = try registry.createValidated(allocator, candidate, registered);
    errdefer registry.deinitOwner(owner);
    var models: @import("domain/config.zig").ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(allocator);
    try models.slots.map.put(allocator, slot, .{ .provider = contract.provider.bytes, .model = contract.model.bytes });
    const allowlist = try @import("domain/repository_model_allowlist.zig").createValidated(allocator, &models, registry.registry(owner));
    return .init(.init(owner), allowlist);
}

fn rootOwner(allocator: std.mem.Allocator) !*roots.Owner {
    const root_contract = @import("domain/bootstrap_roots.zig");
    const paths = [_][]const u8{ "specs", "references", "specs/archive", "workflows", "presets", "principles", "templates" };
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    var configured: [root_contract.PathKey.count]root_contract.ValidatedConfiguredRoot = undefined;
    for (&configured, paths, 0..) |*value, path, index| {
        const key: root_contract.PathKey = @enumFromInt(index);
        value.* = .{ .path_key = key, .root_role = key.role(), .canonical_project_root = "/project", .configured_relative_path = path, .canonical_path = try std.fmt.allocPrint(arena.allocator(), "/project/{s}", .{path}), .access_class = key.accessClass(), .existence_policy = key.existencePolicy(), .observation = if (key == .workflows) .{ .directory = .{ .filesystem_id = 1, .file_id = 20 } } else .absent };
    }
    return roots.createValidated(allocator, .{ .id = .{ .canonical_project_root = "/project", .contract_version = root_contract.bootstrap_root_contract_version }, .config_location = .{ .canonical_project_root = "/project", .canonical_config_path = "/project/.sddtoolkit.json", .no_follow_file_identity = .{ .filesystem_id = 1, .file_id = 1 } }, .configured_roots = configured, .llm_provider_config_path = .{ .relative_path = ".sddproviders.json", .canonical_project_root = "/project", .canonical_path = "/project/.sddproviders.json" } });
}

const Harness = struct {
    runner: *runner_module.Runner,
    steps: usize = 0,
    cancel_at: ?usize = null,
    cancelled: bool = false,
    fn run(self: *Harness) workflow.OutcomeTag {
        return self.result().executionStatus().?;
    }
    fn result(self: *Harness) @import("domain/run_outcome.zig").Outcome {
        return engine.run(.{ .context = self, .vtable = &.{ .validate_operation_registry = selected, .parse_invocation = selected, .select_workflow = selected, .prepare_workflow = ready, .selected_graph = graph, .invoke_invocation = invocation, .invoke_step = step } });
    }
    fn selected(_: *anyopaque) children.SelectionStepOutcome {
        return .ok;
    }
    fn ready(_: *anyopaque) children.PreparationOutcome {
        return .ok;
    }
    fn graph(context: *const anyopaque) *const compilation.CompiledWorkflow {
        const self: *const Harness = @ptrCast(@alignCast(context));
        return self.runner.selected.graph;
    }
    fn invocation(context: *anyopaque) execution.Applied {
        const self: *Harness = @ptrCast(@alignCast(context));
        return self.runner.bindings().invokeInvocation();
    }
    fn step(context: *anyopaque, id: workflow.WorkflowStepId) execution.Applied {
        const self: *Harness = @ptrCast(@alignCast(context));
        if (self.cancel_at == self.steps) self.cancelled = true;
        self.steps += 1;
        return self.runner.bindings().invokeStep(id);
    }
    fn status(context: ?*anyopaque) pipeline.RuntimeStatus {
        const self: *Harness = @ptrCast(@alignCast(context.?));
        return if (self.cancelled) .cancelled else .active;
    }
};

fn currentRequest(runner: *const runner_module.Runner) operations.Error!*const handoff.Request {
    return requests.readCurrent(&.{ .slots = runner.envelope.slots }, requests.prepared_schema);
}

fn noTelemetry(_: *anyopaque, _: @import("domain/telemetry.zig").WorkflowTelemetryFact) @import("domain/feature_log_stream.zig").Outcome {
    return .dropped;
}

const ModelCaptureSink = struct {
    const prompt = @import("domain/sanitized_prompt_log.zig");
    const stream = @import("domain/feature_log_stream.zig");
    allocator: std.mem.Allocator,
    fail_direction: ?prompt.PromptDirection = null,
    fragments: std.ArrayList(prompt.SanitizedPromptFragment) = .empty,

    fn barrier(self: *@This()) @import("ports/telemetry_barrier.zig").Barrier {
        return .{ .context = self, .process_fn = noTelemetry, .select_prompt_fn = selected, .process_prompt_fn = process };
    }
    fn selected(_: *anyopaque, _: prompt.SanitizedPromptFragment) bool {
        return true;
    }
    fn process(context: *anyopaque, fragment: prompt.SanitizedPromptFragment) stream.Outcome {
        const self: *@This() = @ptrCast(@alignCast(context));
        if (self.fail_direction == fragment.direction) return .{ .blocked = .LOG_FLUSH_FAILURE };
        var retained = fragment;
        retained.request_id.bytes = self.allocator.dupe(u8, fragment.request_id.bytes) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        retained.fragment_id.bytes = self.allocator.dupe(u8, fragment.fragment_id.bytes) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        retained.content = self.allocator.dupe(u8, fragment.content) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        self.fragments.append(self.allocator, retained) catch return .{ .blocked = .LOG_SERIALIZATION_FAILURE };
        return .{ .persisted = .{ .sequence = self.fragments.items.len, .segment_ordinal = 1, .bytes_written = retained.content.len, .flushed = true } };
    }
};

test "production request capture failure records non-delivery and response capture failure retains usage" {
    const Case = struct { direction: ModelCaptureSink.prompt.PromptDirection, overshoot: bool = false };
    for ([_]Case{ .{ .direction = .request }, .{ .direction = .response }, .{ .direction = .response, .overshoot = true } }) |case| {
        var fixture: Fixture = undefined;
        try fixture.initWithProvider(std.testing.allocator, 0, false);
        defer fixture.deinit();
        const graph = try fixture.compile(try invocationYaml(&fixture));
        var environment = try bedrockEnvironment(std.testing.allocator);
        defer environment.deinit();
        var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
            .environment = &environment,
            .operations = &fixture.native,
            .authorization = .{ .allocator = std.testing.allocator },
            .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
        };
        defer runtime.deinit();
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var sink: ModelCaptureSink = .{ .allocator = fixture.arena.allocator(), .fail_direction = case.direction };
        runner.model_capture.logs = sink.barrier();
        try runtime.bind(&runner);
        const body = if (case.overshoot) try std.mem.replaceOwned(u8, fixture.arena.allocator(), bedrock_complete_body, "\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12", "\"inputTokens\":100000,\"outputTokens\":2,\"totalTokens\":100002") else bedrock_complete_body;
        var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = body };
        runtime.provider.?.aws_bedrock.transport = wire.port();
        var harness: Harness = .{ .runner = &runner };
        const outcome = harness.result();
        try std.testing.expectEqual(.LOG_FLUSH_FAILURE, outcome.execution_rejected.logging);
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expect(runner.model_capture.current == null);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(model_invocation.schema.key)] == null);
        const tokens = runner.tokenLedger();
        try std.testing.expectEqual(@as(usize, 1), tokens.accounted_operations.items.len);
        try std.testing.expectEqual(@as(u64, 1), tokens.revision().value);
        const accounted = tokens.accounted_operations.items[0];
        try std.testing.expect(accounted.id.eql((try invokedOperation(&runner)).operation().id));
        if (case.direction == .request) {
            try std.testing.expectEqual(@as(usize, 0), wire.calls);
            try std.testing.expect(accounted.reconciliation == .not_sent);
            try std.testing.expectEqual(@as(u128, 0), tokens.committed());
            try std.testing.expectEqual(.available, tokens.status());
            try std.testing.expectEqual(@as(usize, 0), sink.fragments.items.len);
        } else {
            const expected: u64 = if (case.overshoot) 100002 else 12;
            try std.testing.expectEqual(@as(usize, 1), wire.calls);
            try std.testing.expectEqual(expected, accounted.reconciliation.exact_usage.total_tokens);
            try std.testing.expectEqual(@as(u128, expected), tokens.committed());
            try std.testing.expectEqual(@as(@TypeOf(tokens.status()), if (case.overshoot) .exceeded else .available), tokens.status());
            try std.testing.expect(sink.fragments.items.len > 0);
            for (sink.fragments.items) |fragment| try std.testing.expectEqual(.request, fragment.direction);
        }
    }
}

test "production count capture failure blocks inference without changing token accounting" {
    for ([_]ModelCaptureSink.prompt.PromptDirection{ .request, .response }) |direction| {
        var fixture: Fixture = undefined;
        try fixture.initWithProvider(std.testing.allocator, 1, false);
        defer fixture.deinit();
        const graph = try fixture.compile(try countInferenceYaml(&fixture));
        var environment = try bedrockEnvironment(std.testing.allocator);
        defer environment.deinit();
        var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
            .environment = &environment,
            .operations = &fixture.native,
            .authorization = .{ .allocator = std.testing.allocator },
            .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
        };
        defer runtime.deinit();
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var sink: ModelCaptureSink = .{ .allocator = fixture.arena.allocator(), .fail_direction = direction };
        runner.model_capture.logs = sink.barrier();
        try runtime.bind(&runner);
        var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = bedrock_complete_body };
        runtime.provider.?.aws_bedrock.transport = wire.port();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(.LOG_FLUSH_FAILURE, harness.result().execution_rejected.logging);
        try std.testing.expectEqual(@as(usize, if (direction == .request) 0 else 1), wire.calls);
        try std.testing.expectEqual(@as(u64, 0), runner.tokenLedger().revision().value);
        try std.testing.expectEqual(@as(usize, 0), runner.tokenLedger().accounted_operations.items.len);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(model_invocation.count_schema.key)] == null);
        try std.testing.expect(runner.model_capture.current == null);
    }
}

test "production capture attributes count and inference bodies to the existing request ledger" {
    var fixture: Fixture = undefined;
    try fixture.initWithProvider(std.testing.allocator, 1, false);
    defer fixture.deinit();
    const a = fixture.arena.allocator();
    const yaml_source = try std.mem.concat(a, u8, &.{ try countInferenceYaml(&fixture), "\n# " ++ "source snapshot " ** 1000 });
    var graph_value = (try fixture.compile(yaml_source)).*;
    graph_value.source = .{ .path = "request.workflow.yaml", .content = yaml_source };
    const graph = &graph_value;
    var environment = try bedrockEnvironment(std.testing.allocator);
    defer environment.deinit();
    var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
        .environment = &environment,
        .operations = &fixture.native,
        .authorization = .{ .allocator = std.testing.allocator },
        .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
    };
    defer runtime.deinit();
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var sink: ModelCaptureSink = .{ .allocator = a };
    runner.model_capture.logs = sink.barrier();
    try runtime.bind(&runner);
    var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = bedrock_complete_body };
    runtime.provider.?.aws_bedrock.transport = wire.port();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.ok, harness.run());
    try std.testing.expectEqual(@as(usize, 2), wire.calls);
    const request = try currentRequest(&runner);
    const ledger = try requestLedger(&runner);
    const request_id = try std.fmt.allocPrint(a, "request-{d}", .{ledger.indexOf(request.id()).?.value});
    const completed = (try completedOperation(&runner)).record().id;
    for ([_]provider.ProviderOperationKind{ .input_token_count, .inference }) |kind| {
        for ([_]ModelCaptureSink.prompt.PromptDirection{ .request, .response }) |direction| {
            const prefix = try std.fmt.allocPrint(a, "{s}-{s}-provider_body-utf8-", .{ @tagName(kind), @tagName(direction) });
            var body: std.ArrayList(u8) = .empty;
            for (sink.fragments.items) |fragment| {
                try std.testing.expectEqualStrings(request_id, fragment.request_id.bytes);
                try std.testing.expectEqual(completed.model_attempt_ordinal.value, fragment.attempt);
                try std.testing.expectEqualStrings(request.prepared().?.model_operation_id.workflow_step_id.bytes, fragment.route_id.bytes);
                try std.testing.expectEqualStrings(request.binding().slot_id.bytes, fragment.model_profile_id.bytes);
                try std.testing.expectEqualDeep(graph.shortcode, fragment.workflow_shortcode);
                if (!std.mem.startsWith(u8, fragment.fragment_id.bytes, prefix)) continue;
                try std.testing.expectEqualStrings(if (kind == .input_token_count) "call" else "infer", fragment.node_id.?.bytes);
                try body.appendSlice(a, fragment.content);
            }
            const expected = if (direction == .request)
                try @import("adapters/provider/bedrock_request.zig").encode(a, request.prepared().?, kind)
            else if (kind == .input_token_count)
                "{\"inputTokens\":10}"
            else
                bedrock_complete_body;
            try std.testing.expectEqualStrings(expected, body.items);
        }
    }
    const captured = try restoreCapturedSources(a, sink.fragments.items);
    try std.testing.expectEqual(@as(usize, 2), captured.len);
    for (captured) |call| {
        const snapshot = call.source_snapshot.?;
        try std.testing.expectEqualStrings(yaml_source, snapshot.document.content);
        try std.testing.expectEqualStrings("request.workflow.yaml", snapshot.document.path);
        try std.testing.expectEqualStrings(call.node, snapshot.caller.chain[0].id);
        try std.testing.expectEqualStrings(call.action, snapshot.caller.chain[0].target);
        try std.testing.expectEqualStrings(call.request_step, snapshot.preparation.chain[0].id);
        try std.testing.expectEqual(@as(usize, 3), snapshot.resources.len);
        try std.testing.expectEqualStrings("prompt.md", snapshot.resources[0].document.path);
        try std.testing.expectEqualStrings(prompt_bytes, snapshot.resources[0].document.content);
        try std.testing.expectEqualStrings(schema_bytes, snapshot.resources[1].document.content);
        try std.testing.expectEqualStrings(input_bytes, snapshot.resources[2].document.content);
    }
    var first_source: ?usize = null;
    var last_source: ?usize = null;
    for (sink.fragments.items, 0..) |fragment, index| {
        if (std.mem.startsWith(u8, fragment.fragment_id.bytes, "inference-request-source_snapshot-")) {
            if (first_source == null) first_source = index;
            last_source = index;
        }
    }
    try std.testing.expect(first_source.? < last_source.?);
    var partial: std.ArrayList(ModelCaptureSink.prompt.SanitizedPromptFragment) = .empty;
    for (sink.fragments.items, 0..) |fragment, index| if (index != last_source.?) try partial.append(a, fragment);
    const partial_calls = try restoreCapturedSources(a, partial.items);
    try std.testing.expect(partial_calls[0].source_snapshot != null);
    try std.testing.expect(partial_calls[1].source_snapshot == null);
    partial.clearRetainingCapacity();
    for (sink.fragments.items, 0..) |fragment, index| if (index != first_source.?) try partial.append(a, fragment);
    try std.testing.expectError(error.InvalidDebugArchive, restoreCapturedSources(a, partial.items));
    try std.testing.expectEqual(@as(u128, 12), runner.tokenLedger().committed());
    try std.testing.expect(runner.model_capture.current == null);
}

test "production Bedrock composition executes count inference validation and request closure from YAML" {
    for ([_]bool{ false, true }) |count_first| {
        var fixture: Fixture = undefined;
        try fixture.initWithProvider(std.testing.allocator, if (count_first) 1 else 0, false);
        defer fixture.deinit();
        const graph = try fixture.compile(if (count_first) try countInferenceYaml(&fixture) else try requestCompletionYaml(&fixture));
        // A fresh invocation captures its own environment snapshot and ledger.
        for (0..2) |_| {
            var environment = try bedrockEnvironment(std.testing.allocator);
            defer environment.deinit();
            var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
                .environment = &environment,
                .operations = &fixture.native,
                .authorization = .{ .allocator = std.testing.allocator },
                .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
            };
            defer runtime.deinit();
            var runner = fixture.runner(graph, std.testing.allocator);
            defer runner.deinit();
            try runtime.bind(&runner);
            // Changing the environment after preloading cannot refresh a lease.
            try environment.put("AWS_BEARER_TOKEN_BEDROCK", "");
            var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = bedrock_complete_body };
            runtime.provider.?.aws_bedrock.transport = wire.port();
            var harness: Harness = .{ .runner = &runner };
            try std.testing.expectEqual(.ok, harness.run());
            try std.testing.expectEqual(@as(usize, if (count_first) 2 else 1), wire.calls);
            try std.testing.expectEqual(@as(u128, 12), runner.tokenLedger().committed());
            try std.testing.expectEqual(@as(u64, 1), runner.tokenLedger().revision().value);
            const request = try currentRequest(&runner);
            try std.testing.expectEqual(.terminal, (try requestLedger(&runner)).record(request.id()).?.status);
            try runner.model_accounting.?.current_operations.validateRequestClosure(request.id());
        }
    }
}

test "production Bedrock YAML records budget overshoot and blocks another call" {
    var fixture: Fixture = undefined;
    try fixture.initWithProvider(std.testing.allocator, 0, false);
    defer fixture.deinit();
    const graph = try fixture.compile(try invocationYaml(&fixture));
    var environment = try bedrockEnvironment(std.testing.allocator);
    defer environment.deinit();
    var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
        .environment = &environment,
        .operations = &fixture.native,
        .authorization = .{ .allocator = std.testing.allocator },
        .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
    };
    defer runtime.deinit();
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    try runtime.bind(&runner);
    const body = try std.mem.replaceOwned(u8, fixture.arena.allocator(), bedrock_complete_body, "\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12", "\"inputTokens\":100000,\"outputTokens\":2,\"totalTokens\":100002");
    var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = body };
    runtime.provider.?.aws_bedrock.transport = wire.port();
    var harness: Harness = .{ .runner = &runner };
    const result = harness.result();
    try std.testing.expect(result == .execution_rejected);
    try std.testing.expectEqual(@as(u128, 100002), runner.tokenLedger().committed());
    try std.testing.expectEqual(@as(u64, 100002), runner.tokenLedger().accounted_operations.items[0].reconciliation.exact_usage.total_tokens);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(model_invocation.schema.key)] == null);
    const repeated = runner.bindings().invokeStep(.{ .bytes = "call" });
    try std.testing.expect(repeated == .rejected);
    try std.testing.expectEqual(@as(usize, 1), wire.calls);
}

test "production Bedrock missing credentials follow explicit pre-call termination without effects" {
    var fixture: Fixture = undefined;
    try fixture.initWithProvider(std.testing.allocator, 0, false);
    defer fixture.deinit();
    const graph = try fixture.compile(try requestTerminationYaml(&fixture, "inference"));
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
        .environment = &environment,
        .operations = &fixture.native,
        .authorization = .{ .allocator = std.testing.allocator },
        .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
    };
    defer runtime.deinit();
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    try runtime.bind(&runner);
    var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{};
    runtime.provider.?.aws_bedrock.transport = wire.port();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.failed, harness.run());
    try std.testing.expectEqual(@as(usize, 0), wire.calls);
    try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    const request = try currentRequest(&runner);
    try std.testing.expectEqual(.not_invoked_authorization_failure, (try requestLedger(&runner)).record(request.id()).?.terminal_reason.?);
}

const bedrock_complete_body = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"text\":\"{\\\"answer\\\":\\\"candidate\\\"}\"}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}";

test "production missing-answer observation retains usage and can close without correction" {
    for ([_]bool{ false, true }) |overshoot| {
        var fixture: Fixture = undefined;
        try fixture.initWithProvider(std.testing.allocator, 0, false);
        defer fixture.deinit();
        const graph = try fixture.compile(try requestCompletionYaml(&fixture));
        var environment = try bedrockEnvironment(std.testing.allocator);
        defer environment.deinit();
        var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
            .environment = &environment,
            .operations = &fixture.native,
            .authorization = .{ .allocator = std.testing.allocator },
            .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
        };
        defer runtime.deinit();
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try std.testing.expectEqual(@as(usize, 0), runner.envelope.records.items.len);
        try runtime.bind(&runner);
        const body = if (overshoot)
            "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\"}}}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":100000,\"outputTokens\":48,\"totalTokens\":100048}}"
        else
            "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"metadata\"}}}]}},\"stopReason\":\"end_turn\",\"metrics\":{\"latencyMs\":416},\"usage\":{\"inputTokens\":884,\"outputTokens\":48,\"totalTokens\":932}}";
        var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{ .inference_body = body };
        runtime.provider.?.aws_bedrock.transport = wire.port();
        var harness: Harness = .{ .runner = &runner };
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (overshoot) .failed else .invalid), harness.run());
        try std.testing.expectEqual(@as(usize, 1), wire.calls);
        const tokens = runner.tokenLedger();
        try std.testing.expectEqual(@as(u128, if (overshoot) 100048 else 932), tokens.committed());
        try std.testing.expectEqual(@as(usize, 1), tokens.accounted_operations.items.len);
        try std.testing.expectEqual(@as(u64, 1), tokens.revision().value);
        if (overshoot) {
            try std.testing.expectEqual(.exceeded, tokens.status());
            try std.testing.expect(runner.bindings().invokeStep(.{ .bytes = "call" }) == .rejected);
        } else {
            const observation = @import("application/provider_observation_workflow.zig");
            const history = runner.envelope.latestInformation(observation.schema.key);
            const retained = try values.read(&history, observation.schema, observation.Result);
            const evidence = retained.outcome().validated;
            try std.testing.expectEqual(.response_invalid, evidence.result().failed.cause);
            try std.testing.expectEqual(.never, evidence.result().failed.retry_class);
            try std.testing.expectEqual(provider.ProviderContentDiagnostic.missing_final_text, evidence.result().failed.content.?);
            try std.testing.expectEqual(@as(u64, 932), evidence.usage().?.total_tokens);
            try std.testing.expectEqual(.available, tokens.status());
            const record = runner.envelope.records.items[runner.envelope.records.items.len - 1];
            const encode = @import("adapters/provider/bedrock_request.zig").encode;
            const before = try encode(std.testing.allocator, evidence.request(), .inference);
            defer std.testing.allocator.free(before);
            _ = try runner.envelope.place(record.occurrence, record.value, record.origin);
            const after = try encode(std.testing.allocator, evidence.request(), .inference);
            defer std.testing.allocator.free(after);
            try std.testing.expectEqualStrings(before, after);
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = ".zig-cache/chunk18-stack-request-before.json", .data = before });
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = ".zig-cache/chunk18-stack-request-after.json", .data = after });
            try std.testing.expectEqual(@as(u128, 932), tokens.committed());
            try std.testing.expectError(error.TokenUsageAlreadyAccounted, @import("domain/workflow_token_accounting.zig").proposeReconciliation(tokens, tokens.revision(), retained.operationId(), .{ .exact_usage = evidence.usage().? }));
        }
        try std.testing.expectEqual(@as(usize, 1), wire.calls);
    }
}

test "missing answers share protocol allowance through mixed failure and successful recovery" {
    const missing = "{\"output\":{\"message\":{\"role\":\"assistant\",\"content\":[{\"reasoningContent\":{\"reasoningText\":{\"text\":\"reasoning must not become an answer\"}}}]}},\"stopReason\":\"end_turn\",\"usage\":{\"inputTokens\":10,\"outputTokens\":2,\"totalTokens\":12}}";
    const shapes = [_]struct { schema: []const u8, valid: []const u8 }{
        .{ .schema = schema_bytes, .valid = "{\"answer\":\"complete\"}" },
        .{ .schema = "{\"type\":\"object\",\"properties\":{\"ready\":{\"type\":\"boolean\"},\"names\":{\"type\":\"array\",\"items\":{\"type\":\"string\",\"maxLength\":20},\"maxItems\":3}},\"required\":[\"ready\",\"names\"],\"additionalProperties\":false}", .valid = "{\"ready\":true,\"names\":[\"first\",\"second\"]}" },
    };
    for ([_]bool{ false, true }) |json| for (shapes) |shape| for ([_]bool{ false, true }) |consolidated| for (0..3) |sequence| {
        var fixture: Fixture = undefined;
        try fixture.initWithProvider(std.testing.allocator, 0, json);
        defer fixture.deinit();
        const graph = try fixture.compileWithSchema(try responseAdmissionYaml(&fixture, try protocolRetryYaml(&fixture), consolidated), shape.schema);
        var environment = try bedrockEnvironment(std.testing.allocator);
        defer environment.deinit();
        var runtime: @import("composition/model_provider_runtime.zig").Assembly = .{
            .environment = &environment,
            .operations = &fixture.native,
            .authorization = .{ .allocator = std.testing.allocator },
            .transport = .{ .io = std.testing.io, .clock = fixture.clock.port(), .runtime = .{} },
        };
        defer runtime.deinit();
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        try runtime.bind(&runner);
        var wire: @import("bedrock_transport_test_fixture.zig").Wire = .{ .expected_json = json };
        runtime.provider.?.aws_bedrock.transport = wire.port();
        var original_id: ?*const identity.ModelRequestId = null;
        for (0..3) |attempt| {
            const absent = if (sequence == 0) attempt == 1 else if (sequence == 1) true else attempt != 1;
            const succeeds = sequence == 0 and attempt == 2;
            const body = if (succeeds) shape.valid else if (sequence == 2) "{}" else "{";
            wire.inference_body = if (absent) missing else try std.json.Stringify.valueAlloc(fixture.arena.allocator(), .{
                .output = .{ .message = .{ .role = "assistant", .content = .{.{ .text = body }} } },
                .stopReason = "end_turn",
                .usage = .{ .inputTokens = @as(u64, 10), .outputTokens = @as(u64, 2), .totalTokens = @as(u64, 12) },
            }, .{});
            try prepareProtocolAttempt(&runner, attempt != 0);
            const request = try currentRequest(&runner);
            if (original_id == null) original_id = request.id();
            try std.testing.expect(request.id() == original_id.?);
            try std.testing.expectEqual(json, request.prepared().?.response_guidance_mode == .native_schema);
            try std.testing.expectEqual(.zero, request.prepared().?.controls.temperature.?);
            try std.testing.expectEqualStrings(shape.schema, request.prepared().?.response_schema.bytes());
            try std.testing.expectEqual(@as(u32, @intCast(attempt + 1)), (try invokedOperation(&runner)).operation().id.model_attempt_ordinal.value);
            for ([_][]const u8{ "call", "validate-response", "complete-operation" }) |step|
                try std.testing.expectEqual(@as(workflow.OutcomeTag, if (absent) .failed else .ok), runner.bindings().invokeStep(.{ .bytes = step }).outcome);
            const decoded: workflow.OutcomeTag = if (absent or (!succeeds and sequence == 0)) .invalid else .ok;
            if (!consolidated) try std.testing.expectEqual(decoded, runner.bindings().invokeStep(.{ .bytes = "decode" }).outcome);
            try std.testing.expectEqual(@as(workflow.OutcomeTag, if (succeeds) .ok else .invalid), runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).outcome);
            try std.testing.expectEqual(@as(u128, (attempt + 1) * 12), runner.tokenLedger().committed());
            try std.testing.expectEqual(attempt + 1, runner.tokenLedger().accounted_operations.items.len);
            try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
            if (succeeds) {
                const accepted = (try payloadResult(&runner)).outcome().valid.candidate();
                try std.testing.expectEqualStrings(shape.valid, accepted.association().result().complete.content());
                for ([_][]const u8{ "close-request", "observe" }) |step|
                    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
                try std.testing.expectEqual(.accepted, (try requestLedger(&runner)).record(original_id.?).?.terminal_reason.?);
            } else {
                try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "retry" }).outcome);
                const correction = (try currentRequest(&runner)).prepared().?;
                try std.testing.expect(correction.model_request_id == original_id.?);
                try std.testing.expectEqualStrings(prompt_bytes, correction.content[0].guidance);
                try std.testing.expectEqualStrings(input_bytes, correction.content[1].user);
                try std.testing.expectEqual(@as(usize, if (absent) 4 else 5), correction.content.len);
                if (absent) {
                    try std.testing.expect(std.mem.indexOf(u8, correction.content[3].guidance, "missing_final_text") != null);
                    try std.testing.expect(std.mem.indexOf(u8, correction.content[3].guidance, "Final-answer admission failed: no final answer was received.") != null);
                    for (correction.content) |part| try std.testing.expect(part != .evidence);
                    try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.model_payload_schema_result)] == null);
                }
                try std.testing.expectEqual(@as(usize, if (sequence == 1 and attempt > 0) 1 else 0), std.mem.count(u8, correction.content[2].guidance, "The previous correction still failed this validation."));
            }
        }
        if (sequence != 0) {
            const stopped = runner.bindings().invokeStep(.{ .bytes = "account" });
            try std.testing.expectEqual(@as(u64, 3), stopped.rejected.retry_limit.completed_executions);
            try std.testing.expectEqual(@as(u32, 2), stopped.rejected.retry_limit.limit.value);
        }
        try std.testing.expectEqual(@as(usize, 3), wire.calls);
        try std.testing.expectEqual(@as(u128, 36), runner.tokenLedger().committed());
    };
}

fn bedrockEnvironment(allocator: std.mem.Allocator) !std.process.Environ.Map {
    var environment: std.process.Environ.Map = .init(allocator);
    errdefer environment.deinit();
    var canary: [48]u8 = undefined;
    std.testing.io.random(&canary);
    for (&canary) |*byte| byte.* = 'A' + byte.* % 26;
    defer std.crypto.secureZero(u8, &canary);
    try environment.put("AWS_BEARER_TOKEN_BEDROCK", &canary);
    return environment;
}

test "packet result selection binds one immutable named schema and fails before invocation when absent" {
    const packets = @import("domain/model_input_packet.zig");
    const schema_source = "{\"$defs\":{\"answer\":" ++ schema_bytes ++ ",\"flag\":{\"type\":\"boolean\"},\"decision\":{\"type\":\"object\",\"properties\":{\"approved\":{\"type\":\"boolean\"}},\"required\":[\"approved\"],\"additionalProperties\":false}},\"$ref\":\"#/$defs/answer\"}";
    for ([_]?[]const u8{ "answer", "decision", "missing", "flag", null }) |selection| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const a = fixture.arena.allocator();
        var definition = try std.mem.replaceOwned(u8, a, yaml, ", input: input }", ", result-selection: input }");
        definition = try std.mem.replaceOwned(u8, a, definition, ", input: input.txt", "");
        const graph = try fixture.compileWithAssets(definition, schema_source, false);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        const packet = try packets.create(std.testing.allocator, "{}", .workflow_step, .initial_generation, if (selection) |id| .{ .bytes = id } else null);
        runner.envelope.slots[@intFromEnum(requests.packet_schema.key)] = try requests.adoptPacket(std.testing.allocator, packet);
        var harness: Harness = .{ .runner = &runner };
        const valid = selection != null and (std.mem.eql(u8, selection.?, "answer") or std.mem.eql(u8, selection.?, "decision"));
        try std.testing.expectEqual(if (valid) workflow.OutcomeTag.ok else .failed, harness.run());
        try std.testing.expectEqual(@as(usize, if (valid) 1 else 0), fixture.observer.calls);
        if (valid) {
            const request = try currentRequest(&runner);
            const bound = request.prepared().?.response_schema;
            try std.testing.expectEqualStrings(schema_source, bound.bytes());
            const expected = if (std.mem.eql(u8, selection.?, "answer")) "answer" else "approved";
            try std.testing.expectEqualStrings(expected, bound.root().object[0].name);
            try std.testing.expectEqualStrings(selection.?, request.packet().?.resultDefinition().?.bytes);
            try std.testing.expect(std.mem.indexOf(u8, bound.modelBytes(), "$defs") == null);
        }
    }
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const definition = try std.mem.replaceOwned(u8, fixture.arena.allocator(), yaml, "input: input }", "input: input, result-selection: input }");
    const graph = try fixture.compileWithSchema(definition, schema_source);
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.failed, harness.run());
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
}

fn restoreCapturedSources(a: std.mem.Allocator, fragments: []const ModelCaptureSink.prompt.SanitizedPromptFragment) ![]@import("domain/request_debugger.zig").Call {
    const format = @import("domain/feature_log_format.zig");
    var rows: std.ArrayList(u8) = .empty;
    try rows.appendSlice(a, format.prompt_heading);
    for (fragments, 1..) |fragment, sequence| {
        try rows.appendSlice(a, try format.serializePrompt(a, .{
            .log_policy_id = .{ .bytes = "policy-1" },
            .binding_id = .{ .bytes = "binding-1" },
            .segment_ordinal = 1,
            .event_id = .{ .bytes = "event-1" },
            .sequence = sequence,
            .occurred_at_utc = "2026-09-20T00:00:00Z",
            .monotonic_offset = 1,
            .run_id = .{ .bytes = "run-one" },
            .feature_id = .{ .bytes = "feature" },
            .fragment = fragment,
        }));
    }
    var archive: @import("domain/request_debugger_archive.zig").Archive = .{ .allocator = a };
    try archive.ingest(rows.items);
    return archive.calls();
}
