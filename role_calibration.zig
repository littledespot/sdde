//! Development diagnostic only. No workflow runner or publication capability.
pub const main = @import("test/harness/roles/cli.zig").main;
pub const live_model_connections = true;
