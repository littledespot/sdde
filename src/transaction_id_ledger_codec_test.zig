const std = @import("std");
const codec = @import("adapters/parsers/transaction_id_ledger.zig");
const ledger = @import("domain/transaction_id_ledger.zig");
const identity = @import("domain/transaction_identity.zig");
const roots = @import("domain/bootstrap_roots.zig");
const allocator = std.testing.allocator;
const limits: codec.Limits = .{ .maximum_bytes = 32768, .ledger = .{ .maximum_records = 128, .maximum_owner_bytes = 4096 } };

fn project(path: []const u8) identity.StorageOwner {
    return .{ .project = .{ .canonical_project_root = path, .contract_version = roots.bootstrap_root_contract_version } };
}
fn feature(name: []const u8, ordinal: u64) identity.StorageOwner {
    return .{ .feature = .{
        .feature_id = .{ .bytes = name },
        .workflow_artifact_registry_state_id = .{ .feature_id = .{ .bytes = name }, .ordinal = ordinal },
    } };
}
const project_owner = project("/private/engine-project");
const feature_owner = feature("hello-world", 7);
const project_golden = "{\"schema\":\"transaction-id-ledger/v1\",\"storageOwner\":{\"project\":{\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\"}},\"revision\":1,\"nextTransactionOrdinal\":2,\"reservations\":[{\"transactionOrdinal\":1,\"transactionKind\":\"feature_activation\",\"status\":\"reserved\"}],\"retiredTransactionOrdinals\":[]}\n";
const feature_golden = "{\"schema\":\"transaction-id-ledger/v1\",\"storageOwner\":{\"feature\":{\"featureId\":\"hello-world\",\"workflowArtifactRegistryStateOrdinal\":7}},\"revision\":5,\"nextTransactionOrdinal\":4,\"reservations\":[{\"transactionOrdinal\":1,\"transactionKind\":\"specify_completion\",\"status\":\"committed\"},{\"transactionOrdinal\":2,\"transactionKind\":\"clarification_response\",\"status\":\"retired\"},{\"transactionOrdinal\":3,\"transactionKind\":\"task_checkpoint\",\"status\":\"reserved\"}],\"retiredTransactionOrdinals\":[2]}\n";

fn record(owner: identity.StorageOwner, ordinal: u64, kind: identity.Kind, status: ledger.Status) ledger.Record {
    return .{ .transaction_id = .{ .storage_owner = owner, .ordinal = .{ .value = ordinal } }, .transaction_kind = kind, .status = status };
}

fn expectChangedError(expected_error: anyerror, base: []const u8, owner: identity.StorageOwner, old: []const u8, new: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, base, old) != null);
    const bytes = try std.mem.replaceOwned(u8, allocator, base, old, new);
    defer allocator.free(bytes);
    try std.testing.expectError(expected_error, codec.decode(allocator, bytes, owner, null, limits));
}

test "stored project and feature ledgers round trip to exact golden bytes" {
    const cases = [_]struct { bytes: []const u8, owner: identity.StorageOwner }{
        .{ .bytes = project_golden, .owner = project_owner },
        .{ .bytes = feature_golden, .owner = feature_owner },
    };
    for (cases) |case| {
        const decoded_owner = try codec.decode(allocator, case.bytes, case.owner, null, limits);
        defer ledger.deinitOwner(decoded_owner);
        const decoded = ledger.ledger(decoded_owner);
        const bytes = try codec.encode(allocator, decoded, case.owner, limits.maximum_bytes);
        defer allocator.free(bytes);
        try std.testing.expectEqualStrings(case.bytes, bytes);
        const again = try codec.decode(allocator, bytes, case.owner, null, limits);
        defer ledger.deinitOwner(again);
        try std.testing.expectEqualDeep(decoded.candidate(), ledger.ledger(again).candidate());
    }
}

test "all admitted kinds and statuses preserve the validated in-memory ledger" {
    const owners = [_]identity.StorageOwner{ project_owner, feature_owner, feature("stock-control", std.math.maxInt(u64)) };
    inline for (std.meta.tags(identity.Kind)) |kind| {
        for (owners) |owner| {
            if (!owner.allows(kind)) continue;
            inline for (std.meta.tags(ledger.Status)) |status| {
                const records = [_]ledger.Record{record(owner, 1, kind, status)};
                const retired = [_]identity.TransactionId{records[0].transaction_id};
                const value = try ledger.createValidated(allocator, .{
                    .storage_owner = owner,
                    .revision = .{ .value = if (status == .reserved) 1 else 2 },
                    .next_transaction_ordinal = .{ .value = 2 },
                    .reservations = &records,
                    .retired_transaction_ids = if (status == .retired) &retired else &.{},
                }, owner, null, limits.ledger);
                defer ledger.deinitOwner(value);
                const bytes = try codec.encode(allocator, ledger.ledger(value), owner, limits.maximum_bytes);
                defer allocator.free(bytes);
                const decoded = try codec.decode(allocator, bytes, owner, null, limits);
                defer ledger.deinitOwner(decoded);
                try std.testing.expectEqualDeep(ledger.ledger(value).candidate(), ledger.ledger(decoded).candidate());
            }
        }
    }
}

