const std = @import("std");
const bootstrap_error = @import("../domain/bootstrap_error.zig");
const bootstrap_roots = @import("../domain/bootstrap_roots.zig");
const bootstrap_root_registry = @import("../domain/bootstrap_root_registry.zig");
const config = @import("../domain/config.zig");
const log_policy = @import("../domain/log_policy.zig");
const pipeline = @import("../domain/pipeline.zig");
const definition = @import("../domain/workflow_definition.zig");
const compilation = @import("../domain/workflow_compilation.zig");
const inventory = @import("../domain/workflow_inventory.zig");
const workflow_registry = @import("../domain/workflow_registry.zig");
const config_decoding = @import("../domain/engine_config_decode.zig");
const root_derivation = @import("../domain/bootstrap_root_derivation.zig");
const inventory_building = @import("../domain/workflow_authority_inventory_build.zig");
const resource_binding = @import("../domain/workflow_resource_binding.zig");
const definition_schema = @import("../domain/workflow_definition_schema.zig");
const graph_compilation = @import("../domain/workflow_graph_compilation.zig");
const graph_validation = @import("../domain/workflow_graph_validation.zig");
const config_port = @import("../ports/engine_config_source.zig");
const inspector_port = @import("../ports/bootstrap_root_inspector.zig");
const source_port = @import("../ports/workflow_authority_source.zig");
const parser_port = @import("../ports/workflow_definition_parser.zig");
const operation_registry = @import("../ports/workflow_operation_registry.zig");
const schema_compiler_port = @import("../ports/model_result_schema_compiler.zig");

// ADR 0032: startup before workflow selection as one engine routine. It locates and reads the
// engine configuration, validates the logging policy and the configured roots, builds the root
// registry, captures and validates the workflow authority, and builds the workflow registry. It is
// not a pipeline node and no workflow can select it. Public error codes are unchanged: every
// failure of a step, including allocation failure and deadline exhaustion, maps to that step's
// fixed code, and explicit cancellation stays distinct. It acquires no feature transaction lock.

/// The closed set of steps, in execution order. A failure or a stop at a checkpoint records the
/// step it belongs to in the caller's `Diagnostic`.
pub const Step = enum {
    locate_config,
    read_config,
    decode_config,
    canonicalize_log_level,
    validate_logging_policy,
    validate_root_paths,
    validate_provider_path,
    resolve_roots,
    resolve_provider_path,
    validate_roots,
    build_registry_id,
    build_root_registry,
    validate_root_registry,
    build_workflow_layout,
    enumerate_workflow_resources,
    normalize_workflow_entries,
    build_workflow_accounts,
    build_workflow_inventory,
    validate_workflow_inventory,
    capture_workflows,
    parse_workflows,
    validate_workflow_schema,
    resolve_workflow_resources,
    capture_workflow_resources,
    validate_workflow_operations,
    compile_workflows,
    validate_workflow_graphs,
    build_workflow_registry,
    validate_workflow_registry,
};

pub const Diagnostic = struct { step: ?Step = null };

/// The ports the routine's steps reach. No step receives this set; each takes the one port it uses.
pub const Ports = struct {
    config_locator: config_port.Locator,
    root_inspector: inspector_port.Inspector,
    workflow_enumerator: source_port.Enumerator,
    workflow_capturer: source_port.Capturer,
    workflow_parser: parser_port.Parser,
    result_schema_compiler: schema_compiler_port.Compiler,
};

/// Closed values the routine reads: the platform path limits and the registered operation contracts.
pub const Inputs = struct {
    path_policy: bootstrap_roots.WorkspacePathPolicy,
    operations: *const operation_registry.Registry,
};

/// The validated owners a run publishes, built only after every step has validated.
pub const Ready = struct {
    config: config.Owned,
    logging_policy: *log_policy.Owner,
    roots: *bootstrap_root_registry.Owner,
    workflows: *workflow_registry.Owner,

    pub fn deinit(self: *Ready) void {
        workflow_registry.deinitOwner(self.workflows);
        bootstrap_root_registry.deinitOwner(self.roots);
        log_policy.deinitOwner(self.logging_policy);
        self.config.deinit();
        self.* = undefined;
    }
};

