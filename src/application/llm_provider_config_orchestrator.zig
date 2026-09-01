const std = @import("std");
const child_bindings = @import("llm_provider_config_child_bindings.zig");
const service = @import("llm_provider_config_service.zig");

pub const Outcome = union(enum) {
    ready: service.LLMProviderConfigService,
    failed,
    cancelled,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*value| value.deinit(),
            .failed, .cancelled => {},
        }
        self.* = undefined;
    }
};

pub fn run(children: child_bindings.ChildBindings) Outcome {
    if (terminal(children.invokeLocate())) |outcome| return outcome;
    if (terminal(children.invokeRead())) |outcome| return outcome;
    return .{ .ready = children.takeService() };
}

fn terminal(step: child_bindings.StepOutcome) ?Outcome {
    return switch (step) {
        .ok => null,
        .failed => .failed,
        .cancelled => .cancelled,
    };
}

test "coordinates locate then read and stops on each terminal outcome" {
    inline for (.{
        .{ .terminal_step = Step.locate, .cancelled = false },
        .{ .terminal_step = Step.read, .cancelled = false },
        .{ .terminal_step = Step.locate, .cancelled = true },
        .{ .terminal_step = Step.read, .cancelled = true },
    }) |scenario| {
        var spy: Spy = .{
            .terminal_step = scenario.terminal_step,
            .cancelled = scenario.cancelled,
        };
        var outcome = run(spy.bindings());
        defer outcome.deinit();
        try std.testing.expect(if (scenario.cancelled)
            outcome == .cancelled
        else
            outcome == .failed);
        const expected: []const Step = switch (scenario.terminal_step) {
            .locate => &.{.locate},
            .read => &.{ .locate, .read },
        };
        try std.testing.expectEqualSlices(Step, expected, spy.calls[0..spy.call_count]);
        try std.testing.expect(!spy.service_taken);
    }
}

const Step = enum { locate, read };

const Spy = struct {
    terminal_step: Step,
    cancelled: bool,
    calls: [2]Step = undefined,
    call_count: usize = 0,
    service_taken: bool = false,

    fn bindings(self: *Spy) child_bindings.ChildBindings {
        return .{ .context = self, .vtable = &spy_vtable };
    }

    fn invoke(self: *Spy, step: Step) child_bindings.StepOutcome {
        self.calls[self.call_count] = step;
        self.call_count += 1;
        if (step != self.terminal_step) return .ok;
        return if (self.cancelled) .cancelled else .failed;
    }
};

fn spyLocate(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.locate);
}

fn spyRead(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.read);
}

fn spyTakeService(context: *anyopaque) service.LLMProviderConfigService {
    const spy: *Spy = @ptrCast(@alignCast(context));
    spy.service_taken = true;
    unreachable;
}

const spy_vtable: child_bindings.ChildBindings.VTable = .{
    .locate = spyLocate,
    .read = spyRead,
    .take_service = spyTakeService,
};
