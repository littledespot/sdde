//! Read-only review assignments derived from native subjects and canonical text.
const std = @import("std");
const authority = @import("required_authority.zig");
const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");

pub const Field = struct { slot: authority.Slot, text: []const u8, provenance: spec.Provenance, record: ?spec.IdentifiedRecord = null };
/// A reference obligation keeps its native subject through support review and
/// omission attribution. Surrounding authored content does not redefine it.
pub const ReferenceSubject = union(enum) {
    source: @import("reference_identity.zig").SourceId,
    signal: @import("source_omission_context.zig").Signal,
    token: @import("model_evidence.zig").Token,
    conflict: @import("source_omission_context.zig").Conflict,
};
pub const Subject = union(enum) {
    source_preservation: struct {},
    candidate_field: Field,
    collection: Collection,
    entity_applicability: EntityApplicability,
    reference: ReferenceSubject,
};

/// Purpose-free business facts. Review instructions belong to the selected prompt.
pub const BusinessContext = struct {
    brief: struct { title: spec.Scalar, description: spec.Scalar, primary_goal: spec.Scalar },
    candidate: spec.CapturedDocument,
    entity_basis: spec.Scalar,
};
pub const Collection = struct { slot: authority.Slot, records: []const spec.CapturedRecord, context: BusinessContext };
pub const EntityApplicability = struct { disposition: spec.Applicability, basis: spec.Scalar, context: BusinessContext };
pub const BusinessSubject = union(enum) {
    field: struct { slot: authority.Slot, text: []const u8, record: ?spec.CapturedRecord = null, context: BusinessContext },
    collection: Collection,
    entity_applicability: EntityApplicability,
};

/// Complete native assignment ownership. Source review owns business units;
/// principle review assesses every subject against the current selected set.
/// Collection coverage remains its own duty, not a pass inferred from members.
pub const AssignmentUnit = union(enum) {
    principle_set,
    brief,
    primary_user_story,
    entities,
    record: spec.Id,
    collection: authority.Slot,
    reference: authority.Unit,
    singleton: authority.Id,
};
pub fn assignmentUnit(a: std.mem.Allocator, inputs: authority.Inputs, id: authority.Id) authority.Error!AssignmentUnit {
    if (inputs.projection == .principle_assessment) {
        const context = inputs.principle_context orelse return error.InvalidRequiredAuthority;
        var arena: std.heap.ArenaAllocator = .init(a);
        defer arena.deinit();
        const assigned = try @import("principle_assessment.zig").subjects(arena.allocator(), context.business);
        if (id.kind != .policy_predicate or id.slot != .compliance or id.unit != .decision or id.unit.decision.ordinal == 0 or id.unit.decision.ordinal > assigned.len or context.selection.chunks.len == 0) return error.InvalidRequiredAuthority;
        return .principle_set;
    }
    if (inputs.projection != .specification) return .{ .singleton = id };
    return businessUnit(id);
}
fn businessUnit(id: authority.Id) authority.Error!AssignmentUnit {
    return switch (id.unit) {
        .record => |record| .{ .record = record },
        .feature => switch (id.slot) {
            .display_name, .description, .primary_goal => .brief,
            .primary_user_story => .primary_user_story,
            .entities => .entities,
            .acceptance_criteria, .functional_requirements, .scenario_coverage => .{ .collection = id.slot },
            else => error.InvalidRequiredAuthority,
        },
        .source, .signal, .token, .conflict => .{ .reference = id.unit },
        .decision => error.InvalidRequiredAuthority,
    };
}

fn collection(a: std.mem.Allocator, slot: authority.Slot, context: BusinessContext) authority.Error!Collection {
    var selected: std.ArrayList(spec.CapturedRecord) = .empty;
    errdefer selected.deinit(a);
    for (context.candidate.records) |record| {
        if (try @import("specification_authority.zig").collectionContains(slot, std.meta.activeTag(record.content))) try selected.append(a, record);
    }
    return .{ .slot = slot, .records = try selected.toOwnedSlice(a), .context = context };
}

fn field(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id) (provenance.Error || authority.Error)!?Field {
    if (@import("specification_authority.zig").featureField(inputs, id)) |selected| return .{
        .slot = id.slot,
        .text = (try @import("specification_projection.zig").scalar(a, context, selected)).bytes,
        .provenance = selected.provenance,
    };
    if (try @import("specification_authority.zig").recordField(inputs, id)) |selected| return .{
        .slot = id.slot,
        .text = (try @import("specification_projection.zig").recordScalar(a, context, selected.record.proposal, selected.field.value)).bytes,
        .provenance = selected.field.provenance,
        .record = selected.record,
    };
    return null;
}

