const std = @import("std");
const logging = @import("logging.zig");
const telemetry = @import("telemetry.zig");

pub const event_heading = "record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|parent_event_id|correlation_id|attempt|task_id|duration_ms|diagnostic_code|validator_id|transaction_id|rule_id|model_route_id|model_profile_id|input_tokens|output_tokens|repair_unit_kind|command_id|exit_code|evidence_status|outcome|count\n";
pub const prompt_heading = "record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|attempt|request_id|route_id|model_profile_id|fragment_id|direction|body_class|content|retained_bytes|truncated|redacted\n";

pub const Error = error{ InvalidFeatureLogRecord, OutOfMemory };

pub const EventRecord = struct {
    log_policy_id: telemetry.Identifier,
    binding_id: telemetry.Identifier,
    segment_ordinal: u16,
    workflow_shortcode: telemetry.WorkflowShortcode,
    event_id: telemetry.Identifier,
    sequence: u64,
    occurred_at_utc: []const u8,
    monotonic_offset: u64,
    run_id: telemetry.Identifier,
    feature_id: telemetry.Identifier,
    fact: telemetry.TelemetryFact,
};

pub const PromptRecord = struct {
    log_policy_id: telemetry.Identifier,
    binding_id: telemetry.Identifier,
    segment_ordinal: u16,
    event_id: telemetry.Identifier,
    sequence: u64,
    occurred_at_utc: []const u8,
    monotonic_offset: u64,
    run_id: telemetry.Identifier,
    feature_id: telemetry.Identifier,
    fragment: @import("feature_log_runtime.zig").SanitizedPromptFragment,
};

pub const ControlKind = enum { segment_header, segment_trailer };
pub const EventControlRecord = struct {
    kind: ControlKind,
    log_policy_id: telemetry.Identifier,
    binding_id: telemetry.Identifier,
    segment_ordinal: u16,
    final_sequence: ?u64 = null,
    occurred_at_utc: []const u8,
    run_id: telemetry.Identifier,
    feature_id: telemetry.Identifier,
};

