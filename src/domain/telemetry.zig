const std = @import("std");

pub const WorkflowShortcode = struct {
    bytes: [4]u8,

    pub const Error = error{InvalidWorkflowShortcode};

    pub fn parse(raw: []const u8) Error!WorkflowShortcode {
        if (raw.len != 4) return error.InvalidWorkflowShortcode;
        var result: WorkflowShortcode = undefined;
        for (raw, 0..) |byte, index| {
            if (!std.ascii.isAlphanumeric(byte)) return error.InvalidWorkflowShortcode;
            result.bytes[index] = byte;
        }
        return result;
    }

    pub fn slice(self: *const WorkflowShortcode) []const u8 {
        return &self.bytes;
    }
};

pub const CanonicalLogLevel = enum {
    fatal,
    error_level,
    warning,
    info,
    debug,
    trace,

    pub fn rank(self: CanonicalLogLevel) u8 {
        return switch (self) {
            .fatal => 60,
            .error_level => 50,
            .warning => 40,
            .info => 30,
            .debug => 20,
            .trace => 10,
        };
    }

    pub fn text(self: CanonicalLogLevel) []const u8 {
        return switch (self) {
            .fatal => "fatal",
            .error_level => "error",
            .warning => "warning",
            .info => "info",
            .debug => "debug",
            .trace => "trace",
        };
    }
};

pub const EventType = enum {
    publication_prepared,
    run_started,
    run_completed,
    run_blocked,
    run_failed,
    run_cancelled,
    stage_started,
    stage_completed,
    stage_blocked,
    stage_failed,
    stage_clarification_pending,
    action_started,
    action_completed,
    action_invalid,
    action_failed,
    model_requested,
    model_completed,
    model_provider_stopped,
    model_runaway_resent,
    model_response_normalized,
    model_protocol_failed,
    model_schema_failed,
    validation_completed,
    validation_failed,
    repair_requested,
    repair_applied,
    repair_rejected,
    repair_exhausted,
    retry_admitted,
    retry_exhausted,
    review_requested,
    review_approved,
    review_rejected,
    command_started,
    command_completed,
    command_failed,
    task_started,
    task_completed,
    task_blocked,
    task_failed,
    security_denied,
    model_prompt_fragment,

    pub fn text(self: EventType) []const u8 {
        return switch (self) {
            .publication_prepared => "publication.prepared",
            .run_started => "run.started",
            .run_completed => "run.completed",
            .run_blocked => "run.blocked",
            .run_failed => "run.failed",
            .run_cancelled => "run.cancelled",
            .stage_started => "stage.started",
            .stage_completed => "stage.completed",
            .stage_blocked => "stage.blocked",
            .stage_failed => "stage.failed",
            .stage_clarification_pending => "stage.clarification_pending",
            .action_started => "action.started",
            .action_completed => "action.completed",
            .action_invalid => "action.invalid",
            .action_failed => "action.failed",
            .model_requested => "model.requested",
            .model_completed => "model.completed",
            .model_provider_stopped => "model.provider_stopped",
            .model_runaway_resent => "model.runaway_resent",
            .model_response_normalized => "model.response_normalized",
            .model_protocol_failed => "model.protocol_failed",
            .model_schema_failed => "model.schema_failed",
            .validation_completed => "validation.completed",
            .validation_failed => "validation.failed",
            .repair_requested => "repair.requested",
            .repair_applied => "repair.applied",
            .repair_rejected => "repair.rejected",
            .repair_exhausted => "repair.exhausted",
            .retry_admitted => "retry.admitted",
            .retry_exhausted => "retry.exhausted",
            .review_requested => "review.requested",
            .review_approved => "review.approved",
            .review_rejected => "review.rejected",
            .command_started => "command.started",
            .command_completed => "command.completed",
            .command_failed => "command.failed",
            .task_started => "task.started",
            .task_completed => "task.completed",
            .task_blocked => "task.blocked",
            .task_failed => "task.failed",
            .security_denied => "security.denied",
            .model_prompt_fragment => "model.prompt_fragment",
        };
    }
};

