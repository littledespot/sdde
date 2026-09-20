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

    pub fn explanation(self: Diagnostic) []const u8 {
        return switch (self.reason) {
            .unknown_property => "Schema validation failed: this property is not allowed at this location.",
            .missing_required_property => "Schema validation failed: this required property is missing.",
            .type_mismatch => if (self.expected_location == .parent)
                "Schema validation failed: the discriminator must be a string matching an allowed kind."
            else
                "Schema validation failed: this value has the wrong type; use the expected type.",
            .string_length => "Schema validation failed: the string length is outside the allowed bounds.",
            .integer_range => "Schema validation failed: the integer is outside the allowed range.",
            .array_length => "Schema validation failed: the number of array items is outside the allowed bounds.",
            .constant_mismatch => "Schema validation failed: this value must equal the expected constant.",
            .enum_mismatch => "Schema validation failed: this value is not among the allowed values.",
            .unknown_variant => "Schema validation failed: this discriminator does not identify an allowed kind.",
        };
    }

    /// Own only candidate path strings; the selected compiled schema outlives requests.
    pub fn copy(self: Diagnostic, allocator: std.mem.Allocator) std.mem.Allocator.Error!Diagnostic {
        var result = self;
        result.length = 0;
        errdefer result.deinit(allocator);
        for (self.segments[0..self.length], 0..) |segment, index| {
            result.segments[index] = switch (segment) {
                .property => |name| .{ .property = try allocator.dupe(u8, name) },
                .index => segment,
            };
            result.length += 1;
        }
        return result;
    }

    pub fn deinit(self: Diagnostic, allocator: std.mem.Allocator) void {
        for (self.segments[0..self.length]) |segment| if (segment == .property) allocator.free(segment.property);
    }

    pub fn eql(self: Diagnostic, other: Diagnostic) bool {
        if (self.reason != other.reason or self.expected != other.expected or
            self.expected_location != other.expected_location or self.length != other.length) return false;
        for (self.segments[0..self.length], other.segments[0..other.length]) |left, right| {
            if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
            switch (left) {
                .property => |name| if (!std.mem.eql(u8, name, right.property)) return false,
                .index => |index| if (index != right.index) return false,
            }
        }
        return true;
    }

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
