//! Read-only review assignments derived from native subjects and canonical text.
const std = @import("std");
const authority = @import("required_authority.zig");
const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");

pub const Scope = enum { focused, dependencies };
pub const Field = struct { slot: authority.Slot, text: []const u8, provenance: spec.Provenance, record: ?spec.IdentifiedRecord = null };
pub const Subject = union(enum) {
    source_preservation: struct {},
    candidate_field: Field,
    collection: Collection,
    entity_applicability: EntityApplicability,
    reference_signal: struct { signal: @import("model_evidence.zig").Signal, exact_value: ?[]const u8 = null },
    producer_localization: struct { target: ?Field, candidate: ?spec.IdentifiedContent, brief: ?spec.Brief },
    candidate_support: struct {
        instruction: []const u8 = "Assess the assigned requirement in the surrounding candidate. Preserve required, optional, excluded and prohibited roles; matching words or citations alone do not establish support. Resolve passive references to their display values; a filename does not express the behavior in that file. Accept source-backed exclusions; optional sections need no filler.",
        candidate: ?spec.IdentifiedContent,
        brief: ?spec.Brief,
    },
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

/// Focus the current target without changing evidence eligibility. Producer
/// localization retains dependencies but has no support-assessment instruction.
pub fn project(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id, scope: Scope) (provenance.Error || authority.Error)!Subject {
    const target = try field(a, inputs, context, id);
    if (scope == .dependencies) return .{ .producer_localization = .{ .target = target, .candidate = inputs.specification, .brief = inputs.brief } };
    if (target) |selected| return .{ .candidate_field = selected };
    if (inputs.specification != null and inputs.brief != null and id.unit == .feature) switch (id.slot) {
        .acceptance_criteria, .functional_requirements, .scenario_coverage => return .{ .collection = (try projectBusiness(a, inputs, context, id)).collection },
        .entities => return .{ .entity_applicability = (try projectBusiness(a, inputs, context, id)).entity_applicability },
        else => {},
    };
    if (id.unit == .signal) {
        const records = inputs.references orelse return error.InvalidRequiredAuthority;
        for (records.signals) |signal| if (std.meta.eql(signal.id, id.unit.signal)) {
            const view = (try @import("model_evidence.zig").signals(a, &.{signal}))[0];
            const exact_value = if (signal.value.content == .preserved_token) value: {
                if (signal.value.claim_ids.len != 1) return error.InvalidRequiredAuthority;
                const token = @import("reference_support.zig").exact(records.items, signal.value.claim_ids[0]) catch return error.InvalidRequiredAuthority;
                break :value token.value.raw_value.bytes;
            } else null;
            return .{ .reference_signal = .{ .signal = view, .exact_value = exact_value } };
        };
        return error.InvalidRequiredAuthority;
    }
    if (inputs.specification == null and inputs.brief == null) return .{ .source_preservation = .{} };
    return .{ .candidate_support = .{ .candidate = inputs.specification, .brief = inputs.brief } };
}
