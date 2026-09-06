//! Complete form projection, including retained user-closed submission bytes.
const std = @import("std");
const c = @import("clarification_inputs.zig");
const form = @import("clarification_form.zig");
pub const View = struct { id: c.Id, content: union(enum) { replace: []const u8, retain: []const u8 } };

pub fn render(allocator: std.mem.Allocator, state: c.ValidatedState, protected: []const c.FormCapture) c.Error![]const View {
    const current = state.value orelse return error.InvalidClarificationInput;
    const views = try allocator.alloc(View, current.records.len);
    var retained: usize = 0;
    for (current.records, views) |record, *view| {
        const id = c.Id.parse(record.id) orelse return error.InvalidClarificationInput;
        view.id = id;
        if (record.status == .resolved_by_user) {
            const response = c.findResponse(current, record.response_id orelse return error.InvalidClarificationInput) orelse return error.InvalidClarificationInput;
            for (protected) |capture| {
                if (capture.id.index() != id.index()) continue;
                if (!std.mem.eql(u8, capture.bytes, response.submitted_form_bytes)) return error.InvalidClarificationInput;
                retained += 1;
                view.content = .{ .retain = response.submitted_form_bytes };
                break;
            } else return error.InvalidClarificationInput;
            continue;
        }
        for (protected) |capture| if (capture.id.index() == id.index()) return error.InvalidClarificationInput;
        const bytes = switch (record.status) {
            .resolved_by_user => unreachable,
            .resolved_by_authority => try form.renderAuthorityAudit(allocator, record, current),
            .open => try form.render(allocator, record, .{ .state_ordinal = current.state_ordinal, .state_revision = current.revision, .record_revision = record.revision, .status = .open }, .open, ""),
            // Cancelled audit forms are replaceable, but preserve their original
            // response binding. They are not fresh submittable forms.
            .cancelled_by_user => blk: {
                const response = c.findResponse(current, record.response_id orelse return error.InvalidClarificationInput) orelse return error.InvalidClarificationInput;
                break :blk response.submitted_form_bytes;
            },
        };
        if (bytes.len > c.max_form_bytes) return error.InvalidClarificationInput;
        view.content = .{ .replace = bytes };
    }
    if (retained != protected.len) return error.InvalidClarificationInput;
    return views;
}
