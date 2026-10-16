//! Shared validation of the frozen diagnostic cohort's production requests.
const std = @import("std");
const transport = @import("../../src/adapters/provider/bedrock_transport.zig");
const Description = @import("../../src/domain/model_request_description.zig").Description;

fn protocol(a: std.mem.Allocator) !@import("generation_comparison.zig").Protocol {
    return @import("generation_comparison.zig").parseProtocol(a, @embedFile("../calibration/semantic-simplicity/protocol.json"));
}

fn validateGeneration(frozen: @import("generation_comparison.zig").Protocol, models: *const @import("../../src/domain/config.zig").ModelsConfig) !void {
    const selected = models.slots.map.get(frozen.generation_slot) orelse return error.FrozenBindingRejected;
    if (!std.mem.eql(u8, selected.provider, frozen.provider) or !std.mem.eql(u8, selected.model, frozen.model) or
        selected.reasoningEffort == null or !std.mem.eql(u8, selected.reasoningEffort.?, @tagName(frozen.reasoning_effort)) or
        selected.maxOutputTokens == null or selected.maxOutputTokens.? != frozen.max_output_tokens) return error.FrozenBindingRejected;
}

pub fn validateModels(a: std.mem.Allocator, models: *const @import("../../src/domain/config.zig").ModelsConfig) !void {
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    try validateGeneration(try protocol(arena.allocator()), models);
}

pub fn validateWire(a: std.mem.Allocator, wire: transport.Request) !void {
    try @import("model_cost_policy.zig").require(.{ .bytes = "aws-bedrock" }, wire.model);
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const frozen = try protocol(arena.allocator());
    if (wire.kind != .inference or !std.mem.eql(u8, @tagName(wire.region), frozen.region) or
        !std.mem.eql(u8, wire.model.bytes, frozen.model)) return error.FrozenBindingRejected;
}

pub fn validateDescription(a: std.mem.Allocator, description: Description, wire: transport.Request, expected_models: *const @import("../../src/domain/config.zig").ModelsConfig) !void {
    try validateWire(a, wire);
    @import("diagnostic_binding.zig").validateBinding(description) catch return error.FrozenBindingRejected;
    var arena: std.heap.ArenaAllocator = .init(a);
    defer arena.deinit();
    const frozen = try protocol(arena.allocator());
    try validateGeneration(frozen, expected_models);
    const slot = @import("../../src/domain/llm_provider_identity.zig").ModelSlotId.parse(description.model_slot) orelse return error.FrozenBindingRejected;
    const expected = expected_models.slots.map.get(slot.bytes) orelse return error.FrozenBindingRejected;
    const temperature = if (description.controls.temperature) |value| value.wireValue() else null;
    const allowance = if (description.controls.max_output_tokens) |value| value.value else null;
    if (!std.mem.eql(u8, @tagName(description.response_mode), @tagName(frozen.response_mode)) or
        !@import("../../src/domain/request_debugger.zig").sameOptional(description.reasoning_effort, expected.reasoningEffort) or
        allowance != expected.maxOutputTokens or
        !std.mem.eql(u8, description.provider, expected.provider) or !std.mem.eql(u8, description.model, expected.model) or
        !std.meta.eql(temperature, @as(?f64, frozen.temperature)) or
        description.provider_config != .aws_bedrock or description.provider_config.aws_bedrock.region != wire.region or
        !std.mem.eql(u8, description.model, wire.model.bytes)) return error.FrozenBindingRejected;
    if (std.mem.eql(u8, description.model_slot, frozen.generation_slot) and
        (description.reasoning_effort == null or !std.mem.eql(u8, description.reasoning_effort.?, @tagName(frozen.reasoning_effort)) or
            allowance == null or allowance.? != frozen.max_output_tokens)) return error.FrozenBindingRejected;
}

test "frozen slot controls retain omitted and distinct allowances without substituting generation settings" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const frozen = try protocol(a);
    var models: @import("../../src/domain/config.zig").ModelsConfig = .{ .slots = .{} };
    defer models.slots.deinit(a);
    try models.slots.map.put(a, frozen.generation_slot, .{ .provider = frozen.provider, .model = frozen.model, .reasoningEffort = "low", .maxOutputTokens = frozen.max_output_tokens });
    for ([_]struct { slot: []const u8, effort: ?[]const u8, allowance: ?u32 }{
        .{ .slot = "bounded_analysis", .effort = "low", .allowance = 4096 },
        .{ .slot = "field_adjustment", .effort = "low", .allowance = null },
        .{ .slot = "source_inspection", .effort = null, .allowance = 8192 },
    }) |example| {
        try models.slots.map.put(a, example.slot, .{ .provider = frozen.provider, .model = frozen.model, .reasoningEffort = example.effort, .maxOutputTokens = example.allowance });
        const description: Description = .{
            .provider = frozen.provider,
            .model = frozen.model,
            .provider_config = .{ .aws_bedrock = .{ .region = .@"ap-southeast-2" } },
            .model_slot = example.slot,
            .workflow_id = "current-native-workflow",
            .workflow_version = 1,
            .request_step = "native-request",
            .content = &.{.{ .user = "Use the assigned source evidence." }},
            .protocol_prompt = @import("../../src/domain/model_controls.zig").response_format_guidance,
            .schema = "{}",
            .response_mode = .native_schema,
            .controls = .{ .temperature = .fixed, .max_output_tokens = if (example.allowance) |value| .{ .value = value } else null },
            .reasoning_effort = example.effort,
            .operation_kind = .inference,
        };
        const wire: transport.Request = .{ .region = .@"ap-southeast-2", .model = .{ .bytes = frozen.model }, .kind = .inference, .body = "{}", .api_key = "", .deadline_monotonic_ms = 1 };
        try validateDescription(a, description, wire, &models);
        var changed = description;
        changed.controls.max_output_tokens = if (example.allowance == null) .{ .value = 4096 } else null;
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        changed = description;
        changed.reasoning_effort = "medium";
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        changed = description;
        changed.model_slot = "unconfigured_slot";
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        changed = description;
        changed.model_slot = frozen.generation_slot;
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, changed, wire, &models));
        // Another role cannot hide absent/drifting generation policy.
        const selected_generation = models.slots.map.getPtr(frozen.generation_slot).?;
        selected_generation.maxOutputTokens = 4096;
        try std.testing.expectError(error.FrozenBindingRejected, validateDescription(a, description, wire, &models));
        selected_generation.maxOutputTokens = frozen.max_output_tokens;
    }
    try std.testing.expect(models.slots.map.swapRemove(frozen.generation_slot));
    try std.testing.expectError(error.FrozenBindingRejected, validateModels(a, &models));
}
