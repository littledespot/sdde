//! Native selection of one reconciliation repair. No model calls, continuation
//! policy, semantic survivor choice, or accepted-history mutation.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const d = r.diagnostic;
const v = @import("reference_reconciliation_validation.zig");
const context = @import("reference_reconciliation_context.zig");
const dispositions = @import("reference_disposition_validation.zig");
const packets = @import("model_input_packet.zig");
pub const Target = union(enum) {
    statement_selection: usize,
    statement_content: usize,
    statement: usize,
    insert_statement: struct { index: usize, claim: r.ClaimId },
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

    const Guidance = struct { unit: std.meta.Tag(Target), index: ?usize = null, claim: ?r.ClaimId = null, claims: ?[]const r.ClaimId = null };
    pub fn guidance(self: Target) Guidance {
        var result: Guidance = .{ .unit = std.meta.activeTag(self) };
        switch (self) {
            inline .insert_statement, .disposition, .insert_disposition, .insert_signal => |value| result.claim = value.claim,
            .insert_conflict => |value| result.claims = value.claims,
            inline else => |index| result.index = index,
        }
        return result;
    }
};
pub const Replacement = union(enum) {
    selection: struct { claim_ids: []const r.ClaimId },
    content: r.ContentProposal,
    statement: r.StatementProposal,
    disposition: @FieldType(r.ClaimDispositionProposal, "disposition"),
    disposition_record: r.ClaimDispositionProposal,
    signal: r.SignalProposal,
    conflict: r.ConflictProposal,
    summary: r.text.ReferenceSemanticText,
    conflict_detail: struct { kind: r.ConflictKind, summary: r.text.ReferenceSemanticText },
    conflict_group: ConflictGroup,
};
pub const ConflictGroup = struct { conflict_groups: []const @import("reference_conflict_groups.zig").Group = &.{}, claim_dispositions: []const r.ClaimDispositionProposal, conflicts: []const r.ConflictProposal };
pub const Rule = struct {
    rejection: d.Rejection,
    requirement: []const u8,
    disposition_choices: ?dispositions.RepairChoices = null,
    const Guidance = struct {
        rule: d.Rule,
        /// Diagnostic about the rejected candidate, not replacement scope.
        /// The authorized target and input constraints govern the repair.
        failed_requirement: ?[]const u8,
        expected: ?d.Fact,
        content: ?d.ContentKind,
        selection: ?[]const r.ClaimId,
        conflicting_pairs: ?@FieldType(d.Relations, "conflicting_pairs"),
        disposition_choices: ?dispositions.RepairChoices,
    };
    pub fn guidance(self: Rule) Guidance {
        const expected = self.rejection.issue.expected;
        const relations = self.rejection.relations;
        return .{
            .rule = self.rejection.issue.rule,
            .failed_requirement = if (self.disposition_choices == null and (expected == .constraint or expected == .text_issue)) self.requirement else null,
            .expected = if (expected == .count or expected == .constraint) null else expected,
            .content = relations.content,
            .selection = if (relations.selection.len == 0) null else relations.selection,
            .conflicting_pairs = if (relations.conflicting_pairs.len == 0) null else relations.conflicting_pairs,
            .disposition_choices = self.disposition_choices,
        };
    }
};
const shared = @import("atomic_repair.zig");
const atomic = shared.Contract(Target, Replacement, context.Facts, Rule);
pub const Authorization = atomic.Authorization;
pub const Error = atomic.Error || r.Error;
pub const Block = d.RepairBlock;
pub const Decision = union(enum) { model: Authorization, automatic: struct { authorization: Authorization, replacement: ?Replacement }, blocked: Block };
const occurrences = @import("repair_occurrences.zig");
const Family = enum { selection, content, disposition, membership, coverage, duplicate };
const StableTarget = union(enum) {
    statement: occurrences.Id,
    disposition: r.ClaimId,
    disposition_occurrence: occurrences.Id,
    signal: occurrences.Id,
    conflict: occurrences.Id,
    missing_statement: r.ClaimId,
    missing_signal: r.ClaimId,
    missing_conflict: []const r.ClaimId,
};
pub const ObservationTarget = struct { selected: Target, stable: StableTarget, rule: d.Rule, operation: enum { replace, insert, delete } };

fn stableTarget(a: std.mem.Allocator, source: d.Source, proposal: @FieldType(r.Parsed, "proposal"), target: Target) Error!StableTarget {
    return switch (target) {
        .statement_selection, .statement_content, .statement => |index| .{ .statement = source.statements.at(index, proposal.summary.statements.len) catch return error.InvalidAtomicRepair },
        .disposition => |value| .{ .disposition = value.claim },
        .disposition_record => |index| .{ .disposition_occurrence = source.dispositions.at(index, proposal.global.claim_dispositions.len) catch return error.InvalidAtomicRepair },
        .insert_disposition => |value| .{ .disposition = value.claim },
        .signal_selection, .signal_content, .signal => |index| .{ .signal = source.signals.at(index, proposal.global.signals.len) catch return error.InvalidAtomicRepair },
        .conflict_selection, .conflict_summary, .conflict => |index| .{ .conflict = source.conflicts.at(index, proposal.global.conflicts.len) catch return error.InvalidAtomicRepair },
        .insert_statement => |value| .{ .missing_statement = value.claim },
        .insert_signal => |value| .{ .missing_signal = value.claim },
        .insert_conflict => |value| blk: {
            if (value.claims.len < 2) return error.InvalidAtomicRepair;
            const members = try a.dupe(r.ClaimId, value.claims);
            std.mem.sort(r.ClaimId, members, {}, struct {
                fn less(_: void, left: r.ClaimId, right: r.ClaimId) bool {
                    return left.ordinal < right.ordinal;
                }
            }.less);
            break :blk .{ .missing_conflict = members };
        },
    };
}

