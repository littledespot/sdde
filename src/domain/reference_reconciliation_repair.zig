//! Native selection of one reconciliation repair. No model calls, continuation
//! policy, semantic survivor choice, or accepted-history mutation.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const d = r.diagnostic;
const v = @import("reference_reconciliation_validation.zig");
const context = @import("reference_reconciliation_context.zig");
const packets = @import("model_input_packet.zig");
pub const Target = union(enum) {
    statement_key: usize,
    statement_selection: usize,
    statement_content: usize,
    statement: usize,
    insert_statement: struct { index: usize, key: u32, claim: r.ClaimId },
    disposition: struct { index: usize, claim: r.ClaimId },
    disposition_record: usize,
    insert_disposition: struct { index: usize, claim: r.ClaimId },
    signal_selection: usize,
    signal_content: usize,
    signal: usize,
    insert_signal: struct { index: usize, claim: r.ClaimId },
    conflict_selection: usize,
    conflict_summary: usize,
    conflict: usize,
    insert_conflict: struct { index: usize, claims: []const r.ClaimId },
};
pub const Replacement = union(enum) {
    key: struct { local_key: u32 },
    selection: struct { claim_ids: []const r.ClaimId },
    content: r.ContentProposal,
    statement: r.StatementProposal,
    disposition: @FieldType(r.ClaimDispositionProposal, "disposition"),
    disposition_record: r.ClaimDispositionProposal,
    signal: r.SignalProposal,
    conflict: r.ConflictProposal,
    summary: r.text.ReferenceSemanticText,
    conflict_detail: struct { kind: r.ConflictKind, summary: r.text.ReferenceSemanticText },
};
pub const Rule = struct {
    validator: enum { reference_reconciliation_v1 } = .reference_reconciliation_v1,
    rejection: d.Rejection,
    requirement: []const u8,
    const Guidance = struct { validator: @FieldType(Rule, "validator"), rule: d.Rule, requirement: []const u8, expected: d.Fact, choices: d.Relations };
    pub fn guidance(self: Rule) Guidance {
        return .{ .validator = self.validator, .rule = self.rejection.issue.rule, .requirement = self.requirement, .expected = self.rejection.issue.expected, .choices = self.rejection.relations };
    }
};
const shared = @import("atomic_repair.zig");
const atomic = shared.Contract(Target, Replacement, context.Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = atomic.Error || r.Error;
pub const Block = d.RepairBlock;
pub const Decision = union(enum) { model: Authorization, automatic: struct { authorization: Authorization, replacement: ?Replacement }, blocked: Block };

pub fn authorize(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, rejection: d.Rejection) Error!Decision {
    try v.input(a, parsed.input);
    const facts = try context.capture(a, parsed, if (needsText(rejection.unit)) ctx else null);
    defer a.free(facts.lineage.history);
    if (!parsed.input.progress.plan.layout.items.state_id.eql(rejection.state_id) or parsed.input.partition.id.ordinal != rejection.partition_id.ordinal or parsed.source.revision != rejection.revision or
        !std.meta.eql(parsed.source.at(rejection.unit, d.fieldFor(rejection.unit, rejection.issue.rule)), rejection.origin) or
        !std.meta.eql(rejection.dependencies orelse return error.InvalidAtomicRepair, try shared.snapshot(context.Facts, a, facts))) return error.InvalidAtomicRepair;
    const rule: Rule = .{ .rejection = rejection, .requirement = switch (rejection.issue.expected) {
        .constraint => |constraint| constraint.description(),
        .text_issue => |issue| issue.description(),
        else => "Use only the supplied identities and preserve complete member coverage.",
    } };
    switch (rejection.unit) {
        .statement => |index| {
            if (parsed.proposal != .summary or index >= parsed.proposal.summary.statements.len) return error.InvalidAtomicRepair;
            if (rejection.relations.redundant) |redundant| return deletion(a, parsed, facts, .{ .statement = redundant }, rule);
            const target: Target = switch (rejection.issue.rule) {
                .local_key => .{ .statement_key = index },
                .claim_selection, .content, .typed_text => projectionTarget(.statement, index, rejection) orelse return .{ .blocked = .no_independent_target },
                else => return .{ .blocked = .no_independent_target },
            };
            return replace(a, parsed, facts, target, rule);
        },
        .summary => {
            if (parsed.proposal != .summary or rejection.issue.rule != .membership) return .{ .blocked = .no_independent_target };
            const statements = parsed.proposal.summary.statements;
            if (rejection.relations.redundant) |index| return deletion(a, parsed, facts, .{ .statement = index }, rule);
            if (rejection.relations.competing) return .{ .blocked = .competing_entries };
            for (parsed.input.partition.group.claim_ids) |id| {
                for (statements) |statement| {
                    if (r.contains(r.ClaimId, statement.claim_ids, id)) break;
                } else {
                    var key: u32 = 1;
                    key_search: while (true) {
                        for (statements) |statement| if (statement.local_key == key) {
                            key = try r.next(key);
                            continue :key_search;
                        };
                        break;
                    }
                    const selected = try insertion(a, parsed, facts, .{ .insert_statement = .{ .index = statements.len, .key = key, .claim = id } }, .content, rule);
                    const item = try r.item(parsed.input.progress.plan.layout.items, id);
                    if (item.claim.content == .preserved_token) return .{ .automatic = .{ .authorization = selected.model, .replacement = .{ .content = .{ .preserved_token = .{ .token_id = item.claim.content.preserved_token.value.id } } } } };
                    return selected;
                }
            }
            return .{ .blocked = .no_required_member };
        },
        .dispositions, .disposition => {
            if (parsed.proposal != .global) return error.InvalidAtomicRepair;
            const values = parsed.proposal.global.claim_dispositions;
            if (rejection.relations.redundant) |index| return deletion(a, parsed, facts, .{ .disposition_record = index }, rule);
            if (rejection.relations.competing) return .{ .blocked = .competing_entries };
            var missing: ?r.ClaimId = null;
            for (parsed.input.partition.group.claim_ids) |id| {
                for (values) |value| {
                    if (value.claim_id.ordinal == id.ordinal) break;
                } else {
                    missing = id;
                    break;
                }
            }
            for (values, 0..) |value, index| if (!r.contains(r.ClaimId, parsed.input.partition.group.claim_ids, value.claim_id)) {
                return if (missing) |id| replace(a, parsed, facts, .{ .disposition = .{ .index = index, .claim = id } }, rule) else .{ .blocked = .no_independent_target };
            };
            if (missing) |id| return insertion(a, parsed, facts, .{ .insert_disposition = .{ .index = values.len, .claim = id } }, .disposition, rule);
            if (rejection.unit != .disposition or rejection.unit.disposition >= values.len) return .{ .blocked = .no_independent_target };
            const index = rejection.unit.disposition;
            return replace(a, parsed, facts, .{ .disposition = .{ .index = index, .claim = values[index].claim_id } }, rule);
        },
        .signal => |index| {
            if (parsed.proposal != .global or index >= parsed.proposal.global.signals.len) return error.InvalidAtomicRepair;
            if (rejection.issue.rule == .duplicate_signal) {
                if (rejection.relations.redundant) |redundant| return deletion(a, parsed, facts, .{ .signal = redundant }, rule);
                return .{ .blocked = .competing_entries };
            }
            return replace(a, parsed, facts, switch (rejection.issue.rule) {
                .content, .typed_text, .claim_selection, .relationship => projectionTarget(.signal, index, rejection) orelse return .{ .blocked = .no_independent_target },
                else => return .{ .blocked = .no_independent_target },
            }, rule);
        },
        .signals => {
            if (parsed.proposal != .global or rejection.issue.rule != .signal_coverage or rejection.issue.observed != .disposition) return .{ .blocked = .no_independent_target };
            const id = rejection.issue.observed.disposition.claim_id;
            const item = try r.item(parsed.input.progress.plan.layout.items, id);
            const target: Target = .{ .insert_signal = .{ .index = parsed.proposal.global.signals.len, .claim = id } };
            const selected = try insertion(a, parsed, facts, target, .content, rule);
            if (item.claim.content == .preserved_token) return .{ .automatic = .{ .authorization = selected.model, .replacement = .{ .content = .{ .preserved_token = .{ .token_id = item.claim.content.preserved_token.value.id } } } } };
            return selected;
        },
        .conflict => |index| {
            if (parsed.proposal != .global or index >= parsed.proposal.global.conflicts.len) return error.InvalidAtomicRepair;
            if (rejection.issue.rule == .duplicate_conflict) {
                if (rejection.relations.redundant) |redundant| return deletion(a, parsed, facts, .{ .conflict = redundant }, rule);
                return .{ .blocked = .competing_entries };
            }
            if (rejection.issue.rule != .typed_text and rejection.relations.conflicting_pairs.len == 0) return .{ .blocked = .no_independent_target };
            return replace(a, parsed, facts, if (rejection.issue.rule == .typed_text) .{ .conflict_summary = index } else .{ .conflict_selection = index }, rule);
        },
        .conflicts => {
            if (parsed.proposal != .global or rejection.issue.rule != .conflict_coverage or rejection.issue.observed != .disposition) return .{ .blocked = .no_independent_target };
            const disposition = rejection.issue.observed.disposition;
            if (disposition.disposition != .conflicting) return .{ .blocked = .no_independent_target };
            for (disposition.related_claim_ids) |related| {
                for (parsed.proposal.global.conflicts) |conflict| {
                    if (r.contains(r.ClaimId, conflict.claim_ids, disposition.claim_id) and r.contains(r.ClaimId, conflict.claim_ids, related)) break;
                } else return insertion(a, parsed, facts, .{ .insert_conflict = .{ .index = parsed.proposal.global.conflicts.len, .claims = try a.dupe(r.ClaimId, &.{ disposition.claim_id, related }) } }, .conflict_detail, rule);
            }
            return .{ .blocked = .no_required_member };
        },
    }
}
/// Summaries and signals share one independent-field selection policy. Native
/// compatibility facts stay in validation; only this owner chooses a write.
fn projectionTarget(kind: enum { statement, signal }, index: usize, rejection: d.Rejection) ?Target {
    if ((rejection.issue.rule == .content or rejection.issue.rule == .typed_text) and rejection.relations.content != null)
        return switch (kind) {
            .statement => .{ .statement_content = index },
            .signal => .{ .signal_content = index },
        };
    if (rejection.relations.selection.len == 0) return null;
    return switch (kind) {
        .statement => .{ .statement_selection = index },
        .signal => .{ .signal_selection = index },
    };
}

fn replace(a: std.mem.Allocator, parsed: r.Parsed, facts: context.Facts, target: Target, rule: Rule) Error!Decision {
    return .{ .model = try atomic.authorize(a, try owner(a, parsed), parsed.source.revision, target, (try select(parsed, target)) orelse return error.InvalidAtomicRepair, facts, rule) };
}
fn insertion(a: std.mem.Allocator, parsed: r.Parsed, facts: context.Facts, target: Target, kind: std.meta.Tag(Replacement), rule: Rule) Error!Decision {
    if (try select(parsed, target) != null) return error.InvalidAtomicRepair;
    return .{ .model = try atomic.authorizeInsert(a, try owner(a, parsed), parsed.source.revision, target, kind, facts, rule) };
}
fn deletion(a: std.mem.Allocator, parsed: r.Parsed, facts: context.Facts, target: Target, rule: Rule) Error!Decision {
    return .{ .automatic = .{ .authorization = try atomic.authorizeDelete(a, try owner(a, parsed), parsed.source.revision, target, (try select(parsed, target)) orelse return error.InvalidAtomicRepair, facts, rule), .replacement = null } };
}
pub fn packet(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, authorization: Authorization) Error!*packets.Packet {
    const base = try @import("reference_model_input.zig").reconciliationPacket(a, parsed.input, ctx.inputs, ctx.registry);
    defer packets.release(base);
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    try atomic.checkDependencies(scratch, authorization, try context.capture(scratch, parsed, if (needsText(authorization.rule.rejection.unit)) ctx else null));
    const contextual = try packets.withContext(@FieldType(r.Parsed, "proposal"), a, base, "candidate", parsed.proposal);
    defer packets.release(contextual);
    const kind = switch (authorization.operation) {
        .replace => |value| std.meta.activeTag(value),
        .insert => |kind| kind,
        .delete => return error.InvalidAtomicRepair,
    };
    const definition = try std.fmt.allocPrint(scratch, "repair_{s}", .{@tagName(kind)});
    return atomic.packet(a, authorization, contextual, .{ .bytes = definition });
}
pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
    return atomic.parse(a, authorization, input, bytes);
}
pub fn merge(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, authorization: Authorization, proposed_replacement: ?Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!r.Parsed {
    const replacement = if (proposed_replacement) |value| try atomic.copyReplacement(a, value) else null;
    try v.input(a, parsed.input);
    const facts = try context.capture(a, parsed, if (needsText(authorization.rule.rejection.unit)) ctx else null);
    defer a.free(facts.lineage.history);
    const target = authorization.target;
    const merged = try atomic.checkMerge(a, try owner(a, parsed), parsed.source.revision, try select(parsed, target), facts, authorization, replacement, origin);
    var result = parsed;
    if (parsed.proposal == .summary) {
        var statements: std.ArrayList(r.StatementProposal) = .empty;
        try statements.appendSlice(a, parsed.proposal.summary.statements);
        switch (target) {
            .statement_key => |index| statements.items[index].local_key = replacement.?.key.local_key,
            .statement_selection => |index| statements.items[index].claim_ids = replacement.?.selection.claim_ids,
            .statement_content => |index| statements.items[index].content = replacement.?.content,
            .statement => |index| {
                _ = statements.orderedRemove(index);
            },
            .insert_statement => |value| try statements.insert(a, value.index, .{ .local_key = value.key, .claim_ids = try a.dupe(r.ClaimId, &.{value.claim}), .content = replacement.?.content }),
            else => return error.InvalidAtomicRepair,
        }
        result.proposal = .{ .summary = .{ .statements = try statements.toOwnedSlice(a) } };
    } else {
        var global = parsed.proposal.global;
        switch (target) {
            .disposition, .disposition_record, .insert_disposition => {
                var values: std.ArrayList(r.ClaimDispositionProposal) = .empty;
                try values.appendSlice(a, global.claim_dispositions);
                switch (target) {
                    .disposition => |value| values.items[value.index] = .{ .claim_id = value.claim, .disposition = replacement.?.disposition },
                    .disposition_record => |index| {
                        _ = values.orderedRemove(index);
                    },
                    .insert_disposition => |value| try values.insert(a, value.index, .{ .claim_id = value.claim, .disposition = replacement.?.disposition }),
                    else => unreachable,
                }
                global.claim_dispositions = try values.toOwnedSlice(a);
            },
            .signal_selection, .signal_content, .signal, .insert_signal => {
                var values: std.ArrayList(r.SignalProposal) = .empty;
                try values.appendSlice(a, global.signals);
                switch (target) {
                    .signal_selection => |index| values.items[index].claim_ids = replacement.?.selection.claim_ids,
                    .signal_content => |index| values.items[index].content = replacement.?.content,
                    .signal => |index| {
                        _ = values.orderedRemove(index);
                    },
                    .insert_signal => |value| try values.insert(a, value.index, .{ .claim_ids = try a.dupe(r.ClaimId, &.{value.claim}), .content = replacement.?.content }),
                    else => unreachable,
                }
                global.signals = try values.toOwnedSlice(a);
            },
            .conflict_selection, .conflict_summary, .conflict, .insert_conflict => {
                var values: std.ArrayList(r.ConflictProposal) = .empty;
                try values.appendSlice(a, global.conflicts);
                switch (target) {
                    .conflict_selection => |index| values.items[index].claim_ids = replacement.?.selection.claim_ids,
                    .conflict_summary => |index| values.items[index].summary = replacement.?.summary,
                    .conflict => |index| {
                        _ = values.orderedRemove(index);
                    },
                    .insert_conflict => |value| try values.insert(a, value.index, .{ .claim_ids = try a.dupe(r.ClaimId, value.claims), .summary = replacement.?.conflict_detail.summary, .kind = replacement.?.conflict_detail.kind, .resolution = .unresolved }),
                    else => unreachable,
                }
                global.conflicts = try values.toOwnedSlice(a);
            },
            else => return error.InvalidAtomicRepair,
        }
        result.proposal = .{ .global = global };
    }
    result.source = try origins(a, parsed.source, target, authorization.operation == .delete, origin);
    result.source.revision = merged.revision_after;
    result.source.last_repair = merged;
    return result;
}
fn select(parsed: r.Parsed, target: Target) Error!?Replacement {
    const summary = parsed.proposal == .summary;
    return switch (target) {
        .statement_key, .statement_selection, .statement_content, .statement => |index| if (summary and index < parsed.proposal.summary.statements.len) switch (target) {
            .statement_key => .{ .key = .{ .local_key = parsed.proposal.summary.statements[index].local_key } },
            .statement_selection => .{ .selection = .{ .claim_ids = parsed.proposal.summary.statements[index].claim_ids } },
            .statement_content => .{ .content = parsed.proposal.summary.statements[index].content },
            .statement => .{ .statement = parsed.proposal.summary.statements[index] },
            else => unreachable,
        } else error.InvalidAtomicRepair,
        .insert_statement => |value| if (summary and value.index == parsed.proposal.summary.statements.len) null else error.InvalidAtomicRepair,
        .disposition => |value| if (!summary and value.index < parsed.proposal.global.claim_dispositions.len) .{ .disposition = parsed.proposal.global.claim_dispositions[value.index].disposition } else error.InvalidAtomicRepair,
        .disposition_record => |index| if (!summary and index < parsed.proposal.global.claim_dispositions.len) .{ .disposition_record = parsed.proposal.global.claim_dispositions[index] } else error.InvalidAtomicRepair,
        .insert_disposition => |value| if (!summary and value.index == parsed.proposal.global.claim_dispositions.len) null else error.InvalidAtomicRepair,
        .signal_selection, .signal_content, .signal => |index| if (!summary and index < parsed.proposal.global.signals.len) switch (target) {
            .signal_selection => .{ .selection = .{ .claim_ids = parsed.proposal.global.signals[index].claim_ids } },
            .signal_content => .{ .content = parsed.proposal.global.signals[index].content },
            .signal => .{ .signal = parsed.proposal.global.signals[index] },
            else => unreachable,
        } else error.InvalidAtomicRepair,
        .insert_signal => |value| if (!summary and value.index == parsed.proposal.global.signals.len) null else error.InvalidAtomicRepair,
        .conflict_selection, .conflict_summary, .conflict => |index| if (!summary and index < parsed.proposal.global.conflicts.len) switch (target) {
            .conflict_selection => .{ .selection = .{ .claim_ids = parsed.proposal.global.conflicts[index].claim_ids } },
            .conflict_summary => .{ .summary = parsed.proposal.global.conflicts[index].summary },
            .conflict => .{ .conflict = parsed.proposal.global.conflicts[index] },
            else => unreachable,
        } else error.InvalidAtomicRepair,
        .insert_conflict => |value| if (!summary and value.index == parsed.proposal.global.conflicts.len) null else error.InvalidAtomicRepair,
    };
}
fn owner(a: std.mem.Allocator, parsed: r.Parsed) Error!@import("model_request_identity.zig").ImmutableUnitOwnerId {
    return .{ .reference_global = .{ .reference_state_id = .{ .bytes = parsed.input.progress.plan.layout.items.state_id.bytes }, .unit_slot_id = .{ .bytes = try std.fmt.allocPrint(a, "reconciliation-{d}", .{parsed.input.partition.id.ordinal}) } } };
}
fn needsText(unit: d.Unit) bool {
    return switch (unit) {
        .dispositions, .disposition => false,
        else => true,
    };
}
fn targetOrigin(target: Target) struct { unit: d.Unit, field: d.Field } {
    return switch (target) {
        .statement_key => |i| .{ .unit = .{ .statement = i }, .field = .key },
        .statement_selection => |i| .{ .unit = .{ .statement = i }, .field = .selections },
        .statement_content => |i| .{ .unit = .{ .statement = i }, .field = .content },
        .statement => |i| .{ .unit = .{ .statement = i }, .field = .record },
        .insert_statement => |value| .{ .unit = .{ .statement = value.index }, .field = .record },
        .disposition => |value| .{ .unit = .{ .disposition = value.index }, .field = .record },
        .disposition_record => |i| .{ .unit = .{ .disposition = i }, .field = .record },
        .insert_disposition => |value| .{ .unit = .{ .disposition = value.index }, .field = .record },
        .signal_selection => |i| .{ .unit = .{ .signal = i }, .field = .selections },
        .signal_content => |i| .{ .unit = .{ .signal = i }, .field = .content },
        .signal => |i| .{ .unit = .{ .signal = i }, .field = .record },
        .insert_signal => |value| .{ .unit = .{ .signal = value.index }, .field = .record },
        .conflict_selection => |i| .{ .unit = .{ .conflict = i }, .field = .selections },
        .conflict_summary => |i| .{ .unit = .{ .conflict = i }, .field = .content },
        .conflict => |i| .{ .unit = .{ .conflict = i }, .field = .record },
        .insert_conflict => |value| .{ .unit = .{ .conflict = value.index }, .field = .record },
    };
}
fn origins(a: std.mem.Allocator, source: d.Source, target: Target, deleted: bool, origin: ?@import("model_candidate_origin.zig").Origin) Error!d.Source {
    const changed = targetOrigin(target);
    var fields: std.ArrayList(d.FieldOrigin) = .empty;
    for (source.fields) |entry| {
        var retained = entry;
        if (std.meta.activeTag(entry.unit) == std.meta.activeTag(changed.unit)) {
            switch (changed.unit) {
                inline .statement, .disposition, .signal, .conflict => |index, tag| {
                    const old = @field(entry.unit, @tagName(tag));
                    if (old == index and (deleted or changed.field == .record or entry.field == changed.field)) continue;
                    if (deleted and old > index) retained.unit = @unionInit(d.Unit, @tagName(tag), old - 1);
                },
                else => unreachable,
            }
        }
        try fields.append(a, retained);
    }
    if (!deleted) try fields.append(a, .{ .unit = changed.unit, .field = changed.field, .origin = origin });
    return .{ .revision = source.revision, .origin = source.origin, .fields = try fields.toOwnedSlice(a) };
}