pub const Outcome = union(enum) {
    ready: Ready,
    failed: bootstrap_error.PublicError,
    cancelled,

    pub fn deinit(self: *Outcome) void {
        switch (self.*) {
            .ready => |*value| value.deinit(),
            .failed, .cancelled => {},
        }
        self.* = undefined;
    }
};

/// The operation registry after `validateWorkflowOperations` accepted it. Compilation requires it.
pub const ValidatedOperations = struct { registry: *const operation_registry.Registry };

const RootCount = bootstrap_roots.PathKey.count;
pub const NormalizedPaths = [RootCount]bootstrap_roots.NormalizedConfiguredPath;
pub const RootCandidates = [RootCount]bootstrap_roots.ConfiguredRootCandidate;
pub const RootCapabilities = [RootCount]bootstrap_roots.ValidatedConfiguredRoot;

/// The entry function only sequences the steps and passes each port on. It checks the runtime after
/// each step, and before the first, and reports the step each stop belongs to. All intermediate
/// candidates live in one scratch arena; the owners it publishes are built on `allocator`.
pub fn run(
    ports: Ports,
    allocator: std.mem.Allocator,
    runtime: pipeline.NodeRuntime,
    diagnostic: *Diagnostic,
    inputs: Inputs,
) Outcome {
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const arena = scratch.allocator();

    if (checkpoint(runtime, diagnostic, .locate_config)) |stop| return stop;
    var exact = steps.locateConfig(ports.config_locator, allocator) catch return failed(diagnostic, .locate_config);
    defer exact.deinit(allocator);
    if (checkpoint(runtime, diagnostic, .locate_config)) |stop| return stop;
    var raw = steps.readConfig(&exact, allocator) catch return failed(diagnostic, .read_config);
    defer raw.deinit(allocator);
    if (checkpoint(runtime, diagnostic, .read_config)) |stop| return stop;
    var decoded = steps.decodeConfig(allocator, raw.bytes) catch return failed(diagnostic, .decode_config);
    var published = false;
    defer if (!published) decoded.deinit();
    if (checkpoint(runtime, diagnostic, .decode_config)) |stop| return stop;
    const canonicalized = steps.canonicalizeLogLevel(decoded.value().logs.level) catch return failed(diagnostic, .canonicalize_log_level);
    if (checkpoint(runtime, diagnostic, .canonicalize_log_level)) |stop| return stop;
    const logging_owner = steps.validateLoggingPolicy(allocator, decoded.value().logs, canonicalized) catch return failed(diagnostic, .validate_logging_policy);
    defer if (!published) log_policy.deinitOwner(logging_owner);
    if (checkpoint(runtime, diagnostic, .validate_logging_policy)) |stop| return stop;

    const normalized_paths = steps.validateRootPaths(inputs.path_policy, arena, decoded.value().paths) catch return failed(diagnostic, .validate_root_paths);
    if (checkpoint(runtime, diagnostic, .validate_root_paths)) |stop| return stop;
    const normalized_provider = steps.validateProviderPath(inputs.path_policy, arena, decoded.value().paths.providers) catch return failed(diagnostic, .validate_provider_path);
    if (checkpoint(runtime, diagnostic, .validate_provider_path)) |stop| return stop;
    const root_candidates = steps.resolveRoots(inputs.path_policy, arena, exact.canonical_project_root, &normalized_paths) catch return failed(diagnostic, .resolve_roots);
    if (checkpoint(runtime, diagnostic, .resolve_roots)) |stop| return stop;
    const provider_candidate = steps.resolveProviderPath(inputs.path_policy, arena, exact.canonical_project_root, normalized_provider) catch return failed(diagnostic, .resolve_provider_path);
    if (checkpoint(runtime, diagnostic, .resolve_provider_path)) |stop| return stop;
    const root_capabilities = steps.validateRoots(ports.root_inspector, &root_candidates) catch |failure| return if (failure == error.Cancelled) stopped(diagnostic, .validate_roots, .cancelled) else failed(diagnostic, .validate_roots);
    if (checkpoint(runtime, diagnostic, .validate_roots)) |stop| return stop;
    const registry_id = steps.buildRegistryId(arena, exact.canonical_project_root) catch return failed(diagnostic, .build_registry_id);
    if (checkpoint(runtime, diagnostic, .build_registry_id)) |stop| return stop;
    const root_candidate = steps.buildRootRegistry(arena, registry_id, &exact, root_capabilities, provider_candidate) catch return failed(diagnostic, .build_root_registry);
    if (checkpoint(runtime, diagnostic, .build_root_registry)) |stop| return stop;
    const roots_owner = steps.validateRootRegistry(allocator, root_candidate) catch return failed(diagnostic, .validate_root_registry);
    defer if (!published) bootstrap_root_registry.deinitOwner(roots_owner);
    if (checkpoint(runtime, diagnostic, .validate_root_registry)) |stop| return stop;

    const layout = steps.buildWorkflowLayout(bootstrap_root_registry.registry(roots_owner));
    if (checkpoint(runtime, diagnostic, .build_workflow_layout)) |stop| return stop;
    const raw_entries = steps.enumerateWorkflowResources(ports.workflow_enumerator, arena, layout, runtime) catch |failure| return if (failure == error.Cancelled) stopped(diagnostic, .enumerate_workflow_resources, .cancelled) else failed(diagnostic, .enumerate_workflow_resources);
    if (checkpoint(runtime, diagnostic, .enumerate_workflow_resources)) |stop| return stop;
    const entries = steps.normalizeWorkflowEntries(raw_entries) catch return failed(diagnostic, .normalize_workflow_entries);
    if (checkpoint(runtime, diagnostic, .normalize_workflow_entries)) |stop| return stop;
    const accounts = steps.buildWorkflowAccounts(arena, entries) catch return failed(diagnostic, .build_workflow_accounts);
    if (checkpoint(runtime, diagnostic, .build_workflow_accounts)) |stop| return stop;
    const inventory_candidate = steps.buildWorkflowInventory(layout, entries, accounts);
    if (checkpoint(runtime, diagnostic, .build_workflow_inventory)) |stop| return stop;
    const workflow_inventory = steps.validateWorkflowInventory(inventory_candidate) catch return failed(diagnostic, .validate_workflow_inventory);
    if (checkpoint(runtime, diagnostic, .validate_workflow_inventory)) |stop| return stop;

    const definition_captures = steps.captureWorkflows(ports.workflow_capturer, arena, workflow_inventory, runtime) catch |failure| return if (failure == error.Cancelled) stopped(diagnostic, .capture_workflows, .cancelled) else failed(diagnostic, .capture_workflows);
    if (checkpoint(runtime, diagnostic, .capture_workflows)) |stop| return stop;
    const raw_definitions = steps.parseWorkflows(ports.workflow_parser, arena, definition_captures) catch return failed(diagnostic, .parse_workflows);
    if (checkpoint(runtime, diagnostic, .parse_workflows)) |stop| return stop;
    const definitions = steps.validateWorkflowSchema(arena, raw_definitions) catch return failed(diagnostic, .validate_workflow_schema);
    if (checkpoint(runtime, diagnostic, .validate_workflow_schema)) |stop| return stop;
    const manifest = steps.resolveWorkflowResources(arena, workflow_inventory, definitions) catch return failed(diagnostic, .resolve_workflow_resources);
    if (checkpoint(runtime, diagnostic, .resolve_workflow_resources)) |stop| return stop;
    const resource_captures = steps.captureWorkflowResources(ports.workflow_capturer, arena, workflow_inventory, manifest, runtime) catch |failure| return if (failure == error.Cancelled) stopped(diagnostic, .capture_workflow_resources, .cancelled) else failed(diagnostic, .capture_workflow_resources);
    if (checkpoint(runtime, diagnostic, .capture_workflow_resources)) |stop| return stop;
    const operations = steps.validateWorkflowOperations(inputs.operations) catch return failed(diagnostic, .validate_workflow_operations);
    if (checkpoint(runtime, diagnostic, .validate_workflow_operations)) |stop| return stop;
    const graphs = steps.compileWorkflows(ports.result_schema_compiler, operations, arena, definitions, workflow_inventory, manifest, resource_captures) catch return failed(diagnostic, .compile_workflows);
    if (checkpoint(runtime, diagnostic, .compile_workflows)) |stop| return stop;
    const validated_graphs = steps.validateWorkflowGraphs(arena, graphs, operations) catch return failed(diagnostic, .validate_workflow_graphs);
    if (checkpoint(runtime, diagnostic, .validate_workflow_graphs)) |stop| return stop;
    const workflow_candidate = steps.buildWorkflowRegistry(arena, workflow_inventory, definition_captures, manifest, resource_captures, definitions, validated_graphs, operations) catch return failed(diagnostic, .build_workflow_registry);
    if (checkpoint(runtime, diagnostic, .build_workflow_registry)) |stop| return stop;
    const workflows_owner = steps.validateWorkflowRegistry(allocator, workflow_candidate) catch return failed(diagnostic, .validate_workflow_registry);
    defer if (!published) workflow_registry.deinitOwner(workflows_owner);
    if (checkpoint(runtime, diagnostic, .validate_workflow_registry)) |stop| return stop;

    published = true;
    return .{ .ready = .{
        .config = decoded,
        .logging_policy = logging_owner,
        .roots = roots_owner,
        .workflows = workflows_owner,
    } };
}

