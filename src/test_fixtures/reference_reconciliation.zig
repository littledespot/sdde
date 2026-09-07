//! Scripted results only. Native actions remain the sole validation authority.
const std = @import("std");
pub const r = @import("../domain/reference_reconciliation.zig");
pub const build_items = @import("../actions/reference/build_reference_reconciliation_items.zig").Action{};
pub const partition = @import("../actions/reference/partition_reference_reconciliation_items.zig").Action{};
pub const assign_partitions = @import("../actions/reference/assign_reference_reconciliation_partitions.zig").Action{};
pub const validate_partitions = @import("../actions/reference/validate_reference_reconciliation_partitions.zig").Action{};
pub const build_input = @import("../actions/reference/build_reference_reconciliation_input.zig").Action{};
pub const parse = @import("../actions/reference/parse_reference_reconciliation_result.zig").Action{};
pub const validate_summary = @import("../actions/reference/validate_reference_reconciliation_summary.zig").Action{ .validator = @import("reference_text.zig").validator };
pub const assign_summary = @import("../actions/reference/assign_reference_summary_identities.zig").Action{};
pub const build_summary = @import("../actions/reference/build_reference_reconciliation_summary.zig").Action{};
pub const validate_dispositions = @import("../actions/reference/validate_reference_claim_dispositions.zig").Action{};
pub const validate_signals = @import("../actions/reference/validate_reference_signal_proposals.zig").Action{ .validator = @import("reference_text.zig").validator };
pub const validate_conflicts = @import("../actions/reference/validate_reference_conflict_proposals.zig").Action{ .validator = @import("reference_text.zig").validator };
pub const assign_records = @import("../actions/reference/assign_reference_reconciliation_identities.zig").Action{};
pub const build_records = @import("../actions/reference/build_reference_reconciliation_records.zig").Action{};
pub const account = @import("../actions/reference/validate_reference_reconciliation_completeness.zig").Action{};
pub const Context = @import("../domain/reference_reconciliation_validation.zig").TextContext;

pub fn content(claim: r.extraction.Claim) r.ContentProposal {
    return switch (claim.content) {
        .preserved_token => |token| .{ .preserved_token = .{ .token_id = token.value.id } },
        .model => |model| .{ .model = switch (model) {
            inline else => |value, tag| @unionInit(r.extraction.ProposalContent, @tagName(tag), value.value),
        } },
    };
}
pub fn summary(allocator: std.mem.Allocator, input: r.Input) !r.SummaryProposal {
    const statements = try allocator.alloc(r.StatementProposal, input.items.len);
    for (input.items, statements, 0..) |item, *statement, index| {
        const ids = try allocator.alloc(r.ClaimId, 1);
        ids[0] = item.claim.id;
        statement.* = .{ .local_key = @intCast(index + 1), .claim_ids = ids, .content = content(item.claim) };
    }
    return .{ .member_claim_ids = input.partition.group.claim_ids, .member_summary_ids = input.member_summary_ids, .statements = statements };
}
pub fn global(allocator: std.mem.Allocator, input: r.Input) !r.Proposal {
    const dispositions = try allocator.alloc(r.ClaimDisposition, input.items.len);
    const signals = try allocator.alloc(r.SignalProposal, input.items.len);
    for (input.items, dispositions, signals) |item, *disposition, *signal| {
        const ids = try allocator.alloc(r.ClaimId, 1);
        ids[0] = item.claim.id;
        disposition.* = .{ .claim_id = item.claim.id, .disposition = .retained, .related_claim_ids = &.{} };
        signal.* = .{ .claim_ids = ids, .citation_ids = item.claim.citation_ids, .content = content(item.claim) };
    }
    return .{ .claim_dispositions = dispositions, .signals = signals, .conflicts = &.{} };
}
pub fn initialize(allocator: std.mem.Allocator, inputs: r.evidence.Inputs, extracted: r.extraction.Accounted, size: u32) !r.Progress {
    return validate_partitions.execute(allocator, try assign_partitions.execute(allocator, try partition.execute(allocator, try build_items.execute(allocator, inputs, extracted), size)));
}
pub fn summaries(allocator: std.mem.Allocator, initial: r.Progress, context: Context) !r.Input {
    var progress = initial;
    while (true) {
        const input = try build_input.execute(allocator, progress);
        if (input.purpose == .global) return input;
        const bytes = try @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), allocator, .{ .summary = try summary(allocator, input) });
        const parsed = try parse.execute(allocator, .{ .input = input, .bytes = bytes });
        progress = try build_summary.execute(allocator, try assign_summary.execute(allocator, try validate_summary.execute(allocator, parsed, context)));
    }
}
pub fn finish(allocator: std.mem.Allocator, input: r.Input, proposal: r.Proposal, context: Context) !r.Accounted {
    const bytes = try @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), allocator, .{ .global = proposal });
    const parsed = try parse.execute(allocator, .{ .input = input, .bytes = bytes });
    const dispositions = try validate_dispositions.execute(allocator, parsed);
    const signals = try validate_signals.execute(allocator, dispositions, context);
    const conflicts = try validate_conflicts.execute(allocator, signals, context);
    return account.execute(allocator, try build_records.execute(allocator, try assign_records.execute(allocator, conflicts)));
}
