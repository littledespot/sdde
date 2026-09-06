const g = @import("../domain/specification_generation.zig");
pub const Payload = union(enum) {
    session: @import("../domain/specification_session.zig").Session,
    raw: []const u8,
    parsed: @import("../domain/specification_repair.zig").Candidate,
    repair_authorization: @import("../domain/specification_repair.zig").Authorization,
    repair_result: @import("../domain/specification_repair.zig").Replacement,
    checked: g.Checked,
    coverage: @import("../domain/specification_coverage.zig").Coverage,
    document: @import("../domain/specification.zig").CapturedDocument,
    rendered: []const u8,
    rejected: enum { invalid_unit },
};
pub const storage = @import("retained_candidate.zig").Storage(Payload, .{ .rejected = .invalid_unit });
