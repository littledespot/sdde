const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const a = @import("../../domain/required_authority.zig");
pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{ .id = "build-required-authority-observations", .kind = .action, .requires = &.{.required_authority_ledger}, .produces = &.{.required_authority_observations}, .side_effect = .none };
    pub fn execute(_: Action, allocator: std.mem.Allocator, ledger: a.Ledger) a.Error!a.Observations {
        const entries = try allocator.alloc(a.Observation, ledger.requirements.len);
        for (ledger.requirements, entries) |requirement, *entry| {
            var ids: std.ArrayList(a.EvidenceId) = .empty;
            for (ledger.inputs.evidence) |evidence| if (std.meta.eql(evidence.requirement, requirement.seed.id)) try ids.append(allocator, evidence.id);
            entry.* = .{ .requirement = requirement.seed.id, .inspected_authorities = requirement.seed.input_authorities, .evidence_ids = try ids.toOwnedSlice(allocator) };
        }
        return .{ .entries = entries };
    }
};
