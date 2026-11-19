const bindings = @import("feature_log_retention_child_bindings.zig");
const runtime = @import("../domain/feature_log_stream.zig");

pub const Outcome = union(enum) { ok, blocked: runtime.FailureCode, cancelled };

pub fn run(children: bindings.ChildBindings) Outcome {
    switch (children.invokeAuthorize()) {
        .ok => {},
        .failed => |failure| return .{ .blocked = failure },
    }
    switch (children.invokeResolveStream()) {
        .ok => {},
        .failed => |failure| return .{ .blocked = failure },
    }
    switch (children.invokeAcquire()) {
        .ok => {},
        .failed => |failure| return .{ .blocked = failure },
        .cancelled => return .cancelled,
    }
    var stop: ?runtime.Stop = null;
    switch (children.invokePrune()) {
        .ok => {},
        .failed => |value| stop = .{ .blocked = value },
        .cancelled => stop = .cancelled,
    }
    // Release is always attempted, a cancelled prune included; a prune stop is the cause and is kept.
    switch (children.invokeRelease()) {
        .ok => {},
        .failed => |value| stop = stop orelse .{ .blocked = value },
    }
    return if (stop) |value| switch (value) {
        .blocked => |failure| .{ .blocked = failure },
        .cancelled => .cancelled,
    } else .ok;
}
