const std = @import("std");
const config = @import("config.zig");
const telemetry = @import("telemetry.zig");

pub const schema_version = "feature-log/v2";
pub const event_column_schema_id = "event-columns/v2";
pub const prompt_column_schema_id = "prompt-columns/v2";
pub const event_registry_id = "feature-log-events/poc-v2";
pub const redaction_policy_id = "redaction/default-v1";

pub const max_record_bytes: usize = 65_536;
pub const max_segment_bytes: usize = 8_388_608;
pub const max_segments: u8 = 16;
pub const retention_days: u8 = 14;
pub const retention_period_ms: u64 = @as(u64, retention_days) * 24 * 60 * 60 * 1000;
pub const lower_level_flush_records: u8 = 32;
pub const lower_level_flush_interval_ms: u16 = 1000;
pub const max_prompt_content_bytes: usize = 5000;
pub const stream_lock_deadline_ms: u16 = 2000;
pub const stream_lock_attempt_count: u8 = 1;
pub const emergency_max_ascii_bytes: usize = 128;

pub const AliasEvidence = enum { none, critical_to_fatal, warn_to_warning };

pub const CanonicalizedLevel = struct {
    threshold: telemetry.CanonicalLogLevel,
    alias_evidence: AliasEvidence,
    source: []const u8 = "",
};

pub const Error = error{InvalidLoggingPolicy};

pub fn canonicalizeConfiguredLevel(raw: []const u8) Error!CanonicalizedLevel {
    if (std.ascii.eqlIgnoreCase(raw, "fatal")) return canonicalizedLevel(raw, .fatal, .none);
    if (std.ascii.eqlIgnoreCase(raw, "critical")) return canonicalizedLevel(raw, .fatal, .critical_to_fatal);
    if (std.ascii.eqlIgnoreCase(raw, "error")) return canonicalizedLevel(raw, .error_level, .none);
    if (std.ascii.eqlIgnoreCase(raw, "warning")) return canonicalizedLevel(raw, .warning, .none);
    if (std.ascii.eqlIgnoreCase(raw, "warn")) return canonicalizedLevel(raw, .warning, .warn_to_warning);
    if (std.ascii.eqlIgnoreCase(raw, "info")) return canonicalizedLevel(raw, .info, .none);
    if (std.ascii.eqlIgnoreCase(raw, "debug")) return canonicalizedLevel(raw, .debug, .none);
    if (std.ascii.eqlIgnoreCase(raw, "trace")) return canonicalizedLevel(raw, .trace, .none);
    return error.InvalidLoggingPolicy;
}

fn canonicalizedLevel(raw: []const u8, threshold: telemetry.CanonicalLogLevel, evidence: AliasEvidence) CanonicalizedLevel {
    return .{ .threshold = threshold, .alias_evidence = evidence, .source = raw };
}

pub const CompiledLoggingPolicy = struct {
    level: CanonicalizedLevel,
    console: bool,
    prompt_capture: []const config.PromptCapture,
    timestamp_enabled: bool = true,
    file_enabled: bool = true,
    max_record_bytes: usize = max_record_bytes,
    max_segment_bytes: usize = max_segment_bytes,
    max_segments: u8 = max_segments,
    retention_days: u8 = retention_days,
    flush_at_or_above: telemetry.CanonicalLogLevel = .error_level,
    lower_level_flush_records: u8 = lower_level_flush_records,
    lower_level_flush_interval_ms: u16 = lower_level_flush_interval_ms,
    max_prompt_content_bytes: usize = max_prompt_content_bytes,
    stream_lock_deadline_ms: u16 = stream_lock_deadline_ms,
    stream_lock_attempt_count: u8 = stream_lock_attempt_count,
};

pub const Owner = opaque {};

const OwnerStorage = struct {
    backing_allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    policy: CompiledLoggingPolicy,
};

