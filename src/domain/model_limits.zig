// Memory and transport safety only. Token consumption belongs exclusively to
// the workflow execution's actual-usage ledger.
pub const Limits = struct {
    maximum_input_bytes: u32,
    maximum_output_bytes: u32,

    pub fn init(input_bytes: u32, output_bytes: u32) ?Limits {
        const value: Limits = .{
            .maximum_input_bytes = input_bytes,
            .maximum_output_bytes = output_bytes,
        };
        return if (value.isValid()) value else null;
    }

    pub fn isValid(self: Limits) bool {
        return self.maximum_input_bytes > 0 and self.maximum_output_bytes > 0;
    }

    pub fn intersect(left: Limits, right: Limits) ?Limits {
        if (!left.isValid() or !right.isValid()) return null;
        var result: Limits = undefined;
        inline for (@typeInfo(Limits).@"struct".fields) |field| {
            @field(result, field.name) = @min(@field(left, field.name), @field(right, field.name));
        }
        return if (result.isValid()) result else null;
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
