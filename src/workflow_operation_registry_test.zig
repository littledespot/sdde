const std = @import("std");
const operation = @import("domain/workflow_operation.zig");
const operations = @import("ports/workflow_operation_registry.zig");
const Entry = operations.Entry;
const Registry = operations.Registry;
const bindings = @import("application/workflow_operation_binding.zig");
const fixture = @import("workflow_binding_test_fixture.zig");

test "one registry rejects duplicate and structurally invalid operations" {
    try std.testing.expect(!@hasField(operation.PolicyProfile, "retry_limit"));
    try std.testing.expect(!@hasField(operation.PolicyProfile, "attempts"));
    const noop: Entry = .{
        .contract = .{ .id = "core.noop@1", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none },
        .binding = bindings.bind(void, null, fixture.unused),
    };
    const valid: Registry = .{
        .operations = &.{noop},
        .policies = &.{.{
            .id = "core.safe@1",
            .allowed_capabilities = &.{},
            .allowed_terminal_outcomes = &.{.ok},
            .total_model_token_budget = .{ .value = 1 },
        }},
        .gates = &.{},
    };
    try std.testing.expect(valid.validate());
    var duplicate = valid;
    duplicate.operations = &.{ noop, noop };
    try std.testing.expect(!duplicate.validate());

    const hidden_invocation: Entry = .{
        .contract = .{ .id = "core.hidden@1", .kind = .invocation, .outcomes = &.{ .ok, .failed }, .side_effect = .none },
        .binding = bindings.bind(void, null, fixture.unused),
    };
    duplicate.operations = &.{hidden_invocation};
    try std.testing.expect(!duplicate.validate());

    const model_without_slot: Entry = .{
        .contract = .{
            .id = "model.invalid@1",
            .kind = .step,
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .binding = bindings.bind(fixture.ModelContext, &fixture.model_context, fixture.unusedModel),
    };
    var invalid_model_registry = valid;
    invalid_model_registry.operations = &.{model_without_slot};
    try std.testing.expect(!invalid_model_registry.validate());

    const hidden_slot: Entry = .{
        .contract = .{
            .id = "model.hidden-slot@1",
            .kind = .step,
            .parameters = &.{.{
                .id = "slot",
                .kind = .model_slot,
                .required = true,
                .workflow_definition_safe = true,
            }},
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .binding = bindings.bind(void, null, fixture.unused),
    };
    invalid_model_registry.operations = &.{hidden_slot};
    try std.testing.expect(!invalid_model_registry.validate());

    var zero_budget = valid;
    zero_budget.policies = &.{.{
        .id = "core.safe@1",
        .allowed_capabilities = &.{},
        .allowed_terminal_outcomes = &.{.ok},
        .total_model_token_budget = .{ .value = 0 },
    }};
    try std.testing.expect(!zero_budget.validate());

    const hidden_retry: Entry = .{
        .contract = .{
            .id = "core.hidden-retry@1",
            .kind = .step,
            .parameters = &.{.{
                .id = "retry-limit",
                .kind = .integer,
                .required = true,
                .workflow_definition_safe = true,
                .integer_min = 0,
                .integer_max = 2,
            }},
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .binding = bindings.bind(void, null, fixture.unused),
    };
    var invalid_retry_registry = valid;
    invalid_retry_registry.operations = &.{hidden_retry};
    try std.testing.expect(!invalid_retry_registry.validate());

    var declared_retry = hidden_retry;
    declared_retry.contract.retry_limit = .{ .maximum = 2 };
    try std.testing.expect((Registry{
        .operations = &.{declared_retry},
        .policies = valid.policies,
        .gates = &.{},
    }).validate());
    declared_retry.contract.parameters = &.{.{
        .id = "retry-limit",
        .kind = .integer,
        .required = true,
        .workflow_definition_safe = true,
        .integer_min = 0,
        .integer_max = 3,
    }};
    invalid_retry_registry.operations = &.{declared_retry};
    try std.testing.expect(!invalid_retry_registry.validate());
}

test "validation action rejects a duplicate operation identity" {
    const entry: Entry = .{ .contract = .{ .id = "test.noop@1", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none }, .binding = bindings.bind(void, null, fixture.unused) };
    const registry: Registry = .{ .operations = &.{ entry, entry }, .policies = &.{}, .gates = &.{} };
    try std.testing.expectError(error.WorkflowOperationRegistryInvalid, (@import("actions/workflow/validate_workflow_operation_registry.zig").Action{}).execute(&registry));
}

test "pure model-binding contracts require one slot and complete trusted capacity authority" {
    const capacity = @import("model_contract_test_fixture.zig").capacity;
    const parameters = [_]operation.ParameterDescriptor{
        .{ .id = "slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
    } ++ @import("domain/workflow_model.zig").parameters;
    const entry: Entry = .{
        .contract = .{
            .id = "test.prepare@1",
            .kind = .step,
            .parameters = &parameters,
            .model_capacity = capacity,
            .outcomes = &.{.ok},
            .side_effect = .none,
        },
        .binding = bindings.bind(void, null, fixture.unused),
    };
    const valid: Registry = .{ .model_capacity = capacity, .operations = &.{entry}, .policies = &.{}, .gates = &.{} };
    try std.testing.expect(valid.validate());
    try std.testing.expectEqual(@as(usize, 0), entry.binding.capabilities().len);

    for (0..9) |variant| {
        var changed = entry;
        var descriptors = parameters ++ [_]operation.ParameterDescriptor{
            .{ .id = "other-slot", .kind = .model_slot, .required = true, .workflow_definition_safe = true },
        };
        var registry = valid;
        switch (variant) {
            0 => registry.model_capacity = null,
            1 => changed.contract.model_capacity = null,
            2 => changed.contract.parameters = parameters[1..],
            3 => changed.contract.parameters = &descriptors,
            4 => {
                descriptors[0].required = false;
                changed.contract.parameters = descriptors[0..parameters.len];
            },
            5 => changed.contract.model_capacity.?.canonical.maximum_input_bytes = 0,
            6 => changed.contract.parameters = parameters[0..1],
            7 => {
                changed.contract.model_capacity = null;
                changed.contract.parameters = &descriptors;
            },
            8 => changed.contract.kind = .invocation,
            else => unreachable,
        }
        registry.operations = &.{changed};
        try std.testing.expect(!registry.validate());
    }
}

test "bindings derive reachable port capabilities and reject erased or executable contexts" {
    const Pure = struct { text: []const u8, count: usize };
    const Nested = struct { providers: [2]?*fixture.ModelContext, data: Pure };
    const Recursive = struct { next: ?*@This(), provider: fixture.ModelContext };
    const pure = comptime bindings.inspect(Pure, &.{});
    const nested = comptime bindings.inspect(Nested, &.{});
    const recursive = comptime bindings.inspect(Recursive, &.{});
    try std.testing.expect(pure.valid and !pure.model_provider);
    try std.testing.expect(nested.valid and nested.model_provider);
    try std.testing.expect(recursive.valid and recursive.model_provider);
    inline for (.{ anyopaque, *anyopaque, *const fn () void, [*]u8, struct { hidden: ?*anyopaque } }) |T| {
        try std.testing.expect(!(comptime bindings.inspect(T, &.{})).valid);
    }
    const pure_binding = bindings.bind(void, null, fixture.unused);
    const model_binding = bindings.bind(fixture.ModelContext, &fixture.model_context, fixture.unusedModel);
    try std.testing.expectEqual(@as(usize, 0), pure_binding.capabilities().len);
    try std.testing.expectEqual(@as(usize, 1), model_binding.capabilities().len);
    try std.testing.expectEqualStrings("model-provider", model_binding.capabilities()[0]);
}

test "registry rejects absent typed operation context" {
    const Context = struct {
        count: usize = 0,
        fn invoke(_: ?*@This(), _: operations.Input) operations.Error!@import("domain/workflow_execution.zig").Candidate {
            return .{ .outcome = .ok, .delta = .{} };
        }
    };
    var context: Context = .{};
    var entry: Entry = .{
        .contract = .{ .id = "test.bound@1", .kind = .step, .outcomes = &.{.ok}, .side_effect = .none },
        .binding = bindings.bind(Context, &context, Context.invoke),
    };
    const registry: Registry = .{ .operations = (&entry)[0..1], .policies = &.{}, .gates = &.{} };
    try std.testing.expect(registry.validate());
    entry.binding.context = null;
    try std.testing.expect(!registry.validate());
}
