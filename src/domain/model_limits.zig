const std = @import("std");

// Per-operation capacity facts, never execution-wide consumption policy.
pub const Limits = struct {
    maximum_input_bytes: u32,
    maximum_output_bytes: u32,
    maximum_input_tokens: u64,
    maximum_output_tokens: u64,
    context_window_tokens: u64,

    pub fn init(input_bytes: u32, output_bytes: u32, input_tokens: u64, output_tokens: u64, context_tokens: u64) ?Limits {
        const value: Limits = .{
            .maximum_input_bytes = input_bytes,
            .maximum_output_bytes = output_bytes,
            .maximum_input_tokens = input_tokens,
            .maximum_output_tokens = output_tokens,
            .context_window_tokens = context_tokens,
        };
        return if (value.isValid()) value else null;
    }

    pub fn isValid(self: Limits) bool {
        return self.maximum_input_bytes > 0 and self.maximum_output_bytes > 0 and
            self.maximum_input_tokens > 0 and self.maximum_output_tokens > 0 and
            self.context_window_tokens > 0 and self.maximum_output_tokens <= self.context_window_tokens;
    }

    pub fn intersect(left: Limits, right: Limits) ?Limits {
        if (!left.isValid() or !right.isValid()) return null;
        var result: Limits = undefined;
        inline for (@typeInfo(Limits).@"struct".fields) |field| {
            @field(result, field.name) = @min(@field(left, field.name), @field(right, field.name));
        }
        return if (result.isValid()) result else null;
    }

    pub fn acceptsInputTokens(self: Limits, exact: u64) bool {
        if (!self.isValid() or exact > self.maximum_input_tokens) return false;
        const total = std.math.add(u64, exact, self.maximum_output_tokens) catch return false;
        return total <= self.context_window_tokens;
    }
};

pub const WireBudgets = struct {
    maximum_request_body_bytes: u32,
    maximum_request_path_bytes: u32,
    maximum_request_header_count: u16,
    maximum_request_header_bytes: u32,
    maximum_response_header_count: u16,
    maximum_response_header_bytes: u32,
    maximum_response_body_bytes: u32,

    pub fn isValid(self: WireBudgets) bool {
        inline for (@typeInfo(WireBudgets).@"struct".fields) |field| {
            if (@field(self, field.name) == 0) return false;
        }
        return true;
    }

    pub fn intersect(left: WireBudgets, right: WireBudgets) ?WireBudgets {
        if (!left.isValid() or !right.isValid()) return null;
        var result: WireBudgets = undefined;
        inline for (@typeInfo(WireBudgets).@"struct".fields) |field| {
            @field(result, field.name) = @min(@field(left, field.name), @field(right, field.name));
        }
        return result;
    }
};

pub const Capacity = struct {
    canonical: Limits,
    wire: WireBudgets,

    pub fn isValid(self: Capacity) bool {
        return self.canonical.isValid() and self.wire.isValid();
    }

    pub fn intersect(left: Capacity, right: Capacity) ?Capacity {
        return .{
            .canonical = Limits.intersect(left.canonical, right.canonical) orelse return null,
            .wire = WireBudgets.intersect(left.wire, right.wire) orelse return null,
        };
    }
};