pub fn createValidated(
    allocator: std.mem.Allocator,
    logs: config.LogsConfig,
    canonicalized: CanonicalizedLevel,
) Error!*Owner {
    if (!std.mem.eql(u8, logs.level, canonicalized.source) or
        logs.promptCapture.len > @typeInfo(config.PromptCapture).@"enum".fields.len)
    {
        return error.InvalidLoggingPolicy;
    }
    var has_direction = false;
    for (logs.promptCapture, 0..) |selector, index| {
        if (selector == .request or selector == .response) has_direction = true;
        for (logs.promptCapture[0..index]) |previous| {
            if (selector == previous) return error.InvalidLoggingPolicy;
        }
    }
    if (logs.promptCapture.len != 0 and !has_direction) return error.InvalidLoggingPolicy;

    const owner = allocator.create(OwnerStorage) catch return error.InvalidLoggingPolicy;
    errdefer allocator.destroy(owner);
    owner.* = .{ .backing_allocator = allocator, .arena = .init(allocator), .policy = undefined };
    errdefer owner.arena.deinit();
    owner.policy = .{
        .level = .{
            .threshold = canonicalized.threshold,
            .alias_evidence = canonicalized.alias_evidence,
            .source = owner.arena.allocator().dupe(u8, canonicalized.source) catch return error.InvalidLoggingPolicy,
        },
        .console = logs.console,
        .prompt_capture = owner.arena.allocator().dupe(
            config.PromptCapture,
            logs.promptCapture,
        ) catch return error.InvalidLoggingPolicy,
    };
    return @ptrCast(owner);
}

pub fn policy(owner: *const Owner) *const CompiledLoggingPolicy {
    return &ownerStorageConst(owner).policy;
}

pub fn deinitOwner(owner: *Owner) void {
    const storage = ownerStorage(owner);
    const allocator = storage.backing_allocator;
    storage.arena.deinit();
    allocator.destroy(storage);
}

pub const Field = enum {
    outcome,
    duration_ms,
    diagnostic_code,
    validator_id,
    transaction_id,
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
        .transaction_prepared, .transaction_applying => definition(event_type, level(event_type), &.{ .transaction_id, .count }, &.{}),
        .transaction_committed => definition(event_type, level(event_type), &.{ .transaction_id, .count, .outcome }, &.{}),
        .transaction_rolled_back => definition(event_type, level(event_type), &.{ .transaction_id, .diagnostic_code, .outcome }, &.{.count}),
        .transaction_recovered => definition(event_type, level(event_type), &.{ .transaction_id, .outcome }, &.{.count}),
        .command_started => definition(event_type, level(event_type), &.{.command_id}, &.{}),
        .command_completed => definition(event_type, level(event_type), &.{ .command_id, .outcome }, &.{ .exit_code, .duration_ms }),
        .command_failed => definition(event_type, level(event_type), &.{ .command_id, .diagnostic_code, .outcome }, &.{ .exit_code, .duration_ms }),
        .task_started => definition(event_type, level(event_type), &.{.task_id}, &.{}),
        .model_prompt_fragment => .{ .event_type = event_type, .level = .debug, .required = none, .optional = none },
    };
}

fn definitionForFailure(event_type: telemetry.EventType) EventDefinition {
    return switch (event_type) {
        .model_protocol_failed, .model_schema_failed => definition(
            event_type,
            level(event_type),
            &.{ .model_route_id, .model_profile_id, .diagnostic_code, .outcome },
            &.{},
        ),
        .repair_rejected, .repair_exhausted => definition(
            event_type,
            level(event_type),
            &.{ .repair_unit_kind, .diagnostic_code, .outcome },
            &.{},
        ),
        .task_blocked => definition(
            event_type,
            level(event_type),
            &.{ .task_id, .diagnostic_code, .outcome },
            &.{},
        ),
        .security_denied => definition(
            event_type,
            level(event_type),
            &.{ .rule_id, .diagnostic_code, .outcome },
            &.{},
        ),
        else => definition(
            event_type,
            level(event_type),
            &.{ .diagnostic_code, .outcome },
            &.{},
        ),
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
        .run_blocked,
        .run_failed,
        .stage_blocked,
        .stage_failed,
        .action_failed,
        .repair_exhausted,
        .command_failed,
        .task_failed,
        => .error_level,
        .action_invalid,
        .model_protocol_failed,
        .model_schema_failed,
        .validation_failed,
        .repair_rejected,
        .review_rejected,
        .transaction_rolled_back,
        .transaction_recovered,
        .task_blocked,
        .security_denied,
        => .warning,
        .action_started,
        .action_completed,
        .model_requested,
        .model_completed,
        .validation_completed,
        .repair_requested,
        .transaction_prepared,
        .transaction_applying,
        .command_started,
        .command_completed,
        .model_prompt_fragment,
        => .debug,
        else => .info,
    };
}

