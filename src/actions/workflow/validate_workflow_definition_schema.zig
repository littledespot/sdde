const std = @import("std");
const pipeline = @import("../../domain/pipeline.zig");
const telemetry = @import("../../domain/telemetry.zig");
const workflow = @import("../../domain/workflow_registry.zig");

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
        raw_values: []const workflow.RawDefinition,
    ) Error![]const workflow.Definition {
        const definitions = allocator.alloc(workflow.Definition, raw_values.len) catch return invalid();
        for (raw_values, definitions) |raw, *destination| {
            destination.* = try convert(allocator, raw.ordinal, raw.root);
        }
        return definitions;
    }
};

const root_fields = [_][]const u8{
    "schemaVersion",
    "workflowId",
    "workflowVersion",
    "workflowShortcode",
    "invocationContractNodeId",
    "workflowPolicyProfileId",
    "entryWorkflowNodeId",
    "nodes",
    "transitions",
};
const node_fields = [_][]const u8{ "workflowNodeId", "pipelineNodeContractId", "parameters" };
const parameter_fields = [_][]const u8{ "parameterId", "value" };
const parameter_value_fields = [_][]const u8{ "kind", "value" };
const transition_fields = [_][]const u8{ "fromWorkflowNodeId", "outcomeTag", "target" };

fn convert(
    allocator: std.mem.Allocator,
    ordinal: u16,
    root: *workflow.RawNode,
) Error!workflow.Definition {
    const map = exactMapping(root, &root_fields) orelse return invalid();
    if (!stringEquals(field(map, "schemaVersion"), workflow.schema_version)) return invalid();

    const workflow_id = workflow.WorkflowId.parse(string(field(map, "workflowId")) orelse return invalid()) orelse return invalid();
    const version_value = integer(field(map, "workflowVersion")) orelse return invalid();
    if (version_value <= 0 or version_value > std.math.maxInt(u32)) return invalid();
    const shortcode = telemetry.WorkflowShortcode.parse(string(field(map, "workflowShortcode")) orelse return invalid()) catch return invalid();
    const invocation = workflow.RegisteredRef.parse(string(field(map, "invocationContractNodeId")) orelse return invalid()) orelse return invalid();
    const policy = workflow.RegisteredRef.parse(string(field(map, "workflowPolicyProfileId")) orelse return invalid()) orelse return invalid();
    const entry = workflow.WorkflowNodeId.parse(string(field(map, "entryWorkflowNodeId")) orelse return invalid()) orelse return invalid();

    const raw_nodes = sequence(field(map, "nodes")) orelse return invalid();
    if (raw_nodes.len == 0 or raw_nodes.len > workflow.max_nodes) return invalid();
    const nodes = allocator.alloc(workflow.DeclarativeNode, raw_nodes.len) catch return invalid();
    for (raw_nodes, nodes, 0..) |raw_node, *node, index| {
        node.* = try convertNode(allocator, raw_node);
        for (nodes[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id.bytes, node.id.bytes)) return invalid();
        }
    }
    std.mem.sort(workflow.DeclarativeNode, nodes, {}, nodeLessThan);

    const raw_transitions = sequence(field(map, "transitions")) orelse return invalid();
    if (raw_transitions.len == 0 or raw_transitions.len > workflow.max_transitions) return invalid();
    const transitions = allocator.alloc(workflow.Transition, raw_transitions.len) catch return invalid();
    for (raw_transitions, transitions) |raw_transition, *transition| {
        transition.* = try convertTransition(raw_transition);
    }
    std.mem.sort(workflow.Transition, transitions, {}, transitionLessThan);

    return .{
        .source_ordinal = ordinal,
        .workflow_id = workflow_id,
        .workflow_version = @intCast(version_value),
        .shortcode = shortcode,
        .invocation_contract_id = invocation,
        .policy_profile_id = policy,
        .entry_node_id = entry,
        .nodes = nodes,
        .transitions = transitions,
    };
}

