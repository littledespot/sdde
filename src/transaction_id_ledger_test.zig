const std = @import("std");
const identity = @import("domain/transaction_identity.zig");
const ledger = @import("domain/transaction_id_ledger.zig");
const artifacts = @import("domain/workflow_artifact_registry.zig");
const allocator = std.testing.allocator;
const limits: ledger.Limits = .{ .maximum_records = 128, .maximum_owner_bytes = 4096 };

fn feature(name: []const u8, ordinal: u64) identity.StorageOwner {
    return .{
        .feature_id = .{ .bytes = name },
        .workflow_artifact_registry_state_id = .{ .feature_id = .{ .bytes = name }, .ordinal = ordinal },
    };
}

const owners = [_]identity.StorageOwner{ feature("catalogue", 3), feature("hello-world", 1), feature("stock-control", 7) };

fn transactionId(owner: identity.StorageOwner, ordinal: u64) identity.TransactionId {
    return .{ .storage_owner = owner, .ordinal = .{ .value = ordinal } };
}

fn reservation(owner: identity.StorageOwner, ordinal: u64, kind: identity.Kind, status: ledger.Status) ledger.Record {
    return .{ .transaction_id = transactionId(owner, ordinal), .transaction_kind = kind, .status = status };
}

fn transition(current: *const ledger.Ledger, command: ledger.Command) ledger.Transition {
    return .{ .expected_ledger = current, .expected_revision = current.candidate().revision, .command = command };
}

fn initial(test_allocator: std.mem.Allocator, owner: identity.StorageOwner) !*ledger.Owner {
    return ledger.createValidated(test_allocator, ledger.initialCandidate(owner), owner, null, limits);
}

test "transaction owners use feature and artifact registry identities only" {
    try std.testing.expect(@FieldType(identity.StorageOwner, "workflow_artifact_registry_state_id") == artifacts.StateId);
    try std.testing.expect(!@hasField(identity.StorageOwner, "project"));
    try std.testing.expect(std.meta.stringToEnum(identity.Kind, "feature_activation") == null);
    try std.testing.expect(identity.Ordinal.init(0) == null);
    try std.testing.expectEqual(@as(u64, 1), identity.Ordinal.init(1).?.value);
    for (owners) |owner| {
        try std.testing.expect(owner.isValid());
        try std.testing.expect(owner.eql(owner));
        try std.testing.expect(transactionId(owner, 1).eql(transactionId(owner, 1)));
        try std.testing.expect(!transactionId(owner, 1).eql(transactionId(owner, 2)));
    }
    try std.testing.expect(!owners[0].eql(owners[1]));
    try std.testing.expect(!feature("hello-world", 1).eql(feature("hello-world", 2)));
    try std.testing.expect(!feature("hello-world", 1).eql(feature("other-feature", 1)));
    try std.testing.expect(!transactionId(owners[0], 1).eql(transactionId(owners[1], 1)));
}

test "empty ledgers begin at revision zero and ordinal one for each feature owner" {
    for (owners) |owner| {
        const owned = try initial(allocator, owner);
        defer ledger.deinitOwner(owned);
        const current = ledger.ledger(owned).candidate();
        try std.testing.expectEqual(@as(u64, 0), current.revision.value);
        try std.testing.expectEqual(@as(u64, 1), current.next_transaction_ordinal.value);
        try std.testing.expect(current.storage_owner.eql(owner));
        try std.testing.expectEqual(@as(usize, 0), current.reservations.len);
        try std.testing.expectEqual(@as(usize, 0), current.retired_transaction_ids.len);
    }
}

test "every closed transaction kind is available to feature owners" {
    inline for (std.meta.tags(identity.Kind)) |kind| {
        for (owners) |owner| {
            const owned = try initial(allocator, owner);
            defer ledger.deinitOwner(owned);
            const current = ledger.ledger(owned);
            const command: ledger.Command = .{ .reserve = kind };
            const next = try ledger.buildCandidate(allocator, current, transition(current, command));
            defer ledger.deinitOwner(next);
            const result = ledger.ledger(next).candidate();
            try std.testing.expectEqual(@as(u64, 1), result.revision.value);
            try std.testing.expectEqual(@as(u64, 2), result.next_transaction_ordinal.value);
            try std.testing.expectEqual(kind, result.reservations[0].transaction_kind);
            try std.testing.expectEqual(ledger.Status.reserved, result.reservations[0].status);
            try std.testing.expectEqual(@as(usize, 0), current.candidate().reservations.len);
        }
    }
}

