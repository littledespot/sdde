const std = @import("std");
const fixture = @import("model_contract_test_fixture.zig");
const limits = @import("domain/model_limits.zig");
const model = @import("domain/workflow_model.zig");
const contracts = @import("domain/llm_provider_contracts.zig");
const operation = @import("domain/workflow_operation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const provider_registry = @import("domain/llm_provider_registry.zig");

test "capacity intersection uses every strictest canonical and wire bound" {
    inline for (@typeInfo(limits.Limits).@"struct".fields) |field| {
        var narrowed = fixture.capacity;
        @field(narrowed.canonical, field.name) /= 2;
        const left = limits.Capacity.intersect(narrowed, fixture.capacity).?;
        const right = limits.Capacity.intersect(fixture.capacity, narrowed).?;
        try std.testing.expectEqualDeep(narrowed, left);
        try std.testing.expectEqualDeep(left, right);
    }
    inline for (@typeInfo(limits.WireBudgets).@"struct".fields) |field| {
        var narrowed = fixture.capacity;
        @field(narrowed.wire, field.name) /= 2;
        try std.testing.expectEqualDeep(narrowed, limits.Capacity.intersect(narrowed, fixture.capacity).?);
        try std.testing.expectEqualDeep(narrowed, limits.Capacity.intersect(fixture.capacity, narrowed).?);
    }
}

test "every absent memory or transport safety bound rejects" {
    inline for (@typeInfo(limits.Limits).@"struct".fields) |field| {
        var invalid = fixture.capacity;
        @field(invalid.canonical, field.name) = 0;
        try std.testing.expect(!invalid.isValid());
        try std.testing.expect(limits.Capacity.intersect(invalid, fixture.capacity) == null);
    }
    inline for (@typeInfo(limits.WireBudgets).@"struct".fields) |field| {
        var invalid = fixture.capacity;
        @field(invalid.wire, field.name) = 0;
        try std.testing.expect(!invalid.isValid());
        try std.testing.expect(limits.Capacity.intersect(fixture.capacity, invalid) == null);
    }
}

test "memory safety contract carries no model token ceilings" {
    try std.testing.expect(!@hasField(limits.Limits, "maximum_input_tokens"));
    try std.testing.expect(!@hasField(limits.Limits, "maximum_output_tokens"));
    try std.testing.expect(!@hasField(limits.Limits, "context_window_tokens"));
    try std.testing.expect(!@hasDecl(limits.Limits, "acceptsInputTokens"));
}

test "compiled model requirements intersect engine operation and explicit YAML capacities" {
    var engine_capacity = fixture.capacity;
    engine_capacity.canonical.maximum_input_bytes = 2048;
    var operation_capacity = fixture.capacity;
    operation_capacity.canonical.maximum_input_bytes = 500;
    var values = fixture.compiled_parameters;
    values[1].value = .{ .integer = 30 };
    const resolved = model.resolve(engine_capacity, operation_capacity, &values).?;
    try std.testing.expectEqual(@as(u32, 500), resolved.capacity.canonical.maximum_input_bytes);
    try std.testing.expectEqual(@as(u64, 30), resolved.capacity.canonical.maximum_output_bytes);
    try std.testing.expect(resolved.controls.temperature == null);
    try std.testing.expectEqualDeep(fixture.capacity, fixture.capabilities.capacity);
}

test "missing malformed excessive and duplicate model parameters cannot create requirements" {
    for (0..fixture.compiled_parameters.len) |index| {
        var values = fixture.compiled_parameters;
        values[index].id.bytes = "unrelated";
        try std.testing.expect(model.resolve(fixture.capacity, fixture.capacity, &values) == null);
    }
    inline for (.{ @as(i64, 0), -1, std.math.maxInt(u32) + 1 }) |invalid| {
        var values = fixture.compiled_parameters;
        values[0].value = .{ .integer = invalid };
        try std.testing.expect(model.resolve(fixture.capacity, fixture.capacity, &values) == null);
    }
    var malformed = fixture.compiled_parameters;
    malformed[0].value = .{ .string = "1024" };
    try std.testing.expect(model.resolve(fixture.capacity, fixture.capacity, &malformed) == null);
    malformed = fixture.compiled_parameters;
    malformed[2].value = .{ .enumeration = "automatic" };
    try std.testing.expect(model.resolve(fixture.capacity, fixture.capacity, &malformed) == null);
    const duplicate = fixture.compiled_parameters ++ .{fixture.compiled_parameters[0]};
    try std.testing.expect(model.resolve(fixture.capacity, fixture.capacity, &duplicate) == null);
    const duplicate_control = fixture.compiled_parameters ++ [_]@import("domain/workflow_compilation.zig").CompiledParameter{
        .{ .id = .{ .bytes = "temperature" }, .value = .{ .integer = 0 } },
        .{ .id = .{ .bytes = "temperature" }, .value = .{ .integer = 1000 } },
    };
    try std.testing.expect(model.resolve(fixture.capacity, fixture.capacity, &duplicate_control) == null);
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

test "catalogue candidate cannot forge capability or increase trusted limits" {
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
    candidate.entries[0].capabilities.capacity.canonical.maximum_output_bytes += 1;
    try std.testing.expectError(error.InvalidLLMProviderRegistry, provider_registry.createValidated(std.testing.allocator, candidate, registered));
    try std.testing.expectEqual(@as(u32, 1024), provider_registry.registry(owner).resolveId(.{ .ordinal = 1 }).?.capabilities.capacity.canonical.maximum_output_bytes);
    candidate.entries[0].capabilities = fixture.capabilities;
    candidate.entries[0].capabilities.temperature = false;
    try std.testing.expectError(error.InvalidLLMProviderRegistry, provider_registry.createValidated(std.testing.allocator, candidate, registered));
}

test "model operation registry requires explicit engine and operation ceilings without defaults" {
    var entry = model_operation;
    var registry: operations.Registry = .{
        .operations = &.{entry},
        .model_capacity = fixture.capacity,
        .policies = &.{},
        .gates = &.{},
    };
    try std.testing.expect(registry.validate());
    registry.model_capacity = null;
    try std.testing.expect(!registry.validate());
    registry.model_capacity = fixture.capacity;
    entry.contract.model_capacity = null;
    registry.operations = &.{entry};
    try std.testing.expect(!registry.validate());
    entry = model_operation;
    entry.contract.parameters = model_operation.contract.parameters[0..1];
    registry.operations = &.{entry};
    try std.testing.expect(!registry.validate());
    try std.testing.expect(!@hasField(operation.PolicyProfile, "model_capacity"));
    try std.testing.expect(!@hasField(@import("domain/config.zig").ModelsConfig, "model_capacity"));
}

test "provider operations reject request bounds controls and receive budgets outside binding" {
    var authorization: @import("provider_authorization_test_fixture.zig").Fixture = undefined;
    try authorization.init(std.testing.allocator);
    defer authorization.deinit();
    const started = try authorization.startCount();
    const provider = @import("domain/llm_provider_operation.zig");
    try std.testing.expect(provider.validateCountInvocation(&authorization.provider_binding, &authorization.request, started.invoked));
    var request = authorization.request;
    request.limits.maximum_input_bytes += 1;
    try std.testing.expect(!provider.validateCountInvocation(&authorization.provider_binding, &request, started.invoked));
    request = authorization.request;
    request.controls.temperature = null;
    try std.testing.expect(!provider.validateCountInvocation(&authorization.provider_binding, &request, started.invoked));
    request = authorization.request;
    request.response_guidance_mode = .native_schema;
    try std.testing.expect(!provider.validateCountInvocation(&authorization.provider_binding, &request, started.invoked));
    var invoked = started.invoked.*;
    invoked.receive_budgets.maximum_body_bytes = authorization.provider_binding.capacity.wire.maximum_response_body_bytes + 1;
    try std.testing.expect(!provider.validateCountInvocation(&authorization.provider_binding, &authorization.request, &invoked));
    const evidence = authorization.evidence();
    const inference = try authorization.finishCountAndStartInference(evidence);
    try std.testing.expect(provider.validateInferenceInvocation(&authorization.provider_binding, &authorization.request, inference.invoked));
    invoked = inference.invoked.*;
    invoked.receive_budgets.maximum_header_count = authorization.provider_binding.capacity.wire.maximum_response_header_count + 1;
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
        .model_capacity = fixture.capacity,
    },
    .binding = @import("application/workflow_operation_binding.zig").bind(@import("workflow_binding_test_fixture.zig").ModelContext, &@import("workflow_binding_test_fixture.zig").model_context, @import("workflow_binding_test_fixture.zig").unusedModel),
};
