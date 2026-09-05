const std = @import("std");
const provider = @import("llm_provider_operation.zig");
const binding = @import("llm_provider_binding.zig");
const identity = @import("model_request_identity.zig");
const accounting = @import("model_attempt_accounting.zig");

pub const Revision = struct {
    value: u64,
    pub const initial: Revision = .{ .value = 0 };

    pub fn eql(left: Revision, right: Revision) bool {
        return left.value == right.value;
    }
};

pub const Status = enum { assigned, invoked, terminal };
pub const Assignment = struct {
    binding_id: binding.ProviderModelBindingId,
    model_visible_input_id: provider.ModelVisibleInputId,
};
pub const Invocation = struct {
    deadline_monotonic_ms: u64,
};
pub const Terminal = union(enum) {
    counted: provider.ExactInputTokenCountEvidence,
    completed,
    stopped: provider.ProviderNonCandidateStopReason,
    failed: provider.ProviderFailure,
    preparation_failed: provider.ProviderFailure,
    cancelled: provider.ProviderDeliveryDisposition,
};
pub const Command = union(enum) {
    assign_count: Assignment,
    assign_inference: Assignment,
    invoke: Invocation,
    terminate: Terminal,
};

// A terminal record stores only facts, never provider content or duplicated IDs.
pub const FailureFact = struct {
    cause: provider.ProviderFailureCause,
    retry_class: provider.ProviderRetryClass,
    delivery: provider.ProviderDeliveryDisposition,
};
pub const TerminalFact = union(enum) {
    counted: u64,
    completed,
    stopped: provider.ProviderNonCandidateStopReason,
    failed: FailureFact,
    preparation_failed: FailureFact,
    cancelled: provider.ProviderDeliveryDisposition,

    pub fn delivery(self: TerminalFact) provider.ProviderDeliveryDisposition {
        return switch (self) {
            .counted, .completed, .stopped => .response_received,
            .failed, .preparation_failed => |failure| failure.delivery,
            .cancelled => |value| value,
        };
    }
};
pub const State = union(Status) {
    assigned,
    invoked: provider.InvokedProviderOperation,
    terminal: TerminalFact,
};
pub const Record = struct {
    id: provider.ProviderOperationId,
    binding_id: binding.ProviderModelBindingId,
    model_visible_input_id: provider.ModelVisibleInputId,
    revision: Revision,
    state: State,
};

pub const Authority = struct {
    requests: *const identity.ModelRequestIdentityLedger,
    expected_request_revision: identity.LedgerRevision,
    attempts: *const accounting.RunnerModelAttemptAccounting,
    expected_attempt_revision: accounting.Revision,
};
pub const Transition = struct {
    expected_ledger: *const Ledger,
    expected_revision: Revision,
    operation_id: provider.ProviderOperationId,
    expected_operation_revision: ?Revision,
    command: Command,
};

pub const Ledger = opaque {
    pub fn revision(self: *const Ledger) Revision {
        return storage(self).revision;
    }

    pub fn stageRunEpochId(self: *const Ledger) identity.StageRunEpochId {
        return storage(self).epoch;
    }

    pub fn record(self: *const Ledger, id: provider.ProviderOperationId) ?*const Record {
        var node = storage(self).latest;
        while (node) |value| : (node = value.previous) {
            if (value.record.id.eql(id)) return &value.record;
        }
        return null;
    }

    pub fn requireInvoked(self: *const Ledger, id: provider.ProviderOperationId) ValidationError!*const provider.InvokedProviderOperation {
        const found = self.record(id) orelse return error.ProviderOperationNotFound;
        return switch (found.state) {
            .invoked => |*value| value,
            .assigned, .terminal => error.ProviderOperationNotInvoked,
        };
    }

    pub fn validateRequestClosure(self: *const Ledger, request: *const identity.ModelRequestId) ValidationError!void {
        if (!self.stageRunEpochId().eql(request.stage_run_epoch_id)) return error.ProviderOperationEpochConflict;
        var node = storage(self).latest;
        while (node) |value| : (node = value.previous) {
            if (value.record.id.model_request_id != request) continue;
            const current = self.record(value.record.id).?;
            if (current.state != .terminal) return error.ProviderOperationStillOpen;
        }
    }
};

// One execution owner retains immutable snapshots. Canonical request IDs are
// borrowed from the request runner, which destroys this owner before its ledger.
pub const Owner = opaque {};
const Node = struct { previous: ?*const Node, record: Record };
const Storage = struct {
    owner: *Owner,
    epoch: identity.StageRunEpochId,
    revision: Revision,
    latest: ?*const Node,
};
const OwnerStorage = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    initial: Storage,
};

