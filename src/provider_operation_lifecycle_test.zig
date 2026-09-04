const std = @import("std");
const action = @import("actions/model/advance_provider_operation_lifecycle.zig");
const lifecycle = @import("domain/provider_operation_lifecycle.zig");
const provider = @import("domain/llm_provider_operation.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const requests_module = @import("application/model_request_identity_runner.zig");
const attempts_module = @import("application/model_attempt_accounting_runner.zig");
const lifecycle_runner = @import("application/provider_operation_lifecycle_runner.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const binding = @import("domain/llm_provider_binding.zig");
const registry = @import("domain/llm_provider_registry.zig");

test "fake provider executes only after applied count and inference lifecycle transitions" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .count_plan = .{ .counted = 10 },
        .invocation_plan = .{ .complete = .{ .content = "{}", .output_tokens = 5 } },
    };
    const provider_binding: binding.ValidatedProviderModelBinding = .{
        .operation_id = facts().binding_id.operation_id,
        .slot_id = facts().binding_id.slot_id,
        .registry_entry = &fake_entry,
        .reasoning_effort = null,
    };
    const request = try provider.IdentifiedProviderNeutralModelRequest.init(.{
        .model_request_id = fixture.request,
        .model_operation_id = fixture.request.model_operation_id,
        .binding_id = provider_binding.bindingId(),
        .request_schema_id = .{ .bytes = "request/v1" },
        .result_schema_id = .{ .bytes = "result/v1" },
        .model_visible_input_id = facts().model_visible_input_id,
        .content = &.{.{ .user = "Return a bounded candidate." }},
        .response_schema = "{}",
        .response_guidance_mode = .prompt_only,
        .controls = .{},
        .limits = provider.EffectiveModelLimits.init(256, 32, 50, 20, 100).?,
    });
    try std.testing.expectError(error.ProviderOperationNotFound, fixture.ledger().requireInvoked(fixture.id(.input_token_count)));
    try std.testing.expectEqual(@as(usize, 0), fake.count_call_count);
    try fixture.startCount();
    const count_operation = try fixture.ledger().requireInvoked(fixture.id(.input_token_count));
    const count_lease = lease(count_operation.*);
    const observation = try fake.interface().countInputTokens(&provider_binding, &request, &count_lease, count_operation);
    const evidence = try provider.ExactInputTokenCountEvidence.fromObservation(observation, request, provider_binding);
    _ = try fixture.change(.input_token_count, .{ .terminate = .{ .counted = evidence } });
    _ = try fixture.change(.inference, .{ .assign_inference = evidence });
    try std.testing.expectError(error.ProviderOperationNotInvoked, fixture.ledger().requireInvoked(fixture.id(.inference)));
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
    _ = try fixture.change(.inference, .{ .invoke = invocation });
    const inference_operation = try fixture.ledger().requireInvoked(fixture.id(.inference));
    const inference_lease = lease(inference_operation.*);
    var result = try fake.interface().invoke(&provider_binding, &request, &evidence, &inference_lease, inference_operation);
    defer result.deinit();
    try std.testing.expect(result == .completed);
    try std.testing.expect(result.completed.operation_id.eql(fixture.id(.inference)));
    try std.testing.expect(result.completed.raw_result == .complete);
    _ = try fixture.change(.inference, .{ .terminate = .completed });
    try std.testing.expectEqual(@as(usize, 1), fake.count_call_count);
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
}

const fake_entry: registry.Entry = .{
    .id = .{ .ordinal = 1 },
    .provider = .{ .bytes = "fake-provider" },
    .model = .{ .bytes = "fake-model" },
    .implementation_id = .{ .ordinal = 1 },
    .config = .empty_object,
    .supported_reasoning_efforts = &.{},
};

fn lease(operation: provider.InvokedProviderOperation) provider.ValidatedProviderAuthorizationLeaseRef {
    return .{
        .id = .{ .value = 1 },
        .operation_id = operation.id,
        .binding_id = facts().binding_id,
        .model_visible_input_id = facts().model_visible_input_id,
        .deadline_monotonic_ms = operation.deadline_monotonic_ms,
    };
}

