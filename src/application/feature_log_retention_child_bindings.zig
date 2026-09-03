const log_stream = @import("../domain/feature_log_stream.zig");

pub const StepOutcome = union(enum) { ok, failed: log_stream.FailureCode };

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        resolve_stream: *const fn (*anyopaque) StepOutcome,
        acquire: *const fn (*anyopaque) StepOutcome,
        prune: *const fn (*anyopaque) StepOutcome,
        release: *const fn (*anyopaque) StepOutcome,
    };

    pub fn invokeResolveStream(self: ChildBindings) StepOutcome {
        return self.vtable.resolve_stream(self.context);
    }
    pub fn invokeAcquire(self: ChildBindings) StepOutcome {
        return self.vtable.acquire(self.context);
    }
    pub fn invokePrune(self: ChildBindings) StepOutcome {
        return self.vtable.prune(self.context);
    }
    pub fn invokeRelease(self: ChildBindings) StepOutcome {
        return self.vtable.release(self.context);
    }
};
