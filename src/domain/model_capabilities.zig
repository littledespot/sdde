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

    pub fn isValid(self: Capabilities) bool {
        return (self.input_token_count or self.inference) and
            (self.exact_token_counter != .provider_input_token_count or self.input_token_count) and
            (self.structured_response == .unavailable or self.inference) and
            (!self.temperature or self.inference);
    }

    pub fn supports(self: Capabilities, mode: @import("model_controls.zig").ResponseGuidanceMode, selected: @import("model_controls.zig").InferenceControls) bool {
        if (!self.isValid() or !self.inference) return false;
        if (selected.temperature) |temperature| {
            if (!self.temperature or temperature.value > 1000) return false;
        }
        return switch (mode) {
            .prompt_only => self.structured_response != .unavailable,
            .native_schema => self.structured_response == .bedrock_json_schema,
        };
    }
};
