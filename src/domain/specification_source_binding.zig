//! Native associations between authored values and complete current source groups.
//! Selection is model-assisted; membership and derived evidence are native facts.
const std = @import("std");
const r = @import("reference_reconciliation.zig");
const refs = @import("reference_support.zig");
const spec = @import("specification.zig");
const evidence = @import("reference_evidence.zig");
pub const Error = r.Error || spec.Error || error{InvalidSpecificationBinding};
pub const Mode = enum { content, question };
pub const Catalogue = struct { records: refs.Records, inputs: evidence.Inputs };
pub const EligibleSignal = struct { signal_id: r.SignalId, claim_ids: []const r.ClaimId };
pub const Association = struct { source_group_ids: []const r.SignalId, selection: spec.Selection };
pub const Rejection = struct {
    state_id: evidence.identity.StateId,
    partition_id: r.PartitionId,
    revision: u64,
    origin: ?@import("model_candidate_origin.zig").Origin,
    reason: enum { empty_catalogue, no_record_authoring_groups } = .empty_catalogue,
    eligible_signals: []const EligibleSignal,
};
pub const Unit = union(enum) { brief, primary_user_story, entities, records };
pub const RecordBound = struct { signal: r.SignalId, selection: spec.Selection, catalogue: Catalogue };
pub const Bound = union(enum) { brief: Catalogue, primary_user_story: Catalogue, entities: Catalogue, records: RecordBound };
pub const GuidanceMode = enum { authoring, repair };
const Requirement = @import("model_evidence.zig").Requirement;
pub const FieldGuidance = struct { purpose: ?[]const u8 = null };
/// Batch records inherit exactly one assignment. A feature-owned entity selects
/// its own nonempty set of eligible groups; neither boundary infers support.
pub fn validRecordGroupCount(kind: spec.Kind, count: usize) bool {
    return if (kind == .entity) count != 0 else count == 1;
}
pub const GroupGuidance = struct { signal_id: r.SignalId, requirements: []const Requirement };
/// A native membership fact, independent of field policy or semantic support.
pub fn tokenOnly(records: refs.Records, id: r.SignalId) Error!bool {
    for (records.signals) |signal| {
        if (signal.id.ordinal != id.ordinal) continue;
        return preservedTokensOnly(records, signal.value.claim_ids);
    }
    return error.InvalidSpecificationBinding;
}
fn preservedTokensOnly(records: refs.Records, claims: []const r.ClaimId) Error!bool {
    if (claims.len == 0) return error.InvalidSpecificationBinding;
    try r.unique(r.ClaimId, claims);
    for (claims) |claim| if ((try r.item(records.items, claim)).claim.content != .preserved_token) return false;
    return true;
}
pub const Guidance = union(enum) {
    brief: struct { title: FieldGuidance, description: FieldGuidance, primary_goal: FieldGuidance },
    primary_user_story: FieldGuidance,
    entities: FieldGuidance,
    records: struct { purpose: ?[]const u8 = null, signal: r.SignalId, requirements: []const Requirement },
};

