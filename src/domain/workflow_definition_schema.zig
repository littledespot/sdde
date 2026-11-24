const std = @import("std");
const telemetry = @import("telemetry.zig");
const workflow = @import("workflow.zig");
const definition = @import("workflow_definition.zig");
const inventory = @import("workflow_inventory.zig");
const workflow_source = @import("workflow_source.zig");
const rejection = @import("definition_rejection.zig");

pub const Error = error{WorkflowDefinitionSchemaInvalid};

/// Converts the raw parsed workflow documents into declarative definitions through the closed
/// workflow-definition schema. It applies no policy and registers nothing. A rejection records the
/// section that failed, the definition's ordinal and, for a failing step, its ID in `evidence`, when one
/// is supplied; a failure outside every section is the definition's header.
pub fn validate(
    allocator: std.mem.Allocator,
    raw_values: []const definition.RawDefinition,
    evidence: ?*rejection.Slot,
) Error![]const definition.Definition {
    const definitions = allocator.alloc(definition.Definition, raw_values.len) catch return invalid();
    for (raw_values, definitions) |raw, *destination| {
        destination.* = convert(allocator, raw.ordinal, raw.root, evidence) catch return failed(evidence, .definition_header, raw.ordinal, null);
    }
    return definitions;
}

/// The family's one error with the section that raised it and the definition recorded; an inner owner's
/// rule, recorded first, is the one that stays.
fn failed(evidence: ?*rejection.Slot, rule: rejection.Rule, ordinal: u16, subject: ?[]const u8) Error {
    rejection.record(evidence, rule, ordinal, subject);
    return error.WorkflowDefinitionSchemaInvalid;
}

const root_fields = [_][]const u8{ "schema", "id", "version", "shortcode", "invoke", "policy", "start", "resources", "steps", "subgraphs" };
const root_required = [_][]const u8{ "schema", "id", "version", "shortcode", "invoke", "policy", "start", "steps" };
const step_fields = [_][]const u8{ "use", "with", "on" };
const step_required = [_][]const u8{ "use", "on" };

