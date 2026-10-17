const std = @import("std");
test {
    _ = @import("dispatch.zig");
    _ = @import("admission.zig");
    _ = @import("experiment.zig");
    _ = @import("upstream.zig");
    _ = @import("feasibility.zig");
    _ = @import("assessment.zig");
    _ = @import("candidates.zig");
    _ = @import("freeze.zig");
    _ = @import("acquisition.zig");
    _ = @import("scoring.zig");
    _ = @import("useful_completion.zig");
    _ = @import("qualification_budget.zig");
    _ = @import("phase2_decision.zig");
}

test "baseline commands require explicit inputs and never infer live approval" {
    const cli = @import("cli.zig");
    try std.testing.expectError(error.InvalidArguments, cli.parse(&.{}));
    try std.testing.expectError(error.InvalidArguments, cli.parse(&.{ "acquire", "--freeze", "freeze.json" }));
    try std.testing.expectError(error.InvalidArguments, cli.parse(&.{ "acquire", "--freeze", "freeze.json", "--live", "--live" }));
    try std.testing.expectError(error.InvalidEvaluationContract, cli.parse(&.{ "acquire", "--freeze", "../freeze.json", "--live" }));
    try std.testing.expect((try cli.parse(&.{ "acquire", "--freeze", "run/freeze.json", "--live" })) == .acquire);
    try std.testing.expectError(error.InvalidArguments, cli.parse(&.{ "prepare", "--protocol", "p.json", "--cases", "c.json", "--template-case", "w.json" }));
    try std.testing.expectError(error.InvalidArguments, cli.parse(&.{ "prepare", "--protocol", "p.json", "--cases", "c.json", "--template-case", "w.json", "--budget-plan", "b.json" }));
    try std.testing.expect((try cli.parse(&.{ "prepare", "--protocol", "p.json", "--cases", "c.json", "--template-case", "w.json", "--budget-plan", "b.json", "--rubric", "r.json" })) == .prepare);
    try std.testing.expect((try cli.parse(&.{ "score", "--freeze", "f.json", "--cases", "c.json", "--acquisition", "a.json", "--assessments", "s.json" })) == .score);
}
