//! Borrowed field-level schema rejection. The candidate and compiled schema own
//! field names and expected shapes; reports copy only reason and JSON Pointer.
const std = @import("std");
const schema = @import("model_result_schema.zig");
pub const Reason = enum { type_mismatch, missing_required_property, unknown_property, string_length, integer_range, array_length, constant_mismatch, enum_mismatch, unknown_variant, duplicate_member, shared_member, missing_member, equal_items, disagreeing_items, group_member_not_conflicting };
pub const Segment = @import("json_pointer.zig").Segment;
pub const Description = struct { reason: Reason, path: []const u8 };
pub const Diagnostic = struct {
    reason: Reason,
    expected: *const schema.Node,
    expected_location: enum { value, parent } = .value,
    /// ADR 0038 Decision 5: for `shared_member`, the compiled cross-item rule and the
    /// property it governs, borrowed like `expected`, so a correction can name the kinds
    /// it governs and find every naming.
    coverage: ?schema.Coverage = null,
    /// For `missing_member`, the first assigned member no item names. For `group_member_not_conflicting`
    /// (ADR 0046 Decision 7), the first value the located item lists that the sibling array disposes otherwise.
    member: ?i64 = null,
    /// For `equal_items` (ADR 0038 Decision 3), the compiled member rule whose `distinct` properties the
    /// equal items repeat, borrowed like `expected`, so a correction can find every equal set.
    members: ?schema.Members = null,
    /// For `disagreeing_items` (ADR 0036 Decision 7), the compiled agreement rule whose listed
    /// property the disagreeing items share a value of, borrowed like `expected`, so a correction
    /// can find every value its items disagree on.
    agreement: ?schema.Agreement = null,
    /// For `enum_mismatch` on an integer enumeration, the out-of-set integer the candidate
    /// gave, so a correction can name it beside the node's allowed set.
    rejected: ?i64 = null,
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
            .duplicate_member => "Schema validation failed: this item repeats an assigned member; return exactly one item for every assigned member.",
            .missing_member => "Schema validation failed: no item names this assigned member; return exactly one item for every assigned member.",
            .shared_member => "Schema validation failed: this item names values that an item of a kind in exclusive.owning names, or an earlier item of a kind in exclusive.kinds names, as well as values none of those items names. Rewrite this item to name and state only the values none of those items names. shared lists every such naming in this response.",
            .equal_items => "Schema validation failed: items of this array return the same values for every property in equal.compared. equal.sets lists, for each set of such items, the equal.key value of every item in it. Return every item again, each with the values its own equal.key value calls for, so that no two items of a set stay equal.",
            .disagreeing_items => "Schema validation failed: items of this array list a common value in agreement.property but return different values for agreement.agree. agreement.sets lists, for each group of such values, the values and the location of every item that lists them. Return every item again so that items listing a common value return the same value for agreement.agree.",
            .group_member_not_conflicting => "Schema validation failed: this item lists a claim in member that another array of this response disposes as something other than conflicting. Every claim that a conflict group lists must be disposed conflicting. Return the complete response again so that the groups and the dispositions agree.",
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
            self.expected_location != other.expected_location or self.length != other.length or
            !std.meta.eql(self.coverage, other.coverage) or !std.meta.eql(self.members, other.members) or !std.meta.eql(self.agreement, other.agreement) or self.member != other.member or self.rejected != other.rejected) return false;
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

    /// An item-level defect whose expected contract belongs to the enclosing
    /// array, such as a repeated assignment member.
    pub fn item(self: Diagnostic, index: usize) Diagnostic {
        var result = self.within(.{ .index = index });
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
