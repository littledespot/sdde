pub const PublicError = enum {
    ENGINE_CONFIG_READ_ERROR,
    ENGINE_CONFIG_PARSE_ERROR,
    BOOTSTRAP_ROOT_RESOLUTION_ERROR,
    BOOTSTRAP_ROOT_REGISTRY_INVALID,

    pub fn text(self: PublicError) []const u8 {
        return @tagName(self);
    }
};
