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
        resolve_roots: *const fn (*anyopaque) StepOutcome,
        validate_roots: *const fn (*anyopaque) StepOutcome,
        build_registry_id: *const fn (*anyopaque) StepOutcome,
        build_registry: *const fn (*anyopaque) StepOutcome,
        validate_registry: *const fn (*anyopaque) StepOutcome,
        build_workflow_layout: *const fn (*anyopaque) StepOutcome,
        inventory_workflows: *const fn (*anyopaque) StepOutcome,
        capture_workflows: *const fn (*anyopaque) StepOutcome,
        parse_workflows: *const fn (*anyopaque) StepOutcome,
        validate_workflow_schema: *const fn (*anyopaque) StepOutcome,
        compile_workflows: *const fn (*anyopaque) StepOutcome,
        validate_workflow_graphs: *const fn (*anyopaque) StepOutcome,
        build_workflow_registry: *const fn (*anyopaque) StepOutcome,
        validate_workflow_registry: *const fn (*anyopaque) StepOutcome,
        capture_project_toolchain: *const fn (*anyopaque) StepOutcome,
        inventory_toolchain_presets: *const fn (*anyopaque) StepOutcome,
        capture_toolchain_presets: *const fn (*anyopaque) StepOutcome,
        parse_toolchain_documents: *const fn (*anyopaque) StepOutcome,
        validate_project_toolchain_schema: *const fn (*anyopaque) StepOutcome,
        validate_toolchain_preset_registry: *const fn (*anyopaque) StepOutcome,
        resolve_toolchain_inheritance: *const fn (*anyopaque) StepOutcome,
        compose_toolchain: *const fn (*anyopaque) StepOutcome,
        validate_toolchain_safety: *const fn (*anyopaque) StepOutcome,
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
    pub fn invokeInventoryWorkflows(self: ChildBindings) StepOutcome {
        return self.vtable.inventory_workflows(self.context);
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
    pub fn invokeCaptureProjectToolchain(self: ChildBindings) StepOutcome {
        return self.vtable.capture_project_toolchain(self.context);
    }
    pub fn invokeInventoryToolchainPresets(self: ChildBindings) StepOutcome {
        return self.vtable.inventory_toolchain_presets(self.context);
    }
    pub fn invokeCaptureToolchainPresets(self: ChildBindings) StepOutcome {
        return self.vtable.capture_toolchain_presets(self.context);
    }
    pub fn invokeParseToolchainDocuments(self: ChildBindings) StepOutcome {
        return self.vtable.parse_toolchain_documents(self.context);
    }
    pub fn invokeValidateProjectToolchainSchema(self: ChildBindings) StepOutcome {
        return self.vtable.validate_project_toolchain_schema(self.context);
    }
    pub fn invokeValidateToolchainPresetRegistry(self: ChildBindings) StepOutcome {
        return self.vtable.validate_toolchain_preset_registry(self.context);
    }
    pub fn invokeResolveToolchainInheritance(self: ChildBindings) StepOutcome {
        return self.vtable.resolve_toolchain_inheritance(self.context);
    }
    pub fn invokeComposeToolchain(self: ChildBindings) StepOutcome {
        return self.vtable.compose_toolchain(self.context);
    }
    pub fn invokeValidateToolchainSafety(self: ChildBindings) StepOutcome {
        return self.vtable.validate_toolchain_safety(self.context);
    }

    pub fn takeServices(self: ChildBindings) bootstrap_services.BootstrapServices {
        return self.vtable.take_services(self.context);
    }
};
