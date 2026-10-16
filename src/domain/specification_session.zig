//! Execution-local business units. Native code owns identities and dispatch;
//! authored source-group selections remain untrusted candidate data.
const std = @import("std");
const g = @import("specification_generation.zig");
const p = @import("specification_provenance.zig");
const packets = @import("model_input_packet.zig");
const identity = @import("model_request_identity.zig");
const binding = @import("specification_source_binding.zig");
pub const unit_count = std.meta.fields(g.Unit).len;
pub const records_index = @intFromEnum(std.meta.Tag(g.Unit).records);
pub const Session = struct {
    feature: @import("feature_identity.zig").FeatureId,
    reference_state: @import("reference_identity.zig").StateId,
    revision: u64 = 1,
    completed: usize = 0,
    record_cursor: usize = 0,
    record_group_count: usize = 0,
    record_batches: []const g.Checked = &.{},
    units: [unit_count]?g.Checked = @splat(null),
    starting_ledger: @import("specification_identity.zig").Ledger = .{},
    omission_target_bound: ?u32 = null,
};
pub const Error = @import("strict_json.zig").Error || g.Error || packets.Error || binding.Error;

/// One native population covers the narrative units and every retained group.
/// Repairs of already completed units do not reopen this authoring pass.
pub fn iterationProgress(current: Session) Error!struct { limit: usize, position: usize } {
    if (current.record_group_count == 0 or current.completed > unit_count or current.record_cursor > current.record_group_count) return error.InvalidSpecificationUnit;
    if (current.completed < records_index) {
        if (current.record_cursor != 0 or current.record_batches.len != 0) return error.InvalidSpecificationUnit;
    } else if (current.record_batches.len != current.record_cursor or
        (current.completed == records_index and current.record_cursor == current.record_group_count) or
        (current.completed == unit_count and current.record_cursor != current.record_group_count)) return error.InvalidSpecificationUnit;
    return .{
        .limit = std.math.add(usize, records_index, current.record_group_count) catch return error.InvalidSpecificationUnit,
        .position = if (current.completed < records_index) current.completed else std.math.add(usize, records_index, current.record_cursor) catch return error.InvalidSpecificationUnit,
    };
}

pub fn unit(index: usize) error{InvalidSpecificationUnit}!g.Unit {
    return switch (index) {
        0 => .brief,
        1 => .primary_user_story,
        2 => .entities,
        records_index => .records,
        else => error.InvalidSpecificationUnit,
    };
}

pub const Initialization = union(enum) { ready: Session, blocked: binding.Rejection };

pub fn initialize(a: std.mem.Allocator, feature: @import("feature_identity.zig").FeatureId, context: p.Context) Error!Initialization {
    if (@import("feature_identity.zig").FeatureId.parse(feature.bytes) == null or !p.generationReady(context.references)) return error.InvalidSpecificationUnit;
    _ = try p.items(context);
    const records = @import("reference_support.zig").records(context.references);
    if (try binding.recordCount(records) == 0) return .{ .blocked = try binding.rejection(a, context.references) };
    try binding.validate(records, context.inputs);
    return .{ .ready = .{ .feature = feature, .reference_state = context.inputs.corpus.state_id, .record_group_count = try binding.recordCount(records) } };
}

