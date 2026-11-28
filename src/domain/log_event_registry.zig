const std = @import("std");
const telemetry = @import("telemetry.zig");

pub const Error = error{InvalidLogEventFact};

/// Whether the configured threshold may drop an event. An event an ADR requires to be
/// logged is emitted at every threshold (§26.5), so a normalized response, a provider
/// stop or a runaway re-send never goes unrecorded.
pub const Emission = enum { threshold, always };

/// What a row of the event may carry (F0002 section 6): the event stream's metadata fields are all public
/// metadata, and only the prompt stream's content is sanitized content. The registry, not the caller, owns it.
pub const Sensitivity = enum { public_metadata, sanitized_content };

/// An event's level, emission and sensitivity. Its fields are the variant of `telemetry.TelemetryFact`
/// that names it ([row](telemetry.zig)).
pub const EventDefinition = struct {
    event_type: telemetry.EventType,
    level: telemetry.CanonicalLogLevel,
    emission: Emission = .threshold,
    sensitivity: Sensitivity = .public_metadata,

    pub fn templateId(self: EventDefinition, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "{s}/v1", .{self.event_type.text()});
    }
};

pub fn eventDefinition(event_type: telemetry.EventType) EventDefinition {
    return .{
        .event_type = event_type,
        .level = level(event_type),
        .emission = switch (event_type) {
            // ADR 0011, 0014 and 0039 require these events at every threshold (§26.5).
            .model_response_normalized, .model_provider_stopped, .model_runaway_resent => .always,
            else => .threshold,
        },
        // A prompt fragment is the prompt stream's content, never an event-stream metadata row.
        .sensitivity = if (event_type == .model_prompt_fragment) .sanitized_content else .public_metadata,
    };
}

/// The one registered definition of a fact's event. The fact's fields are its variant's row, so the
/// event stream needs only to refuse the event whose content is not public metadata.
pub fn validateFact(fact: telemetry.TelemetryFact) Error!EventDefinition {
    const event_definition = eventDefinition(telemetry.eventOf(fact));
    if (event_definition.sensitivity != .public_metadata) return error.InvalidLogEventFact;
    return event_definition;
}

fn level(event_type: telemetry.EventType) telemetry.CanonicalLogLevel {
    return switch (event_type) {
        .run_blocked, .run_failed, .stage_blocked, .stage_failed, .action_failed, .repair_exhausted, .retry_exhausted, .command_failed, .task_failed => .error_level,
        .action_invalid, .model_protocol_failed, .model_schema_failed, .model_provider_stopped, .model_runaway_resent, .model_response_normalized, .validation_failed, .repair_rejected, .review_rejected, .task_blocked, .security_denied => .warning,
        .action_started, .action_completed, .model_requested, .model_completed, .validation_completed, .repair_requested, .retry_admitted, .command_started, .command_completed, .model_prompt_fragment => .debug,
        .publication_prepared, .run_started, .run_completed, .run_cancelled, .stage_started, .stage_completed, .stage_clarification_pending, .repair_applied, .review_requested, .review_approved, .task_started, .task_completed => .info,
    };
}

fn listed(comptime fields: []const telemetry.Field, comptime field: telemetry.Field) bool {
    for (fields) |candidate| if (candidate == field) return true;
    return false;
}

test "every event's payload holds its required fields, its optional fields and the common ones, and nothing else" {
    @setEvalBranchQuota(100_000);
    const common = @typeInfo(telemetry.Common).@"struct".fields;
    inline for (std.enums.values(telemetry.EventType)) |event_type| {
        const spec = comptime telemetry.row(event_type);
        const Payload = telemetry.Payload(event_type);
        inline for (std.enums.values(telemetry.Field)) |field| {
            const required = comptime listed(spec.required, field);
            const optional = comptime listed(spec.optional, field);
            // A row never names a field as both required and optional.
            try std.testing.expect(!(required and optional));
            try std.testing.expectEqual(required or optional, @hasField(Payload, @tagName(field)));
            if (required) try std.testing.expect(@FieldType(Payload, @tagName(field)) == telemetry.FieldType(field));
            if (optional) try std.testing.expect(@FieldType(Payload, @tagName(field)) == ?telemetry.FieldType(field));
        }
        // F0002 section 6.2: every event row may carry the common fields, each optional.
        inline for (common) |named| try std.testing.expect(@FieldType(Payload, named.name) == named.type);
        try std.testing.expectEqual(spec.required.len + spec.optional.len + common.len, @typeInfo(Payload).@"struct".fields.len);
    }
}