pub fn retryPermit(a: std.mem.Allocator, authorization: Authorization) Error!@import("workflow_retry.zig").Permit {
    const facts = authorization.dependencies;
    const source = facts.source;
    const proposal = facts.proposal;
    const existing = if (proposal == .summary) proposal.summary.statements.len else count: {
        const records = proposal.global;
        const first = std.math.add(usize, records.claim_dispositions.len, records.signals.len) catch return error.InvalidAtomicRepair;
        break :count std.math.add(usize, first, records.conflicts.len) catch return error.InvalidAtomicRepair;
    };
    const claims = facts.partition.group.claim_ids.len;
    const pairs = std.math.mul(usize, claims, claims -| 1) catch return error.InvalidAtomicRepair;
    const linear = std.math.mul(usize, claims, 3) catch return error.InvalidAtomicRepair;
    const additions = std.math.add(usize, linear, pairs / 2) catch return error.InvalidAtomicRepair;
    const subjects = std.math.add(usize, existing, additions) catch return error.InvalidAtomicRepair;
    const maximum = std.math.mul(usize, subjects, std.meta.tags(Family).len) catch return error.InvalidAtomicRepair;
    const family: Family = switch (authorization.target) {
        .statement_selection, .signal_selection, .conflict_selection => .selection,
        .statement_content, .signal_content, .conflict_summary => .content,
        .disposition, .insert_disposition => .disposition,
        .statement, .signal, .conflict, .disposition_record => .duplicate,
        .insert_statement => .membership,
        .insert_signal, .insert_conflict => .coverage,
    };
    var permit = try shared.permit(StableTarget, Family, a, authorization.owner, try stableTarget(a, source, proposal, authorization.target), family, authorization.id, authorization.revision, std.math.cast(u32, maximum) orelse return error.InvalidAtomicRepair);
    const scope = .{ .boundary = permit.key.scope, .origin = source.origin, .collections = .{
        source.at(.summary, .record), source.at(.dispositions, .record), source.at(.signals, .record), source.at(.conflicts, .record),
    } };
    permit.key.scope = (try shared.snapshot(@TypeOf(scope), a, scope)).bytes;
    if (source.last_repair) |prior| if (prior.retry) |previous| if (std.mem.eql(u8, &previous.key.scope, &permit.key.scope)) {
        permit.maximum_targets = previous.maximum_targets;
    };
    return permit;
}

