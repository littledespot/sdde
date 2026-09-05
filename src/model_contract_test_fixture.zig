const limits = @import("domain/model_limits.zig");
const capabilities_module = @import("domain/model_capabilities.zig");
const compilation = @import("domain/workflow_compilation.zig");
const workflow = @import("domain/workflow.zig");

// Compiler-supplied test facts only. Never installed by production composition.
pub const capacity: limits.Capacity = .{
    .canonical = limits.Limits.init(4096, 1024, 1000, 200, 1200).?,
    .wire = .{
        .maximum_request_body_bytes = 8192,
        .maximum_request_path_bytes = 512,
        .maximum_request_header_count = 32,
        .maximum_request_header_bytes = 4096,
        .maximum_response_header_count = 32,
        .maximum_response_header_bytes = 4096,
        .maximum_response_body_bytes = 8192,
    },
};
pub const capabilities: capabilities_module.Capabilities = .{
    .input_token_count = true,
    .inference = true,
    .exact_token_counter = .provider_input_token_count,
    .structured_response = .prompt_only,
    .temperature = true,
    .capacity = capacity,
};
pub const compiled_parameters = [_]compilation.CompiledParameter{
    .{ .id = .{ .bytes = "input-bytes" }, .value = .{ .integer = 4096 } },
    .{ .id = .{ .bytes = "output-bytes" }, .value = .{ .integer = 1024 } },
    .{ .id = .{ .bytes = "input-tokens" }, .value = .{ .integer = 1000 } },
    .{ .id = .{ .bytes = "output-tokens" }, .value = .{ .integer = 200 } },
    .{ .id = .{ .bytes = "response-mode" }, .value = .{ .enumeration = "prompt-only" } },
};
pub const declared_parameters = [_]workflow.ParameterBinding{
    .{ .id = .{ .bytes = "input-bytes" }, .value = .{ .integer = 4096 } },
    .{ .id = .{ .bytes = "output-bytes" }, .value = .{ .integer = 1024 } },
    .{ .id = .{ .bytes = "input-tokens" }, .value = .{ .integer = 1000 } },
    .{ .id = .{ .bytes = "output-tokens" }, .value = .{ .integer = 200 } },
    .{ .id = .{ .bytes = "response-mode" }, .value = .{ .string = "prompt-only" } },
};