pub const EventOutcome = enum {
    completed,
    blocked,
    failed,
    cancelled,
    rejected,
    invalid,
    needs_user,
};

pub const Stage = enum { specify, plan, tasks, implement, other };
pub const EvidenceStatus = enum { present, missing, passed, failed };
pub const RepairUnitKind = enum { field, record, section, task, file_operation, authorized_unit };

pub const Identifier = struct {
    bytes: []const u8,

    pub fn validate(bytes: []const u8) ?Identifier {
        if (bytes.len == 0 or bytes.len > 128) return null;
        for (bytes) |byte| {
            if (!(std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or
                byte == '.' or byte == '@')) return null;
        }
        return .{ .bytes = bytes };
    }
};

pub const DiagnosticCode = struct {
    bytes: []const u8,

    pub fn validate(bytes: []const u8) ?DiagnosticCode {
        if (bytes.len == 0 or bytes.len > 96) return null;
        for (bytes) |byte| {
            if (!(std.ascii.isUpper(byte) or std.ascii.isDigit(byte) or byte == '_')) return null;
        }
        return .{ .bytes = bytes };
    }
};

/// The event-specific fields of F0002 section 6.2. A row names the ones it requires and the ones it
/// admits; the common fields below belong to every row.
pub const Field = enum {
    outcome,
    duration_ms,
    diagnostic_code,
    validator_id,
    rule_id,
    /// The internal step of a stage action at which a failed action stopped (ADR 0031).
    step_id,
    model_route_id,
    model_profile_id,
    input_tokens,
    output_tokens,
    repair_unit_kind,
    command_id,
    exit_code,
    count,
    task_id,
};

pub fn FieldType(comptime field: Field) type {
    return switch (field) {
        .outcome => EventOutcome,
        .duration_ms, .input_tokens, .output_tokens, .count => u64,
        .diagnostic_code => DiagnosticCode,
        .validator_id, .rule_id, .step_id, .model_route_id, .model_profile_id, .command_id, .task_id => Identifier,
        .repair_unit_kind => RepairUnitKind,
        .exit_code => i32,
    };
}

/// What every event row may carry besides its own fields (F0002 section 6.2).
pub const Common = struct {
    stage: ?Stage = null,
    node_id: ?Identifier = null,
    parent_event_id: ?Identifier = null,
    correlation_id: ?Identifier = null,
    attempt: ?u64 = null,
    evidence_status: ?EvidenceStatus = null,
};

pub const Row = struct {
    required: []const Field = &.{},
    optional: []const Field = &.{},
};

