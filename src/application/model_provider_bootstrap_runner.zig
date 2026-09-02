const std = @import("std");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const config = @import("../domain/config.zig");
const document = @import("../domain/llm_provider_document.zig");
const contracts = @import("../domain/llm_provider_contracts.zig");
const provider_registry = @import("../domain/llm_provider_registry.zig");
const repository_allowlist = @import("../domain/repository_model_allowlist.zig");
const requirement = @import("../domain/model_provider_requirement.zig");
const execution = @import("../domain/workflow_execution.zig");
const pipeline = @import("../domain/pipeline.zig");
const derive_requirement = @import("../actions/provider/derive_provider_requirement.zig");
const decode_provider_config = @import("../actions/provider/decode_llm_provider_config.zig");
const build_registry = @import("../actions/provider/build_llm_provider_registry.zig");
const validate_registry = @import("../actions/provider/validate_llm_provider_registry.zig");
const validate_allowlist = @import("../actions/provider/validate_repository_model_allowlist.zig");
const config_orchestrator = @import("llm_provider_config_orchestrator.zig");
const config_runner = @import("llm_provider_config_runner.zig");
const config_service = @import("llm_provider_config_service.zig");
const registry_service = @import("llm_provider_registry_service.zig");
const bindings = @import("model_provider_bootstrap_child_bindings.zig");
const services = @import("model_provider_bootstrap_services.zig");