pub fn validateFact(fact: telemetry.TelemetryFact) Error!EventDefinition {
    if (fact.event_type == .model_prompt_fragment) return error.InvalidLoggingPolicy;
    const event_definition = eventDefinition(fact.event_type);
    const actual = fieldSet(fact.fields);
    if (!actual.supersetOf(event_definition.required)) return error.InvalidLoggingPolicy;
    var allowed = event_definition.required;
    allowed.setUnion(event_definition.optional);
    if (!allowed.supersetOf(actual)) return error.InvalidLoggingPolicy;
    return event_definition;
}

pub fn isEmitted(policy_value: CompiledLoggingPolicy, level_value: telemetry.CanonicalLogLevel) bool {
    return level_value.rank() >= policy_value.level.threshold.rank();
}

pub fn transitionCompatible(current: CompiledLoggingPolicy, next: CompiledLoggingPolicy) bool {
    return current.timestamp_enabled == next.timestamp_enabled and
        current.file_enabled == next.file_enabled and
        current.max_record_bytes == next.max_record_bytes and
        current.max_segment_bytes == next.max_segment_bytes and
        current.max_segments == next.max_segments and
        current.retention_days == next.retention_days and
        current.flush_at_or_above == next.flush_at_or_above and
        current.lower_level_flush_records == next.lower_level_flush_records and
        current.lower_level_flush_interval_ms == next.lower_level_flush_interval_ms and
        current.max_prompt_content_bytes == next.max_prompt_content_bytes and
        current.stream_lock_deadline_ms == next.stream_lock_deadline_ms and
        current.stream_lock_attempt_count == next.stream_lock_attempt_count;
}

fn fieldSet(fields: telemetry.TelemetryFields) FieldSet {
    var result = FieldSet.initEmpty();
    inline for (@typeInfo(telemetry.TelemetryFields).@"struct".fields) |field| {
        if (@field(fields, field.name) != null) result.insert(@field(Field, field.name));
    }
    return result;
}

fn ownerStorage(owner: *Owner) *OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

fn ownerStorageConst(owner: *const Owner) *const OwnerStorage {
    return @ptrCast(@alignCast(owner));
}

test "canonical level aliases have one owner and threshold comparison is exhaustive" {
    try std.testing.expectEqual(telemetry.CanonicalLogLevel.fatal, (try canonicalizeConfiguredLevel("CRITICAL")).threshold);
    try std.testing.expectEqual(AliasEvidence.warn_to_warning, (try canonicalizeConfiguredLevel("warn")).alias_evidence);
    try std.testing.expectError(error.InvalidLoggingPolicy, canonicalizeConfiguredLevel("verbose"));

    const levels = std.enums.values(telemetry.CanonicalLogLevel);
    for (levels) |configured| {
        const policy_value: CompiledLoggingPolicy = .{
            .level = .{ .threshold = configured, .alias_evidence = .none },
            .console = false,
            .prompt_capture = &.{},
        };
        for (levels) |event_level| {
            try std.testing.expectEqual(
                event_level.rank() >= configured.rank(),
                isEmitted(policy_value, event_level),
            );
        }
    }
}

test "closed event registry validates required and unexpected fields" {
    _ = try validateFact(.{
        .event_type = .task_started,
        .fields = .{ .task_id = telemetry.Identifier.validate("TASK-1") },
    });
    try std.testing.expectError(error.InvalidLoggingPolicy, validateFact(.{ .event_type = .task_started }));
    try std.testing.expectError(error.InvalidLoggingPolicy, validateFact(.{
        .event_type = .task_started,
        .fields = .{
            .task_id = telemetry.Identifier.validate("TASK-1"),
            .command_id = telemetry.Identifier.validate("CMD-1"),
        },
    }));
}

test "policy transitions permit user choices but preserve hard logging contracts" {
    const current: CompiledLoggingPolicy = .{
        .level = .{ .threshold = .info, .alias_evidence = .none },
        .console = false,
        .prompt_capture = &.{},
    };
    var next = current;
    next.level.threshold = .debug;
    next.console = true;
    try std.testing.expect(transitionCompatible(current, next));
    next.max_segments -= 1;
    try std.testing.expect(!transitionCompatible(current, next));
}
