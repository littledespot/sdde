//! The typed reasons a clarification form is rejected (ADR 0025). The reasons are one closed vocabulary, each naming the
//! rule one form broke; a rejected closed form stops the run before any model call, and no answer is accepted.
const std = @import("std");
const clarification = @import("clarification_inputs.zig");

pub const Reason = enum {
    /// A record of the registry has no form file.
    form_missing,
    /// A form that holds a submission belongs to no record.
    form_without_record,
    /// The form is empty, over the size bound, not UTF-8, or does not hold exactly one answer region.
    form_structure,
    /// Engine-owned text (front matter, headings, the question, the answer markers) differs from what the engine wrote.
    engine_text_changed,
    /// The requested status is not `open`, `closed` or `cancel`, or its line is unterminated.
    requested_status_invalid,
    /// The answer is not valid bounded text: empty, over its bound, a control character or not normalizable.
    answer_text_invalid,
    /// A `cancel` form's answer does not begin with its `cancel: ` reason.
    cancel_reason_missing,
    /// The answer names an option the record does not offer.
    option_unknown,
    /// A select-many answer names one option more than once.
    option_duplicate,
    /// A select-many answer selects fewer or more options than the record allows.
    selection_count,
    /// An authority-resolved record's form differs from the audit text the engine renders.
    audit_changed,
    /// A recorded response's form differs from the bytes saved with it.
    saved_form_changed,
    /// A recorded response's form holds a different answer from the saved one.
    answer_changed,
    /// A recorded response's form requests a status its record contradicts.
    status_contradicts_record,
};

pub const FormRejection = struct { id: clarification.Id, reason: Reason };

/// Every rejected form of one validation, in the order found. A form is added at most once, and a registry holds at most
/// `max_forms` forms, so the list never outgrows its capacity.
pub const FormRejections = struct {
    entries: [clarification.max_forms]FormRejection = undefined,
    len: usize = 0,

    pub fn add(self: *FormRejections, id: clarification.Id, reason: Reason) void {
        std.debug.assert(self.len < self.entries.len);
        self.entries[self.len] = .{ .id = id, .reason = reason };
        self.len += 1;
    }

    pub fn slice(self: *const FormRejections) []const FormRejection {
        return self.entries[0..self.len];
    }
};

test "a rejection list keeps each form's reason in the order found" {
    var list: FormRejections = .{};
    try std.testing.expectEqual(@as(usize, 0), list.slice().len);
    list.add(clarification.Id.parse("S02").?, .form_missing);
    list.add(clarification.Id.parse("S01").?, .answer_changed);
    try std.testing.expectEqual(@as(usize, 2), list.slice().len);
    try std.testing.expectEqual(Reason.form_missing, list.slice()[0].reason);
    try std.testing.expectEqual(clarification.Id.parse("S01").?, list.slice()[1].id);
}