pub fn currentBinding(a: std.mem.Allocator, current: Session, context: p.Context) Error!binding.Bound {
    if (!current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    if (current.record_group_count != try binding.recordCount(@import("reference_support.zig").records(context.references))) return error.InvalidSpecificationUnit;
    return binding.forUnit(a, @import("reference_support.zig").records(context.references), context.inputs, try unit(current.completed), current.record_cursor);
}

/// A checked batch retains the native dispatch occurrence even when it is empty.
/// It cannot be inferred later from its authored records or equal claim sets.
pub fn admit(a: std.mem.Allocator, current: Session, context: p.Context, checked: g.Checked) Error!g.Checked {
    if (!std.meta.eql(checked.unit, try unit(current.completed))) return error.InvalidSpecificationUnit;
    if (checked.unit != .records) return checked;
    const assigned = try currentBinding(a, current, context);
    defer a.free(assigned.records.selection.claim_ids);
    if (checked.response == .clarification) {
        const groups = checked.response.clarification.question.source_group_ids;
        if (groups.len != 1 or groups[0].ordinal != assigned.records.signal.ordinal or checked.record_assignment != null) return error.InvalidSpecificationUnit;
        return checked;
    }
    if (checked.response != .content or checked.response.content != .records) return error.InvalidSpecificationUnit;
    try checkBatchGroup(checked, assigned.records.signal);
    const fact: g.RecordAssignment = .{ .reference_state = current.reference_state, .group_index = current.record_cursor, .source_group_id = assigned.records.signal, .references = try referenceSnapshot(a, context) };
    if (checked.record_assignment) |prior| if (!sameAssignment(prior, fact)) return error.InvalidSpecificationUnit;
    var result = checked;
    result.record_assignment = fact;
    return result;
}

fn sameAssignment(left: g.RecordAssignment, right: g.RecordAssignment) bool {
    return left.reference_state.eql(right.reference_state) and left.group_index == right.group_index and left.source_group_id.ordinal == right.source_group_id.ordinal and std.meta.eql(left.references, right.references);
}

fn referenceSnapshot(a: std.mem.Allocator, context: p.Context) Error!@import("atomic_repair.zig").Snapshot {
    const facts = try p.dependencies(a, context);
    defer a.free(facts.lineage.history);
    return @import("atomic_repair.zig").snapshot(p.Dependencies, a, facts);
}

fn checkBatchGroup(checked: g.Checked, group: @import("reference_reconciliation.zig").SignalId) Error!void {
    if (checked.unit != .records or checked.response != .content or checked.response.content != .records) return error.InvalidSpecificationUnit;
    for (checked.response.content.records) |record| if (record.source_group_ids.len != 1 or record.source_group_ids[0].ordinal != group.ordinal) return error.InvalidSpecificationUnit;
}

pub fn validateRecordAssignments(a: std.mem.Allocator, current: Session, context: p.Context) Error!void {
    if (current.record_cursor != current.record_group_count) return error.InvalidSpecificationUnit;
    try validateRecordPrefix(a, current, context);
}

/// Empty batches retain the same current reference witness as nonempty batches.
/// Presentation may read this admitted prefix, never a stale or fabricated one.
fn validateRecordPrefix(a: std.mem.Allocator, current: Session, context: p.Context) Error!void {
    if (!current.reference_state.eql(context.inputs.corpus.state_id) or current.record_group_count == 0 or current.record_group_count != try binding.recordCount(@import("reference_support.zig").records(context.references)) or current.record_cursor > current.record_group_count or current.record_batches.len != current.record_cursor) return error.InvalidSpecificationUnit;
    const references = try referenceSnapshot(a, context);
    for (current.record_batches, 0..) |batch, index| {
        const assigned = try binding.record(a, @import("reference_support.zig").records(context.references), context.inputs, index);
        defer a.free(assigned.records.selection.claim_ids);
        const fact = batch.record_assignment orelse return error.InvalidSpecificationUnit;
        if (!sameAssignment(fact, .{ .reference_state = current.reference_state, .group_index = index, .source_group_id = assigned.records.signal, .references = references })) return error.InvalidSpecificationUnit;
        try checkBatchGroup(batch, assigned.records.signal);
    }
}

pub fn owner(allocator: std.mem.Allocator, current: Session) Error!identity.ImmutableUnitOwnerId {
    return ownerFor(allocator, current, current.completed);
}
pub fn ownerFor(allocator: std.mem.Allocator, current: Session, index: usize) Error!identity.ImmutableUnitOwnerId {
    _ = try unit(index);
    return .{
        .specification_unit = .{
            .reference_state_id = .{ .bytes = current.reference_state.bytes },
            // Feature directory is the feature identity; no second ownership registry.
            .feature_id = current.feature,
            .unit_slot_id = .{ .bytes = if (index == records_index and current.completed == records_index) try std.fmt.allocPrint(allocator, "specification-{d}-group-{d}", .{ index + 1, current.record_cursor + 1 }) else try std.fmt.allocPrint(allocator, "specification-{d}", .{index + 1}) },
        },
    };
}

pub fn packet(allocator: std.mem.Allocator, current: Session, context: p.Context) Error!*packets.Packet {
    return packetFor(allocator, current, context, current.completed);
}
pub fn packetFor(allocator: std.mem.Allocator, current: Session, context: p.Context, index: usize) Error!*packets.Packet {
    return packetForOptions(allocator, current, context, index, .{});
}

pub const PacketOptions = struct {
    exact_claims: ?[]const @import("reference_reconciliation.zig").ClaimId = null,
    task: ?[]const u8 = null,
};

/// Present the aggregate contract without imposing a floor on each source group.
const RecordRequirements = struct {
    scope: enum { assembled_specification } = .assembled_specification,
    required_families: []const g.spec.Kind,
    present_families: []const g.spec.Kind,
    unmet_required_families: []const g.spec.Kind,
};

/// Family presence is a native structural fact, not evidence that the earlier
/// candidate's content is correct or that its obligations have been fulfilled.
fn recordRequirements(a: std.mem.Allocator, current: Session, context: p.Context, disposition: g.spec.Applicability) Error!RecordRequirements {
    if (current.completed != records_index or current.record_cursor >= current.record_group_count) return error.InvalidSpecificationUnit;
    try validateRecordPrefix(a, current, context);
    var present: std.EnumSet(g.spec.Kind) = .initEmpty();
    for (current.record_batches) |batch| for (batch.response.content.records) |record| present.insert(std.meta.activeTag(record.content));
    const required = g.spec.assemblyRequiredRecordFamilies(disposition);
    var families: std.ArrayList(g.spec.Kind) = .empty;
    errdefer families.deinit(a);
    for (std.meta.tags(g.spec.Kind)) |kind| if (present.contains(kind)) try families.append(a, kind);
    var unmet: std.ArrayList(g.spec.Kind) = .empty;
    errdefer unmet.deinit(a);
    for (required) |kind| if (!present.contains(kind)) try unmet.append(a, kind);
    return .{ .required_families = required, .present_families = try families.toOwnedSlice(a), .unmet_required_families = try unmet.toOwnedSlice(a) };
}

/// Repair retains all source claims but offers exact-copy choices only from the
/// bound owning unit. An explicit task replaces authoring purposes while retaining
/// the source binding. Completed units receive only their authorized repair task.
pub fn packetForOptions(allocator: std.mem.Allocator, current: Session, context: p.Context, index: usize, options: PacketOptions) Error!*packets.Packet {
    if (!current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    const all = try p.items(context);
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const selected = try unit(index);
    const entity_decision: ?g.spec.ApplicabilityProposal = if (selected == .records) decision: {
        const checked = current.units[2] orelse return error.InvalidSpecificationUnit;
        if (checked.unit != .entities or checked.response != .content or checked.response.content != .entities) return error.InvalidSpecificationUnit;
        break :decision checked.response.content.entities;
    } else null;
    const excluded: []const @import("model_result_schema.zig").ExcludedVariant = if (entity_decision != null and entity_decision.?.disposition == .not_applicable) &.{.{ .kind = "entity" }} else &.{};
    // The schema restriction is also the presentation filter. Descriptions do
    // not establish another applicability rule or offer an excluded family.
    var record_kinds: std.ArrayList(g.spec.Kind) = .empty;
    families: for (std.meta.tags(g.spec.Kind)) |kind| {
        for (excluded) |entry| if (std.mem.eql(u8, entry.kind, @tagName(kind))) continue :families;
        try record_kinds.append(a, kind);
    }
    const projection = @import("model_evidence.zig");
    var requirements: std.ArrayList(projection.Requirement) = .empty;
    var exact_choices: std.ArrayList(projection.ExactLiteral) = .empty;
    var scopes: std.ArrayList(@import("reference_evidence.zig").Scope) = .empty;
    for (context.references.records.assignments.checked.prior.prior.dispositions) |disposition| {
        if (!@import("reference_support.zig").eligibleClaim(disposition.disposition)) continue;
        const item = try @import("reference_reconciliation.zig").item(all, disposition.claim_id);
        try requirements.append(a, try projection.requirement(a, item, context.inputs, context.registry));
        try scopes.append(a, .{ .state_id = all.state_id, .chunk_id = item.claim.chunk_id });
        if (item.claim.content == .preserved_token) {
            const token = item.claim.content.preserved_token;
            if (p.permitsExactKind(token.value.kind) and (options.exact_claims == null or @import("reference_reconciliation.zig").contains(@import("reference_reconciliation.zig").ClaimId, options.exact_claims.?, item.claim.id))) {
                try exact_choices.append(a, .{ .claim_id = item.claim.id, .value = token.value.raw_value.bytes, .source_id = item.source_id });
            }
        }
    }
    // Completed units are repaired under an atomic target and its evidence.
    // Their authoring cursor no longer selects a current source assignment.
    const assigned: ?binding.Guidance = if (index < current.completed) null else try binding.guidance(a, try binding.forUnit(a, @import("reference_support.zig").records(context.references), context.inputs, selected, current.record_cursor), if (options.task != null) .repair else .authoring, requirements.items, record_kinds.items);
    var contextual_requirements: std.ArrayList(projection.Requirement) = .empty;
    for (requirements.items) |requirement| {
        if (assigned) |selection| {
            if (selected != .records or binding.assigns(selection, requirement.claim_id)) continue;
        }
        // Exact occurrences have one display catalogue; they are not additional
        // behavioral requirements merely because their bytes are preserved.
        if ((try @import("reference_reconciliation.zig").item(all, requirement.claim_id)).claim.content == .preserved_token) continue;
        try contextual_requirements.append(a, requirement);
    }
    const offered_scopes = if (options.exact_claims) |ids|
        (@import("reference_support.zig").select(a, all, context.inputs, ids) catch |err| switch (err) {
            error.InvalidReferenceState => return error.InvalidSpecificationUnit,
            else => |other| return other,
        }).scopes
    else
        scopes.items;
    const source_groups = if (assigned != null and selected != .records) try binding.groupGuidance(a, @import("reference_support.zig").records(context.references), requirements.items) else &.{};
    const payload = .{
        .source_assignment = assigned,
        .source_groups = source_groups,
        .context_requirements = contextual_requirements.items,
        .preserved_tokens = exact_choices.items,
        .sources = try @import("model_evidence.zig").sources(a, context.inputs),
        .passive_literals = try @import("reference_model_input.zig").passiveChoices(a, context.registry, context.inputs, offered_scopes),
    };
    const body = try @import("model_candidate_json.zig").encode(@TypeOf(payload), a, payload);
    var result = try packets.create(allocator, body, try ownerFor(a, current, index), .initial_generation, .{ .bytes = switch (selected) {
        .brief => "brief",
        .primary_user_story => "primary_user_story",
        .entities => "entities",
        .records => "records",
    } });
    defer packets.release(result);
    const witnessed = try packets.withOriginalSources(allocator, result, context.inputs);
    packets.release(result);
    result = witnessed;
    const model_fields = @import("model_candidate_json.zig").fieldBindings(g.ModelResponse, a, .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit;
    const policies = try packets.withFieldPolicies(allocator, result, model_fields);
    packets.release(result);
    result = policies;
    const presentation = @import("model_field_presentation.zig");
    var omissions: std.ArrayList(presentation.Omission) = .empty;
    try omissions.append(a, .{ .requires = .exact_copy, .path = &.{.{ .property = "preserved_tokens" }} });
    for (source_groups, 0..) |group, group_index| if (try binding.tokenOnly(@import("reference_support.zig").records(context.references), group.signal_id)) {
        const path = try a.dupe(presentation.BodyStep, &.{ .{ .property = "source_groups" }, .{ .index = std.math.cast(u32, group_index) orelse return error.InvalidSpecificationUnit } });
        try omissions.append(a, .{ .requires = .exact_copy, .path = path });
    };
    const offered = try packets.withPresentationOmissions(allocator, result, omissions.items);
    packets.release(result);
    result = offered;
    if (options.task) |task| {
        const contextual = try packets.withContext([]const u8, allocator, result, "task", task);
        packets.release(result);
        result = contextual;
    } else {
        const contextual = try packets.withContext(enum { write }, allocator, result, "operation", .write);
        packets.release(result);
        result = contextual;
    }
    // Only dependent units receive earlier drafts. The evidence catalogue and
    // native dependency snapshots remain complete for generation and repair.
    switch (selected) {
        .brief, .primary_user_story => {},
        .entities, .records => if (current.units[0]) |checked| {
            const business = @import("specification_projection.zig");
            const contextual = try packets.withContext(business.Brief, allocator, result, "brief", try business.brief(a, context, checked.response.content.brief));
            packets.release(result);
            result = contextual;
        },
    }
    const exact_ids = try a.alloc(i64, exact_choices.items.len);
    for (exact_choices.items, exact_ids) |choice, *id| id.* = choice.claim_id.ordinal;
    const input = @import("reference_model_input.zig");
    const passive_ids = try input.passiveIds(a, payload.passive_literals);
    if (selected == .records) {
        if (assigned != null and options.task == null) {
            const contextual = try packets.withContext(RecordRequirements, allocator, result, "record_requirements", try recordRequirements(a, current, context, entity_decision.?.disposition));
            packets.release(result);
            result = contextual;
        }
        const business = @import("specification_projection.zig");
        const contextual = try packets.withContext(business.EntityDecision, allocator, result, "entities", try business.entities(a, context, entity_decision.?));
        packets.release(result);
        result = contextual;
    }
    const fixed = try packets.withExcludedVariants(allocator, result, excluded);
    defer packets.release(fixed);
    const choices = try input.withTextChoices(allocator, fixed, passive_ids, exact_ids);
    defer packets.release(choices);
    if (options.task != null or index < current.completed) return packets.withRestrictions(allocator, choices, choices.excludedVariants(), choices.integerChoices());
    return withGroupChoices(allocator, choices, context, selected, current.record_cursor);
}

fn withGroupChoices(allocator: std.mem.Allocator, base: *const packets.Packet, context: p.Context, selected: g.Unit, cursor: usize) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const records = @import("reference_support.zig").records(context.references);
    const positive = try binding.catalogue(a, records, .content);
    const questions = try binding.catalogue(a, records, .question);
    const returned_fields = switch (selected) {
        inline else => |_, tag| @import("model_candidate_json.zig").selectedFieldBindings(g.ModelResponse, a, @field(std.meta.Tag(g.ModelResponse), @tagName(tag)), .{}) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationUnit,
    };
    const permits_exact = for (returned_fields) |field| {
        if (@import("text_field_policy.zig").permits(field.field, .exact_copy)) break true;
    } else false;
    var question_ids: std.ArrayList(i64) = .empty;
    if (selected == .records) {
        try question_ids.append(a, (try binding.record(a, records, context.inputs, cursor)).records.signal.ordinal);
    } else for (questions) |group| {
        if (!permits_exact and try binding.tokenOnly(records, group.signal_id)) continue;
        try question_ids.append(a, group.signal_id.ordinal);
    }
    var eligible_positive: std.ArrayList(i64) = .empty;
    for (positive) |group| {
        if (!permits_exact and try binding.tokenOnly(records, group.signal_id)) continue;
        try eligible_positive.append(a, group.signal_id.ordinal);
    }
    const positive_ids = eligible_positive.items;
    var choices: std.ArrayList(@import("model_result_schema.zig").IntegerChoice) = .empty;
    try choices.append(a, .{ .target = .{ .path = &.{ .{ .property = "question" }, .{ .property = "signal_ids" } } }, .allowed = question_ids.items, .collection = .unique_subset });
    if (selected != .records and positive_ids.len != 0) switch (selected) {
        .brief => inline for (.{ "title", "description", "primary_goal" }) |field| {
            try choices.append(a, .{ .target = .{ .path = &.{ .{ .property = field }, .{ .property = "signal_ids" } } }, .allowed = positive_ids, .collection = .unique_subset });
        },
        .primary_user_story => try choices.append(a, .{ .target = .{ .tagged = .{ .kind = "primary_user_story", .field = "signal_ids" } }, .allowed = positive_ids, .collection = .unique_subset }),
        .entities => try choices.append(a, .{ .target = .{ .path = &.{ .{ .property = "basis" }, .{ .property = "signal_ids" } } }, .allowed = positive_ids, .collection = .unique_subset }),
        .records => unreachable,
    };
    const narrowed = try packets.withIntegerChoices(allocator, base, choices.items);
    defer packets.release(narrowed);
    if (selected != .records and positive_ids.len == 0) {
        const excluded = try a.alloc(@import("model_result_schema.zig").ExcludedVariant, base.excludedVariants().len + 1);
        @memcpy(excluded[0..base.excludedVariants().len], base.excludedVariants());
        excluded[excluded.len - 1] = .{ .kind = @tagName(std.meta.activeTag(selected)) };
        return packets.withExcludedVariants(allocator, narrowed, excluded);
    }
    return packets.withRestrictions(allocator, narrowed, narrowed.excludedVariants(), narrowed.integerChoices());
}

/// A value-only repair cannot borrow choices from unchanged sibling evidence.
pub fn withSelectionChoices(a: std.mem.Allocator, base: *const packets.Packet, context: p.Context, selection: g.spec.Selection) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const choices = try p.choicesFor(arena.allocator(), context, selection);
    const scratch = arena.allocator();
    const passive_ids = try scratch.alloc(i64, choices.passive.len);
    for (choices.passive, passive_ids) |choice, *id| id.* = choice.ordinal;
    const exact_ids = try scratch.alloc(i64, choices.exact_copy.len);
    for (choices.exact_copy, exact_ids) |choice, *id| id.* = choice.claim_id.ordinal;
    const visible = try narrowDisplayCatalogues(a, base, passive_ids, exact_ids);
    defer packets.release(visible);
    return @import("reference_model_input.zig").withTextChoices(a, visible, passive_ids, exact_ids);
}

/// Keep Spec's presented display choices aligned with the bound native scope.
/// Other source facts in the packet remain available for semantic judgment.
fn narrowDisplayCatalogues(a: std.mem.Allocator, base: *const packets.Packet, passive: []const i64, exact: []const i64) Error!*packets.Packet {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const scratch = arena.allocator();
    var parsed = try @import("strict_json.zig").parse(scratch, base.body(), .{ .maximum_depth = @import("model_result_schema.zig").max_json_depth }, false, null);
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidModelInputPacket;
    for ([_]struct { name: []const u8, id: []const u8, allowed: []const i64 }{
        .{ .name = "passive_literals", .id = "id", .allowed = passive },
        .{ .name = "preserved_tokens", .id = "claim_id", .allowed = exact },
    }) |catalogue| {
        const list = parsed.value.object.getPtr(catalogue.name) orelse return error.InvalidModelInputPacket;
        if (list.* != .array) return error.InvalidModelInputPacket;
        var index: usize = 0;
        while (index < list.array.items.len) {
            const entry = list.array.items[index];
            if (entry != .object) return error.InvalidModelInputPacket;
            const id = entry.object.get(catalogue.id) orelse return error.InvalidModelInputPacket;
            if (id != .number_string) return error.InvalidModelInputPacket;
            const number = std.fmt.parseInt(i64, id.number_string, 10) catch return error.InvalidModelInputPacket;
            var permitted = false;
            for (catalogue.allowed) |allowed| if (number == allowed) {
                permitted = true;
                break;
            };
            if (permitted) index += 1 else _ = list.array.orderedRemove(index);
        }
    }
    const body = try std.json.Stringify.valueAlloc(scratch, parsed.value, .{});
    const projected = if (base.repairPermit()) |permit|
        packets.createRepair(a, body, base.unit(), base.purpose(), base.resultDefinition(), permit, base.repairOrigin())
    else
        packets.create(a, body, base.unit(), base.purpose(), base.resultDefinition());
    const unbound = try projected;
    defer packets.release(unbound);
    const witnessed = try packets.withOriginalSourceTexts(a, unbound, base.originalSources());
    defer packets.release(witnessed);
    const prose = try packets.withProseFields(a, witnessed, base.proseFields());
    defer packets.release(prose);
    const policies = try packets.withFieldPolicies(a, prose, base.fieldPolicies());
    defer packets.release(policies);
    const offered = try packets.withPresentationOmissions(a, policies, base.presentationOmissions());
    defer packets.release(offered);
    return packets.withRestrictions(a, offered, base.excludedVariants(), base.integerChoices());
}

pub fn append(current: Session, checked: g.Checked) Error!Session {
    if (!std.meta.eql(try unit(current.completed), checked.unit) or checked.response != .content) return error.InvalidSpecificationUnit;
    var next = current;
    if (next.units[current.completed] != null) return error.InvalidSpecificationUnit;
    next.units[current.completed] = checked;
    next.completed += 1;
    next.revision = std.math.add(u64, current.revision, 1) catch return error.InvalidSpecificationUnit;
    return next;
}

/// Preserve each source-bound record batch until all groups have been authored.
/// The completed unit remains one canonical owner for repair, coverage and IDs.
pub fn appendBound(a: std.mem.Allocator, current: Session, checked: g.Checked) Error!Session {
    if (current.completed != records_index) return append(current, checked);
    if (checked.unit != .records or checked.response != .content or checked.response.content != .records or
        current.record_group_count == 0 or current.record_cursor >= current.record_group_count or
        current.record_batches.len != current.record_cursor) return error.InvalidSpecificationUnit;
    const fact = checked.record_assignment orelse return error.InvalidSpecificationUnit;
    if (!fact.reference_state.eql(current.reference_state) or fact.group_index != current.record_cursor or fact.source_group_id.ordinal == 0) return error.InvalidSpecificationUnit;
    try checkBatchGroup(checked, fact.source_group_id);
    const batches = try a.alloc(g.Checked, current.record_batches.len + 1);
    @memcpy(batches[0..current.record_batches.len], current.record_batches);
    batches[current.record_batches.len] = checked;
    var next = current;
    next.record_batches = batches;
    next.record_cursor += 1;
    if (next.record_cursor < next.record_group_count) {
        next.revision = std.math.add(u64, current.revision, 1) catch return error.InvalidSpecificationUnit;
        return next;
    }
    var total: usize = 0;
    for (batches) |batch| total = std.math.add(usize, total, batch.response.content.records.len) catch return error.InvalidSpecificationUnit;
    const records = try a.alloc(g.spec.RecordProposal, total);
    errdefer a.free(records);
    var origins: @import("specification_candidate.zig").Origins = .{};
    errdefer {
        a.free(origins.fields);
        a.free(origins.record_occurrences.values);
    }
    var offset: usize = 0;
    for (batches) |batch| {
        const count = batch.response.content.records.len;
        @memcpy(records[offset..][0..count], batch.response.content.records);
        const projected = origins.appendingRecords(a, offset, batch.origins, count) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidRepairOccurrence, error.InvalidSpecificationRepair => error.InvalidSpecificationUnit,
        };
        a.free(origins.fields);
        a.free(origins.record_occurrences.values);
        origins = projected;
        offset += count;
    }
    var combined = checked;
    combined.record_assignment = null;
    combined.response.content.records = records;
    combined.origins = origins;
    return append(next, combined);
}