fn convert(
    allocator: std.mem.Allocator,
    ordinal: u16,
    root: *definition.RawNode,
    evidence: ?*rejection.Slot,
) Error!definition.Definition {
    const map = closedMapping(root, &root_fields, &root_required) orelse return invalid();
    if (!stringEquals(field(map, "schema"), definition.schema_version)) return invalid();

    const workflow_id = workflow.WorkflowId.parse(string(field(map, "id")) orelse return invalid()) orelse return invalid();
    const version_value = integer(field(map, "version")) orelse return invalid();
    if (version_value <= 0 or version_value > std.math.maxInt(u32)) return invalid();
    const shortcode = telemetry.WorkflowShortcode.parse(string(field(map, "shortcode")) orelse return invalid()) catch return invalid();
    const invocation = workflow.OperationId.parse(string(field(map, "invoke")) orelse return invalid()) orelse return invalid();
    const policy = workflow.RegisteredRef.parse(string(field(map, "policy")) orelse return invalid()) orelse return invalid();
    const start = workflow.WorkflowStepId.parseLocal(string(field(map, "start")) orelse return invalid()) orelse return invalid();
    const resources = convertResources(allocator, field(map, "resources")) catch return failed(evidence, .resources, ordinal, null);
    const steps = convertSteps(allocator, field(map, "steps") orelse return invalid(), ordinal, evidence) catch return failed(evidence, .steps, ordinal, null);

    return .{
        .source_ordinal = ordinal,
        .workflow_id = workflow_id,
        .workflow_version = @intCast(version_value),
        .shortcode = shortcode,
        .invocation_operation_id = invocation,
        .policy_profile_id = policy,
        .start_step_id = start,
        .resources = resources,
        .steps = steps.operations,
        .calls = steps.calls,
        .subgraphs = convertSubgraphs(allocator, field(map, "subgraphs")) catch return failed(evidence, .subgraphs, ordinal, null),
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
    ordinal: u16,
    evidence: ?*rejection.Slot,
) Error!struct { operations: []const workflow.DeclarativeStep, calls: []const definition.SubgraphCall } {
    const map = mapping(raw) orelse return invalid();
    if (map.len == 0 or map.len > definition.max_steps) return invalid();
    var steps: std.ArrayList(workflow.DeclarativeStep) = .empty;
    var calls: std.ArrayList(definition.SubgraphCall) = .empty;
    for (map) |pair| {
        const id = workflow.WorkflowStepId.parseLocal(string(pair.key) orelse return invalid()) orelse return invalid();
        if (closedMapping(pair.value, &.{ "call", "with", "on" }, &.{ "call", "on" })) |call| {
            const converted = convertCall(allocator, id, call, pair.value, ordinal, evidence) catch return failed(evidence, .steps, ordinal, id.bytes);
            calls.append(allocator, converted) catch return invalid();
            continue;
        }
        const step_map = closedMapping(pair.value, &step_fields, &step_required) orelse return failed(evidence, .steps, ordinal, id.bytes);
        const converted = convertOperation(allocator, id, step_map, pair.value, ordinal, evidence) catch return failed(evidence, .steps, ordinal, id.bytes);
        steps.append(allocator, converted) catch return invalid();
    }
    std.mem.sort(workflow.DeclarativeStep, steps.items, {}, stepLessThan);
    return .{ .operations = steps.toOwnedSlice(allocator) catch return invalid(), .calls = calls.toOwnedSlice(allocator) catch return invalid() };
}

/// One step that calls a subgraph. Its parameters and outcomes are sections of their own.
fn convertCall(
    allocator: std.mem.Allocator,
    id: workflow.WorkflowStepId,
    call: []const definition.RawPair,
    value: *definition.RawNode,
    ordinal: u16,
    evidence: ?*rejection.Slot,
) Error!definition.SubgraphCall {
    return .{
        .id = id,
        .source = try sourceEntry(allocator, null, id.bytes, .subgraph, string(field(call, "call")) orelse return invalid(), value),
        .subgraph = definition.SubgraphId.parse(string(field(call, "call")) orelse return invalid()) orelse return invalid(),
        .parameters = convertParameters(allocator, field(call, "with")) catch return failed(evidence, .parameters, ordinal, id.bytes),
        .outcomes = convertOutcomes(allocator, field(call, "on") orelse return invalid()) catch return failed(evidence, .outcomes, ordinal, id.bytes),
    };
}

/// One step that runs an operation. Its parameters and outcomes are sections of their own.
fn convertOperation(
    allocator: std.mem.Allocator,
    id: workflow.WorkflowStepId,
    step_map: []const definition.RawPair,
    value: *definition.RawNode,
    ordinal: u16,
    evidence: ?*rejection.Slot,
) Error!workflow.DeclarativeStep {
    return .{
        .id = id,
        .source = try sourceEntry(allocator, null, id.bytes, .operation, string(field(step_map, "use")) orelse return invalid(), value),
        .operation_id = workflow.OperationId.parse(string(field(step_map, "use")) orelse return invalid()) orelse return invalid(),
        .parameters = convertParameters(allocator, field(step_map, "with")) catch return failed(evidence, .parameters, ordinal, id.bytes),
        .outcomes = convertOutcomes(allocator, field(step_map, "on") orelse return invalid()) catch return failed(evidence, .outcomes, ordinal, id.bytes),
    };
}

fn convertSubgraphs(allocator: std.mem.Allocator, raw: ?*definition.RawNode) Error![]const definition.Subgraph {
    const present = raw orelse return &.{};
    const map = mapping(present) orelse return invalid();
    if (map.len == 0 or map.len > definition.max_subgraphs) return invalid();
    const result = allocator.alloc(definition.Subgraph, map.len) catch return invalid();
    for (map, result) |pair, *subgraph| {
        const value = closedMapping(pair.value, &.{ "start", "steps" }, &.{ "start", "steps" }) orelse return invalid();
        const entries = mapping(field(value, "steps") orelse return invalid()) orelse return invalid();
        if (entries.len == 0 or entries.len > definition.max_steps) return invalid();
        const steps = allocator.alloc(definition.SubgraphStep, entries.len) catch return invalid();
        for (entries, steps) |entry, *step| {
            const call_map = closedMapping(entry.value, &.{ "call", "with", "on" }, &.{ "call", "on" });
            const step_map = call_map orelse closedMapping(entry.value, &step_fields, &step_required) orelse return invalid();
            var parameters: std.ArrayList(definition.SubgraphParameter) = .empty;
            if (field(step_map, "with")) |with| {
                const bindings = mapping(with) orelse return invalid();
                if (bindings.len > definition.max_parameters) return invalid();
                for (bindings) |binding| {
                    const parameter: definition.SubgraphParameter = .{
                        .id = workflow.WorkflowParameterId.parse(string(binding.key) orelse return invalid()) orelse return invalid(),
                        .value = if (binding.value.* == .mapping) value: {
                            const reference = closedMapping(binding.value, &.{"param"}, &.{"param"}) orelse return invalid();
                            break :value .{ .parameter = workflow.WorkflowParameterId.parse(string(field(reference, "param")) orelse return invalid()) orelse return invalid() };
                        } else .{ .literal = try scalarValue(binding.value) },
                    };
                    parameters.append(allocator, parameter) catch return invalid();
                }
            }
            step.* = .{
                .source = try sourceEntry(allocator, string(pair.key) orelse return invalid(), string(entry.key) orelse return invalid(), if (call_map != null) .subgraph else .operation, string(field(step_map, if (call_map != null) "call" else "use")) orelse return invalid(), entry.value),
                .id = workflow.WorkflowStepId.parseLocal(string(entry.key) orelse return invalid()) orelse return invalid(),
                .target = if (call_map != null)
                    .{ .subgraph = definition.SubgraphId.parse(string(field(step_map, "call")) orelse return invalid()) orelse return invalid() }
                else
                    .{ .operation = workflow.OperationId.parse(string(field(step_map, "use")) orelse return invalid()) orelse return invalid() },
                .parameters = parameters.toOwnedSlice(allocator) catch return invalid(),
                .outcomes = try convertOutcomes(allocator, field(step_map, "on") orelse return invalid()),
            };
        }
        subgraph.* = .{
            .id = definition.SubgraphId.parse(string(pair.key) orelse return invalid()) orelse return invalid(),
            .start = workflow.WorkflowStepId.parseLocal(string(field(value, "start")) orelse return invalid()) orelse return invalid(),
            .steps = steps,
        };
    }
    return result;
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

/// An outcome's authored spelling, as the workflow-definition schema names it.
/// A Zig tag name is not a spelling, so `needs_user` is not accepted.
fn spelling(tag: workflow.OutcomeTag) []const u8 {
    return switch (tag) {
        .ok => "ok",
        .more => "more",
        .needs_user => "needs-user",
        .invalid => "invalid",
        .blocked => "blocked",
        .failed => "failed",
        .cancelled => "cancelled",
    };
}

fn parseOutcome(value: []const u8) ?workflow.OutcomeTag {
    for (std.enums.values(workflow.OutcomeTag)) |tag| {
        if (std.mem.eql(u8, value, spelling(tag))) return tag;
    }
    return null;
}

fn parseTarget(value: []const u8) ?workflow.TransitionTarget {
    if (std.mem.startsWith(u8, value, "end.")) {
        const outcome = parseOutcome(value[4..]) orelse return null;
        return .{ .terminal = outcome };
    }
    return .{ .step = workflow.WorkflowStepId.parseLocal(value) orelse return null };
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

fn sourceEntry(a: std.mem.Allocator, subgraph: ?[]const u8, id: []const u8, kind: @FieldType(workflow_source.Entry, "kind"), target: []const u8, node: *definition.RawNode) Error!workflow_source.Entry {
    return .{ .subgraph = subgraph, .id = id, .kind = kind, .target = target, .declaration = std.json.Stringify.valueAlloc(a, try sourceJson(a, node), .{ .whitespace = .indent_2 }) catch return invalid() };
}
// Structural view of the accepted authored entry; exact YAML bytes are retained
// separately by the registry. This projection is not imported as authority.
fn sourceJson(a: std.mem.Allocator, node: *definition.RawNode) Error!std.json.Value {
    return switch (node.*) {
        .null_value => .null,
        .boolean => |v| .{ .bool = v },
        .integer => |v| .{ .number_string = std.fmt.allocPrint(a, "{d}", .{v}) catch return invalid() },
        .float => |v| .{ .float = v },
        .scalar => |v| .{ .string = v },
        .sequence => |items| block: {
            var result: std.array_list.Managed(std.json.Value) = .init(a);
            for (items) |item| result.append(try sourceJson(a, item)) catch return invalid();
            break :block .{ .array = result };
        },
        .mapping => |items| block: {
            var result: std.json.ObjectMap = .{};
            for (items) |pair| result.put(a, string(pair.key) orelse return invalid(), try sourceJson(a, pair.value)) catch return invalid();
            break :block .{ .object = result };
        },
    };
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
    if (legacy) {
        return builder.mapping(&.{
            try builder.pair("schemaVersion", try builder.scalar("1.0")),
            try builder.pair("workflowId", try builder.scalar("legacy")),
        });
    }
    return outcomeRaw(builder, "ok", "end.ok");
}

/// The concise workflow whose one step declares a single outcome transition.
fn outcomeRaw(builder: RawBuilder, outcome: []const u8, target: []const u8) !*definition.RawNode {
    const outcomes = try builder.mapping(&.{try builder.pair(outcome, try builder.scalar(target))});
    const step = try builder.mapping(&.{
        try builder.pair("use", try builder.scalar("core.noop")),
        try builder.pair("on", outcomes),
    });
    const steps = try builder.mapping(&.{try builder.pair("run", step)});
    return builder.mapping(&.{
        try builder.pair("schema", try builder.scalar("workflow/v1")),
        try builder.pair("id", try builder.scalar("arbitrary-flow")),
        try builder.pair("version", try builder.integer(1)),
        try builder.pair("shortcode", try builder.scalar("FLOW")),
        try builder.pair("invoke", try builder.scalar("core.empty-invocation")),
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
    const values = try validate(arena.allocator(), &accepted, null);
    try std.testing.expectEqualStrings("arbitrary-flow", values[0].workflow_id.bytes);
    try std.testing.expectEqualStrings("run", values[0].start_step_id.bytes);

    const rejected = [_]definition.RawDefinition{.{ .ordinal = 1, .root = try conciseRaw(builder, true) }};
    try std.testing.expectError(error.WorkflowDefinitionSchemaInvalid, validate(arena.allocator(), &rejected, null));
}

test "rejects unknown outcome and unsafe resource name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    const invalid_outcomes = try builder.mapping(&.{try builder.pair("success", try builder.scalar("end.ok"))});
    const step = try builder.mapping(&.{
        try builder.pair("use", try builder.scalar("core.noop")),
        try builder.pair("on", invalid_outcomes),
    });
    const steps = try builder.mapping(&.{try builder.pair("run", step)});
    const resources = try builder.mapping(&.{try builder.pair("prompt", try builder.scalar("../prompt.md"))});
    const root = try builder.mapping(&.{
        try builder.pair("schema", try builder.scalar("workflow/v1")),
        try builder.pair("id", try builder.scalar("bad-flow")),
        try builder.pair("version", try builder.integer(1)),
        try builder.pair("shortcode", try builder.scalar("BADF")),
        try builder.pair("invoke", try builder.scalar("core.empty-invocation")),
        try builder.pair("policy", try builder.scalar("core.capability-free@1")),
        try builder.pair("start", try builder.scalar("run")),
        try builder.pair("resources", resources),
        try builder.pair("steps", steps),
    });
    try std.testing.expectError(
        error.WorkflowDefinitionSchemaInvalid,
        validate(arena.allocator(), &.{.{ .ordinal = 1, .root = root }}, null),
    );
}

test "a schema rejection records its section, the definition and, for a step, the step" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    // An outcome key outside the schema's spelling, in the step named `run` of the definition at ordinal 4.
    var outcome: rejection.Slot = .{};
    try std.testing.expectError(
        error.WorkflowDefinitionSchemaInvalid,
        validate(arena.allocator(), &.{.{ .ordinal = 4, .root = try outcomeRaw(builder, "success", "end.ok") }}, &outcome),
    );
    try std.testing.expectEqual(rejection.Rule.outcomes, outcome.evidence.rule.?);
    try std.testing.expectEqual(@as(u16, 4), outcome.evidence.ordinal.?);
    try std.testing.expectEqualStrings("run", outcome.evidence.subject.?.text());
    // A document that fails in no section is the definition's header, and names no step.
    var header: rejection.Slot = .{};
    try std.testing.expectError(
        error.WorkflowDefinitionSchemaInvalid,
        validate(arena.allocator(), &.{.{ .ordinal = 2, .root = try conciseRaw(builder, true) }}, &header),
    );
    try std.testing.expectEqual(rejection.Rule.definition_header, header.evidence.rule.?);
    try std.testing.expectEqual(@as(u16, 2), header.evidence.ordinal.?);
    try std.testing.expect(header.evidence.subject == null);
    // An unsafe resource name is the resources section, which is read before the steps.
    const steps = try builder.mapping(&.{try builder.pair("run", try builder.mapping(&.{
        try builder.pair("use", try builder.scalar("core.noop")),
        try builder.pair("on", try builder.mapping(&.{try builder.pair("ok", try builder.scalar("end.ok"))})),
    }))});
    const root = try builder.mapping(&.{
        try builder.pair("schema", try builder.scalar("workflow/v1")),
        try builder.pair("id", try builder.scalar("bad-flow")),
        try builder.pair("version", try builder.integer(1)),
        try builder.pair("shortcode", try builder.scalar("BADF")),
        try builder.pair("invoke", try builder.scalar("core.empty-invocation")),
        try builder.pair("policy", try builder.scalar("core.capability-free@1")),
        try builder.pair("start", try builder.scalar("run")),
        try builder.pair("resources", try builder.mapping(&.{try builder.pair("prompt", try builder.scalar("../prompt.md"))})),
        try builder.pair("steps", steps),
    });
    var resources: rejection.Slot = .{};
    try std.testing.expectError(error.WorkflowDefinitionSchemaInvalid, validate(arena.allocator(), &.{.{ .ordinal = 1, .root = root }}, &resources));
    try std.testing.expectEqual(rejection.Rule.resources, resources.evidence.rule.?);
    try std.testing.expectEqual(@as(u16, 1), resources.evidence.ordinal.?);
}

test "outcome keys and terminal targets use the schema spelling, never a Zig tag name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const builder: RawBuilder = .{ .allocator = arena.allocator() };
    // workflow-definition-v1.schema.json names these outcome keys and these terminals.
    for ([_]struct { key: []const u8, target: []const u8, outcome: workflow.OutcomeTag }{
        .{ .key = "ok", .target = "end.ok", .outcome = .ok },
        .{ .key = "needs-user", .target = "end.needs-user", .outcome = .needs_user },
        .{ .key = "invalid", .target = "end.invalid", .outcome = .invalid },
        .{ .key = "blocked", .target = "end.blocked", .outcome = .blocked },
        .{ .key = "failed", .target = "end.failed", .outcome = .failed },
        .{ .key = "cancelled", .target = "end.cancelled", .outcome = .cancelled },
    }) |case| {
        const values = try validate(arena.allocator(), &.{.{ .ordinal = 1, .root = try outcomeRaw(builder, case.key, case.target) }}, null);
        const transition = values[0].steps[0].outcomes[0];
        try std.testing.expectEqual(case.outcome, transition.outcome);
        try std.testing.expectEqual(case.outcome, transition.target.terminal);
    }
    // `more` is a declared outcome key whose successor is a step, never a terminal.
    const progress = try validate(arena.allocator(), &.{.{ .ordinal = 1, .root = try outcomeRaw(builder, "more", "run") }}, null);
    try std.testing.expectEqual(workflow.OutcomeTag.more, progress[0].steps[0].outcomes[0].outcome);
    try std.testing.expect(progress[0].steps[0].outcomes[0].target == .step);
    for ([_]struct { key: []const u8, target: []const u8 }{
        .{ .key = "needs_user", .target = "end.ok" },
        .{ .key = "ok", .target = "end.needs_user" },
        .{ .key = "needs_user", .target = "end.needs_user" },
        .{ .key = "Needs-User", .target = "end.ok" },
        .{ .key = "Ok", .target = "end.ok" },
        .{ .key = "ok", .target = "end.Ok" },
    }) |case| {
        try std.testing.expectError(
            error.WorkflowDefinitionSchemaInvalid,
            validate(arena.allocator(), &.{.{ .ordinal = 1, .root = try outcomeRaw(builder, case.key, case.target) }}, null),
        );
    }
}
