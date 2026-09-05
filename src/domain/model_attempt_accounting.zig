const std = @import("std");
const operation = @import("llm_provider_operation.zig");
const request_identity = @import("model_request_identity.zig");
const workflow_retry = @import("workflow_retry.zig");

pub const Revision = struct {
    value: u64,

    pub const initial: Revision = .{ .value = 0 };

    pub fn eql(left: Revision, right: Revision) bool {
        return left.value == right.value;
    }
};

pub const Attempt = union(enum) {
    initial,
    retry: struct {
        authority: workflow_retry.CompiledAuthority,
        // Borrowed observation of the runner's operation-local counter, not
        // a second counter derived from this request's total attempt ordinal.
        completed_retries: u64,
    },

    pub fn eql(left: Attempt, right: Attempt) bool {
        if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
        return switch (left) {
            .initial => true,
            .retry => |value| value.authority.eql(right.retry.authority) and value.completed_retries == right.retry.completed_retries,
        };
    }
};

/// Read-only view of a canonical applied accounting record, never a proposal.
pub const AccountedAttempt = opaque {
    pub fn requestId(self: *const AccountedAttempt) *const request_identity.ModelRequestId {
        const record: *const Record = @ptrCast(@alignCast(self));
        return record.model_request_id;
    }

    pub fn ordinal(self: *const AccountedAttempt) operation.ModelAttemptOrdinal {
        const record: *const Record = @ptrCast(@alignCast(self));
        return operation.ModelAttemptOrdinal.init(record.attempts_reserved).?;
    }
};

pub fn latestAttempt(owner: *const Owner) *const AccountedAttempt {
    return @ptrCast(ownerStorageConst(owner).accounting.latest_record.?);
}

pub const Transition = struct {
    stage_run_epoch_id: request_identity.StageRunEpochId,
    model_request_id: *const request_identity.ModelRequestId,
    expected_revision: Revision,
    expected_request_value: u32,
    next_request_value: u32,
    attempt: Attempt,

    pub fn ordinal(self: Transition) operation.ModelAttemptOrdinal {
        return operation.ModelAttemptOrdinal.init(self.next_request_value).?;
    }
};

pub const RunnerModelAttemptAccounting = opaque {
    pub fn stageRunEpochId(self: *const RunnerModelAttemptAccounting) request_identity.StageRunEpochId {
        return storage(self).stage_run_epoch_id;
    }

    pub fn revision(self: *const RunnerModelAttemptAccounting) Revision {
        return storage(self).revision;
    }

    pub fn attemptsReserved(
        self: *const RunnerModelAttemptAccounting,
        request_id: *const request_identity.ModelRequestId,
    ) u32 {
        const record = resolveRecord(storage(self), request_id) orelse return 0;
        return record.attempts_reserved;
    }
};

pub const Owner = opaque {};

const Record = struct {
    previous: ?*const Record,
    model_request_id: *const request_identity.ModelRequestId,
    attempts_reserved: u32,
};

const Storage = struct {
    owner: *Owner,
    stage_run_epoch_id: request_identity.StageRunEpochId,
    revision: Revision,
    latest_record: ?*const Record,
};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    reference_count: usize,
    previous_owner: ?*Owner,
    arena: std.heap.ArenaAllocator,
    accounting: Storage,
};

pub const ValidationError = error{
    InvalidAttemptClassification,
    ModelAttemptAccountingRevisionConflict,
    ModelAttemptValueConflict,
    ModelRetryLimitExhausted,
    ModelAttemptOrdinalExhausted,
    ModelAttemptAccountingRevisionExhausted,
    ModelAttemptAccountingOwnerReferenceExhausted,
    ModelAttemptAccountingEpochConflict,
};

pub const ProposalError = error{
    InvalidAttemptClassification,
    ModelAttemptAccountingRevisionConflict,
    ModelRetryLimitExhausted,
    ModelAttemptOrdinalExhausted,
};

pub const Error = std.mem.Allocator.Error || ValidationError;

pub const RequestError = @import("provider_operation_lifecycle.zig").ValidationError || error{
    ModelRequestLedgerRevisionConflict,
    ModelRequestUnavailableForAttempt,
};

pub fn validateRequest(current: *const RunnerModelAttemptAccounting, requests: *const request_identity.ModelRequestIdentityLedger, operations: *const @import("provider_operation_lifecycle.zig").Ledger, revision: request_identity.LedgerRevision, request: *const request_identity.ModelRequestId) RequestError!*const request_identity.ModelRequestId {
    if (!requests.revision().eql(revision)) return error.ModelRequestLedgerRevisionConflict;
    const record = requests.record(request) orelse return error.ModelRequestUnavailableForAttempt;
    if (record.status == .terminal or !current.stageRunEpochId().eql(record.model_request_id.stage_run_epoch_id)) return error.ModelRequestUnavailableForAttempt;
    const canonical = requests.canonicalRequestId(request) orelse return error.ModelRequestUnavailableForAttempt;
    try operations.validateRequestClosure(canonical);
    return canonical;
}

pub fn createInitial(
    allocator: std.mem.Allocator,
    stage_run_epoch_id: request_identity.StageRunEpochId,
) Error!*Owner {
    const value = try allocator.create(OwnerStorage);
    errdefer allocator.destroy(value);
    value.* = .{
        .backing_allocator = allocator,
        .reference_count = 1,
        .previous_owner = null,
        .arena = .init(allocator),
        .accounting = undefined,
    };
    errdefer value.arena.deinit();
    const epoch = stage_run_epoch_id.reference.retain();
    const owner: *Owner = @ptrCast(value);
    value.accounting = .{
        .owner = owner,
        .stage_run_epoch_id = .{ .reference = epoch },
        .revision = .initial,
        .latest_record = null,
    };
    return owner;
}

