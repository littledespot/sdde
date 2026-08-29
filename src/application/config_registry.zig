const config = @import("../domain/config.zig");

pub const Registry = struct {
    config: config.Owned,

    pub fn init(owned_config: config.Owned) Registry {
        return .{ .config = owned_config };
    }

    pub fn query(self: *const Registry) *const config.SDDToolKitConfig {
        return self.config.value();
    }

    pub fn deinit(self: *Registry) void {
        self.config.deinit();
        self.* = undefined;
    }
};