/// Resolve a native business assignment without exposing its authority tuple or
/// importing source-review instructions. Free-text policies can relate different
/// requirements, so every subject retains the complete resolved business context.
pub fn projectBusiness(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id) (provenance.Error || authority.Error)!BusinessSubject {
    const projection = @import("specification_projection.zig");
    const candidate = inputs.specification orelse return error.InvalidRequiredAuthority;
    // Preserve complete business-view validation even for a focused packet.
    const resolved = try projection.project(a, context, candidate);
    const brief = inputs.brief orelse return error.InvalidRequiredAuthority;
    const related: BusinessContext = .{
        .brief = .{ .title = try projection.scalar(a, context, brief.title), .description = try projection.scalar(a, context, brief.description), .primary_goal = try projection.scalar(a, context, brief.primary_goal) },
        .candidate = resolved,
        .entity_basis = try projection.scalar(a, context, candidate.entities.basis),
    };
    if (try field(a, inputs, context, id)) |selected| return .{ .field = .{
        .slot = selected.slot,
        .text = selected.text,
        .record = if (selected.record) |record| for (resolved.records) |sibling| {
            if (std.meta.eql(sibling.id.?, record.id)) break sibling;
        } else return error.InvalidRequiredAuthority else null,
        .context = related,
    } };
    if (id.unit != .feature) return error.InvalidRequiredAuthority;
    return switch (id.slot) {
        .acceptance_criteria, .functional_requirements, .scenario_coverage => .{ .collection = try collection(a, id.slot, related) },
        .entities => .{ .entity_applicability = .{ .disposition = candidate.entities.disposition, .basis = related.entity_basis, .context = related } },
        else => error.InvalidRequiredAuthority,
    };
}

/// Focus the current target without changing evidence eligibility.
pub fn project(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id) (provenance.Error || authority.Error)!Subject {
    if (authority.policy(id) == null) return error.InvalidRequiredAuthority;
    switch (id.unit) {
        .source, .signal, .token, .conflict => return .{ .reference = try projectReference(a, inputs, context, id) },
        .feature, .record => {},
        .decision => return error.InvalidRequiredAuthority,
    }
    const target = try field(a, inputs, context, id);
    if (target) |selected| return .{ .candidate_field = selected };
    if (inputs.specification != null and inputs.brief != null and id.unit == .feature) switch (id.slot) {
        .acceptance_criteria, .functional_requirements, .scenario_coverage => return .{ .collection = (try projectBusiness(a, inputs, context, id)).collection },
        .entities => return .{ .entity_applicability = (try projectBusiness(a, inputs, context, id)).entity_applicability },
        else => {},
    };
    if (id.unit == .feature and inputs.specification == null) return .{ .source_preservation = .{} };
    return error.InvalidRequiredAuthority;
}

fn projectReference(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id) (provenance.Error || authority.Error)!ReferenceSubject {
    const records = inputs.references orelse return error.InvalidRequiredAuthority;
    return switch (id.unit) {
        .source => |source| found: {
            for (context.inputs.corpus.sources) |selected| if (std.meta.eql(selected.id, source)) break :found .{ .source = source };
            return error.InvalidRequiredAuthority;
        },
        .signal => |signal_id| found: {
            for (records.signals) |signal| if (std.meta.eql(signal.id, signal_id)) break :found .{ .signal = try @import("source_omission_context.zig").projectSignal(a, records, context, signal) };
            return error.InvalidRequiredAuthority;
        },
        .token => |token| found: {
            const view = try @import("model_evidence.zig").project(a, records.items.entries);
            for (view.preserved_tokens) |selected| if (std.meta.eql(selected.id, token)) break :found .{ .token = selected };
            return error.InvalidRequiredAuthority;
        },
        .conflict => |conflict_id| found: {
            for (records.conflicts) |conflict| if (std.meta.eql(conflict.id, conflict_id)) break :found .{ .conflict = try @import("source_omission_context.zig").projectConflict(a, records, context, conflict) };
            return error.InvalidRequiredAuthority;
        },
        .feature, .record, .decision => error.InvalidRequiredAuthority,
    };
}

/// Attribution compares business values, not canonical fragment bookkeeping.
/// It keeps the assigned subject and its surrounding candidate without importing
/// the source-review task or offering another verdict.
pub const LossSubject = union(enum) {
    business: BusinessSubject,
    brief_field: struct { slot: authority.Slot, text: []const u8, brief: @import("specification_projection.zig").Brief },
    pending_subject: struct { slot: authority.Slot, brief: ?@import("specification_projection.zig").Brief = null },
    reference: ReferenceSubject,
};

pub fn projectLoss(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id) (provenance.Error || authority.Error)!LossSubject {
    if (authority.policy(id) == null) return error.InvalidRequiredAuthority;
    switch (id.unit) {
        .source, .signal, .token, .conflict => return .{ .reference = try projectReference(a, inputs, context, id) },
        .feature, .record => {},
        .decision => return error.InvalidRequiredAuthority,
    }
    if (inputs.specification != null and inputs.brief != null) return .{ .business = try projectBusiness(a, inputs, context, id) };
    if (inputs.brief) |brief| {
        const resolved = try @import("specification_projection.zig").brief(a, context, brief);
        if (try field(a, inputs, context, id)) |target| return .{ .brief_field = .{ .slot = id.slot, .text = target.text, .brief = resolved } };
        return .{ .pending_subject = .{ .slot = id.slot, .brief = resolved } };
    }
    // A not-yet-authored field has no candidate to blame. Its current bound
    // producers and the fixed finding remain in the surrounding loss packet.
    return .{ .pending_subject = .{ .slot = id.slot } };
}
