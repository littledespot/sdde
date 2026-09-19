const std = @import("std");
const flow = @import("domain/workflow_json_composition.zig");
const compilation = @import("domain/workflow_compilation.zig");
const schemas = @import("adapters/parsers/model_result_schemas.zig");

const result_bytes = "{\"type\":\"object\",\"properties\":{\"title\":{\"type\":\"string\",\"maxLength\":80},\"enabled\":{\"type\":\"boolean\"}},\"required\":[\"title\",\"enabled\"],\"additionalProperties\":false}";
const composition_bytes = "{\"schema\":\"json-composition/v1\",\"result\":\"result\",\"parts\":{\"text\":{\"paths\":[\"/title\"]},\"flags\":{\"paths\":[\"/enabled\"],\"requires\":[\"text\"]}}}";

test "composition flow retains successful parts across correction loops and assembles without a new request" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const resources = try fixtureResources(arena.allocator());
    var state = try flow.apply(.{}, initialize(), &resources, .ok);
    state = try flow.apply(state, request("text"), &resources, .ok);
    state = try flow.apply(state, complete(), &resources, .ok);
    state = try flow.apply(state, retain(), &resources, .ok);
    try std.testing.expect(state.eql(try flow.apply(state, retain(), &resources, .ok)));
    const text = state.plan.?.part(.{ .bytes = "text" }).?;
    try std.testing.expect(state.completed.isSet(text));
    state = try flow.apply(state, retire(), &resources, .ok);
    state = try flow.apply(state, request("flags"), &resources, .ok);
    state = try flow.apply(state, complete(), &resources, .invalid);
    var correction = step();
    correction.replaces = &.{.prepared_model_request};
    correction.invalidates = &.{.model_payload_schema_result};
    const pending = state;
    state = try flow.apply(state, correction, &resources, .ok);
    try std.testing.expect(state.eql(pending));
    try std.testing.expect(state.completed.isSet(text));
    state = try flow.apply(state, complete(), &resources, .ok);
    state = try flow.apply(state, retain(), &resources, .ok);
    // The final successful request is retired after the assembled candidate is
    // consumed; its retained value is sufficient for this handoff.
    state = try flow.apply(state, assemble(), &resources, .ok);
    try std.testing.expect(state.eql(.{}));
}

test "composition flow rejects missing dependency foreign selection incomplete assembly and unsuccessful retention" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const resources = try fixtureResources(arena.allocator());
    const initialized = try flow.apply(.{}, initialize(), &resources, .ok);
    try rejected(.{}, request("text"), &resources);
    try rejected(initialized, initialize(), &resources);
    try rejected(initialized, request("unknown"), &resources);
    try rejected(initialized, request("flags"), &resources);
    try rejected(initialized, retain(), &resources);
    try rejected(initialized, assemble(), &resources);
    var native = request("text");
    native.parameters = &.{.{ .id = .{ .bytes = "result-schema" }, .value = .{ .resource = .{ .bytes = "result" } } }};
    try rejected(initialized, native, &resources);
    var duplicate_shape = request("text");
    duplicate_shape.parameters = &.{
        .{ .id = .{ .bytes = "composition-part" }, .value = .{ .string = "text" } },
        .{ .id = .{ .bytes = "result-schema" }, .value = .{ .resource = .{ .bytes = "result" } } },
    };
    try rejected(initialized, duplicate_shape, &resources);
    var state = try flow.apply(initialized, request("text"), &resources, .ok);
    try rejected(state, retain(), &resources);
    state = try flow.apply(state, complete(), &resources, .invalid);
    try rejected(state, retain(), &resources);
    state = try flow.apply(state, complete(), &resources, .ok);
    state = try flow.apply(state, retain(), &resources, .ok);
    try std.testing.expect(!state.eql(initialized));
    state = try flow.apply(state, retire(), &resources, .ok);
    try rejected(state, request("text"), &resources);
    try rejected(state, assemble(), &resources);
}

fn rejected(state: flow.State, selected: compilation.CompiledStep, resources: []const compilation.CompiledResource) !void {
    try std.testing.expectError(error.InvalidWorkflowComposition, flow.apply(state, selected, resources, .ok));
}

fn fixtureResources(allocator: std.mem.Allocator) ![2]compilation.CompiledResource {
    var adapter: schemas.Adapter = .{};
    const canonical = try adapter.compiler().compile(allocator, result_bytes);
    return .{
        .{ .id = .{ .bytes = "result" }, .content = .{ .result_schema = canonical } },
        .{ .id = .{ .bytes = "split" }, .content = .{ .json_composition = try adapter.compiler().compileComposition(allocator, composition_bytes, canonical) } },
    };
}

fn step() compilation.CompiledStep {
    return .{ .id = .{ .bytes = "unit" }, .operation_id = .{ .bytes = "unit.operation" }, .parameters = &.{}, .requires = &.{}, .produces = &.{}, .replaces = &.{}, .invalidates = &.{}, .outcomes = &.{.ok}, .side_effect = .none, .gates = &.{}, .capabilities = &.{}, .retry_authority = null };
}

fn initialize() compilation.CompiledStep {
    var value = step();
    value.produces = &.{.json_composition};
    value.parameters = &.{.{ .id = .{ .bytes = "composition" }, .value = .{ .resource = .{ .bytes = "split" } } }};
    return value;
}

fn request(comptime part: []const u8) compilation.CompiledStep {
    var value = step();
    value.produces = &.{.assigned_model_request};
    value.replaces = &.{.model_request_identity_ledger};
    value.parameters = &.{.{ .id = .{ .bytes = "composition-part" }, .value = .{ .string = part } }};
    return value;
}

fn complete() compilation.CompiledStep {
    var value = step();
    value.requires = &.{.terminal_provider_operation};
    value.replaces = &.{.model_request_identity_ledger};
    return value;
}

fn retain() compilation.CompiledStep {
    var value = step();
    value.requires = &.{ .prepared_model_request, .model_payload_schema_result };
    value.replaces = &.{.json_composition};
    return value;
}

fn retire() compilation.CompiledStep {
    var value = step();
    value.invalidates = &.{ .assigned_model_request, .prepared_model_request };
    return value;
}

fn assemble() compilation.CompiledStep {
    var value = step();
    value.invalidates = &.{.json_composition};
    value.produces = &.{.assembled_json};
    return value;
}
