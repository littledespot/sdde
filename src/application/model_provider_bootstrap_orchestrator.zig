const std = @import("std");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const child_bindings = @import("model_provider_bootstrap_child_bindings.zig");
const services = @import("model_provider_bootstrap_services.zig");

pub const Outcome = union(enum) {
    not_required,
    ready: services.ModelProviderBootstrapServices,
    failed: bootstrap_error.PublicError,
    cancelled,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*value| value.deinit(),
            .not_required, .failed, .cancelled => {},
        }
        self.* = undefined;
    }
};

pub fn run(children: child_bindings.ChildBindings) Outcome {
    if (terminal(children.invokeDeriveRequirement())) |outcome| return outcome;
    switch (children.requirement()) {
        .not_required => return .not_required,
        .required => {},
    }

    if (terminal(children.invokeLoadProviderConfig())) |outcome| return outcome;
    if (terminal(children.invokeDecodeProviderConfig())) |outcome| return outcome;
    if (terminal(children.invokeBuildRegistry())) |outcome| return outcome;
    if (terminal(children.invokeValidateRegistry())) |outcome| return outcome;
    if (terminal(children.invokeValidateAllowlist())) |outcome| return outcome;
    return .{ .ready = children.takeServices() };
}

fn terminal(step: child_bindings.StepOutcome) ?Outcome {
    return switch (step) {
        .ok => null,
        .failed => |failure| .{ .failed = failure },
        .cancelled => .cancelled,
    };
}

test "not-required preparation makes every provider child unreachable" {
    var spy: Spy = .{ .derived = .not_required };
    var outcome = run(spy.bindings());
    defer outcome.deinit();

    try std.testing.expect(outcome == .not_required);
    try std.testing.expectEqualSlices(Step, &.{.derive_requirement}, spy.calls());
}

test "required preparation stops on every failed child and preserves cancellation" {
    inline for (.{
        .{ .terminal_step = Step.derive_requirement, .cancelled = false },
        .{ .terminal_step = Step.load_provider_config, .cancelled = false },
        .{ .terminal_step = Step.decode_provider_config, .cancelled = false },
        .{ .terminal_step = Step.build_registry, .cancelled = false },
        .{ .terminal_step = Step.validate_registry, .cancelled = false },
        .{ .terminal_step = Step.validate_allowlist, .cancelled = false },
        .{ .terminal_step = Step.load_provider_config, .cancelled = true },
    }) |scenario| {
        var spy: Spy = .{
            .derived = .required,
            .terminal_step = scenario.terminal_step,
            .cancelled = scenario.cancelled,
        };
        var outcome = run(spy.bindings());
        defer outcome.deinit();

        if (scenario.cancelled) {
            try std.testing.expect(outcome == .cancelled);
        } else {
            try std.testing.expectEqual(
                failureFor(scenario.terminal_step),
                outcome.failed,
            );
        }
        try std.testing.expectEqual(
            scenario.terminal_step,
            spy.calls()[spy.calls().len - 1],
        );
        try std.testing.expect(!spy.services_taken);
    }
}

const Step = enum {
    derive_requirement,
    load_provider_config,
    decode_provider_config,
    build_registry,
    validate_registry,
    validate_allowlist,
};

const Spy = struct {
    derived: @import("../domain/model_provider_requirement.zig").Requirement,
    terminal_step: ?Step = null,
    cancelled: bool = false,
    observed: [6]Step = undefined,
    observed_count: usize = 0,
    services_taken: bool = false,

    fn bindings(self: *Spy) child_bindings.ChildBindings {
        return .{ .context = self, .vtable = &spy_vtable };
    }

    fn invoke(self: *Spy, step: Step) child_bindings.StepOutcome {
        self.observed[self.observed_count] = step;
        self.observed_count += 1;
        if (self.terminal_step != step) return .ok;
        return if (self.cancelled)
            .cancelled
        else
            .{ .failed = failureFor(step) };
    }

    fn calls(self: *const Spy) []const Step {
        return self.observed[0..self.observed_count];
    }
};

fn spyDeriveRequirement(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.derive_requirement);
}

fn spyRequirement(context: *const anyopaque) @import("../domain/model_provider_requirement.zig").Requirement {
    const spy: *const Spy = @ptrCast(@alignCast(context));
    return spy.derived;
}

fn spyLoadProviderConfig(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.load_provider_config);
}

fn spyDecodeProviderConfig(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.decode_provider_config);
}

fn spyBuildRegistry(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.build_registry);
}

fn spyValidateRegistry(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.validate_registry);
}

fn spyValidateAllowlist(context: *anyopaque) child_bindings.StepOutcome {
    const spy: *Spy = @ptrCast(@alignCast(context));
    return spy.invoke(.validate_allowlist);
}

fn spyTakeServices(context: *anyopaque) services.ModelProviderBootstrapServices {
    const spy: *Spy = @ptrCast(@alignCast(context));
    spy.services_taken = true;
    unreachable;
}

const spy_vtable: child_bindings.ChildBindings.VTable = .{
    .derive_requirement = spyDeriveRequirement,
    .requirement = spyRequirement,
    .load_provider_config = spyLoadProviderConfig,
    .decode_provider_config = spyDecodeProviderConfig,
    .build_registry = spyBuildRegistry,
    .validate_registry = spyValidateRegistry,
    .validate_allowlist = spyValidateAllowlist,
    .take_services = spyTakeServices,
};

fn failureFor(step: Step) bootstrap_error.PublicError {
    return switch (step) {
        .derive_requirement, .build_registry, .validate_registry => .LLM_PROVIDER_REGISTRY_INVALID,
        .load_provider_config => .LLM_PROVIDER_CONFIG_READ_ERROR,
        .decode_provider_config => .LLM_PROVIDER_CONFIG_PARSE_ERROR,
        .validate_allowlist => .LLM_PROVIDER_MODEL_BINDING_INVALID,
    };
}