test "reserve commit and retire retain history without reusing IDs or mutating predecessors" {
    for (owners) |owner| {
        const empty_owner = try initial(allocator, owner);
        defer ledger.deinitOwner(empty_owner);
        const empty = ledger.ledger(empty_owner);
        const kind: identity.Kind = .review_decision;
        const first_owner = try ledger.buildCandidate(allocator, empty, transition(empty, .{ .reserve = kind }));
        defer ledger.deinitOwner(first_owner);
        const first = ledger.ledger(first_owner);
        const committed_owner = try ledger.buildCandidate(allocator, first, transition(first, .{ .commit = transactionId(owner, 1) }));
        defer ledger.deinitOwner(committed_owner);
        const committed = ledger.ledger(committed_owner);
        const second_owner = try ledger.buildCandidate(allocator, committed, transition(committed, .{ .reserve = kind }));
        defer ledger.deinitOwner(second_owner);
        const second = ledger.ledger(second_owner);
        const retired_owner = try ledger.buildCandidate(allocator, second, transition(second, .{ .retire = transactionId(owner, 2) }));
        defer ledger.deinitOwner(retired_owner);
        const retired = ledger.ledger(retired_owner);
        const third_owner = try ledger.buildCandidate(allocator, retired, transition(retired, .{ .reserve = kind }));
        defer ledger.deinitOwner(third_owner);
        const third = ledger.ledger(third_owner).candidate();

        try std.testing.expectEqual(@as(u64, 5), third.revision.value);
        try std.testing.expectEqual(@as(u64, 4), third.next_transaction_ordinal.value);
        try std.testing.expectEqual(ledger.Status.committed, third.reservations[0].status);
        try std.testing.expectEqual(ledger.Status.retired, third.reservations[1].status);
        try std.testing.expectEqual(ledger.Status.reserved, third.reservations[2].status);
        try std.testing.expectEqual(@as(usize, 1), third.retired_transaction_ids.len);
        try std.testing.expect(third.retired_transaction_ids[0].eql(transactionId(owner, 2)));
        try std.testing.expectEqual(@as(usize, 0), empty.candidate().reservations.len);
        try std.testing.expectEqual(ledger.Status.reserved, first.record(transactionId(owner, 1)).?.status);
        try std.testing.expectEqual(@as(usize, 1), committed.candidate().reservations.len);
        try std.testing.expectEqual(ledger.Status.reserved, second.record(transactionId(owner, 2)).?.status);

        // Restoration of an in-memory snapshot is structural, not journal recovery.
        const restored = try ledger.createValidated(allocator, third, owner, retired, limits);
        defer ledger.deinitOwner(restored);
        try std.testing.expectEqualDeep(third, ledger.ledger(restored).candidate());
    }
}

test "closed structural validation rejects invalid owners and mismatched namespaces" {
    var mismatch = feature("first-feature", 1);
    mismatch.workflow_artifact_registry_state_id.feature_id.bytes = "second-feature";
    const invalid = [_]identity.StorageOwner{
        feature("", 1), feature("UPPER", 1), feature("../escape", 1), feature("/absolute", 1), feature("hello-world", 0), mismatch,
    };
    for (invalid) |owner| {
        try std.testing.expectError(error.InvalidTransactionStorageOwner, initial(allocator, owner));
    }
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, ledger.createValidated(
        allocator,
        ledger.initialCandidate(owners[0]),
        owners[1],
        null,
        limits,
    ));
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, ledger.createValidated(
        allocator,
        ledger.initialCandidate(owners[1]),
        feature("hello-world", 2),
        null,
        limits,
    ));
}

