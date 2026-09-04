const std = @import("std");
const composition = @import("composition/root.zig");

pub const config = @import("domain/config.zig");
pub const RunOutcome = @import("domain/run_outcome.zig").Outcome;

pub fn run(io: std.Io, allocator: std.mem.Allocator, arguments: []const []const u8) RunOutcome {
    return composition.run(io, allocator, arguments);
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
    refAllDeclsRecursive(@This());
    _ = @import("llm_provider_registry_test.zig");
    _ = @import("llm_provider_binding_test.zig");
    _ = @import("model_request_identity_test.zig");
    _ = @import("model_attempt_accounting_test.zig");
    _ = @import("workflow_token_accounting_test.zig");
    _ = @import("llm_provider_interface_test.zig");
    _ = @import("model_provider_bootstrap_test.zig");
    _ = @import("runtime_tests.zig");
}
