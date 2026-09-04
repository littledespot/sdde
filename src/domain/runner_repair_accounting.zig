const std = @import("std");
const operation = @import("llm_provider_operation.zig");
const request_identity = @import("model_request_identity.zig");

pub const Revision = struct {
    value: u64,

    pub const initial: Revision = .{ .value = 0 };

    pub fn eql(left: Revision, right: Revision) bool {
        return left.value == right.value;
    }
};

pub const MaximumAttempts = struct {
    configured: u32,
    hard: u32,

    pub fn init(configured: u32, hard: u32) ?MaximumAttempts {
        if (configured == 0 or hard == 0) return null;
        return .{ .configured = configured, .hard = hard };
    }

    pub fn effective(self: MaximumAttempts) u32 {
        return @min(self.configured, self.hard);
    }
};

pub const ModelAttemptTransition = struct {
    stage_run_epoch_id: request_identity.StageRunEpochId,
    model_request_id: *const request_identity.ModelRequestId,
    expected_revision: Revision,
    expected_request_value: u32,
    next_request_value: u32,
    maximum: MaximumAttempts,

    pub fn ordinal(self: ModelAttemptTransition) operation.ModelAttemptOrdinal {
        return operation.ModelAttemptOrdinal.init(self.next_request_value).?;
    }
};

pub const Transition = union(enum) {
    increment_model_attempt: ModelAttemptTransition,
};

pub const RunnerRepairAccounting = opaque {
    pub fn stageRunEpochId(self: *const RunnerRepairAccounting) request_identity.StageRunEpochId {
        return storage(self).stage_run_epoch_id;
    }

    pub fn revision(self: *const RunnerRepairAccounting) Revision {
        return storage(self).revision;
    }

    pub fn attemptsReserved(
        self: *const RunnerRepairAccounting,
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
    InvalidStageRunEpochId,
    InvalidMaximumAttempts,
    RepairAccountingRevisionConflict,
    ModelAttemptValueConflict,
    ModelAttemptCeilingExhausted,
    ModelAttemptOrdinalExhausted,
    RepairAccountingRevisionExhausted,
    RepairAccountingOwnerReferenceExhausted,
    RepairAccountingEpochConflict,
};

pub const ProposalError = error{
    InvalidMaximumAttempts,
    RepairAccountingRevisionConflict,
    ModelAttemptCeilingExhausted,
    ModelAttemptOrdinalExhausted,
};

pub const Error = std.mem.Allocator.Error || ValidationError;

pub fn createInitial(
    allocator: std.mem.Allocator,
    stage_run_epoch_id: request_identity.StageRunEpochId,
) Error!*Owner {
    if (!stage_run_epoch_id.isValid()) return error.InvalidStageRunEpochId;
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
    const epoch_bytes = try value.arena.allocator().dupe(u8, stage_run_epoch_id.bytes);
    const owner: *Owner = @ptrCast(value);
    value.accounting = .{
        .owner = owner,
        .stage_run_epoch_id = .{ .bytes = epoch_bytes },
        .revision = .initial,
        .latest_record = null,
    };
    return owner;
}

pub fn proposeModelAttempt(
    current: *const RunnerRepairAccounting,
    expected_revision: Revision,
    model_request_id: *const request_identity.ModelRequestId,
    maximum: MaximumAttempts,
) ProposalError!ModelAttemptTransition {
    const current_storage = storage(current);
    if (!current_storage.revision.eql(expected_revision)) {
        return error.RepairAccountingRevisionConflict;
    }
    if (MaximumAttempts.init(maximum.configured, maximum.hard) == null) {
        return error.InvalidMaximumAttempts;
    }
    const reserved = if (resolveRecord(current_storage, model_request_id)) |record|
        record.attempts_reserved
    else
        0;
    if (reserved >= maximum.effective()) return error.ModelAttemptCeilingExhausted;
    const next = std.math.add(u32, reserved, 1) catch {
        return error.ModelAttemptOrdinalExhausted;
    };
    return .{
        .stage_run_epoch_id = current_storage.stage_run_epoch_id,
        .model_request_id = model_request_id,
        .expected_revision = expected_revision,
        .expected_request_value = reserved,
        .next_request_value = next,
        .maximum = maximum,
    };
}

pub fn apply(
    current: *const RunnerRepairAccounting,
    transition: ModelAttemptTransition,
) Error!*Owner {
    const current_storage = storage(current);
    if (!current_storage.revision.eql(transition.expected_revision)) {
        return error.RepairAccountingRevisionConflict;
    }
    if (!current_storage.stage_run_epoch_id.eql(transition.stage_run_epoch_id)) {
        return error.RepairAccountingEpochConflict;
    }
    if (MaximumAttempts.init(transition.maximum.configured, transition.maximum.hard) == null) {
        return error.InvalidMaximumAttempts;
    }
    const reserved = if (resolveRecord(current_storage, transition.model_request_id)) |record|
        record.attempts_reserved
    else
        0;
    if (reserved != transition.expected_request_value) return error.ModelAttemptValueConflict;
    if (reserved >= transition.maximum.effective()) return error.ModelAttemptCeilingExhausted;
    const expected_next = std.math.add(u32, reserved, 1) catch {
        return error.ModelAttemptOrdinalExhausted;
    };
    if (transition.next_request_value != expected_next) return error.ModelAttemptValueConflict;
    const next_revision = std.math.add(u64, current_storage.revision.value, 1) catch {
        return error.RepairAccountingRevisionExhausted;
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

pub fn accounting(owner: *const Owner) *const RunnerRepairAccounting {
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
        const allocator = value.backing_allocator;
        value.arena.deinit();
        allocator.destroy(value);
        next = previous;
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

fn retainOwner(owner: *Owner) ValidationError!void {
    const value = ownerStorage(owner);
    std.debug.assert(value.reference_count > 0);
    value.reference_count = std.math.add(usize, value.reference_count, 1) catch {
        return error.RepairAccountingOwnerReferenceExhausted;
    };
}

fn storage(value: *const RunnerRepairAccounting) *const Storage {
    return @ptrCast(@alignCast(value));
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}