test "ledger validator rejects duplicate reordered missing zero and reused ordinals" {
    const owner = owners[1];
    const valid_records = [_]ledger.Record{
        reservation(owner, 1, .specify_completion, .committed),
        reservation(owner, 2, .clarification_response, .reserved),
        reservation(owner, 3, .task_outcome, .retired),
    };
    var records = valid_records;
    const tombstones = [_]identity.TransactionId{transactionId(owner, 3)};
    const valid: ledger.Candidate = .{
        .storage_owner = owner,
        .revision = .{ .value = 5 },
        .next_transaction_ordinal = .{ .value = 4 },
        .reservations = &records,
        .retired_transaction_ids = &tombstones,
    };
    const accepted = try ledger.createValidated(allocator, valid, owner, null, limits);
    defer ledger.deinitOwner(accepted);
    const bad_ordinals = [_]u64{ 0, 1, 3, std.math.maxInt(u64) };
    for (bad_ordinals) |ordinal| {
        records = valid_records;
        records[1].transaction_id.ordinal.value = ordinal;
        try std.testing.expectError(error.InvalidTransactionOrdinal, ledger.createValidated(allocator, valid, owner, null, limits));
    }
    records = valid_records;
    std.mem.swap(ledger.Record, &records[0], &records[1]);
    try std.testing.expectError(error.InvalidTransactionOrdinal, ledger.createValidated(allocator, valid, owner, null, limits));
    records = valid_records;
    for ([_]u64{ 0, 1, 3, 5, std.math.maxInt(u64) }) |next| {
        var invalid = valid;
        invalid.next_transaction_ordinal.value = next;
        try std.testing.expectError(error.InvalidTransactionOrdinal, ledger.createValidated(allocator, invalid, owner, null, limits));
    }
    var missing = valid;
    missing.reservations = records[1..];
    missing.next_transaction_ordinal.value = 3;
    try std.testing.expectError(error.InvalidTransactionOrdinal, ledger.createValidated(allocator, missing, owner, null, limits));
    records[1].transaction_id.storage_owner = owners[2];
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, ledger.createValidated(allocator, valid, owner, null, limits));
    records = valid_records;
    for ([_]u64{ 0, 4, 6, std.math.maxInt(u64) }) |revision| {
        var invalid = valid;
        invalid.revision.value = revision;
        try std.testing.expectError(error.InvalidTransactionLedgerRevision, ledger.createValidated(allocator, invalid, owner, null, limits));
    }
}

test "retirement IDs must be the exact projection of retired records" {
    const owner = owners[2];
    const records = [_]ledger.Record{
        reservation(owner, 1, .task_checkpoint, .retired),
        reservation(owner, 2, .task_success, .committed),
        reservation(owner, 3, .manual_verification, .retired),
    };
    const valid_ids = [_]identity.TransactionId{ transactionId(owner, 1), transactionId(owner, 3) };
    var ids = valid_ids;
    const candidate: ledger.Candidate = .{
        .storage_owner = owner,
        .revision = .{ .value = 6 },
        .next_transaction_ordinal = .{ .value = 4 },
        .reservations = &records,
        .retired_transaction_ids = &ids,
    };
    const accepted = try ledger.createValidated(allocator, candidate, owner, null, limits);
    defer ledger.deinitOwner(accepted);
    for ([_]u64{ 0, 1, 2, 4 }) |ordinal| {
        ids = valid_ids;
        ids[1].ordinal.value = ordinal;
        try std.testing.expectError(error.InvalidTransactionRetirementProjection, ledger.createValidated(allocator, candidate, owner, null, limits));
    }
    ids = valid_ids;
    ids[1].storage_owner = owners[1];
    try std.testing.expectError(error.InvalidTransactionRetirementProjection, ledger.createValidated(allocator, candidate, owner, null, limits));
    ids = valid_ids;
    std.mem.swap(identity.TransactionId, &ids[0], &ids[1]);
    try std.testing.expectError(error.InvalidTransactionRetirementProjection, ledger.createValidated(allocator, candidate, owner, null, limits));
    var missing = candidate;
    missing.retired_transaction_ids = &.{};
    try std.testing.expectError(error.InvalidTransactionRetirementProjection, ledger.createValidated(allocator, missing, owner, null, limits));
    var extra = ledger.initialCandidate(owner);
    extra.retired_transaction_ids = &valid_ids;
    try std.testing.expectError(error.InvalidTransactionRetirementProjection, ledger.createValidated(allocator, extra, owner, null, limits));
}

