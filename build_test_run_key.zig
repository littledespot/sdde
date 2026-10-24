//! Development-only root for the test-run key tool; never part of the SDDE executable.
pub const main = @import("build/test_run_key.zig").main;