pub fn serializeEventControl(
    allocator: std.mem.Allocator,
    record: EventControlRecord,
) Error![]u8 {
    if (record.segment_ordinal == 0 or !validUtcTimestamp(record.occurred_at_utc) or
        (record.kind == .segment_header and record.final_sequence != null))
    {
        return error.InvalidFeatureLogRecord;
    }
    var row: std.ArrayList(u8) = .empty;
    errdefer row.deinit(allocator);
    var first = true;
    var number_buffer: [32]u8 = undefined;
    try appendCell(allocator, &row, &first, @tagName(record.kind));
    try appendCell(allocator, &row, &first, logging.schema_version);
    try appendCell(allocator, &row, &first, "event");
    try appendCell(allocator, &row, &first, logging.event_column_schema_id);
    try appendCell(allocator, &row, &first, record.log_policy_id.bytes);
    try appendCell(allocator, &row, &first, record.binding_id.bytes);
    try appendUnsigned(allocator, &row, &first, record.segment_ordinal, &number_buffer);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendOptionalUnsigned(allocator, &row, &first, record.final_sequence, &number_buffer);
    try appendCell(allocator, &row, &first, record.occurred_at_utc);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendCell(allocator, &row, &first, record.run_id.bytes);
    try appendCell(allocator, &row, &first, record.feature_id.bytes);
    for (0..21) |_| try appendOptional(allocator, &row, &first, null);
    row.append(allocator, '\n') catch return error.OutOfMemory;
    try validateEncodedRow(allocator, row.items, 38);
    return row.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

pub fn serializePromptControl(allocator: std.mem.Allocator, record: EventControlRecord) Error![]u8 {
    if (record.segment_ordinal == 0 or !validUtcTimestamp(record.occurred_at_utc) or
        (record.kind == .segment_header and record.final_sequence != null)) return error.InvalidFeatureLogRecord;
    var row: std.ArrayList(u8) = .empty;
    errdefer row.deinit(allocator);
    var first = true;
    var number_buffer: [32]u8 = undefined;
    try appendCell(allocator, &row, &first, @tagName(record.kind));
    try appendCell(allocator, &row, &first, logging.schema_version);
    try appendCell(allocator, &row, &first, "prompt");
    try appendCell(allocator, &row, &first, logging.prompt_column_schema_id);
    try appendCell(allocator, &row, &first, record.log_policy_id.bytes);
    try appendCell(allocator, &row, &first, record.binding_id.bytes);
    try appendUnsigned(allocator, &row, &first, record.segment_ordinal, &number_buffer);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendOptionalUnsigned(allocator, &row, &first, record.final_sequence, &number_buffer);
    try appendCell(allocator, &row, &first, record.occurred_at_utc);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendOptional(allocator, &row, &first, null);
    try appendCell(allocator, &row, &first, record.run_id.bytes);
    try appendCell(allocator, &row, &first, record.feature_id.bytes);
    for (0..13) |_| try appendOptional(allocator, &row, &first, null);
    row.append(allocator, '\n') catch return error.OutOfMemory;
    try validateEncodedRow(allocator, row.items, 30);
    return row.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

pub fn serializePrompt(allocator: std.mem.Allocator, record: PromptRecord) Error![]u8 {
    const fragment = record.fragment;
    if (record.segment_ordinal == 0 or record.sequence == 0 or
        !validUtcTimestamp(record.occurred_at_utc) or fragment.attempt == 0 or
        fragment.content.len != fragment.retained_bytes or
        fragment.content.len > logging.max_prompt_content_bytes or
        !std.unicode.utf8ValidateSlice(fragment.content)) return error.InvalidFeatureLogRecord;
    var row: std.ArrayList(u8) = .empty;
    errdefer row.deinit(allocator);
    var first = true;
    var number_buffer: [32]u8 = undefined;
    try appendCell(allocator, &row, &first, "prompt");
    try appendCell(allocator, &row, &first, logging.schema_version);
    try appendCell(allocator, &row, &first, "prompt");
    try appendCell(allocator, &row, &first, logging.prompt_column_schema_id);
    try appendCell(allocator, &row, &first, record.log_policy_id.bytes);
    try appendCell(allocator, &row, &first, record.binding_id.bytes);
    try appendUnsigned(allocator, &row, &first, record.segment_ordinal, &number_buffer);
    try appendCell(allocator, &row, &first, fragment.workflow_shortcode.slice());
    try appendCell(allocator, &row, &first, record.event_id.bytes);
    try appendUnsigned(allocator, &row, &first, record.sequence, &number_buffer);
    try appendCell(allocator, &row, &first, record.occurred_at_utc);
    try appendUnsigned(allocator, &row, &first, record.monotonic_offset, &number_buffer);
    try appendCell(allocator, &row, &first, "debug");
    try appendCell(allocator, &row, &first, "model.prompt_fragment");
    try appendCell(allocator, &row, &first, "model.prompt_fragment/v1");
    try appendCell(allocator, &row, &first, record.run_id.bytes);
    try appendCell(allocator, &row, &first, record.feature_id.bytes);
    try appendOptional(allocator, &row, &first, if (fragment.stage) |value| stageText(value) else null);
    try appendOptionalId(allocator, &row, &first, fragment.node_id);
    try appendUnsigned(allocator, &row, &first, fragment.attempt, &number_buffer);
    try appendCell(allocator, &row, &first, fragment.request_id.bytes);
    try appendCell(allocator, &row, &first, fragment.route_id.bytes);
    try appendCell(allocator, &row, &first, fragment.model_profile_id.bytes);
    try appendCell(allocator, &row, &first, fragment.fragment_id.bytes);
    try appendCell(allocator, &row, &first, @tagName(fragment.direction));
    try appendCell(allocator, &row, &first, @tagName(fragment.body_class));
    try appendCell(allocator, &row, &first, fragment.content);
    try appendUnsigned(allocator, &row, &first, fragment.retained_bytes, &number_buffer);
    try appendCell(allocator, &row, &first, if (fragment.truncated) "true" else "false");
    try appendCell(allocator, &row, &first, if (fragment.redacted) "true" else "false");
    row.append(allocator, '\n') catch return error.OutOfMemory;
    try validateEncodedRow(allocator, row.items, 30);
    return row.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

pub fn serializeEvent(
    allocator: std.mem.Allocator,
    record: EventRecord,
) Error![]u8 {
    const definition = logging.validateFact(record.fact) catch return error.InvalidFeatureLogRecord;
    if (record.segment_ordinal == 0 or record.sequence == 0 or
        !validUtcTimestamp(record.occurred_at_utc)) return error.InvalidFeatureLogRecord;

    var row: std.ArrayList(u8) = .empty;
    errdefer row.deinit(allocator);
    var first = true;
    var number_buffer: [32]u8 = undefined;
    var template_buffer: [96]u8 = undefined;
    const template_id = definition.templateId(&template_buffer) catch return error.InvalidFeatureLogRecord;
    const fields = record.fact.fields;

    try appendCell(allocator, &row, &first, "event");
    try appendCell(allocator, &row, &first, logging.schema_version);
    try appendCell(allocator, &row, &first, "event");
    try appendCell(allocator, &row, &first, logging.event_column_schema_id);
    try appendCell(allocator, &row, &first, record.log_policy_id.bytes);
    try appendCell(allocator, &row, &first, record.binding_id.bytes);
    try appendUnsigned(allocator, &row, &first, record.segment_ordinal, &number_buffer);
    try appendCell(allocator, &row, &first, record.workflow_shortcode.slice());
    try appendCell(allocator, &row, &first, record.event_id.bytes);
    try appendUnsigned(allocator, &row, &first, record.sequence, &number_buffer);
    try appendCell(allocator, &row, &first, record.occurred_at_utc);
    try appendUnsigned(allocator, &row, &first, record.monotonic_offset, &number_buffer);
    try appendCell(allocator, &row, &first, definition.level.text());
    try appendCell(allocator, &row, &first, record.fact.event_type.text());
    try appendCell(allocator, &row, &first, template_id);
    try appendCell(allocator, &row, &first, record.run_id.bytes);
    try appendCell(allocator, &row, &first, record.feature_id.bytes);
    try appendOptional(allocator, &row, &first, if (record.fact.stage) |value| stageText(value) else null);
    try appendOptionalId(allocator, &row, &first, record.fact.node_id);
    try appendOptionalId(allocator, &row, &first, record.fact.parent_event_id);
    try appendOptionalId(allocator, &row, &first, record.fact.correlation_id);
    try appendOptionalUnsigned(allocator, &row, &first, record.fact.attempt, &number_buffer);
    try appendOptionalId(allocator, &row, &first, fields.task_id);
    try appendOptionalUnsigned(allocator, &row, &first, fields.duration_ms, &number_buffer);
    try appendOptional(allocator, &row, &first, if (fields.diagnostic_code) |value| value.bytes else null);
    try appendOptionalId(allocator, &row, &first, fields.validator_id);
    try appendOptionalId(allocator, &row, &first, fields.transaction_id);
    try appendOptionalId(allocator, &row, &first, fields.rule_id);
    try appendOptionalId(allocator, &row, &first, fields.model_route_id);
    try appendOptionalId(allocator, &row, &first, fields.model_profile_id);
    try appendOptionalUnsigned(allocator, &row, &first, fields.input_tokens, &number_buffer);
    try appendOptionalUnsigned(allocator, &row, &first, fields.output_tokens, &number_buffer);
    try appendOptional(allocator, &row, &first, if (fields.repair_unit_kind) |value| @tagName(value) else null);
    try appendOptionalId(allocator, &row, &first, fields.command_id);
    try appendOptionalSigned(allocator, &row, &first, fields.exit_code, &number_buffer);
    try appendOptional(allocator, &row, &first, if (fields.evidence_status) |value| @tagName(value) else null);
    try appendOptional(allocator, &row, &first, if (fields.outcome) |value| @tagName(value) else null);
    try appendOptionalUnsigned(allocator, &row, &first, fields.count, &number_buffer);
    row.append(allocator, '\n') catch return error.OutOfMemory;
    if (row.items.len > logging.max_record_bytes) return error.InvalidFeatureLogRecord;
    return row.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

pub fn validateEncodedRow(
    allocator: std.mem.Allocator,
    encoded: []const u8,
    expected_cells: usize,
) Error!void {
    if (encoded.len == 0 or encoded[encoded.len - 1] != '\n' or
        encoded.len > logging.max_record_bytes) return error.InvalidFeatureLogRecord;
    var cells: usize = 1;
    var escaped = false;
    var index: usize = 0;
    while (index + 1 < encoded.len) : (index += 1) {
        const byte = encoded[index];
        if (escaped) {
            if (!(byte == '\\' or byte == '|' or byte == 'r' or byte == 'n')) {
                return error.InvalidFeatureLogRecord;
            }
            escaped = false;
        } else if (byte == '\\') {
            if (index + 1 < encoded.len - 1 and encoded[index + 1] == 'N' and
                (index == 0 or encoded[index - 1] == '|') and
                (index + 2 == encoded.len - 1 or encoded[index + 2] == '|'))
            {
                index += 1;
            } else escaped = true;
        } else if (byte == '|') {
            cells += 1;
        } else if (byte == '\r' or byte == '\n') return error.InvalidFeatureLogRecord;
    }
    _ = allocator;
    if (escaped or cells != expected_cells) return error.InvalidFeatureLogRecord;
}

fn appendCell(
    allocator: std.mem.Allocator,
    row: *std.ArrayList(u8),
    first: *bool,
    value: []const u8,
) Error!void {
    if (!first.*) row.append(allocator, '|') catch return error.OutOfMemory;
    first.* = false;
    for (value) |byte| switch (byte) {
        '\\' => row.appendSlice(allocator, "\\\\") catch return error.OutOfMemory,
        '|' => row.appendSlice(allocator, "\\|") catch return error.OutOfMemory,
        '\r' => row.appendSlice(allocator, "\\r") catch return error.OutOfMemory,
        '\n' => row.appendSlice(allocator, "\\n") catch return error.OutOfMemory,
        else => row.append(allocator, byte) catch return error.OutOfMemory,
    };
}

fn appendOptional(
    allocator: std.mem.Allocator,
    row: *std.ArrayList(u8),
    first: *bool,
    value: ?[]const u8,
) Error!void {
    if (value) |present| return appendCell(allocator, row, first, present);
    if (!first.*) row.append(allocator, '|') catch return error.OutOfMemory;
    first.* = false;
    row.appendSlice(allocator, "\\N") catch return error.OutOfMemory;
}

fn appendOptionalId(
    allocator: std.mem.Allocator,
    row: *std.ArrayList(u8),
    first: *bool,
    value: ?telemetry.Identifier,
) Error!void {
    return appendOptional(allocator, row, first, if (value) |present| present.bytes else null);
}

fn appendUnsigned(
    allocator: std.mem.Allocator,
    row: *std.ArrayList(u8),
    first: *bool,
    value: u64,
    buffer: []u8,
) Error!void {
    const text = std.fmt.bufPrint(buffer, "{d}", .{value}) catch return error.InvalidFeatureLogRecord;
    return appendCell(allocator, row, first, text);
}

fn appendOptionalUnsigned(
    allocator: std.mem.Allocator,
    row: *std.ArrayList(u8),
    first: *bool,
    value: ?u64,
    buffer: []u8,
) Error!void {
    if (value) |present| return appendUnsigned(allocator, row, first, present, buffer);
    return appendOptional(allocator, row, first, null);
}

fn appendOptionalSigned(
    allocator: std.mem.Allocator,
    row: *std.ArrayList(u8),
    first: *bool,
    value: ?i32,
    buffer: []u8,
) Error!void {
    if (value) |present| {
        const text = std.fmt.bufPrint(buffer, "{d}", .{present}) catch {
            return error.InvalidFeatureLogRecord;
        };
        return appendCell(allocator, row, first, text);
    }
    return appendOptional(allocator, row, first, null);
}

fn validUtcTimestamp(value: []const u8) bool {
    return value.len == 20 and value[4] == '-' and value[7] == '-' and
        value[10] == 'T' and value[13] == ':' and value[16] == ':' and value[19] == 'Z';
}

fn stageText(value: telemetry.Stage) []const u8 {
    return @tagName(value);
}

test "built-in headings are byte stable and have exact widths" {
    try std.testing.expectEqual(@as(usize, 38), std.mem.countScalar(u8, event_heading, '|') + 1);
    try std.testing.expectEqual(@as(usize, 30), std.mem.countScalar(u8, prompt_heading, '|') + 1);
    try std.testing.expect(std.mem.endsWith(u8, event_heading, "|count\n"));
    try std.testing.expect(std.mem.endsWith(u8, prompt_heading, "|redacted\n"));
}

test "event rows use fixed columns escaping and reserved nulls" {
    const allocator = std.testing.allocator;
    const row = try serializeEvent(allocator, .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .segment_ordinal = 1,
        .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"),
        .event_id = telemetry.Identifier.validate("EVENT-1").?,
        .sequence = 1,
        .occurred_at_utc = "2026-08-30T10:15:30Z",
        .monotonic_offset = 42,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = telemetry.Identifier.validate("F0002").?,
        .fact = .{
            .event_type = .task_started,
            .fields = .{ .task_id = telemetry.Identifier.validate("TASK-1").? },
        },
    });
    defer allocator.free(row);
    try validateEncodedRow(allocator, row, 38);
    try std.testing.expect(std.mem.indexOf(u8, row, "|IMPL|") != null);
    try std.testing.expect(std.mem.indexOf(u8, row, "|info|task.started|task.started/v1|") != null);
}

test "dialect rejects unknown dangling escapes and wrong width" {
    try std.testing.expectError(error.InvalidFeatureLogRecord, validateEncodedRow(std.testing.allocator, "a|b\\q\n", 2));
    try std.testing.expectError(error.InvalidFeatureLogRecord, validateEncodedRow(std.testing.allocator, "a|b\\\n", 2));
    try std.testing.expectError(error.InvalidFeatureLogRecord, validateEncodedRow(std.testing.allocator, "a|b\n", 3));
}

test "event control rows use the same exact heading width" {
    const allocator = std.testing.allocator;
    const row = try serializeEventControl(allocator, .{
        .kind = .segment_header,
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .segment_ordinal = 1,
        .occurred_at_utc = "2026-08-30T10:15:30Z",
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = telemetry.Identifier.validate("F0002").?,
    });
    defer allocator.free(row);
    try validateEncodedRow(allocator, row, 38);
    try std.testing.expect(std.mem.startsWith(u8, row, "segment_header|feature-log/v2|event|"));
}

test "prompt rows are scalar bounded and use the exact prompt schema" {
    const allocator = std.testing.allocator;
    const row = try serializePrompt(allocator, .{
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .segment_ordinal = 1,
        .event_id = telemetry.Identifier.validate("EVENT-1").?,
        .sequence = 1,
        .occurred_at_utc = "2026-08-30T10:15:30Z",
        .monotonic_offset = 42,
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = telemetry.Identifier.validate("F0002").?,
        .fragment = .{
            .workflow_shortcode = try telemetry.WorkflowShortcode.parse("IMPL"),
            .attempt = 1,
            .request_id = telemetry.Identifier.validate("REQ-1").?,
            .route_id = telemetry.Identifier.validate("ROUTE-1").?,
            .model_profile_id = telemetry.Identifier.validate("PROFILE-1").?,
            .fragment_id = telemetry.Identifier.validate("FRAG-1").?,
            .direction = .request,
            .body_class = .ordinary,
            .content = "safe|body",
            .retained_bytes = 9,
            .truncated = false,
            .redacted = true,
        },
    });
    defer allocator.free(row);
    try validateEncodedRow(allocator, row, 30);
    try std.testing.expect(std.mem.indexOf(u8, row, "|debug|model.prompt_fragment|") != null);
    try std.testing.expect(std.mem.indexOf(u8, row, "|safe\\|body|9|false|true\n") != null);
}
