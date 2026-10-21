//! Shared validation of the frozen diagnostic cohort's production requests.
const std = @import("std");
const transport = @import("../../src/adapters/provider/model_http_transport.zig");
const Description = @import("../../src/domain/model_request_description.zig").Description;

fn protocol(a: std.mem.Allocator) !@import("generation_comparison.zig").Protocol {
    return @import("generation_comparison.zig").parseProtocol(a, @embedFile("../calibration/semantic-simplicity/protocol.json"));
}

fn validateGeneration(frozen: @import("generation_comparison.zig").Protocol, models: *const @import("../../src/domain/config.zig").ModelsConfig) !void {
    const selected = models.slots.map.get(frozen.generation_slot) orelse return error.FrozenBindingRejected;
    if (!std.mem.eql(u8, selected.provider, frozen.provider) or !std.mem.eql(u8, selected.model, frozen.model) or
        selected.reasoningEffort == null or !std.mem.eql(u8, selected.reasoningEffort.?, @tagName(frozen.reasoning_effort))) return error.FrozenBindingRejected;
}

pub fn validateModels(a: std.mem.Allocator, models: *const @import("../../src/domain/config.zig").ModelsConfig) !void {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    try validateGeneration(try protocol(arena.allocator()), models);
}

/// The frozen protocol's maximum output: the only value a frozen-registration
/// request sends (ADR 0011). The shipped catalogue must record the same value.
pub fn maximumOutput(a: std.mem.Allocator) !@import("../../src/domain/llm_provider_contracts.zig").ModelMaximumOutput {
    return (try protocol(a)).max_output_tokens;
}

/// The frozen cohort is one Bedrock binding; no other family's target qualifies.
fn bedrockTarget(wire: transport.Request) error{FrozenBindingRejected}!@FieldType(transport.Target, "aws_bedrock") {
    return switch (wire.target) {
        .aws_bedrock => |target| target,
        .anthropic => error.FrozenBindingRejected,
    };
}

pub fn validateWire(a: std.mem.Allocator, wire: transport.Request) !void {
    const target = try bedrockTarget(wire);
    try @import("model_cost_policy.zig").require(.generation, .{ .bytes = "aws-bedrock" }, target.model);
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const frozen = try protocol(arena.allocator());
    if (target.kind != .inference or !std.mem.eql(u8, @tagName(target.region), frozen.region) or
        !std.mem.eql(u8, target.model.bytes, frozen.model)) return error.FrozenBindingRejected;
    // The frozen maximum output is a bound setting: a drifted catalogue cannot send another.
    const body = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), wire.body, .{}) catch |err|
        return if (err == error.OutOfMemory) error.OutOfMemory else error.FrozenBindingRejected;
    const config = if (body == .object) body.object.get("inferenceConfig") else null;
    const sent = if (config != null and config.? == .object) config.?.object.get("maxTokens") else null;
    if (sent == null or sent.? != .integer or sent.?.integer != frozen.max_output_tokens.tokens) return error.FrozenBindingRejected;
}

pub fn validateDescription(a: std.mem.Allocator, description: Description, wire: transport.Request, expected_models: *const @import("../../src/domain/config.zig").ModelsConfig) !void {
    try validateWire(a, wire);
    const target = try bedrockTarget(wire);
    @import("diagnostic_binding.zig").validateBinding(description) catch return error.FrozenBindingRejected;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const frozen = try protocol(arena.allocator());
    try validateGeneration(frozen, expected_models);
    const slot = @import("../../src/domain/llm_provider_identity.zig").ModelSlotId.parse(description.model_slot) orelse return error.FrozenBindingRejected;
    const expected = expected_models.slots.map.get(slot.bytes) orelse return error.FrozenBindingRejected;
    const temperature = if (description.controls.temperature) |value| value.wireValue() else null;
    if (!std.mem.eql(u8, @tagName(description.response_mode), @tagName(frozen.response_mode)) or
        !@import("../../src/domain/request_debugger.zig").sameOptional(description.reasoning_effort, expected.reasoningEffort) or
        !std.mem.eql(u8, description.provider, expected.provider) or !std.mem.eql(u8, description.model, expected.model) or
        !std.meta.eql(temperature, @as(?f64, frozen.temperature)) or
        !std.meta.eql(description.provider_config, @import("../../src/domain/llm_provider_contracts.zig").ValidatedProviderConfig{ .aws_bedrock = .{ .region = target.region, .family = frozen.family, .max_output_tokens = frozen.max_output_tokens } }) or
        !std.mem.eql(u8, description.model, target.model.bytes)) return error.FrozenBindingRejected;
    if (std.mem.eql(u8, description.model_slot, frozen.generation_slot) and
        (description.reasoning_effort == null or !std.mem.eql(u8, description.reasoning_effort.?, @tagName(frozen.reasoning_effort)))) return error.FrozenBindingRejected;
}