/// The closed event registry's field sets, one row per event (F0002 section 6.2). The levels and
/// emission rules of the same rows belong to `log_event_registry.zig`.
pub fn row(comptime event: EventType) Row {
    return switch (event) {
        .run_started, .stage_started, .review_requested, .model_prompt_fragment => .{},
        // Every event of one stage of a `request-model` step names the stage (ADR 0030).
        .action_started => .{ .optional = &.{.step_id} },
        .run_completed, .stage_completed => .{ .required = &.{.outcome}, .optional = &.{.duration_ms} },
        .task_completed => .{ .required = &.{ .task_id, .outcome }, .optional = &.{.duration_ms} },
        .action_completed => .{ .required = &.{.outcome}, .optional = &.{ .duration_ms, .step_id } },
        .action_invalid => .{ .required = &.{ .diagnostic_code, .outcome }, .optional = &.{.step_id} },
        .run_blocked, .run_failed, .stage_blocked => .{ .required = &.{ .diagnostic_code, .outcome } },
        .model_protocol_failed, .model_schema_failed => .{ .required = &.{ .model_route_id, .model_profile_id, .diagnostic_code, .outcome } },
        .repair_rejected, .repair_exhausted => .{ .required = &.{ .repair_unit_kind, .diagnostic_code, .outcome } },
        .task_blocked => .{ .required = &.{ .task_id, .diagnostic_code, .outcome } },
        .security_denied => .{ .required = &.{ .rule_id, .diagnostic_code, .outcome } },
        .run_cancelled, .publication_prepared, .stage_clarification_pending, .review_approved, .review_rejected => .{ .required = &.{.outcome} },
        .repair_applied => .{ .required = &.{ .repair_unit_kind, .outcome } },
        .stage_failed => .{ .required = &.{ .diagnostic_code, .outcome }, .optional = &.{.duration_ms} },
        .task_failed => .{ .required = &.{ .task_id, .diagnostic_code, .outcome }, .optional = &.{.duration_ms} },
        // A failed stage action may also name the internal step it stopped at (ADR 0031).
        .action_failed => .{ .required = &.{ .diagnostic_code, .outcome }, .optional = &.{ .duration_ms, .step_id } },
        .model_requested => .{ .required = &.{ .model_route_id, .model_profile_id } },
        .model_completed => .{ .required = &.{ .model_route_id, .model_profile_id, .outcome }, .optional = &.{ .input_tokens, .output_tokens, .duration_ms } },
        // ADR 0014 and section 22.6: every normalization is logged.
        .model_response_normalized => .{ .required = &.{ .model_route_id, .model_profile_id, .diagnostic_code } },
        // Provider-applied stops carry their exact closed reason, never only usage.
        .model_provider_stopped => .{ .required = &.{ .model_route_id, .model_profile_id, .diagnostic_code, .outcome }, .optional = &.{ .input_tokens, .output_tokens } },
        // ADR 0039: every re-send of a runaway names the attempt it repeats.
        .model_runaway_resent => .{ .required = &.{ .model_route_id, .model_profile_id, .diagnostic_code }, .optional = &.{ .input_tokens, .output_tokens } },
        .validation_completed => .{ .required = &.{ .validator_id, .outcome }, .optional = &.{ .count, .duration_ms } },
        .validation_failed => .{ .required = &.{ .validator_id, .diagnostic_code, .outcome }, .optional = &.{.count} },
        .repair_requested => .{ .required = &.{.repair_unit_kind} },
        .retry_admitted => .{ .required = &.{.count} },
        .retry_exhausted => .{ .required = &.{ .count, .diagnostic_code, .outcome } },
        .command_started => .{ .required = &.{.command_id} },
        .command_completed => .{ .required = &.{ .command_id, .outcome }, .optional = &.{ .exit_code, .duration_ms } },
        .command_failed => .{ .required = &.{ .command_id, .diagnostic_code, .outcome }, .optional = &.{ .exit_code, .duration_ms } },
        .task_started => .{ .required = &.{.task_id} },
    };
}

fn Absent(comptime T: type) type {
    return struct {
        const value: ?T = null;
    };
}

/// One event's payload: its required fields, its optional fields and the common ones, and nothing else.
pub fn Payload(comptime event: EventType) type {
    const spec = row(event);
    const common = @typeInfo(Common).@"struct".fields;
    const count = spec.required.len + spec.optional.len + common.len;
    var names: [count][:0]const u8 = undefined;
    var types: [count]type = undefined;
    var attributes: [count]std.builtin.Type.StructField.Attributes = undefined;
    var index: usize = 0;
    for (spec.required) |field| {
        names[index] = @tagName(field);
        types[index] = switch (field) {
            inline else => |named| FieldType(named),
        };
        attributes[index] = .{};
        index += 1;
    }
    for (spec.optional) |field| {
        names[index] = @tagName(field);
        types[index] = switch (field) {
            inline else => |named| ?FieldType(named),
        };
        attributes[index] = .{ .default_value_ptr = switch (field) {
            inline else => |named| &Absent(FieldType(named)).value,
        } };
        index += 1;
    }
    for (common) |field| {
        names[index] = field.name;
        types[index] = field.type;
        attributes[index] = .{ .default_value_ptr = field.default_value_ptr };
        index += 1;
    }
    return @Struct(.auto, null, &names, &types, &attributes);
}