test "empty ledgers retain initial revision and ordinal for both collection kinds" {
    for ([_]identity.StorageOwner{ project_owner, feature_owner }) |owner| {
        const initial = try ledger.createValidated(allocator, ledger.initialCandidate(owner), owner, null, limits.ledger);
        defer ledger.deinitOwner(initial);
        const bytes = try codec.encode(allocator, ledger.ledger(initial), owner, limits.maximum_bytes);
        defer allocator.free(bytes);
        const decoded = try codec.decode(allocator, bytes, owner, null, limits);
        defer ledger.deinitOwner(decoded);
        try std.testing.expectEqualDeep(ledger.initialCandidate(owner), ledger.ledger(decoded).candidate());
    }
}

test "whitespace field ordering and escaped names normalize without changing the ledger" {
    const input =
        \\{ "retiredTransactionOrdinals":[], "reservations":[{"status":"reserved","transactionKind":"feature_activation","transactionOrdinal":1}],
        \\  "nextTransactionOrdinal":2, "revision":1, "storageOwner":{"project":{"bootstrapRootContractVersion":"bootstrap-roots/v2"}},
        \\  "\u0073chema":"transaction-id-ledger/v1" }
    ;
    const owned = try codec.decode(allocator, input, project_owner, null, limits);
    defer ledger.deinitOwner(owned);
    const bytes = try codec.encode(allocator, ledger.ledger(owned), project_owner, limits.maximum_bytes);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings(project_golden, bytes);
}

test "missing unknown duplicate escaped-duplicate and wrong-type fields are rejected at every nesting level" {
    const invalid_changes = [_]struct { old: []const u8, new: []const u8 }{
        .{ .old = "\"revision\":1,", .new = "" },
        .{ .old = "\"revision\":1", .new = "\"revision\":1,\"unknown\":0" },
        .{ .old = "\"revision\":1", .new = "\"revision\":1,\"revision\":1" },
        .{ .old = "\"revision\":1", .new = "\"revision\":1,\"\\u0072evision\":1" },
        .{ .old = "\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\"", .new = "" },
        .{ .old = "\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\"", .new = "\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\",\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\"" },
        .{ .old = "\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\"", .new = "\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\",\"canonicalProjectRoot\":\"/foreign\"" },
        .{ .old = "\"transactionOrdinal\":1", .new = "\"transactionOrdinal\":1,\"transactionOrdinal\":1" },
        .{ .old = "\"transactionOrdinal\":1", .new = "\"transactionOrdinal\":1,\"owner\":\"other\"" },
        .{ .old = "\"transactionOrdinal\":1,", .new = "" },
        .{ .old = "\"status\":\"reserved\"", .new = "\"status\":\"reserved\",\"status\":\"committed\"" },
        .{ .old = "\"schema\":\"transaction-id-ledger/v1\"", .new = "\"schema\":[116,120]" },
        .{ .old = "\"transactionKind\":\"feature_activation\"", .new = "\"transactionKind\":0" },
        .{ .old = "\"transactionKind\":\"feature_activation\"", .new = "\"transactionKind\":\"0\"" },
        .{ .old = "\"status\":\"reserved\"", .new = "\"status\":[114,101,115,101,114,118,101,100]" },
        .{ .old = "\"status\":\"reserved\"", .new = "\"status\":0" },
        .{ .old = "\"retiredTransactionOrdinals\":[]", .new = "\"retiredTransactionOrdinals\":\"\"" },
        .{ .old = "\"project\":{", .new = "\"unknown\":{ " },
        .{ .old = "\"transactionKind\":\"feature_activation\"", .new = "\"transactionKind\":\"future_kind\"" },
        .{ .old = "\"status\":\"reserved\"", .new = "\"status\":\"future_status\"" },
    };
    for (invalid_changes) |change| try expectChangedError(error.InvalidTransactionLedgerDocument, project_golden, project_owner, change.old, change.new);
    try expectChangedError(error.UnsupportedTransactionLedgerSchema, project_golden, project_owner, "transaction-id-ledger/v1", "transaction-id-ledger/v2");
    try expectChangedError(error.InvalidTransactionLedgerDocument, feature_golden, feature_owner, "\"featureId\":\"hello-world\"", "\"featureId\":\"hello-world\",\"featureId\":\"hello-world\"");
    try expectChangedError(error.InvalidTransactionLedgerDocument, feature_golden, feature_owner, "\"workflowArtifactRegistryStateOrdinal\":7", "\"workflowArtifactRegistryStateOrdinal\":7,\"namespace\":\"plan\"");
    try expectChangedError(error.InvalidTransactionLedgerDocument, project_golden, project_owner, "\"project\":{\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\"}", "\"project\":{\"bootstrapRootContractVersion\":\"bootstrap-roots/v2\"},\"feature\":{\"featureId\":\"hello-world\",\"workflowArtifactRegistryStateOrdinal\":7}");
}

