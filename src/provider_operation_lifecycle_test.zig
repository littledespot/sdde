const std = @import("std");
const action = @import("actions/model/advance_provider_operation_lifecycle.zig");
const lifecycle = @import("domain/provider_operation_lifecycle.zig");
const provider = @import("domain/llm_provider_operation.zig");
const identity = @import("domain/model_request_identity.zig");
const pipeline = @import("domain/pipeline.zig");
const requests_module = @import("model_request_identity_runner_test_fixture.zig");
const attempts_module = @import("model_attempt_test_fixture.zig");
const lifecycle_runner = @import("provider_operation_lifecycle_runner_test_fixture.zig");
const fake_provider = @import("adapters/provider/fake_llm_provider.zig");
const AuthorizationFixture = @import("provider_authorization_test_fixture.zig").Fixture;

test "fake provider executes only after applied inference lifecycle transitions" {
    var fixture: AuthorizationFixture = undefined;
    try fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var fake: fake_provider.FakeLLMProvider = .{
        .allocator = std.testing.allocator,
        .authorization_leases = fixture.leasePort(),
        .invocation_plan = .{ .complete = .{ .content = "{}", .input_tokens = 10, .output_tokens = 5 } },
    };
    try std.testing.expectError(error.ProviderOperationNotFound, fixture.ledger().requireInvoked(fixture.id(.inference)));
    try fixture.change(.inference, .{ .assign_inference = fixture.assignment() });
    try std.testing.expectError(error.ProviderOperationNotInvoked, fixture.ledger().requireInvoked(fixture.id(.inference)));
    try std.testing.expectEqual(@as(usize, 0), fake.invocation_call_count);
    const inference_lease = try fixture.prepare(.inference);
    _ = try fixture.invoke(.inference);
    const inference_operation = try fixture.ledger().requireInvoked(fixture.id(.inference));
    var result = try fake.interface().invoke(&fixture.provider_binding, &fixture.request, inference_lease, inference_operation);
    defer result.deinit();
    try std.testing.expect(result == .completed);
    try std.testing.expect(result.completed.operation_id.eql(fixture.id(.inference)));
    try std.testing.expect(result.completed.raw_result == .complete);
    try fixture.change(.inference, .{ .terminate = .completed });
    try std.testing.expectEqual(@as(usize, 1), fake.invocation_call_count);
    try std.testing.expectEqual(@as(usize, 1), fixture.preloader.destroyed_count);
}

test "inference preserves immutable lifecycle snapshots" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const empty = fixture.ledger();
    const assigned = try fixture.change(.inference, .{ .assign_inference = facts() });
    try std.testing.expect(assigned.state == .assigned);
    try std.testing.expectEqual(@as(u64, 1), assigned.revision.value);
    try std.testing.expect(empty.record(fixture.id(.inference)) == null);
    const assigned_snapshot = fixture.ledger();
    try std.testing.expectError(error.ProviderOperationNotInvoked, assigned_snapshot.requireInvoked(fixture.id(.inference)));
    try fixture.invokeRequest();
    const invoked = try fixture.change(.inference, .{ .invoke = invocation });
    try std.testing.expect(invoked.state == .invoked);
    try std.testing.expect(assigned_snapshot.record(fixture.id(.inference)).?.state == .assigned);
    const applied = try fixture.ledger().requireInvoked(fixture.id(.inference));
    try std.testing.expectEqual(@as(u64, 1000), applied.deadline_monotonic_ms);
    const terminal = try fixture.change(.inference, .{ .terminate = .completed });
    try std.testing.expectEqual(provider.ProviderDeliveryDisposition.response_received, terminal.state.terminal.delivery());
    try std.testing.expectEqual(@as(u32, 1), fixture.attempts.current().attemptsReserved(fixture.request));
    try std.testing.expectEqual(@as(u64, 3), fixture.ledger().revision().value);
    try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .invoked, .{ .terminal = .accepted });
    try std.testing.expectError(error.ProviderOperationNotInvoked, fixture.ledger().requireInvoked(fixture.id(.inference)));
}

