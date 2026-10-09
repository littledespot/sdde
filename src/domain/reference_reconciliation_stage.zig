//! Native phase handoffs. No dispatch, retry or workflow execution authority.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const packets = @import("model_input_packet.zig");
const json = @import("model_candidate_json.zig");
pub const Stage = enum { dispositions, signals, roles, conflicts };
pub const Prior = union(Stage) { dispositions: r.Input, signals: r.CheckedDispositions, roles: r.CheckedSignals, conflicts: r.CheckedSignals };
pub fn input(prior: Prior) r.Input {
    return switch (prior) {
        .dispositions => |value| value,
        .signals => |value| value.input,
        .roles, .conflicts => |value| value.prior.input,
    };
}
pub fn packet(a: std.mem.Allocator, prior: Prior, source: r.evidence.Inputs, registry: @import("passive_literals.zig").Registry) @import("reference_model_input.zig").ReconciliationError!*packets.Packet {
    const current = input(prior);
    if (current.purpose != .global or !accepts(prior)) return error.InvalidReferenceReconciliation;
    const stage = std.meta.activeTag(prior);
    const base = try @import("reference_model_input.zig").reconciliationPhasePacket(a, prior, source, registry);
    defer packets.release(base);
    const selected = try packets.withAssignmentContext(a, base, packets.AssignmentContextId.parse(@tagName(stage)).?);
    defer packets.release(selected);
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    const signal_values: []const r.ValidatedSignal = switch (prior) {
        .roles, .conflicts => |v| v.signals,
        else => &.{},
    };
    var groups: std.ArrayList(@import("reference_role_assignment.zig").Group) = .empty;
    const group_source: r.diagnostic.Source = switch (prior) {
        .roles, .conflicts => |v| v.prior.source,
        else => .{},
    };
    for (try @import("reference_role_assignment.zig").groups(scratch, group_source, signal_values)) |group| {
        if (prior == .roles and !try @import("reference_support.zig").eligibleSelection(prior.roles.prior.dispositions, group.value.claim_ids)) continue;
        try groups.append(scratch, group);
    }
    const conflict_groups: []const @import("reference_conflict_groups.zig").Group = switch (prior) {
        .roles, .conflicts => |v| v.prior.proposal.conflict_groups,
        else => &.{},
    };
    const conflict_catalogue = try @import("reference_conflict_groups.zig").catalogue(scratch, conflict_groups);
    const accepted = switch (prior) {
        .dispositions => try json.encode(r.PartitionId, scratch, current.partition.id),
        .signals => |value| try json.encode(@TypeOf(.{ .dispositions = value.dispositions, .signals = value.proposal.signals }), scratch, .{ .dispositions = value.dispositions, .signals = value.proposal.signals }),
        .roles, .conflicts => |value| try json.encode(@import("reference_role_assignment.zig").Facts, scratch, .{ .dispositions = value.prior.dispositions, .signals = groups.items, .conflict_groups = conflict_catalogue }),
    };
    const values = std.json.parseFromSlice(std.json.Value, scratch, accepted, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
    const with_facts = try packets.withJsonContext(a, selected, "accepted", values.value);
    defer packets.release(with_facts);
    // The definition and revision belong to this exact immutable assignment.
    const slot = try slotId(scratch, prior);
    const result = try packets.create(a, with_facts.body(), .{ .reference_global = .{ .reference_state_id = .{ .bytes = current.progress.plan.layout.items.state_id.bytes }, .unit_slot_id = .{ .bytes = slot } } }, .initial_generation, .{ .bytes = definition(stage) });
    defer packets.release(result);
    const inherited = try packets.withRestrictions(a, result, selected.excludedVariants(), selected.integerChoices());
    if (prior == .signals) return inherited;
    defer packets.release(inherited);
    if (prior == .dispositions) return @import("reference_model_input.zig").withDispositionChoices(a, inherited, current.partition.group.claim_ids, null, true);
    if (prior == .roles) return restrictRolePacket(a, inherited, prior.roles.prior.dispositions, groups.items);
    const ids = try scratch.alloc(i64, conflict_catalogue.len);
    for (ids, conflict_catalogue) |*id, group| id.* = group.group_id.ordinal;
    return packets.withIntegerChoices(a, inherited, &.{.{ .target = .{ .path = &.{ .{ .property = "conflicts" }, .{ .items = {} }, .{ .property = "group_id" } } }, .definition = result.resultDefinition(), .allowed = ids }});
}
/// Production and diagnostic replay share the same eligible support projection.
pub fn restrictRolePacket(a: std.mem.Allocator, base: *const packets.Packet, dispositions: []const r.ClaimDisposition, offered: []const @import("reference_role_assignment.zig").Group) @import("reference_model_input.zig").ReconciliationError!*packets.Packet {
    var ids: std.ArrayList(i64) = .empty;
    defer ids.deinit(a);
    for (offered) |group| if (try @import("reference_support.zig").eligibleSelection(dispositions, group.value.claim_ids)) try ids.append(a, group.signal_id.ordinal);
    if (ids.items.len == 0) {
        const schema = @import("model_result_schema.zig");
        const excluded = try a.alloc(schema.ExcludedVariant, base.excludedVariants().len + 1);
        defer a.free(excluded);
        @memcpy(excluded[0..base.excludedVariants().len], base.excludedVariants());
        excluded[excluded.len - 1] = .{ .kind = "supported" };
        return packets.withExcludedVariants(a, base, excluded);
    }
    return packets.withIntegerChoices(a, base, &.{.{ .target = .{ .tagged = .{ .kind = "supported", .field = "signal_ids" } }, .definition = base.resultDefinition(), .allowed = ids.items }});
}
pub fn collect(a: std.mem.Allocator, prior: Prior, bound: *const packets.Packet, body: []const u8, origin: @import("model_candidate_origin.zig").Origin) r.Error!r.Parsed {
    const current = input(prior);
    const stage = std.meta.activeTag(prior);
    if (!accepts(prior)) return error.InvalidReferenceReconciliation;
    if (bound.unit() != .reference_global or bound.purpose() != .initial_generation or !std.mem.eql(u8, bound.unit().reference_global.reference_state_id.bytes, current.progress.plan.layout.items.state_id.bytes) or !std.mem.eql(u8, (bound.resultDefinition() orelse return error.InvalidReferenceReconciliation).bytes, definition(stage))) return error.InvalidReferenceReconciliation;
    const expected = try slotId(a, prior);
    defer a.free(expected);
    if (!std.mem.eql(u8, bound.unit().reference_global.unit_slot_id.bytes, expected)) return error.InvalidReferenceReconciliation;
    var result: r.Parsed = switch (prior) {
        .dispositions => .{ .input = current, .proposal = .{ .global = .{ .claim_dispositions = &.{}, .signals = &.{}, .conflicts = &.{} } } },
        .signals => |value| .{ .phase = value.phase, .source = value.source, .input = value.input, .proposal = .{ .global = value.proposal } },
        .roles, .conflicts => |value| .{ .phase = value.prior.phase, .source = value.prior.source, .input = value.prior.input, .proposal = .{ .global = value.prior.proposal } },
    };
    const value = json.decodeSelected(Response, a, stage, body) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
    switch (value) {
        .dispositions => |v| {
            result.proposal.global.conflict_groups = v.conflict_groups;
            result.proposal.global.claim_dispositions = try @import("reference_conflict_groups.zig").expand(a, v);
            result.phase = .dispositions;
        },
        .signals => |v| {
            result.proposal.global.signals = try @import("reference_reconciliation_projection.zig").signals(a, prior.signals, v.signals);
            for (prior.signals.proposal.signals.len..result.proposal.global.signals.len) |index| result.source.signals = result.source.signals.inserting(a, index, index) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
            result.phase = if (result.proposal.global.conflicts.len > 0) .signals_with_conflicts else .signals;
        },
        .roles => |v| {
            result.proposal.global.role_decisions = v.role_decisions;
            result.phase = if (result.phase == .signals_with_conflicts) .complete else .roles;
        },
        .conflicts => |v| {
            result.proposal.global.conflicts = try @import("reference_conflict_groups.zig").explain(a, prior.conflicts.prior.proposal.conflict_groups, v.conflicts);
            result.phase = .complete;
        },
    }
    var fields: std.ArrayList(r.diagnostic.FieldOrigin) = .empty;
    const unit: r.diagnostic.Unit = switch (stage) {
        .dispositions => .dispositions,
        .signals, .roles => .signals,
        .conflicts => .conflicts,
    };
    const field: r.diagnostic.Field = if (stage == .roles) .relationship else .record;
    for (result.source.fields) |old| {
        if (std.meta.eql(old.unit, unit) and old.field == field) continue;
        if (stage == .signals and old.unit == .signal) continue;
        if (stage == .conflicts and old.unit == .conflict) continue;
        try fields.append(a, old);
    }
    try fields.append(a, .{ .unit = unit, .field = field, .origin = origin });
    if (stage == .signals) for (result.proposal.global.signals, 0..) |signal, index| {
        try fields.append(a, .{ .unit = .{ .signal = index }, .field = .record, .origin = if (index < prior.signals.proposal.signals.len) prior.signals.source.at(.{ .signal = index }, .record) else if (signal.content == .preserved_token) null else origin });
    };
    result.source.fields = try fields.toOwnedSlice(a);
    return result;
}
pub const Response = union(Stage) { dispositions: @import("reference_conflict_groups.zig").Selection, signals: struct { signals: []const @import("reference_reconciliation_projection.zig").SemanticSignal }, roles: struct { role_decisions: r.RoleDecisions }, conflicts: struct { conflicts: []const @import("reference_conflict_groups.zig").Explanation } };

fn definition(stage: Stage) []const u8 {
    return switch (stage) {
        inline else => |v| @tagName(v) ++ "_assignment",
    };
}

fn slotId(a: std.mem.Allocator, prior: Prior) std.mem.Allocator.Error![]const u8 {
    const digest = try @import("atomic_repair.zig").snapshot(Prior, a, prior);
    return std.fmt.allocPrint(a, "reconciliation-{d}-{s}-r{d}-{s}", .{ input(prior).partition.id.ordinal, @tagName(std.meta.activeTag(prior)), switch (prior) {
        .dispositions => @as(u64, 1),
        .signals => |v| v.source.revision,
        .roles, .conflicts => |v| v.prior.source.revision,
    }, std.fmt.bytesToHex(digest.bytes, .lower) });
}

fn accepts(prior: Prior) bool {
    return switch (prior) {
        .dispositions => |v| v.purpose == .global,
        .signals => |v| v.phase == .dispositions,
        .roles => |v| v.prior.phase == .signals or v.prior.phase == .signals_with_conflicts,
        .conflicts => |v| v.prior.phase == .roles,
    };
}
