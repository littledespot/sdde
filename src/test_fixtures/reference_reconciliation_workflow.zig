//! A finite scripted graph, not a shipped workflow or runtime graph generator.
const std = @import("std");
pub fn suffix(allocator: std.mem.Allocator, summary_count: usize) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    try result.appendSlice(allocator, "  observe-extraction: { use: build-reference-reconciliation-items, on: { ok: partition-reconciliation, failed: end.failed } }\n" ++
        "  partition-reconciliation: { use: partition-reference-reconciliation-items, with: { group-size: 2 }, on: { ok: assign-partitions, failed: end.failed } }\n" ++
        "  assign-partitions: { use: assign-reference-reconciliation-partitions, on: { ok: validate-partitions, failed: end.failed } }\n" ++
        "  validate-partitions: { use: validate-reference-reconciliation-partitions, on: { ok: input-0, failed: end.failed } }\n");
    for (0..summary_count + 1) |index| {
        const block = try std.fmt.allocPrint(allocator, "  input-{d}: {{ use: build-reference-reconciliation-input, on: {{ ok: propose-{d}, failed: end.failed }} }}\n" ++
            "  propose-{d}: {{ use: test.propose-reconciliation, on: {{ ok: parse-{d} }} }}\n" ++
            "  parse-{d}: {{ use: parse-reference-reconciliation-result, on: {{ ok: check-{d}, failed: end.failed }} }}\n", .{ index, index, index, index, index, index });
        defer allocator.free(block);
        try result.appendSlice(allocator, block);
        if (index == summary_count) {
            const final = try std.fmt.allocPrint(allocator, "  check-{d}: {{ use: validate-reference-claim-dispositions, on: {{ ok: check-signals, failed: end.failed }} }}\n", .{index});
            defer allocator.free(final);
            try result.appendSlice(allocator, final);
        } else {
            const summary = try std.fmt.allocPrint(allocator, "  check-{d}: {{ use: validate-reference-reconciliation-summary, on: {{ ok: assign-summary-{d}, failed: end.failed }} }}\n" ++
                "  assign-summary-{d}: {{ use: assign-reference-summary-identities, on: {{ ok: build-summary-{d}, failed: end.failed }} }}\n" ++
                "  build-summary-{d}: {{ use: build-reference-reconciliation-summary, on: {{ ok: input-{d}, failed: end.failed }} }}\n", .{ index, index, index, index, index, index + 1 });
            defer allocator.free(summary);
            try result.appendSlice(allocator, summary);
        }
    }
    try result.appendSlice(allocator, "  check-signals: { use: validate-reference-signal-proposals, on: { ok: check-conflicts, failed: end.failed } }\n" ++
        "  check-conflicts: { use: validate-reference-conflict-proposals, on: { ok: assign-records, failed: end.failed } }\n" ++
        "  assign-records: { use: assign-reference-reconciliation-identities, on: { ok: build-records, failed: end.failed } }\n" ++
        "  build-records: { use: build-reference-reconciliation-records, on: { ok: account-reconciliation, failed: end.failed } }\n" ++
        "  account-reconciliation: { use: validate-reference-reconciliation-completeness, on: { ok: project-authority, blocked: end.blocked, failed: end.failed } }\n" ++
        "  project-authority: { use: build-specification-authority-requirements, on: { ok: build-authority, blocked: end.blocked } }\n" ++
        "  build-authority: { use: build-required-authority-ledger, on: { ok: observe-reconciliation, blocked: end.blocked } }\n" ++
        "  observe-reconciliation: { use: test.observe-reconciliation, on: { ok: end.ok } }\n");
    return result.toOwnedSlice(allocator);
}
