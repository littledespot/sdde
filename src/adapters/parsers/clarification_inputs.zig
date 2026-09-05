const std = @import("std");
const clarification = @import("../../domain/clarification_inputs.zig");
const forms = @import("../../domain/clarification_form.zig");
const port = @import("../../ports/clarification_input_parser.zig");

pub fn stateParser() port.StateParser {
    return .{ .parse_state_fn = parseState };
}
pub fn formParser() port.FormParser {
    return .{ .parse_form_fn = parseForm };
}
fn parseState(allocator: std.mem.Allocator, bytes: []const u8) clarification.Error!clarification.State {
    if (bytes.len == 0 or bytes.len > clarification.max_state_bytes or !std.unicode.utf8ValidateSlice(bytes)) return error.InvalidClarificationInput;
    return std.json.parseFromSliceLeaky(clarification.State, allocator, bytes, .{ .allocate = .alloc_always, .max_value_len = clarification.max_state_bytes }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidClarificationInput,
    };
}
fn parseForm(allocator: std.mem.Allocator, bytes: []const u8, record: clarification.Record, binding: forms.Binding) clarification.Error!port.Form {
    if (bytes.len == 0 or bytes.len > clarification.max_form_bytes or !std.unicode.utf8ValidateSlice(bytes) or
        std.mem.count(u8, bytes, forms.answer_start) != 1 or std.mem.count(u8, bytes, forms.answer_end) != 1) return error.InvalidClarificationInput;
    const expected = try forms.template(allocator, record, binding);
    defer allocator.free(expected.before_status);
    defer allocator.free(expected.before_answer);
    if (!std.mem.startsWith(u8, bytes, expected.before_status) or !std.mem.endsWith(u8, bytes, expected.after_answer)) return error.InvalidClarificationInput;
    const remainder = bytes[expected.before_status.len..];
    const line_end = std.mem.indexOfScalar(u8, remainder, '\n') orelse return error.InvalidClarificationInput;
    const status = std.meta.stringToEnum(clarification.RequestedStatus, remainder[0..line_end]) orelse return error.InvalidClarificationInput;
    if (!std.mem.startsWith(u8, remainder[line_end..], expected.before_answer)) return error.InvalidClarificationInput;
    const answer_offset = expected.before_status.len + line_end + expected.before_answer.len;
    const end = bytes.len - expected.after_answer.len;
    if (end < answer_offset) return error.InvalidClarificationInput;
    const raw_answer = std.mem.trim(u8, bytes[answer_offset..end], " \t\r\n");
    const answer = try normalizeAnswer(allocator, raw_answer, status, record.answer_schema);
    return .{ .requested_status = status, .answer = answer };
}
fn text(allocator: std.mem.Allocator, raw: []const u8, maximum: usize) clarification.Error![]const u8 {
    if (!clarification.validText(raw, maximum)) return error.InvalidClarificationInput;
    return @import("unicode_normalization").nfc(allocator, raw, maximum) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidClarificationInput,
    };
}
fn normalizeAnswer(allocator: std.mem.Allocator, raw: []const u8, status: clarification.RequestedStatus, schema: clarification.AnswerSchema) clarification.Error!clarification.Answer {
    switch (status) {
        .open => {
            if (raw.len == 0) return .{ .none = {} };
            if (!std.mem.startsWith(u8, raw, "defer: ")) return error.InvalidClarificationInput;
            return .{ .defer_reason = try text(allocator, std.mem.trim(u8, raw["defer: ".len..], " \t"), clarification.max_text_bytes) };
        },
        .cancel => {
            if (!std.mem.startsWith(u8, raw, "cancel: ")) return error.InvalidClarificationInput;
            return .{ .cancel_reason = try text(allocator, std.mem.trim(u8, raw["cancel: ".len..], " \t"), clarification.max_text_bytes) };
        },
        .closed => {},
    }
    switch (schema) {
        .bounded_business_text => |maximum| return .{ .business_text = try text(allocator, raw, maximum) },
        .select_one => |options| {
            for (options) |option| if (std.mem.eql(u8, option.key, raw)) return .{ .selected_option = option.key };
            return error.InvalidClarificationInput;
        },
        .select_many => |many| {
            var selected: [32]bool = @splat(false);
            var count: usize = 0;
            var lines = std.mem.splitScalar(u8, raw, '\n');
            while (lines.next()) |line| {
                const key = std.mem.trim(u8, line, " \t");
                if (key.len == 0) continue;
                const index = for (many.options, 0..) |option, index| {
                    if (std.mem.eql(u8, option.key, key)) break index;
                } else return error.InvalidClarificationInput;
                if (selected[index]) return error.InvalidClarificationInput;
                selected[index] = true;
                count += 1;
            }
            if (count < many.minimum or count > many.maximum) return error.InvalidClarificationInput;
            const keys = try allocator.alloc([]const u8, count);
            var cursor: usize = 0;
            for (many.options, 0..) |option, index| if (selected[index]) {
                keys[cursor] = option.key;
                cursor += 1;
            };
            return .{ .selected_options = keys };
        },
    }
}
