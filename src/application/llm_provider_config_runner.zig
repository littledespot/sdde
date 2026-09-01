const std = @import("std");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const llm_provider_config = @import("../domain/llm_provider_config.zig");
const pipeline = @import("../domain/pipeline.zig");
const source = @import("../ports/llm_provider_config_source.zig");
const locate = @import("../actions/provider/locate_llm_provider_config.zig");
const read = @import("../actions/provider/read_llm_provider_config.zig");
const bindings = @import("llm_provider_config_child_bindings.zig");
const service = @import("llm_provider_config_service.zig");

comptime {
    pipeline.validateLinear(
        &.{.bootstrap_root_registry_evidence},
        &.{ locate.Action.contract, read.Action.contract },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    runtime: pipeline.NodeRuntime,
    capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
    locate_action: locate.Action,
    read_action: read.Action,
    envelope: pipeline.PipelineEnvelope = .init(&.{.bootstrap_root_registry_evidence}),
    exact_file: ?source.ExactFile = null,
    raw: ?llm_provider_config.Raw = null,

    pub fn init(
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
        capability: *const bootstrap_root_registry.LLMProviderConfigCapability,
        locate_action: locate.Action,
        read_action: read.Action,
    ) Runner {
        return .{
            .allocator = allocator,
            .runtime = runtime,
            .capability = capability,
            .locate_action = locate_action,
            .read_action = read_action,
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.raw) |*raw| raw.deinit(self.allocator);
        if (self.exact_file) |*exact_file| exact_file.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn childBindings(self: *Runner) bindings.ChildBindings {
        return .{ .context = self, .vtable = &bindings_vtable };
    }

    fn invokeLocate(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome()) |outcome| return outcome;
        self.envelope.validateInvocation(locate.Action.contract) catch return .failed;
        std.debug.assert(self.exact_file == null);

        self.exact_file = self.locate_action.execute(
            self.capability,
            self.allocator,
            self.runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.DeadlineExhausted, error.LLMProviderConfigReadError => .failed,
        };
        return self.finishNode(locate.Action.contract);
    }

    fn invokeRead(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome()) |outcome| return outcome;
        self.envelope.validateInvocation(read.Action.contract) catch return .failed;
        std.debug.assert(self.exact_file != null);
        std.debug.assert(self.raw == null);

        self.raw = self.read_action.execute(
            &self.exact_file.?,
            self.allocator,
            self.runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.DeadlineExhausted, error.LLMProviderConfigReadError => .failed,
        };
        return self.finishNode(read.Action.contract);
    }

    fn takeService(context: *anyopaque) service.LLMProviderConfigService {
        const self: *Runner = @ptrCast(@alignCast(context));
        std.debug.assert(self.envelope.contains(.raw_llm_provider_config));
        const raw = self.raw.?;
        self.raw = null;
        return service.LLMProviderConfigService.init(self.allocator, raw);
    }

    fn finishNode(self: *Runner, contract: pipeline.NodeContract) bindings.StepOutcome {
        if (self.runtimeOutcome()) |outcome| return outcome;
        self.envelope = self.envelope.apply(
            contract,
            pipeline.NodeDelta.successful(contract),
        ) catch return .failed;
        return .ok;
    }

    fn runtimeOutcome(self: *const Runner) ?bindings.StepOutcome {
        return switch (self.runtime.status()) {
            .active => null,
            .cancelled => .cancelled,
            .deadline_exhausted => .failed,
        };
    }
};

const bindings_vtable: bindings.ChildBindings.VTable = .{
    .locate = Runner.invokeLocate,
    .read = Runner.invokeRead,
    .take_service = Runner.takeService,
};
