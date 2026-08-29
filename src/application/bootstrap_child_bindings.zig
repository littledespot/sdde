const config_error = @import("../domain/config_error.zig");
const config_registry = @import("config_registry.zig");

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
        take_registry: *const fn (*anyopaque) config_registry.Registry,
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

    pub fn takeRegistry(self: ChildBindings) config_registry.Registry {
        return self.vtable.take_registry(self.context);
    }
};