fn convertNode(allocator: std.mem.Allocator, raw: *workflow.RawNode) Error!workflow.DeclarativeNode {
    const map = exactMapping(raw, &node_fields) orelse return invalid();
    const id = workflow.WorkflowNodeId.parse(string(field(map, "workflowNodeId")) orelse return invalid()) orelse return invalid();
    const contract = workflow.RegisteredRef.parse(string(field(map, "pipelineNodeContractId")) orelse return invalid()) orelse return invalid();
    const raw_parameters = sequence(field(map, "parameters")) orelse return invalid();
    if (raw_parameters.len > workflow.max_parameters) return invalid();
    const parameters = allocator.alloc(workflow.ParameterBinding, raw_parameters.len) catch return invalid();
    for (raw_parameters, parameters, 0..) |raw_parameter, *parameter, index| {
        parameter.* = try convertParameter(raw_parameter);
        for (parameters[0..index]) |previous| {
            if (std.mem.eql(u8, previous.id.bytes, parameter.id.bytes)) return invalid();
        }
    }
    std.mem.sort(workflow.ParameterBinding, parameters, {}, parameterLessThan);
    return .{ .id = id, .contract_id = contract, .parameters = parameters };
}

fn convertParameter(raw: *workflow.RawNode) Error!workflow.ParameterBinding {
    const map = exactMapping(raw, &parameter_fields) orelse return invalid();
    const id = workflow.WorkflowParameterId.parse(string(field(map, "parameterId")) orelse return invalid()) orelse return invalid();
    const value_map = exactMapping(field(map, "value") orelse return invalid(), &parameter_value_fields) orelse return invalid();
    const kind = string(field(value_map, "kind")) orelse return invalid();
    const raw_value = field(value_map, "value");
    const value: workflow.ParameterValue = if (std.mem.eql(u8, kind, "boolean")) blk: {
        break :blk .{ .boolean = boolean(raw_value) orelse return invalid() };
    } else if (std.mem.eql(u8, kind, "integer")) blk: {
        const number = integer(raw_value) orelse return invalid();
        if (number < std.math.minInt(i64) or number > std.math.maxInt(i64)) return invalid();
        break :blk .{ .integer = @intCast(number) };
    } else if (std.mem.eql(u8, kind, "enum")) blk: {
        break :blk .{ .@"enum" = workflow.WorkflowNodeId.parse(string(raw_value) orelse return invalid()) orelse return invalid() };
    } else if (std.mem.eql(u8, kind, "registered_id")) blk: {
        break :blk .{ .registered_id = workflow.RegisteredRef.parse(string(raw_value) orelse return invalid()) orelse return invalid() };
    } else return invalid();
    return .{ .id = id, .value = value };
}

fn convertTransition(raw: *workflow.RawNode) Error!workflow.Transition {
    const map = exactMapping(raw, &transition_fields) orelse return invalid();
    return .{
        .from = workflow.WorkflowNodeId.parse(string(field(map, "fromWorkflowNodeId")) orelse return invalid()) orelse return invalid(),
        .outcome = std.meta.stringToEnum(workflow.OutcomeTag, string(field(map, "outcomeTag")) orelse return invalid()) orelse return invalid(),
        .target = try convertTarget(field(map, "target") orelse return invalid()),
    };
}

fn convertTarget(raw: *workflow.RawNode) Error!workflow.TransitionTarget {
    const map = mapping(raw) orelse return invalid();
    const kind = string(field(map, "kind")) orelse return invalid();
    if (std.mem.eql(u8, kind, "node")) {
        const fields = [_][]const u8{ "kind", "workflowNodeId" };
        if (exactMapping(raw, &fields) == null) return invalid();
        return .{ .node = workflow.WorkflowNodeId.parse(string(field(map, "workflowNodeId")) orelse return invalid()) orelse return invalid() };
    }
    if (std.mem.eql(u8, kind, "terminal")) {
        const fields = [_][]const u8{ "kind", "outcomeTag" };
        if (exactMapping(raw, &fields) == null) return invalid();
        return .{ .terminal = std.meta.stringToEnum(workflow.OutcomeTag, string(field(map, "outcomeTag")) orelse return invalid()) orelse return invalid() };
    }
    return invalid();
}