test "inference assignment owns immutable binding input facts" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const before = fixture.ledger();
    var input = "input".*;
    var assignment = facts();
    assignment.model_visible_input_id.bytes = &input;
    _ = try fixture.change(.inference, .{ .assign_inference = assignment });
    input[0] = 'X';
    try std.testing.expect(before.record(fixture.id(.inference)) == null);
    try std.testing.expectEqualStrings("input", fixture.ledger().record(fixture.id(.inference)).?.model_visible_input_id.bytes);
    try fixture.invokeRequest();
    _ = try fixture.change(.inference, .{ .invoke = invocation });
    _ = try fixture.change(.inference, .{ .terminate = .completed });
    try std.testing.expectEqual(@as(u64, 3), fixture.ledger().revision().value);
}

test "failed or cancelled inference preserves its delivery disposition" {
    inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.startInference();
        const result = try fixture.change(.inference, .{ .terminate = .{ .failed = fixture.failure(.inference, delivery) } });
        try std.testing.expectEqual(delivery, result.state.terminal.delivery());
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .{ .cancelled = delivery } }));
    }
    inline for (std.enums.values(provider.ProviderDeliveryDisposition)) |delivery| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        try fixture.startInference();
        const result = try fixture.change(.inference, .{ .terminate = .{ .cancelled = delivery } });
        try std.testing.expectEqual(delivery, result.state.terminal.delivery());
        try std.testing.expectEqual(std.meta.Tag(lifecycle.TerminalFact).cancelled, std.meta.activeTag(result.state.terminal));
    }
}

test "assigned operations close only through not-sent preparation failure or cancellation" {
    inline for (.{ false, true }) |cancelled| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        _ = try fixture.change(.inference, .{ .assign_inference = facts() });
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .completed }));
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .{ .failed = fixture.failure(.inference, .not_sent) } }));
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .{ .cancelled = .accepted_or_unknown } }));
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .{ .preparation_failed = fixture.failure(.inference, .response_received) } }));
        const terminal: lifecycle.Terminal = if (cancelled) .{ .cancelled = .not_sent } else .{ .preparation_failed = fixture.failure(.inference, .not_sent) };
        const record = try fixture.change(.inference, .{ .terminate = terminal });
        try std.testing.expectEqual(provider.ProviderDeliveryDisposition.not_sent, record.state.terminal.delivery());
        try std.testing.expectEqual(@as(u32, 1), fixture.attempts.current().attemptsReserved(fixture.request));
        try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .assigned, .{ .terminal = if (cancelled) .cancelled else .not_invoked_authorization_failure });
    }
}

test "operation lifecycle rejects skipped transitions repeated invocation and foreign failures" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try std.testing.expectError(error.ProviderOperationNotFound, fixture.change(.inference, .{ .invoke = invocation }));
    _ = try fixture.change(.inference, .{ .assign_inference = facts() });
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .assign_inference = facts() }));
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .invoke = invocation }));
    try fixture.invokeRequest();
    var invalid_invocation = invocation;
    invalid_invocation.deadline_monotonic_ms = 0;
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .invoke = invalid_invocation }));
    _ = try fixture.change(.inference, .{ .invoke = invocation });
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .invoke = invocation }));
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .{ .preparation_failed = fixture.failure(.inference, .not_sent) } }));
    var foreign = fixture.failure(.inference, .not_sent);
    foreign.operation_id.model_attempt_ordinal.value += 1;
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = .{ .failed = foreign } }));
    const stopped = try fixture.change(.inference, .{ .terminate = .{ .stopped = .output_limit } });
    try std.testing.expectEqual(provider.ProviderNonCandidateStopReason.output_limit, stopped.state.terminal.stopped);
    try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .invoke = invocation }));
}

