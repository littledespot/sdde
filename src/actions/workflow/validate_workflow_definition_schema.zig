const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const telemetry = @import("../../domain/telemetry.zig");
const workflow = @import("../../domain/workflow.zig");
const definition = @import("../../domain/workflow_definition.zig");
const inventory = @import("../../domain/workflow_inventory.zig");

pub const Error = error{WorkflowDefinitionSchemaInvalid};

pub const Action = struct {
    pub const contract: pipeline.NodeContract = .{
        .id = "validate-workflow-definition-schema@1",
        .kind = .action,
        .requires = &.{.raw_workflow_definitions},
        .produces = &.{.declarative_workflow_definitions},
        .side_effect = .none,
    };

    pub fn execute(
        _: Action,
        allocator: std.mem.Allocator,
        raw_values: []const definition.RawDefinition,
    ) Error![]const definition.Definition {
        const definitions = allocator.alloc(definition.Definition, raw_values.len) catch return invalid();
        for (raw_values, definitions) |raw, *destination| {
            destination.* = try convert(allocator, raw.ordinal, raw.root);
        }
        return definitions;
    }
};

const root_fields = [_][]const u8{ "schema", "id", "version", "shortcode", "invoke", "policy", "start", "resources", "steps" };
const root_required = [_][]const u8{ "schema", "id", "version", "shortcode", "invoke", "policy", "start", "steps" };
const step_fields = [_][]const u8{ "use", "with", "on" };
const step_required = [_][]const u8{ "use", "on" };

fn convert(
    allocator: std.mem.Allocator,
    ordinal: u16,
    root: *definition.RawNode,
) Error!definition.Definition {
    const map = closedMapping(root, &root_fields, &root_required) orelse return invalid();
    if (!stringEquals(field(map, "schema"), definition.schema_version)) return invalid();

    const workflow_id = workflow.WorkflowId.parse(string(field(map, "id")) orelse return invalid()) orelse return invalid();
    const version_value = integer(field(map, "version")) orelse return invalid();
    if (version_value <= 0 or version_value > std.math.maxInt(u32)) return invalid();
    const shortcode = telemetry.WorkflowShortcode.parse(string(field(map, "shortcode")) orelse return invalid()) catch return invalid();
    const invocation = workflow.RegisteredRef.parse(string(field(map, "invoke")) orelse return invalid()) orelse return invalid();
    const policy = workflow.RegisteredRef.parse(string(field(map, "policy")) orelse return invalid()) orelse return invalid();
    const start = workflow.WorkflowStepId.parse(string(field(map, "start")) orelse return invalid()) orelse return invalid();
    const resources = try convertResources(allocator, field(map, "resources"));
    const steps = try convertSteps(allocator, field(map, "steps") orelse return invalid());

    return .{
        .source_ordinal = ordinal,
        .workflow_id = workflow_id,
        .workflow_version = @intCast(version_value),
        .shortcode = shortcode,
        .invocation_operation_id = invocation,
        .policy_profile_id = policy,
        .start_step_id = start,
        .resources = resources,
        .steps = steps,
    };
}

fn convertResources(
    allocator: std.mem.Allocator,
    raw: ?*definition.RawNode,
) Error![]const workflow.ResourceDeclaration {
    const present = raw orelse return &.{};
    const map = mapping(present) orelse return invalid();
    if (map.len > definition.max_resources) return invalid();
    const resources = allocator.alloc(workflow.ResourceDeclaration, map.len) catch return invalid();
    for (map, resources) |pair, *resource| {
        const id = workflow.WorkflowResourceId.parse(string(pair.key) orelse return invalid()) orelse return invalid();
        const name = string(pair.value) orelse return invalid();
        if (!inventory.validPath(name)) return invalid();
        resource.* = .{ .id = id, .name = name };
    }
    std.mem.sort(workflow.ResourceDeclaration, resources, {}, resourceLessThan);
    return resources;
}

fn convertSteps(
    allocator: std.mem.Allocator,
    raw: *definition.RawNode,
) Error![]const workflow.DeclarativeStep {
    const map = mapping(raw) orelse return invalid();
    if (map.len == 0 or map.len > definition.max_steps) return invalid();
    const steps = allocator.alloc(workflow.DeclarativeStep, map.len) catch return invalid();
    for (map, steps) |pair, *step| {
        const id = workflow.WorkflowStepId.parse(string(pair.key) orelse return invalid()) orelse return invalid();
        const step_map = closedMapping(pair.value, &step_fields, &step_required) orelse return invalid();
        step.* = .{
            .id = id,
            .operation_id = workflow.RegisteredRef.parse(string(field(step_map, "use")) orelse return invalid()) orelse return invalid(),
            .parameters = try convertParameters(allocator, field(step_map, "with")),
            .outcomes = try convertOutcomes(allocator, field(step_map, "on") orelse return invalid()),
        };
    }
    std.mem.sort(workflow.DeclarativeStep, steps, {}, stepLessThan);
    return steps;
}