fn exactMapping(node: *workflow.RawNode, expected: []const []const u8) ?[]const workflow.RawPair {
    const map = mapping(node) orelse return null;
    if (map.len != expected.len) return null;
    for (map, 0..) |pair, index| {
        const key = string(pair.key) orelse return null;
        if (!containsString(expected, key)) return null;
        for (map[0..index]) |prior| {
            const prior_key = string(prior.key) orelse return null;
            if (std.mem.eql(u8, prior_key, key)) return null;
        }
    }
    return map;
}

fn mapping(node: *workflow.RawNode) ?[]const workflow.RawPair {
    return switch (node.*) {
        .mapping => |value| value,
        else => null,
    };
}
fn sequence(node: ?*workflow.RawNode) ?[]const *workflow.RawNode {
    const present = node orelse return null;
    return switch (present.*) {
        .sequence => |value| value,
        else => null,
    };
}
fn string(node: ?*workflow.RawNode) ?[]const u8 {
    const present = node orelse return null;
    return switch (present.*) {
        .scalar => |value| value,
        else => null,
    };
}
fn integer(node: ?*workflow.RawNode) ?i128 {
    const present = node orelse return null;
    return switch (present.*) {
        .integer => |value| value,
        else => null,
    };
}
fn boolean(node: ?*workflow.RawNode) ?bool {
    const present = node orelse return null;
    return switch (present.*) {
        .boolean => |value| value,
        else => null,
    };
}
fn stringEquals(node: ?*workflow.RawNode, expected: []const u8) bool {
    return if (string(node)) |actual| std.mem.eql(u8, actual, expected) else false;
}
fn field(map: []const workflow.RawPair, name: []const u8) ?*workflow.RawNode {
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
fn nodeLessThan(_: void, left: workflow.DeclarativeNode, right: workflow.DeclarativeNode) bool {
    return std.mem.order(u8, left.id.bytes, right.id.bytes) == .lt;
}
fn parameterLessThan(_: void, left: workflow.ParameterBinding, right: workflow.ParameterBinding) bool {
    return std.mem.order(u8, left.id.bytes, right.id.bytes) == .lt;
}
fn transitionLessThan(_: void, left: workflow.Transition, right: workflow.Transition) bool {
    const order = std.mem.order(u8, left.from.bytes, right.from.bytes);
    return order == .lt or (order == .eq and @intFromEnum(left.outcome) < @intFromEnum(right.outcome));
}
fn invalid() Error {
    return error.WorkflowDefinitionSchemaInvalid;
}

const RawBuilder = struct {
    allocator: std.mem.Allocator,

    fn scalar(self: RawBuilder, value: []const u8) !*workflow.RawNode {
        const node = try self.allocator.create(workflow.RawNode);
        node.* = .{ .scalar = value };
        return node;
    }
    fn integer(self: RawBuilder, value: i128) !*workflow.RawNode {
        const node = try self.allocator.create(workflow.RawNode);
        node.* = .{ .integer = value };
        return node;
    }
    fn boolean(self: RawBuilder, value: bool) !*workflow.RawNode {
        const node = try self.allocator.create(workflow.RawNode);
        node.* = .{ .boolean = value };
        return node;
    }
    fn nullValue(self: RawBuilder) !*workflow.RawNode {
        const node = try self.allocator.create(workflow.RawNode);
        node.* = .null_value;
        return node;
    }
    fn sequence(self: RawBuilder, values: []const *workflow.RawNode) !*workflow.RawNode {
        const node = try self.allocator.create(workflow.RawNode);
        node.* = .{ .sequence = try self.allocator.dupe(*workflow.RawNode, values) };
        return node;
    }
    fn mapping(self: RawBuilder, pairs: []const workflow.RawPair) !*workflow.RawNode {
        const node = try self.allocator.create(workflow.RawNode);
        node.* = .{ .mapping = try self.allocator.dupe(workflow.RawPair, pairs) };
        return node;
    }
    fn pair(self: RawBuilder, key: []const u8, value: *workflow.RawNode) !workflow.RawPair {
        return .{ .key = try self.scalar(key), .value = value };
    }
};

fn minimalRaw(builder: RawBuilder, add_unknown: bool) !*workflow.RawNode {
    const empty = try builder.sequence(&.{});
    const node = try builder.mapping(&.{
        try builder.pair("workflowNodeId", try builder.scalar("run")),
        try builder.pair("pipelineNodeContractId", try builder.scalar("core.noop@1")),
        try builder.pair("parameters", empty),
    });
    const nodes = try builder.sequence(&.{node});
    const target = try builder.mapping(&.{
        try builder.pair("kind", try builder.scalar("terminal")),
        try builder.pair("outcomeTag", try builder.scalar("ok")),
    });
    const transition = try builder.mapping(&.{
        try builder.pair("fromWorkflowNodeId", try builder.scalar("run")),
        try builder.pair("outcomeTag", try builder.scalar("ok")),
        try builder.pair("target", target),
    });
    const transitions = try builder.sequence(&.{transition});
    var pairs: std.ArrayList(workflow.RawPair) = .empty;
    try pairs.append(builder.allocator, try builder.pair("schemaVersion", try builder.scalar("1.0")));
    try pairs.append(builder.allocator, try builder.pair("workflowId", try builder.scalar("hello")));
    try pairs.append(builder.allocator, try builder.pair("workflowVersion", try builder.integer(1)));
    try pairs.append(builder.allocator, try builder.pair("workflowShortcode", try builder.scalar("HELO")));
    try pairs.append(builder.allocator, try builder.pair("invocationContractNodeId", try builder.scalar("core.empty@1")));
    try pairs.append(builder.allocator, try builder.pair("workflowPolicyProfileId", try builder.scalar("core.safe@1")));
    try pairs.append(builder.allocator, try builder.pair("entryWorkflowNodeId", try builder.scalar("run")));
    try pairs.append(builder.allocator, try builder.pair("nodes", nodes));
    try pairs.append(builder.allocator, try builder.pair("transitions", transitions));
    if (add_unknown) try pairs.append(builder.allocator, try builder.pair("command", try builder.scalar("no")));
    return builder.mapping(pairs.items);
}

test "converts the closed minimal raw schema" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    const raw = [_]workflow.RawDefinition{.{ .ordinal = 1, .root = try minimalRaw(builder, false) }};
    const values = try (Action{}).execute(arena.allocator(), &raw);
    try std.testing.expectEqualStrings("hello", values[0].workflow_id.bytes);
}

