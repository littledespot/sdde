const std = @import("std");
const identity = @import("../../domain/transaction_identity.zig");
const ledger = @import("../../domain/transaction_id_ledger.zig");
const json = @import("../../domain/strict_json.zig");

pub const schema = "transaction-id-ledger/v1";
pub const Limits = struct { maximum_bytes: u32, ledger: ledger.Limits };
pub const Error = ledger.Error || error{
    InvalidTransactionLedgerDocument,
    UnsupportedTransactionLedgerSchema,
    InvalidTransactionLedgerDocumentLimit,
    TransactionLedgerDocumentLimitExceeded,
    TransactionLedgerSerializationFailed,
};

// These wire-only wrappers prevent std.json's integer/string/enum coercions.
const Integer = struct {
    value: u64,

    pub fn jsonParse(_: std.mem.Allocator, source: *std.json.Scanner, _: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!Integer {
        const bytes = switch (try source.next()) {
            .number => |bytes| bytes,
            else => return error.UnexpectedToken,
        };
        if (bytes.len == 0) return error.UnexpectedToken;
        for (bytes) |byte| if (!std.ascii.isDigit(byte)) return error.UnexpectedToken;
        return .{ .value = try std.fmt.parseInt(u64, bytes, 10) };
    }

    pub fn jsonStringify(self: Integer, writer: *std.json.Stringify) std.json.Stringify.Error!void {
        try writer.write(self.value);
    }
};

const Text = struct {
    bytes: []const u8,

    pub fn jsonParse(allocator: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!Text {
        return switch (try source.nextAllocMax(allocator, options.allocate.?, options.max_value_len.?)) {
            .string, .allocated_string => |bytes| .{ .bytes = bytes },
            else => error.UnexpectedToken,
        };
    }

    pub fn jsonStringify(self: Text, writer: *std.json.Stringify) std.json.Stringify.Error!void {
        try writer.write(self.bytes);
    }
};

const StoredOwner = struct {
    feature: struct { featureId: Text, workflowArtifactRegistryStateOrdinal: Integer },
};
const StoredRecord = struct {
    transactionOrdinal: Integer,
    transactionKind: Text,
    status: Text,
};
const Document = struct {
    schema: Text,
    storageOwner: StoredOwner,
    revision: Integer,
    nextTransactionOrdinal: Integer,
    reservations: []const StoredRecord,
    retiredTransactionOrdinals: []const Integer,
};

/// The caller supplies collection context, not a project path from the bytes.
/// The result is an owned structural ledger, never storage/durability evidence.
pub fn decode(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    expected_owner: identity.StorageOwner,
    prior: ?*const ledger.Ledger,
    limits: Limits,
) Error!*ledger.Owner {
    if (limits.maximum_bytes == 0) return error.InvalidTransactionLedgerDocumentLimit;
    try limits.ledger.validateCounts(0, 0);
    if (bytes.len > limits.maximum_bytes) return error.TransactionLedgerDocumentLimitExceeded;
    json.validateTransport(allocator, bytes, .{
        .maximum_bytes = limits.maximum_bytes,
        .maximum_depth = 3,
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidTransactionLedgerDocument,
    };
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temporary = arena.allocator();
    const document = std.json.parseFromSliceLeaky(Document, temporary, bytes, .{
        .duplicate_field_behavior = .@"error",
        .ignore_unknown_fields = false,
        .allocate = .alloc_always,
        .max_value_len = limits.maximum_bytes,
    }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidTransactionLedgerDocument;
    if (!std.mem.eql(u8, document.schema.bytes, schema)) return error.UnsupportedTransactionLedgerSchema;
    try limits.ledger.validateCounts(document.reservations.len, document.retiredTransactionOrdinals.len);
    const owner = decodeOwner(document.storageOwner);
    const records = try temporary.alloc(ledger.Record, document.reservations.len);
    for (document.reservations, records) |record, *result| result.* = .{
        .transaction_id = .{ .storage_owner = owner, .ordinal = .{ .value = record.transactionOrdinal.value } },
        .transaction_kind = std.meta.stringToEnum(identity.Kind, record.transactionKind.bytes) orelse return error.InvalidTransactionLedgerDocument,
        .status = std.meta.stringToEnum(ledger.Status, record.status.bytes) orelse return error.InvalidTransactionLedgerDocument,
    };
    const retired = try temporary.alloc(identity.TransactionId, document.retiredTransactionOrdinals.len);
    for (document.retiredTransactionOrdinals, retired) |ordinal, *id| id.* = .{ .storage_owner = owner, .ordinal = .{ .value = ordinal.value } };
    return ledger.createValidated(allocator, .{
        .storage_owner = owner,
        .revision = .{ .value = document.revision.value },
        .next_transaction_ordinal = .{ .value = document.nextTransactionOrdinal.value },
        .reservations = records,
        .retired_transaction_ids = retired,
    }, expected_owner, prior, limits.ledger);
}

/// Emits one compact document plus LF. Caller owns the returned bytes.
pub fn encode(
    allocator: std.mem.Allocator,
    current: *const ledger.Ledger,
    expected_owner: identity.StorageOwner,
    maximum_bytes: u32,
) Error![]u8 {
    if (maximum_bytes == 0) return error.InvalidTransactionLedgerDocumentLimit;
    const candidate = current.candidate();
    if (!candidate.storage_owner.eql(expected_owner)) return error.TransactionStorageOwnerMismatch;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const temporary = arena.allocator();
    const records = try temporary.alloc(StoredRecord, candidate.reservations.len);
    for (candidate.reservations, records) |record, *result| result.* = .{
        .transactionOrdinal = .{ .value = record.transaction_id.ordinal.value },
        .transactionKind = .{ .bytes = @tagName(record.transaction_kind) },
        .status = .{ .bytes = @tagName(record.status) },
    };
    const retired = try temporary.alloc(Integer, candidate.retired_transaction_ids.len);
    for (candidate.retired_transaction_ids, retired) |id, *result| result.* = .{ .value = id.ordinal.value };
    const document: Document = .{
        .schema = .{ .bytes = schema },
        .storageOwner = .{ .feature = .{
            .featureId = .{ .bytes = candidate.storage_owner.feature_id.bytes },
            .workflowArtifactRegistryStateOrdinal = .{ .value = candidate.storage_owner.workflow_artifact_registry_state_id.ordinal },
        } },
        .revision = .{ .value = candidate.revision.value },
        .nextTransactionOrdinal = .{ .value = candidate.next_transaction_ordinal.value },
        .reservations = records,
        .retiredTransactionOrdinals = retired,
    };
    var counter: std.Io.Writer.Discarding = .init(&.{});
    try render(document, &counter.writer);
    const length = counter.fullCount();
    if (length > maximum_bytes) return error.TransactionLedgerDocumentLimitExceeded;
    const output = try allocator.alloc(u8, @intCast(length));
    errdefer allocator.free(output);
    var writer: std.Io.Writer = .fixed(output);
    try render(document, &writer);
    if (writer.end != output.len) return error.TransactionLedgerSerializationFailed;
    return output;
}

fn decodeOwner(stored: StoredOwner) identity.StorageOwner {
    return .{
        .feature_id = .{ .bytes = stored.feature.featureId.bytes },
        .workflow_artifact_registry_state_id = .{
            .feature_id = .{ .bytes = stored.feature.featureId.bytes },
            .ordinal = stored.feature.workflowArtifactRegistryStateOrdinal.value,
        },
    };
}

fn render(document: Document, writer: *std.Io.Writer) Error!void {
    std.json.Stringify.value(document, .{
        .whitespace = .minified,
        .emit_nonportable_numbers_as_strings = false,
    }, writer) catch return error.TransactionLedgerSerializationFailed;
    writer.writeByte('\n') catch return error.TransactionLedgerSerializationFailed;
}
