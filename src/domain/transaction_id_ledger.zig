const std = @import("std");
const identity = @import("transaction_identity.zig");

pub const Revision = struct {
    value: u64,
    pub const initial: Revision = .{ .value = 0 };
};
pub const Status = enum { reserved, committed, retired };
pub const Record = struct {
    transaction_id: identity.TransactionId,
    transaction_kind: identity.Kind,
    status: Status,
};

/// Closed in-memory input, not a persisted-file schema. All slices are borrowed.
pub const Candidate = struct {
    storage_owner: identity.StorageOwner,
    revision: Revision,
    next_transaction_ordinal: identity.Ordinal,
    reservations: []const Record,
    // Checked projection of retired records, never an independent status owner.
    retired_transaction_ids: []const identity.TransactionId,
};

/// Supplied by the owning boundary; this library invents no runtime defaults.
pub const Limits = struct {
    maximum_records: u32,
    maximum_owner_bytes: u32,

    pub fn validateCounts(self: Limits, records: usize, retired_ids: usize) ValidationError!void {
        if (self.maximum_records == 0 or self.maximum_owner_bytes == 0) return error.InvalidTransactionLedgerLimits;
        if (records > self.maximum_records or retired_ids > self.maximum_records) return error.TransactionLedgerLimitExceeded;
    }
};

pub const ValidationError = error{
    InvalidTransactionLedgerLimits,
    TransactionLedgerLimitExceeded,
    InvalidTransactionStorageOwner,
    TransactionStorageOwnerMismatch,
    InvalidTransactionKind,
    InvalidTransactionOrdinal,
    InvalidTransactionLedgerRevision,
    InvalidTransactionRetirementProjection,
    TransactionLedgerRevisionConflict,
    TransactionLedgerRevisionExhausted,
    TransactionOrdinalExhausted,
    TransactionNotFound,
    InvalidTransactionTransition,
};
pub const Error = ValidationError || std.mem.Allocator.Error;

/// Structural validation only: no journal, lock, allocation, or durability proof.
pub const Ledger = opaque {
    pub fn candidate(self: *const Ledger) Candidate {
        return storage(self).candidate;
    }

    pub fn record(self: *const Ledger, id: identity.TransactionId) ?Record {
        const value = self.candidate();
        if (!id.storage_owner.eql(value.storage_owner) or id.ordinal.value == 0 or
            id.ordinal.value > value.reservations.len) return null;
        return value.reservations[@intCast(id.ordinal.value - 1)];
    }
};

// The owner retains exactly one immutable, independently owned snapshot.
pub const Owner = opaque {};
const Storage = struct { candidate: Candidate, limits: Limits };
const OwnerStorage = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    ledger: Storage,
};

pub const Command = union(enum) {
    reserve: identity.Kind,
    commit: identity.TransactionId,
    retire: identity.TransactionId,
};
pub const Transition = struct {
    expected_ledger: *const Ledger,
    expected_revision: Revision,
    command: Command,
};

/// Does not assert that a collection or its ledger file is absent.
pub fn initialCandidate(owner: identity.StorageOwner) Candidate {
    return .{
        .storage_owner = owner,
        .revision = .initial,
        .next_transaction_ordinal = .{ .value = 1 },
        .reservations = &.{},
        .retired_transaction_ids = &.{},
    };
}

pub fn createValidated(
    allocator: std.mem.Allocator,
    candidate: Candidate,
    expected_owner: identity.StorageOwner,
    prior: ?*const Ledger,
    limits: Limits,
) Error!*Owner {
    try validate(candidate, expected_owner, prior, limits);
    const owned = try allocateOwner(allocator);
    errdefer destroyOwner(owned);
    const arena = owned.arena.allocator();
    const owner = try cloneStorageOwner(arena, candidate.storage_owner);
    const records = try arena.dupe(Record, candidate.reservations);
    for (records) |*record| record.transaction_id.storage_owner = owner;
    owned.ledger = .{ .candidate = .{
        .storage_owner = owner,
        .revision = candidate.revision,
        .next_transaction_ordinal = candidate.next_transaction_ordinal,
        .reservations = records,
        .retired_transaction_ids = try projectRetiredIds(arena, records),
    }, .limits = limits };
    return @ptrCast(owned);
}

pub fn ledger(owner: *const Owner) *const Ledger {
    const owned: *const OwnerStorage = @ptrCast(@alignCast(owner));
    return @ptrCast(&owned.ledger);
}

