const bindings = @import("feature_log_retention_child_bindings.zig");
const runtime = @import("../domain/feature_log_stream.zig");

pub const Outcome = union(enum) { ok, blocked: runtime.FailureCode };

pub fn run(children: bindings.ChildBindings) Outcome {
    switch (children.invokeResolveStream()) {
        .ok => {},
        .failed => |failure| return .{ .blocked = failure },
    }
    switch (children.invokeAcquire()) {
        .ok => {},
        .failed => |failure| return .{ .blocked = failure },
    }
    var failure: ?runtime.FailureCode = null;
    switch (children.invokePrune()) {
        .ok => {},
        .failed => |value| failure = value,
    }
    switch (children.invokeRelease()) {
        .ok => {},
        .failed => |value| failure = value,
    }
    return if (failure) |value| .{ .blocked = value } else .ok;
}