test "integer tokens never accept coercions fractional exponent or overflow values" {
    const invalid = [_][]const u8{ "\"1\"", "1.0", "1e0", "-0", "-1", "+1", "01", "true", "null", "18446744073709551616", "{}", "[]" };
    for (invalid) |value| {
        const replacement = try std.fmt.allocPrint(allocator, "\"revision\":{s}", .{value});
        defer allocator.free(replacement);
        try expectChangedError(error.InvalidTransactionLedgerDocument, project_golden, project_owner, "\"revision\":1", replacement);
    }
    try expectChangedError(error.InvalidTransactionLedgerDocument, feature_golden, feature_owner, "\"workflowArtifactRegistryStateOrdinal\":7", "\"workflowArtifactRegistryStateOrdinal\":\"7\"");
    try expectChangedError(error.InvalidTransactionLedgerDocument, feature_golden, feature_owner, "\"retiredTransactionOrdinals\":[2]", "\"retiredTransactionOrdinals\":[\"2\"]");
}

test "malformed transport trailing data BOM and excessive nesting are rejected" {
    const invalid = [_][]const u8{
        "",                               " ",                      "{",  project_golden[0 .. project_golden.len - 2], project_golden ++ "{}",
        "\xef\xbb\xbf" ++ project_golden, project_golden ++ "\xff", "[]", "null",                                      "{\"schema\":[[[[[[[[[[[[[[[[[[[[\"transaction-id-ledger/v1\"]]]]]]]]]]]]]]]]]]]]}",
    };
    for (invalid) |bytes| try std.testing.expectError(error.InvalidTransactionLedgerDocument, codec.decode(allocator, bytes, project_owner, null, limits));
}

test "codec delegates invalid identity status history and retirement to the shared validator" {
    try expectChangedError(error.InvalidTransactionOrdinal, project_golden, project_owner, "\"transactionOrdinal\":1", "\"transactionOrdinal\":0");
    try expectChangedError(error.InvalidTransactionOrdinal, project_golden, project_owner, "\"nextTransactionOrdinal\":2", "\"nextTransactionOrdinal\":1");
    try expectChangedError(error.InvalidTransactionLedgerRevision, project_golden, project_owner, "\"revision\":1", "\"revision\":2");
    try expectChangedError(error.InvalidTransactionRetirementProjection, feature_golden, feature_owner, "\"retiredTransactionOrdinals\":[2]", "\"retiredTransactionOrdinals\":[1]");
    try expectChangedError(error.InvalidTransactionOrdinal, feature_golden, feature_owner, "\"transactionOrdinal\":2", "\"transactionOrdinal\":1");
    try expectChangedError(error.InvalidTransactionKind, project_golden, project_owner, "feature_activation", "task_outcome");
    try expectChangedError(error.InvalidTransactionStorageOwner, project_golden, project_owner, "bootstrap-roots/v2", "bootstrap-roots/v1");
    try expectChangedError(error.InvalidTransactionStorageOwner, feature_golden, feature_owner, "\"workflowArtifactRegistryStateOrdinal\":7", "\"workflowArtifactRegistryStateOrdinal\":0");
}

test "collection binding rejects owner mismatches and no absolute root appears in stored bytes" {
    const owned = try codec.decode(allocator, project_golden, project_owner, null, limits);
    defer ledger.deinitOwner(owned);
    const current = ledger.ledger(owned);
    const bytes = try codec.encode(allocator, current, project_owner, limits.maximum_bytes);
    defer allocator.free(bytes);
    try std.testing.expect(std.mem.indexOf(u8, bytes, project_owner.project.canonical_project_root) == null);
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, codec.encode(allocator, current, project("/another-project"), limits.maximum_bytes));
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, codec.decode(allocator, project_golden, feature_owner, null, limits));
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, codec.decode(allocator, feature_golden, project_owner, null, limits));
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, codec.decode(allocator, feature_golden, feature("other-feature", 7), null, limits));
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, codec.decode(allocator, feature_golden, feature("hello-world", 8), null, limits));
    // Project references are relative to supplied context, not provenance proof.
    const other = try codec.decode(allocator, project_golden, project("/another-project"), null, limits);
    defer ledger.deinitOwner(other);
    try std.testing.expect(!current.candidate().storage_owner.eql(ledger.ledger(other).candidate().storage_owner));
}

