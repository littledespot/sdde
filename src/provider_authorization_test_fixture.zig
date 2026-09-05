const std = @import("std");
const binding = @import("domain/llm_provider_binding.zig");
const identity = @import("domain/model_request_identity.zig");
const operation = @import("domain/llm_provider_operation.zig");
const lifecycle = @import("domain/provider_operation_lifecycle.zig");
const registry = @import("domain/llm_provider_registry.zig");
const requests_module = @import("application/model_request_identity_runner.zig");
const attempts_module = @import("application/model_attempt_accounting_runner.zig");
const lifecycle_runner = @import("application/provider_operation_lifecycle_runner.zig");
const preparation_runner = @import("application/provider_authorization_runner.zig");
const preparation = @import("ports/provider_operation_authorization.zig");
const lease = @import("ports/provider_authorization_lease.zig");
const fake_authorization = @import("adapters/provider/fake_provider_authorization.zig");

pub const TestClock = struct {
    now_ms: u64 = 1,
    unavailable: bool = false,

    pub fn port(self: *TestClock) lease.Clock {
        return .{ .context = @ptrCast(self), .now_fn = now };
    }

    fn now(context: *lease.Context) error{ClockUnavailable}!u64 {
        const self: *TestClock = @ptrCast(@alignCast(context));
        if (self.unavailable) return error.ClockUnavailable;
        return self.now_ms;
    }
};

pub const Authorized = struct {
    reference: *const operation.ValidatedProviderAuthorizationLeaseRef,
    invoked: *const operation.InvokedProviderOperation,
};

