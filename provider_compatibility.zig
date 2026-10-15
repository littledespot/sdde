//! Development-only, explicitly selected one-exchange compatibility diagnostic.
pub const main = @import("test/harness/compatibility/cli.zig").main;
pub const live_model_connections = true;

test {
    _ = @import("test/harness/compatibility/tests.zig");
    _ = @import("test/harness/e2e/tests.zig");
}