test "inference preparation failure cancellation and provider failure preserve terminal facts" {
    inline for (0..4) |case| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        _ = try fixture.change(.inference, .{ .assign_inference = facts() });
        try fixture.invokeRequest();
        if (case >= 2) _ = try fixture.change(.inference, .{ .invoke = invocation });
        const terminal: lifecycle.Terminal = switch (case) {
            0 => .{ .preparation_failed = fixture.failure(.inference, .not_sent) },
            1 => .{ .cancelled = .not_sent },
            2 => .{ .failed = fixture.failure(.inference, .accepted_or_unknown) },
            3 => .{ .cancelled = .accepted_or_unknown },
            else => unreachable,
        };
        const record = try fixture.change(.inference, .{ .terminate = terminal });
        try std.testing.expectEqual(
            if (case < 2) provider.ProviderDeliveryDisposition.not_sent else provider.ProviderDeliveryDisposition.accepted_or_unknown,
            record.state.terminal.delivery(),
        );
        try std.testing.expectError(error.InvalidProviderOperationTransition, fixture.change(.inference, .{ .terminate = terminal }));
        try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .invoked, .{ .terminal = if (case == 1 or case == 3) .cancelled else .failed });
    }
}

test "request finalization and new attempts cannot strand assigned or invoked operations" {
    inline for (.{ false, true }) |invoked| {
        var fixture = try Fixture.init(std.testing.allocator);
        defer fixture.deinit();
        _ = try fixture.change(.inference, .{ .assign_inference = facts() });
        if (invoked) {
            try fixture.invokeRequest();
            _ = try fixture.change(.inference, .{ .invoke = invocation });
        }
        const request_status: identity.RequestStatus = if (invoked) .invoked else .assigned;
        try std.testing.expectError(error.ProviderOperationStillOpen, fixture.requests.advance(
            fixture.requests.ledger().?.revision(),
            fixture.request,
            request_status,
            .{ .terminal = if (invoked) .cancelled else .not_invoked_authorization_failure },
        ));
        try std.testing.expectError(error.ProviderOperationStillOpen, fixture.retry());
        _ = try fixture.change(.inference, .{ .terminate = .{ .cancelled = if (invoked) .accepted_or_unknown else .not_sent } });
        try fixture.retry();
        try std.testing.expectEqual(@as(u32, 2), fixture.attempts.current().attemptsReserved(fixture.request));
        _ = try fixture.change(.inference, .{ .assign_inference = facts() });
        try std.testing.expectEqual(@as(u64, 1), fixture.ledger().record(fixture.id(.inference)).?.revision.value);
    }
}

test "lifecycle rejects stale ledger operation request and attempt revisions without mutation" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const empty = fixture.ledger();
    const proposal = try (action.Action{}).execute(empty, fixture.authority(), .initial, fixture.id(.inference), null, .{ .assign_inference = facts() });
    const transition = proposal.runner_accounting_transition.?.advance_provider_operation;
    const envelope = pipeline.DataShape.init(&.{.model_request_identity_ledger});
    _ = try envelope.applyDelta(action.Action.contract, &proposal);
    var forbidden = action.Action.contract;
    forbidden.runner_accounting = .none;
    try std.testing.expectError(error.UndeclaredRunnerAccountingTransition, envelope.applyDelta(forbidden, &proposal));
    try std.testing.expectError(error.MissingRunnerAccountingTransition, envelope.apply(action.Action.contract, pipeline.DataEffects.fromContract(action.Action.contract)));
    try std.testing.expect(empty.record(fixture.id(.inference)) == null);
    try std.testing.expect(transition.expected_ledger == empty);
    try std.testing.expect(transition.expected_operation_revision == null);
    try std.testing.expect(transition.command == .assign_inference);
    _ = try fixture.change(.inference, .{ .assign_inference = facts() });
    try std.testing.expectError(error.ProviderOperationRevisionConflict, lifecycle.apply(fixture.ledger(), fixture.authority(), transition));
    const before = fixture.ledger();
    try std.testing.expectError(error.ProviderOperationRevisionConflict, fixture.requests.providerOperations().advance(fixture.authority(), before.revision(), fixture.id(.inference), .{ .value = 0 }, .{ .terminate = .{ .cancelled = .not_sent } }));
    var wrong_authority = fixture.authority();
    wrong_authority.expected_request_revision.value += 1;
    try std.testing.expectError(error.ProviderOperationRequestRevisionConflict, (action.Action{}).execute(before, wrong_authority, before.revision(), fixture.id(.inference), .{ .value = 1 }, .{ .terminate = .{ .cancelled = .not_sent } }));
    wrong_authority = fixture.authority();
    wrong_authority.expected_attempt_revision.value += 1;
    try std.testing.expectError(error.ProviderOperationAttemptRevisionConflict, (action.Action{}).execute(before, wrong_authority, before.revision(), fixture.id(.inference), .{ .value = 1 }, .{ .terminate = .{ .cancelled = .not_sent } }));
    try std.testing.expect(fixture.ledger() == before);
}

