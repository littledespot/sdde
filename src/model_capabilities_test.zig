const std = @import("std");
const fixture = @import("model_contract_test_fixture.zig");
const model = @import("domain/workflow_model.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const operation = @import("domain/workflow_operation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const provider_registry = @import("domain/llm_provider_registry.zig");

test "temperature policy requires zero exactly when the registered model supports it" {
    for ([_]bool{ false, true }) |supported| {
        var capabilities = fixture.capabilities;
        capabilities.temperature = supported;
        const selected = capabilities.inferenceControls();
        try std.testing.expectEqual(supported, selected.temperature != null);
        if (selected.temperature) |temperature| try std.testing.expectEqual(@as(f64, 0), temperature.wireValue());
        try std.testing.expect(capabilities.supports(.prompt_only, selected));
        try std.testing.expect(!capabilities.supports(.prompt_only, .forTemperatureSupport(!supported)));
    }
}

test "workflow requirements reject response mode overrides and duplicate parameters" {
    try std.testing.expect(model.resolve(&.{}) == null);
    const parameter = @import("domain/workflow_compilation.zig").CompiledParameter;
    const slot: parameter = .{ .id = .{ .bytes = "slot" }, .value = .{ .model_slot = .{ .bytes = "selected" } } };
    try std.testing.expectEqualStrings("selected", model.resolve(&.{slot}).?.slot.bytes);
    const duplicate = [_]parameter{
        .{ .id = .{ .bytes = "slot" }, .value = .{ .model_slot = .{ .bytes = "selected" } } },
        .{ .id = .{ .bytes = "slot" }, .value = .{ .model_slot = .{ .bytes = "selected" } } },
    };
    try std.testing.expect(model.resolve(&duplicate) == null);
    for ([_][]const u8{ "prompt-only", "native-schema", "automatic" }) |mode| {
        try std.testing.expect(model.resolve(&.{ slot, .{ .id = .{ .bytes = "response-mode" }, .value = .{ .enumeration = mode } } }) == null);
    }
}

test "request result selection keeps exactly one canonical schema or configured part" {
    const parameter = @import("domain/workflow_compilation.zig").CompiledParameter;
    const resource: parameter = .{ .id = .{ .bytes = "result-schema" }, .value = .{ .resource = .{ .bytes = "canonical" } } };
    const part: parameter = .{ .id = .{ .bytes = "composition-part" }, .value = .{ .string = "content" } };
    try std.testing.expect(model.validResultSelection(&.{resource}));
    try std.testing.expect(model.validResultSelection(&.{part}));
    try std.testing.expect(!model.validResultSelection(&.{}));
    try std.testing.expect(!model.validResultSelection(&.{ resource, part }));
    try std.testing.expect(!model.validResultSelection(&.{ part, .{ .id = .{ .bytes = "input" }, .value = .{ .resource = .{ .bytes = "other" } } } }));
    try std.testing.expect(!model.validResultSelection(&.{ part, .{ .id = .{ .bytes = "result-selection" }, .value = .{ .enumeration = "input" } } }));
    try std.testing.expect(!model.validResultSelection(&.{.{ .id = part.id, .value = .{ .string = "unknown/part" } }}));
    try std.testing.expect(!model.validResultSelection(&.{.{ .id = resource.id, .value = .{ .string = "canonical" } }}));
}

test "model contracts validate capabilities without granting unsupported operations" {
    var contract = provider_contract;
    try (contracts.Registry{ .entries = &.{contract} }).validate();
    contract.capabilities.input_token_count = false;
    try std.testing.expectError(error.InvalidProviderModelContracts, (contracts.Registry{ .entries = &.{contract} }).validate());
    contract.capabilities.exact_token_counter = .unavailable;
    try (contracts.Registry{ .entries = &.{contract} }).validate();
    try std.testing.expect(contract.capabilities.supports(.prompt_only, contract.capabilities.inferenceControls()));
    contract = provider_contract;
    contract.capabilities.inference = false;
    try std.testing.expectError(error.InvalidProviderModelContracts, (contracts.Registry{ .entries = &.{contract} }).validate());
    contract = provider_contract;
    contract.capabilities.temperature = false;
    try std.testing.expect(contract.capabilities.supports(.prompt_only, contract.capabilities.inferenceControls()));
    try std.testing.expect(!contract.capabilities.supports(.prompt_only, .{ .temperature = .zero }));
    try std.testing.expect(!fixture.capabilities.supports(.native_schema, fixture.capabilities.inferenceControls()));
}

test "catalogue candidate cannot substitute compiled capability facts" {
    var candidate = try provider_registry.Candidate.init(std.testing.allocator, 1);
    defer candidate.deinit();
    candidate.entries[0] = .{
        .provider = provider_contract.provider,
        .model = provider_contract.model,
        .implementation_id = provider_contract.implementation_id,
        .config = .empty_object,
        .json = false,
        .capabilities = fixture.capabilities,
        .supported_reasoning_efforts = &.{},
    };
    const registered: contracts.Registry = .{ .entries = &.{provider_contract} };
    const owner = try provider_registry.createValidated(std.testing.allocator, candidate, registered);
    defer provider_registry.deinitOwner(owner);
    candidate.entries[0].capabilities.temperature = false;
    try std.testing.expectError(error.InvalidLLMProviderRegistry, provider_registry.createValidated(std.testing.allocator, candidate, registered));
    try std.testing.expect(provider_registry.registry(owner).resolveId(.{ .ordinal = 1 }).?.capabilities.temperature);
}

test "model registration requires a typed slot but no capacity configuration" {
    var entry = model_operation;
    var registry: operations.Registry = .{ .operations = &.{entry}, .policies = &.{}, .gates = &.{} };
    try std.testing.expect(registry.validate());
    try std.testing.expect(entry.contract.requiresModelBinding());
    entry.contract.parameters = &.{};
    registry.operations = &.{entry};
    try std.testing.expect(!registry.validate());
}

test "registered model contracts cannot restore temperature or retired size parameters" {
    inline for (.{ "response-mode", "temperature", "input-bytes", "output-bytes", "input-tokens", "output-tokens" }) |retired| {
        var entry = model_operation;
        const parameters = [_]operation.ParameterDescriptor{
            .{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
        } ++ [_]operation.ParameterDescriptor{
            .{ .id = retired, .kind = .integer, .required = true, .workflow_definition_safe = true },
        };
        entry.contract.parameters = &parameters;
        const registry: operations.Registry = .{ .operations = &.{entry}, .policies = &.{}, .gates = &.{} };
        try std.testing.expect(!registry.validate());
        const values = [_]@import("domain/workflow_compilation.zig").CompiledParameter{
            .{ .id = .{ .bytes = "slot" }, .value = .{ .model_slot = .{ .bytes = "selected" } } },
            .{ .id = .{ .bytes = retired }, .value = .{ .integer = 1 } },
        };
        try std.testing.expect(model.resolve(&values) == null);
    }
}

test "provider operations retain binding control mode and deadline checks" {
    var authorization: @import("provider_authorization_test_fixture.zig").Fixture = undefined;
    try authorization.init(std.testing.allocator);
    defer authorization.deinit();
    const started = try authorization.startCount();
    const provider = @import("domain/llm_provider_operation.zig");
    try std.testing.expect(provider.validateCountInvocation(&authorization.provider_binding, &authorization.request, started.invoked));
    var request = authorization.request;
    request.controls.temperature = null;
    try std.testing.expect(!provider.validateCountInvocation(&authorization.provider_binding, &request, started.invoked));
    request = authorization.request;
    request.response_guidance_mode = .native_schema;
    try std.testing.expect(!provider.validateCountInvocation(&authorization.provider_binding, &request, started.invoked));
    var invoked = started.invoked.*;
    invoked.deadline_monotonic_ms = 0;
    try std.testing.expect(!provider.validateCountInvocation(&authorization.provider_binding, &authorization.request, &invoked));
    const evidence = authorization.evidence();
    const inference = try authorization.finishCountAndStartInference(evidence);
    try std.testing.expect(provider.validateInferenceInvocation(&authorization.provider_binding, &authorization.request, inference.invoked));
    invoked = inference.invoked.*;
    invoked.deadline_monotonic_ms = 0;
    try std.testing.expect(!provider.validateInferenceInvocation(&authorization.provider_binding, &authorization.request, &invoked));
}

const provider_contract: contracts.ProviderModelContract = .{
    .provider = .{ .bytes = "compiled-provider" },
    .model = .{ .bytes = "test-model" },
    .implementation_id = .{ .ordinal = 1 },
    .config_schema = .empty_object,
    .capabilities = fixture.capabilities,
};
const model_operation: operations.Entry = .{
    .contract = .{
        .id = "test.generate",
        .kind = .step,
        .parameters = &([_]operation.ParameterDescriptor{.{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true }}),
        .outcomes = &.{.ok},
        .side_effect = .none,
    },
    .binding = @import("application/workflow_operation_binding.zig").bind(@import("workflow_binding_test_fixture.zig").ModelContext, &@import("workflow_binding_test_fixture.zig").model_context, @import("workflow_binding_test_fixture.zig").unusedModel),
};