test "rejects unknown fields and YAML scalar kind mismatches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    const unknown = [_]workflow.RawDefinition{.{ .ordinal = 1, .root = try minimalRaw(builder, true) }};
    try std.testing.expectError(error.WorkflowDefinitionSchemaInvalid, (Action{}).execute(arena.allocator(), &unknown));

    const wrong_kind_root = try minimalRaw(builder, false);
    const version = field(mapping(wrong_kind_root).?, "workflowVersion").?;
    version.* = .{ .scalar = "1" };
    const wrong_kind = [_]workflow.RawDefinition{.{ .ordinal = 1, .root = wrong_kind_root }};
    try std.testing.expectError(error.WorkflowDefinitionSchemaInvalid, (Action{}).execute(arena.allocator(), &wrong_kind));
}

test "rejects missing fields versions malformed identifiers and empty graph sequences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };

    const missing_root = try minimalRaw(builder, false);
    const missing_map = mapping(missing_root).?;
    missing_root.* = .{ .mapping = missing_map[0 .. missing_map.len - 1] };
    try expectInvalid(missing_root);

    const invalid_cases = [_]struct { field_name: []const u8, value: *workflow.RawNode }{
        .{ .field_name = "schemaVersion", .value = try builder.scalar("2.0") },
        .{ .field_name = "workflowId", .value = try builder.scalar("Hello") },
        .{ .field_name = "workflowVersion", .value = try builder.integer(0) },
        .{ .field_name = "workflowVersion", .value = try builder.integer(@as(i128, std.math.maxInt(u32)) + 1) },
        .{ .field_name = "workflowShortcode", .value = try builder.scalar("ABC") },
        .{ .field_name = "invocationContractNodeId", .value = try builder.scalar("core.empty@0") },
        .{ .field_name = "workflowPolicyProfileId", .value = try builder.scalar("latest") },
        .{ .field_name = "entryWorkflowNodeId", .value = try builder.scalar("Run") },
        .{ .field_name = "nodes", .value = try builder.sequence(&.{}) },
        .{ .field_name = "transitions", .value = try builder.sequence(&.{}) },
    };
    for (invalid_cases) |case| {
        const root = try minimalRaw(builder, false);
        field(mapping(root).?, case.field_name).?.* = case.value.*;
        try expectInvalid(root);
    }
}

