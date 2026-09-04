const std = @import("std");
const decode_toolkit = @import("actions/config/decode_sddtoolkit_config.zig");
const resolve_binding = @import("actions/provider/resolve_provider_model_binding.zig");
const provider_services = @import("application/model_provider_bootstrap_services.zig");
const workflow_runner = @import("application/workflow_pipeline_runner.zig");
const config = @import("domain/config.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const identity = @import("domain/llm_provider_identity.zig");
const provider_registry = @import("domain/llm_provider_registry.zig");
const repository_allowlist = @import("domain/repository_model_allowlist.zig");
const workflow = @import("domain/workflow.zig");
const compilation = @import("domain/workflow_compilation.zig");
const execution = @import("domain/workflow_execution.zig");
const pipeline = @import("domain/pipeline.zig");
const telemetry = @import("domain/telemetry.zig");
const registry_service = @import("application/llm_provider_registry_service.zig");
const operation_registry = @import("ports/workflow_operation_registry.zig");
const telemetry_barrier = @import("ports/telemetry_barrier.zig");

const provider_id = identity.ProviderId.parse("compiled-provider").?;
const model_id = identity.ModelId.parse("model-a").?;
const implementation_id = contracts.RegisteredProviderImplementationId.init(1).?;
const provider_contracts: contracts.Registry = .{ .entries = &.{.{
    .provider = provider_id,
    .model = model_id,
    .implementation_id = implementation_id,
    .config_schema = .empty_object,
    .supported_reasoning_efforts = &.{"low"},
}} };

test "YAML-declared model slot resolves to one immutable provider binding" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    const resolved = try (resolve_binding.Action{}).execute(
        &model_graph,
        model_step.id,
        fixture.services.registry(),
        fixture.services.allowlist(),
    );
    try std.testing.expectEqualStrings("custom-generation", resolved.operation_id.workflow_id.bytes);
    try std.testing.expectEqual(@as(u32, 1), resolved.operation_id.workflow_version);
    try std.testing.expectEqualStrings("generate", resolved.operation_id.workflow_step_id.bytes);
    try std.testing.expectEqualStrings("spec-generation", resolved.slot_id.bytes);
    try std.testing.expect(resolved.registry_entry.id.eql(
        fixture.services.allowlist().resolveSlot(resolved.slot_id).?.registry_entry_id,
    ));
    try std.testing.expectEqualStrings("low", resolved.reasoning_effort.?);
}

test "binding rejects absent slot authority and non-model steps" {
    var fixture = try Fixture.init();
    defer fixture.deinit();

    var missing_slot = model_step;
    missing_slot.parameters = &.{.{
        .id = .{ .bytes = "slot" },
        .value = .{ .model_slot = identity.ModelSlotId.parse("not-allowed").? },
    }};
    var missing_graph = model_graph;
    missing_graph.authority.steps = &.{missing_slot};
    try std.testing.expectError(
        error.ProviderModelBindingInvalid,
        (resolve_binding.Action{}).execute(
            &missing_graph,
            missing_slot.id,
            fixture.services.registry(),
            fixture.services.allowlist(),
        ),
    );

    var non_model = model_step;
    non_model.capabilities = &.{};
    var non_model_graph = model_graph;
    non_model_graph.authority.steps = &.{non_model};
    try std.testing.expectError(
        error.ProviderModelBindingInvalid,
        (resolve_binding.Action{}).execute(
            &non_model_graph,
            non_model.id,
            fixture.services.registry(),
            fixture.services.allowlist(),
        ),
    );
}

test "generic runner exposes a binding only to the active model operation" {
    var fixture = try Fixture.init();
    defer fixture.deinit();
    var control: OperationControl = .{};
    var registry = control.registry();
    var barrier: FakeBarrier = .{};
    var runner = workflow_runner.Runner.init(
        std.testing.allocator,
        .{
            .invocation = .{ .workflow_id = model_graph.authority.workflow_id, .arguments = &.{} },
            .graph = &model_graph,
        },
        &registry,
        barrier.port(),
        .{},
        &fixture.services,
    );
    defer runner.deinit();

    try std.testing.expectEqual(workflow.OutcomeTag.ok, runner.bindings().invokeStep(model_step.id).outcome);
    try std.testing.expectEqual(@as(usize, 1), control.calls);
    try std.testing.expectEqualStrings("spec-generation", control.observed_slot.?);

    var runner_without_authority = workflow_runner.Runner.init(
        std.testing.allocator,
        runner.selected,
        &registry,
        barrier.port(),
        .{},
        null,
    );
    defer runner_without_authority.deinit();
    try std.testing.expectEqual(
        workflow.OutcomeTag.failed,
        runner_without_authority.bindings().invokeStep(model_step.id).outcome,
    );
    try std.testing.expectEqual(@as(usize, 1), control.calls);
}

