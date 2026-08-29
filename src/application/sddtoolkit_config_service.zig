const config_contract = @import("../domain/config.zig");

pub const SDDToolKitConfigService = struct {
    owned_config: config_contract.Owned,

    pub fn init(owned_config: config_contract.Owned) SDDToolKitConfigService {
        return .{ .owned_config = owned_config };
    }

    pub fn config(self: *const SDDToolKitConfigService) *const config_contract.SDDToolKitConfig {
        return self.owned_config.value();
    }

    pub fn deinit(self: *SDDToolKitConfigService) void {
        self.owned_config.deinit();
        self.* = undefined;
    }
};