pub fn deinitOwner(owner: *Owner) void {
    destroyOwner(@ptrCast(@alignCast(owner)));
}

/// Builds a successor candidate only. The caller retains the current ledger;
/// only a future locked durable CAS may make the successor canonical.
pub fn buildCandidate(
    allocator: std.mem.Allocator,
    current: *const Ledger,
    transition: Transition,
) Error!*Owner {
    const input = current.candidate();
    if (transition.expected_ledger != current or transition.expected_revision.value != input.revision.value)
        return error.TransactionLedgerRevisionConflict;
    const next_revision = std.math.add(u64, input.revision.value, 1) catch return error.TransactionLedgerRevisionExhausted;
    const limits = storage(current).limits;
    var count = input.reservations.len;
    var next_ordinal = input.next_transaction_ordinal;
    const target: usize = switch (transition.command) {
        .reserve => |kind| blk: {
            if (!input.storage_owner.allows(kind)) return error.InvalidTransactionKind;
            if (count >= limits.maximum_records) return error.TransactionLedgerLimitExceeded;
            next_ordinal.value = std.math.add(u64, next_ordinal.value, 1) catch return error.TransactionOrdinalExhausted;
            count += 1;
            break :blk count - 1;
        },
        .commit, .retire => |id| blk: {
            if (!id.storage_owner.eql(input.storage_owner)) return error.TransactionStorageOwnerMismatch;
            const record = current.record(id) orelse return error.TransactionNotFound;
            try validateStatusTransition(record.status, switch (transition.command) {
                .commit => .committed,
                .retire => .retired,
                .reserve => unreachable,
            });
            break :blk @intCast(id.ordinal.value - 1);
        },
    };
    const owned = try allocateOwner(allocator);
    errdefer destroyOwner(owned);
    const arena = owned.arena.allocator();
    const owner = try cloneStorageOwner(arena, input.storage_owner);
    const records = try arena.alloc(Record, count);
    @memcpy(records[0..input.reservations.len], input.reservations);
    switch (transition.command) {
        .reserve => |kind| records[target] = .{
            .transaction_id = .{ .storage_owner = owner, .ordinal = input.next_transaction_ordinal },
            .transaction_kind = kind,
            .status = .reserved,
        },
        .commit => records[target].status = .committed,
        .retire => records[target].status = .retired,
    }
    for (records) |*record| record.transaction_id.storage_owner = owner;
    const candidate: Candidate = .{
        .storage_owner = owner,
        .revision = .{ .value = next_revision },
        .next_transaction_ordinal = next_ordinal,
        .reservations = records,
        .retired_transaction_ids = try projectRetiredIds(arena, records),
    };
    try validate(candidate, input.storage_owner, current, limits);
    owned.ledger = .{ .candidate = candidate, .limits = limits };
    return @ptrCast(owned);
}

fn validate(candidate: Candidate, expected: identity.StorageOwner, prior: ?*const Ledger, limits: Limits) ValidationError!void {
    try limits.validateCounts(candidate.reservations.len, candidate.retired_transaction_ids.len);
    try validateStorageOwner(expected, limits);
    try validateStorageOwner(candidate.storage_owner, limits);
    if (!candidate.storage_owner.eql(expected)) return error.TransactionStorageOwnerMismatch;
    // Every allocation remains present, including terminal history. No gaps,
    // compaction, reordering, or ID reuse can hide in an otherwise valid snapshot.
    if (candidate.next_transaction_ordinal.value != @as(u64, @intCast(candidate.reservations.len)) + 1)
        return error.InvalidTransactionOrdinal;
    var retired: usize = 0;
    var terminal: u64 = 0;
    for (candidate.reservations, 0..) |record, index| {
        try validateStorageOwner(record.transaction_id.storage_owner, limits);
        if (!record.transaction_id.storage_owner.eql(expected)) return error.TransactionStorageOwnerMismatch;
        if (record.transaction_id.ordinal.value != @as(u64, @intCast(index)) + 1) return error.InvalidTransactionOrdinal;
        if (!expected.allows(record.transaction_kind)) return error.InvalidTransactionKind;
        switch (record.status) {
            .reserved => {},
            .committed => terminal += 1,
            .retired => {
                terminal += 1;
                if (retired >= candidate.retired_transaction_ids.len) return error.InvalidTransactionRetirementProjection;
                const tombstone = candidate.retired_transaction_ids[retired];
                try validateStorageOwner(tombstone.storage_owner, limits);
                if (!tombstone.eql(record.transaction_id)) return error.InvalidTransactionRetirementProjection;
                retired += 1;
            },
        }
    }
    if (retired != candidate.retired_transaction_ids.len) return error.InvalidTransactionRetirementProjection;
    // Each record has one reservation and at most one terminal transition.
    if (candidate.revision.value != @as(u64, @intCast(candidate.reservations.len)) + terminal)
        return error.InvalidTransactionLedgerRevision;
    if (prior) |current| try validateSuccessor(current, candidate);
}

