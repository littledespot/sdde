pub const TotalTokenBudget = struct {
    value: u64,

    pub fn init(value: u64) ?TotalTokenBudget {
        return if (value == 0) null else .{ .value = value };
    }

    pub fn isValid(self: TotalTokenBudget) bool {
        return self.value != 0;
    }
};