test "every closed mapping rejects missing wrong-kind and prohibited fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };

    for (root_fields) |field_name| {
        const missing_root = try minimalRaw(builder, false);
        const source = mapping(missing_root).?;
        const reduced = try arena.allocator().alloc(workflow.RawPair, source.len - 1);
        var destination: usize = 0;
        for (source) |pair_value| {
            if (std.mem.eql(u8, string(pair_value.key).?, field_name)) continue;
            reduced[destination] = pair_value;
            destination += 1;
        }
        missing_root.* = .{ .mapping = reduced };
        try expectInvalid(missing_root);

        const wrong_kind_root = try minimalRaw(builder, false);
        field(mapping(wrong_kind_root).?, field_name).?.* = (try builder.nullValue()).*;
        try expectInvalid(wrong_kind_root);
    }

    const prohibited = [_][]const u8{ "path", "command", "adapter", "capability", "script", "runnerControl" };
    for (prohibited) |field_name| {
        const root = try minimalRaw(builder, false);
        const source = mapping(root).?;
        const expanded = try arena.allocator().alloc(workflow.RawPair, source.len + 1);
        @memcpy(expanded[0..source.len], source);
        expanded[source.len] = try builder.pair(field_name, try builder.scalar("forbidden"));
        root.* = .{ .mapping = expanded };
        try expectInvalid(root);
    }

    const nested_root = try minimalRaw(builder, false);
    const node = sequence(field(mapping(nested_root).?, "nodes")).?[0];
    try appendUnknownField(builder, node, "adapter");
    try expectInvalid(nested_root);

    const parameter_root = try minimalRaw(builder, false);
    const parameter_node = sequence(field(mapping(parameter_root).?, "nodes")).?[0];
    const parameter_value = try rawParameter(builder, "flag", "boolean", try builder.boolean(true));
    field(mapping(parameter_node).?, "parameters").?.* = .{ .sequence = &.{parameter_value} };
    try appendUnknownField(builder, parameter_value, "path");
    try expectInvalid(parameter_root);

    const tagged_root = try minimalRaw(builder, false);
    const tagged_node = sequence(field(mapping(tagged_root).?, "nodes")).?[0];
    const tagged_parameter = try rawParameter(builder, "flag", "boolean", try builder.boolean(true));
    field(mapping(tagged_node).?, "parameters").?.* = .{ .sequence = &.{tagged_parameter} };
    try appendUnknownField(builder, field(mapping(tagged_parameter).?, "value").?, "command");
    try expectInvalid(tagged_root);

    const transition_root = try minimalRaw(builder, false);
    const transition = sequence(field(mapping(transition_root).?, "transitions")).?[0];
    try appendUnknownField(builder, transition, "script");
    try expectInvalid(transition_root);

    const target_root = try minimalRaw(builder, false);
    const target_transition = sequence(field(mapping(target_root).?, "transitions")).?[0];
    try appendUnknownField(builder, field(mapping(target_transition).?, "target").?, "capability");
    try expectInvalid(target_root);
}