/// One variant per event, each holding exactly that event's row (F0002 section 4). A producer states the
/// event by constructing its variant; the registry owns level, template and sensitivity. A variant of
/// `model_prompt_fragment` is representable but is never a fact: the prompt stream's content is
/// accepted only from the sanitization pipeline (`log_event_registry.validateFact`).
pub const TelemetryFact = blk: {
    const events = @typeInfo(EventType).@"enum".fields;
    var names: [events.len][:0]const u8 = undefined;
    var types: [events.len]type = undefined;
    var attributes: [events.len]std.builtin.Type.UnionField.Attributes = undefined;
    for (events, &names, &types, &attributes) |event, *name, *payload, *attribute| {
        name.* = event.name;
        payload.* = Payload(@field(EventType, event.name));
        attribute.* = .{};
    }
    break :blk @Union(.auto, EventType, &names, &types, &attributes);
};

pub fn eventOf(fact: TelemetryFact) EventType {
    return std.meta.activeTag(fact);
}

/// The common fields of the fact's row.
pub fn commonOf(fact: TelemetryFact) Common {
    switch (fact) {
        inline else => |payload| {
            var result: Common = .{};
            inline for (@typeInfo(Common).@"struct".fields) |named| @field(result, named.name) = @field(payload, named.name);
            return result;
        },
    }
}

/// The fact's value of one event-specific field: null when the event's row does not carry it, or
/// carries it unset.
pub fn fieldOf(fact: TelemetryFact, comptime which: Field) ?FieldType(which) {
    switch (fact) {
        inline else => |payload| {
            if (!@hasField(@TypeOf(payload), @tagName(which))) return null;
            return @field(payload, @tagName(which));
        },
    }
}

pub const WorkflowTelemetryFact = struct {
    workflow_shortcode: WorkflowShortcode,
    fact: TelemetryFact,
};

test "a fact reads its event, its common fields and its row, and no field outside its row" {
    const task = Identifier.validate("TASK-1").?;
    const node = Identifier.validate("node-1").?;
    const fact: TelemetryFact = .{ .task_completed = .{ .task_id = task, .outcome = .completed, .node_id = node, .attempt = 2 } };
    try std.testing.expectEqual(EventType.task_completed, eventOf(fact));
    try std.testing.expectEqualStrings("TASK-1", fieldOf(fact, .task_id).?.bytes);
    try std.testing.expectEqual(EventOutcome.completed, fieldOf(fact, .outcome).?);
    // An admitted field left unset, and a field the row does not carry, are both absent.
    try std.testing.expectEqual(@as(?u64, null), fieldOf(fact, .duration_ms));
    try std.testing.expectEqual(@as(?Identifier, null), fieldOf(fact, .command_id));
    const common = commonOf(fact);
    try std.testing.expectEqualStrings("node-1", common.node_id.?.bytes);
    try std.testing.expectEqual(@as(?u64, 2), common.attempt);
    try std.testing.expectEqual(@as(?Identifier, null), common.correlation_id);
    try std.testing.expectEqual(EventType.run_started, eventOf(.{ .run_started = .{} }));
}

test "workflow shortcodes preserve exactly four ASCII alphanumeric bytes" {
    const shortcode = try WorkflowShortcode.parse("ImP1");
    try std.testing.expectEqualStrings("ImP1", shortcode.slice());
    try std.testing.expectError(error.InvalidWorkflowShortcode, WorkflowShortcode.parse("ABC"));
    try std.testing.expectError(error.InvalidWorkflowShortcode, WorkflowShortcode.parse("AB-C"));
}
