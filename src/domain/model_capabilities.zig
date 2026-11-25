// Native output uses the shared native projection of the compiled result
// schema, whichever provider family encodes it. Its structural constraints never
// replace the complete acceptance validator. Every registered contract supports it.
pub const Capabilities = struct {
    inference: bool,
    temperature: bool,

    pub fn isValid(self: Capabilities) bool {
        return self.inference;
    }

    /// The project's configured temperatures apply only to a model that takes one.
    pub fn inferenceControls(self: Capabilities, temperatures: @import("model_controls.zig").Temperatures) @import("model_controls.zig").InferenceControls {
        return .forTemperatureSupport(self.temperature, temperatures);
    }

    pub fn supports(self: Capabilities, selected: @import("model_controls.zig").InferenceControls) bool {
        if (!self.isValid()) return false;
        return (selected.temperatures != null) == self.temperature;
    }
};
