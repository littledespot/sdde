const std = @import("std");
const pipeline = @import("domain/pipeline.zig");
const data = @import("domain/pipeline_data.zig");
const values = @import("application/pipeline_values.zig");
const envelope_module = @import("application/pipeline_envelope.zig");

const Context = struct { text: []const u8, attempts: u32 };
const context_schema = values.schema(.workflow_invocation, Context, 1, 256);
const count_schema = values.schema(.canonical_log_level, u32, 1, 32);
const schemas = [_]data.Schema{ context_schema, count_schema };
const context_index = @intFromEnum(pipeline.DataKey.workflow_invocation);
const count_index = @intFromEnum(pipeline.DataKey.canonical_log_level);
const produce: pipeline.NodeContract = .{
    .id = "test.context@1",
    .kind = .action,
    .requires = &.{},
    .produces = &.{.workflow_invocation},
    .side_effect = .none,
};
const consume: pipeline.NodeContract = .{
    .id = "test.consume@1",
    .kind = .action,
    .requires = &.{.workflow_invocation},
    .produces = &.{},
    .side_effect = .none,
};

test "envelope owns copied input and exposes only declared keys" {
    var envelope = envelope_module.PipelineEnvelope.init(&schemas);
    defer envelope.deinit();
    var bytes = "hello".*;
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = &bytes, .attempts = 2 });
    try envelope.apply(produce, &delta, .ok);
    try std.testing.expect(delta.data_writes[context_index] == null);
    bytes[0] = 'x';
    const view = try envelope.view(consume);
    const context = try values.read(&view, context_schema, Context);
    try std.testing.expectEqualStrings("hello", context.text);
    try std.testing.expectEqual(@as(u32, 2), context.attempts);
    const hidden = try envelope.view(.{ .id = "test.hidden@1", .kind = .action, .requires = &.{}, .produces = &.{}, .side_effect = .none });
    try std.testing.expect(!hidden.contains(.workflow_invocation));
    try std.testing.expectError(error.MissingRequiredData, values.read(&hidden, context_schema, Context));
    try std.testing.expectError(error.DataSchemaMismatch, values.read(&view, context_schema, u32));
}

test "optional inputs expose present values without making absent values required" {
    var envelope = envelope_module.PipelineEnvelope.init(&schemas);
    defer envelope.deinit();
    const optional: pipeline.NodeContract = .{
        .id = "test.optional@1",
        .kind = .action,
        .requires = &.{},
        .optional = &.{.workflow_invocation},
        .produces = &.{},
        .side_effect = .none,
    };
    const absent = try envelope.view(optional);
    try std.testing.expect(!absent.contains(.workflow_invocation));
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "optional", .attempts = 1 });
    try envelope.apply(produce, &delta, .ok);
    const present = try envelope.view(optional);
    try std.testing.expectEqualStrings("optional", (try values.read(&present, context_schema, Context)).text);
}

test "rejected replacements and schema mismatches preserve the complete old envelope" {
    var envelope = envelope_module.PipelineEnvelope.init(&schemas);
    defer envelope.deinit();
    var initial: pipeline.NodeDelta = .{};
    defer envelope.discard(&initial);
    initial.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "old", .attempts = 1 });
    try envelope.apply(produce, &initial, .ok);
    const replace_and_write: pipeline.NodeContract = .{
        .id = "test.replace@1",
        .kind = .action,
        .requires = &.{.workflow_invocation},
        .produces = &.{.canonical_log_level},
        .replaces = &.{.workflow_invocation},
        .side_effect = .none,
    };
    var bad_version = count_schema;
    bad_version.version = 2;
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "new", .attempts = 2 });
    delta.data_writes[count_index] = try values.create(std.testing.allocator, bad_version, u32, 9);
    try std.testing.expectError(error.DataSchemaMismatch, envelope.apply(replace_and_write, &delta, .ok));
    const old = try envelope.view(consume);
    try std.testing.expectEqualStrings("old", (try values.read(&old, context_schema, Context)).text);
    const require_count: pipeline.NodeContract = .{ .id = "test.count@1", .kind = .action, .requires = &.{.canonical_log_level}, .produces = &.{}, .side_effect = .none };
    try std.testing.expectError(error.MissingRequiredData, envelope.view(require_count));
    envelope.discard(&delta);
    delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "new", .attempts = 2 });
    delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 9);
    try envelope.apply(replace_and_write, &delta, .ok);
    const next = try envelope.view(consume);
    try std.testing.expectEqualStrings("new", (try values.read(&next, context_schema, Context)).text);
    const counts = try envelope.view(require_count);
    try std.testing.expectEqual(@as(u32, 9), (try values.read(&counts, count_schema, u32)).*);

    var invalidation: pipeline.NodeDelta = .{ .data_invalidations = .initOne(.workflow_invocation) };
    const invalidate: pipeline.NodeContract = .{ .id = "test.invalidate@1", .kind = .action, .requires = &.{}, .produces = &.{}, .invalidates = &.{.workflow_invocation}, .side_effect = .none };
    try envelope.apply(invalidate, &invalidation, .ok);
    try std.testing.expectError(error.MissingRequiredData, envelope.view(consume));
    try std.testing.expectError(error.InvalidationTargetMissing, envelope.apply(invalidate, &invalidation, .ok));
}