test "transition candidates reject stale revisions foreign snapshots and unknown or cross-owner IDs" {
    const owner = owners[1];
    const empty_owner = try initial(allocator, owner);
    defer ledger.deinitOwner(empty_owner);
    const empty = ledger.ledger(empty_owner);
    const first_owner = try ledger.buildCandidate(allocator, empty, transition(empty, .{ .reserve = .specify_completion }));
    defer ledger.deinitOwner(first_owner);
    const first = ledger.ledger(first_owner);
    var stale = transition(first, .{ .commit = transactionId(owner, 1) });
    stale.expected_revision = .initial;
    try std.testing.expectError(error.TransactionLedgerRevisionConflict, ledger.buildCandidate(allocator, first, stale));
    const other_owner = try ledger.createValidated(allocator, first.candidate(), owner, null, limits);
    defer ledger.deinitOwner(other_owner);
    try std.testing.expectError(error.TransactionLedgerRevisionConflict, ledger.buildCandidate(allocator, ledger.ledger(other_owner), transition(first, .{ .reserve = .plan_candidate })));
    for ([_]u64{ 0, 2, std.math.maxInt(u64) }) |ordinal| {
        try std.testing.expectError(error.TransactionNotFound, ledger.buildCandidate(allocator, first, transition(first, .{ .commit = transactionId(owner, ordinal) })));
    }
    const foreign_owners = [_]identity.StorageOwner{ owners[0], owners[2], feature("hello-world", 2) };
    for (foreign_owners) |foreign| {
        try std.testing.expectError(error.TransactionStorageOwnerMismatch, ledger.buildCandidate(allocator, first, transition(first, .{ .retire = transactionId(foreign, 1) })));
    }
}

test "committed and retired records cannot be terminalized twice or changed to the other terminal status" {
    for (owners) |owner| {
        const kind: identity.Kind = .reference_revision;
        const empty_owner = try initial(allocator, owner);
        defer ledger.deinitOwner(empty_owner);
        const empty = ledger.ledger(empty_owner);
        const reserved_owner = try ledger.buildCandidate(allocator, empty, transition(empty, .{ .reserve = kind }));
        defer ledger.deinitOwner(reserved_owner);
        const reserved = ledger.ledger(reserved_owner);
        const commands = [_]ledger.Command{ .{ .commit = transactionId(owner, 1) }, .{ .retire = transactionId(owner, 1) } };
        for (commands) |command| {
            const terminal_owner = try ledger.buildCandidate(allocator, reserved, transition(reserved, command));
            defer ledger.deinitOwner(terminal_owner);
            const terminal = ledger.ledger(terminal_owner);
            for (commands) |repeated| {
                try std.testing.expectError(error.InvalidTransactionTransition, ledger.buildCandidate(allocator, terminal, transition(terminal, repeated)));
            }
        }
    }
}

test "successor validation rejects history rewrites resurrection deletion and multi-record changes" {
    const owner = owners[1];
    const previous_records = [_]ledger.Record{
        reservation(owner, 1, .specify_completion, .committed),
        reservation(owner, 2, .plan_candidate, .reserved),
        reservation(owner, 3, .reference_revision, .reserved),
    };
    const previous: ledger.Candidate = .{
        .storage_owner = owner,
        .revision = .{ .value = 4 },
        .next_transaction_ordinal = .{ .value = 4 },
        .reservations = &previous_records,
        .retired_transaction_ids = &.{},
    };
    const prior_owner = try ledger.createValidated(allocator, previous, owner, null, limits);
    defer ledger.deinitOwner(prior_owner);
    const prior = ledger.ledger(prior_owner);
    var records = previous_records;
    records[1].status = .committed;
    var next = previous;
    next.reservations = &records;
    next.revision.value = 5;
    const accepted = try ledger.createValidated(allocator, next, owner, prior, limits);
    defer ledger.deinitOwner(accepted);
    records[0].transaction_kind = .task_success;
    try std.testing.expectError(error.InvalidTransactionTransition, ledger.createValidated(allocator, next, owner, prior, limits));
    // Still structurally valid at revision five, but resurrects one terminal
    // ID and terminalizes two others in the same proposed transition.
    records = previous_records;
    records[0].status = .reserved;
    records[1].status = .committed;
    records[2].status = .committed;
    try std.testing.expectError(error.InvalidTransactionTransition, ledger.createValidated(allocator, next, owner, prior, limits));
    try std.testing.expectError(error.TransactionLedgerRevisionConflict, ledger.createValidated(allocator, previous, owner, prior, limits));
    try std.testing.expectError(error.TransactionLedgerRevisionConflict, ledger.createValidated(allocator, ledger.initialCandidate(owner), owner, prior, limits));
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, ledger.createValidated(allocator, ledger.initialCandidate(owners[2]), owners[2], prior, limits));
}

