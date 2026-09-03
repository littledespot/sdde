const bindings = @import("feature_log_policy_transition_child_bindings.zig");
const log_stream = @import("../domain/feature_log_stream.zig");

pub const Outcome = union(enum) { ok, blocked: log_stream.FailureCode, invalid };

/// Coordinates a validated transition using runner-owned child bindings only.
pub fn run(children: bindings.ChildBindings) Outcome {
    if (children.invokeValidate() == .invalid) return .invalid;
    switch (children.invokeCloseCurrent()) {
        .dropped, .persisted => {},
        .blocked => |failure| return .{ .blocked = failure },
    }
    return switch (children.invokePrepareNext()) {
        .dropped, .persisted => .ok,
        .blocked => |failure| .{ .blocked = failure },
    };
}
