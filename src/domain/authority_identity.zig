//! Shared authority identities, not evidence that an authority is current.
const std = @import("std");
pub const Canonical = struct { kind: enum { principles, specification, plan, tasks }, ordinal: u64, revision: u64 };
pub const Authority = union(enum) {
    reference: @import("reference_identity.zig").StateId,
    canonical: Canonical,

    pub fn valid(self: Authority) bool {
        return switch (self) {
            .reference => |id| id.bytes.len != 0,
            .canonical => |value| value.ordinal != 0 and value.revision != 0,
        };
    }
    pub fn eql(self: Authority, other: Authority) bool {
        if (std.meta.activeTag(self) != std.meta.activeTag(other)) return false;
        return switch (self) {
            .reference => |id| id.eql(other.reference),
            .canonical => |value| std.meta.eql(value, other.canonical),
        };
    }
};
