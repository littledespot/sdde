const std = @import("std");
const telemetry = @import("telemetry.zig");

pub const Error = error{InvalidLogEventFact};

pub const Field = enum {
    outcome,
    duration_ms,
    diagnostic_code,
    validator_id,
    rule_id,
    model_route_id,
    model_profile_id,
    input_tokens,
    output_tokens,
    repair_unit_kind,
    command_id,
    exit_code,
    evidence_status,
    count,
    task_id,
};

pub const FieldSet = std.EnumSet(Field);

pub const EventDefinition = struct {
    event_type: telemetry.EventType,
    level: telemetry.CanonicalLogLevel,
    required: FieldSet,
    optional: FieldSet,

    pub fn templateId(self: EventDefinition, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "{s}/v1", .{self.event_type.text()});
    }
};

pub fn eventDefinition(event_type: telemetry.EventType) EventDefinition {
    const none = FieldSet.initEmpty();
    return switch (event_type) {
        .run_started, .stage_started, .action_started, .review_requested => definition(event_type, level(event_type), &.{}, &.{}),
        .run_completed, .stage_completed, .action_completed, .task_completed => definition(event_type, level(event_type), &.{.outcome}, &.{.duration_ms}),
        .run_blocked,
        .run_failed,
        .stage_blocked,
        .action_invalid,
        .model_protocol_failed,
        .model_schema_failed,
        .repair_rejected,
        .repair_exhausted,
        .task_blocked,
        .security_denied,
        => definitionForFailure(event_type),
        .run_cancelled,
        .stage_clarification_pending,
        .repair_applied,
        .review_approved,
        .review_rejected,
        => definition(event_type, level(event_type), &.{.outcome}, &.{}),
        .stage_failed, .action_failed, .task_failed => definition(event_type, level(event_type), &.{ .diagnostic_code, .outcome }, &.{.duration_ms}),
        .model_requested => definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id }, &.{}),
        .model_completed => definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id, .outcome }, &.{ .input_tokens, .output_tokens, .duration_ms }),
        .validation_completed => definition(event_type, level(event_type), &.{ .validator_id, .outcome }, &.{ .count, .duration_ms }),
        .validation_failed => definition(event_type, level(event_type), &.{ .validator_id, .diagnostic_code, .outcome }, &.{.count}),
        .repair_requested => definition(event_type, level(event_type), &.{.repair_unit_kind}, &.{}),
        .command_started => definition(event_type, level(event_type), &.{.command_id}, &.{}),
        .command_completed => definition(event_type, level(event_type), &.{ .command_id, .outcome }, &.{ .exit_code, .duration_ms }),
        .command_failed => definition(event_type, level(event_type), &.{ .command_id, .diagnostic_code, .outcome }, &.{ .exit_code, .duration_ms }),
        .task_started => definition(event_type, level(event_type), &.{.task_id}, &.{}),
        .model_prompt_fragment => .{ .event_type = event_type, .level = .debug, .required = none, .optional = none },
    };
}

pub fn validateFact(fact: telemetry.TelemetryFact) Error!EventDefinition {
    if (fact.event_type == .model_prompt_fragment) return error.InvalidLogEventFact;
    const event_definition = eventDefinition(fact.event_type);
    const actual = fieldSet(fact.fields);
    if (!actual.supersetOf(event_definition.required)) return error.InvalidLogEventFact;
    var allowed = event_definition.required;
    allowed.setUnion(event_definition.optional);
    if (!allowed.supersetOf(actual)) return error.InvalidLogEventFact;
    return event_definition;
}

fn definitionForFailure(event_type: telemetry.EventType) EventDefinition {
    return switch (event_type) {
        .model_protocol_failed, .model_schema_failed => definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id, .diagnostic_code, .outcome }, &.{}),
        .repair_rejected, .repair_exhausted => definition(event_type, level(event_type), &.{ .repair_unit_kind, .diagnostic_code, .outcome }, &.{}),
        .task_blocked => definition(event_type, level(event_type), &.{ .task_id, .diagnostic_code, .outcome }, &.{}),
        .security_denied => definition(event_type, level(event_type), &.{ .rule_id, .diagnostic_code, .outcome }, &.{}),
        else => definition(event_type, level(event_type), &.{ .diagnostic_code, .outcome }, &.{}),
    };
}

fn definition(
    event_type: telemetry.EventType,
    event_level: telemetry.CanonicalLogLevel,
    required: []const Field,
    optional: []const Field,
) EventDefinition {
    var required_set = FieldSet.initEmpty();
    var optional_set = FieldSet.initEmpty();
    for (required) |field| required_set.insert(field);
    for (optional) |field| optional_set.insert(field);
    return .{ .event_type = event_type, .level = event_level, .required = required_set, .optional = optional_set };
}

fn level(event_type: telemetry.EventType) telemetry.CanonicalLogLevel {
    return switch (event_type) {
        .run_blocked, .run_failed, .stage_blocked, .stage_failed, .action_failed, .repair_exhausted, .command_failed, .task_failed => .error_level,
        .action_invalid, .model_protocol_failed, .model_schema_failed, .validation_failed, .repair_rejected, .review_rejected, .task_blocked, .security_denied => .warning,
        .action_started, .action_completed, .model_requested, .model_completed, .validation_completed, .repair_requested, .command_started, .command_completed, .model_prompt_fragment => .debug,
        else => .info,
    };
}

fn fieldSet(fields: telemetry.TelemetryFields) FieldSet {
    var result = FieldSet.initEmpty();
    inline for (@typeInfo(telemetry.TelemetryFields).@"struct".fields) |field| {
        if (@field(fields, field.name) != null) result.insert(@field(Field, field.name));
    }
    return result;
}

test "closed event registry validates required and unexpected fields" {
    _ = try validateFact(.{
        .event_type = .task_started,
        .fields = .{ .task_id = telemetry.Identifier.validate("TASK-1") },
    });
    try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{ .event_type = .task_started }));
    try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{
        .event_type = .task_started,
        .fields = .{
            .task_id = telemetry.Identifier.validate("TASK-1"),
            .command_id = telemetry.Identifier.validate("CMD-1"),
        },
    }));
}