pub const ValidationError = error{
    InvalidStageRunEpochId,
    ProviderOperationEpochConflict,
    ProviderOperationRevisionConflict,
    ProviderOperationRevisionExhausted,
    ProviderOperationRequestRevisionConflict,
    ProviderOperationAttemptRevisionConflict,
    ProviderOperationRequestUnavailable,
    ProviderOperationAttemptUnavailable,
    ProviderOperationNotFound,
    ProviderOperationNotInvoked,
    ProviderOperationStillOpen,
    InvalidProviderOperationTransition,
    InvalidProviderOperationBinding,
    InvalidProviderOperationCountEvidence,
};
pub const Error = std.mem.Allocator.Error || ValidationError;

pub fn createInitial(allocator: std.mem.Allocator, epoch: identity.StageRunEpochId) Error!*Owner {
    if (!epoch.isValid()) return error.InvalidStageRunEpochId;
    const value = try allocator.create(OwnerStorage);
    errdefer allocator.destroy(value);
    value.* = .{ .allocator = allocator, .arena = .init(allocator), .initial = undefined };
    errdefer value.arena.deinit();
    const owned_epoch = try value.arena.allocator().dupe(u8, epoch.bytes);
    const owner: *Owner = @ptrCast(value);
    value.initial = .{ .owner = owner, .epoch = .{ .bytes = owned_epoch }, .revision = .initial, .latest = null };
    return owner;
}

pub fn initial(owner: *const Owner) *const Ledger {
    const value: *const OwnerStorage = @ptrCast(@alignCast(owner));
    return @ptrCast(&value.initial);
}

pub fn deinitOwner(owner: *Owner) void {
    const value = ownerStorage(owner);
    const allocator = value.allocator;
    value.arena.deinit();
    allocator.destroy(value);
}

pub fn propose(
    current: *const Ledger,
    authority: Authority,
    expected_revision: Revision,
    id: provider.ProviderOperationId,
    expected_operation_revision: ?Revision,
    command: Command,
) ValidationError!Transition {
    const transition: Transition = .{
        .expected_ledger = current,
        .expected_revision = expected_revision,
        .operation_id = id,
        .expected_operation_revision = expected_operation_revision,
        .command = command,
    };
    _ = try nextRecord(current, authority, transition);
    return transition;
}

pub fn apply(current: *const Ledger, authority: Authority, transition: Transition) Error!*const Ledger {
    const next = try nextRecord(current, authority, transition);
    const next_revision = std.math.add(u64, current.revision().value, 1) catch return error.ProviderOperationRevisionExhausted;
    const source = storage(current);
    const allocator = ownerStorage(source.owner).arena.allocator();
    const snapshot = try allocator.create(Storage);
    const node = try allocator.create(Node);
    var owned = next;
    if (transition.command == .assign_count or transition.command == .assign_inference) {
        owned.binding_id = try cloneBinding(allocator, next.binding_id);
        owned.model_visible_input_id.bytes = try allocator.dupe(u8, next.model_visible_input_id.bytes);
    }
    node.* = .{ .previous = source.latest, .record = owned };
    snapshot.* = .{ .owner = source.owner, .epoch = source.epoch, .revision = .{ .value = next_revision }, .latest = node };
    return @ptrCast(snapshot);
}

fn nextRecord(current: *const Ledger, authority: Authority, transition: Transition) ValidationError!Record {
    if (transition.expected_ledger != current or !current.revision().eql(transition.expected_revision)) return error.ProviderOperationRevisionConflict;
    if (!authority.requests.revision().eql(authority.expected_request_revision)) return error.ProviderOperationRequestRevisionConflict;
    if (!authority.attempts.revision().eql(authority.expected_attempt_revision)) return error.ProviderOperationAttemptRevisionConflict;
    const id = transition.operation_id;
    const request = authority.requests.canonicalRequestId(id.model_request_id) orelse return error.ProviderOperationRequestUnavailable;
    if (request != id.model_request_id or authority.requests.record(request).?.status == .terminal) return error.ProviderOperationRequestUnavailable;
    if (!current.stageRunEpochId().eql(request.stage_run_epoch_id) or
        !current.stageRunEpochId().eql(authority.attempts.stageRunEpochId())) return error.ProviderOperationEpochConflict;
    if (id.model_attempt_ordinal.value == 0 or
        id.model_attempt_ordinal.value != authority.attempts.attemptsReserved(request)) return error.ProviderOperationAttemptUnavailable;
    const previous = current.record(id);
    if (previous) |record| {
        const expected = transition.expected_operation_revision orelse return error.ProviderOperationRevisionConflict;
        if (!record.revision.eql(expected)) return error.ProviderOperationRevisionConflict;
    } else if (transition.expected_operation_revision != null) return error.ProviderOperationNotFound;

    switch (transition.command) {
        .assign_count, .assign_inference => |facts| {
            const kind: provider.ProviderOperationKind = if (transition.command == .assign_count) .input_token_count else .inference;
            if (previous != null or id.kind != kind) return error.InvalidProviderOperationTransition;
            try current.validateRequestClosure(request);
            try validateBinding(request, facts);
            return assignedRecord(id, facts);
        },
        .invoke => |invocation| {
            const record = previous orelse return error.ProviderOperationNotFound;
            if (record.state != .assigned or authority.requests.record(request).?.status != .invoked) return error.InvalidProviderOperationTransition;
            var next = record.*;
            next.revision = try increment(record.revision);
            next.state = .{ .invoked = provider.InvokedProviderOperation.init(id, invocation.deadline_monotonic_ms) orelse return error.InvalidProviderOperationTransition };
            return next;
        },
        .terminate => |terminal| {
            const record = previous orelse return error.ProviderOperationNotFound;
            var next = record.*;
            next.state = .{ .terminal = try terminalFact(record.*, terminal) };
            next.revision = try increment(record.revision);
            return next;
        },
    }
}