test "missing extra wrong-key and aliased values cannot satisfy a data contract" {
    var envelope = envelope_module.PipelineEnvelope.init(&schemas);
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    try std.testing.expectError(error.MissingDeclaredWrite, envelope.apply(produce, &delta, .ok));
    delta.data_writes[count_index] = try values.create(std.testing.allocator, count_schema, u32, 1);
    try std.testing.expectError(error.UndeclaredWrite, envelope.apply(produce, &delta, .ok));
    delta.data_writes[context_index] = delta.data_writes[count_index];
    const both: pipeline.NodeContract = .{ .id = "test.both@1", .kind = .action, .requires = &.{}, .produces = &.{ .canonical_log_level, .workflow_invocation }, .side_effect = .none };
    try std.testing.expectError(error.AliasedDataValue, envelope.apply(both, &delta, .ok));
    envelope.discard(&delta); // Duplicate handle is destroyed once.
    delta.data_writes[context_index] = try values.create(std.testing.allocator, count_schema, u32, 1);
    try std.testing.expectError(error.DataSchemaMismatch, envelope.apply(produce, &delta, .ok));
    envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "retained", .attempts = 1 });
    try envelope.apply(produce, &delta, .ok);
    const view = try envelope.view(consume);
    delta.data_replacements[context_index] = view.slots[context_index];
    const replace: pipeline.NodeContract = .{ .id = "test.replace@1", .kind = .action, .requires = &.{}, .produces = &.{}, .replaces = &.{.workflow_invocation}, .side_effect = .none };
    try std.testing.expectError(error.AliasedDataValue, envelope.apply(replace, &delta, .ok));
    envelope.discard(&delta); // A borrowed input remains owned by the envelope.
    try std.testing.expectEqualStrings("retained", (try values.read(&view, context_schema, Context)).text);
}

test "value construction enforces native type version and allocation bounds" {
    try std.testing.expectError(error.DataSchemaMismatch, values.create(std.testing.allocator, count_schema, Context, .{ .text = "wrong type", .attempts = 1 }));
    var invalid = context_schema;
    invalid.version = 0;
    try std.testing.expectError(error.InvalidDataSchema, values.create(std.testing.allocator, invalid, Context, .{ .text = "", .attempts = 1 }));
    var small = context_schema;
    small.maximum_bytes = @sizeOf(Context) + 1;
    try std.testing.expectError(error.DataValueLimitExceeded, values.create(std.testing.allocator, small, Context, .{ .text = "oversized", .attempts = 1 }));
}

test "unregistered schemas invalid telemetry and conflicting effects leave values unchanged" {
    var envelope = envelope_module.PipelineEnvelope.init(&.{});
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "retained", .attempts = 1 });
    try std.testing.expectError(error.UnregisteredDataSchema, envelope.apply(produce, &delta, .ok));
    envelope.schemas = &schemas;
    delta.telemetry_fact_count = 255;
    try std.testing.expectError(error.InvalidTelemetryCount, envelope.apply(produce, &delta, .ok));
    try std.testing.expectError(error.MissingRequiredData, envelope.view(consume));
    delta.telemetry_fact_count = 0;
    try envelope.apply(produce, &delta, .ok);
    delta.data_replacements[context_index] = try values.create(std.testing.allocator, context_schema, Context, .{ .text = "rejected", .attempts = 2 });
    delta.data_invalidations.insert(.workflow_invocation);
    const conflicting: pipeline.NodeContract = .{
        .id = "test.conflict@1",
        .kind = .action,
        .requires = &.{},
        .produces = &.{},
        .replaces = &.{.workflow_invocation},
        .invalidates = &.{.workflow_invocation},
        .side_effect = .none,
    };
    try std.testing.expectError(error.ConflictingDataEffects, envelope.apply(conflicting, &delta, .ok));
    const retained = try envelope.view(consume);
    try std.testing.expectEqualStrings("retained", (try values.read(&retained, context_schema, Context)).text);
}

test "value and envelope ownership survives every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    const Nested = struct { tags: []const []const u8, choice: union(enum) { text: []const u8, count: u32 }, context: ?*const Context };
    const nested_schema = values.schema(.workflow_invocation, Nested, 1, 1024);
    var envelope = envelope_module.PipelineEnvelope.init(&.{nested_schema});
    defer envelope.deinit();
    var delta: pipeline.NodeDelta = .{};
    defer envelope.discard(&delta);
    delta.data_writes[context_index] = try values.create(allocator, nested_schema, Nested, .{
        .tags = &.{ "one", "two" },
        .choice = .{ .text = "three" },
        .context = &.{ .text = "four", .attempts = 4 },
    });
    try envelope.apply(produce, &delta, .ok);
    const view = try envelope.view(consume);
    const result = try values.read(&view, nested_schema, Nested);
    try std.testing.expectEqualStrings("two", result.tags[1]);
    try std.testing.expectEqualStrings("three", result.choice.text);
    try std.testing.expectEqualStrings("four", result.context.?.text);
}
