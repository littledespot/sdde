pub const Outcome = enum { ok, failed };

pub const ChildBindings = struct {
    context: *anyopaque,
    parse_fn: *const fn (*anyopaque) Outcome,
    validate_fn: *const fn (*anyopaque) Outcome,

    pub fn parse(self: ChildBindings) Outcome {
        return self.parse_fn(self.context);
    }
    pub fn validate(self: ChildBindings) Outcome {
        return self.validate_fn(self.context);
    }
};
