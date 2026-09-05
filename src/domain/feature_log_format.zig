const std = @import("std");
const log_event_registry = @import("log_event_registry.zig");
const log_limits = @import("feature_log_limits.zig");
const telemetry = @import("telemetry.zig");
const log_binding = @import("feature_log_binding.zig");
const log_stream = @import("feature_log_stream.zig");
const prompt_log = @import("sanitized_prompt_log.zig");

pub const event_heading = "record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|parent_event_id|correlation_id|attempt|task_id|duration_ms|diagnostic_code|validator_id|rule_id|model_route_id|model_profile_id|input_tokens|output_tokens|repair_unit_kind|command_id|exit_code|evidence_status|outcome|count\n";
pub const event_column_count = std.mem.countScalar(u8, event_heading, '|') + 1;

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
    feature_id: @import("feature_identity.zig").FeatureId,
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
    feature_id: @import("feature_identity.zig").FeatureId,
    fragment: prompt_log.SanitizedPromptFragment,
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
    feature_id: @import("feature_identity.zig").FeatureId,
};

pub fn serializeEventControl(
    allocator: std.mem.Allocator,
    record: EventControlRecord,
) Error![]u8 {
    if (record.segment_ordinal == 0 or !validUtcTimestamp(record.occurred_at_utc) or
        !validControlSequence(record.kind, record.final_sequence))
    {
        return error.InvalidFeatureLogRecord;
    }
    var row: std.ArrayList(u8) = .empty;
    errdefer row.deinit(allocator);
    var first = true;
    var number_buffer: [32]u8 = undefined;
    try appendCell(allocator, &row, &first, @tagName(record.kind));
    try appendCell(allocator, &row, &first, log_limits.schema_version);
    try appendCell(allocator, &row, &first, "event");
    try appendCell(allocator, &row, &first, log_limits.event_column_schema_id);
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
    for (0..event_column_count - 17) |_| try appendOptional(allocator, &row, &first, null);
    row.append(allocator, '\n') catch return error.OutOfMemory;
    try validateEncodedRow(allocator, row.items, event_column_count);
    return row.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

pub fn serializePromptControl(allocator: std.mem.Allocator, record: EventControlRecord) Error![]u8 {
    if (record.segment_ordinal == 0 or !validUtcTimestamp(record.occurred_at_utc) or
        !validControlSequence(record.kind, record.final_sequence)) return error.InvalidFeatureLogRecord;
    var row: std.ArrayList(u8) = .empty;
    errdefer row.deinit(allocator);
    var first = true;
    var number_buffer: [32]u8 = undefined;
    try appendCell(allocator, &row, &first, @tagName(record.kind));
    try appendCell(allocator, &row, &first, log_limits.schema_version);
    try appendCell(allocator, &row, &first, "prompt");
    try appendCell(allocator, &row, &first, log_limits.prompt_column_schema_id);
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
        !validUtcTimestamp(record.occurred_at_utc)) return error.InvalidFeatureLogRecord;
    prompt_log.validate(fragment) catch return error.InvalidFeatureLogRecord;
    var row: std.ArrayList(u8) = .empty;
    errdefer row.deinit(allocator);
    var first = true;
    var number_buffer: [32]u8 = undefined;
    try appendCell(allocator, &row, &first, "prompt");
    try appendCell(allocator, &row, &first, log_limits.schema_version);
    try appendCell(allocator, &row, &first, "prompt");
    try appendCell(allocator, &row, &first, log_limits.prompt_column_schema_id);
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
    const definition = log_event_registry.validateFact(record.fact) catch return error.InvalidFeatureLogRecord;
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
    try appendCell(allocator, &row, &first, log_limits.schema_version);
    try appendCell(allocator, &row, &first, "event");
    try appendCell(allocator, &row, &first, log_limits.event_column_schema_id);
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
    if (row.items.len > log_limits.max_record_bytes) return error.InvalidFeatureLogRecord;
    return row.toOwnedSlice(allocator) catch return error.OutOfMemory;
}