const Fixture = struct {
    toolkit: config.Owned,
    services: provider_services.ModelProviderBootstrapServices,

    fn init() !Fixture {
        var toolkit = try (decode_toolkit.Action{}).execute(std.testing.allocator, toolkit_config);
        errdefer toolkit.deinit();
        var candidate = try provider_registry.Candidate.init(std.testing.allocator, 1);
        defer candidate.deinit();
        candidate.entries[0] = .{
            .provider = provider_id,
            .model = model_id,
            .implementation_id = implementation_id,
            .config = .empty_object,
            .supported_reasoning_efforts = &.{"low"},
        };
        const registry_owner = try provider_registry.createValidated(
            std.testing.allocator,
            candidate,
            provider_contracts,
        );
        errdefer provider_registry.deinitOwner(registry_owner);
        const allowlist_owner = try repository_allowlist.createValidated(
            std.testing.allocator,
            &toolkit.value().models,
            provider_registry.registry(registry_owner),
        );
        return .{
            .toolkit = toolkit,
            .services = .init(registry_service.LLMProviderRegistryService.init(registry_owner), allowlist_owner),
        };
    }

    fn deinit(self: *Fixture) void {
        self.services.deinit();
        self.toolkit.deinit();
        self.* = undefined;
    }
};

const model_parameters = [_]compilation.CompiledParameter{.{
    .id = .{ .bytes = "slot" },
    .value = .{ .model_slot = identity.ModelSlotId.parse("spec-generation").? },
}};
const model_step: compilation.CompiledStep = .{
    .id = .{ .bytes = "generate" },
    .operation_id = .{ .bytes = "model.generate@1" },
    .parameters = &model_parameters,
    .requires = &.{},
    .produces = &.{},
    .replaces = &.{},
    .invalidates = &.{},
    .outcomes = &.{.ok},
    .side_effect = .none,
    .gates = &.{},
    .capabilities = &.{"model-provider"},
    .retry_authority = null,
};
const model_graph: compilation.CompiledWorkflow = .{
    .source_ordinal = 1,
    .shortcode = telemetry.WorkflowShortcode.parse("TEST") catch unreachable,
    .authority = .{
        .workflow_id = .{ .bytes = "custom-generation" },
        .workflow_version = 1,
        .invocation_operation_id = .{ .bytes = "test.empty@1" },
        .policy_profile_id = .{ .bytes = "test.model-policy@1" },
        .total_model_token_budget = .{ .value = 1000 },
        .start_step_id = model_step.id,
        .invocation_outputs = &.{},
        .resources = &.{},
        .steps = &.{model_step},
        .transitions = &.{.{ .from = model_step.id, .outcome = .ok, .target = .{ .terminal = .ok } }},
        .maximum_step_executions = 1,
    },
};

const OperationControl = struct {
    calls: usize = 0,
    observed_slot: ?[]const u8 = null,
    entries: [1]operation_registry.Entry = undefined,

    fn registry(self: *OperationControl) operation_registry.Registry {
        self.entries[0] = .{
            .contract = .{
                .id = "model.generate@1",
                .kind = .step,
                .parameters = &.{.{
                    .id = "slot",
                    .kind = .model_slot,
                    .required = true,
                    .workflow_definition_safe = true,
                }},
                .outcomes = &.{.ok},
                .side_effect = .none,
                .capabilities = &.{"model-provider"},
            },
            .context = self,
            .invoke_fn = invoke,
        };
        return .{
            .operations = &self.entries,
            .policies = &.{.{
                .id = "test.model-policy@1",
                .allowed_capabilities = &.{"model-provider"},
                .allowed_terminal_outcomes = &.{.ok},
                .total_model_token_budget = .{ .value = 1000 },
            }},
            .gates = &.{},
            .capabilities = &.{"model-provider"},
        };
    }

    fn invoke(context: ?*anyopaque, input: operation_registry.Input) operation_registry.Error!execution.Candidate {
        const self: *OperationControl = @ptrCast(@alignCast(context.?));
        const step = switch (input) {
            .step => |value| value,
            .invocation => return error.OperationExecutionFailed,
        };
        const bound = step.model_binding orelse return error.OperationExecutionFailed;
        self.calls += 1;
        self.observed_slot = bound.slot_id.bytes;
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const FakeBarrier = struct {
    fn port(self: *FakeBarrier) telemetry_barrier.Barrier {
        return .{ .context = self, .process_fn = process };
    }

    fn process(_: *anyopaque, _: telemetry.WorkflowTelemetryFact) execution.Candidate {
        return .{ .outcome = .ok, .delta = .{} };
    }
};

const toolkit_config =
    \\{"logs":{"level":"info","console":false,"promptCapture":[]},"models":{"slots":{"spec-generation":{"provider":"compiled-provider","model":"model-a","reasoningEffort":"low"}}},"paths":{"specs":"specs","references":"references","specsArchive":"specs/archive","workflows":"workflows","toolchainPreset":"presets","principles":"principles","templates":"templates","providers":".sddproviders.json"}}
;
