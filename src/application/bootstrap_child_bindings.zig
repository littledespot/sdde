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
        validate_root_paths: *const fn (*anyopaque) StepOutcome,
        resolve_roots: *const fn (*anyopaque) StepOutcome,
        validate_roots: *const fn (*anyopaque) StepOutcome,
        build_registry_id: *const fn (*anyopaque) StepOutcome,
        build_registry: *const fn (*anyopaque) StepOutcome,
        validate_registry: *const fn (*anyopaque) StepOutcome,
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

    pub fn takeServices(self: ChildBindings) bootstrap_services.BootstrapServices {
        return self.vtable.take_services(self.context);
    }
};