test "foreign forged and unreserved operation identities fail closed" {
    var fixture = try Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var other = try Fixture.init(std.testing.allocator);
    defer other.deinit();
    const foreign_transition = try lifecycle.propose(other.ledger(), other.authority(), .initial, other.id(.inference), null, .{ .assign_inference = facts() });
    try std.testing.expectError(error.ProviderOperationRevisionConflict, lifecycle.apply(fixture.ledger(), fixture.authority(), foreign_transition));
    var id = fixture.id(.inference);
    id.model_request_id = other.request;
    try std.testing.expectError(error.ProviderOperationRequestUnavailable, lifecycle.propose(fixture.ledger(), fixture.authority(), .initial, id, null, .{ .assign_inference = facts() }));
    var forged_request = fixture.request.*;
    id.model_request_id = &forged_request;
    try std.testing.expectError(error.ProviderOperationRequestUnavailable, lifecycle.propose(fixture.ledger(), fixture.authority(), .initial, id, null, .{ .assign_inference = facts() }));
    inline for (.{ 0, 2 }) |ordinal| {
        id = fixture.id(.inference);
        id.model_attempt_ordinal.value = ordinal;
        try std.testing.expectError(error.ProviderOperationAttemptUnavailable, lifecycle.propose(fixture.ledger(), fixture.authority(), .initial, id, null, .{ .assign_inference = facts() }));
    }
    var foreign_epoch = try lifecycle_runner.Runner.init(std.testing.allocator, other.requests.ledger().?.stageRunEpochId());
    defer foreign_epoch.deinit();
    try std.testing.expectError(error.ProviderOperationEpochConflict, foreign_epoch.advance(fixture.authority(), .initial, fixture.id(.inference), null, .{ .assign_inference = facts() }));
    inline for (0..3) |variant| {
        var invalid_facts = facts();
        switch (variant) {
            0 => invalid_facts.binding_id.operation_id.workflow_version += 1,
            1 => invalid_facts.binding_id.slot_id.bytes = "",
            2 => invalid_facts.model_visible_input_id.bytes = "",
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidProviderOperationBinding, fixture.change(.inference, .{ .assign_inference = invalid_facts }));
    }
    try fixture.requests.advance(fixture.requests.ledger().?.revision(), fixture.request, .assigned, .{ .terminal = .not_invoked_authorization_failure });
    try std.testing.expectError(error.ProviderOperationRequestUnavailable, fixture.change(.inference, .{ .assign_inference = facts() }));
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
    const record = try fixture.change(.inference, .{ .assign_inference = assigned_facts });
    @memset(&slot, 'x');
    @memset(&input, 'x');
    try std.testing.expectEqualStrings("slot", fixture.ledger().record(fixture.id(.inference)).?.binding_id.slot_id.bytes);
    try std.testing.expectEqualStrings("input", record.model_visible_input_id.bytes);
    try std.testing.expectEqual(@as(u64, 0), other.ledger().revision().value);
    try std.testing.expect(other.ledger().record(fixture.id(.inference)) == null);
}