/// Initialized in its final location: binding, preloader and injected clock
/// references remain stable until deterministic deinit.
pub const Fixture = struct {
    requests: requests_module.Runner,
    attempts: attempts_module.Runner,
    model_request_id: *const identity.ModelRequestId,
    registry_entry: registry.Entry,
    provider_binding: binding.ValidatedProviderModelBinding,
    request: operation.IdentifiedProviderNeutralModelRequest,
    preloader: fake_authorization.FakeProviderAuthorization,
    clock: TestClock,
    request_invoked: bool,

    pub fn init(self: *Fixture, allocator: std.mem.Allocator) !void {
        self.requests = requests_module.Runner.init(allocator);
        errdefer self.requests.deinit();
        try self.requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
        self.model_request_id = try self.requests.assign(.initial, .{ .task_cluster = .{
            .plan_state_id = .{ .bytes = "plan-1" },
            .obligation_cluster_id = .{ .bytes = "cluster-1" },
        } }, modelOperation(), .initial_generation);
        self.attempts = try attempts_module.Runner.init(allocator, .{ .bytes = "epoch-1" });
        errdefer self.attempts.deinit();
        _ = try self.attempts.reserve(.initial, self.requests.ledger().?, self.ledger(), self.requests.ledger().?.revision(), self.model_request_id, .initial);
        self.registry_entry = .{
            .id = .{ .ordinal = 1 },
            .provider = .{ .bytes = "fake-provider" },
            .model = .{ .bytes = "fake-model" },
            .implementation_id = .{ .ordinal = 1 },
            .config = .empty_object,
            .capabilities = @import("model_contract_test_fixture.zig").capabilities,
            .supported_reasoning_efforts = &.{"low"},
        };
        self.provider_binding = .{
            .operation_id = modelOperation(),
            .slot_id = .{ .bytes = "generation" },
            .registry_entry = &self.registry_entry,
            .reasoning_effort = "low",
            .capacity = .{
                .canonical = @import("domain/model_limits.zig").Limits.init(256, 40, 100, 20, 100).?,
                .wire = @import("model_contract_test_fixture.zig").capacity.wire,
            },
            .response_mode = .prompt_only,
            .controls = .{ .temperature = @import("domain/model_controls.zig").TemperaturePermille.init(100) },
        };
        self.request = try operation.IdentifiedProviderNeutralModelRequest.init(.{
            .model_request_id = self.model_request_id,
            .model_operation_id = modelOperation(),
            .binding_id = self.provider_binding.bindingId(),
            .request_schema_id = .{ .bytes = "request.test/v1" },
            .result_schema_id = .{ .bytes = "result.test/v1" },
            .model_visible_input_id = .{ .bytes = "input-1" },
            .content = &.{ .{ .system = "Return the declared result." }, .{ .user = "Generate the bounded candidate." } },
            .response_schema = "{}",
            .response_guidance_mode = .prompt_only,
            .controls = self.provider_binding.controls,
            .limits = self.provider_binding.capacity.canonical,
        });
        self.preloader = .{ .allocator = allocator };
        self.clock = .{};
        self.request_invoked = false;
    }

    pub fn deinit(self: *Fixture) void {
        self.attempts.deinit();
        self.requests.deinit();
    }

    pub fn operations(self: *Fixture) *lifecycle_runner.Runner {
        return self.requests.providerOperations();
    }

    pub fn ledger(self: *Fixture) *const lifecycle.Ledger {
        return self.operations().current();
    }

    pub fn id(self: *Fixture, kind: operation.ProviderOperationKind) operation.ProviderOperationId {
        return .{ .model_request_id = self.model_request_id, .model_attempt_ordinal = .{ .value = self.attempts.current().attemptsReserved(self.model_request_id) }, .kind = kind };
    }

    pub fn facts(self: *Fixture, kind: operation.ProviderOperationKind) preparation.Facts {
        return .{ .provider_binding = &self.provider_binding, .request = &self.request, .operation_id = self.id(kind), .deadline_monotonic_ms = 1000 };
    }

    pub fn assignment(self: *Fixture) lifecycle.Assignment {
        return .{ .binding_id = self.provider_binding.bindingId(), .model_visible_input_id = self.request.model_visible_input_id };
    }

    pub fn change(self: *Fixture, kind: operation.ProviderOperationKind, command: lifecycle.Command) !lifecycle.Effect {
        const operation_id = self.id(kind);
        const previous = self.ledger().record(operation_id);
        const authority: lifecycle.Authority = .{
            .requests = self.requests.ledger().?,
            .expected_request_revision = self.requests.ledger().?.revision(),
            .attempts = self.attempts.current(),
            .expected_attempt_revision = self.attempts.current().revision(),
        };
        return self.operations().advance(authority, self.ledger().revision(), operation_id, if (previous) |record| record.revision else null, command);
    }

    pub fn assignCount(self: *Fixture) !void {
        _ = try self.change(.input_token_count, .{ .assign_count = self.assignment() });
    }

    pub fn preparationRunner(self: *Fixture) preparation_runner.Runner {
        return .{ .table = &self.operations().authorization_leases, .prepare_action = .{ .authorization = self.preloader.port() }, .clock = self.clock.port() };
    }

    pub fn prepare(self: *Fixture, kind: operation.ProviderOperationKind) !*const operation.ValidatedProviderAuthorizationLeaseRef {
        var runner = self.preparationRunner();
        return switch (try runner.prepare(self.facts(kind))) {
            .prepared => |reference| reference,
            else => error.ExpectedPreparedAuthorization,
        };
    }

    pub fn invoke(self: *Fixture, kind: operation.ProviderOperationKind) !*const operation.InvokedProviderOperation {
        if (!self.request_invoked) {
            try self.requests.advance(self.requests.ledger().?.revision(), self.model_request_id, .assigned, .invoked);
            self.request_invoked = true;
        }
        _ = try self.change(kind, .{ .invoke = .{ .deadline_monotonic_ms = 1000, .receive_budgets = operation.ProviderReceiveBudgets.init(32, 4096, 4096).? } });
        return self.ledger().requireInvoked(self.id(kind));
    }

    pub fn leasePort(self: *Fixture) lease.Port {
        return self.operations().authorization_leases.port(self.clock.port(), .{});
    }

    pub fn startCount(self: *Fixture) !Authorized {
        try self.assignCount();
        const reference = try self.prepare(.input_token_count);
        return .{ .reference = reference, .invoked = try self.invoke(.input_token_count) };
    }

    pub fn evidence(self: *Fixture) operation.ExactInputTokenCountEvidence {
        return .{ .count_operation_id = self.id(.input_token_count), .binding_id = self.provider_binding.bindingId(), .model_visible_input_id = self.request.model_visible_input_id, .input_tokens = 10 };
    }

    pub fn finishCountAndStartInference(self: *Fixture, count: operation.ExactInputTokenCountEvidence) !Authorized {
        _ = try self.change(.input_token_count, .{ .terminate = .{ .counted = count } });
        _ = try self.change(.inference, .{ .assign_inference = count });
        const reference = try self.prepare(.inference);
        return .{ .reference = reference, .invoked = try self.invoke(.inference) };
    }
};

fn modelOperation() binding.WorkflowModelOperationId {
    return .{ .workflow_id = .{ .bytes = "arbitrary-flow" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "generate" } };
}
