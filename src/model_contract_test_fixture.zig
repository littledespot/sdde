const capabilities_module = @import("domain/model_capabilities.zig");
const compilation = @import("domain/workflow_compilation.zig");
const workflow = @import("domain/workflow.zig");

// Compiler-supplied test facts only. Never installed by production composition.
pub const capabilities: capabilities_module.Capabilities = .{
    .input_token_count = true,
    .inference = true,
    .exact_token_counter = .provider_input_token_count,
    .structured_response = .prompt_only,
    .temperature = true,
};
pub const compiled_parameters = [_]compilation.CompiledParameter{
    .{ .id = .{ .bytes = "response-mode" }, .value = .{ .enumeration = "prompt-only" } },
};
pub const declared_parameters = [_]workflow.ParameterBinding{
    .{ .id = .{ .bytes = "response-mode" }, .value = .{ .string = "prompt-only" } },
};
