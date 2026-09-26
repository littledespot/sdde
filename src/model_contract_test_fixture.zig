const capabilities_module = @import("domain/model_capabilities.zig");

// Compiler-supplied test facts only. Never installed by production composition.
pub const capabilities: capabilities_module.Capabilities = .{
    .input_token_count = true,
    .inference = true,
    .exact_token_counter = .provider_input_token_count,
    .structured_response = .prompt_only,
    .temperature = true,
};
