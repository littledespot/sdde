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
pub const validate_roles = @import("../actions/reference/validate_reference_role_assignments.zig").Action{};
pub const validate_conflicts = @import("../actions/reference/validate_reference_conflict_proposals.zig").Action{ .validator = @import("reference_text.zig").validator };
pub const assign_records = @import("../actions/reference/assign_reference_reconciliation_identities.zig").Action{};
pub const build_records = @import("../actions/reference/build_reference_reconciliation_records.zig").Action{};
pub const account = @import("../actions/reference/validate_reference_reconciliation_completeness.zig").Action{};
pub const Context = @import("../domain/reference_reconciliation_validation.zig").TextContext;

pub fn repairResponse(a: std.mem.Allocator, value: @import("../domain/reference_reconciliation_repair.zig").Replacement) ![]const u8 {
    const json = @import("../domain/model_candidate_json.zig");
    if (value == .disposition and value.disposition == .conflicting) return "{\"kind\":\"conflicting\"}";
    if (value == .conflict_group) {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, try json.encodeSelected(@TypeOf(value), a, value), .{});
        var result = parsed.value;
        for (result.object.getPtr("claim_dispositions").?.array.items) |*entry| {
            const choice = entry.object.getPtr("disposition").?;
            if (std.mem.eql(u8, choice.object.get("kind").?.string, "conflicting")) _ = choice.object.swapRemove("related_claim_ids");
        }
        try result.object.put(a, "conflicts", try explanationWire(a, result.object.get("conflict_groups").?.array.items, result.object.get("conflicts").?.array.items));
        return std.json.Stringify.valueAlloc(a, result, .{});
    }
    return if (value == .content) switch (value.content) {
        .model => |model| json.encodeSelected(r.extraction.ProposalContent, a, model),
        .preserved_token => |token| json.encode(r.TokenReference, a, token),
    } else json.encodeSelected(@TypeOf(value), a, value);
}

/// Initial and repaired fake-provider responses use the same group-handle wire.
/// Unmatched selections stay invalid; projection never hides the injected defect.
pub fn explanationWire(a: std.mem.Allocator, groups: []const std.json.Value, supplied: []const std.json.Value) !std.json.Value {
    var result: std.array_list.Managed(std.json.Value) = .init(a);
    for (supplied) |entry| {
        const ids = entry.object.get("claim_ids").?.array.items;
        var handles: std.ArrayList(i64) = .empty;
        for (groups, 0..) |group, index| {
            const included = for (group.object.get("claim_ids").?.array.items) |id| {
                const found = for (ids) |member| {
                    if (member.integer == id.integer) break true;
                } else false;
                if (!found) break false;
            } else true;
            if (!included) continue;
            try handles.append(a, @intCast(index + 1));
        }
        if (handles.items.len == 0) try handles.append(a, 999999);
        for (handles.items) |id| {
            var explanation: std.json.ObjectMap = .{};
            try explanation.put(a, "group_id", .{ .integer = id });
            try explanation.put(a, "kind", entry.object.get("kind").?);
            try explanation.put(a, "summary", entry.object.get("summary").?);
            try result.append(.{ .object = explanation });
        }
    }
    return .{ .array = result };
}

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
    for (input.items, statements) |item, *statement| {
        const ids = try allocator.alloc(r.ClaimId, 1);
        ids[0] = item.claim.id;
        statement.* = .{ .claim_ids = ids, .content = content(item.claim) };
    }
    return .{ .statements = statements };
}
pub fn global(allocator: std.mem.Allocator, input: r.Input) !r.Proposal {
    const dispositions = try allocator.alloc(r.ClaimDispositionProposal, input.items.len);
    const signals = try allocator.alloc(r.SignalProposal, input.items.len);
    const roles = try allocator.alloc(r.RoleAssignment, input.items.len);
    var role_count: usize = 0;
    var assigned_feature = false;
    for (input.items, dispositions, signals, 0..) |item, *disposition, *signal, index| {
        const ids = try allocator.alloc(r.ClaimId, 1);
        ids[0] = item.claim.id;
        disposition.* = .{ .claim_id = item.claim.id, .disposition = .{ .retained = .{} } };
        const business = item.claim.content == .model and item.claim.content.model == .business;
        signal.* = .{ .claim_ids = ids, .content = content(item.claim) };
        if (business) {
            roles[role_count] = .{ .signal_id = .{ .ordinal = @intCast(index + 1) }, .generation_roles = if (!assigned_feature)
                &.{ .title, .description, .primary_goal, .primary_user_story, .entity_basis, .records }
            else
                &.{.records} };
            role_count += 1;
        }
        if (business) assigned_feature = true;
    }
    return .{ .claim_dispositions = dispositions, .signals = signals, .role_assignments = roles[0..role_count], .conflicts = &.{} };
}

pub fn initialize(allocator: std.mem.Allocator, inputs: r.evidence.Inputs, extracted: r.extraction.Accounted, size: u32) !r.Progress {
    return validate_partitions.execute(allocator, try assign_partitions.execute(allocator, try partition.execute(allocator, try build_items.execute(allocator, inputs, extracted), size)));
}
pub fn summaries(allocator: std.mem.Allocator, initial: r.Progress, context: Context) !r.Input {
    var progress = initial;
    while (true) {
        const input = try build_input.execute(allocator, progress);
        if (input.purpose == .global) return input;
        const bytes = try modelWire(allocator, .{ .summary = try summary(allocator, input) });
        const parsed = try parse.execute(allocator, .{ .input = input, .bytes = bytes });
        progress = try build_summary.execute(allocator, try assign_summary.execute(allocator, (try validate_summary.execute(allocator, parsed, context)).valid));
    }
}
pub fn finish(allocator: std.mem.Allocator, input: r.Input, proposal: r.Proposal, context: Context) !r.diagnostic.Result(r.Accounted) {
    const parsed: r.Parsed = .{ .input = input, .proposal = .{ .global = proposal } };
    const dispositions = try validate_dispositions.execute(allocator, parsed);
    if (dispositions == .invalid) return .{ .invalid = dispositions.invalid };
    const signals = try validate_signals.execute(allocator, dispositions.valid, context);
    if (signals == .invalid) return .{ .invalid = signals.invalid };
    const roles = try validate_roles.execute(allocator, signals.valid);
    if (roles == .invalid) return .{ .invalid = roles.invalid };
    const conflicts = try validate_conflicts.execute(allocator, roles.valid, context);
    if (conflicts == .invalid) return .{ .invalid = conflicts.invalid };
    return .{ .valid = try account.execute(allocator, try build_records.execute(allocator, try assign_records.execute(allocator, conflicts.valid))) };
}

/// Project scripted native fixtures into the model's semantic-only shape.
pub fn modelWire(a: std.mem.Allocator, proposal: @FieldType(r.Parsed, "proposal")) ![]const u8 {
    const raw = try @import("../domain/model_candidate_json.zig").encodeSelected(@FieldType(r.Parsed, "proposal"), a, proposal);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, raw, .{});
    const name = if (proposal == .summary) "statements" else "signals";
    const list = parsed.value.object.getPtr(name).?;
    var retained: std.array_list.Managed(std.json.Value) = .init(a);
    for (list.array.items) |entry| {
        if (std.mem.eql(u8, entry.object.get("content").?.object.get("kind").?.string, "preserved_token")) continue;
        try retained.append(entry);
    }
    list.* = .{ .array = retained };
    return std.json.Stringify.valueAlloc(a, parsed.value, .{});
}
