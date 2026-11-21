const std = @import("std");
const telemetry = @import("telemetry.zig");

pub const Error = error{InvalidLogEventFact};

pub const Field = enum {
    outcome,
    duration_ms,
    diagnostic_code,
    validator_id,
    rule_id,
    step_id,
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

/// Whether the configured threshold may drop an event. An event an ADR requires to be
/// logged is emitted at every threshold (§26.5), so a normalized response, a provider
/// stop or a runaway re-send never goes unrecorded.
pub const Emission = enum { threshold, always };

/// What a row of the event may carry (F0002 section 6): the event stream's metadata fields are all public
/// metadata, and only the prompt stream's content is sanitized content. The registry, not the caller, owns it.
pub const Sensitivity = enum { public_metadata, sanitized_content };

pub const EventDefinition = struct {
    event_type: telemetry.EventType,
    level: telemetry.CanonicalLogLevel,
    emission: Emission = .threshold,
    sensitivity: Sensitivity = .public_metadata,
    required: FieldSet,
    optional: FieldSet,

    pub fn templateId(self: EventDefinition, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "{s}/v1", .{self.event_type.text()});
    }
};

pub fn eventDefinition(event_type: telemetry.EventType) EventDefinition {
    const none = FieldSet.initEmpty();
    return switch (event_type) {
        .run_started, .stage_started, .review_requested => definition(event_type, level(event_type), &.{}, &.{}),
        // Every event of one stage of a `request-model` step names the stage (ADR 0030).
        .action_started => definition(event_type, level(event_type), &.{}, &.{.step_id}),
        .run_completed, .stage_completed => definition(event_type, level(event_type), &.{.outcome}, &.{.duration_ms}),
        .task_completed => definition(event_type, level(event_type), &.{ .task_id, .outcome }, &.{.duration_ms}),
        .action_completed => definition(event_type, level(event_type), &.{.outcome}, &.{ .duration_ms, .step_id }),
        .action_invalid => definition(event_type, level(event_type), &.{ .diagnostic_code, .outcome }, &.{.step_id}),
        .run_blocked,
        .run_failed,
        .stage_blocked,
        .model_protocol_failed,
        .model_schema_failed,
        .repair_rejected,
        .repair_exhausted,
        .task_blocked,
        .security_denied,
        => definitionForFailure(event_type),
        .run_cancelled,
        .publication_prepared,
        .stage_clarification_pending,
        .review_approved,
        .review_rejected,
        => definition(event_type, level(event_type), &.{.outcome}, &.{}),
        .repair_applied => definition(event_type, level(event_type), &.{ .repair_unit_kind, .outcome }, &.{}),
        .stage_failed => definition(event_type, level(event_type), &.{ .diagnostic_code, .outcome }, &.{.duration_ms}),
        .task_failed => definition(event_type, level(event_type), &.{ .task_id, .diagnostic_code, .outcome }, &.{.duration_ms}),
        // A failed stage action may also name the internal step it stopped at (ADR 0031), and any
        // action event of a `request-model` stage names the stage (ADR 0030).
        .action_failed => definition(event_type, level(event_type), &.{ .diagnostic_code, .outcome }, &.{ .duration_ms, .step_id }),
        .model_requested => definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id }, &.{}),
        .model_completed => definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id, .outcome }, &.{ .input_tokens, .output_tokens, .duration_ms }),
        // ADR 0014 and section 22.6: every normalization is logged.
        .model_response_normalized => adrRequired(definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id, .diagnostic_code }, &.{})),
        // Provider-applied stops carry their exact closed reason, never only usage.
        .model_provider_stopped => adrRequired(definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id, .diagnostic_code, .outcome }, &.{ .input_tokens, .output_tokens })),
        // ADR 0039: every re-send of a runaway names the attempt it repeats.
        .model_runaway_resent => adrRequired(definition(event_type, level(event_type), &.{ .model_route_id, .model_profile_id, .diagnostic_code }, &.{ .input_tokens, .output_tokens })),
        .validation_completed => definition(event_type, level(event_type), &.{ .validator_id, .outcome }, &.{ .count, .duration_ms }),
        .validation_failed => definition(event_type, level(event_type), &.{ .validator_id, .diagnostic_code, .outcome }, &.{.count}),
        .repair_requested => definition(event_type, level(event_type), &.{.repair_unit_kind}, &.{}),
        .retry_admitted => definition(event_type, level(event_type), &.{.count}, &.{}),
        .retry_exhausted => definition(event_type, level(event_type), &.{ .count, .diagnostic_code, .outcome }, &.{}),
        .command_started => definition(event_type, level(event_type), &.{.command_id}, &.{}),
        .command_completed => definition(event_type, level(event_type), &.{ .command_id, .outcome }, &.{ .exit_code, .duration_ms }),
        .command_failed => definition(event_type, level(event_type), &.{ .command_id, .diagnostic_code, .outcome }, &.{ .exit_code, .duration_ms }),
        .task_started => definition(event_type, level(event_type), &.{.task_id}, &.{}),
        // A prompt fragment is the prompt stream's content, never an event-stream metadata row.
        .model_prompt_fragment => .{ .event_type = event_type, .level = level(event_type), .sensitivity = .sanitized_content, .required = none, .optional = none },
    };
}

