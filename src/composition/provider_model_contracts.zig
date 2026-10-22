const contracts = @import("../domain/llm_provider_contracts.zig");

pub const bedrock_implementation: contracts.RegisteredProviderImplementationId = .{ .ordinal = 1 };
pub const anthropic_implementation: contracts.RegisteredProviderImplementationId = .{ .ordinal = 2 };

// Claude models (ADR 0028, ADR 0029): adaptive thinking stays on, effort is the only
// reasoning control, temperature is never sent and no exact counter exists, whether
// through the Messages API or Bedrock Converse. Each Messages API model still needs
// its own approved compatibility probe before live use.
const anthropic_efforts: []const []const u8 = &.{ "low", "medium", "high", "xhigh", "max" };
const anthropic_capabilities: @import("../domain/model_capabilities.zig").Capabilities = .{ .input_token_count = false, .inference = true, .exact_token_counter = .unavailable, .structured_response = .native_json_schema, .temperature = false };

/// Bedrock family capabilities: Converse inference in either response mode, the
/// catalogue's `json` flag choosing one, and no CountTokens (ADR 0029).
fn bedrockCapabilities(temperature: bool) @import("../domain/model_capabilities.zig").Capabilities {
    return .{ .input_token_count = false, .inference = true, .exact_token_counter = .unavailable, .structured_response = .native_json_schema, .temperature = temperature };
}

// Support, not defaults. A Bedrock family contract covers every catalogue model
// that names its family; each model, Region and family must still be selected by
// the external catalogue and authorized by the repository slot allowlist.
pub const registry: contracts.Registry = .{
    .entries = &.{
        .{
            .provider = .{ .bytes = "aws-bedrock" },
            .model = null,
            .implementation_id = bedrock_implementation,
            // Plain Converse: no reasoning field and the provider's default temperature.
            .facts = .{ .aws_bedrock = .converse },
            .capabilities = bedrockCapabilities(false),
        },
        .{
            .provider = .{ .bytes = "aws-bedrock" },
            .model = null,
            .implementation_id = bedrock_implementation,
            .facts = .{ .aws_bedrock = .@"gpt-oss" },
            .supported_reasoning_efforts = &.{ "low", "medium", "high" },
            .capabilities = bedrockCapabilities(true),
        },
        .{
            .provider = .{ .bytes = "aws-bedrock" },
            .model = null,
            .implementation_id = bedrock_implementation,
            // AWS documents default medium but not its Converse override mapping.
            // Admit omission only until that exact wire contract is established.
            .facts = .{ .aws_bedrock = .luna },
            .capabilities = bedrockCapabilities(false),
        },
        .{
            .provider = .{ .bytes = "aws-bedrock" },
            .model = null,
            .implementation_id = bedrock_implementation,
            .facts = .{ .aws_bedrock = .claude },
            .supported_reasoning_efforts = anthropic_efforts,
            .capabilities = bedrockCapabilities(false),
        },
        .{
            .provider = .{ .bytes = "anthropic" },
            .model = .{ .bytes = "claude-haiku-5-5" },
            .implementation_id = anthropic_implementation,
            .facts = .anthropic,
            .supported_reasoning_efforts = anthropic_efforts,
            .capabilities = anthropic_capabilities,
        },
        .{
            .provider = .{ .bytes = "anthropic" },
            .model = .{ .bytes = "claude-opus-5-5" },
            .implementation_id = anthropic_implementation,
            .facts = .anthropic,
            .supported_reasoning_efforts = anthropic_efforts,
            .capabilities = anthropic_capabilities,
        },
        .{
            .provider = .{ .bytes = "anthropic" },
            .model = .{ .bytes = "claude-sonnet-5-5" },
            .implementation_id = anthropic_implementation,
            .facts = .anthropic,
            .supported_reasoning_efforts = anthropic_efforts,
            .capabilities = anthropic_capabilities,
        },
    },
};