test "count and inference share one attempt and preserve immutable lifecycle snapshots" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const empty = fixture.ledger();
    const assigned = try fixture.change(.input_token_count, .{ .assign_count = facts() });
    try std.testing.expect(assigned.phase == .assigned);
    try std.testing.expect(assigned.expected_revision == null);
    try std.testing.expect(empty.record(fixture.id(.input_token_count)) == null);
    const count_snapshot = fixture.ledger();
    try std.testing.expectError(error.ProviderOperationNotInvoked, count_snapshot.requireInvoked(fixture.id(.input_token_count)));
    try fixture.invokeRequest();
    const invoked = try fixture.change(.input_token_count, .{ .invoke = invocation });
    try std.testing.expect(invoked.phase == .send_may_occur);
    try std.testing.expect(count_snapshot.record(fixture.id(.input_token_count)).?.state == .assigned);
    const applied = try fixture.ledger().requireInvoked(fixture.id(.input_token_count));
    try std.testing.expectEqual(@as(u64, 1000), applied.deadline_monotonic_ms);
    const terminal = try fixture.change(.input_token_count, .{ .terminate = .{ .counted = fixture.evidence() } });
    try std.testing.expectEqual(provider.ProviderDeliveryDisposition.response_received, terminal.phase.terminal_observed.delivery());
    _ = try fixture.change(.inference, .{ .assign_inference = fixture.evidence() });
    try std.testing.expect(fixture.ledger().record(fixture.id(.input_token_count)).?.state == .terminal);
    _ = try fixture.change(.inference, .{ .invoke = invocation });
    _ = try fixture.change(.inference, .{ .terminate = .completed });
    try std.testing.expectEqual(@as(u32, 1), fixture.attempts.current().attemptsReserved(fixture.request));
    try std.testing.expectEqual(@as(u64, 6), fixture.ledger().revision().value);
    try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .invoked, .{ .terminal = .accepted });
    try std.testing.expectError(error.ProviderOperationNotInvoked, fixture.ledger().requireInvoked(fixture.id(.inference)));
}

test "inference requires successful terminal count and exact attempt binding input and value" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try std.testing.expectError(error.InvalidProviderOperationCountEvidence, fixture.change(.inference, .{ .assign_inference = fixture.evidence() }));
    _ = try fixture.change(.input_token_count, .{ .assign_count = facts() });
    try std.testing.expectError(error.InvalidProviderOperationCountEvidence, fixture.change(.inference, .{ .assign_inference = fixture.evidence() }));
    try fixture.invokeRequest();
    _ = try fixture.change(.input_token_count, .{ .invoke = invocation });
    try std.testing.expectError(error.InvalidProviderOperationCountEvidence, fixture.change(.inference, .{ .assign_inference = fixture.evidence() }));

    var wrong = fixture.evidence();
    wrong.model_visible_input_id.bytes = "different-input";
    try std.testing.expectError(error.InvalidProviderOperationCountEvidence, fixture.change(.input_token_count, .{ .terminate = .{ .counted = wrong } }));
    _ = try fixture.change(.input_token_count, .{ .terminate = .{ .counted = fixture.evidence() } });
    inline for (0..5) |case| {
        wrong = fixture.evidence();
        switch (case) {
            0 => wrong.count_operation_id.model_attempt_ordinal.value = 2,
            1 => wrong.binding_id.registry_entry_id.ordinal = 2,
            2 => wrong.model_visible_input_id.bytes = "different-input",
            3 => wrong.input_tokens += 1,
            4 => wrong.count_operation_id.kind = .inference,
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidProviderOperationCountEvidence, fixture.change(.inference, .{ .assign_inference = wrong }));
    }
    try std.testing.expectEqual(@as(u64, 3), fixture.ledger().revision().value);
}

