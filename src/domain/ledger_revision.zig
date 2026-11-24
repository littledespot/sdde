/// The revision of one ledger: a counter that a transition compares with the revision the writer read, so a stale
/// writer is refused. Each ledger names its own type, so a revision of one ledger cannot be passed where another
/// ledger's is expected; the name is the type's identity and nothing else.
pub fn Revision(comptime ledger: []const u8) type {
    return struct {
        value: u64,

        pub const initial: @This() = .{ .value = 0 };
        pub const owner = ledger;

        pub fn eql(left: @This(), right: @This()) bool {
            return left.value == right.value;
        }
    };
}

const testing = @import("std").testing;

test "the four ledgers' revisions are pairwise distinct types, so no ledger accepts another's" {
    const types = [_]type{
        @import("model_request_identity.zig").LedgerRevision,
        @import("model_attempt_accounting.zig").Revision,
        @import("provider_operation_lifecycle.zig").Revision,
        @import("workflow_token_accounting.zig").Revision,
    };
    inline for (types, 0..) |left, index| {
        inline for (types[index + 1 ..]) |right| try testing.expect(left != right);
    }
}

test "each ledger's revision is its own type and compares by value" {
    const request = Revision("request");
    const attempt = Revision("attempt");
    try testing.expect(request != attempt);
    try testing.expect(request.initial.eql(.{ .value = 0 }));
    try testing.expect(!request.initial.eql(.{ .value = 1 }));
    try testing.expect(Revision("request") == request);
}
