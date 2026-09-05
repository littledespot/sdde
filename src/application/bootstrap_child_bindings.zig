const bootstrap_error = @import("../domain/bootstrap_error.zig");
const bootstrap_services = @import("bootstrap_services.zig");

pub const StepOutcome = union(enum) {
    ok,
    failed: bootstrap_error.PublicError,
    cancelled,
};

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        locate: *const fn (*anyopaque) StepOutcome,
        read: *const fn (*anyopaque) StepOutcome,
        decode: *const fn (*anyopaque) StepOutcome,
        canonicalize_log_level: *const fn (*anyopaque) StepOutcome,
        validate_logging_policy: *const fn (*anyopaque) StepOutcome,
        validate_root_paths: *const fn (*anyopaque) StepOutcome,
        validate_provider_path: *const fn (*anyopaque) StepOutcome,
        resolve_roots: *const fn (*anyopaque) StepOutcome,
        resolve_provider_path: *const fn (*anyopaque) StepOutcome,
        validate_roots: *const fn (*anyopaque) StepOutcome,
        build_registry_id: *const fn (*anyopaque) StepOutcome,
        build_registry: *const fn (*anyopaque) StepOutcome,
        validate_registry: *const fn (*anyopaque) StepOutcome,
        build_workflow_layout: *const fn (*anyopaque) StepOutcome,
        enumerate_workflow_resources: *const fn (*anyopaque) StepOutcome,
        normalize_workflow_entries: *const fn (*anyopaque) StepOutcome,
        build_workflow_accounts: *const fn (*anyopaque) StepOutcome,
        build_workflow_inventory: *const fn (*anyopaque) StepOutcome,
        validate_workflow_inventory: *const fn (*anyopaque) StepOutcome,
        capture_workflows: *const fn (*anyopaque) StepOutcome,
        parse_workflows: *const fn (*anyopaque) StepOutcome,
        validate_workflow_schema: *const fn (*anyopaque) StepOutcome,
        resolve_workflow_resources: *const fn (*anyopaque) StepOutcome,
        capture_workflow_resources: *const fn (*anyopaque) StepOutcome,
        validate_workflow_operations: *const fn (*anyopaque) StepOutcome,
        compile_workflows: *const fn (*anyopaque) StepOutcome,
        validate_workflow_graphs: *const fn (*anyopaque) StepOutcome,
        build_workflow_registry: *const fn (*anyopaque) StepOutcome,
        validate_workflow_registry: *const fn (*anyopaque) StepOutcome,
        take_services: *const fn (*anyopaque) bootstrap_services.BootstrapServices,
    };

    pub fn invokeLocate(self: ChildBindings) StepOutcome {
        return self.vtable.locate(self.context);
    }

    pub fn invokeRead(self: ChildBindings) StepOutcome {
        return self.vtable.read(self.context);
    }

    pub fn invokeDecode(self: ChildBindings) StepOutcome {
        return self.vtable.decode(self.context);
    }

    pub fn invokeCanonicalizeLogLevel(self: ChildBindings) StepOutcome {
        return self.vtable.canonicalize_log_level(self.context);
    }

    pub fn invokeValidateLoggingPolicy(self: ChildBindings) StepOutcome {
        return self.vtable.validate_logging_policy(self.context);
    }

    pub fn invokeValidateRootPaths(self: ChildBindings) StepOutcome {
        return self.vtable.validate_root_paths(self.context);
    }

    pub fn invokeResolveRoots(self: ChildBindings) StepOutcome {
        return self.vtable.resolve_roots(self.context);
    }
    pub fn invokeValidateProviderPath(self: ChildBindings) StepOutcome {
        return self.vtable.validate_provider_path(self.context);
    }
    pub fn invokeResolveProviderPath(self: ChildBindings) StepOutcome {
        return self.vtable.resolve_provider_path(self.context);
    }

    pub fn invokeValidateRoots(self: ChildBindings) StepOutcome {
        return self.vtable.validate_roots(self.context);
    }

    pub fn invokeBuildRegistryId(self: ChildBindings) StepOutcome {
        return self.vtable.build_registry_id(self.context);
    }

    pub fn invokeBuildRegistry(self: ChildBindings) StepOutcome {
        return self.vtable.build_registry(self.context);
    }

    pub fn invokeValidateRegistry(self: ChildBindings) StepOutcome {
        return self.vtable.validate_registry(self.context);
    }

    pub fn invokeBuildWorkflowLayout(self: ChildBindings) StepOutcome {
        return self.vtable.build_workflow_layout(self.context);
    }
    pub fn invokeEnumerateWorkflowResources(self: ChildBindings) StepOutcome {
        return self.vtable.enumerate_workflow_resources(self.context);
    }
    pub fn invokeNormalizeWorkflowEntries(self: ChildBindings) StepOutcome {
        return self.vtable.normalize_workflow_entries(self.context);
    }
    pub fn invokeBuildWorkflowAccounts(self: ChildBindings) StepOutcome {
        return self.vtable.build_workflow_accounts(self.context);
    }
    pub fn invokeBuildWorkflowInventory(self: ChildBindings) StepOutcome {
        return self.vtable.build_workflow_inventory(self.context);
    }
    pub fn invokeValidateWorkflowInventory(self: ChildBindings) StepOutcome {
        return self.vtable.validate_workflow_inventory(self.context);
    }
    pub fn invokeCaptureWorkflows(self: ChildBindings) StepOutcome {
        return self.vtable.capture_workflows(self.context);
    }
    pub fn invokeParseWorkflows(self: ChildBindings) StepOutcome {
        return self.vtable.parse_workflows(self.context);
    }
    pub fn invokeValidateWorkflowSchema(self: ChildBindings) StepOutcome {
        return self.vtable.validate_workflow_schema(self.context);
    }
    pub fn invokeResolveWorkflowResources(self: ChildBindings) StepOutcome {
        return self.vtable.resolve_workflow_resources(self.context);
    }
    pub fn invokeCaptureWorkflowResources(self: ChildBindings) StepOutcome {
        return self.vtable.capture_workflow_resources(self.context);
    }
    pub fn invokeValidateWorkflowOperations(self: ChildBindings) StepOutcome {
        return self.vtable.validate_workflow_operations(self.context);
    }
    pub fn invokeCompileWorkflows(self: ChildBindings) StepOutcome {
        return self.vtable.compile_workflows(self.context);
    }
    pub fn invokeValidateWorkflowGraphs(self: ChildBindings) StepOutcome {
        return self.vtable.validate_workflow_graphs(self.context);
    }
    pub fn invokeBuildWorkflowRegistry(self: ChildBindings) StepOutcome {
        return self.vtable.build_workflow_registry(self.context);
    }
    pub fn invokeValidateWorkflowRegistry(self: ChildBindings) StepOutcome {
        return self.vtable.validate_workflow_registry(self.context);
    }

    pub fn takeServices(self: ChildBindings) bootstrap_services.BootstrapServices {
        return self.vtable.take_services(self.context);
    }
};
