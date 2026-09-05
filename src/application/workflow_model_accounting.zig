const std = @import("std");
const accounting = @import("../domain/model_attempt_accounting.zig");
const identity = @import("../domain/model_request_identity.zig");
const lifecycle = @import("../domain/provider_operation_lifecycle.zig");
const values = @import("pipeline_values.zig");
const data = @import("../domain/pipeline_data.zig");

pub const schema = values.schema(.accounted_model_attempt, accounting.AccountedAttempt, 1, null);
pub const Error = accounting.Error || accounting.RequestError || identity.Error || lifecycle.Error || values.Error || error{InvalidAccountingTransition};

/// Execution-owned accounting only. No action dispatch, retry counter or I/O.
pub const State = struct {
    allocator: std.mem.Allocator,
    attempts: *accounting.Owner,
    operations: *lifecycle.Owner,
    requests: *identity.Owner,

    pub fn init(allocator: std.mem.Allocator, requests: *const identity.ModelRequestIdentityLedger) Error!State {
        const retained = try identity.retainLedger(requests);
        errdefer identity.deinitOwner(retained);
        const attempts = try accounting.createInitial(allocator, requests.stageRunEpochId());
        errdefer accounting.deinitOwner(attempts);
        const operations = try lifecycle.createInitial(allocator, requests.stageRunEpochId());
        return .{ .allocator = allocator, .attempts = attempts, .operations = operations, .requests = retained };
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
        _ = try accounting.validateRequest(current, requests, lifecycle.initial(self.operations), requests.revision(), request);
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
        return .{ .attempts = successor, .requests = retained, .value = value };
    }

    pub fn commit(self: *State, pending: Pending) void {
        accounting.deinitOwner(self.attempts);
        identity.deinitOwner(self.requests);
        self.attempts = pending.attempts;
        self.requests = pending.requests;
    }
};

pub const Pending = struct {
    attempts: *accounting.Owner,
    requests: *identity.Owner,
    value: *data.Value,

    // The candidate/envelope owns value after staging; this releases only the
    // unapplied state references when envelope validation rejects the delta.
    pub fn discard(self: Pending) void {
        accounting.deinitOwner(self.attempts);
        identity.deinitOwner(self.requests);
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
