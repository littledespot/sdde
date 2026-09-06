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
const model_invocation = @import("application/model_invocation_workflow.zig");
const invocation_result = @import("domain/model_invocation_result.zig");
const observation_workflow = @import("application/provider_observation_workflow.zig");
const envelope_workflow = @import("application/model_envelope_workflow.zig");
const payload_workflow = @import("application/model_payload_schema_workflow.zig");
const payload_validation = @import("domain/model_payload_schema.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const lease_port = @import("ports/provider_authorization_lease.zig");

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
    \\    with: { slot: selected, response-mode: prompt-only, prompt: prompt, result-schema: result, input: input }
    \\    on: { ok: validate, failed: end.failed }
    \\  validate: { use: validate-model-request-binding, on: { ok: build, failed: end.failed } }
    \\  build: { use: build-model-request, on: { ok: observe, failed: end.failed } }
    \\  observe: { use: test.observe-request, on: { ok: end.ok } }
;
const prompt_bytes = "Return the requested object.";
const schema_bytes = "{\"type\":\"object\",\"properties\":{\"answer\":{\"type\":\"string\",\"maxLength\":20000}},\"required\":[\"answer\"],\"additionalProperties\":false}";
const input_bytes = "x" ** 16_384;

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
        .{ "response-mode: prompt-only, ", "" },
        .{ "slot: selected", "slot: 7" },
        .{ "response-mode: prompt-only", "response-mode: unsupported" },
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
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const invalid = try std.mem.replaceOwned(u8, fixture.arena.allocator(), yaml, "slot: selected", "slot: unauthorized");
    const graph = try fixture.compile(invalid);
    var runner = fixture.runner(graph, std.testing.allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    try std.testing.expectEqual(.failed, harness.run());
    try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
    try std.testing.expect(runner.envelope.slots[@intFromEnum(pipeline.DataKey.prepared_model_request)] == null);
}

test "each execution has fresh identities and rejects a foreign retained request" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(yaml);
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

test "cancellation at every preparation boundary stops the compiled workflow" {
    for (0..5) |boundary| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(yaml);
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var harness: Harness = .{ .runner = &runner, .cancel_at = boundary };
        runner.runtime = .{ .context = &harness, .status_fn = Harness.status };
        try std.testing.expectEqual(.cancelled, harness.run());
        try std.testing.expectEqual(@as(usize, 0), fixture.observer.calls);
        try std.testing.expectEqual(@as(u128, 0), runner.tokenLedger().committed());
    }
}

test "native preparation releases partial allocations and unapplied deltas" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(yaml);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{ &fixture, graph });
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
        .{ .id = "response-mode", .kind = .enumeration, .allowed_values = &.{"prompt-only"}, .required = true, .workflow_definition_safe = true },
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
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (fault == .cancel_after_action) .cancelled else .invalid), harness.run());
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
        try std.testing.expectEqual(.invalid, harness.run());
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
    try std.testing.expectEqual(.operation_failed, second.bindings().invokeStep(.{ .bytes = "assign-operation" }).rejected);
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
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (fault == .cancel_after_action) .cancelled else .invalid), harness.run());
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
        try std.testing.expectEqual(@as(workflow.OutcomeTag, if (fault == .undeclared_write) .invalid else .failed), actual);
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
        try std.testing.expectEqual(.operation_failed, runner.bindings().invokeStep(.{ .bytes = "advance-request" }).rejected);
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
            try std.testing.expectEqual(@as(workflow.OutcomeTag, switch (fault) {
                .missing, .undeclared_write => .invalid,
                .cancel => .cancelled,
                else => .failed,
            }), if (applied == .rejected) applied.rejected.status() else applied.outcome);
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
            try std.testing.expectEqual(.invalid, runner.bindings().invokeStep(.{ .bytes = "advance-operation" }).outcome);
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
            0 => .operation_failed,
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
            try std.testing.expectEqual(@as(workflow.OutcomeTag, switch (fault) {
                .cancel => .cancelled,
                .expire => .failed,
                else => .invalid,
            }), if (applied == .rejected) applied.rejected.status() else applied.outcome);
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
        if (wrong_outcome) try std.testing.expectEqual(.authority, outcome.rejected) else try std.testing.expectEqual(.invalid, outcome.outcome);
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
    try std.testing.expectEqual(.invalid, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).outcome);
    runner.envelope.slots[observation_key] = source;
    try std.testing.expect(original == state.current_operations);
    const invoked_key = @intFromEnum(attempt_values.invoked_schema.key);
    const retained = try values.retain(runner.envelope.slots[invoked_key].?);
    try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).outcome);
    const current = state.current_operations;
    try std.testing.expectEqual(.invalid, runner.bindings().invokeStep(.{ .bytes = "complete-operation" }).outcome);
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
        if (fault == .cancelled) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.invalid, outcome.outcome);
        try std.testing.expect(original == runner.model_accounting.?.current_operations);
        try std.testing.expect(try observationResult(&runner) == response);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.terminal_schema.key)] == null);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(attempt_values.invoked_schema.key)] != null);
        try expectResponseAccounting(&runner, &fake, 7);
    }
}

