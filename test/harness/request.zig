//! Select one provider wire projection without changing evaluation policy.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");

pub fn encode(a: std.mem.Allocator, config: configuration.Config, capture: c.Capture) c.Error![]const u8 {
    return switch (config.api) {
        .openai_responses => @import("openai.zig").request(a, config, capture),
        .bedrock_converse => @import("bedrock.zig").request(a, config, capture),
    };
}