fn withRetry(a: std.mem.Allocator, authorization: Authorization) Error!Authorization {
    var result = authorization;
    result.retry = try retryPermit(a, result);
    return result;
}

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
                .claim_selection, .content, .typed_text => projectionTarget(.statement, index, rejection) orelse return .{ .blocked = .no_independent_target },
                else => return .{ .blocked = .no_independent_target },
            };
            return replace(a, parsed, facts, target, rule);
        },
        .summary => {
            if (parsed.proposal != .summary or rejection.issue.rule != .membership) return .{ .blocked = .no_independent_target };
            const statements = parsed.proposal.summary.statements;
            for (parsed.input.partition.group.claim_ids) |id| {
                for (statements) |statement| {
                    if (r.contains(r.ClaimId, statement.claim_ids, id)) break;
                } else {
                    const selected = try insertion(a, parsed, facts, .{ .insert_statement = .{ .index = statements.len, .claim = id } }, .content, rule);
                    const item = try r.item(parsed.input.progress.plan.layout.items, id);
                    if (item.claim.content == .preserved_token) return .{ .automatic = .{ .authorization = selected.model, .replacement = .{ .content = try @import("reference_reconciliation_projection.zig").token(item) } } };
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
            if (rejection.relations.redundant) |redundant| return deletion(a, parsed, facts, .{ .signal = redundant }, rule);
            if (rejection.issue.rule == .duplicate_signal) {
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
            if (item.claim.content == .preserved_token) return .{ .automatic = .{ .authorization = selected.model, .replacement = .{ .content = try @import("reference_reconciliation_projection.zig").token(item) } } };
            return selected;
        },
        .conflict => |index| {
            if (parsed.proposal != .global or index >= parsed.proposal.global.conflicts.len) return error.InvalidAtomicRepair;
            if (rejection.issue.rule == .duplicate_conflict) {
                if (rejection.relations.redundant) |redundant| return deletion(a, parsed, facts, .{ .conflict = redundant }, rule);
                return .{ .blocked = .competing_entries };
            }
            if (rejection.issue.rule != .typed_text and (rejection.relations.conflicting_pairs.len == 0 or parsed.proposal.global.conflict_groups.len == 0)) return .{ .blocked = .no_independent_target };
            return replace(a, parsed, facts, if (rejection.issue.rule == .typed_text) .{ .conflict_summary = index } else .{ .conflict_selection = index }, rule);
        },
        .conflicts => {
            if (parsed.proposal != .global or rejection.issue.rule != .conflict_coverage) return .{ .blocked = .no_independent_target };
            if (rejection.issue.observed == .claims) return insertion(a, parsed, facts, .{ .insert_conflict = .{ .index = parsed.proposal.global.conflicts.len, .claims = try a.dupe(r.ClaimId, rejection.issue.observed.claims) } }, .conflict_detail, rule);
            if (rejection.issue.observed != .disposition) return .{ .blocked = .no_independent_target };
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
    var bound_rule = rule;
    bound_rule.disposition_choices = try dispositionChoices(a, parsed, target);
    if (rule.rejection.relations.content) |content| if (content == .preserved_token and (target == .statement_content or target == .signal_content)) {
        return .{ .automatic = .{ .authorization = try withRetry(a, try atomic.authorize(a, try owner(a, parsed), parsed.source.revision, target, (try select(parsed, target)) orelse return error.InvalidAtomicRepair, facts, bound_rule)), .replacement = .{ .content = .{ .preserved_token = content.preserved_token } } } };
    };
    return .{ .model = try withRetry(a, try atomic.authorize(a, try owner(a, parsed), parsed.source.revision, target, (try select(parsed, target)) orelse return error.InvalidAtomicRepair, facts, bound_rule)) };
}
fn insertion(a: std.mem.Allocator, parsed: r.Parsed, facts: context.Facts, target: Target, kind: std.meta.Tag(Replacement), rule: Rule) Error!Decision {
    if (try select(parsed, target) != null) return error.InvalidAtomicRepair;
    var bound_rule = rule;
    bound_rule.disposition_choices = try dispositionChoices(a, parsed, target);
    if (kind == .content) {
        const claim = switch (target) {
            inline .insert_statement, .insert_signal => |value| value.claim,
            else => return error.InvalidAtomicRepair,
        };
        bound_rule.rejection.relations.content = (try v.selectedKind(parsed.input.progress.plan.layout.items, &.{claim})) orelse return error.InvalidAtomicRepair;
    }
    return .{ .model = try withRetry(a, try atomic.authorizeInsert(a, try owner(a, parsed), parsed.source.revision, target, kind, facts, bound_rule)) };
}
fn deletion(a: std.mem.Allocator, parsed: r.Parsed, facts: context.Facts, target: Target, rule: Rule) Error!Decision {
    return .{ .automatic = .{ .authorization = try withRetry(a, try atomic.authorizeDelete(a, try owner(a, parsed), parsed.source.revision, target, (try select(parsed, target)) orelse return error.InvalidAtomicRepair, facts, rule)), .replacement = null } };
}
pub fn packet(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, authorization: Authorization) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    try atomic.checkDependencies(scratch, authorization, try context.capture(scratch, parsed, if (needsText(authorization.rule.rejection.unit)) ctx else null));
    const kind = switch (authorization.operation) {
        .replace => |value| std.meta.activeTag(value),
        .insert => |kind| kind,
        .delete => return error.InvalidAtomicRepair,
    };
    const scope: d.Constraint.Scope = switch (kind) {
        .selection => .{ .selection = switch (authorization.target) {
            .statement_selection => .statement,
            .signal_selection => .signal,
            .conflict_selection => .conflict,
            else => return error.InvalidAtomicRepair,
        } },
        .content => .{ .content = authorization.rule.rejection.relations.content orelse return error.InvalidAtomicRepair },
        .disposition => .{ .disposition = if (authorization.rule.disposition_choices == null) .rules else .choices },
        .summary => .summary,
        .conflict_detail => .conflict_detail,
        .statement, .disposition_record, .signal, .conflict, .conflict_group => return error.InvalidAtomicRepair,
    };
    const base = try @import("reference_model_input.zig").reconciliationPacket(a, parsed.input, ctx.inputs, ctx.registry, scope);
    defer packets.release(base);
    const contextual = if (authorization.target == .conflict_selection)
        try packets.withContext([]const @import("reference_conflict_groups.zig").CatalogueEntry, a, base, "accepted_conflict_groups", try @import("reference_conflict_groups.zig").catalogue(scratch, parsed.proposal.global.conflict_groups))
    else
        try packets.withContext(@FieldType(r.Parsed, "proposal"), a, base, "candidate", parsed.proposal);
    defer packets.release(contextual);
    const definition = if (authorization.target == .conflict_selection) "repair_conflict_selection" else if (scope == .content) switch (scope.content) {
        .model => |model| switch (model) {
            .business, .scope_guard => "business_text",
            .design, .technical, .validation, .implementation_assumption, .open_question => "reference_text",
        },
        .preserved_token => return error.InvalidAtomicRepair,
    } else try std.fmt.allocPrint(scratch, "repair_{s}", .{@tagName(kind)});
    const prepared_input = try atomic.packet(a, authorization, contextual, .{ .bytes = definition }, parsed.source.at(targetOrigin(authorization.target).unit, targetOrigin(authorization.target).field));
    if (kind == .disposition) {
        defer packets.release(prepared_input);
        return @import("reference_model_input.zig").withDispositionChoices(a, prepared_input, parsed.input.partition.group.claim_ids, authorization.rule.disposition_choices, false);
    }
    if (kind != .selection) return prepared_input;
    defer packets.release(prepared_input);
    const groups = @import("reference_conflict_groups.zig");
    const ids = if (authorization.target == .conflict_selection) group_ids: {
        const catalogue = try groups.catalogue(scratch, parsed.proposal.global.conflict_groups);
        const values = try scratch.alloc(i64, catalogue.len);
        for (values, catalogue) |*id, group| id.* = group.group_id.ordinal;
        break :group_ids values;
    } else selections: {
        const values = try scratch.alloc(i64, authorization.rule.rejection.relations.selection.len);
        for (values, authorization.rule.rejection.relations.selection) |*id, claim| id.* = claim.ordinal;
        break :selections values;
    };
    return packets.withIntegerChoices(a, prepared_input, &.{.{
        .target = .{ .path = &.{.{ .property = if (authorization.target == .conflict_selection) "group_id" else "claim_ids" }} },
        .definition = .{ .bytes = definition },
        .allowed = ids,
        .collection = if (authorization.target == .conflict_selection) .sequence else .unique_subset,
    }});
}
pub fn parse(a: std.mem.Allocator, authorization: Authorization, input: *const packets.Packet, bytes: []const u8) Error!Replacement {
    const kind = try atomic.checkRequest(authorization, input);
    if (authorization.target == .conflict_selection) {
        const selection = try @import("model_candidate_json.zig").decode(struct { group_id: @import("reference_conflict_groups.zig").Id }, a, bytes);
        return .{ .selection = .{ .claim_ids = try a.dupe(r.ClaimId, @import("reference_conflict_groups.zig").members(authorization.dependencies.proposal.global.conflict_groups, selection.group_id)) } };
    }
    if (kind == .disposition) return .{ .disposition = try @import("reference_conflict_groups.zig").disposition(a, try @import("model_candidate_json.zig").decode(@import("reference_conflict_groups.zig").SemanticDisposition, a, bytes), authorization.rule.disposition_choices) };
    if (kind == .content) {
        const json = @import("model_candidate_json.zig");
        return .{ .content = switch (authorization.rule.rejection.relations.content orelse return error.InvalidAtomicRepair) {
            .model => |content_kind| .{ .model = try json.decodeSelected(@FieldType(r.ContentProposal, "model"), a, content_kind, bytes) },
            .preserved_token => return error.InvalidAtomicRepair,
        } };
    }
    return atomic.parse(a, authorization, input, bytes);
}

fn dispositionChoices(a: std.mem.Allocator, parsed: r.Parsed, target: Target) Error!?dispositions.RepairChoices {
    return switch (target) {
        inline .disposition, .insert_disposition => |value| dispositions.repairChoices(a, parsed.input.progress.plan.layout.items, parsed.proposal.global.claim_dispositions, value.index, value.claim),
        else => null,
    };
}
pub fn merge(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, authorization: Authorization, proposed_replacement: ?Replacement, origin: ?@import("model_candidate_origin.zig").Origin) Error!r.Parsed {
    const replacement = if (proposed_replacement) |value| try atomic.copyReplacement(a, value) else null;
    try v.input(a, parsed.input);
    const facts = try context.capture(a, parsed, if (needsText(authorization.rule.rejection.unit)) ctx else null);
    defer a.free(facts.lineage.history);
    const target = authorization.target;
    const merged = try atomic.checkMerge(a, try owner(a, parsed), parsed.source.revision, try select(parsed, target), facts, authorization, replacement, origin);
    var result = try apply(a, parsed, target, replacement, merged, origin);
    if (authorization.retry) |permit| result.source.pending_repair = .{ .permit = permit, .target = .{
        .selected = if (target == .insert_conflict) .{ .insert_conflict = .{ .index = target.insert_conflict.index, .claims = try a.dupe(r.ClaimId, target.insert_conflict.claims) } } else target,
        .stable = try stableTarget(a, parsed.source, parsed.proposal, target),
        .rule = authorization.rule.rejection.issue.rule,
        .operation = switch (authorization.operation) {
            .replace => .replace,
            .insert => .insert,
            .delete => .delete,
        },
    } };
    return result;
}
fn apply(a: std.mem.Allocator, parsed: r.Parsed, target: Target, replacement: ?Replacement, merged: shared.Merge, origin: ?@import("model_candidate_origin.zig").Origin) Error!r.Parsed {
    var result = parsed;
    if (parsed.proposal == .summary) {
        var statements: std.ArrayList(r.StatementProposal) = .empty;
        try statements.appendSlice(a, parsed.proposal.summary.statements);
        switch (target) {
            .statement_selection => |index| statements.items[index].claim_ids = replacement.?.selection.claim_ids,
            .statement_content => |index| statements.items[index].content = replacement.?.content,
            .statement => |index| {
                _ = statements.orderedRemove(index);
            },
            .insert_statement => |value| try statements.insert(a, value.index, .{ .claim_ids = try a.dupe(r.ClaimId, &.{value.claim}), .content = replacement.?.content }),
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
                    .insert_conflict => |value| try values.insert(a, value.index, .{ .claim_ids = try a.dupe(r.ClaimId, value.claims), .summary = replacement.?.conflict_detail.summary, .kind = replacement.?.conflict_detail.kind }),
                    else => unreachable,
                }
                global.conflicts = try values.toOwnedSlice(a);
            },
            else => return error.InvalidAtomicRepair,
        }
        if (merged.changed) switch (target) {
            .disposition, .insert_disposition => {
                result.proposal.global = global;
                result = try retireSignals(a, result, &.{target.guidance().claim.?});
                global = result.proposal.global;
                result.phase = .dispositions;
            },
            .signal_selection, .signal_content, .signal, .insert_signal => {
                global.role_decisions = null;
                result.source.fields = try retireRoles(a, result.source.fields);
                result.phase = if (parsed.phase == .complete or parsed.phase == .signals_with_conflicts) .signals_with_conflicts else .signals;
            },
            else => {},
        };
        result.proposal = .{ .global = global };
    }
    result.source = try origins(a, result.source, target, merged.operation == .delete, origin);
    result.source.pending_repair = null;
    switch (target) {
        .statement => |index| result.source.statements = parsed.source.statements.deleting(a, index, parsed.proposal.summary.statements.len) catch |err| return occurrenceError(err),
        .insert_statement => |value| result.source.statements = parsed.source.statements.inserting(a, value.index, parsed.proposal.summary.statements.len) catch |err| return occurrenceError(err),
        .disposition_record => |index| result.source.dispositions = parsed.source.dispositions.deleting(a, index, parsed.proposal.global.claim_dispositions.len) catch |err| return occurrenceError(err),
        .insert_disposition => |value| result.source.dispositions = parsed.source.dispositions.inserting(a, value.index, parsed.proposal.global.claim_dispositions.len) catch |err| return occurrenceError(err),
        .signal => |index| result.source.signals = parsed.source.signals.deleting(a, index, parsed.proposal.global.signals.len) catch |err| return occurrenceError(err),
        .insert_signal => |value| result.source.signals = parsed.source.signals.inserting(a, value.index, parsed.proposal.global.signals.len) catch |err| return occurrenceError(err),
        .conflict => |index| result.source.conflicts = parsed.source.conflicts.deleting(a, index, parsed.proposal.global.conflicts.len) catch |err| return occurrenceError(err),
        .insert_conflict => |value| result.source.conflicts = parsed.source.conflicts.inserting(a, value.index, parsed.proposal.global.conflicts.len) catch |err| return occurrenceError(err),
        else => {},
    }
    result.source.revision = merged.revision_after;
    result.source.last_repair = merged;
    return result;
}