pub fn validateEncodedRow(
    allocator: std.mem.Allocator,
    encoded: []const u8,
    expected_cells: usize,
) Error!void {
    if (encoded.len == 0 or encoded[encoded.len - 1] != '\n' or
        encoded.len > log_limits.max_record_bytes) return error.InvalidFeatureLogRecord;
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

pub fn validatePersistedIdentityRow(
    line: []const u8,
    binding: *const log_binding.ValidatedFeatureLogBinding,
    ordinal: u16,
    stream: log_stream.Stream,
) Error!void {
    if (!std.mem.eql(u8, cellAt(line, 1) orelse return error.InvalidFeatureLogRecord, log_limits.schema_version) or
        !std.mem.eql(u8, cellAt(line, 2) orelse return error.InvalidFeatureLogRecord, @tagName(stream)) or
        !std.mem.eql(u8, cellAt(line, 3) orelse return error.InvalidFeatureLogRecord, if (stream == .event) log_limits.event_column_schema_id else log_limits.prompt_column_schema_id) or
        !std.mem.eql(u8, cellAt(line, 4) orelse return error.InvalidFeatureLogRecord, binding.logPolicyId().bytes) or
        !std.mem.eql(u8, cellAt(line, 5) orelse return error.InvalidFeatureLogRecord, binding.bindingId().bytes) or
        (std.fmt.parseInt(u16, cellAt(line, 6) orelse return error.InvalidFeatureLogRecord, 10) catch return error.InvalidFeatureLogRecord) != ordinal or
        !std.mem.eql(u8, cellAt(line, 15) orelse return error.InvalidFeatureLogRecord, binding.runId().bytes) or
        !std.mem.eql(u8, cellAt(line, 16) orelse return error.InvalidFeatureLogRecord, binding.featureId().bytes))
    {
        return error.InvalidFeatureLogRecord;
    }
}

pub fn validatePersistedControlRow(
    line: []const u8,
    kind: ControlKind,
    stream: log_stream.Stream,
    final_sequence: ?u64,
) Error!void {
    if (!std.mem.eql(u8, cellAt(line, 0) orelse return error.InvalidFeatureLogRecord, @tagName(kind)) or
        parseUtcMs(cellAt(line, 10) orelse return error.InvalidFeatureLogRecord) == null) return error.InvalidFeatureLogRecord;
    const event_nulls = [_]usize{ 7, 8, 11, 12, 13, 14, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36 };
    const prompt_nulls = [_]usize{ 7, 8, 11, 12, 13, 14, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29 };
    const null_columns: []const usize = if (stream == .event) &event_nulls else &prompt_nulls;
    for (null_columns) |column| {
        if (!std.mem.eql(u8, cellAt(line, column) orelse return error.InvalidFeatureLogRecord, "\\N")) {
            return error.InvalidFeatureLogRecord;
        }
    }
    const sequence = cellAt(line, 9) orelse return error.InvalidFeatureLogRecord;
    if (final_sequence) |expected| {
        const actual = std.fmt.parseInt(u64, sequence, 10) catch return error.InvalidFeatureLogRecord;
        if (actual != expected) return error.InvalidFeatureLogRecord;
    } else if (!std.mem.eql(u8, sequence, "\\N")) return error.InvalidFeatureLogRecord;
}

pub fn cellAt(line: []const u8, expected: usize) ?[]const u8 {
    var cell: usize = 0;
    var start: usize = 0;
    var escaped = false;
    for (line, 0..) |byte, index| {
        if (escaped) {
            escaped = false;
            continue;
        }
        if (byte == '\\') {
            escaped = true;
        } else if (byte == '|') {
            if (cell == expected) return line[start..index];
            cell += 1;
            start = index + 1;
        }
    }
    return if (cell == expected) line[start..] else null;
}

pub fn trailerUnixMs(bytes: []const u8) ?u64 {
    if (bytes.len == 0 or bytes[bytes.len - 1] != '\n') return null;
    const without_lf = bytes[0 .. bytes.len - 1];
    const start = (std.mem.lastIndexOfScalar(u8, without_lf, '\n') orelse return null) + 1;
    const line = without_lf[start..];
    if (!std.mem.eql(u8, cellAt(line, 0) orelse return null, "segment_trailer")) return null;
    return parseUtcMs(cellAt(line, 10) orelse return null);
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
    return parseUtcMs(value) != null;
}

fn validControlSequence(kind: ControlKind, final_sequence: ?u64) bool {
    return switch (kind) {
        .segment_header => final_sequence == null,
        .segment_trailer => final_sequence != null,
    };
}

fn parseUtcMs(value: []const u8) ?u64 {
    if (value.len != 20 or value[4] != '-' or value[7] != '-' or value[10] != 'T' or
        value[13] != ':' or value[16] != ':' or value[19] != 'Z') return null;
    const year = std.fmt.parseInt(u16, value[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, value[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, value[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, value[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u8, value[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u8, value[17..19], 10) catch return null;
    if (year < 1970 or month == 0 or month > 12 or day == 0 or hour > 23 or minute > 59 or second > 59) return null;
    var days: u64 = 0;
    var current_year: u16 = 1970;
    while (current_year < year) : (current_year += 1) days += if (isLeapYear(current_year)) 366 else 365;
    const month_days = [_]u8{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    var current_month: u8 = 1;
    while (current_month < month) : (current_month += 1) {
        days += month_days[current_month - 1] + @as(u8, if (current_month == 2 and isLeapYear(year)) 1 else 0);
    }
    const max_day = month_days[month - 1] + @as(u8, if (month == 2 and isLeapYear(year)) 1 else 0);
    if (day > max_day) return null;
    days += day - 1;
    return (((days * 24 + hour) * 60 + minute) * 60 + second) * 1000;
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
}

fn stageText(value: telemetry.Stage) []const u8 {
    return @tagName(value);
}

test "built-in headings are byte stable and have exact widths" {
    try std.testing.expectEqual(@as(usize, 37), std.mem.countScalar(u8, event_heading, '|') + 1);
    try std.testing.expectEqual(@as(usize, 30), std.mem.countScalar(u8, prompt_heading, '|') + 1);
    try std.testing.expect(std.mem.endsWith(u8, event_heading, "|count\n"));
    try std.testing.expect(std.mem.endsWith(u8, prompt_heading, "|redacted\n"));
}

test "UTC timestamps reject impossible calendar dates" {
    try std.testing.expect(validUtcTimestamp("2024-02-29T12:30:05Z"));
    try std.testing.expect(!validUtcTimestamp("2023-02-29T12:30:05Z"));
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
        .feature_id = @import("feature_identity.zig").FeatureId.parse("F0002").?,
        .fact = .{
            .event_type = .task_started,
            .fields = .{ .task_id = telemetry.Identifier.validate("TASK-1").? },
        },
    });
    defer allocator.free(row);
    try validateEncodedRow(allocator, row, event_column_count);
    try std.testing.expect(std.mem.indexOf(u8, row, "|IMPL|") != null);
    try std.testing.expect(std.mem.indexOf(u8, row, "|info|task.started|task.started/v1|") != null);
}

test "dialect rejects unknown dangling escapes and wrong width" {
    try std.testing.expectError(error.InvalidFeatureLogRecord, validateEncodedRow(std.testing.allocator, "a|b\\q\n", 2));
    try std.testing.expectError(error.InvalidFeatureLogRecord, validateEncodedRow(std.testing.allocator, "a|b\\\n", 2));
    try std.testing.expectError(error.InvalidFeatureLogRecord, validateEncodedRow(std.testing.allocator, "a|b\n", 3));
}

test "event rows reject the obsolete transaction column" {
    const obsolete_heading = "record_kind|schema_version|stream|column_schema_id|log_policy_id|feature_log_binding_id|segment_ordinal|workflow_shortcode|event_id|sequence|occurred_at_utc|monotonic_offset|level|event_type|message_template_id|run_id|feature_id|stage|node_id|parent_event_id|correlation_id|attempt|task_id|duration_ms|diagnostic_code|validator_id|transaction_id|rule_id|model_route_id|model_profile_id|input_tokens|output_tokens|repair_unit_kind|command_id|exit_code|evidence_status|outcome|count\n";
    try std.testing.expectError(error.InvalidFeatureLogRecord, validateEncodedRow(std.testing.allocator, obsolete_heading, event_column_count));
    try std.testing.expect(std.mem.indexOf(u8, event_heading, "transaction_id") == null);
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
        .feature_id = @import("feature_identity.zig").FeatureId.parse("F0002").?,
    });
    defer allocator.free(row);
    try validateEncodedRow(allocator, row, event_column_count);
    try std.testing.expect(std.mem.startsWith(u8, row, "segment_header|feature-log/v2|event|"));

    try std.testing.expectError(error.InvalidFeatureLogRecord, serializeEventControl(allocator, .{
        .kind = .segment_trailer,
        .log_policy_id = telemetry.Identifier.validate("LOGPOL-1").?,
        .binding_id = telemetry.Identifier.validate("LOGBIND-1").?,
        .segment_ordinal = 1,
        .occurred_at_utc = "2026-08-30T10:15:30Z",
        .run_id = telemetry.Identifier.validate("RUN-1").?,
        .feature_id = @import("feature_identity.zig").FeatureId.parse("F0002").?,
    }));
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
        .feature_id = @import("feature_identity.zig").FeatureId.parse("F0002").?,
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
