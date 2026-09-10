//! Development-only single-case E2E command. Never installed with SDDE.
pub const main = @import("test/harness/e2e/cli.zig").main;
test {
    _ = @import("test/harness/e2e/tests.zig");
}
