const std = @import("std");
const fixture = @import("model_contract_test_fixture.zig");
const model = @import("domain/workflow_model.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const operation = @import("domain/workflow_operation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const provider_registry = @import("domain/llm_provider_registry.zig");

test "compiled model requirements need only explicit response mode and supported controls" {
    const resolved = model.resolve(&fixture.compiled_parameters).?;
    try std.testing.expectEqual(.prompt_only, resolved.response_mode);
    try std.testing.expect(resolved.controls.temperature == null);
    const controlled = fixture.compiled_parameters ++ [_]@import("domain/workflow_compilation.zig").CompiledParameter{
        .{ .id = .{ .bytes = "temperature" }, .value = .{ .integer = 1000 } },
    };
    try std.testing.expectEqual(@as(u16, 1000), model.resolve(&controlled).?.controls.temperature.?.value);
}

test "missing malformed and duplicate model controls cannot create requirements" {
    try std.testing.expect(model.resolve(&.{}) == null);
    var malformed = fixture.compiled_parameters;
    malformed[0].value = .{ .integer = 1 };
    try std.testing.expect(model.resolve(&malformed) == null);
    malformed[0].value = .{ .enumeration = "automatic" };
    try std.testing.expect(model.resolve(&malformed) == null);
    const duplicate = fixture.compiled_parameters ++ .{fixture.compiled_parameters[0]};
    try std.testing.expect(model.resolve(&duplicate) == null);
    inline for (.{ @as(i64, -1), 1001 }) |invalid| {
        const values = fixture.compiled_parameters ++ [_]@import("domain/workflow_compilation.zig").CompiledParameter{
            .{ .id = .{ .bytes = "temperature" }, .value = .{ .integer = invalid } },
        };
        try std.testing.expect(model.resolve(&values) == null);
    }
    const duplicate_control = fixture.compiled_parameters ++ [_]@import("domain/workflow_compilation.zig").CompiledParameter{
        .{ .id = .{ .bytes = "temperature" }, .value = .{ .integer = 0 } },
        .{ .id = .{ .bytes = "temperature" }, .value = .{ .integer = 1000 } },
    };
    try std.testing.expect(model.resolve(&duplicate_control) == null);
}

test "model contracts validate capabilities without granting unsupported operations" {
    var contract = provider_contract;
    try (contracts.Registry{ .entries = &.{contract} }).validate();
    contract.capabilities.input_token_count = false;
    try std.testing.expectError(error.InvalidProviderModelContracts, (contracts.Registry{ .entries = &.{contract} }).validate());
    contract.capabilities.exact_token_counter = .unavailable;
    try (contracts.Registry{ .entries = &.{contract} }).validate();
    try std.testing.expect(contract.capabilities.supports(.prompt_only, .{}));
    contract = provider_contract;
    contract.capabilities.inference = false;
    try std.testing.expectError(error.InvalidProviderModelContracts, (contracts.Registry{ .entries = &.{contract} }).validate());
    contract = provider_contract;
    contract.capabilities.temperature = false;
    try std.testing.expect(contract.capabilities.supports(.prompt_only, .{}));
    try std.testing.expect(!contract.capabilities.supports(.prompt_only, .{ .temperature = .{ .value = 0 } }));
    try std.testing.expect(!fixture.capabilities.supports(.native_schema, .{}));
}

test "catalogue candidate cannot substitute compiled capability facts" {
    var candidate = try provider_registry.Candidate.init(std.testing.allocator, 1);
    defer candidate.deinit();
    candidate.entries[0] = .{
        .provider = provider_contract.provider,
        .model = provider_contract.model,
        .implementation_id = provider_contract.implementation_id,
        .config = .empty_object,
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
    entry.contract.parameters = model.parameters[0..];
    registry.operations = &.{entry};
    try std.testing.expect(!registry.validate());
    entry = model_operation;
    entry.contract.parameters = model_operation.contract.parameters[0..1];
    registry.operations = &.{entry};
    try std.testing.expect(!registry.validate());
}

test "registered model contracts cannot restore retired size parameters" {
    inline for (.{ "input-bytes", "output-bytes", "input-tokens", "output-tokens" }) |retired| {
        var entry = model_operation;
        const parameters = [_]operation.ParameterDescriptor{
            .{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
        } ++ model.parameters ++ [_]operation.ParameterDescriptor{
            .{ .id = retired, .kind = .integer, .required = true, .workflow_definition_safe = true },
        };
        entry.contract.parameters = &parameters;
        const registry: operations.Registry = .{ .operations = &.{entry}, .policies = &.{}, .gates = &.{} };
        try std.testing.expect(!registry.validate());
        const values = fixture.compiled_parameters ++ [_]@import("domain/workflow_compilation.zig").CompiledParameter{
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
        .id = "test.generate@1",
        .kind = .step,
        .parameters = &([_]operation.ParameterDescriptor{.{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true }} ++ model.parameters),
        .outcomes = &.{.ok},
        .side_effect = .none,
    },
    .binding = @import("application/workflow_operation_binding.zig").bind(@import("workflow_binding_test_fixture.zig").ModelContext, &@import("workflow_binding_test_fixture.zig").model_context, @import("workflow_binding_test_fixture.zig").unusedModel),
};
