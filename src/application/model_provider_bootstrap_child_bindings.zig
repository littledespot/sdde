const bootstrap_error = @import("../domain/bootstrap_error.zig");
const model_requirement = @import("../domain/model_provider_requirement.zig");
const services = @import("model_provider_bootstrap_services.zig");

pub const StepOutcome = union(enum) {
    ok,
    failed: bootstrap_error.PublicError,
    cancelled,
};

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        derive_requirement: *const fn (*anyopaque) StepOutcome,
        requirement: *const fn (*const anyopaque) model_requirement.Requirement,
        load_provider_config: *const fn (*anyopaque) StepOutcome,
        decode_provider_config: *const fn (*anyopaque) StepOutcome,
        build_registry: *const fn (*anyopaque) StepOutcome,
        validate_registry: *const fn (*anyopaque) StepOutcome,
        validate_allowlist: *const fn (*anyopaque) StepOutcome,
        take_services: *const fn (*anyopaque) services.ModelProviderBootstrapServices,
    };

    pub fn invokeDeriveRequirement(self: ChildBindings) StepOutcome {
        return self.vtable.derive_requirement(self.context);
    }

    pub fn requirement(self: ChildBindings) model_requirement.Requirement {
        return self.vtable.requirement(self.context);
    }

    pub fn invokeLoadProviderConfig(self: ChildBindings) StepOutcome {
        return self.vtable.load_provider_config(self.context);
    }

    pub fn invokeDecodeProviderConfig(self: ChildBindings) StepOutcome {
        return self.vtable.decode_provider_config(self.context);
    }

    pub fn invokeBuildRegistry(self: ChildBindings) StepOutcome {
        return self.vtable.build_registry(self.context);
    }

    pub fn invokeValidateRegistry(self: ChildBindings) StepOutcome {
        return self.vtable.validate_registry(self.context);
    }

    pub fn invokeValidateAllowlist(self: ChildBindings) StepOutcome {
        return self.vtable.validate_allowlist(self.context);
    }

    pub fn takeServices(self: ChildBindings) services.ModelProviderBootstrapServices {
        return self.vtable.take_services(self.context);
    }
};
