const std = @import("std");
const config = @import("../domain/config.zig");
const bootstrap_roots = @import("../domain/bootstrap_roots.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const pipeline = @import("../domain/pipeline.zig");
const engine_config_source = @import("../ports/engine_config_source.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");
const validate_path_policy = @import("../actions/bootstrap/validate_engine_path_policy.zig");
const resolve_root = @import("../actions/bootstrap/resolve_configured_base_root.zig");
const validate_root = @import("../actions/bootstrap/validate_configured_base_root.zig");
const build_registry_id = @import("../actions/bootstrap/build_bootstrap_root_registry_id.zig");
const build_registry = @import("../actions/bootstrap/build_bootstrap_root_registry.zig");
const validate_registry = @import("../actions/bootstrap/validate_bootstrap_root_registry.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const sddtoolkit_config_service = @import("sddtoolkit_config_service.zig");
const bootstrap_root_registry_service = @import("bootstrap_root_registry_service.zig");
const bootstrap_services = @import("bootstrap_services.zig");

comptime {
    pipeline.validateLinear(
        &.{.invocation_working_directory},
        &.{
            locate.Action.contract,
            read.Action.contract,
            decode.Action.contract,
            validate_path_policy.Action.contract,
            resolve_root.Action.contract,
            validate_root.Action.contract,
            build_registry_id.Action.contract,
            build_registry.Action.contract,
            validate_registry.Action.contract,
        },
    );
}

pub const Runner = struct {
    allocator: std.mem.Allocator,
    runtime: pipeline.NodeRuntime,
    envelope: pipeline.PipelineEnvelope,
    locate_action: locate.Action,
    read_action: read.Action,
    decode_action: decode.Action,
    validate_path_policy_action: validate_path_policy.Action,
    resolve_root_action: resolve_root.Action,
    validate_root_action: validate_root.Action,
    build_registry_id_action: build_registry_id.Action,
    build_registry_action: build_registry.Action,
    validate_registry_action: validate_registry.Action,
    exact_config_file: ?engine_config_source.ExactEngineConfigFile = null,
    raw_config: ?engine_config_source.RawEngineConfig = null,
    decoded_config: ?config.Owned = null,
    root_scratch: std.heap.ArenaAllocator,
    validated_root_owner: ?*bootstrap_root_registry.Owner = null,
    normalized_paths: [bootstrap_roots.PathKey.count]?bootstrap_roots.NormalizedConfiguredPath =
        [_]?bootstrap_roots.NormalizedConfiguredPath{null} ** bootstrap_roots.PathKey.count,
    root_candidates: [bootstrap_roots.PathKey.count]?bootstrap_roots.ConfiguredRootCandidate =
        [_]?bootstrap_roots.ConfiguredRootCandidate{null} ** bootstrap_roots.PathKey.count,
    root_capabilities: [bootstrap_roots.PathKey.count]?bootstrap_roots.ValidatedConfiguredRoot =
        [_]?bootstrap_roots.ValidatedConfiguredRoot{null} ** bootstrap_roots.PathKey.count,
    registry_id: ?bootstrap_roots.BootstrapRootRegistryId = null,
    registry_candidate: ?bootstrap_roots.BootstrapRootRegistryCandidate = null,

    pub fn init(
        allocator: std.mem.Allocator,
        locate_action: locate.Action,
        read_action: read.Action,
        decode_action: decode.Action,
        validate_path_policy_action: validate_path_policy.Action,
        resolve_root_action: resolve_root.Action,
        validate_root_action: validate_root.Action,
        build_registry_id_action: build_registry_id.Action,
        build_registry_action: build_registry.Action,
        validate_registry_action: validate_registry.Action,
        runtime: pipeline.NodeRuntime,
    ) Runner {
        return .{
            .allocator = allocator,
            .runtime = runtime,
            .envelope = .init(&.{.invocation_working_directory}),
            .locate_action = locate_action,
            .read_action = read_action,
            .decode_action = decode_action,
            .validate_path_policy_action = validate_path_policy_action,
            .resolve_root_action = resolve_root_action,
            .validate_root_action = validate_root_action,
            .build_registry_id_action = build_registry_id_action,
            .build_registry_action = build_registry_action,
            .validate_registry_action = validate_registry_action,
            .root_scratch = .init(allocator),
        };
    }

    pub fn bindings(self: *Runner) child_bindings.ChildBindings {
        return .{
            .context = self,
            .vtable = &bindings_vtable,
        };
    }

    pub fn deinit(self: *Runner) void {
        if (self.decoded_config) |*owned| owned.deinit();
        if (self.validated_root_owner) |owner| bootstrap_root_registry.deinitOwner(owner);
        self.root_scratch.deinit();
        if (self.raw_config) |*raw| raw.deinit(self.allocator);
        if (self.exact_config_file) |*exact_config_file| exact_config_file.deinit(self.allocator);
        self.* = undefined;
    }

    fn invokeLocate(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(locate.Action.contract, .ENGINE_CONFIG_READ_ERROR)) |outcome| {
            return outcome;
        }
        std.debug.assert(self.exact_config_file == null);

        self.exact_config_file = self.locate_action.execute(self.allocator) catch {
            return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
        };
        return self.finishNode(locate.Action.contract, .ENGINE_CONFIG_READ_ERROR);
    }

    fn invokeRead(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(read.Action.contract, .ENGINE_CONFIG_READ_ERROR)) |outcome| {
            return outcome;
        }
        std.debug.assert(self.exact_config_file != null);
        std.debug.assert(self.raw_config == null);

        self.raw_config = self.read_action.execute(
            &self.exact_config_file.?,
            self.allocator,
        ) catch {
            return .{ .failed = .ENGINE_CONFIG_READ_ERROR };
        };
        return self.finishNode(read.Action.contract, .ENGINE_CONFIG_READ_ERROR);
    }

    fn invokeDecode(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(decode.Action.contract, .ENGINE_CONFIG_PARSE_ERROR)) |outcome| {
            return outcome;
        }
        std.debug.assert(self.raw_config != null);
        std.debug.assert(self.decoded_config == null);

        self.decoded_config = self.decode_action.execute(
            self.allocator,
            self.raw_config.?.bytes,
        ) catch {
            return .{ .failed = .ENGINE_CONFIG_PARSE_ERROR };
        };
        return self.finishNode(decode.Action.contract, .ENGINE_CONFIG_PARSE_ERROR);
    }

    fn invokeValidateRootPaths(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            validate_path_policy.Action.contract,
            .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        )) |outcome| return outcome;
        std.debug.assert(self.decoded_config != null);
        const paths = self.decoded_config.?.value().paths;
        const allocator = self.root_scratch.allocator();

        for (0..bootstrap_roots.PathKey.count) |index| {
            std.debug.assert(self.normalized_paths[index] == null);
            const key: bootstrap_roots.PathKey = @enumFromInt(index);
            self.normalized_paths[index] = self.validate_path_policy_action.execute(
                allocator,
                key,
                configuredPath(paths, key),
            ) catch return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
        }
        return self.finishNode(
            validate_path_policy.Action.contract,
            .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        );
    }

    fn invokeResolveRoots(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            resolve_root.Action.contract,
            .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        )) |outcome| return outcome;
        std.debug.assert(self.exact_config_file != null);
        const allocator = self.root_scratch.allocator();

        for (0..bootstrap_roots.PathKey.count) |index| {
            std.debug.assert(self.normalized_paths[index] != null);
            std.debug.assert(self.root_candidates[index] == null);
            self.root_candidates[index] = self.resolve_root_action.execute(
                allocator,
                self.exact_config_file.?.canonical_project_root,
                self.normalized_paths[index].?,
            ) catch return .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR };
        }
        return self.finishNode(
            resolve_root.Action.contract,
            .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        );
    }

    fn invokeValidateRoots(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            validate_root.Action.contract,
            .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        )) |outcome| return outcome;
        for (0..bootstrap_roots.PathKey.count) |index| {
            std.debug.assert(self.root_candidates[index] != null);
            std.debug.assert(self.root_capabilities[index] == null);
            self.root_capabilities[index] = self.validate_root_action.execute(
                self.root_candidates[index].?,
            ) catch |validation_error| return switch (validation_error) {
                error.Cancelled => .cancelled,
                error.BootstrapRootResolutionError => .{ .failed = .BOOTSTRAP_ROOT_RESOLUTION_ERROR },
            };
        }
        return self.finishNode(
            validate_root.Action.contract,
            .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        );
    }

    fn invokeBuildRegistryId(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            build_registry_id.Action.contract,
            .BOOTSTRAP_ROOT_REGISTRY_INVALID,
        )) |outcome| return outcome;
        std.debug.assert(self.exact_config_file != null);
        std.debug.assert(self.registry_id == null);
        self.registry_id = self.build_registry_id_action.execute(
            self.root_scratch.allocator(),
            self.exact_config_file.?.canonical_project_root,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_REGISTRY_INVALID };
        return self.finishNode(
            build_registry_id.Action.contract,
            .BOOTSTRAP_ROOT_REGISTRY_INVALID,
        );
    }

    fn invokeBuildRegistry(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            build_registry.Action.contract,
            .BOOTSTRAP_ROOT_REGISTRY_INVALID,
        )) |outcome| return outcome;
        std.debug.assert(self.registry_id != null);
        std.debug.assert(self.registry_candidate == null);
        std.debug.assert(self.exact_config_file != null);

        var capabilities: [bootstrap_roots.PathKey.count]bootstrap_roots.ValidatedConfiguredRoot = undefined;
        for (&capabilities, 0..) |*capability, index| {
            std.debug.assert(self.root_capabilities[index] != null);
            capability.* = self.root_capabilities[index].?;
        }
        self.registry_candidate = self.build_registry_action.execute(
            self.root_scratch.allocator(),
            self.registry_id.?,
            self.exact_config_file.?.canonical_config_path,
            self.exact_config_file.?.no_follow_file_identity,
            capabilities,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_REGISTRY_INVALID };
        return self.finishNode(
            build_registry.Action.contract,
            .BOOTSTRAP_ROOT_REGISTRY_INVALID,
        );
    }

    fn invokeValidateRegistry(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            validate_registry.Action.contract,
            .BOOTSTRAP_ROOT_REGISTRY_INVALID,
        )) |outcome| return outcome;
        std.debug.assert(self.registry_candidate != null);
        std.debug.assert(self.validated_root_owner == null);
        self.validated_root_owner = self.validate_registry_action.execute(
            self.allocator,
            self.registry_candidate.?,
        ) catch return .{ .failed = .BOOTSTRAP_ROOT_REGISTRY_INVALID };
        return self.finishNode(
            validate_registry.Action.contract,
            .BOOTSTRAP_ROOT_REGISTRY_INVALID,
        );
    }

    fn takeServices(context: *anyopaque) bootstrap_services.BootstrapServices {
        const self: *Runner = @ptrCast(@alignCast(context));
        std.debug.assert(self.envelope.contains(.bootstrap_root_registry_evidence));
        const owned_config = self.decoded_config.?;
        self.decoded_config = null;
        const owned_roots = self.validated_root_owner.?;
        self.validated_root_owner = null;
        return .{
            .config = sddtoolkit_config_service.SDDToolKitConfigService.init(owned_config),
            .roots = bootstrap_root_registry_service.BootstrapRootRegistryService.init(owned_roots),
        };
    }

    fn beginNode(
        self: *Runner,
        contract: pipeline.NodeContract,
        failure: bootstrap_error.PublicError,
    ) ?child_bindings.StepOutcome {
        if (self.runtimeOutcome(failure)) |outcome| return outcome;
        self.envelope.validateInvocation(contract) catch {
            return .{ .failed = failure };
        };
        return null;
    }

    fn finishNode(
        self: *Runner,
        contract: pipeline.NodeContract,
        failure: bootstrap_error.PublicError,
    ) child_bindings.StepOutcome {
        if (self.runtimeOutcome(failure)) |outcome| return outcome;
        self.envelope = self.envelope.apply(
            contract,
            pipeline.NodeDelta.successful(contract),
        ) catch return .{ .failed = failure };
        return .ok;
    }

    fn runtimeOutcome(
        self: *const Runner,
        failure: bootstrap_error.PublicError,
    ) ?child_bindings.StepOutcome {
        return switch (self.runtime.status()) {
            .active => null,
            .cancelled => .cancelled,
            .deadline_exhausted => .{ .failed = failure },
        };
    }
};

fn configuredPath(paths: config.PathsConfig, key: bootstrap_roots.PathKey) []const u8 {
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

const bindings_vtable: child_bindings.ChildBindings.VTable = .{
    .locate = Runner.invokeLocate,
    .read = Runner.invokeRead,
    .decode = Runner.invokeDecode,
    .validate_root_paths = Runner.invokeValidateRootPaths,
    .resolve_roots = Runner.invokeResolveRoots,
    .validate_roots = Runner.invokeValidateRoots,
    .build_registry_id = Runner.invokeBuildRegistryId,
    .build_registry = Runner.invokeBuildRegistry,
    .validate_registry = Runner.invokeValidateRegistry,
    .take_services = Runner.takeServices,
};
