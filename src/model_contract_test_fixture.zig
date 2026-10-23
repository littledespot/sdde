const capabilities_module = @import("domain/model_capabilities.zig");

// Compiler-supplied test facts only. Never installed by production composition.
pub const capabilities: capabilities_module.Capabilities = .{
    .inference = true,
    .structured_response = .prompt_only,
    .temperature = true,
};

/// Catalogue model IDs a Bedrock family contract accepts without interpreting
/// them: a plain ID, a versioned inference profile and an ARN that needs path
/// escaping (ADR 0029). None names a real model.
pub const bedrock_model_ids = [_][]const u8{ "MOCK-model", "MOCK.vendor.model-v1:0", "arn:aws:bedrock:MOCK:application-inference-profile/MOCK" };