test "abandoned assigned and invoked operations require no recovery for a fresh execution" {
    inline for (.{ false, true }) |invoked| {
        {
            var abandoned = try Fixture.init(std.testing.allocator);
            defer abandoned.deinit();
            _ = try abandoned.change(.inference, .{ .assign_inference = facts() });
            if (invoked) {
                try abandoned.invokeRequest();
                _ = try abandoned.change(.inference, .{ .invoke = invocation });
            }
            try std.testing.expectError(error.ProviderOperationStillOpen, abandoned.ledger().validateRequestClosure(abandoned.request));
        }
        var fresh = try Fixture.init(std.testing.allocator);
        defer fresh.deinit();
        try std.testing.expectEqual(lifecycle.Revision.initial, fresh.ledger().revision());
        try std.testing.expectEqual(@as(u32, 1), fresh.attempts.current().attemptsReserved(fresh.request));
        try std.testing.expectError(error.ProviderOperationNotFound, fresh.ledger().requireInvoked(fresh.id(.inference)));
        _ = try fresh.change(.inference, .{ .assign_inference = facts() });
        try fresh.invokeRequest();
        _ = try fresh.change(.inference, .{ .invoke = invocation });
        _ = try fresh.change(.inference, .{ .terminate = .completed });
        try fresh.requests.advance(fresh.requests.ledger().?.revision(), fresh.request, .invoked, .{ .terminal = .accepted });
    }
}

test "lifecycle allocation failures preserve current state and release all ownership" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(allocationCase, .{});
}

fn allocationCase(allocator: std.mem.Allocator) !void {
    var fixture = try Fixture.init(allocator);
    defer fixture.deinit();
    try fixture.startInference();
    const before = fixture.ledger();
    _ = fixture.change(.inference, .{ .terminate = .completed }) catch |err| {
        try std.testing.expect(before == fixture.ledger());
        return err;
    };
}

const invocation: lifecycle.Invocation = .{
    .deadline_monotonic_ms = 1000,
};

const Fixture = struct {
    requests: requests_module.Runner,
    attempts: attempts_module.Runner,
    request: *const identity.ModelRequestId,

    fn init(allocator: std.mem.Allocator) !Fixture {
        var requests = requests_module.Runner.init(allocator);
        errdefer requests.deinit();
        try requests.initialize(identity.RequestPurposeRegistry.all());
        const request = try requests.assign(.initial, .{ .task_cluster = .{
            .plan_state_id = .{ .bytes = "plan-1" },
            .obligation_cluster_id = .{ .bytes = "cluster-1" },
        } }, facts().binding_id.operation_id, .initial_generation);
        var attempts = try attempts_module.Runner.init(allocator, requests.ledger().?.stageRunEpochId());
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

    fn change(self: *Fixture, kind: provider.ProviderOperationKind, command: lifecycle.Command) !*const lifecycle.Record {
        const operation_id = self.id(kind);
        const previous = self.ledger().record(operation_id);
        try self.requests.providerOperations().advance(self.authority(), self.ledger().revision(), operation_id, if (previous) |record| record.revision else null, command);
        return self.ledger().record(operation_id).?;
    }

    fn invokeRequest(self: *Fixture) !void {
        try self.requests.advance(self.requests.ledger().?.revision(), self.request, .assigned, .invoked);
    }

    fn startInference(self: *Fixture) !void {
        _ = try self.change(.inference, .{ .assign_inference = facts() });
        try self.invokeRequest();
        _ = try self.change(.inference, .{ .invoke = invocation });
    }

    fn failure(self: *Fixture, kind: provider.ProviderOperationKind, delivery: provider.ProviderDeliveryDisposition) provider.ProviderFailure {
        return .{ .operation_id = self.id(kind), .cause = .authorization_denied, .retry_class = .never, .delivery = delivery };
    }

    fn retry(self: *Fixture) !void {
        _ = try self.attempts.reserve(self.attempts.current().revision(), self.requests.ledger().?, self.ledger(), self.requests.ledger().?.revision(), self.request, .{ .retry = .{
            .authority = .{
                .workflow_id = self.request.model_operation_id.workflow_id,
                .workflow_version = self.request.model_operation_id.workflow_version,
                .operation_instance_id = self.request.model_operation_id.workflow_step_id,
                .limit = .{ .value = 1 },
            },
            .completed_retries = 0,
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
            .controls = .{},
        },
        .model_visible_input_id = .{ .bytes = "input" },
    };
}
