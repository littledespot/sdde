//! Immutable generation evidence and candidate dependencies for native repair.
const std = @import("std");
const session = @import("specification_session.zig");
const provenance = @import("specification_provenance.zig");
const candidates = @import("specification_candidate.zig");
pub const Facts = struct {
    session: session.Session,
    input: []const u8,
    policy_ids: []const []const u8,
    rules: []const @import("naming_policy.zig").BoundRule,
    passive_records: []const @import("passive_literals.zig").Record,
    passive_occurrences: []const @import("passive_literals.zig").Occurrence,
    candidate: candidates.Candidate,
};
pub fn capture(a: std.mem.Allocator, current: session.Session, context: provenance.Context, candidate: candidates.Candidate) session.Error!Facts {
    if (!context.registry.grammar.policy.toolchain_identity.eql(context.current.identity())) return error.StaleNamingPolicy;
    const packet = try session.packet(a, current, context);
    defer @import("model_input_packet.zig").release(packet);
    return .{ .session = current, .input = try a.dupe(u8, packet.body()), .policy_ids = context.registry.grammar.policy.policy_ids, .rules = context.registry.grammar.policy.rules, .passive_records = context.registry.records, .passive_occurrences = context.registry.occurrences, .candidate = candidate };
}
pub fn snapshot(a: std.mem.Allocator, current: session.Session, context: provenance.Context, candidate: candidates.Candidate) session.Error!@import("atomic_repair.zig").Snapshot {
    const facts = try capture(a, current, context, candidate);
    defer a.free(facts.input);
    return @import("atomic_repair.zig").snapshot(Facts, a, facts);
}
