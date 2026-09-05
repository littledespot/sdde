pub const ResponseGuidanceMode = enum { prompt_only, native_schema };

pub const TemperaturePermille = struct {
    value: u16,

    pub fn init(value: u16) ?TemperaturePermille {
        return if (value <= 1000) .{ .value = value } else null;
    }
};

pub const InferenceControls = struct {
    temperature: ?TemperaturePermille = null,
};
