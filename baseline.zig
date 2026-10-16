//! Development-only baseline acquisition and supplied semantic assessment.
pub const main = @import("test/harness/baseline/cli.zig").main;
pub const live_model_connections = true;

test {
    _ = @import("test/harness/baseline/tests.zig");
}