comptime {
    pipeline.validateLinear(
        &.{.selected_compiled_workflow},
        &.{derive_requirement.Action.contract},
    );
    pipeline.validateLinear(
        &.{ .raw_llm_provider_config, .engine_config },
        &.{
            decode_provider_config.Action.contract,
            build_registry.Action.contract,
            validate_registry.Action.contract,
            validate_allowlist.Action.contract,
        },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    runtime: pipeline.NodeRuntime,
    selected: *const execution.SelectedWorkflow,
    models: *const config.ModelsConfig,
    config_runner: *config_runner.Runner,
    derive_requirement_action: derive_requirement.Action,
    decode_provider_config_action: decode_provider_config.Action,
    build_registry_action: build_registry.Action,
    validate_registry_action: validate_registry.Action,
    validate_allowlist_action: validate_allowlist.Action,
    requirement_envelope: pipeline.PipelineEnvelope = .init(&.{.selected_compiled_workflow}),
    provider_envelope: ?pipeline.PipelineEnvelope = null,
    derived_requirement: ?requirement.Requirement = null,
    provider_config_service: ?config_service.LLMProviderConfigService = null,
    decoded: ?document.Owned = null,
    registry_candidate: ?provider_registry.Candidate = null,
    registry_owner: ?*provider_registry.Owner = null,
    allowlist_owner: ?*repository_allowlist.Owner = null,

    pub fn init(
        allocator: std.mem.Allocator,
        runtime: pipeline.NodeRuntime,
        selected: *const execution.SelectedWorkflow,
        models: *const config.ModelsConfig,
        provider_config_runner: *config_runner.Runner,
        registered_contracts: *const contracts.Registry,
    ) Runner {
        return .{
            .allocator = allocator,
            .runtime = runtime,
            .selected = selected,
            .models = models,
            .config_runner = provider_config_runner,
            .derive_requirement_action = .{},
            .decode_provider_config_action = .{},
            .build_registry_action = .{ .contracts = registered_contracts },
            .validate_registry_action = .{ .contracts = registered_contracts },
            .validate_allowlist_action = .{},
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.allowlist_owner) |owner| repository_allowlist.deinitOwner(owner);
        if (self.registry_owner) |owner| provider_registry.deinitOwner(owner);
        if (self.registry_candidate) |*candidate| candidate.deinit();
        if (self.decoded) |*decoded| decoded.deinit();
        if (self.provider_config_service) |*provider_config| provider_config.deinit();
        self.* = undefined;
    }

    pub fn childBindings(self: *Runner) bindings.ChildBindings {
        return .{ .context = self, .vtable = &bindings_vtable };
    }

    fn invokeDeriveRequirement(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome(.LLM_PROVIDER_REGISTRY_INVALID)) |outcome| return outcome;
        self.requirement_envelope.validateInvocation(derive_requirement.Action.contract) catch {
            return .{ .failed = .LLM_PROVIDER_REGISTRY_INVALID };
        };
        std.debug.assert(self.derived_requirement == null);

        self.derived_requirement = self.derive_requirement_action.execute(self.selected);
        return self.finishRequirementNode();
    }

    fn getRequirement(context: *const anyopaque) requirement.Requirement {
        const self: *const Runner = @ptrCast(@alignCast(context));
        return self.derived_requirement.?;
    }

    fn invokeLoadProviderConfig(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome(.LLM_PROVIDER_CONFIG_READ_ERROR)) |outcome| return outcome;
        std.debug.assert(self.provider_config_service == null);

        const outcome = config_orchestrator.run(self.config_runner.childBindings());
        return switch (outcome) {
            .ready => |provider_config| ready: {
                self.provider_config_service = provider_config;
                self.provider_envelope = .init(&.{ .raw_llm_provider_config, .engine_config });
                break :ready .ok;
            },
            .failed => .{ .failed = .LLM_PROVIDER_CONFIG_READ_ERROR },
            .cancelled => .cancelled,
        };
    }

    fn invokeDecodeProviderConfig(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome(.LLM_PROVIDER_CONFIG_PARSE_ERROR)) |outcome| return outcome;
        self.provider_envelope.?.validateInvocation(decode_provider_config.Action.contract) catch {
            return .{ .failed = .LLM_PROVIDER_CONFIG_PARSE_ERROR };
        };
        std.debug.assert(self.provider_config_service != null);
        std.debug.assert(self.decoded == null);

        self.decoded = self.decode_provider_config_action.execute(
            self.allocator,
            self.provider_config_service.?.bytes(),
        ) catch return .{ .failed = .LLM_PROVIDER_CONFIG_PARSE_ERROR };
        return self.finishProviderNode(
            decode_provider_config.Action.contract,
            .LLM_PROVIDER_CONFIG_PARSE_ERROR,
        );
    }

    fn invokeBuildRegistry(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome(.LLM_PROVIDER_REGISTRY_INVALID)) |outcome| return outcome;
        self.provider_envelope.?.validateInvocation(build_registry.Action.contract) catch {
            return .{ .failed = .LLM_PROVIDER_REGISTRY_INVALID };
        };
        std.debug.assert(self.decoded != null);
        std.debug.assert(self.registry_candidate == null);

        self.registry_candidate = self.build_registry_action.execute(
            self.allocator,
            self.decoded.?.value(),
        ) catch return .{ .failed = .LLM_PROVIDER_REGISTRY_INVALID };
        return self.finishProviderNode(
            build_registry.Action.contract,
            .LLM_PROVIDER_REGISTRY_INVALID,
        );
    }

    fn invokeValidateRegistry(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome(.LLM_PROVIDER_REGISTRY_INVALID)) |outcome| return outcome;
        self.provider_envelope.?.validateInvocation(validate_registry.Action.contract) catch {
            return .{ .failed = .LLM_PROVIDER_REGISTRY_INVALID };
        };
        std.debug.assert(self.registry_candidate != null);
        std.debug.assert(self.registry_owner == null);

        self.registry_owner = self.validate_registry_action.execute(
            self.allocator,
            self.registry_candidate.?,
        ) catch return .{ .failed = .LLM_PROVIDER_REGISTRY_INVALID };
        return self.finishProviderNode(
            validate_registry.Action.contract,
            .LLM_PROVIDER_REGISTRY_INVALID,
        );
    }

    fn invokeValidateAllowlist(context: *anyopaque) bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.runtimeOutcome(.LLM_PROVIDER_MODEL_BINDING_INVALID)) |outcome| return outcome;
        self.provider_envelope.?.validateInvocation(validate_allowlist.Action.contract) catch {
            return .{ .failed = .LLM_PROVIDER_MODEL_BINDING_INVALID };
        };
        std.debug.assert(self.registry_owner != null);
        std.debug.assert(self.allowlist_owner == null);

        self.allowlist_owner = self.validate_allowlist_action.execute(
            self.allocator,
            self.models,
            provider_registry.registry(self.registry_owner.?),
        ) catch return .{ .failed = .LLM_PROVIDER_MODEL_BINDING_INVALID };
        return self.finishProviderNode(
            validate_allowlist.Action.contract,
            .LLM_PROVIDER_MODEL_BINDING_INVALID,
        );
    }

    fn takeServices(context: *anyopaque) services.ModelProviderBootstrapServices {
        const self: *Runner = @ptrCast(@alignCast(context));
        std.debug.assert(self.registry_owner != null);
        std.debug.assert(self.allowlist_owner != null);
        std.debug.assert(self.provider_envelope.?.contains(.repository_model_allowlist));

        const result = services.ModelProviderBootstrapServices.init(
            registry_service.LLMProviderRegistryService.init(self.registry_owner.?),
            self.allowlist_owner.?,
        );
        self.registry_owner = null;
        self.allowlist_owner = null;
        return result;
    }

    fn finishRequirementNode(self: *Runner) bindings.StepOutcome {
        if (self.runtimeOutcome(.LLM_PROVIDER_REGISTRY_INVALID)) |outcome| return outcome;
        self.requirement_envelope = self.requirement_envelope.apply(
            derive_requirement.Action.contract,
            pipeline.NodeDelta.successful(derive_requirement.Action.contract),
        ) catch return .{ .failed = .LLM_PROVIDER_REGISTRY_INVALID };
        return .ok;
    }

    fn finishProviderNode(
        self: *Runner,
        contract: pipeline.NodeContract,
        failure: bootstrap_error.PublicError,
    ) bindings.StepOutcome {
        if (self.runtimeOutcome(failure)) |outcome| return outcome;
        self.provider_envelope = self.provider_envelope.?.apply(
            contract,
            pipeline.NodeDelta.successful(contract),
        ) catch return .{ .failed = failure };
        return .ok;
    }

    fn runtimeOutcome(
        self: *const Runner,
        failure: bootstrap_error.PublicError,
    ) ?bindings.StepOutcome {
        return switch (self.runtime.status()) {
            .active => null,
            .cancelled => .cancelled,
            .deadline_exhausted => .{ .failed = failure },
        };
    }
};

const bindings_vtable: bindings.ChildBindings.VTable = .{
    .derive_requirement = Runner.invokeDeriveRequirement,
    .requirement = Runner.getRequirement,
    .load_provider_config = Runner.invokeLoadProviderConfig,
    .decode_provider_config = Runner.invokeDecodeProviderConfig,
    .build_registry = Runner.invokeBuildRegistry,
    .validate_registry = Runner.invokeValidateRegistry,
    .validate_allowlist = Runner.invokeValidateAllowlist,
    .take_services = Runner.takeServices,
};
