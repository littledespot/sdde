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
    reference_signal: struct { signal: @import("model_evidence.zig").Signal, exact_value: ?[]const u8 = null },
    producer_localization: struct { target: ?Field, candidate: ?spec.IdentifiedContent, brief: ?spec.Brief },
    candidate_support: struct {
        instruction: []const u8 = "Assess the assigned requirement in the surrounding candidate. Preserve required, optional, excluded and prohibited roles; matching words or citations alone do not establish support. Resolve passive references to their display values; a filename does not express the behavior in that file. Accept source-backed exclusions; optional sections need no filler.",
        candidate: ?spec.IdentifiedContent,
        brief: ?spec.Brief,
    },
};

/// Focus the current target without changing evidence eligibility. Producer
/// localization retains dependencies but has no support-assessment instruction.
pub fn project(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id, scope: Scope) (provenance.Error || authority.Error)!Subject {
    var target: ?Field = null;
    if (@import("specification_authority.zig").featureField(inputs, id)) |selected| target = .{
        .slot = id.slot,
        .text = (try @import("specification_projection.zig").scalar(a, context, selected)).bytes,
        .provenance = selected.provenance,
    } else if (try @import("specification_authority.zig").recordField(inputs, id)) |selected| target = .{
        .slot = id.slot,
        .text = (try @import("specification_projection.zig").recordScalar(a, context, selected.record.proposal, selected.field.value)).bytes,
        .provenance = selected.field.provenance,
        .record = selected.record,
    };
    if (scope == .dependencies) return .{ .producer_localization = .{ .target = target, .candidate = inputs.specification, .brief = inputs.brief } };
    if (target) |selected| return .{ .candidate_field = selected };
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