fn assignedRecord(id: provider.ProviderOperationId, facts: Assignment) Record {
    return .{ .id = id, .binding_id = facts.binding_id, .model_visible_input_id = facts.model_visible_input_id, .revision = .{ .value = 1 }, .state = .assigned };
}

fn terminalFact(record: Record, terminal: Terminal) ValidationError!TerminalFact {
    if (record.state == .terminal) return error.InvalidProviderOperationTransition;
    switch (terminal) {
        .preparation_failed => |failure| {
            if (record.state != .assigned or !failure.operation_id.eql(record.id) or failure.delivery != .not_sent) return error.InvalidProviderOperationTransition;
            return .{ .preparation_failed = failureFact(failure) };
        },
        .cancelled => |delivery| {
            if (record.state == .assigned and delivery != .not_sent) return error.InvalidProviderOperationTransition;
            return .{ .cancelled = delivery };
        },
        .counted => |evidence| {
            if (record.state != .invoked or record.id.kind != .input_token_count) return error.InvalidProviderOperationTransition;
            try validateEvidence(record, evidence);
            return .{ .counted = evidence.input_tokens };
        },
        .completed => {
            if (record.state != .invoked or record.id.kind != .inference) return error.InvalidProviderOperationTransition;
            return .completed;
        },
        .stopped => |reason| {
            if (record.state != .invoked or record.id.kind != .inference) return error.InvalidProviderOperationTransition;
            return .{ .stopped = reason };
        },
        .failed => |failure| {
            if (record.state != .invoked or !failure.operation_id.eql(record.id)) return error.InvalidProviderOperationTransition;
            return .{ .failed = failureFact(failure) };
        },
    }
}

fn validateBinding(request: *const identity.ModelRequestId, facts: Assignment) ValidationError!void {
    if (!facts.binding_id.isValid() or !facts.binding_id.operation_id.eql(request.model_operation_id) or
        provider.ModelVisibleInputId.parse(facts.model_visible_input_id.bytes) == null) return error.InvalidProviderOperationBinding;
}
fn validateEvidence(record: Record, evidence: provider.ExactInputTokenCountEvidence) ValidationError!void {
    if (!record.id.eql(evidence.count_operation_id) or !record.binding_id.eql(evidence.binding_id) or
        !record.model_visible_input_id.eql(evidence.model_visible_input_id)) return error.InvalidProviderOperationCountEvidence;
}
fn failureFact(failure: provider.ProviderFailure) FailureFact {
    return .{ .cause = failure.cause, .retry_class = failure.retry_class, .delivery = failure.delivery };
}
fn increment(revision: Revision) ValidationError!Revision {
    return .{ .value = std.math.add(u64, revision.value, 1) catch return error.ProviderOperationRevisionExhausted };
}
fn cloneBinding(allocator: std.mem.Allocator, source: binding.ProviderModelBindingId) std.mem.Allocator.Error!binding.ProviderModelBindingId {
    var result = source;
    result.operation_id.workflow_id.bytes = try allocator.dupe(u8, source.operation_id.workflow_id.bytes);
    result.operation_id.workflow_step_id.bytes = try allocator.dupe(u8, source.operation_id.workflow_step_id.bytes);
    result.slot_id.bytes = try allocator.dupe(u8, source.slot_id.bytes);
    if (source.reasoning_effort) |value| result.reasoning_effort = try allocator.dupe(u8, value);
    return result;
}
fn storage(value: *const Ledger) *const Storage {
    return @ptrCast(@alignCast(value));
}
fn ownerStorage(value: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(value));
}
