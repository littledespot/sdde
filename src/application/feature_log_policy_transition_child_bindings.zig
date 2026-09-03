const feature_log_result = @import("feature_log_result.zig");
const feature_log_bindings = @import("feature_log_child_bindings.zig");

pub const ValidationOutcome = enum { valid, invalid };

pub const Participants = struct {
    current_identity: feature_log_bindings.RuntimeIdentity,
    next: feature_log_bindings.ChildBindings,
};

pub const ChildBindings = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        participants: *const fn (*anyopaque) Participants,
        validate: *const fn (*anyopaque) ValidationOutcome,
        close_current: *const fn (*anyopaque) feature_log_result.Outcome,
        prepare_next: *const fn (*anyopaque) feature_log_result.Outcome,
    };

    pub fn participants(self: ChildBindings) Participants {
        return self.vtable.participants(self.context);
    }

    pub fn invokeValidate(self: ChildBindings) ValidationOutcome {
        return self.vtable.validate(self.context);
    }

    pub fn invokeCloseCurrent(self: ChildBindings) feature_log_result.Outcome {
        return self.vtable.close_current(self.context);
    }

    pub fn invokePrepareNext(self: ChildBindings) feature_log_result.Outcome {
        return self.vtable.prepare_next(self.context);
    }
};
