//! Borrowed field-level schema rejection. The candidate and compiled schema own
//! field names and expected shapes; reports copy only reason and JSON Pointer.
const std = @import("std");
const schema = @import("model_result_schema.zig");
pub const Reason = enum { type_mismatch, missing_required_property, unknown_property, string_length, integer_range, array_length, constant_mismatch, enum_mismatch, unknown_variant };
pub const Segment = @import("json_pointer.zig").Segment;
pub const Description = struct { reason: Reason, path: []const u8 };
pub const Diagnostic = struct {
    reason: Reason,
    expected: *const schema.Node,
    expected_location: enum { value, parent } = .value,
    // Compiler depth bounds traversal; this is not a response size/token limit.
    segments: [schema.max_depth + 2]Segment = @splat(.{ .property = "" }),
    length: usize = 0,

    pub fn property(self: Diagnostic, name: []const u8) Diagnostic {
        var result = self.within(.{ .property = name });
        result.expected_location = .parent;
        return result;
    }

    pub fn describeExpected(self: Diagnostic, allocator: std.mem.Allocator) std.mem.Allocator.Error!Description {
        var scope = self;
        if (self.expected_location == .parent) scope.length -= 1;
        return scope.describe(allocator);
    }

    pub fn within(self: Diagnostic, segment: Segment) Diagnostic {
        var result = self;
        std.debug.assert(result.length < result.segments.len);
        std.mem.copyBackwards(Segment, result.segments[1 .. result.length + 1], result.segments[0..result.length]);
        result.segments[0] = segment;
        result.length += 1;
        return result;
    }

    pub fn describe(self: Diagnostic, allocator: std.mem.Allocator) std.mem.Allocator.Error!Description {
        return .{ .reason = self.reason, .path = try @import("json_pointer.zig").render(allocator, self.segments[0..self.length]) };
    }
};
