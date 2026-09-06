const g = @import("../domain/specification_generation.zig");
pub const Payload = union(enum) {
    session: @import("../domain/specification_session.zig").Session,
    raw: []const u8,
    parsed: g.Response,
    checked: g.Checked,
    coverage: @import("../domain/specification_coverage.zig").Coverage,
    rejected: enum { invalid_unit },
};
pub const storage = @import("retained_candidate.zig").Storage(Payload, .{ .rejected = .invalid_unit });
