const std = @import("std");
const clarification = @import("../domain/clarification_inputs.zig");
const form = @import("../domain/clarification_form.zig");

pub const Form = struct { requested_status: clarification.RequestedStatus, answer: clarification.Answer };
/// Parsing uses a caller-owned arena, including partial allocations on failure.
pub const StateParser = struct {
    parse_state_fn: *const fn (std.mem.Allocator, []const u8) clarification.Error!clarification.State,
    pub fn parse(self: StateParser, allocator: std.mem.Allocator, bytes: []const u8) clarification.Error!clarification.State {
        return self.parse_state_fn(allocator, bytes);
    }
};
pub const FormParser = struct {
    /// Parsed answers may borrow option keys from the validated record.
    parse_form_fn: *const fn (std.mem.Allocator, []const u8, clarification.Record, form.Binding) clarification.Error!Form,
    pub fn parse(self: FormParser, allocator: std.mem.Allocator, bytes: []const u8, record: clarification.Record, binding: form.Binding) clarification.Error!Form {
        return self.parse_form_fn(allocator, bytes, record, binding);
    }
};