test "parameter variants are closed bounded and locally unique" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    const root = try minimalRaw(builder, false);
    const node = sequence(field(mapping(root).?, "nodes")).?[0];
    const parameters = [_]*workflow.RawNode{
        try rawParameter(builder, "flag", "boolean", try builder.boolean(true)),
        try rawParameter(builder, "minimum", "integer", try builder.integer(std.math.minInt(i64))),
        try rawParameter(builder, "mode", "enum", try builder.scalar("safe-mode")),
        try rawParameter(builder, "profile", "registered_id", try builder.scalar("core.profile@1")),
    };
    field(mapping(node).?, "parameters").?.* = .{ .sequence = &parameters };
    _ = try (Action{}).execute(arena.allocator(), &.{.{ .ordinal = 1, .root = root }});

    const duplicate = try minimalRaw(builder, false);
    const duplicate_node = sequence(field(mapping(duplicate).?, "nodes")).?[0];
    const repeated = try rawParameter(builder, "same", "boolean", try builder.boolean(true));
    field(mapping(duplicate_node).?, "parameters").?.* = .{ .sequence = &.{ repeated, repeated } };
    try expectInvalid(duplicate);

    const invalid_values = [_]struct { kind: []const u8, value: *workflow.RawNode }{
        .{ .kind = "integer", .value = try builder.integer(@as(i128, std.math.maxInt(i64)) + 1) },
        .{ .kind = "enum", .value = try builder.scalar("Not-Kebab") },
        .{ .kind = "registered_id", .value = try builder.scalar("core.profile@0") },
        .{ .kind = "text", .value = try builder.scalar("free text") },
        .{ .kind = "boolean", .value = try builder.scalar("true") },
    };
    for (invalid_values) |invalid_value| {
        const invalid_root = try minimalRaw(builder, false);
        const invalid_node = sequence(field(mapping(invalid_root).?, "nodes")).?[0];
        const parameter = try rawParameter(builder, "value", invalid_value.kind, invalid_value.value);
        field(mapping(invalid_node).?, "parameters").?.* = .{ .sequence = &.{parameter} };
        try expectInvalid(invalid_root);
    }
}

