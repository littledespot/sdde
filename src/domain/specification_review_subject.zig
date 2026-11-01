//! Read-only review subjects derived from native requirements before generation.
const std = @import("std");
const authority = @import("required_authority.zig");
const provenance = @import("specification_provenance.zig");

/// A reference obligation keeps its native subject through support review and
/// omission attribution. Surrounding authored content does not redefine it.
pub const ReferenceSubject = union(enum) {
    source: @import("reference_identity.zig").SourceId,
    signal: @import("source_omission_context.zig").Signal,
    token: @import("model_evidence.zig").Token,
    conflict: @import("source_omission_context.zig").Conflict,
};
/// No candidate exists before generation: a feature requirement asks whether the
/// sources support it, and a reference obligation keeps its native subject.
pub const Subject = union(enum) {
    source_preservation: struct {},
    reference: ReferenceSubject,
};

/// Focus the current target without changing evidence eligibility.
pub fn project(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id) (provenance.Error || authority.Error)!Subject {
    if (authority.policy(id) == null) return error.InvalidRequiredAuthority;
    return switch (id.unit) {
        .source, .signal, .token, .conflict => .{ .reference = try projectReference(a, inputs, context, id) },
        .feature => .{ .source_preservation = .{} },
        .record, .decision => error.InvalidRequiredAuthority,
    };
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
            for (view.exact_texts) |selected| if (std.meta.eql(selected.id, token)) break :found .{ .token = selected };
            return error.InvalidRequiredAuthority;
        },
        .conflict => |conflict_id| found: {
            for (records.conflicts) |conflict| if (std.meta.eql(conflict.id, conflict_id)) break :found .{ .conflict = try @import("source_omission_context.zig").projectConflict(a, records, context, conflict) };
            return error.InvalidRequiredAuthority;
        },
        .feature, .record, .decision => error.InvalidRequiredAuthority,
    };
}

/// Attribution keeps the assigned subject without importing the source-review
/// task or offering another verdict. A not-yet-authored field has no candidate
/// to blame; its bound producers and the fixed finding stay in the loss packet.
pub const LossSubject = union(enum) {
    pending_subject: struct { slot: authority.Slot },
    reference: ReferenceSubject,
};

pub fn projectLoss(a: std.mem.Allocator, inputs: authority.Inputs, context: provenance.Context, id: authority.Id) (provenance.Error || authority.Error)!LossSubject {
    if (authority.policy(id) == null) return error.InvalidRequiredAuthority;
    return switch (id.unit) {
        .source, .signal, .token, .conflict => .{ .reference = try projectReference(a, inputs, context, id) },
        .feature => .{ .pending_subject = .{ .slot = id.slot } },
        .record, .decision => error.InvalidRequiredAuthority,
    };
}