test "prior ledger binding rejects stale and foreign histories through the existing validator" {
    const initial = try ledger.createValidated(allocator, ledger.initialCandidate(project_owner), project_owner, null, limits.ledger);
    defer ledger.deinitOwner(initial);
    const next = try codec.decode(allocator, project_golden, project_owner, ledger.ledger(initial), limits);
    defer ledger.deinitOwner(next);
    try std.testing.expectError(error.TransactionLedgerRevisionConflict, codec.decode(allocator, project_golden, project_owner, ledger.ledger(next), limits));
    try std.testing.expectError(error.TransactionStorageOwnerMismatch, codec.decode(allocator, project_golden, project("/foreign"), ledger.ledger(initial), limits));
}

test "input output and record limits include exact boundary success" {
    const exact: codec.Limits = .{ .maximum_bytes = project_golden.len, .ledger = limits.ledger };
    const owned = try codec.decode(allocator, project_golden, project_owner, null, exact);
    defer ledger.deinitOwner(owned);
    const bytes = try codec.encode(allocator, ledger.ledger(owned), project_owner, project_golden.len);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings(project_golden, bytes);
    var below = exact;
    below.maximum_bytes -= 1;
    try std.testing.expectError(error.TransactionLedgerDocumentLimitExceeded, codec.decode(allocator, project_golden, project_owner, null, below));
    try std.testing.expectError(error.TransactionLedgerDocumentLimitExceeded, codec.encode(allocator, ledger.ledger(owned), project_owner, below.maximum_bytes));
    below.maximum_bytes = 0;
    try std.testing.expectError(error.InvalidTransactionLedgerDocumentLimit, codec.decode(allocator, project_golden, project_owner, null, below));
    try std.testing.expectError(error.InvalidTransactionLedgerDocumentLimit, codec.encode(allocator, ledger.ledger(owned), project_owner, 0));
    var small = limits;
    small.ledger.maximum_records = 2;
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, codec.decode(allocator, feature_golden, feature_owner, null, small));
    small.ledger.maximum_records = 1;
    const extra_retired = try std.mem.replaceOwned(u8, allocator, project_golden, "\"retiredTransactionOrdinals\":[]", "\"retiredTransactionOrdinals\":[1,1]");
    defer allocator.free(extra_retired);
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, codec.decode(allocator, extra_retired, project_owner, null, small));
    small.ledger.maximum_records = 0;
    try std.testing.expectError(error.InvalidTransactionLedgerLimits, codec.decode(allocator, project_golden, project_owner, null, small));
    small = limits;
    small.ledger.maximum_owner_bytes = 1;
    try std.testing.expectError(error.TransactionLedgerLimitExceeded, codec.decode(allocator, project_golden, project_owner, null, small));
}

test "decoded snapshots own their source bytes after parser cleanup" {
    const bytes = try allocator.dupe(u8, feature_golden);
    defer allocator.free(bytes);
    const owned = try codec.decode(allocator, bytes, feature_owner, null, limits);
    defer ledger.deinitOwner(owned);
    @memset(bytes, 'x');
    const output = try codec.encode(allocator, ledger.ledger(owned), feature_owner, limits.maximum_bytes);
    defer allocator.free(output);
    try std.testing.expectEqualStrings(feature_golden, output);
}

fn allocationScenario(test_allocator: std.mem.Allocator, bytes: []const u8, owner: identity.StorageOwner) !void {
    const owned = try codec.decode(test_allocator, bytes, owner, null, limits);
    defer ledger.deinitOwner(owned);
    const rendered = try codec.encode(test_allocator, ledger.ledger(owned), owner, limits.maximum_bytes);
    defer test_allocator.free(rendered);
    const again = try codec.decode(test_allocator, rendered, owner, null, limits);
    defer ledger.deinitOwner(again);
}

test "all codec allocation failures clean up without hiding OutOfMemory" {
    try std.testing.checkAllAllocationFailures(allocator, allocationScenario, .{ project_golden, project_owner });
    try std.testing.checkAllAllocationFailures(allocator, allocationScenario, .{ feature_golden, feature_owner });
}