pub fn validateFact(fact: telemetry.TelemetryFact) Error!EventDefinition {
    const event_definition = eventDefinition(fact.event_type);
    if (event_definition.sensitivity != .public_metadata) return error.InvalidLogEventFact;
    const actual = fieldSet(fact.fields);
    if (!actual.supersetOf(event_definition.required)) return error.InvalidLogEventFact;
    var allowed = event_definition.required;
    allowed.setUnion(event_definition.optional);
    // F0002 section 6: the evidence status is common to every event row.
    allowed.insert(.evidence_status);
    if (!allowed.supersetOf(actual)) return error.InvalidLogEventFact;
    return event_definition;
}

/// Marks an event an ADR requires to be logged (ADR 0011, 0014 and 0039); the
/// threshold never drops it (§26.5).
fn adrRequired(event_definition: EventDefinition) EventDefinition {
    var result = event_definition;
    result.emission = .always;
    return result;
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
        .run_blocked, .run_failed, .stage_blocked, .stage_failed, .action_failed, .repair_exhausted, .retry_exhausted, .command_failed, .task_failed => .error_level,
        .action_invalid, .model_protocol_failed, .model_schema_failed, .model_provider_stopped, .model_runaway_resent, .model_response_normalized, .validation_failed, .repair_rejected, .review_rejected, .task_blocked, .security_denied => .warning,
        .action_started, .action_completed, .model_requested, .model_completed, .validation_completed, .repair_requested, .retry_admitted, .command_started, .command_completed, .model_prompt_fragment => .debug,
        .publication_prepared, .run_started, .run_completed, .run_cancelled, .stage_started, .stage_completed, .stage_clarification_pending, .repair_applied, .review_requested, .review_approved, .task_started, .task_completed => .info,
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

test "repair.applied names its repair unit, and task.completed and task.failed name their task (F0002 section 6)" {
    const task = telemetry.Identifier.validate("TASK-1");
    const code = telemetry.DiagnosticCode.validate("TASK_FAILED");
    _ = try validateFact(.{ .event_type = .repair_applied, .fields = .{ .repair_unit_kind = .authorized_unit, .outcome = .completed } });
    try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{ .event_type = .repair_applied, .fields = .{ .outcome = .completed } }));
    _ = try validateFact(.{ .event_type = .task_completed, .fields = .{ .task_id = task, .outcome = .completed } });
    try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{ .event_type = .task_completed, .fields = .{ .outcome = .completed } }));
    _ = try validateFact(.{ .event_type = .task_failed, .fields = .{ .task_id = task, .diagnostic_code = code, .outcome = .failed } });
    try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{ .event_type = .task_failed, .fields = .{ .diagnostic_code = code, .outcome = .failed } }));
    // The run and stage events that shared those rows keep theirs.
    _ = try validateFact(.{ .event_type = .run_completed, .fields = .{ .outcome = .completed } });
    _ = try validateFact(.{ .event_type = .stage_failed, .fields = .{ .diagnostic_code = code, .outcome = .failed } });
}

