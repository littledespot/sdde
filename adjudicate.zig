//! Offline development authority. This executable has no model connections.
pub const main = @import("test/harness/adjudicate_cli.zig").main;
pub const live_model_connections = false;