fn validateSuccessor(current: *const Ledger, candidate: Candidate) ValidationError!void {
    const previous = current.candidate();
    if (!candidate.storage_owner.eql(previous.storage_owner)) return error.TransactionStorageOwnerMismatch;
    const next = std.math.add(u64, previous.revision.value, 1) catch return error.TransactionLedgerRevisionExhausted;
    if (candidate.revision.value != next) return error.TransactionLedgerRevisionConflict;
    const added = candidate.reservations.len > previous.reservations.len and
        candidate.reservations.len - previous.reservations.len == 1;
    if (!added and candidate.reservations.len != previous.reservations.len) return error.InvalidTransactionTransition;
    var changes: usize = 0;
    for (previous.reservations, candidate.reservations[0..previous.reservations.len]) |old, new| {
        if (!old.transaction_id.eql(new.transaction_id) or old.transaction_kind != new.transaction_kind)
            return error.InvalidTransactionTransition;
        if (old.status == new.status) continue;
        if (added) return error.InvalidTransactionTransition;
        try validateStatusTransition(old.status, new.status);
        changes += 1;
    }
    if (added) {
        if (candidate.reservations[previous.reservations.len].status != .reserved) return error.InvalidTransactionTransition;
    } else if (changes != 1) return error.InvalidTransactionTransition;
}

fn validateStatusTransition(previous: Status, next: Status) ValidationError!void {
    if (previous != .reserved or next == .reserved) return error.InvalidTransactionTransition;
}

fn validateStorageOwner(owner: identity.StorageOwner, limits: Limits) ValidationError!void {
    const bounded = switch (owner) {
        .project => |id| id.canonical_project_root.len <= limits.maximum_owner_bytes,
        .feature => |value| value.feature_id.bytes.len <= limits.maximum_owner_bytes and
            value.workflow_artifact_registry_state_id.feature_id.bytes.len <= limits.maximum_owner_bytes,
    };
    if (!bounded) return error.TransactionLedgerLimitExceeded;
    if (!owner.isValid()) return error.InvalidTransactionStorageOwner;
}

fn cloneStorageOwner(allocator: std.mem.Allocator, source: identity.StorageOwner) std.mem.Allocator.Error!identity.StorageOwner {
    return switch (source) {
        .project => |id| .{ .project = .{
            .canonical_project_root = try allocator.dupe(u8, id.canonical_project_root),
            .contract_version = @import("bootstrap_roots.zig").bootstrap_root_contract_version,
        } },
        .feature => |owner| blk: {
            const feature_id: @import("feature_identity.zig").FeatureId = .{ .bytes = try allocator.dupe(u8, owner.feature_id.bytes) };
            break :blk .{ .feature = .{
                .feature_id = feature_id,
                .workflow_artifact_registry_state_id = .{
                    .feature_id = feature_id,
                    .ordinal = owner.workflow_artifact_registry_state_id.ordinal,
                },
            } };
        },
    };
}

fn projectRetiredIds(allocator: std.mem.Allocator, records: []const Record) std.mem.Allocator.Error![]const identity.TransactionId {
    var count: usize = 0;
    for (records) |record| if (record.status == .retired) {
        count += 1;
    };
    const result = try allocator.alloc(identity.TransactionId, count);
    var index: usize = 0;
    for (records) |record| if (record.status == .retired) {
        result[index] = record.transaction_id;
        index += 1;
    };
    return result;
}

fn allocateOwner(allocator: std.mem.Allocator) std.mem.Allocator.Error!*OwnerStorage {
    const owned = try allocator.create(OwnerStorage);
    owned.* = .{ .allocator = allocator, .arena = .init(allocator), .ledger = undefined };
    return owned;
}

fn destroyOwner(owned: *OwnerStorage) void {
    const allocator = owned.allocator;
    owned.arena.deinit();
    allocator.destroy(owned);
}

fn storage(value: *const Ledger) *const Storage {
    return @ptrCast(@alignCast(value));
}
