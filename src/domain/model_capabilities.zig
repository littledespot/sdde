pub const ExactTokenCounter = enum { unavailable, provider_input_token_count };

// Native output uses a registered projection of the compiled result schema.
// Its structural constraints never replace the complete acceptance validator.
pub const StructuredResponse = enum {
    unavailable,
    prompt_only,
    bedrock_json_schema,
};

pub const Capabilities = struct {
    input_token_count: bool,
    inference: bool,
    exact_token_counter: ExactTokenCounter,
    structured_response: StructuredResponse,
    temperature: bool,
    supports_max_output_tokens: bool = false,

    pub fn isValid(self: Capabilities) bool {
        return (self.input_token_count or self.inference) and
            (self.exact_token_counter != .provider_input_token_count or self.input_token_count) and
            (self.structured_response == .unavailable or self.inference) and
            (!self.temperature or self.inference) and
            (!self.supports_max_output_tokens or self.inference);
    }

    pub fn inferenceControls(self: Capabilities) @import("model_controls.zig").InferenceControls {
        return .forTemperatureSupport(self.temperature);
    }

    pub fn supports(self: Capabilities, mode: @import("model_controls.zig").ResponseGuidanceMode, selected: @import("model_controls.zig").InferenceControls) bool {
        if (!self.isValid() or !self.inference) return false;
        if (!selected.isValid() or selected.temperature != self.inferenceControls().temperature) return false;
        if (selected.max_output_tokens != null and !self.supports_max_output_tokens) return false;
        return switch (mode) {
            .prompt_only => self.structured_response != .unavailable,
            .native_schema => self.structured_response == .bedrock_json_schema,
        };
    }
};