pub fn guidance(a: std.mem.Allocator, bound: Bound, mode: GuidanceMode, requirements: []const Requirement, record_kinds: []const spec.Kind) Error!Guidance {
    return switch (bound) {
        .brief => .{ .brief = .{ .title = try fieldGuidance(a, .display_name, mode), .description = try fieldGuidance(a, .description, mode), .primary_goal = try fieldGuidance(a, .primary_goal, mode) } },
        .primary_user_story => .{ .primary_user_story = try fieldGuidance(a, .primary_user_story, mode) },
        .entities => .{ .entities = .{ .purpose = if (mode == .authoring) try std.fmt.allocPrint(a, "{s}\n{s}", .{ (try fieldGuidance(a, .entities, mode)).purpose.?, @import("required_authority_description.zig").record(a, .entity) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationBinding }) else null } },
        .records => |value| .{ .records = .{
            .purpose = if (mode == .authoring) @import("required_authority_description.zig").recordsFor(a, record_kinds) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationBinding else null,
            .signal = value.signal,
            .requirements = try assignedRequirements(a, value.selection, requirements),
        } },
    };
}
fn fieldGuidance(a: std.mem.Allocator, slot: @import("required_authority.zig").Slot, mode: GuidanceMode) Error!FieldGuidance {
    return .{ .purpose = if (mode == .authoring) @import("required_authority_description.zig").task(a, .{ .kind = if (slot == .entities) .entity_applicability else .feature_intent, .unit = .{ .feature = .singleton }, .slot = slot }) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationBinding else null };
}
fn assignedRequirements(a: std.mem.Allocator, selected: spec.Selection, requirements: []const Requirement) Error![]const Requirement {
    const result = try a.alloc(Requirement, selected.claim_ids.len);
    errdefer a.free(result);
    for (selected.claim_ids, result) |id, *copy| copy.* = for (requirements) |requirement| {
        if (id.ordinal == requirement.claim_id.ordinal) break requirement;
    } else return error.InvalidSpecificationBinding;
    return result;
}
pub fn groupGuidance(a: std.mem.Allocator, records: refs.Records, requirements: []const Requirement) Error![]const GroupGuidance {
    const available = try catalogue(a, records, .question);
    defer a.free(available);
    const result = try a.alloc(GroupGuidance, available.len);
    errdefer a.free(result);
    var completed: usize = 0;
    errdefer for (result[0..completed]) |entry| a.free(entry.requirements);
    for (available, result) |group, *copy| {
        copy.* = .{ .signal_id = group.signal_id, .requirements = try assignedRequirements(a, .{ .claim_ids = group.claim_ids, .clarification_response_ids = &.{} }, requirements) };
        completed += 1;
    }
    return result;
}
pub fn assigns(value: Guidance, id: r.ClaimId) bool {
    if (value == .records) for (value.records.requirements) |requirement| if (id.ordinal == requirement.claim_id.ordinal) return true;
    return false;
}
fn activeSignal(records: refs.Records, index: usize, mode: Mode) Error!bool {
    const signal = records.signals[index];
    for (records.signals[0..index]) |prior| if (prior.id.ordinal == signal.id.ordinal) return error.InvalidSpecificationBinding;
    if (signal.value.claim_ids.len == 0) return error.InvalidSpecificationBinding;
    try r.unique(r.ClaimId, signal.value.claim_ids);
    if (!(refs.eligibleSelection(records.dispositions, signal.value.claim_ids) catch return error.InvalidSpecificationBinding)) return false;
    if (mode == .content) for (signal.value.claim_ids) |id| {
        if (!spec.permitsPositiveMapping((try r.item(records.items, id)).claim.content)) return false;
    };
    return true;
}
fn recordSignal(records: refs.Records, index: usize) Error!bool {
    if (!try activeSignal(records, index, .question)) return false;
    return !try preservedTokensOnly(records, records.signals[index].value.claim_ids);
}
pub fn catalogue(a: std.mem.Allocator, records: refs.Records, mode: Mode) Error![]const EligibleSignal {
    var result: std.ArrayList(EligibleSignal) = .empty;
    errdefer result.deinit(a);
    for (records.signals, 0..) |signal, index| {
        if (try activeSignal(records, index, mode)) try result.append(a, .{ .signal_id = signal.id, .claim_ids = signal.value.claim_ids });
    }
    return result.toOwnedSlice(a);
}
pub fn resolveGroups(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, ids: []const r.SignalId, mode: Mode) Error!Association {
    if (ids.len == 0 or !records.items.state_id.eql(inputs.corpus.state_id)) return error.InvalidSpecificationBinding;
    try r.unique(r.SignalId, ids);
    var groups: std.ArrayList(r.SignalId) = .empty;
    errdefer groups.deinit(a);
    var claims: std.ArrayList(r.ClaimId) = .empty;
    errdefer claims.deinit(a);
    const available = try catalogue(a, records, mode);
    defer a.free(available);
    // Accepted occurrence order owns the canonical projection, not model order.
    for (available) |group| if (r.contains(r.SignalId, ids, group.signal_id)) {
        try groups.append(a, group.signal_id);
        for (group.claim_ids) |id| if (!r.contains(r.ClaimId, claims.items, id)) try claims.append(a, id);
    };
    if (groups.items.len != ids.len) return error.InvalidSpecificationBinding;
    const selected = refs.select(a, records.items, inputs, claims.items) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InvalidSpecificationBinding;
    defer a.free(selected.citation_ids);
    defer a.free(selected.scopes);
    const owned_claims = try claims.toOwnedSlice(a);
    errdefer a.free(owned_claims);
    return .{ .source_group_ids = try groups.toOwnedSlice(a), .selection = .{ .claim_ids = owned_claims, .clarification_response_ids = &.{} } };
}
pub fn selectGroups(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, ids: []const r.SignalId, mode: Mode) Error!spec.Selection {
    const resolved = try resolveGroups(a, records, inputs, ids, mode);
    a.free(resolved.source_group_ids);
    return resolved.selection;
}
pub fn recordCount(records: refs.Records) Error!usize {
    var count: usize = 0;
    for (records.signals, 0..) |_, index| if (try recordSignal(records, index)) {
        count += 1;
    };
    return count;
}
pub fn record(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, index: usize) Error!Bound {
    _ = try recordCount(records);
    var cursor: usize = 0;
    for (records.signals, 0..) |signal, signal_index| {
        if (!try recordSignal(records, signal_index)) continue;
        if (cursor == index) {
            const association = try resolveGroups(a, records, inputs, &.{signal.id}, .question);
            defer a.free(association.source_group_ids);
            return .{ .records = .{ .signal = signal.id, .selection = association.selection, .catalogue = .{ .records = records, .inputs = inputs } } };
        }
        cursor += 1;
    }
    return error.InvalidSpecificationBinding;
}
pub fn recordForGroup(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, id: r.SignalId) Error!Bound {
    _ = try recordCount(records);
    const eligible = for (records.signals, 0..) |signal, index| {
        if (signal.id.ordinal == id.ordinal) break try recordSignal(records, index);
    } else false;
    if (!eligible) return error.InvalidSpecificationBinding;
    const selected = try resolveGroups(a, records, inputs, &.{id}, .question);
    defer a.free(selected.source_group_ids);
    return .{ .records = .{ .signal = id, .selection = selected.selection, .catalogue = .{ .records = records, .inputs = inputs } } };
}
pub fn forUnit(a: std.mem.Allocator, records: refs.Records, inputs: evidence.Inputs, unit: Unit, record_index: usize) Error!Bound {
    const available: Catalogue = .{ .records = records, .inputs = inputs };
    return switch (unit) {
        .brief => .{ .brief = available },
        .primary_user_story => .{ .primary_user_story = available },
        .entities => .{ .entities = available },
        .records => record(a, records, inputs, record_index),
    };
}
pub fn validate(records: refs.Records, inputs: evidence.Inputs) Error!void {
    if (!records.items.state_id.eql(inputs.corpus.state_id) or try recordCount(records) == 0) return error.InvalidSpecificationBinding;
    for (records.signals, 0..) |signal, index| if (try activeSignal(records, index, .question)) for (signal.value.claim_ids) |id| {
        const item = try r.item(records.items, id);
        _ = evidence.resolve(inputs, .{ .state_id = records.items.state_id, .chunk_id = item.claim.chunk_id }) catch return error.InvalidSpecificationBinding;
    };
}
pub fn rejection(a: std.mem.Allocator, references: r.Accounted) Error!Rejection {
    const records = refs.records(references);
    if (try recordCount(records) != 0) return error.InvalidSpecificationBinding;
    const prior = references.records.assignments.checked.prior.prior;
    const available = try catalogue(a, records, .question);
    return .{ .state_id = records.items.state_id, .partition_id = prior.input.partition.id, .revision = prior.source.revision, .origin = prior.source.at(.signals, .record), .reason = if (available.len == 0) .empty_catalogue else .no_record_authoring_groups, .eligible_signals = available };
}
