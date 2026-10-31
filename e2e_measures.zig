//! Offline retained-run measures (FIX06 T5). This executable has no model connections.
pub const main = @import("test/harness/e2e/measures_cli.zig").main;
pub const live_model_connections = false;
