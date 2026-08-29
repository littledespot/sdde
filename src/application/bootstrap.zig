const std = @import("std");
const config_error = @import("../domain/config_error.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const config_registry = @import("config_registry.zig");

pub const Outcome = union(enum) {
    ready: config_registry.Registry,
    failed: config_error.PublicError,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*registry| registry.deinit(),
            .failed => {},
        }
        self.* = undefined;
    }
};

pub fn run(children: child_bindings.ChildBindings) Outcome {
    switch (children.invokeLocate()) {
        .ok => {},
        .failed => |failure| return .{ .failed = failure },
    }
    switch (children.invokeRead()) {
        .ok => {},
        .failed => |failure| return .{ .failed = failure },
    }
    switch (children.invokeDecode()) {
        .ok => {},
        .failed => |failure| return .{ .failed = failure },
    }

    return .{ .ready = children.takeRegistry() };
}

test "coordinates child bindings in order and preserves a decode failure" {
    var spy: SpyBindings = .{ .fail_at = .decode };
    var outcome = run(spy.bindings());
    defer outcome.deinit();

    try std.testing.expectEqual(
        config_error.PublicError.ENGINE_CONFIG_PARSE_ERROR,
        outcome.failed,
    );
    try std.testing.expectEqualSlices(
        Step,
        &.{ .locate, .read, .decode },
        spy.calls[0..spy.call_count],
    );
}

test "stops after a failed locate binding" {
    var spy: SpyBindings = .{ .fail_at = .locate };
    var outcome = run(spy.bindings());
    defer outcome.deinit();

    try std.testing.expectEqual(
        config_error.PublicError.ENGINE_CONFIG_READ_ERROR,
        outcome.failed,
    );
    try std.testing.expectEqualSlices(
        Step,
        &.{.locate},
        spy.calls[0..spy.call_count],
    );
}

const Step = enum { locate, read, decode };

const SpyBindings = struct {
    fail_at: Step,
    calls: [3]Step = undefined,
    call_count: usize = 0,

    fn bindings(self: *SpyBindings) child_bindings.ChildBindings {
        return .{
            .context = self,
            .vtable = &spy_vtable,
        };
    }

    fn record(self: *SpyBindings, step: Step) child_bindings.StepOutcome {
        self.calls[self.call_count] = step;
        self.call_count += 1;
        if (self.fail_at != step) return .ok;
        return .{ .failed = switch (step) {
            .locate, .read => .ENGINE_CONFIG_READ_ERROR,
            .decode => .ENGINE_CONFIG_PARSE_ERROR,
        } };
    }
};

const spy_vtable: child_bindings.ChildBindings.VTable = .{
    .locate = spyLocate,
    .read = spyRead,
    .decode = spyDecode,
    .take_registry = spyTakeRegistry,
};

fn spyLocate(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.locate);
}

fn spyRead(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.read);
}

fn spyDecode(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *SpyBindings = @ptrCast(@alignCast(context));
    return spy.record(.decode);
}

fn spyTakeRegistry(_: *anyopaque) config_registry.Registry {
    unreachable;
}