const CompletionDeltaSpy = struct {
    const Fault = enum { command, identity, revision, ledger, outcome, missing_invalidation, extra_invalidation, fabricated_evidence, cancelled };
    inner: *completion_workflow.Complete,
    fault: Fault,
    invoked: bool = false,

    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var candidate = try completion_workflow.Complete.invoke(self.inner, input);
        const transition = &candidate.delta.runner_accounting_transition.?.advance_provider_operation;
        switch (self.fault) {
            .command => transition.command = .{ .terminate = .completed },
            .identity => transition.operation_id.kind = .input_token_count,
            .revision => transition.expected_operation_revision.?.value += 1,
            .ledger => transition.expected_revision.value += 1,
            .outcome => candidate.outcome = .ok,
            .missing_invalidation => candidate.delta.data_invalidations.remove(.invoked_provider_operation),
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

test "YAML payload validation uses each exact compiled schema and retains the same candidate" {
    const variants =
        \\{"oneOf":[{"type":"object","properties":{"kind":{"const":"content"},"values":{"type":"array","minItems":1,"maxItems":2,"items":{"type":"integer","minimum":1,"maximum":2}},"marker":{"const":true}},"required":["kind","values","marker"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"question"},"subject":{"enum":["alpha","beta"]}},"required":["kind","subject"],"additionalProperties":false}]}
    ;
    const Case = struct { schema: []const u8 = schema_bytes, body: []const u8, rejection: ?payload_validation.Rejection = null };
    for ([_]Case{
        .{ .body = "{\"answer\":\"é😀\"}" },
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
        const graph = try fixture.compileWithSchema(try payloadYaml(&fixture), case.schema);
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
            try std.testing.expectEqual(reason, result.outcome().schema_rejected);
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

test "YAML payload validation preserves protocol provider cancellation and observation rejection" {
    for ([_][]const u8{ "{", "[]", "{\"answer\":1,\"answer\":2}", "{} trailing" }) |body| {
        try checkUnvalidatedPayload(.{ .complete = .{ .content = body, .input_tokens = 5, .output_tokens = 2 } }, false);
    }
    for (std.enums.values(provider.ProviderNonCandidateStopReason)) |reason| {
        try checkUnvalidatedPayload(.{ .stopped = .{ .reason = reason, .input_tokens = 5, .output_tokens = 2 } }, false);
    }
    for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        try checkUnvalidatedPayload(.{ .failed = .{ .cause = .request_rejected, .retry_class = .policy_eligible, .delivery = delivery } }, false);
    }
    try checkUnvalidatedPayload(.cancelled, false);
    try checkUnvalidatedPayload(.{ .complete = .{ .content = "{}", .input_tokens = 5, .output_tokens = 2 } }, true);
}

fn checkUnvalidatedPayload(plan: fake_provider.InvocationPlan, invalid_utf8: bool) !void {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try payloadYaml(&fixture));
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
    if (expected == .invalid) try std.testing.expectEqual(error.InvalidModelEnvelope, decoded.outcome().protocol_rejected) else try std.testing.expect(decoded.outcome().not_decoded == try observationResult(&runner));
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
    for ([_][]const u8{ "{\"answer\":\"retained\"}", "{}", "{" }) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try payloadYaml(&fixture));
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
            .schema_rejected => |reason| try std.testing.expectEqual(.missing_required_property, reason),
            .not_validated => |source| try std.testing.expectEqual(error.InvalidModelEnvelope, source.outcome().protocol_rejected),
        }
        try std.testing.expectEqual(@as(usize, 1), fixture.authorization.destroyed_count);
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
            try std.testing.expectEqual(.operation_failed, runner.bindings().invokeStep(.{ .bytes = "validate-payload" }).rejected);
            try std.testing.expect(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null);
            try expectResponseAccounting(runner, fake, 7);
        }
    }
}

