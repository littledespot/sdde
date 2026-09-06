const std = @import("std");
const accounting = @import("../domain/model_attempt_accounting.zig");
const identity = @import("../domain/model_request_identity.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const values = @import("pipeline_values.zig");
const data = @import("../domain/pipeline_data.zig");
const provider = @import("../domain/llm_provider_operation.zig");
const leases = @import("provider_authorization_lease_table.zig");

pub const schema = values.schema(.accounted_model_attempt, accounting.AccountedAttempt, 1, null);
pub const operation_schema = values.schema(.assigned_provider_operation, lifecycle.AssignedOperation, 1, null);
pub const invoked_schema = values.schema(.invoked_provider_operation, lifecycle.InvokedOperation, 1, null);
pub const terminal_schema = values.schema(.terminal_provider_operation, lifecycle.TerminalOperation, 1, null);
pub const Error = accounting.Error || accounting.RequestError || identity.Error || lifecycle.Error || values.Error || error{InvalidAccountingTransition};

/// Expected terminal facts retain their exact applied source, not a second record.
pub const Completion = struct {
    source: CompletionSource,
    terminal: lifecycle.Terminal,
    outcome: @import("../domain/workflow.zig").OutcomeTag,
};

pub const CompletionSource = union(enum) {
    assigned: *const lifecycle.AssignedOperation,
    invoked: *const provider.InvokedProviderOperation,

    pub fn id(self: CompletionSource) provider.ProviderOperationId {
        return switch (self) {
            .assigned => |value| value.record().id,
            .invoked => |value| value.id,
        };
    }

    pub fn key(self: CompletionSource) @import("../domain/pipeline.zig").DataKey {
        return switch (self) {
            .assigned => .assigned_provider_operation,
            .invoked => .invoked_provider_operation,
        };
    }
};

/// Execution-owned accounting only. No action dispatch, retry counter or I/O.
pub const State = struct {
    allocator: std.mem.Allocator,
    attempts: *accounting.Owner,
    operations: *lifecycle.Owner,
    current_operations: *const lifecycle.Ledger,
    authorization_leases: leases.Table,
    requests: *identity.Owner,

    pub fn init(allocator: std.mem.Allocator, requests: *const identity.ModelRequestIdentityLedger) Error!State {
        const retained = try identity.retainLedger(requests);
        errdefer identity.deinitOwner(retained);
        const attempts = try accounting.createInitial(allocator, requests.stageRunEpochId());
        errdefer accounting.deinitOwner(attempts);
        const operations = try lifecycle.createInitial(allocator, requests.stageRunEpochId());
        return .{ .allocator = allocator, .attempts = attempts, .operations = operations, .current_operations = lifecycle.initial(operations), .authorization_leases = leases.Table.init(allocator, lifecycle.initial(operations)), .requests = retained };
    }

    pub fn deinit(self: *State) void {
        self.authorization_leases.deinit();
        lifecycle.deinitOwner(self.operations);
        accounting.deinitOwner(self.attempts);
        identity.deinitOwner(self.requests);
        self.* = undefined;
    }

    /// Construct the successor and sealed output before publishing either.
    pub fn prepare(self: *const State, requests: *const identity.ModelRequestIdentityLedger, request: *const identity.ModelRequestId, expected: accounting.Attempt, transition: accounting.Transition) Error!Pending {
        if (transition.model_request_id != request or !transition.attempt.eql(expected)) return error.InvalidAccountingTransition;
        const current = accounting.accounting(self.attempts);
        _ = try accounting.validateRequest(current, requests, self.current_operations, requests.revision(), request);
        const successor = try accounting.apply(current, transition);
        errdefer accounting.deinitOwner(successor);
        const retained = try identity.retainLedger(requests);
        errdefer identity.deinitOwner(retained);
        const owner = try self.allocator.create(RetainedAttempt);
        errdefer self.allocator.destroy(owner);
        try accounting.retainOwner(successor);
        errdefer accounting.deinitOwner(successor);
        try identity.retainOwner(retained);
        errdefer identity.deinitOwner(retained);
        owner.* = .{ .allocator = self.allocator, .attempts = successor, .requests = retained };
        const value = try values.adopt(self.allocator, schema, accounting.AccountedAttempt, RetainedAttempt, owner, RetainedAttempt.get, RetainedAttempt.destroy, null);
        return .{ .successor = .{ .attempts = successor }, .requests = retained, .value = value };
    }

    pub fn operationAuthority(self: *const State, requests: *const identity.ModelRequestIdentityLedger) lifecycle.Authority {
        const current = accounting.accounting(self.attempts);
        return .{ .requests = requests, .expected_request_revision = requests.revision(), .attempts = current, .expected_attempt_revision = current.revision() };
    }

    /// Retain the exact envelope snapshot; this is not a separately advanced ledger.
    pub fn replaceRequests(self: *State, requests: *identity.Owner) void {
        identity.deinitOwner(self.requests);
        self.requests = requests;
    }

    pub fn prepareAssignment(self: *const State, requests: *const identity.ModelRequestIdentityLedger, request: *const provider.IdentifiedProviderNeutralModelRequest, kind: provider.ProviderOperationKind, transition: lifecycle.Transition) Error!Pending {
        const id = transition.operation_id;
        if (id.model_request_id != request.model_request_id or id.kind != kind or
            id.model_attempt_ordinal.value != accounting.accounting(self.attempts).attemptsReserved(request.model_request_id)) return error.InvalidAccountingTransition;
        const facts = switch (transition.command) {
            .assign_inference => |facts| if (kind == .inference) facts else return error.InvalidAccountingTransition,
            .assign_count => |facts| if (kind == .input_token_count) facts else return error.InvalidAccountingTransition,
            .invoke, .terminate => return error.InvalidAccountingTransition,
        };
        if (!facts.binding_id.eql(request.binding_id) or !facts.model_visible_input_id.eql(request.model_visible_input_id)) return error.InvalidAccountingTransition;
        const successor = try lifecycle.apply(self.current_operations, self.operationAuthority(requests), transition);
        return self.retainOperation(lifecycle.AssignedOperation, operation_schema, requests, successor, try successor.requireAssigned(id));
    }

    pub fn prepareInvocation(self: *const State, requests: *const identity.ModelRequestIdentityLedger, request: *const provider.IdentifiedProviderNeutralModelRequest, assigned: *const lifecycle.AssignedOperation, invocation: lifecycle.Invocation, transition: lifecycle.Transition) Error!Pending {
        try self.validateAssignment(assigned, request);
        if (!transition.operation_id.eql(assigned.record().id) or transition.command != .invoke or
            transition.command.invoke.deadline_monotonic_ms != invocation.deadline_monotonic_ms) return error.InvalidAccountingTransition;
        const successor = try lifecycle.apply(self.current_operations, self.operationAuthority(requests), transition);
        return self.retainOperation(lifecycle.InvokedOperation, invoked_schema, requests, successor, try successor.requireInvocation(transition.operation_id));
    }

    pub fn prepareCompletion(self: *const State, requests: *const identity.ModelRequestIdentityLedger, request: *const provider.IdentifiedProviderNeutralModelRequest, expected: Completion, transition: lifecycle.Transition) Error!Pending {
        switch (expected.source) {
            .assigned => |value| try self.validateAssignment(value, request),
            .invoked => |value| try self.validateInvocation(value, request),
        }
        if (!transition.operation_id.eql(expected.source.id()) or transition.command != .terminate or
            !std.meta.eql(transition.command.terminate, expected.terminal)) return error.InvalidAccountingTransition;
        const successor = try lifecycle.apply(self.current_operations, self.operationAuthority(requests), transition);
        return self.retainOperation(lifecycle.TerminalOperation, terminal_schema, requests, successor, try successor.requireTerminal(expected.source.id()));
    }

    fn retainOperation(self: *const State, comptime T: type, comptime value_schema: data.Schema, requests: *const identity.ModelRequestIdentityLedger, successor: *const lifecycle.Ledger, evidence: *const T) Error!Pending {
        const Retained = RetainedOperation(T);
        const retained = try identity.retainLedger(requests);
        errdefer identity.deinitOwner(retained);
        const owner = try self.allocator.create(Retained);
        errdefer self.allocator.destroy(owner);
        try lifecycle.retainOwner(self.operations);
        errdefer lifecycle.deinitOwner(self.operations);
        try identity.retainOwner(retained);
        errdefer identity.deinitOwner(retained);
        owner.* = .{ .allocator = self.allocator, .operations = self.operations, .requests = retained, .evidence = evidence };
        const value = try values.adopt(self.allocator, value_schema, T, Retained, owner, Retained.get, Retained.destroy, null);
        return .{ .successor = .{ .operations = successor }, .requests = retained, .value = value };
    }

    pub fn validateAssignment(self: *const State, evidence: *const lifecycle.AssignedOperation, request: *const provider.IdentifiedProviderNeutralModelRequest) Error!void {
        const record = evidence.record();
        try self.validateOperation(record, request);
        if (try self.current_operations.requireAssigned(record.id) != evidence) return error.InvalidAccountingTransition;
    }

    pub fn validateInvocation(self: *const State, evidence: *const provider.InvokedProviderOperation, request: *const provider.IdentifiedProviderNeutralModelRequest) Error!void {
        const record = self.current_operations.record(evidence.id) orelse return error.InvalidAccountingTransition;
        try self.validateOperation(record, request);
        if (try self.current_operations.requireInvoked(record.id) != evidence) return error.InvalidAccountingTransition;
    }

    pub fn validateTerminal(self: *const State, evidence: *const lifecycle.TerminalOperation, request: *const provider.IdentifiedProviderNeutralModelRequest) Error!void {
        try self.validateOperation(evidence.record(), request);
        if (try self.current_operations.requireTerminal(evidence.record().id) != evidence) return error.InvalidAccountingTransition;
    }

    fn validateOperation(self: *const State, record: *const lifecycle.Record, request: *const provider.IdentifiedProviderNeutralModelRequest) Error!void {
        if (record.id.model_request_id != request.model_request_id or
            !record.binding_id.eql(request.binding_id) or !record.model_visible_input_id.eql(request.model_visible_input_id) or
            record.id.model_attempt_ordinal.value != accounting.accounting(self.attempts).attemptsReserved(request.model_request_id)) return error.InvalidAccountingTransition;
    }

    pub fn commit(self: *State, pending: Pending) void {
        switch (pending.successor) {
            .attempts => |next| {
                accounting.deinitOwner(self.attempts);
                self.attempts = next;
            },
            .operations => |next| {
                self.current_operations = next;
                self.authorization_leases.update(next);
            },
        }
        self.replaceRequests(pending.requests);
    }
};

pub const Pending = struct {
    successor: union(enum) { attempts: *accounting.Owner, operations: *const lifecycle.Ledger },
    requests: *identity.Owner,
    value: *data.Value,

    // The candidate/envelope owns value after staging; this releases only the
    // unapplied state references when envelope validation rejects the delta.
    pub fn discard(self: Pending) void {
        switch (self.successor) {
            .attempts => |next| accounting.deinitOwner(next),
            .operations => {}, // Immutable snapshots share the execution arena.
        }
        identity.deinitOwner(self.requests);
    }
};

fn RetainedOperation(comptime T: type) type {
    if (T != lifecycle.AssignedOperation and T != lifecycle.InvokedOperation and T != lifecycle.TerminalOperation) @compileError("operation evidence only");
    return struct {
        allocator: std.mem.Allocator,
        operations: *lifecycle.Owner,
        requests: *identity.Owner,
        evidence: *const T,

        fn get(self: *const @This()) *const T {
            return self.evidence;
        }

        fn destroy(self: *@This()) void {
            lifecycle.deinitOwner(self.operations);
            identity.deinitOwner(self.requests);
            self.allocator.destroy(self);
        }
    };
}

const RetainedAttempt = struct {
    allocator: std.mem.Allocator,
    attempts: *accounting.Owner,
    requests: *identity.Owner,

    fn get(self: *const RetainedAttempt) *const accounting.AccountedAttempt {
        return accounting.latestAttempt(self.attempts);
    }

    fn destroy(self: *RetainedAttempt) void {
        accounting.deinitOwner(self.attempts);
        identity.deinitOwner(self.requests);
        self.allocator.destroy(self);
    }
};
