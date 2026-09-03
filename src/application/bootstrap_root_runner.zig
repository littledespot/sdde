const std = @import("std");
const bootstrap_roots = @import("../domain/bootstrap_roots.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const pipeline = @import("../domain/pipeline.zig");
const validate_path_policy = @import("../actions/bootstrap/validate_configured_root_path_policy.zig");
const validate_provider_path_policy = @import("../actions/bootstrap/validate_llm_provider_config_path_policy.zig");
const resolve_root = @import("../actions/bootstrap/resolve_configured_base_root.zig");
const resolve_provider_path = @import("../actions/bootstrap/resolve_llm_provider_config_path.zig");
const validate_root = @import("../actions/bootstrap/validate_configured_base_root.zig");
const build_registry_id = @import("../actions/bootstrap/build_bootstrap_root_registry_id.zig");
const build_registry = @import("../actions/bootstrap/build_bootstrap_root_registry.zig");
const validate_registry = @import("../actions/bootstrap/validate_bootstrap_root_registry.zig");
const config_runner = @import("bootstrap_config_runner.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const execution = @import("bootstrap_execution.zig");

comptime {
    pipeline.validateLinear(
        &.{
            .invocation_working_directory,
            .exact_engine_config_file,
            .raw_engine_config,
            .engine_config,
            .canonical_log_level,
            .logging_policy,
        },
        &.{
            validate_path_policy.Action.contract,
            validate_provider_path_policy.Action.contract,
            resolve_root.Action.contract,
            resolve_provider_path.Action.contract,
            validate_root.Action.contract,
            build_registry_id.Action.contract,
            build_registry.Action.contract,
            validate_registry.Action.contract,
        },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    execution: *execution.State,
    config_source: *config_runner.Runner,
    validate_path_policy_action: validate_path_policy.Action,
    validate_provider_path_policy_action: validate_provider_path_policy.Action,
    resolve_root_action: resolve_root.Action,
    resolve_provider_path_action: resolve_provider_path.Action,
    validate_root_action: validate_root.Action,
    build_registry_id_action: build_registry_id.Action,
    build_registry_action: build_registry.Action,
    validate_registry_action: validate_registry.Action,
    scratch: std.heap.ArenaAllocator,
    normalized_paths: [bootstrap_roots.PathKey.count]?bootstrap_roots.NormalizedConfiguredPath =
        [_]?bootstrap_roots.NormalizedConfiguredPath{null} ** bootstrap_roots.PathKey.count,
    normalized_provider_path: ?bootstrap_roots.NormalizedLLMProviderConfigPath = null,
    root_candidates: [bootstrap_roots.PathKey.count]?bootstrap_roots.ConfiguredRootCandidate =
        [_]?bootstrap_roots.ConfiguredRootCandidate{null} ** bootstrap_roots.PathKey.count,
    provider_path_candidate: ?bootstrap_roots.LLMProviderConfigPathCandidate = null,
    root_capabilities: [bootstrap_roots.PathKey.count]?bootstrap_roots.ValidatedConfiguredRoot =
        [_]?bootstrap_roots.ValidatedConfiguredRoot{null} ** bootstrap_roots.PathKey.count,
    registry_id: ?bootstrap_roots.BootstrapRootRegistryId = null,
    registry_candidate: ?bootstrap_roots.BootstrapRootRegistryCandidate = null,
    validated_owner: ?*bootstrap_root_registry.Owner = null,

    pub fn init(
        allocator: std.mem.Allocator,
        execution_state: *execution.State,
        config_source: *config_runner.Runner,
        validate_path_policy_action: validate_path_policy.Action,
        validate_provider_path_policy_action: validate_provider_path_policy.Action,
        resolve_root_action: resolve_root.Action,
        resolve_provider_path_action: resolve_provider_path.Action,
        validate_root_action: validate_root.Action,
        build_registry_id_action: build_registry_id.Action,
        build_registry_action: build_registry.Action,
        validate_registry_action: validate_registry.Action,
    ) Runner {
        return .{
            .allocator = allocator,
            .execution = execution_state,
            .config_source = config_source,
            .validate_path_policy_action = validate_path_policy_action,
            .validate_provider_path_policy_action = validate_provider_path_policy_action,
            .resolve_root_action = resolve_root_action,
            .resolve_provider_path_action = resolve_provider_path_action,
            .validate_root_action = validate_root_action,
            .build_registry_id_action = build_registry_id_action,
            .build_registry_action = build_registry_action,
            .validate_registry_action = validate_registry_action,
            .scratch = .init(allocator),
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.validated_owner) |owner| bootstrap_root_registry.deinitOwner(owner);
        self.scratch.deinit();
        self.* = undefined;
    }

    pub fn invokeValidateRootPaths(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_path_policy.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR)) |outcome| return outcome;
        const paths = self.config_source.configValue().paths;
        for (0..bootstrap_roots.PathKey.count) |index| {
            std.debug.assert(self.normalized_paths[index] == null);
            const key: bootstrap_roots.PathKey = @enumFromInt(index);
            self.normalized_paths[index] = self.validate_path_policy_action.execute(
                self.scratch.allocator(),
                key,
                configuredPath(paths, key),
            ) catch return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
        }
        return self.execution.finish(validate_path_policy.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
    }

    pub fn invokeValidateProviderPath(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_provider_path_policy.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR)) |outcome| return outcome;
        std.debug.assert(self.normalized_provider_path == null);
        self.normalized_provider_path = self.validate_provider_path_policy_action.execute(
            self.scratch.allocator(),
            self.config_source.configValue().paths.providers,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
        return self.execution.finish(validate_provider_path_policy.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
    }

    pub fn invokeResolveRoots(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(resolve_root.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR)) |outcome| return outcome;
        const exact = self.config_source.exactConfigFile();
        for (0..bootstrap_roots.PathKey.count) |index| {
            std.debug.assert(self.normalized_paths[index] != null);
            std.debug.assert(self.root_candidates[index] == null);
            self.root_candidates[index] = self.resolve_root_action.execute(
                self.scratch.allocator(),
                exact.canonical_project_root,
                self.normalized_paths[index].?,
            ) catch return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
        }
        return self.execution.finish(resolve_root.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
    }

    pub fn invokeResolveProviderPath(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(resolve_provider_path.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR)) |outcome| return outcome;
        std.debug.assert(self.normalized_provider_path != null);
        std.debug.assert(self.provider_path_candidate == null);
        self.provider_path_candidate = self.resolve_provider_path_action.execute(
            self.scratch.allocator(),
            self.config_source.exactConfigFile().canonical_project_root,
            self.normalized_provider_path.?,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
        return self.execution.finish(resolve_provider_path.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
    }

    pub fn invokeValidateRoots(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_root.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR)) |outcome| return outcome;
        for (0..bootstrap_roots.PathKey.count) |index| {
            std.debug.assert(self.root_candidates[index] != null);
            std.debug.assert(self.root_capabilities[index] == null);
            self.root_capabilities[index] = self.validate_root_action.execute(self.root_candidates[index].?) catch |validation_error| return switch (validation_error) {
                error.Cancelled => .cancelled,
                error.BootstrapRootResolutionError => .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR },
            };
        }
        return self.execution.finish(validate_root.Action.contract, .BOOTSTRAP_ROOT_RESOLUTION_ERROR);
    }

    pub fn invokeBuildRegistryId(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(build_registry_id.Action.contract, .BOOTSTRAP_ROOT_REGISTRY_INVALID)) |outcome| return outcome;
        std.debug.assert(self.registry_id == null);
        self.registry_id = self.build_registry_id_action.execute(
            self.scratch.allocator(),
            self.config_source.exactConfigFile().canonical_project_root,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_REGISTRY_INVALID };
        return self.execution.finish(build_registry_id.Action.contract, .BOOTSTRAP_ROOT_REGISTRY_INVALID);
    }

    pub fn invokeBuildRegistry(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(build_registry.Action.contract, .BOOTSTRAP_ROOT_REGISTRY_INVALID)) |outcome| return outcome;
        std.debug.assert(self.registry_id != null);
        std.debug.assert(self.registry_candidate == null);
        std.debug.assert(self.provider_path_candidate != null);
        var capabilities: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot = undefined;
        for (&capabilities, 0..) |*capability, index| {
            std.debug.assert(self.root_capabilities[index] != null);
            capability.* = self.root_capabilities[index].?;
        }
        const exact = self.config_source.exactConfigFile();
        self.registry_candidate = self.build_registry_action.execute(
            self.scratch.allocator(),
            self.registry_id.?,
            exact.canonical_config_path,
            exact.no_follow_file_identity,
            capabilities,
            self.provider_path_candidate.?,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_REGISTRY_INVALID };
        return self.execution.finish(build_registry.Action.contract, .BOOTSTRAP_ROOT_REGISTRY_INVALID);
    }

    pub fn invokeValidateRegistry(self: *Runner) child_bindings.StepOutcome {
        if (self.execution.begin(validate_registry.Action.contract, .BOOTSTRAP_ROOT_REGISTRY_INVALID)) |outcome| return outcome;
        std.debug.assert(self.registry_candidate != null);
        std.debug.assert(self.validated_owner == null);
        self.validated_owner = self.validate_registry_action.execute(
            self.allocator,
            self.registry_candidate.?,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_REGISTRY_INVALID };
        return self.execution.finish(validate_registry.Action.contract, .BOOTSTRAP_ROOT_REGISTRY_INVALID);
    }

    pub fn registry(self: *const Runner) *const bootstrap_root_registry.BootstrapRootRegistry {
        return bootstrap_root_registry.registry(self.validated_owner.?);
    }

    pub fn takeRegistry(self: *Runner) *bootstrap_root_registry.Owner {
        const owner = self.validated_owner.?;
        self.validated_owner = null;
        return owner;
    }
};

fn configuredPath(paths: @import("../domain/config.zig").PathsConfig, key: bootstrap_roots.PathKey) []const u8 {
    return switch (key) {
        .specs => paths.specs,
        .references => paths.references,
        .specs_archive => paths.specsArchive,
        .workflows => paths.workflows,
        .toolchain_preset => paths.toolchainPreset,
        .principles => paths.principles,
        .templates => paths.templates,
    };
}