/// Cross-batch and cross-unit consistency belongs to the session. The same
/// check governs admission, completed replacements and assembly.
pub fn checkConsistency(a: std.mem.Allocator, current: Session, context: p.Context, checked: g.Checked) Error!?@import("specification_candidate.zig").Issue {
    if (checked.response != .content) return null;
    const proposed = checked.response.content;
    if (proposed != .records and proposed != .entities) return null;
    if (proposed == .records and current.completed == records_index) for (proposed.records, 0..) |record, index| {
        for (current.record_batches) |batch| for (batch.response.content.records) |prior| {
            if (try g.duplicateRecordIssue(a, prior, record, index, null)) |issue| return issue;
        };
    };
    const entities = if (proposed == .entities) proposed.entities else (current.units[2] orelse return error.InvalidSpecificationUnit).response.content.entities;
    const records = if (proposed == .records) proposed.records else if (current.units[records_index]) |entry| entry.response.content.records else return null;
    var count: usize = 0;
    var first: ?usize = null;
    for (records, 0..) |record, index| if (record.content == .entity) {
        count += 1;
        if (first == null) first = index;
    };
    if (proposed == .records) {
        if (current.completed == records_index) for (current.record_batches) |batch| for (batch.response.content.records) |record| if (record.content == .entity) {
            count += 1;
        };
        if (entities.disposition == .required and count == 0 and current.record_cursor + 1 < current.record_group_count) return null;
    }
    if (g.spec.entityMembershipSatisfied(entities.disposition, count)) return null;
    const scope = if (count == 0 and proposed == .records) try entityInsertionScope(a, current, context) else null;
    errdefer if (scope) |owner_scope| a.free(owner_scope.basis_source_group_ids);
    return .{
        .unit = checked.unit,
        .field = if (proposed == .records and first != null) .{ .target = .{ .record = first.? } } else .unit,
        .rule = .entity_membership,
        .observed = null,
        .blocked = if (scope != null and scope.?.outcome != .current_group) .entity_insertion_scope else null,
        .membership = .{ .disposition = entities.disposition, .entity_count = count, .insertion_scope = scope },
        .detail = if (scope) |owner_scope| switch (owner_scope.outcome) {
            .current_group => "The fixed entity decision requires at least one entity record; none was supplied.",
            .multiple_basis_groups => "The required entity basis selects several source groups; this batch cannot choose its owner. A separately authorized owner-bound rebuild is required.",
            .outside_writable_group => try std.fmt.allocPrint(a, "The required entity basis selects source group {d}, but the current writable batch is source group {d}. Insertion here would change its source assignment; an owner-bound rebuild is required.", .{ owner_scope.basis_source_group_ids[0].ordinal, owner_scope.writable_source_group_id.?.ordinal }),
            .no_writable_group => "The assembled specification lacks a required entity, but no record batch is currently writable. An owner-bound rebuild is required.",
        } else if (count == 0) "The fixed entity decision requires at least one entity record; none was supplied." else "Entity records contradict the fixed not_applicable decision.",
    };
}

