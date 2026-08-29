const config_error = @import("../domain/config_error.zig");
const sddtoolkit_config_service = @import("sddtoolkit_config_service.zig");

pub const StepOutcome = union(enum) {
    ok,
    failed: config_error.PublicError,
};

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        locate: *const fn (*anyopaque) StepOutcome,
        read: *const fn (*anyopaque) StepOutcome,
        decode: *const fn (*anyopaque) StepOutcome,
        take_config_service: *const fn (*anyopaque) sddtoolkit_config_service.SDDToolKitConfigService,
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

    pub fn takeConfigService(self: ChildBindings) sddtoolkit_config_service.SDDToolKitConfigService {
        return self.vtable.take_config_service(self.context);
    }
};