fn occurrenceError(err: occurrences.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidRepairOccurrence => error.InvalidAtomicRepair,
    };
}

pub const ValidationStage = enum { summary, dispositions, signals, conflicts };

pub fn dispositionProgress(a: std.mem.Allocator, parsed: r.Parsed) Error!?@import("workflow_retry.zig").Transition {
    const pending = parsed.source.pending_repair orelse return null;
    if (stageOf(pending.target.selected) != .dispositions) return null;
    const valid = if (pending.target.operation == .delete)
        !try containsOccurrence(parsed.source.dispositions, parsed.proposal.global.claim_dispositions.len, pending.target.stable.disposition_occurrence)
    else switch (pending.target.selected) {
        inline .disposition, .insert_disposition => |value| try dispositions.validClaim(a, parsed.input.progress.plan.layout.items, parsed.proposal.global.claim_dispositions, value.claim),
        else => return error.InvalidAtomicRepair,
    };
    return .{ .validated = .{ .permit = pending.permit, .revision = parsed.source.revision, .result = if (valid) .resolved else .recurring } };
}

fn stageOf(target: Target) ValidationStage {
    return switch (target) {
        .statement_selection, .statement_content, .statement, .insert_statement => .summary,
        .disposition, .disposition_record, .insert_disposition => .dispositions,
        .signal_selection, .signal_content, .signal, .insert_signal => .signals,
        .conflict_selection, .conflict_summary, .conflict, .insert_conflict => .conflicts,
    };
}

