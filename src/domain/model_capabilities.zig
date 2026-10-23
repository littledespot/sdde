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

    pub fn inferenceControls(self: Capabilities) @import("model_controls.zig").InferenceControls {
        return .forTemperatureSupport(self.temperature);
    }

    pub fn supports(self: Capabilities, mode: @import("model_controls.zig").ResponseGuidanceMode, selected: @import("model_controls.zig").InferenceControls) bool {
        if (!self.isValid()) return false;
        if (selected.temperature != self.inferenceControls().temperature) return false;
        return switch (mode) {
            .prompt_only => self.structured_response != .unavailable,
            .native_schema => self.structured_response == .native_json_schema,
        };
    }
};
