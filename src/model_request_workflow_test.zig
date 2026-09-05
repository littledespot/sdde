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

const yaml =
    \\schema: workflow/v1
    \\id: arbitrary-request
    \\version: 1
    \\shortcode: PREP
    \\invoke: core.empty-invocation@1
    \\policy: core.capability-free@1
    \\start: initialize
    \\resources: { prompt: prompt.md, result: result.json, input: input.txt }
    \\steps:
    \\  initialize: { use: build-initial-model-request-identity-ledger@1, on: { ok: origin, failed: end.failed } }
    \\  origin:
    \\    use: assign-model-request-id@1
    \\    with: { slot: selected, response-mode: prompt-only, prompt: prompt, result-schema: result, input: input }
    \\    on: { ok: validate, failed: end.failed }
    \\  validate: { use: validate-model-request-binding@1, on: { ok: build, failed: end.failed } }
    \\  build: { use: build-model-request@1, on: { ok: observe, failed: end.failed } }
    \\  observe: { use: test.observe-request@1, on: { ok: end.ok } }
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
        .{ "use: build-model-request@1,", "use: build-model-request@1, with: {slot: selected}," },
        .{ "use: build-model-request@1,", "use: build-model-request@1, with: {prompt: prompt}," },
        .{ "use: validate-model-request-binding@1, on: { ok: build, failed: end.failed }", "use: core.noop@1, on: { ok: build }" },
        .{ "use: build-initial-model-request-identity-ledger@1, on: { ok: origin, failed: end.failed }", "use: core.noop@1, on: { ok: origin }" },
        .{ "use: build-model-request@1", "use: hidden-model-route@1" },
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
            try std.testing.expectEqual(state.current_operations.revision().value != 0, runner.envelope.slots[@intFromEnum(pipeline.DataKey.assigned_provider_operation)] != null);
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
        .{ "use: build-model-request@1", "use: core.noop@1" },
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
    return std.fmt.allocPrint(allocator, "{s}\n  account: {{ use: advance-model-attempt-accounting@1, with: {{retry-limit: {d}}}, on: {{ok: observe, failed: end.failed}} }}\n", .{ source, limit });
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
        .{ "use: advance-model-attempt-accounting@1, with: {retry-limit: 0}, on: {ok: assign-operation, failed: end.failed}", "use: core.noop@1, on: {ok: assign-operation}" },
        .{ "use: build-model-request@1", "use: core.noop@1" },
        .{ "assign-provider-operation@1", "hidden-provider-operation@1" },
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
    return std.fmt.allocPrint(fixture.arena.allocator(), "{s}\n  assign-operation: {{ use: assign-provider-operation@1, with: {{kind: {s}}}, on: {{ok: observe, failed: end.failed}} }}\n", .{ replaced, kind });
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
        .{ "use: assign-provider-operation@1, with: {kind: inference}, on: {ok: authorize, failed: end.failed}", "use: core.noop@1, on: {ok: authorize}" },
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
    return std.fmt.allocPrint(allocator, "{s}\n  authorize: {{ use: prepare-provider-operation-authorization@1, with: {{timeout-ms: 1000}}, on: {{ok: observe, failed: observe, cancelled: end.cancelled}} }}\n", .{replaced});
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
        .{ "use: prepare-provider-operation-authorization@1, with: {timeout-ms: 1000}, on: {ok: advance-request, failed: end.failed, cancelled: end.cancelled}", "use: core.noop@1, on: {ok: advance-request}" },
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
    return std.fmt.allocPrint(fixture.arena.allocator(), "{s}\n  advance-request: {{ use: advance-model-request-lifecycle@1, with: {{transition: invoked}}, on: {{ok: observe, failed: end.failed}} }}\n", .{replaced});
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
            .contract = .{ .id = "test.observe-request@1", .kind = .step, .requires = &.{ .model_request_identity_ledger, .prepared_model_request }, .outcomes = &.{.ok}, .side_effect = .none },
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
        const allocator = self.arena.allocator();
        var parser: @import("adapters/parsers/workflow_definitions.zig").Adapter = .{};
        var schema_parser: @import("adapters/parsers/model_result_schemas.zig").Adapter = .{};
        const raw = try (@import("actions/workflow/parse_workflow_definitions.zig").Action{ .parser = parser.parser() }).execute(allocator, &.{.{ .ordinal = 1, .bytes = bytes }});
        const definitions = try (@import("actions/workflow/validate_workflow_definition_schema.zig").Action{}).execute(allocator, raw);
        const paths = [_][]const u8{ "request.workflow.yaml", "prompt.md", "result.json", "input.txt" };
        const bodies = [_][]const u8{ bytes, prompt_bytes, schema_bytes, input_bytes };
        var descriptors: [4]inventory.InventoryDescriptor = undefined;
        var accounts: [4]inventory.InventoryAccount = undefined;
        for (paths, bodies, 0..) |path, body, index| {
            descriptors[index] = .{ .path = path, .kind = .file, .identity = .{ .filesystem_id = 1, .file_id = index + 1 }, .size = body.len };
            accounts[index] = .{ .ordinal = @intCast(index + 1), .path = path, .disposition = if (index == 0) .definition else .resource };
        }
        const inv: inventory.Inventory = .{ .capability = roots.registry(self.roots_owner).workflowAuthority(), .descriptors = &descriptors, .accounts = &accounts, .definition_ordinals = &.{1}, .resource_ordinals = &.{ 2, 3, 4 } };
        const manifest = try (@import("actions/workflow/resolve_workflow_resources.zig").Action{}).execute(allocator, inv, definitions);
        const graphs = try (@import("actions/workflow/compile_workflow_graphs.zig").Action{ .registry = &self.registry, .result_schema_compiler = schema_parser.compiler() }).execute(allocator, definitions, inv, manifest, &.{ .{ .ordinal = 2, .bytes = prompt_bytes }, .{ .ordinal = 3, .bytes = schema_bytes }, .{ .ordinal = 4, .bytes = input_bytes } });
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
        return engine.run(.{ .context = self, .vtable = &.{ .validate_operation_registry = selected, .parse_invocation = selected, .select_workflow = selected, .prepare_workflow = ready, .selected_graph = graph, .invoke_invocation = invocation, .invoke_step = step } }).execution;
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
