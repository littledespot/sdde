const std = @import("std");
const composition = @import("composition/root.zig");

pub const config = @import("domain/config.zig");
pub const RunOutcome = @import("domain/run_outcome.zig").Outcome;

pub fn run(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8, environment: *const std.process.Environ.Map) RunOutcome {
    return composition.run(io, allocator, arguments, environment);
}

fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(@field(T, decl.name)),
                else => {},
            }
        }
        _ = &@field(T, decl.name);
    }
}

test {
    _ = @import("provider_conformance_test.zig");
    _ = @import("required_authority_test.zig");
    _ = @import("specification_contract_test.zig");
    _ = @import("reference_model_input_test.zig");
    _ = @import("specification_generation_test.zig");
    _ = @import("model_result_schema_test.zig");
    _ = @import("model_capabilities_test.zig");
    refAllDeclsRecursive(@This());
    _ = @import("llm_provider_registry_test.zig");
    _ = @import("llm_provider_binding_test.zig");
    _ = @import("model_request_identity_test.zig");
    _ = @import("model_request_preparation_test.zig");
    _ = @import("model_request_workflow_test.zig");
    _ = @import("provider_invocation_validation_test.zig");
    _ = @import("model_envelope_test.zig");
    _ = @import("model_payload_schema_test.zig");
    _ = @import("invoke_model_test.zig");
    _ = @import("count_model_input_tokens_test.zig");
    _ = @import("model_token_count_validation_test.zig");
    _ = @import("model_attempt_accounting_test.zig");
    _ = @import("provider_operation_lifecycle_test.zig");
    _ = @import("provider_authorization_test.zig");
    _ = @import("execution_reference_test.zig");
    _ = @import("workflow_token_accounting_test.zig");
    _ = @import("llm_provider_interface_test.zig");
    _ = @import("model_provider_bootstrap_test.zig");
    _ = @import("runtime_tests.zig");
}