test "record and owner limits are enforced before snapshot construction" {
    const owner = owners[0];
    for ([_]ledger.Limits{
        .{ .maximum_records = 0, .maximum_owner_bytes = 10 },
        .{ .maximum_records = 1, .maximum_owner_bytes = 0 },
    }) |invalid| {
        try std.testing.expectError(error.InvalidTransactionLedgerLimits, ledger.createValidated(allocator, ledger.initialCandidate(owner), owner, null, invalid));
    }
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, ledger.createValidated(
        allocator,
        ledger.initialCandidate(owner),
        owner,
        null,
        .{ .maximum_records = 1, .maximum_owner_bytes = 2 },
    ));
    const oversized_records = [_]ledger.Record{
        reservation(owner, 1, .specify_completion, .reserved),
        reservation(owner, 2, .plan_candidate, .reserved),
    };
    var oversized = ledger.initialCandidate(owner);
    oversized.reservations = &oversized_records;
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, ledger.createValidated(
        allocator,
        oversized,
        owner,
        null,
        .{ .maximum_records = 1, .maximum_owner_bytes = 4096 },
    ));
    oversized = ledger.initialCandidate(owner);
    oversized.retired_transaction_ids = &.{ transactionId(owner, 1), transactionId(owner, 2) };
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, ledger.createValidated(
        allocator,
        oversized,
        owner,
        null,
        .{ .maximum_records = 1, .maximum_owner_bytes = 4096 },
    ));
    const empty_owner = try ledger.createValidated(allocator, ledger.initialCandidate(owner), owner, null, .{ .maximum_records = 1, .maximum_owner_bytes = 4096 });
    defer ledger.deinitOwner(empty_owner);
    const empty = ledger.ledger(empty_owner);
    const first_owner = try ledger.buildCandidate(allocator, empty, transition(empty, .{ .reserve = .specify_completion }));
    defer ledger.deinitOwner(first_owner);
    const first = ledger.ledger(first_owner);
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, ledger.buildCandidate(allocator, first, transition(first, .{ .reserve = .specify_completion })));
    const committed_owner = try ledger.buildCandidate(allocator, first, transition(first, .{ .commit = transactionId(owner, 1) }));
    defer ledger.deinitOwner(committed_owner);
    const committed = ledger.ledger(committed_owner);
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, ledger.buildCandidate(allocator, committed, transition(committed, .{ .reserve = .specify_completion })));
}

test "snapshots own all input bytes and successors outlive their predecessors" {
    var bytes = "hello-world".*;
    const owner = feature(&bytes, 1);
    var records = [_]ledger.Record{reservation(owner, 1, .specify_completion, .retired)};
    var retired = [_]identity.TransactionId{transactionId(owner, 1)};
    const next_owner = blk: {
        const current_owner = try ledger.createValidated(allocator, .{
            .storage_owner = owner,
            .revision = .{ .value = 2 },
            .next_transaction_ordinal = .{ .value = 2 },
            .reservations = &records,
            .retired_transaction_ids = &retired,
        }, owner, null, limits);
        defer ledger.deinitOwner(current_owner);
        const current = ledger.ledger(current_owner);
        const result = try ledger.buildCandidate(allocator, current, transition(current, .{ .reserve = .plan_candidate }));
        errdefer ledger.deinitOwner(result);
        @memset(&bytes, 'z');
        records[0].status = .reserved;
        retired[0].ordinal.value = 999;
        const copied = current.candidate();
        try std.testing.expect(copied.storage_owner.eql(feature("hello-world", 1)));
        try std.testing.expectEqual(ledger.Status.retired, copied.reservations[0].status);
        try std.testing.expectEqual(@as(u64, 1), copied.retired_transaction_ids[0].ordinal.value);
        break :blk result;
    };
    defer ledger.deinitOwner(next_owner);
    const next = ledger.ledger(next_owner).candidate();
    try std.testing.expect(next.storage_owner.eql(feature("hello-world", 1)));
    try std.testing.expect(next.reservations[0].transaction_id.storage_owner.eql(next.storage_owner));
    try std.testing.expect(next.retired_transaction_ids[0].storage_owner.eql(next.storage_owner));
    try std.testing.expectEqual(@as(u64, 2), next.reservations[1].transaction_id.ordinal.value);
}