test "failed count cannot assign inference and cancellation preserves delivery" {
    inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.startCount();
        const result = try fixture.change(.input_token_count, .{ .terminate = .{ .failed = fixture.failure(.input_token_count, delivery) } });
        try std.testing.expectEqual(delivery, result.phase.terminal_observed.delivery());
        try std.testing.expectError(error.InvalidProviderOperationCountEvidence, fixture.change(.inference, .{ .assign_inference = fixture.evidence() }));
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .{ .cancelled = delivery } }));
    }
    inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.startCount();
        const result = try fixture.change(.input_token_count, .{ .terminate = .{ .cancelled = delivery } });
        try std.testing.expectEqual(delivery, result.phase.terminal_observed.delivery());
        try std.testing.expectEqual(std.meta.Tag(lifecycle.TerminalSummary).cancelled, std.meta.activeTag(result.phase.terminal_observed));
    }
}

test "assigned operations close only through not-sent preparation failure or cancellation" {
    inline for (.{ false, true }) |cancelled| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        _ = try fixture.change(.input_token_count, .{ .assign_count = facts() });
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .completed }));
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .{ .failed = fixture.failure(.input_token_count, .not_sent) } }));
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .{ .cancelled = .accepted_or_unknown } }));
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .{ .preparation_failed = fixture.failure(.input_token_count, .response_received) } }));
        const terminal: lifecycle.Terminal = if (cancelled) .{ .cancelled = .not_sent } else .{ .preparation_failed = fixture.failure(.input_token_count, .not_sent) };
        const effect = try fixture.change(.input_token_count, .{ .terminate = terminal });
        try std.testing.expectEqual(provider.ProviderDeliveryDisposition.not_sent, effect.phase.terminal_observed.delivery());
        try std.testing.expectEqual(@as(u32, 1), fixture.attempts.current().attemptsReserved(fixture.request));
        try std.testing.expectError(error.InvalidProviderOperationCountEvidence, fixture.change(.inference, .{ .assign_inference = fixture.evidence() }));
        try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .assigned, .{ .terminal = if (cancelled) .cancelled else .not_invoked_authorization_failure });
    }
}

test "operation lifecycle rejects skipped transitions repeated invocation and wrong-kind terminals" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try std.testing.expectError(error.ProviderOperationNotFound, fixture.change(.input_token_count, .{ .invoke = invocation }));
    _ = try fixture.change(.input_token_count, .{ .assign_count = facts() });
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .assign_count = facts() }));
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .invoke = invocation }));
    try fixture.invokeRequest();
    var invalid_invocation = invocation;
    invalid_invocation.deadline_monotonic_ms = 0;
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .invoke = invalid_invocation }));
    _ = try fixture.change(.input_token_count, .{ .invoke = invocation });
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .invoke = invocation }));
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .completed }));
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .{ .stopped = .output_limit } }));
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .{ .preparation_failed = fixture.failure(.input_token_count, .not_sent) } }));
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.input_token_count, .{ .terminate = .{ .failed = fixture.failure(.inference, .not_sent) } }));
    _ = try fixture.change(.input_token_count, .{ .terminate = .{ .counted = fixture.evidence() } });
    _ = try fixture.change(.inference, .{ .assign_inference = fixture.evidence() });
    _ = try fixture.change(.inference, .{ .invoke = invocation });
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .{ .counted = fixture.evidence() } }));
    const stopped = try fixture.change(.inference, .{ .terminate = .{ .stopped = .output_limit } });
    try std.testing.expectEqual(provider.ProviderNonCandidateStopReason.output_limit, stopped.phase.terminal_observed.stopped);
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .invoke = invocation }));
}

test "inference preparation failure cancellation and provider failure preserve terminal facts" {
    inline for (0..4) |case| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.startCount();
        _ = try fixture.change(.input_token_count, .{ .terminate = .{ .counted = fixture.evidence() } });
        _ = try fixture.change(.inference, .{ .assign_inference = fixture.evidence() });
        if (case >= 2) _ = try fixture.change(.inference, .{ .invoke = invocation });
        const terminal: lifecycle.Terminal = switch (case) {
            0 => .{ .preparation_failed = fixture.failure(.inference, .not_sent) },
            1 => .{ .cancelled = .not_sent },
            2 => .{ .failed = fixture.failure(.inference, .accepted_or_unknown) },
            3 => .{ .cancelled = .accepted_or_unknown },
            else => unreachable,
        };
        const effect = try fixture.change(.inference, .{ .terminate = terminal });
        try std.testing.expectEqual(
            if (case < 2) provider.ProviderDeliveryDisposition.not_sent else provider.ProviderDeliveryDisposition.accepted_or_unknown,
            effect.phase.terminal_observed.delivery(),
        );
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = terminal }));
        try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .invoked, .{ .terminal = if (case == 1 or case == 3) .cancelled else .failed });
    }
}