/// Resolve only an existing, admitted association. Native code does not decide
/// which of several business groups ought to own a new entity.
pub fn entityInsertionScope(a: std.mem.Allocator, current: Session, context: p.Context) Error!@import("specification_candidate.zig").EntityInsertionScope {
    if (!current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    const checked = current.units[2] orelse return error.InvalidSpecificationUnit;
    if (checked.unit != .entities or checked.response != .content or checked.response.content != .entities) return error.InvalidSpecificationUnit;
    const basis = checked.response.content.entities.basis;
    if (basis.source_group_ids.len == 0) return error.InvalidSpecificationUnit;
    const groups = try p.validateAssociation(.canonical, a, context.inputs, @import("reference_support.zig").records(context.references), basis.source_group_ids, basis.provenance, .content);
    errdefer a.free(groups);
    const writable = if (current.completed == records_index and current.record_cursor < current.record_group_count) scope: {
        const bound = try currentBinding(a, current, context);
        defer a.free(bound.records.selection.claim_ids);
        break :scope bound.records.signal;
    } else null;
    return .{ .basis_source_group_ids = groups, .writable_source_group_id = writable, .outcome = if (writable == null) .no_writable_group else if (groups.len != 1) .multiple_basis_groups else if (groups[0].ordinal != writable.?.ordinal) .outside_writable_group else .current_group };
}

pub fn assemble(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, current: Session) Error!@import("specification_identity.zig").Assigned {
    if (current.completed != unit_count or !current.reference_state.eql(context.inputs.corpus.state_id)) return error.InvalidSpecificationUnit;
    try validateRecordAssignments(allocator, current, context);
    var records: std.ArrayList(g.spec.RecordProposal) = .empty;
    for (current.units, 0..) |entry, index| {
        const checked = entry orelse return error.InvalidSpecificationUnit;
        // Full-candidate revalidation uses the same owning unit validator.
        const result = switch (try g.revalidate(allocator, validator, context, try unit(index), checked.response)) {
            .valid => |valid| valid,
            .invalid => return error.InvalidSpecificationUnit,
        };
        if (result.response != .content) return error.InvalidSpecificationUnit;
        if (try checkConsistency(allocator, current, context, result) != null) return error.InvalidSpecificationUnit;
        if (result.response.content == .records) {
            // Canonical section order is a projection; candidate indices and
            // repair origins retain the model's order throughout the session.
            for (std.enums.values(g.spec.Kind)) |kind| for (result.response.content.records) |record| {
                if (record.content == kind) try records.append(allocator, record);
            };
        }
    }
    const entities = current.units[2].?.response.content.entities;
    return @import("specification_identity.zig").assign(allocator, .{
        .display_name = current.units[0].?.response.content.brief.title,
        .primary_user_story = current.units[1].?.response.content.primary_user_story,
        .entities = entities,
        .records = records.items,
    }, current.starting_ledger);
}

/// Locate a canonical ID in the retained request order, without reordering
/// candidate values or their per-field repair origins.
pub fn recordIndex(current: Session, id: g.spec.Id) Error!usize {
    if (current.completed != unit_count) return error.InvalidSpecificationUnit;
    const checked = current.units[records_index] orelse return error.InvalidSpecificationUnit;
    if (checked.unit != .records or checked.response != .content or checked.response.content != .records) return error.InvalidSpecificationUnit;
    var ordinal = current.starting_ledger.next[@intFromEnum(id.kind)];
    for (checked.response.content.records, 0..) |record, index| {
        if (record.content != id.kind) continue;
        if (ordinal == id.ordinal) return index;
        ordinal = std.math.add(u32, ordinal, 1) catch return error.InvalidSpecificationUnit;
    }
    return error.InvalidSpecificationUnit;
}

/// A completed unit may change only through an exact authorized merge. This
/// boundary revalidates the whole affected unit before it becomes checked data.
pub fn replaceCompleted(allocator: std.mem.Allocator, validator: @import("typed_text.zig").Validator, context: p.Context, current: Session, index: usize, response: g.CanonicalResponse, merged: @import("atomic_repair.zig").Merge, origins: @import("specification_candidate.zig").Origins) Error!Session {
    if (current.completed != unit_count or index >= unit_count or current.units[index] == null or current.revision != merged.revision_before) return error.InvalidSpecificationUnit;
    var checked = switch (try g.revalidate(allocator, validator, context, try unit(index), response)) {
        .valid => |value| value,
        .invalid => return error.InvalidSpecificationUnit,
    };
    checked.origins = origins;
    checked.last_repair = merged;
    var next = current;
    next.revision = merged.revision_after;
    next.units[index] = checked;
    if (try checkConsistency(allocator, next, context, checked) != null) return error.InvalidSpecificationUnit;
    return next;
}