test "frozen slot controls retain each role's effort without substituting generation settings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try protocol(a);
    var models: @import("../../src/domain/config.zig").ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(a);
    try models.slots.map.put(a, frozen.generation_slot, .{ .provider = frozen.provider, .model = frozen.model, .reasoningEffort = "low" });
    for ([_]struct { slot: []const u8, effort: ?[]const u8 }{
        .{ .slot = "bounded_analysis", .effort = "low" },
        .{ .slot = "source_inspection", .effort = null },
    }) |example| {
        try models.slots.map.put(a, example.slot, .{ .provider = frozen.provider, .model = frozen.model, .reasoningEffort = example.effort });
        const description: Description = .{
            .provider = frozen.provider,
            .model = frozen.model,
            .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .family = frozen.family, .max_output_tokens = frozen.max_output_tokens } },
            .model_slot = example.slot,
            .workflow_id = "current-native-workflow",
            .workflow_version = 1,
            .request_step = "native-request",
            .content = &.{.{ .user = "Use the assigned source evidence." }},
            .protocol_prompt = @import("../../src/domain/model_controls.zig").response_format_guidance,
            .schema = "{}",
            .response_mode = .native_schema,
            .controls = .{ .temperature = .fixed },
            .reasoning_effort = example.effort,
            .operation_kind = .inference,
        };
        const wire: transport.Request = .{ .target = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2", .model = .{ .bytes = frozen.model }, .kind = .inference } }, .body = "{\"inferenceConfig\":{\"temperature\":0.1,\"maxTokens\":16384}}", .api_key = "", .deadline_monotonic_ms = 1 };
        try validateDescription(a, description, wire, &models);
        var changed = description;
        changed.reasoning_effort = "medium";
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        changed = description;
        changed.model_slot = "unconfigured_slot";
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        changed = description;
        changed.controls.temperature = null;
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        // A drifted maximum, recorded or sent, is rejected before transport.
        changed = description;
        changed.provider_config.aws_bedrock.max_output_tokens = .{ .tokens = 4096 };
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        for ([_][]const u8{ "{\"inferenceConfig\":{\"temperature\":0.1,\"maxTokens\":4096}}", "{\"inferenceConfig\":{\"temperature\":0.1}}", "{}" }) |body| {
            var drifted = wire;
            drifted.body = body;
            try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, description, drifted, &models));
        }
        if (example.effort == null) {
            // A role cannot be relabelled as generation without its frozen effort.
            changed = description;
            changed.model_slot = frozen.generation_slot;
            try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        }
        // Another role cannot hide absent/drifting generation policy.
        const selected_generation = models.slots.map.getPtr(frozen.generation_slot).?;
        selected_generation.reasoningEffort = "medium";
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, description, wire, &models));
        selected_generation.reasoningEffort = "low";
    }
    models.slots.map.getPtr(frozen.generation_slot).?.reasoningEffort = null;
    try std.testing.expectError(error.FrozenBindingRejected, validateModels(a, &models));
    try std.testing.expect(models.slots.map.swapRemove(frozen.generation_slot));
    try std.testing.expectError(error.FrozenBindingRejected, validateModels(a, &models));
}
