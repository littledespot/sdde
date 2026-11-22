const std = @import("std");
const clarification = @import("../../domain/clarification_inputs.zig");
const forms = @import("../../domain/clarification_form.zig");
const rejection = @import("../../domain/clarification_form_rejection.zig");
const port = @import("../../ports/clarification_input_parser.zig");
const strict_json = @import("../../domain/strict_json.zig");

pub fn stateParser() port.StateParser {
    return .{ .parse_state_fn = parseState };
}
pub fn formParser() port.FormParser {
    return .{ .parse_form_fn = parseForm };
}
fn parseState(allocator: std.mem.Allocator, bytes: []const u8) clarification.Error!clarification.State {
    return strict_json.decode(clarification.State, allocator, bytes, .{
        .maximum_bytes = clarification.max_state_bytes,
        .maximum_depth = clarification.max_state_depth,
    }) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidJsonDocument => error.InvalidClarificationInput,
    };
}

/// A form that breaks a rule; the rule is written to the caller's slot first, so no error carries it.
const Rejected = error{Rejected};

fn reject(slot: *rejection.Reason, reason: rejection.Reason) Rejected {
    slot.* = reason;
    return error.Rejected;
}

fn parseForm(allocator: std.mem.Allocator, bytes: []const u8, record: clarification.Record, binding: forms.Binding) clarification.Error!port.Parsed {
    var reason: rejection.Reason = undefined;
    const parsed = parseBytes(allocator, bytes, record, binding, &reason) catch |failure| switch (failure) {
        error.Rejected => return .{ .rejected = reason },
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidClarificationInput => return error.InvalidClarificationInput,
    };
    return .{ .form = parsed };
}
fn parseBytes(allocator: std.mem.Allocator, bytes: []const u8, record: clarification.Record, binding: forms.Binding, slot: *rejection.Reason) (clarification.Error || Rejected)!port.Form {
    if (bytes.len == 0 or bytes.len > clarification.max_form_bytes or !std.unicode.utf8ValidateSlice(bytes) or
        std.mem.count(u8, bytes, forms.answer_start) != 1 or std.mem.count(u8, bytes, forms.answer_end) != 1) return reject(slot, .form_structure);
    const expected = try forms.template(allocator, record, binding);
    defer allocator.free(expected.before_status);
    defer allocator.free(expected.before_answer);
    if (!std.mem.startsWith(u8, bytes, expected.before_status) or !std.mem.endsWith(u8, bytes, expected.after_answer)) return reject(slot, .engine_text_changed);
    const remainder = bytes[expected.before_status.len..];
    const line_end = std.mem.indexOfScalar(u8, remainder, '\n') orelse return reject(slot, .requested_status_invalid);
    const status = std.meta.stringToEnum(clarification.RequestedStatus, remainder[0..line_end]) orelse return reject(slot, .requested_status_invalid);
    if (!std.mem.startsWith(u8, remainder[line_end..], expected.before_answer)) return reject(slot, .engine_text_changed);
    const answer_offset = expected.before_status.len + line_end + expected.before_answer.len;
    const end = bytes.len - expected.after_answer.len;
    if (end < answer_offset) return reject(slot, .form_structure);
    const raw_answer = std.mem.trim(u8, bytes[answer_offset..end], forms.answer_trim);
    const answer = try normalizeAnswer(allocator, raw_answer, status, record.answer_schema, slot);
    return .{ .requested_status = status, .answer = answer };
}
fn text(allocator: std.mem.Allocator, raw: []const u8, maximum: usize, slot: *rejection.Reason) (std.mem.Allocator.Error || Rejected)![]const u8 {
    if (!clarification.validText(raw, maximum)) return reject(slot, .answer_text_invalid);
    return @import("unicode_normalization").nfc(allocator, raw, maximum) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => reject(slot, .answer_text_invalid),
    };
}
fn normalizeAnswer(allocator: std.mem.Allocator, raw: []const u8, status: clarification.RequestedStatus, schema: clarification.AnswerSchema, slot: *rejection.Reason) (std.mem.Allocator.Error || Rejected)!clarification.Answer {
    switch (status) {
        .open => {
            if (raw.len == 0) return .{ .none = {} };
            // Unsubmitted open drafts are replaceable, not accepted answers.
            // Only the explicit defer syntax submits an open-status event.
            if (!forms.isDeferral(raw)) return .{ .none = {} };
            return .{ .defer_reason = try text(allocator, std.mem.trim(u8, forms.deferralReason(raw), " \t"), clarification.max_text_bytes, slot) };
        },
        .cancel => {
            if (!std.mem.startsWith(u8, raw, "cancel: ")) return reject(slot, .cancel_reason_missing);
            return .{ .cancel_reason = try text(allocator, std.mem.trim(u8, raw["cancel: ".len..], " \t"), clarification.max_text_bytes, slot) };
        },
        .closed => {},
    }
    switch (schema) {
        .bounded_business_text => |maximum| return .{ .business_text = try text(allocator, raw, maximum, slot) },
        .select_one => |options| {
            for (options) |option| if (std.mem.eql(u8, option.key, raw)) return .{ .selected_option = option.key };
            return reject(slot, .option_unknown);
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
                } else return reject(slot, .option_unknown);
                if (selected[index]) return reject(slot, .option_duplicate);
                selected[index] = true;
                count += 1;
            }
            if (count < many.minimum or count > many.maximum) return reject(slot, .selection_count);
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
