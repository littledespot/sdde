const log_stream = @import("../domain/feature_log_stream.zig");

pub const StepOutcome = union(enum) { ok, failed: log_stream.FailureCode };
pub const SinkOutcome = @import("feature_log_child_bindings.zig").SinkOutcome;

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        authorize: *const fn (*anyopaque) StepOutcome,
        resolve_stream: *const fn (*anyopaque) StepOutcome,
        acquire: *const fn (*anyopaque) SinkOutcome,
        prune: *const fn (*anyopaque) SinkOutcome,
        release: *const fn (*anyopaque) StepOutcome,
    };

    pub fn invokeAuthorize(self: ChildBindings) StepOutcome {
        return self.vtable.authorize(self.context);
    }
    pub fn invokeResolveStream(self: ChildBindings) StepOutcome {
        return self.vtable.resolve_stream(self.context);
    }
    pub fn invokeAcquire(self: ChildBindings) SinkOutcome {
        return self.vtable.acquire(self.context);
    }
    pub fn invokePrune(self: ChildBindings) SinkOutcome {
        return self.vtable.prune(self.context);
    }
    pub fn invokeRelease(self: ChildBindings) StepOutcome {
        return self.vtable.release(self.context);
    }
};