test "request finalization and new attempts cannot strand assigned or invoked operations" {
    inline for (.{ false, true }) |invoked| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        _ = try fixture.change(.input_token_count, .{ .assign_count = facts() });
        if (invoked) {
            try fixture.invokeRequest();
            _ = try fixture.change(.input_token_count, .{ .invoke = invocation });
        }
        const request_status: identity.RequestStatus = if (invoked) .invoked else .assigned;
        try std.testing.expectError(error.ProviderOperationStillOpen, fixture.requests.advance(
            fixture.requests.ledger().?.revision(),
            fixture.request,
            request_status,
            .{ .terminal = if (invoked) .cancelled else .not_invoked_authorization_failure },
        ));
        try std.testing.expectError(error.ProviderOperationStillOpen, fixture.retry());
        _ = try fixture.change(.input_token_count, .{ .terminate = .{ .cancelled = if (invoked) .accepted_or_unknown else .not_sent } });
        try fixture.retry();
        try std.testing.expectEqual(@as(u32, 2), fixture.attempts.current().attemptsReserved(fixture.request));
        _ = try fixture.change(.input_token_count, .{ .assign_count = facts() });
        try std.testing.expectEqual(@as(u64, 1), fixture.ledger().record(fixture.id(.input_token_count)).?.revision.value);
    }
}

test "lifecycle rejects stale ledger operation request and attempt revisions without mutation" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const empty = fixture.ledger();
    const proposal = try (action.Action{}).execute(empty, fixture.authority(), .initial, fixture.id(.input_token_count), null, .{ .assign_count = facts() });
    const transition = proposal.runner_accounting_transition.?.advance_provider_operation;
    const envelope = pipeline.PipelineEnvelope.init(&.{.model_request_identity_ledger});
    _ = try envelope.apply(action.Action.contract, proposal);
    var forbidden = action.Action.contract;
    forbidden.runner_accounting = .none;
    try std.testing.expectError(error.UndeclaredRunnerAccountingTransition, envelope.apply(forbidden, proposal));
    try std.testing.expectError(error.MissingRunnerAccountingTransition, envelope.apply(action.Action.contract, pipeline.NodeDelta.successful(action.Action.contract)));
    try std.testing.expect(empty.record(fixture.id(.input_token_count)) == null);
    const effect = try transition.effect(fixture.authority());
    try std.testing.expect(effect.phase == .assigned);
    _ = try fixture.change(.input_token_count, .{ .assign_count = facts() });
    try std.testing.expectError(error.ProviderOperationRevisionConflict, lifecycle.apply(fixture.ledger(), fixture.authority(), transition));
    const before = fixture.ledger();
    try std.testing.expectError(error.ProviderOperationRevisionConflict, fixture.requests.providerOperations().advance(fixture.authority(), before.revision(), fixture.id(.input_token_count), .{ .value = 0 }, .{ .terminate = .{ .cancelled = .not_sent } }));
    var wrong_authority = fixture.authority();
    wrong_authority.expected_request_revision.value += 1;
    try std.testing.expectError(error.ProviderOperationRequestRevisionConflict, (action.Action{}).execute(before, wrong_authority, before.revision(), fixture.id(.input_token_count), .{ .value = 1 }, .{ .terminate = .{ .cancelled = .not_sent } }));
    wrong_authority = fixture.authority();
    wrong_authority.expected_attempt_revision.value += 1;
    try std.testing.expectError(error.ProviderOperationAttemptRevisionConflict, (action.Action{}).execute(before, wrong_authority, before.revision(), fixture.id(.input_token_count), .{ .value = 1 }, .{ .terminate = .{ .cancelled = .not_sent } }));
    try std.testing.expect(fixture.ledger() == before);
}