test "rows state the fields F0002 section 6.2 gives them" {
    const Identifier = telemetry.Identifier;
    // task.started names its task and no command.
    try std.testing.expect(@FieldType(telemetry.Payload(.task_started), "task_id") == Identifier);
    try std.testing.expect(!@hasField(telemetry.Payload(.task_started), "command_id"));
    // repair.applied requires its repair unit; the run and stage events that shared its row keep theirs.
    try std.testing.expect(@FieldType(telemetry.Payload(.repair_applied), "repair_unit_kind") == telemetry.RepairUnitKind);
    try std.testing.expect(!@hasField(telemetry.Payload(.run_completed), "repair_unit_kind"));
    // task.completed and task.failed require their task; run.completed and stage.failed carry none.
    try std.testing.expect(@FieldType(telemetry.Payload(.task_completed), "task_id") == Identifier);
    try std.testing.expect(@FieldType(telemetry.Payload(.task_failed), "task_id") == Identifier);
    try std.testing.expect(!@hasField(telemetry.Payload(.run_completed), "task_id"));
    try std.testing.expect(!@hasField(telemetry.Payload(.stage_failed), "task_id"));
    // run.completed requires an outcome and admits a duration; stage.failed also requires its code.
    try std.testing.expect(@FieldType(telemetry.Payload(.run_completed), "outcome") == telemetry.EventOutcome);
    try std.testing.expect(@FieldType(telemetry.Payload(.run_completed), "duration_ms") == ?u64);
    try std.testing.expect(@FieldType(telemetry.Payload(.stage_failed), "diagnostic_code") == telemetry.DiagnosticCode);
    // A command's exit code is optional, and only a command row carries it.
    try std.testing.expect(@FieldType(telemetry.Payload(.command_completed), "exit_code") == ?i32);
    try std.testing.expect(!@hasField(telemetry.Payload(.task_started), "exit_code"));
    // A failed validation may name its rule; a security denial requires one; no action or run row carries one.
    try std.testing.expect(@FieldType(telemetry.Payload(.validation_failed), "rule_id") == ?Identifier);
    try std.testing.expect(@FieldType(telemetry.Payload(.security_denied), "rule_id") == Identifier);
    try std.testing.expect(!@hasField(telemetry.Payload(.validation_completed), "rule_id"));
    try std.testing.expect(!@hasField(telemetry.Payload(.action_failed), "rule_id"));
    try std.testing.expect(!@hasField(telemetry.Payload(.run_failed), "rule_id"));
}

test "only the prompt fragment is sanitized content, and the event stream admits public metadata alone" {
    for (std.enums.values(telemetry.EventType)) |event_type| {
        const expected: Sensitivity = if (event_type == .model_prompt_fragment) .sanitized_content else .public_metadata;
        try std.testing.expectEqual(expected, eventDefinition(event_type).sensitivity);
    }
    try std.testing.expectError(error.InvalidLogEventFact, validateFact(.{ .model_prompt_fragment = .{} }));
    const task = telemetry.Identifier.validate("TASK-1").?;
    _ = try validateFact(.{ .task_started = .{ .task_id = task } });
}

test "every event has the level its class states, and its definition carries that level" {
    const Level = telemetry.CanonicalLogLevel;
    var listed_events: usize = 0;
    for ([_]struct { Level, []const telemetry.EventType }{
        .{ .error_level, &.{ .run_blocked, .run_failed, .stage_blocked, .stage_failed, .action_failed, .repair_exhausted, .retry_exhausted, .command_failed, .task_failed } },
        .{ .warning, &.{ .action_invalid, .model_protocol_failed, .model_schema_failed, .model_provider_stopped, .model_runaway_resent, .model_response_normalized, .validation_failed, .repair_rejected, .review_rejected, .task_blocked, .security_denied } },
        .{ .debug, &.{ .action_started, .action_completed, .model_requested, .model_completed, .validation_completed, .repair_requested, .retry_admitted, .command_started, .command_completed, .model_prompt_fragment } },
        .{ .info, &.{ .publication_prepared, .run_started, .run_completed, .run_cancelled, .stage_started, .stage_completed, .stage_clarification_pending, .repair_applied, .review_requested, .review_approved, .task_started, .task_completed } },
    }) |class| {
        for (class[1]) |event_type| {
            try std.testing.expectEqual(class[0], level(event_type));
            try std.testing.expectEqual(class[0], eventDefinition(event_type).level);
            listed_events += 1;
        }
    }
    // The four classes list every event once.
    try std.testing.expectEqual(std.enums.values(telemetry.EventType).len, listed_events);
}

test "exactly the events an ADR requires are always emitted" {
    const required = [_]telemetry.EventType{ .model_response_normalized, .model_provider_stopped, .model_runaway_resent };
    for (std.enums.values(telemetry.EventType)) |event_type| {
        const expected: Emission = if (std.mem.indexOfScalar(telemetry.EventType, &required, event_type) != null) .always else .threshold;
        try std.testing.expectEqual(expected, eventDefinition(event_type).emission);
    }
}
