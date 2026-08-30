const std = @import("std");

pub const max_facts_per_delta: usize = 32;

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
    model_protocol_failed,
    model_schema_failed,
    validation_completed,
    validation_failed,
    repair_requested,
    repair_applied,
    repair_rejected,
    repair_exhausted,
    review_requested,
    review_approved,
    review_rejected,
    transaction_prepared,
    transaction_applying,
    transaction_committed,
    transaction_rolled_back,
    transaction_recovered,
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
            .model_protocol_failed => "model.protocol_failed",
            .model_schema_failed => "model.schema_failed",
            .validation_completed => "validation.completed",
            .validation_failed => "validation.failed",
            .repair_requested => "repair.requested",
            .repair_applied => "repair.applied",
            .repair_rejected => "repair.rejected",
            .repair_exhausted => "repair.exhausted",
            .review_requested => "review.requested",
            .review_approved => "review.approved",
            .review_rejected => "review.rejected",
            .transaction_prepared => "transaction.prepared",
            .transaction_applying => "transaction.applying",
            .transaction_committed => "transaction.committed",
            .transaction_rolled_back => "transaction.rolled_back",
            .transaction_recovered => "transaction.recovered",
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
pub const RepairUnitKind = enum { field, record, section, task, file_operation };

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

pub const TelemetryFields = struct {
    outcome: ?EventOutcome = null,
    duration_ms: ?u64 = null,
    diagnostic_code: ?DiagnosticCode = null,
    validator_id: ?Identifier = null,
    transaction_id: ?Identifier = null,
    rule_id: ?Identifier = null,
    model_route_id: ?Identifier = null,
    model_profile_id: ?Identifier = null,
    input_tokens: ?u64 = null,
    output_tokens: ?u64 = null,
    repair_unit_kind: ?RepairUnitKind = null,
    command_id: ?Identifier = null,
    exit_code: ?i32 = null,
    evidence_status: ?EvidenceStatus = null,
    count: ?u64 = null,
    task_id: ?Identifier = null,
};

pub const TelemetryFact = struct {
    event_type: EventType,
    stage: ?Stage = null,
    node_id: ?Identifier = null,
    parent_event_id: ?Identifier = null,
    correlation_id: ?Identifier = null,
    attempt: ?u64 = null,
    fields: TelemetryFields = .{},
};

pub const WorkflowTelemetryFact = struct {
    workflow_shortcode: WorkflowShortcode,
    fact: TelemetryFact,
};

test "workflow shortcodes preserve exactly four ASCII alphanumeric bytes" {
    const shortcode = try WorkflowShortcode.parse("ImP1");
    try std.testing.expectEqualStrings("ImP1", shortcode.slice());
    try std.testing.expectError(error.InvalidWorkflowShortcode, WorkflowShortcode.parse("ABC"));
    try std.testing.expectError(error.InvalidWorkflowShortcode, WorkflowShortcode.parse("AB-C"));
}
