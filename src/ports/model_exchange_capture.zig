//! Provider-side observation only. It grants no model, filesystem or workflow capability.
const prompt = @import("../domain/sanitized_prompt_log.zig");
pub const Context = opaque {};
pub const Outcome = enum { recorded, disabled, blocked };
pub const Body = @import("../domain/model_exchange.zig").Body;
pub const Port = struct {
    context: *Context,
    capture_fn: *const fn (*Context, prompt.PromptDirection, Body, []const []const u8) Outcome,

    /// Borrowed body and credentials are valid only during this synchronous call.
    /// Headers, environment maps and authorization capabilities are never accepted.
    pub fn capture(self: Port, direction: prompt.PromptDirection, body: Body, credentials: []const []const u8) Outcome {
        return self.capture_fn(self.context, direction, body, credentials);
    }
};
