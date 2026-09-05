pub const Error = error{InvalidSpecifyArguments};
pub const ParsedInvocation = struct {
    reference: ?[]const u8 = null,
    feature: ?[]const u8 = null,
};
pub const Invocation = struct { raw_reference: []const u8, raw_feature: []const u8 };