pub fn propose(
    current: *const RunnerModelAttemptAccounting,
    expected_revision: Revision,
    model_request_id: *const request_identity.ModelRequestId,
    attempt: Attempt,
) ProposalError!Transition {
    const current_storage = storage(current);
    if (!current_storage.revision.eql(expected_revision)) {
        return error.ModelAttemptAccountingRevisionConflict;
    }
    const reserved = if (resolveRecord(current_storage, model_request_id)) |record|
        record.attempts_reserved
    else
        0;
    try validateAttempt(model_request_id, attempt, reserved);
    const next = std.math.add(u32, reserved, 1) catch {
        return error.ModelAttemptOrdinalExhausted;
    };
    return .{
        .stage_run_epoch_id = current_storage.stage_run_epoch_id,
        .model_request_id = model_request_id,
        .expected_revision = expected_revision,
        .expected_request_value = reserved,
        .next_request_value = next,
        .attempt = attempt,
    };
}

pub fn apply(
    current: *const RunnerModelAttemptAccounting,
    transition: Transition,
) Error!*Owner {
    const current_storage = storage(current);
    if (!current_storage.revision.eql(transition.expected_revision)) {
        return error.ModelAttemptAccountingRevisionConflict;
    }
    if (!current_storage.stage_run_epoch_id.eql(transition.stage_run_epoch_id) or
        !current_storage.stage_run_epoch_id.eql(transition.model_request_id.stage_run_epoch_id))
    {
        return error.ModelAttemptAccountingEpochConflict;
    }
    const reserved = if (resolveRecord(current_storage, transition.model_request_id)) |record|
        record.attempts_reserved
    else
        0;
    if (reserved != transition.expected_request_value) return error.ModelAttemptValueConflict;
    try validateAttempt(transition.model_request_id, transition.attempt, reserved);
    const expected_next = std.math.add(u32, reserved, 1) catch {
        return error.ModelAttemptOrdinalExhausted;
    };
    if (transition.next_request_value != expected_next) return error.ModelAttemptValueConflict;
    const next_revision = std.math.add(u64, current_storage.revision.value, 1) catch {
        return error.ModelAttemptAccountingRevisionExhausted;
    };

    const previous_owner = current_storage.owner;
    const previous_storage = ownerStorage(previous_owner);
    const value = try previous_storage.backing_allocator.create(OwnerStorage);
    errdefer previous_storage.backing_allocator.destroy(value);
    value.* = .{
        .backing_allocator = previous_storage.backing_allocator,
        .reference_count = 1,
        .previous_owner = null,
        .arena = .init(previous_storage.backing_allocator),
        .accounting = undefined,
    };
    errdefer value.arena.deinit();
    const record = try value.arena.allocator().create(Record);
    record.* = .{
        .previous = current_storage.latest_record,
        .model_request_id = transition.model_request_id,
        .attempts_reserved = transition.next_request_value,
    };
    try retainOwner(previous_owner);
    value.previous_owner = previous_owner;
    const owner: *Owner = @ptrCast(value);
    value.accounting = .{
        .owner = owner,
        .stage_run_epoch_id = current_storage.stage_run_epoch_id,
        .revision = .{ .value = next_revision },
        .latest_record = record,
    };
    return owner;
}

pub fn accounting(owner: *const Owner) *const RunnerModelAttemptAccounting {
    return @ptrCast(&ownerStorageConst(owner).accounting);
}

pub fn deinitOwner(owner: *Owner) void {
    var next: ?*Owner = owner;
    while (next) |current| {
        const value = ownerStorage(current);
        std.debug.assert(value.reference_count > 0);
        value.reference_count -= 1;
        if (value.reference_count != 0) return;
        const previous = value.previous_owner;
        if (previous == null) value.accounting.stage_run_epoch_id.reference.release();
        const allocator = value.backing_allocator;
        value.arena.deinit();
        allocator.destroy(value);
        next = previous;
    }
}

fn validateAttempt(
    model_request_id: *const request_identity.ModelRequestId,
    attempt: Attempt,
    reserved: u32,
) ProposalError!void {
    switch (attempt) {
        .initial => if (reserved != 0) return error.InvalidAttemptClassification,
        .retry => |retry| {
            const authority = retry.authority;
            if (reserved == 0 or !authority.isValid() or
                !std.mem.eql(u8, authority.workflow_id.bytes, model_request_id.model_operation_id.workflow_id.bytes) or
                authority.workflow_version != model_request_id.model_operation_id.workflow_version)
            {
                return error.InvalidAttemptClassification;
            }
            if (retry.completed_retries >= authority.limit.value) return error.ModelRetryLimitExhausted;
        },
    }
}

fn resolveRecord(
    current: *const Storage,
    model_request_id: *const request_identity.ModelRequestId,
) ?*const Record {
    var record = current.latest_record;
    while (record) |value| : (record = value.previous) {
        if (value.model_request_id == model_request_id) return value;
    }
    return null;
}

pub fn retainOwner(owner: *Owner) ValidationError!void {
    const value = ownerStorage(owner);
    std.debug.assert(value.reference_count > 0);
    value.reference_count = std.math.add(usize, value.reference_count, 1) catch {
        return error.ModelAttemptAccountingOwnerReferenceExhausted;
    };
}

fn storage(value: *const RunnerModelAttemptAccounting) *const Storage {
    return @ptrCast(@alignCast(value));
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