test "schema sequence limits accept exact bounds and reject one more" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };

    const exact_nodes_root = try minimalRaw(builder, false);
    const exact_nodes = try arena.allocator().alloc(*workflow.RawNode, workflow.max_nodes);
    for (exact_nodes, 0..) |*node, index| node.* = try rawNode(builder, try std.fmt.allocPrint(arena.allocator(), "n{d}", .{index}), &.{});
    field(mapping(exact_nodes_root).?, "nodes").?.* = .{ .sequence = exact_nodes };
    _ = try (Action{}).execute(arena.allocator(), &.{.{ .ordinal = 1, .root = exact_nodes_root }});

    const too_many_nodes_root = try minimalRaw(builder, false);
    const too_many_nodes = try arena.allocator().alloc(*workflow.RawNode, workflow.max_nodes + 1);
    @memset(too_many_nodes, exact_nodes[0]);
    field(mapping(too_many_nodes_root).?, "nodes").?.* = .{ .sequence = too_many_nodes };
    try expectInvalid(too_many_nodes_root);

    const duplicate_nodes_root = try minimalRaw(builder, false);
    const duplicate_node = sequence(field(mapping(duplicate_nodes_root).?, "nodes")).?[0];
    field(mapping(duplicate_nodes_root).?, "nodes").?.* = .{ .sequence = &.{ duplicate_node, duplicate_node } };
    try expectInvalid(duplicate_nodes_root);

    const exact_parameters_root = try minimalRaw(builder, false);
    const exact_parameters_node = sequence(field(mapping(exact_parameters_root).?, "nodes")).?[0];
    const exact_parameters = try arena.allocator().alloc(*workflow.RawNode, workflow.max_parameters);
    for (exact_parameters, 0..) |*parameter, index| parameter.* = try rawParameter(
        builder,
        try std.fmt.allocPrint(arena.allocator(), "p{d}", .{index}),
        "boolean",
        try builder.boolean(true),
    );
    field(mapping(exact_parameters_node).?, "parameters").?.* = .{ .sequence = exact_parameters };
    _ = try (Action{}).execute(arena.allocator(), &.{.{ .ordinal = 1, .root = exact_parameters_root }});
    const too_many_parameters = try arena.allocator().alloc(*workflow.RawNode, workflow.max_parameters + 1);
    @memset(too_many_parameters, exact_parameters[0]);
    field(mapping(exact_parameters_node).?, "parameters").?.* = .{ .sequence = too_many_parameters };
    try expectInvalid(exact_parameters_root);

    const exact_transitions_root = try minimalRaw(builder, false);
    const transition = sequence(field(mapping(exact_transitions_root).?, "transitions")).?[0];
    const exact_transitions = try arena.allocator().alloc(*workflow.RawNode, workflow.max_transitions);
    @memset(exact_transitions, transition);
    field(mapping(exact_transitions_root).?, "transitions").?.* = .{ .sequence = exact_transitions };
    _ = try (Action{}).execute(arena.allocator(), &.{.{ .ordinal = 1, .root = exact_transitions_root }});
    const too_many_transitions = try arena.allocator().alloc(*workflow.RawNode, workflow.max_transitions + 1);
    @memset(too_many_transitions, transition);
    field(mapping(exact_transitions_root).?, "transitions").?.* = .{ .sequence = too_many_transitions };
    try expectInvalid(exact_transitions_root);
}

fn expectInvalid(root: *workflow.RawNode) !void {
    var scratch = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer scratch.deinit();
    try std.testing.expectError(
        error.WorkflowDefinitionSchemaInvalid,
        (Action{}).execute(scratch.allocator(), &.{.{ .ordinal = 1, .root = root }}),
    );
}

fn rawNode(builder: RawBuilder, id: []const u8, parameters: []const *workflow.RawNode) !*workflow.RawNode {
    return builder.mapping(&.{
        try builder.pair("workflowNodeId", try builder.scalar(id)),
        try builder.pair("pipelineNodeContractId", try builder.scalar("core.noop@1")),
        try builder.pair("parameters", try builder.sequence(parameters)),
    });
}

fn rawParameter(builder: RawBuilder, id: []const u8, kind: []const u8, value: *workflow.RawNode) !*workflow.RawNode {
    const tagged = try builder.mapping(&.{
        try builder.pair("kind", try builder.scalar(kind)),
        try builder.pair("value", value),
    });
    return builder.mapping(&.{
        try builder.pair("parameterId", try builder.scalar(id)),
        try builder.pair("value", tagged),
    });
}

fn appendUnknownField(builder: RawBuilder, node: *workflow.RawNode, name: []const u8) !void {
    const source = mapping(node) orelse return error.ExpectedMapping;
    const expanded = try builder.allocator.alloc(workflow.RawPair, source.len + 1);
    @memcpy(expanded[0..source.len], source);
    expanded[source.len] = try builder.pair(name, try builder.scalar("forbidden"));
    node.* = .{ .mapping = expanded };
}
