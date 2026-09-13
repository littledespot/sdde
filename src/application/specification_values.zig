const g = @import("../domain/specification_generation.zig");
pub const Payload = union(enum) {
    session: @import("../domain/specification_session.zig").Session,
    raw: @import("../domain/specification_candidate.zig").Raw,
    parsed: @import("../domain/specification_repair.zig").Candidate,
    repair_authorization: struct { authorization: @import("../domain/specification_repair.zig").Authorization, response: ?struct { value: @import("../domain/specification_repair.zig").Replacement, origin: @import("../domain/model_candidate_origin.zig").Origin } = null },
    checked: g.Checked,
    coverage_rejected: @import("../domain/specification_coverage.zig").Rejection,
    coverage_repair: @import("../domain/specification_coverage_repair.zig").Decision,
    coverage: @import("../domain/specification_coverage.zig").Coverage,
    document: @import("../domain/specification.zig").CapturedDocument,
    rendered: []const u8,
    prior_state: @import("../domain/specification_state.zig").Prior,
    publication_state: @import("../domain/specification_state.zig").State,
    reference_context: []const u8,
    reference_snapshot: @import("../domain/reference_snapshot.zig").Snapshot,
    unit_rejected: @import("../domain/specification_candidate.zig").Rejection,
    rejected,
};
pub const storage = @import("retained_candidate.zig").Storage(Payload, .rejected);
