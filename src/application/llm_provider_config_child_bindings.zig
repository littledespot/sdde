const service = @import("llm_provider_config_service.zig");

pub const StepOutcome = enum {
    ok,
    failed,
    cancelled,
};

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        locate: *const fn (*anyopaque) StepOutcome,
        read: *const fn (*anyopaque) StepOutcome,
        take_service: *const fn (*anyopaque) service.LLMProviderConfigService,
    };

    pub fn invokeLocate(self: ChildBindings) StepOutcome {
        return self.vtable.locate(self.context);
    }

    pub fn invokeRead(self: ChildBindings) StepOutcome {
        return self.vtable.read(self.context);
    }

    pub fn takeService(self: ChildBindings) service.LLMProviderConfigService {
        return self.vtable.take_service(self.context);
    }
};
