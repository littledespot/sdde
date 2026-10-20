//! Development acceptance retains native score accounting and grader
//! qualification as diagnostic facts. It cannot authorize workflow transitions or
//! provider requests.
const acceptance = @import("acceptance.zig");
const contracts = @import("contracts.zig");
const judgment = @import("judgment.zig");

pub const Qualification = enum { qualified, unresolved };
/// Model scores never accept or reject a specification, so a model-scored decision
/// is always unresolved. Only separately bound human adjudication can decide.
pub const Decision = enum { not_evaluated, input_changed, human_adjudication_required };
pub const Evidence = struct {
    qualification: Qualification = .unresolved,
    quality: ?acceptance.Quality = null,
    decision: Decision = .not_evaluated,
};

pub fn from(rubric: contracts.Rubric, result: judgment.Result, qualification: Qualification) Evidence {
    return .{
        .qualification = qualification,
        .quality = acceptance.quality(rubric, result),
        .decision = .human_adjudication_required,
    };
}