test "snapshots own feature identity bytes from independently borrowed fields" {
    var feature_bytes = "catalogue".*;
    var artifact_feature_bytes = "catalogue".*;
    var owner = feature(&feature_bytes, 3);
    owner.workflow_artifact_registry_state_id.feature_id.bytes = &artifact_feature_bytes;
    const owned = try initial(allocator, owner);
    defer ledger.deinitOwner(owned);
    @memset(&feature_bytes, 'z');
    @memset(&artifact_feature_bytes, 'y');
    try std.testing.expect(ledger.ledger(owned).candidate().storage_owner.eql(feature("catalogue", 3)));
}

fn allocationScenario(test_allocator: std.mem.Allocator, owner: identity.StorageOwner) !void {
    const first_owner = try initial(test_allocator, owner);
    defer ledger.deinitOwner(first_owner);
    const first = ledger.ledger(first_owner);
    const kind: identity.Kind = .task_outcome;
    const second_owner = try ledger.buildCandidate(test_allocator, first, transition(first, .{ .reserve = kind }));
    defer ledger.deinitOwner(second_owner);
    const second = ledger.ledger(second_owner);
    const third_owner = try ledger.buildCandidate(test_allocator, second, transition(second, .{ .retire = transactionId(owner, 1) }));
    defer ledger.deinitOwner(third_owner);
    const restored_owner = try ledger.createValidated(test_allocator, ledger.ledger(third_owner).candidate(), owner, second, limits);
    defer ledger.deinitOwner(restored_owner);
}

test "every allocation failure cleans up each feature owner" {
    for (owners) |owner| try std.testing.checkAllAllocationFailures(allocator, allocationScenario, .{owner});
}

test "monotonic sequences retain all terminal IDs across repeated snapshot replacement" {
    for (owners) |owner| {
        var current_owner = try initial(allocator, owner);
        defer ledger.deinitOwner(current_owner);
        const kind: identity.Kind = .manual_verification;
        for (1..65) |ordinal| {
            const current = ledger.ledger(current_owner);
            const reserved_owner = try ledger.buildCandidate(allocator, current, transition(current, .{ .reserve = kind }));
            ledger.deinitOwner(current_owner);
            current_owner = reserved_owner;
            const reserved = ledger.ledger(current_owner);
            const command: ledger.Command = if (ordinal % 2 == 0)
                .{ .commit = transactionId(owner, ordinal) }
            else
                .{ .retire = transactionId(owner, ordinal) };
            const terminal_owner = try ledger.buildCandidate(allocator, reserved, transition(reserved, command));
            ledger.deinitOwner(current_owner);
            current_owner = terminal_owner;
            const result = ledger.ledger(current_owner).candidate();
            try std.testing.expectEqual(@as(u64, @intCast(ordinal * 2)), result.revision.value);
            try std.testing.expectEqual(@as(u64, @intCast(ordinal + 1)), result.next_transaction_ordinal.value);
            try std.testing.expectEqual(ordinal, result.reservations.len);
            try std.testing.expectEqual((ordinal + 1) / 2, result.retired_transaction_ids.len);
            for (result.reservations, 1..) |record, expected| {
                try std.testing.expectEqual(@as(u64, @intCast(expected)), record.transaction_id.ordinal.value);
                try std.testing.expectEqual(if (expected % 2 == 0) ledger.Status.committed else ledger.Status.retired, record.status);
            }
        }
    }
}