fn containsOccurrence(set: occurrences.Set, count: usize, id: occurrences.Id) Error!bool {
    for (0..count) |index| if (std.meta.eql(set.at(index, count) catch |err| return occurrenceError(err), id)) return true;
    return false;
}

/// Observe the selected native rule after the ordinary stage validator has run.
/// Other failed records do not substitute for proof about this authorized unit.
pub fn progress(a: std.mem.Allocator, validator: r.text.Validator, ctx: v.TextContext, parsed: r.Parsed, stage: ValidationStage, checked_dispositions: []const r.ClaimDisposition) Error!?@import("workflow_retry.zig").Transition {
    const pending = parsed.source.pending_repair orelse return null;
    const watch = pending.target;
    const target = watch.selected;
    if (stageOf(target) != stage) return null;
    const items = parsed.input.progress.plan.layout.items;
    const valid = if (watch.operation == .delete) switch (watch.stable) {
        .statement => |id| !try containsOccurrence(parsed.source.statements, parsed.proposal.summary.statements.len, id),
        .disposition_occurrence => |id| !try containsOccurrence(parsed.source.dispositions, parsed.proposal.global.claim_dispositions.len, id),
        .signal => |id| !try containsOccurrence(parsed.source.signals, parsed.proposal.global.signals.len, id),
        .conflict => |id| !try containsOccurrence(parsed.source.conflicts, parsed.proposal.global.conflicts.len, id),
        else => return error.InvalidAtomicRepair,
    } else switch (target) {
        .statement_selection => |index| blk: {
            const value = parsed.proposal.summary.statements[index];
            if (v.claims(items, value.claim_ids, parsed.input.partition.group.claim_ids) != null) break :blk false;
            break :blk if (watch.rule == .content) (try v.contentIssue(items, value.claim_ids, value.content)) == null else true;
        },
        .statement_content => |index| blk: {
            const value = parsed.proposal.summary.statements[index];
            break :blk (try v.content(a, validator, ctx, items, value.claim_ids, value.content)) == .valid;
        },
        .insert_statement => |value| blk: {
            const selected = parsed.proposal.summary.statements[value.index];
            break :blk v.claims(items, selected.claim_ids, parsed.input.partition.group.claim_ids) == null and r.contains(r.ClaimId, selected.claim_ids, value.claim);
        },
        inline .disposition, .insert_disposition => |value| try dispositions.validClaim(a, items, parsed.proposal.global.claim_dispositions, value.claim),
        .signal_selection => |index| blk: {
            const value = parsed.proposal.global.signals[index];
            if (try v.signalClaims(items, checked_dispositions, value.claim_ids, parsed.input.partition.group.claim_ids) != null) break :blk false;
            break :blk if (watch.rule == .content) (try v.contentIssue(items, value.claim_ids, value.content)) == null else true;
        },
        .signal_content => |index| blk: {
            const value = parsed.proposal.global.signals[index];
            break :blk (try v.content(a, validator, ctx, items, value.claim_ids, value.content)) == .valid;
        },
        .insert_signal => |value| blk: {
            const selected = parsed.proposal.global.signals[value.index];
            break :blk try v.signalClaims(items, checked_dispositions, selected.claim_ids, parsed.input.partition.group.claim_ids) == null and try v.selectedSignalCoverage(items, checked_dispositions, selected, value.claim) == null;
        },
        .conflict_selection => |index| blk: {
            const value = parsed.proposal.global.conflicts[index];
            break :blk (try v.conflictClaims(items, checked_dispositions, value.claim_ids, parsed.input.partition.group.claim_ids)) == null;
        },
        .conflict_summary => |index| blk: {
            const value = parsed.proposal.global.conflicts[index];
            break :blk (try v.conflictSummary(a, validator, ctx, items, value.claim_ids, value.summary)) == .valid;
        },
        .insert_conflict => |value| blk: {
            const selected = parsed.proposal.global.conflicts[value.index];
            break :blk try v.conflictClaims(items, checked_dispositions, selected.claim_ids, parsed.input.partition.group.claim_ids) == null and v.sameMembers(selected.claim_ids, value.claims);
        },
        .statement, .disposition_record, .signal, .conflict => return error.InvalidAtomicRepair,
    };
    return .{ .validated = .{ .permit = pending.permit, .revision = parsed.source.revision, .result = if (valid) .resolved else .recurring } };
}
fn select(parsed: r.Parsed, target: Target) Error!?Replacement {
    const summary = parsed.proposal == .summary;
    return switch (target) {
        .statement_selection, .statement_content, .statement => |index| if (summary and index < parsed.proposal.summary.statements.len) switch (target) {
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
    var result = source;
    result.fields = try fields.toOwnedSlice(a);
    return result;
}

fn retireSignals(a: std.mem.Allocator, parsed: r.Parsed, claims: []const r.ClaimId) Error!r.Parsed {
    var result = parsed;
    var values: std.ArrayList(r.SignalProposal) = .empty;
    try values.appendSlice(a, parsed.proposal.global.signals);
    var index = values.items.len;
    while (index > 0) {
        index -= 1;
        var affected = false;
        for (values.items[index].claim_ids) |id| if (r.contains(r.ClaimId, claims, id)) {
            affected = true;
        };
        if (!affected) continue;
        result.source.signals = result.source.signals.deleting(a, index, values.items.len) catch |err| return occurrenceError(err);
        result.source = try origins(a, result.source, .{ .signal = index }, true, null);
        _ = values.orderedRemove(index);
    }
    result.proposal.global.signals = try values.toOwnedSlice(a);
    result.proposal.global.role_decisions = null;
    result.source.fields = try retireRoles(a, result.source.fields);
    return result;
}

fn retireRoles(a: std.mem.Allocator, fields: []const d.FieldOrigin) Error![]const d.FieldOrigin {
    var result: std.ArrayList(d.FieldOrigin) = .empty;
    for (fields) |field| {
        if (field.unit == .signals and field.field == .relationship) continue;
        try result.append(a, field);
    }
    return result.toOwnedSlice(a);
}

pub const Omission = struct {
    const loss = @import("source_omission.zig");
    pub const Facts = struct { reconciliation: context.Facts, support: loss.Support };
    const OmissionRule = struct { finding: @import("required_authority.zig").ReviewEvidence, disposition_choices: ?dispositions.RepairChoices };
    pub const OmissionTarget = union(enum) { unit: Target, conflict_group: []const r.ClaimId };
    const Atomic = shared.Contract(OmissionTarget, Replacement, Facts, OmissionRule);
    pub const OmissionAuthorization = Atomic.Authorization;
    pub const OmissionError = Atomic.Error || loss.Error;
    pub fn facts(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, support: loss.Support) OmissionError!Facts {
        return .{ .reconciliation = try context.capture(a, parsed, ctx), .support = support };
    }
    pub fn authorize(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, support: loss.Support) OmissionError!OmissionAuthorization {
        if (parsed.proposal != .global) return error.InvalidAtomicRepair;
        try v.input(a, parsed.input);
        const selected = try loss.select(a, ctx.inputs, support);
        const finding = selected.finding.review.?;
        const target: OmissionTarget = switch (selected.location) {
            .reconciliation_signal => |id| blk: {
                if (id.ordinal == 0 or id.ordinal > parsed.proposal.global.signals.len) return error.InvalidAtomicRepair;
                const index = id.ordinal - 1;
                try r.sameSet(r.ClaimId, parsed.proposal.global.signals[index].claim_ids, finding.provenance.claim_ids);
                break :blk .{ .unit = .{ .signal_content = index } };
            },
            .reconciliation_disposition => |id| blk: {
                for (parsed.proposal.global.claim_dispositions, 0..) |value, index| if (std.meta.eql(value.claim_id, id)) break :blk .{ .unit = .{ .disposition = .{ .index = index, .claim = id } } };
                return error.InvalidAtomicRepair;
            },
            .reconciliation_conflict => |id| blk: {
                if (id.ordinal == 0 or id.ordinal > parsed.proposal.global.conflicts.len) return error.InvalidAtomicRepair;
                const claims = parsed.proposal.global.conflicts[id.ordinal - 1].claim_ids;
                try r.sameSet(r.ClaimId, claims, finding.provenance.claim_ids);
                break :blk .{ .conflict_group = try a.dupe(r.ClaimId, claims) };
            },
            else => return error.InvalidAtomicRepair,
        };
        const current = try facts(a, parsed, ctx, support);
        defer a.free(current.reconciliation.lineage.history);
        var result = try Atomic.authorize(a, try owner(a, parsed), parsed.source.revision, target, (try selectedValue(a, parsed, target)).?, current, .{ .finding = finding, .disposition_choices = if (target == .unit) try dispositionChoices(a, parsed, target.unit) else null });
        result.retry = try Omission.retryPermit(a, result);
        return result;
    }
    pub fn retryPermit(a: std.mem.Allocator, auth: OmissionAuthorization) OmissionError!@import("workflow_retry.zig").Permit {
        const current = auth.dependencies;
        const selected = try loss.select(a, current.reconciliation.text.?.inputs, current.support);
        return loss.retryPermit(a, .reconciliation, auth.owner, auth.id, auth.revision, current.support, selected.finding.requirement, current.reconciliation.source.omission_retry);
    }
    pub fn packet(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, support: loss.Support, auth: OmissionAuthorization) OmissionError!*packets.Packet {
        const current = try facts(a, parsed, ctx, support);
        defer a.free(current.reconciliation.lineage.history);
        try Atomic.checkDependencies(a, auth, current);
        const kind = if (auth.target == .unit and auth.target.unit == .signal_content) (try v.selectedKind(parsed.input.progress.plan.layout.items, parsed.proposal.global.signals[auth.target.unit.signal_content].claim_ids)) orelse return error.InvalidAtomicRepair else null;
        const base = try @import("reference_model_input.zig").reconciliationPacket(a, parsed.input, ctx.inputs, ctx.registry, if (kind) |value| .{ .content = value } else if (auth.target == .conflict_group) .all else .{ .disposition = if (auth.rule.disposition_choices == null) .rules else .choices });
        defer packets.release(base);
        const prepared_input = try Atomic.packet(a, auth, base, .{ .bytes = if (kind) |value| switch (value) {
            .preserved_token => return error.InvalidAtomicRepair,
            .model => |model| switch (model) {
                .business, .scope_guard => "business_text",
                else => "reference_text",
            },
        } else if (auth.target == .conflict_group) "repair_conflict_group" else "repair_disposition" }, if (auth.target == .unit) parsed.source.at(targetOrigin(auth.target.unit).unit, targetOrigin(auth.target.unit).field) else parsed.source.at(.conflicts, .record));
        if (kind != null) return prepared_input;
        defer packets.release(prepared_input);
        return @import("reference_model_input.zig").withDispositionChoices(a, prepared_input, if (auth.target == .conflict_group) auth.target.conflict_group else parsed.input.partition.group.claim_ids, auth.rule.disposition_choices, auth.target == .conflict_group);
    }
    pub fn parse(a: std.mem.Allocator, auth: OmissionAuthorization, input: *const packets.Packet, bytes: []const u8) OmissionError!Replacement {
        const json = @import("model_candidate_json.zig");
        const kind = try Atomic.checkRequest(auth, input);
        const groups = @import("reference_conflict_groups.zig");
        if (kind == .disposition) return .{ .disposition = try groups.disposition(a, try json.decode(groups.SemanticDisposition, a, bytes), auth.rule.disposition_choices) };
        if (kind == .conflict_group) {
            const value = try json.decode(groups.Repair, a, bytes);
            return .{ .conflict_group = .{ .conflict_groups = value.conflict_groups, .claim_dispositions = try groups.expand(a, .{ .claim_dispositions = value.claim_dispositions, .conflict_groups = value.conflict_groups }), .conflicts = try groups.explain(a, value.conflict_groups, value.conflicts) } };
        }
        if (kind != .content) return Atomic.parse(a, auth, input, bytes);
        const selected = auth.operation.replace.content;
        return .{ .content = switch (selected) {
            .model => |value| .{ .model = try json.decodeSelected(@FieldType(r.ContentProposal, "model"), a, std.meta.activeTag(value), bytes) },
            .preserved_token => return error.InvalidAtomicRepair,
        } };
    }
    pub fn merge(a: std.mem.Allocator, parsed: r.Parsed, ctx: v.TextContext, support: loss.Support, auth: OmissionAuthorization, proposed: Replacement, origin: ?@import("model_candidate_origin.zig").Origin) OmissionError!r.Parsed {
        const replacement = try Atomic.copyReplacement(a, proposed);
        const current = try facts(a, parsed, ctx, support);
        defer a.free(current.reconciliation.lineage.history);
        const merged = try Atomic.checkMerge(a, try owner(a, parsed), parsed.source.revision, try selectedValue(a, parsed, auth.target), current, auth, replacement, origin);
        var result = if (auth.target == .unit) try apply(a, parsed, auth.target.unit, replacement, merged, origin) else try applyGroup(a, parsed, auth.target.conflict_group, replacement.conflict_group, merged, origin);
        result.source.omission_conflict_claims = if (auth.target == .conflict_group) try a.dupe(r.ClaimId, auth.target.conflict_group) else &.{};
        result.source.omission_retry = auth.retry orelse return error.InvalidAtomicRepair;
        return result;
    }
    fn selectedValue(a: std.mem.Allocator, parsed: r.Parsed, target: OmissionTarget) OmissionError!?Replacement {
        if (target == .unit) return select(parsed, target.unit);
        if (parsed.proposal != .global or target.conflict_group.len < 2) return error.InvalidAtomicRepair;
        const claims = target.conflict_group;
        var selected_dispositions: std.ArrayList(r.ClaimDispositionProposal) = .empty;
        var selected_conflicts: std.ArrayList(r.ConflictProposal) = .empty;
        var selected_groups: std.ArrayList(@import("reference_conflict_groups.zig").Group) = .empty;
        for (parsed.proposal.global.conflict_groups) |group| {
            var touches = false;
            for (group.claim_ids) |id| if (r.contains(r.ClaimId, claims, id)) {
                touches = true;
            };
            if (!touches) continue;
            for (group.claim_ids) |id| if (!r.contains(r.ClaimId, claims, id)) return error.InvalidAtomicRepair;
            try selected_groups.append(a, group);
        }
        for (parsed.proposal.global.claim_dispositions) |value| {
            if (!r.contains(r.ClaimId, claims, value.claim_id)) continue;
            if (value.disposition != .conflicting) return error.InvalidAtomicRepair;
            for (value.disposition.conflicting.related_claim_ids) |id| if (!r.contains(r.ClaimId, claims, id)) return error.InvalidAtomicRepair;
            try selected_dispositions.append(a, value);
        }
        if (selected_dispositions.items.len != claims.len) return error.InvalidAtomicRepair;
        for (parsed.proposal.global.conflicts) |value| {
            var touches = false;
            for (value.claim_ids) |id| if (r.contains(r.ClaimId, claims, id)) {
                touches = true;
            };
            if (!touches) continue;
            for (value.claim_ids) |id| if (!r.contains(r.ClaimId, claims, id)) return error.InvalidAtomicRepair;
            try selected_conflicts.append(a, value);
        }
        if (selected_conflicts.items.len == 0) return error.InvalidAtomicRepair;
        return .{ .conflict_group = .{ .conflict_groups = try selected_groups.toOwnedSlice(a), .claim_dispositions = try selected_dispositions.toOwnedSlice(a), .conflicts = try selected_conflicts.toOwnedSlice(a) } };
    }
    fn applyGroup(a: std.mem.Allocator, parsed: r.Parsed, claims: []const r.ClaimId, replacement: ConflictGroup, merged: shared.Merge, origin: ?@import("model_candidate_origin.zig").Origin) OmissionError!r.Parsed {
        // No external links, missing members, duplicates or foreign records can
        // widen this native-bound unit. Ordinary validators judge its meaning.
        if (replacement.claim_dispositions.len != claims.len) return error.InvalidAtomicRepair;
        for (replacement.claim_dispositions, 0..) |value, index| {
            if (!r.contains(r.ClaimId, claims, value.claim_id)) return error.InvalidAtomicRepair;
            for (replacement.claim_dispositions[0..index]) |prior| if (std.meta.eql(prior.claim_id, value.claim_id)) return error.InvalidAtomicRepair;
            const canonical = try value.canonical(a);
            for (canonical.related_claim_ids) |id| if (!r.contains(r.ClaimId, claims, id)) return error.InvalidAtomicRepair;
        }
        for (replacement.conflict_groups) |group| {
            if (group.claim_ids.len < 2) return error.InvalidAtomicRepair;
            for (group.claim_ids) |id| if (!r.contains(r.ClaimId, claims, id)) return error.InvalidAtomicRepair;
        }
        for (replacement.conflicts) |value| {
            if (value.claim_ids.len < 2) return error.InvalidAtomicRepair;
            for (value.claim_ids) |id| if (!r.contains(r.ClaimId, claims, id)) return error.InvalidAtomicRepair;
        }
        var result = parsed;
        const values = try a.dupe(r.ClaimDispositionProposal, parsed.proposal.global.claim_dispositions);
        for (values) |*value| for (replacement.claim_dispositions) |revised| {
            if (value.claim_id.ordinal == revised.claim_id.ordinal) value.* = revised;
        };
        var groups: std.ArrayList(@import("reference_conflict_groups.zig").Group) = .empty;
        for (parsed.proposal.global.conflict_groups) |group| {
            if (!r.contains(r.ClaimId, claims, group.claim_ids[0])) try groups.append(a, group);
        }
        try groups.appendSlice(a, replacement.conflict_groups);
        var conflicts: std.ArrayList(r.ConflictProposal) = .empty;
        for (parsed.proposal.global.conflicts) |value| {
            if (!r.contains(r.ClaimId, claims, value.claim_ids[0])) try conflicts.append(a, value);
        }
        try conflicts.appendSlice(a, replacement.conflicts);
        for (replacement.claim_dispositions) |value| for (values, 0..) |existing, index| {
            if (existing.claim_id.ordinal == value.claim_id.ordinal) result.source = try origins(a, result.source, .{ .disposition = .{ .index = index, .claim = value.claim_id } }, false, origin);
        };
        var count = parsed.proposal.global.conflicts.len;
        var cursor = count;
        while (cursor > 0) {
            cursor -= 1;
            if (!r.contains(r.ClaimId, claims, parsed.proposal.global.conflicts[cursor].claim_ids[0])) continue;
            result.source.conflicts = result.source.conflicts.deleting(a, cursor, count) catch |err| return occurrenceError(err);
            result.source = try origins(a, result.source, .{ .conflict = cursor }, true, null);
            count -= 1;
        }
        for (replacement.conflicts) |_| {
            result.source.conflicts = result.source.conflicts.inserting(a, count, count) catch |err| return occurrenceError(err);
            result.source = try origins(a, result.source, .{ .insert_conflict = .{ .index = count, .claims = claims } }, false, origin);
            count += 1;
        }
        result.proposal.global.claim_dispositions = values;
        result.proposal.global.conflict_groups = try groups.toOwnedSlice(a);
        result.proposal.global.conflicts = try conflicts.toOwnedSlice(a);
        if (merged.changed) {
            // Signals were accepted against the old complete disposition graph.
            // Their downstream assignment is rebuilt; independent conflicts survive.
            result = try retireSignals(a, result, claims);
            result.phase = .dispositions;
        }
        result.source.revision = merged.revision_after;
        result.source.last_repair = merged;
        return result;
    }
    pub const Authorization = OmissionAuthorization;
    pub const Error = OmissionError;
};
