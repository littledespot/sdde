const child_bindings = @import("bootstrap_child_bindings.zig");
const config_runner = @import("bootstrap_config_runner.zig");
const root_runner = @import("bootstrap_root_runner.zig");
const workflow_runner = @import("bootstrap_workflow_runner.zig");
const toolchain_runner = @import("bootstrap_toolchain_runner.zig");
const bootstrap_services = @import("bootstrap_services.zig");
const config_service = @import("sddtoolkit_config_service.zig");
const root_service = @import("bootstrap_root_registry_service.zig");
const log_service = @import("log_service.zig");
const workflow_service = @import("workflow_definition_registry_service.zig");
const toolchain_service = @import("toolchain_service.zig");

pub const Runner = struct {
    config: *config_runner.Runner,
    roots: *root_runner.Runner,
    workflows: *workflow_runner.Runner,
    toolchain: *toolchain_runner.Runner,

    pub fn bindings(self: *Runner) child_bindings.ChildBindings {
        return .{ .context = self, .vtable = &vtable };
    }

    fn cast(context: *anyopaque) *Runner {
        return @ptrCast(@alignCast(context));
    }
    fn locate(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).config.invokeLocate();
    }
    fn read(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).config.invokeRead();
    }
    fn decode(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).config.invokeDecode();
    }
    fn canonicalizeLogLevel(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).config.invokeCanonicalizeLogLevel();
    }
    fn validateLoggingPolicy(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).config.invokeValidateLoggingPolicy();
    }
    fn validateRootPaths(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeValidateRootPaths();
    }
    fn validateProviderPath(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeValidateProviderPath();
    }
    fn resolveRoots(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeResolveRoots();
    }
    fn resolveProviderPath(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeResolveProviderPath();
    }
    fn validateRoots(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeValidateRoots();
    }
    fn buildRegistryId(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeBuildRegistryId();
    }
    fn buildRegistry(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeBuildRegistry();
    }
    fn validateRegistry(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).roots.invokeValidateRegistry();
    }
    fn buildWorkflowLayout(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeBuildLayout();
    }
    fn enumerateWorkflowResources(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeEnumerateResources();
    }
    fn normalizeWorkflowEntries(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeNormalizeEntries();
    }
    fn buildWorkflowAccounts(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeBuildAccounts();
    }
    fn buildWorkflowInventory(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeBuildInventory();
    }
    fn validateWorkflowInventory(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeValidateInventory();
    }
    fn captureWorkflows(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeCaptureDefinitions();
    }
    fn parseWorkflows(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeParseDefinitions();
    }
    fn validateWorkflowSchema(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeValidateSchema();
    }
    fn compileWorkflows(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeCompileGraphs();
    }
    fn validateWorkflowGraphs(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeValidateGraphs();
    }
    fn buildWorkflowRegistry(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeBuildRegistry();
    }
    fn validateWorkflowRegistry(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).workflows.invokeValidateRegistry();
    }
    fn captureProjectToolchain(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeCaptureProject();
    }
    fn inventoryToolchainPresets(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeInventoryPresets();
    }
    fn captureToolchainPresets(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeCapturePresets();
    }
    fn parseToolchainDocuments(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeParseDocuments();
    }
    fn validateProjectToolchainSchema(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeValidateProjectSchema();
    }
    fn validateToolchainPresetRegistry(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeValidatePresetRegistry();
    }
    fn resolveToolchainInheritance(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeResolveInheritance();
    }
    fn composeToolchain(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeCompose();
    }
    fn validateToolchainSafety(context: *anyopaque) child_bindings.StepOutcome {
        return cast(context).toolchain.invokeValidateSafety();
    }

    fn takeServices(context: *anyopaque) bootstrap_services.BootstrapServices {
        const self = cast(context);
        return .{
            .config = config_service.SDDToolKitConfigService.init(self.config.takeConfig()),
            .roots = root_service.BootstrapRootRegistryService.init(self.roots.takeRegistry()),
            .logs = log_service.LogService.init(self.config.takeLoggingPolicy()),
            .workflows = workflow_service.WorkflowDefinitionRegistryService.init(self.workflows.takeRegistry()),
            .toolchain = toolchain_service.ToolChainService.init(self.toolchain.takeToolchain()),
        };
    }
};

const vtable: child_bindings.ChildBindings.VTable = .{
    .locate = Runner.locate,
    .read = Runner.read,
    .decode = Runner.decode,
    .canonicalize_log_level = Runner.canonicalizeLogLevel,
    .validate_logging_policy = Runner.validateLoggingPolicy,
    .validate_root_paths = Runner.validateRootPaths,
    .validate_provider_path = Runner.validateProviderPath,
    .resolve_roots = Runner.resolveRoots,
    .resolve_provider_path = Runner.resolveProviderPath,
    .validate_roots = Runner.validateRoots,
    .build_registry_id = Runner.buildRegistryId,
    .build_registry = Runner.buildRegistry,
    .validate_registry = Runner.validateRegistry,
    .build_workflow_layout = Runner.buildWorkflowLayout,
    .enumerate_workflow_resources = Runner.enumerateWorkflowResources,
    .normalize_workflow_entries = Runner.normalizeWorkflowEntries,
    .build_workflow_accounts = Runner.buildWorkflowAccounts,
    .build_workflow_inventory = Runner.buildWorkflowInventory,
    .validate_workflow_inventory = Runner.validateWorkflowInventory,
    .capture_workflows = Runner.captureWorkflows,
    .parse_workflows = Runner.parseWorkflows,
    .validate_workflow_schema = Runner.validateWorkflowSchema,
    .compile_workflows = Runner.compileWorkflows,
    .validate_workflow_graphs = Runner.validateWorkflowGraphs,
    .build_workflow_registry = Runner.buildWorkflowRegistry,
    .validate_workflow_registry = Runner.validateWorkflowRegistry,
    .capture_project_toolchain = Runner.captureProjectToolchain,
    .inventory_toolchain_presets = Runner.inventoryToolchainPresets,
    .capture_toolchain_presets = Runner.captureToolchainPresets,
    .parse_toolchain_documents = Runner.parseToolchainDocuments,
    .validate_project_toolchain_schema = Runner.validateProjectToolchainSchema,
    .validate_toolchain_preset_registry = Runner.validateToolchainPresetRegistry,
    .resolve_toolchain_inheritance = Runner.resolveToolchainInheritance,
    .compose_toolchain = Runner.composeToolchain,
    .validate_toolchain_safety = Runner.validateToolchainSafety,
    .take_services = Runner.takeServices,
};
