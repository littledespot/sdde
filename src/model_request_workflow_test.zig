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
    @memcpy(fixture.entries[core.entries.len .. core.entries.len + native.count], &fixture.native.entries);
    var runner = fixture.runner(graph, allocator);
    defer runner.deinit();
    var harness: Harness = .{ .runner = &runner };
    const outcome = harness.run();
    if (outcome == .failed) return error.OutOfMemory;
    try std.testing.expectEqual(.ok, outcome);
}

const Observer = struct {
    calls: usize = 0,
    fn invoke(context: ?*@This(), input: operations.Input) operations.Error!execution.Candidate {
        const self = context.?;
        const request = try requests.readCurrent(&input.step.data, requests.prepared_schema);
        if (request.prepared() == null or input.step.model_binding != request.binding()) return error.OperationExecutionFailed;
        self.calls += 1;
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    services: @import("application/model_provider_bootstrap_services.zig").ModelProviderBootstrapServices,
    roots_owner: *roots.Owner,
    native: native.Assembly,
    observer: Observer,
    entries: [core.entries.len + native.count + 1]operations.Entry,
    registry: operations.Registry,

    fn init(self: *Fixture, allocator: std.mem.Allocator) !void {
        self.arena = .init(allocator);
        errdefer self.arena.deinit();
        self.services = try providerServices(allocator);
        errdefer self.services.deinit();
        self.roots_owner = try rootOwner(allocator);
        self.native.init(allocator);
        self.observer = .{};
        self.entries = core.entries ++ self.native.entries ++ [_]operations.Entry{.{
            .contract = .{ .id = "test.observe-request@1", .kind = .step, .requires = &.{ .model_request_identity_ledger, .prepared_model_request }, .outcomes = &.{.ok}, .side_effect = .none },
            .binding = bindings.bind(Observer, &self.observer, Observer.invoke),
        }};
        self.registry = .{ .operations = &self.entries, .data_schemas = &requests.schemas, .policies = &core.profiles, .gates = &.{} };
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
        return .init(allocator, .{ .invocation = .{ .workflow_id = graph.authority.workflow_id, .arguments = &.{} }, .graph = graph }, &self.registry, .{ .context = self, .process_fn = noTelemetry }, .{}, &self.services);
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
