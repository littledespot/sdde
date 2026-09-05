pub const Error = error{IdentityUnavailable};

/// Supplies exactly one fresh namespace; no paths, stores or model capability.
pub const Source = struct {
    context: *anyopaque,
    next_fn: *const fn (*anyopaque) Error![16]u8,

    pub fn next(self: Source) Error![16]u8 {
        return self.next_fn(self.context);
    }
};