test "foreign forged and unreserved operation identities fail closed" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var other = try Fixture.init(std.testing.allocator);
    defer other.deinit();
    const foreign_transition = try lifecycle.propose(other.ledger(), other.authority(), .initial, other.id(.input_token_count), null, .{ .assign_count = facts() });
    try std.testing.expectError(error.ProviderOperationRevisionConflict, lifecycle.apply(fixture.ledger(), fixture.authority(), foreign_transition));
    var id = fixture.id(.input_token_count);
    id.model_request_id = other.request;
    try std.testing.expectError(error.ProviderOperationRequestUnavailable, lifecycle.propose(fixture.ledger(), fixture.authority(), .initial, id, null, .{ .assign_count = facts() }));
    var forged_request = fixture.request.*;
    id.model_request_id = &forged_request;
    try std.testing.expectError(error.ProviderOperationRequestUnavailable, lifecycle.propose(fixture.ledger(), fixture.authority(), .initial, id, null, .{ .assign_count = facts() }));
    inline for (.{ 0, 2 }) |ordinal| {
        id = fixture.id(.input_token_count);
        id.model_attempt_ordinal.value = ordinal;
        try std.testing.expectError(error.ProviderOperationAttemptUnavailable, lifecycle.propose(fixture.ledger(), fixture.authority(), .initial, id, null, .{ .assign_count = facts() }));
    }
    var foreign_epoch = try lifecycle_runner.Runner.init(std.testing.allocator, .{ .bytes = "other-epoch" });
    defer foreign_epoch.deinit();
    try std.testing.expectError(error.ProviderOperationEpochConflict, foreign_epoch.advance(fixture.authority(), .initial, fixture.id(.input_token_count), null, .{ .assign_count = facts() }));
    var invalid_facts = facts();
    invalid_facts.binding_id.operation_id.workflow_version += 1;
    try std.testing.expectError(error.InvalidProviderOperationBinding, fixture.change(.input_token_count, .{ .assign_count = invalid_facts }));
    try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .assigned, .{ .terminal = .not_invoked_authorization_failure });
    try std.testing.expectError(error.ProviderOperationRequestUnavailable, fixture.change(.input_token_count, .{ .assign_count = facts() }));
}

test "lifecycle owns assignment bytes and isolates executions" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var other = try Fixture.init(std.testing.allocator);
    defer other.deinit();
    var slot = [_]u8{ 's', 'l', 'o', 't' };
    var input = [_]u8{ 'i', 'n', 'p', 'u', 't' };
    var assigned_facts = facts();
    assigned_facts.binding_id.slot_id.bytes = &slot;
    assigned_facts.model_visible_input_id.bytes = &input;
    const effect = try fixture.change(.input_token_count, .{ .assign_count = assigned_facts });
    @memset(&slot, 'x');
    @memset(&input, 'x');
    try std.testing.expectEqualStrings("slot", fixture.ledger().record(fixture.id(.input_token_count)).?.binding_id.slot_id.bytes);
    try std.testing.expectEqualStrings("input", effect.model_visible_input_id.bytes);
    try std.testing.expectEqual(@as(u64, 0), other.ledger().revision().value);
    try std.testing.expect(other.ledger().record(fixture.id(.input_token_count)) == null);
}

test "lifecycle allocation failures preserve current state and release all ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture = try Fixture.init(allocator);
    defer fixture.deinit();
    try fixture.startCount();
    _ = try fixture.change(.input_token_count, .{ .terminate = .{ .counted = fixture.evidence() } });
    _ = try fixture.change(.inference, .{ .assign_inference = fixture.evidence() });
    _ = try fixture.change(.inference, .{ .invoke = invocation });
    const before = fixture.ledger();
    _ = fixture.change(.inference, .{ .terminate = .completed }) catch |err| {
        try std.testing.expect(before == fixture.ledger());
        return err;
    };
}

const invocation: lifecycle.Invocation = .{
    .deadline_monotonic_ms = 1000,
    .receive_budgets = provider.ProviderReceiveBudgets.init(32, 4096, 4096).?,
};

