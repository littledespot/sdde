const std = @import("std");
const accounting = @import("../domain/model_attempt_accounting.zig");
const identity = @import("../domain/model_request_identity.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const values = @import("pipeline_values.zig");
const data = @import("../domain/pipeline_data.zig");
const provider = @import("../domain/llm_provider_operation.zig");

pub const schema = values.schema(.accounted_model_attempt, accounting.AccountedAttempt, 1, null);
pub const operation_schema = values.schema(.assigned_provider_operation, lifecycle.AssignedOperation, 1, null);
pub const Error = accounting.Error || accounting.RequestError || identity.Error || lifecycle.Error || values.Error || error{InvalidAccountingTransition};

/// Execution-owned accounting only. No action dispatch, retry counter or I/O.
pub const State = struct {
    allocator: std.mem.Allocator,
    attempts: *accounting.Owner,
    operations: *lifecycle.Owner,
    current_operations: *const lifecycle.Ledger,
    requests: *identity.Owner,

    pub fn init(allocator: std.mem.Allocator, requests: *const identity.ModelRequestIdentityLedger) Error!State {
        const retained = try identity.retainLedger(requests);
        errdefer identity.deinitOwner(retained);
        const attempts = try accounting.createInitial(allocator, requests.stageRunEpochId());
        errdefer accounting.deinitOwner(attempts);
        const operations = try lifecycle.createInitial(allocator, requests.stageRunEpochId());
        return .{ .allocator = allocator, .attempts = attempts, .operations = operations, .current_operations = lifecycle.initial(operations), .requests = retained };
    }

    pub fn deinit(self: *State) void {
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
        const evidence = try successor.requireAssigned(id);
        const retained = try identity.retainLedger(requests);
        errdefer identity.deinitOwner(retained);
        const owner = try self.allocator.create(RetainedOperation);
        errdefer self.allocator.destroy(owner);
        try lifecycle.retainOwner(self.operations);
        errdefer lifecycle.deinitOwner(self.operations);
        try identity.retainOwner(retained);
        errdefer identity.deinitOwner(retained);
        owner.* = .{ .allocator = self.allocator, .operations = self.operations, .requests = retained, .evidence = evidence };
        const value = try values.adopt(self.allocator, operation_schema, lifecycle.AssignedOperation, RetainedOperation, owner, RetainedOperation.get, RetainedOperation.destroy, null);
        return .{ .successor = .{ .operations = successor }, .requests = retained, .value = value };
    }

    pub fn validateAssignment(self: *const State, evidence: *const lifecycle.AssignedOperation, request: *const provider.IdentifiedProviderNeutralModelRequest) Error!void {
        const record = evidence.record();
        if (record.id.model_request_id != request.model_request_id or
            !record.binding_id.eql(request.binding_id) or !record.model_visible_input_id.eql(request.model_visible_input_id) or
            record.id.model_attempt_ordinal.value != accounting.accounting(self.attempts).attemptsReserved(request.model_request_id) or
            try self.current_operations.requireAssigned(record.id) != evidence) return error.InvalidAccountingTransition;
    }

    pub fn commit(self: *State, pending: Pending) void {
        switch (pending.successor) {
            .attempts => |next| {
                accounting.deinitOwner(self.attempts);
                self.attempts = next;
            },
            .operations => |next| self.current_operations = next,
        }
        identity.deinitOwner(self.requests);
        self.requests = pending.requests;
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

const RetainedOperation = struct {
    allocator: std.mem.Allocator,
    operations: *lifecycle.Owner,
    requests: *identity.Owner,
    evidence: *const lifecycle.AssignedOperation,

    fn get(self: *const RetainedOperation) *const lifecycle.AssignedOperation {
        return self.evidence;
    }

    fn destroy(self: *RetainedOperation) void {
        lifecycle.deinitOwner(self.operations);
        identity.deinitOwner(self.requests);
        self.allocator.destroy(self);
    }
};

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
