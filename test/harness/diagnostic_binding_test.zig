const std = @import("std");
const binding = @import("diagnostic_binding.zig");
const debug = @import("../../src/domain/request_debugger.zig");

const catalogue =
    \\{"providers":[{"provider":"aws-bedrock","models":[{"model":"openai.gpt-oss-20b-1:0","json":true,"config":{"region":"ap-southeast-2"}},{"model":"anthropic.claude-3-5-haiku-20241022-v1:0","json":false,"config":{"region":"us-west-2"}}]}]}
;
const prompt_catalogue =
    \\{"providers":[{"provider":"aws-bedrock","models":[{"model":"openai.gpt-oss-20b-1:0","json":false,"config":{"region":"ap-southeast-2"}},{"model":"anthropic.claude-3-5-haiku-20241022-v1:0","json":false,"config":{"region":"us-west-2"}}]}]}
;
const captured: debug.Description = .{
    .provider = "aws-bedrock",
    .model = "openai.gpt-oss-20b-1:0",
    .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
    .model_slot = "MOCK-generation",
    .workflow_id = "MOCK-workflow",
    .workflow_version = 1,
    .request_step = "MOCK-prepare",
    .content = &.{.{ .user = "MOCK captured input" }},
    .protocol_prompt = @import("../../src/domain/model_controls.zig").response_format_guidance,
    .schema = "MOCK captured schema",
    .response_mode = .native_schema,
    .controls = .{ .temperature = .fixed },
    .reasoning_effort = "medium",
    .operation_kind = .inference,
};

test "diagnostic binding validates requested low high and omitted effort without mutating captured data" {
    for ([_]?[]const u8{ "low", "high", null }) |effort| {
        const selected = try binding.rebind(std.testing.allocator, captured, catalogue, captured.model, effort);
        try std.testing.expect(debug.sameOptional(effort, selected.reasoning_effort));
        var expected = captured;
        expected.reasoning_effort = effort;
        try std.testing.expectEqualDeep(expected, selected);
        try std.testing.expectEqualStrings("medium", captured.reasoning_effort.?);
    }
}

test "diagnostic model change derives target deployment config and preserves omission and content" {
    var original = captured;
    original.response_mode = .prompt_only;
    const selected = try binding.rebind(std.testing.allocator, original, prompt_catalogue, "anthropic.claude-3-5-haiku-20241022-v1:0", null);
    try std.testing.expectEqualStrings("anthropic.claude-3-5-haiku-20241022-v1:0", selected.model);
    try std.testing.expectEqual(.@"us-west-2", selected.provider_config.aws_bedrock.region);
    try std.testing.expectEqualDeep(original.controls, selected.controls);
    try std.testing.expectEqualDeep(original.content, selected.content);
    try std.testing.expectEqualStrings(original.schema, selected.schema);
    try std.testing.expectEqual(original.response_mode, selected.response_mode);
    try std.testing.expectEqualDeep(captured.provider_config, original.provider_config);
    try std.testing.expectEqualStrings(captured.model, original.model);
}

test "diagnostic binding rejects unknown model effort and incompatible provider mode controls" {
    for ([_][]const u8{ "unknown-model", "" }) |model| {
        try std.testing.expectError(error.InvalidEvaluationContract, binding.rebind(std.testing.allocator, captured, catalogue, model, "low"));
    }
    for ([_][]const u8{ "xhigh", "" }) |effort| {
        try std.testing.expectError(error.InvalidEvaluationContract, binding.rebind(std.testing.allocator, captured, catalogue, captured.model, effort));
    }
    for (0..4) |mode| {
        var rejected = captured;
        switch (mode) {
            0 => rejected.provider = "unknown-provider",
            1 => rejected.provider_config = .empty_object,
            2 => rejected.controls.temperature = null,
            3 => rejected.model_slot = "",
            else => unreachable,
        }
        try std.testing.expectError(error.InvalidEvaluationContract, binding.rebind(std.testing.allocator, rejected, catalogue, captured.model, "low"));
    }
    // A currently declared different response mode cannot silently rewrite a
    // historical request, even when the target supports both modes.
    try std.testing.expectError(error.InvalidEvaluationContract, binding.rebind(std.testing.allocator, captured, prompt_catalogue, captured.model, "low"));
    try std.testing.expectError(error.InvalidEvaluationContract, binding.rebind(std.testing.allocator, captured, catalogue, "anthropic.claude-3-5-haiku-20241022-v1:0", null));
}

