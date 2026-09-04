const feature_log_bindings = @import("feature_log_child_bindings.zig");
const log_stream = @import("../domain/feature_log_stream.zig");

pub const ValidationOutcome = enum { valid, invalid };

pub const Target = struct {
    identity: feature_log_bindings.RuntimeIdentity,
    mode: log_stream.FinalizationMode,
};

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        target: *const fn (*anyopaque) Target,
        validate: *const fn (*anyopaque) ValidationOutcome,
        prepare: *const fn (*anyopaque) log_stream.Outcome,
        close: *const fn (*anyopaque) log_stream.Outcome,
    };

    pub fn target(self: ChildBindings) Target {
        return self.vtable.target(self.context);
    }

    pub fn invokeValidate(self: ChildBindings) ValidationOutcome {
        return self.vtable.validate(self.context);
    }

    pub fn invokePrepare(self: ChildBindings) log_stream.Outcome {
        return self.vtable.prepare(self.context);
    }

    pub fn invokeClose(self: ChildBindings) log_stream.Outcome {
        return self.vtable.close(self.context);
    }
};
