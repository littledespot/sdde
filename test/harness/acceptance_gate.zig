//! Development acceptance combines native score accounting with explicit grader
//! provenance. It cannot authorize workflow transitions or provider requests.
const acceptance = @import("acceptance.zig");
const independence = @import("judge_independence.zig");
const contracts = @import("contracts.zig");
const judgment = @import("judgment.zig");

pub const Qualification = enum { qualified, unresolved };
pub const Reason = enum {
    not_evaluated,
    missing_threshold,
    uncertainty,
    no_applicable,
    self_grading,
    unknown_generation,
    grader_unqualified,
    input_changed,
    human_adjudication_required,
};
pub const Decision = union(enum) {
    passed,
    failed: acceptance.Failure,
    unresolved: Reason,
};
pub const Evidence = struct {
    independence: enum { not_checked, independent, self_grading, unknown_generation } = .not_checked,
    qualification: Qualification = .unresolved,
    quality: ?acceptance.Quality = null,
    decision: Decision = .{ .unresolved = .not_evaluated },
};

/// Model scores remain advisory. Only separately bound human adjudication can
/// authoritatively accept or reject a specification.
pub fn decide(quality: acceptance.Quality, identity: independence.Result, qualification: Qualification) Decision {
    _ = quality;
    _ = identity;
    _ = qualification;
    return .{ .unresolved = .human_adjudication_required };
}

pub fn from(rubric: contracts.Rubric, result: judgment.Result, identity: independence.Result, qualification: Qualification) Evidence {
    const quality = acceptance.quality(rubric, result);
    return .{
        .independence = switch (identity) {
            .independent => .independent,
            .self_grading => .self_grading,
            .unknown_generation => .unknown_generation,
        },
        .qualification = qualification,
        .quality = quality,
        .decision = decide(quality, identity, qualification),
    };
}
