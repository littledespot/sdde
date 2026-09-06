pub const ExactTokenCounter = enum { unavailable, provider_input_token_count };

// Native schema profiles must be supplied with a provider implementation. A
// nominal "supports JSON" flag cannot authorize an arbitrary result schema.
pub const StructuredResponse = enum {
    unavailable,
    prompt_only,
    bedrock_json_schema,

    pub fn represents(self: StructuredResponse, schema: *const @import("model_result_schema.zig").Schema) bool {
        return switch (self) {
            .unavailable, .prompt_only => false,
            .bedrock_json_schema => @import("bedrock_schema_profile.zig").represents(schema.root()),
        };
    }
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
