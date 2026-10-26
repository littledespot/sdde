const std = @import("std");

pub const ResponseGuidanceMode = enum { prompt_only, native_schema };

/// Fixed model-visible framing for the engine's JSON result contract (ADR 0014).
/// Serialize once per request; keep it out of workflow content retained by retries.
pub const response_format_guidance = "Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.";

/// A configured sampling temperature (ADR 0039): a finite number, zero or
/// greater. The provider owns its accepted range; a value it rejects is a typed
/// provider rejection.
pub const Temperature = struct {
    value: f64,

    /// The closed wire kind `strict_json` checks before `jsonParse` runs.
    pub const ClosedJsonWire = f64;

    pub fn init(value: f64) ?Temperature {
        if (!std.math.isFinite(value) or value < 0) return null;
        // Negative zero is zero; one value has one wire form.
        return .{ .value = if (value == 0) 0 else value };
    }

    pub fn wireValue(self: Temperature) f64 {
        return self.value;
    }

    pub fn jsonParse(a: std.mem.Allocator, source: *std.json.Scanner, options: std.json.ParseOptions) std.json.ParseError(std.json.Scanner)!Temperature {
        const token = try source.nextAllocMax(a, .alloc_if_needed, options.max_value_len orelse std.json.default_max_value_len);
        const written = switch (token) {
            .number => |bytes| bytes,
            .allocated_number => |bytes| bytes,
            else => return error.UnexpectedToken,
        };
        return init(std.fmt.parseFloat(f64, written) catch return error.InvalidNumber) orelse error.InvalidNumber;
    }

    pub fn jsonStringify(self: Temperature, writer: *std.json.Stringify) std.json.Stringify.Error!void {
        try writer.write(self.value);
    }
};

/// The project's two configured temperatures (`.sddtoolkit.json`).
pub const Temperatures = struct {
    configured: Temperature,
    runaway_retry: Temperature,
};

/// Which configured temperature one attempt sends. Only the runaway re-send of
/// ADR 0039 sends `runaway_retry`.
pub const Sampling = enum { configured, runaway_resend };

/// SDDE never requests an output-token allowance (ADR 0011): the provider's own
/// model maximum is the only output ceiling, and a stop at it is logged.
/// A model whose registered contract takes no temperature carries none.
pub const InferenceControls = struct {
    temperatures: ?Temperatures = null,

    pub fn forTemperatureSupport(supported: bool, temperatures: Temperatures) InferenceControls {
        return .{ .temperatures = if (supported) temperatures else null };
    }

    /// The temperature one attempt sends, or null when the model takes none.
    pub fn temperature(self: InferenceControls, sampling: Sampling) ?Temperature {
        const configured = self.temperatures orelse return null;
        return switch (sampling) {
            .configured => configured.configured,
            .runaway_resend => configured.runaway_retry,
        };
    }
};

test "a temperature is a finite number, zero or greater" {
    const a = std.testing.allocator;
    for ([_]struct { bytes: []const u8, value: f64 }{ .{ .bytes = "0", .value = 0 }, .{ .bytes = "0.1", .value = 0.1 }, .{ .bytes = "1", .value = 1 }, .{ .bytes = "-0", .value = 0 }, .{ .bytes = "2.5e-1", .value = 0.25 } }) |case| {
        const parsed = try std.json.parseFromSliceLeaky(Temperature, a, case.bytes, .{});
        try std.testing.expectEqual(case.value, parsed.value);
        try std.testing.expect(!std.math.signbit(parsed.value));
    }
    for ([_][]const u8{ "-0.1", "-1", "\"0.1\"", "null", "true", "[]", "{}" }) |bytes| {
        try std.testing.expect(std.meta.isError(std.json.parseFromSliceLeaky(Temperature, a, bytes, .{})));
    }
    const encoded = try std.json.Stringify.valueAlloc(a, Temperatures{ .configured = Temperature.init(0.1).?, .runaway_retry = Temperature.init(1).? }, .{});
    defer a.free(encoded);
    const decoded = try std.json.parseFromSliceLeaky(Temperatures, a, encoded, .{});
    try std.testing.expectEqual(@as(f64, 0.1), decoded.configured.value);
    try std.testing.expectEqual(@as(f64, 1), decoded.runaway_retry.value);
}

test "each attempt sends its configured temperature, or none when the model takes none" {
    const temperatures: Temperatures = .{ .configured = Temperature.init(0.1).?, .runaway_retry = Temperature.init(1).? };
    const supported: InferenceControls = .forTemperatureSupport(true, temperatures);
    try std.testing.expectEqual(@as(f64, 0.1), supported.temperature(.configured).?.value);
    try std.testing.expectEqual(@as(f64, 1), supported.temperature(.runaway_resend).?.value);
    const omitted: InferenceControls = .forTemperatureSupport(false, temperatures);
    try std.testing.expectEqual(@as(?Temperature, null), omitted.temperature(.configured));
    try std.testing.expectEqual(@as(?Temperature, null), omitted.temperature(.runaway_resend));
}
