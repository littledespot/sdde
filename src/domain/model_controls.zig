pub const ResponseGuidanceMode = enum { prompt_only, native_schema };

/// Fixed model-visible framing for the engine's JSON result contract (ADR 0014).
/// Serialize once per request; keep it out of workflow content retained by retries.
pub const response_format_guidance = "Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.";

/// Engine policy: supported temperature controls have exactly one value.
pub const Temperature = enum {
    fixed,

    pub fn wireValue(self: Temperature) f64 {
        return switch (self) {
            .fixed => 0.1,
        };
    }
};

/// SDDE never requests an output-token allowance (ADR 0011): the provider's own
/// model maximum is the only output ceiling, and a stop at it is logged.
pub const InferenceControls = struct {
    temperature: ?Temperature = null,

    pub fn forTemperatureSupport(supported: bool) InferenceControls {
        return .{ .temperature = if (supported) .fixed else null };
    }
};