fn convertParameters(
    allocator: std.mem.Allocator,
    raw: ?*definition.RawNode,
) Error![]const workflow.ParameterBinding {
    const present = raw orelse return &.{};
    const map = mapping(present) orelse return invalid();
    if (map.len > definition.max_parameters) return invalid();
    const parameters = allocator.alloc(workflow.ParameterBinding, map.len) catch return invalid();
    for (map, parameters) |pair, *parameter| {
        parameter.* = .{
            .id = workflow.WorkflowParameterId.parse(string(pair.key) orelse return invalid()) orelse return invalid(),
            .value = try scalarValue(pair.value),
        };
    }
    std.mem.sort(workflow.ParameterBinding, parameters, {}, parameterLessThan);
    return parameters;
}

fn convertOutcomes(
    allocator: std.mem.Allocator,
    raw: *definition.RawNode,
) Error![]const workflow.OutcomeTransition {
    const map = mapping(raw) orelse return invalid();
    if (map.len == 0 or map.len > @typeInfo(workflow.OutcomeTag).@"enum".fields.len) return invalid();
    const outcomes = allocator.alloc(workflow.OutcomeTransition, map.len) catch return invalid();
    for (map, outcomes) |pair, *outcome| {
        const tag = parseOutcome(string(pair.key) orelse return invalid()) orelse return invalid();
        outcome.* = .{ .outcome = tag, .target = parseTarget(string(pair.value) orelse return invalid()) orelse return invalid() };
    }
    std.mem.sort(workflow.OutcomeTransition, outcomes, {}, outcomeLessThan);
    return outcomes;
}

fn scalarValue(raw: *definition.RawNode) Error!workflow.ParameterValue {
    return switch (raw.*) {
        .boolean => |value| .{ .boolean = value },
        .integer => |value| if (value >= std.math.minInt(i64) and value <= std.math.maxInt(i64))
            .{ .integer = @intCast(value) }
        else
            invalid(),
        .scalar => |value| if (value.len > 0 and value.len <= definition.max_yaml_scalar_bytes)
            .{ .string = value }
        else
            invalid(),
        else => invalid(),
    };
}

fn parseOutcome(value: []const u8) ?workflow.OutcomeTag {
    if (std.mem.eql(u8, value, "needs-user")) return .needs_user;
    return std.meta.stringToEnum(workflow.OutcomeTag, value);
}

fn parseTarget(value: []const u8) ?workflow.TransitionTarget {
    if (std.mem.startsWith(u8, value, "end.")) {
        const outcome = parseOutcome(value[4..]) orelse return null;
        return .{ .terminal = outcome };
    }
    return .{ .step = workflow.WorkflowStepId.parse(value) orelse return null };
}

fn closedMapping(
    node: *definition.RawNode,
    allowed: []const []const u8,
    required: []const []const u8,
) ?[]const definition.RawPair {
    const map = mapping(node) orelse return null;
    for (map, 0..) |pair, index| {
        const key = string(pair.key) orelse return null;
        if (!containsString(allowed, key)) return null;
        for (map[0..index]) |prior| {
            const prior_key = string(prior.key) orelse return null;
            if (std.mem.eql(u8, prior_key, key)) return null;
        }
    }
    for (required) |name| if (field(map, name) == null) return null;
    return map;
}

fn mapping(node: *definition.RawNode) ?[]const definition.RawPair {
    return switch (node.*) {
        .mapping => |value| value,
        else => null,
    };
}
fn string(node: ?*definition.RawNode) ?[]const u8 {
    const present = node orelse return null;
    return switch (present.*) {
        .scalar => |value| value,
        else => null,
    };
}
fn integer(node: ?*definition.RawNode) ?i128 {
    const present = node orelse return null;
    return switch (present.*) {
        .integer => |value| value,
        else => null,
    };
}
fn stringEquals(node: ?*definition.RawNode, expected: []const u8) bool {
    return if (string(node)) |actual| std.mem.eql(u8, actual, expected) else false;
}
fn field(map: []const definition.RawPair, name: []const u8) ?*definition.RawNode {
    for (map) |pair| {
        const key = string(pair.key) orelse return null;
        if (std.mem.eql(u8, key, name)) return pair.value;
    }
    return null;
}
fn containsString(values: []const []const u8, expected: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, expected)) return true;
    return false;
}
fn resourceLessThan(_: void, left: workflow.ResourceDeclaration, right: workflow.ResourceDeclaration) bool {
    return std.mem.order(u8, left.id.bytes, right.id.bytes) == .lt;
}
fn stepLessThan(_: void, left: workflow.DeclarativeStep, right: workflow.DeclarativeStep) bool {
    return std.mem.order(u8, left.id.bytes, right.id.bytes) == .lt;
}
fn parameterLessThan(_: void, left: workflow.ParameterBinding, right: workflow.ParameterBinding) bool {
    return std.mem.order(u8, left.id.bytes, right.id.bytes) == .lt;
}
fn outcomeLessThan(_: void, left: workflow.OutcomeTransition, right: workflow.OutcomeTransition) bool {
    return @intFromEnum(left.outcome) < @intFromEnum(right.outcome);
}
fn invalid() Error {
    return error.WorkflowDefinitionSchemaInvalid;
}