test "the evidence status is common to every event, and no other field is" {
    for (std.enums.values(telemetry.EventType)) |event_type| {
        if (eventDefinition(event_type).sensitivity != .public_metadata) continue;
        const definition_fields = eventDefinition(event_type);
        var fields: telemetry.TelemetryFields = .{};
        // Build the event's required fields from its definition, then add the common one.
        var required = definition_fields.required.iterator();
        while (required.next()) |field| switch (field) {
            .outcome => fields.outcome = .completed,
            .duration_ms => fields.duration_ms = 1,
            .diagnostic_code => fields.diagnostic_code = telemetry.DiagnosticCode.validate("CODE"),
            .validator_id => fields.validator_id = telemetry.Identifier.validate("V-1"),
            .rule_id => fields.rule_id = telemetry.Identifier.validate("R-1"),
            .step_id => fields.step_id = telemetry.Identifier.validate("S-1"),
            .model_route_id => fields.model_route_id = telemetry.Identifier.validate("ROUTE-1"),
            .model_profile_id => fields.model_profile_id = telemetry.Identifier.validate("PROFILE-1"),
            .input_tokens => fields.input_tokens = 1,
            .output_tokens => fields.output_tokens = 1,
            .repair_unit_kind => fields.repair_unit_kind = .authorized_unit,
            .command_id => fields.command_id = telemetry.Identifier.validate("CMD-1"),
            .exit_code => fields.exit_code = 0,
            .evidence_status => fields.evidence_status = .present,
            .count => fields.count = 1,
            .task_id => fields.task_id = telemetry.Identifier.validate("TASK-1"),
        };
        _ = try validateFact(.{ .event_type = event_type, .fields = fields });
        fields.evidence_status = .present;
        _ = try validateFact(.{ .event_type = event_type, .fields = fields });
        // A field that is neither required, optional nor common is still refused.
        if (!definition_fields.required.contains(.exit_code) and !definition_fields.optional.contains(.exit_code)) {
            fields.exit_code = 0;
            try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{ .event_type = event_type, .fields = fields }));
        }
    }
}

test "only the prompt fragment is sanitized content, and the event stream admits public metadata alone" {
    for (std.enums.values(telemetry.EventType)) |event_type| {
        const expected: Sensitivity = if (event_type == .model_prompt_fragment) .sanitized_content else .public_metadata;
        try std.testing.expectEqual(expected, eventDefinition(event_type).sensitivity);
    }
    try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{ .event_type = .model_prompt_fragment }));
}

test "every event has the level its class states, and its definition carries that level" {
    const Level = telemetry.CanonicalLogLevel;
    var listed: usize = 0;
    for ([_]struct { Level, []const telemetry.EventType }{
        .{ .error_level, &.{ .run_blocked, .run_failed, .stage_blocked, .stage_failed, .action_failed, .repair_exhausted, .retry_exhausted, .command_failed, .task_failed } },
        .{ .warning, &.{ .action_invalid, .model_protocol_failed, .model_schema_failed, .model_provider_stopped, .model_runaway_resent, .model_response_normalized, .validation_failed, .repair_rejected, .review_rejected, .task_blocked, .security_denied } },
        .{ .debug, &.{ .action_started, .action_completed, .model_requested, .model_completed, .validation_completed, .repair_requested, .retry_admitted, .command_started, .command_completed, .model_prompt_fragment } },
        .{ .info, &.{ .publication_prepared, .run_started, .run_completed, .run_cancelled, .stage_started, .stage_completed, .stage_clarification_pending, .repair_applied, .review_requested, .review_approved, .task_started, .task_completed } },
    }) |class| {
        for (class[1]) |event_type| {
            try std.testing.expectEqual(class[0], level(event_type));
            try std.testing.expectEqual(class[0], eventDefinition(event_type).level);
            listed += 1;
        }
    }
    // The four classes list every event once.
    try std.testing.expectEqual(std.enums.values(telemetry.EventType).len, listed);
}

test "exactly the events an ADR requires are always emitted" {
    const required = [_]telemetry.EventType{ .model_response_normalized, .model_provider_stopped, .model_runaway_resent };
    for (std.enums.values(telemetry.EventType)) |event_type| {
        const expected: Emission = if (std.mem.indexOfScalar(telemetry.EventType, &required, event_type) != null) .always else .threshold;
        try std.testing.expectEqual(expected, eventDefinition(event_type).emission);
    }
}
