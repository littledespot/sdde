//! Select one provider wire projection without changing evaluation policy.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");

/// A correction resends the same instruction, documents, schema and model, plus
/// the typed diagnostic and the rejected response. Bedrock carries the guidance
/// in its system blocks and the evidence in the user message; OpenAI sends both
/// as user messages after the documents.
pub fn encode(a: std.mem.Allocator, config: configuration.Config, capture: c.Capture, correction: ?@import("correction.zig").Correction) c.Error![]const u8 {
    return switch (config.api) {
        .openai_responses => @import("openai.zig").request(a, config, capture, correction),
        .bedrock_converse => @import("bedrock.zig").request(a, config, capture, correction),
    };
}
