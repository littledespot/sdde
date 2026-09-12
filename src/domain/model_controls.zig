pub const ResponseGuidanceMode = enum { prompt_only, native_schema };

/// Fixed model-visible framing for the engine's JSON result contract (ADR 0014).
/// Serialize once per request; keep it out of workflow content retained by retries.
pub const response_format_guidance = "Return exactly one JSON object matching the supplied schema. No Markdown fences or surrounding text.";

pub const TemperaturePermille = struct {
    value: u16,

    pub fn init(value: u16) ?TemperaturePermille {
        return if (value <= 1000) .{ .value = value } else null;
    }
};

pub const InferenceControls = struct {
    temperature: ?TemperaturePermille = null,
};