test "YAML payload validation allocation failures release retained candidates on every outcome" {
    for ([_][]const u8{ "{\"answer\":\"value\"}", "{}", "{" }) |body| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try payloadYaml(&fixture));
        try std.testing.checkAllAllocationFailures(std.testing.allocator, payloadAllocationCase, .{ &fixture, graph, body });
        try std.testing.expectEqual(fixture.authorization.prepared_count, fixture.authorization.destroyed_count);
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
    if (body.len > 2) try std.testing.expect(result.outcome() == .valid) else if (body.len == 2) try std.testing.expectEqual(.missing_required_property, result.outcome().schema_rejected) else try std.testing.expectEqual(error.InvalidModelEnvelope, result.outcome().not_validated.outcome().protocol_rejected);
    try expectResponseAccounting(&runner, &fake, 7);
}

test "YAML payload validation remains available at the token budget without another charge" {
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try payloadYaml(&fixture));
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

test "YAML payload publication rejection and cancellation release evidence without consuming the candidate" {
    for ([_]bool{ false, true }) |cancel| {
        var fixture: Fixture = undefined;
        try fixture.init(std.testing.allocator);
        defer fixture.deinit();
        const graph = try fixture.compile(try payloadYaml(&fixture));
        var runner = fixture.runner(graph, std.testing.allocator);
        defer runner.deinit();
        var fake = invocationProvider(&runner, std.testing.allocator);
        fake.invocation_plan.complete.content = "{\"answer\":\"value\"}";
        fixture.native.invoke_model.action = .{ .provider = fake.interface() };
        var spy: PayloadDeltaSpy = .{ .inner = &fixture.native.validate_payload, .cancel = cancel };
        for (&fixture.entries) |*entry| if (std.mem.eql(u8, entry.contract.id, payload_workflow.Validate.contract.id)) {
            entry.binding = bindings.bind(PayloadDeltaSpy, &spy, PayloadDeltaSpy.invoke);
        };
        try prepareInvocable(&runner);
        for ([_][]const u8{ "advance-operation", "call", "validate-response", "decode" }) |step| {
            try std.testing.expectEqual(.ok, runner.bindings().invokeStep(.{ .bytes = step }).outcome);
        }
        runner.runtime = .{ .context = &spy, .status_fn = PayloadDeltaSpy.status };
        const original = try envelopeResult(&runner);
        const outcome = runner.bindings().invokeStep(.{ .bytes = "validate-payload" });
        if (cancel) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.invalid, outcome.outcome);
        try std.testing.expect(runner.envelope.slots[@intFromEnum(payload_workflow.schema.key)] == null);
        try std.testing.expect(try envelopeResult(&runner) == original);
        try std.testing.expectEqualStrings("value", original.outcome().decoded.root().get("answer").?.string);
        try expectResponseAccounting(&runner, &fake, 7);
    }
}

