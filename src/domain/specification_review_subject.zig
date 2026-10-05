//! Read-only review assignments derived from native subjects and canonical text.
const std = @import("std");
const authority = @import("required_authority.zig");
const spec = @import("specification.zig");
const provenance = @import("specification_provenance.zig");

pub const Scope = enum { focused, dependencies };
pub const Subject = union(enum) {
    source_preservation: struct {},
    candidate_field: struct { slot: authority.Slot, text: []const u8, provenance: spec.Provenance },
    candidate_support: struct {
        instruction: []const u8 = "Assess the assigned requirement in the surrounding candidate. Preserve required, optional, excluded and prohibited roles; matching words or citations alone do not establish support. Resolve passive references to their display values; a filename does not express the behavior in that file. Accept source-backed exclusions; optional sections need no filler.",
        candidate: ?spec.IdentifiedContent,
        brief: ?spec.Brief,
    },
};

/// Scalar feature fields are independent assignments. Record/coverage reviews
/// and producer localization retain the surrounding candidate they depend on.
pub fn project(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id, scope: Scope) provenance.Error!Subject {
    if (inputs.specification == null and inputs.brief == null) return .{ .source_preservation = .{} };
    if (scope == .focused) {
        if (@import("specification_authority.zig").featureField(inputs, id)) |selected| return .{ .candidate_field = .{
            .slot = id.slot,
            .text = (try @import("specification_projection.zig").scalar(a, context, selected)).bytes,
            .provenance = selected.provenance,
        } };
    }
    return .{ .candidate_support = .{ .candidate = inputs.specification, .brief = inputs.brief } };
}
