const contracts = @import("../domain/llm_provider_contracts.zig");

pub const bedrock_implementation: contracts.RegisteredProviderImplementationId = .{ .ordinal = 1 };

// Support, not defaults. Every model and region must still be selected by the
// external catalogue and authorized by the repository slot allowlist.
pub const registry: contracts.Registry = .{ .entries = &.{
    .{
        .provider = .{ .bytes = "aws-bedrock" },
        .model = .{ .bytes = "openai.gpt-oss-20b-1:0" },
        .implementation_id = bedrock_implementation,
        .config_schema = .aws_bedrock,
        .bedrock_regions = &.{.@"ap-southeast-2"},
        .capabilities = .{ .input_token_count = false, .inference = true, .exact_token_counter = .unavailable, .structured_response = .bedrock_json_schema, .temperature = true },
    },
    .{
        .provider = .{ .bytes = "aws-bedrock" },
        .model = .{ .bytes = "anthropic.claude-3-5-haiku-20241022-v1:0" },
        .implementation_id = bedrock_implementation,
        .config_schema = .aws_bedrock,
        .bedrock_regions = &.{.@"us-west-2"},
        .capabilities = .{ .input_token_count = true, .inference = true, .exact_token_counter = .provider_input_token_count, .structured_response = .prompt_only, .temperature = true },
    },
} };