const PayloadDeltaSpy = struct {
    inner: *payload_workflow.Validate,
    cancel: bool,
    invoked: bool = false,

    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        var candidate = try payload_workflow.Validate.invoke(self.inner, input);
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
    var fixture: Fixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const graph = try fixture.compile(try payloadYaml(&fixture));
    for (0..3) |variant| {
        var tampered = graph.*;
        const steps = try fixture.arena.allocator().dupe(compilation.CompiledStep, graph.authority.steps);
        for (steps) |*step| if (std.mem.eql(u8, step.operation_id.bytes, payload_workflow.Validate.contract.id)) {
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
        try std.testing.expectEqual(error.InvalidModelEnvelope, (try envelopeResult(&runner)).outcome().protocol_rejected);
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
        try std.testing.expectEqual(.operation_failed, runner.bindings().invokeStep(.{ .bytes = "decode" }).rejected);
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
        try std.testing.expectEqual(error.InvalidModelEnvelope, decoded.outcome().protocol_rejected);
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
        if (cancel) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.invalid, outcome.outcome);
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
        if (cancel) try std.testing.expectEqual(.cancelled, outcome.rejected) else try std.testing.expectEqual(.invalid, outcome.outcome);
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

fn invocationProvider(runner: *runner_module.Runner, allocator: std.mem.Allocator) fake_provider.FakeLLMProvider {
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

const Observer = struct {
    calls: usize = 0,
    last_attempt: u32 = 0,
    retry_until: u32 = 1,
    consume_attempt: bool = false,
    consume_operation: bool = false,
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
        self.arena = .init(allocator);
        errdefer self.arena.deinit();
        self.services = try providerServices(allocator);
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
        const allocator = self.arena.allocator();
        var parser: @import("adapters/parsers/workflow_definitions.zig").Adapter = .{};
        var schema_parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const raw = try (@import("actions/workflow/parse_workflow_definitions.zig").Action{ .parser = parser.parser() }).execute(allocator, &.{.{ .ordinal = 1, .bytes = bytes }});
        const definitions = try (@import("actions/workflow/validate_workflow_definition_schema.zig").Action{}).execute(allocator, raw);
        const paths = [_][]const u8{ "request.workflow.yaml", "prompt.md", "result.json", "input.txt" };
        const bodies = [_][]const u8{ bytes, prompt_bytes, result_schema, input_bytes };
        var descriptors: [4]inventory.InventoryDescriptor = undefined;
        var accounts: [4]inventory.InventoryAccount = undefined;
        for (paths, bodies, 0..) |path, body, index| {
            descriptors[index] = .{ .path = path, .kind = .file, .identity = .{ .filesystem_id = 1, .file_id = index + 1 }, .size = body.len };
            accounts[index] = .{ .ordinal = @intCast(index + 1), .path = path, .disposition = if (index == 0) .definition else .resource };
        }
        const inv: inventory.Inventory = .{ .capability = roots.registry(self.roots_owner).workflowAuthority(), .descriptors = &descriptors, .accounts = &accounts, .definition_ordinals = &.{1}, .resource_ordinals = &.{ 2, 3, 4 } };
        const manifest = try (@import("actions/workflow/resolve_workflow_resources.zig").Action{}).execute(allocator, inv, definitions);
        const graphs = try (@import("actions/workflow/compile_workflow_graphs.zig").Action{ .registry = &self.registry, .result_schema_compiler = schema_parser.compiler() }).execute(allocator, definitions, inv, manifest, &.{ .{ .ordinal = 2, .bytes = prompt_bytes }, .{ .ordinal = 3, .bytes = result_schema }, .{ .ordinal = 4, .bytes = input_bytes } });
        _ = try (@import("actions/workflow/validate_compiled_workflow_graphs.zig").Action{}).execute(allocator, graphs);
        return &graphs[0];
    }

    fn runner(self: *Fixture, graph: *const compilation.CompiledWorkflow, allocator: std.mem.Allocator) runner_module.Runner {
        var result = runner_module.Runner.init(allocator, .{ .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} }, .graph = graph }, &self.registry, .{ .context = self, .process_fn = noTelemetry }, .{}, &self.services);
        result.provider_clock = self.clock.port();
        return result;
    }
};

fn providerServices(allocator: std.mem.Allocator) !@import("application/model_provider_bootstrap_services.zig").ModelProviderBootstrapServices {
    const registered: contracts.Registry = .{ .entries = &.{.{ .provider = .{ .bytes = "test-provider" }, .model = .{ .bytes = "test-model" }, .implementation_id = .{ .ordinal = 1 }, .config_schema = .empty_object, .capabilities = @import("model_contract_test_fixture.zig").capabilities, .supported_reasoning_efforts = &.{} }} };
    var candidate = try registry.Candidate.init(allocator, 1);
    defer candidate.deinit();
    const contract = registered.entries[0];
    candidate.entries[0] = .{ .provider = contract.provider, .model = contract.model, .implementation_id = contract.implementation_id, .config = .empty_object, .capabilities = contract.capabilities, .supported_reasoning_efforts = &.{} };
    const owner = try registry.createValidated(allocator, candidate, registered);
    errdefer registry.deinitOwner(owner);
    var models: @import("domain/config.zig").ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(allocator);
    try models.slots.map.put(allocator, "selected", .{ .provider = "test-provider", .model = "test-model" });
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
