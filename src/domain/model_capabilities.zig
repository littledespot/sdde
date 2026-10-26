// Native output uses the shared native projection of the compiled result
// schema, whichever provider family encodes it. Its structural constraints never
// replace the complete acceptance validator.
pub const StructuredResponse = enum {
    unavailable,
    prompt_only,
    native_json_schema,
};

pub const Capabilities = struct {
    inference: bool,
    structured_response: StructuredResponse,
    temperature: bool,

    pub fn isValid(self: Capabilities) bool {
        return self.inference;
    }

    /// The project's configured temperatures apply only to a model that takes one.
    pub fn inferenceControls(self: Capabilities, temperatures: @import("model_controls.zig").Temperatures) @import("model_controls.zig").InferenceControls {
        return .forTemperatureSupport(self.temperature, temperatures);
    }

    pub fn supports(self: Capabilities, mode: @import("model_controls.zig").ResponseGuidanceMode, selected: @import("model_controls.zig").InferenceControls) bool {
        if (!self.isValid()) return false;
        if ((selected.temperatures != null) != self.temperature) return false;
        return self.supportsResponse(mode);
    }

    pub fn supportsResponse(self: Capabilities, mode: @import("model_controls.zig").ResponseGuidanceMode) bool {
        if (!self.isValid()) return false;
        return switch (mode) {
            .prompt_only => self.structured_response != .unavailable,
            .native_schema => self.structured_response == .native_json_schema,
        };
    }
};