test "diagnostic binding rejects the entire malformed duplicate or unsupported catalogue" {
    const rejected = [_][]const u8{
        \\{"providers":[],"extra":true}
        ,
        \\{"providers":[],"providers":[]}
        ,
        \\{"providers":[{"provider":"aws-bedrock","models":[{"model":"openai.gpt-oss-20b-1:0","json":true,"config":{"region":"ap-southeast-2"}},{"model":"unknown-model","json":false,"config":{"region":"us-west-2"}}]}]}
        ,
        \\{"providers":[{"provider":"aws-bedrock","models":[{"model":"openai.gpt-oss-20b-1:0","json":true,"config":{"region":"us-west-2"}}]}]}
        ,
        \\{"providers":[{"provider":"aws-bedrock","models":[{"model":"openai.gpt-oss-20b-1:0","json":true,"config":{"region":"ap-southeast-2"}},{"model":"openai.gpt-oss-20b-1:0","json":true,"config":{"region":"ap-southeast-2"}}]}]}
        ,
        "not-json",
    };
    for (rejected) |bytes| {
        try std.testing.expectError(error.InvalidEvaluationContract, binding.rebind(std.testing.allocator, captured, bytes, captured.model, "low"));
    }
}

test "diagnostic authorization accepts content edits and rejects binding drift before dispatch" {
    var authority: binding.Authorization = .{ .binding = captured };
    const context: *@import("../../src/ports/request_replay.zig").Context = @ptrCast(&authority);
    try std.testing.expectEqual(.openai_oss, try binding.Authorization.authorize(context, captured));
    var edited = captured;
    edited.content = &.{.{ .user = "MOCK changed prompt" }};
    edited.schema = "MOCK changed schema";
    try std.testing.expectEqual(.openai_oss, try binding.Authorization.authorize(context, edited));
    for (0..7) |mode| {
        var rejected = captured;
        switch (mode) {
            0 => rejected.provider = "unknown-provider",
            1 => rejected.model = "anthropic.claude-3-5-haiku-20241022-v1:0",
            2 => rejected.provider_config = .{ .aws_bedrock = .{ .region = .@"us-west-2" } },
            3 => rejected.reasoning_effort = "high",
            4 => rejected.controls.temperature = null,
            5 => rejected.response_mode = .prompt_only,
            6 => rejected.operation_kind = .input_token_count,
            else => unreachable,
        }
        try std.testing.expectError(error.ReplayUnauthorized, binding.Authorization.authorize(context, rejected));
    }
}

test "diagnostic authorization derives request profile from each validated registered tuple" {
    const registered = @import("../../src/composition/provider_model_contracts.zig");
    for (registered.registry.entries) |entry| {
        var selected = captured;
        selected.provider = entry.provider.bytes;
        selected.model = entry.model.bytes;
        selected.provider_config = .{ .aws_bedrock = .{ .region = entry.bedrock_regions[0] } };
        selected.controls = entry.capabilities.inferenceControls();
        selected.response_mode = if (entry.capabilities.structured_response == .bedrock_json_schema) .native_schema else .prompt_only;
        selected.reasoning_effort = if (entry.supported_reasoning_efforts.len == 0) null else entry.supported_reasoning_efforts[0];
        var authority: binding.Authorization = .{ .binding = selected };
        const context: *@import("../../src/ports/request_replay.zig").Context = @ptrCast(&authority);
        try std.testing.expectEqual(entry.bedrock_request_profile, try binding.Authorization.authorize(context, selected));
        authority.binding.model = "unregistered-model";
        try std.testing.expectError(error.ReplayUnauthorized, binding.Authorization.authorize(context, authority.binding));
    }
}