/// The public code a step's failure maps to.
pub fn code(step: Step) bootstrap_error.PublicError {
    return switch (step) {
        .locate_config, .read_config => .ENGINE_CONFIG_READ_ERROR,
        .decode_config => .ENGINE_CONFIG_PARSE_ERROR,
        .canonicalize_log_level, .validate_logging_policy => .LOGGING_POLICY_INVALID,
        .validate_root_paths,
        .validate_provider_path,
        .resolve_roots,
        .resolve_provider_path,
        .validate_roots,
        => .BOOTSTRAP_ROOT_RESOLUTION_ERROR,
        .build_registry_id, .build_root_registry, .validate_root_registry => .BOOTSTRAP_ROOT_REGISTRY_INVALID,
        .build_workflow_layout,
        .enumerate_workflow_resources,
        .normalize_workflow_entries,
        .build_workflow_accounts,
        .build_workflow_inventory,
        .validate_workflow_inventory,
        .resolve_workflow_resources,
        => .WORKFLOW_AUTHORITY_INVENTORY_INVALID,
        .capture_workflows, .capture_workflow_resources => .WORKFLOW_DEFINITION_READ_ERROR,
        .parse_workflows => .WORKFLOW_DEFINITION_PARSE_ERROR,
        .validate_workflow_schema => .WORKFLOW_DEFINITION_SCHEMA_INVALID,
        .validate_workflow_operations, .compile_workflows, .validate_workflow_graphs => .WORKFLOW_GRAPH_COMPILE_INVALID,
        .build_workflow_registry, .validate_workflow_registry => .WORKFLOW_REGISTRY_INVALID,
    };
}

