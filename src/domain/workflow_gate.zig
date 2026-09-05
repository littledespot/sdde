const std = @import("std");
const data = @import("pipeline_data.zig");
const pipeline = @import("pipeline.zig");
const workflow = @import("workflow.zig");

pub const Decision = enum { accepted, rejected };

pub const Contract = struct {
    id: workflow.RegisteredRef,
    issuer: workflow.RegisteredRef,
    evidence: pipeline.DataKey,
    authority: []const pipeline.DataKey,

    pub fn eql(self: Contract, other: Contract) bool {
        return std.mem.eql(u8, self.id.bytes, other.id.bytes) and
            std.mem.eql(u8, self.issuer.bytes, other.issuer.bytes) and
            self.evidence == other.evidence and
            std.mem.eql(pipeline.DataKey, self.authority, other.authority);
    }
};

pub const Rejection = enum {
    missing_evidence,
    rejected_evidence,
    foreign_issuer,
    missing_authority,
    stale_authority,
    invalid_evidence,
};

pub fn check(contract: Contract, decision: Decision, origin: data.Origin, current: [data.key_count]?u64) ?Rejection {
    if (!std.mem.eql(u8, contract.issuer.bytes, origin.producer)) return .foreign_issuer;
    if (origin.outcome != .ok or decision != .accepted) return .rejected_evidence;
    for (contract.authority) |key| {
        const index = @intFromEnum(key);
        const generation = current[index] orelse return .missing_authority;
        if (origin.inputs[index] != generation) return .stale_authority;
    }
    return null;
}