const RawBuilder = struct {
    allocator: std.mem.Allocator,

    fn scalar(self: RawBuilder, value: []const u8) !*definition.RawNode {
        const node = try self.allocator.create(definition.RawNode);
        node.* = .{ .scalar = value };
        return node;
    }
    fn integer(self: RawBuilder, value: i128) !*definition.RawNode {
        const node = try self.allocator.create(definition.RawNode);
        node.* = .{ .integer = value };
        return node;
    }
    fn mapping(self: RawBuilder, pairs: []const definition.RawPair) !*definition.RawNode {
        const node = try self.allocator.create(definition.RawNode);
        node.* = .{ .mapping = try self.allocator.dupe(definition.RawPair, pairs) };
        return node;
    }
    fn pair(self: RawBuilder, key: []const u8, value: *definition.RawNode) !definition.RawPair {
        return .{ .key = try self.scalar(key), .value = value };
    }
};

fn conciseRaw(builder: RawBuilder, legacy: bool) !*definition.RawNode {
    const outcomes = try builder.mapping(&.{try builder.pair("ok", try builder.scalar("end.ok"))});
    const step = try builder.mapping(&.{
        try builder.pair("use", try builder.scalar("core.noop@1")),
        try builder.pair("on", outcomes),
    });
    const steps = try builder.mapping(&.{try builder.pair("run", step)});
    if (legacy) {
        return builder.mapping(&.{
            try builder.pair("schemaVersion", try builder.scalar("1.0")),
            try builder.pair("workflowId", try builder.scalar("legacy")),
        });
    }
    return builder.mapping(&.{
        try builder.pair("schema", try builder.scalar("workflow/v1")),
        try builder.pair("id", try builder.scalar("arbitrary-flow")),
        try builder.pair("version", try builder.integer(1)),
        try builder.pair("shortcode", try builder.scalar("FLOW")),
        try builder.pair("invoke", try builder.scalar("core.empty-invocation@1")),
        try builder.pair("policy", try builder.scalar("core.capability-free@1")),
        try builder.pair("start", try builder.scalar("run")),
        try builder.pair("steps", steps),
    });
}

test "accepts the concise workflow mapping and rejects legacy fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    const accepted = [_]definition.RawDefinition{.{ .ordinal = 1, .root = try conciseRaw(builder, false) }};
    const values = try (Action{}).execute(arena.allocator(), &accepted);
    try std.testing.expectEqualStrings("arbitrary-flow", values[0].workflow_id.bytes);
    try std.testing.expectEqualStrings("run", values[0].start_step_id.bytes);

    const rejected = [_]definition.RawDefinition{.{ .ordinal = 1, .root = try conciseRaw(builder, true) }};
    try std.testing.expectError(error.WorkflowDefinitionSchemaInvalid, (Action{}).execute(arena.allocator(), &rejected));
}

test "rejects unknown outcome and unsafe resource name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    const invalid_outcomes = try builder.mapping(&.{try builder.pair("success", try builder.scalar("end.ok"))});
    const step = try builder.mapping(&.{
        try builder.pair("use", try builder.scalar("core.noop@1")),
        try builder.pair("on", invalid_outcomes),
    });
    const steps = try builder.mapping(&.{try builder.pair("run", step)});
    const resources = try builder.mapping(&.{try builder.pair("prompt", try builder.scalar("../prompt.md"))});
    const root = try builder.mapping(&.{
        try builder.pair("schema", try builder.scalar("workflow/v1")),
        try builder.pair("id", try builder.scalar("bad-flow")),
        try builder.pair("version", try builder.integer(1)),
        try builder.pair("shortcode", try builder.scalar("BADF")),
        try builder.pair("invoke", try builder.scalar("core.empty-invocation@1")),
        try builder.pair("policy", try builder.scalar("core.capability-free@1")),
        try builder.pair("start", try builder.scalar("run")),
        try builder.pair("resources", resources),
        try builder.pair("steps", steps),
    });
    try std.testing.expectError(
        error.WorkflowDefinitionSchemaInvalid,
        (Action{}).execute(arena.allocator(), &.{.{ .ordinal = 1, .root = root }}),
    );
}
