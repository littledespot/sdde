//! Native phase handoffs. No dispatch, retry or workflow execution authority.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const packets = @import("model_input_packet.zig");
const json = @import("model_candidate_json.zig");
pub const Stage = enum { dispositions, signals, conflicts };
pub const Prior = union(Stage) { dispositions: r.Input, signals: r.CheckedDispositions, conflicts: r.CheckedSignals };
/// Current native groups retain their repair occurrence IDs until canonical IDs
/// are allocated. This projection carries no authoring support decision.
pub const Group = struct { signal_id: r.SignalSelectionId, value: r.ValidatedSignal };
pub const Facts = struct {
    dispositions: []const r.ClaimDisposition,
    signals: []const Group,
    conflict_groups: []const @import("reference_conflict_groups.zig").CatalogueEntry,
};
pub fn groups(a: std.mem.Allocator, source: r.diagnostic.Source, signals: []const r.ValidatedSignal) r.Error![]const Group {
    const result = try a.alloc(Group, signals.len);
    errdefer a.free(result);
    for (signals, result, 0..) |signal, *group, index| group.* = .{
        .signal_id = .{ .ordinal = (source.signals.at(index, signals.len) catch return error.InvalidReferenceReconciliation).ordinal },
        .value = signal,
    };
    return result;
}
pub fn input(prior: Prior) r.Input {
    return switch (prior) {
        .dispositions => |value| value,
        .signals => |value| value.input,
        .conflicts => |value| value.prior.input,
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
        .conflicts => |v| v.signals,
        else => &.{},
    };
    const group_source: r.diagnostic.Source = switch (prior) {
        .conflicts => |v| v.prior.source,
        else => .{},
    };
    const accepted_groups = try groups(scratch, group_source, signal_values);
    const conflict_groups: []const @import("reference_conflict_groups.zig").Group = switch (prior) {
        .conflicts => |v| v.prior.proposal.conflict_groups,
        else => &.{},
    };
    const conflict_catalogue = try @import("reference_conflict_groups.zig").catalogue(scratch, conflict_groups);
    const accepted = switch (prior) {
        .dispositions => try json.encode(r.PartitionId, scratch, current.partition.id),
        .signals => |value| try json.encode(@TypeOf(.{ .dispositions = value.dispositions, .signals = value.proposal.signals }), scratch, .{ .dispositions = value.dispositions, .signals = value.proposal.signals }),
        .conflicts => |value| try json.encode(Facts, scratch, .{ .dispositions = value.prior.dispositions, .signals = accepted_groups, .conflict_groups = conflict_catalogue }),
    };
    const values = std.json.parseFromSlice(std.json.Value, scratch, accepted, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidReferenceReconciliation;
    const with_facts = try packets.withJsonContext(a, selected, "accepted", values.value);
    defer packets.release(with_facts);
    // The definition and revision belong to this exact immutable assignment.
    const slot = try slotId(scratch, prior);
    const result = try packets.create(a, with_facts.body(), .{ .reference_global = .{ .reference_state_id = .{ .bytes = current.progress.plan.layout.items.state_id.bytes }, .unit_slot_id = .{ .bytes = slot } } }, .initial_generation, .{ .bytes = definition(stage) });
    defer packets.release(result);
    const witnessed = try packets.withOriginalSourceTexts(a, result, with_facts.originalSources());
    defer packets.release(witnessed);
    const prose = try packets.withProseFields(a, witnessed, with_facts.proseFields());
    defer packets.release(prose);
    const fields = try packets.withFieldPolicies(a, prose, with_facts.fieldPolicies());
    defer packets.release(fields);
    const inherited = try packets.withRestrictions(a, fields, selected.excludedVariants(), selected.integerChoices());
    if (prior == .signals) return inherited;
    defer packets.release(inherited);
    if (prior == .dispositions) return @import("reference_model_input.zig").withDispositionChoices(a, inherited, current.partition.group.claim_ids, null, true);
    const ids = try scratch.alloc(i64, conflict_catalogue.len);
    for (ids, conflict_catalogue) |*id, group| id.* = group.group_id.ordinal;
    return packets.withIntegerChoices(a, inherited, &.{.{ .target = .{ .path = &.{ .{ .property = "conflicts" }, .{ .items = {} }, .{ .property = "group_id" } } }, .definition = result.resultDefinition(), .allowed = ids }});
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
        .conflicts => |value| .{ .phase = value.prior.phase, .source = value.prior.source, .input = value.prior.input, .proposal = .{ .global = value.prior.proposal } },
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
            result.phase = if (result.proposal.global.conflicts.len > 0) .complete else .signals;
        },
        .conflicts => |v| {
            result.proposal.global.conflicts = try @import("reference_conflict_groups.zig").explain(a, prior.conflicts.prior.proposal.conflict_groups, v.conflicts);
            result.phase = .complete;
        },
    }
    var fields: std.ArrayList(r.diagnostic.FieldOrigin) = .empty;
    const unit: r.diagnostic.Unit = switch (stage) {
        .dispositions => .dispositions,
        .signals => .signals,
        .conflicts => .conflicts,
    };
    const field: r.diagnostic.Field = .record;
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
pub const Response = union(Stage) { dispositions: @import("reference_conflict_groups.zig").Selection, signals: struct { signals: []const @import("reference_reconciliation_projection.zig").SemanticSignal }, conflicts: struct { conflicts: []const @import("reference_conflict_groups.zig").Explanation } };

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
        .conflicts => |v| v.prior.source.revision,
    }, std.fmt.bytesToHex(digest.bytes, .lower) });
}

fn accepts(prior: Prior) bool {
    return switch (prior) {
        .dispositions => |v| v.purpose == .global,
        .signals => |v| v.phase == .dispositions,
        .conflicts => |v| v.prior.phase == .signals,
    };
}
