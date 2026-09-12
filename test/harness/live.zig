//! Shared live judge composition for supplied-spec and generated-spec grading.
const std = @import("std");
const c = @import("contracts.zig");
const configuration = @import("configuration.zig");

pub fn run(io: std.Io, allocator: std.mem.Allocator, config: configuration.Config, key: []const u8, inputs: c.Capture, store: ?@import("evidence.zig").Store) !@import("report.zig").Report {
    try configuration.validate(config);
    var clock: @import("../../src/adapters/system/provider_operation_clock.zig").Adapter = .{ .io = io };
    var transport: @import("../../src/adapters/provider/bedrock_http.zig").Adapter = .{ .io = io, .clock = clock.clock(), .runtime = .{} };
    var adapter: union(configuration.Api) {
        openai_responses: @import("http.zig").Adapter,
        bedrock_converse: @import("bedrock.zig").Adapter,
    } = switch (config.api) {
        .openai_responses => .{ .openai_responses = .{ .io = io, .api_key = key } },
        .bedrock_converse => .{ .bedrock_converse = .{ .transport = transport.port(), .clock = clock.clock(), .model = c.ModelId.parse(config.model).?, .region = config.region.?, .api_key = key } },
    };
    const port = switch (adapter) {
        .openai_responses => |*value| value.port(),
        .bedrock_converse => |*value| value.port(),
    };
    if (store) |destination| {
        var trace: @import("evaluation_trace.zig").Trace = .{ .store = destination, .inner = port };
        const result = try @import("evaluate.zig").run(io, allocator, trace.port(), config, inputs);
        if (trace.failure != null) return error.EvidenceCaptureFailed;
        return result;
    }
    return @import("evaluate.zig").run(io, allocator, port, config, inputs);
}
