const safety = @import("../domain/toolchain_safety.zig");
pub const ToolChainService = struct {
    value: *const safety.ValidToolchain,
    pub fn init(value: *const safety.ValidToolchain) ToolChainService {
        return .{ .value = value };
    }
    pub fn toolchain(self: *const ToolChainService) *const safety.ValidToolchain {
        return self.value;
    }
};
