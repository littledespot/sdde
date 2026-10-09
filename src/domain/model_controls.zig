pub const ResponseGuidanceMode = enum { prompt_only, native_schema };

/// Fixed model-visible framing for the engine's JSON result contract (ADR 0014).
/// Serialize once per request; keep it out of workflow content retained by retries.
pub const response_format_guidance = "Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.";

/// Engine policy: supported temperature controls have exactly one value.
pub const Temperature = enum {
    zero,

    pub fn wireValue(self: Temperature) f64 {
        return switch (self) {
            .zero => 0,
        };
    }
};

/// An explicitly selected provider output allowance, not an engine capacity.
pub const OutputTokenAllowance = struct {
    value: u32,

    pub fn init(value: u32) ?OutputTokenAllowance {
        return if (value == 0) null else .{ .value = value };
    }

    pub fn isValid(self: OutputTokenAllowance) bool {
        return init(self.value) != null;
    }
};

pub const InferenceControls = struct {
    temperature: ?Temperature = null,
    max_output_tokens: ?OutputTokenAllowance = null,

    pub fn isValid(self: InferenceControls) bool {
        return if (self.max_output_tokens) |allowance| allowance.isValid() else true;
    }

    pub fn forTemperatureSupport(supported: bool) InferenceControls {
        return .{ .temperature = if (supported) .zero else null };
    }
};
