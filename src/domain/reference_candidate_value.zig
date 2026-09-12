//! Execution-local ownership only. No filesystem, counters persisted to disk,
//! model capabilities or model-call byte ceilings.
const std = @import("std");
const extraction = @import("reference_extraction.zig");
const reconciliation = @import("reference_reconciliation.zig");
pub const Payload = union(enum) {
    extraction_progress: @import("reference_model_iteration.zig").Progress,
    raw: extraction.Raw,
    parsed: extraction.Parsed,
    text_validated: extraction.TextValidated,
    token_classified: extraction.Classified,
    token_classification_rejected: @import("token_classification_validation.zig").Rejection,
    tokens_assigned: extraction.TokenAssignments,
    prepared: extraction.Prepared,
    validated: extraction.Validated,
    assigned: extraction.Assignments,
    ledger: extraction.Ledger,
    accounted: extraction.Accounted,
    reconciliation_items: reconciliation.Items,
    reconciliation_layout: reconciliation.Layout,
    reconciliation_plan: reconciliation.Plan,
    reconciliation_progress: reconciliation.Progress,
    reconciliation_input: reconciliation.Input,
    reconciliation_raw: reconciliation.Raw,
    reconciliation_parsed: reconciliation.Parsed,
    reconciliation_summary: reconciliation.CheckedSummary,
    reconciliation_summary_ids: reconciliation.SummaryAssignment,
    reconciliation_dispositions: reconciliation.CheckedDispositions,
    reconciliation_signals: reconciliation.CheckedSignals,
    reconciliation_conflicts: reconciliation.CheckedConflicts,
    reconciliation_record_ids: reconciliation.RecordAssignments,
    reconciliation_records: reconciliation.Records,
    reconciliation_accounted: reconciliation.Accounted,
};
pub const Value = opaque {
    pub fn payload(self: *const Value) *const Payload {
        return &storage(self).payload;
    }
};
pub const Owner = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    references: usize = 1,
    parent: ?*const Value,
    payload: Payload,
    handle: Handle,
};
const Handle = struct { owner: *Owner };

/// A result may borrow its one preceding immutable candidate, never a runner
/// input's unretained allocation. Each successor retains one closed prior stage.
pub fn create(allocator: std.mem.Allocator, parent: ?*const Value) std.mem.Allocator.Error!*Owner {
    const owner = try allocator.create(Owner);
    owner.* = .{ .allocator = allocator, .arena = .init(allocator), .parent = parent, .payload = .{ .raw = .{ .entries = &.{} } }, .handle = .{ .owner = owner } };
    if (parent) |value| storage(value).references = std.math.add(usize, storage(value).references, 1) catch @panic("reference value count exhausted");
    return owner;
}
pub fn view(owner: *const Owner) *const Value {
    return @ptrCast(&owner.handle);
}
pub fn destroy(owner: *Owner) void {
    var current = owner;
    while (true) {
        std.debug.assert(current.references > 0);
        current.references -= 1;
        if (current.references != 0) return;
        const parent = if (current.parent) |value| storage(value) else null;
        const allocator = current.allocator;
        current.arena.deinit();
        allocator.destroy(current);
        current = parent orelse return;
    }
}
fn storage(value: *const Value) *Owner {
    const handle: *const Handle = @ptrCast(@alignCast(value));
    return handle.owner;
}

/// Test/provider adapters transfer engine-bound observations, not model IDs.
pub fn capture(allocator: std.mem.Allocator, raw: extraction.Raw) std.mem.Allocator.Error!*Owner {
    const owner = try create(allocator, null);
    errdefer destroy(owner);
    const arena = owner.arena.allocator();
    const entries = try arena.alloc(extraction.RawResult, raw.entries.len);
    for (raw.entries, entries) |input, *entry| {
        entry.* = .{
            .scope = .{ .state_id = .{ .bytes = try arena.dupe(u8, input.scope.state_id.bytes) }, .chunk_id = .{ .bytes = try arena.dupe(u8, input.scope.chunk_id.bytes) } },
            .result = switch (input.result) {
                .response => |bytes| .{ .response = try arena.dupe(u8, bytes) },
                .blocked => |reason| .{ .blocked = reason },
            },
        };
    }
    owner.payload = .{ .raw = .{ .entries = entries } };
    return owner;
}
