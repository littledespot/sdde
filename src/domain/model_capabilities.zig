const limits = @import("model_limits.zig");

pub const ExactTokenCounter = enum { unavailable, provider_input_token_count };

// Native schema profiles must be supplied with a provider implementation. A
// nominal "supports JSON" flag cannot authorize an arbitrary result schema.
pub const StructuredResponse = enum { unavailable, prompt_only };

pub const Capabilities = struct {
    input_token_count: bool,
    inference: bool,
    exact_token_counter: ExactTokenCounter,
    structured_response: StructuredResponse,
    temperature: bool,
    capacity: limits.Capacity,

    pub fn isValid(self: Capabilities) bool {
        return self.capacity.isValid() and (self.input_token_count or self.inference) and
            (self.exact_token_counter != .provider_input_token_count or self.input_token_count) and
            (self.structured_response == .unavailable or self.inference) and
            (!self.temperature or self.inference);
    }

    pub fn supports(self: Capabilities, mode: @import("model_controls.zig").ResponseGuidanceMode, selected: @import("model_controls.zig").InferenceControls) bool {
        if (!self.isValid() or !self.input_token_count or !self.inference or
            self.exact_token_counter != .provider_input_token_count) return false;
        if (selected.temperature) |temperature| {
            if (!self.temperature or temperature.value > 1000) return false;
        }
        return switch (mode) {
            .prompt_only => self.structured_response == .prompt_only,
            .native_schema => false,
        };
    }
};
