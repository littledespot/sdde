pub const PublicError = enum {
    ENGINE_CONFIG_READ_ERROR,
    ENGINE_CONFIG_PARSE_ERROR,

    pub fn text(self: PublicError) []const u8 {
        return @tagName(self);
    }
};
