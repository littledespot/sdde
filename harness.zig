//! Development-only root: never imported or installed by the SDDE executable.
pub const main = @import("test/harness/cli.zig").main;
test {
    _ = @import("test/harness/tests.zig");
}
