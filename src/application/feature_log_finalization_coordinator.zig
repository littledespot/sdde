const bindings = @import("feature_log_finalization_child_bindings.zig");
const log_stream = @import("../domain/feature_log_stream.zig");

pub const Outcome = union(enum) { ok, blocked: log_stream.FailureCode, invalid };

/// Finalizes one runner-selected binding using runner-owned child bindings.
pub fn run(children: bindings.ChildBindings) Outcome {
    if (children.invokeValidate() == .invalid) return .invalid;
    if (children.target().mode == .historical) switch (children.invokePrepare()) {
        .dropped, .persisted => {},
        .blocked => |failure| return .{ .blocked = failure },
    };
    return switch (children.invokeClose()) {
        .dropped, .persisted => .ok,
        .blocked => |failure| .{ .blocked = failure },
    };
}
