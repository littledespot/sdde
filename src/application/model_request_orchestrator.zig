const execution = @import("../domain/workflow_execution.zig");
const kernel = @import("../domain/model_request_kernel.zig");
const bindings = @import("model_request_child_bindings.zig");

/// Run one logical model request: invoke each stage through its runner-owned child
/// binding and follow only the stage's typed outcome, by the domain's transition table
/// (ADR 0030). A runner rejection ends the request at once and is returned unchanged. The
/// step finishes with `ok`, `invalid`, `failed` or `cancelled`; an outcome a stage cannot
/// produce is an authority rejection. The runner owns every count and bound.
pub fn run(children: bindings.ChildBindings) execution.Applied {
    var stage: bindings.Stage = .prepare_request;
    while (true) {
        const applied = children.invokeStage(stage);
        const outcome = switch (applied) {
            .rejected => return applied,
            .outcome => |tag| tag,
        };
        switch (kernel.next(stage, outcome) orelse return .{ .rejected = .authority }) {
            .stage => |following| stage = following,
            .finish => |tag| return .{ .outcome = tag },
        }
    }
}
