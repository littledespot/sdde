//! Typed progress of the two assessments. YAML owns calls and continuation.
const std = @import("std");
const authority = @import("required_authority.zig");
const support = @import("specification_support.zig");
const principles = @import("principle_assessment.zig");
pub const Source = support.Source;
pub const Policy = support.Contract(.principles);
pub const Pending = struct { source: @FieldType(Source.Collection, "accepted"), inputs: authority.Inputs };
pub const PolicyResult = struct { pending: Pending, result: Policy.Collection };
pub const Progress = union(enum) { initial, source: Source.Collection, pending: Pending, principles: PolicyResult };
pub const Advanced = struct { progress: Progress, outcome: enum { complete, more } };
pub const Error = Source.Error || Policy.Error;

pub fn advance(a: std.mem.Allocator, current: Progress, registry: @import("principle_registry.zig").Registry) Error!Advanced {
    return switch (current) {
        .initial, .pending => error.InvalidRequiredAuthority,
        .source => |reviewed| blk: {
            if (reviewed != .accepted) return error.InvalidRequiredAuthority;
            const inputs = reviewed.accepted.inputs;
            if (inputs.principle_assessment != null) return error.InvalidRequiredAuthority;
            const ledger = try authority.build(a, inputs);
            const result = try authority.reconcile(a, ledger, try authority.buildObservations(a, ledger));
            if (inputs.specification == null or result.continuation != .all_resolved) break :blk .{ .progress = current, .outcome = .complete };
            const selection = try @import("principle_registry.zig").select(a, registry, .{ .stage = .spec, .environment = null, .fileKind = null });
            const policy_inputs = try principles.project(a, .{ .business = try principles.businessInput(a, inputs), .registry = registry, .selection = selection });
            if (selection.chunks.len == 0) {
                var accepted = reviewed.accepted;
                accepted.inputs.principle_assessment = try principles.canonical(a, policy_inputs);
                break :blk .{ .progress = .{ .source = .{ .accepted = accepted } }, .outcome = .complete };
            }
            break :blk .{ .progress = .{ .pending = .{ .source = reviewed.accepted, .inputs = policy_inputs } }, .outcome = .more };
        },
        .principles => |reviewed| blk: {
            if (reviewed.result != .accepted) return error.InvalidRequiredAuthority;
            if (!try @import("principle_registry.zig").equal(a, registry, reviewed.pending.inputs.principle_context.?.registry)) return error.InvalidRequiredAuthority;
            var accepted = reviewed.pending.source;
            accepted.inputs.principle_assessment = try principles.canonical(a, reviewed.result.accepted.inputs);
            break :blk .{ .progress = .{ .source = .{ .accepted = accepted } }, .outcome = .complete };
        },
    };
}