const Fixture = struct {
    requests: requests_module.Runner,
    attempts: attempts_module.Runner,
    request: *const identity.ModelRequestId,

    fn init(allocator: std.mem.Allocator) !Fixture {
        var requests = requests_module.Runner.init(allocator);
        errdefer requests.deinit();
        try requests.initialize(.{ .bytes = "epoch-1" }, identity.RequestPurposeRegistry.all());
        const request = try requests.assign(.initial, .{ .task_cluster = .{
            .plan_state_id = .{ .bytes = "plan-1" },
            .obligation_cluster_id = .{ .bytes = "cluster-1" },
        } }, facts().binding_id.operation_id, .initial_generation);
        var attempts = try attempts_module.Runner.init(allocator, .{ .bytes = "epoch-1" });
        errdefer attempts.deinit();
        _ = try attempts.reserve(.initial, requests.ledger().?, requests.providerOperations().current(), requests.ledger().?.revision(), request, .initial);
        return .{ .requests = requests, .attempts = attempts, .request = request };
    }

    fn deinit(self: *Fixture) void {
        self.attempts.deinit();
        self.requests.deinit();
        self.* = undefined;
    }

    fn ledger(self: *Fixture) *const lifecycle.Ledger {
        return self.requests.providerOperations().current();
    }

    fn authority(self: *Fixture) lifecycle.Authority {
        return .{
            .requests = self.requests.ledger().?,
            .expected_request_revision = self.requests.ledger().?.revision(),
            .attempts = self.attempts.current(),
            .expected_attempt_revision = self.attempts.current().revision(),
        };
    }

    fn id(self: *Fixture, kind: provider.ProviderOperationKind) provider.ProviderOperationId {
        return .{ .model_request_id = self.request, .model_attempt_ordinal = .{ .value = self.attempts.current().attemptsReserved(self.request) }, .kind = kind };
    }

    fn evidence(self: *Fixture) provider.ExactInputTokenCountEvidence {
        return .{ .count_operation_id = self.id(.input_token_count), .binding_id = facts().binding_id, .model_visible_input_id = facts().model_visible_input_id, .input_tokens = 10 };
    }

    fn change(self: *Fixture, kind: provider.ProviderOperationKind, command: lifecycle.Command) !lifecycle.Effect {
        const operation_id = self.id(kind);
        const previous = self.ledger().record(operation_id);
        return self.requests.providerOperations().advance(self.authority(), self.ledger().revision(), operation_id, if (previous) |record| record.revision else null, command);
    }

    fn invokeRequest(self: *Fixture) !void {
        try self.requests.advance(self.requests.ledger().?.revision(), self.request, .assigned, .invoked);
    }

    fn startCount(self: *Fixture) !void {
        _ = try self.change(.input_token_count, .{ .assign_count = facts() });
        try self.invokeRequest();
        _ = try self.change(.input_token_count, .{ .invoke = invocation });
    }

    fn failure(self: *Fixture, kind: provider.ProviderOperationKind, delivery: provider.ProviderDeliveryDisposition) provider.ProviderFailure {
        return .{ .operation_id = self.id(kind), .cause = .authorization_denied, .retry_class = .never, .delivery = delivery };
    }

    fn retry(self: *Fixture) !void {
        _ = try self.attempts.reserve(self.attempts.current().revision(), self.requests.ledger().?, self.ledger(), self.requests.ledger().?.revision(), self.request, .{ .retry = .{
            .workflow_id = self.request.model_operation_id.workflow_id,
            .workflow_version = self.request.model_operation_id.workflow_version,
            .operation_instance_id = self.request.model_operation_id.workflow_step_id,
            .limit = .{ .value = 1 },
        } });
    }
};

fn facts() lifecycle.Assignment {
    return .{
        .binding_id = .{
            .operation_id = .{ .workflow_id = .{ .bytes = "arbitrary-flow" }, .workflow_version = 1, .workflow_step_id = .{ .bytes = "generate" } },
            .slot_id = .{ .bytes = "slot" },
            .registry_entry_id = .{ .ordinal = 1 },
            .reasoning_effort = null,
        },
        .model_visible_input_id = .{ .bytes = "input" },
    };
}