fn failed(diagnostic: *Diagnostic, step: Step) Outcome {
    diagnostic.step = step;
    return .{ .failed = code(step) };
}

/// Stops on cancellation, and on deadline exhaustion with `step`'s code: the step the checkpoint
/// follows, or the first step for the opening checkpoint.
fn checkpoint(runtime: pipeline.NodeRuntime, diagnostic: *Diagnostic, step: Step) ?Outcome {
    return switch (runtime.status()) {
        .active => null,
        .cancelled => stopped(diagnostic, step, .cancelled),
        .deadline_exhausted => stopped(diagnostic, step, .{ .failed = code(step) }),
    };
}

fn stopped(diagnostic: *Diagnostic, step: Step, outcome: Outcome) Outcome {
    diagnostic.step = step;
    return outcome;
}

/// The twenty-nine steps. Each is one typed function; a step that reaches a port takes exactly that
/// port, and none takes the port set. The pure steps call their domain owners.
pub const steps = struct {
    pub fn locateConfig(locator: config_port.Locator, allocator: std.mem.Allocator) config_port.Error!config_port.ExactEngineConfigFile {
        return locator.locate(allocator);
    }

    /// Reads the located file's one capture within the compiler's byte limit; it never parses.
    pub fn readConfig(exact: *config_port.ExactEngineConfigFile, allocator: std.mem.Allocator) config_port.Error!config_port.RawEngineConfig {
        return exact.read(allocator, config.max_engine_config_bytes);
    }

    pub fn decodeConfig(allocator: std.mem.Allocator, bytes: []const u8) config_decoding.Error!config.Owned {
        return config_decoding.decode(allocator, bytes);
    }

    pub fn canonicalizeLogLevel(raw: []const u8) error{LoggingPolicyInvalid}!log_policy.CanonicalizedLevel {
        return log_policy.canonicalizeConfiguredLevel(raw) catch error.LoggingPolicyInvalid;
    }

    pub fn validateLoggingPolicy(
        allocator: std.mem.Allocator,
        logs: config.LogsConfig,
        canonicalized: log_policy.CanonicalizedLevel,
    ) error{LoggingPolicyInvalid}!*log_policy.Owner {
        return log_policy.createValidated(allocator, logs, canonicalized) catch error.LoggingPolicyInvalid;
    }

    pub fn validateRootPaths(
        policy: bootstrap_roots.WorkspacePathPolicy,
        allocator: std.mem.Allocator,
        paths: config.PathsConfig,
    ) root_derivation.ResolutionError!NormalizedPaths {
        var normalized: NormalizedPaths = undefined;
        for (&normalized, 0..) |*slot, index| {
            const key: bootstrap_roots.PathKey = @enumFromInt(index);
            slot.* = try root_derivation.normalizeRootPath(policy, allocator, key, configuredPath(paths, key));
        }
        return normalized;
    }

    pub fn validateProviderPath(
        policy: bootstrap_roots.WorkspacePathPolicy,
        allocator: std.mem.Allocator,
        raw_path: []const u8,
    ) root_derivation.ResolutionError!bootstrap_roots.NormalizedLLMProviderConfigPath {
        return root_derivation.normalizeProviderPath(policy, allocator, raw_path);
    }

    pub fn resolveRoots(
        policy: bootstrap_roots.WorkspacePathPolicy,
        allocator: std.mem.Allocator,
        canonical_project_root: []const u8,
        normalized: *const NormalizedPaths,
    ) root_derivation.ResolutionError!RootCandidates {
        var candidates: RootCandidates = undefined;
        for (&candidates, normalized) |*slot, path| {
            slot.* = try root_derivation.resolveRoot(policy, allocator, canonical_project_root, path);
        }
        return candidates;
    }

    pub fn resolveProviderPath(
        policy: bootstrap_roots.WorkspacePathPolicy,
        allocator: std.mem.Allocator,
        canonical_project_root: []const u8,
        normalized: bootstrap_roots.NormalizedLLMProviderConfigPath,
    ) root_derivation.ResolutionError!bootstrap_roots.LLMProviderConfigPathCandidate {
        return root_derivation.resolveProviderPath(policy, allocator, canonical_project_root, normalized);
    }

    pub fn validateRoots(
        inspector: inspector_port.Inspector,
        candidates: *const RootCandidates,
    ) error{ BootstrapRootResolutionError, Cancelled }!RootCapabilities {
        var capabilities: RootCapabilities = undefined;
        for (&capabilities, candidates) |*slot, candidate| slot.* = try validateRoot(inspector, candidate);
        return capabilities;
    }

    /// One root: a structurally valid candidate, observed once through the inspector, whose required
    /// directory must be present.
    pub fn validateRoot(
        inspector: inspector_port.Inspector,
        candidate: bootstrap_roots.ConfiguredRootCandidate,
    ) error{ BootstrapRootResolutionError, Cancelled }!bootstrap_roots.ValidatedConfiguredRoot {
        if (!candidate.isStructurallyValid()) return error.BootstrapRootResolutionError;
        const observation = inspector.inspect(candidate.path.relative_path) catch |inspection_error| {
            return switch (inspection_error) {
                error.Cancelled => error.Cancelled,
                error.BootstrapRootInspectionFailure => error.BootstrapRootResolutionError,
            };
        };
        if (candidate.path.path_key.existencePolicy() == .required_directory and observation == .absent) {
            return error.BootstrapRootResolutionError;
        }
        return .{
            .path_key = candidate.path.path_key,
            .root_role = candidate.path.root_role,
            .canonical_project_root = candidate.canonical_project_root,
            .configured_relative_path = candidate.path.relative_path,
            .canonical_path = candidate.canonical_path,
            .access_class = candidate.path.path_key.accessClass(),
            .existence_policy = candidate.path.path_key.existencePolicy(),
            .observation = observation,
        };
    }

    pub fn buildRegistryId(
        allocator: std.mem.Allocator,
        canonical_project_root: []const u8,
    ) root_derivation.RegistryError!bootstrap_roots.BootstrapRootRegistryId {
        return root_derivation.buildRegistryId(allocator, canonical_project_root);
    }

    pub fn buildRootRegistry(
        allocator: std.mem.Allocator,
        id: bootstrap_roots.BootstrapRootRegistryId,
        exact: *const config_port.ExactEngineConfigFile,
        capabilities: RootCapabilities,
        provider: bootstrap_roots.LLMProviderConfigPathCandidate,
    ) root_derivation.RegistryError!bootstrap_roots.BootstrapRootRegistryCandidate {
        return root_derivation.buildRegistryCandidate(
            allocator,
            id,
            exact.canonical_config_path,
            exact.no_follow_file_identity,
            capabilities,
            provider,
        );
    }

    pub fn validateRootRegistry(
        allocator: std.mem.Allocator,
        candidate: bootstrap_roots.BootstrapRootRegistryCandidate,
    ) bootstrap_root_registry.Error!*bootstrap_root_registry.Owner {
        return bootstrap_root_registry.createValidated(allocator, candidate);
    }

    pub fn buildWorkflowLayout(registry: *const bootstrap_root_registry.BootstrapRootRegistry) inventory.Layout {
        return inventory_building.buildLayout(registry);
    }

    pub fn enumerateWorkflowResources(
        enumerator: source_port.Enumerator,
        allocator: std.mem.Allocator,
        layout: inventory.Layout,
        runtime: pipeline.NodeRuntime,
    ) error{ Cancelled, WorkflowAuthorityInventoryInvalid }![]inventory.InventoryDescriptor {
        const descriptors = enumerator.enumerate(layout.capability, allocator, runtime) catch |failure| {
            return switch (failure) {
                error.Cancelled => error.Cancelled,
                else => error.WorkflowAuthorityInventoryInvalid,
            };
        };
        if (descriptors.len > inventory.max_inventory_entries) return error.WorkflowAuthorityInventoryInvalid;
        return descriptors;
    }

    pub fn normalizeWorkflowEntries(
        descriptors: []inventory.InventoryDescriptor,
    ) inventory_building.Error![]inventory.InventoryDescriptor {
        return inventory_building.normalizeEntries(descriptors);
    }

    pub fn buildWorkflowAccounts(
        allocator: std.mem.Allocator,
        descriptors: []const inventory.InventoryDescriptor,
    ) inventory_building.Error!inventory.AccountSet {
        return inventory_building.buildAccounts(allocator, descriptors);
    }

    pub fn buildWorkflowInventory(
        layout: inventory.Layout,
        descriptors: []const inventory.InventoryDescriptor,
        accounts: inventory.AccountSet,
    ) inventory.Inventory {
        return inventory_building.buildInventory(layout, descriptors, accounts);
    }

    /// The only producer of a `ValidatedInventory`: later steps require the wrapper, so a candidate
    /// inventory cannot reach capture, resource binding or registry building.
    pub fn validateWorkflowInventory(
        candidate: inventory.Inventory,
    ) inventory_building.Error!inventory_building.ValidatedInventory {
        return inventory_building.validate(candidate);
    }

    pub fn captureWorkflows(
        capturer: source_port.Capturer,
        allocator: std.mem.Allocator,
        validated: inventory_building.ValidatedInventory,
        runtime: pipeline.NodeRuntime,
    ) error{ Cancelled, WorkflowDefinitionReadError }![]const inventory.Capture {
        const inventory_value = validated.value;
        inventory.validateCaptureBudget(inventory_value) catch return error.WorkflowDefinitionReadError;
        const captures = allocator.alloc(inventory.Capture, inventory_value.definition_ordinals.len) catch {
            return error.WorkflowDefinitionReadError;
        };
        for (inventory_value.definition_ordinals, captures) |ordinal, *capture| {
            const descriptor = inventory_value.descriptors[ordinal - 1];
            const bytes = capturer.capture(inventory_value.capability, descriptor, allocator, runtime) catch |failure| {
                return switch (failure) {
                    error.Cancelled => error.Cancelled,
                    else => error.WorkflowDefinitionReadError,
                };
            };
            capture.* = .{ .ordinal = ordinal, .bytes = bytes };
        }
        return captures;
    }

    pub fn parseWorkflows(
        parser: parser_port.Parser,
        allocator: std.mem.Allocator,
        captures: []const inventory.Capture,
    ) error{WorkflowDefinitionParseError}![]const definition.RawDefinition {
        return parser.parse(allocator, captures) catch error.WorkflowDefinitionParseError;
    }

    pub fn validateWorkflowSchema(
        allocator: std.mem.Allocator,
        raw_definitions: []const definition.RawDefinition,
    ) definition_schema.Error![]const definition.Definition {
        return definition_schema.validate(allocator, raw_definitions);
    }

    pub fn resolveWorkflowResources(
        allocator: std.mem.Allocator,
        validated: inventory_building.ValidatedInventory,
        definitions: []const definition.Definition,
    ) resource_binding.Error!inventory.ResourceManifest {
        return resource_binding.resolve(allocator, validated.value, definitions);
    }

    pub fn captureWorkflowResources(
        capturer: source_port.Capturer,
        allocator: std.mem.Allocator,
        validated: inventory_building.ValidatedInventory,
        manifest: inventory.ResourceManifest,
        runtime: pipeline.NodeRuntime,
    ) error{ Cancelled, WorkflowResourceReadError }![]const inventory.Capture {
        const inventory_value = validated.value;
        inventory.validateResourceCaptureBudget(inventory_value, manifest) catch return error.WorkflowResourceReadError;
        const captures = allocator.alloc(inventory.Capture, manifest.resource_ordinals.len) catch return error.WorkflowResourceReadError;
        for (manifest.resource_ordinals, captures) |ordinal, *capture| {
            const descriptor = inventory_value.descriptors[ordinal - 1];
            const bytes = capturer.capture(inventory_value.capability, descriptor, allocator, runtime) catch |failure| {
                return switch (failure) {
                    error.Cancelled => error.Cancelled,
                    else => error.WorkflowResourceReadError,
                };
            };
            capture.* = .{ .ordinal = ordinal, .bytes = bytes };
        }
        return captures;
    }

    pub fn validateWorkflowOperations(
        registry: *const operation_registry.Registry,
    ) error{WorkflowOperationRegistryInvalid}!ValidatedOperations {
        if (!registry.validate()) return error.WorkflowOperationRegistryInvalid;
        return .{ .registry = registry };
    }

    pub fn compileWorkflows(
        result_schema_compiler: schema_compiler_port.Compiler,
        operations: ValidatedOperations,
        allocator: std.mem.Allocator,
        definitions: []const definition.Definition,
        validated: inventory_building.ValidatedInventory,
        manifest: inventory.ResourceManifest,
        captures: []const inventory.Capture,
    ) graph_compilation.Error![]const compilation.CompiledWorkflow {
        return graph_compilation.compile(operations.registry, result_schema_compiler, allocator, definitions, validated.value, manifest, captures);
    }

    pub fn validateWorkflowGraphs(
        allocator: std.mem.Allocator,
        graphs: []const compilation.CompiledWorkflow,
        operations: ValidatedOperations,
    ) graph_validation.Error!compilation.ValidatedGraphs {
        return graph_validation.validate(allocator, graphs, operations.registry);
    }

    pub fn buildWorkflowRegistry(
        allocator: std.mem.Allocator,
        validated: inventory_building.ValidatedInventory,
        definition_captures: []const inventory.Capture,
        manifest: inventory.ResourceManifest,
        resource_captures: []const inventory.Capture,
        definitions: []const definition.Definition,
        graphs: compilation.ValidatedGraphs,
        operations: ValidatedOperations,
    ) error{WorkflowRegistryInvalid}!workflow_registry.RegistryCandidate {
        const sorted = allocator.dupe(compilation.CompiledWorkflow, graphs.values) catch {
            return error.WorkflowRegistryInvalid;
        };
        std.mem.sort(compilation.CompiledWorkflow, sorted, {}, graphLessThan);
        return .{
            .inventory = validated.value,
            .definition_captures = definition_captures,
            .resource_manifest = manifest,
            .resource_captures = resource_captures,
            .definitions = definitions,
            .graphs = sorted,
            .operations = operations.registry,
        };
    }

    pub fn validateWorkflowRegistry(
        allocator: std.mem.Allocator,
        candidate: workflow_registry.RegistryCandidate,
    ) error{WorkflowRegistryInvalid}!*workflow_registry.Owner {
        return workflow_registry.createValidated(allocator, candidate) catch error.WorkflowRegistryInvalid;
    }
};

fn graphLessThan(_: void, left: compilation.CompiledWorkflow, right: compilation.CompiledWorkflow) bool {
    return std.mem.order(u8, left.authority.workflow_id.bytes, right.authority.workflow_id.bytes) == .lt;
}

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
