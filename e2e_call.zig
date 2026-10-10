pub const main = @import("test/harness/call/cli.zig").main;
pub const live_model_connections = true;

test {
    _ = @import("test/harness/call/tests.zig");
    _ = @import("test/harness/call/capture_test.zig");
    _ = @import("test/harness/call/report_test.zig");
    _ = @import("test/harness/diagnostic_binding_test.zig");
}
