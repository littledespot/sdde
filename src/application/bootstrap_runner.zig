const std = @import("std");
const config = @import("../domain/config.zig");
const bootstrap_roots = @import("../domain/bootstrap_roots.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const logging = @import("../domain/logging.zig");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const pipeline = @import("../domain/pipeline.zig");
const engine_config_source = @import("../ports/engine_config_source.zig");
const locate = @import("../actions/config/locate_exact_engine_config.zig");
const read = @import("../actions/config/read_engine_config.zig");
const decode = @import("../actions/config/decode_sddtoolkit_config.zig");
const canonicalize_log_level = @import("../actions/log/canonicalize_log_level.zig");
const validate_logging_policy = @import("../actions/log/validate_logging_policy.zig");
const validate_path_policy = @import("../actions/bootstrap/validate_engine_path_policy.zig");
const resolve_root = @import("../actions/bootstrap/resolve_configured_base_root.zig");
const validate_root = @import("../actions/bootstrap/validate_configured_base_root.zig");
const build_registry_id = @import("../actions/bootstrap/build_bootstrap_root_registry_id.zig");
const build_registry = @import("../actions/bootstrap/build_bootstrap_root_registry.zig");
const validate_registry = @import("../actions/bootstrap/validate_bootstrap_root_registry.zig");
const child_bindings = @import("bootstrap_child_bindings.zig");
const sddtoolkit_config_service = @import("sddtoolkit_config_service.zig");
const bootstrap_root_registry_service = @import("bootstrap_root_registry_service.zig");
const log_service = @import("log_service.zig");
const workflow = @import("../domain/workflow.zig");
const workflow_definition = @import("../domain/workflow_definition.zig");
const workflow_compilation = @import("../domain/workflow_compilation.zig");
const workflow_inventory = @import("../domain/workflow_inventory.zig");
const workflow_registry = @import("../domain/workflow_registry.zig");
const build_workflow_layout = @import("../actions/workflow/build_workflow_authority_layout.zig");
const inventory_workflows = @import("../actions/workflow/inventory_workflow_authority.zig");
const capture_workflows = @import("../actions/workflow/capture_workflow_definitions.zig");
const parse_workflows = @import("../actions/workflow/parse_workflow_definitions.zig");
const validate_workflow_schema = @import("../actions/workflow/validate_workflow_definition_schema.zig");
const compile_workflows = @import("../actions/workflow/compile_workflow_graphs.zig");
const validate_workflow_graphs = @import("../actions/workflow/validate_compiled_workflow_graphs.zig");
const build_workflow_registry = @import("../actions/workflow/build_workflow_definition_registry.zig");
const validate_workflow_registry = @import("../actions/workflow/validate_workflow_definition_registry.zig");
const workflow_definition_registry_service = @import("workflow_definition_registry_service.zig");
const bootstrap_services = @import("bootstrap_services.zig");
const toolchain = @import("../domain/toolchain.zig");
const toolchain_safety = @import("../domain/toolchain_safety.zig");
const capture_project_toolchain = @import("../actions/toolchain/capture_project_toolchain.zig");
const inventory_toolchain_presets = @import("../actions/toolchain/inventory_toolchain_presets.zig");
const capture_toolchain_presets = @import("../actions/toolchain/capture_toolchain_presets.zig");
const parse_toolchain_documents = @import("../actions/toolchain/parse_toolchain_documents.zig");
const validate_project_toolchain_schema = @import("../actions/toolchain/validate_project_toolchain_schema.zig");
const validate_toolchain_preset_registry = @import("../actions/toolchain/validate_toolchain_preset_registry.zig");
const resolve_toolchain_inheritance = @import("../actions/toolchain/resolve_toolchain_inheritance.zig");
const compose_toolchain = @import("../actions/toolchain/compose_toolchain.zig");
const validate_toolchain_safety = @import("../actions/toolchain/validate_toolchain_safety.zig");
const toolchain_service = @import("toolchain_service.zig");

comptime {
    pipeline.validateLinear(
        &.{.invocation_working_directory},
        &.{
            locate.Action.contract,
            read.Action.contract,
            decode.Action.contract,
            canonicalize_log_level.Action.contract,
            validate_logging_policy.Action.contract,
            validate_path_policy.Action.contract,
            resolve_root.Action.contract,
            validate_root.Action.contract,
            build_registry_id.Action.contract,
            build_registry.Action.contract,
            validate_registry.Action.contract,
            build_workflow_layout.Action.contract,
            inventory_workflows.Action.contract,
            capture_workflows.Action.contract,
            parse_workflows.Action.contract,
            validate_workflow_schema.Action.contract,
            compile_workflows.Action.contract,
            validate_workflow_graphs.Action.contract,
            build_workflow_registry.Action.contract,
            validate_workflow_registry.Action.contract,
            capture_project_toolchain.Action.contract,
            inventory_toolchain_presets.Action.contract,
            capture_toolchain_presets.Action.contract,
            parse_toolchain_documents.Action.contract,
            validate_project_toolchain_schema.Action.contract,
            validate_toolchain_preset_registry.Action.contract,
            resolve_toolchain_inheritance.Action.contract,
            compose_toolchain.Action.contract,
            validate_toolchain_safety.Action.contract,
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
    canonicalize_log_level_action: canonicalize_log_level.Action,
    validate_logging_policy_action: validate_logging_policy.Action,
    validate_path_policy_action: validate_path_policy.Action,
    resolve_root_action: resolve_root.Action,
    validate_root_action: validate_root.Action,
    build_registry_id_action: build_registry_id.Action,
    build_registry_action: build_registry.Action,
    validate_registry_action: validate_registry.Action,
    build_workflow_layout_action: build_workflow_layout.Action,
    inventory_workflows_action: inventory_workflows.Action,
    capture_workflows_action: capture_workflows.Action,
    parse_workflows_action: parse_workflows.Action,
    validate_workflow_schema_action: validate_workflow_schema.Action,
    compile_workflows_action: compile_workflows.Action,
    validate_workflow_graphs_action: validate_workflow_graphs.Action,
    build_workflow_registry_action: build_workflow_registry.Action,
    validate_workflow_registry_action: validate_workflow_registry.Action,
    capture_project_toolchain_action: capture_project_toolchain.Action,
    inventory_toolchain_presets_action: inventory_toolchain_presets.Action,
    capture_toolchain_presets_action: capture_toolchain_presets.Action,
    parse_toolchain_documents_action: parse_toolchain_documents.Action,
    validate_project_toolchain_schema_action: validate_project_toolchain_schema.Action,
    validate_toolchain_preset_registry_action: validate_toolchain_preset_registry.Action,
    resolve_toolchain_inheritance_action: resolve_toolchain_inheritance.Action,
    compose_toolchain_action: compose_toolchain.Action,
    validate_toolchain_safety_action: validate_toolchain_safety.Action,
    exact_config_file: ?engine_config_source.ExactEngineConfigFile = null,
    raw_config: ?engine_config_source.RawEngineConfig = null,
    decoded_config: ?config.Owned = null,
    canonicalized_log_level: ?logging.CanonicalizedLevel = null,
    validated_log_owner: ?*logging.Owner = null,
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
    workflow_scratch: std.heap.ArenaAllocator,
    workflow_layout: ?workflow_inventory.Layout = null,
    workflow_inventory: ?workflow_inventory.Inventory = null,
    workflow_captures: ?[]const workflow_inventory.Capture = null,
    raw_workflow_definitions: ?[]const workflow_definition.RawDefinition = null,
    workflow_definitions: ?[]const workflow_definition.Definition = null,
    compiled_workflow_graphs: ?[]const workflow_compilation.CompiledWorkflow = null,
    validated_workflow_graphs: ?workflow_compilation.ValidatedGraphs = null,
    workflow_registry_candidate: ?workflow_registry.RegistryCandidate = null,
    validated_workflow_owner: ?*workflow_registry.Owner = null,
    toolchain_scratch: std.heap.ArenaAllocator,
    project_toolchain_capture: ?toolchain.Capture = null,
    toolchain_preset_inventory: ?[]const toolchain.Entry = null,
    toolchain_preset_captures: ?[]const toolchain.Capture = null,
    raw_toolchain_documents: ?[]const toolchain.RawDocument = null,
    project_toolchain: ?toolchain.Project = null,
    toolchain_registry: ?toolchain.Registry = null,
    resolved_toolchain: ?toolchain.Resolved = null,
    composed_toolchain: ?toolchain.Composed = null,
    valid_toolchain_owner: ?*toolchain_safety.Owner = null,

    pub fn init(
        allocator: std.mem.Allocator,
        locate_action: locate.Action,
        read_action: read.Action,
        decode_action: decode.Action,
        canonicalize_log_level_action: canonicalize_log_level.Action,
        validate_logging_policy_action: validate_logging_policy.Action,
        validate_path_policy_action: validate_path_policy.Action,
        resolve_root_action: resolve_root.Action,
        validate_root_action: validate_root.Action,
        build_registry_id_action: build_registry_id.Action,
        build_registry_action: build_registry.Action,
        validate_registry_action: validate_registry.Action,
        build_workflow_layout_action: build_workflow_layout.Action,
        inventory_workflows_action: inventory_workflows.Action,
        capture_workflows_action: capture_workflows.Action,
        parse_workflows_action: parse_workflows.Action,
        validate_workflow_schema_action: validate_workflow_schema.Action,
        compile_workflows_action: compile_workflows.Action,
        validate_workflow_graphs_action: validate_workflow_graphs.Action,
        build_workflow_registry_action: build_workflow_registry.Action,
        validate_workflow_registry_action: validate_workflow_registry.Action,
        capture_project_toolchain_action: capture_project_toolchain.Action,
        inventory_toolchain_presets_action: inventory_toolchain_presets.Action,
        capture_toolchain_presets_action: capture_toolchain_presets.Action,
        parse_toolchain_documents_action: parse_toolchain_documents.Action,
        validate_project_toolchain_schema_action: validate_project_toolchain_schema.Action,
        validate_toolchain_preset_registry_action: validate_toolchain_preset_registry.Action,
        resolve_toolchain_inheritance_action: resolve_toolchain_inheritance.Action,
        compose_toolchain_action: compose_toolchain.Action,
        validate_toolchain_safety_action: validate_toolchain_safety.Action,
        runtime: pipeline.NodeRuntime,
    ) Runner {
        return .{
            .allocator = allocator,
            .runtime = runtime,
            .envelope = .init(&.{.invocation_working_directory}),
            .locate_action = locate_action,
            .read_action = read_action,
            .decode_action = decode_action,
            .canonicalize_log_level_action = canonicalize_log_level_action,
            .validate_logging_policy_action = validate_logging_policy_action,
            .validate_path_policy_action = validate_path_policy_action,
            .resolve_root_action = resolve_root_action,
            .validate_root_action = validate_root_action,
            .build_registry_id_action = build_registry_id_action,
            .build_registry_action = build_registry_action,
            .validate_registry_action = validate_registry_action,
            .build_workflow_layout_action = build_workflow_layout_action,
            .inventory_workflows_action = inventory_workflows_action,
            .capture_workflows_action = capture_workflows_action,
            .parse_workflows_action = parse_workflows_action,
            .validate_workflow_schema_action = validate_workflow_schema_action,
            .compile_workflows_action = compile_workflows_action,
            .validate_workflow_graphs_action = validate_workflow_graphs_action,
            .build_workflow_registry_action = build_workflow_registry_action,
            .validate_workflow_registry_action = validate_workflow_registry_action,
            .capture_project_toolchain_action = capture_project_toolchain_action,
            .inventory_toolchain_presets_action = inventory_toolchain_presets_action,
            .capture_toolchain_presets_action = capture_toolchain_presets_action,
            .parse_toolchain_documents_action = parse_toolchain_documents_action,
            .validate_project_toolchain_schema_action = validate_project_toolchain_schema_action,
            .validate_toolchain_preset_registry_action = validate_toolchain_preset_registry_action,
            .resolve_toolchain_inheritance_action = resolve_toolchain_inheritance_action,
            .compose_toolchain_action = compose_toolchain_action,
            .validate_toolchain_safety_action = validate_toolchain_safety_action,
            .root_scratch = .init(allocator),
            .workflow_scratch = .init(allocator),
            .toolchain_scratch = .init(allocator),
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
        if (self.validated_log_owner) |owner| logging.deinitOwner(owner);
        if (self.validated_root_owner) |owner| bootstrap_root_registry.deinitOwner(owner);
        if (self.validated_workflow_owner) |owner| workflow_registry.deinitOwner(owner);
        if (self.valid_toolchain_owner) |owner| toolchain_safety.deinitOwner(owner);
        self.toolchain_scratch.deinit();
        self.workflow_scratch.deinit();
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

    fn invokeCanonicalizeLogLevel(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            canonicalize_log_level.Action.contract,
            .LOGGING_POLICY_INVALID,
        )) |outcome| return outcome;
        std.debug.assert(self.decoded_config != null);
        std.debug.assert(self.canonicalized_log_level == null);
        self.canonicalized_log_level = self.canonicalize_log_level_action.execute(
            self.decoded_config.?.value().logs.level,
        ) catch return .{ .failed = .LOGGING_POLICY_INVALID };
        return self.finishNode(
            canonicalize_log_level.Action.contract,
            .LOGGING_POLICY_INVALID,
        );
    }

    fn invokeValidateLoggingPolicy(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(
            validate_logging_policy.Action.contract,
            .LOGGING_POLICY_INVALID,
        )) |outcome| return outcome;
        std.debug.assert(self.decoded_config != null);
        std.debug.assert(self.canonicalized_log_level != null);
        std.debug.assert(self.validated_log_owner == null);
        self.validated_log_owner = self.validate_logging_policy_action.execute(
            self.allocator,
            self.decoded_config.?.value().logs,
            self.canonicalized_log_level.?,
        ) catch return .{ .failed = .LOGGING_POLICY_INVALID };
        return self.finishNode(
            validate_logging_policy.Action.contract,
            .LOGGING_POLICY_INVALID,
        );
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

    fn invokeBuildWorkflowLayout(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(build_workflow_layout.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        std.debug.assert(self.validated_root_owner != null);
        self.workflow_layout = self.build_workflow_layout_action.execute(
            bootstrap_root_registry.registry(self.validated_root_owner.?),
        ) catch return .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID };
        return self.finishNode(build_workflow_layout.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    fn invokeInventoryWorkflows(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(inventory_workflows.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID)) |outcome| return outcome;
        self.workflow_inventory = self.inventory_workflows_action.execute(
            self.workflow_scratch.allocator(),
            self.workflow_layout.?,
            self.runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.WorkflowAuthorityInventoryInvalid => .{ .failed = .WORKFLOW_AUTHORITY_INVENTORY_INVALID },
        };
        return self.finishNode(inventory_workflows.Action.contract, .WORKFLOW_AUTHORITY_INVENTORY_INVALID);
    }

    fn invokeCaptureWorkflows(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(capture_workflows.Action.contract, .WORKFLOW_DEFINITION_READ_ERROR)) |outcome| return outcome;
        self.workflow_captures = self.capture_workflows_action.execute(
            self.workflow_scratch.allocator(),
            self.workflow_inventory.?,
            self.runtime,
        ) catch |failure| return switch (failure) {
            error.Cancelled => .cancelled,
            error.WorkflowDefinitionReadError => .{ .failed = .WORKFLOW_DEFINITION_READ_ERROR },
        };
        return self.finishNode(capture_workflows.Action.contract, .WORKFLOW_DEFINITION_READ_ERROR);
    }

    fn invokeParseWorkflows(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(parse_workflows.Action.contract, .WORKFLOW_DEFINITION_PARSE_ERROR)) |outcome| return outcome;
        self.raw_workflow_definitions = self.parse_workflows_action.execute(
            self.workflow_scratch.allocator(),
            self.workflow_captures.?,
        ) catch return .{ .failed = .WORKFLOW_DEFINITION_PARSE_ERROR };
        return self.finishNode(parse_workflows.Action.contract, .WORKFLOW_DEFINITION_PARSE_ERROR);
    }

    fn invokeValidateWorkflowSchema(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(validate_workflow_schema.Action.contract, .WORKFLOW_DEFINITION_SCHEMA_INVALID)) |outcome| return outcome;
        self.workflow_definitions = self.validate_workflow_schema_action.execute(
            self.workflow_scratch.allocator(),
            self.raw_workflow_definitions.?,
        ) catch return .{ .failed = .WORKFLOW_DEFINITION_SCHEMA_INVALID };
        return self.finishNode(validate_workflow_schema.Action.contract, .WORKFLOW_DEFINITION_SCHEMA_INVALID);
    }

    fn invokeCompileWorkflows(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(compile_workflows.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID)) |outcome| return outcome;
        self.compiled_workflow_graphs = self.compile_workflows_action.execute(
            self.workflow_scratch.allocator(),
            self.workflow_definitions.?,
        ) catch return .{ .failed = .WORKFLOW_GRAPH_COMPILE_INVALID };
        return self.finishNode(compile_workflows.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID);
    }

    fn invokeValidateWorkflowGraphs(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(validate_workflow_graphs.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID)) |outcome| return outcome;
        self.validated_workflow_graphs = self.validate_workflow_graphs_action.execute(
            self.workflow_scratch.allocator(),
            self.compiled_workflow_graphs.?,
        ) catch return .{ .failed = .WORKFLOW_GRAPH_COMPILE_INVALID };
        return self.finishNode(validate_workflow_graphs.Action.contract, .WORKFLOW_GRAPH_COMPILE_INVALID);
    }

    fn invokeBuildWorkflowRegistry(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(build_workflow_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID)) |outcome| return outcome;
        self.workflow_registry_candidate = self.build_workflow_registry_action.execute(
            self.workflow_scratch.allocator(),
            self.workflow_inventory.?,
            self.workflow_captures.?,
            self.workflow_definitions.?,
            self.validated_workflow_graphs.?,
        ) catch return .{ .failed = .WORKFLOW_REGISTRY_INVALID };
        return self.finishNode(build_workflow_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID);
    }

    fn invokeValidateWorkflowRegistry(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(validate_workflow_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID)) |outcome| return outcome;
        self.validated_workflow_owner = self.validate_workflow_registry_action.execute(
            self.allocator,
            self.workflow_registry_candidate.?,
        ) catch return .{ .failed = .WORKFLOW_REGISTRY_INVALID };
        return self.finishNode(validate_workflow_registry.Action.contract, .WORKFLOW_REGISTRY_INVALID);
    }

    fn invokeCaptureProjectToolchain(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(capture_project_toolchain.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.project_toolchain_capture = self.capture_project_toolchain_action.execute(
            self.toolchain_scratch.allocator(),
            bootstrap_root_registry.registry(self.validated_root_owner.?),
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(capture_project_toolchain.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeInventoryToolchainPresets(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(inventory_toolchain_presets.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.toolchain_preset_inventory = self.inventory_toolchain_presets_action.execute(
            self.toolchain_scratch.allocator(),
            bootstrap_root_registry.registry(self.validated_root_owner.?),
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(inventory_toolchain_presets.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeCaptureToolchainPresets(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(capture_toolchain_presets.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.toolchain_preset_captures = self.capture_toolchain_presets_action.execute(
            self.toolchain_scratch.allocator(),
            bootstrap_root_registry.registry(self.validated_root_owner.?),
            self.project_toolchain_capture.?,
            self.toolchain_preset_inventory.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(capture_toolchain_presets.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeParseToolchainDocuments(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(parse_toolchain_documents.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.raw_toolchain_documents = self.parse_toolchain_documents_action.execute(
            self.toolchain_scratch.allocator(),
            self.project_toolchain_capture.?,
            self.toolchain_preset_captures.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(parse_toolchain_documents.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeValidateProjectToolchainSchema(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(validate_project_toolchain_schema.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.project_toolchain = self.validate_project_toolchain_schema_action.execute(
            self.toolchain_scratch.allocator(),
            self.raw_toolchain_documents.?[0],
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(validate_project_toolchain_schema.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeValidateToolchainPresetRegistry(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(validate_toolchain_preset_registry.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.toolchain_registry = self.validate_toolchain_preset_registry_action.execute(
            self.toolchain_scratch.allocator(),
            self.raw_toolchain_documents.?[1..],
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(validate_toolchain_preset_registry.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeResolveToolchainInheritance(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(resolve_toolchain_inheritance.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.resolved_toolchain = self.resolve_toolchain_inheritance_action.execute(
            self.toolchain_scratch.allocator(),
            self.project_toolchain.?,
            self.toolchain_registry.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(resolve_toolchain_inheritance.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeComposeToolchain(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(compose_toolchain.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.composed_toolchain = self.compose_toolchain_action.execute(
            self.toolchain_scratch.allocator(),
            self.project_toolchain.?,
            self.resolved_toolchain.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(compose_toolchain.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn invokeValidateToolchainSafety(context: *anyopaque) child_bindings.StepOutcome {
        const self: *Runner = @ptrCast(@alignCast(context));
        if (self.beginNode(validate_toolchain_safety.Action.contract, .TOOLCHAIN_INVALID)) |outcome| return outcome;
        self.valid_toolchain_owner = self.validate_toolchain_safety_action.execute(
            self.allocator,
            self.composed_toolchain.?,
        ) catch return .{ .failed = .TOOLCHAIN_INVALID };
        return self.finishNode(validate_toolchain_safety.Action.contract, .TOOLCHAIN_INVALID);
    }

    fn takeServices(context: *anyopaque) bootstrap_services.BootstrapServices {
        const self: *Runner = @ptrCast(@alignCast(context));
        std.debug.assert(self.envelope.contains(.bootstrap_root_registry_evidence));
        const owned_config = self.decoded_config.?;
        self.decoded_config = null;
        const owned_roots = self.validated_root_owner.?;
        self.validated_root_owner = null;
        const owned_logs = self.validated_log_owner.?;
        self.validated_log_owner = null;
        const owned_workflows = self.validated_workflow_owner.?;
        self.validated_workflow_owner = null;
        const owned_toolchain = self.valid_toolchain_owner.?;
        self.valid_toolchain_owner = null;
        return .{
            .config = sddtoolkit_config_service.SDDToolKitConfigService.init(owned_config),
            .roots = bootstrap_root_registry_service.BootstrapRootRegistryService.init(owned_roots),
            .logs = log_service.LogService.init(owned_logs),
            .workflows = workflow_definition_registry_service.WorkflowDefinitionRegistryService.init(owned_workflows),
            .toolchain = toolchain_service.ToolChainService.init(owned_toolchain),
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
    .canonicalize_log_level = Runner.invokeCanonicalizeLogLevel,
    .validate_logging_policy = Runner.invokeValidateLoggingPolicy,
    .validate_root_paths = Runner.invokeValidateRootPaths,
    .resolve_roots = Runner.invokeResolveRoots,
    .validate_roots = Runner.invokeValidateRoots,
    .build_registry_id = Runner.invokeBuildRegistryId,
    .build_registry = Runner.invokeBuildRegistry,
    .validate_registry = Runner.invokeValidateRegistry,
    .build_workflow_layout = Runner.invokeBuildWorkflowLayout,
    .inventory_workflows = Runner.invokeInventoryWorkflows,
    .capture_workflows = Runner.invokeCaptureWorkflows,
    .parse_workflows = Runner.invokeParseWorkflows,
    .validate_workflow_schema = Runner.invokeValidateWorkflowSchema,
    .compile_workflows = Runner.invokeCompileWorkflows,
    .validate_workflow_graphs = Runner.invokeValidateWorkflowGraphs,
    .build_workflow_registry = Runner.invokeBuildWorkflowRegistry,
    .validate_workflow_registry = Runner.invokeValidateWorkflowRegistry,
    .capture_project_toolchain = Runner.invokeCaptureProjectToolchain,
    .inventory_toolchain_presets = Runner.invokeInventoryToolchainPresets,
    .capture_toolchain_presets = Runner.invokeCaptureToolchainPresets,
    .parse_toolchain_documents = Runner.invokeParseToolchainDocuments,
    .validate_project_toolchain_schema = Runner.invokeValidateProjectToolchainSchema,
    .validate_toolchain_preset_registry = Runner.invokeValidateToolchainPresetRegistry,
    .resolve_toolchain_inheritance = Runner.invokeResolveToolchainInheritance,
    .compose_toolchain = Runner.invokeComposeToolchain,
    .validate_toolchain_safety = Runner.invokeValidateToolchainSafety,
    .take_services = Runner.takeServices,
};
